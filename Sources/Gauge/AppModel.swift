import Foundation
import AppKit
import ServiceManagement
import UserNotifications

@MainActor
final class AppModel {
    static let shared = AppModel()
    var onChange: (() -> Void)?
    private let defaults = UserDefaults.standard
    private var tickTimer: Timer?
    private var refreshTimer: Timer?
    private var alertBands: [String: Int] = [:]
    private(set) var windows: [UsageWindow] = []
    private(set) var lastUpdated: Date?
    private(set) var busy = false
    private(set) var error: String?
    private(set) var loginError: String?
    private(set) var now = Date()
    private(set) var claudeLocal: ClaudeLocalUsage?
    private let claudeCode = ClaudeCodeClient()

    var claudeSession: Int { didSet { defaults.set(claudeSession, forKey: "claudeSession"); changed() } }
    var claudeWeekly: Int { didSet { defaults.set(claudeWeekly, forKey: "claudeWeekly"); changed() } }
    var claudeReset: Date { didSet { defaults.set(claudeReset, forKey: "claudeReset"); changed() } }
    var claudeSavedAt: Date? { didSet {
        if let claudeSavedAt { defaults.set(claudeSavedAt, forKey: "claudeSavedAt") }
        else { defaults.removeObject(forKey: "claudeSavedAt") }
        changed()
    }}
    var useClaudeCode: Bool { didSet { defaults.set(useClaudeCode, forKey: "useClaudeCode"); refresh(); changed() } }
    var showNotch: Bool { didSet { defaults.set(showNotch, forKey: "showNotch"); changed() } }
    var notify: Bool { didSet {
        defaults.set(notify, forKey: "notify")
        if notify { UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in } }
        changed()
    }}
    var refreshMinutes: Int { didSet {
        defaults.set(refreshMinutes, forKey: "refreshMinutes")
        setupRefreshTimer()
        changed()
    }}
    var launchAtLogin: Bool { SMAppService.mainApp.status == .enabled }
    var claudeStale: Bool { guard let saved = claudeSavedAt else { return true }; return now.timeIntervalSince(saved) > 3600 }
    var codexStale: Bool { error != nil || lastUpdated == nil || (lastUpdated.map { now.timeIntervalSince($0) > Double(refreshMinutes * 60 + 90) } ?? true) }
    private var manualClaudeFresh: Bool { claudeSession >= 0 && !claudeStale }
    /// Short text for the menu bar and notch badge.
    var claudeBarText: String {
        if manualClaudeFresh { return "\(claudeSession)%" }
        if let local = claudeLocal { return compactTokens(local.sessionTokens ?? local.weeklyTokens) }
        return claudeSession >= 0 ? "\(claudeSession)%" : "—"
    }
    /// Text for the dashboard card.
    var claudeCardText: String {
        if manualClaudeFresh { return "\(claudeSession)% left" }
        if let local = claudeLocal {
            if let tokens = local.sessionTokens {
                return "\(compactTokens(tokens)) · \(resetText(local.sessionResetsAt, now: now).replacingOccurrences(of: "Resets in ", with: ""))"
            }
            return "Idle · \(compactTokens(local.weeklyTokens)) / 7d"
        }
        if claudeSession >= 0 { return "\(claudeSession)% left · Stale" }
        if claudeWeekly >= 0 { return "\(claudeWeekly)% weekly" }
        return "No data"
    }
    var shortestCodex: UsageWindow? { windows.min { $0.remainingPercent < $1.remainingPercent } }

    private init() {
        claudeSession = defaults.object(forKey: "claudeSession") as? Int ?? -1
        claudeWeekly = defaults.object(forKey: "claudeWeekly") as? Int ?? -1
        claudeReset = defaults.object(forKey: "claudeReset") as? Date ?? .now
        claudeSavedAt = defaults.object(forKey: "claudeSavedAt") as? Date
        useClaudeCode = defaults.object(forKey: "useClaudeCode") as? Bool ?? true
        showNotch = defaults.object(forKey: "showNotch") as? Bool ?? true
        notify = defaults.object(forKey: "notify") as? Bool ?? false
        refreshMinutes = defaults.object(forKey: "refreshMinutes") as? Int ?? 5
    }
    private func changed() { onChange?() }

    func start() {
        tickTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.now = .now
                self?.changed()
            }
        }
        tickTimer?.tolerance = 5
        setupRefreshTimer()
        refresh()
    }
    private func setupRefreshTimer() {
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: Double(max(1, refreshMinutes) * 60), repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }
    func refresh() {
        guard !busy else { return }
        busy = true
        changed()
        let readClaudeCode = useClaudeCode
        DispatchQueue.global(qos: .utility).async { [weak self, claudeCode] in
            let result = Result { try CodexClient().fetch() }
            let local = readClaudeCode ? claudeCode.fetch() : nil
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.busy = false
                self.claudeLocal = local
                switch result {
                case .success(let windows):
                    self.windows = windows
                    self.error = nil
                    self.lastUpdated = Date()
                    self.checkNotifications(windows)
                case .failure(let error):
                    self.error = error.localizedDescription
                    // Keep last successful values, but clearly mark them STALE.
                }
                self.changed()
            }
        }
    }
    func saveClaude(session: Int, weekly: Int, reset: Date) {
        claudeSession = session
        claudeWeekly = weekly
        claudeReset = reset
        claudeSavedAt = Date()
    }
    func clearClaude() {
        claudeSession = -1
        claudeWeekly = -1
        claudeSavedAt = nil
    }
    func setLaunchAtLogin(_ enable: Bool) {
        guard Bundle.main.bundleURL.pathExtension == "app" else {
            loginError = "Install and open the .app bundle first (not swift run)."
            changed()
            return
        }
        do {
            if enable { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            loginError = nil
        } catch { loginError = error.localizedDescription }
        changed()
    }
    private func checkNotifications(_ values: [UsageWindow]) {
        guard notify else { return }
        for item in values {
            let remaining = item.remainingPercent
            let band = remaining <= 0 ? 0 : remaining <= 10 ? 10 : remaining <= 20 ? 20 : 101
            let previous = alertBands[item.id] ?? 101
            alertBands[item.id] = band
            guard band < previous, band != 101 else { continue }
            let note = UNMutableNotificationContent()
            note.title = "Codex usage warning"
            note.body = "\(item.name): \(Int(remaining.rounded()))% remaining"
            UNUserNotificationCenter.current().add(
                UNNotificationRequest(identifier: UUID().uuidString, content: note, trigger: nil)
            ) { _ in }
        }
    }
}

func resetText(_ reset: Date?, now: Date) -> String {
    guard let reset else { return "Reset time unavailable" }
    let seconds = Int(reset.timeIntervalSince(now))
    if seconds <= 0 { return "Reset passed · refresh usage" }
    let days = seconds / 86400
    let hours = (seconds % 86400) / 3600
    let minutes = (seconds % 3600) / 60
    if days > 0 { return "Resets in \(days)d \(hours)h" }
    if hours > 0 { return "Resets in \(hours)h \(minutes)m" }
    return "Resets in \(max(1, minutes))m"
}
