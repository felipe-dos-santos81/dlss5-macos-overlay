# Architecture

## Frame pipeline

```text
ScreenCaptureKit → current frame + at most one pending latest frame
    → Metal: aspect-preserving downscale
    → VideoToolbox / Vision: optical flow and history validation
    → MLX-DLSS: fused Metal / FP16 / temporal history
    → Metal: original + upscale(NR(reduced frame) − reduced frame)
    → MetalKit: preview / overlay
    → AVFoundation: PNG / MP4 with system audio
```

Display capture excludes this app's windows to prevent overlay feedback.
Window capture is desktop-independent. The overlay follows the source window,
hides when minimized and updates capture size after resizing stabilizes.
Optical flow uses processed frames. Stale pending frames are dropped. Source,
size, profile, major settings changes and long gaps reset temporal history.
Stop waits for submitted GPU work before another start.


The same RenderEngine loads NR.dlss once for Realtime and Upload Video.
File export uses a separate AVFoundation reader/writer path that waits for every
frame; realtime capture retains only the latest pending frame.

Source organization:

- `Sources/ScreenCore`: settings, frame geometry and bounded frame handoff.
- `Sources/NeuralScreenMac`: AppKit/SwiftUI interface, capture, rendering and export.
- `Vendor/MLX-DLSS`: unmodified upstream inference and model extraction code.
- `Tests/ScreenCoreTests`: model-independent unit tests.
- `Resources`: application metadata and original project license.
