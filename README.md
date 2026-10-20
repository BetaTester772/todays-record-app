# 오늘의 판 (Today's Record)

A macOS menu bar app that turns your desktop into a record player for whatever is playing in **Apple Music** or **Spotify**.

The record spins, the tonearm moves inward as the song plays and leaves a trail in the album's colors, and a tiny character rides on the needle. Albums are split into LP sides, so the next song on the same side just moves the needle, and a new side or album swaps the record.

- Sits on the desktop layer: your icons stay on top and clicks pass through
- Album cover, colors, LP sides, volume knob, and time-of-day window light
- Shows on every display (each one can be turned off)
- Pauses when the screen is locked, asleep, or covered; 30 fps on battery

## Requirements

- macOS 14 Sonoma or later (Apple Silicon or Intel)
- Apple Music or Spotify for Mac

## Install

1. Download `TodaysRecord-<version>.zip` from [Releases](https://github.com/soysaucecrab/todays-record-app/releases) and unzip it.
2. Move **TodaysRecord.app** to your **Applications** folder.
3. Open it. A record icon appears in the menu bar.

### First launch: "Apple could not verify…"

The app is not notarized by Apple (it is ad-hoc signed), so macOS blocks it the first time you open it. To allow it once:

1. Open the app. When the warning appears, click **Done** (or **OK**).
2. Open **System Settings → Privacy & Security**.
3. Scroll down to the message about TodaysRecord and click **Open Anyway**.
4. Confirm with **Open Anyway** again and enter your password if asked.

After this, the app opens normally.

<details>
<summary>Alternative: Terminal</summary>

```bash
xattr -dr com.apple.quarantine /Applications/TodaysRecord.app
```

This removes the "downloaded from the internet" mark so macOS no longer blocks it. Only do this for apps you trust.
</details>

### Allow access to Music or Spotify

The first time a song plays, macOS asks whether **TodaysRecord** may control **Music** (or **Spotify**). Click **Allow**. The app only reads what is playing; it never starts, stops, or changes your music, and it never opens Music or Spotify by itself.

If you clicked **Don't Allow**, turn it on in **System Settings → Privacy & Security → Automation → TodaysRecord**, or use **Allow Control of …** in the app's menu.

## Updates

The app checks GitHub for a new release once a day. When one is out, **Update to v…** appears in the menu (and in **Settings → General**). Click it, then **Update**: the app downloads the new version, checks it, replaces itself, and restarts. You can turn automatic checks off or use **Check Now** in **Settings → General**.

Keep the app in **Applications** so it can update itself. If you open it straight from Downloads, the app offers to move itself there. If it needs permission to write to Applications, macOS asks for your password. If an update fails, the app tells you why and links to the download page.

Updates installed this way don't need **Open Anyway** again. From 0.4.0 on, releases are signed with the same certificate, so macOS also keeps your Music/Spotify permission across updates.

## Using it

Click the record icon in the menu bar:

| Menu | |
|---|---|
| Now playing | The song shown on the record |
| Player | Choose Music or Spotify when both are running |
| Show Wallpaper | Turn the record on or off |
| Clear This Record | Erase the lines on the current record |
| Settings… (⌘,) | Open the settings window |
| Check for Updates… | Check for a new version now |
| Update to v… | Shown when a new version is available |

**Settings**

- **General**: Show Wallpaper, Open at Login, Frame Rate (Auto uses 30 fps on battery), Clear This Record, automatic update checks
- **Displays**: choose which displays show the record
- **Appearance**: record position, transparent background, **Colored Vinyl** (the record takes the album's main color), record / background / line / text colors (from the album or your own), tonearm and arm base colors, and the rider's shirt and pants. Each color is **Album** (or **Default**) until you pick **Custom**; **Reset Colors** puts them all back.
- **Effects**: window light that follows the time of day, line trail (keep or afterglow), grain, side change, and **Crowd**: the longer the music plays, the more little friends drop by to dance, read, doze, take calls, play and run on the record (**Crowd Pace** speeds it up)
- **Players**: permission status for Music and Spotify

## Troubleshooting

**Nothing shows on the desktop.** Check **Show Wallpaper** in the menu, and that the display is on in **Settings → Displays**.

**It doesn't show on my external display.** Turn the display on in **Settings → Displays**. The list updates when you plug a display in.

**The song doesn't appear.** Make sure Music or Spotify is playing, then check **Settings → Players**. If it says *Not Allowed*, click **Open Automation Settings…** and turn TodaysRecord on. If the switch is missing, quit the app and play a song again to get the prompt back, or reset the permission in Terminal and reopen the app:

```bash
tccutil reset AppleEvents com.todaysrecord.app
```

**Songs from Apple Music streaming don't split into LP sides.** Music doesn't report track numbers for songs that aren't in your library, so the app looks the album up in the iTunes catalog. If it can't find the same edition, the record still plays, just without sides.

**An update fails or only opens the download page.** Versions before 0.4.2 can't update themselves when they run from Downloads. Quit the app, move **TodaysRecord.app** to **Applications**, open it again, and use **Check for Updates…**. Or download the new zip and replace the app by hand.

**Open at Login doesn't stick.** Keep the app in the Applications folder, and check **System Settings → General → Login Items**.

**Uninstall.** Quit the app, delete it from Applications, and optionally remove its settings:

```bash
defaults delete com.todaysrecord.app
```

## Build from source

Needs Xcode or the Command Line Tools (`xcode-select --install`).

```bash
swift build                     # build
swift test                      # unit tests
scripts/run.sh                  # assemble the .app, install it in /Applications, and run
scripts/install.sh              # assemble, install in /Applications, and open
scripts/run.sh --demo           # run with preview data (no Music needed)
scripts/package.sh              # universal release zip in dist/
```

When you run the app from Terminal with `scripts/run.sh`, macOS attaches the Music/Spotify permission to Terminal instead of the app. To test the app's own permission, use `scripts/install.sh`, which opens the installed app normally. Both scripts sign with the release certificate when it's in your keychain; otherwise each ad-hoc rebuild has a new signature, so macOS may ask for permission again.

Docs: [`docs/SPEC.md`](docs/SPEC.md) (full spec, in Korean) · [`docs/claude-code-guide.md`](docs/claude-code-guide.md) (how this app was built with Claude Code)

---

## 한국어 요약

Apple Music이나 Spotify에서 재생 중인 곡을 바탕화면의 레코드 턴테이블로 보여 주는 macOS 메뉴 막대 앱이에요.

1. [Releases](https://github.com/soysaucecrab/todays-record-app/releases)에서 zip을 받아 풀고, **TodaysRecord.app**을 **응용 프로그램** 폴더로 옮겨요.
2. 처음 열 때 "Apple이 확인할 수 없음" 경고가 뜨면 **완료**를 누르고, **시스템 설정 → 개인정보 보호 및 보안**에서 **그래도 열기**를 눌러요. Apple 공증을 받지 않은 앱이라 한 번만 필요해요.
3. 곡을 틀면 "Music(또는 Spotify)을 제어하려고 합니다" 창이 떠요. **허용**을 눌러요. 앱은 재생 정보를 읽기만 하고, 음악을 바꾸거나 Music·Spotify를 대신 켜지 않아요.
4. 메뉴 막대의 레코드 아이콘 → **Settings…**에서 화면, 색, 효과를 바꿀 수 있어요.
5. 새 버전이 나오면 메뉴에 **Update to v…**가 떠요. 누르면 앱이 알아서 받아 바꾸고 다시 켜져요. 앱이 응용 프로그램 폴더에 있어야 스스로 업데이트할 수 있어요. 다운로드 폴더에서 열면 옮길지 물어봐요.

macOS 14 이상, Apple Silicon과 Intel 모두 지원해요.
