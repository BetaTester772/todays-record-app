#!/bin/bash
# 빌드, 조립, 서명 후 실행한다. 인자(--demo, --windowed, --log-nowplaying)는 앱에 그대로 넘긴다.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/TodaysRecord.app"

pkill -x TodaysRecord 2>/dev/null || true
"$ROOT/scripts/bundle.sh"

# 표준 출력을 터미널에서 보려고 open 대신 실행 파일을 직접 띄운다. Ctrl+C로 종료.
exec "$APP/Contents/MacOS/TodaysRecord" "$@"
