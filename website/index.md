# Airakeet

The uncompromising transcription tool for base-model Apple Silicon.

Airakeet is an open-source, local-first dictation app designed specifically for the 8GB MacBook Air. It brings NVIDIA's Parakeet ASR model to your Mac without melting your RAM or draining your battery.

- Download: https://github.com/cyne-wulf/airakeet/releases
- Source: https://github.com/cyne-wulf/airakeet
- Contribute: https://airakeet.com/contribute.html

## Key Numbers

- 800 MB model footprint, unloaded when idle.
- 45x real-time factor on M2 MacBook Air.
- 5 minute auto-off to return all RAM.

## Why It Matters

Most dictation apps idle at 2-3GB. Airakeet uses aggressive unloads, streaming buffers, and CoreML tuning to stay invisible until you need it.

## Features

### Zero-overhead idle

The 800MB Parakeet model is evicted after five minutes of inactivity, returning memory to the OS automatically.

### ANE-first execution

Inference runs exclusively on the Apple Neural Engine, keeping the CPU free and the laptop fanless during long sessions.

### Waveform overlay

A translucent HUD follows your cursor with a live waveform. It is fully color-customizable, echoing Superwhisper's UX.

### Clipboard injection

Dictation drops straight into the active text field using Clipboard + Cmd+V with no extra permissions and no network.

### Configurable hotkeys

Supports standard shortcuts, Fn combos, and a dedicated Shift+Fn gesture for quick starts on compact keyboards.

### Audio cache and debug

Replay exactly what the engine heard via a safety cache so you can validate inputs without uploading sensitive data.

## Engineering

Airakeet is a full-stack native build covering CoreML conversion, macOS UX polish, memory management, and low-level performance work.

- Model distillation: NVIDIA Parakeet TDT 0.6B converted to CoreML with quantization and ANE-friendly ops.
- Security-first footprint: menubar-only surface, no analytics, scoped macOS permissions.
- Hotkey architecture: custom event tap avoids global listeners while preserving instant response.
- Memory choreography: extract-and-clear buffers plus timed auto-unload keep RAM usage flat during long recordings.

## Under the Hood

Airakeet is built on NVIDIA Parakeet, a speech model family converted to CoreML and tuned for everyday workflows.

### What Parakeet brings

- Accent friendly: trained on noisy, multi-accent corpora so code-switching and filler words are less likely to be dropped.
- ANE-ready tensors: converted into CoreML operators that map cleanly to the Apple Neural Engine.
- Streaming aware: supports chunk-by-chunk inference without waiting for full clips.

### Future engines

The 1.1B Parakeet-EOU build will unlock live dictation with punctuation, multilingual translation, and smarter "keep listening" behavior without adding cloud latency.

## Parakeet vs Local Whisper

| Attribute | Parakeet | Local Whisper |
| --- | --- | --- |
| Latency target | Optimized for low-latency partials so you see text mid-sentence. | Batch-first decoding introduces a pause before the first characters appear. |
| Hardware sweet spot | Runs comfortably on the Apple Neural Engine with 8GB RAM. | Prefers discrete GPU or 16GB+ unified memory to stay smooth. |
| Streaming feel | Designed for incremental injection with ANE offload. | Often buffers a full sentence before emitting, so text arrives in bursts. |

## Roadmap

- Phase 1, engine abstraction: refactor `ASREngine` to load either 0.6B or 1.1B models on demand and prevent RAM collisions.
- Phase 2, live injection: streaming text, word-by-word insertion, and silence detection using Parakeet-EOU.
- Phase 3, hardware validation: benchmark M5 hardware, monitor thermals, and explore NVIDIA Canary for multilingual translation.

## Future Streaming Engine

When the author upgrades to a 32GB MacBook Air, the higher-capacity Parakeet EOU 1.1B build will be validated end to end. That model is expected to enable word-by-word streaming and EOU, or End of Utterance, timing.

- Words appear as you speak: paragraphs grow in the active text field without waiting for the clip to finish.
- EOU means natural pauses: the engine listens for the tiny silence after each thought, then auto-stops recording with punctuation.
- Instant re-entry: if you keep talking, the future engine jumps back into capture without reloading gigabytes of weights.

## Privacy and Licensing

Airakeet keeps voice processing on device. It is MIT licensed and built to be cloned, forked, remixed, or shipped as-is.
