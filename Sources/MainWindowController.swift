import Cocoa

class MainWindowController: NSWindowController {

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 400),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
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

        window.title = "teaBASEv2"
        window.center()
        window.contentViewController = MainViewController()
        window.makeKeyAndOrderFront(nil)
        window.level = .normal

        // Ensure the app is active
        NSApp.activate(ignoringOtherApps: true)
    }
}
