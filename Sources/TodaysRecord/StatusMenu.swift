import AppKit

/// 메뉴 막대 아이콘과 메뉴. 명세 4.8.
/// 자주 쓰는 동작만 두고, 나머지 설정은 설정 창(SettingsWindow)에서 한다.
final class StatusMenu: NSObject, NSMenuDelegate {
    private static let automationSettingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!

    var onClearRecord: (() -> Void)?
    var onOpenSettings: (() -> Void)?
    var onInstallUpdate: (() -> Void)?
    var onCheckForUpdates: (() -> Void)?
    /// 메뉴를 열 때 불린다. 실행 중인 플레이어와 지금 보여주는 플레이어(4.5.2). 없으면 Player 항목을 숨긴다.
    var playerChoice: (() -> (running: [PlayerKind], shown: PlayerKind?))?
    var onChoosePlayer: ((PlayerKind) -> Void)?

    private let settings: Settings
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let nowItem = NSMenuItem(title: "Nothing Playing", action: nil, keyEquivalent: "")
    private let playerItem = NSMenuItem(title: "Player", action: nil, keyEquivalent: "")
    private var playerItems: [PlayerKind: NSMenuItem] = [:]
    private let permissionItem = NSMenuItem(title: "Allow Control of Music…", action: nil, keyEquivalent: "")
    private let enabledItem = NSMenuItem(title: "Show Wallpaper", action: nil, keyEquivalent: "")
    private let updateItem = NSMenuItem(title: "Update Available…", action: nil, keyEquivalent: "")

    init(settings: Settings) {
        self.settings = settings
        super.init()
        let image = NSImage(systemSymbolName: "opticaldisc", accessibilityDescription: "오늘의 판")
        image?.isTemplate = true
        statusItem.button?.image = image

        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = self
        nowItem.isEnabled = false
        menu.addItem(nowItem)
        let players = NSMenu()
        for kind in PlayerKind.allCases {
            let item = target(NSMenuItem(title: kind.name, action: nil, keyEquivalent: ""), #selector(choosePlayer(_:)))
            item.representedObject = kind.rawValue
            playerItems[kind] = item
            players.addItem(item)
        }
        playerItem.submenu = players
        playerItem.isHidden = true
        menu.addItem(playerItem)
        menu.addItem(.separator())

        menu.addItem(target(enabledItem, #selector(toggleEnabled)))
        menu.addItem(target(NSMenuItem(title: "Clear This Record", action: nil, keyEquivalent: ""), #selector(clearRecord)))
        menu.addItem(target(NSMenuItem(title: "Settings…", action: nil, keyEquivalent: ","), #selector(openSettings)))
        menu.addItem(target(NSMenuItem(title: "Check for Updates…", action: nil, keyEquivalent: ""), #selector(checkForUpdates)))
        menu.addItem(.separator())

        target(updateItem, #selector(installUpdate))
        updateItem.isHidden = true
        menu.addItem(updateItem)

        target(permissionItem, #selector(openAutomationSettings))
        permissionItem.isHidden = true
        menu.addItem(permissionItem)

        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
        refreshChecks()
    }

    func update(_ info: NowPlayingInfo) {
        if info.state == .stopped || info.title.isEmpty {
            nowItem.title = "Nothing Playing"
        } else if info.artist.isEmpty {
            nowItem.title = info.title
        } else {
            nowItem.title = "\(info.title) — \(info.artist)"
        }
    }

    /// 제어 권한이 없는 플레이어. 비어 있으면 권한 항목을 숨긴다.
    func setPermissionNeeded(for players: Set<PlayerKind>) {
        let names = PlayerKind.allCases.filter(players.contains).map(\.name)
        permissionItem.isHidden = names.isEmpty
        if !names.isEmpty {
            permissionItem.title = "Allow Control of \(names.joined(separator: " and "))…"
        }
    }

    /// 새 버전이 있을 때만 업데이트 항목을 보인다. 명세 4.10.
    func setUpdate(_ state: Updater.State) {
        switch state {
        case .available(let release):
            updateItem.title = "Update to v\(release.version)…"
            updateItem.isEnabled = true
            updateItem.isHidden = false
        case .installing(let release):
            updateItem.title = "Updating to v\(release.version)…"
            updateItem.isEnabled = false
            updateItem.isHidden = false
        default:
            updateItem.isHidden = true
        }
    }

    // MARK: - 메뉴 동작

    @objc private func installUpdate() {
        onInstallUpdate?()
    }

    @objc private func checkForUpdates() {
        onCheckForUpdates?()
    }

    @objc private func toggleEnabled() {
        settings.enabled.toggle()   // UserDefaults 변경 알림으로 화면에 반영된다
        refreshChecks()
    }

    @objc private func clearRecord() {
        onClearRecord?()
    }

    @objc private func openSettings() {
        onOpenSettings?()
    }

    @objc private func choosePlayer(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let kind = PlayerKind(rawValue: raw) else { return }
        onChoosePlayer?(kind)
    }

    @objc private func openAutomationSettings() {
        NSWorkspace.shared.open(Self.automationSettingsURL)
    }

    // 메뉴를 열 때마다 체크 표시를 실제 상태에 맞춘다(설정 창에서도 바뀔 수 있다).
    // Player 항목은 둘 다 실행 중일 때만 보인다.
    func menuWillOpen(_ menu: NSMenu) {
        refreshChecks()
        refreshPlayers()
    }

    private func refreshPlayers() {
        guard let choice = playerChoice?() else {
            playerItem.isHidden = true
            return
        }
        playerItem.isHidden = choice.running.count < 2
        playerItems.forEach { $0.value.state = $0.key == choice.shown ? .on : .off }
    }

    private func refreshChecks() {
        enabledItem.state = settings.enabled ? .on : .off
    }

    @discardableResult
    private func target(_ item: NSMenuItem, _ action: Selector) -> NSMenuItem {
        item.target = self
        item.action = action
        return item
    }
}
