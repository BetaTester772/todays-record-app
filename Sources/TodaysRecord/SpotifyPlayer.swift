import Foundation

/// Spotify 상태 묻기와 해석. 명세 4.5.1.
final class SpotifyPlayer: Player {
    let kind = PlayerKind.spotify
    private let logToStdout: Bool
    private let statusScript: AppleScriptRunner

    init(logToStdout: Bool) {
        self.logToStdout = logToStdout
        statusScript = AppleScriptRunner(label: "Spotify", source: Self.statusSource, logToStdout: logToStdout)
    }

    func status(running: Bool) -> PlayerStatus {
        guard running else {
            if logToStdout { stdout("[Spotify] 꺼져 있어 묻지 않음") }
            return .info(.stopped)
        }
        switch statusScript.run() {
        case .error(let code):
            return code == AppleScriptRunner.notAuthorized ? .notAuthorized : .failed
        case .output(let output):
            let text = output.stringValue ?? ""
            if logToStdout { stdout("[Spotify] \(text.replacingOccurrences(of: fieldSeparator, with: " | "))") }
            return .info(Self.parse(text))
        }
    }

    /// Spotify는 커버 바이트를 주지 않고 주소만 준다.
    func artwork(for info: NowPlayingInfo, running: Bool, completion: @escaping (Data?) -> Void) {
        guard let url = info.artworkURL else {
            completion(nil)
            return
        }
        ITunesSearch.download(url, completion: completion)
    }

    static func parse(_ output: String) -> NowPlayingInfo {
        guard !output.isEmpty, output != "notrunning", output != "stopped" else { return .stopped }
        var fields = output.components(separatedBy: fieldSeparator)
        fields += Array(repeating: "", count: max(0, 11 - fields.count))
        let (st, name, artist, album, albumArtist, dur, pos, id) =
            (fields[0], fields[1], fields[2], fields[3], fields[4], fields[5], fields[6], fields[7])

        var info = NowPlayingInfo()
        info.state = st == "playing" ? .playing : .paused
        info.title = name
        info.artist = artist
        info.album = album
        info.albumArtist = albumArtist
        // 사전에는 초로 적혀 있지만 밀리초로 온다(2026-10 확인).
        info.duration = parseNumber(dur) / 1000
        info.position = parseNumber(pos)
        info.id = id.isEmpty ? "\(name)|\(artist)|\(album)" : id
        info.trackNumber = Int(parseNumber(fields[8]))
        info.discNumber = Int(parseNumber(fields[9]))
        if let url = URL(string: fields[10]), url.scheme == "https" {
            info.artworkURL = url
        }
        info.isAd = id.hasPrefix("spotify:ad:")
        return info
    }

    // Spotify를 스스로 실행시키지 않는다. 곡 수, 디스크 수, BPM은 사전에 없다.
    // 구분자는 tell 블록 밖에서 만든다(Spotify 사전의 id와 겹치지 않게).
    private static let statusSource = """
    if application "Spotify" is running then
      set sep to character id 31
      tell application "Spotify"
        set pstate to player state as string
        if pstate is "stopped" then return "stopped"
        try
          set t to current track
        on error
          return "stopped"
        end try
        set nm to ""
        set ar to ""
        set al to ""
        set aa to ""
        set du to 0
        set po to 0
        set tid to ""
        set tn to 0
        set dn to 0
        set au to ""
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
          set tid to id of t
        end try
        try
          set tn to track number of t
        end try
        try
          set dn to disc number of t
        end try
        try
          set au to artwork url of t
        end try
        return pstate & sep & nm & sep & ar & sep & al & sep & aa & sep & (du as string) & sep & (po as string) & sep & tid & sep & (tn as string) & sep & (dn as string) & sep & au
      end tell
    else
      return "notrunning"
    end if
    """
}
