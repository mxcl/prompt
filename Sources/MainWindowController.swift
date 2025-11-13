import Cocoa

class MainWindowController: NSWindowController {

    private var escapeKeyMonitor: Any?

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 400),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        self.init(window: window)
        setupWindow()
    }

    override init(window: NSWindow?) {
        super.init(window: window)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupWindow() {
        guard let window = window else { return }

        window.title = "teaRUN"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.isMovableByWindowBackground = true
        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        window.center()
        window.contentViewController = MainViewController()
        window.makeKeyAndOrderFront(nil)
        window.level = .normal

        // Ensure the app is active
        NSApp.activate(ignoringOtherApps: true)

        // Hide the window when escape is pressed while it is focused
        escapeKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53, // Escape key
                  let self,
                  let window = self.window,
                  (event.window == window || window.isKeyWindow) else {
                return event
            }

            window.orderOut(nil)
            return nil
        }
    }

    deinit {
        if let monitor = escapeKeyMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }
}
