import AppKit

/// 실행 인자. 명세 4.1.
struct LaunchOptions {
    var demo = false
    var windowed = false
    var logNowPlaying = false
    /// 시작할 때 설정 창을 연다(디버깅용).
    var openSettings = false
    /// 시작하자마자 업데이트를 확인하고, 새 버전이 있으면 묻지 않고 설치한다(업데이트 시험용).
    var installUpdate = false

    init(arguments: [String]) {
        for arg in arguments.dropFirst() {
            switch arg {
            case "--demo": demo = true
            case "--windowed": windowed = true
            case "--log-nowplaying": logNowPlaying = true
            case "--settings": openSettings = true
            case "--install-update": installUpdate = true
            default: break
            }
        }
    }
}

let options = LaunchOptions(arguments: CommandLine.arguments)
Log.app.info("시작 demo=\(options.demo) windowed=\(options.windowed) logNowPlaying=\(options.logNowPlaying)")

let app = NSApplication.shared
let delegate = AppDelegate(options: options)
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
