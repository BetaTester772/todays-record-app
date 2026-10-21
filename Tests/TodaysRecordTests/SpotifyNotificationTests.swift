import XCTest
@testable import TodaysRecord

/// Spotify 알림 값으로 바로 반영하기. 명세 4.5.1.
final class SpotifyNotificationTests: XCTestCase {
    /// 2026-10 --log-nowplaying로 찍은 실제 알림의 키와 값 모양 그대로.
    private func userInfo(state: String = "Playing", id: String = "spotify:track:37R0bQOQj5a7DOqh1TGzvB") -> [AnyHashable: Any] {
        [
            "Album": "Nine Track Mind", "Album Artist": "Charlie Puth", "Artist": "Charlie Puth",
            "Disc Number": NSNumber(value: 1), "Duration": NSNumber(value: 194453), "Has Artwork": NSNumber(value: true),
            "Name": "One Call Away", "Play Count": NSNumber(value: 0), "Playback Position": NSNumber(value: 181.998),
            "Player State": state, "Popularity": NSNumber(value: 72), "Track ID": id, "Track Number": NSNumber(value: 1),
        ]
    }

    func testPlayingTrackFromNotification() throws {
        let info = try XCTUnwrap(SpotifyPlayer.parse(notification: userInfo()))
        XCTAssertEqual(info.state, .playing)
        XCTAssertEqual(info.title, "One Call Away")
        XCTAssertEqual(info.artist, "Charlie Puth")
        XCTAssertEqual(info.album, "Nine Track Mind")
        XCTAssertEqual(info.albumArtist, "Charlie Puth")
        XCTAssertEqual(info.duration, 194.453, accuracy: 0.001)
        XCTAssertEqual(info.position, 181.998, accuracy: 0.001)
        XCTAssertEqual(info.id, "spotify:track:37R0bQOQj5a7DOqh1TGzvB")
        XCTAssertEqual(info.trackNumber, 1)
        XCTAssertEqual(info.discNumber, 1)
        // 알림에는 커버 주소가 없어 AppleScript로 채워야 한다.
        XCTAssertNil(info.artworkURL)
        XCTAssertTrue(info.needsDetails)
    }

    func testPausedAndStopped() throws {
        XCTAssertEqual(try XCTUnwrap(SpotifyPlayer.parse(notification: userInfo(state: "Paused"))).state, .paused)
        XCTAssertEqual(try XCTUnwrap(SpotifyPlayer.parse(notification: ["Player State": "Stopped"])).state, .stopped)
    }

    func testAdFromNotification() throws {
        let info = try XCTUnwrap(SpotifyPlayer.parse(notification: userInfo(id: "spotify:ad:000000012c95ec5a")))
        XCTAssertTrue(info.isAd)
        XCTAssertEqual(info.displayed.state, .stopped)
    }

    /// 상태를 알 수 없는 알림은 쓰지 않고 AppleScript 결과를 기다린다.
    func testUnknownNotificationIsIgnored() {
        XCTAssertNil(SpotifyPlayer.parse(notification: [:]))
        XCTAssertNil(SpotifyPlayer.parse(notification: ["Player State": "Playing"]))
    }

    func testAppleScriptResultHasDetails() {
        let info = SpotifyPlayer.parse("playing\u{1F}A\u{1F}B\u{1F}C\u{1F}\u{1F}60000\u{1F}0\u{1F}spotify:track:x\u{1F}1\u{1F}1\u{1F}https://i.scdn.co/image/x")
        XCTAssertFalse(info.needsDetails)
    }
}

/// 커버를 언제 가져오나. 알림만으로 만든 정보에는 커버 주소가 없다.
final class ArtworkTimingTests: XCTestCase {
    private func info(_ id: String, needsDetails: Bool, state: NowPlayingInfo.State = .playing) -> NowPlayingInfo {
        var info = NowPlayingInfo()
        info.state = state
        info.id = id
        info.title = id
        info.needsDetails = needsDetails
        return info
    }

    func testNewTrackWithDetailsFetchesNow() {
        XCTAssertTrue(NowPlaying.shouldFetchArtwork(new: info("b", needsDetails: false), previous: info("a", needsDetails: false), hasArt: true))
    }

    func testNewTrackFromNotificationWaitsForDetails() {
        XCTAssertFalse(NowPlaying.shouldFetchArtwork(new: info("b", needsDetails: true), previous: info("a", needsDetails: false), hasArt: true))
    }

    func testDetailsArrivingForSameTrackFetchesThen() {
        XCTAssertTrue(NowPlaying.shouldFetchArtwork(new: info("b", needsDetails: false), previous: info("b", needsDetails: true), hasArt: false))
    }

    func testSameTrackAlreadyCompleteDoesNotFetchAgain() {
        XCTAssertFalse(NowPlaying.shouldFetchArtwork(new: info("b", needsDetails: false), previous: info("b", needsDetails: false), hasArt: false))
        XCTAssertFalse(NowPlaying.shouldFetchArtwork(new: info("b", needsDetails: false), previous: info("b", needsDetails: true), hasArt: true))
    }

    func testStoppedNeverFetches() {
        XCTAssertFalse(NowPlaying.shouldFetchArtwork(new: info("b", needsDetails: false, state: .stopped), previous: info("a", needsDetails: false), hasArt: false))
    }
}
