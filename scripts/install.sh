#!/bin/bash
# 빌드하고 /Applications/TodaysRecord.app에 넣은 뒤 연다(이 Mac에서 쓰는 앱을 최신 코드로 바꾼다).
#   scripts/install.sh            # 설치하고 열기
#   scripts/install.sh --no-open  # 설치만 (scripts/run.sh가 쓴다)
# 배포용 인증서가 있으면 그것으로 서명해, 다시 설치해도 Music·Spotify 권한이 유지된다. 없으면 애드혹.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILT="$ROOT/build/TodaysRecord.app"
TARGET="${INSTALL_DIR:-/Applications}/TodaysRecord.app"

"$ROOT/scripts/bundle.sh" >/dev/null

SIGN_NAME="${SIGN_NAME:-Todays Record Code Signing}"
SIGN_ID="$(security find-identity -p codesigning 2>/dev/null | awk -v n="\"$SIGN_NAME\"" 'index($0, n) { print $2; exit }')"
if [ -n "$SIGN_ID" ]; then
  codesign --force --sign "$SIGN_ID" --timestamp=none "$BUILT"
fi

pkill -x TodaysRecord 2>/dev/null || true
for _ in 1 2 3 4 5 6 7 8 9 10; do pgrep -x TodaysRecord >/dev/null || break; sleep 0.3; done
rm -rf "$TARGET"
ditto --noqtn "$BUILT" "$TARGET"
echo "설치: $TARGET ($( [ -n "$SIGN_ID" ] && echo "$SIGN_NAME" || echo 애드혹) 서명)"

if [ "${1:-}" != "--no-open" ]; then open "$TARGET"; fi
