# Contributing

Use an Apple Silicon Mac with macOS 26+ and full Xcode/Swift 6.2+.
Start with [BUILDING.md](docs/BUILDING.md).

Before submitting a change:

```sh
./scripts/verify-source.sh
```

For capture, inference or export changes, also run the relevant local diagnostics
with NR.dlss prepared. Describe the hardware, media characteristics, settings and
actual checks performed in the pull request. Do not claim tests that were not run.

Keep the interface and first-party documentation in English. Preserve Realtime /
Upload Video and automatic NR.dlss loading. Keep realtime queues bounded and file
exports lossless with respect to frame count and timestamps. Do not modify source
videos or replace an existing export until the new file is complete.

`Vendor/MLX-DLSS` is a pinned upstream snapshot. Prefer app-level changes. When a
vendor update is necessary, update provenance and preserve upstream license and
notice files. Do not replace Package.resolved incidentally.

Do not commit model weights, DLLs, prepared apps, local captures, private media,
credentials or signing material. Use the ignored local directories documented
in [PUBLICATION.md](PUBLICATION.md).
