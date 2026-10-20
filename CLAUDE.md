# TurnTable (macOS 메뉴 막대 앱)

Apple Music 또는 Spotify에서 재생 중인 곡을 레코드 턴테이블 그림으로 바탕화면에 보여주는 앱이다.
전체 명세는 아래 문서에 있다. 작업 전에 반드시 읽는다.

@docs/SPEC.md

## 참고 파일

- `Resources/index.html` 레코드 화면. 이미 완성되어 있으며 WKWebView에서 그대로 쓴다.
- `Resources/crowd.js` 모여드는 사람들(명세 6장 25). 사람 모양, 동작, 자리 고르기는 여기서 고친다.
- `reference/nowplaying.py` Music 앱 AppleScript 질의의 검증된 참고 구현(`STATUS_SCRIPT`, `ART_SCRIPT`, 앨범 커버 검색 대체). Swift로 옮길 때 이 스크립트를 기준으로 한다.

## 작업 방식

- 마일스톤 M1 → M6 순서로, 한 번에 하나씩 진행한다(M5는 뺐다).
- 각 마일스톤을 시작하기 전에 구현 계획(만들 파일, 핵심 API, 확인 방법)을 먼저 보여주고 사용자 승인을 받는다.
- 마일스톤이 끝나면 명세 8장의 완료 기준을 체크리스트로 보고하고, 사용자가 Mac에서 직접 확인해야 하는 항목과 확인 방법을 짧게 안내한다.
- 명세가 모호하거나 macOS 동작이 명세와 다르면 추측해서 진행하지 말고, 확인한 사실과 선택지를 정리해 묻는다.
- 명세를 바꿔야 할 결정을 내리면 `docs/SPEC.md`를 함께 고친다.

## 기술 규칙

- Swift 5.9 이상, AppKit + WebKit. 외부 라이브러리를 쓰지 않는다.
- Swift Package Manager로 빌드하고 `scripts/bundle.sh`로 .app을 조립한다. `.xcodeproj`는 만들지 않는다.
- 비공개 API(MediaRemote 등)를 쓰지 않는다. 명세에 적힌 것 외의 비공개 속성 접근도 하지 않는다.
- Music이나 Spotify가 꺼져 있을 때 그 앱을 실행시키는 코드를 만들지 않는다. AppleScript 전에 `com.apple.Music`, `com.spotify.client` 실행 여부를 확인한다.
- AppleScript와 네트워크 요청은 메인 스레드 밖에서 실행한다.
- 로그는 `os.Logger`(subsystem `com.todaysrecord`)로 남긴다.
- 사용자에게 보이는 문구(화면, 메뉴, 권한 설명)는 영어로, 짧고 쉬운 말로 쓴다. 곡·앨범·아티스트 이름은 그대로 둔다. (2026-10-20 사용자 요청으로 한국어에서 변경)
- 앱 이름은 **TurnTable**(2026-10-21 사용자 요청으로 바꿈). 사용자에게 보이는 곳(화면, README, 릴리스 노트)에는 옛 이름을 쓰지 않는다. 앱 파일은 `TurnTable.app`, 배포 zip은 `TurnTable-<버전>.zip`. 번들 ID `com.todaysrecord.app`, 실행 파일·SwiftPM 이름 `TodaysRecord`, 저장소 이름은 그대로 둔다(설정·권한·업데이트가 이어지게).

## index.html 수정 규칙

- 명세 6장에 적힌 항목만 추가한다. 그림의 모양, 색, 애니메이션은 바꾸지 않는다.
- 브라우저에서 파일을 직접 열었을 때 미리보기 모드가 계속 동작해야 한다. Wallpaper Engine, 로컬 도우미 경로도 지우지 않는다.
- 수정 후 브라우저 미리보기와 `--demo` 실행 두 가지로 확인한다.

## 명령

```bash
swift build                     # 빌드
swift test                      # 단위 테스트 (고르기 규칙, 상태 해석, 곡 위치)
scripts/run.sh                  # .app 조립 → /Applications에 설치(인증서 서명) → 실행. NO_INSTALL=1이면 build/에서 애드혹으로 실행
scripts/install.sh              # .app 조립 → /Applications에 설치(인증서 서명) → 열기 (이 Mac에서 쓰는 앱을 최신 코드로)
scripts/run.sh --demo           # Music 없이 미리보기 데이터로 실행
scripts/run.sh --windowed       # 일반 창으로 띄워 디버깅 (Safari 웹 속성 검사기 연결 가능)
scripts/run.sh --log-nowplaying # Music·Spotify 알림과 AppleScript 결과 출력
scripts/run.sh --settings       # 시작할 때 설정 창 열기 (--settings=Appearance처럼 탭 지정 가능)
# 업데이트 시험: 버전을 낮춘 사본을 --install-update로 실행하면 GitHub 최신 릴리스로 스스로 바뀐다
swift scripts/make-icon.swift   # 앱 아이콘(Resources/AppIcon.icns) 다시 만들기
scripts/package.sh              # 배포용 Universal zip (dist/)
log stream --predicate 'subsystem == "com.todaysrecord"'   # 로그 보기
```

`scripts/bundle.sh`와 `scripts/run.sh`는 M1에서 만든다.

## 확인할 수 없는 것

바탕화면 층에 실제로 보이는지, 아이콘 클릭이 통과되는지, 권한 창이 뜨는지는 Claude가 직접 볼 수 없다. 이런 항목은 사용자에게 무엇을 보면 되는지 구체적으로 요청하고, 결과를 받은 뒤 다음으로 넘어간다.

## 하지 말 것

- 사용자 확인 없이 `tccutil reset` 등 시스템 권한을 초기화하지 않는다.
- 시스템 배경화면을 바꾸지 않는다(M5 시스템 배경화면 색 맞추기는 0.17에서 뺐다).
- `reference/` 폴더의 파일은 참고용이다. 앱 빌드에 포함하지 않는다.
