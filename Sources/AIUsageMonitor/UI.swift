import AppKit
import Foundation

private enum Palette {
    static let background = NSColor.black
    static let muted = NSColor(calibratedWhite: 0.66, alpha: 1)
    static let orange = NSColor(calibratedRed: 0.92, green: 0.64, blue: 0.45, alpha: 1)
    static let blue = NSColor(calibratedRed: 0.59, green: 0.74, blue: 0.98, alpha: 1)
}

enum Layout {
    /// Size of the usage card (menu-bar popover and notch panel share it).
    static let card = NSSize(width: 300, height: 170)
}

@MainActor
func makeLabel(_ title: String, size: CGFloat = 12, color: NSColor = .white, weight: NSFont.Weight = .regular) -> NSTextField {
    let label = NSTextField(labelWithString: title)
    label.font = NSFont.systemFont(ofSize: size, weight: weight)
    label.textColor = color
    label.lineBreakMode = .byTruncatingTail
    label.maximumNumberOfLines = 2
    return label
}

@MainActor
func actionButton(_ title: String, target: AnyObject, action: Selector) -> NSButton {
    let button = NSButton(title: title, target: target, action: action)
    button.bezelStyle = .rounded
    return button
}

@MainActor
func verticalStack(spacing: CGFloat = 10) -> NSStackView {
    let stack = NSStackView()
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.spacing = spacing
    stack.translatesAutoresizingMaskIntoConstraints = false
    return stack
}

@MainActor
func horizontalStack(spacing: CGFloat = 8) -> NSStackView {
    let stack = NSStackView()
    stack.orientation = .horizontal
    stack.alignment = .centerY
    stack.spacing = spacing
    return stack
}

@MainActor
final class DashboardViewController: NSViewController {
    private let model: AppModel
    private let claudeStatus = makeLabel("", size: 15, color: Palette.muted)
    private let codexStatus = makeLabel("", size: 15, color: Palette.muted)
    private let updatedStatus = makeLabel("", size: 11, color: Palette.muted)
    private let refreshButton = NSButton()

    init(model: AppModel) {
        self.model = model
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) unavailable") }

    override func loadView() {
        let root = NSView(frame: NSRect(origin: .zero, size: Layout.card))
        root.wantsLayer = true
        root.layer?.backgroundColor = Palette.background.cgColor
        root.layer?.cornerRadius = 22
        root.layer?.masksToBounds = true

        let stack = verticalStack(spacing: 0)
        stack.alignment = .width
        root.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 18),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -18),
            stack.topAnchor.constraint(equalTo: root.topAnchor, constant: 14),
            stack.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -10)
        ])

        let heading = horizontalStack(spacing: 0)
        heading.addArrangedSubview(makeLabel("AI Usage", size: 15, weight: .medium))
        let headingSpacer = NSView()
        headingSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        heading.addArrangedSubview(headingSpacer)
        let settingsButton = iconButton("gearshape", label: "Settings", action: #selector(settings))
        heading.addArrangedSubview(settingsButton)
        heading.heightAnchor.constraint(equalToConstant: 28).isActive = true
        stack.addArrangedSubview(heading)
        stack.setCustomSpacing(6, after: heading)

        let claudeRow = providerRow("✳  Claude", status: claudeStatus, color: Palette.orange)
        stack.addArrangedSubview(claudeRow)
        stack.setCustomSpacing(0, after: claudeRow)

        let divider = NSView()
        divider.wantsLayer = true
        divider.layer?.backgroundColor = NSColor(calibratedWhite: 0.25, alpha: 1).cgColor
        divider.heightAnchor.constraint(equalToConstant: 1).isActive = true
        stack.addArrangedSubview(divider)
        stack.setCustomSpacing(0, after: divider)

        let codexRow = providerRow("✦  ChatGPT", status: codexStatus, color: Palette.blue)
        stack.addArrangedSubview(codexRow)
        stack.setCustomSpacing(4, after: codexRow)

        let footer = horizontalStack(spacing: 0)
        footer.addArrangedSubview(updatedStatus)
        let footerSpacer = NSView()
        footerSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        footer.addArrangedSubview(footerSpacer)
        refreshButton.image = NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: "Refresh")
        refreshButton.isBordered = false
        refreshButton.contentTintColor = Palette.muted
        refreshButton.target = self
        refreshButton.action = #selector(refresh)
        refreshButton.toolTip = "Refresh usage"
        refreshButton.setContentHuggingPriority(.required, for: .horizontal)
        refreshButton.widthAnchor.constraint(equalToConstant: 24).isActive = true
        refreshButton.heightAnchor.constraint(equalToConstant: 24).isActive = true
        footer.addArrangedSubview(refreshButton)
        footer.heightAnchor.constraint(equalToConstant: 24).isActive = true
        stack.addArrangedSubview(footer)

        view = root
        update()
    }

    func update() {
        guard isViewLoaded else { return }
        if model.claudeSession >= 0 {
            claudeStatus.stringValue = "\(model.claudeSession)% left"
        } else if model.claudeWeekly >= 0 {
            claudeStatus.stringValue = "\(model.claudeWeekly)% weekly"
        } else {
            claudeStatus.stringValue = "No data"
        }

        if let codex = model.shortestCodex {
            let remaining = "\(Int(codex.remainingPercent.rounded()))% left"
            codexStatus.stringValue = model.codexStale ? "\(remaining) · Stale" : remaining
        } else {
            codexStatus.stringValue = model.busy ? "Updating…" : "Unavailable"
        }

        if model.error != nil {
            updatedStatus.stringValue = "Refresh failed"
            refreshButton.toolTip = model.error
        } else if let lastUpdated = model.lastUpdated {
            let seconds = max(0, Int(model.now.timeIntervalSince(lastUpdated)))
            if seconds < 60 {
                updatedStatus.stringValue = "Updated just now"
            } else {
                updatedStatus.stringValue = "Updated \(seconds / 60) min ago"
            }
            refreshButton.toolTip = "Refresh usage"
        } else {
            updatedStatus.stringValue = model.busy ? "Updating…" : "Not updated yet"
            refreshButton.toolTip = model.error ?? "Refresh usage"
        }
        refreshButton.isEnabled = !model.busy
    }

    private func providerRow(_ title: String, status: NSTextField, color: NSColor) -> NSView {
        let row = NSView()
        let name = makeLabel(title, size: 15, color: color, weight: .medium)
        status.alignment = .right
        status.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        row.addSubview(name)
        row.addSubview(status)
        name.translatesAutoresizingMaskIntoConstraints = false
        status.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            row.heightAnchor.constraint(equalToConstant: 42),
            name.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            name.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            status.leadingAnchor.constraint(greaterThanOrEqualTo: name.trailingAnchor, constant: 12),
            status.trailingAnchor.constraint(equalTo: row.trailingAnchor),
            status.centerYAnchor.constraint(equalTo: row.centerYAnchor)
        ])
        return row
    }

    private func iconButton(_ symbol: String, label: String, action: Selector) -> NSButton {
        let button = NSButton()
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
        button.isBordered = false
        button.contentTintColor = Palette.muted
        button.target = self
        button.action = action
        button.toolTip = label
        button.widthAnchor.constraint(equalToConstant: 28).isActive = true
        button.heightAnchor.constraint(equalToConstant: 28).isActive = true
        return button
    }

    @objc private func refresh() { model.refresh() }
    @objc private func settings() { AppDelegate.instance?.showSettings() }
}

@MainActor
final class SettingsWindowController: NSWindowController {
    private let model: AppModel
    private let stack = verticalStack(spacing: 13)
    private let session = NSPopUpButton()
    private let weekly = NSPopUpButton()
    private let resetPicker = NSDatePicker()
    private let notchCheckbox = NSButton(checkboxWithTitle: "Show notch panel", target: nil, action: nil)
    private let notifyCheckbox = NSButton(checkboxWithTitle: "Notify when Codex has 20%, 10%, or 0% left", target: nil, action: nil)
    private let loginCheckbox = NSButton(checkboxWithTitle: "Launch at Login (.app only)", target: nil, action: nil)
    private let interval = NSPopUpButton()
    private let status = makeLabel("", size: 11, color: .systemOrange)

    init(model: AppModel) {
        self.model = model
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 490, height: 510), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "AI Usage Monitor · Settings"
        window.center()
        window.isReleasedWhenClosed = false
        super.init(window: window)
        build()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) unavailable") }
    private func build() {
        guard let content = window?.contentView else { return }
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 18),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor, constant: -18)
        ])
        stack.addArrangedSubview(makeLabel("Claude · manual subscription usage", size: 15, color: .labelColor, weight: .semibold))
        let help = makeLabel("Copy percentages from Claude → Settings → Usage. Unknown values are not guessed.", size: 11, color: .secondaryLabelColor)
        help.maximumNumberOfLines = 2
        stack.addArrangedSubview(help)
        for pop in [session, weekly] {
            pop.addItem(withTitle: "Unknown")
            for value in 0...100 { pop.addItem(withTitle: "\(value)%") }
        }
        stack.addArrangedSubview(settingsRow("5-hour remaining", control: session))
        stack.addArrangedSubview(settingsRow("Weekly remaining", control: weekly))
        resetPicker.datePickerStyle = .textFieldAndStepper
        resetPicker.datePickerElements = [.yearMonthDay, .hourMinute]
        stack.addArrangedSubview(settingsRow("Session reset", control: resetPicker))
        let claudeButtons = horizontalStack()
        claudeButtons.addArrangedSubview(actionButton("Save snapshot", target: self, action: #selector(saveClaude)))
        claudeButtons.addArrangedSubview(actionButton("Clear", target: self, action: #selector(clearClaude)))
        claudeButtons.addArrangedSubview(actionButton("Open Claude Usage", target: self, action: #selector(openClaude)))
        stack.addArrangedSubview(claudeButtons)
        stack.addArrangedSubview(makeLabel("ChatGPT · Codex subscription", size: 15, color: .labelColor, weight: .semibold))
        let codexHelp = makeLabel("Uses Codex CLI App Server. Codex quotas are NOT all ChatGPT chat limits.", size: 11, color: .secondaryLabelColor)
        codexHelp.maximumNumberOfLines = 2
        stack.addArrangedSubview(codexHelp)
        stack.addArrangedSubview(actionButton("Refresh Codex now", target: self, action: #selector(refresh)))
        stack.addArrangedSubview(makeLabel("App behavior", size: 15, color: .labelColor, weight: .semibold))
        for box in [notchCheckbox, notifyCheckbox, loginCheckbox] { stack.addArrangedSubview(box) }
        notchCheckbox.target = self; notchCheckbox.action = #selector(toggleNotch)
        notifyCheckbox.target = self; notifyCheckbox.action = #selector(toggleNotify)
        loginCheckbox.target = self; loginCheckbox.action = #selector(toggleLogin)
        for n in [1, 5, 10, 15] { interval.addItem(withTitle: "\(n) min") }
        interval.target = self; interval.action = #selector(changeInterval)
        stack.addArrangedSubview(settingsRow("Auto-refresh", control: interval))
        status.maximumNumberOfLines = 2
        stack.addArrangedSubview(status)
        reload()
    }
    private func settingsRow(_ title: String, control: NSView) -> NSView {
        let row = horizontalStack()
        let label = makeLabel(title, size: 12, color: .labelColor)
        label.widthAnchor.constraint(equalToConstant: 155).isActive = true
        row.addArrangedSubview(label)
        row.addArrangedSubview(control)
        return row
    }
    func reload() {
        session.selectItem(at: model.claudeSession + 1)
        weekly.selectItem(at: model.claudeWeekly + 1)
        resetPicker.dateValue = model.claudeReset
        notchCheckbox.state = model.showNotch ? .on : .off
        notifyCheckbox.state = model.notify ? .on : .off
        loginCheckbox.state = model.launchAtLogin ? .on : .off
        interval.selectItem(at: [1,5,10,15].firstIndex(of: model.refreshMinutes) ?? 1)
        status.stringValue = model.loginError ?? "Local-only · No passwords or session cookies collected"
    }
    @objc private func saveClaude() { model.saveClaude(session: session.indexOfSelectedItem - 1, weekly: weekly.indexOfSelectedItem - 1, reset: resetPicker.dateValue) }
    @objc private func clearClaude() { model.clearClaude(); reload() }
    @objc private func openClaude() { NSWorkspace.shared.open(URL(string: "https://claude.ai/settings/usage")!) }
    @objc private func refresh() { model.refresh() }
    @objc private func toggleNotch() { model.showNotch = notchCheckbox.state == .on }
    @objc private func toggleNotify() { model.notify = notifyCheckbox.state == .on }
    @objc private func toggleLogin() { model.setLaunchAtLogin(loginCheckbox.state == .on); reload() }
    @objc private func changeInterval() { model.refreshMinutes = [1,5,10,15][interval.indexOfSelectedItem] }
}
