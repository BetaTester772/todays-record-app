#!/bin/bash
# 빌드하고 /Applications/TurnTable.app에 넣은 뒤 연다(이 Mac에서 쓰는 앱을 최신 코드로 바꾼다).
# 옛 이름으로 깔린 TodaysRecord.app이 있으면 지운다.
#   scripts/install.sh            # 설치하고 열기
#   scripts/install.sh --no-open  # 설치만 (scripts/run.sh가 쓴다)
# 배포용 인증서가 있으면 그것으로 서명해, 다시 설치해도 Music·Spotify 권한이 유지된다. 없으면 애드혹.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILT="$ROOT/build/TurnTable.app"
TARGET="${INSTALL_DIR:-/Applications}/TurnTable.app"
OLD="${INSTALL_DIR:-/Applications}/TodaysRecord.app"

"$ROOT/scripts/bundle.sh" >/dev/null

SIGN_NAME="${SIGN_NAME:-Todays Record Code Signing}"
SIGN_ID="$(security find-identity -p codesigning 2>/dev/null | awk -v n="\"$SIGN_NAME\"" 'index($0, n) { print $2; exit }')"
if [ -n "$SIGN_ID" ]; then
  codesign --force --sign "$SIGN_ID" --timestamp=none "$BUILT"
fi

# 0.7.x까지는 실행 파일 이름이 TodaysRecord였다. 그 버전이 켜져 있어도 끈다.
pkill -x TurnTable 2>/dev/null || true
pkill -x TodaysRecord 2>/dev/null || true
for _ in 1 2 3 4 5 6 7 8 9 10; do pgrep -x TurnTable >/dev/null || pgrep -x TodaysRecord >/dev/null || break; sleep 0.3; done
# 옛 이름 앱을 지울 때는 새 앱이 처음 켜질 때 로그인 항목을 새 위치로 다시 등록하게 한다
if [ -d "$OLD" ]; then defaults write com.todaysrecord.app renamedApp -bool true; fi
rm -rf "$TARGET" "$OLD"
ditto --noqtn "$BUILT" "$TARGET"
echo "설치: $TARGET ($( [ -n "$SIGN_ID" ] && echo "$SIGN_NAME" || echo 애드혹) 서명)"

if [ "${1:-}" != "--no-open" ]; then open "$TARGET"; fi
