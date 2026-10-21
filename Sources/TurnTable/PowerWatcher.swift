import AppKit
import IOKit.ps

/// 화면 잠자기, 시스템 잠자기, 화면 잠금, 배터리 사용을 감지한다. 명세 4.7.
/// 창이 가려진 것은 창마다 다르므로 WallpaperController가 따로 본다.
final class PowerWatcher {
    enum Reason: String {
        case screensAsleep, systemAsleep, locked
    }

    /// 화면 전체를 멈출 이유가 생기거나 모두 풀리면 메인 스레드에서 불린다.
    var onPausedChange: ((Bool) -> Void)?
    /// 배터리 사용 여부가 바뀌면 메인 스레드에서 불린다.
    var onBatteryChange: ((Bool) -> Void)?

    private(set) var reasons: Set<Reason> = []
    private(set) var onBattery = false
    var isPaused: Bool { !reasons.isEmpty }

    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var powerSource: CFRunLoopSource?

    deinit {
        observers.forEach { center, token in center.removeObserver(token) }
        if let powerSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), powerSource, .defaultMode) }
    }

    func start() {
        let workspace = NSWorkspace.shared.notificationCenter
        observe(workspace, NSWorkspace.screensDidSleepNotification) { $0.set(.screensAsleep, true) }
        observe(workspace, NSWorkspace.screensDidWakeNotification) { $0.set(.screensAsleep, false) }
        observe(workspace, NSWorkspace.willSleepNotification) { $0.set(.systemAsleep, true) }
        observe(workspace, NSWorkspace.didWakeNotification) { $0.set(.systemAsleep, false) }
        let distributed = DistributedNotificationCenter.default()
        observe(distributed, Notification.Name("com.apple.screenIsLocked")) { $0.set(.locked, true) }
        observe(distributed, Notification.Name("com.apple.screenIsUnlocked")) { $0.set(.locked, false) }

        onBattery = Self.isOnBattery()
        let context = Unmanaged.passUnretained(self).toOpaque()
        if let source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            Unmanaged<PowerWatcher>.fromOpaque(context).takeUnretainedValue().powerSourceChanged()
        }, context)?.takeRetainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
            powerSource = source
        }
        Log.app.info("전원 \(self.onBattery ? "배터리" : "충전기", privacy: .public)")
    }

    private func observe(_ center: NotificationCenter, _ name: Notification.Name, _ action: @escaping (PowerWatcher) -> Void) {
        observers.append((center, center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            action(self)
        }))
    }

    private func set(_ reason: Reason, _ active: Bool) {
        let wasPaused = isPaused
        if active { reasons.insert(reason) } else { reasons.remove(reason) }
        Log.app.info("절전 \(reason.rawValue, privacy: .public)=\(active) 멈춤=\(self.isPaused)")
        if wasPaused != isPaused { onPausedChange?(isPaused) }
    }

    private func powerSourceChanged() {
        let battery = Self.isOnBattery()
        guard battery != onBattery else { return }
        onBattery = battery
        Log.app.info("전원 \(battery ? "배터리" : "충전기", privacy: .public)")
        onBatteryChange?(battery)
    }

    private static func isOnBattery() -> Bool {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let type = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() else { return false }
        return (type as String) == kIOPMBatteryPowerKey
    }
}
