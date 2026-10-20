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
    /// 플레이어가 주는 커버 주소(Spotify). 웹뷰로 보내지 않는다.
    var artworkURL: URL?
    /// Spotify 광고. 고르기에서는 그대로 보고, 화면에는 정지로 보낸다(4.5.1).
    var isAd = false

    static let stopped = NowPlayingInfo()

    /// 웹뷰와 메뉴에 보낼 상태. 광고는 곡으로 치지 않는다.
    var displayed: NowPlayingInfo { isAd ? .stopped : self }

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

/// Music, Spotify 재생 정보 읽기. 플레이어마다 분산 알림과 AppleScript를 합쳐 쓰고,
/// 그중 보여줄 플레이어 하나의 상태만 내보낸다. 명세 4.5, 4.5.2.
final class NowPlaying {
    private static let pollInterval: TimeInterval = 10

    /// 상태가 바뀌거나 위치를 보정할 때마다 메인 스레드에서 불린다.
    var onUpdate: ((NowPlayingInfo) -> Void)?
    /// 커버가 준비되면 메인 스레드에서 불린다. (dataURL, version)
    var onArt: ((String, String) -> Void)?
    /// 제어 권한이 없는 플레이어가 바뀌면 불린다.
    var onPermissionChange: ((Set<PlayerKind>) -> Void)?

    /// 보여주는 상태. 광고는 정지로 바뀌어 있다.
    private(set) var current = NowPlayingInfo.stopped
    private(set) var currentArt: (dataURL: String, version: String)?
    private(set) var deniedPlayers: Set<PlayerKind> = []
    var shownPlayer: PlayerKind? { chooser.shown }

    private let logToStdout: Bool
    private let queue = DispatchQueue(label: "com.todaysrecord.applescript", qos: .utility)
    private let players: [PlayerKind: Player]
    private let artwork: Artwork
    private let albumTracks = AlbumTracks()
    private var chooser = PlayerChooser()
    /// 곡 길이를 기다리는 동안 더 새로운 결과가 오거나 보여주는 플레이어가 바뀌면 이전 결과를 버리기 위한 번호.
    private var resultGeneration = 0
    private var pollTimer: Timer?
    private var pendingQueries: [PlayerKind: DispatchWorkItem] = [:]
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []

    init(logToStdout: Bool) {
        self.logToStdout = logToStdout
        self.artwork = Artwork(queue: queue, logToStdout: logToStdout)
        self.players = [
            .music: MusicPlayer(logToStdout: logToStdout),
            .spotify: SpotifyPlayer(logToStdout: logToStdout),
        ]
    }

    deinit {
        observers.forEach { center, token in center.removeObserver(token) }
        pollTimer?.invalidate()
    }

    func start() {
        let distributed = DistributedNotificationCenter.default()
        for kind in PlayerKind.allCases {
            observers.append((distributed, distributed.addObserver(
                forName: kind.notification, object: nil, queue: .main
            ) { [weak self] note in
                self?.receivedPlayerInfo(note, from: kind)
            }))
        }

        // 플레이어가 종료될 때 알림이 오지 않을 수 있어 직접 정지로 바꾼다.
        let workspace = NSWorkspace.shared.notificationCenter
        observers.append((workspace, workspace.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            guard let kind = PlayerKind.allCases.first(where: { $0.bundleID == app?.bundleIdentifier }) else { return }
            Log.nowPlaying.info("\(kind.name, privacy: .public) 종료")
            self?.pendingQueries.removeValue(forKey: kind)?.cancel()
            self?.handle(kind, .info(.stopped))
        }))

        // 이 순서로 묻고 받는다. 둘 다 재생 중이면 먼저 받은 Music을 보여준다(4.5.2).
        PlayerKind.allCases.forEach(query)
    }

    /// 메뉴에서 플레이어를 골랐을 때.
    func choose(_ kind: PlayerKind) {
        guard chooser.shown != kind else { return }
        logSwitch(from: chooser.shown, to: kind, reason: "메뉴에서 선택")
        chooser.choose(kind)
        resultGeneration += 1
        query(kind)
    }

    // MARK: - 알림

    private func receivedPlayerInfo(_ note: Notification, from kind: PlayerKind) {
        if logToStdout {
            let info = (note.userInfo ?? [:])
                .map { "  \($0.key) = \($0.value)" }
                .sorted()
                .joined(separator: "\n")
            stdout("[알림] \(note.name.rawValue)\n\(info)")
        }
        // 곡이 바뀔 때 알림이 연달아 올 수 있어 짧게 모아서 한 번 묻는다.
        pendingQueries[kind]?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.pendingQueries[kind] = nil
            self?.query(kind)
        }
        pendingQueries[kind] = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: work)
    }

    // MARK: - AppleScript

    private func query(_ kind: PlayerKind) {
        guard let player = players[kind] else { return }
        let running = kind.isRunning
        queue.async { [weak self] in
            let status = player.status(running: running)
            DispatchQueue.main.async { self?.handle(kind, status) }
        }
    }

    private func handle(_ kind: PlayerKind, _ status: PlayerStatus) {
        let info: NowPlayingInfo
        switch status {
        case .info(let result):
            setPermission(kind, denied: false)
            info = result
        case .notAuthorized:
            setPermission(kind, denied: true)
            info = .stopped
        case .failed:
            info = .stopped
        }

        let before = chooser.shown
        chooser.update(kind, info.state)
        if chooser.shown != before {
            logSwitch(from: before, to: chooser.shown, reason: "\(kind.name) \(info.state.rawValue)")
        }
        guard let shown = chooser.shown, shown != kind else {
            // 이 플레이어를 보여주거나, 보여줄 플레이어가 없다(정지).
            present(info, from: kind)
            return
        }
        if shown != before {
            // 다른 플레이어로 넘어갔다. 최신 위치를 다시 묻는다.
            resultGeneration += 1
            query(shown)
        }
        // 그 밖에는 보이지 않는 플레이어의 변화라 내보내지 않는다.
    }

    private func logSwitch(from old: PlayerKind?, to new: PlayerKind?, reason: String) {
        let text = "보여줄 플레이어 \(old?.name ?? "없음") → \(new?.name ?? "없음") (\(reason))"
        Log.nowPlaying.info("\(text, privacy: .public)")
        if logToStdout { stdout("[플레이어] \(text)") }
    }

    private func setPermission(_ kind: PlayerKind, denied: Bool) {
        guard denied != deniedPlayers.contains(kind) else { return }
        if denied { deniedPlayers.insert(kind) } else { deniedPlayers.remove(kind) }
        Log.nowPlaying.notice("\(kind.name, privacy: .public) 제어 권한 \(denied ? "없음" : "있음")")
        onPermissionChange?(deniedPlayers)
    }

    // MARK: - 상태 반영

    /// 보여주는 플레이어의 상태를 내보낸다.
    private func present(_ result: NowPlayingInfo, from kind: PlayerKind) {
        let info = result.displayed
        resultGeneration += 1
        let generation = resultGeneration
        // 새 곡의 앨범 곡 목록을 아직 모르면 찾을 때까지(최대 3초) 기다렸다 보낸다.
        guard info.id != current.id, info.state != .stopped, !info.album.isEmpty, !albumTracks.isSettled(info) else {
            apply(info, from: kind)
            return
        }
        let asked = Date()
        albumTracks.load(for: info) { [weak self] in
            guard let self, generation == self.resultGeneration else { return }
            var info = info
            if info.state == .playing { info.position += Date().timeIntervalSince(asked) }
            self.apply(info, from: kind)
        }
    }

    private func apply(_ newInfo: NowPlayingInfo, from kind: PlayerKind) {
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
            stdout("[곡 위치] \(kind.name) 디스크 \(info.discNumber)/\(info.discCount), \(info.trackNumber)/\(info.trackCount)번, \(durations)")
        }
        if trackChanged {
            currentArt = nil
        } else {
            info.art = current.art
        }
        current = info
        onUpdate?(info)
        updatePollTimer()

        if trackChanged, info.state != .stopped, let player = players[kind] {
            fetchArtwork(for: info, from: player)
        }
    }

    private func fetchArtwork(for info: NowPlayingInfo, from player: Player) {
        let id = info.id
        artwork.fetch(for: info, from: player) { [weak self] result in
            guard let self, self.current.id == id, let result else { return }
            self.currentArt = (result.dataURL, result.version)
            self.current.art = result.version
            if result.isNew { self.onArt?(result.dataURL, result.version) }
            self.onUpdate?(self.current)
        }
    }

    /// 잠자기·잠금 동안 위치 확인을 쉰다. 풀리면 보여주는 플레이어에게 바로 한 번 묻는다. 명세 4.7.
    var suspended = false {
        didSet {
            guard suspended != oldValue else { return }
            Log.nowPlaying.info("위치 확인 \(self.suspended ? "쉼" : "다시 시작", privacy: .public)")
            updatePollTimer()
            if !suspended, let shown = chooser.shown { query(shown) }
        }
    }

    /// 위치 보정은 보여주는 플레이어에게만 묻는다.
    private func updatePollTimer() {
        if current.state == .playing && !suspended {
            guard pollTimer == nil else { return }
            let timer = Timer(timeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
                guard let self, let shown = self.chooser.shown else { return }
                self.query(shown)
            }
            timer.tolerance = 1
            RunLoop.main.add(timer, forMode: .common)
            pollTimer = timer
        } else {
            pollTimer?.invalidate()
            pollTimer = nil
        }
    }
}

/// --log-nowplaying 출력. 파이프로 넘겨도 바로 보이게 한 줄씩 쓴다.
func stdout(_ text: String) {
    FileHandle.standardOutput.write(Data((text + "\n").utf8))
}
