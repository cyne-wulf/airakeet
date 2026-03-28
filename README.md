# <img src="Final-icon.png" width="64" height="64" valign="middle"> Airakeet 🦜

**The uncompromising transcription tool for base-model Apple Silicon.**

Airakeet is an open-source, local-first dictation app designed specifically for the **8GB MacBook Air**. It brings the power of NVIDIA's Parakeet ASR model to your Mac without melting your RAM or draining your battery.

👉 Explore the [Airakeet landing site](https://airakeet.com/) for visuals, feature highlights, and roadmap details.

## Repository Layout
- [`cyne-wulf/airakeet`](https://github.com/cyne-wulf/airakeet) — the canonical repository for the macOS app, packaging scripts, internal docs, updater assets, and the GitHub Pages website.
- [`website/`](./website) — static site source deployed to `https://airakeet.com/`.

To improve the website, edit the HTML/CSS/JS files in [`website/`](./website) and merge the changes into `main`.

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
- **Escape to cancel:** Press Esc while recording to discard safely (audio stays available via Debug > Play Last Recording).
- **Reactive Waveform:** A sleek, liquid-motion overlay that reacts to your voice in real-time.
- **Custom Appearance:** Choose your own waveform color to match your setup.
- **Configurable Hotkeys:** Support for standard Mac shortcuts, custom `Fn + Key` combos, and a specialized `Shift + Fn` trigger.
- **One-click Updates:** Use the new “Check for Updates…” menu item to download and install the latest GitHub release in-place.
- **Audio Cache:** "Play Last Recording" feature in the debug menu to verify what the engine heard (disk-cached to save RAM).
- **Model Management:** Manually reload or delete the ~800MB model cache from the Debug menu for testing or space management.
- **Verbose Initialization:** Real-time log viewer during first-install or model loading to track download and compilation progress.
- **Direct Injection:** Transcribes audio and injects text via Clipboard + CMD+V.
- **Fast:** ~45x real-time factor on Apple M2 (0.11s for 5s of audio).

## System Requirements
- Apple Silicon MacBook Air or MacBook Pro (M1/M2/M3 generations)
- macOS 14 Sonoma or newer
- Microphone and Accessibility permissions (for audio capture + text injection)

## Design Decisions
### Escape to Cancel
When the listening overlay is visible, Airakeet temporarily arms a global Escape-key monitor. Pressing Esc immediately abandons the current session, hides the overlay, and skips clipboard injection. The captured audio is still cached on disk, so you can recover it later via **Debug → Play Last Recording**. Because the monitor only exists during active sessions, the idle CPU and security footprint remain effectively zero—perfect for the 8GB-first design goal.

### Memory Management
Airakeet uses an "extract-and-clear" strategy for audio data. Raw samples are moved out of active memory immediately when recording stops, and the ~800MB ASR model is automatically unloaded after 5 minutes of inactivity.

## Releases & Install
1. Download the latest build from [GitHub Releases](https://github.com/cyne-wulf/airakeet/releases).
2. Move `Airakeet.app` into your Applications folder.
3. Grant Accessibility and Microphone permissions, then start dictating from the menubar.

### Updates
Already running Airakeet? Click the status bar icon and choose **Check for Updates…**. The app will fetch the newest GitHub release, stream the download directly to disk, verify it, and replace your existing bundle. If macOS blocks the automatic replace (e.g., no write access to `/Applications`), Airakeet drops the new build in `~/Downloads` and lets you move it manually.

### Build from Source
1. Clone the repository.
2. Build the app bundle: `./package_app.sh`
3. Drag `Airakeet.app` into **System Settings > Privacy & Security > Accessibility**.
4. Launch `Airakeet.app`.
