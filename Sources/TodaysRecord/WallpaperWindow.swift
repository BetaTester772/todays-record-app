import AppKit

/// 바탕화면 층 창. 명세 4.2.
final class WallpaperWindow: NSWindow {
    private let windowed: Bool

    init(screen: NSScreen, windowed: Bool) {
        self.windowed = windowed
        if windowed {
            let size = NSSize(width: screen.frame.width * 0.6, height: screen.frame.height * 0.6)
            let origin = NSPoint(x: screen.frame.midX - size.width / 2, y: screen.frame.midY - size.height / 2)
            super.init(
                contentRect: NSRect(origin: origin, size: size),
                styleMask: [.titled, .closable, .resizable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            title = "오늘의 판 (Debug)"
        } else {
            super.init(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
            level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))
            collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone]
            ignoresMouseEvents = true
            hasShadow = false
            isOpaque = true
            backgroundColor = .black
        }
        isReleasedWhenClosed = false
    }

    override var canBecomeKey: Bool { windowed }
    override var canBecomeMain: Bool { windowed }

    /// 투명 배경 설정. 명세 4.2.
    func setTransparent(_ transparent: Bool) {
        isOpaque = !transparent
        backgroundColor = transparent ? .clear : (windowed ? .windowBackgroundColor : .black)
    }

    /// 화면 크기가 바뀌었을 때 창을 다시 맞춘다.
    func fit(to screen: NSScreen) {
        guard !windowed else { return }
        setFrame(screen.frame, display: true)
    }
}
