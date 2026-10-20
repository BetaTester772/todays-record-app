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

    /// 화면 그레인(잡음 무늬) 세기.
    enum Grain: String, CaseIterable {
        case off, low, normal, high
    }

    /// 사용자가 고를 수 있는 색. 빈 문자열이면 앨범에서 뽑은 색을 쓴다.
    enum ColorSlot: String, CaseIterable {
        case record = "recordColor"
        case background = "bgColor"
        case line = "lineColor"

        var menuTitle: String {
            switch self {
            case .record: return "Record Color"
            case .background: return "Background Color"
            case .line: return "Line Color"
            }
        }

        /// 첫 항목은 앨범 색.
        var presets: [(title: String, hex: String)] {
            switch self {
            case .record:
                return [("Album Colors", ""), ("Black", "#1C1B1E"), ("White", "#F4F0E6"), ("Red", "#B8323A"), ("Blue", "#2F5C9E"), ("Green", "#3F7A55")]
            case .background:
                return [("Album Colors", ""), ("Cream", "#F1E9DA"), ("Gray", "#D9D9DC"), ("Sage", "#CFD9C8"), ("Charcoal", "#2B2B2E"), ("Navy", "#1F2A44")]
            case .line:
                return [("Album Colors", ""), ("White", "#FFFFFF"), ("Black", "#1A1A1A"), ("Red", "#E0443C"), ("Orange", "#F07A2A"), ("Blue", "#3A7BD5"), ("Green", "#3FAF6A")]
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
            "recordColor": color(.record),
            "bgColor": color(.background),
            "lineColor": color(.line),
        ]
    }
}
