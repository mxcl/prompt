import Foundation
import HotKey

final class GlobalShortcutManager {
    static let shared = GlobalShortcutManager()

    private static let defaultsKey = "GlobalShortcutKeyCombo"
    private var hotKey: HotKey?
    private var keyDownHandler: (() -> Void)?

    private(set) var currentCombo: KeyCombo {
        didSet {
            Self.persist(combo: currentCombo)
            registerHotKeyIfPossible()
            NotificationCenter.default.post(name: .globalShortcutDidChange, object: currentCombo)
        }
    }

    static let defaultCombo = KeyCombo(key: .escape, modifiers: [.command])

    private init() {
        if let stored = Self.loadPersistedCombo() {
            currentCombo = stored
        } else {
            currentCombo = Self.defaultCombo
            Self.persist(combo: currentCombo)
        }
    }

    func register(keyDownHandler: @escaping () -> Void) {
        self.keyDownHandler = keyDownHandler
        registerHotKeyIfPossible()
    }

    func update(combo: KeyCombo) {
        guard combo.isValid else { return }
        currentCombo = combo
    }

    func resetToDefault() {
        currentCombo = Self.defaultCombo
    }

    private func registerHotKeyIfPossible() {
        hotKey?.isPaused = true
        hotKey = nil
        guard let handler = keyDownHandler else { return }
        hotKey = HotKey(keyCombo: currentCombo, keyDownHandler: handler)
    }

    private static func persist(combo: KeyCombo) {
        UserDefaults.standard.set(combo.dictionary, forKey: defaultsKey)
    }

    private static func loadPersistedCombo() -> KeyCombo? {
        guard let dictionary = UserDefaults.standard.dictionary(forKey: defaultsKey) else {
            return nil
        }
        return KeyCombo(dictionary: dictionary)
    }
}

extension Notification.Name {
    static let globalShortcutDidChange = Notification.Name("GlobalShortcutDidChange")
}
