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
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 460, height: 640),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            window.title = "오늘의 판 Settings"
            window.contentViewController = NSHostingController(rootView: SettingsView(model: model))
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

    var onClearRecord: (() -> Void)?

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

private struct SettingsView: View {
    @ObservedObject var model: SettingsModel

    // 기본값은 Settings.init에서 등록한 값과 같아야 한다.
    @AppStorage(Settings.Key.enabled) private var enabled = true
    @AppStorage(Settings.Key.disabledDisplays) private var disabledDisplays = ""
    @AppStorage(Settings.Key.position) private var position = Settings.Position.right.rawValue
    @AppStorage(Settings.Key.transparent) private var transparent = false
    @AppStorage(Settings.ColorSlot.record.rawValue) private var recordColor = ""
    @AppStorage(Settings.ColorSlot.background.rawValue) private var bgColor = ""
    @AppStorage(Settings.ColorSlot.line.rawValue) private var lineColor = ""
    @AppStorage(Settings.Key.windowLight) private var windowLight = true
    @AppStorage(Settings.Key.trail) private var trail = Settings.Trail.afterglow.rawValue
    @AppStorage(Settings.Key.grain) private var grain = Settings.Grain.normal.rawValue
    @AppStorage(Settings.Key.fps) private var fps = Settings.FrameRate.auto.rawValue

    var body: some View {
        Form {
            Section("General") {
                Toggle("Show Wallpaper", isOn: $enabled)
                Toggle("Open at Login", isOn: Binding(get: { model.loginEnabled }, set: { model.setLogin($0) }))
            }

            Section("Displays") {
                ForEach(model.displays) { display in
                    Toggle(isOn: displayBinding(display.id)) {
                        Text(display.isMain ? "\(display.name) (Main)" : display.name)
                    }
                }
            }

            Section("Appearance") {
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
                ColorRow(title: "Record Color", hex: $recordColor)
                ColorRow(title: "Background Color", hex: $bgColor)
                ColorRow(title: "Line Color", hex: $lineColor)
            }

            Section("Effects") {
                Toggle("Window Light", isOn: $windowLight)
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

            Section("Performance") {
                Picker("Frame Rate", selection: $fps) {
                    Text("Auto").tag(Settings.FrameRate.auto.rawValue)
                    Text("30 fps").tag(Settings.FrameRate.fps30.rawValue)
                    Text("60 fps").tag(Settings.FrameRate.fps60.rawValue)
                }
                .pickerStyle(.segmented)
                Text("Auto uses 30 fps on battery and 60 fps when plugged in.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Players") {
                ForEach(PlayerKind.allCases, id: \.self) { kind in
                    LabeledContent(kind.name) {
                        Text(model.deniedPlayers.contains(kind) ? "Not Allowed" : "Allowed")
                            .foregroundStyle(model.deniedPlayers.contains(kind) ? .red : .secondary)
                    }
                }
                Button("Open Automation Settings…") { model.openAutomationSettings() }
            }

            Section {
                Button("Clear This Record") { model.onClearRecord?() }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .frame(minHeight: 560)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in
            model.refresh()
        }
    }

    private func displayBinding(_ id: String) -> Binding<Bool> {
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

/// "From Album"이 켜져 있으면 앨범 색, 끄면 직접 고른 색.
private struct ColorRow: View {
    let title: String
    @Binding var hex: String

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Toggle("From Album", isOn: Binding(
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
