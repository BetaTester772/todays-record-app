import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let options: LaunchOptions
    private var wallpaper: WallpaperController?
    private var statusMenu: StatusMenu?
    private var nowPlaying: NowPlaying?
    private let volume = SystemVolume()
    private let settings = Settings()
    private let power = PowerWatcher()
    private let settingsModel = SettingsModel()
    private lazy var settingsWindow = SettingsWindowController(model: settingsModel)
    private var defaultsObserver: NSObjectProtocol?
    private lazy var updater = Updater(settings: settings)
    /// 메뉴의 Check for Updates…로 확인 중이면 결과를 창으로 알린다.
    private var reportUpdateCheck = false
    private var applyScheduled = false

    init(options: LaunchOptions) {
        self.options = options
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let menu = StatusMenu(settings: settings)
        let clearRecord: () -> Void = { [weak self] in self?.wallpaper?.webViews.forEach { $0.clearRecord() } }
        menu.onClearRecord = clearRecord
        menu.onOpenSettings = { [weak self] in self?.settingsWindow.show() }
        settingsModel.onClearRecord = clearRecord
        statusMenu = menu

        updater.onChange = { [weak self] state in
            guard let self else { return }
            self.statusMenu?.setUpdate(state)
            self.settingsModel.update = state
            if self.options.installUpdate, case .available(let release) = state { self.updater.install(release) }
            if self.reportUpdateCheck { self.reportUpdateResult(state) }
        }
        menu.onInstallUpdate = { [weak self] in self?.confirmUpdate() }
        menu.onCheckForUpdates = { [weak self] in
            self?.reportUpdateCheck = true
            self?.updater.check()
        }
        settingsModel.onInstallUpdate = { [weak self] in self?.confirmUpdate() }
        settingsModel.onCheckForUpdates = { [weak self] in self?.updater.check() }
        updater.onFailure = { [weak self] reason, release in self?.showUpdateFailure(reason, release) }
        updater.start()
        if options.installUpdate { updater.check() }

        // 메뉴와 설정 창은 UserDefaults에 바로 쓴다. 바뀌면 한 번에 모아 화면에 반영한다.
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.scheduleApplySettings()
        }

        wallpaper = WallpaperController(options: options, settings: settings) { [weak self] webView in
            self?.sendCurrentState(to: webView)
        }
        power.start()
        wallpaper?.fps = frameRate
        wallpaper?.start()
        power.onPausedChange = { [weak self] paused in
            self?.wallpaper?.globalPaused = paused
            self?.nowPlaying?.suspended = paused
        }
        power.onBatteryChange = { [weak self] _ in
            guard let self else { return }
            self.wallpaper?.fps = self.frameRate
        }

        volume.onChange = { [weak self] level in
            self?.wallpaper?.webViews.forEach { $0.sendVolume(level.payload) }
        }
        volume.start()

        if options.openSettings { settingsWindow.show(tab: options.settingsTab) }
        offerMoveToApplications()

        // --demo면 index.html의 미리보기 데이터를 쓰므로 Music, Spotify를 보지 않는다.
        guard !options.demo else { return }
        let nowPlaying = NowPlaying(logToStdout: options.logNowPlaying)
        nowPlaying.onUpdate = { [weak self] info in
            self?.statusMenu?.update(info)
            self?.wallpaper?.webViews.forEach { $0.sendNowPlaying(info.payload) }
        }
        nowPlaying.onArt = { [weak self] dataURL, version in
            self?.wallpaper?.webViews.forEach { $0.sendArt(dataURL: dataURL, version: version) }
        }
        nowPlaying.onPermissionChange = { [weak self] denied in
            self?.statusMenu?.setPermissionNeeded(for: denied)
            self?.settingsModel.deniedPlayers = denied
        }
        statusMenu?.playerChoice = { [weak nowPlaying] in
            (PlayerKind.allCases.filter(\.isRunning), nowPlaying?.shownPlayer)
        }
        statusMenu?.onChoosePlayer = { [weak nowPlaying] kind in
            nowPlaying?.choose(kind)
        }
        self.nowPlaying = nowPlaying
        nowPlaying.start()
    }

    /// 업데이트 실패 이유를 알린다. 다운로드 페이지에서 직접 받을 수도 있다.
    private func showUpdateFailure(_ reason: String, _ release: Updater.Release) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Couldn't update to v\(release.version)"
        alert.informativeText = reason + "\n\nYou can download the update and install it yourself."
        alert.addButton(withTitle: "Open Download Page")
        alert.addButton(withTitle: "OK")
        if alert.runModal() == .alertFirstButtonReturn { NSWorkspace.shared.open(release.pageURL) }
    }

    /// 다운로드 폴더나 임시 위치(App Translocation)에서 실행됐으면 응용 프로그램 폴더로 옮기기를 권한다.
    /// 그 자리에서는 앱이 자기 자신을 업데이트할 수 없다.
    private func offerMoveToApplications() {
        let appURL = Bundle.main.bundleURL
        guard Updater.shouldOfferMove(appURL) else { return }
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Move 오늘의 판 to the Applications folder?"
        alert.informativeText = "It's running from your Downloads folder or a temporary location, where it can't update itself."
        alert.addButton(withTitle: "Move to Applications")
        alert.addButton(withTitle: "Not Now")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result { try Updater.moveToApplications(appURL) }
            DispatchQueue.main.async {
                switch result {
                case .success(let moved):
                    Log.app.info("응용 프로그램 폴더로 옮김 \(moved.path, privacy: .public)")
                    Updater.relaunch(moved)
                case .failure(let error):
                    Log.app.error("옮기기 실패 \(String(describing: error), privacy: .public)")
                    let fail = NSAlert()
                    fail.alertStyle = .warning
                    fail.messageText = "Couldn't move 오늘의 판"
                    fail.informativeText = ((error as? Updater.InstallError)?.message ?? error.localizedDescription)
                        + "\n\nYou can drag it into the Applications folder in Finder instead."
                    fail.runModal()
                }
            }
        }
    }

    /// Check for Updates… 결과: 새 버전이면 설치를 묻고, 아니면 알린다.
    private func reportUpdateResult(_ state: Updater.State) {
        switch state {
        case .checking, .idle, .installing:
            return
        case .available:
            reportUpdateCheck = false
            confirmUpdate()
        case .upToDate, .failed:
            reportUpdateCheck = false
            NSApp.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
            if case .failed(let message) = state {
                alert.messageText = "Couldn't check for updates"
                alert.informativeText = message
            } else {
                alert.messageText = "You're up to date"
                alert.informativeText = "오늘의 판 v\(version) is the latest version."
            }
            alert.runModal()
        }
    }

    /// 설치 전에 한 번 묻는다. 앱이 바뀌고 다시 실행된다.
    private func confirmUpdate() {
        guard case .available(let release) = updater.state else { return }
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Update to 오늘의 판 v\(release.version)?"
        alert.informativeText = "The app will download the update, replace itself, and restart."
        alert.addButton(withTitle: "Update")
        alert.addButton(withTitle: "Later")
        alert.addButton(withTitle: "Release Notes")
        switch alert.runModal() {
        case .alertFirstButtonReturn: updater.install(release)
        case .alertThirdButtonReturn: NSWorkspace.shared.open(release.pageURL)
        default: break
        }
    }

    private func scheduleApplySettings() {
        guard !applyScheduled else { return }
        applyScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.applyScheduled = false
            self.wallpaper?.fps = self.frameRate
            self.wallpaper?.applySettings()
        }
    }

    /// 설정 fps가 auto면 배터리일 때 30, 아니면 60. 명세 4.7.
    private var frameRate: Int {
        switch settings.fps {
        case .auto: return power.onBattery ? 30 : 60
        case .fps30: return 30
        case .fps60: return 60
        }
    }

    /// 웹뷰가 처음 준비되거나 다시 불러와졌을 때 마지막 상태를 보낸다.
    private func sendCurrentState(to webView: RecordWebView) {
        webView.sendOptions(wallpaper?.webOptions() ?? settings.webOptions)
        webView.sendVolume(volume.current.payload)
        guard let nowPlaying else { return }
        webView.sendNowPlaying(nowPlaying.current.payload)
        if let art = nowPlaying.currentArt {
            webView.sendArt(dataURL: art.dataURL, version: art.version)
        }
    }
}
