import Cocoa

class AppDelegate: NSObject, NSApplicationDelegate {
    var windowController: MainWindowController?
    private var settingsWindowController: SettingsWindowController?
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        setupApplication()
        setupGlobalShortcut()
        // Initialize cask data loading
        _ = CaskStore.shared.casks.count
    }

    private func setupApplication() {
        NSApp.setActivationPolicy(.accessory)

        windowController = MainWindowController()
    }

    private func setupGlobalShortcut() {
        GlobalShortcutManager.shared.register { [weak self] in
            self?.toggleWindow()
        }
    }

    @objc private func toggleWindow() {
        guard let window = windowController?.window else {
            showMainWindow()
            return
        }

        if window.isVisible && NSApp.isActive && window.isKeyWindow {
            hideMainWindow()
        } else {
            showMainWindow()
        }
    }

    private func setupStatusItem() {
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        self.statusItem = statusItem

        if let button = statusItem.button {
            if let image = NSImage(systemSymbolName: "cup.and.saucer.fill", accessibilityDescription: "teaBASE") {
                image.isTemplate = true
                button.image = image
            } else {
                button.title = "tea"
            }
        }

        let menu = NSMenu()

        let openItem = NSMenuItem(title: "Open Window", action: #selector(openWindowFromStatusItem), keyEquivalent: "")
        openItem.target = self
        menu.addItem(openItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quitItem.target = NSApp
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    @objc private func openWindowFromStatusItem() {
        showMainWindow()
    }

    private func showMainWindow() {
        guard let windowController = windowController else {
            return
        }

        NSApp.activate(ignoringOtherApps: true)
        windowController.showWindow(nil)
        windowController.window?.makeKeyAndOrderFront(nil)
    }

    private func hideMainWindow() {
        windowController?.window?.orderOut(nil)
    }

    @objc private func openSettings() {
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController()
        }
        settingsWindowController?.showWindow(nil)
        settingsWindowController?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            showMainWindow()
        }
        return true
    }
}
