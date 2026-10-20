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

/// 명세 4.10 설치할 자리.
final class UpdaterLocationTests: XCTestCase {
    func testTranslocatedAppInstallsToApplications() {
        let translocated = URL(fileURLWithPath: "/private/var/folders/ab/T/AppTranslocation/1234-ABCD/d/TodaysRecord.app")
        XCTAssertTrue(Updater.isTranslocated(translocated))
        XCTAssertTrue(Updater.shouldOfferMove(translocated))
        XCTAssertEqual(Updater.installLocation(for: translocated).path, "/Applications/TodaysRecord.app")
    }

    func testAppInDownloadsIsOfferedAMove() {
        let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
        XCTAssertTrue(Updater.shouldOfferMove(downloads.appendingPathComponent("TodaysRecord.app")))
        XCTAssertFalse(Updater.shouldOfferMove(URL(fileURLWithPath: "/Applications/TodaysRecord.app")))
    }

    func testWritableLocationIsKept() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("loc-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let app = dir.appendingPathComponent("TodaysRecord.app")
        XCTAssertEqual(Updater.installLocation(for: app), app)
    }
}
