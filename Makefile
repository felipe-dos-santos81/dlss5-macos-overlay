# Makefile for DLSS 5 — Apple Silicon
# Thin wrapper over scripts/. Targets follow the pipeline stage order:
#   doctor → setup (all-in-one) → 1 model → 2 build → 3 sign → 4 run → dev
SERVICE = DLSS 5 — Apple Silicon

# Variables
APP = dist/DLSS_5_APPLE_SILICON.app
dll ?=
TOOLS = swift cmake ninja python3 curl unzip shasum

.PHONY: help doctor setup model build sign run test verify clean distclean

# ── Environment ──────────────────────────────────────────────────────────────

help: ## Print this help message
	@printf '\033[01;32m${SERVICE} — Experimental neural image enhancement\033[00;37m\n\n'
	@printf "\033[33mUsage:\033[0m\n  make [target] [arg=\"val\"...]\n\n\033[33mTargets:\033[0m\n"
	@grep -E '^[-a-zA-Z0-9_\.\/]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; \
		{printf "  \033[36m%-26s\033[0m %s\n", $$1, $$2}'

# Build needs the Metal compiler, which ships with full Xcode (not with the
# Command Line Tools alone), so fail here with an install hint instead of
# letting swift build emit one error per .metal source.
doctor: ## Check required tools and the Xcode Metal toolchain before building
	@missing=0; \
	for tool in $(TOOLS); do \
		if command -v "$$tool" >/dev/null 2>&1; then \
			printf '  ok       %s\n' "$$tool"; \
		else \
			printf '  MISSING  %s\n' "$$tool"; missing=1; \
		fi; \
	done; \
	if xcrun --find metal >/dev/null 2>&1; then \
		printf '  ok       metal (Xcode Metal Toolchain)\n'; \
	else \
		printf '  MISSING  metal (Xcode Metal Toolchain)\n'; \
		printf '           Install full Xcode, then run:\n'; \
		printf '             sudo xcode-select -s /Applications/Xcode.app/Contents/Developer\n'; \
		printf '             sudo xcodebuild -license accept\n'; \
		printf '             sudo xcodebuild -runFirstLaunch\n'; \
		printf '             xcodebuild -downloadComponent MetalToolchain\n'; \
		printf '           See docs/BUILDING.md (Requirements).\n'; \
		missing=1; \
	fi; \
	if [ "$$missing" -ne 0 ]; then \
		echo "doctor: prerequisites missing." >&2; \
		exit 1; \
	fi; \
	echo "doctor: all prerequisites present."

setup: doctor ## [STEP 0] One command: fetch + verify DLL, prepare model, build, launch
	@echo "Running one-command setup (fetch, verify, prepare, build, launch)..."
	./scripts/setup-and-run.sh

# ── Stage 1 · Model (nvngx_dlssnr.dll → Models/NR.dlss) ──────────────────────

model: doctor ## [STEP 1] Prepare Models/NR.dlss from a DLL (usage: make model dll=/path/to/nvngx_dlssnr.dll)
	./scripts/prepare-model.sh $(dll)

# ── Stage 2 · Build + sign ───────────────────────────────────────────────────

build: doctor ## [STEP 2] Build and sign dist/DLSS_5_APPLE_SILICON.app (requires Models/NR.dlss)
	@echo "Building $(APP)..."
	./scripts/build-app.sh

# ── Stage 3 · Re-sign ────────────────────────────────────────────────────────

sign: ## [STEP 3] Re-sign an existing app without rebuilding (set DLSS_CODESIGN_IDENTITY or ad-hoc)
	./scripts/sign-app.sh

# ── Stage 4 · Launch ─────────────────────────────────────────────────────────

run: ## [STEP 4] Launch the app, building only when it is missing
	./Launch.command

# ── Development ───────────────────────────────────────────────────────────────

test: doctor ## Run ScreenCore unit tests and the binary --self-test
	./scripts/test.sh

verify: doctor ## Source checks: public tree, shell syntax, Info.plist, build + tests (no weights needed)
	./scripts/verify-source.sh

clean: ## Remove build outputs (.build, dist)
	rm -rf .build
	rm -rf dist
	@echo "Cleanup complete."

distclean: clean ## Also remove Models/ (downloaded DLL and prepared model)
	rm -rf Models
	@echo "Full cleanup complete."
