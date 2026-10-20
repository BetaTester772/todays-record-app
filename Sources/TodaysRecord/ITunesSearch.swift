import Foundation

/// iTunes Search API. 커버 대체 검색과 앨범 곡 길이에 쓴다. 명세 4.6.
/// 결과는 URLSession 스레드에서 돌려준다.
enum ITunesSearch {
    static let countryKey = "artworkCountry"
    static let defaultCountry = "KR"
    /// KR 스토어는 음악 결과가 비어 있어서, 찾지 못하면 이 국가로 한 번 더 찾는다.
    static let fallbackCountry = "US"

    struct Album {
        let collectionID: Int
        let name: String
        let artworkURL: URL?
        let country: String
    }

    static var countries: [String] {
        let country = UserDefaults.standard.string(forKey: countryKey) ?? defaultCountry
        return country.uppercased() == fallbackCountry ? [fallbackCountry] : [country, fallbackCountry]
    }

    struct Track {
        let disc: Int
        let number: Int
        let name: String
        let duration: Double
    }

    /// 곡 검색(아티스트 + 제목)으로 앨범을 찾는다. 스트리밍 곡은 앨범 검색에 잘 걸리지 않아서다.
    /// 곡 검색에서 못 찾으면 앨범 검색을 쓴다. 앨범 이름이 같은 결과를 먼저 고른다.
    static func findAlbum(artist: String, album: String, title: String, countries: [String], completion: @escaping (Album?) -> Void) {
        guard let country = countries.first else {
            completion(nil)
            return
        }
        let tryNext = { findAlbum(artist: artist, album: album, title: title, countries: Array(countries.dropFirst()), completion: completion) }
        search(term: "\(artist) \(title)", entity: "song", country: country, album: album, title: title) { found in
            if let found {
                completion(found)
                return
            }
            search(term: "\(artist) \(album.isEmpty ? title : album)", entity: "album", country: country, album: album, title: nil) { found in
                if let found { completion(found) } else { tryNext() }
            }
        }
    }

    private static func search(term: String, entity: String, country: String, album: String, title: String?, completion: @escaping (Album?) -> Void) {
        let term = term.trimmingCharacters(in: .whitespaces)
        guard !term.isEmpty else {
            completion(nil)
            return
        }
        let url = endpoint("search", ["term": term, "entity": entity, "limit": "10", "country": country])
        getJSON(url) { results in
            guard let match = bestMatch(in: results, album: album, title: title), let id = match["collectionId"] as? Int else {
                completion(nil)
                return
            }
            let artwork = (match["artworkUrl100"] as? String)
                .flatMap { URL(string: $0.replacingOccurrences(of: "100x100bb", with: "600x600bb")) }
            completion(Album(collectionID: id, name: match["collectionName"] as? String ?? "", artworkURL: artwork, country: country))
        }
    }

    /// 앨범 이름과 곡 제목이 같은 결과 → 앨범 이름이 같은 결과 → 곡 검색이면 제목이 같은 결과, 앨범 검색(title nil)이면 첫 결과.
    static func bestMatch(in results: [[String: Any]], album: String, title: String?) -> [String: Any]? {
        let albumKey = albumName(album)
        let sameAlbum = { (item: [String: Any]) in
            albumName(item["collectionName"] as? String ?? "") == albumKey
        }
        let sameTitle = { (item: [String: Any]) in
            title.map { normalized(item["trackName"] as? String ?? "") == normalized($0) } ?? true
        }
        return results.first { sameAlbum($0) && sameTitle($0) }
            ?? results.first(where: sameAlbum)
            ?? (title == nil ? results.first : results.first(where: sameTitle))
    }

    /// 앨범의 모든 곡. 디스크, 곡 번호 순서.
    static func tracks(of album: Album, completion: @escaping ([Track]) -> Void) {
        let url = endpoint("lookup", ["id": String(album.collectionID), "entity": "song", "country": album.country])
        getJSON(url) { results in
            let tracks = results.compactMap { item -> Track? in
                guard
                    item["wrapperType"] as? String == "track",
                    let number = item["trackNumber"] as? Int,
                    let millis = item["trackTimeMillis"] as? Double
                else { return nil }
                return Track(disc: item["discNumber"] as? Int ?? 1, number: number, name: item["trackName"] as? String ?? "", duration: millis / 1000)
            }
            completion(tracks.sorted { ($0.disc, $0.number) < ($1.disc, $1.number) })
        }
    }

    static func normalized(_ text: String) -> String {
        text.lowercased().trimmingCharacters(in: .whitespaces)
    }

    /// 비교용 앨범 이름. iTunes는 싱글과 EP 이름 끝에 " - Single", " - EP"를 붙이지만 Spotify는 붙이지 않는다.
    static func albumName(_ name: String) -> String {
        let name = normalized(name)
        for suffix in [" - single", " - ep"] where name.hasSuffix(suffix) {
            return String(name.dropLast(suffix.count))
        }
        return name
    }

    static func download(_ url: URL, completion: @escaping (Data?) -> Void) {
        var request = URLRequest(url: url)
        request.timeoutInterval = 6
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error {
                Log.nowPlaying.error("요청 실패 \(url.host ?? "", privacy: .public) \(error.localizedDescription, privacy: .public)")
            }
            let ok = (response as? HTTPURLResponse)?.statusCode == 200
            completion(ok ? data : nil)
        }.resume()
    }

    private static func endpoint(_ path: String, _ query: [String: String]) -> URL {
        var components = URLComponents(string: "https://itunes.apple.com/\(path)")!
        components.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        return components.url!
    }

    private static func getJSON(_ url: URL, completion: @escaping ([[String: Any]]) -> Void) {
        download(url) { data in
            let json = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            completion(json?["results"] as? [[String: Any]] ?? [])
        }
    }
}
