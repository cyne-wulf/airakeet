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
    func asrEngineDidUpdateProgress(_ progress: Double)
    func asrEngineDidUpdateLoadLog(_ log: String)
}

public enum ASREngineStatus: String, Sendable {
    case idle = "Idle"
    case loading = "Loading Models..."
    case ready = "Ready"
    case transcribing = "Transcribing..."
    case error = "Error"
}

/// A thread-safe wrapper for FluidAudio's AsrManager
public final class AsrManagerWrapper: @unchecked Sendable {
    public let manager: AsrManager
    
    public init(manager: AsrManager) {
        self.manager = manager
    }
    
    public func transcribe(_ samples: [Float]) async throws -> ASRResult {
        return try await manager.transcribe(samples)
    }
    
    public func transcribe(_ url: URL) async throws -> ASRResult {
        return try await manager.transcribe(url, source: .system)
    }
}

public final class ASREngine: Sendable {
    private let logger = Logger(subsystem: "com.airakeet.app", category: "ASREngine")
    private let managerContainer = AsrManagerContainer()
    private let state = EngineState()
    
    public init() {}
    
    public func setDelegate(_ delegate: ASREngineDelegate?) async {
        await state.setDelegate(delegate)
    }
    
    public var status: ASREngineStatus {
        get async { await state.status }
    }
    
    public func ensureInitialized() async throws {
        if await managerContainer.isInitialized() { return }
        try await loadModel()
    }
    
    public func loadModel() async throws {
        await updateStatus(.loading)
        await updateProgress(0.0)
        await clearLog()
        
        await appendLog("Starting Airakeet Engine initialization...")
        await appendLog("Targeting NVIDIA Parakeet TDT 0.6B (v2)")
        
        do {
            await appendLog("Checking local cache...")
            await updateProgress(0.1)
            
            let cacheDir = AsrModels.defaultCacheDirectory(for: .v2)
            await appendLog("Cache directory: \(cacheDir.lastPathComponent)")
            
            if AsrModels.modelsExist(at: cacheDir, version: .v2) {
                await appendLog("Cached models found. Starting compilation...")
                await updateProgress(0.3)
            } else {
                await appendLog("Models missing. Initiating HuggingFace download (~800MB)...")
                await appendLog("This may take a few minutes depending on your internet speed.")
                await updateProgress(0.2)
            }
            
            let models = try await AsrModels.downloadAndLoad(version: .v2)
            await appendLog("All components loaded and compiled successfully.")
            await updateProgress(0.9)
            
            let manager = AsrManager(config: .default)
            try await manager.initialize(models: models)
            
            let wrapper = AsrManagerWrapper(manager: manager)
            await managerContainer.initialize(with: wrapper)
            
            await appendLog("ASR Manager initialized. Ready for dictation.")
            await updateStatus(.ready)
            await updateProgress(1.0)
        } catch {
            await appendLog("ERROR: \(error.localizedDescription)")
            await updateStatus(.error)
            throw error
        }
    }
    
    public func deleteModelCache() async throws {
        await managerContainer.unload()
        let cacheDir = AsrModels.defaultCacheDirectory(for: .v2)
        if FileManager.default.fileExists(atPath: cacheDir.path) {
            try FileManager.default.removeItem(at: cacheDir)
            await appendLog("Model cache deleted.")
        }
        await updateStatus(.idle)
        await updateProgress(0.0)
    }
    
    public func transcribe(samples: [Float], audioDuration: TimeInterval) async throws -> TranscriptionResult {
        guard let wrapper = await managerContainer.getWrapper() else {
            throw NSError(domain: "ASREngine", code: 1, userInfo: [NSLocalizedDescriptionKey: "ASREngine not initialized"])
        }
        
        let startTotal = Date()
        await updateStatus(.transcribing)
        
        do {
            let startInference = Date()
            let result = try await wrapper.transcribe(samples)
            let endInference = Date()
            
            let transcriptionTime = endInference.timeIntervalSince(startInference)
            let totalTime = endInference.timeIntervalSince(startTotal)
            
            let metrics = TranscriptionMetrics(
                audioDuration: audioDuration,
                transcriptionTime: transcriptionTime,
                totalTime: totalTime
            )
            
            await updateStatus(.ready)
            return TranscriptionResult(text: result.text, metrics: metrics)
        } catch {
            await updateStatus(.error)
            logger.error("Transcription failed: \(error.localizedDescription)")
            throw error
        }
    }
    
    public func transcribe(url: URL) async throws -> TranscriptionResult {
        guard let wrapper = await managerContainer.getWrapper() else {
            throw NSError(domain: "ASREngine", code: 1, userInfo: [NSLocalizedDescriptionKey: "ASREngine not initialized"])
        }
        
        let startTotal = Date()
        await updateStatus(.transcribing)
        
        do {
            let startInference = Date()
            let result = try await wrapper.transcribe(url)
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
            return TranscriptionResult(text: result.text, metrics: metrics)
        } catch {
            await updateStatus(.error)
            logger.error("File transcription failed: \(error.localizedDescription)")
            throw error
        }
    }
    
    private func updateStatus(_ status: ASREngineStatus) async {
        await state.updateStatus(status)
        if let d = await state.delegate {
            await MainActor.run { d.asrEngineDidUpdateStatus(status) }
        }
    }
    
    private func updateProgress(_ progress: Double) async {
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
    
    func updateStatus(_ status: ASREngineStatus) {
        self.status = status
    }
    
    func setDelegate(_ delegate: ASREngineDelegate?) {
        self.delegate = delegate
    }
    
    func appendLog(_ message: String) {
        self.loadLog += message
    }
    
    func clearLog() {
        self.loadLog = ""
    }
}

actor AsrManagerContainer {
    private var _wrapper: AsrManagerWrapper?
    
    func getWrapper() -> AsrManagerWrapper? {
        return _wrapper
    }
    
    func isInitialized() -> Bool {
        return _wrapper != nil
    }
    
    func initialize(with wrapper: AsrManagerWrapper) {
        self._wrapper = wrapper
    }
    
    func unload() {
        self._wrapper = nil
    }
}

extension ASREngine {
    public func unload() async {
        await managerContainer.unload()
        await updateStatus(.idle)
        logger.info("ASREngine models unloaded to save memory.")
    }
}
