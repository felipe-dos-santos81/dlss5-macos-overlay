# Building from a clean checkout

## Requirements

- Apple Silicon Mac running macOS 26 or later.
- Full Xcode with Swift 6.2+ and the Metal Toolchain. Command Line Tools alone
  are insufficient for packaging the Metal runtime.
- CMake and Ninja in the shell.
- Python 3.10+, used only to prepare the model.

```sh
uname -m
xcodebuild -version
swift --version
xcrun --find metal
cmake --version
ninja --version
python3 --version
```

The architecture must be `arm64`. Select your full Xcode installation with
`xcode-select` if necessary. If the Metal compiler is missing, install the Metal
Toolchain component through Xcode.

## 1. Prepare the model

The repository omits model weights, DLLs and prepared applications. Provide your
own `nvngx_dlssnr.dll` as input:

```sh
./scripts/prepare-model.sh /path/to/nvngx_dlssnr.dll
```

This creates a local Python environment with NumPy and safetensors, extracts the
packed tensors, unpacks them and writes `Models/NR.dlss`. The DLL is read as data
and never executed. Extraction outputs are not overwritten; keep existing outputs
or move them aside before preparing another copy. Source and model licensing are
separate. Provenance of the locally tested model is in [VALIDATION.md](VALIDATION.md).

## 2. Build and launch

```sh
./scripts/build-app.sh
./Launch.command
```

Packaging requires `Models/NR.dlss/manifest.json` and `weights.safetensors`.
It creates `dist/DLSS_5_APPLE_SILICON.app`, copies the model into
`Contents/Resources/NR.dlss`, includes Metal kernels and dependency licenses,
then applies and verifies a code signature. If exactly one Apple Development or
Mac Developer identity is installed, it is selected automatically. Otherwise, set
`DLSS_CODESIGN_IDENTITY` to an installed signing identity, or the build uses an
ad-hoc signature. Use the same identity across builds to preserve the app identity
used by macOS privacy permissions. Certificates and private keys stay in Keychain.
These local builds are not notarized public releases.

To re-sign an existing app without rebuilding its code or model:

```sh
./scripts/sign-app.sh
```

Quit the application before replacing or re-signing it. Changing from ad-hoc to
certificate signing can require a one-time permission renewal. See
[Screen Recording troubleshooting](TESTING_GAME.md#screen-recording-permission).

The prepared app loads NR.dlss automatically for Realtime and Upload Video.
It can be moved independently of the project folder. Python, the DLL, CMake and
Xcode are not needed at runtime. The first neural frame may compile kernels.

`Launch.command` builds only when the app is missing. After changing source code,
run the build script again before launching.

## Source checks without weights

```sh
./scripts/verify-source.sh
```

This checks the public file set, shell syntax and Info.plist, builds the Swift
executable and runs ScreenCore tests. It needs Xcode but no model, Screen Recording
permission or inference. CI runs the same script on a macOS 26 ARM64 runner.
CI results become available after the repository is pushed.

Dependency versions come from `Package.resolved`; source checks disable automatic
resolution. MLX-DLSS is included directly under `Vendor/`, with no submodules.
Limit compiler parallelism with `DLSS_BUILD_JOBS` if memory is constrained
(source checks default to 2 jobs, app builds to 6).

## Local inference checks

After preparing the model and building:

```sh
./scripts/test.sh
dist/DLSS_5_APPLE_SILICON.app/Contents/MacOS/DLSS_5_APPLE_SILICON --video-test --output /tmp/dlss-video-tests
dist/DLSS_5_APPLE_SILICON.app/Contents/MacOS/DLSS_5_APPLE_SILICON --capture-test
```

The last command requires Screen Recording permission. Use a fresh output
directory when repeating video diagnostics. Diagnostic outputs stay local.
