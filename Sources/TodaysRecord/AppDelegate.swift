import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let options: LaunchOptions
    private var wallpaper: WallpaperController?
    private var statusMenu: StatusMenu?
    private var nowPlaying: NowPlaying?
    private let volume = SystemVolume()
    private let settings = Settings()

    init(options: LaunchOptions) {
        self.options = options
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let menu = StatusMenu(settings: settings)
        menu.onSettingsChange = { [weak self] in self?.wallpaper?.applySettings() }
        menu.onClearRecord = { [weak self] in self?.wallpaper?.webViews.forEach { $0.clearRecord() } }
        statusMenu = menu

        wallpaper = WallpaperController(options: options, settings: settings) { [weak self] webView in
            self?.sendCurrentState(to: webView)
        }
        wallpaper?.start()

        volume.onChange = { [weak self] level in
            self?.wallpaper?.webViews.forEach { $0.sendVolume(level.payload) }
        }
        volume.start()

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

    /// 웹뷰가 처음 준비되거나 다시 불러와졌을 때 마지막 상태를 보낸다.
    private func sendCurrentState(to webView: RecordWebView) {
        webView.sendOptions(settings.webOptions)
        webView.sendVolume(volume.current.payload)
        guard let nowPlaying else { return }
        webView.sendNowPlaying(nowPlaying.current.payload)
        if let art = nowPlaying.currentArt {
            webView.sendArt(dataURL: art.dataURL, version: art.version)
        }
    }
}
