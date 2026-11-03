import AppKit
import Foundation

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static var instance: AppDelegate?
    private let model = AppModel.shared
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var dashboard: DashboardViewController!
    private var notchDashboard: DashboardViewController!
    private var islandPanel: NSPanel?
    private var cardPanel: NSPanel?
    private var settingsWindow: SettingsWindowController?
    private var mouseMonitor: Any?
    private var localMouseMonitor: Any?
    private var expanded = false
    private var lastNotchEnabled = true
    private let badge = NSView()          // content of the island panel
    private let cardHost = NSView()       // content of the card panel
    private var badgeLabels: [NSTextField] = []
    private var cardHeight: NSLayoutConstraint!
    private var notchGeneration = 0
    private var lastRowCount = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        Self.instance = self
        NSApp.setActivationPolicy(.accessory)
        dashboard = DashboardViewController(model: model)
        notchDashboard = DashboardViewController(model: model)
        popover = NSPopover()
        popover.behavior = .transient
        popover.contentSize = Layout.cardSize(rows: model.cards.count)
        popover.contentViewController = dashboard

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.target = self
        statusItem.button?.action = #selector(statusItemClicked)
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        statusItem.button?.toolTip = "Gauge · click to open · right-click for menu"
        model.onChange = { [weak self] in self?.updateUI() }
        lastNotchEnabled = model.showNotch
        if model.showNotch { buildNotch() }
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) { [weak self] event in
            Task { @MainActor in self?.checkMousePosition() }
        }
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.expanded = false
                self?.cardPanel?.orderOut(nil)
                self?.applyNotchLayout()
                self?.updateUI()
            }
        }
        // Moves inside our own panel are not seen by the global monitor.
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved]) { [weak self] event in
            MainActor.assumeIsolated { self?.checkMousePosition() }
            return event
        }
        updateUI()
        model.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let mouseMonitor { NSEvent.removeMonitor(mouseMonitor) }
        if let localMouseMonitor { NSEvent.removeMonitor(localMouseMonitor) }
    }

    @objc private func statusItemClicked() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            let menu = NSMenu()
            menu.addItem(withTitle: "Refresh", action: #selector(refreshNow), keyEquivalent: "r").target = self
            menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",").target = self
            menu.addItem(.separator())
            menu.addItem(withTitle: "Quit Gauge", action: #selector(quit), keyEquivalent: "q").target = self
            statusItem.menu = menu
            statusItem.button?.performClick(nil)
            statusItem.menu = nil   // keep left-click opening the popover
        } else {
            toggleMenu()
        }
    }
    @objc private func refreshNow() { model.refresh() }
    @objc private func openSettings() { showSettings() }
    @objc private func quit() { NSApp.terminate(nil) }

    private func toggleMenu() {
        guard let button = statusItem.button else { return }
        if popover.isShown { popover.performClose(nil) }
        else {
            dashboard.update()
            popover.contentSize = dashboard.view.frame.size
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    func showSettings() {
        if settingsWindow == nil { settingsWindow = SettingsWindowController(model: model) }
        settingsWindow?.reload()
        settingsWindow?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.window?.makeKeyAndOrderFront(nil)
    }

    private func updateUI() {
        let cards = model.cards
        // With a notch, the island already shows the numbers: keep only an icon in the menu bar.
        if (cards.isEmpty || (hasNotchScreen && model.showNotch)), let icon = NSImage(systemSymbolName: "gauge.medium", accessibilityDescription: "Gauge") {
            statusItem.button?.image = icon
            statusItem.button?.title = ""
        } else {
            statusItem.button?.image = nil
            let font = NSFont.menuBarFont(ofSize: 0)
            let title = NSMutableAttributedString()
            for (index, card) in cards.enumerated() {
                if index > 0 { title.append(NSAttributedString(string: "   ", attributes: [.font: font])) }
                title.append(ProviderIcons.label(card, text: card.barText, font: font, color: .labelColor, iconTint: .labelColor, gap: " "))
            }
            statusItem.button?.attributedTitle = title
        }
        dashboard.update()
        notchDashboard.update()
        settingsWindow?.refreshStatus()
        if popover.isShown { popover.contentSize = dashboard.view.frame.size }
        if cards.count != lastRowCount {   // a service appeared or disappeared: resize the island and card
            lastRowCount = cards.count
            if islandPanel != nil { applyNotchLayout() }
        }
        if model.showNotch != lastNotchEnabled {
            lastNotchEnabled = model.showNotch
            if model.showNotch { buildNotch() } else { tearDownNotch() }
        }
        if islandPanel != nil { updateBadgeText() }
    }

    private static let perLabelWidth: CGFloat = 60   // badge width per service, to the left of the physical notch
    private static let cardGap: CGFloat = 6           // free space between the island and the card below it
    private static let cardRim: CGFloat = 8           // transparent margin so the spring can overshoot without clipping
    private var rowCount: Int { max(1, model.cards.count) }   // an empty island still shows a placeholder
    private var leftWidth: CGFloat { Self.perLabelWidth * CGFloat(rowCount) }

    /// Prefers the display that has a physical notch; otherwise the one with the menu bar.
    private var targetScreen: NSScreen? {
        NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.screens.first ?? NSScreen.main
    }
    private var hasNotchScreen: Bool { NSScreen.screens.contains { $0.safeAreaInsets.top > 0 } }
    private func notchWidth(_ screen: NSScreen) -> CGFloat {
        guard screen.safeAreaInsets.top > 0, let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea
        else { return 0 }
        return max(0, screen.frame.width - left.width - right.width)
    }

    /// The island: its right edge sits at the notch's right edge, so the labels live left of the notch.
    private func islandRect(_ screen: NSScreen) -> NSRect {
        let notch = notchWidth(screen)
        let size = notch > 0 ? NSSize(width: notch + leftWidth, height: screen.safeAreaInsets.top) : NSSize(width: 170, height: 28)
        let x = notch > 0 ? screen.frame.midX + notch / 2 - size.width : screen.frame.midX - size.width / 2
        return NSRect(x: x, y: screen.frame.maxY - size.height, width: size.width, height: size.height)
    }
    /// The card hangs below the island, separated by a small gap, under the same spot (not re-centered).
    private func cardRect(_ screen: NSScreen) -> NSRect {
        let size = Layout.cardSize(rows: rowCount)
        let island = islandRect(screen)
        var x = notchWidth(screen) > 0 ? island.minX : screen.frame.midX - size.width / 2
        x = min(max(x, screen.frame.minX + 8), screen.frame.maxX - size.width - 8)
        return NSRect(x: x, y: island.minY - Self.cardGap - size.height, width: size.width, height: size.height)
    }
    private func cardPanelFrame(_ screen: NSScreen) -> NSRect {
        let card = cardRect(screen)
        return NSRect(x: card.minX - Self.cardRim, y: card.minY - Self.cardRim,
                      width: card.width + Self.cardRim * 2, height: card.height + Self.cardRim)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .popUpMenu   // above the menu bar and other overlays
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = false
        panel.acceptsMouseMovedEvents = true
        return panel
    }

    private func buildNotch() {
        guard targetScreen != nil else { return }
        if islandPanel == nil {
            let island = makePanel()
            island.ignoresMouseEvents = true   // the island never blocks menu-bar clicks beneath it
            badge.wantsLayer = true
            badge.layer?.backgroundColor = NSColor.black.cgColor
            badge.layer?.cornerRadius = 12
            badge.layer?.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]   // bottom corners only
            island.contentView = badge
            islandPanel = island

            let card = makePanel()
            card.ignoresMouseEvents = true
            card.contentView = cardHost
            cardHost.wantsLayer = true
            let view = notchDashboard.view
            view.removeFromSuperview()
            view.translatesAutoresizingMaskIntoConstraints = false
            cardHost.addSubview(view)
            cardHeight = view.heightAnchor.constraint(equalToConstant: Layout.cardSize(rows: rowCount).height)
            NSLayoutConstraint.activate([
                view.topAnchor.constraint(equalTo: cardHost.topAnchor),
                view.centerXAnchor.constraint(equalTo: cardHost.centerXAnchor),
                view.widthAnchor.constraint(equalToConstant: Layout.cardWidth),
                cardHeight
            ])
            cardPanel = card
        }
        applyNotchLayout()
        islandPanel?.orderFrontRegardless()
    }

    private func tearDownNotch() {
        expanded = false
        islandPanel?.orderOut(nil)
        cardPanel?.orderOut(nil)
        islandPanel = nil
        cardPanel = nil
    }

    private func updateBadgeText() {
        let cards = model.cards
        let slots = max(1, cards.count)   // nothing found yet: one placeholder label
        while badgeLabels.count < slots {
            let label = makeLabel("", size: 12, weight: .medium)
            label.alignment = .center
            badge.addSubview(label)
            badgeLabels.append(label)
        }
        while badgeLabels.count > slots { badgeLabels.removeLast().removeFromSuperview() }
        if cards.isEmpty {
            badgeLabels[0].attributedStringValue = NSAttributedString(string: "Gauge", attributes: [
                .font: badgeLabels[0].font ?? NSFont.systemFont(ofSize: 12), .foregroundColor: Palette.muted])
            return
        }
        for (label, card) in zip(badgeLabels, cards) {
            label.attributedStringValue = ProviderIcons.label(card, text: card.barText, font: label.font ?? .systemFont(ofSize: 12),
                                                              color: .white, gap: " ")
        }
    }

    /// Positions both panels for the current screen and service count (no animation).
    private func applyNotchLayout() {
        guard let island = islandPanel, let card = cardPanel, let screen = targetScreen else { return }
        let rect = islandRect(screen)
        island.setFrame(rect, display: false)
        badge.frame = NSRect(origin: .zero, size: rect.size)
        updateBadgeText()
        let visible = notchWidth(screen) > 0 ? leftWidth : rect.width   // labels never sit behind the notch
        let each = max(1, visible - 8) / CGFloat(max(1, badgeLabels.count))
        for (index, label) in badgeLabels.enumerated() {
            label.frame = NSRect(x: 4 + each * CGFloat(index), y: (rect.height - 16) / 2, width: each, height: 16)
        }
        cardHeight.constant = Layout.cardSize(rows: rowCount).height
        card.setFrame(cardPanelFrame(screen), display: false)
    }

    /// Card size is scaled about its top edge so it appears to unfold downward from the island.
    private func foldedTransform(for size: CGSize) -> CATransform3D {
        let scale: CGFloat = 0.92
        let scaled = CATransform3DMakeScale(scale, scale, 1)
        return CATransform3DConcat(scaled, CATransform3DMakeTranslation(0, size.height / 2 * (1 - scale), 0))
    }

    /// Slides the card out below the island with a soft spring, or tucks it away again.
    private func setCardVisible(_ visible: Bool) {
        guard let panel = cardPanel, let layer = notchDashboard.view.layer else { return }
        notchGeneration += 1
        let generation = notchGeneration
        applyNotchLayout()
        if visible { notchDashboard.update() }
        cardHost.layoutSubtreeIfNeeded()
        let size = layer.bounds.size
        let folded = foldedTransform(for: size)
        let fromTransform = layer.presentation()?.transform ?? (visible ? folded : CATransform3DIdentity)
        let fromOpacity = layer.presentation()?.opacity ?? (visible ? 0 : 1)

        panel.ignoresMouseEvents = !visible
        if visible { panel.orderFrontRegardless() }
        layer.transform = visible ? CATransform3DIdentity : folded
        layer.opacity = visible ? 1 : 0

        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self, weak panel] in
            MainActor.assumeIsolated {
                if let self, generation == self.notchGeneration, !visible { panel?.orderOut(nil) }
            }
        }
        if visible {
            let spring = CASpringAnimation(keyPath: "transform")
            spring.fromValue = NSValue(caTransform3D: fromTransform)
            spring.toValue = NSValue(caTransform3D: CATransform3DIdentity)
            spring.mass = 1; spring.stiffness = 340; spring.damping = 24
            spring.duration = spring.settlingDuration
            layer.add(spring, forKey: "transform")
        } else {
            let move = CABasicAnimation(keyPath: "transform")
            move.fromValue = NSValue(caTransform3D: fromTransform)
            move.toValue = NSValue(caTransform3D: folded)
            move.duration = 0.16
            move.timingFunction = CAMediaTimingFunction(name: .easeIn)
            layer.add(move, forKey: "transform")
        }
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = fromOpacity
        fade.toValue = visible ? 1 : 0
        fade.duration = visible ? 0.18 : 0.14
        fade.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer.add(fade, forKey: "opacity")
        CATransaction.commit()
    }

    private func checkMousePosition() {
        guard model.showNotch, let screen = targetScreen else { return }
        let mouse = NSEvent.mouseLocation
        func inside(_ rect: NSRect) -> Bool {
            mouse.x >= rect.minX && mouse.x <= rect.maxX && mouse.y >= rect.minY && mouse.y <= rect.maxY
        }
        let island = islandRect(screen)
        var hover = inside(island)
        if expanded {
            // Keep the card open while the pointer travels from the island, across the gap, into the card.
            let card = cardRect(screen)
            let gap = NSRect(x: card.minX, y: card.maxY, width: card.width, height: max(0, island.minY - card.maxY))
            hover = hover || inside(gap) || inside(card.insetBy(dx: -6, dy: -8))
        }
        if hover != expanded {
            expanded = hover
            setCardVisible(hover)
        }
    }
}

// `Gauge --statusline` is run by Claude Code (see ClaudeLimits.swift); it must never start the app.
if CommandLine.arguments.contains("--statusline") {
    StatusLineBridge.run()
    exit(0)
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
}
