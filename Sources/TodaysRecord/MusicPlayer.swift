import Foundation

/// Music 상태 묻기와 해석. 명세 4.5.
final class MusicPlayer: Player {
    let kind = PlayerKind.music
    private let logToStdout: Bool
    private let statusScript: AppleScriptRunner
    private let diagnosticScript: AppleScriptRunner
    private let artScript: AppleScriptRunner

    init(logToStdout: Bool) {
        self.logToStdout = logToStdout
        statusScript = AppleScriptRunner(label: "Music", source: Self.statusSource, logToStdout: logToStdout)
        diagnosticScript = AppleScriptRunner(label: "Music 재생 목록", source: Self.diagnosticSource, logToStdout: false)
        artScript = AppleScriptRunner(label: "Music 커버", source: Self.artSource, logToStdout: false)
    }

    func status(running: Bool) -> PlayerStatus {
        guard running else {
            if logToStdout { stdout("[Music] 꺼져 있어 묻지 않음") }
            return .info(.stopped)
        }
        switch statusScript.run() {
        case .error(let code):
            return code == AppleScriptRunner.notAuthorized ? .notAuthorized : .failed
        case .output(let output):
            let text = output.stringValue ?? ""
            if logToStdout {
                stdout("[Music] \(text.replacingOccurrences(of: fieldSeparator, with: " | "))")
                stdout("[Music 재생 목록] \(diagnostics())")
            }
            return .info(Self.parse(text))
        }
    }

    /// --log-nowplaying 전용. 셔플, 반복, 지금 재생 중인 목록과 그 안의 순서.
    private func diagnostics() -> String {
        switch diagnosticScript.run() {
        case .output(let output): return output.stringValue ?? ""
        case .error(let code): return "오류 \(code)"
        }
    }

    func artwork(for info: NowPlayingInfo, running: Bool, completion: @escaping (Data?) -> Void) {
        guard running, case .output(let result) = artScript.run(), result.stringValue != "none" else {
            completion(nil)
            return
        }
        completion(result.data)
    }

    static func parse(_ output: String) -> NowPlayingInfo {
        guard !output.isEmpty, output != "notrunning", output != "stopped" else { return .stopped }
        var fields = output.components(separatedBy: fieldSeparator)
        fields += Array(repeating: "", count: max(0, 13 - fields.count))
        let (st, name, artist, album, albumArtist, dur, pos, pid, bpm) =
            (fields[0], fields[1], fields[2], fields[3], fields[4], fields[5], fields[6], fields[7], fields[8])

        var info = NowPlayingInfo()
        info.state = ["playing", "fast forwarding", "rewinding"].contains(st) ? .playing : .paused
        info.title = name
        info.artist = artist
        info.album = album
        info.albumArtist = albumArtist
        info.duration = parseNumber(dur)
        info.position = parseNumber(pos)
        info.bpm = parseNumber(bpm)
        info.id = pid.isEmpty ? "\(name)|\(artist)|\(album)" : pid
        info.trackNumber = Int(parseNumber(fields[9]))
        info.trackCount = Int(parseNumber(fields[10]))
        info.discNumber = Int(parseNumber(fields[11]))
        info.discCount = Int(parseNumber(fields[12]))
        return info
    }

    // reference/nowplaying.py의 STATUS_SCRIPT를 바탕으로 한다. Music을 스스로 실행시키지 않는다.
    // macOS 27의 Music 사전에서는 tell 블록 안의 변수 이름 st가 컴파일되지 않아 pstate로 바꿨다.
    // LP 면 나누기를 위해 곡 번호, 곡 수, 디스크 번호, 디스크 수를 더 읽는다.
    private static let diagnosticSource = """
    if application "Music" is running then
      tell application "Music"
        set out to ""
        try
          set out to out & "shuffle=" & (shuffle enabled as string)
        end try
        try
          set out to out & " mode=" & (shuffle mode as string)
        end try
        try
          set out to out & " repeat=" & (song repeat as string)
        end try
        try
          set pl to current playlist
          set out to out & " playlist=" & (name of pl) & " kind=" & (class of pl as string)
          try
            set out to out & " special=" & (special kind of pl as string)
          end try
        end try
        try
          set out to out & " index=" & (index of current track as string)
        end try
        return out
      end tell
    end if
    return "notrunning"
    """

    private static let statusSource = """
    if application "Music" is running then
      tell application "Music"
        set pstate to player state as string
        if pstate is "stopped" then return "stopped"
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
        set tn to 0
        set tc to 0
        set dn to 0
        set dc to 0
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
        try
          set tn to track number of t
        end try
        try
          set tc to track count of t
        end try
        try
          set dn to disc number of t
        end try
        try
          set dc to disc count of t
        end try
        return pstate & sep & nm & sep & ar & sep & al & sep & aa & sep & (du as string) & sep & (po as string) & sep & pid & sep & (bp as string) & sep & (tn as string) & sep & (tc as string) & sep & (dn as string) & sep & (dc as string)
      end tell
    else
      return "notrunning"
    end if
    """

    // reference/nowplaying.py의 ART_SCRIPT와 같은 내용. 파일 대신 raw data를 바로 돌려받는다.
    private static let artSource = """
    if application "Music" is running then
      tell application "Music"
        try
          set t to current track
          if (count of artworks of t) is 0 then return "none"
          return raw data of artwork 1 of t
        on error
          return "none"
        end try
      end tell
    end if
    return "none"
    """
}
