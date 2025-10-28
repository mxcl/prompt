import Cocoa
import HotKey

final class SettingsViewController: NSViewController {
    private let captureField = ShortcutCaptureTextField(frame: .zero)
    private let feedbackLabel = NSTextField(labelWithString: "")
    private let infoLabel = NSTextField(labelWithString: "Click the field, then press your preferred shortcut using modifier keys.")
    private let resetButton = NSButton(title: "Reset to Default", target: nil, action: nil)

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 160))
        setupUI()
        configureCallbacks()
        updateDisplayedShortcut()
        configureObservers()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    private func setupUI() {
        view.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = NSTextField(labelWithString: "Global Shortcut")
        titleLabel.font = NSFont.systemFont(ofSize: 18, weight: .semibold)

        captureField.translatesAutoresizingMaskIntoConstraints = false
        captureField.placeholderString = "Press shortcut"

        feedbackLabel.translatesAutoresizingMaskIntoConstraints = false
        feedbackLabel.textColor = .secondaryLabelColor

        infoLabel.translatesAutoresizingMaskIntoConstraints = false
        infoLabel.textColor = .secondaryLabelColor
        infoLabel.lineBreakMode = .byWordWrapping
        infoLabel.maximumNumberOfLines = 0

        resetButton.translatesAutoresizingMaskIntoConstraints = false
        resetButton.target = self
        resetButton.action = #selector(resetButtonPressed)

        view.addSubview(titleLabel)
        view.addSubview(infoLabel)
        view.addSubview(captureField)
        view.addSubview(feedbackLabel)
        view.addSubview(resetButton)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: view.topAnchor, constant: 20),
            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),

            infoLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
            infoLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            infoLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),

            captureField.topAnchor.constraint(equalTo: infoLabel.bottomAnchor, constant: 16),
            captureField.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            captureField.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            captureField.heightAnchor.constraint(equalToConstant: 32),

            feedbackLabel.topAnchor.constraint(equalTo: captureField.bottomAnchor, constant: 8),
            feedbackLabel.leadingAnchor.constraint(equalTo: captureField.leadingAnchor),
            feedbackLabel.trailingAnchor.constraint(equalTo: captureField.trailingAnchor),

            resetButton.topAnchor.constraint(equalTo: feedbackLabel.bottomAnchor, constant: 16),
            resetButton.leadingAnchor.constraint(equalTo: captureField.leadingAnchor),
            resetButton.bottomAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor, constant: -20)
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
