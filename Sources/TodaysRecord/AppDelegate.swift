import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let options: LaunchOptions
    private var wallpaper: WallpaperController?
    private var statusMenu: StatusMenu?
    private var nowPlaying: NowPlaying?

    init(options: LaunchOptions) {
        self.options = options
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let menu = StatusMenu()
        statusMenu = menu

        wallpaper = WallpaperController(options: options) { [weak self] webView in
            self?.sendCurrentState(to: webView)
        }
        wallpaper?.start()

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

    /// 웹뷰가 처음 준비되거나 다시 불러와졌을 때 마지막 상태를 보낸다.
    private func sendCurrentState(to webView: RecordWebView) {
        guard let nowPlaying else { return }
        webView.sendNowPlaying(nowPlaying.current.payload)
        if let art = nowPlaying.currentArt {
            webView.sendArt(dataURL: art.dataURL, version: art.version)
        }
    }
}
