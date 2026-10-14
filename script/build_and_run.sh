#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
MODE="${1:-run}"
shift $(( $# > 0 ? 1 : 0 ))
APP_BUNDLE="$ROOT_DIR/dist/AIUsageBar.app"
while IFS= read -r pid; do
  command_path="$(ps -p "$pid" -o comm= || true)"
  if [[ "$command_path" == "$APP_BUNDLE/Contents/MacOS/AIUsageBar" ]]; then kill "$pid" || true; fi
done < <(pgrep -x AIUsageBar || true)
./script/package_app.sh "${AI_USAGE_BAR_CONFIGURATION:-debug}"
case "$MODE" in
  run) /usr/bin/open -n "$APP_BUNDLE" --args "$@" ;;
  --verify) /usr/bin/open -n "$APP_BUNDLE" --args "$@"; sleep 1; pgrep -x AIUsageBar >/dev/null ;;
  --debug) lldb -- "$APP_BUNDLE/Contents/MacOS/AIUsageBar" "$@" ;;
  --logs) /usr/bin/open -n "$APP_BUNDLE" --args "$@"; /usr/bin/log stream --info --style compact --predicate 'process == "AIUsageBar"' ;;
  *) echo "usage: $0 [run|--verify|--debug|--logs] [--demo]" >&2; exit 2 ;;
esac
