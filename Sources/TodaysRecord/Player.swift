import AppKit

/// 재생 정보를 읽는 플레이어 앱. 명세 4.5, 4.5.1.
enum PlayerKind: String, CaseIterable {
    // 순서가 우선순위다. 앱 시작 때 이 순서로 묻는다(4.5.2, 둘 다 재생 중이면 Music).
    case music, spotify

    var name: String {
        switch self {
        case .music: return "Music"
        case .spotify: return "Spotify"
        }
    }

    var bundleID: String {
        switch self {
        case .music: return "com.apple.Music"
        case .spotify: return "com.spotify.client"
        }
    }

    /// 곡 변경, 재생, 일시정지, 정지 때 오는 분산 알림.
    var notification: Notification.Name {
        switch self {
        case .music: return Notification.Name("com.apple.Music.playerInfo")
        case .spotify: return Notification.Name("com.spotify.client.PlaybackStateChanged")
        }
    }

    /// 꺼져 있는 앱에는 AppleScript를 보내지 않는다(보내면 앱이 실행된다). 메인 스레드에서만 부른다.
    /// NSRunningApplication.runningApplications(withBundleIdentifier:)는 다른 앱이 종료되는 순간
    /// 실행 중인 앱을 빠뜨릴 때가 있어(2026-10 확인), 종료 알림과 함께 갱신되는 NSWorkspace 목록을 쓴다.
    var isRunning: Bool {
        assert(Thread.isMainThread, "isRunning은 메인 스레드에서만 부른다")
        return NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == bundleID }
    }
}

enum PlayerStatus {
    case info(NowPlayingInfo)
    case notAuthorized
    case failed
}

protocol Player: AnyObject {
    var kind: PlayerKind { get }
    /// AppleScript 큐에서만 부른다. running은 메인 스레드에서 확인한 실행 여부.
    func status(running: Bool) -> PlayerStatus
    /// 플레이어가 주는 커버(4.6의 1순위). AppleScript 큐에서만 부른다. 결과는 아무 스레드에서나 온다.
    func artwork(for info: NowPlayingInfo, running: Bool, completion: @escaping (Data?) -> Void)
}

/// 컴파일한 AppleScript를 기억해 두고 실행한다. AppleScript 큐에서만 쓴다.
final class AppleScriptRunner {
    static let notAuthorized = -1743

    enum Result {
        case output(NSAppleEventDescriptor)
        case error(code: Int)
    }

    private let label: String
    private let source: String
    private let logToStdout: Bool
    private var script: NSAppleScript?

    init(label: String, source: String, logToStdout: Bool) {
        self.label = label
        self.source = source
        self.logToStdout = logToStdout
    }

    func run() -> Result {
        if script == nil {
            script = NSAppleScript(source: source)
        }
        var error: NSDictionary?
        let started = DispatchTime.now()
        let output = script?.executeAndReturnError(&error)
        let elapsed = Double(DispatchTime.now().uptimeNanoseconds - started.uptimeNanoseconds) / 1_000_000
        Log.nowPlaying.debug("\(self.label, privacy: .public) \(elapsed, format: .fixed(precision: 1))ms")
        if let error {
            let code = error[NSAppleScript.errorNumber] as? Int ?? 0
            Log.nowPlaying.error("\(self.label, privacy: .public) 오류 \(code): \(String(describing: error[NSAppleScript.errorMessage] ?? ""), privacy: .public)")
            if logToStdout { stdout("[\(label)] 오류 \(code) \(error)") }
            return .error(code: code)
        }
        if logToStdout { stdout("[\(label)] \(String(format: "%.1f", elapsed))ms") }
        return .output(output ?? NSAppleEventDescriptor.null())
    }
}

/// 상태 스크립트의 결과 구분자.
let fieldSeparator = "\u{1F}"

/// 지역 설정에 따라 소수점이 쉼표일 수 있다.
func parseNumber(_ text: String) -> Double {
    Double(text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")) ?? 0
}
