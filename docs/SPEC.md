# 오늘의 판 — macOS 앱 명세서

버전 0.4 · 2026-10-20 (0.2: LP 면 나누기, iTunes 검색 국가 대체 · 0.3: 음량 노브, 면 램프 · 0.4: 색 퍼짐 전환, 곡 안 위치 이동)

## 1. 개요

Apple Music에서 지금 재생 중인 곡을 레코드 턴테이블 그림으로 바탕화면에 보여주는 macOS 메뉴 막대 앱이다. 레코드가 돌고, 톤암 바늘이 곡의 진행에 맞춰 판 안쪽으로 이동하며 앨범 색으로 선을 남기고, 바늘 머리에는 작은 캐릭터가 앉아 있다.

화면 그리기는 이미 완성된 `Resources/index.html`(HTML5 Canvas)을 그대로 쓴다. 이 앱이 새로 만드는 것은 그 화면을 바탕화면 층에 띄우고, Music 앱의 재생 정보를 읽어 화면에 넘겨주는 macOS 쪽 부분이다.

### 목표

- 설치 후 터미널이나 별도 앱(Plash 등) 없이 앱 하나로 동작한다.
- 바탕화면 아이콘과 위젯을 가리지 않고, 클릭을 방해하지 않는다.
- 재생하지 않을 때나 화면이 가려졌을 때는 거의 자원을 쓰지 않는다.

### 범위 밖 (이번 버전에서 하지 않음)

- Spotify 등 Music 외 플레이어 지원
- 잠금 화면, 로그인 화면 표시
- App Store 배포와 샌드박스
- 소리 자체를 분석하는 비트 반응
- 비공개 API(MediaRemote 등) 사용

## 2. 환경

| 항목 | 값 |
|---|---|
| 최소 macOS | 14 (Sonoma) |
| 아키텍처 | Apple Silicon, Intel (Universal 빌드는 선택) |
| 언어 | Swift 5.9 이상 |
| UI | AppKit (창, 메뉴 막대). SwiftUI는 필요할 때만 |
| 렌더링 | WebKit `WKWebView` + `Resources/index.html` |
| 빌드 | Swift Package Manager + 번들 스크립트. Xcode 프로젝트 파일은 만들지 않는다 |
| 외부 라이브러리 | 사용하지 않는다 |
| 서명 | 개발 중 애드혹 서명(`codesign -s -`). 샌드박스 사용 안 함 |

## 3. 구조

```
Package.swift
Sources/TodaysRecord/
├─ main.swift              NSApplication 시작, 실행 인자 처리
├─ AppDelegate.swift       구성 요소 생성과 연결
├─ StatusMenu.swift        메뉴 막대 아이콘과 메뉴
├─ Settings.swift          UserDefaults에 저장되는 설정
├─ WallpaperController.swift  화면별 창 생성, 모니터 변경 대응
├─ WallpaperWindow.swift   바탕화면 층 창
├─ RecordWebView.swift     WKWebView 설정과 브리지
├─ NowPlaying.swift        Music 재생 정보 읽기
├─ Artwork.swift           앨범 커버 가져오기 (Music → 검색 대체)
├─ ITunesSearch.swift      iTunes Search API (커버 검색, 앨범 곡 목록)
├─ AlbumTracks.swift       앨범 디스크별 곡 길이 (LP 면 나누기용)
├─ SystemVolume.swift      시스템 출력 음량 (음량 노브용)
├─ PowerWatcher.swift      잠금, 잠자기, 가려짐 감지
└─ WallpaperSync.swift     시스템 배경화면 색 맞추기 (선택 기능)
Resources/
├─ index.html              레코드 화면 (기존 파일, 6장에 따라 일부 수정)
├─ Info.plist              번들 정보
└─ AppIcon.icns            (선택)
scripts/
├─ bundle.sh               .app 번들 조립과 애드혹 서명
└─ run.sh                  빌드 후 실행
```

데이터 흐름: Music 앱 → `NowPlaying` → `AppDelegate` → 각 `RecordWebView` → `index.html`. 설정 변경은 `StatusMenu` → `Settings` → 각 `RecordWebView`. 절전 상태는 `PowerWatcher` → 각 `RecordWebView`.

## 4. 구성 요소 명세

### 4.1 앱 형태와 실행

- Dock 아이콘 없이 메뉴 막대에만 존재한다 (`Info.plist`의 `LSUIElement = true`).
- 실행 인자
  - `--demo`: Music 대신 index.html 내장 미리보기 데이터로 동작 (Music 없이 테스트용)
  - `--log-nowplaying`: 받은 Music 알림 내용과 AppleScript 결과를 표준 출력에 기록
  - `--windowed`: 바탕화면 층 대신 일반 창으로 띄워 디버깅 (Safari 웹 속성 검사기로 확인 가능하게 `isInspectable = true`)

### 4.2 바탕화면 층 창 (`WallpaperWindow`)

- 테두리 없는 `NSWindow`(`styleMask: .borderless`), 해당 화면 전체 크기.
- 창 층: `CGWindowLevelForKey(.desktopWindow)`. 바탕화면 그림 위, Finder 아이콘 아래에 와야 한다. 아이콘이 가려지면 층 값을 조정한다.
- `collectionBehavior`: `.canJoinAllSpaces`, `.stationary`, `.ignoresCycle`, `.fullScreenNone`
- `ignoresMouseEvents = true` (아이콘 클릭, 바탕화면 우클릭, 드래그 선택이 그대로 동작해야 함)
- `isOpaque`, `backgroundColor`: 투명 배경 설정(4.6)에 따라 바뀐다. 투명일 때 `isOpaque = false`, `backgroundColor = .clear`.
- `hasShadow = false`, `isReleasedWhenClosed = false`
- 창은 키 윈도우나 메인 윈도우가 되지 않는다.

### 4.3 화면 관리 (`WallpaperController`)

- 설정 `displays`: `main`(기본, 주 화면만) 또는 `all`(모든 화면).
- `NSApplication.didChangeScreenParametersNotification`을 받으면 창을 다시 만들거나 크기를 맞춘다.
- `all`일 때 주 화면의 창만 `role = primary`, 나머지는 `mirror`. 기록 저장은 primary만 한다(6장).

### 4.4 웹 화면 (`RecordWebView`)

- `WKWebView`로 번들의 `index.html`을 `loadFileURL(_:allowingReadAccessTo:)`로 연다.
- `WKWebsiteDataStore.default()`를 써서 localStorage가 앱을 껐다 켜도 유지되게 한다.
- 문서 시작 시점(`atDocumentStart`)에 다음 스크립트를 주입한다.
  ```js
  window.__TR_NATIVE__ = { role: "primary", screen: "<화면 식별자>" };
  ```
- `WKScriptMessageHandler` 이름은 `todaysRecord`.
- 투명 배경일 때 웹뷰 배경도 투명해야 한다 (`underPageBackgroundColor = .clear`, 필요하면 `setValue(false, forKey: "drawsBackground")`).
- 다른 주소로의 이동은 막는다 (`WKNavigationDelegate`에서 파일 주소 외 취소).
- 웹 콘텐츠 프로세스가 죽으면(`webViewWebContentProcessDidTerminate`) 다시 불러온다.

### 4.5 재생 정보 읽기 (`NowPlaying`)

Music 앱의 재생 정보를 다음 두 가지 방법을 합쳐서 얻는다.

**(1) 분산 알림.** `DistributedNotificationCenter`에서 이름 `com.apple.Music.playerInfo`를 구독한다. 곡 변경, 재생, 일시정지, 정지 때 온다. `userInfo`에 곡 이름, 아티스트, 앨범, 재생 상태, 전체 시간, 영구 ID 등이 들어 있다. 정확한 키 이름은 `--log-nowplaying`으로 실제 값을 찍어 확인한 뒤 확정한다.

**(2) AppleScript.** 알림에 없는 정보(현재 재생 위치, 앨범 아티스트, BPM, 곡 번호·곡 수·디스크 번호·디스크 수, 앨범 커버)와 앱 시작 시점의 상태는 `NSAppleScript`로 묻는다. 참고 구현은 `reference/nowplaying.py`의 `STATUS_SCRIPT`, `ART_SCRIPT`에 있다.
- Music이 실행 중이 아니면 절대 실행시키지 않는다. `NSRunningApplication`으로 번들 ID `com.apple.Music`이 떠 있을 때만 묻는다.
- AppleScript는 메인 스레드를 막지 않도록 별도 직렬 큐에서 실행한다.
- 언제 묻는가: 앱 시작 시 1번, 알림을 받을 때마다 1번, 재생 중에는 위치 보정을 위해 10초마다 1번. 1초마다 묻지 않는다.
- 숫자는 지역 설정에 따라 소수점이 쉼표일 수 있으니 문자열로 받으면 `,`를 `.`로 바꿔 해석한다.
- macOS 27의 Music 사전에서는 `tell application "Music"` 안에서 변수 이름 `st`가 컴파일되지 않는다. 참고 구현의 `st`는 `pstate`로 바꿔 쓴다.

**(3) 앨범 곡 목록.** 곡이 바뀌어 새 앨범이 나오면 iTunes Search API로 그 앨범의 곡 목록(디스크, 곡 번호, 제목, 길이)을 한 번 받아 앨범별로 기억한다(`AlbumTracks`). 찾는 동안 최대 3초까지 새 곡 상태를 보내지 않고 기다리며, 시간이 넘거나 찾지 못하면 목록 없이 보낸다.
- 라이브러리에 없는 스트리밍 곡은 AppleScript의 `track number`, `track count`, `disc number`, `disc count`가 모두 0이다(2026-10 확인). 이때는 곡 목록에서 제목이 같은 곡(없으면 길이가 1초 이내로 같은 곡이 하나뿐일 때 그 곡)으로 곡 번호와 디스크를 정한다.
- 디스크의 곡 번호가 1부터 빠짐없이 이어지지 않거나, Music이 준 곡 수와 다르면 목록을 쓰지 않는다.

**출력 형식.** 상태가 바뀔 때마다 아래 JSON을 만들어 모든 웹뷰에 보낸다. `/now` 엔드포인트(참고 구현)와 같은 모양이다.

```json
{
  "state": "playing",            // "playing" | "paused" | "stopped"
  "title": "곡 이름",
  "artist": "아티스트",
  "album": "앨범",
  "albumArtist": "앨범 아티스트",
  "duration": 215.5,             // 초
  "position": 12.0,              // 초, 이 값을 보낸 시점 기준
  "bpm": 0,                      // 없으면 0
  "id": "영구 ID 또는 제목|아티스트|앨범",
  "trackNumber": 3,              // 디스크 안 곡 번호, 없으면 0
  "trackCount": 12,              // 디스크 안 곡 수, 없으면 0
  "discNumber": 1,               // 없으면 0
  "discCount": 1,                // 없으면 0
  "trackDurations": [184.0, ...],// 이 디스크의 곡 길이(초), 곡 번호 순서. 모르면 생략
  "art": "3"                     // 이 곡의 커버가 준비됐을 때만. 커버 버전 문자열
}
```

`fast forwarding`, `rewinding`은 `playing`으로 본다.

**권한.** 처음 AppleScript를 실행하면 macOS가 “Music을 제어하려고 합니다” 권한을 묻는다. `Info.plist`에 `NSAppleEventsUsageDescription`을 넣는다. 오류 코드 -1743(권한 없음)을 받으면 상태를 `stopped`로 보내고, 메뉴에 “Music 제어 권한 열기” 항목을 보여 시스템 설정의 자동화 화면을 연다.

### 4.6 앨범 커버 (`Artwork`)

- 곡 ID가 바뀔 때만 가져온다.
- 1순위: AppleScript로 `artwork 1 of current track`의 `raw data`.
- 2순위(커버가 없거나 실패): iTunes Search API `https://itunes.apple.com/search?term=<아티스트 앨범>&entity=album&limit=5&country=<국가>`에서 앨범 이름이 같은 결과(없으면 첫 결과)의 `artworkUrl100`에서 `100x100bb`를 `600x600bb`로 바꿔 받는다. 국가 기본값 `KR`, 설정으로 변경 가능.
- 앨범 찾기는 먼저 `entity=song`, `term=<아티스트 제목>`으로 하고(스트리밍 곡의 앨범은 앨범 검색에 잘 걸리지 않음), 못 찾으면 위의 앨범 검색을 쓴다. 앨범 이름과 곡 제목이 같은 결과를 먼저 고른다.
- 2026-10 확인 결과 `country=KR`은 search, lookup 모두 결과가 0건이다(한국 iTunes Store는 음악을 팔지 않음). 그래서 설정 국가로 찾지 못하면 `US`로 한 번 더 찾는다. 찾은 앨범의 `collectionId`로 `lookup?id=<id>&entity=song`을 불러 곡 목록과 길이(`trackTimeMillis`)도 얻는다(4.5의 (3)).
- PNG/JPEG 바이트를 base64 data URL로 바꿔 `TodaysRecord.art(dataURL, version)`으로 보낸다. 같은 커버를 다시 보내지 않는다.

### 4.6.1 시스템 음량 (`SystemVolume`)

- CoreAudio 공개 API로 기본 출력 장치의 음량(`kAudioHardwareServiceDeviceProperty_VirtualMainVolume`, 0~1)과 음소거(`kAudioDevicePropertyMute`)를 읽는다.
- 속성 알림(`AudioObjectAddPropertyListenerBlock`)으로 바뀔 때마다 바로 받는다. 기본 출력 장치가 바뀌면 새 장치에 다시 붙는다. 주기적으로 묻지 않는다.
- 값이 바뀌면 `TodaysRecord.setVolume({level, muted})`로 보낸다. 장치에 음량 조절이 없으면 `level`을 빼고 보낸다. `--demo`에서도 보낸다.

### 4.7 절전 (`PowerWatcher`)

다음 중 하나라도 해당하면 모든 웹뷰에 `setPaused(true)`, 모두 풀리면 `setPaused(false)`.

- 화면 잠자기 (`NSWorkspace.screensDidSleepNotification` / `screensDidWakeNotification`)
- 시스템 잠자기 (`willSleepNotification` / `didWakeNotification`)
- 화면 잠금 (분산 알림 `com.apple.screenIsLocked` / `com.apple.screenIsUnlocked`)
- 창이 완전히 가려짐 (`NSWindow.didChangeOcclusionStateNotification`, 창별로 판단)
- 사용자가 메뉴에서 끔

배터리 사용 중이면 초당 프레임을 30으로 제한한다(설정 `fps`가 `auto`일 때).

### 4.8 메뉴 막대 (`StatusMenu`)

아이콘은 작은 레코드 모양의 템플릿 이미지(SF Symbols `opticaldisc` 등 대체 가능). 메뉴 항목:

| 항목 | 동작 |
|---|---|
| 지금 재생 중인 곡 (비활성 텍스트) | 제목 — 아티스트 표시. 없으면 “재생 중인 음악 없음” |
| 배경화면 켜기 / 끄기 | 창 표시 여부 |
| 레코드 위치 ▸ 왼쪽 / 가운데 / 오른쪽 | `setOptions({position})` |
| 배경 ▸ 기본 / 투명 | 투명이면 원래 배경화면 위에 턴테이블만 표시 |
| 표시할 화면 ▸ 주 화면 / 모든 화면 | 4.3 |
| 시스템 배경화면 색 맞추기 (체크) | 4.9 |
| 이 판 비우기 | `clearRecord()` |
| 로그인 시 실행 (체크) | `SMAppService.mainApp` 등록/해제 |
| Music 제어 권한 열기 | 권한이 없을 때만 표시 |
| 종료 | 앱 종료 (4.9가 켜져 있으면 원래 배경화면 복원 후) |

설정은 `UserDefaults`에 저장하고, 앱 시작 시 모든 웹뷰에 `setOptions`로 적용한다.

### 4.9 시스템 배경화면 색 맞추기 (`WallpaperSync`, 선택 기능, 기본 꺼짐)

메뉴 막대 색, 위젯 색, 잠금 화면이 레코드 화면과 어울리도록 시스템 배경화면을 현재 앨범 색의 단색 이미지로 바꾼다.

- 켤 때 화면별 현재 배경화면 주소(`NSWorkspace.shared.desktopImageURL(for:)`)와 옵션을 저장한다.
- 웹 화면이 보내는 `palette` 메시지(6장)를 받으면 `bg` 색의 작은 PNG를 Application Support 폴더에 만들어 `setDesktopImageURL(_:for:options:)`로 지정한다. 같은 색이면 다시 하지 않는다.
- 끄거나 앱을 종료할 때 저장해둔 원래 배경화면으로 되돌린다.
- 원래 배경화면이 동적 배경화면이나 에어리얼이어서 주소로 복원이 안 되는 경우를 확인하고, 안 되면 메뉴에 그 사실을 알리고 이 기능을 끈다.

## 5. 브리지 계약 (Swift ↔ JavaScript)

### Swift → JavaScript

`evaluateJavaScript`로 호출한다. 문자열은 반드시 JSON 직렬화해서 넘긴다(따옴표, 줄바꿈 이스케이프).

| 호출 | 설명 |
|---|---|
| `TodaysRecord.nowPlaying(payload)` | 4.5의 JSON |
| `TodaysRecord.art(dataURL, version)` | 앨범 커버 |
| `TodaysRecord.setPaused(bool)` | 그리기 멈춤/재개 |
| `TodaysRecord.setOptions({position, transparent, fps})` | position: `"left"`, `"center"`, `"right"` · transparent: bool · fps: 30 또는 60 |
| `TodaysRecord.clearRecord()` | 지금 판의 선 지우기 |
| `TodaysRecord.setVolume({level, muted})` | 시스템 음량. level: 0~1(모르면 생략), muted: bool (4.6.1) |

### JavaScript → Swift

`window.webkit.messageHandlers.todaysRecord.postMessage(obj)`

| type | 내용 |
|---|---|
| `ready` | 화면 준비 완료. Swift는 이걸 받은 뒤에 첫 상태와 설정을 보낸다 |
| `palette` | `{ type, bg, plinth, accent }` 16진수 색. 앨범이 바뀌어 색이 확정될 때 |
| `log` | `{ type, message }` 디버그용 |

## 6. index.html 수정 사항

기존 동작(브라우저 미리보기, Wallpaper Engine, 로컬 도우미)은 그대로 둔다. 다음을 추가한다.

1. **native 소스.** `window.__TR_NATIVE__`가 있으면 `media.source = 'native'`로 시작하고 미리보기 데이터를 쓰지 않는다. `TodaysRecord.nowPlaying`은 기존 `applyNowPlaying`을 재사용한다. 커버는 `TodaysRecord.art`로 받아 기존 `applyArt` 경로를 쓴다. 준비되면 `ready`를 보낸다.
2. **앱 실행 인자 `--demo`.** Swift가 `__TR_NATIVE__.demo = true`를 넣으면 미리보기 데이터로 동작한다.
3. **멈춤.** `setPaused(true)`면 `requestAnimationFrame` 루프를 멈추고, false면 시간 차이를 건너뛰고 재개한다(멈춘 동안의 시간이 한꺼번에 흐르지 않게).
4. **프레임 제한.** `fps`가 30이면 프레임을 하나 걸러 그린다.
5. **레코드 위치.** `layout()`의 가로 중심을 left ≈ 0.32W, center ≈ 0.5W, right ≈ 0.57W(현재값)로 바꾼다. 곡 정보 표시는 레코드 반대쪽 위에 둔다(left일 때 오른쪽 위).
6. **투명 배경.** transparent면 배경 채우기와 받침(plinth)을 그리지 않고, 레코드·톤암·노브·곡 정보만 그린다. 그레인은 레코드 영역에만 적용하거나 생략한다.
7. **역할.** `role`이 `mirror`면 localStorage에 쓰지 않는다(읽기만).
8. **palette 메시지.** 앨범 색이 바뀔 때 `bg`, `plinth`, `accent`를 보낸다.
9. 상태 문구: native에서 권한 오류 등으로 stopped일 때 “Apple Music에서 음악을 틀면 바늘이 내려가요”를 보여준다.
10. **LP 면 나누기.** `trackNumber`, `trackCount`가 있으면 실제 LP처럼 디스크를 면으로 나눈다.
    - 한 면에 최대 6곡. 면 수는 `ceil(곡 수 / 6)`, 곡은 앞면부터 고르게 나눈다(2곡 → 1면, 12곡 → 6+6, 13곡 → 5+4+4).
    - 면 하나가 판 하나다(판 키 = 앨범 키 + 디스크 + 면). 면 안에서 곡마다 띠를 나누고, 띠 폭은 `trackDurations`가 있으면 곡 길이 비율, 없으면 같은 폭. 기존 미리보기 데이터의 `bandsFor`와 `beginTrack({band, gaps})`를 그대로 쓴다.
    - 같은 면의 다른 곡이면 바늘만 그 곡의 띠로 옮기고, 같은 앨범의 다른 면이나 다른 앨범이면 기존 판 바꾸기 동작을 쓴다.
    - 같은 앨범의 다른 면은 커버(라벨, 색)를 함께 쓴다.
    - 곡 번호나 곡 수가 없으면 기존 동작(곡 길이를 `SIDE_LEN` 기준으로 이어 그림)을 쓴다.
11. **음량 노브와 면 표시.** 기존 속도 노브, 전원 램프와 같은 모양과 색을 쓴다.
    - 음량 노브: 속도 노브 오른쪽(판 평면 좌표 1.0R, 1.0R)의 같은 금속 노브. 바늘이 0~100%를 왼쪽 아래에서 오른쪽 아래까지 270도로 가리키고, 둘레의 눈금 점 10개 중 음량만큼을 앨범 색(accent)으로 켠다. 음소거면 눈금을 모두 끈다. 값이 바뀌면 바늘이 부드럽게 따라간다. 미리보기에서는 60%로 보인다.
    - 면 램프: 판과 전원 램프 사이(0.18R, 1.06R부터)에 이 디스크의 면 수만큼(최대 4개) 작은 램프와 A·B·C… 픽셀 글자를 두고, 지금 면만 앨범 색으로 켠다. 정지 중이거나 면을 모르면 그리지 않는다.
    - 곡 정보: 진행 막대 아래에 `B면 · 4/6`(면 글자, 면 안의 곡 번호/곡 수)을 기존 픽셀 글씨로 쓴다.
    - 매우 넓은 화면(21:9)에서도 잘리지 않는 위치인지 확인했다.
12. **앨범 색 전환.** 앨범 색(배경, 받침 등)이 바뀔 때 한 번에 바꾸지 않고, 새 색이 판 가운데에서 둥글게 퍼져 나가 약 1.6초에 화면을 덮는다(가장자리는 부드럽게 섞음). 판을 바꾸는 순간이나, 이미 놓인 판의 커버가 늦게 도착했을 때 일어난다. 색이 같으면 하지 않고, 동작 줄이기 설정(`prefers-reduced-motion`)이면 기존처럼 천천히 섞는다.
13. **곡 안 위치 이동.** 같은 곡에서 위치가 3초 넘게 달라지면(처음으로, 건너뛰기) 바늘을 들어 새 위치로 옮긴다. Music은 위치 이동에 알림을 보내지 않으므로(2026-10 확인) 다음 정기 확인 때 반영된다.

## 7. 성능 목표

- 재생 중 30fps 기준, Apple Silicon에서 활동 모니터 CPU가 낮게 유지될 것(구현 후 측정해서 기록).
- 멈춤 상태에서는 웹 콘텐츠 프로세스 CPU가 거의 0이어야 한다.
- AppleScript 호출은 재생 중에도 10초당 1번 이하(알림 반응 제외).

## 8. 마일스톤과 완료 기준

각 마일스톤이 끝나면 사용자가 Mac에서 직접 확인한다.

**M1. 바탕화면에 띄우기**
- `swift build`와 `scripts/run.sh`로 .app이 만들어지고 실행된다.
- `--demo`로 실행하면 미리보기 레코드가 바탕화면 층에 보인다.
- 아이콘이 레코드 위에 보이고, 아이콘 클릭·우클릭·드래그 선택이 된다.
- 모든 데스크톱 공간에서 보이고, Mission Control에서 창으로 잡히지 않는다.

**M2. 메뉴 막대와 설정**
- 메뉴 항목이 동작하고 설정이 재시작 후에도 유지된다.
- 레코드 위치, 투명 배경, 이 판 비우기가 화면에 반영된다(6장 5·6 포함).
- 로그인 시 실행이 등록/해제된다.

**M3. Apple Music 연결**
- Music에서 곡을 틀면 제목, 아티스트, 앨범, 진행 시간, 커버가 반영된다.
- 같은 면의 다음 곡은 같은 판에서 바늘만 그 곡의 띠로 옮겨가고, 다른 면이나 다른 앨범이면 판을 바꾼다(6장 10).
- 일시정지, 정지, Music 종료가 각각 맞게 표시된다.
- Music이 꺼져 있을 때 앱이 Music을 실행시키지 않는다.
- 권한을 거부하면 메뉴에 권한 열기 항목이 보인다.

**M4. 절전과 여러 화면**
- 잠금, 잠자기, 전체 화면 앱으로 가려질 때 그리기가 멈추고 돌아오면 이어진다.
- 모든 화면 모드에서 모니터를 꽂고 빼도 창이 맞게 다시 생긴다.

**M5. 시스템 배경화면 색 맞추기**
- 켜면 앨범이 바뀔 때 시스템 배경화면이 그 색으로 바뀌고, 끄거나 종료하면 원래대로 돌아온다.

**M6. 마무리**
- README에 빌드, 설치(/Applications로 복사), 권한, 문제 해결을 적는다.
- 애드혹 서명된 .app을 zip으로 만드는 스크립트.

## 9. 알려진 주의점

- 애드혹 서명은 빌드할 때마다 서명이 바뀌어 Music 제어 권한을 다시 물을 수 있다. 계속 거슬리면 키체인 접근에서 자체 서명 인증서를 만들어 그 인증서로 서명한다.
- 서명·공증 없는 앱은 처음 열 때 “확인되지 않은 개발자” 경고가 뜬다. 다른 사람에게 배포하려면 Apple 개발자 프로그램 서명과 공증이 필요하다.
- 시스템 메뉴 막대와 위젯 색은 실제 시스템 배경화면을 따른다(4.9가 이를 보완).
- 바탕화면 층 창의 정확한 층 값과 동작은 macOS 버전마다 다를 수 있어 M1에서 실제로 확인한다.
