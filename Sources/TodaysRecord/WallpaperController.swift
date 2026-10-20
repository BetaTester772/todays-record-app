import AppKit

/// 화면별 창 생성과 모니터 변경 대응. 명세 4.3.
/// M1에서는 주 화면에만 창을 띄운다. 모든 화면 모드는 M4에서 붙인다.
final class WallpaperController {
    private let options: LaunchOptions
    private let onReady: (RecordWebView) -> Void
    private var window: WallpaperWindow?
    private var webView: RecordWebView?
    private var screenObserver: NSObjectProtocol?

    var webViews: [RecordWebView] { webView.map { [$0] } ?? [] }

    /// onReady: 웹뷰가 준비되면 불린다. 여기서 첫 상태를 보낸다.
    init(options: LaunchOptions, onReady: @escaping (RecordWebView) -> Void) {
        self.options = options
        self.onReady = onReady
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
        webView.onReady = onReady
        webView.insets = insets(for: screen)
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
        webView?.insets = insets(for: screen)
    }

    /// 화면 전체와 visibleFrame의 차이. 메뉴 막대와 Dock이 차지하는 부분이다.
    /// 일반 창(--windowed)에서는 피할 것이 없다.
    private func insets(for screen: NSScreen) -> NSEdgeInsets {
        guard !options.windowed else { return NSEdgeInsetsZero }
        let full = screen.frame, visible = screen.visibleFrame
        let insets = NSEdgeInsets(
            top: full.maxY - visible.maxY,
            left: visible.minX - full.minX,
            bottom: visible.minY - full.minY,
            right: full.maxX - visible.maxX
        )
        Log.window.info("여백 top=\(insets.top) left=\(insets.left) bottom=\(insets.bottom) right=\(insets.right)")
        return insets
    }

    static func identifier(for screen: NSScreen) -> String {
        if let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
            return number.stringValue
        }
        return screen.localizedName
    }
}
