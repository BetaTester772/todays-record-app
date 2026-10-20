import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let options: LaunchOptions
    private var wallpaper: WallpaperController?
    private var statusItem: NSStatusItem?

    init(options: LaunchOptions) {
        self.options = options
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        wallpaper = WallpaperController(options: options)
        wallpaper?.start()
        installTemporaryStatusItem()
    }

    // M1 임시: 앱을 끌 수 있도록 종료 항목만 둔다. M2에서 StatusMenu로 바꾼다.
    private func installTemporaryStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let image = NSImage(systemSymbolName: "opticaldisc", accessibilityDescription: "오늘의 판")
        image?.isTemplate = true
        item.button?.image = image

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "종료", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        item.menu = menu
        statusItem = item
    }
}
