import XCTest
@testable import TodaysRecord

/// 상태 스크립트 결과 해석. 명세 4.5, 4.5.1.
final class PlayerParseTests: XCTestCase {
    private func joined(_ fields: [String]) -> String {
        fields.joined(separator: "\u{1F}")
    }

    // MARK: - Music

    func testMusicParsesTrackWithCommaDecimals() {
        let info = MusicPlayer.parse(joined([
            "playing", "Ditto", "NewJeans", "OMG", "NewJeans", "185,5", "12,25", "ABCDEF0123", "0", "1", "2", "1", "1",
        ]))
        XCTAssertEqual(info.state, .playing)
        XCTAssertEqual(info.title, "Ditto")
        XCTAssertEqual(info.duration, 185.5)
        XCTAssertEqual(info.position, 12.25)
        XCTAssertEqual(info.id, "ABCDEF0123")
        XCTAssertEqual(info.trackNumber, 1)
        XCTAssertEqual(info.trackCount, 2)
    }

    func testMusicFastForwardingIsPlaying() {
        let info = MusicPlayer.parse(joined(["fast forwarding", "A", "B", "C", "", "100", "1", "", "0", "0", "0", "0", "0"]))
        XCTAssertEqual(info.state, .playing)
        XCTAssertEqual(info.id, "A|B|C")
    }

    // MARK: - Spotify

    func testSpotifyParsesPlayingTrack() {
        let info = SpotifyPlayer.parse(joined([
            "playing", "Hype Boy", "NewJeans", "New Jeans", "NewJeans", "179000", "12,5",
            "spotify:track:0a4MMyCrzT0En247IhqZbD", "3", "1", "https://i.scdn.co/image/ab67616d0000b273",
        ]))
        XCTAssertEqual(info.state, .playing)
        XCTAssertEqual(info.title, "Hype Boy")
        XCTAssertEqual(info.artist, "NewJeans")
        XCTAssertEqual(info.album, "New Jeans")
        XCTAssertEqual(info.albumArtist, "NewJeans")
        XCTAssertEqual(info.duration, 179)
        XCTAssertEqual(info.position, 12.5)
        XCTAssertEqual(info.id, "spotify:track:0a4MMyCrzT0En247IhqZbD")
        XCTAssertEqual(info.trackNumber, 3)
        XCTAssertEqual(info.discNumber, 1)
        XCTAssertEqual(info.trackCount, 0)
        XCTAssertEqual(info.discCount, 0)
        XCTAssertEqual(info.artworkURL, URL(string: "https://i.scdn.co/image/ab67616d0000b273"))
        XCTAssertFalse(info.isAd)
    }

    func testSpotifyPaused() {
        let info = SpotifyPlayer.parse(joined(["paused", "A", "B", "C", "", "60000", "0", "spotify:track:x", "1", "1", ""]))
        XCTAssertEqual(info.state, .paused)
        XCTAssertNil(info.artworkURL)
    }

    func testSpotifyStoppedOrNotRunning() {
        XCTAssertEqual(SpotifyPlayer.parse("stopped").state, .stopped)
        XCTAssertEqual(SpotifyPlayer.parse("notrunning").state, .stopped)
        XCTAssertEqual(SpotifyPlayer.parse("").state, .stopped)
    }

    /// 광고는 고르기에서는 재생 중으로 보고(다른 플레이어로 넘어가지 않게), 화면에는 정지로 보낸다.
    func testSpotifyAdIsPlayingButDisplayedAsStopped() {
        let info = SpotifyPlayer.parse(joined(["playing", "Spotify", "", "", "", "30000", "3", "spotify:ad:000000012c95ec5a", "0", "0", ""]))
        XCTAssertTrue(info.isAd)
        XCTAssertEqual(info.state, .playing)
        XCTAssertEqual(info.displayed.state, .stopped)
    }

    func testDisplayedKeepsRegularTrack() {
        let info = SpotifyPlayer.parse(joined(["playing", "A", "B", "C", "", "60000", "0", "spotify:track:x", "1", "1", ""]))
        XCTAssertEqual(info.displayed, info)
    }
}
