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
    private(set) var codexPlan: String?
    private(set) var codexCredits: CodexCredits?
    private(set) var codexSpendReached = false
    private(set) var lastUpdated: Date?
    private(set) var busy = false
    private(set) var error: String?
    private(set) var loginError: String?
    private(set) var now = Date()
    private(set) var claudeLocal: ClaudeLocalUsage?
    private(set) var codexProjects: [ProjectUsage] = []
    private(set) var codexProjectsWeek: [ProjectUsage] = []
    private(set) var copilotUsage: CopilotUsage?
    private(set) var copilotBilling = BillingResult(requests: nil, note: nil)
    private let githubBilling = GitHubBillingClient()
    private let copilotLog = CopilotLogClient()
    private let codexLog = CodexLogClient()
    private let claudeCode = ClaudeCodeClient()

    var claudeSession: Int { didSet { defaults.set(claudeSession, forKey: "claudeSession"); changed() } }
    var claudeWeekly: Int { didSet { defaults.set(claudeWeekly, forKey: "claudeWeekly"); changed() } }
    var claudeReset: Date { didSet { defaults.set(claudeReset, forKey: "claudeReset"); changed() } }
    var claudeSavedAt: Date? { didSet {
        if let claudeSavedAt { defaults.set(claudeSavedAt, forKey: "claudeSavedAt") }
        else { defaults.removeObject(forKey: "claudeSavedAt") }
        changed()
    }}
    var useCopilot: Bool { didSet { defaults.set(useCopilot, forKey: "useCopilot"); refresh(); changed() } }
    /// Monthly premium-request allowance of the user's Copilot plan (Free 50, Pro 300, Pro+ 1500).
    /// Opt-in: exact totals from GitHub's billing API through the user's `gh` login.
    var useGitHubBilling: Bool { didSet { defaults.set(useGitHubBilling, forKey: "useGitHubBilling"); refresh(force: true); changed() } }
    var copilotLimit: Int { didSet { defaults.set(copilotLimit, forKey: "copilotLimit"); changed() } }
    /// "dollars" shows API-equivalent USD for Claude Code usage; "tokens" shows raw token counts.
    var claudeUnit: String { didSet { defaults.set(claudeUnit, forKey: "claudeUnit"); changed() } }
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
    private func claudeAmount(tokens: Int, cost: Double) -> String { claudeUnit == "dollars" ? money(cost) : compactTokens(tokens) }
    var claudeBarText: String {
        if manualClaudeFresh { return "\(claudeSession)%" }
        if let local = claudeLocal {
            return claudeAmount(tokens: local.sessionTokens ?? local.weeklyTokens, cost: local.sessionCost ?? local.weeklyCost)
        }
        return claudeSession >= 0 ? "\(claudeSession)%" : "—"
    }
    /// 0...1 for the Claude bar: remaining % when known, otherwise the time left in the current 5-hour session.
    var claudeProgress: Double? {
        if manualClaudeFresh { return Double(claudeSession) / 100 }
        if let local = claudeLocal, let resets = local.sessionResetsAt { return max(0, min(1, resets.timeIntervalSince(now) / (5 * 3600))) }
        if claudeLocal != nil { return 1 }
        return claudeSession >= 0 ? Double(claudeSession) / 100 : nil
    }
    /// Per-project lines for the card (at most 4 rows; the rest are folded into "+N more").
    private func lines(_ projects: [ProjectUsage], amount: (Int, Double) -> String) -> [(name: String, tokens: String)] {
        guard !projects.isEmpty else { return [] }
        var rows = projects.prefix(projects.count > 4 ? 3 : 4).map { (name: String($0.name.prefix(24)), tokens: amount($0.tokens, $0.cost)) }
        if projects.count > 4 {
            let rest = projects.dropFirst(3)
            rows.append((name: "+\(rest.count) more", tokens: amount(rest.reduce(0) { $0 + $1.tokens }, rest.reduce(0) { $0 + $1.cost })))
        }
        return rows
    }
    /// When the current window is empty, say so and fall back to the 7-day picture so hovering is never a dead end.
    private func idleLines(_ title: String, week: [ProjectUsage]) -> [(name: String, tokens: String)] {
        var rows: [(name: String, tokens: String)] = [(title, ""), ("Last 7 days", compactTokens(week.reduce(0) { $0 + $1.tokens }))]
        rows += week.prefix(2).map { (name: "  " + String($0.name.prefix(22)), tokens: compactTokens($0.tokens)) }
        return rows
    }
    var claudeProjectLines: [(name: String, tokens: String)] {
        guard let local = claudeLocal else { return [] }
        var rows: [(name: String, tokens: String)]
        if !local.sessionProjects.isEmpty {
            rows = lines(local.sessionProjects, amount: claudeAmount)
        } else {
            rows = [("No active session", ""), ("Last 7 days", claudeAmount(tokens: local.weeklyTokens, cost: local.weeklyCost))]
        }
        if claudeUnit == "dollars" { rows.append(("At API list prices, not a bill", "")) }
        return rows
    }
    var codexProjectLines: [(name: String, tokens: String)] {
        if !codexProjects.isEmpty { return lines(codexProjects) { tokens, _ in compactTokens(tokens) } }
        return codexProjectsWeek.isEmpty ? [] : idleLines("No activity in this window", week: codexProjectsWeek)
    }
    private var codexBarText: String {
        if let codex = shortestCodex { return "\(codexStale ? "~" : "")\(Int(codex.remainingPercent.rounded()))%" }
        if codexCredits?.unlimited == true { return "∞" }
        if codexSpendReached { return "0" }
        if let balance = codexCredits?.balance, codexCredits?.hasCredits == true { return balance }
        return "—"
    }
    private var codexCardText: String {
        if codexSpendReached { return "Spend limit reached" }
        if let codex = shortestCodex {
            let remaining = "\(Int(codex.remainingPercent.rounded()))% left"
            if codexStale { return "\(remaining) · Stale" }
            if let countdown = shortCountdown(codex.resetsAt, now: now) { return "\(remaining) · \(countdown)" }
            return remaining
        }
        // No percent windows: admin-managed or credit-based plan.
        if let credits = codexCredits {
            if credits.unlimited { return "Unlimited" }
            if credits.hasCredits { return "Credits \(credits.balance ?? "")" }
        }
        return busy ? "Updating…" : "Unavailable"
    }
    private func windowLabel(_ minutes: Int?) -> String {
        switch minutes {
        case 300: return "5-hour limit"
        case 10080: return "Weekly limit"
        case let m?: return m % 1440 == 0 ? "\(m / 1440)-day limit" : "\(m / 60)-hour limit"
        case nil: return "Limit"
        }
    }
    /// One line per rate-limit window ("Weekly limit  79% · 3d 4h"), shown before the per-project list.
    private var codexWindowLines: [(name: String, value: String)] {
        windows.sorted { ($0.durationMinutes ?? 0) < ($1.durationMinutes ?? 0) }.map { w in
            let left = "\(Int(w.remainingPercent.rounded()))%"
            let value = shortCountdown(w.resetsAt, now: now).map { "\(left) · \($0)" } ?? left
            return (name: windowLabel(w.durationMinutes), value: value)
        }
    }
    private var codexProgress: Double? {
        if let codex = shortestCodex { return codex.remainingPercent / 100 }
        if codexSpendReached { return 0 }
        if codexCredits?.unlimited == true { return 1 }
        return nil
    }
    private func rows(_ items: [(name: String, tokens: String)]) -> [(name: String, value: String)] {
        items.map { (name: $0.name, value: $0.tokens) }
    }

    private var copilotCard: ProviderCard? {
        let exact = useGitHubBilling ? copilotBilling.requests : nil
        guard useCopilot, copilotUsage != nil || exact != nil else { return nil }
        let used = exact ?? copilotUsage?.requests ?? 0
        let limit = max(1, copilotLimit)
        var lines: [(name: String, value: String)] = (copilotUsage?.projects ?? []).prefix(3).map {
            (name: String($0.name.prefix(24)), value: "\(formatRequests($0.amount)) req")
        }
        if lines.isEmpty { lines = [("No CLI requests this month", "")] }
        if exact != nil {
            lines.append(("Total from GitHub billing", ""))
        } else {
            // VS Code / web / mobile chat is not visible locally; say why the number may be low.
            lines.append((useGitHubBilling ? "CLI only · GitHub billing unavailable" : "Copilot CLI only", ""))
        }
        return ProviderCard(id: "copilot", glyph: "◆", name: "Copilot", tint: Palette.green,
                            barText: formatRequests(used),
                            cardText: "\(formatRequests(used)) / \(limit) req",
                            progress: max(0, 1 - used / Double(limit)), lines: lines)
    }

    /// Why GitHub billing could not be read (nil when it works or is off). Shown in Settings.
    var billingNote: String? { useGitHubBilling ? copilotBilling.note : nil }

    /// The services shown in the card, the notch badge and the menu bar, in display order.
    var cards: [ProviderCard] {
        var list = [
            ProviderCard(id: "claude", glyph: "✳", name: "Claude", tint: Palette.orange, barText: claudeBarText,
                         cardText: claudeCardText, progress: claudeProgress, lines: rows(claudeProjectLines)),
            ProviderCard(id: "codex", glyph: "✦", name: "ChatGPT", tint: Palette.blue, barText: codexBarText,
                         cardText: codexCardText, progress: codexProgress,
                         lines: codexWindowLines + rows(codexProjectLines))
        ]
        if let copilot = copilotCard { list.append(copilot) }
        return list
    }
    /// Text for the dashboard card.
    var claudeCardText: String {
        if manualClaudeFresh { return "\(claudeSession)% left" }
        if let local = claudeLocal {
            if let tokens = local.sessionTokens {
                let amount = claudeAmount(tokens: tokens, cost: local.sessionCost ?? 0)
                return "\(amount) · \(resetText(local.sessionResetsAt, now: now).replacingOccurrences(of: "Resets in ", with: ""))"
            }
            return "Idle · \(claudeAmount(tokens: local.weeklyTokens, cost: local.weeklyCost)) / 7d"
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
        useCopilot = defaults.object(forKey: "useCopilot") as? Bool ?? true
        useGitHubBilling = defaults.object(forKey: "useGitHubBilling") as? Bool ?? false
        copilotLimit = defaults.object(forKey: "copilotLimit") as? Int ?? 300
        claudeUnit = defaults.string(forKey: "claudeUnit") ?? "dollars"
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
    func refresh(force: Bool = false) {
        guard !busy else { return }
        busy = true
        changed()
        let readClaudeCode = useClaudeCode
        let readCopilot = useCopilot
        let readBilling = useGitHubBilling
        let knownWindows = windows
        DispatchQueue.global(qos: .utility).async { [weak self, claudeCode, codexLog, copilotLog, githubBilling] in
            let result = Result { try CodexClient().fetch() }
            let local = readClaudeCode ? claudeCode.fetch() : nil
            let copilot = readCopilot ? copilotLog.fetch() : nil
            let billing = (readCopilot && readBilling) ? githubBilling.fetch(force: force) : BillingResult(requests: nil, note: nil)
            // Per-project Codex usage over the shortest rate-limit window (normally the 5-hour one).
            let current = (try? result.get())?.windows ?? knownWindows
            let window = current.compactMap { w in w.durationMinutes.map { (w, $0) } }.min { $0.1 < $1.1 }
            let since = window.flatMap { w, minutes in w.resetsAt.map { $0.addingTimeInterval(-Double(minutes) * 60) } }
                ?? Date().addingTimeInterval(-5 * 3600)
            let projects = codexLog.projects(since: since)
            let week = codexLog.projects(since: Date().addingTimeInterval(-7 * 86400))
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.busy = false
                self.claudeLocal = local
                self.codexProjects = projects
                self.copilotUsage = copilot
                self.copilotBilling = billing
                self.codexProjectsWeek = week
                switch result {
                case .success(let limits):
                    self.windows = limits.windows
                    self.codexPlan = limits.planType
                    self.codexCredits = limits.credits
                    self.codexSpendReached = limits.spendControlReached
                    self.error = nil
                    self.lastUpdated = Date()
                    self.checkNotifications(limits.windows)
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

/// Compact countdown such as "2h 10m" or "3d 4h"; nil when unknown or already passed.
func shortCountdown(_ reset: Date?, now: Date) -> String? {
    guard let reset, reset.timeIntervalSince(now) > 0 else { return nil }
    return resetText(reset, now: now).replacingOccurrences(of: "Resets in ", with: "")
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
