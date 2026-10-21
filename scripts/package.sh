#!/bin/bash
# 배포용 zip을 만든다. 결과: dist/TurnTable-<버전>.zip과 TurnTable-<버전>.sha256,
# 그리고 이름을 바꾸기 전(0.4.x) 앱의 업데이트용 TodaysRecord-<버전>.zip과 .zip.sha256(안의 앱은 같고 이름만 TodaysRecord.app).
# 옛 앱은 릴리스에서 처음 보이는 .zip.sha256을 쓰므로, 새 체크섬 파일 이름에는 .zip을 넣지 않는다.
# Apple Silicon과 Intel이 함께 든 실행 파일로 조립하고, 배포용 인증서로 서명한다(공증은 하지 않음, README 참고).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT/Resources/Info.plist")"
DIST="$ROOT/dist"
ZIP="$DIST/TurnTable-$VERSION.zip"
OLDZIP="$DIST/TodaysRecord-$VERSION.zip"

UNIVERSAL=1 "$ROOT/scripts/bundle.sh" >/dev/null
APP="$ROOT/build/TurnTable.app"

# 이 Mac의 로그인 키체인에 배포용 자체 서명 인증서가 있으면 그것으로 다시 서명한다.
# 같은 인증서로 서명한 버전끼리는 macOS가 같은 앱으로 보아, 업데이트해도 Music·Spotify 권한이 유지된다.
SIGN_NAME="${SIGN_NAME:-Todays Record Code Signing}"
SIGN_ID="$(security find-identity -p codesigning 2>/dev/null | awk -v n="\"$SIGN_NAME\"" 'index($0, n) { print $2; exit }')"
if [ -n "$SIGN_ID" ]; then
  codesign --force --sign "$SIGN_ID" --timestamp=none "$APP"
  echo "서명: $SIGN_NAME ($SIGN_ID)"
else
  echo "서명: 애드혹 ('$SIGN_NAME' 인증서가 없음)"
fi
codesign --verify --strict "$APP"
codesign -d -r- "$APP" 2>&1 | tail -1
lipo -info "$APP/Contents/MacOS/TurnTable"

mkdir -p "$DIST"
rm -f "$ZIP" "$DIST/TurnTable-$VERSION.sha256" "$OLDZIP" "$OLDZIP.sha256"
# ditto는 확장 속성과 서명을 지켜서 압축한다(Finder의 '압축'과 같은 방식).
ditto -c -k --keepParent "$APP" "$ZIP"
(cd "$DIST" && shasum -a 256 "$(basename "$ZIP")" > "TurnTable-$VERSION.sha256")
# 옛 이름 사본: 서명은 번들 폴더 이름과 상관없어 그대로 유효하다
OLDTMP="$(mktemp -d)"; ditto "$APP" "$OLDTMP/TodaysRecord.app"
codesign --verify --strict "$OLDTMP/TodaysRecord.app"
ditto -c -k --keepParent "$OLDTMP/TodaysRecord.app" "$OLDZIP"; rm -rf "$OLDTMP"
(cd "$DIST" && shasum -a 256 "$(basename "$OLDZIP")" > "$(basename "$OLDZIP").sha256")
echo "$ZIP"; cat "$DIST/TurnTable-$VERSION.sha256"
echo "$OLDZIP"; cat "$OLDZIP.sha256"
