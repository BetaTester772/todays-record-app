import XCTest
@testable import TodaysRecord

/// 명세 4.10 업데이트 확인.
final class UpdaterTests: XCTestCase {
    func testVersionsCompareByNumberNotText() {
        XCTAssertTrue(Updater.isNewer("0.10.0", than: "0.9.2"))
        XCTAssertTrue(Updater.isNewer("0.3.1", than: "0.3.0"))
        XCTAssertTrue(Updater.isNewer("1.0", than: "0.99.9"))
        XCTAssertFalse(Updater.isNewer("0.3.0", than: "0.3.0"))
        XCTAssertFalse(Updater.isNewer("0.3", than: "0.3.0"))
        XCTAssertFalse(Updater.isNewer("0.2.0", than: "0.3.0"))
    }

    func testParsesLatestReleaseAssets() throws {
        let json = """
        {"tag_name": "v0.4.0", "html_url": "https://github.com/soysaucecrab/todays-record-app/releases/tag/v0.4.0",
         "assets": [
           {"name": "TodaysRecord-0.4.0.zip.sha256", "browser_download_url": "https://example.com/TodaysRecord-0.4.0.zip.sha256"},
           {"name": "TodaysRecord-0.4.0.zip", "browser_download_url": "https://example.com/TodaysRecord-0.4.0.zip"}
         ]}
        """
        let release = try XCTUnwrap(Updater.parse(Data(json.utf8)))
        XCTAssertEqual(release.version, "0.4.0")
        XCTAssertEqual(release.zipURL.lastPathComponent, "TodaysRecord-0.4.0.zip")
        XCTAssertEqual(release.checksumURL.lastPathComponent, "TodaysRecord-0.4.0.zip.sha256")
    }

    func testReleaseWithoutZipIsIgnored() {
        let json = #"{"tag_name": "v0.4.0", "html_url": "https://example.com", "assets": []}"#
        XCTAssertNil(Updater.parse(Data(json.utf8)))
    }
}
