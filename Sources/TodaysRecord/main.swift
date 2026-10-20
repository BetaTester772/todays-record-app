import AppKit

/// 실행 인자. 명세 4.1.
struct LaunchOptions {
    var demo = false
    var windowed = false
    var logNowPlaying = false

    init(arguments: [String]) {
        for arg in arguments.dropFirst() {
            switch arg {
            case "--demo": demo = true
            case "--windowed": windowed = true
            case "--log-nowplaying": logNowPlaying = true
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
