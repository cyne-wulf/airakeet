# Airakeet - Development Plan

## Project Vision
Airakeet is a high-performance, local-first dictation app for macOS that aims to match the user experience of Superwhisper while remaining strictly open-source and powered by NVIDIA Airakeet ASR. It is designed to run efficiently on Apple Silicon without cloud fallbacks.

## 8GB RAM Optimization Strategy (M2 MacBook Air Focus)
On 8GB RAM machines, memory pressure is the primary constraint. 
1.  **Model Lifecycle Management:** Instead of keeping the ~800MB model resident in RAM 24/7, we implement an optional "Idle Unload" feature.
2.  **Resource Re-use:** Use `AVAudioEngine` with fixed-size buffers to avoid allocations during recording.
3.  **CoreML ANE Priority:** Ensure the model is optimized for the Apple Neural Engine to offload work from the CPU/GPU, which share the 8GB unified memory.
4.  **English-Only Target:** Stick to Airakeet-TDT 0.6B V2 (English) to minimize vocabulary and weight size compared to multilingual versions.

---

## Accomplished So Far
- [x] **Feasibility Spike:** Verified Airakeet TDT 0.6B V2 on M2. Achieved 0.11s inference for 5s audio (~45x real-time).
- [x] **Project Scaffolding:** Set up Swift Package Manager (SPM) with `FluidAudio` and `HotKey` dependencies.
- [x] **Core Logic:**
    - `ASREngine`: Actor-based thread-safe wrapper for Airakeet.
    - `AudioRecorder`: 16kHz mono capture with `AVCaptureSession` (stabilized).
    - `HotkeyManager`: Global hotkey support for Hold-to-talk and Toggle modes.
    - `TextInjector`: Clipboard + CMD+V injection for reliable text delivery.
- [x] **UI Prototype:** SwiftUI menubar app with status menu and a comprehensive Debug/Test window.
- [x] **Strict Concurrency:** Resolved Swift 6 strict concurrency issues using Actors and Sendable protocols.

---

## Future Roadmap

### Phase 1: Performance & Polish (Current)
- [ ] **Memory Management:** Implement automatic model unloading after X minutes of inactivity to save 800MB RAM.
- [ ] **Audio VAD (Voice Activity Detection):** Implement lightweight silence trimming to avoid transcribing dead air.
- [ ] **Onboarding UX:** Add a "Setup Wizard" that guides the user through Microphone and Accessibility permissions.

### Phase 2: Refinement
- [ ] **Custom Hotkeys:** Allow users to record their own hotkey combination in the settings.
- [ ] **Visual Feedback:** Add a small overlay (bezel) or menubar animation to show recording progress/power levels.
- [ ] **Start at Login:** Add a helper to launch the app automatically on system boot.

### Phase 3: Advanced Features
- [ ] **Formatting Engine:** Add basic post-processing (capitalization, punctuation refinement) using a lightweight local rule engine.
- [ ] **Vocabulary Boosting:** Integrate FluidAudio's vocabulary boosting for specialized terms (medical, technical).

---

## Technical Rationale
- **Why NVIDIA Airakeet?** It currently offers the best accuracy-to-latency ratio for local ASR, outperforming Whisper on shorter utterances typical of dictation.
- **Why FluidAudio?** It provides a clean, ANE-optimized CoreML implementation specifically for macOS/iOS.
- **Why Clipboard Injection?** Accessibility-based text insertion (`AXUIElementSetAttribute`) is often blocked by apps like Terminals, Slack, or Electron. Clipboard + CMD+V is the most universal "it just works" method.
