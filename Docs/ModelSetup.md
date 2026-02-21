# Model Setup

Parakeet uses a CoreML-optimized version of NVIDIA's Parakeet TDT 0.6B V2 Automatic Speech Recognition (ASR) model.

## Checkpoint Information
- **Model:** NVIDIA Parakeet TDT 0.6B V2 (English-only)
- **HuggingFace ID:** `FluidInference/parakeet-tdt-0.6b-v2-coreml`
- **Architecture:** FastConformer-TDT
- **Parameters:** ~600M
- **Size:** ~800MB (FP16/CoreML)

## Automated Setup
Parakeet is designed for seamless onboarding. The model is automatically downloaded and cached on the user's device during the first initialization using the `FluidAudio` Swift SDK:

```swift
// Initializing ASR models via FluidAudio
let models = try await AsrModels.downloadAndLoad(version: .v2)
```

## Manual Conversion (if needed)
If you wish to convert the original NVIDIA NeMo checkpoint manually:
1. Obtain the NeMo checkpoint from [NVIDIA NeMo](https://github.com/NVIDIA/NeMo).
2. Use the `nemo2coreml` tools (or `coremltools` directly) to convert the FastConformer-TDT architecture.
3. Optimize for the Apple Neural Engine (ANE) by ensuring static input shapes and fixed-length Mel spectrogram preprocessing.

## Runtime Configuration
- **Sample Rate:** 16,000 Hz (Mono)
- **Input Format:** Float32 PCM
- **Decoding:** Greedy decoding (TDT)
- **Hardware:** Apple Neural Engine (ANE) preferred, with GPU/CPU fallbacks.
- **Latency Target:** < 2s for 5s of audio (Measured at 0.11s on M2).

## Licensing
The Parakeet-TDT-0.6B model is released by NVIDIA under the [Creative Commons Attribution 4.0 International (CC-BY-4.0)](https://creativecommons.org/licenses/by/4.0/) license.
The CoreML conversion and integration are provided via [FluidAudio](https://github.com/FluidInference/FluidAudio).
