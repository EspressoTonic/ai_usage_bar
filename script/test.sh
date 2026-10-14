#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
DEV_DIR="$(xcode-select -p)"
if [[ "$DEV_DIR" == */CommandLineTools ]]; then
  python3 script/portable_tests.py
else
  swift test
fi
