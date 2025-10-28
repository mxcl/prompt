import Cocoa
import HotKey
import ApplicationServices

class AppDelegate: NSObject, NSApplicationDelegate {
    var windowController: MainWindowController?
    var hotKey: HotKey?
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    // No custom event tap; rely on HotKey

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenu()
        setupApplication()
        setupGlobalShortcut()
        // Initialize cask data loading
        _ = CaskProvider.shared.searchCasks(query: "").count
    }

    private func setupApplication() {
        NSApp.setActivationPolicy(.regular)

        windowController = MainWindowController()
        windowController?.showWindow(self)
    }

    private func setupGlobalShortcut() {
        // Implement Fn + ` using a CGEvent tap (Fn not exposed via standard hotkey APIs)
        // Grave keyCode = 50. We check for the secondaryFn flag and absence of command/option/control to reduce conflicts.
        let mask = (1 << CGEventType.keyDown.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard type == .keyDown else { return Unmanaged.passUnretained(event) }
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
            if keyCode == 50 { // grave
                let flags = event.flags
                let rawFlags = flags.rawValue
                let secondaryFnMask: UInt64 = 0x800000 // 1 << 23
                let hasFnBit = (rawFlags & secondaryFnMask) != 0
                var hasFn = hasFnBit
                if let cocoaEvent = NSEvent(cgEvent: event) { // more reliable for Fn
                    if cocoaEvent.modifierFlags.contains(.function) { hasFn = true }
                }
                let hasOther = flags.contains(.maskCommand) || flags.contains(.maskAlternate) || flags.contains(.maskControl) || flags.contains(.maskShift)
#if DEBUG
                if hasFnBit || hasFn { print("[FnGrave] keyDown rawFlags=0x\(String(rawFlags, radix:16)) hasFnBit=\(hasFnBit) hasFn=\(hasFn) hasOther=\(hasOther)") }
#endif
                if hasFn && !hasOther {
                    if let ref = refcon {
                        let delegate = Unmanaged<AppDelegate>.fromOpaque(ref).takeUnretainedValue()
                        DispatchQueue.main.async { delegate.toggleWindow() }
                        return nil // swallow
                    }
                }
            }
            return Unmanaged.passUnretained(event)
        }
        let refcon = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        if let tap = CGEvent.tapCreate(tap: .cgSessionEventTap,
                                       place: .headInsertEventTap,
                                       options: .defaultTap,
                                       eventsOfInterest: CGEventMask(mask),
                                       callback: callback,
                                       userInfo: refcon) {
            eventTap = tap
            runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
            if let src = runLoopSource {
                CFRunLoopAddSource(CFRunLoopGetCurrent(), src, .commonModes)
                CGEvent.tapEnable(tap: tap, enable: true)
            }
        } else {
            // Fallback (if tap fails): keep previous Command+Option+`
            hotKey = HotKey(key: .grave, modifiers: [.command, .option])
            hotKey?.keyDownHandler = { [weak self] in self?.toggleWindow() }
        }
    }

    @objc private func toggleWindow() {
        guard let windowController = windowController else {
            return
        }

        if let window = windowController.window {
            if window.isVisible && NSApp.isActive && window.isKeyWindow {
                // Window is visible, app is active, and window has focus - hide it
                window.orderOut(nil)
            } else {
                // Show and activate the window
                NSApp.activate(ignoringOtherApps: true)
                windowController.showWindow(nil)
                window.makeKeyAndOrderFront(nil)
            }
        }
    }

    private func setupMenu() {
        let mainMenu = NSMenu()

        // App Menu
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()

        // About menu item
        let aboutItem = NSMenuItem(title: "About teaBASEv2", action: #selector(showAbout), keyEquivalent: "")
        aboutItem.target = self
        appMenu.addItem(aboutItem)

        appMenu.addItem(NSMenuItem.separator())

        // Hide menu item
        let hideItem = NSMenuItem(title: "Hide teaBASEv2", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
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
        let quitItem = NSMenuItem(title: "Quit teaBASEv2", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
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
        hotKey = nil
        if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let src = runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetCurrent(), src, .commonModes) }
    }
}
