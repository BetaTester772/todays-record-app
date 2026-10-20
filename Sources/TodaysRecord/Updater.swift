import AppKit
import CryptoKit
import Security

/// GitHub 릴리스로 새 버전을 확인하고, 사용자가 원하면 내려받아 설치한다. 명세 4.10.
/// 네트워크와 파일 작업은 메인 스레드 밖에서 하고, 결과는 메인 스레드로 알린다.
final class Updater {
    struct Release: Equatable {
        let version: String
        let pageURL: URL
        let zipURL: URL
        let checksumURL: URL
    }

    enum State: Equatable {
        case idle
        case checking
        case upToDate
        case available(Release)
        case installing(Release)
        case failed(String)
    }

    static let latestURL = URL(string: "https://api.github.com/repos/soysaucecrab/todays-record-app/releases/latest")!
    static let releasesPage = URL(string: "https://github.com/soysaucecrab/todays-record-app/releases")!
    private static let checkInterval: TimeInterval = 24 * 60 * 60

    /// 메인 스레드에서 불린다.
    var onChange: ((State) -> Void)?
    private(set) var state: State = .idle {
        didSet { if state != oldValue { onChange?(state) } }
    }

    private let settings: Settings
    private var timer: Timer?
    private let currentVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"

    init(settings: Settings) {
        self.settings = settings
    }

    /// 자동 확인이 켜져 있으면 잠시 뒤 한 번, 그 뒤로 하루에 한 번 확인한다.
    func start() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in self?.checkIfDue() }
        let timer = Timer(timeInterval: 60 * 60, repeats: true) { [weak self] _ in self?.checkIfDue() }
        timer.tolerance = 300
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func checkIfDue() {
        guard settings.autoUpdateCheck else { return }
        if let last = settings.lastUpdateCheck, Date().timeIntervalSince(last) < Self.checkInterval { return }
        check()
    }

    // MARK: - 확인

    func check() {
        if case .installing = state { return }
        state = .checking
        var request = URLRequest(url: Self.latestURL)
        request.timeoutInterval = 15
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            let ok = (response as? HTTPURLResponse)?.statusCode == 200
            let release = ok ? data.flatMap(Self.parse) : nil
            DispatchQueue.main.async {
                guard let self else { return }
                self.settings.lastUpdateCheck = Date()
                guard let release else {
                    Log.app.error("업데이트 확인 실패 \(error?.localizedDescription ?? "응답 없음", privacy: .public)")
                    self.state = .failed("Couldn't check for updates.")
                    return
                }
                let newer = Self.isNewer(release.version, than: self.currentVersion)
                Log.app.info("업데이트 확인: 최신 \(release.version, privacy: .public), 지금 \(self.currentVersion, privacy: .public)")
                self.state = newer ? .available(release) : .upToDate
            }
        }.resume()
    }

    /// releases/latest 응답에서 버전, zip, SHA-256 파일을 꺼낸다.
    static func parse(_ data: Data) -> Release? {
        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let tag = json["tag_name"] as? String,
            let page = (json["html_url"] as? String).flatMap(URL.init(string:)),
            let assets = json["assets"] as? [[String: Any]]
        else { return nil }
        func asset(_ test: (String) -> Bool) -> URL? {
            assets.first { test($0["name"] as? String ?? "") }
                .flatMap { $0["browser_download_url"] as? String }
                .flatMap(URL.init(string:))
        }
        guard let zip = asset({ $0.hasPrefix("TodaysRecord-") && $0.hasSuffix(".zip") }),
              let sum = asset({ $0.hasSuffix(".zip.sha256") }) else { return nil }
        let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        return Release(version: version, pageURL: page, zipURL: zip, checksumURL: sum)
    }

    /// "0.10.0"이 "0.9.2"보다 새 버전인지처럼 숫자 단위로 비교한다.
    static func isNewer(_ candidate: String, than current: String) -> Bool {
        let a = candidate.split(separator: ".").map { Int($0) ?? 0 }
        let b = current.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0, y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    // MARK: - 설치

    /// zip을 받아 SHA-256과 서명을 확인한 뒤 지금 앱과 바꾸고 다시 실행한다.
    /// 어느 단계든 실패하면 아무것도 바꾸지 않고 릴리스 페이지를 연다.
    func install(_ release: Release) {
        state = .installing(release)
        let appURL = Bundle.main.bundleURL
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = Result { try Self.download(release, replacing: appURL) }
            DispatchQueue.main.async {
                guard let self else { return }
                switch result {
                case .success(let installed):
                    Log.app.info("업데이트 설치 \(release.version, privacy: .public), 다시 실행")
                    Self.relaunch(installed)
                case .failure(let error):
                    Log.app.error("업데이트 설치 실패 \(String(describing: error), privacy: .public)")
                    self.state = .failed("Couldn't install the update. Opening the download page instead.")
                    NSWorkspace.shared.open(release.pageURL)
                }
            }
        }
    }

    private enum InstallError: Error {
        case checksum, notAnApp, wrongApp, signature, otherSigner, notWritable(String)
    }

    /// 메인 스레드 밖에서 부른다.
    private static func download(_ release: Release, replacing appURL: URL) throws -> URL {
        let fm = FileManager.default
        let work = fm.temporaryDirectory.appendingPathComponent("TodaysRecord-update-\(UUID().uuidString)")
        try fm.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: work) }

        guard fm.isWritableFile(atPath: appURL.deletingLastPathComponent().path) else {
            throw InstallError.notWritable(appURL.deletingLastPathComponent().path)
        }

        let zipData = try Data(contentsOf: release.zipURL)
        let expected = try String(contentsOf: release.checksumURL, encoding: .utf8)
            .split(separator: " ").first.map(String.init)?.lowercased() ?? ""
        let actual = SHA256.hash(data: zipData).map { String(format: "%02x", $0) }.joined()
        guard !expected.isEmpty, actual == expected else { throw InstallError.checksum }

        let zip = work.appendingPathComponent("update.zip")
        try zipData.write(to: zip)
        try run("/usr/bin/ditto", ["-x", "-k", zip.path, work.path])
        let newApp = work.appendingPathComponent("TodaysRecord.app")
        guard let bundle = Bundle(url: newApp), bundle.bundleIdentifier == Bundle.main.bundleIdentifier else {
            throw fm.fileExists(atPath: newApp.path) ? InstallError.wrongApp : InstallError.notAnApp
        }
        do { try run("/usr/bin/codesign", ["--verify", "--strict", newApp.path]) } catch { throw InstallError.signature }
        // 지금 앱이 인증서로 서명돼 있으면, 새 앱도 같은 인증서로 서명된 것만 받는다(릴리스가 바꿔치기돼도 설치하지 않게).
        if let requirement = currentRequirement(), !satisfies(newApp, requirement) { throw InstallError.otherSigner }

        // 지금 앱 자리에 새 앱을 원자적으로 넣는다. 예전 앱은 휴지통 대신 지운다.
        _ = try fm.replaceItemAt(appURL, withItemAt: newApp, backupItemName: nil, options: [])
        return appURL
    }

    /// 지금 실행 중인 앱의 designated requirement. 애드혹 서명(인증서 없음)이면 nil.
    private static func currentRequirement() -> SecRequirement? {
        var code: SecCode?
        var staticCode: SecStaticCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code,
              SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else { return nil }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let certificates = (info as? [String: Any])?[kSecCodeInfoCertificates as String] as? [SecCertificate],
              !certificates.isEmpty else { return nil }
        var requirement: SecRequirement?
        guard SecCodeCopyDesignatedRequirement(staticCode, [], &requirement) == errSecSuccess else { return nil }
        return requirement
    }

    private static func satisfies(_ appURL: URL, _ requirement: SecRequirement) -> Bool {
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(appURL as CFURL, [], &staticCode) == errSecSuccess, let staticCode else { return false }
        let flags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSStrictValidate)
        return SecStaticCodeCheckValidity(staticCode, flags, requirement) == errSecSuccess
    }

    private static func run(_ tool: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw NSError(domain: tool, code: Int(process.terminationStatus))
        }
    }

    /// 이 앱이 끝난 뒤 새 앱을 연다.
    private static func relaunch(_ appURL: URL) {
        let pid = ProcessInfo.processInfo.processIdentifier
        let shell = Process()
        shell.executableURL = URL(fileURLWithPath: "/bin/sh")
        shell.arguments = ["-c", "while kill -0 \(pid) 2>/dev/null; do sleep 0.2; done; open \"$0\"", appURL.path]
        try? shell.run()
        NSApp.terminate(nil)
    }
}
