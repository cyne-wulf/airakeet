import AVFoundation
import FluidAudio
import Foundation
import OSLog
import Synchronization

public struct TranscriptionMetrics: Sendable {
    public let audioDuration: TimeInterval
    public let transcriptionTime: TimeInterval
    public let totalTime: TimeInterval
    
    public var realTimeFactor: Double {
        return audioDuration / transcriptionTime
    }
}

public struct TranscriptionResult: Sendable {
    public let text: String
    public let metrics: TranscriptionMetrics
}

@MainActor
public protocol ASREngineDelegate: AnyObject, Sendable {
    func asrEngineDidUpdateStatus(_ status: ASREngineStatus)
    /// Load progress in [0, 1], or `nil` while a phase with no measurable
    /// progress is running (e.g. Core ML compilation) so the UI can show an
    /// indeterminate spinner instead of a frozen bar.
    func asrEngineDidUpdateProgress(_ progress: Double?)
    func asrEngineDidUpdateLoadLog(_ log: String)
}

public enum ASREngineStatus: String, Sendable {
    case idle = "Idle"
    case loading = "Loading Models..."
    case ready = "Ready"
    case transcribing = "Transcribing..."
    case error = "Error"
}

/// A thin wrapper around FluidAudio's AsrManager actor that supplies a fresh
/// per-utterance decoder state, matching the pre-0.15 convenience overloads.
public final class AsrManagerWrapper: Sendable {
    public let manager: AsrManager

    public init(manager: AsrManager) {
        self.manager = manager
    }

    public func transcribe(_ samples: [Float]) async throws -> ASRResult {
        var decoderState = TdtDecoderState.make()
        return try await manager.transcribe(samples, decoderState: &decoderState)
    }

    public func transcribe(_ url: URL) async throws -> ASRResult {
        var decoderState = TdtDecoderState.make()
        return try await manager.transcribe(url, decoderState: &decoderState)
    }
}

/// The concrete inference backend currently loaded. At most one exists at a
/// time, which also guarantees both models are never resident together.
enum LoadedBackend {
    case parakeet(AsrManagerWrapper)
    case nemotron(StreamingNemotronAsrManager)
}

public final class ASREngine: Sendable {
    private let logger = Logger(subsystem: "com.airakeet.app", category: "ASREngine")
    private let managerContainer = AsrManagerContainer()
    private let state = EngineState()
    private let loadCoordinator = LoadCoordinator()
    
    public init() {}
    
    public func setDelegate(_ delegate: ASREngineDelegate?) async {
        await state.setDelegate(delegate)
    }
    
    public var status: ASREngineStatus {
        get async { await state.status }
    }
    
    public var selectedModel: TranscriptionModel {
        get async { await state.selectedModel }
    }

    /// Persists the selection and eagerly (re)loads the backend so download
    /// and compile progress surfaces through the delegate immediately.
    public func setModel(_ model: TranscriptionModel) async throws {
        let alreadySelected = await state.selectedModel == model
        if alreadySelected, await managerContainer.isInitialized(for: model) { return }
        await state.setSelectedModel(model)
        model.saveSelected()
        try await loadModel(forceReload: true)
    }

    public func ensureInitialized() async throws {
        if await managerContainer.isInitialized(for: state.selectedModel) { return }
        try await queueModelLoad(forceReload: false)
    }

    public func loadModel(forceReload: Bool = false) async throws {
        if !forceReload, await managerContainer.isInitialized(for: state.selectedModel) { return }
        try await queueModelLoad(forceReload: forceReload)
    }
    
    private func queueModelLoad(forceReload: Bool) async throws {
        let task = await loadCoordinator.beginLoad(forceReload: forceReload) {
            if forceReload {
                await self.managerContainer.unload()
                await self.updateStatus(.idle)
            }
            try await self.performModelInitialization()
        }

        do {
            try await task.value
        } catch {
            await loadCoordinator.finish(task)
            throw error
        }

        await loadCoordinator.finish(task)
    }
    
    private func performModelInitialization() async throws {
        let model = await state.selectedModel
        await updateStatus(.loading)
        await updateProgress(0.0)
        await clearLog()

        await appendLog("Starting Airakeet Engine initialization...")

        do {
            switch model {
            case .parakeetV2:
                try await initializeParakeet()
            case .nemotronStreaming:
                try await initializeNemotron()
            }
            await updateStatus(.ready)
            await updateProgress(1.0)
        } catch is CancellationError {
            // A newer load (e.g. an explicit model switch) superseded this one;
            // let the replacement own the status/progress UI instead of flashing
            // an error.
            throw CancellationError()
        } catch {
            await appendLog("ERROR: \(error.localizedDescription)")
            await updateStatus(.error)
            throw error
        }
    }

    private func initializeParakeet() async throws {
        await appendLog("Targeting NVIDIA Parakeet TDT 0.6B (v2)")
        await appendLog("Checking local cache...")
        await updateProgress(0.1)

        let cacheDir = AsrModels.defaultCacheDirectory(for: .v2)
        await appendLog("Cache directory: \(cacheDir.lastPathComponent)")

        if AsrModels.modelsExist(at: cacheDir, version: .v2) {
            await appendLog("Cached models found. Starting compilation...")
        } else {
            await appendLog("Models missing. Initiating HuggingFace download (~800MB)...")
            await appendLog("This may take a few minutes depending on your internet speed.")
        }

        // FluidAudio reports the download (0→0.5) and a per-sub-model compile
        // tick (0.5→1.0), so the bar advances during compile instead of
        // freezing at a manual 0.3.
        let models = try await AsrModels.downloadAndLoad(version: .v2, progressHandler: { [weak self] progress in
            guard let self else { return }
            Task { await self.handleParakeetLoadProgress(progress) }
        })
        await appendLog("All components loaded and compiled successfully.")
        await updateProgress(0.95)

        let manager = AsrManager(config: .default)
        try await manager.loadModels(models)

        await managerContainer.set(.parakeet(AsrManagerWrapper(manager: manager)), model: .parakeetV2)
        await appendLog("ASR Manager initialized. Ready for dictation.")
    }

    private func initializeNemotron() async throws {
        let chunkSize = Self.nemotronChunkSize
        await appendLog("Targeting NVIDIA Nemotron Speech Streaming EN 0.6B (\(chunkSize.rawValue)ms chunks)")
        await appendLog("Checking local cache...")
        await updateProgress(0.1)

        if isModelDownloaded(.nemotronStreaming) {
            await appendLog("Cached models found. Starting compilation...")
        } else {
            await appendLog("Models missing. Initiating HuggingFace download (~600MB)...")
            await appendLog("This may take a few minutes depending on your internet speed.")
            await updateProgress(0.2)
        }

        // FluidAudio forwards the progress handler only to the download, not the
        // Core ML compile, so go indeterminate up front. The download handler
        // overrides this with real progress while files transfer, then restores
        // the spinner once the (silent) compile begins.
        await updateProgress(nil)

        let manager = StreamingNemotronAsrManager(requestedChunkSize: chunkSize)
        try await manager.loadModels(to: nil, progressHandler: { [weak self] progress in
            guard let self else { return }
            Task { await self.handleNemotronDownloadProgress(progress) }
        })
        await appendLog("All components loaded and compiled successfully.")
        await updateProgress(0.9)

        await managerContainer.set(.nemotron(manager), model: .nemotronStreaming)
        await appendLog("Nemotron streaming engine ready for dictation.")
    }

    private func handleNemotronDownloadProgress(_ progress: DownloadUtils.DownloadProgress) async {
        // FluidAudio only reports the download here; the compile is silent.
        // Show determinate progress while files transfer (mapped onto 0.2–0.85),
        // and hand back to the indeterminate spinner once the download is done.
        if case .downloading(let completed, let total) = progress.phase, total > 0, completed < total {
            await updateProgress(0.2 + progress.fractionCompleted * 0.65)
            await appendLog("Downloading model files (\(completed)/\(total))...")
        } else {
            await updateProgress(nil)
        }
    }

    private func handleParakeetLoadProgress(_ progress: DownloadUtils.DownloadProgress) async {
        // FluidAudio reports the download (0→0.5) then a per-sub-model compile
        // tick (0.5→1.0). Map onto our 0.1–0.95 band; the final steps own the
        // rest of the bar.
        await updateProgress(0.1 + progress.fractionCompleted * 0.85)
        switch progress.phase {
        case .downloading(let completed, let total) where total > 0:
            await appendLog("Downloading model files (\(completed)/\(total))...")
        case .compiling(let modelName) where !modelName.isEmpty:
            await appendLog("Compiling \(modelName)...")
        default:
            break
        }
    }

    /// Hidden override for experimentation:
    /// `defaults write com.cyne-wulf.airakeet nemotronChunkMs -int 560`
    static var nemotronChunkSize: NemotronChunkSize {
        NemotronChunkSize(rawValue: UserDefaults.standard.integer(forKey: "nemotronChunkMs")) ?? .ms1120
    }

    static func nemotronCacheDirectory(for chunkSize: NemotronChunkSize) -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("FluidAudio", isDirectory: true)
            .appendingPathComponent("Models", isDirectory: true)
            .appendingPathComponent(chunkSize.repo.folderName, isDirectory: true)
    }

    public func isModelDownloaded(_ model: TranscriptionModel) -> Bool {
        switch model {
        case .parakeetV2:
            return AsrModels.modelsExist(at: AsrModels.defaultCacheDirectory(for: .v2), version: .v2)
        case .nemotronStreaming:
            let encoderPath = Self.nemotronCacheDirectory(for: Self.nemotronChunkSize)
                .appendingPathComponent("encoder/encoder_int8.mlmodelc")
            return FileManager.default.fileExists(atPath: encoderPath.path)
        }
    }

    public func deleteModelCache(for model: TranscriptionModel) async throws {
        if await managerContainer.loadedModel == model {
            await managerContainer.unload()
            await updateStatus(.idle)
            await updateProgress(0.0)
        }

        let cacheDir: URL
        switch model {
        case .parakeetV2:
            cacheDir = AsrModels.defaultCacheDirectory(for: .v2)
        case .nemotronStreaming:
            cacheDir = Self.nemotronCacheDirectory(for: Self.nemotronChunkSize)
        }

        if FileManager.default.fileExists(atPath: cacheDir.path) {
            try FileManager.default.removeItem(at: cacheDir)
            await appendLog("\(model.displayName) model cache deleted.")
        }
    }

    public func deleteModelCache() async throws {
        try await deleteModelCache(for: await state.selectedModel)
    }
    
    public func transcribe(samples: [Float], audioDuration: TimeInterval) async throws -> TranscriptionResult {
        guard let backend = await managerContainer.getBackend() else {
            throw NSError(domain: "ASREngine", code: 1, userInfo: [NSLocalizedDescriptionKey: "ASREngine not initialized"])
        }

        let startTotal = Date()
        await updateStatus(.transcribing)

        do {
            let startInference = Date()
            let text: String
            switch backend {
            case .parakeet(let wrapper):
                text = try await wrapper.transcribe(samples).text
            case .nemotron(let manager):
                text = try await Self.nemotronBatchTranscribe(manager, samples: samples)
            }
            let endInference = Date()

            let transcriptionTime = endInference.timeIntervalSince(startInference)
            let totalTime = endInference.timeIntervalSince(startTotal)

            let metrics = TranscriptionMetrics(
                audioDuration: audioDuration,
                transcriptionTime: transcriptionTime,
                totalTime: totalTime
            )

            await updateStatus(.ready)
            return TranscriptionResult(text: text, metrics: metrics)
        } catch {
            await updateStatus(.error)
            logger.error("Transcription failed: \(error.localizedDescription)")
            throw error
        }
    }

    public func transcribe(url: URL) async throws -> TranscriptionResult {
        guard let backend = await managerContainer.getBackend() else {
            throw NSError(domain: "ASREngine", code: 1, userInfo: [NSLocalizedDescriptionKey: "ASREngine not initialized"])
        }

        let startTotal = Date()
        await updateStatus(.transcribing)

        do {
            let startInference = Date()
            let text: String
            switch backend {
            case .parakeet(let wrapper):
                text = try await wrapper.transcribe(url).text
            case .nemotron(let manager):
                text = try await Self.nemotronBatchTranscribe(manager, url: url)
            }
            let endInference = Date()

            // For files, we don't have the audio duration as easily without loading it,
            // but result might have it if the SDK provides it.
            // For now we'll estimate or use 0.
            let transcriptionTime = endInference.timeIntervalSince(startInference)
            let totalTime = endInference.timeIntervalSince(startTotal)

            let metrics = TranscriptionMetrics(
                audioDuration: 0,
                transcriptionTime: transcriptionTime,
                totalTime: totalTime
            )

            await updateStatus(.ready)
            return TranscriptionResult(text: text, metrics: metrics)
        } catch {
            await updateStatus(.error)
            logger.error("File transcription failed: \(error.localizedDescription)")
            throw error
        }
    }

    // MARK: - Nemotron batch shim

    /// Runs the streaming manager in a one-shot session over a full clip.
    /// Used for re-transcription, file transcription, and as the fallback
    /// when the live streaming path produced nothing.
    private static func nemotronBatchTranscribe(_ manager: StreamingNemotronAsrManager, samples: [Float]) async throws -> String {
        await manager.reset()
        do {
            let buffer = try pcmBuffer(from: samples, sampleRate: 16000)
            _ = try await manager.process(audioBuffer: buffer)
            let text = try await manager.finish()
            await manager.reset()
            return text
        } catch {
            await manager.reset()
            throw error
        }
    }

    private static func nemotronBatchTranscribe(_ manager: StreamingNemotronAsrManager, url: URL) async throws -> String {
        await manager.reset()
        do {
            let file = try AVAudioFile(forReading: url)
            let format = file.processingFormat
            let chunkFrames: AVAudioFrameCount = 32768
            while file.framePosition < file.length {
                guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunkFrames) else { break }
                try file.read(into: buffer, frameCount: chunkFrames)
                if buffer.frameLength == 0 { break }
                // process() resamples to the model rate internally.
                _ = try await manager.process(audioBuffer: buffer)
            }
            let text = try await manager.finish()
            await manager.reset()
            return text
        } catch {
            await manager.reset()
            throw error
        }
    }

    private static func pcmBuffer(from samples: [Float], sampleRate: Double) throws -> AVAudioPCMBuffer {
        guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(max(samples.count, 1))) else {
            throw NSError(domain: "ASREngine", code: 2, userInfo: [NSLocalizedDescriptionKey: "Could not allocate audio buffer"])
        }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        if let channel = buffer.floatChannelData?[0] {
            samples.withUnsafeBufferPointer { src in
                if let base = src.baseAddress {
                    channel.update(from: base, count: samples.count)
                }
            }
        }
        return buffer
    }

    // MARK: - Streaming session (Nemotron only)

    /// Starts a live streaming session. Returns false when the loaded backend
    /// is batch-only (Parakeet), in which case the caller uses the stop-time
    /// batch path exactly as before.
    public func beginStreamingSession() async throws -> Bool {
        guard let backend = await managerContainer.getBackend() else {
            throw NSError(domain: "ASREngine", code: 1, userInfo: [NSLocalizedDescriptionKey: "ASREngine not initialized"])
        }
        guard case .nemotron(let manager) = backend else { return false }
        await manager.reset()
        return true
    }

    /// Feeds one captured chunk (any sample rate, mono Float32) and returns
    /// the running partial transcript.
    public func streamChunk(samples: [Float], sampleRate: Double) async throws -> String {
        guard case .nemotron(let manager) = await managerContainer.getBackend() else { return "" }
        let buffer = try Self.pcmBuffer(from: samples, sampleRate: sampleRate)
        _ = try await manager.process(audioBuffer: buffer)
        return await manager.getPartialTranscript()
    }

    /// Flushes the session and returns the final transcript.
    public func finishStreamingSession(audioDuration: TimeInterval) async throws -> TranscriptionResult {
        guard case .nemotron(let manager) = await managerContainer.getBackend() else {
            throw NSError(domain: "ASREngine", code: 1, userInfo: [NSLocalizedDescriptionKey: "No streaming session active"])
        }
        let startTotal = Date()
        await updateStatus(.transcribing)
        do {
            let text = try await manager.finish()
            await manager.reset()
            let totalTime = Date().timeIntervalSince(startTotal)
            let metrics = TranscriptionMetrics(
                audioDuration: audioDuration,
                transcriptionTime: totalTime,
                totalTime: totalTime
            )
            await updateStatus(.ready)
            return TranscriptionResult(text: text, metrics: metrics)
        } catch {
            await manager.reset()
            await updateStatus(.error)
            throw error
        }
    }

    /// Discards any in-flight session state (Escape cancel path).
    public func cancelStreamingSession() async {
        if case .nemotron(let manager) = await managerContainer.getBackend() {
            await manager.reset()
        }
    }
    
    private func updateStatus(_ status: ASREngineStatus) async {
        await state.updateStatus(status)
        if let d = await state.delegate {
            await MainActor.run { d.asrEngineDidUpdateStatus(status) }
        }
    }
    
    private func updateProgress(_ progress: Double?) async {
        if let d = await state.delegate {
            await MainActor.run { d.asrEngineDidUpdateProgress(progress) }
        }
    }
    
    private func appendLog(_ message: String) async {
        let timestamp = Date().formatted(date: .omitted, time: .standard)
        let formattedMessage = "[\(timestamp)] \(message)\n"
        await state.appendLog(formattedMessage)
        if let d = await state.delegate {
            let fullLog = await state.loadLog
            await MainActor.run { d.asrEngineDidUpdateLoadLog(fullLog) }
        }
    }
    
    private func clearLog() async {
        await state.clearLog()
        if let d = await state.delegate {
            await MainActor.run { d.asrEngineDidUpdateLoadLog("") }
        }
    }
}

actor EngineState {
    var status: ASREngineStatus = .idle
    weak var delegate: ASREngineDelegate?
    var loadLog: String = ""
    var selectedModel: TranscriptionModel = .loadSelected()

    func updateStatus(_ status: ASREngineStatus) {
        self.status = status
    }

    func setDelegate(_ delegate: ASREngineDelegate?) {
        self.delegate = delegate
    }

    func setSelectedModel(_ model: TranscriptionModel) {
        self.selectedModel = model
    }

    func appendLog(_ message: String) {
        self.loadLog += message
    }

    func clearLog() {
        self.loadLog = ""
    }
}

actor AsrManagerContainer {
    private var backend: LoadedBackend?
    private(set) var loadedModel: TranscriptionModel?

    func getBackend() -> LoadedBackend? {
        return backend
    }

    func isInitialized(for model: TranscriptionModel) -> Bool {
        return backend != nil && loadedModel == model
    }

    func set(_ backend: LoadedBackend, model: TranscriptionModel) {
        self.backend = backend
        self.loadedModel = model
    }

    func unload() async {
        if case .nemotron(let manager) = backend {
            await manager.cleanup()
        }
        backend = nil
        loadedModel = nil
    }
}

extension ASREngine {
    public func unload() async {
        await managerContainer.unload()
        await updateStatus(.idle)
        logger.info("ASREngine models unloaded to save memory.")
    }
}

actor LoadCoordinator {
    private var task: Task<Void, Error>?

    /// Returns the task that will complete the requested load.
    ///
    /// Non-force loads coalesce onto any in-flight load (e.g. the deferred
    /// warmup plus a concurrent `ensureInitialized` share one load). A force
    /// reload — an explicit model switch — never coalesces: it serializes after
    /// the in-flight load so the final resident backend matches the most recent
    /// selection rather than whatever the warmup happened to be loading.
    func beginLoad(
        forceReload: Bool,
        operation: @escaping @Sendable () async throws -> Void
    ) -> Task<Void, Error> {
        if !forceReload, let task {
            return task
        }

        let previous = forceReload ? task : nil
        let newTask = Task {
            if let previous {
                previous.cancel()
                _ = try? await previous.value
            }
            try await operation()
        }
        task = newTask
        return newTask
    }

    /// Clears the stored task only if it is still the one that finished, so a
    /// superseded load's awaiter cannot clear the replacement task.
    func finish(_ finished: Task<Void, Error>) {
        if task == finished {
            task = nil
        }
    }
}
