#!/bin/bash
# 배포용 zip을 만든다. 결과: dist/TodaysRecord-<버전>.zip 과 .sha256
# Apple Silicon과 Intel이 함께 든 실행 파일로 조립하고 애드혹 서명한다(공증은 하지 않음, README 참고).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT/Resources/Info.plist")"
DIST="$ROOT/dist"
ZIP="$DIST/TodaysRecord-$VERSION.zip"

UNIVERSAL=1 "$ROOT/scripts/bundle.sh" >/dev/null
APP="$ROOT/build/TodaysRecord.app"
codesign --verify --strict "$APP"
lipo -info "$APP/Contents/MacOS/TodaysRecord"

mkdir -p "$DIST"
rm -f "$ZIP" "$ZIP.sha256"
# ditto는 확장 속성과 서명을 지켜서 압축한다(Finder의 '압축'과 같은 방식).
ditto -c -k --keepParent "$APP" "$ZIP"
(cd "$DIST" && shasum -a 256 "$(basename "$ZIP")" > "$(basename "$ZIP").sha256")
echo "$ZIP"
cat "$ZIP.sha256"
