#!/bin/bash
# .app 번들 조립과 애드혹 서명. 결과: build/TurnTable.app (실행 파일 Contents/MacOS/TurnTable)
# UNIVERSAL=1이면 Apple Silicon과 Intel이 함께 든 실행 파일로 만든다(배포용, scripts/package.sh).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG="${CONFIG:-release}"
APP="$ROOT/build/TurnTable.app"
rm -rf "$ROOT/build/TodaysRecord.app"   # 이름을 바꾸기 전에 만든 번들

cd "$ROOT"
ARCH_FLAGS=()
if [ "${UNIVERSAL:-0}" = "1" ]; then ARCH_FLAGS=(--arch arm64 --arch x86_64); fi
swift build -c "$CONFIG" ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"}
BIN="$(swift build -c "$CONFIG" ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"} --show-bin-path)/TurnTable"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/TurnTable"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/Resources/index.html" "$APP/Contents/Resources/index.html"
cp "$ROOT/Resources/crowd.js" "$APP/Contents/Resources/crowd.js"
cp "$ROOT/Resources/sound.js" "$APP/Contents/Resources/sound.js"
if [ -f "$ROOT/Resources/AppIcon.icns" ]; then
  cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
fi

codesign --force --sign - "$APP"
echo "$APP"
