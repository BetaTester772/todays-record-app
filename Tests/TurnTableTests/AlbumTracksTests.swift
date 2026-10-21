import XCTest
@testable import TurnTable

/// 앨범 곡 목록으로 곡 위치 정하기. 명세 4.5 (3), 4.5.1.
final class AlbumTracksTests: XCTestCase {
    private let tracks = [
        ITunesSearch.Track(disc: 1, number: 1, name: "Attention", duration: 180),
        ITunesSearch.Track(disc: 1, number: 2, name: "Hype Boy", duration: 179),
        ITunesSearch.Track(disc: 1, number: 3, name: "Cookie", duration: 235),
    ]

    private func info(number: Int, count: Int, duration: Double, title: String = "") -> NowPlayingInfo {
        var info = NowPlayingInfo()
        info.state = .playing
        info.title = title
        info.trackNumber = number
        info.trackCount = count
        info.discNumber = number > 0 ? 1 : 0
        info.duration = duration
        return info
    }

    /// Spotify처럼 곡 번호만 있고 곡 수가 없으면 곡 수와 길이를 목록에서 얻는다.
    func testNumberWithoutCountUsesListedCountAndDurations() {
        let place = AlbumTracks.placement(for: info(number: 2, count: 0, duration: 180), in: tracks)
        XCTAssertEqual(place?.trackNumber, 2)
        XCTAssertEqual(place?.trackCount, 3)
        XCTAssertEqual(place?.durations, [180, 179, 235])
    }

    /// 곡 수로 판본을 확인할 수 없으니 그 번호 곡의 길이가 3초 넘게 다르면 쓰지 않는다.
    func testNumberWithoutCountRejectsDifferentLength() {
        XCTAssertNil(AlbumTracks.placement(for: info(number: 2, count: 0, duration: 200), in: tracks))
    }

    func testMusicTrackCountMismatchIsRejected() {
        XCTAssertNil(AlbumTracks.placement(for: info(number: 2, count: 12, duration: 179), in: tracks))
    }

    func testStreamingTrackFoundByTitle() {
        let place = AlbumTracks.placement(for: info(number: 0, count: 0, duration: 235, title: "cookie"), in: tracks)
        XCTAssertEqual(place?.trackNumber, 3)
    }
}

/// 찾은 곡 목록을 디스크에 저장해 앱을 다시 켜도 기다리지 않는다. 명세 4.5 (3).
final class AlbumTracksStoreTests: XCTestCase {
    private var url: URL!

    override func setUpWithError() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("AlbumTracks.json")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }

    private func info(album: String, number: Int = 1) -> NowPlayingInfo {
        var info = NowPlayingInfo()
        info.state = .playing
        info.title = "Hype Boy"
        info.artist = "NewJeans"
        info.album = album
        info.trackNumber = number
        info.discNumber = 1
        info.duration = 179
        return info
    }

    private let tracks = [
        ITunesSearch.Track(disc: 1, number: 1, name: "Hype Boy", duration: 179),
        ITunesSearch.Track(disc: 1, number: 2, name: "Cookie", duration: 235),
    ]

    func testFoundListIsRememberedAfterRelaunch() {
        let first = AlbumTracks(storeURL: url)
        first.store(tracks, for: info(album: "New Jeans"))
        first.waitForSave()

        let relaunched = AlbumTracks(storeURL: url)
        XCTAssertTrue(relaunched.isSettled(info(album: "New Jeans")))
        XCTAssertEqual(relaunched.placement(for: info(album: "New Jeans"))?.trackCount, 2)
    }

    /// 못 찾은 앨범은 나중에 iTunes에 올라올 수 있어 저장하지 않고 다음 실행 때 다시 찾는다.
    func testNotFoundIsNotRemembered() {
        let first = AlbumTracks(storeURL: url)
        first.store([], for: info(album: "Missing"))
        first.waitForSave()
        XCTAssertTrue(first.isSettled(info(album: "Missing")))

        XCTAssertFalse(AlbumTracks(storeURL: url).isSettled(info(album: "Missing")))
    }

    func testOnlyLatestAlbumsAreKept() {
        let first = AlbumTracks(storeURL: url, maxStored: 2)
        for album in ["A", "B", "C"] { first.store(tracks, for: info(album: album)) }
        first.waitForSave()

        let relaunched = AlbumTracks(storeURL: url, maxStored: 2)
        XCTAssertFalse(relaunched.isSettled(info(album: "A")))
        XCTAssertTrue(relaunched.isSettled(info(album: "B")))
        XCTAssertTrue(relaunched.isSettled(info(album: "C")))
    }

    func testBrokenFileIsIgnored() throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: url)
        XCTAssertFalse(AlbumTracks(storeURL: url).isSettled(info(album: "New Jeans")))
    }
}
