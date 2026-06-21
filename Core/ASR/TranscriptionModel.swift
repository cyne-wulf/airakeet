import Foundation

/// The on-device speech models the user can choose between.
public enum TranscriptionModel: String, CaseIterable, Sendable {
    /// NVIDIA Parakeet TDT 0.6B v2 — batch transcription after recording stops.
    case parakeetV2 = "parakeet-v2"
    /// NVIDIA Parakeet TDT-CTC 110M — smaller batch model for lower latency.
    case parakeetFast110M = "parakeet-fast-110m"
    /// NVIDIA Nemotron Speech Streaming EN 0.6B — cache-aware streaming with
    /// live partial transcripts and native punctuation/capitalization.
    case nemotronStreaming = "nemotron-streaming"

    public static let userDefaultsKey = "transcriptionModel"

    public static func loadSelected() -> TranscriptionModel {
        guard let raw = UserDefaults.standard.string(forKey: userDefaultsKey),
              let model = TranscriptionModel(rawValue: raw) else {
            return .parakeetV2
        }
        return model
    }

    public func saveSelected() {
        UserDefaults.standard.set(rawValue, forKey: Self.userDefaultsKey)
    }

    public var displayName: String {
        switch self {
        case .parakeetV2: return "Parakeet TDT 0.6B v2"
        case .parakeetFast110M: return "Parakeet Fast 110M"
        case .nemotronStreaming: return "Nemotron Streaming"
        }
    }

    public var detail: String {
        switch self {
        case .parakeetV2:
            return "Accuracy-first batch transcription after you finish speaking. ~800 MB"
        case .parakeetFast110M:
            return "Speed-first batch transcription with a smaller fused model. ~250 MB"
        case .nemotronStreaming:
            return "Live transcription as you speak. ~600 MB"
        }
    }

    public var approximateDownloadSize: String {
        switch self {
        case .parakeetV2: return "~800MB"
        case .parakeetFast110M: return "~250MB"
        case .nemotronStreaming: return "~600MB"
        }
    }
}
