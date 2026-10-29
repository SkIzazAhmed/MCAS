// Log.swift
//
// What: one logger per feature folder (capture, storage, paste, notch, app).
// Why:  when something goes wrong, open Console.app, search "com.izaz.mcas",
//       and you can see exactly which part of the app said what.
//
// Privacy rule: never log clipboard *contents*. Log kinds, sizes and counts only.

import OSLog

enum Log {
    static let subsystem = Bundle.main.bundleIdentifier ?? "com.izaz.mcas"

    static let app = Logger(subsystem: subsystem, category: "app")
    static let capture = Logger(subsystem: subsystem, category: "capture")
    static let storage = Logger(subsystem: subsystem, category: "storage")
    static let paste = Logger(subsystem: subsystem, category: "paste")
    static let notch = Logger(subsystem: subsystem, category: "notch")
}

enum AppEnvironment {
    /// True while Xcode is running our unit tests (⌘U).
    /// During tests the app must NOT watch your real clipboard or touch your real history.
    static var isRunningTests: Bool {
        let env = ProcessInfo.processInfo.environment
        return env["XCTestConfigurationFilePath"] != nil
            || env["XCTestBundlePath"] != nil
            || env["XCTestSessionIdentifier"] != nil
    }
}
