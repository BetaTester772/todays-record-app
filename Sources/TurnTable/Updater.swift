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
        // 릴리스에는 TurnTable-<v>.zip과 TurnTable-<v>.sha256을 올린다(0.7.2까지는 옛 이름 zip도 함께 있었다).
        let names = assets.compactMap { $0["name"] as? String }
        guard let zipName = names.first(where: { $0.hasPrefix(Self.appName + "-") && $0.hasSuffix(".zip") }),
              let zip = asset({ $0 == zipName }),
              let sum = asset({ $0 == zipName.dropLast(4) + ".sha256" }) else { return nil }
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

    /// zip을 받아 SHA-256과 서명을 확인한 뒤 설치하고 다시 실행한다.
    /// 어느 단계든 실패하면 아무것도 바꾸지 않고, 이유를 onFailure로 알린다.
    var onFailure: ((String, Release) -> Void)?

    func install(_ release: Release) {
        state = .installing(release)
        let appURL = Bundle.main.bundleURL
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = Result { try Self.downloadAndInstall(release, current: appURL) }
            DispatchQueue.main.async {
                guard let self else { return }
                switch result {
                case .success(let installed):
                    Log.app.info("업데이트 설치 \(release.version, privacy: .public) → \(installed.path, privacy: .public), 다시 실행")
                    Self.relaunch(installed)
                case .failure(let error):
                    let reason = (error as? InstallError)?.message ?? error.localizedDescription
                    Log.app.error("업데이트 설치 실패 \(String(describing: error), privacy: .public)")
                    self.state = .failed(reason)
                    self.onFailure?(reason, release)
                }
            }
        }
    }

    enum InstallError: Error {
        case download, checksum, notAnApp, wrongApp, signature, otherSigner, cancelled, notWritable(String)

        /// 알림 창에 보이는 문구.
        var message: String {
            switch self {
            case .download: return "Couldn't download the update. Check your internet connection."
            case .checksum: return "The download didn't match its checksum, so it wasn't installed."
            case .notAnApp, .wrongApp: return "The download wasn't a TurnTable app, so it wasn't installed."
            case .signature: return "The download's signature is broken, so it wasn't installed."
            case .otherSigner: return "The update is signed by someone else, so it wasn't installed."
            case .cancelled: return "The update was cancelled."
            case .notWritable(let path): return "No permission to write to \(path)."
            }
        }
    }

    /// 메인 스레드 밖에서 부른다.
    private static func downloadAndInstall(_ release: Release, current appURL: URL) throws -> URL {
        let fm = FileManager.default
        let work = fm.temporaryDirectory.appendingPathComponent("TurnTable-update-\(UUID().uuidString)")
        try fm.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: work) }

        let zipData: Data, expected: String
        do {
            zipData = try Data(contentsOf: release.zipURL)
            expected = try String(contentsOf: release.checksumURL, encoding: .utf8)
                .split(separator: " ").first.map(String.init)?.lowercased() ?? ""
        } catch { throw InstallError.download }
        let actual = SHA256.hash(data: zipData).map { String(format: "%02x", $0) }.joined()
        guard !expected.isEmpty, actual == expected else { throw InstallError.checksum }

        let zip = work.appendingPathComponent("update.zip")
        try zipData.write(to: zip)
        try run("/usr/bin/ditto", ["-x", "-k", zip.path, work.path])
        // zip 안에는 TurnTable.app이 있다.
        let newApp = work.appendingPathComponent(Self.appName + ".app")
        guard let bundle = Bundle(url: newApp), bundle.bundleIdentifier == Bundle.main.bundleIdentifier else {
            throw fm.fileExists(atPath: newApp.path) ? InstallError.wrongApp : InstallError.notAnApp
        }
        do { try run("/usr/bin/codesign", ["--verify", "--strict", newApp.path]) } catch { throw InstallError.signature }
        // 지금 앱이 인증서로 서명돼 있으면, 새 앱도 같은 인증서로 서명된 것만 받는다(릴리스가 바꿔치기돼도 설치하지 않게).
        if let requirement = currentRequirement(), !satisfies(newApp, requirement) { throw InstallError.otherSigner }

        let target = installLocation(for: appURL)
        try place(newApp, at: target)
        // 옛 이름 앱은 휴지통으로(지금 실행 중인 앱은 끝날 때까지 그대로 돈다)
        if target != appURL, !isTranslocated(appURL), fm.fileExists(atPath: appURL.path) { try? fm.trashItem(at: appURL, resultingItemURL: nil) }
        return target
    }

    /// 0.5.0부터의 앱 파일 이름(예전 TodaysRecord.app). 번들 ID는 com.todaysrecord.app 그대로라
    /// 설정, Music·Spotify 권한, 로그인 항목이 이어진다.
    static let appName = "TurnTable"

    /// 쓸 수 있는 폴더에 있는 옛 이름 앱(TodaysRecord.app)은 스스로 TurnTable.app으로 이름을 바꾼다.
    /// 바꿨으면 새 위치를, 아니면 nil. 앱 시작 때 가장 먼저 부르고, 바꿨으면 새 위치에서 다시 연다.
    static func renameIfNeeded(_ appURL: URL) -> URL? {
        let fm = FileManager.default, parent = appURL.deletingLastPathComponent()
        let target = parent.appendingPathComponent(appName + ".app")
        guard appURL.lastPathComponent == "TodaysRecord.app", !isTranslocated(appURL),
              fm.isWritableFile(atPath: parent.path), !fm.fileExists(atPath: target.path) else { return nil }
        do { try fm.moveItem(at: appURL, to: target) } catch { return nil }
        return target
    }

    /// 인터넷에서 받은 앱을 받은 자리에서 열면 macOS가 읽기 전용 임시 위치(App Translocation)에서 실행한다.
    static func isTranslocated(_ appURL: URL) -> Bool {
        appURL.path.contains("/AppTranslocation/")
    }

    /// 다운로드 폴더나 임시 위치에서 실행 중이면 응용 프로그램 폴더로 옮기기를 권한다.
    static func shouldOfferMove(_ appURL: URL) -> Bool {
        let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first?.path ?? "~/Downloads"
        return isTranslocated(appURL) || appURL.path.hasPrefix(downloads + "/")
    }

    /// 지금 자리에 쓸 수 있으면 그 자리, 아니면(임시 위치 등) 응용 프로그램 폴더.
    /// 옛 이름 앱(TodaysRecord.app)은 같은 폴더에 TurnTable.app으로 설치한다.
    static func installLocation(for appURL: URL) -> URL {
        if !isTranslocated(appURL), FileManager.default.isWritableFile(atPath: appURL.deletingLastPathComponent().path) {
            return appURL.deletingLastPathComponent().appendingPathComponent(appName + ".app")
        }
        return URL(fileURLWithPath: "/Applications/\(appName).app")
    }

    /// 새 앱을 target에 둔다. 폴더에 쓸 수 없으면 관리자 암호를 물어서 복사한다.
    /// 앱이 직접 받은 사본이라 “인터넷에서 받음” 표시는 붙이지 않는다.
    static func place(_ newApp: URL, at target: URL) throws {
        let fm = FileManager.default
        if fm.isWritableFile(atPath: target.deletingLastPathComponent().path) {
            if fm.fileExists(atPath: target.path) {
                _ = try fm.replaceItemAt(target, withItemAt: newApp, backupItemName: nil, options: [])
            } else {
                try run("/usr/bin/ditto", ["--noqtn", newApp.path, target.path])
            }
            return
        }
        // 표준 사용자 계정 등: macOS 관리자 암호 창으로 허락받아 복사한다.
        let quote = { (path: String) in "\"" + path.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\"" }
        let source = """
        do shell script "/bin/rm -rf " & quoted form of \(quote(target.path)) & " && /usr/bin/ditto --noqtn " & quoted form of \(quote(newApp.path)) & " " & quoted form of \(quote(target.path)) with administrator privileges
        """
        var error: NSDictionary?
        _ = NSAppleScript(source: source)?.executeAndReturnError(&error)
        if let error {
            // -128: 사용자가 암호 창에서 취소
            throw (error[NSAppleScript.errorNumber] as? Int) == -128 ? InstallError.cancelled : InstallError.notWritable(target.deletingLastPathComponent().path)
        }
    }

    /// 다운로드 폴더나 임시 위치에서 도는 앱을 응용 프로그램 폴더로 옮기고 거기서 다시 연다.
    /// 메인 스레드 밖에서 부른다. 성공하면 옮긴 위치를 돌려준다.
    static func moveToApplications(_ appURL: URL) throws -> URL {
        let fm = FileManager.default
        let target = URL(fileURLWithPath: "/Applications/\(appName).app")
        let work = fm.temporaryDirectory.appendingPathComponent("TurnTable-move-\(UUID().uuidString)")
        try fm.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: work) }
        let copy = work.appendingPathComponent(appName + ".app")
        try run("/usr/bin/ditto", ["--noqtn", appURL.path, copy.path])
        try place(copy, at: target)
        // 받은 자리에 남은 원본은 휴지통으로(임시 위치에서 돌고 있으면 원본 위치를 알 수 없어 그대로 둔다).
        if !isTranslocated(appURL), appURL != target { try? fm.trashItem(at: appURL, resultingItemURL: nil) }
        return target
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
    static func relaunch(_ appURL: URL) {
        let pid = ProcessInfo.processInfo.processIdentifier
        let shell = Process()
        shell.executableURL = URL(fileURLWithPath: "/bin/sh")
        shell.arguments = ["-c", "while kill -0 \(pid) 2>/dev/null; do sleep 0.2; done; open \"$0\"", appURL.path]
        try? shell.run()
        NSApp.terminate(nil)
    }
}
