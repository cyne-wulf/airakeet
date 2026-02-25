@preconcurrency import AVFoundation
import Foundation
import OSLog
import FluidAudio

@MainActor
public protocol AudioRecorderDelegate: AnyObject, Sendable {
    func audioRecorderDidUpdateRecordingState(_ isRecording: Bool)
    func audioRecorderDidUpdatePower(_ power: Float)
}

@MainActor
public final class AudioRecorder: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate {
    private let logger = Logger(subsystem: "com.airakeet.app", category: "AudioRecorder")
    
    private var captureSession: AVCaptureSession?
    private var audioOutput: AVCaptureAudioDataOutput?
    
    public private(set) var isRecording = false {
        didSet { 
            let state = isRecording
            Task { @MainActor in
                self.delegate?.audioRecorderDidUpdateRecordingState(state)
            }
        }
    }
    
    public weak var delegate: AudioRecorderDelegate?
    
    // Thread-safe sample accumulator for the capture queue.
    // Only the lock-protected members are accessed off-MainActor (from the capture callback).
    // inputFormat and delegate are set/read on MainActor only.
    private final class CaptureBuffer: @unchecked Sendable {
        private let lock = NSLock()
        private var _samples = [Float]()
        weak var delegate: AudioRecorderDelegate?
        var inputFormat: AVAudioFormat?

        func append(_ newSamples: [Float]) {
            lock.withLock { _samples.append(contentsOf: newSamples) }

            guard !newSamples.isEmpty, let delegate else { return }

            var maxVal: Float = 0
            for sample in newSamples {
                let magnitude = abs(sample)
                if magnitude > maxVal { maxVal = magnitude }
            }
            Task { @MainActor in delegate.audioRecorderDidUpdatePower(maxVal) }
        }

        func drainSamples() -> [Float] {
            lock.withLock {
                let result = _samples
                _samples = []
                return result
            }
        }

        func reset() {
            lock.withLock {
                _samples = []
                _samples.reserveCapacity(48000 * 60)
            }
            inputFormat = nil
        }
    }
    private let captureBuffer = CaptureBuffer()
    private var lastRecordingURL: URL?
    private let cacheDirectoryName = "com.airakeet.app"
    private let lastRecordingFilename = "last_recording.wav"

    public override init() {
        super.init()
    }
    
    public var selectedDeviceID: String?

    public static func availableDevices() -> [AVCaptureDevice] {
        let discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone],
            mediaType: .audio,
            position: .unspecified
        )
        return discoverySession.devices
    }
    
    public func startRecording() throws {
        guard !isRecording else { return }
        
        let session = AVCaptureSession()
        
        let device: AVCaptureDevice
        if let deviceID = selectedDeviceID, let found = AVCaptureDevice(uniqueID: deviceID) {
            device = found
        } else if let defaultDevice = AVCaptureDevice.default(for: .audio) {
            device = defaultDevice
        } else {
            throw NSError(domain: "AudioRecorder", code: 1, userInfo: [NSLocalizedDescriptionKey: "No audio device found"])
        }
        
        let input = try AVCaptureDeviceInput(device: device)
        if session.canAddInput(input) {
            session.addInput(input)
        }
        
        let output = AVCaptureAudioDataOutput()
        
        // Explicitly request Float32 Non-Interleaved PCM to ensure compatibility
        output.audioSettings = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsNonInterleaved: true
        ]
        
        let queue = DispatchQueue(label: "com.airakeet.audio.capture", qos: .userInteractive)
        output.setSampleBufferDelegate(self, queue: queue)
        
        if session.canAddOutput(output) {
            session.addOutput(output)
        }
        
        captureBuffer.reset()
        captureBuffer.delegate = delegate
        self.captureSession = session
        self.audioOutput = output
        
        // startRunning() must be called on a background thread to avoid UI hang
        let sessionToRun = session
        DispatchQueue.global(qos: .userInitiated).async {
            sessionToRun.startRunning()
        }
        
        isRecording = true
        logger.info("Recording started with device: \(device.localizedName)")
    }
    
    nonisolated public func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        // Extract PCM data from sampleBuffer
        // First query the required buffer list size
        var sizeNeeded: Int = 0
        CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: &sizeNeeded,
            bufferListOut: nil,
            bufferListSize: 0,
            blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil,
            flags: 0,
            blockBufferOut: nil
        )

        // Allocate the exact size needed for the audio buffer list
        let ablMemory = UnsafeMutablePointer<UInt8>.allocate(capacity: sizeNeeded)
        defer { ablMemory.deallocate() }
        let ablPointer = UnsafeMutableRawPointer(ablMemory).bindMemory(to: AudioBufferList.self, capacity: 1)

        var blockBuffer: CMBlockBuffer?
        let status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: nil,
            bufferListOut: ablPointer,
            bufferListSize: sizeNeeded,
            blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil,
            flags: kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment,
            blockBufferOut: &blockBuffer
        )

        guard status == noErr else { return }

        let buffers = UnsafeMutableAudioBufferListPointer(ablPointer)
        var mixedSamples: [Float] = []
        var channelCount = 0
        
        for buffer in buffers {
            guard let mData = buffer.mData else { continue }
            let frameCount = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size
            guard frameCount > 0 else { continue }
            if mixedSamples.count < frameCount {
                mixedSamples += Array(repeating: 0, count: frameCount - mixedSamples.count)
            }
            
            let ptr = mData.assumingMemoryBound(to: Float.self)
            for i in 0..<frameCount {
                mixedSamples[i] += ptr[i]
            }
            channelCount += 1
        }
        
        guard !mixedSamples.isEmpty else { return }

        if channelCount > 1 {
            let normalization = 1.0 / Float(channelCount)
            for i in 0..<mixedSamples.count {
                mixedSamples[i] *= normalization
            }
        }
        
        captureBuffer.append(mixedSamples)
        
        // Capture format on first buffer if not set
        if captureBuffer.inputFormat == nil {
            if let desc = CMSampleBufferGetFormatDescription(sampleBuffer),
               let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(desc),
               let format = AVAudioFormat(streamDescription: asbd) {
                captureBuffer.inputFormat = format
            }
        }
    }
    
    public func stopRecording() async throws -> (samples: [Float], duration: TimeInterval) {
        guard isRecording else { return ([], 0) }
        
        isRecording = false
        
        // stopRunning() should be on background thread
        let sessionToStop = captureSession
        DispatchQueue.global(qos: .userInitiated).async {
            sessionToStop?.stopRunning()
        }
        
        let rawSamples = captureBuffer.drainSamples()
        let format = captureBuffer.inputFormat
        
        if rawSamples.isEmpty {
            logger.warning("No samples captured.")
            return ([], 0)
        }
        
        guard let inputFormat = format else {
            logger.error("Input format never captured.")
            return ([], 0)
        }
        
        logger.info("Processing \(rawSamples.count) samples from AVCapture...")
        
        // Determine source format (mixed to mono if needed)
        let sourceFormat: AVAudioFormat
        if inputFormat.channelCount == 1 {
            sourceFormat = inputFormat
        } else {
            guard let monoFormat = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: inputFormat.sampleRate,
                channels: 1,
                interleaved: false
            ) else {
                logger.error("Failed to create mono source format.")
                return ([], 0)
            }
            sourceFormat = monoFormat
        }
        
        // 1. Create a buffer from the raw samples
        guard let inputBuffer = AVAudioPCMBuffer(pcmFormat: sourceFormat, frameCapacity: AVAudioFrameCount(rawSamples.count)) else {
            logger.error("Failed to create input buffer.")
            return ([], 0)
        }
        inputBuffer.frameLength = AVAudioFrameCount(rawSamples.count)
        
        if let dst = inputBuffer.floatChannelData?[0] {
            rawSamples.withUnsafeBufferPointer { src in
                if let base = src.baseAddress {
                    memcpy(dst, base, rawSamples.count * MemoryLayout<Float>.size)
                }
            }
        }
        
        // 2. Convert to 16kHz mono
        let targetFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false)!
        guard let converter = AVAudioConverter(from: sourceFormat, to: targetFormat) else {
            throw NSError(domain: "AudioRecorder", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to create converter"])
        }
        
        let ratio = targetFormat.sampleRate / inputFormat.sampleRate
        let targetCapacity = AVAudioFrameCount(Double(inputBuffer.frameLength) * ratio) + 100
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: targetCapacity) else {
            return ([], 0)
        }
        
        let consumed = SendableFlag()
        let status = converter.convert(to: outputBuffer, error: nil) { inNumPackets, outStatus in
            if consumed.value {
                outStatus.pointee = .noDataNow
                return nil
            }
            outStatus.pointee = .haveData
            consumed.value = true
            return inputBuffer
        }
        
        if status == .error {
             throw NSError(domain: "AudioRecorder", code: 4, userInfo: [NSLocalizedDescriptionKey: "Conversion failed"])
        }
        
        guard let finalPtr = outputBuffer.floatChannelData?[0] else {
            logger.error("Output buffer has no channel data.")
            return ([], 0)
        }
        
        let finalSamples = Array(UnsafeBufferPointer(start: finalPtr, count: Int(outputBuffer.frameLength)))
        let duration = Double(finalSamples.count) / 16000.0
        
        saveLastRecording(outputBuffer)
        
        return (finalSamples, duration)
    }
    
    private func saveLastRecording(_ buffer: AVAudioPCMBuffer) {
        do {
            let targetURL = try ensureLastRecordingURL()
            let tempURL = targetURL.appendingPathExtension("tmp")
            if FileManager.default.fileExists(atPath: tempURL.path) {
                try FileManager.default.removeItem(at: tempURL)
            }
            let file = try AVAudioFile(forWriting: tempURL, settings: buffer.format.settings)
            try file.write(from: buffer)
            if FileManager.default.fileExists(atPath: targetURL.path) {
                _ = try FileManager.default.replaceItemAt(targetURL, withItemAt: tempURL)
            } else {
                try FileManager.default.moveItem(at: tempURL, to: targetURL)
            }
            self.lastRecordingURL = targetURL
        } catch {
            logger.error("Failed to save last recording: \(error.localizedDescription)")
        }
    }
    
    private func ensureLastRecordingURL() throws -> URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let directory = caches.appendingPathComponent(cacheDirectoryName, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent(lastRecordingFilename)
    }
    
    public func getLastRecordingURL() -> URL? {
        if let url = lastRecordingURL {
            return url
        }
        return try? ensureLastRecordingURL()
    }
    
    public func clearLastRecording() {
        if let url = try? ensureLastRecordingURL() {
            try? FileManager.default.removeItem(at: url)
        }
        lastRecordingURL = nil
    }
}

/// Sendable mutable flag for use in AVAudioConverter's @Sendable closure.
private final class SendableFlag: @unchecked Sendable {
    var value = false
}
