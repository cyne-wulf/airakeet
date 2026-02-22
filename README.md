# <img src="Final-icon.png" width="64" height="64" valign="middle"> Airakeet 🦜

**The uncompromising transcription tool for base-model Apple Silicon.**

Airakeet is an open-source, local-first dictation app designed specifically for the **8GB MacBook Air**. It brings the power of NVIDIA's Parakeet ASR model to your Mac without melting your RAM or draining your battery.

## Why Airakeet?
I built this because I was tired of "lightweight" dictation apps that still consumed 2-3GB of RAM, choking my base model M2 Air. I wanted the accuracy of modern large models (like Whisper or Parakeet) but with the efficiency of a native tool.

**Airakeet is different:**
- **Zero-Overhead Idle:** Unloads the 800MB model from RAM after 5 minutes of inactivity.
- **Smart Memory Management:** Uses an "extract-and-clear" buffer strategy to prevent memory spikes during long dictations.
- **ANE Optimized:** Runs exclusively on the Apple Neural Engine to keep your CPU free for other tasks.
- **Strictly Essential:** No bloat, no analytics, no "AI Assistant" features—just rock-solid dictation.

## Features
- **Strictly Local:** Powered by NVIDIA Parakeet TDT 0.6B V2 via CoreML.
- **Superwhisper-like UX:** Menubar-only app with global hotkeys.
- **Reactive Waveform:** A sleek, liquid-motion overlay that reacts to your voice in real-time.
- **Custom Appearance:** Choose your own waveform color to match your setup.
- **Configurable Hotkeys:** Support for standard Mac shortcuts, custom `Fn + Key` combos, and a specialized `Shift + Fn` trigger.
- **Audio Cache:** "Play Last Recording" feature in the debug menu to verify what the engine heard (disk-cached to save RAM).
- **Direct Injection:** Transcribes audio and injects text via Clipboard + CMD+V.
- **Fast:** ~45x real-time factor on Apple M2 (0.11s for 5s of audio).

## Design Decisions
### Why no "Escape to Cancel?"
To keep Airakeet's footprint as small as possible on 8GB machines, I opted not to include global keyboard event listeners beyond the primary hotkey. This minimizes background CPU usage and keeps the app's security profile strictly limited to the essential "Dictation" task.

### Memory Management
Airakeet uses an "extract-and-clear" strategy for audio data. Raw samples are moved out of active memory immediately when recording stops, and the ~800MB ASR model is automatically unloaded after 5 minutes of inactivity.

## Installation & Build
### Download
Grab the latest release from the [Releases Page](https://github.com/cyne-wulf/airakeet/releases).

### Build from Source
1. Clone the repository.
2. Build the app bundle: `./package_app.sh`
3. Drag `Airakeet.app` into **System Settings > Privacy & Security > Accessibility**.
4. Launch `Airakeet.app`.

## License
MIT (App) / CC-BY-4.0 (Model)
