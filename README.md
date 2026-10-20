<div align="center">

# TurnTable

**Your desktop, spinning whatever you're listening to.**

A tiny record player that lives on your Mac's desktop. It plays along with Apple Music and Spotify: the record turns, the needle drifts inward as the song goes on, and little friends drop by the longer you listen.

[![Download](https://img.shields.io/github/v/release/soysaucecrab/todays-record-app?label=Download&style=for-the-badge&color=2D5C48)](https://github.com/soysaucecrab/todays-record-app/releases/latest)

![macOS 14+](https://img.shields.io/badge/macOS-14%2B-black?logo=apple)
![Apple Silicon & Intel](https://img.shields.io/badge/Apple%20Silicon%20%26%20Intel-universal-555)
![Apple Music & Spotify](https://img.shields.io/badge/works%20with-Apple%20Music%20%C2%B7%20Spotify-EE5A36)

<img src="docs/images/hero.jpg" alt="TurnTable on the desktop: a pink and green turntable playing Pink Wheels by The Pink Platters, with little people around it" width="100%">

</div>

<br>

## A record that plays along

The song you're playing becomes a record. Its cover turns into the label and sets the colors of the whole scene, and the needle traces a line in the album's color as the song plays.

<img src="docs/images/detail.jpg" alt="Close-up: the rider on the needle, the line it leaves, the volume dial, the speed dial and the side lamp" width="46%" align="right">

- **Real LP sides.** Albums are split into sides like a real record, up to six songs a side. The next song on the same side just moves the needle; a new side lifts the record and turns it over.
- **A rider on the needle.** A little character sits on the needle all day, swinging their legs to the beat and nodding off when the music stops.
- **Live dials.** The volume dial follows your Mac's volume, the lamps show which side is up, and the info in the corner shows the song, time, side and how many songs you've played today.
- **A record with weight.** It spins up and slows down like a heavy platter, the needle lowers softly, and the record has a slight warp.

<br clear="right">

## Light that follows the day

A window's light falls across the desk and moves with your Mac's clock: peach at dawn, clear at noon, deep orange at sunset, and navy at night.

| | |
|:---:|:---:|
| <img src="docs/images/time-dawn.jpg" alt="Morning light"> | <img src="docs/images/time-noon.jpg" alt="Midday"> |
| **Morning** | **Noon** |
| <img src="docs/images/time-sunset.jpg" alt="Sunset"> | <img src="docs/images/time-night.jpg" alt="Night"> |
| **Sunset** | **Night** |

## Make it yours

Everything follows the album by default. Change only what you want.

| | | |
|:---:|:---:|:---:|
| <img src="docs/images/color-vinyl.jpg" alt="Colored vinyl in the album's teal"> | <img src="docs/images/color-black.jpg" alt="A black record with a gold tonearm"> | <img src="docs/images/color-left.jpg" alt="The record on the left, with the song info on the right"> |
| **Colored Vinyl** in the album's own color | **Black record**, gold tonearm | **Record on the left**, info on the right |

Record, background, line, text, tonearm, arm base and the rider's shirt, pants and hat can each be **Album** (or **Default**) or **Custom**. There's also a transparent background that puts just the turntable over your own wallpaper.

## Friends drop by

The longer the music plays, the more little people show up: the first one a few minutes in, then one every few minutes, up to six. Each one looks different, and each one has their own idea of a good time.

| | | | | |
|:---:|:---:|:---:|:---:|:---:|
| <img src="docs/images/crowd-dance.png" alt="Dancing" width="140"> | <img src="docs/images/crowd-headbang.png" alt="Headbanging" width="140"> | <img src="docs/images/crowd-phone.png" alt="On the phone" width="140"> | <img src="docs/images/crowd-read.png" alt="Reading" width="140"> | <img src="docs/images/crowd-doze.png" alt="Dozing off" width="140"> |
| Dancing | Headbanging | On the phone | Reading | Dozing off |

They also breakdance, swing their feet over the edge of the turntable, play tag, high-five, and **run on the record like a treadmill**. They cheer when a new song starts, and the dozers wake up with a start when the music comes back. When you stop listening they head home one by one, every 30 seconds to a minute. Whoever is still there when you press play again stays.

Too slow to watch? **Crowd Pace** runs them at 2×, 5× or 10×. Prefer a quiet desk? Turn the crowd off.

## Stays out of your way

- **Lives on the desktop layer.** Your icons stay on top, and clicks, right-clicks and drag-selection all go through to the desktop.
- **Every display.** It shows on every screen you connect, and you can turn each one off. It avoids the menu bar and the Dock.
- **Light on your battery.** It stops drawing when the screen is locked, asleep or covered by full-screen apps, and drops to 30 fps on battery.
- **Reads only.** It never starts, stops or changes your music, and it never opens Music or Spotify by itself.
- **Updates itself.** New versions arrive from GitHub with one click, checked and signed.

## Settings

Click the record icon in the menu bar and choose **Settings…** (⌘,).

| | |
|:---:|:---:|
| <img src="docs/images/settings-appearance.png" alt="Appearance settings" width="100%"> | <img src="docs/images/settings-characters.png" alt="Characters settings" width="100%"> |
| **Appearance**: position, background, colors | **Characters**: the rider's pose and colors, the crowd |
| <img src="docs/images/settings-effects.png" alt="Effects settings" width="100%"> | <img src="docs/images/settings-general.png" alt="General settings" width="100%"> |
| **Effects**: window light, trail, grain, side change | **General**: login, frame rate, updates |

**Displays** picks which screens show the record, and **Players** shows the Music and Spotify permission.

The menu itself keeps the everyday things: what's playing, **Player** (when both Music and Spotify are open), **Show Wallpaper**, **Clear This Record**, **Settings…**, **Check for Updates…** and **Quit**.

---

## Install

1. Download **`TurnTable-<version>.zip`** from [Releases](https://github.com/soysaucecrab/todays-record-app/releases/latest) and unzip it.
2. Move **TurnTable.app** to your **Applications** folder. (If you open it from Downloads, it offers to move itself.)
3. Open it. A record icon appears in the menu bar.

**First launch: "Apple could not verify…"** TurnTable isn't notarized by Apple, so macOS asks once:

1. Open the app. When the warning appears, click **Done**.
2. Open **System Settings → Privacy & Security**, scroll down to the message about TurnTable, and click **Open Anyway**.
3. Confirm with **Open Anyway** and enter your password if asked.

<details>
<summary>Or use Terminal</summary>

```bash
xattr -dr com.apple.quarantine /Applications/TurnTable.app
```

This removes the "downloaded from the internet" mark. Only do this for apps you trust.
</details>

**Allow access to Music or Spotify.** The first time a song plays, macOS asks whether TurnTable may control Music (or Spotify). Click **Allow**. TurnTable only reads what's playing.

## Updates

TurnTable checks GitHub once a day. When a new version is out, **Update to v…** appears in the menu. Click it, then **Update**: it downloads the new version, checks its checksum and signature, replaces itself and restarts. Your settings and Music/Spotify permission stay.

Keep the app in **Applications** so it can update itself. If writing there needs permission, macOS asks for your password. If an update fails, the app tells you why.

**Coming from 오늘의 판 (0.4.x)?** TurnTable used to be called 오늘의 판 (TodaysRecord.app). Update as usual: the app renames itself to TurnTable.app and keeps your settings, permission and Open at Login.

<details>
<summary><b>Troubleshooting</b></summary>

**Nothing shows on the desktop.** Check **Show Wallpaper** in the menu, and that the display is on in **Settings → Displays**.

**The song doesn't appear.** Make sure Music or Spotify is playing, then check **Settings → Players**. If it says *Not Allowed*, click **Open Automation Settings…** and turn TurnTable on. If the switch is missing, reset the permission and reopen the app:

```bash
tccutil reset AppleEvents com.todaysrecord.app
```

**Apple Music streaming songs don't split into sides.** Music doesn't report track numbers for songs that aren't in your library, so TurnTable looks the album up in the iTunes catalog. If it can't find the same edition, the record still plays, just without sides.

**An update only opens the download page.** Versions before 0.4.2 can't update themselves when they run from Downloads. Move the app to **Applications**, open it again, and choose **Check for Updates…**, or download the new zip and replace the app.

**Open at Login doesn't stick.** Keep the app in Applications and check **System Settings → General → Login Items**.

**Uninstall.** Quit the app, delete it from Applications, and if you like, remove its settings:

```bash
defaults delete com.todaysrecord.app
```
</details>

<details>
<summary><b>Build from source</b></summary>

Needs Xcode or the Command Line Tools (`xcode-select --install`). No third-party dependencies: Swift, AppKit, WebKit and a single HTML canvas.

```bash
swift build                     # build
swift test                      # unit tests
scripts/install.sh              # assemble, install in /Applications and open
scripts/run.sh                  # same, then run it from Terminal (logs in the terminal)
scripts/run.sh --demo           # preview albums, no Music needed
scripts/run.sh --settings=Characters   # open a settings tab at launch
scripts/package.sh              # universal release zips in dist/
```

Running from Terminal attaches the Music/Spotify permission to Terminal instead of the app; `scripts/install.sh` opens the installed app normally. Both sign with the release certificate when it's in your keychain.

The turntable is drawn in [`Resources/index.html`](Resources/index.html) and the crowd in [`Resources/crowd.js`](Resources/crowd.js). Docs: [`docs/SPEC.md`](docs/SPEC.md) (full spec, in Korean) · [`docs/claude-code-guide.md`](docs/claude-code-guide.md) (how this app was built with Claude Code).
</details>

<sub>The albums in these pictures are TurnTable's built-in preview albums, made up for the app.</sub>
