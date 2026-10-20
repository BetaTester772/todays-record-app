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

    func show() {
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
            window.title = "오늘의 판 Settings"
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            self.window = window
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
    @AppStorage(Settings.ColorSlot.record.rawValue) private var recordColor = ""
    @AppStorage(Settings.ColorSlot.background.rawValue) private var bgColor = ""
    @AppStorage(Settings.ColorSlot.line.rawValue) private var lineColor = ""
    @AppStorage(Settings.ColorSlot.text.rawValue) private var textColor = ""
    @AppStorage(Settings.ColorSlot.arm.rawValue) private var armColor = ""

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
                Toggle("Colored Vinyl", isOn: $coloredVinyl)
                    .disabled(!recordColor.isEmpty)
                Text(recordColor.isEmpty
                     ? "The record takes the album's main color, like colored vinyl."
                     : "Turn on From Album for Record Color to use this.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                ColorRow(title: "Record Color", hex: $recordColor)
                ColorRow(title: "Background Color", hex: $bgColor)
                ColorRow(title: "Line Color", hex: $lineColor)
                ColorRow(title: "Text Color", hex: $textColor)
                ColorRow(title: "Arm Color", hex: $armColor, automatic: "Default")
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
                Text("오늘의 판 needs permission to read what Music or Spotify is playing.")
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

/// "From Album"이 켜져 있으면 앨범 색, 끄면 직접 고른 색. 톤암처럼 기본 색이 앨범 색이 아니면 `automatic`에 다른 이름을 준다.
private struct ColorRow: View {
    let title: String
    @Binding var hex: String
    var automatic = "From Album"

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Toggle(automatic, isOn: Binding(
                get: { hex.isEmpty },
                set: { hex = $0 ? "" : (hex.isEmpty ? "#808080" : hex) }
            ))
            .toggleStyle(.checkbox)
            ColorPicker("", selection: Binding(
                get: { Color(nsColor: Self.color(hex) ?? .gray) },
                set: { hex = Self.hex(NSColor($0)) }
            ), supportsOpacity: false)
            .labelsHidden()
            .disabled(hex.isEmpty)
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
