import Cocoa
import HotKey

final class SettingsViewController: NSViewController {
    private let captureField = ShortcutCaptureTextField(frame: .zero)
    private let feedbackLabel = NSTextField(labelWithString: "")
    private let infoLabel = NSTextField(wrappingLabelWithString: "Click the field, then press your preferred shortcut while holding at least one modifier key.")
    private let resetButton = NSButton(title: "Reset to Default", target: nil, action: nil)

    private let containerStack: NSStackView = {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.edgeInsets = NSEdgeInsets(top: 24, left: 24, bottom: 24, right: 24)
        return stack
    }()

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 380, height: 200))
        setupUI()
        configureCallbacks()
        updateDisplayedShortcut()
        configureObservers()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    private func setupUI() {
        let titleLabel = NSTextField(labelWithString: "Global Shortcut")
        titleLabel.font = NSFont.systemFont(ofSize: 18, weight: .semibold)

        captureField.placeholderString = "Press shortcut"
        captureField.translatesAutoresizingMaskIntoConstraints = false
        captureField.widthAnchor.constraint(greaterThanOrEqualToConstant: 220).isActive = true
        captureField.heightAnchor.constraint(equalToConstant: 32).isActive = true
        captureField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        captureField.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)

        feedbackLabel.textColor = .secondaryLabelColor
        feedbackLabel.font = NSFont.systemFont(ofSize: 12)
        feedbackLabel.stringValue = ""

        infoLabel.textColor = .secondaryLabelColor

        resetButton.bezelStyle = .rounded

        let shortcutStack = NSStackView(views: [captureField])
        shortcutStack.orientation = .horizontal
        shortcutStack.alignment = .centerY
        shortcutStack.spacing = 0
        shortcutStack.translatesAutoresizingMaskIntoConstraints = false

        let buttonRow = NSStackView()
        buttonRow.orientation = .horizontal
        buttonRow.alignment = .centerY
        buttonRow.spacing = 8
        buttonRow.translatesAutoresizingMaskIntoConstraints = false

        let spacer = NSView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        buttonRow.addArrangedSubview(spacer)
        buttonRow.addArrangedSubview(resetButton)

        containerStack.addArrangedSubview(titleLabel)
        containerStack.addArrangedSubview(infoLabel)
        containerStack.addArrangedSubview(shortcutStack)
        containerStack.addArrangedSubview(feedbackLabel)
        containerStack.addArrangedSubview(buttonRow)

        view.addSubview(containerStack)

        NSLayoutConstraint.activate([
            containerStack.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            containerStack.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            containerStack.topAnchor.constraint(equalTo: view.topAnchor),
            containerStack.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func configureCallbacks() {
        captureField.onComboCaptured = { [weak self] combo in
            GlobalShortcutManager.shared.update(combo: combo)
            self?.feedbackLabel.stringValue = "Shortcut updated to \(combo.description)."
        }

        captureField.onInvalidCapture = { [weak self] in
            self?.feedbackLabel.stringValue = "Please include ⌘, ⌥, ⌃, or ⇧."
        }

        resetButton.target = self
        resetButton.action = #selector(resetButtonPressed)
    }

    private func configureObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleShortcutChange(_:)),
            name: .globalShortcutDidChange,
            object: nil
        )
    }

    @objc private func handleShortcutChange(_ notification: Notification) {
        updateDisplayedShortcut()
        feedbackLabel.stringValue = "Shortcut updated to \(captureField.stringValue)."
    }

    private func updateDisplayedShortcut() {
        let combo = GlobalShortcutManager.shared.currentCombo
        captureField.stringValue = combo.description
    }

    @objc private func resetButtonPressed() {
        GlobalShortcutManager.shared.resetToDefault()
        feedbackLabel.stringValue = "Shortcut reset to default."
    }
}
