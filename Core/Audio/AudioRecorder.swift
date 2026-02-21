@preconcurrency import AVFoundation
import Foundation
import OSLog
import FluidAudio

public protocol AudioRecorderDelegate: AnyObject, Sendable {
    func audioRecorderDidUpdateRecordingState(_ isRecording: Bool)
    func audioRecorderDidUpdatePower(_ power: Float)
}

@MainActor
public final class AudioRecorder: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate {
    private let logger = Logger(subsystem: "com.parakeet.app", category: "AudioRecorder")
    
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
    
    // Thread-safe state for the capture queue
    private final class InternalState: @unchecked Sendable {
        private let lock = NSLock()
        private var _samples = [Float]()
        private var _inputFormat: AVAudioFormat?
        private weak var _delegate: AudioRecorderDelegate?
        
        var samples: [Float] {
            lock.lock()
            defer { lock.unlock() }
            return _samples
        }
        
        var inputFormat: AVAudioFormat? {
            lock.lock()
            defer { lock.unlock() }
            return _inputFormat
        }
        
        func setInputFormat(_ format: AVAudioFormat) {
            lock.lock()
            defer { lock.unlock() }
            if _inputFormat == nil {
                _inputFormat = format
            }
        }
        
        func setDelegate(_ delegate: AudioRecorderDelegate?) {
            lock.lock()
            defer { lock.unlock() }
            _delegate = delegate
        }
        
        func append(_ newSamples: [Float]) {
            lock.lock()
            let count = newSamples.count
            _samples.append(contentsOf: newSamples)
            let d = _delegate
            lock.unlock()
            
            if count > 0, let d = d {
                let rms = sqrt(newSamples[0] * newSamples[0])
                Task { @MainActor in d.audioRecorderDidUpdatePower(rms) }
            }
        }
        
        func reset() {
            lock.lock()
            defer { lock.unlock() }
            _samples = []
            _samples.reserveCapacity(48000 * 60)
            _inputFormat = nil
        }
    }
    private let internalState = InternalState()
    private var lastRecordingURL: URL?

    public var selectedDeviceID: String?

    public override init() {
        super.init()
    }
    
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
        let queue = DispatchQueue(label: "com.parakeet.audio.capture", qos: .userInteractive)
        output.setSampleBufferDelegate(self, queue: queue)
        
        if session.canAddOutput(output) {
            session.addOutput(output)
        }
        
        internalState.reset()
        internalState.setDelegate(delegate)
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
        var audioBufferList = AudioBufferList()
        var blockBuffer: CMBlockBuffer?
        
        CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: nil,
            bufferListOut: &audioBufferList,
            bufferListSize: MemoryLayout<AudioBufferList>.size,
            blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil,
            flags: kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment,
            blockBufferOut: &blockBuffer
        )
        
        let buffers = UnsafeMutableAudioBufferListPointer(&audioBufferList)
        for buffer in buffers {
            guard let mData = buffer.mData else { continue }
            let frameCount = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size
            let ptr = mData.assumingMemoryBound(to: Float.self)
            
            let samples = Array(UnsafeBufferPointer(start: ptr, count: frameCount))
            internalState.append(samples)
        }
        
        // Capture format on first buffer if not set
        if internalState.inputFormat == nil {
            if let desc = CMSampleBufferGetFormatDescription(sampleBuffer) {
                if let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(desc) {
                    if let format = AVAudioFormat(streamDescription: asbd) {
                        internalState.setInputFormat(format)
                    }
                }
            }
        }
    }
    
    public func stopRecording() async throws -> (samples: [Float], duration: TimeInterval) {
        guard isRecording else { return ([], 0) }
        
        // stopRunning() should be on background thread
        let sessionToStop = captureSession
        DispatchQueue.global(qos: .userInitiated).async {
            sessionToStop?.stopRunning()
        }
        
        isRecording = false
        
        let rawSamples = internalState.samples
        let format = internalState.inputFormat
        
        if rawSamples.isEmpty || format == nil { return ([], 0) }
        
        logger.info("Processing \(rawSamples.count) samples from AVCapture...")
        
        let inputFormat = format!
        guard let inputBuffer = AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: AVAudioFrameCount(rawSamples.count)) else {
            return ([], 0)
        }
        inputBuffer.frameLength = AVAudioFrameCount(rawSamples.count)
        
        for channel in 0..<Int(inputFormat.channelCount) {
            let dst = inputBuffer.floatChannelData![channel]
            rawSamples.withUnsafeBufferPointer { src in
                if let base = src.baseAddress {
                    memcpy(dst, base, rawSamples.count * MemoryLayout<Float>.size)
                }
            }
        }
        
        let targetFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false)!
        guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            throw NSError(domain: "AudioRecorder", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to create converter"])
        }
        
        let ratio = targetFormat.sampleRate / inputFormat.sampleRate
        let targetCapacity = AVAudioFrameCount(Double(inputBuffer.frameLength) * ratio) + 100
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: targetCapacity) else {
            throw NSError(domain: "AudioRecorder", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to create output buffer"])
        }
        
        let convState = ConversionState()
        let status = converter.convert(to: outputBuffer, error: nil) { inNumPackets, outStatus in
            if convState.inputDone {
                outStatus.pointee = .noDataNow
                return nil
            }
            outStatus.pointee = .haveData
            convState.inputDone = true
            return inputBuffer
        }
        
        if status == .error {
             throw NSError(domain: "AudioRecorder", code: 4, userInfo: [NSLocalizedDescriptionKey: "Conversion failed"])
        }
        
        let finalSamples = Array(UnsafeBufferPointer(start: outputBuffer.floatChannelData![0], count: Int(outputBuffer.frameLength)))
        let duration = Double(finalSamples.count) / 16000.0
        
        saveLastRecording(outputBuffer)
        
        return (finalSamples, duration)
    }
    
    private func saveLastRecording(_ buffer: AVAudioPCMBuffer) {
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("last_recording.wav")
        do {
            if FileManager.default.fileExists(atPath: fileURL.path) {
                try FileManager.default.removeItem(at: fileURL)
            }
            let file = try AVAudioFile(forWriting: fileURL, settings: buffer.format.settings)
            try file.write(from: buffer)
            self.lastRecordingURL = fileURL
        } catch {
            logger.error("Failed to save last recording: \(error.localizedDescription)")
        }
    }
    
    public func getLastRecordingURL() -> URL? {
        return lastRecordingURL
    }
}

private final class ConversionState: @unchecked Sendable {
    var inputDone = false
}
