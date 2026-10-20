import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let options: LaunchOptions
    private var wallpaper: WallpaperController?
    private var statusMenu: StatusMenu?
    private var nowPlaying: NowPlaying?
    private let volume = SystemVolume()
    private let settings = Settings()
    private let power = PowerWatcher()

    init(options: LaunchOptions) {
        self.options = options
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let menu = StatusMenu(settings: settings)
        menu.onSettingsChange = { [weak self] in
            guard let self else { return }
            self.wallpaper?.fps = self.frameRate
            self.wallpaper?.applySettings()
        }
        menu.onClearRecord = { [weak self] in self?.wallpaper?.webViews.forEach { $0.clearRecord() } }
        statusMenu = menu

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

        // --demo면 index.html의 미리보기 데이터를 쓰므로 Music을 보지 않는다.
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
            self?.statusMenu?.setPermissionNeeded(denied)
        }
        self.nowPlaying = nowPlaying
        nowPlaying.start()
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
