import OSLog

nonisolated enum Log {
    static let app = Logger(subsystem: "io.github.ender-wang.EdgeMark", category: "app")
    static let storage = Logger(subsystem: "io.github.ender-wang.EdgeMark", category: "storage")
    static let window = Logger(subsystem: "io.github.ender-wang.EdgeMark", category: "window")
    static let shortcuts = Logger(subsystem: "io.github.ender-wang.EdgeMark", category: "shortcuts")
    static let updates = Logger(subsystem: "io.github.ender-wang.EdgeMark", category: "updates")
}
