import AppKit
import ServiceManagement
import SwiftUI

/// 설정 창. 명세 4.8.
/// 값은 Settings와 같은 UserDefaults 키에 바로 저장되고, AppDelegate가 UserDefaults 변경 알림을 받아 화면에 반영한다.
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private let model: SettingsModel
    private var window: NSWindow?

    init(model: SettingsModel) {
        self.model = model
    }

    /// `tab`: 처음 보일 탭 이름(General, Displays, …). 없으면 마지막에 보던 탭.
    func show(tab: String? = nil) {
        model.refresh()
        if window == nil {
            // macOS 설정 창처럼 위쪽 도구 막대 아이콘을 누르면 아래 내용이 바뀐다.
            let tabs = NSTabViewController()
            tabs.tabStyle = .toolbar
            tabs.canPropagateSelectedChildViewControllerTitle = false
            let panes: [(String, String, AnyView)] = [
                ("General", "gearshape", AnyView(GeneralPane(model: model))),
                ("Displays", "display.2", AnyView(DisplaysPane(model: model))),
                ("Appearance", "paintpalette", AnyView(AppearancePane())),
                ("Effects", "sparkles", AnyView(EffectsPane())),
                ("Characters", "person.2", AnyView(CharactersPane())),
                ("Players", "music.note", AnyView(PlayersPane(model: model))),
            ]
            for (title, symbol, view) in panes {
                let hosting = NSHostingController(rootView: view)
                hosting.sizingOptions = [.preferredContentSize]   // 탭마다 창 높이를 내용에 맞춘다
                let item = NSTabViewItem(viewController: hosting)
                item.label = title
                item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
                tabs.addTabViewItem(item)
            }
            let window = NSWindow(contentViewController: tabs)
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.toolbarStyle = .preference
            window.title = "TurnTable Settings"
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            self.window = window
        }
        if let tab, let tabs = window?.contentViewController as? NSTabViewController,
           let index = tabs.tabViewItems.firstIndex(where: { $0.label.caseInsensitiveCompare(tab) == .orderedSame }) {
            tabs.selectedTabViewItemIndex = index
        }
        // 메뉴 막대 앱이라 창을 열 때 앱을 앞으로 가져온다.
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

/// 설정 창이 UserDefaults 밖에서 알아야 하는 것: 연결된 화면, 로그인 항목, 플레이어 권한.
final class SettingsModel: ObservableObject {
    struct Display: Identifiable, Hashable {
        let id: String      // UUID
        let name: String
        let isMain: Bool
    }

    @Published private(set) var displays: [Display] = []
    @Published private(set) var loginEnabled = false
    @Published var deniedPlayers: Set<PlayerKind> = []
    @Published var update: Updater.State = .idle

    var onClearRecord: (() -> Void)?
    var onCheckForUpdates: (() -> Void)?
    var onInstallUpdate: (() -> Void)?
    let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"

    func refresh() {
        displays = NSScreen.screens.enumerated().map { index, screen in
            Display(id: WallpaperController.uuid(for: screen), name: screen.localizedName, isMain: index == 0)
        }
        loginEnabled = SMAppService.mainApp.status == .enabled
    }

    func setLogin(_ enabled: Bool) {
        let service = SMAppService.mainApp
        do {
            if enabled { try service.register() } else { try service.unregister() }
        } catch {
            Log.app.error("로그인 항목 변경 실패 \(error.localizedDescription, privacy: .public)")
        }
        Log.app.info("로그인 항목 상태 \(String(describing: service.status), privacy: .public)")
        // 사용자의 승인이 필요하면 시스템 설정의 로그인 항목 화면을 연다.
        if service.status == .requiresApproval {
            SMAppService.openSystemSettingsLoginItems()
        }
        refresh()
    }

    func openAutomationSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!)
    }
}

// 각 탭. @AppStorage 키는 Settings.Key와 같고, 기본값은 Settings.init에서 등록한 값과 같아야 한다.

private struct GeneralPane: View {
    @ObservedObject var model: SettingsModel
    @AppStorage(Settings.Key.enabled) private var enabled = true
    @AppStorage(Settings.Key.fps) private var fps = Settings.FrameRate.auto.rawValue
    @AppStorage(Settings.Key.autoUpdateCheck) private var autoUpdateCheck = true

    var body: some View {
        Pane {
            Section {
                Toggle("Show Wallpaper", isOn: $enabled)
                Toggle("Open at Login", isOn: Binding(get: { model.loginEnabled }, set: { model.setLogin($0) }))
            }
            Section {
                Picker("Frame Rate", selection: $fps) {
                    Text("Auto").tag(Settings.FrameRate.auto.rawValue)
                    Text("30 fps").tag(Settings.FrameRate.fps30.rawValue)
                    Text("60 fps").tag(Settings.FrameRate.fps60.rawValue)
                }
                .pickerStyle(.segmented)
                Text("Auto uses 30 fps on battery and 60 fps when plugged in.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                LabeledContent("Lines on the record") {
                    Button("Clear This Record") { model.onClearRecord?() }
                }
            }
            Section {
                Toggle("Check for Updates Automatically", isOn: $autoUpdateCheck)
                LabeledContent("Version \(model.version)") {
                    switch model.update {
                    case .checking:
                        ProgressView().controlSize(.small)
                    case .available(let release):
                        Button("Update to v\(release.version)") { model.onInstallUpdate?() }
                    case .installing:
                        Text("Updating…").foregroundStyle(.secondary)
                    default:
                        Button("Check Now") { model.onCheckForUpdates?() }
                    }
                }
                switch model.update {
                case .upToDate: Text("You're up to date.").font(.caption).foregroundStyle(.secondary)
                case .failed(let message): Text(message).font(.caption).foregroundStyle(.secondary)
                default: EmptyView()
                }
            }
        }
    }
}

private struct DisplaysPane: View {
    @ObservedObject var model: SettingsModel
    @AppStorage(Settings.Key.disabledDisplays) private var disabledDisplays = ""

    var body: some View {
        Pane {
            Section {
                ForEach(model.displays) { display in
                    Toggle(isOn: binding(display.id)) {
                        Text(display.isMain ? "\(display.name) (Main)" : display.name)
                    }
                }
            } footer: {
                Text("Show the record on these displays.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in
            model.refresh()
        }
    }

    private func binding(_ id: String) -> Binding<Bool> {
        Binding(
            get: { !disabledDisplays.split(separator: ",").contains(Substring(id)) },
            set: { on in
                var set = Set(disabledDisplays.split(separator: ",").map(String.init))
                if on { set.remove(id) } else { set.insert(id) }
                disabledDisplays = set.sorted().joined(separator: ",")
            }
        )
    }
}

private struct AppearancePane: View {
    @AppStorage(Settings.Key.position) private var position = Settings.Position.right.rawValue
    @AppStorage(Settings.Key.transparent) private var transparent = false
    @AppStorage(Settings.Key.coloredVinyl) private var coloredVinyl = false
    @AppStorage(Settings.Key.vinylStyle) private var vinylStyle = "match"
    @AppStorage(Settings.Key.lineStyle) private var lineStyle = "album"
    @AppStorage(Settings.ColorSlot.record.rawValue) private var recordColor = ""
    @AppStorage(Settings.ColorSlot.background.rawValue) private var bgColor = ""
    @AppStorage(Settings.ColorSlot.line.rawValue) private var lineColor = ""
    @AppStorage(Settings.ColorSlot.text.rawValue) private var textColor = ""
    @AppStorage(Settings.ColorSlot.arm.rawValue) private var armColor = ""
    @AppStorage(Settings.ColorSlot.armBase.rawValue) private var armBaseColor = ""

    private var colorsChanged: Bool {
        coloredVinyl || lineStyle == "contrast" || ![recordColor, bgColor, lineColor, textColor, armColor, armBaseColor].allSatisfy(\.isEmpty)
    }

    var body: some View {
        Pane {
            Section {
                Picker("Record Position", selection: $position) {
                    Text("Left").tag(Settings.Position.left.rawValue)
                    Text("Center").tag(Settings.Position.center.rawValue)
                    Text("Right").tag(Settings.Position.right.rawValue)
                }
                .pickerStyle(.segmented)
                Picker("Background", selection: $transparent) {
                    Text("Default").tag(false)
                    Text("Transparent").tag(true)
                }
                .pickerStyle(.segmented)
            }
            Section {
                ColorRow(slot: .record, title: "Record", hex: $recordColor, vinyl: $coloredVinyl, vinylStyle: $vinylStyle)
                ColorRow(slot: .background, title: "Background", hex: $bgColor)
                ColorRow(slot: .line, title: "Line", hex: $lineColor, contrast: Binding(get: { lineStyle == "contrast" }, set: { lineStyle = $0 ? "contrast" : "album" }))
                ColorRow(slot: .text, title: "Text", hex: $textColor)
                ColorRow(slot: .arm, title: "Tonearm", hex: $armColor)
                ColorRow(slot: .armBase, title: "Arm Base", hex: $armBaseColor)
                HStack {
                    Spacer()
                    Button("Reset Colors") {
                        coloredVinyl = false; vinylStyle = "match"; lineStyle = "album"
                        for slot in [Settings.ColorSlot.record, .background, .line, .text, .arm, .armBase] { UserDefaults.standard.set("", forKey: slot.rawValue) }
                    }
                    .disabled(!colorsChanged)
                }
            } header: {
                Text("Colors")
            } footer: {
                Text("Album colors come from the cover. Colored Vinyl paints the record in the album's main color, Contrast Vinyl in the opposite color. Custom colors stay the same for every album.")
                    .font(.caption).foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

private struct EffectsPane: View {
    @AppStorage(Settings.Key.windowLight) private var windowLight = true
    @AppStorage(Settings.Key.trail) private var trail = Settings.Trail.afterglow.rawValue
    @AppStorage(Settings.Key.grain) private var grain = Settings.Grain.normal.rawValue
    @AppStorage(Settings.Key.sideChange) private var sideChange = Settings.SideChange.turn.rawValue

    var body: some View {
        Pane {
            Section {
                Toggle("Window Light", isOn: $windowLight)
                Text("Light through a window follows the time of day.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                Picker("Trail", selection: $trail) {
                    Text("Keep").tag(Settings.Trail.keep.rawValue)
                    Text("Afterglow").tag(Settings.Trail.afterglow.rawValue)
                }
                .pickerStyle(.segmented)
                Picker("Grain", selection: $grain) {
                    Text("Off").tag(Settings.Grain.off.rawValue)
                    Text("Low").tag(Settings.Grain.low.rawValue)
                    Text("Normal").tag(Settings.Grain.normal.rawValue)
                    Text("High").tag(Settings.Grain.high.rawValue)
                }
                .pickerStyle(.segmented)
            }
            Section {
                Picker("Side Change", selection: $sideChange) {
                    Text("Lift & Turn").tag(Settings.SideChange.turn.rawValue)
                    Text("Swap Record").tag(Settings.SideChange.swap.rawValue)
                    Text("Needle Only").tag(Settings.SideChange.needle.rawValue)
                }
                Text("How the record moves when the next song is on the other side of the same record.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

/// 바늘 위 캐릭터(포즈, 옷 색)와 모여드는 사람들. 명세 4.8, 6장 25·27.
private struct CharactersPane: View {
    @AppStorage(Settings.Key.riderPose) private var riderPose = Settings.RiderPose.auto.rawValue
    @AppStorage(Settings.ColorSlot.shirt.rawValue) private var shirtColor = ""
    @AppStorage(Settings.ColorSlot.pants.rawValue) private var pantsColor = ""
    @AppStorage(Settings.ColorSlot.hat.rawValue) private var hatColor = ""
    @AppStorage(Settings.Key.crowd) private var crowd = true
    @AppStorage(Settings.Key.crowdPace) private var crowdPace = 1

    var body: some View {
        Pane {
            Section {
                Picker("Pose", selection: $riderPose) {
                    Text("Auto").tag(Settings.RiderPose.auto.rawValue)
                    Text("Sit").tag(Settings.RiderPose.sit.rawValue)
                    Text("Lean Back").tag(Settings.RiderPose.lean.rawValue)
                    Text("Cross-Legged").tag(Settings.RiderPose.cross.rawValue)
                    Text("Hug Knees").tag(Settings.RiderPose.hug.rawValue)
                }
            } header: {
                Text("Rider")
            } footer: {
                Text("The little one on the needle. On Auto the pose sometimes changes when a new song starts.")
                    .font(.caption).foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Section {
                ColorRow(slot: .shirt, title: "Shirt", hex: $shirtColor)
                ColorRow(slot: .pants, title: "Pants", hex: $pantsColor)
                ColorRow(slot: .hat, title: "Hat", hex: $hatColor)
                HStack {
                    Spacer()
                    Button("Reset Colors") { shirtColor = ""; pantsColor = ""; hatColor = "" }
                        .disabled(shirtColor.isEmpty && pantsColor.isEmpty && hatColor.isEmpty)
                }
            } header: {
                Text("Rider Colors")
            }
            Section {
                Toggle("Crowd", isOn: $crowd)
                Picker("Crowd Pace", selection: $crowdPace) {
                    Text("1×").tag(1)
                    Text("2×").tag(2)
                    Text("5×").tag(5)
                    Text("10×").tag(10)
                }
                .pickerStyle(.segmented)
                .disabled(!crowd)
            } header: {
                Text("Crowd")
            } footer: {
                Text("The longer the music plays, the more friends drop by. When the music stops they head home one by one. Crowd Pace makes them come and go faster.")
                    .font(.caption).foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

private struct PlayersPane: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        Pane {
            Section {
                ForEach(PlayerKind.allCases, id: \.self) { kind in
                    LabeledContent(kind.name) {
                        Text(model.deniedPlayers.contains(kind) ? "Not Allowed" : "Allowed")
                            .foregroundStyle(model.deniedPlayers.contains(kind) ? .red : .secondary)
                    }
                }
            } footer: {
                Text("TurnTable needs permission to read what Music or Spotify is playing.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                Button("Open Automation Settings…") { model.openAutomationSettings() }
            }
        }
    }
}

/// 탭 하나의 공통 모양: macOS 설정 창 같은 묶음 폼, 고정 너비.
private struct Pane<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        Form { content }
            .formStyle(.grouped)
            .scrollDisabled(true)
            .frame(width: 480)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// 색 하나: 기본 색(앨범 색, 톤암·받침판은 Default) / Custom. 판은 Colored Vinyl도 고를 수 있다.
/// 색 상자는 Custom일 때만 보인다(자리는 남겨 메뉴 줄을 맞춘다).
private struct ColorRow: View {
    let slot: Settings.ColorSlot
    let title: String
    @Binding var hex: String
    var vinyl: Binding<Bool>?
    var vinylStyle: Binding<String>?
    /// 선처럼 앨범 색의 반대 색(Contrast)을 고를 수 있는 줄
    var contrast: Binding<Bool>?

    private enum Choice: Hashable { case automatic, vinyl, contrast, custom }

    private var automaticTitle: String { [.arm, .armBase, .hat].contains(slot) ? "Default" : "Album" }

    private var choice: Binding<Choice> {
        Binding(
            get: {
                if !hex.isEmpty { return .custom }
                if contrast?.wrappedValue == true { return .contrast }
                guard vinyl?.wrappedValue == true else { return .automatic }
                return vinylStyle?.wrappedValue == "contrast" ? .contrast : .vinyl
            },
            set: { new in
                contrast?.wrappedValue = new == .contrast
                vinyl?.wrappedValue = new == .vinyl || new == .contrast
                if new == .vinyl || new == .contrast { vinylStyle?.wrappedValue = new == .contrast ? "contrast" : "match" }
                if new == .custom {
                    if hex.isEmpty { hex = slot.presets.dropFirst().first?.hex ?? "#808080" }
                } else {
                    hex = ""
                }
            }
        )
    }

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 8) {
                Picker(title, selection: choice) {
                    Text(automaticTitle).tag(Choice.automatic)
                    if vinyl != nil {
                        Text("Colored Vinyl").tag(Choice.vinyl)
                        Text("Contrast Vinyl").tag(Choice.contrast)
                    }
                    if contrast != nil { Text("Contrast").tag(Choice.contrast) }
                    Text("Custom").tag(Choice.custom)
                }
                .labelsHidden()
                .fixedSize()
                ColorPicker(title, selection: Binding(
                    get: { Color(nsColor: Self.color(hex) ?? .gray) },
                    set: { hex = Self.hex(NSColor($0)) }
                ), supportsOpacity: false)
                .labelsHidden()
                .disabled(hex.isEmpty)
                .opacity(hex.isEmpty ? 0 : 1)
            }
        }
    }

    static func color(_ hex: String) -> NSColor? {
        guard hex.count == 7, let value = Int(hex.dropFirst(), radix: 16) else { return nil }
        return NSColor(srgbRed: CGFloat((value >> 16) & 0xFF) / 255, green: CGFloat((value >> 8) & 0xFF) / 255,
                       blue: CGFloat(value & 0xFF) / 255, alpha: 1)
    }

    static func hex(_ color: NSColor) -> String {
        guard let rgb = color.usingColorSpace(.sRGB) else { return "" }
        return String(format: "#%02X%02X%02X", Int((rgb.redComponent * 255).rounded()),
                      Int((rgb.greenComponent * 255).rounded()), Int((rgb.blueComponent * 255).rounded()))
    }
}
