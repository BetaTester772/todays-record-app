import Foundation

/// UserDefaults에 저장되는 설정. 명세 4.8.
final class Settings {
    enum Position: String, CaseIterable {
        case left, center, right
    }

    enum Trail: String, CaseIterable {
        case keep, afterglow
    }

    /// 초당 프레임. auto는 배터리일 때 30, 아니면 60. 명세 4.7.
    enum FrameRate: String, CaseIterable {
        case auto, fps30 = "30", fps60 = "60"
    }

    /// 같은 판의 다른 면으로 넘어갈 때의 동작. 명세 6장 23.
    enum SideChange: String, CaseIterable {
        case turn, swap, needle
    }

    /// 화면 그레인(잡음 무늬) 세기.
    enum Grain: String, CaseIterable {
        case off, low, normal, high
    }

    /// 사용자가 고를 수 있는 색. 빈 문자열이면 기본 색(앨범에서 뽑은 색, 톤암과 받침판은 금속색)을 쓴다.
    enum ColorSlot: String, CaseIterable {
        case record = "recordColor"
        case background = "bgColor"
        case line = "lineColor"
        case text = "textColor"
        case arm = "armColor"
        case armBase = "armBaseColor"
        case shirt = "shirtColor"
        case pants = "pantsColor"
        case hat = "hatColor"

        var menuTitle: String {
            switch self {
            case .record: return "Record Color"
            case .background: return "Background Color"
            case .line: return "Line Color"
            case .text: return "Text Color"
            case .arm: return "Arm Color"
            case .armBase: return "Arm Base Color"
            case .shirt: return "Shirt Color"
            case .pants: return "Pants Color"
            case .hat: return "Hat Color"
            }
        }

        /// 첫 항목은 기본 색. 둘째 항목은 설정 창에서 Custom을 처음 고를 때의 색.
        var presets: [(title: String, hex: String)] {
            switch self {
            case .record:
                return [("Album Colors", ""), ("Black", "#1C1B1E"), ("White", "#F4F0E6"), ("Red", "#B8323A"), ("Blue", "#2F5C9E"), ("Green", "#3F7A55")]
            case .background:
                return [("Album Colors", ""), ("Cream", "#F1E9DA"), ("Gray", "#D9D9DC"), ("Sage", "#CFD9C8"), ("Charcoal", "#2B2B2E"), ("Navy", "#1F2A44")]
            case .line:
                return [("Album Colors", ""), ("White", "#FFFFFF"), ("Black", "#1A1A1A"), ("Red", "#E0443C"), ("Orange", "#F07A2A"), ("Blue", "#3A7BD5"), ("Green", "#3FAF6A")]
            case .text:
                return [("Album Colors", ""), ("White", "#FFFFFF"), ("Black", "#1A1A1A")]
            case .arm:
                return [("Default", ""), ("Black", "#26262A"), ("Gold", "#C9A45C"), ("Red", "#B8323A")]
            case .armBase:
                return [("Default", ""), ("Black", "#26262A"), ("Gold", "#C9A45C")]
            case .shirt:
                return [("Album Colors", ""), ("Red", "#D9483B"), ("Yellow", "#F2C230"), ("Blue", "#3A7BD5")]
            case .pants:
                return [("Album Colors", ""), ("Denim", "#3D5A80"), ("Black", "#26262A"), ("Khaki", "#B59E72")]
            case .hat:
                return [("Default", ""), ("Red", "#D9483B"), ("Yellow", "#F2C230"), ("Black", "#26262A")]
            }
        }
    }

    /// UserDefaults 키. 설정 창의 @AppStorage도 같은 키를 쓴다.
    enum Key {
        static let enabled = "enabled"
        static let position = "position"
        static let transparent = "transparent"
        static let windowLight = "windowLight"
        static let trail = "trail"
        static let grain = "grain"
        static let sideChange = "sideChange"
        static let coloredVinyl = "coloredVinyl"
        static let crowd = "crowd"
        static let crowdPace = "crowdPace"
        static let riderPose = "riderPose"
        static let autoUpdateCheck = "autoUpdateCheck"
        static let lastUpdateCheck = "lastUpdateCheck"
        static let disabledDisplays = "disabledDisplays"
        static let fps = "fps"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Key.enabled: true,
            Key.position: Position.right.rawValue,
            Key.transparent: false,
            Key.windowLight: true,
            Key.trail: Trail.afterglow.rawValue,
            Key.grain: Grain.normal.rawValue,
            Key.sideChange: SideChange.turn.rawValue,
            Key.coloredVinyl: false,
            Key.crowd: true,
            Key.crowdPace: 1,
            Key.riderPose: RiderPose.auto.rawValue,
            Key.autoUpdateCheck: true,
            Key.disabledDisplays: "",
            Key.fps: FrameRate.auto.rawValue,
        ])
    }

    /// 배경화면 창을 보일지.
    var enabled: Bool {
        get { defaults.bool(forKey: Key.enabled) }
        set { defaults.set(newValue, forKey: Key.enabled) }
    }

    var position: Position {
        get { Position(rawValue: defaults.string(forKey: Key.position) ?? "") ?? .right }
        set { defaults.set(newValue.rawValue, forKey: Key.position) }
    }

    var transparent: Bool {
        get { defaults.bool(forKey: Key.transparent) }
        set { defaults.set(newValue, forKey: Key.transparent) }
    }

    var windowLight: Bool {
        get { defaults.bool(forKey: Key.windowLight) }
        set { defaults.set(newValue, forKey: Key.windowLight) }
    }

    var trail: Trail {
        get { Trail(rawValue: defaults.string(forKey: Key.trail) ?? "") ?? .afterglow }
        set { defaults.set(newValue.rawValue, forKey: Key.trail) }
    }

    var grain: Grain {
        get { Grain(rawValue: defaults.string(forKey: Key.grain) ?? "") ?? .normal }
        set { defaults.set(newValue.rawValue, forKey: Key.grain) }
    }

    /// 레코드를 띄우지 않을 화면의 UUID(`CGDisplayCreateUUIDFromDisplayID`). 비어 있으면 모든 화면에 띄운다. 명세 4.3.
    /// 설정 창의 @AppStorage가 배열을 다루지 못해 쉼표로 이은 문자열로 저장한다.
    var disabledDisplays: Set<String> {
        get { Set((defaults.string(forKey: Key.disabledDisplays) ?? "").split(separator: ",").map(String.init)) }
        set { defaults.set(newValue.sorted().joined(separator: ","), forKey: Key.disabledDisplays) }
    }

    var fps: FrameRate {
        get { FrameRate(rawValue: defaults.string(forKey: Key.fps) ?? "") ?? .auto }
        set { defaults.set(newValue.rawValue, forKey: Key.fps) }
    }

    /// 하루에 한 번 GitHub 릴리스를 확인할지. 명세 4.10.
    var autoUpdateCheck: Bool {
        get { defaults.bool(forKey: Key.autoUpdateCheck) }
        set { defaults.set(newValue, forKey: Key.autoUpdateCheck) }
    }

    var lastUpdateCheck: Date? {
        get { defaults.object(forKey: Key.lastUpdateCheck) as? Date }
        set { defaults.set(newValue, forKey: Key.lastUpdateCheck) }
    }

    var sideChange: SideChange {
        get { SideChange(rawValue: defaults.string(forKey: Key.sideChange) ?? "") ?? .turn }
        set { defaults.set(newValue.rawValue, forKey: Key.sideChange) }
    }

    /// 판을 앨범의 주된 색으로 칠할지(컬러 바이닐). Record Color를 직접 고르면 그 색이 먼저다. 명세 6장 21.
    var coloredVinyl: Bool {
        get { defaults.bool(forKey: Key.coloredVinyl) }
        set { defaults.set(newValue, forKey: Key.coloredVinyl) }
    }

    /// 오래 들을수록 사람들이 모여드는지. 명세 6장 25.
    var crowd: Bool {
        get { defaults.bool(forKey: Key.crowd) }
        set { defaults.set(newValue, forKey: Key.crowd) }
    }

    /// 사람들이 모이고 흩어지는 시간 배율(1, 2, 5, 10). 명세 6장 25.
    var crowdPace: Int {
        get { [1, 2, 5, 10].contains(defaults.integer(forKey: Key.crowdPace)) ? defaults.integer(forKey: Key.crowdPace) : 1 }
        set { defaults.set(newValue, forKey: Key.crowdPace) }
    }

    /// 바늘 위 캐릭터의 포즈. auto면 새 곡에 가끔 바뀐다. 명세 6장 27.
    enum RiderPose: String, CaseIterable { case auto, sit, lean, cross, hug }
    var riderPose: RiderPose {
        get { RiderPose(rawValue: defaults.string(forKey: Key.riderPose) ?? "") ?? .auto }
        set { defaults.set(newValue.rawValue, forKey: Key.riderPose) }
    }

    /// "#RRGGBB" 또는 빈 문자열(앨범 색).
    func color(_ slot: ColorSlot) -> String {
        defaults.string(forKey: slot.rawValue) ?? ""
    }

    func setColor(_ hex: String, for slot: ColorSlot) {
        defaults.set(hex, forKey: slot.rawValue)
    }

    /// `TodaysRecord.setOptions`로 보내는 값. 명세 5장.
    var webOptions: [String: Any] {
        [
            "position": position.rawValue,
            "transparent": transparent,
            "windowLight": windowLight,
            "trail": trail.rawValue,
            "grain": grain.rawValue,
            "sideChange": sideChange.rawValue,
            "coloredVinyl": coloredVinyl,
            "crowd": crowd,
            "crowdPace": crowdPace,
            "recordColor": color(.record),
            "bgColor": color(.background),
            "lineColor": color(.line),
            "textColor": color(.text),
            "armColor": color(.arm),
            "armBaseColor": color(.armBase),
            "shirtColor": color(.shirt),
            "pantsColor": color(.pants),
            "hatColor": color(.hat),
            "riderPose": riderPose.rawValue,
        ]
    }
}
