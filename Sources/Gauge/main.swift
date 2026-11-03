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
    private var notchPanel: NSPanel?
    private var settingsWindow: SettingsWindowController?
    private var mouseMonitor: Any?
    private var expanded = false
    private var lastNotchEnabled = true
    private let badge = NSView()
    private let badgeLabel = makeLabel("", size: 11, weight: .medium)

    func applicationDidFinishLaunching(_ notification: Notification) {
        Self.instance = self
        NSApp.setActivationPolicy(.accessory)
        dashboard = DashboardViewController(model: model)
        notchDashboard = DashboardViewController(model: model)
        popover = NSPopover()
        popover.behavior = .transient
        popover.contentSize = Layout.card
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
        updateUI()
        model.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let mouseMonitor { NSEvent.removeMonitor(mouseMonitor) }
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
        let cl = model.claudeBarText
        let cg = model.shortestCodex.map { "\(Int($0.remainingPercent.rounded()))%" } ?? "—"
        statusItem.button?.title = "✳ \(cl)  ✦ \(model.codexStale ? "~" : "")\(cg)"
        dashboard.update()
        notchDashboard.update()
        if popover.isShown { popover.contentSize = dashboard.view.frame.size }
        if model.showNotch != lastNotchEnabled {
            lastNotchEnabled = model.showNotch
            if model.showNotch { buildNotch() } else { notchPanel?.orderOut(nil); notchPanel = nil }
        }
        if !expanded, notchPanel != nil { updateBadgeText() }
    }

    private static let badgeSize = NSSize(width: 170, height: 28)
    private static let inset: CGFloat = 10

    private func buildNotch() {
        guard NSScreen.main != nil else { return }
        if notchPanel == nil {
            let panel = NSPanel(contentRect: NSRect(origin: .zero, size: Self.badgeSize),
                                styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.level = .statusBar
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            panel.hidesOnDeactivate = false
            panel.isMovableByWindowBackground = false
            notchPanel = panel

            badge.wantsLayer = true
            badge.layer?.backgroundColor = NSColor.black.cgColor
            badge.layer?.cornerRadius = 13
            badgeLabel.alignment = .center
            badgeLabel.frame = NSRect(x: 5, y: 6, width: Self.badgeSize.width - 10, height: 16)
            badge.addSubview(badgeLabel)
        }
        layoutNotch()
        notchPanel?.orderFrontRegardless()
    }

    private func updateBadgeText() {
        let claude = model.claudeBarText
        let codex = model.shortestCodex.map { "\(Int($0.remainingPercent.rounded()))%" } ?? "—"
        badgeLabel.stringValue = "✳  \(claude)      ✦  \(codex)"
    }

    private var notchGeneration = 0

    private func notchFrame(expanded: Bool, screen: NSScreen) -> NSRect {
        let size = expanded
            ? NSSize(width: Layout.card.width + Self.inset * 2, height: Layout.card.height + Self.inset)
            : Self.badgeSize
        // Use the full frame (not visibleFrame) to anchor to the physical notch.
        return NSRect(x: screen.frame.midX - size.width / 2, y: screen.frame.maxY - size.height,
                      width: size.width, height: size.height)
    }

    private func showBadge(in panel: NSPanel) {
        updateBadgeText()
        badge.frame = NSRect(origin: .zero, size: Self.badgeSize)
        panel.contentView = badge
    }

    /// Sets the notch panel to the current state (no animation).
    private func layoutNotch() {
        guard let panel = notchPanel, let screen = NSScreen.main else { return }
        notchGeneration += 1
        panel.setFrame(notchFrame(expanded: expanded, screen: screen), display: true)
        if expanded { panel.contentView = makeCardHost(size: panel.frame.size) }
        else { showBadge(in: panel) }
    }

    private func makeCardHost(size: NSSize) -> NSView {
        let host = NSView(frame: NSRect(origin: .zero, size: size))
        let view = notchDashboard.view
        view.removeFromSuperview()
        view.frame = NSRect(x: Self.inset, y: Self.inset, width: Layout.card.width, height: Layout.card.height)
        view.autoresizingMask = [.minYMargin]   // stay pinned to the top while the panel resizes
        host.addSubview(view)
        host.wantsLayer = true
        return host
    }

    /// Smoothly grows the badge into the card, or shrinks the card back into the badge.
    private func animateNotch() {
        guard let panel = notchPanel, let screen = NSScreen.main else { return }
        notchGeneration += 1
        let generation = notchGeneration
        let target = notchFrame(expanded: expanded, screen: screen)
        if expanded {
            let host = makeCardHost(size: panel.frame.size)
            host.alphaValue = 0
            panel.contentView = host
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.24
                ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.3, 1)
                panel.animator().setFrame(target, display: true)
                host.animator().alphaValue = 1
            }
        } else {
            let host = panel.contentView
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.18
                ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
                panel.animator().setFrame(target, display: true)
                host?.animator().alphaValue = 0
            }, completionHandler: { [weak self] in
                MainActor.assumeIsolated {
                    guard let self, generation == self.notchGeneration, !self.expanded else { return }
                    self.badge.alphaValue = 0
                    self.showBadge(in: panel)
                    NSAnimationContext.runAnimationGroup { $0.duration = 0.12; self.badge.animator().alphaValue = 1 }
                }
            })
        }
    }

    private func checkMousePosition() {
        guard model.showNotch, let screen = NSScreen.main else { return }
        let mouse = NSEvent.mouseLocation
        let top = screen.frame.maxY
        // Expand when the pointer reaches the badge; collapse once it leaves the card area.
        let hover = expanded
            ? abs(mouse.x - screen.frame.midX) < Layout.card.width / 2 + Self.inset
                && mouse.y > top - Layout.card.height - Self.inset - 8
            : abs(mouse.x - screen.frame.midX) < Self.badgeSize.width / 2
                && mouse.y > top - Self.badgeSize.height
        if hover != expanded {
            expanded = hover
            notchDashboard.update()
            animateNotch()
        }
    }
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
}
