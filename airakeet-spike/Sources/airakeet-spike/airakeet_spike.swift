import FluidAudio
import Foundation

@main
struct AirakeetSpike {
    static func main() async {
        do {
            print("Starting Airakeet feasibility spike...")
            
            // 1. Download and load models
            print("Loading models (version: .v2)...")
            let startLoad = Date()
            let models = try await AsrModels.downloadAndLoad(version: .v2)
            let loadDuration = Date().timeIntervalSince(startLoad)
            print("Models loaded in \(String(format: "%.2f", loadDuration))s")
            
            let asrManager = AsrManager(config: .default)
            try await asrManager.initialize(models: models)
            
            // 2. Generate 5s of 16kHz mono audio (sine wave 440Hz)
            print("Generating 5s of test audio (16kHz mono)...")
            let sampleRate = 16000.0
            let durationSeconds = 5.0
            let frequency = 440.0
            let numSamples = Int(sampleRate * durationSeconds)
            var samples = [Float](repeating: 0, count: numSamples)
            for i in 0..<numSamples {
                samples[i] = sin(Float(2.0 * Double.pi * frequency * Double(i) / sampleRate))
            }
            
            // 3. Transcribe and measure
            print("Transcribing...")
            let startInference = Date()
            // The signature is transcribe(_ samples: [Float], source: AudioSource = .microphone)
            let result = try await asrManager.transcribe(samples)
            let inferenceDuration = Date().timeIntervalSince(startInference)
            
            print("\n--- RESULTS ---")
            print("Transcript: \"\(result.text)\"")
            print("Audio Duration: \(durationSeconds)s")
            print("Inference Time: \(String(format: "%.2f", inferenceDuration))s")
            print("Real-time factor: \(String(format: "%.2f", durationSeconds / inferenceDuration))x")
            
            if inferenceDuration < 2.0 {
                print("SUCCESS: Latency is under 2s target.")
            } else {
                print("FAILURE: Latency (\(inferenceDuration)s) exceeds 2s target.")
            }
            
        } catch {
            print("\nERROR during spike: \(error)")
        }
    }
}
