import Foundation

/// UserDefaults에 저장되는 설정. 명세 4.8.
final class Settings {
    enum Position: String, CaseIterable {
        case left, center, right
    }

    enum Trail: String, CaseIterable {
        case keep, afterglow
    }

    private enum Key {
        static let enabled = "enabled"
        static let position = "position"
        static let transparent = "transparent"
        static let windowLight = "windowLight"
        static let trail = "trail"
        static let recordColor = "recordColor"
    }

    /// 메뉴에 보이는 레코드 판 색. 빈 문자열은 앨범에서 뽑은 색.
    static let recordColorPresets: [(title: String, hex: String)] = [
        ("Album Colors", ""),
        ("Black", "#1C1B1E"),
        ("White", "#F4F0E6"),
        ("Red", "#B8323A"),
        ("Blue", "#2F5C9E"),
        ("Green", "#3F7A55"),
    ]

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Key.enabled: true,
            Key.position: Position.right.rawValue,
            Key.transparent: false,
            Key.windowLight: true,
            Key.trail: Trail.afterglow.rawValue,
            Key.recordColor: "",
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

    /// "#RRGGBB" 또는 빈 문자열(앨범 색).
    var recordColor: String {
        get { defaults.string(forKey: Key.recordColor) ?? "" }
        set { defaults.set(newValue, forKey: Key.recordColor) }
    }

    /// `TodaysRecord.setOptions`로 보내는 값. 명세 5장.
    var webOptions: [String: Any] {
        [
            "position": position.rawValue,
            "transparent": transparent,
            "windowLight": windowLight,
            "trail": trail.rawValue,
            "recordColor": recordColor,
        ]
    }
}
