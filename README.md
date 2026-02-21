# Parakeet (In Progress)

An open-source, local-first dictation app for macOS built strictly with NVIDIA Parakeet ASR. No Whisper fallback.

## 🚧 Status: Alpha/In-Development
This project is currently a functional prototype being built autonomously. 

### Recent Progress:
- [x] **High-Performance ASR:** NVIDIA Parakeet TDT 0.6B V2 running locally on Apple Silicon via CoreML (0.11s for 5s audio).
- [x] **Stable Audio Pipeline:** Switched to `AVCaptureSession` to prevent real-time thread crashes found in `AVAudioEngine`.
- [x] **Memory Optimization:** Automatic model unloading after 5 minutes of idle time (optimized for 8GB RAM).
- [x] **Superwhisper-like UX:** Menubar app with global hotkeys and direct text injection.

### Known Technical Challenges:
- **macOS Permissions:** The app currently hits a `Trace/BPT trap: 5` when run from the command line because `AVCaptureSession` requires a proper macOS App Bundle (`.app`) with a valid `Info.plist` and `NSMicrophoneUsageDescription`. 
- **Recommendation:** Open `Package.swift` in Xcode to run the app as a bundled process.

## Features
- **Strictly Local:** Powered by NVIDIA Parakeet TDT 0.6B V2 via CoreML.
- **Superwhisper-like UX:** Menubar-only app with global hotkeys.
- **Recording Modes:**
  - **Hold-to-talk:** Press and hold `Option + Command + R` (Default)
  - **Toggle dictation:** Press to start, press to stop.
- **Direct Injection:** Transcribes audio and injects text via Clipboard + CMD+V.
- **Fast:** ~45x real-time factor on Apple M2.

## Installation & Build
1. Clone the repository.
2. Open `Package.swift` in Xcode 16+.
3. Build and run the `Parakeet` target.
4. On first run, it will download the ~800MB model from HuggingFace.

## License
MIT (App) / CC-BY-4.0 (Model)
