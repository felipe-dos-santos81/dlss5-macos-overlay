# Validation

Initial build 0.1.0, tested on 2026-09-13: Apple M4 Max, 128 GB unified memory,
macOS 26.6.2, Xcode / Swift 6.3.3. Executable: ARM64 Mach-O.
Version 0.1.1 changes the product name to DLSS 5 — Apple Silicon and makes the
application interface and first-party documentation English only.

## Version 0.1.1 checks

- Release build and strict signature verification passed after the product rename.
- No Russian strings remain in first-party sources, resources or documentation.
- The English control view was rendered and visually checked for text clipping.
- Renamed bundle resources load successfully; Metal identity, bypass and H.264/AAC
  diagnostics passed. Inference algorithms are unchanged by this update.

## Version 0.2.0 video export checks

- Added Live / Video workspaces and native AVFoundation offline decoding/encoding.
- Real neural export of a synthetic video passed: **12 input / 12 output frames**,
  variable presentation timestamps preserved within 0.1 ms, duration within 25 ms,
  source audio retained as AAC and source file byte-for-byte unchanged.
- A rotated source exported to upright **180×320** pixels with identity orientation
  metadata. Silent output retained all 12 frames and contained no audio track.
- Input path and hardlink aliases are rejected as export destinations.
- Cancellation after a processed frame removed the partial file and preserved an
  existing destination. A subsequent export successfully replaced that destination.
- The English Video workspace was rendered to PNG and visually checked.
- Individual user clips, long exports and unusual codec/container combinations
  still require testing. HDR and odd frame sizes are explicitly unsupported.

## Version 0.2.1 default model checks

- Renamed workspaces to Realtime / Upload Video and removed both model selectors.
- A single NR.dlss package is embedded in the prepared app and loaded automatically
  into the shared engine. The former saved model path is no longer read.
- Copied the app to an independent directory without a Models folder. Both
  workspace previews loaded NR.dlss from that copied app's own resources.
- Both interfaces were rendered and visually checked with NR.dlss marked Ready.
- Video diagnostics passed with no model argument, including real inference on
  all 12 frames, audio, variable timestamps, portrait output and cancellation.
- Strict signature verification passed with the embedded model.

## Initial validation passed

- Release build with MLX Swift 0.31.6, app packaging, Info.plist validation
  and `codesign --verify --strict`.
- Four XCTest checks: portrait/ultrawide geometry, sanitizing invalid settings,
  bounded latest-frame queue and temporal-history reset boundaries. Zero failures.
- Metal resize and zero-delta residual composition: MAE **0.0**.
- Inference disabled: output is pixel-identical to the original.
- H.264 + AAC export: video and audio tracks, **0.400 seconds** from a synthetic
  sequence. No microphone input.
- PNG export visually checked with a synthetic color pattern.
- Real MLX/Metal inference with extracted weights: MAE from the input pattern
  **0.02526**, confirming a measurable effect. This is not an NVIDIA comparison.
- Before/After at 1.0 returns the original image.
- ScreenCaptureKit received real **3600×2338** frames.
- Full capture → inference → composition checked on three real frames at that
  size without saving desktop contents. Initial timings include warmup
  (1294, 314, 493 ms) and are not steady-state FPS measurements.
- SwiftUI controls rendered to PNG and inspected: Start and Overlay On / Off
  remain pinned and visible without scrolling. Controls return to normal window
  level when losing focus. Overlay starts disabled.
- The app launched from the final project folder remained running.

## Performance

Synthetic translating color pattern at 960×540, downscaled to 512×288,
temporal processing enabled, Natural profile, FP16/fused Metal.
36 frames with the first 6 excluded from the average:

| Metric | Value |
| --- | --- |
| Average processing time after warmup | 29.98 ms |
| Processing rate after warmup | 33.36 FPS |
| First frame in this run | 1987 ms |

Includes downscale, optical flow, inference, FP16 output and composition.
Excludes capture and display. Retina displays have different aspect ratios and
network alignment; games share the GPU with inference. These are not promised
game FPS values. Initial cold-cache compilation took approximately 7.2 seconds.
Raw report: `benchmark-512.json`.

## Local model provenance

The DLL was extracted as data from the public NeuralScreen release:
https://github.com/perseval-BLR/DLSS5-NeuralScreen/releases/tag/v1.8.2

- Archive: `neuralscreen-v1.8.2-full.zip`.
- DLL: `native/nvngx_dlssnr.dll`, FileVersion `310,8,0,0`.
- DLL SHA-256: `dcc0dc2414aedec4a8e084647070383be068554042587180c20c784d4772d36f`.
- WEIGHTS_HT SHA-256: `836f445d06ecd2e59bb9f17b84b91c143396fd76ccda1c9dc7fe81d5edd548f4`.
- All **153** source tensors decoded into **649** logical tensors.
  Unsupported or opaque tensors: **0**.
- Logical weights SHA-256:
  `f9047d0c934f19c71e0d125a65ad27f0435a1698209e5c8f205e0097e98f6541`.

The DLL checksum differs from the MLX-DLSS tools' reference. Structural
compatibility was verified by extraction and successful inference. Bit-for-bit
equivalence with the reference NVIDIA DLL was not separately verified.
The DLL was never executed. The source model is kept outside version control in `Models/NR.dlss`.
Since version 0.2.1, prepared local builds also embed it in the application bundle.

## Still requires testing

- Individual games, fullscreen/borderless behavior, long sessions, faces,
  fast camera motion and text interfaces.
- Real system-audio synchronization during long game recordings.
- Extended use across Spaces/displays, HDR and protected video.
- External UI automation was unavailable during initial validation; the app's
  own control renderer was used. A complete manual game UI test is not claimed.

## Screen Recording recovery — 0.2.2

- Confirmed that macOS TCC rejected the old ad-hoc code requirement after rebuilding.
- Local packaging now selects an installed development signing identity when unambiguous; explicit identity selection remains available.
- Refresh now calls the screen-capture permission request API when preflight is false.
- Renewed this app's Screen Recording entry for the certificate-signed bundle.
- A fresh LaunchServices process reported the expected bundle identifier and `Screen Recording preflight: true`.
- Capture-only diagnostics received three 3600 × 2338 screen frames.
- A second diagnostic received and processed three screen frames through NR.dlss. First-frame processing took 416.74 ms; the next two took 71.14 and 33.52 ms. These are a short smoke test including warmup, not a sustained FPS benchmark.
- No captured images or audio were saved by these diagnostics.
- Release compilation and strict signature verification passed.
