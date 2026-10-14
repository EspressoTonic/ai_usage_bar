#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mkdir -p "$ROOT_DIR/dist"
python3 "$ROOT_DIR/script/generate_touchbar_preset.py"
cd "$ROOT_DIR/addons"
/usr/bin/ditto -c -k --keepParent TouchBar "$ROOT_DIR/dist/AIUsageBar-TouchBar.zip"
du -sh "$ROOT_DIR/dist/AIUsageBar-TouchBar.zip"
