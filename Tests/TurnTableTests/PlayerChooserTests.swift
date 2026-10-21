import XCTest
@testable import TurnTable

/// 명세 4.5.2 보여줄 플레이어 고르기.
final class PlayerChooserTests: XCTestCase {
    func testNothingShownUntilAPlayerReportsActivity() {
        var chooser = PlayerChooser()
        chooser.update(.music, .stopped)
        XCTAssertNil(chooser.shown)
    }

    func testFirstPlayingPlayerIsShown() {
        var chooser = PlayerChooser()
        chooser.update(.spotify, .playing)
        XCTAssertEqual(chooser.shown, .spotify)
    }

    func testPausedPlayerIsShownWhenNothingElse() {
        var chooser = PlayerChooser()
        chooser.update(.spotify, .paused)
        XCTAssertEqual(chooser.shown, .spotify)
    }

    func testLaterStartIsIgnoredWhileShownIsPlaying() {
        var chooser = PlayerChooser()
        chooser.update(.music, .playing)
        chooser.update(.spotify, .playing)
        XCTAssertEqual(chooser.shown, .music)
    }

    func testBothPausedKeepsFirst() {
        var chooser = PlayerChooser()
        chooser.update(.music, .paused)
        chooser.update(.spotify, .paused)
        XCTAssertEqual(chooser.shown, .music)
    }

    func testOtherStartSwitchesWhenShownIsPaused() {
        var chooser = PlayerChooser()
        chooser.update(.music, .paused)
        chooser.update(.spotify, .paused)
        chooser.update(.spotify, .playing)
        XCTAssertEqual(chooser.shown, .spotify)
    }

    func testShownPauseSwitchesToPlayingOther() {
        var chooser = PlayerChooser()
        chooser.update(.music, .playing)
        chooser.update(.spotify, .playing)
        chooser.update(.music, .paused)
        XCTAssertEqual(chooser.shown, .spotify)
    }

    func testShownPauseStaysWhenOtherIsPaused() {
        var chooser = PlayerChooser()
        chooser.update(.music, .playing)
        chooser.update(.spotify, .paused)
        chooser.update(.music, .paused)
        XCTAssertEqual(chooser.shown, .music)
    }

    func testShownStopSwitchesToPausedOther() {
        var chooser = PlayerChooser()
        chooser.update(.music, .playing)
        chooser.update(.spotify, .paused)
        chooser.update(.music, .stopped)
        XCTAssertEqual(chooser.shown, .spotify)
    }

    func testShownStopPrefersPlayingOther() {
        var chooser = PlayerChooser()
        chooser.update(.spotify, .playing)
        chooser.update(.music, .playing)
        chooser.update(.spotify, .stopped)
        XCTAssertEqual(chooser.shown, .music)
    }

    func testPausedOtherIsTakenAfterShownStopped() {
        var chooser = PlayerChooser()
        chooser.update(.music, .playing)
        chooser.update(.music, .stopped)
        chooser.update(.spotify, .paused)
        XCTAssertEqual(chooser.shown, .spotify)
    }

    func testChoiceSwitchesShownPlayer() {
        var chooser = PlayerChooser()
        chooser.update(.music, .playing)
        chooser.update(.spotify, .playing)
        chooser.choose(.spotify)
        XCTAssertEqual(chooser.shown, .spotify)
    }

    /// 재생 중 다음 곡으로 넘어가는 알림(재생 → 재생)은 재생 시작이 아니다.
    func testChosenPausedPlayerSurvivesBackgroundTrackChange() {
        var chooser = PlayerChooser()
        chooser.update(.music, .playing)
        chooser.update(.spotify, .playing)
        chooser.update(.music, .paused)
        XCTAssertEqual(chooser.shown, .spotify)
        chooser.choose(.music)
        chooser.update(.spotify, .playing)
        XCTAssertEqual(chooser.shown, .music)
    }

    func testChosenPausedPlayerYieldsWhenOtherRestarts() {
        var chooser = PlayerChooser()
        chooser.update(.music, .paused)
        chooser.update(.spotify, .playing)
        chooser.choose(.music)
        chooser.update(.spotify, .paused)
        chooser.update(.spotify, .playing)
        XCTAssertEqual(chooser.shown, .spotify)
    }
}
