import Foundation

/// 앨범 커버 가져오기. 플레이어 → iTunes 검색 순서. 명세 4.6.
final class Artwork {
    struct Result {
        let dataURL: String
        let version: String
        /// 바로 앞에 보낸 커버와 다를 때 true. 같은 커버는 다시 보내지 않는다.
        let isNew: Bool
    }

    private let queue: DispatchQueue
    private let logToStdout: Bool
    // 아래 두 값은 메인 스레드에서만 다룬다.
    private var counter = 0
    private var last: (data: Data, version: String)?

    /// queue는 AppleScript 전용 직렬 큐. NowPlaying과 같은 큐를 쓴다.
    init(queue: DispatchQueue, logToStdout: Bool) {
        self.queue = queue
        self.logToStdout = logToStdout
    }

    /// 결과는 메인 스레드에서 받는다. 찾지 못하면 nil.
    func fetch(for info: NowPlayingInfo, from player: Player, completion: @escaping (Result?) -> Void) {
        let countries = ITunesSearch.countries
        let name = player.kind.name
        let running = player.kind.isRunning
        queue.async { [weak self] in
            player.artwork(for: info, running: running) { data in
                guard let self else { return }
                if let data, Self.mimeType(of: data) != nil {
                    if self.logToStdout { stdout("[커버] \(name)에서 받음 \(data.count)바이트") }
                    self.finish(data, completion)
                    return
                }
                Self.search(artist: info.artist, album: info.album, title: info.title, countries: countries) { data in
                    if self.logToStdout { stdout("[커버] 검색 결과 \(data.map { "\($0.count)바이트" } ?? "없음")") }
                    self.finish(data, completion)
                }
            }
        }
    }

    private func finish(_ data: Data?, _ completion: @escaping (Result?) -> Void) {
        DispatchQueue.main.async {
            guard let data, let mime = Self.mimeType(of: data) else {
                completion(nil)
                return
            }
            if let last = self.last, last.data == data {
                completion(Result(dataURL: Self.dataURL(data, mime), version: last.version, isNew: false))
                return
            }
            self.counter += 1
            let version = String(self.counter)
            self.last = (data, version)
            completion(Result(dataURL: Self.dataURL(data, mime), version: version, isNew: true))
        }
    }

    private static func search(artist: String, album: String, title: String, countries: [String], completion: @escaping (Data?) -> Void) {
        ITunesSearch.findAlbum(artist: artist, album: album, title: title, countries: countries) { found in
            guard let url = found?.artworkURL else {
                completion(nil)
                return
            }
            ITunesSearch.download(url, completion: completion)
        }
    }

    static func mimeType(of data: Data) -> String? {
        if data.starts(with: [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) { return "image/png" }
        if data.starts(with: [0xFF, 0xD8, 0xFF]) { return "image/jpeg" }
        return nil
    }

    private static func dataURL(_ data: Data, _ mime: String) -> String {
        "data:\(mime);base64,\(data.base64EncodedString())"
    }
}
