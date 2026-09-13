#!/usr/bin/env python3
"""Read-only publication check; also works before the first git init.

With Git, inspect tracked and unignored files. Before initialization, inspect
the source tree while skipping known local build/data directories. This is a
small guard against accidental binaries and private data, not a secret scanner.
"""
from pathlib import Path
import argparse
import os
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
LOCAL_DIRS = {".build", ".swiftpm", ".venv", "venv", "__pycache__", ".pytest_cache",
              ".idea", ".vscode", "xcuserdata"}
LOCAL_ROOTS = {"Models", "dist", "local-runtime", "recordings", "exports", "captures", "diagnostics", "tmp"}
FORBIDDEN_SUFFIXES = {".dll", ".dylib", ".safetensors", ".metallib", ".pt", ".pth", ".onnx",
                      ".pem", ".p12", ".pfx", ".mobileprovision", ".keychain-db"}
MAX_BYTES = 10 * 1024 * 1024
PERSONAL_PATH = re.compile(rb"/(?:Us" + rb"ers|ho" + rb"me)/[A-Za-z0-9_.-]+/")
TOKEN = re.compile(rb"(?:gh[pousr]_" + rb"[A-Za-z0-9]{30,}|AKIA" + rb"[A-Z0-9]{16})")
PRIVATE_KEY = re.compile(rb"-----BEGIN " + rb"(?:[A-Z]+ )?PRIVATE KEY-----")
EXECUTABLE_MAGIC = {b"\x7fELF", b"\xcf\xfa\xed\xfe", b"\xfe\xed\xfa\xcf",
                    b"\xce\xfa\xed\xfe", b"\xfe\xed\xfa\xce", b"\xca\xfe\xba\xbe"}


def git_files():
    result = subprocess.run(["git", "rev-parse", "--show-toplevel"], cwd=ROOT,
                            capture_output=True, text=True)
    if result.returncode or Path(result.stdout.strip()).resolve() != ROOT:
        return None
    result = subprocess.run(["git", "ls-files", "-z", "--cached", "--others", "--exclude-standard"],
                            cwd=ROOT, capture_output=True, check=True)
    return sorted(set(os.fsdecode(item) for item in result.stdout.split(b"\0") if item))


def source_files():
    files = []
    for directory, dirs, names in os.walk(ROOT, followlinks=False):
        base = Path(directory)
        keep = []
        for name in dirs:
            if name in LOCAL_DIRS or (base == ROOT and name in LOCAL_ROOTS):
                continue
            if name == ".git":
                if base != ROOT:
                    files.append(str((base / name).relative_to(ROOT)))
                continue
            keep.append(name)
        dirs[:] = keep
        for name in names:
            if name == ".DS_Store" or name.startswith("._") or name.endswith((".log", ".pyc", ".pyo")):
                continue
            files.append(str((base / name).relative_to(ROOT)))
    return sorted(files)


def inspect(relative):
    path = ROOT / relative
    parts = Path(relative).parts
    reasons = []
    if parts[0] in LOCAL_ROOTS or any(part in LOCAL_DIRS or part == ".git" or
        part.endswith((".app", ".dlss", ".dlssmodel", ".dSYM")) for part in parts):
        reasons.append("local data, application bundle or nested repository")
    if path.suffix.lower() in FORBIDDEN_SUFFIXES or path.name == ".env" or path.name.startswith(".env."):
        reasons.append("model/runtime data or machine-local credential file")
    if path.suffix.lower() in {".mp4", ".mov", ".m4v", ".mkv", ".avi", ".wav", ".mp3", ".aac"} and not relative.startswith("Vendor/MLX-DLSS/docs/assets/"):
        reasons.append("capture/export media belongs in an ignored local output directory")
    if path.is_symlink():
        reasons.append("symbolic links are not part of this source distribution")
        return reasons
    if not path.is_file():
        return reasons + ["missing file or nested repository; inspect the Git index"]
    if path.stat().st_size > MAX_BYTES:
        return reasons + ["file exceeds the 10 MiB source-file budget"]
    data = path.read_bytes()
    if data[:4] in EXECUTABLE_MAGIC or data[:2] == b"MZ":
        reasons.append("compiled executable")
    if PERSONAL_PATH.search(data):
        reasons.append("absolute personal home path")
    if TOKEN.search(data) or PRIVATE_KEY.search(data):
        reasons.append("possible credential or private key")
    return reasons


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--list", action="store_true", help="List accepted source paths")
    args = parser.parse_args()
    files = git_files()
    mode = "Git candidates" if files is not None else "source tree (before Git initialization)"
    files = files if files is not None else source_files()
    problems = [(name, inspect(name)) for name in files]
    failures = [(name, reasons) for name, reasons in problems if reasons]
    for name, reasons in failures:
        print(f"FAIL {name}: {'; '.join(reasons)}", file=sys.stderr)
    if failures:
        return 1
    if args.list:
        print("\n".join(files))
    else:
        size = sum((ROOT / name).stat().st_size for name in files)
        print(f"PASS {mode}: {len(files)} files, {size / 1024 / 1024:.2f} MiB; no rejected files.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
