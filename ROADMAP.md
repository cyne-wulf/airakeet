# Airakeet - Future Hardware Roadmap 🚀

This roadmap outlines the plan for supporting "High-Tier" hardware (Apple Silicon with 16GB+ RAM) while maintaining the gold-standard optimization for base-model (8GB) devices.

> **NOTE:** Implementation of the High-Tier features is paused until I upgrade to an **M5 32GB MacBook Air**.

---

## 🛠 Target: Dual-Engine Architecture

The goal is to allow Airakeet to adapt to the user's hardware, offering a choice between "Maximum Efficiency" and "Real-time Magic."

### 1. Engine Selector UI
Add a toggle in the **Hotkey & Appearance** menu (or a new "Engine" settings pane):
- **Standard (Low-Spec):** Optimized for 8GB RAM. Uses Parakeet-TDT 0.6B. (Current Default)
- **Extreme (High-Spec):** Optimized for 16GB/32GB RAM. Uses Parakeet-EOU 1.1B.

### 2. The "Extreme" Engine (Parakeet-EOU 1.1B)
- **Streaming Logic:** Switch from batch processing to streaming. Text will be injected word-by-word into the active application as the user speaks.
- **End-of-Utterance (EOU) Detection:** Leverage the 1.1B model's built-in silence/completion detection to finalize sentences with high-precision punctuation.
- **Multi-Model Support:** Potential to add **NVIDIA Canary** for real-time translation (Speak in one language, type in another).

---

## 📋 Implementation Steps (Post-Upgrade)

### Phase 1: Engine Abstraction
- Refactor `ASREngine.swift` to support a `StreamingASREngine` protocol.
- Implement model switching logic that unloads the 0.6B model before loading the 1.1B model to prevent RAM collisions.

### Phase 2: Live Injection
- Update `TextInjector.swift` to handle incremental string updates (appending words to the focused field without replacing the entire clipboard contents every time).

### Phase 3: Hardware Benchmarking
- Validate load times on M5 hardware.
- Monitor thermal impact of continuous ANE usage during long streaming sessions.
- Verify that the 2.0GB RAM footprint of the 1.1B model remains stable under heavy multitasking.

---

## 💡 Technical Rationale
The **0.6B** model remains the best choice for reliability and speed on 8GB machines. The **1.1B EOU** model is purely a UX upgrade—removing the "wait time" entirely and making the interaction feel instantaneous. This transition represents the leap from a "Tool" to a "Superpower."
