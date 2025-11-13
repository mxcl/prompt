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

        setupMainMenu()

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

        let preferencesItem = NSMenuItem(title: "Preferences…", action: #selector(openSettings), keyEquivalent: ",")
        preferencesItem.target = self
        menu.addItem(preferencesItem)

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

    private func setupMainMenu() {
        let mainMenu = NSMenu(title: "MainMenu")

        // App submenu (kept minimal but avoids empty menu warnings)
        let appMenuItem = NSMenuItem(title: "teaRUN", action: nil, keyEquivalent: "")
        let appMenu = NSMenu()
        appMenu.addItem(
            withTitle: "Quit teaRUN",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        // Edit menu supplying standard responder chain actions for keyboard shortcuts
        let editMenuItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        editMenuItem.submenu = NSMenu(title: "Edit")
        if let editMenu = editMenuItem.submenu {
            let undoItem = NSMenuItem(
                title: "Undo",
                action: #selector(UndoManager.undo),
                keyEquivalent: "z"
            )
            undoItem.target = nil
            editMenu.addItem(undoItem)

            let redoItem = NSMenuItem(
                title: "Redo",
                action: #selector(UndoManager.redo),
                keyEquivalent: "Z"
            )
            redoItem.target = nil
            editMenu.addItem(redoItem)

            editMenu.addItem(NSMenuItem.separator())

            let cutItem = NSMenuItem(
                title: "Cut",
                action: #selector(NSText.cut(_:)),
                keyEquivalent: "x"
            )
            cutItem.target = nil
            editMenu.addItem(cutItem)

            let copyItem = NSMenuItem(
                title: "Copy",
                action: #selector(NSText.copy(_:)),
                keyEquivalent: "c"
            )
            copyItem.target = nil
            editMenu.addItem(copyItem)

            let pasteItem = NSMenuItem(
                title: "Paste",
                action: #selector(NSText.paste(_:)),
                keyEquivalent: "v"
            )
            pasteItem.target = nil
            editMenu.addItem(pasteItem)

            let selectAllItem = NSMenuItem(
                title: "Select All",
                action: #selector(NSText.selectAll(_:)),
                keyEquivalent: "a"
            )
            selectAllItem.target = nil
            editMenu.addItem(selectAllItem)
        }
        mainMenu.addItem(editMenuItem)

        NSApp.mainMenu = mainMenu
    }
}
