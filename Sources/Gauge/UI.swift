import AppKit
import Foundation

/// Thin rounded progress bar. `progress` is 0...1 of the amount used; nil shows an empty track.
@MainActor
final class ProgressBar: NSView {
    private let fill = CALayer()
    private let tint: NSColor
    var progress: Double? { didSet { needsLayout = true } }
    /// Inexact bars (a time guide, not a real remaining amount) stay grey and never turn red.
    var isExact = true { didSet { needsLayout = true } }

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
        // Turn red when the limit is nearly used up.
        let low = isExact && (progress.map { $0 >= 0.85 } ?? false)   // nearly used up
        fill.backgroundColor = (low ? NSColor.systemRed : (isExact ? tint : NSColor(calibratedWhite: 0.5, alpha: 1))).cgColor
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
        let caption: NSTextField
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
    private let emptyLabel: NSTextField = {
        let label = makeLabel("No AI tools found yet\nInstall and sign in to Claude Code, Codex or GitHub Copilot CLI on this Mac, then press ⟳. Gauge lists each one as soon as it finds it.", size: 11, color: Palette.muted)
        label.maximumNumberOfLines = 4
        label.lineBreakMode = .byWordWrapping
        label.isHidden = true
        return label
    }()

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
        emptyLabel.heightAnchor.constraint(equalToConstant: 50).isActive = true
        stack.insertArrangedSubview(emptyLabel, at: 1)
        stack.setCustomSpacing(4, after: emptyLabel)

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
        emptyLabel.isHidden = !cards.isEmpty
        emptyLabel.stringValue = model.hasScanned
            ? "No AI tools found yet\nInstall and sign in to Claude Code, Codex or GitHub Copilot CLI on this Mac, then press ⟳. Gauge lists each one as soon as it finds it."
            : "Looking for your AI tools…"
        for (row, card) in zip(rows, cards) {
            row.name.attributedStringValue = ProviderIcons.label(card, text: card.name, font: row.name.font ?? .systemFont(ofSize: 15), color: card.tint)
            row.status.stringValue = card.cardText
            row.bar.isExact = card.progressIsExact
            row.bar.progress = card.progress
            row.bar.isHidden = card.caption != nil
            row.caption.isHidden = card.caption == nil
            row.caption.stringValue = card.caption ?? ""
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
        let caption = makeLabel("", size: 10.5, color: Palette.muted)
        caption.maximumNumberOfLines = 1
        caption.isHidden = true
        status.alignment = .right
        status.maximumNumberOfLines = 1
        name.maximumNumberOfLines = 1
        status.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        for sub in [name, status, bar, caption] { row.addSubview(sub); sub.translatesAutoresizingMaskIntoConstraints = false }
        NSLayoutConstraint.activate([
            row.heightAnchor.constraint(equalToConstant: 50),
            name.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            name.centerYAnchor.constraint(equalTo: row.centerYAnchor, constant: -4),
            bar.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: row.trailingAnchor),
            bar.bottomAnchor.constraint(equalTo: row.bottomAnchor, constant: -6),
            bar.heightAnchor.constraint(equalToConstant: 4),
            caption.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            caption.trailingAnchor.constraint(lessThanOrEqualTo: row.trailingAnchor),
            caption.bottomAnchor.constraint(equalTo: row.bottomAnchor, constant: -3),
            status.leadingAnchor.constraint(greaterThanOrEqualTo: name.trailingAnchor, constant: 12),
            status.trailingAnchor.constraint(equalTo: row.trailingAnchor),
            status.centerYAnchor.constraint(equalTo: row.centerYAnchor, constant: -4)
        ])
        return Row(id: card.id, view: row, name: name, status: status, bar: bar, caption: caption)
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
final class SettingsWindowController: NSWindowController, NSTabViewDelegate {
    private static let copilotLimits = [50, 300, 1000, 1500, 3000]
    private static let windowWidth: CGFloat = 460
    private static let contentWidth: CGFloat = 396   // width of every block, so help text wraps predictably
    private let model: AppModel
    private let tabView = NSTabView()
    private var tabStacks: [NSStackView] = []

    // Claude
    private let claudeCodeCheckbox = NSButton(checkboxWithTitle: "Track Claude Code usage on this Mac", target: nil, action: nil)
    private let claudeUnitPopup = NSPopUpButton()
    private let limitsStatus = SettingsWindowController.helpLabel("")
    private let limitsButton = NSButton()
    private let manualToggle = NSButton()
    private let manualBody = NSStackView()
    private let session = NSPopUpButton()
    private let weekly = NSPopUpButton()
    private let resetPicker = NSDatePicker()
    // ChatGPT
    private let notifyCheckbox = NSButton(checkboxWithTitle: "Notify me when my limit is almost used up", target: nil, action: nil)
    // Copilot
    private let copilotCheckbox = NSButton(checkboxWithTitle: "Count my Copilot CLI requests", target: nil, action: nil)
    private let copilotLimitField = NSComboBox()
    private let billingCheckbox = NSButton(checkboxWithTitle: "Use GitHub billing for the exact total", target: nil, action: nil)
    private let billingStatus = SettingsWindowController.helpLabel("")
    // General
    private let notchCheckbox = NSButton(checkboxWithTitle: "Show Gauge next to the notch", target: nil, action: nil)
    private let loginCheckbox = NSButton(checkboxWithTitle: "Open Gauge when I log in", target: nil, action: nil)
    private let interval = NSPopUpButton()
    private let status = SettingsWindowController.helpLabel("")

    init(model: AppModel) {
        self.model = model
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: Self.windowWidth, height: 420),
                              styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "Gauge Settings"
        window.center()
        window.isReleasedWhenClosed = false
        super.init(window: window)
        build()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) unavailable") }

    // MARK: Building blocks (one look for every setting)

    private static func helpLabel(_ text: String) -> NSTextField {
        let label = makeLabel(text, size: 11, color: .secondaryLabelColor)
        label.lineBreakMode = .byWordWrapping
        label.maximumNumberOfLines = 0
        label.preferredMaxLayoutWidth = contentWidth
        return label
    }
    private func help(_ text: String) -> NSTextField { Self.helpLabel(text) }
    private func groupTitle(_ text: String) -> NSTextField {
        makeLabel(text, size: 13, color: .labelColor, weight: .semibold)
    }
    /// A titled block: title, then controls, then optional help text.
    private func group(_ title: String, _ views: [NSView]) -> NSStackView {
        let block = verticalStack(spacing: 8)
        block.addArrangedSubview(groupTitle(title))
        views.forEach { block.addArrangedSubview($0) }
        return block
    }
    private func settingsRow(_ title: String, control: NSView) -> NSView {
        let row = horizontalStack()
        let label = makeLabel(title, size: 13, color: .labelColor)
        label.widthAnchor.constraint(equalToConstant: 130).isActive = true
        row.addArrangedSubview(label)
        row.addArrangedSubview(control)
        return row
    }
    private func addTab(_ title: String, _ groups: [NSView]) {
        let item = NSTabViewItem(identifier: title)
        item.label = title
        let container = NSView()
        let stack = verticalStack(spacing: 22)
        groups.forEach { stack.addArrangedSubview($0) }
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 18),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
            stack.widthAnchor.constraint(equalToConstant: Self.contentWidth)
        ])
        item.view = container
        tabView.addTabViewItem(item)
        tabStacks.append(stack)
    }

    // MARK: Layout

    private func build() {
        guard let content = window?.contentView else { return }
        tabView.frame = content.bounds
        tabView.autoresizingMask = [.width, .height]
        tabView.delegate = self
        content.addSubview(tabView)

        claudeCodeCheckbox.target = self; claudeCodeCheckbox.action = #selector(toggleClaudeCode)
        claudeUnitPopup.addItems(withTitles: ["Dollars (at API prices)", "Tokens"])
        claudeUnitPopup.target = self; claudeUnitPopup.action = #selector(changeClaudeUnit)
        limitsButton.bezelStyle = .rounded
        limitsButton.target = self; limitsButton.action = #selector(toggleLimits)
        limitsStatus.maximumNumberOfLines = 0
        limitsStatus.preferredMaxLayoutWidth = 230   // sits beside the button
        billingStatus.textColor = .systemOrange
        for pop in [session, weekly] {
            pop.addItem(withTitle: "Unknown")
            for value in 0...100 { pop.addItem(withTitle: "\(value)%") }
        }
        resetPicker.datePickerStyle = .textFieldAndStepper
        resetPicker.datePickerElements = [.yearMonthDay, .hourMinute]
        notifyCheckbox.target = self; notifyCheckbox.action = #selector(toggleNotify)
        copilotCheckbox.target = self; copilotCheckbox.action = #selector(toggleCopilot)
        billingCheckbox.target = self; billingCheckbox.action = #selector(toggleBilling)
        copilotLimitField.addItems(withObjectValues: Self.copilotLimits.map { String($0) })
        copilotLimitField.numberOfVisibleItems = 6
        copilotLimitField.widthAnchor.constraint(equalToConstant: 110).isActive = true
        copilotLimitField.target = self; copilotLimitField.action = #selector(changeCopilotLimit)
        notchCheckbox.target = self; notchCheckbox.action = #selector(toggleNotch)
        loginCheckbox.target = self; loginCheckbox.action = #selector(toggleLogin)
        for n in [1, 5, 10, 15] { interval.addItem(withTitle: "Every \(n) min") }
        interval.target = self; interval.action = #selector(changeInterval)

        // Claude
        let limitsRow = horizontalStack()
        limitsRow.addArrangedSubview(limitsButton)
        limitsRow.addArrangedSubview(limitsStatus)
        manualToggle.setButtonType(.pushOnPushOff)
        manualToggle.bezelStyle = .disclosure
        manualToggle.title = ""
        manualToggle.target = self; manualToggle.action = #selector(toggleManual)
        let manualHeader = horizontalStack(spacing: 6)
        manualHeader.addArrangedSubview(manualToggle)
        manualHeader.addArrangedSubview(groupTitle("Enter percentages by hand"))
        manualBody.orientation = .vertical
        manualBody.alignment = .leading
        manualBody.spacing = 8
        manualBody.translatesAutoresizingMaskIntoConstraints = false
        let manualButtons = horizontalStack()
        manualButtons.addArrangedSubview(actionButton("Save", target: self, action: #selector(saveClaude)))
        manualButtons.addArrangedSubview(actionButton("Clear", target: self, action: #selector(clearClaude)))
        manualButtons.addArrangedSubview(actionButton("Open Claude usage page", target: self, action: #selector(openClaude)))
        [help("Only needed if you do not connect real limits above. Copy the percentages from claude.ai → Settings → Usage. A value saved less than an hour ago is shown instead of dollars or tokens."),
         settingsRow("5-hour window used", control: session), settingsRow("Weekly limit used", control: weekly),
         settingsRow("Window resets at", control: resetPicker), manualButtons].forEach { manualBody.addArrangedSubview($0) }
        let manualBlock = verticalStack(spacing: 8)
        manualBlock.addArrangedSubview(manualHeader)
        manualBlock.addArrangedSubview(manualBody)
        let hasManual = model.claudeSession >= 0 || model.claudeWeekly >= 0
        manualToggle.state = hasManual ? .on : .off
        manualBody.isHidden = !hasManual

        addTab("Claude", [
            group("Usage on this Mac", [claudeCodeCheckbox, settingsRow("Show as", control: claudeUnitPopup),
                help("Dollars is what this usage would cost at public API prices. On Pro, Max and Team plans you are not billed per token, so it shows the value you get, not a charge.")]),
            group("Real limits from Claude Code", [
                help("Claude Code can tell Gauge your real 5-hour and weekly limits (or your company's spend limit). Connecting adds one line to Claude Code's settings after you confirm, keeps a backup, and keeps any status line you already use."),
                limitsRow]),
            manualBlock
        ])
        addTab("ChatGPT", [
            group("Limits", [help("Gauge asks the Codex program on this Mac for your limits and when they reset. Sign in once with your ChatGPT account using the command codex login."),
                              actionButton("Refresh now", target: self, action: #selector(refresh))]),
            group("Alerts", [notifyCheckbox, help("A normal macOS notification when 80%, 90% and 100% of your limit is used. macOS asks your permission the first time.")])
        ])
        addTab("Copilot", [
            group("Usage", [copilotCheckbox, settingsRow("Monthly requests", control: copilotLimitField),
                help("Counts your prompts from Copilot CLI logs on this Mac, per calendar month (UTC). Allowance: Free 50, Pro or Business 300, Enterprise 1000, Pro+ 1500, or type your own. VS Code, github.com and mobile chats are not included.")]),
            group("Exact total", [billingCheckbox,
                help("Asks GitHub for your real total through your own GitHub login (the gh tool), including VS Code and the website. Needs a one-time setup, described in the README."),
                billingStatus])
        ])
        addTab("General", [
            group("Display", [notchCheckbox, help("Shows your numbers beside the notch. Off: they appear in the menu bar instead.")]),
            group("Start and refresh", [loginCheckbox, settingsRow("Reload numbers", control: interval),
                help("Gauge must be in the Applications folder to open at login.")]),
            group("Privacy", [status])
        ])
        reload()
        fit(animated: false)
    }

    /// Sizes the window to the selected tab so it never stretches taller than it needs to.
    private func fit(animated: Bool = true) {
        guard let window, let item = tabView.selectedTabViewItem else { return }
        let index = tabView.indexOfTabViewItem(item)
        guard tabStacks.indices.contains(index) else { return }
        let stack = tabStacks[index]
        item.view?.layoutSubtreeIfNeeded()
        let chrome = tabView.frame.height - tabView.contentRect.height
        let height = ceil(stack.fittingSize.height) + 18 + 24 + chrome
        let target = window.frameRect(forContentRect: NSRect(x: 0, y: 0, width: Self.windowWidth, height: height))
        var frame = window.frame
        frame.origin.y += frame.height - target.height   // keep the title bar where it is
        frame.size = target.size
        window.setFrame(frame, display: true, animate: animated && window.isVisible)
    }
    func tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?) { fit() }
    @objc private func toggleManual() { manualBody.isHidden = manualToggle.state != .on; fit() }

    /// Lightweight update for values that change in the background (does not touch editable controls).
    func refreshStatus() {
        updateLimitsUI()
        updateBillingNote()
    }
    private func updateBillingNote() {
        billingStatus.stringValue = model.billingNote ?? ""
        let hide = model.billingNote == nil
        if billingStatus.isHidden != hide { billingStatus.isHidden = hide; fit(animated: false) }
    }
    func reload() {
        updateLimitsUI()
        // The model keeps "% left" (as before); the pickers show "% used", like claude.ai does.
        session.selectItem(at: model.claudeSession < 0 ? 0 : (100 - model.claudeSession) + 1)
        weekly.selectItem(at: model.claudeWeekly < 0 ? 0 : (100 - model.claudeWeekly) + 1)
        resetPicker.dateValue = model.claudeReset
        copilotCheckbox.state = model.useCopilot ? .on : .off
        copilotLimitField.stringValue = String(model.copilotLimit)
        billingCheckbox.state = model.useGitHubBilling ? .on : .off
        updateBillingNote()
        claudeCodeCheckbox.state = model.useClaudeCode ? .on : .off
        claudeUnitPopup.selectItem(at: model.claudeUnit == "tokens" ? 1 : 0)
        notchCheckbox.state = model.showNotch ? .on : .off
        notifyCheckbox.state = model.notify ? .on : .off
        loginCheckbox.state = model.launchAtLogin ? .on : .off
        interval.selectItem(at: [1,5,10,15].firstIndex(of: model.refreshMinutes) ?? 1)
        status.stringValue = model.loginError ?? "Gauge keeps everything on this Mac. It never asks for passwords, reads cookies or sends your data anywhere."
        status.textColor = model.loginError == nil ? .secondaryLabelColor : .systemOrange
    }
    @objc private func saveClaude() {
        func left(_ index: Int) -> Int { index <= 0 ? -1 : 100 - (index - 1) }   // picker shows "used"
        model.saveClaude(session: left(session.indexOfSelectedItem), weekly: left(weekly.indexOfSelectedItem), reset: resetPicker.dateValue)
    }
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
    private func updateLimitsUI() {
        let connected = ClaudeConnector.isConnected
        limitsButton.title = connected ? "Disconnect" : "Connect Claude limits"
        if ClaudeConnector.managedPolicyBlocksStatusLine {
            limitsStatus.stringValue = "Blocked by your organization's Claude Code policy"
            limitsStatus.textColor = .systemOrange
            return
        }
        limitsStatus.textColor = .secondaryLabelColor
        if !connected { limitsStatus.stringValue = "Not connected"; return }
        if let limits = model.claudeLimits {
            let minutes = max(0, Int(Date().timeIntervalSince(limits.updatedAt) / 60))
            limitsStatus.stringValue = "Connected · updated " + (minutes < 1 ? "just now" : minutes < 60 ? "\(minutes) min ago" : "\(minutes / 60) h ago")
        } else if ClaudeLimitsStore.lastHeartbeat() != nil {
            limitsStatus.stringValue = "Connected, but Claude Code reports no limits for your plan"
        } else {
            limitsStatus.stringValue = "Connected · waiting for Claude Code's next reply"
        }
    }

    @objc private func toggleLimits() {
        func fail(_ error: Error) {
            let alert = NSAlert()
            alert.messageText = "Could not change Claude Code's settings"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
        if ClaudeConnector.isConnected {
            do { try ClaudeConnector.disconnect() } catch { fail(error) }
            updateLimitsUI()
            return
        }
        if ClaudeConnector.managedPolicyBlocksStatusLine {
            let blocked = NSAlert()
            blocked.messageText = "Your organization blocks this"
            blocked.informativeText = "Your company's Claude Code settings only allow status lines and hooks that the company manages (allowManagedHooksOnly). Claude Code would silently ignore Gauge's, so nothing would arrive. Gauge left your settings untouched.\n\nAsk your administrator to allow it or to add Gauge as the managed status line. Meanwhile Gauge keeps estimating from Claude Code's local logs, and you can type your percentages by hand below."
            blocked.runModal()
            return
        }
        let executable = Bundle.main.executablePath ?? CommandLine.arguments[0]
        let alert = NSAlert()
        alert.messageText = "Connect Claude limits?"
        var text = "Gauge will add a status line entry to \(ClaudeConnector.settingsURL.path). A backup is saved next to it as settings.json.gauge-backup, and any status line you already use keeps working. You can disconnect here at any time to put everything back."
        if !executable.contains(".app/") { text += "\n\nNote: Gauge is not running from an app bundle, so the connection would point at a temporary location. Install Gauge.app in Applications first." }
        alert.informativeText = text
        alert.addButton(withTitle: "Connect")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do {
            try ClaudeConnector.connect(executable: executable)
            let done = NSAlert()
            done.messageText = "Connected"
            done.informativeText = "Real limits appear after Claude Code's next reply. Already-open Claude Code sessions may need a restart."
            done.runModal()
        } catch { fail(error) }
        updateLimitsUI()
    }

    @objc private func changeClaudeUnit() { model.claudeUnit = claudeUnitPopup.indexOfSelectedItem == 1 ? "tokens" : "dollars" }
    @objc private func toggleClaudeCode() { model.useClaudeCode = claudeCodeCheckbox.state == .on }
    @objc private func toggleNotch() { model.showNotch = notchCheckbox.state == .on }
    @objc private func toggleNotify() { model.notify = notifyCheckbox.state == .on }
    @objc private func toggleLogin() { model.setLaunchAtLogin(loginCheckbox.state == .on); reload() }
    @objc private func changeInterval() { model.refreshMinutes = [1,5,10,15][interval.indexOfSelectedItem] }
}
