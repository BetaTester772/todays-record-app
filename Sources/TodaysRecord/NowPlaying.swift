import AppKit

/// 지금 재생 중인 곡. 명세 4.5의 출력 형식.
struct NowPlayingInfo: Equatable {
    enum State: String {
        case playing, paused, stopped
    }

    var state: State = .stopped
    var title = ""
    var artist = ""
    var album = ""
    var albumArtist = ""
    var duration = 0.0
    var position = 0.0
    var bpm = 0.0
    var id = ""
    var trackNumber = 0
    var trackCount = 0
    var discNumber = 0
    var discCount = 0
    /// 이 디스크의 곡 길이(초), 곡 번호 순서. 모르면 nil.
    var trackDurations: [Double]?
    var art: String?

    static let stopped = NowPlayingInfo()

    var payload: [String: Any] {
        guard state != .stopped else { return ["state": state.rawValue] }
        var dict: [String: Any] = [
            "state": state.rawValue,
            "title": title,
            "artist": artist,
            "album": album,
            "albumArtist": albumArtist,
            "duration": duration,
            "position": position,
            "bpm": bpm,
            "id": id,
            "trackNumber": trackNumber,
            "trackCount": trackCount,
            "discNumber": discNumber,
            "discCount": discCount,
        ]
        if let trackDurations { dict["trackDurations"] = trackDurations }
        if let art { dict["art"] = art }
        return dict
    }
}

/// Music 재생 정보 읽기. 분산 알림과 AppleScript를 합쳐 쓴다. 명세 4.5.
final class NowPlaying {
    static let musicBundleID = "com.apple.Music"
    private static let playerInfoNotification = Notification.Name("com.apple.Music.playerInfo")
    private static let pollInterval: TimeInterval = 10
    private static let notAuthorized = -1743

    /// 상태가 바뀌거나 위치를 보정할 때마다 메인 스레드에서 불린다.
    var onUpdate: ((NowPlayingInfo) -> Void)?
    /// 커버가 준비되면 메인 스레드에서 불린다. (dataURL, version)
    var onArt: ((String, String) -> Void)?
    /// Music 제어 권한이 없을 때 true.
    var onPermissionChange: ((Bool) -> Void)?

    private(set) var current = NowPlayingInfo.stopped
    private(set) var currentArt: (dataURL: String, version: String)?
    private(set) var permissionDenied = false

    private let logToStdout: Bool
    private let queue = DispatchQueue(label: "com.todaysrecord.applescript", qos: .utility)
    private let artwork: Artwork
    private let albumTracks = AlbumTracks()
    /// 곡 길이를 기다리는 동안 더 새로운 결과가 오면 이전 결과를 버리기 위한 번호.
    private var resultGeneration = 0
    private var statusScript: NSAppleScript?
    private var diagnosticScript: NSAppleScript?
    private var pollTimer: Timer?
    private var pendingQuery: DispatchWorkItem?
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []

    init(logToStdout: Bool) {
        self.logToStdout = logToStdout
        self.artwork = Artwork(queue: queue, logToStdout: logToStdout)
    }

    deinit {
        observers.forEach { center, token in center.removeObserver(token) }
        pollTimer?.invalidate()
    }

    func start() {
        let distributed = DistributedNotificationCenter.default()
        observers.append((distributed, distributed.addObserver(
            forName: Self.playerInfoNotification, object: nil, queue: .main
        ) { [weak self] note in
            self?.receivedPlayerInfo(note)
        }))

        // Music이 종료될 때 알림이 오지 않을 수 있어 직접 정지로 바꾼다.
        let workspace = NSWorkspace.shared.notificationCenter
        observers.append((workspace, workspace.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            guard app?.bundleIdentifier == Self.musicBundleID else { return }
            Log.nowPlaying.info("Music 종료")
            self?.resultGeneration += 1
            self?.apply(.stopped)
        }))

        query(reason: "start")
    }

    // MARK: - 알림

    private func receivedPlayerInfo(_ note: Notification) {
        if logToStdout {
            let info = (note.userInfo ?? [:])
                .map { "  \($0.key) = \($0.value)" }
                .sorted()
                .joined(separator: "\n")
            stdout("[알림] \(note.name.rawValue)\n\(info)")
        }
        // 곡이 바뀔 때 알림이 연달아 올 수 있어 짧게 모아서 한 번 묻는다.
        pendingQuery?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.query(reason: "notification") }
        pendingQuery = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: work)
    }

    // MARK: - AppleScript

    private func query(reason: String) {
        queue.async { [weak self] in
            guard let self else { return }
            let result = self.runStatusScript()
            DispatchQueue.main.async { self.handle(result, reason: reason) }
        }
    }

    private enum StatusResult {
        case info(NowPlayingInfo)
        case notAuthorized
        case failed
    }

    /// AppleScript 큐에서만 부른다.
    private func runStatusScript() -> StatusResult {
        guard Self.isMusicRunning else {
            if logToStdout { stdout("[AppleScript] Music이 꺼져 있어 묻지 않음") }
            return .info(.stopped)
        }
        if statusScript == nil {
            statusScript = NSAppleScript(source: Self.statusSource)
        }
        var error: NSDictionary?
        let started = DispatchTime.now()
        let output = statusScript?.executeAndReturnError(&error).stringValue
        let elapsed = Double(DispatchTime.now().uptimeNanoseconds - started.uptimeNanoseconds) / 1_000_000
        Log.nowPlaying.debug("상태 스크립트 \(elapsed, format: .fixed(precision: 1))ms")
        if logToStdout { stdout("[AppleScript] \(String(format: "%.1f", elapsed))ms") }
        if let error {
            let code = error[NSAppleScript.errorNumber] as? Int ?? 0
            Log.nowPlaying.error("상태 스크립트 오류 \(code): \(String(describing: error[NSAppleScript.errorMessage] ?? ""), privacy: .public)")
            if logToStdout { stdout("[AppleScript] 오류 \(code) \(error)") }
            return code == Self.notAuthorized ? .notAuthorized : .failed
        }
        if logToStdout {
            stdout("[AppleScript] \(output?.replacingOccurrences(of: Self.separator, with: " | ") ?? "nil")")
            stdout("[재생 목록] \(runDiagnosticScript())")
        }
        return .info(Self.parse(output ?? ""))
    }

    /// --log-nowplaying 전용. 셔플, 반복, 지금 재생 중인 목록과 그 안의 순서를 묻는다.
    private func runDiagnosticScript() -> String {
        if diagnosticScript == nil {
            diagnosticScript = NSAppleScript(source: Self.diagnosticSource)
        }
        var error: NSDictionary?
        let output = diagnosticScript?.executeAndReturnError(&error).stringValue
        return output ?? "오류 \(error?[NSAppleScript.errorNumber] ?? "")"
    }

    static var isMusicRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: musicBundleID).isEmpty
    }

    private func handle(_ result: StatusResult, reason: String) {
        switch result {
        case .info(let info):
            setPermissionDenied(false)
            resultGeneration += 1
            let generation = resultGeneration
            // 새 곡의 앨범 곡 목록을 아직 모르면 찾을 때까지(최대 3초) 기다렸다 보낸다.
            guard info.id != current.id, info.state != .stopped, !info.album.isEmpty, !albumTracks.isSettled(info) else {
                apply(info)
                return
            }
            let asked = Date()
            albumTracks.load(for: info) { [weak self] in
                guard let self, generation == self.resultGeneration else { return }
                var info = info
                if info.state == .playing { info.position += Date().timeIntervalSince(asked) }
                self.apply(info)
            }
        case .notAuthorized:
            resultGeneration += 1
            setPermissionDenied(true)
            apply(.stopped)
        case .failed:
            resultGeneration += 1
            apply(.stopped)
        }
    }

    private func setPermissionDenied(_ denied: Bool) {
        guard denied != permissionDenied else { return }
        permissionDenied = denied
        Log.nowPlaying.notice("Music 제어 권한 \(denied ? "없음" : "있음")")
        onPermissionChange?(denied)
    }

    // MARK: - 상태 반영

    private func apply(_ newInfo: NowPlayingInfo) {
        var info = newInfo
        let trackChanged = info.id != current.id
        if info.state != .stopped, let place = albumTracks.placement(for: info) {
            info.trackNumber = place.trackNumber
            info.trackCount = place.trackCount
            info.discNumber = place.discNumber
            info.discCount = place.discCount
            info.trackDurations = place.durations
        }
        if logToStdout, trackChanged, info.state != .stopped {
            let durations = info.trackDurations.map { "\($0.count)곡 길이 있음" } ?? "길이 없음"
            stdout("[곡 위치] 디스크 \(info.discNumber)/\(info.discCount), \(info.trackNumber)/\(info.trackCount)번, \(durations)")
        }
        if trackChanged {
            currentArt = nil
        } else {
            info.art = current.art
        }
        current = info
        onUpdate?(info)
        updatePollTimer()

        if trackChanged, info.state != .stopped {
            fetchArtwork(for: info)
        }
    }

    private func fetchArtwork(for info: NowPlayingInfo) {
        let id = info.id
        artwork.fetch(artist: info.artist, album: info.album, title: info.title) { [weak self] result in
            guard let self, self.current.id == id, let result else { return }
            self.currentArt = (result.dataURL, result.version)
            self.current.art = result.version
            if result.isNew { self.onArt?(result.dataURL, result.version) }
            self.onUpdate?(self.current)
        }
    }

    private func updatePollTimer() {
        if current.state == .playing {
            guard pollTimer == nil else { return }
            let timer = Timer(timeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
                self?.query(reason: "poll")
            }
            timer.tolerance = 1
            RunLoop.main.add(timer, forMode: .common)
            pollTimer = timer
        } else {
            pollTimer?.invalidate()
            pollTimer = nil
        }
    }

    // MARK: - 해석

    static let separator = "\u{1F}"

    static func parse(_ output: String) -> NowPlayingInfo {
        guard !output.isEmpty, output != "notrunning", output != "stopped" else { return .stopped }
        var fields = output.components(separatedBy: separator)
        fields += Array(repeating: "", count: max(0, 13 - fields.count))
        let (st, name, artist, album, albumArtist, dur, pos, pid, bpm) =
            (fields[0], fields[1], fields[2], fields[3], fields[4], fields[5], fields[6], fields[7], fields[8])

        var info = NowPlayingInfo()
        info.state = ["playing", "fast forwarding", "rewinding"].contains(st) ? .playing : .paused
        info.title = name
        info.artist = artist
        info.album = album
        info.albumArtist = albumArtist
        info.duration = number(dur)
        info.position = number(pos)
        info.bpm = number(bpm)
        info.id = pid.isEmpty ? "\(name)|\(artist)|\(album)" : pid
        info.trackNumber = Int(number(fields[9]))
        info.trackCount = Int(number(fields[10]))
        info.discNumber = Int(number(fields[11]))
        info.discCount = Int(number(fields[12]))
        return info
    }

    /// 지역 설정에 따라 소수점이 쉼표일 수 있다.
    static func number(_ text: String) -> Double {
        Double(text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")) ?? 0
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
}

/// --log-nowplaying 출력. 파이프로 넘겨도 바로 보이게 한 줄씩 쓴다.
func stdout(_ text: String) {
    FileHandle.standardOutput.write(Data((text + "\n").utf8))
}
