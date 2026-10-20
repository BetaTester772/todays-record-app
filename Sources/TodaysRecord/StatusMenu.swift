import AppKit

/// 메뉴 막대 아이콘과 메뉴. 명세 4.8.
/// 지금은 M3에 필요한 항목만 있다. 설정 항목은 M2에서 더한다.
final class StatusMenu: NSObject {
    private static let automationSettingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let nowItem = NSMenuItem(title: "재생 중인 음악 없음", action: nil, keyEquivalent: "")
    private let permissionItem = NSMenuItem(title: "Music 제어 권한 열기", action: nil, keyEquivalent: "")

    override init() {
        super.init()
        let image = NSImage(systemSymbolName: "opticaldisc", accessibilityDescription: "오늘의 판")
        image?.isTemplate = true
        statusItem.button?.image = image

        let menu = NSMenu()
        menu.autoenablesItems = false
        nowItem.isEnabled = false
        menu.addItem(nowItem)
        menu.addItem(.separator())

        permissionItem.target = self
        permissionItem.action = #selector(openAutomationSettings)
        permissionItem.isHidden = true
        menu.addItem(permissionItem)

        menu.addItem(NSMenuItem(title: "종료", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    func update(_ info: NowPlayingInfo) {
        if info.state == .stopped || info.title.isEmpty {
            nowItem.title = "재생 중인 음악 없음"
        } else if info.artist.isEmpty {
            nowItem.title = info.title
        } else {
            nowItem.title = "\(info.title) — \(info.artist)"
        }
    }

    func setPermissionNeeded(_ needed: Bool) {
        permissionItem.isHidden = !needed
    }

    @objc private func openAutomationSettings() {
        NSWorkspace.shared.open(Self.automationSettingsURL)
    }
}
