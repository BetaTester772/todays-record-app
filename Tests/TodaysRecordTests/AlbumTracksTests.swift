import XCTest
@testable import TodaysRecord

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
