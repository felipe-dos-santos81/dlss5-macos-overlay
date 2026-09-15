# setup-and-run.sh Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** One command (`./scripts/setup-and-run.sh`) takes a fresh checkout to a running app: fetch and hash-verify `nvngx_dlssnr.dll` from the NeuralScreen v1.8.2 release, prepare the model, build, and launch.

**Architecture:** A new orchestrator script delegates every step to the existing scripts (`prepare-model.sh`, `build-app.sh`, `Launch.command`); it only adds what is missing: download, extraction, SHA-256 verification, and caching under git-ignored `Models/`.

**Tech Stack:** Bash, macOS built-ins (`curl`, `unzip`, `shasum`, `mktemp`, `awk`).

**Spec:** `docs/superpowers/specs/2026-09-15-setup-and-run-script-design.md`

## Global Constraints

- Expected DLL SHA-256: `dcc0dc2414aedec4a8e084647070383be068554042587180c20c784d4772d36f` (from `docs/VALIDATION.md:91`)
- Release asset URL: `https://github.com/perseval-BLR/NeuralScreen/releases/download/v1.8.2/neuralscreen-v1.8.2-full.zip`
- Zip member: `native/nvngx_dlssnr.dll` (from `docs/VALIDATION.md:88`)
- DLL cached at `Models/nvngx_dlssnr.dll` (git-ignored by `.gitignore` line 4 `/Models/`)
- The 225MB zip is never retained; temp dir removed via `trap` on success and failure
- A DLL whose hash mismatches the constant is re-fetched, never reused
- The DLL is read as data only; no NVIDIA DLL is executed
- No new flags; behavior fixed; no dependencies beyond macOS built-ins

---

### Task 1: Create `scripts/setup-and-run.sh`

**Files:**
- Create: `scripts/setup-and-run.sh` (mode +x)
- Modify: `README.md` (build-from-source section, around lines 38-45)
- Modify: `docs/BUILDING.md` (after the `prepare-model.sh` usage block, around lines 53-57)

**Interfaces:**
- Consumes: `scripts/prepare-model.sh /path/to/nvngx_dlssnr.dll` (existing, exit 64 on bad usage), `scripts/build-app.sh` (existing, requires `Models/NR.dlss/{manifest.json,weights.safetensors}`), `Launch.command` (existing, opens `dist/DLSS_5_APPLE_SILICON.app`)
- Produces: nothing consumed by other tasks; this is the repo's new top-level entry point

- [ ] **Step 1: Write the script**

Create `scripts/setup-and-run.sh` with this exact content:

```bash
#!/bin/bash
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_ROOT"

ZIP_URL="https://github.com/perseval-BLR/NeuralScreen/releases/download/v1.8.2/neuralscreen-v1.8.2-full.zip"
ZIP_MEMBER="native/nvngx_dlssnr.dll"
EXPECTED_SHA256="dcc0dc2414aedec4a8e084647070383be068554042587180c20c784d4772d36f"
DLL="$PROJECT_ROOT/Models/nvngx_dlssnr.dll"

for tool in curl unzip shasum; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "Missing required tool: $tool" >&2
    exit 1
  fi
done

dll_sha() { shasum -a 256 "$1" | awk '{print $1}'; }

fresh_dll=false
if [ -f "$DLL" ] && [ "$(dll_sha "$DLL")" = "$EXPECTED_SHA256" ]; then
  echo "DLL already cached: $DLL"
else
  if [ -f "$DLL" ]; then
    echo "Cached DLL hash differs from the expected value; re-fetching." >&2
  fi
  echo "Downloading NeuralScreen v1.8.2 release (~225MB)..."
  TEMP_DIR="$(mktemp -d)"
  trap 'rm -rf "$TEMP_DIR"' EXIT
  curl -fL --retry 3 -o "$TEMP_DIR/neuralscreen.zip" "$ZIP_URL"
  unzip -q "$TEMP_DIR/neuralscreen.zip" "$ZIP_MEMBER" -d "$TEMP_DIR"
  OBSERVED="$(dll_sha "$TEMP_DIR/$ZIP_MEMBER")"
  if [ "$OBSERVED" != "$EXPECTED_SHA256" ]; then
    echo "SHA-256 mismatch for nvngx_dlssnr.dll:" >&2
    echo "  expected: $EXPECTED_SHA256" >&2
    echo "  observed: $OBSERVED" >&2
    echo "See docs/VALIDATION.md." >&2
    exit 1
  fi
  mkdir -p "$PROJECT_ROOT/Models"
  mv "$TEMP_DIR/$ZIP_MEMBER" "$DLL"
  fresh_dll=true
  echo "DLL fetched and verified: $DLL"
fi

MODEL_DIR="$PROJECT_ROOT/Models/NR.dlss"
if [ "$fresh_dll" = true ] || [ ! -f "$MODEL_DIR/manifest.json" ] || [ ! -f "$MODEL_DIR/weights.safetensors" ]; then
  "$PROJECT_ROOT/scripts/prepare-model.sh" "$DLL"
else
  echo "Model already prepared: $MODEL_DIR"
fi

"$PROJECT_ROOT/scripts/build-app.sh"
"$PROJECT_ROOT/Launch.command"
```

- [ ] **Step 2: Make it executable and syntax-check**

Run: `chmod +x scripts/setup-and-run.sh && bash -n scripts/setup-and-run.sh && echo OK`
Expected: `OK`

- [ ] **Step 3: Lint with shellcheck when available**

Run: `command -v shellcheck >/dev/null && shellcheck scripts/setup-and-run.sh || echo "shellcheck not installed"`
Expected: no shellcheck findings (fix any), or `shellcheck not installed`

- [ ] **Step 4: Verify the fetch against the real release (download ~225MB once)**

This validates the URL and the zip member path against reality.

Run:
```bash
TEMP_DIR="$(mktemp -d)"
curl -fL --retry 3 -o "$TEMP_DIR/ns.zip" "https://github.com/perseval-BLR/NeuralScreen/releases/download/v1.8.2/neuralscreen-v1.8.2-full.zip"
unzip -l "$TEMP_DIR/ns.zip" | grep -F 'nvngx_dlssnr.dll'
unzip -q "$TEMP_DIR/ns.zip" 'native/nvngx_dlssnr.dll' -d "$TEMP_DIR"
shasum -a 256 "$TEMP_DIR/native/nvngx_dlssnr.dll"
rm -rf "$TEMP_DIR"
```
Expected: `unzip -l` shows `native/nvngx_dlssnr.dll`; the shasum output equals
`dcc0dc2414aedec4a8e084647070383be068554042587180c20c784d4772d36f`.
If the member path differs, stop and reconcile the script's `ZIP_MEMBER` (and
`docs/VALIDATION.md`) with the real zip layout before continuing.

- [ ] **Step 5: Verify model-prep skip logic against a fake DLL (no download)**

Run:
```bash
TEMP_DIR="$(mktemp -d)"
printf 'not a dll' > "$TEMP_DIR/nvngx_dlssnr.dll"
MODELS="$PWD/Models"; mkdir -p "$MODELS"
cp "$TEMP_DIR/nvngx_dlssnr.dll" "$MODELS/nvngx_dlssnr.dll"
# Cache-hit path must NOT trigger: hash of the fake file differs, so the script
# must print "Cached DLL hash differs" and re-fetch. Redirect the download so no
# 225MB transfer happens: expect a curl failure, proving the mismatch was detected.
bash scripts/setup-and-run.sh 2>&1 | grep -E "re-fetching|Downloading"
rm -rf "$TEMP_DIR" "$MODELS/nvngx_dlssnr.dll"
```
Expected: output contains `Cached DLL hash differs from the expected value; re-fetching.` followed by `Downloading`, then a curl error; script exits non-zero. This proves the stale-cache branch works without network cost.

- [ ] **Step 6: Update README.md**

In `README.md`, in the "Build from source" section, replace the code block
starting with the comment "Supply your own nvngx_dlssnr.dll as the extraction
input." (lines 38-45) with:

````markdown
```sh
# One command: fetches and verifies the DLL, prepares the model, builds and launches.
./scripts/setup-and-run.sh
```

The script downloads the DLL from the public
[NeuralScreen v1.8.2 release](https://github.com/perseval-BLR/DLSS5-NeuralScreen/releases/tag/v1.8.2),
verifies it against the checksum recorded in docs/VALIDATION.md and caches it in
git-ignored Models/. To use a DLL you already have instead:

```sh
# Supply your own nvngx_dlssnr.dll as the extraction input.
./scripts/prepare-model.sh /path/to/nvngx_dlssnr.dll

# Packages NR.dlss into the local application.
./scripts/build-app.sh
./Launch.command
```
````

(Keep the rest of the section unchanged.)

- [ ] **Step 7: Update docs/BUILDING.md**

In `docs/BUILDING.md`, at the start of section "## 1. Prepare the model"
(after the heading, before the "Provide your own" paragraph), insert:

```markdown
To fetch the DLL from the public NeuralScreen release and run preparation,
build and launch in one step:

```sh
./scripts/setup-and-run.sh
```

The script verifies the downloaded DLL against the checksum in
[VALIDATION.md](VALIDATION.md) and caches it in git-ignored `Models/`. The
manual steps below remain valid.
```

Then leave the existing "Provide your own `nvngx_dlssnr.dll` as input:" text
and code block unchanged.

- [ ] **Step 8: Run the publication guard**

Run: `python3 scripts/check-public-tree.py`
Expected: exits 0, no forbidden files (the DLL lives in git-ignored `Models/`).

- [ ] **Step 9: Commit**

```bash
git add scripts/setup-and-run.sh README.md docs/BUILDING.md
git commit -m "Add setup-and-run.sh: one-command fetch, verify, prepare, build, launch"
```
