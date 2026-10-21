import Foundation

/// 앨범 곡 목록. LP 면 나누기에 쓴다. 명세 4.5 (3), 6장 10.
/// Music이 곡 번호를 주지 않는 스트리밍 곡은 여기서 제목으로 곡 번호를 찾는다.
/// 모든 메서드는 메인 스레드에서 부른다.
final class AlbumTracks {
    struct Placement {
        let trackNumber: Int
        let trackCount: Int
        let discNumber: Int
        let discCount: Int
        let durations: [Double]
    }

    /// 곡 목록을 기다리는 최대 시간. 넘으면 목록 없이 진행한다.
    private static let timeout: TimeInterval = 3

    private var cache: [String: [ITunesSearch.Track]] = [:]
    private var waiting: [String: [() -> Void]] = [:]

    /// 찾은 곡 목록을 저장하는 파일. 앱을 다시 켜도 한 번 찾은 앨범은 기다리지 않는다.
    /// 다시 받을 수 있는 자료라 캐시 폴더에 둔다. nil이면 저장하지 않는다.
    private let storeURL: URL?
    /// 저장해 둘 앨범 수. 넘으면 오래된 것부터 뺀다.
    private let maxStored: Int
    /// 저장한 앨범 키. 오래된 것부터.
    private var stored: [String] = []
    private let saveQueue = DispatchQueue(label: "com.todaysrecord.albumtracks", qos: .utility)

    private struct Entry: Codable {
        let key: String
        let tracks: [ITunesSearch.Track]
    }

    static var defaultStoreURL: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("com.todaysrecord.app", isDirectory: true)
            .appendingPathComponent("AlbumTracks.json")
    }

    init(storeURL: URL? = AlbumTracks.defaultStoreURL, maxStored: Int = 500) {
        self.storeURL = storeURL
        self.maxStored = maxStored
        loadStored()
    }

    static func key(for info: NowPlayingInfo) -> String {
        let artist = info.albumArtist.isEmpty ? info.artist : info.albumArtist
        return "\(artist)|\(info.album)"
    }

    /// 이미 찾아봤으면(찾았든 못 찾았든) true.
    func isSettled(_ info: NowPlayingInfo) -> Bool {
        cache[Self.key(for: info)] != nil
    }

    /// 이 곡이 앨범 어디에 있는지. 곡 목록이 없거나 맞지 않으면 nil.
    func placement(for info: NowPlayingInfo) -> Placement? {
        cache[Self.key(for: info)].flatMap { Self.placement(for: info, in: $0) }
    }

    static func placement(for info: NowPlayingInfo, in tracks: [ITunesSearch.Track]) -> Placement? {
        guard !tracks.isEmpty else { return nil }

        let disc: Int
        let number: Int
        if info.trackNumber > 0 {
            disc = max(1, info.discNumber)
            number = info.trackNumber
        } else if let track = find(info, in: tracks) {
            // 길이가 다르면 다른 판본(디럭스, 리마스터 등)의 목록일 수 있어 쓰지 않는다.
            if info.duration > 0, abs(track.duration - info.duration) > 3 { return nil }
            disc = track.disc
            number = track.number
        } else {
            return nil
        }

        let onDisc = tracks.filter { $0.disc == disc }
        // 곡 번호가 1부터 빠짐없이 이어질 때만 쓴다.
        guard onDisc.map(\.number) == Array(1...max(1, onDisc.count)), number <= onDisc.count else { return nil }
        if info.trackCount > 0, info.trackCount != onDisc.count { return nil }
        // Spotify처럼 곡 번호만 있고 곡 수가 없으면 판본을 곡 수로 확인할 수 없어 그 번호 곡의 길이로 확인한다.
        if info.trackCount == 0, info.trackNumber > 0, info.duration > 0,
           abs(onDisc[number - 1].duration - info.duration) > 3 { return nil }
        return Placement(
            trackNumber: number,
            trackCount: onDisc.count,
            discNumber: disc,
            discCount: tracks.map(\.disc).max() ?? 1,
            durations: onDisc.map(\.duration)
        )
    }

    /// 제목이 같은 곡, 없으면 길이가 1초 이내로 같은 곡이 하나뿐일 때 그 곡.
    private static func find(_ info: NowPlayingInfo, in tracks: [ITunesSearch.Track]) -> ITunesSearch.Track? {
        let title = ITunesSearch.normalized(info.title)
        if let track = tracks.first(where: { ITunesSearch.normalized($0.name) == title }) {
            return track
        }
        let close = tracks.filter { abs($0.duration - info.duration) < 1 }
        return close.count == 1 ? close[0] : nil
    }

    /// 찾기가 끝나거나 시간이 지나면 completion을 부른다.
    func load(for info: NowPlayingInfo, completion: @escaping () -> Void) {
        let key = Self.key(for: info)
        if waiting[key] != nil {
            waiting[key]?.append(completion)
            return
        }
        waiting[key] = [completion]

        let artist = info.albumArtist.isEmpty ? info.artist : info.albumArtist
        ITunesSearch.findAlbum(artist: artist, album: info.album, title: info.title, countries: ITunesSearch.countries) { album in
            guard let album else {
                DispatchQueue.main.async { self.finish(key, []) }
                return
            }
            Log.nowPlaying.info("앨범 찾음 \(album.name, privacy: .public) id=\(album.collectionID) \(album.country, privacy: .public)")
            ITunesSearch.tracks(of: album) { tracks in
                DispatchQueue.main.async { self.finish(key, tracks) }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.timeout) { [weak self] in
            self?.release(key)
        }
    }

    private func finish(_ key: String, _ tracks: [ITunesSearch.Track]) {
        remember(tracks, forKey: key)
        Log.nowPlaying.info("앨범 곡 목록 \(key, privacy: .public): \(tracks.count)곡")
        release(key)
    }

    /// 찾은 곡 목록을 기억한다. 못 찾은 앨범(빈 목록)은 이번 실행에서만 기억한다.
    func store(_ tracks: [ITunesSearch.Track], for info: NowPlayingInfo) {
        remember(tracks, forKey: Self.key(for: info))
    }

    private func remember(_ tracks: [ITunesSearch.Track], forKey key: String) {
        cache[key] = tracks
        guard !tracks.isEmpty, storeURL != nil else { return }
        stored.removeAll { $0 == key }
        stored.append(key)
        if stored.count > maxStored {
            let dropped = stored.prefix(stored.count - maxStored)
            dropped.forEach { cache[$0] = nil }
            stored.removeFirst(dropped.count)
        }
        save()
    }

    private func loadStored() {
        guard let storeURL, let data = try? Data(contentsOf: storeURL) else { return }
        guard let entries = try? JSONDecoder().decode([Entry].self, from: data) else {
            Log.nowPlaying.error("앨범 곡 목록 파일을 읽지 못해 무시함")
            return
        }
        for entry in entries.suffix(maxStored) where !entry.tracks.isEmpty {
            cache[entry.key] = entry.tracks
            stored.append(entry.key)
        }
        Log.nowPlaying.info("저장한 앨범 곡 목록 \(self.stored.count)개 읽음")
    }

    private func save() {
        guard let storeURL else { return }
        let entries = stored.compactMap { key in cache[key].map { Entry(key: key, tracks: $0) } }
        saveQueue.async {
            do {
                try FileManager.default.createDirectory(at: storeURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                try JSONEncoder().encode(entries).write(to: storeURL, options: .atomic)
            } catch {
                Log.nowPlaying.error("앨범 곡 목록 저장 실패 \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// 테스트용. 저장이 끝날 때까지 기다린다.
    func waitForSave() {
        saveQueue.sync {}
    }

    private func release(_ key: String) {
        guard let completions = waiting.removeValue(forKey: key) else { return }
        completions.forEach { $0() }
    }
}
