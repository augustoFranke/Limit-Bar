import os

enum Log {
    private static let subsystem = "com.augustodorego.LimitBar"
    static let refresh = Logger(subsystem: subsystem, category: "refresh")
    static let codex = Logger(subsystem: subsystem, category: "codex")
    static let claude = Logger(subsystem: subsystem, category: "claude")
    static let notifications = Logger(subsystem: subsystem, category: "notifications")
}
