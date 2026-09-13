# Changelog

## 0.2.2

- Explicitly request Screen Recording permission from Refresh; report unrelated capture errors separately.

- Prefer stable development signing for local builds to avoid stale Screen Recording grants after rebuilds.
- Document recovery when macOS shows permission enabled but screen capture is denied.

## 0.2.1

- Renamed workspaces to Realtime and Upload Video.
- Embedded NR.dlss into local app builds and load it automatically in both modes.
- Removed manual model selection and dependence on a saved model path.
- Added source publication documentation, public-tree checks and model-free CI.

## 0.2.0

- Offline video processing with progress, cancellation and Original/Result playback.
- Preserve video timestamps and frame count; export H.264 with optional AAC audio.
- Handle portrait orientation and protect source files and existing exports.


## 0.1.0

- Native macOS screen/window capture with MLX and Metal neural processing.
- Click-through overlay toggle, global shortcuts, preview, PNG and video recording.
