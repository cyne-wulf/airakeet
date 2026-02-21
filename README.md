# Parakeet

An open-source, local-first dictation app for macOS built strictly with NVIDIA Parakeet ASR. No Whisper fallback.

## Features
- **Strictly Local:** Powered by NVIDIA Parakeet TDT 0.6B V2 via CoreML.
- **Superwhisper-like UX:** Menubar-only app with global hotkeys.
- **Recording Modes:**
  - **Hold-to-talk:** Press and hold `Option + Cmd + R` to record, release to stop.
  - **Toggle dictation:** Press `Option + Cmd + R` to start, press again to stop.
- **Direct Injection:** Transcribes audio and injects text directly into the focused application.
- **Fast:** Sub-second latency on Apple Silicon (M-series).

## Performance (Apple M2)
Measured on a 5-second audio sample:
- **Inference Time:** 0.11s
- **Real-time Factor:** 45.72x
- **End-to-Text Latency:** ~0.2s after audio ends.

## Installation & Build
1. Clone the repository.
2. Open in Xcode 16+ or use Swift Package Manager.
3. Build and run the `Parakeet` target.
4. On first run, the app will download the ~800MB Parakeet model from HuggingFace via the `FluidAudio` SDK.

## Permissions
Parakeet requires:
1. **Microphone:** To capture your voice.
2. **Accessibility:** To detect global hotkeys and inject text into other apps.
*Note: You will be prompted for these on first use or via the Test/Debug window.*

## Usage
1. Click the waveform icon in the menubar.
2. Choose your preferred mode (Hold-to-talk is default).
3. Use `Option + Cmd + R` to dictate.
4. Text will appear at your cursor in the active app.

## License
MIT (App) / CC-BY-4.0 (Model)
