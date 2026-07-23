import AppKit
import SwiftUI
import ServiceManagement

// MARK: - App entry

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)   // menu-bar only, no Dock icon
app.run()

// MARK: - Delegate: status item + popover

final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    var statusItem: NSStatusItem!
    let popover = NSPopover()
    let store = DashStore()
    private var outsideClickMonitor: Any?
    private var refreshTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        enforceSingleInstance()   // quit any older copy so only one bag icon exists
        enableLaunchAtLoginByDefault()   // opt-in once, on first run
        installEditMenu()   // enables ⌘X/⌘C/⌘V/⌘A/⌘Z in text fields
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "chevron.left.forwardslash.chevron.right", accessibilityDescription: "Mergeline")
            button.image?.isTemplate = true
            button.action = #selector(togglePopover(_:))
            button.target = self
        }

        popover.behavior = .applicationDefined   // we control closing via the outside-click monitor
        popover.animates = true
        // Hide the popover arrow/beak so it drops flush like a native menu-bar panel.
        popover.setValue(true, forKey: "shouldHideAnchor")
        let host = NSHostingController(rootView: ContentView(store: store))
        host.sizingOptions = [.preferredContentSize]   // popover auto-sizes to SwiftUI content (no scroll)
        popover.contentViewController = host
        popover.delegate = self

        store.refresh()   // warm the cache in the background at launch

        // Keep data fresh in the background so the popover is already loaded when
        // opened (no on-open wait). Fires whether or not the popover is showing;
        // `refresh()` no-ops if one is already running.
        let timer = Timer(timeInterval: 60, repeats: true) { [weak self] _ in
            self?.store.refresh()
        }
        timer.tolerance = 15   // let macOS coalesce for battery efficiency
        RunLoop.main.add(timer, forMode: .common)
        refreshTimer = timer
    }

    /// Menu-bar (accessory) apps have no menu bar, so paste/copy shortcuts aren't
    /// routed to the focused text field. Install a minimal Edit menu to fix that.
    private func installEditMenu() {
        let mainMenu = NSMenu()
        let editItem = NSMenuItem()
        mainMenu.addItem(editItem)
        let editMenu = NSMenu(title: "Edit")
        editItem.submenu = editMenu
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: Selector(("cut:")), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: Selector(("copy:")), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: Selector(("paste:")), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: Selector(("selectAll:")), keyEquivalent: "a")
        NSApp.mainMenu = mainMenu
    }

    /// Terminate any other running instance of this app (newest launch wins),
    /// so repeated opens / rebuilds don't stack multiple menu-bar icons.
    private func enforceSingleInstance() {
        let me = NSRunningApplication.current
        let others = NSWorkspace.shared.runningApplications.filter {
            $0.bundleIdentifier == me.bundleIdentifier && $0.processIdentifier != me.processIdentifier
        }
        others.forEach { $0.forceTerminate() }
    }

    /// Always launch at login: register on every launch if not already enabled.
    private func enableLaunchAtLoginByDefault() {
        guard SMAppService.mainApp.status != .enabled else { return }
        do { try SMAppService.mainApp.register() }
        catch { NSLog("launch-at-login register failed: \(error)") }
    }

    @objc func togglePopover(_ sender: Any?) {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            store.refresh()
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
            // Close when the user clicks anywhere OUTSIDE this app (another app,
            // the desktop, a different menu-bar icon). Global monitors only fire
            // for out-of-process events, so clicks inside the popover are unaffected.
            outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(
                matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
                    self?.popover.performClose(nil)
            }
        }
    }

    func popoverDidClose(_ notification: Notification) {
        if let m = outsideClickMonitor { NSEvent.removeMonitor(m); outsideClickMonitor = nil }
    }
}
