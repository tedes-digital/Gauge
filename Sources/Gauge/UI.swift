import AppKit
import Foundation

/// Thin rounded progress bar. `progress` is 0...1 of the remaining amount; nil shows an empty track.
@MainActor
final class ProgressBar: NSView {
    private let fill = CALayer()
    private let tint: NSColor
    var progress: Double? { didSet { needsLayout = true } }

    init(tint: NSColor) {
        self.tint = tint
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor(calibratedWhite: 0.2, alpha: 1).cgColor
        layer?.cornerRadius = 2
        fill.cornerRadius = 2
        layer?.addSublayer(fill)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) unavailable") }

    override func layout() {
        super.layout()
        let value = max(0, min(1, progress ?? 0))
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.25)
        fill.frame = CGRect(x: 0, y: 0, width: bounds.width * value, height: bounds.height)
        // Turn red when little is left.
        fill.backgroundColor = (progress.map { $0 <= 0.15 } ?? false ? NSColor.systemRed : tint).cgColor
        CATransaction.commit()
    }
}

/// A plain container that reports pointer enter/exit (works in non-activating panels too).
@MainActor
final class HoverRow: NSView {
    var onHover: ((Bool) -> Void)?
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }
    override func mouseEntered(with event: NSEvent) { onHover?(true) }
    override func mouseExited(with event: NSEvent) { onHover?(false) }
}

/// Opaque overlay with a two-column list (name left, value right), shown over the other rows while hovering one.
@MainActor
final class DetailsView: NSView {
    static let lineHeight: CGFloat = 17
    static let inset: CGFloat = 3
    private let names = makeLabel("", size: 11, color: Palette.muted)
    private let values = makeLabel("", size: 11, color: .white)
    private var topPins: [NSLayoutConstraint] = []
    private var bottomPins: [NSLayoutConstraint] = []

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = Palette.background.cgColor
        isHidden = true
        for label in [names, values] {
            label.maximumNumberOfLines = 0
            label.lineBreakMode = .byTruncatingTail
            label.translatesAutoresizingMaskIntoConstraints = false
            addSubview(label)
            topPins.append(label.topAnchor.constraint(equalTo: topAnchor, constant: Self.inset))
            bottomPins.append(label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Self.inset))
        }
        values.alignment = .right
        values.setContentHuggingPriority(.required, for: .horizontal)
        NSLayoutConstraint.activate([
            names.leadingAnchor.constraint(equalTo: leadingAnchor),
            values.trailingAnchor.constraint(equalTo: trailingAnchor),
            names.trailingAnchor.constraint(lessThanOrEqualTo: values.leadingAnchor, constant: -10)
        ])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) unavailable") }

    /// How many lines fit in a frame of this height.
    static func capacity(height: CGFloat) -> Int { max(1, Int((height - inset * 2) / lineHeight)) }

    /// `anchorBottom` hugs the lower edge (used when the list sits above the hovered row).
    func set(_ lines: [(name: String, value: String)], tint: NSColor, anchorBottom: Bool) {
        let style = NSMutableParagraphStyle()
        style.minimumLineHeight = Self.lineHeight
        style.maximumLineHeight = Self.lineHeight
        style.lineBreakMode = .byTruncatingTail
        func text(_ strings: [String], color: NSColor, align: NSTextAlignment) -> NSAttributedString {
            let paragraph = style.mutableCopy() as! NSMutableParagraphStyle
            paragraph.alignment = align
            return NSAttributedString(string: strings.joined(separator: "\n"),
                                      attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: color, .paragraphStyle: paragraph])
        }
        names.attributedStringValue = text(lines.map(\.name), color: Palette.muted, align: .left)
        values.attributedStringValue = text(lines.map(\.value), color: tint, align: .right)
        NSLayoutConstraint.deactivate(anchorBottom ? topPins : bottomPins)
        NSLayoutConstraint.activate(anchorBottom ? bottomPins : topPins)
    }
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
    private struct Row {
        let id: String
        let view: HoverRow
        let name: NSTextField
        let status: NSTextField
        let bar: ProgressBar
    }

    private let model: AppModel
    private let stack = verticalStack(spacing: 0)
    private let details = DetailsView()
    private var rows: [Row] = []
    private var hovered: Int?
    private let updatedStatus: NSTextField = {
        let label = makeLabel("", size: 11, color: Palette.muted)
        label.maximumNumberOfLines = 1
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return label
    }()
    private let refreshButton = NSButton()

    init(model: AppModel) {
        self.model = model
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) unavailable") }

    override func loadView() {
        let root = NSView(frame: NSRect(origin: .zero, size: Layout.cardSize(rows: model.cards.count)))
        root.wantsLayer = true
        root.layer?.backgroundColor = Palette.background.cgColor
        root.layer?.cornerRadius = 22
        root.layer?.masksToBounds = true

        stack.alignment = .width
        root.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 18),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -18),
            stack.topAnchor.constraint(equalTo: root.topAnchor, constant: 12),
            stack.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -8)
        ])

        let heading = horizontalStack(spacing: 0)
        heading.addArrangedSubview(makeLabel("AI Usage", size: 15, weight: .medium))
        let headingSpacer = NSView()
        headingSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        heading.addArrangedSubview(headingSpacer)
        heading.addArrangedSubview(iconButton("gearshape", label: "Settings", action: #selector(settings)))
        heading.addArrangedSubview(iconButton("power", label: "Quit Gauge", action: #selector(quit)))
        heading.heightAnchor.constraint(equalToConstant: 26).isActive = true
        stack.addArrangedSubview(heading)
        stack.setCustomSpacing(4, after: heading)

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
        footer.heightAnchor.constraint(equalToConstant: 22).isActive = true
        stack.addArrangedSubview(footer)

        root.addSubview(details)   // above the stack, so it can cover rows
        view = root
        update()
    }

    /// Rebuilds the provider rows when the set of services changes.
    private func syncRows(_ cards: [ProviderCard]) {
        guard cards.map(\.id) != rows.map(\.id) else { return }
        rows.forEach { stack.removeArrangedSubview($0.view); $0.view.removeFromSuperview() }
        rows = cards.enumerated().map { index, card in
            let row = makeRow(card)
            row.view.onHover = { [weak self] inside in
                guard let self else { return }
                if inside { self.hovered = index } else if self.hovered == index { self.hovered = nil }
                self.update()
            }
            stack.insertArrangedSubview(row.view, at: 1 + index)
            stack.setCustomSpacing(4, after: row.view)
            return row
        }
        hovered = nil
        view.setFrameSize(Layout.cardSize(rows: cards.count))
    }

    func update() {
        guard isViewLoaded else { return }
        let cards = model.cards
        syncRows(cards)
        for (row, card) in zip(rows, cards) {
            row.name.attributedStringValue = ProviderIcons.label(card, text: card.name, font: row.name.font ?? .systemFont(ofSize: 15), color: card.tint)
            row.status.stringValue = card.cardText
            row.bar.progress = card.progress
        }

        if model.error != nil {
            updatedStatus.stringValue = "Refresh failed"
            refreshButton.toolTip = model.error
        } else if let lastUpdated = model.lastUpdated {
            let seconds = max(0, Int(model.now.timeIntervalSince(lastUpdated)))
            updatedStatus.stringValue = seconds < 60 ? "Updated just now" : "Updated \(seconds / 60) min ago"
            refreshButton.toolTip = "Refresh usage"
        } else {
            updatedStatus.stringValue = model.busy ? "Updating…" : "Not updated yet"
            refreshButton.toolTip = "Refresh usage"
        }
        refreshButton.isEnabled = !model.busy
        updateDetails(cards)
    }

    /// Covers the rows below the hovered one (or above it, for the last row) with its per-project breakdown.
    /// The list starts right under the hovered row's progress bar.
    private func updateDetails(_ cards: [ProviderCard]) {
        guard let index = hovered, index < cards.count, !cards[index].lines.isEmpty, rows.count > 1 else {
            details.isHidden = true
            return
        }
        view.layoutSubtreeIfNeeded()
        let below = index < rows.count - 1
        let covered = below ? Array(rows[(index + 1)...]) : Array(rows[..<index])
        let frames = covered.map { stack.convert($0.view.frame, to: view) }
        guard let first = frames.first else { return }
        var frame = frames.dropFirst().reduce(first) { $0.union($1) }
        // Stretch over the 4 pt gap so the list begins at the hovered row's edge (y grows upward here).
        if below { frame.size.height += 4 } else { frame.origin.y -= 4; frame.size.height += 4 }
        details.frame = frame
        let lines = Array(cards[index].lines.prefix(DetailsView.capacity(height: frame.height)))
        details.set(lines, tint: cards[index].tint, anchorBottom: !below)
        details.isHidden = false
    }

    private func makeRow(_ card: ProviderCard) -> Row {
        let row = HoverRow()
        let name = makeLabel("", size: 15, color: card.tint, weight: .medium)
        let status = makeLabel("", size: 15, color: Palette.muted)
        let bar = ProgressBar(tint: card.tint)
        status.alignment = .right
        status.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        for sub in [name, status, bar] { row.addSubview(sub); sub.translatesAutoresizingMaskIntoConstraints = false }
        NSLayoutConstraint.activate([
            row.heightAnchor.constraint(equalToConstant: 50),
            name.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            name.centerYAnchor.constraint(equalTo: row.centerYAnchor, constant: -4),
            bar.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: row.trailingAnchor),
            bar.bottomAnchor.constraint(equalTo: row.bottomAnchor, constant: -6),
            bar.heightAnchor.constraint(equalToConstant: 4),
            status.leadingAnchor.constraint(greaterThanOrEqualTo: name.trailingAnchor, constant: 12),
            status.trailingAnchor.constraint(equalTo: row.trailingAnchor),
            status.centerYAnchor.constraint(equalTo: row.centerYAnchor, constant: -4)
        ])
        return Row(id: card.id, view: row, name: name, status: status, bar: bar)
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
    @objc private func quit() { NSApp.terminate(nil) }
    @objc private func settings() { AppDelegate.instance?.showSettings() }
}

@MainActor
final class SettingsWindowController: NSWindowController {
    private static let copilotLimits = [50, 300, 1000, 1500, 3000]
    private let model: AppModel
    private let stack = verticalStack(spacing: 13)
    private let session = NSPopUpButton()
    private let weekly = NSPopUpButton()
    private let resetPicker = NSDatePicker()
    private let notchCheckbox = NSButton(checkboxWithTitle: "Show notch panel", target: nil, action: nil)
    private let notifyCheckbox = NSButton(checkboxWithTitle: "Notify when Codex has 20%, 10%, or 0% left", target: nil, action: nil)
    private let claudeUnitPopup = NSPopUpButton()
    private let claudeCodeCheckbox = NSButton(checkboxWithTitle: "Track Claude Code usage from local logs", target: nil, action: nil)
    private let copilotCheckbox = NSButton(checkboxWithTitle: "Track GitHub Copilot CLI requests", target: nil, action: nil)
    private let billingCheckbox = NSButton(checkboxWithTitle: "Exact total from GitHub billing (uses your gh login)", target: nil, action: nil)
    private let billingStatus = makeLabel("", size: 11, color: .systemOrange)
    private let copilotLimitField = NSComboBox()
    private let loginCheckbox = NSButton(checkboxWithTitle: "Launch at Login (.app only)", target: nil, action: nil)
    private let interval = NSPopUpButton()
    private let status = makeLabel("", size: 11, color: .systemOrange)

    init(model: AppModel) {
        self.model = model
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 490, height: 760), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "Gauge · Settings"
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
        stack.addArrangedSubview(claudeCodeCheckbox)
        claudeCodeCheckbox.target = self; claudeCodeCheckbox.action = #selector(toggleClaudeCode)
        claudeUnitPopup.addItems(withTitles: ["Dollars (API list prices)", "Tokens"])
        claudeUnitPopup.target = self; claudeUnitPopup.action = #selector(changeClaudeUnit)
        stack.addArrangedSubview(settingsRow("Claude Code shows", control: claudeUnitPopup))
        let unitHelp = makeLabel("Dollars is what this usage would cost at public API prices. Pro, Max and Team plans are not billed per token, so treat it as the value you get, not a charge.", size: 11, color: .secondaryLabelColor)
        unitHelp.maximumNumberOfLines = 3
        stack.addArrangedSubview(unitHelp)
        stack.addArrangedSubview(makeLabel("Claude · manual subscription usage", size: 15, color: .labelColor, weight: .semibold))
        let help = makeLabel("Optional: copy percentages from Claude → Settings → Usage. Fresh manual values take priority over Claude Code token counts (5-hour session / 7 days).", size: 11, color: .secondaryLabelColor)
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
        stack.addArrangedSubview(makeLabel("GitHub Copilot", size: 15, color: .labelColor, weight: .semibold))
        let copilotHelp = makeLabel("Counts your prompts from Copilot CLI logs on this Mac per calendar month (UTC). Chat in VS Code, GitHub.com and mobile is not included. Allowance: Free 50, Pro/Business 300, Enterprise 1000, Pro+ 1500, or type your own. An estimate; GitHub billing is authoritative.", size: 11, color: .secondaryLabelColor)
        copilotHelp.maximumNumberOfLines = 4
        stack.addArrangedSubview(copilotHelp)
        stack.addArrangedSubview(copilotCheckbox)
        copilotCheckbox.target = self; copilotCheckbox.action = #selector(toggleCopilot)
        stack.addArrangedSubview(billingCheckbox)
        billingCheckbox.target = self; billingCheckbox.action = #selector(toggleBilling)
        billingStatus.maximumNumberOfLines = 3
        stack.addArrangedSubview(billingStatus)
        copilotLimitField.addItems(withObjectValues: Self.copilotLimits.map { String($0) })
        copilotLimitField.numberOfVisibleItems = 6
        copilotLimitField.widthAnchor.constraint(equalToConstant: 110).isActive = true
        copilotLimitField.target = self; copilotLimitField.action = #selector(changeCopilotLimit)
        let allowance = settingsRow("Monthly requests", control: copilotLimitField)
        stack.addArrangedSubview(allowance)
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
    /// Lightweight update for values that change in the background (does not touch editable controls).
    func refreshStatus() {
        billingStatus.stringValue = model.billingNote ?? ""
        billingStatus.isHidden = model.billingNote == nil
    }
    func reload() {
        session.selectItem(at: model.claudeSession + 1)
        weekly.selectItem(at: model.claudeWeekly + 1)
        resetPicker.dateValue = model.claudeReset
        copilotCheckbox.state = model.useCopilot ? .on : .off
        copilotLimitField.stringValue = String(model.copilotLimit)
        billingCheckbox.state = model.useGitHubBilling ? .on : .off
        billingStatus.stringValue = model.billingNote ?? ""
        billingStatus.isHidden = model.billingNote == nil
        claudeCodeCheckbox.state = model.useClaudeCode ? .on : .off
        claudeUnitPopup.selectItem(at: model.claudeUnit == "tokens" ? 1 : 0)
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
    @objc private func toggleBilling() { model.useGitHubBilling = billingCheckbox.state == .on; reload() }
    @objc private func toggleCopilot() { model.useCopilot = copilotCheckbox.state == .on }
    @objc private func changeCopilotLimit() {
        let text = copilotLimitField.indexOfSelectedItem >= 0
            ? (copilotLimitField.objectValueOfSelectedItem as? String ?? "") : copilotLimitField.stringValue
        let digits = text.filter(\.isNumber)
        if let value = Int(digits), value > 0 { model.copilotLimit = min(value, 1_000_000) }
        copilotLimitField.stringValue = String(model.copilotLimit)   // reject invalid input
    }
    @objc private func changeClaudeUnit() { model.claudeUnit = claudeUnitPopup.indexOfSelectedItem == 1 ? "tokens" : "dollars" }
    @objc private func toggleClaudeCode() { model.useClaudeCode = claudeCodeCheckbox.state == .on }
    @objc private func toggleNotch() { model.showNotch = notchCheckbox.state == .on }
    @objc private func toggleNotify() { model.notify = notifyCheckbox.state == .on }
    @objc private func toggleLogin() { model.setLaunchAtLogin(loginCheckbox.state == .on); reload() }
    @objc private func changeInterval() { model.refreshMinutes = [1,5,10,15][interval.indexOfSelectedItem] }
}
