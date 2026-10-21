#!/bin/bash
# 빌드해서 /Applications에 설치(scripts/install.sh)한 뒤 실행한다. 인자(--demo, --windowed, --log-nowplaying 등)는 앱에 그대로 넘긴다.
# NO_INSTALL=1이면 설치하지 않고 build/TurnTable.app을 애드혹 서명으로 실행한다.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

if [ "${NO_INSTALL:-0}" = "1" ]; then
  pkill -x TurnTable 2>/dev/null || true
  pkill -x TodaysRecord 2>/dev/null || true   # 0.7.x까지의 실행 파일 이름
  "$ROOT/scripts/bundle.sh"
  APP="$ROOT/build/TurnTable.app"
else
  "$ROOT/scripts/install.sh" --no-open
  APP="${INSTALL_DIR:-/Applications}/TurnTable.app"
fi

# 표준 출력을 터미널에서 보려고 open 대신 실행 파일을 직접 띄운다. Ctrl+C로 종료.
exec "$APP/Contents/MacOS/TurnTable" "$@"
