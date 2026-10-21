import AppKit

/// 화면별 창 생성과 모니터 변경 대응. 명세 4.3.
/// 설정에서 끄지 않은 모든 화면에 띄운다. 기록을 저장하는 primary는 띄우는 화면 중 첫 번째이고,
/// 화면 순서는 메뉴 막대가 있는 화면(NSScreen.screens[0])부터다. NSScreen.main은 키 창이 있는 화면이라 쓰지 않는다.
final class WallpaperController {
    private struct Entry {
        let window: WallpaperWindow
        let webView: RecordWebView
    }

    private let options: LaunchOptions
    private let settings: Settings
    private let onReady: (RecordWebView) -> Void
    /// 화면 식별자 → 창과 웹뷰
    private var entries: [String: Entry] = [:]
    private var observers: [NSObjectProtocol] = []

    var webViews: [RecordWebView] { entries.values.map(\.webView) }

    /// 잠자기·잠금 등으로 모든 화면을 멈출 때 true. 명세 4.7.
    var globalPaused = false {
        didSet { updatePaused() }
    }

    /// 화면에 보낼 초당 프레임(30 또는 60).
    var fps = 60 {
        didSet { if fps != oldValue { sendOptions() } }
    }

    /// onReady: 웹뷰가 준비되면 불린다. 여기서 첫 상태를 보낸다.
    init(options: LaunchOptions, settings: Settings, onReady: @escaping (RecordWebView) -> Void) {
        self.options = options
        self.settings = settings
        self.onReady = onReady
    }

    deinit {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
    }

    func start() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            Log.window.info("화면 변경")
            self?.syncScreens()
        })
        // 창이 완전히 가려지면(전체 화면 앱 등) 그 창만 멈춘다.
        observers.append(center.addObserver(forName: NSWindow.didChangeOcclusionStateNotification, object: nil, queue: .main) { [weak self] note in
            guard let self, let window = note.object as? WallpaperWindow, self.entries.values.contains(where: { $0.window === window }) else { return }
            Log.window.info("가려짐 변경 visible=\(window.occlusionState.contains(.visible))")
            self.updatePaused()
        })
        applySettings()
    }

    /// 설정을 창과 웹뷰에 반영한다. 표시할 화면이 바뀌었으면 창을 맞춘다.
    func applySettings() {
        syncScreens()
        for entry in entries.values {
            entry.window.setTransparent(settings.transparent)
            entry.webView.setTransparent(settings.transparent)
            if settings.enabled {
                if options.windowed { entry.window.makeKeyAndOrderFront(nil) } else { entry.window.orderFront(nil) }
            } else {
                entry.window.orderOut(nil)
            }
        }
        sendOptions()
        updatePaused()
    }

    /// 화면 옵션(설정 + 초당 프레임)을 보낸다.
    func webOptions() -> [String: Any] {
        var options = settings.webOptions
        options["fps"] = fps
        return options
    }

    private func sendOptions() {
        let options = webOptions()
        entries.values.forEach { $0.webView.sendOptions(options) }
    }

    // MARK: - 화면 맞추기

    /// 지금 연결된 화면과 설정에 맞게 창을 만들거나 닫고, 남은 창은 크기와 여백을 맞춘다.
    private func syncScreens() {
        let screens = NSScreen.screens
        guard let first = screens.first else {
            Log.window.error("화면을 찾지 못함")
            return
        }
        // 일반 창(--windowed)은 디버깅용이라 주 화면에 하나만 띄운다.
        let disabled = settings.disabledDisplays
        let targets = options.windowed ? [first] : screens.filter { !disabled.contains(Self.uuid(for: $0)) }
        let primaryID = targets.first.map(Self.identifier(for:)) ?? ""
        let wanted = Dictionary(targets.map { (Self.identifier(for: $0), $0) }, uniquingKeysWith: { first, _ in first })

        for (id, entry) in entries {
            let role: RecordWebView.Role = id == primaryID ? .primary : .mirror
            // 빠진 화면, 또는 주 화면이 바뀌어 역할이 달라진 화면의 창은 닫는다(역할은 문서 시작 때 정해진다).
            if wanted[id] == nil || entry.webView.role != role {
                close(entry)
                entries[id] = nil
                Log.window.info("창 닫음 screen=\(id, privacy: .public)")
            }
        }
        for (id, screen) in wanted {
            if let entry = entries[id] {
                entry.window.fit(to: screen)
                entry.webView.insets = insets(for: screen)
            } else {
                entries[id] = makeEntry(for: screen, id: id, role: id == primaryID ? .primary : .mirror)
            }
        }
    }

    private func makeEntry(for screen: NSScreen, id: String, role: RecordWebView.Role) -> Entry {
        let window = WallpaperWindow(screen: screen, windowed: options.windowed)
        let webView = RecordWebView(frame: window.contentLayoutRect, role: role, screenID: id, options: options)
        webView.autoresizingMask = [.width, .height]
        webView.onReady = onReady
        webView.insets = insets(for: screen)
        window.contentView = webView
        window.setTransparent(settings.transparent)
        webView.setTransparent(settings.transparent)
        if settings.enabled {
            if options.windowed { window.makeKeyAndOrderFront(nil) } else { window.orderFront(nil) }
        }
        Log.window.info("창 생성 screen=\(id, privacy: .public) role=\(role.rawValue, privacy: .public) frame=\(NSStringFromRect(window.frame), privacy: .public)")
        return Entry(window: window, webView: webView)
    }

    private func close(_ entry: Entry) {
        entry.webView.paused = true
        entry.window.orderOut(nil)
        entry.window.contentView = nil
        entry.window.close()
    }

    /// 웹뷰마다 멈출지 정한다: 전체 멈춤, 배경화면 끔, 또는 그 창이 보이지 않을 때.
    /// 창이 가려졌을 뿐이면(전체 화면 앱 등) 그리기만 멈추고 소리는 계속 낸다. 잠금·잠자기·배경화면 끔은 소리도 멈춘다.
    private func updatePaused() {
        for entry in entries.values {
            let visible = entry.window.occlusionState.contains(.visible)
            entry.webView.keepSound = !globalPaused && settings.enabled
            entry.webView.paused = globalPaused || !settings.enabled || !visible
        }
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

    /// 다시 연결해도 바뀌지 않는 화면 UUID. 화면별 켜기/끄기 설정에 쓴다.
    static func uuid(for screen: NSScreen) -> String {
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
              let uuid = CGDisplayCreateUUIDFromDisplayID(number.uint32Value)?.takeRetainedValue() else {
            return identifier(for: screen)
        }
        return CFUUIDCreateString(nil, uuid) as String
    }

    static func identifier(for screen: NSScreen) -> String {
        if let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
            return number.stringValue
        }
        return screen.localizedName
    }
}
