import XCTest
@testable import TodaysRecord

/// iTunes 검색 결과에서 앨범 고르기. 명세 4.6.
final class ITunesSearchTests: XCTestCase {
    private func item(_ id: Int, _ album: String, track: String? = nil) -> [String: Any] {
        var item: [String: Any] = ["collectionId": id, "collectionName": album]
        if let track { item["trackName"] = track }
        return item
    }

    /// 2026-10 US 스토어 앨범 검색 "YOASOBI アイドル" 결과 순서 그대로. Spotify 앨범 이름에는 " - Single"이 없다.
    func testSpotifySingleMatchesITunesSingleSuffix() {
        let results = [
            item(1520198755, "たぶん - Single"),
            item(1688334284, "Idol - Single"),
            item(1679278166, "アイドル - Single"),
            item(1542182291, "THE BOOK"),
        ]
        let match = ITunesSearch.bestMatch(in: results, album: "アイドル", title: nil)
        XCTAssertEqual(match?["collectionId"] as? Int, 1679278166)
    }

    func testEPSuffixIsIgnoredInSongSearch() {
        let results = [
            item(1, "Get Up (Remixes)", track: "Get Up"),
            item(2, "Get Up - EP", track: "Get Up"),
        ]
        let match = ITunesSearch.bestMatch(in: results, album: "Get Up", title: "Get Up")
        XCTAssertEqual(match?["collectionId"] as? Int, 2)
    }

    /// Music은 iTunes와 같은 이름(접미사 포함)을 준다. 그대로 맞아야 한다.
    func testSameSuffixOnBothSidesStillMatches() {
        let results = [
            item(1520198755, "たぶん - Single"),
            item(1679278166, "アイドル - Single"),
        ]
        let match = ITunesSearch.bestMatch(in: results, album: "アイドル - Single", title: nil)
        XCTAssertEqual(match?["collectionId"] as? Int, 1679278166)
    }

    /// 접미사 말고 이름 자체가 다른 판본(디럭스 등)은 다른 앨범으로 본다.
    func testOtherEditionIsNotTreatedAsSameAlbum() {
        let results = [
            item(1, "Nine Track Mind (Deluxe)"),
            item(2, "Nine Track Mind"),
        ]
        let match = ITunesSearch.bestMatch(in: results, album: "Nine Track Mind", title: nil)
        XCTAssertEqual(match?["collectionId"] as? Int, 2)
    }
}

/// 어느 스토어부터 찾을지. 명세 4.6.
final class ITunesCountryTests: XCTestCase {
    /// 한국 스토어는 음악을 팔지 않아 search, lookup 모두 0건이다. 묻느라 매번 0.5초 넘게 쓴다(2026-10 측정).
    func testKoreaStoreIsSkipped() {
        XCTAssertEqual(ITunesSearch.countries(setting: "KR"), ["US"])
        XCTAssertEqual(ITunesSearch.countries(setting: "kr"), ["US"])
    }

    func testDefaultIsUS() {
        XCTAssertEqual(ITunesSearch.countries(setting: nil), ["US"])
    }

    func testOtherStoreFallsBackToUS() {
        XCTAssertEqual(ITunesSearch.countries(setting: "JP"), ["JP", "US"])
        XCTAssertEqual(ITunesSearch.countries(setting: "US"), ["US"])
    }
}
