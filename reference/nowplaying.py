#!/usr/bin/env python3
"""
TurnTable — Apple Music 재생 정보 도우미 (macOS)

Music 앱에서 지금 재생 중인 곡 정보를 AppleScript로 읽어서,
같은 폴더의 index.html(레코드 배경화면)에 로컬 주소로 전달합니다.

    python3 nowplaying.py                  실행 (Ctrl+C로 종료)
    python3 nowplaying.py --install-agent  로그인할 때 자동으로 실행되게 등록
    python3 nowplaying.py --remove-agent   자동 실행 해제

환경 변수
    TODAYS_RECORD_PORT     포트 (기본 8765)
    TODAYS_RECORD_COUNTRY  앨범 커버를 못 찾았을 때 검색할 Apple Music 국가 코드 (기본 KR)
"""
import json
import os
import subprocess
import sys
import tempfile
import threading
import time
import urllib.parse
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

PORT = int(os.environ.get("TODAYS_RECORD_PORT", "8765"))
COUNTRY = os.environ.get("TODAYS_RECORD_COUNTRY", "KR")
HERE = os.path.dirname(os.path.abspath(__file__))
INDEX = os.path.join(HERE, "index.html")
AGENT_LABEL = "com.todaysrecord.nowplaying"
AGENT_PATH = os.path.expanduser(f"~/Library/LaunchAgents/{AGENT_LABEL}.plist")
SEP = "\x1f"

# Reads the player state and current track. Never launches Music on its own.
STATUS_SCRIPT = r'''
if application "Music" is running then
  tell application "Music"
    set st to player state as string
    if st is "stopped" then return "stopped"
    try
      set t to current track
    on error
      return "stopped"
    end try
    set sep to character id 31
    set nm to ""
    set ar to ""
    set al to ""
    set aa to ""
    set du to 0
    set po to 0
    set pid to ""
    set bp to 0
    try
      set nm to name of t
    end try
    try
      set ar to artist of t
    end try
    try
      set al to album of t
    end try
    try
      set aa to album artist of t
    end try
    try
      set du to duration of t
    end try
    try
      set po to player position
    end try
    try
      set pid to persistent ID of t
    end try
    try
      set bp to bpm of t
    end try
    return st & sep & nm & sep & ar & sep & al & sep & aa & sep & (du as string) & sep & (po as string) & sep & pid & sep & (bp as string)
  end tell
else
  return "notrunning"
end if
'''

# Writes the current track's artwork to the path given as the first argument.
ART_SCRIPT = r'''
on run argv
  set outPath to item 1 of argv
  tell application "Music"
    try
      set t to current track
      if (count of artworks of t) is 0 then return "none"
      set d to raw data of artwork 1 of t
    on error
      return "none"
    end try
  end tell
  set fh to open for access (POSIX file outPath) with write permission
  try
    set eof fh to 0
    write d to fh
    close access fh
  on error
    try
      close access fh
    end try
    return "none"
  end try
  return "ok"
end run
'''

WORK = tempfile.mkdtemp(prefix="todays-record-")
STATUS_PATH = os.path.join(WORK, "status.applescript")
ART_PATH = os.path.join(WORK, "art.applescript")
ART_OUT = os.path.join(WORK, "artwork.bin")
with open(STATUS_PATH, "w", encoding="utf-8") as f:
    f.write(STATUS_SCRIPT)
with open(ART_PATH, "w", encoding="utf-8") as f:
    f.write(ART_SCRIPT)

lock = threading.Lock()
now_playing = {"state": "stopped"}
artwork = {"for": None, "ver": "", "bytes": None, "type": "image/png"}
art_counter = 0


def osa(path, *args, timeout=5):
    r = subprocess.run(["osascript", path, *args], capture_output=True, text=True, timeout=timeout)
    if r.returncode != 0:
        raise RuntimeError(r.stderr.strip())
    return r.stdout.rstrip("\n")


def num(s):
    try:
        return float(str(s).strip().replace(",", "."))
    except ValueError:
        return 0.0


def sniff(data):
    if data[:8] == b"\x89PNG\r\n\x1a\n":
        return "image/png"
    if data[:3] == b"\xff\xd8\xff":
        return "image/jpeg"
    return None


def search_artwork(artist, album, title):
    """Fallback for streamed tracks whose artwork Music doesn't expose."""
    term = f"{artist} {album or title}".strip()
    if not term:
        return None
    q = urllib.parse.urlencode({"term": term, "entity": "album", "limit": 1, "country": COUNTRY})
    with urllib.request.urlopen(f"https://itunes.apple.com/search?{q}", timeout=6) as r:
        results = json.load(r).get("results") or []
    if not results:
        return None
    url = results[0].get("artworkUrl100", "").replace("100x100bb", "600x600bb")
    if not url:
        return None
    with urllib.request.urlopen(url, timeout=6) as r:
        return r.read()


def fetch_artwork(track_id, artist, album, title):
    global art_counter
    data = None
    try:
        if os.path.exists(ART_OUT):
            os.remove(ART_OUT)
        if osa(ART_PATH, ART_OUT) == "ok" and os.path.exists(ART_OUT):
            with open(ART_OUT, "rb") as f:
                data = f.read()
    except Exception:
        data = None
    if not data or not sniff(data):
        try:
            data = search_artwork(artist, album, title)
        except Exception:
            data = None
    if not data or not sniff(data):
        return
    with lock:
        if now_playing.get("id") != track_id:
            return
        art_counter += 1
        artwork.update({"for": track_id, "ver": f"{art_counter}", "bytes": data, "type": sniff(data)})


def poll_loop():
    last_id = None
    warned = False
    while True:
        try:
            out = osa(STATUS_PATH)
            if not out or out in ("notrunning", "stopped"):
                data = {"state": "stopped"}
            else:
                st, name, artist, album, album_artist, dur, pos, pid, bpm = (out.split(SEP) + [""] * 9)[:9]
                track_id = pid or f"{name}|{artist}|{album}"
                data = {
                    "state": "playing" if st in ("playing", "fast forwarding", "rewinding") else "paused",
                    "title": name, "artist": artist, "album": album, "albumArtist": album_artist,
                    "duration": num(dur), "position": num(pos), "bpm": num(bpm), "id": track_id,
                }
                if track_id != last_id:
                    last_id = track_id
                    threading.Thread(target=fetch_artwork, args=(track_id, artist, album, name), daemon=True).start()
            with lock:
                now_playing.clear()
                now_playing.update(data)
            warned = False
        except Exception as e:
            msg = str(e)
            if not warned:
                if "-1743" in msg or "Not authorized" in msg:
                    print("\n[권한 필요] 시스템 설정 > 개인정보 보호 및 보안 > 자동화에서"
                          " 이 프로그램(터미널 또는 python3)이 ‘Music’을 제어하도록 허용해 주세요.\n", flush=True)
                else:
                    print(f"[알림] Music 정보를 읽지 못했어요: {msg}", flush=True)
                warned = True
            with lock:
                now_playing.clear()
                now_playing.update({"state": "stopped"})
        time.sleep(1)


class Handler(BaseHTTPRequestHandler):
    def _send(self, code, body, ctype, cache="no-store"):
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", cache)
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        path = urllib.parse.urlparse(self.path).path
        if path in ("/", "/index.html"):
            try:
                with open(INDEX, "rb") as f:
                    self._send(200, f.read(), "text/html; charset=utf-8")
            except OSError:
                self._send(404, "index.html을 같은 폴더에 두어 주세요".encode(), "text/plain; charset=utf-8")
        elif path == "/now":
            with lock:
                data = dict(now_playing)
                if artwork["for"] and artwork["for"] == data.get("id"):
                    data["art"] = artwork["ver"]
            self._send(200, json.dumps(data, ensure_ascii=False).encode("utf-8"), "application/json; charset=utf-8")
        elif path == "/art":
            with lock:
                body, ctype = artwork["bytes"], artwork["type"]
            if body:
                self._send(200, body, ctype, cache="max-age=3600")
            else:
                self._send(404, b"", "text/plain")
        else:
            self._send(404, b"", "text/plain")

    def log_message(self, *args):
        pass


def install_agent():
    plist = f'''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>{AGENT_LABEL}</string>
  <key>ProgramArguments</key>
  <array>
    <string>{sys.executable}</string>
    <string>{os.path.abspath(__file__)}</string>
  </array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>StandardOutPath</key><string>/tmp/{AGENT_LABEL}.log</string>
  <key>StandardErrorPath</key><string>/tmp/{AGENT_LABEL}.log</string>
</dict>
</plist>
'''
    os.makedirs(os.path.dirname(AGENT_PATH), exist_ok=True)
    with open(AGENT_PATH, "w", encoding="utf-8") as f:
        f.write(plist)
    uid = os.getuid()
    subprocess.run(["launchctl", "bootout", f"gui/{uid}", AGENT_PATH], capture_output=True)
    r = subprocess.run(["launchctl", "bootstrap", f"gui/{uid}", AGENT_PATH], capture_output=True, text=True)
    if r.returncode == 0:
        print("자동 실행을 등록했어요. 이제 로그인할 때마다 도우미가 켜져요.")
        print("처음 자동 실행될 때 ‘Music 제어’ 권한 창이 한 번 더 뜰 수 있어요. 허용해 주세요.")
        print(f"기록: /tmp/{AGENT_LABEL}.log")
    else:
        print("등록 파일은 만들었지만 바로 시작하지 못했어요. 다음 명령을 직접 실행해 주세요:")
        print(f"  launchctl bootstrap gui/{uid} {AGENT_PATH}")
        print(r.stderr.strip())


def remove_agent():
    uid = os.getuid()
    subprocess.run(["launchctl", "bootout", f"gui/{uid}", AGENT_PATH], capture_output=True)
    if os.path.exists(AGENT_PATH):
        os.remove(AGENT_PATH)
    print("자동 실행을 해제했어요.")


def main():
    if "--install-agent" in sys.argv:
        install_agent()
        return
    if "--remove-agent" in sys.argv:
        remove_agent()
        return
    threading.Thread(target=poll_loop, daemon=True).start()
    server = ThreadingHTTPServer(("127.0.0.1", PORT), Handler)
    print(f"TurnTable 도우미가 켜졌어요 → http://localhost:{PORT}")
    print("이 주소를 Plash에 추가하면 배경화면이 돼요. 끄려면 Ctrl+C.")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\n도우미를 껐어요.")


if __name__ == "__main__":
    main()
