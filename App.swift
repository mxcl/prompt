import Cocoa
import HotKey

class AppDelegate: NSObject, NSApplicationDelegate {
    var windowController: MainWindowController?
    var hotKey: HotKey?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenu()
        setupApplication()
        setupGlobalShortcut()
        print(Provider().json)
        
                // Debug Gmail search after a delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            debugSearchGmail()
        }
        
        // Debug Chrome Apps directory search
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
            debugSearchGmailByPath()
        }
        
        // Debug exact Gmail search
        DispatchQueue.main.asyncAfter(deadline: .now() + 6.0) {
            // debugSearchExactGmail()
            print("=== DEBUG: Searching for exact Gmail.app ===")
            
            let debugQuery = NSMetadataQuery()
            debugQuery.searchScopes = [NSMetadataQueryUserHomeScope, NSMetadataQueryLocalComputerScope]
            
            let predicate = NSPredicate(format: "kMDItemDisplayName == 'Gmail'")
            debugQuery.predicate = predicate
            
            var debugObserver: Any?
            debugObserver = NotificationCenter.default.addObserver(
                forName: .NSMetadataQueryDidFinishGathering,
                object: debugQuery,
                queue: OperationQueue()
            ) { notification in
                
                guard let query = notification.object as? NSMetadataQuery else { return }
                query.disableUpdates()
                
                print("DEBUG: Found \(query.resultCount) items with exact name 'Gmail'")
                
                for (index, item) in (query.results as! [NSMetadataItem]).enumerated() {
                    let displayName = item.value(forAttribute: kMDItemDisplayName as String) as? String ?? "nil"
                    let path = item.value(forAttribute: kMDItemPath as String) as? String ?? "nil"
                    let kind = item.value(forAttribute: kMDItemKind as String) as? String ?? "nil"
                    let contentType = item.value(forAttribute: kMDItemContentType as String) as? String ?? "nil"
                    let bundleId = item.value(forAttribute: kMDItemCFBundleIdentifier as String) as? String ?? "nil"
                    
                    print("DEBUG Item \(index):")
                    print("  Display Name: \(displayName)")
                    print("  Path: \(path)")
                    print("  Kind: \(kind)")
                    print("  Content Type: \(contentType)")
                    print("  Bundle ID: \(bundleId)")
                    print("  ---")
                }
                
                if let observer = debugObserver {
                    NotificationCenter.default.removeObserver(observer)
                }
                debugQuery.stop()
            }
            
            debugQuery.start()
        }
        
        // Debug direct path search
        DispatchQueue.main.asyncAfter(deadline: .now() + 8.0) {
            print("=== DEBUG: Searching for specific Gmail app path ===")
            
            let debugQuery = NSMetadataQuery()
            debugQuery.searchScopes = [NSMetadataQueryUserHomeScope, NSMetadataQueryLocalComputerScope]
            
            let predicate = NSPredicate(format: "kMDItemPath == %@", "/Users/mxcl/Applications/Chrome Apps.localized/Gmail.app")
            debugQuery.predicate = predicate
            
            var debugObserver: Any?
            debugObserver = NotificationCenter.default.addObserver(
                forName: .NSMetadataQueryDidFinishGathering,
                object: debugQuery,
                queue: OperationQueue()
            ) { notification in
                
                guard let query = notification.object as? NSMetadataQuery else { return }
                query.disableUpdates()
                
                print("DEBUG: Found \(query.resultCount) items at exact Gmail path")
                
                for (index, item) in (query.results as! [NSMetadataItem]).enumerated() {
                    let displayName = item.value(forAttribute: kMDItemDisplayName as String) as? String ?? "nil"
                    let path = item.value(forAttribute: kMDItemPath as String) as? String ?? "nil"
                    let kind = item.value(forAttribute: kMDItemKind as String) as? String ?? "nil"
                    let contentType = item.value(forAttribute: kMDItemContentType as String) as? String ?? "nil"
                    let bundleId = item.value(forAttribute: kMDItemCFBundleIdentifier as String) as? String ?? "nil"
                    
                    print("DEBUG Item \(index):")
                    print("  Display Name: \(displayName)")
                    print("  Path: \(path)")
                    print("  Kind: \(kind)")
                    print("  Content Type: \(contentType)")
                    print("  Bundle ID: \(bundleId)")
                    print("  ---")
                }
                
                if let observer = debugObserver {
                    NotificationCenter.default.removeObserver(observer)
                }
                debugQuery.stop()
            }
            
            debugQuery.start()
        }
    }

    private func setupApplication() {
        NSApp.setActivationPolicy(.regular)

        windowController = MainWindowController()
        windowController?.showWindow(self)
    }

    private func setupGlobalShortcut() {
        // Create hotkey for Cmd+` (backtick)
        hotKey = HotKey(key: .grave, modifiers: [.command])
        hotKey?.keyDownHandler = { [weak self] in
            print("Cmd+` hotkey triggered! Toggling window...")
            DispatchQueue.main.async {
                self?.toggleWindow()
            }
        }
        
        if hotKey != nil {
            print("Successfully registered global hotkey: Cmd+`")
        } else {
            print("Failed to register global hotkey")
        }
    }
    
    @objc private func toggleWindow() {
        print("toggleWindow() called")
        guard let windowController = windowController else { 
            print("No windowController")
            return 
        }

        if let window = windowController.window {
            print("Window isVisible: \(window.isVisible), NSApp.isActive: \(NSApp.isActive), isKeyWindow: \(window.isKeyWindow)")
            if window.isVisible && NSApp.isActive && window.isKeyWindow {
                // Window is visible, app is active, and window has focus - hide it
                print("Hiding window")
                window.orderOut(nil)
            } else {
                // Show and activate the window
                print("Showing and activating window")
                NSApp.activate(ignoringOtherApps: true)
                windowController.showWindow(nil)
                window.makeKeyAndOrderFront(nil)
            }
        } else {
            print("No window")
        }
    }

    private func setupMenu() {
        let mainMenu = NSMenu()

        // App Menu
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()

        // About menu item
        let aboutItem = NSMenuItem(title: "About Prompt", action: #selector(showAbout), keyEquivalent: "")
        aboutItem.target = self
        appMenu.addItem(aboutItem)

        appMenu.addItem(NSMenuItem.separator())

        // Hide menu item
        let hideItem = NSMenuItem(title: "Hide Prompt", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(hideItem)

        // Hide Others menu item
        let hideOthersItem = NSMenuItem(title: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthersItem.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(hideOthersItem)

        // Show All menu item
        let showAllItem = NSMenuItem(title: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(showAllItem)

        appMenu.addItem(NSMenuItem.separator())

        // Quit menu item
        let quitItem = NSMenuItem(title: "Quit Prompt", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenu.addItem(quitItem)

        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        // Edit Menu
        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")

        let undoItem = NSMenuItem(title: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(undoItem)

        let redoItem = NSMenuItem(title: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(redoItem)

        editMenu.addItem(NSMenuItem.separator())

        let cutItem = NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(cutItem)

        let copyItem = NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(copyItem)

        let pasteItem = NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(pasteItem)

        let selectAllItem = NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenu.addItem(selectAllItem)

        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        // Window Menu
        let windowMenuItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Window")

        let minimizeItem = NSMenuItem(title: "Minimize", action: #selector(NSWindow.miniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(minimizeItem)

        let closeItem = NSMenuItem(title: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowMenu.addItem(closeItem)

        windowMenuItem.submenu = windowMenu
        mainMenu.addItem(windowMenuItem)

        NSApp.mainMenu = mainMenu
    }

    @objc private func showAbout() {
        NSApp.orderFrontStandardAboutPanel(nil)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            // No visible windows, so show our window
            windowController?.showWindow(nil)
        }
        return true
    }

    deinit {
        hotKey = nil // This will automatically unregister the hotkey
    }
}
