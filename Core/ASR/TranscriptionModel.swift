import Foundation

/// The on-device speech models the user can choose between.
public enum TranscriptionModel: String, CaseIterable, Sendable {
    /// NVIDIA Parakeet TDT 0.6B v2 — batch transcription after recording stops.
    case parakeetV2 = "parakeet-v2"
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
        case .parakeetV2: return "Parakeet TDT v2"
        case .nemotronStreaming: return "Nemotron Streaming"
        }
    }

    public var detail: String {
        switch self {
        case .parakeetV2:
            return "Highest accuracy. Transcribes after you finish speaking. ~800 MB"
        case .nemotronStreaming:
            return "Live transcription as you speak. ~600 MB"
        }
    }

    public var approximateDownloadSize: String {
        switch self {
        case .parakeetV2: return "~800MB"
        case .nemotronStreaming: return "~600MB"
        }
    }
}
