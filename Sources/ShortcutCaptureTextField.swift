import Cocoa
import HotKey

final class ShortcutCaptureTextField: NSTextField {
    var onComboCaptured: ((KeyCombo) -> Void)?
    var onInvalidCapture: (() -> Void)?

    private let allowedModifiers: NSEvent.ModifierFlags = [.command, .option, .control, .shift]

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    override var acceptsFirstResponder: Bool {
        return true
    }

    override func becomeFirstResponder() -> Bool {
        let became = super.becomeFirstResponder()
        if became {
            currentEditor()?.selectedRange = NSRange(location: stringValue.count, length: 0)
        }
        return became
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
    }

    override func keyDown(with event: NSEvent) {
        guard let combo = combo(from: event) else {
            onInvalidCapture?()
            NSSound.beep()
            return
        }

        stringValue = combo.description
        onComboCaptured?(combo)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        keyDown(with: event)
        return true
    }

    private func configure() {
        isEditable = false
        isBordered = true
        isBezeled = true
        focusRingType = .default
        font = NSFont.monospacedSystemFont(ofSize: 15, weight: .regular)
        alignment = .center
        stringValue = ""
        drawsBackground = true
        backgroundColor = NSColor.windowBackgroundColor
    }

    private func combo(from event: NSEvent) -> KeyCombo? {
        // Ignore events that originate from modifier key changes only
        guard event.type == .keyDown else { return nil }

        // Extract supported modifiers
        let modifiers = event.modifierFlags.intersection(allowedModifiers)

        // Require at least one modifier for a global shortcut to reduce conflicts
        guard !modifiers.isEmpty else {
            return nil
        }

        let carbonKeyCode = UInt32(event.keyCode)

        guard let key = Key(carbonKeyCode: carbonKeyCode) else {
            return nil
        }

        return KeyCombo(key: key, modifiers: modifiers)
    }
}
