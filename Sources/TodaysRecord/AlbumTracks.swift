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
        guard let tracks = cache[Self.key(for: info)], !tracks.isEmpty else { return nil }

        let disc: Int
        let number: Int
        if info.trackNumber > 0 {
            disc = max(1, info.discNumber)
            number = info.trackNumber
        } else if let track = Self.find(info, in: tracks) {
            disc = track.disc
            number = track.number
        } else {
            return nil
        }

        let onDisc = tracks.filter { $0.disc == disc }
        // 곡 번호가 1부터 빠짐없이 이어질 때만 쓴다.
        guard onDisc.map(\.number) == Array(1...max(1, onDisc.count)), number <= onDisc.count else { return nil }
        if info.trackCount > 0, info.trackCount != onDisc.count { return nil }
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
            ITunesSearch.tracks(of: album) { tracks in
                DispatchQueue.main.async { self.finish(key, tracks) }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.timeout) { [weak self] in
            self?.release(key)
        }
    }

    private func finish(_ key: String, _ tracks: [ITunesSearch.Track]) {
        cache[key] = tracks
        Log.nowPlaying.info("앨범 곡 목록 \(key, privacy: .public): \(tracks.count)곡")
        release(key)
    }

    private func release(_ key: String) {
        guard let completions = waiting.removeValue(forKey: key) else { return }
        completions.forEach { $0() }
    }
}
