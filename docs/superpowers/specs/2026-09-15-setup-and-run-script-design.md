# Design: `scripts/setup-and-run.sh` — one-command end-to-end setup

Date: 2026-09-15
Status: Approved (conversation), pending spec review

## Problem

Building the app from source requires `nvngx_dlssnr.dll`, which the user must
supply by hand (see `README.md` and `docs/BUILDING.md`). The NVIDIA/DLSS GitHub
releases do not ship it; it is only published inside the NeuralScreen release
`v1.8.2` asset `neuralscreen-v1.8.2-full.zip`. Today the user must manually
download ~225MB, extract the DLL, and run three scripts in order.

## Goal

One command that takes a fresh checkout to a running app:

```sh
./scripts/setup-and-run.sh
```

## Non-goals

- No new flags or configuration; behavior is fixed.
- No reimplementation of existing steps; the script delegates to the existing
  scripts (`prepare-model.sh`, `build-app.sh`, `Launch.command`).
- No support for other NeuralScreen versions or other DLL sources.

## Script behavior

All variables (release URL, zip member path `native/nvngx_dlssnr.dll`,
expected SHA-256) are constants at the top of the script, taken from
`docs/VALIDATION.md`.

1. **Fetch and verify the DLL.**
   - If `Models/nvngx_dlssnr.dll` exists and its SHA-256 equals
     `dcc0dc2414aedec4a8e084647070383be068554042587180c20c784d4772d36f`,
     skip this step ("already cached").
   - Otherwise: download the release zip to a `mktemp` temp directory with
     `curl -fL`, extract only `native/nvngx_dlssnr.dll` with `unzip`,
     verify its SHA-256, move it to `Models/nvngx_dlssnr.dll` (`mkdir -p
     Models` first), and delete the temp directory (the 225MB zip is never
     retained).
   - On failure (bad download, wrong hash), print the expected and observed
     hashes or the download error, point to `docs/VALIDATION.md`, and exit
     non-zero. A mismatching cached DLL is re-fetched (never reused). The temp
     directory is removed via `trap` on both success and failure.
2. **Prepare the model.**
   - Skip only when the DLL was a cache hit and
     `Models/NR.dlss/manifest.json` and `Models/NR.dlss/weights.safetensors`
     both exist. If the DLL was (re-)fetched in this run, always rebuild, so a
     model left over from a different DLL is refreshed.
   - Otherwise run `scripts/prepare-model.sh Models/nvngx_dlssnr.dll`.
3. **Build the app.** Always run `scripts/build-app.sh`; it is incremental and
   a no-op rebuild is fast.
4. **Launch.** Run `Launch.command`, which opens `dist/DLSS_5_APPLE_SILICON.app`.

## Safety and environment

- `set -euo pipefail`; `bash`.
- Dependencies: `curl`, `unzip`, `shasum`, all built into macOS. Missing
  binaries are detected with `command -v` and reported before any download.
- The DLL and model live under `Models/`, which `.gitignore` already excludes.
- The DLL is read as data only; no NVIDIA DLL is executed (existing project
  invariant).

## Testing

- `bash -n` for syntax; `shellcheck` when available.
- The fetch path is verified against the real release once (download, extract,
  hash match).
- Full end-to-end verification (model prep, Swift build, launch) requires the
  local machine and is left to the user's run.

## Verification

`./scripts/check-public-tree.py` must stay clean: the script writes only
git-ignored artifacts and leaves no `.dll` in tracked locations.
