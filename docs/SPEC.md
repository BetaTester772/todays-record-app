# TurnTable — macOS 앱 명세서

버전 0.25 · 2026-10-21 (0.2: LP 면 나누기, iTunes 검색 국가 대체 · 0.3: 음량 노브, 면 램프 · 0.4: 색 섞기 전환, 곡 안 위치 이동 · 0.5: 화면 문구 영어 · 0.6: 긴 이름 흐르기 · 0.7: 메뉴 막대·Dock 피하기 · 0.8: 오늘 들은 곡 수만, 노란 강조색 피하기 · 0.9: M2 설정 메뉴, 창문 빛, 잔상 · 0.10: 판 색 고르기, 시간대 색감 · 0.11: 배경색, 선 색 고르기 · 0.12: 그레인 세기 · 0.13: M4 절전, 여러 화면, 그리기 최적화 · 0.14: Spotify 지원 · 0.15: 설정 창, 화면별 켜기, 앱 아이콘 · 0.16: 배포 zip, README · 0.17: M5 뺌 · 0.18: 긴 앨범 LP 세트 · 0.19: 면 바꾸기 동작 · 0.20: 자연스러운 움직임, 글자 색 · 0.21: 앱 안 업데이트, 배포 인증서 · 0.22: 업데이트 설치 자리, 실패 이유, 응용 프로그램 폴더로 옮기기 · 0.23: 컬러 바이닐, 톤암·받침판 색, 색 설정 정리, 이 Mac에 설치 · 0.24: 모여드는 사람들(crowd.js), 받침 높이, 캐릭터 포즈, Characters 탭 · 0.25: 이름을 TurnTable로)

## 1. 개요

Apple Music 또는 Spotify에서 지금 재생 중인 곡을 레코드 턴테이블 그림으로 바탕화면에 보여주는 macOS 메뉴 막대 앱이다. 레코드가 돌고, 톤암 바늘이 곡의 진행에 맞춰 판 안쪽으로 이동하며 앨범 색으로 선을 남기고, 바늘 머리에는 작은 캐릭터가 앉아 있다.

화면 그리기는 이미 완성된 `Resources/index.html`(HTML5 Canvas)을 그대로 쓴다. 이 앱이 새로 만드는 것은 그 화면을 바탕화면 층에 띄우고, Music과 Spotify 앱의 재생 정보를 읽어 화면에 넘겨주는 macOS 쪽 부분이다.

### 목표

- 설치 후 터미널이나 별도 앱(Plash 등) 없이 앱 하나로 동작한다.
- 바탕화면 아이콘과 위젯을 가리지 않고, 클릭을 방해하지 않는다.
- 재생하지 않을 때나 화면이 가려졌을 때는 거의 자원을 쓰지 않는다.

### 범위 밖 (이번 버전에서 하지 않음)

- Music, Spotify 외 플레이어 지원
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
├─ NowPlaying.swift        보여줄 플레이어 고르기, 곡 목록·커버 연결
├─ Player.swift            플레이어 종류(번들 ID, 알림), AppleScript 실행
├─ PlayerChooser.swift     보여줄 플레이어 고르기 규칙 (4.5.2)
├─ MusicPlayer.swift       Music 상태 묻기와 해석
├─ SpotifyPlayer.swift     Spotify 상태 묻기와 해석
├─ Artwork.swift           앨범 커버 가져오기 (플레이어 → 검색 대체)
├─ ITunesSearch.swift      iTunes Search API (커버 검색, 앨범 곡 목록)
├─ AlbumTracks.swift       앨범 디스크별 곡 길이 (LP 면 나누기용)
├─ SystemVolume.swift      시스템 출력 음량 (음량 노브용)
├─ PowerWatcher.swift      잠금, 잠자기, 가려짐 감지
├─ SettingsWindow.swift    설정 창 (SwiftUI 폼을 담은 AppKit 창)
└─ Updater.swift           GitHub 릴리스로 업데이트 확인·설치
Resources/
├─ index.html              레코드 화면 (기존 파일, 6장에 따라 일부 수정)
├─ crowd.js                모여드는 사람들 (6장 25). 없으면 index.html은 사람 없이 그대로 동작
├─ Info.plist              번들 정보
└─ AppIcon.icns            앱 아이콘 (scripts/make-icon.swift로 만든다)
Tests/TodaysRecordTests/    고르기 규칙, 상태 해석, 곡 위치 단위 테스트 (`swift test`)
scripts/
├─ bundle.sh               .app 번들 조립과 애드혹 서명
├─ run.sh                  빌드 후 실행
├─ package.sh              배포용 zip (Universal, 애드혹 서명, SHA-256)
└─ make-icon.swift         앱 아이콘 그리기 (Core Graphics → iconutil)
```

데이터 흐름: Music·Spotify 앱 → `NowPlaying` → `AppDelegate` → 각 `RecordWebView` → `index.html`. 설정 변경은 `StatusMenu` → `Settings` → 각 `RecordWebView`. 절전 상태는 `PowerWatcher` → 각 `RecordWebView`.

## 4. 구성 요소 명세

### 4.1 앱 형태와 실행

- Dock 아이콘 없이 메뉴 막대에만 존재한다 (`Info.plist`의 `LSUIElement = true`).
- 실행 인자
  - `--demo`: Music, Spotify 대신 index.html 내장 미리보기 데이터로 동작 (Music 없이 테스트용)
  - `--log-nowplaying`: 받은 Music·Spotify 알림 내용과 AppleScript 결과를 표준 출력에 기록
  - `--windowed`: 바탕화면 층 대신 일반 창으로 띄워 디버깅 (Safari 웹 속성 검사기로 확인 가능하게 `isInspectable = true`)
  - `--settings`: 시작할 때 설정 창을 연다 (디버깅용). `--settings=Appearance`처럼 탭 이름을 붙이면 그 탭을 연다
  - `--install-update`: 시작하자마자 업데이트를 확인하고, 새 버전이 있으면 묻지 않고 설치한다 (업데이트 시험용)

### 4.2 바탕화면 층 창 (`WallpaperWindow`)

- 테두리 없는 `NSWindow`(`styleMask: .borderless`), 해당 화면 전체 크기.
- 창 층: `CGWindowLevelForKey(.desktopWindow)`. 바탕화면 그림 위, Finder 아이콘 아래에 와야 한다. 아이콘이 가려지면 층 값을 조정한다.
- `collectionBehavior`: `.canJoinAllSpaces`, `.stationary`, `.ignoresCycle`, `.fullScreenNone`
- `ignoresMouseEvents = true` (아이콘 클릭, 바탕화면 우클릭, 드래그 선택이 그대로 동작해야 함)
- `isOpaque`, `backgroundColor`: 투명 배경 설정(4.6)에 따라 바뀐다. 투명일 때 `isOpaque = false`, `backgroundColor = .clear`.
- `hasShadow = false`, `isReleasedWhenClosed = false`
- 창은 키 윈도우나 메인 윈도우가 되지 않는다.

### 4.3 화면 관리 (`WallpaperController`)

- 기본은 연결된 **모든 화면**에 띄운다. 설정 창에서 화면마다 끌 수 있고, 끈 화면은 `disabledDisplays`(화면 UUID를 쉼표로 이은 문자열)에 저장한다. UUID는 `CGDisplayCreateUUIDFromDisplayID`로 얻어, 모니터를 다시 연결해도 끈 상태를 기억한다. (0.15에서 `displays` main/all 설정을 대신함. 처음에는 기본이 주 화면만이라 확장 모니터에 뜨지 않았다.)
- 화면 순서는 메뉴 막대가 있는 화면(`NSScreen.screens[0]`)부터다. `NSScreen.main`은 키 창이 있는 화면이라 쓰지 않는다. 띄우는 화면 중 첫 번째가 `primary`다(주 화면을 끄면 다음 화면이 primary가 된다).
- 화면 식별자(`NSScreenNumber`)마다 창과 웹뷰를 하나씩 둔다. 화면 설정이 바뀌면 새 화면에는 창을 만들고, 빠진 화면의 창은 닫고, 남은 창은 크기와 여백을 맞춘다. 주 화면이 바뀌어 역할(primary/mirror)이 달라진 창은 역할이 문서 시작 때 정해지므로 닫고 다시 만든다. `--windowed`에서는 주 화면에 하나만 띄운다.
- `NSApplication.didChangeScreenParametersNotification`을 받으면 창을 다시 만들거나 크기를 맞춘다.
- 띄우는 화면이 여럿이면 primary 하나만 `role = primary`, 나머지는 `mirror`. 기록 저장은 primary만 한다(6장).
- 화면마다 `frame`과 `visibleFrame`의 차이로 메뉴 막대와 Dock이 덮는 가장자리(top, right, bottom, left, 포인트)를 구해 `TodaysRecord.setInsets`로 보낸다. 웹뷰가 준비될 때와 화면 설정이 바뀔 때(Dock 위치·크기 변경 포함) 보낸다. `--windowed`에서는 0이다.

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

Music과 Spotify의 재생 정보를 플레이어마다 다음 두 가지 방법을 합쳐서 얻고, 그중 보여줄 플레이어 하나의 상태만 웹뷰와 메뉴에 보낸다(4.5.2). 아래 (1)~(3)은 Music 기준이고, Spotify의 다른 점은 4.5.1에 적는다.

**(1) 분산 알림.** `DistributedNotificationCenter`에서 이름 `com.apple.Music.playerInfo`를 구독한다. 곡 변경, 재생, 일시정지, 정지 때 온다. `userInfo`에 곡 이름, 아티스트, 앨범, 재생 상태, 전체 시간, 영구 ID 등이 들어 있다. 정확한 키 이름은 `--log-nowplaying`으로 실제 값을 찍어 확인한 뒤 확정한다.

**(2) AppleScript.** 알림에 없는 정보(현재 재생 위치, 앨범 아티스트, BPM, 곡 번호·곡 수·디스크 번호·디스크 수, 앨범 커버)와 앱 시작 시점의 상태는 `NSAppleScript`로 묻는다. 참고 구현은 `reference/nowplaying.py`의 `STATUS_SCRIPT`, `ART_SCRIPT`에 있다.
- Music이 실행 중이 아니면 절대 실행시키지 않는다. 메인 스레드에서 `NSWorkspace.shared.runningApplications`에 번들 ID `com.apple.Music`이 있을 때만 묻는다. `NSRunningApplication.runningApplications(withBundleIdentifier:)`는 다른 앱이 종료되는 순간 실행 중인 앱을 빠뜨릴 때가 있어(2026-10 확인, 6번 중 2번) 쓰지 않는다.
- AppleScript는 메인 스레드를 막지 않도록 별도 직렬 큐에서 실행한다.
- 언제 묻는가: 앱 시작 시 실행 중인 플레이어마다 1번, 알림을 받을 때마다 그 플레이어만 1번, 보여주는 플레이어가 재생 중이면 위치 보정을 위해 그 플레이어만 10초마다 1번. 1초마다 묻지 않는다.
- 숫자는 지역 설정에 따라 소수점이 쉼표일 수 있으니 문자열로 받으면 `,`를 `.`로 바꿔 해석한다.
- macOS 27의 Music 사전에서는 `tell application "Music"` 안에서 변수 이름 `st`가 컴파일되지 않는다. 참고 구현의 `st`는 `pstate`로 바꿔 쓴다.

**(3) 앨범 곡 목록.** 곡이 바뀌어 새 앨범이 나오면 iTunes Search API로 그 앨범의 곡 목록(디스크, 곡 번호, 제목, 길이)을 한 번 받아 앨범별로 기억한다(`AlbumTracks`). 찾는 동안 최대 3초까지 새 곡 상태를 보내지 않고 기다리며, 시간이 넘거나 찾지 못하면 목록 없이 보낸다.
- 라이브러리에 없는 스트리밍 곡은 AppleScript의 `track number`, `track count`, `disc number`, `disc count`가 모두 0이다(2026-10 확인). 이때는 곡 목록에서 제목이 같은 곡(없으면 길이가 1초 이내로 같은 곡이 하나뿐일 때 그 곡)으로 곡 번호와 디스크를 정한다. 찾은 곡의 길이가 Music 값과 3초 넘게 다르면 다른 판본의 목록일 수 있으므로 쓰지 않는다.
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
  "id": "영구 ID, Spotify 곡 ID 또는 제목|아티스트|앨범",
  "trackNumber": 3,              // 디스크 안 곡 번호, 없으면 0
  "trackCount": 12,              // 디스크 안 곡 수, 없으면 0
  "discNumber": 1,               // 없으면 0
  "discCount": 1,                // 없으면 0
  "trackDurations": [184.0, ...],// 이 디스크의 곡 길이(초), 곡 번호 순서. 모르면 생략
  "art": "3"                     // 이 곡의 커버가 준비됐을 때만. 커버 버전 문자열
}
```

`fast forwarding`, `rewinding`은 `playing`으로 본다.

**권한.** 플레이어마다 처음 AppleScript를 보내면 macOS가 “Music(Spotify)을 제어하려고 합니다” 권한을 따로 묻는다. `Info.plist`에 `NSAppleEventsUsageDescription`(“Reads the song playing in Music or Spotify to show it on the record.”)을 넣는다. 오류 코드 -1743(권한 없음)을 받으면 그 플레이어를 `stopped`로 보고, 메뉴에 제어 권한 열기 항목을 보여 시스템 설정의 자동화 화면을 연다. 항목 이름은 권한이 없는 플레이어에 따라 “Allow Control of Music…”, “Allow Control of Spotify…”, “Allow Control of Music and Spotify…”로 쓴다.

### 4.5.1 Spotify (`SpotifyPlayer`)

- 번들 ID `com.spotify.client`. 실행 중이 아니면 묻지 않고, 절대 실행시키지 않는다. 스크립트도 `if application "Spotify" is running`으로 감싼다.
- 분산 알림 `com.spotify.client.PlaybackStateChanged`를 구독한다. 재생, 일시정지, 곡 변경 때 바로 온다. `userInfo` 키는 `Name`, `Artist`, `Album`, `Album Artist`, `Track ID`, `Track Number`, `Disc Number`, `Duration`(밀리초), `Playback Position`(초), `Player State`(`Playing`/`Paused`/…), `Has Artwork`, `Play Count`, `Popularity`다(2026-10 확인). Music과 같이 알림은 묻는 계기로만 쓰고 값은 AppleScript로 읽는다.
- AppleScript로 `player state`, `player position`(초)과 `current track`의 `name`, `artist`, `album`, `album artist`, `duration`, `track number`, `disc number`, `id`(`spotify:track:…`), `artwork url`을 묻는다. `duration`은 사전에 초로 적혀 있지만 실제로는 밀리초다(2026-10 확인, Spotify 1.3.5).
- 곡 수, 디스크 수, BPM은 주지 않는다(0). 곡 번호와 디스크는 Spotify 값을 쓰고, 곡 수와 곡 길이는 4.5 (3)의 곡 목록에서 얻는다. 곡 수로 판본을 확인할 수 없으므로, 목록에서 그 번호 곡의 길이가 Spotify 값과 3초 넘게 다르면 목록을 쓰지 않는다.
- 광고(`id`가 `spotify:ad:`로 시작)는 곡으로 치지 않고 화면과 메뉴에 `stopped`로 보낸다. 판 기록과 오늘 들은 곡 수에 들어가지 않는다. 플레이어 고르기(4.5.2)에서는 재생 중으로 보아, 광고 때문에 다른 플레이어로 넘어갔다 돌아오지 않게 한다.
- 팟캐스트 에피소드는 일반 곡처럼 다룬다(앨범 자리에 프로그램 이름).

### 4.5.2 보여줄 플레이어 고르기

플레이어마다 마지막 상태를 기억하고, 그중 하나(보여주는 플레이어)의 상태만 보낸다. 권한이 없거나 꺼진 플레이어는 `stopped`로 본다.

- 처음에는 재생 중인 쪽, 없으면 일시정지 상태인 쪽을 보여준다. 앱 시작 때 둘 다 재생 중이거나 둘 다 일시정지면 어느 쪽이 먼저인지 알 수 없으므로 Music을 보여준다.
- 다른 플레이어가 재생을 시작했을 때(일시정지·정지 → 재생. 재생 중 다음 곡으로 넘어가는 것은 시작이 아님): 보여주는 플레이어가 재생 중이면 무시하고 원래 쪽을 계속 보여준다. 재생 중이 아니면 그쪽으로 넘어간다.
- 보여주는 플레이어가 재생 → 일시정지가 되면, 다른 쪽이 재생 중일 때 그쪽으로 넘어간다.
- 보여주는 플레이어가 `stopped`가 되거나 종료되면, 다른 쪽이 재생 중이거나 일시정지 상태일 때 그쪽으로 넘어간다.
- 둘 다 실행 중이면 메뉴 `Player ▸ Music / Spotify`로 사용자가 고를 수 있다. 고른 플레이어는 위 세 가지 변화가 생길 때까지 그대로 보여준다(재생 중인 쪽이 있어도 일시정지된 쪽을 고를 수 있음). 고른 값은 저장하지 않는다.
- 넘어갈 때는 새 플레이어에게 한 번 더 물어 최신 위치로 보낸다. 곡 ID가 바뀌므로 기존 곡·판 바꾸기 동작(6장 10)이 그대로 쓰인다.

### 4.6 앨범 커버 (`Artwork`)

- 곡 ID가 바뀔 때만 가져온다.
- 1순위: 플레이어가 주는 커버. Music은 AppleScript로 `artwork 1 of current track`의 `raw data`, Spotify는 `artwork url`의 이미지를 받는다.
- 2순위(커버가 없거나 실패): iTunes Search API `https://itunes.apple.com/search?term=<아티스트 앨범>&entity=album&limit=5&country=<국가>`에서 앨범 이름이 같은 결과(없으면 첫 결과)의 `artworkUrl100`에서 `100x100bb`를 `600x600bb`로 바꿔 받는다. 국가 기본값 `KR`, 설정으로 변경 가능.
- 앨범 찾기는 먼저 `entity=song`, `term=<아티스트 제목>`으로 하고(스트리밍 곡의 앨범은 앨범 검색에 잘 걸리지 않음), 못 찾으면 위의 앨범 검색을 쓴다. 앨범 이름과 곡 제목이 같은 결과를 먼저 고른다. 앨범 이름은 대소문자와, iTunes가 싱글·EP 이름 끝에 붙이는 ` - Single`, ` - EP`를 무시하고 비교한다(Spotify 앨범 이름에는 붙지 않는다. 2026-10 확인: `アイドル` ↔ `アイドル - Single`).
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
- 창이 완전히 가려짐 (`NSWindow.didChangeOcclusionStateNotification`, 창별로 판단. 이 창만 멈춘다)
- 사용자가 메뉴에서 끔

배터리 사용 중이면 초당 프레임을 30으로 제한한다(설정 `fps`가 `auto`일 때). 전원은 IOKit 공개 API(`IOPSCopyPowerSourcesInfo`, `IOPSGetProvidingPowerSourceType`)로 읽고 `IOPSNotificationCreateRunLoopSource`로 바뀔 때 받는다. 설정 `fps`는 `auto`(기본), `30`, `60`이다.

잠자기·잠금으로 전체가 멈춘 동안에는 Music 위치 확인(10초마다)도 쉬고, 풀리면 바로 한 번 묻는다.

### 4.8 메뉴 막대 (`StatusMenu`)와 설정 창 (`SettingsWindow`)

아이콘은 작은 레코드 모양의 템플릿 이미지(SF Symbols `opticaldisc`). 메뉴에는 자주 쓰는 동작만 둔다.

| 메뉴 항목 | 동작 |
|---|---|
| 지금 재생 중인 곡 (비활성 텍스트) | 제목 — 아티스트 표시. 없으면 “Nothing Playing” |
| Player ▸ Music / Spotify | 둘 다 실행 중일 때만 표시. 보여줄 플레이어를 고른다(4.5.2) |
| Show Wallpaper (체크) | 창 표시 여부 |
| Clear This Record | `clearRecord()` |
| Settings… (⌘,) | 설정 창을 연다 |
| Check for Updates… | 바로 업데이트를 확인한다. 새 버전이면 설치를 묻고, 최신이면 알린다(4.10) |
| Update to vX… | 새 버전이 있을 때만 표시(4.10) |
| 제어 권한 열기 (“Allow Control of Music…” 등, 4.5) | 권한이 없는 플레이어가 있을 때만 표시 |
| Quit | 앱 종료 |

나머지 설정은 **설정 창**에서 한다. macOS 설정 창처럼 창 위쪽 도구 막대의 아이콘 탭을 누르면 아래 내용이 바뀐다(`NSTabViewController`의 `.toolbar` 스타일, 창 `toolbarStyle = .preference`). 각 탭 내용은 SwiftUI `Form`(grouped)을 `NSHostingController`로 담고, 탭마다 창 높이를 내용에 맞춘다(`sizingOptions = .preferredContentSize`). 메뉴 막대 앱이라 창을 열 때만 앱을 앞으로 가져온다.

| 탭 | 항목 |
|---|---|
| General | Show Wallpaper, Open at Login (`SMAppService.mainApp` 등록/해제), Frame Rate(Auto / 30 / 60, 4.7. Auto는 배터리일 때 30), Clear This Record, Check for Updates Automatically와 버전·Check Now·업데이트 버튼(4.10) |
| Displays | 연결된 화면마다 켜기/끄기 (4.3). 화면이 바뀌면 목록을 다시 읽는다 |
| Appearance | Record Position(Left / Center / Right), Background(Default / Transparent). 그 아래 **Colors** 묶음 하나에 색을 모은다(6장 21): Record(Album / Colored Vinyl / Contrast Vinyl / Custom), Background·Text(Album / Custom), Line(Album / Contrast / Custom), Tonearm·Arm Base(Default / Custom). 기본은 지금 색 그대로이고, Custom일 때만 오른쪽에 색 상자가 보인다. Custom을 처음 고르면 미리 정한 색(판 검정, 배경 크림 등)에서 시작한다. Reset Colors는 모두 기본으로 되돌린다(바꾼 것이 없으면 비활성) |
| Effects | Window Light(6장 19), Trail(Keep / Afterglow, 6장 20), Grain(Off / Low / Normal / High), Side Change(Lift & Turn / Swap Record / Needle Only, 6장 23), Album Change(Swap Record / Slide Over, 6장 28) |
| Characters | Rider(바늘 위 캐릭터): Pose(Auto / Sit / Lean Back / Cross-Legged / Hug Knees, 6장 27). Rider Colors(따로 아래 칸): Shirt·Pants(Album / Custom), Hat(Default / Custom), Reset Colors. Crowd: Crowd(켜기/끄기, 기본 켬), Crowd Pace(1× / 2× / 5× / 10×, 6장 25) |
| Players | Music·Spotify 제어 권한 상태와 자동화 설정 열기 |

설정은 `UserDefaults`에 저장한다(키 `enabled`, `position`, `transparent`, `windowLight`, `trail`, `grain`, `sideChange`, `albumChange`, `coloredVinyl`, `vinylStyle`, `lineStyle`, `crowd`, `crowdPace`, `riderPose`, `hatColor`, `recordColor`, `bgColor`, `lineColor`, `textColor`, `armColor`, `armBaseColor`, `shirtColor`, `pantsColor`, `disabledDisplays`, `fps`). 설정 창은 `@AppStorage`로 같은 키(`Settings.Key`)에 바로 쓰고, 앱은 `UserDefaults.didChangeNotification`을 받아 한 번에 모아 창과 모든 웹뷰에 반영한다(`setOptions`). 앱 시작 시와 웹뷰가 준비될 때도 적용한다. 화면과 메뉴 문구는 영어로 쓴다. 로그인 항목이 사용자 승인을 기다리는 상태(`requiresApproval`)면 시스템 설정의 로그인 항목 화면을 연다.

**앱 아이콘.** `scripts/make-icon.swift`가 앱 화면과 같은 색(분홍 배경, 초록 받침, 크림색 판, 초록 라벨, 주황 바늘)으로 macOS 아이콘 격자(1024 안 824 둥근 사각형)에 그려 `iconutil`로 `Resources/AppIcon.icns`를 만든다. `Info.plist`의 `CFBundleIconFile`이 가리킨다.

### 4.10 업데이트 (`Updater`)

- 설정 `autoUpdateCheck`(기본 켜짐)면 앱 시작 10초 뒤와, 그 뒤 마지막 확인에서 24시간이 지날 때마다 `https://api.github.com/repos/soysaucecrab/todays-record-app/releases/latest`를 확인한다(메인 스레드 밖, 마지막 확인 시각은 `lastUpdateCheck`). 설정 창 General의 **Check Now**로 바로 확인할 수도 있다.
- 태그(`v0.4.0`)를 숫자 단위로 지금 버전(`CFBundleShortVersionString`)과 비교해, 새 버전이면 메뉴에 “Update to v0.4.0…”, 설정 창에 업데이트 버튼을 보인다.
- 누르면 확인 창(Update / Later / Release Notes)을 띄우고, Update면: 릴리스의 `TurnTable-<버전>.zip`과 `TurnTable-<버전>.sha256`(없으면 옛 이름 `TodaysRecord-<버전>.zip`과 `.zip.sha256`)을 받아 SHA-256을 맞춰 보고 → `ditto`로 풀고 → 번들 ID가 같은지, 서명이 정상인지 확인하고 → **지금 앱이 인증서로 서명돼 있으면 새 앱도 같은 designated requirement(같은 인증서)를 만족하는지** 확인한 뒤(`SecStaticCodeCheckValidity`) → 설치할 자리에 바꿔 넣고 → 지금 앱이 끝나면 새 앱을 연다.
- 설치할 자리: 지금 앱 자리에 쓸 수 있고 App Translocation(경로에 `/AppTranslocation/`, 다운로드한 앱을 옮기지 않고 열면 macOS가 읽기 전용 임시 자리에서 실행함) 중이 아니면 지금 자리(`FileManager.replaceItemAt`로 원자적으로 바꿈). 아니면 `/Applications/TurnTable.app`. 옛 이름 앱(`TodaysRecord.app`)은 같은 폴더에 `TurnTable.app`으로 설치하고 옛 앱은 휴지통으로 보낸다. 그 자리에 쓸 권한이 없으면 `NSAppleScript`의 `do shell script … with administrator privileges`로 macOS 관리자 암호 창을 띄워 `rm -rf` 후 `ditto --noqtn`으로 넣는다. 암호 창에서 취소하면(-128) 취소로 본다.
- 어느 단계든 실패하면 아무것도 바꾸지 않고, 실패 이유(받기 실패, 체크섬 다름, 서명 다름, 쓸 권한 없음 등)를 알림 창으로 보여 준다(Open Download Page / OK). 릴리스 페이지를 말없이 열지 않는다.
- 앱 시작 때 App Translocation 중이거나 `~/Downloads` 안에서 실행 중이면 “Move TurnTable to the Applications folder?”(Move to Applications / Not Now)를 묻는다. 옮기면 `/Applications`에 넣고(필요하면 관리자 암호), 원래 자리의 앱은 휴지통으로 보낸 뒤(Translocation이면 원본을 모르므로 그대로 둠) 새 자리에서 다시 연다.
- **이름 바꾸기(0.25, TurnTable).** 화면에 보이는 이름(`CFBundleName`, `CFBundleDisplayName`, 메뉴·창·알림 문구)과 앱 파일 이름을 TurnTable로 바꿨다. 번들 ID, 실행 파일 이름(`TodaysRecord`), UserDefaults 영역, 저장소 이름은 그대로다.
  - 릴리스에는 `TurnTable-<버전>.zip`과 `TurnTable-<버전>.sha256`, 그리고 0.4.x 앱용 `TodaysRecord-<버전>.zip`과 `.zip.sha256`(안의 앱 폴더 이름만 `TodaysRecord.app`, 같은 서명)을 함께 올린다. 0.4.x 업데이트 코드는 `TodaysRecord-`로 시작하는 zip과 처음 보이는 `.zip.sha256`을 쓰므로, 새 체크섬 파일 이름에는 `.zip`을 넣지 않는다.
  - 앱이 시작할 때 자기 파일 이름이 `TodaysRecord.app`이고 그 폴더에 쓸 수 있으며 옆에 `TurnTable.app`이 없으면, `TurnTable.app`으로 이름을 바꾸고 새 자리에서 다시 연다. 다시 열린 앱은 로그인 항목이 켜져 있으면 새 위치로 다시 등록한다(`renamedApp` 표시). `scripts/install.sh`도 옛 앱을 지울 때 이 표시를 남긴다.
- 앱이 직접 받은 파일에는 “인터넷에서 받음” 표시(quarantine)가 붙지 않아, 업데이트 뒤에는 “그래도 열기”가 다시 필요 없다(확인함).

### 4.9 (뺌) 시스템 배경화면 색 맞추기

0.17에서 뺐다(사용자 결정, 필요 없음). 앱은 시스템 배경화면을 바꾸지 않는다. 레코드 화면은 배경화면 위에 창을 덮어 보여 주므로, 메뉴 막대·위젯·잠금 화면은 원래 배경화면 색을 따른다.

## 5. 브리지 계약 (Swift ↔ JavaScript)

### Swift → JavaScript

`evaluateJavaScript`로 호출한다. 문자열은 반드시 JSON 직렬화해서 넘긴다(따옴표, 줄바꿈 이스케이프).

| 호출 | 설명 |
|---|---|
| `TodaysRecord.nowPlaying(payload)` | 4.5의 JSON |
| `TodaysRecord.art(dataURL, version)` | 앨범 커버 |
| `TodaysRecord.setPaused(bool)` | 그리기 멈춤/재개 |
| `TodaysRecord.setOptions({position, transparent, windowLight, trail, fps})` | position: `"left"`, `"center"`, `"right"` · transparent: bool · windowLight: bool · trail: `"keep"` 또는 `"afterglow"` · grain: `"off"`, `"low"`, `"normal"`, `"high"`(기존 세기의 0, 0.45, 1, 1.45배) · sideChange: `"turn"`, `"swap"`, `"needle"`(6장 23) · albumChange: `"swap"`, `"slide"`(6장 28) · coloredVinyl: bool, vinylStyle: `"match"`·`"contrast"`, lineStyle: `"album"`·`"contrast"`(6장 21) · crowd: bool, crowdPace: 1·2·5·10(6장 25) · riderPose: `"auto"`, `"sit"`, `"lean"`, `"cross"`, `"hug"`(6장 27) · hatColor: `"#RRGGBB"` 또는 `""`(기본 흰색) · recordColor, bgColor, lineColor, textColor: `"#RRGGBB"` 또는 `""`(앨범 색) · armColor, armBaseColor: `"#RRGGBB"` 또는 `""`(기본 금속색) · shirtColor, pantsColor: `"#RRGGBB"` 또는 `""`(앨범 색) · fps: 30 또는 60(앱이 설정과 전원에 따라 정해 보낸다) |
| `TodaysRecord.clearRecord()` | 지금 판의 선 지우기 |
| `TodaysRecord.setInsets({top, right, bottom, left})` | 메뉴 막대와 Dock이 덮는 화면 가장자리(4.3) |
| `TodaysRecord.setVolume({level, muted})` | 시스템 음량. level: 0~1(모르면 생략), muted: bool (4.6.1) |

### JavaScript → Swift

`window.webkit.messageHandlers.todaysRecord.postMessage(obj)`

| type | 내용 |
|---|---|
| `ready` | 화면 준비 완료. Swift는 이걸 받은 뒤에 첫 상태와 설정을 보낸다 |
| `log` | `{ type, message }` 디버그용 |

## 6. index.html 수정 사항

기존 동작(브라우저 미리보기, Wallpaper Engine, 로컬 도우미)은 그대로 둔다. 다음을 추가한다.

1. **native 소스.** `window.__TR_NATIVE__`가 있으면 `media.source = 'native'`로 시작하고 미리보기 데이터를 쓰지 않는다. `TodaysRecord.nowPlaying`은 기존 `applyNowPlaying`을 재사용한다. 커버는 `TodaysRecord.art`로 받아 기존 `applyArt` 경로를 쓴다. 준비되면 `ready`를 보낸다.
2. **앱 실행 인자 `--demo`.** Swift가 `__TR_NATIVE__.demo = true`를 넣으면 미리보기 데이터로 동작한다.
3. **멈춤.** `setPaused(true)`면 `requestAnimationFrame` 루프를 멈추고, false면 시간 차이를 건너뛰고 재개한다(멈춘 동안의 시간이 한꺼번에 흐르지 않게).
4. **프레임 제한.** `fps`가 30이면 프레임을 하나 걸러 그린다.
5. **레코드 위치.** `layout()`의 가로 중심을 left ≈ 0.32W, center ≈ 0.5W, right ≈ 0.57W(현재값)로 바꾼다. 곡 정보 표시는 레코드 반대쪽 위에 둔다(left일 때 오른쪽 위, 오른쪽 정렬). 곡 정보는 받침 바깥은 진한 글씨, 받침 위는 밝은 금속색 글씨로 두 번 잘라 그려서, 받침 경계에 걸친 줄도 읽히게 한다.
6. **투명 배경.** transparent면 배경 채우기와 받침(plinth)을 그리지 않고, 레코드·톤암·노브·곡 정보만 그린다. 그레인은 레코드 영역에만 적용하거나 생략한다.
7. **역할.** `role`이 `mirror`면 localStorage에 쓰지 않는다(읽기만).
8. (뺌) palette 메시지. 4.9와 함께 0.17에서 뺐다.
9. 상태 문구: native에서 권한 오류 등으로 stopped일 때 “Play something to drop the needle”을 보여준다(한 줄에 들어가도록 짧게).
10. **LP 면 나누기.** `trackNumber`, `trackCount`가 있으면 실제 LP처럼 디스크를 면으로 나눈다.
    - 한 면에 최대 6곡. 면 수는 `ceil(곡 수 / 6)`, 곡은 앞면부터 고르게 나눈다(2곡 → 1면, 12곡 → 6+6, 13곡 → 5+4+4).
    - 면 하나가 판 하나다(판 키 = 앨범 키 + 디스크 + 면). 면 안에서 곡마다 띠를 나누고, 띠 폭은 `trackDurations`가 있으면 곡 길이 비율, 없으면 같은 폭. 기존 미리보기 데이터의 `bandsFor`와 `beginTrack({band, gaps})`를 그대로 쓴다.
    - 같은 면의 다른 곡이면 바늘만 그 곡의 띠로 옮기고, 같은 앨범의 다른 면이나 다른 앨범이면 기존 판 바꾸기 동작을 쓴다.
    - 같은 앨범의 다른 면은 커버(라벨, 색)를 함께 쓴다.
    - 곡 번호나 곡 수가 없으면 기존 동작(곡 길이를 `SIDE_LEN` 기준으로 이어 그림)을 쓴다.
11. **음량 노브와 면 표시.** 기존 속도 노브, 전원 램프와 같은 모양과 색을 쓴다.
    - 배치: 받침 위 조작부를 모두 판과 같은 중심의 원(반지름 1.22R) 위에 놓는다. 톤암 쪽에서 앞쪽으로 음량 노브(각도 0.78rad) → 속도 노브(1.04) → 전원 램프(1.19) → 면 램프(1.31부터 0.085 간격) 순서다. 기존 속도 노브와 전원 램프의 자리도 이 원으로 옮겼다(사용자 요청).
    - 음량 노브: 속도 노브와 같은 금속 노브. 바늘이 0~100%를 왼쪽 아래에서 오른쪽 아래까지 270도로 가리키고, 둘레의 눈금 점 10개 중 음량만큼을 앨범 색(accent)으로 켠다. 음소거면 눈금을 모두 끈다. 값이 바뀌면 바늘이 부드럽게 따라간다. 미리보기에서는 60%로 보인다.
    - 면 램프: 실제 LP 세트처럼 판 한 장이 앞뒤 두 면이다(A·B, C·D, E·F…). 지금 판의 두 면(면이 홀수면 마지막 판은 하나)만 작은 램프로 두고 지금 면을 앨범 색으로 켠다. A·B·C… 픽셀 글자는 각 램프 바로 바깥(같은 반지름 방향)에 똑바로 세워 쓴다. 판이 두 장 이상이면 램프 뒤에 판 수만큼(최대 6개) 작은 점을 이어 찍고 지금 판의 점을 켠다. Music의 디스크마다 따로 판을 나누고, 다른 디스크도 같은 판 수라고 본다. 정지 중이거나 면을 모르면 그리지 않는다. (0.18: 예전에는 면 수만큼 최대 4개만 그려서 25곡 이상 앨범의 E면부터 램프가 켜지지 않았다.)
    - 곡 정보: 진행 막대 아래에 `Side B · 6/9`(면 글자, 디스크 안의 곡 번호/곡 수. Music의 곡 번호와 같음)을 기존 픽셀 글씨로 쓴다. 판이 두 장 이상이면 ` · LP 3/3`(몇 번째 판/판 수)을 붙인다.
12. **앨범 색 전환.** 판을 바꿀 때 색(배경, 받침, 라벨 등)을 한 번에 바꾸지 않고, 커버가 늦게 왔을 때와 같은 기존 섞기(`targetPal`로 서서히 이동)로 새 앨범 색이 되게 한다. 섞는 속도는 약 1.7초에 거의 다 바뀌도록 늦춘다(`1 - exp(-1.8·dt)`).
13. **곡 안 위치 이동.** 같은 곡에서 위치가 3초 넘게 달라지면(처음으로, 건너뛰기) 바늘을 들어 새 위치로 옮긴다. Music은 위치 이동에 알림을 보내지 않으므로(2026-10 확인) 다음 정기 확인 때 반영된다.

14. **화면 문구 영어.** 상태 문구, 안내 문구, 오늘 들은 곡 수 등 화면의 모든 문구를 영어로 쓴다(Now Playing, Paused, Nothing Playing, Played Today 등). 곡·앨범·아티스트 이름(미리보기 데이터 포함)은 그대로 둔다. 메뉴 막대 메뉴와 권한 설명(`NSAppleEventsUsageDescription`)도 영어로 쓴다.

    - 시간은 `m:ss`, 1시간부터 `h:mm:ss`. 곡 정보가 오른쪽 정렬일 때(레코드 왼쪽) 진행 막대 자리는 곡 길이 형식의 가장 넓은 숫자로 잡아, 숫자가 바뀌어도 막대가 좌우로 움직이지 않는다. 시간 글자는 오른쪽 끝에 맞춘다.
15. **긴 이름 흐르기.** 곡 제목, 아티스트, 앨범 이름이 곡 정보 너비를 넘으면 자르지 않고 옆으로 흐르게 한다. 처음 2초 멈춤 → 끝까지 초당 30px로 이동 → 2초 멈춤 → 되돌아옴을 반복한다. 곡이 바뀌면 처음부터 다시 시작한다. 안내 문구는 한 줄로 쓰도록 곡 정보보다 넓게(화면 너비의 절반, 최대 640px까지) 쓸 수 있고, 그래도 넘으면 자르지 않고 단어 단위로 줄을 바꾼다.

16. **메뉴 막대·Dock 피하기.** `setInsets`로 받은 가장자리를 뺀 영역 안에서 `layout()`을 계산한다(배경 채우기는 화면 전체). 가로 화면의 판 크기 상한은 `0.62H`에서 `0.53H`로 낮춰, 판 앞쪽 원 위의 노브와 면 램프가 늘 보이는 영역 안에 들어오게 한다. 판 중심 높이도 `0.6H`에서 `0.56H`로 올려 Dock 쪽 여유를 더 둔다(0.20). 곡 정보는 원래 자리가 가장자리에 걸릴 때만 안쪽으로 민다.

17. **오늘 들은 곡.** 곡 정보 아래에는 `Played Today N`(오늘 들은 곡 수)만 쓴다. 곡별 색 칸(최대 3줄)은 그리지 않고, 기록 개수 상한(80곡)도 없앤다.
18. **노란 강조색 피하기.** 커버에서 뽑은 강조색(판 위 선, 전원·면 램프, 음량 눈금)의 색상이 노란 계열(약 40~72°)이면 가까운 쪽인 주황(32°)이나 초록(94°)으로 옮긴다. 배경, 받침, 라벨 색은 그대로 둔다.

19. **창문 빛(시간대 조명).** Mac 시계를 기준으로, 네 칸 창문(십자 창틀)을 지난 햇빛이 탁자와 턴테이블 위에 비스듬히 비친다. 키프레임(0·5시 밤, 6.5시 새벽, 9시 아침, 13시 낮, 16.5시 오후, 18.5시 노을, 20시 밤) 사이를 이어서 빛의 색, 세기, 방향(아침 왼쪽 → 저녁 오른쪽), 길이가 바뀐다. 시간대가 한눈에 보이도록 화면 전체에도 색감(multiply)을 입힌다: 새벽 복숭아빛, 낮 없음, 노을 진한 주황, 밤 어두운 남색. 곡 정보 글씨는 색감 위에 그려 늘 읽히게 한다. 빛 조각은 반 해상도 캔버스에 1분마다 다시 그려 두고(가장자리는 여러 겹을 겹쳐 부드럽게, 캔버스 `filter`는 Safari 18 미만에서 지원되지 않아 쓰지 않음) 매 프레임 `screen` 합성으로 얹는다. 투명 배경이면 그리지 않는다.
20. **잔상.** `trail`이 `afterglow`면 판에 쌓인 선 대신, 바늘이 지난 최근 약 1.1초의 점들만 판과 함께 돌며 옅어지는 꼬리로 그린다(반 바퀴 정도). 영구 선 기록은 계속 쌓아 두므로 `keep`으로 바꾸면 다시 보인다. `clearRecord`는 영구 선과 잔상을 모두 지운다.

21. **판·배경·선 색.** 기본은 앨범에서 뽑은 색이고, 값이 있으면 그 색을 쓴다.
    - `recordColor`: 판 색. 판이 어두우면(밝기 0.4 미만) 홈 무늬를 밝은 선으로 그린다.
    - `bgColor`: 턴테이블 주변 배경 색. 배경 밝기에 맞춰 곡 정보 글씨 색을 밝게/어둡게 바꾼다.
    - `lineColor`: 판 위 선과 잔상 색. 이미 그린 선은 그때 색 그대로 남는다.
    - `textColor`: 왼쪽 위 곡 정보 글자 색. 고르면 받침 안팎을 나눠 그리지 않고(6장 5) 모든 줄을 그 색으로 쓴다.
    - `coloredVinyl`(기본 꺼짐, 0.23 사용자 요청): 판을 실제 컬러 바이닐처럼 커버의 주된 색으로 칠한다. 앨범 색(팔레트 `vinyl`)은 배경과 같은 대표 색상에 채도 0.4~0.7, 밝기 0.38~0.52로 만든다. 커버에 색이 거의 없으면(채도 0.25 넘는 중간 밝기 픽셀이 10% 미만) 어두운 판(밝기 0.14)으로 한다. 강조색이 판 색과 겹쳐 선이 안 보일 수 있으므로, 선 색을 고르지 않았으면 판 색의 옅은 색(밝은 판이면 진한 색)으로 선을 그린다. `recordColor`가 있으면 그 색이 먼저다. 확인: C418 *Minecraft - Volume Alpha* → 초록 판, *Volume Beta*(거의 검은 커버) → 어두운 판.
    - `vinylStyle`이 `contrast`(Contrast Vinyl, 사용자 요청)면 컬러 바이닐 색의 색상만 반대로(180°) 돌린 색으로 칠한다(채도·밝기는 같음). 반대 색이라 선은 따로 옅게 하지 않고 강조색 그대로 그린다. 확인: 초록 앨범 → 보라 판, 청록 앨범 → 빨간 판.
    - `armColor`(0.23 사용자 요청): 톤암 색. 기둥, 팔, 균형추, 헤드셸, 바늘을 이 색(그늘진 면은 16% 어둡게)으로 그린다. 노브는 금속색 그대로, 카트리지는 강조색 그대로다. 비어 있으면 기본 금속색.
    - `armBaseColor`(0.23 사용자 요청): 톤암 아래 받침판 색(가운데 원은 받침 색을 18% 섞음). 톤암 색과 따로 고른다. 비어 있으면 기본 금속색.
    - `lineStyle`이 `contrast`(Line ▸ Contrast)면 선을 앨범 강조색의 반대 색상으로 그린다. 노란 계열은 강조색처럼 주황이나 초록으로 옮기고, 판과 밝기 차이가 0.25보다 작으면 판보다 0.3 진하게(밝은 판) 또는 밝게(어두운 판) 해 같은 색 계열 판 위에서도 보이게 한다.
    - `shirtColor`, `pantsColor`(0.23 사용자 요청): 바늘 위 캐릭터의 윗옷(기본 강조색)과 바지(기본 받침 색). 그늘진 쪽은 지금처럼 어둡게 섞는다.
    - 트랙 사이 띠는 밝은 판(밝기 0.8 이상, 기본 판)에서는 지금처럼 흰색 50%를 섞고, 그보다 어두운 판에서는 20%만 섞는다(진한 판에서 흰 고리가 너무 도드라져서).

22. **그리기 최적화.** 그림은 그대로 두고 그리는 방식만 바꾼다. 잘 바뀌지 않는 부분은 화면 밖 캔버스(기기 픽셀)에 한 번 그려 두고, 입력(크기, 배치, 색, 내용)이 바뀔 때만 다시 그린다(`cachedLayer`).
    - 배경 + 받침(그림자 포함)
    - 판의 회전과 무관한 부분: 그림자, 테두리, 판 바탕, 홈 무늬. 판이 들려 움직이는 동안(판 바꾸기)은 직접 그린다. 트랙 사이 띠는 화면 밖 캔버스에서 굵은 선이 끊겨 그려져(macOS 27 WebKit에서 확인) 매 프레임 직접 그린다.
    - 곡 정보: 글자, 진행 칸, 시간, 흐르는 위치, 색, 배치가 바뀔 때만 다시 그린다. 색을 입힌 픽셀 글자도 따로 기억한다.
    - 최적화 전후 같은 시점 그림을 비교해, 정적인 영역의 차이가 없음을 확인했다.

23. **같은 판의 다른 면으로.** 다음 곡이 같은 판의 반대 면(A↔B, C↔D…, 6장 10·11)이면 설정 `sideChange`에 따라 움직인다. 다른 판이나 다른 앨범은 지금처럼 판을 빼고 갈아 끼운다.
    - `turn`(기본, Lift & Turn): 바늘이 쉬는 자리로 가고, 판이 살짝 떠올라(그림자가 커짐) 제자리에서 반 바퀴 더 돌며 판 위의 선과 띠가 새 면 것으로 서서히 섞여 바뀐 뒤, 부드럽게 내려앉고 바늘이 새 곡의 띠로 내려간다(약 2.6초). 반 바퀴는 회전 각도에 직접 더해 끝난 뒤에도 끊기지 않는다. 판을 옆으로 세우는(납작해지는) 뒤집기와 내려앉을 때 튀는 동작은 써 보고 뺐다(사용자 판단).
    - `swap`(Swap Record): 다른 앨범과 같은 판 바꾸기.
    - `needle`(Needle Only): 판은 그대로 두고 바늘만 새 곡의 띠로 옮긴다.

24. **자연스러운 움직임.** 그림은 그대로 두고 움직임만 다듬는다.
    - 회전 시작·멈춤: 판에 무게감을 준다. 임계 감쇠 스프링(ω = 9.5)으로 속도를 바꿔, 가속이 0에서 시작해 넘치지 않고 약 0.5초에 정속의 95%에 닿는다(멈출 때도 같음). 예전에는 지수 접근으로 정속까지 1~2초 걸렸다.
    - 바늘 내리기(큐 레버): 들 때는 빠르게, 내릴 때는 `(1 - t)³`으로 처음보다 끝이 느리게 약 0.8초에 걸쳐 내려와 사뿐히 닿는다(곡 바꾸기 1.7초, 시작 2.1초, 판 바꾸기 2.9초, 반 바퀴 돌리기 3.0초로 늘림). 들기·옮기기·내리기 구간을 서로 겹쳐, 바늘이 위로 → 옆으로 → 아래로 꺾여 움직이지 않고 하나의 호를 그리게 한다. 바늘이 들릴 때 캐릭터가 두 팔을 위로 뻗던 동작과, 바늘이 닿을 때 캐릭터가 흔들리던 동작은 뺐다(사용자 판단).
    - 캐릭터 발 흔들기: 규칙적으로 보이지 않게, 서로 나누어떨어지지 않는 주기의 사인파 몇 개를 섞은 부드러운 값(`wander`)으로 속도(BPM 기준 85~110%)와 폭(0.2~1, 가끔 거의 쉼)이 천천히 바뀌고, 두 발은 정확히 반대로 움직이지 않고 조금씩 엇갈린다.
    - 판의 흔들림(워프): 판 중심이 아주 조금 어긋나 바늘이 한 바퀴에 한 번 안팎으로(판 반지름의 0.35%) 출렁이고, 판이 살짝 휘어 한 바퀴에 두 번 위아래로 움직인다. 회전 속도에 비례하고 바늘이 판 위에 있을 때만 보인다.

25. **모여드는 사람들(`Resources/crowd.js`, 0.24 사용자 요청).** 쉬지 않고 오래 들을수록 작은 사람들이 하나씩 놀러 온다. 움직임 코드가 커서 `index.html`과 나눠 `crowd.js`에 두고, `index.html`은 `TodaysRecordCrowd(scene)`로 만들어 매 프레임 `update`, `draw`를 부른다. `scene`은 화면 상태(크기, 여백, 재생 상태, 판 회전, 판 바꾸기)와 그리기 도구를 읽기 전용으로 넘긴다. 파일이 없으면 사람 없이 그대로 동작한다.
    - 오는 때: 재생 시간이 3~7분(랜덤)일 때 첫 사람, 그 뒤 한 명 올 때마다 3~5분(랜덤) 뒤 다음 사람. 최대 6명. 재생 중에도 사람마다 20~45분(랜덤) 머문 뒤 집에 가고(5분에 한 명까지), 1~3분 뒤 새 사람이 온다. 음악이 멈추거나 정지하면 30초~1분마다 한 명씩 손을 흔들고 화면 밖으로 걸어 나간다. 다시 재생하면 남아 있던 사람은 그대로 있고, 다음 사람은 3~5분(아무도 없으면 3~7분) 뒤에 온다. `crowdPace`(1·2·5·10배)는 사람들 시간 전체를 빠르게 한다: 오고 가는 시간, 걷기, 한 가지 일을 하는 시간, 작은 움직임, 효과. 춤 박자는 음악을 따르고, 판 위에서 뛰는 다리 빠르기는 판의 실제 속도를 따른다(사람들만의 시계 `crowd.clock`). Crowd를 끄면 모두 떠난다. 투명 배경에서는 그리지 않는다.
    - 자리: 책상 위, 받침 위, 받침 왼쪽 가장자리(걸터앉기)에서, 사람 몸 전체가 판, 노브·램프, 톤암과 그 받침, 바늘이 지나는 길, 곡 정보를 가리지 않는 곳만 쓴다. 레코드 위치(left·center·right), 화면 크기, 여백이 바뀌면 자리를 다시 계산하므로 배치마다 보이는 바닥에 선다. 옆으로 가깝고 위아래로 몸 높이보다 가까우면 겹친다고 보고 그런 자리는 고르지 않으며, 그래도 겹쳐 서 있으면 한 명이 옮겨 간다. 판을 가로지르는 길은 판 둘레로 돌아가되, 양쪽 길 중 화면 안에 더 많이 남는 쪽을 고르고 화면 밖으로 나가지 않게 한다. 받침 옆면 위에는 서지 않고, 책상에서 받침으로 갈 때는 화면에서 곧게 걸어 올라가 튀지 않는다.
    - 움직임은 여유롭게: 걸음은 천천히(초당 20u, u는 판 크기에 비례), 한 가지 일을 30초~1분 넘게 하고, 자리 옮기기는 드물다(사용자 요청).
    - 하는 일(재생 중이면 춤 쪽, 멈추면 쉬는 쪽이 많음): 걸어다니기, 가장자리에 걸터앉아 발 흔들기, 춤(세 가지), 헤드뱅잉(4마디마다 손 들기), 비보잉(톱록 → 헤드스핀 → 프리즈), 책 읽기(책장 넘김), 졸기(꾸벅꾸벅, 음악이 다시 나오면 깜짝), 통화(말풍선, 웃음, 서성이기), 서로 놀기(하이파이브, 손잡고 폴짝, 술래잡기), 판 위 달리기, 그냥 서 있기(기지개, 둘러보기, 발 까딱, 컵 마시기). 새 곡이 시작되면 서 있던 사람들이 환호한다.
    - 판 위 달리기: 판 앞쪽이나 뒤쪽(판 표면이 화면에서 좌우로 움직이는 곳, 올라가기 전 자리가 화면 안인 곳)까지 걸어가 같은 걸음 속도로 걸어 올라간 뒤, 러닝머신처럼 판이 도는 반대 방향으로 뛰며 제자리에 있다. 걸어 올라가는 동안과 내려오는 동안에는 판에 실려 도는 방향으로 밀린다(판 속도의 35%). 밀릴 거리만큼 앞에서 올라가 달릴 자리에 닿는다. 다리는 판 표면 속도에 맞춘 느긋한 빠르기(사람이 판보다 빨라 보이지 않게)다. 판이 느려지거나 시간이 다 되면 걸어서 내려오고, 판을 들어 바꾸면 튕겨 나가 구르고 어지러워한다.
    - 다양함: 피부색 6, 머리 모양 9(짧은 머리, 단발, 긴 머리, 포니테일, 똥머리, 곱슬, 모자, 비니, 삐죽), 머리색, 옷·신발 색(일부는 앨범 강조색, 받침·배경과 비슷한 색은 피함), 안경·헤드폰·리본·목도리·가방·주근깨, 키(작은 사람 20%), 걸음 빠르기. 행동을 시작할 때마다 판 쪽이나 아무 쪽을 보고, 서서 하는 일(인사, 춤, 헤드뱅잉, 통화, 서 있기)은 40%쯤 앞(화면 쪽)을 본다. 눈을 깜빡인다. 하트, 음표, z, !, 말풍선, 땀방울, 반짝이 효과.
    - 레코드가 왼쪽이면 오른쪽, 오른쪽이면 왼쪽처럼 화면에서 트인 쪽 자리를 새로 온 사람이 먼저 고른다(자리가 3곳 이상일 때). 걸어 옮길 때도 70%는 트인 쪽으로 간다.
    - 그리는 순서: 판 → 사람(발 위치 순서) → 톤암과 바늘. 톤암 받침판은 받침과 함께 사람 아래에 그린다.
26. **받침 높이.** 받침이 책상보다 조금 높아 보이게, 받침 윗면 아래로 진한 옆면(판 반지름의 0.06)과 더 넓고 부드러운 그림자를 그린다.
    - 톤암 그림자: 팔과 헤드 그림자를 한 도형으로 한 번에 칠해 겹친 곳이 진해지지 않게 한다.
27. **캐릭터 포즈.** 바늘 위 캐릭터는 다리 늘어뜨리고 앉기(기본), 뒤로 기대기, 책상다리, 무릎 껴안기 중 하나로 앉는다. 설정 Pose가 Auto(기본)면 새 곡이 시작될 때 45% 확률로 다른 포즈로, 하나를 고르면 그 포즈로 0.5초에 걸쳐 바뀐다. 윗옷·바지·모자 색은 Characters 탭에서 고른다(`shirtColor`, `pantsColor`, `hatColor`). 박자에 맞춰 위아래로 튀던 동작은 뺐다(사용자 요청).
28. **다른 앨범으로 바꿀 때(`albumChange`, 사용자 요청).** `swap`(기본, Swap Record)은 지금처럼 옛 판을 들어 오른쪽으로 빼고 새 판을 왼쪽에서 가져온다. `slide`(Slide Over)는 바늘이 쉬는 자리로 간 뒤, 두 판이 조금 떠오른 채로 옛 판은 왼쪽으로 빠지고, 조금 뒤(약 0.3초) 새 판이 같은 왼쪽에서 옛 판보다 조금 높이 그 위로 지나 들어와 내려앉는다(각 1초, 곡 바꾸기 전체 2.9초). 옛 판은 바꾸는 순간의 색, 라벨, 선을 그대로 지닌 채 그리고, 새 판은 처음부터 새 앨범 색으로 그린다(배경 색은 평소처럼 서서히 바뀜). 축(스핀들)은 플래터 위 판에만 그린다.

## 7. 성능 목표

- 재생 중 30fps 기준, Apple Silicon에서 활동 모니터 CPU가 낮게 유지될 것(구현 후 측정해서 기록).
- 멈춤 상태에서는 웹 콘텐츠 프로세스 CPU가 거의 0이어야 한다.
- AppleScript 호출은 재생 중에도 10초당 1번 이하(알림 반응 제외).

**측정 기록 (2026-10-20, Apple Silicon, macOS 27, 1008×655 테스트 창, WebKit 웹 콘텐츠 + GPU 프로세스 CPU 합계, `top` 2초 간격 평균)**

| 상태 | 최적화 전 | 최적화 후 |
|---|---|---|
| 60fps | 48% | 18.5% |
| 30fps | 22% | 11.4% |
| 멈춤(`setPaused(true)`) | — | 0.0% |
| 바탕화면이 다른 창에 완전히 가려짐 | 0% (WebKit이 스스로 멈춤) | 0% |

바탕화면 전체(1512×982, 2배 해상도)는 테스트 창보다 픽셀이 많아 이보다 조금 더 쓸 수 있다.

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

**M3.1 Spotify 연결**
- Spotify에서 곡을 틀면 제목, 아티스트, 앨범, 진행 시간, 커버가 반영된다. 광고는 곡으로 표시되지 않는다.
- 둘 다 실행 중이면 메뉴에서 플레이어를 고를 수 있다. 나중에 재생을 시작한 쪽은 무시되고, 보여주던 쪽을 일시정지하면 재생 중인 쪽으로 넘어간다.
- 보여주던 플레이어를 종료하면 다른 쪽으로 넘어가거나 정지로 표시된다.
- Spotify가 꺼져 있을 때 앱이 Spotify를 실행시키지 않는다.
- Spotify 권한을 거부하면 메뉴에 “Allow Control of Spotify…”가 보인다.

**M4. 절전과 여러 화면**
- 잠금, 잠자기, 전체 화면 앱으로 가려질 때 그리기가 멈추고 돌아오면 이어진다.
- 모든 화면 모드에서 모니터를 꽂고 빼도 창이 맞게 다시 생긴다.

**M5. (뺌) 시스템 배경화면 색 맞추기** — 0.17에서 뺐다(사용자 결정).

**M6. 마무리**
- README에 빌드, 설치(/Applications로 복사), 권한, 문제 해결을 적는다.
- 애드혹 서명된 .app을 zip으로 만드는 스크립트.
- (0.16) `scripts/package.sh`: `UNIVERSAL=1 scripts/bundle.sh`로 Apple Silicon + Intel 실행 파일을 조립하고(최소 macOS 14.0 확인), `ditto`로 `dist/TodaysRecord-<버전>.zip`과 `.sha256`을 만든다. 공증하지 않은 애드혹 서명이라 받은 사본은 Gatekeeper가 거부하므로(확인함), README에 “그래도 열기” 절차를 적는다. README는 사용자용(영어 + 한국어 요약)으로 새로 쓰고, 이전의 Claude Code 작업 안내는 `docs/claude-code-guide.md`로 옮긴다. 라이선스 파일은 두지 않는다(사용자 결정).

## 9. 알려진 주의점

- 애드혹 서명은 빌드할 때마다 서명이 바뀌어 Music·Spotify 제어 권한을 다시 물을 수 있다. 그래서 0.4.0부터 배포판은 자체 서명 인증서 “Todays Record Code Signing”(RSA 3072, 2036년까지, 코드 서명 전용)으로 서명한다. 비밀 키는 배포하는 Mac의 로그인 키체인에만 있고 `codesign`만 쓸 수 있으며, 저장소에는 올리지 않는다. 앱은 이름이 아니라 인증서 해시로 구분되므로(designated requirement `certificate root = H"3324a118…"`) 같은 인증서로 서명한 버전끼리는 권한이 유지된다. 인증서를 잃으면 다음 버전에서 사용자가 권한을 다시 허용해야 하므로 `.p12`로 백업해 둔다. `scripts/package.sh`는 이 인증서가 없으면 애드혹으로 서명한다.
- 서명·공증 없는 앱은 처음 열 때 “확인되지 않은 개발자” 경고가 뜬다. 다른 사람에게 배포하려면 Apple 개발자 프로그램 서명과 공증이 필요하다.
- 시스템 메뉴 막대와 위젯 색은 실제 시스템 배경화면을 따른다(레코드 화면과 맞추는 4.9는 뺐다).
- 바탕화면 층 창의 정확한 층 값과 동작은 macOS 버전마다 다를 수 있어 M1에서 실제로 확인한다.
