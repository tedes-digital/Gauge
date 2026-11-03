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

    func applicationDidFinishLaunching(_ notification: Notification) {
        Self.instance = self
        NSApp.setActivationPolicy(.accessory)
        dashboard = DashboardViewController(model: model)
        notchDashboard = DashboardViewController(model: model)
        popover = NSPopover()
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 700, height: 360)
        popover.contentViewController = dashboard

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.target = self
        statusItem.button?.action = #selector(toggleMenu)
        statusItem.button?.toolTip = "AI Usage Monitor · click to open"
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

    @objc private func toggleMenu() {
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
        let cl = model.claudeSession >= 0 ? "\(model.claudeSession)%" : "—"
        let cg = model.shortestCodex.map { "\(Int($0.remainingPercent.rounded()))%" } ?? "—"
        statusItem.button?.title = "✳ \(cl)  ✦ \(model.codexStale ? "~" : "")\(cg)"
        dashboard.update()
        notchDashboard.update()
        if popover.isShown { popover.contentSize = dashboard.view.frame.size }
        if model.showNotch != lastNotchEnabled {
            lastNotchEnabled = model.showNotch
            if model.showNotch { buildNotch() } else { notchPanel?.orderOut(nil); notchPanel = nil }
        }
        if expanded { layoutNotch() }
    }

    private func buildNotch() {
        guard NSScreen.main != nil else { return }
        if notchPanel == nil {
            let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 170, height: 28),
                                styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.level = .statusBar
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            panel.hidesOnDeactivate = false
            panel.isMovableByWindowBackground = false
            notchPanel = panel
        }
        layoutNotch()
        notchPanel?.orderFrontRegardless()
    }

    private func layoutNotch() {
        guard let panel = notchPanel, let screen = NSScreen.main else { return }
        let width: CGFloat = expanded ? 720 : 170
        let height: CGFloat = expanded ? 380 : 28
        // VisibleFrame is below the menu bar; use full frame to anchor to the physical notch.
        let frame = NSRect(x: screen.frame.midX - width / 2,
                           y: screen.frame.maxY - height,
                           width: width, height: height)
        panel.setFrame(frame, display: true, animate: expanded)
        if expanded {
            let card = NSView(frame: NSRect(origin: .zero, size: frame.size))
            let view = notchDashboard.view
            view.removeFromSuperview()
            view.frame = NSRect(x: 10, y: 10, width: 700, height: 360)
            view.autoresizingMask = []
            card.addSubview(view)
            panel.contentView = card
        } else {
            let badge = NSView(frame: NSRect(origin: .zero, size: frame.size))
            badge.wantsLayer = true
            badge.layer?.backgroundColor = NSColor.black.cgColor
            badge.layer?.cornerRadius = 13
            let text = makeLabel("✳  \(model.claudeSession >= 0 ? "\(model.claudeSession)%" : "—")      ✦  \(model.shortestCodex.map { "\(Int($0.remainingPercent))%" } ?? "—")", size: 11, weight: .medium)
            text.alignment = .center
            text.frame = NSRect(x: 5, y: 6, width: width - 10, height: 16)
            badge.addSubview(text)
            panel.contentView = badge
        }
    }

    private func checkMousePosition() {
        guard model.showNotch, let screen = NSScreen.main else { return }
        let mouse = NSEvent.mouseLocation
        // Expand only when pointer approaches center top; collapse when clearly outside panel.
        let hover = abs(mouse.x - screen.frame.midX) < (expanded ? 370 : 110)
            && mouse.y > screen.frame.maxY - (expanded ? 390 : 42)
        if hover != expanded {
            expanded = hover
            notchDashboard.update()
            layoutNotch()
        }
    }
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
}
