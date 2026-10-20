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
        }
        menu.onInstallUpdate = { [weak self] in self?.confirmUpdate() }
        settingsModel.onInstallUpdate = { [weak self] in self?.confirmUpdate() }
        settingsModel.onCheckForUpdates = { [weak self] in self?.updater.check() }
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

        if options.openSettings { settingsWindow.show() }

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
