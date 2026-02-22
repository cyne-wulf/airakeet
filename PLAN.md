# Airakeet - Development Plan

## Project Vision
Airakeet is a high-performance, local-first dictation app for macOS that aims to match the user experience of Superwhisper while remaining strictly open-source and powered by NVIDIA Parakeet ASR. It is designed specifically for the 8GB MacBook Air.

## 8GB RAM Optimization Strategy (M2 MacBook Air Focus)
On 8GB RAM machines, memory pressure is the primary constraint. 
1.  **Model Lifecycle Management:** Instead of keeping the ~800MB model resident in RAM 24/7, we implement an automatic "Idle Unload" feature (5 minutes of inactivity).
2.  **Resource Re-use:** Uses an "extract-and-clear" buffer strategy to hand raw samples to the transcriber without creating memory copies.
3.  **CoreML ANE Priority:** Offloads the heavy math to the Apple Neural Engine to keep the CPU/GPU unified memory free for other tasks.
4.  **English-Only Target:** Uses Parakeet-TDT 0.6B V2 (English) to minimize the footprint compared to multilingual models.

---

## Accomplished So Far
- [x] **Feasibility Spike:** Verified Parakeet TDT 0.6B V2 on M2. Achieved 0.11s inference for 5s audio (~45x real-time).
- [x] **Project Scaffolding:** Set up Swift Package Manager (SPM) with `FluidAudio` and `KeyboardShortcuts` dependencies.
- [x] **Core Logic:**
    - `ASREngine`: Actor-based thread-safe wrapper for Parakeet.
    - `AudioRecorder`: High-reliability capture with `AVCaptureSession`.
    - `HotkeyManager`: Global hotkey support with debouncing and specialized `Shift + Fn` handling.
    - `TextInjector`: Modern `NSPasteboard` logic with `Cmd+V` synthesis.
- [x] **UI Prototype:** SwiftUI menubar app with a sleek, floating waveform overlay.
- [x] **Memory Management:** Automatic idle unloading and extract-and-clear buffer logic implemented.
- [x] **Customization:** Added Hotkey recorder, specialized Fn-key binder, and custom waveform color picker.
- [x] **Debug Features:** "Play Last Recording" and "Save Recording" buttons implemented with zero-RAM disk caching.

---

## Future Roadmap

### Phase 2: Refinement
- [ ] **Audio VAD (Voice Activity Detection):** Implement lightweight silence trimming to avoid transcribing dead air.
- [ ] **Onboarding UX:** Add a "Setup Wizard" that guides the user through Microphone and Accessibility permissions on first launch.
- [ ] **Start at Login:** Add a helper to launch the app automatically on system boot.

### Phase 3: Advanced Features
- [ ] **Formatting Engine:** Add basic post-processing (capitalization, punctuation refinement) using a lightweight local rule engine.
- [ ] **Vocabulary Boosting:** Integrate FluidAudio's vocabulary boosting for specialized terms.

---

## Technical Rationale
- **Why NVIDIA Parakeet?** Best accuracy-to-latency ratio for short utterances.
- **Why FluidAudio?** Native ANE-optimized CoreML implementation.
- **Why Clipboard Injection?** Universal compatibility across Terminal, Slack, and Electron apps.
