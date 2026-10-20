import os

enum Log {
    static let subsystem = "com.todaysrecord"
    static let app = Logger(subsystem: subsystem, category: "app")
    static let window = Logger(subsystem: subsystem, category: "window")
    static let web = Logger(subsystem: subsystem, category: "web")
}
