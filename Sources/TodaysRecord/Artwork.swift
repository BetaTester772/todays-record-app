import Foundation

/// 앨범 커버 가져오기. Music → iTunes 검색 순서. 명세 4.6.
final class Artwork {
    struct Result {
        let dataURL: String
        let version: String
        /// 바로 앞에 보낸 커버와 다를 때 true. 같은 커버는 다시 보내지 않는다.
        let isNew: Bool
    }

    static let countryKey = "artworkCountry"
    static let defaultCountry = "KR"

    private let queue: DispatchQueue
    private let logToStdout: Bool
    private var artScript: NSAppleScript?
    // 아래 두 값은 메인 스레드에서만 다룬다.
    private var counter = 0
    private var last: (data: Data, version: String)?

    /// queue는 AppleScript 전용 직렬 큐. NowPlaying과 같은 큐를 쓴다.
    init(queue: DispatchQueue, logToStdout: Bool) {
        self.queue = queue
        self.logToStdout = logToStdout
    }

    /// 결과는 메인 스레드에서 받는다. 찾지 못하면 nil.
    func fetch(artist: String, album: String, title: String, completion: @escaping (Result?) -> Void) {
        let country = UserDefaults.standard.string(forKey: Self.countryKey) ?? Self.defaultCountry
        queue.async { [weak self] in
            guard let self else { return }
            if let data = self.runArtScript(), Self.mimeType(of: data) != nil {
                if self.logToStdout { stdout("[커버] Music에서 받음 \(data.count)바이트") }
                self.finish(data, completion)
                return
            }
            Self.search(artist: artist, album: album, title: title, country: country) { data in
                if self.logToStdout { stdout("[커버] 검색 결과 \(data.map { "\($0.count)바이트" } ?? "없음")") }
                self.finish(data, completion)
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

    /// AppleScript 큐에서만 부른다.
    private func runArtScript() -> Data? {
        guard NowPlaying.isMusicRunning else { return nil }
        if artScript == nil {
            artScript = NSAppleScript(source: Self.artSource)
        }
        var error: NSDictionary?
        let result = artScript?.executeAndReturnError(&error)
        if let error {
            Log.nowPlaying.error("커버 스크립트 오류 \(String(describing: error[NSAppleScript.errorNumber] ?? ""), privacy: .public)")
            return nil
        }
        guard let result, result.stringValue != "none" else { return nil }
        return result.data
    }

    private static func search(artist: String, album: String, title: String, country: String, completion: @escaping (Data?) -> Void) {
        let term = "\(artist) \(album.isEmpty ? title : album)".trimmingCharacters(in: .whitespaces)
        var components = URLComponents(string: "https://itunes.apple.com/search")!
        components.queryItems = [
            URLQueryItem(name: "term", value: term),
            URLQueryItem(name: "entity", value: "album"),
            URLQueryItem(name: "limit", value: "1"),
            URLQueryItem(name: "country", value: country),
        ]
        guard !term.isEmpty, let url = components.url else {
            completion(nil)
            return
        }
        get(url) { data in
            guard
                let data,
                let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let first = (json["results"] as? [[String: Any]])?.first,
                let small = first["artworkUrl100"] as? String,
                let artURL = URL(string: small.replacingOccurrences(of: "100x100bb", with: "600x600bb"))
            else {
                completion(nil)
                return
            }
            get(artURL, completion: completion)
        }
    }

    private static func get(_ url: URL, completion: @escaping (Data?) -> Void) {
        var request = URLRequest(url: url)
        request.timeoutInterval = 6
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error {
                Log.nowPlaying.error("커버 검색 실패 \(error.localizedDescription, privacy: .public)")
            }
            let ok = (response as? HTTPURLResponse)?.statusCode == 200
            completion(ok ? data : nil)
        }.resume()
    }

    static func mimeType(of data: Data) -> String? {
        if data.starts(with: [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) { return "image/png" }
        if data.starts(with: [0xFF, 0xD8, 0xFF]) { return "image/jpeg" }
        return nil
    }

    private static func dataURL(_ data: Data, _ mime: String) -> String {
        "data:\(mime);base64,\(data.base64EncodedString())"
    }

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
