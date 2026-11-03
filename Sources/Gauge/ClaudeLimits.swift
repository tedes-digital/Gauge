import Foundation

// Real Claude limits come from Claude Code itself. Claude Code runs a user-configured "status line" command and
// pipes it a JSON document that includes `rate_limits` (5-hour and 7-day windows, or a gateway spend limit).
// Gauge can be that command (`Gauge --statusline`): it saves the numbers to a small file and the app reads them.

struct ClaudeLimitWindow: Equatable {
    let usedPercent: Double
    let resetsAt: Date?
}

struct ClaudeSpendLimit: Equatable {
    let usedPercent: Double
    let resetsAt: Date?
    let usedUSD: Double?
    let limitUSD: Double?
    let period: String?
}

struct ClaudeLimits: Equatable {
    /// When these numbers were captured from Claude Code.
    let updatedAt: Date
    let fiveHour: ClaudeLimitWindow?
    let sevenDay: ClaudeLimitWindow?
    let spend: ClaudeSpendLimit?
    var isEmpty: Bool { fiveHour == nil && sevenDay == nil && spend == nil }
}

enum ClaudeLimitsStore {
    /// `GAUGE_SUPPORT_DIR` lets tests use a scratch folder.
    static var directory: URL {
        if let override = ProcessInfo.processInfo.environment["GAUGE_SUPPORT_DIR"] { return URL(fileURLWithPath: override) }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Gauge")
    }
    static var limitsFile: URL { directory.appendingPathComponent("claude-limits.json") }
    /// The user's previous status line command, which Gauge keeps running after it takes over the slot.
    static var chainFile: URL { directory.appendingPathComponent("statusline-chain.txt") }

    private static func number(_ value: Any?) -> Double? { (value as? NSNumber)?.doubleValue }
    private static func date(_ value: Any?) -> Date? { number(value).map { Date(timeIntervalSince1970: $0) } }

    private static func window(_ value: Any?) -> ClaudeLimitWindow? {
        guard let dict = value as? [String: Any], let used = number(dict["used_percentage"]) else { return nil }
        return ClaudeLimitWindow(usedPercent: used, resetsAt: date(dict["resets_at"]))
    }

    private static func parse(_ rateLimits: [String: Any], updatedAt: Date) -> ClaudeLimits {
        var spend: ClaudeSpendLimit?
        if let dict = rateLimits["spend_limit"] as? [String: Any], let used = number(dict["used_percentage"]) {
            spend = ClaudeSpendLimit(usedPercent: used, resetsAt: date(dict["resets_at"]), usedUSD: number(dict["used_usd"]),
                                     limitUSD: number(dict["limit_usd"]), period: dict["period"] as? String)
        }
        return ClaudeLimits(updatedAt: updatedAt, fiveHour: window(rateLimits["five_hour"]),
                            sevenDay: window(rateLimits["seven_day"]), spend: spend)
    }

    private static func load() -> (limits: ClaudeLimits?, heartbeat: Date?)? {
        guard let data = try? Data(contentsOf: limitsFile),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let heartbeat = date(object["heartbeat"])
        guard let rate = object["rate_limits"] as? [String: Any], let captured = date(object["updated_at"]) else { return (nil, heartbeat) }
        let limits = parse(rate, updatedAt: captured)
        return (limits.isEmpty ? nil : limits, heartbeat)
    }

    /// The latest numbers Claude Code reported, or nil when none were ever captured.
    static func read() -> ClaudeLimits? { load()?.limits }

    /// The last time Claude Code ran the status line at all (even if it reported no limits).
    static func lastHeartbeat() -> Date? { load()?.heartbeat }

    /// Saves `rate_limits` from a status line payload. Without it (plans that do not report limits), only the
    /// heartbeat is updated so the settings can say so.
    static func capture(_ payload: Data, now: Date = Date()) {
        guard let object = try? JSONSerialization.jsonObject(with: payload) as? [String: Any] else { return }
        var saved: [String: Any] = [:]
        if let existing = try? Data(contentsOf: limitsFile),
           let old = try? JSONSerialization.jsonObject(with: existing) as? [String: Any] { saved = old }
        saved["heartbeat"] = now.timeIntervalSince1970
        if let rate = object["rate_limits"] as? [String: Any], !rate.isEmpty {
            saved["rate_limits"] = rate
            saved["updated_at"] = now.timeIntervalSince1970
        }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if let data = try? JSONSerialization.data(withJSONObject: saved) { try? data.write(to: limitsFile, options: .atomic) }
    }
}

/// Entry point for `Gauge --statusline`. Runs for every Claude Code status line update, so it stays tiny.
enum StatusLineBridge {
    static func run() {
        let input = FileHandle.standardInput.readDataToEndOfFile()
        ClaudeLimitsStore.capture(input)
        // Keep the user's previous status line alive: feed it the same input and pass its output through.
        guard let chain = try? String(contentsOf: ClaudeLimitsStore.chainFile, encoding: .utf8)
                .trimmingCharacters(in: .whitespacesAndNewlines), !chain.isEmpty else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", chain]
        let stdin = Pipe(), stdout = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return }
        stdin.fileHandleForWriting.write(input)
        stdin.fileHandleForWriting.closeFile()
        let output = stdout.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        FileHandle.standardOutput.write(output)
    }
}

enum ClaudeConnectorError: LocalizedError {
    case unreadable
    var errorDescription: String? {
        "Claude Code's settings file is not valid JSON, so Gauge left it untouched. Fix or remove it and try again."
    }
}

/// Adds or removes Gauge as Claude Code's status line command, with a backup and without losing an existing one.
enum ClaudeConnector {
    static var settingsURL: URL {
        let base = ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"]?.split(separator: ",").first.map { URL(fileURLWithPath: String($0)) }
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude")
        return base.appendingPathComponent("settings.json")
    }
    private static let marker = "--statusline"

    private static func load() throws -> [String: Any] {
        guard FileManager.default.fileExists(atPath: settingsURL.path) else { return [:] }
        let data = try Data(contentsOf: settingsURL)
        if data.isEmpty { return [:] }
        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { throw ClaudeConnectorError.unreadable }
        return object
    }

    private static func save(_ settings: [String: Any]) throws {
        try FileManager.default.createDirectory(at: settingsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try data.write(to: settingsURL, options: .atomic)
    }

    private static func command(of statusLine: Any?) -> String? { (statusLine as? [String: Any])?["command"] as? String }

    static var isConnected: Bool {
        guard let settings = try? load() else { return false }
        return command(of: settings["statusLine"])?.contains(marker) == true
    }

    /// `executable` is the Gauge binary Claude Code will run.
    static func connect(executable: String) throws {
        var settings = try load()
        let ours = "\"\(executable)\" \(marker)"
        let existing = command(of: settings["statusLine"])
        if existing?.contains(marker) == true && existing == ours { return }

        // One-time backup of the original file.
        let backup = settingsURL.appendingPathExtension("gauge-backup")
        if FileManager.default.fileExists(atPath: settingsURL.path), !FileManager.default.fileExists(atPath: backup.path) {
            try FileManager.default.copyItem(at: settingsURL, to: backup)
        }
        try FileManager.default.createDirectory(at: ClaudeLimitsStore.directory, withIntermediateDirectories: true)
        if let existing, !existing.contains(marker) {
            try existing.write(to: ClaudeLimitsStore.chainFile, atomically: true, encoding: .utf8)
        }
        var statusLine = (settings["statusLine"] as? [String: Any]) ?? [:]
        statusLine["type"] = "command"
        statusLine["command"] = ours
        settings["statusLine"] = statusLine
        try save(settings)
    }

    /// Restores the user's previous status line (if there was one) and stops capturing.
    static func disconnect() throws {
        var settings = try load()
        guard command(of: settings["statusLine"])?.contains(marker) == true else { return }
        if let previous = try? String(contentsOf: ClaudeLimitsStore.chainFile, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines), !previous.isEmpty {
            var statusLine = (settings["statusLine"] as? [String: Any]) ?? [:]
            statusLine["command"] = previous
            settings["statusLine"] = statusLine
        } else {
            settings.removeValue(forKey: "statusLine")
        }
        try save(settings)
        try? FileManager.default.removeItem(at: ClaudeLimitsStore.chainFile)
    }
}
