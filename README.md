# DLSS 5 — Apple Silicon

Experimental neural image enhancement for Apple Silicon Macs, inspired by
[NeuralScreen](https://github.com/perseval-BLR/DLSS5-NeuralScreen).
A native Swift app with **Realtime** screen processing and **Upload Video** export,
powered by MLX and Metal. This is an independent project, not an official NVIDIA
or Apple product. 

![DLSS 5 neural rendering of a YouTube video at approximately 6 processing FPS](docs/assets/promo.jpg)

Realtime NR.dlss processing of a YouTube video playing in Chrome: **~6 FPS**, using the **Cinematic** profile.

## Two workspaces

| Realtime | Upload Video |
| --- | --- |
| Capture a display or game window | Open a local SDR video |
| Click-through overlay with an on/off switch | Process every frame and export MP4/H.264 |
| Before/after comparison and PNG snapshots | Preserve original size and frame timing |
| Record MP4 with optional system audio | Optional source audio exported as stereo AAC |
| Global overlay and stop shortcuts | Progress, cancellation and Original/Result playback |

Both workspaces use **NR.dlss** automatically. The finished local app includes
the model; there is no model selector. The interface is English only.

![Upload Video workspace](docs/assets/upload-video.png)

## Build from source

**This repository contains source code, not the prepared application or model
weights.** Prepare the model once before packaging the app.

Requirements: Apple Silicon, macOS 26+, full Xcode with Swift 6.2+ and the Metal
Toolchain, CMake, Ninja, and Python 3.10+ for model preparation.

From the project directory:

```sh
# Supply your own nvngx_dlssnr.dll as the extraction input.
./scripts/prepare-model.sh /path/to/nvngx_dlssnr.dll

# Packages NR.dlss into the local application.
./scripts/build-app.sh
./Launch.command
```

The result is `dist/DLSS_5_APPLE_SILICON.app`. It includes `NR.dlss` and can run
independently of the project folder without Python or Xcode. Local builds use an installed development certificate when available,
with an ad-hoc fallback; they are not notarized public releases.

[Build instructions](docs/BUILDING.md) · [Game setup](docs/TESTING_GAME.md) ·
[Video processing](docs/PROCESS_VIDEO.md)

## Quick start

For a game, select **Realtime**, wait for **NR.dlss · Ready**, refresh the sources
and choose the game window. Allow Screen Recording when macOS requests it.
Start with **Natural**, **512 px** and **30 FPS**, click **Start**, then enable
**Overlay On / Off**. Windowed or borderless mode is preferred for initial testing.

- **⌥⌘1** — show or hide the overlay.
- **⌥⌘0** — stop processing or cancel video export.
- **DLSS → Show Controls** — return to the settings.

For a saved clip, select **Upload Video → Choose Video…**, adjust the effect,
then click **Export Video…**. The original file stays unchanged. Processing uses
local files; the Upload Video tab does not send clips to a server.

**Processing Size** is the neural network's working resolution. The displayed
or exported image keeps the source resolution. **Before / After** shows the
original on the left; set it to 0.00 for the full processed image.

## Checks

Build and test the source without model weights or screen permissions:

```sh
./scripts/verify-source.sh
```

With the local model prepared and the app built:

```sh
./scripts/test.sh
dist/DLSS_5_APPLE_SILICON.app/Contents/MacOS/DLSS_5_APPLE_SILICON --video-test --output /tmp/dlss-video-tests
```

The GitHub workflow builds the Swift executable and runs model-independent unit
tests. It does not download weights, package a distributable app or publish artifacts.
Real inference and capture diagnostics require the local model and hardware.

[Validation and measured performance](docs/VALIDATION.md) ·
[Architecture](docs/ARCHITECTURE.md) · [Contributing](CONTRIBUTING.md)

## Current limits

- Enhancement adds GPU work and latency; processing FPS is different from game FPS.
- SDR only. Video export requires even frame dimensions and a macOS-supported
  decoder. HDR, protected surfaces and unusual fullscreen behavior need further work.
- Video audio is mixed into stereo AAC. Captions, chapters and extra video tracks
  are not exported. Spout/Syphon and full Windows feature parity are not implemented.
- The reconstructed neural model is not guaranteed to match NVIDIA runtime
  output or its automatic masks. Individual games and long sessions need testing.
- First-frame processing includes kernel compilation and warmup.

## Credits and license

New application code is [MIT licensed](LICENSE). The original NeuralScreen
license is retained in [Resources](Resources/NeuralScreen-LICENSE.txt).
[MLX-DLSS](https://github.com/iamwavecut/MLX-DLSS) is vendored unmodified under
Apache-2.0; MLX Swift and other dependency notices are preserved separately.
See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

Model weights and NVIDIA runtime files are not included in the source repository
and are not covered by this project's MIT license. Prepared local apps embed the
model, so the app bundle is also excluded from Git. No NVIDIA DLL executes on macOS.

[Changelog](CHANGELOG.md) 
