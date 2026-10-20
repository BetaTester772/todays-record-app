import AppKit

/// 화면별 창 생성과 모니터 변경 대응. 명세 4.3.
/// M1에서는 주 화면에만 창을 띄운다. 모든 화면 모드는 M4에서 붙인다.
final class WallpaperController {
    private let options: LaunchOptions
    private var window: WallpaperWindow?
    private var webView: RecordWebView?
    private var screenObserver: NSObjectProtocol?

    init(options: LaunchOptions) {
        self.options = options
    }

    deinit {
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
    }

    func start() {
        rebuild()
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.screensChanged()
        }
    }

    private func rebuild() {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else {
            Log.window.error("화면을 찾지 못함")
            return
        }
        let window = WallpaperWindow(screen: screen, windowed: options.windowed)
        let webView = RecordWebView(
            frame: window.contentLayoutRect,
            role: .primary,
            screenID: Self.identifier(for: screen),
            options: options
        )
        webView.autoresizingMask = [.width, .height]
        window.contentView = webView
        if options.windowed {
            window.makeKeyAndOrderFront(nil)
        } else {
            window.orderFront(nil)
        }
        Log.window.info("창 생성 level=\(window.level.rawValue) frame=\(NSStringFromRect(window.frame), privacy: .public)")
        self.window = window
        self.webView = webView
    }

    private func screensChanged() {
        guard let window, let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        Log.window.info("화면 변경 \(NSStringFromRect(screen.frame), privacy: .public)")
        window.fit(to: screen)
    }

    static func identifier(for screen: NSScreen) -> String {
        if let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
            return number.stringValue
        }
        return screen.localizedName
    }
}
