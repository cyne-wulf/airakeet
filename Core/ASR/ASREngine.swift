import FluidAudio
import Foundation
import OSLog

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
}

public final class ASREngine: Sendable {
    private let logger = Logger(subsystem: "com.parakeet.app", category: "ASREngine")
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
        
        await updateStatus(.loading)
        do {
            logger.info("Downloading/Loading Parakeet models (v2)...")
            let models = try await AsrModels.downloadAndLoad(version: .v2)
            
            let manager = AsrManager(config: .default)
            try await manager.initialize(models: models)
            
            let wrapper = AsrManagerWrapper(manager: manager)
            await managerContainer.initialize(with: wrapper)
            await updateStatus(.ready)
            logger.info("ASREngine ready.")
        } catch {
            await updateStatus(.error)
            logger.error("Failed to initialize ASREngine: \(error.localizedDescription)")
            throw error
        }
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
    
    private func updateStatus(_ status: ASREngineStatus) async {
        await state.updateStatus(status)
        if let d = await state.delegate {
            await MainActor.run {
                d.asrEngineDidUpdateStatus(status)
            }
        }
    }
}

actor EngineState {
    var status: ASREngineStatus = .idle
    weak var delegate: ASREngineDelegate?
    
    func updateStatus(_ status: ASREngineStatus) {
        self.status = status
    }
    
    func setDelegate(_ delegate: ASREngineDelegate?) {
        self.delegate = delegate
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
