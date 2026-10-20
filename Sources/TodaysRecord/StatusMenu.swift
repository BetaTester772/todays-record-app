import AppKit
import ServiceManagement

/// 메뉴 막대 아이콘과 메뉴. 명세 4.8.
/// 표시할 화면(M4)과 시스템 배경화면 색 맞추기(M5)는 해당 마일스톤에서 더한다.
final class StatusMenu: NSObject, NSMenuDelegate {
    private static let automationSettingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!

    /// 설정이 바뀌면 불린다. 받는 쪽에서 창과 웹뷰에 반영한다.
    var onSettingsChange: (() -> Void)?
    var onClearRecord: (() -> Void)?
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
    private let windowLightItem = NSMenuItem(title: "Window Light", action: nil, keyEquivalent: "")
    private let loginItem = NSMenuItem(title: "Open at Login", action: nil, keyEquivalent: "")
    private var positionItems: [Settings.Position: NSMenuItem] = [:]
    private var backgroundItems: [Bool: NSMenuItem] = [:]
    private var trailItems: [Settings.Trail: NSMenuItem] = [:]
    private var grainItems: [Settings.Grain: NSMenuItem] = [:]
    private var colorItems: [Settings.ColorSlot: [NSMenuItem]] = [:]
    private var customColorItems: [Settings.ColorSlot: NSMenuItem] = [:]
    /// 색상 창이 지금 바꾸고 있는 색.
    private var customSlot: Settings.ColorSlot?

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

        let position = NSMenu()
        for (value, title) in [(Settings.Position.left, "Left"), (.center, "Center"), (.right, "Right")] {
            let item = target(NSMenuItem(title: title, action: nil, keyEquivalent: ""), #selector(choosePosition(_:)))
            item.representedObject = value.rawValue
            positionItems[value] = item
            position.addItem(item)
        }
        menu.addItem(submenu("Record Position", position))

        let background = NSMenu()
        for (value, title) in [(false, "Default"), (true, "Transparent")] {
            let item = target(NSMenuItem(title: title, action: nil, keyEquivalent: ""), #selector(chooseBackground(_:)))
            item.tag = value ? 1 : 0
            backgroundItems[value] = item
            background.addItem(item)
        }
        menu.addItem(submenu("Background", background))

        for slot in Settings.ColorSlot.allCases {
            menu.addItem(colorSubmenu(slot))
        }

        let effects = NSMenu()
        effects.addItem(target(windowLightItem, #selector(toggleWindowLight)))
        let trail = NSMenu()
        for (value, title) in [(Settings.Trail.keep, "Keep"), (.afterglow, "Afterglow")] {
            let item = target(NSMenuItem(title: title, action: nil, keyEquivalent: ""), #selector(chooseTrail(_:)))
            item.representedObject = value.rawValue
            trailItems[value] = item
            trail.addItem(item)
        }
        effects.addItem(submenu("Trail", trail))
        let grain = NSMenu()
        for (value, title) in [(Settings.Grain.off, "Off"), (.low, "Low"), (.normal, "Normal"), (.high, "High")] {
            let item = target(NSMenuItem(title: title, action: nil, keyEquivalent: ""), #selector(chooseGrain(_:)))
            item.representedObject = value.rawValue
            grainItems[value] = item
            grain.addItem(item)
        }
        effects.addItem(submenu("Grain", grain))
        menu.addItem(submenu("Effects", effects))
        menu.addItem(.separator())

        menu.addItem(target(NSMenuItem(title: "Clear This Record", action: nil, keyEquivalent: ""), #selector(clearRecord)))
        menu.addItem(target(loginItem, #selector(toggleLogin)))
        menu.addItem(.separator())

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

    // MARK: - 메뉴 동작

    @objc private func toggleEnabled() {
        settings.enabled.toggle()
        changed()
    }

    @objc private func choosePosition(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let value = Settings.Position(rawValue: raw) else { return }
        settings.position = value
        changed()
    }

    @objc private func chooseBackground(_ sender: NSMenuItem) {
        settings.transparent = sender.tag == 1
        changed()
    }

    @objc private func toggleWindowLight() {
        settings.windowLight.toggle()
        changed()
    }

    @objc private func chooseTrail(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let value = Settings.Trail(rawValue: raw) else { return }
        settings.trail = value
        changed()
    }

    /// 프리셋 항목. representedObject는 [슬롯, 색].
    @objc private func choosePresetColor(_ sender: NSMenuItem) {
        guard let pair = sender.representedObject as? [String], pair.count == 2,
              let slot = Settings.ColorSlot(rawValue: pair[0]) else { return }
        settings.setColor(pair[1], for: slot)
        changed()
    }

    /// macOS 색상 창으로 색을 직접 고른다. 움직이는 동안 바로 반영한다.
    @objc private func pickCustomColor(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let slot = Settings.ColorSlot(rawValue: raw) else { return }
        customSlot = slot
        let panel = NSColorPanel.shared
        panel.showsAlpha = false
        panel.isContinuous = true
        if let color = Self.color(fromHex: settings.color(slot)) { panel.color = color }
        panel.setTarget(self)
        panel.setAction(#selector(customColorChanged(_:)))
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    @objc private func customColorChanged(_ sender: NSColorPanel) {
        guard let slot = customSlot, let rgb = sender.color.usingColorSpace(.sRGB) else { return }
        let hex = String(format: "#%02X%02X%02X",
                         Int((rgb.redComponent * 255).rounded()),
                         Int((rgb.greenComponent * 255).rounded()),
                         Int((rgb.blueComponent * 255).rounded()))
        guard hex != settings.color(slot) else { return }
        settings.setColor(hex, for: slot)
        changed()
    }

    private static func color(fromHex hex: String) -> NSColor? {
        guard hex.count == 7, let value = Int(hex.dropFirst(), radix: 16) else { return nil }
        return NSColor(srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
                       green: CGFloat((value >> 8) & 0xFF) / 255,
                       blue: CGFloat(value & 0xFF) / 255,
                       alpha: 1)
    }

    @objc private func chooseGrain(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let value = Settings.Grain(rawValue: raw) else { return }
        settings.grain = value
        changed()
    }

    @objc private func clearRecord() {
        onClearRecord?()
    }

    @objc private func toggleLogin() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled {
                try service.unregister()
            } else {
                try service.register()
            }
        } catch {
            Log.app.error("로그인 항목 변경 실패 \(error.localizedDescription, privacy: .public)")
        }
        Log.app.info("로그인 항목 상태 \(String(describing: service.status), privacy: .public)")
        // 사용자의 승인이 필요하면 시스템 설정의 로그인 항목 화면을 연다.
        if service.status == .requiresApproval {
            SMAppService.openSystemSettingsLoginItems()
        }
        refreshChecks()
    }

    @objc private func choosePlayer(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let kind = PlayerKind(rawValue: raw) else { return }
        onChoosePlayer?(kind)
    }

    @objc private func openAutomationSettings() {
        NSWorkspace.shared.open(Self.automationSettingsURL)
    }

    // 메뉴를 열 때마다 체크 표시를 실제 상태에 맞춘다(로그인 항목은 시스템 설정에서도 바뀔 수 있다).
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

    // MARK: - 도우미

    private func changed() {
        refreshChecks()
        onSettingsChange?()
    }

    private func refreshChecks() {
        enabledItem.state = settings.enabled ? .on : .off
        windowLightItem.state = settings.windowLight ? .on : .off
        positionItems.forEach { $0.value.state = $0.key == settings.position ? .on : .off }
        backgroundItems.forEach { $0.value.state = $0.key == settings.transparent ? .on : .off }
        trailItems.forEach { $0.value.state = $0.key == settings.trail ? .on : .off }
        grainItems.forEach { $0.value.state = $0.key == settings.grain ? .on : .off }
        for slot in Settings.ColorSlot.allCases {
            let color = settings.color(slot)
            let isPreset = slot.presets.contains { $0.hex.caseInsensitiveCompare(color) == .orderedSame }
            colorItems[slot]?.forEach { item in
                let hex = (item.representedObject as? [String])?.last ?? ""
                item.state = hex.caseInsensitiveCompare(color) == .orderedSame ? .on : .off
            }
            customColorItems[slot]?.state = isPreset ? .off : .on
        }
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }

    @discardableResult
    private func target(_ item: NSMenuItem, _ action: Selector) -> NSMenuItem {
        item.target = self
        item.action = action
        return item
    }

    private func colorSubmenu(_ slot: Settings.ColorSlot) -> NSMenuItem {
        let menu = NSMenu()
        var items: [NSMenuItem] = []
        for (index, preset) in slot.presets.enumerated() {
            let item = target(NSMenuItem(title: preset.title, action: nil, keyEquivalent: ""), #selector(choosePresetColor(_:)))
            item.representedObject = [slot.rawValue, preset.hex]
            items.append(item)
            menu.addItem(item)
            if index == 0 { menu.addItem(.separator()) }
        }
        menu.addItem(.separator())
        let custom = target(NSMenuItem(title: "Custom…", action: nil, keyEquivalent: ""), #selector(pickCustomColor(_:)))
        custom.representedObject = slot.rawValue
        menu.addItem(custom)
        colorItems[slot] = items
        customColorItems[slot] = custom
        return submenu(slot.menuTitle, menu)
    }

    private func submenu(_ title: String, _ menu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = menu
        return item
    }
}
