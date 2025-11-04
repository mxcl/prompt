import Cocoa

private final class PillTagView: NSView {
    private let label: NSTextField
    private let horizontalPadding: CGFloat = 4
    private let verticalPadding: CGFloat = 3
    private let text: String
    private let letterSpacing: CGFloat = 1.05

    init(text: String) {
        self.text = text
        label = NSTextField(labelWithString: "")
        super.init(frame: .zero)
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false

        label.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize - 4, weight: .medium)
        label.textColor = NSColor.white.withAlphaComponent(0.7)
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        applyAttributedText()

        addSubview(label)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: horizontalPadding),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -horizontalPadding),
            label.topAnchor.constraint(equalTo: topAnchor, constant: verticalPadding),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -verticalPadding)
        ])

        setContentHuggingPriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .horizontal)
    }

    required init?(coder: NSCoder) {
        return nil
    }

    override var intrinsicContentSize: NSSize {
        let labelSize = label.intrinsicContentSize
        return NSSize(width: labelSize.width + horizontalPadding * 2,
                      height: labelSize.height + verticalPadding * 2)
    }

    override func layout() {
        super.layout()
        layer?.cornerRadius = min(5, bounds.height / 2)
        layer?.backgroundColor = NSColor.white.withAlphaComponent(0.18).cgColor
    }

    private func applyAttributedText() {
        let uppercase = text.uppercased()
        let attributes: [NSAttributedString.Key: Any] = [
            .font: label.font as Any,
            .foregroundColor: label.textColor ?? NSColor.white,
            .kern: letterSpacing
        ]
        label.attributedStringValue = NSAttributedString(string: uppercase, attributes: attributes)
    }
}

private final class KeycapLabel: NSView {
    private let label: NSTextField
    private let horizontalPadding: CGFloat = 7
    private let verticalPadding: CGFloat = 3

    init(text: String) {
        label = NSTextField(labelWithString: text)
        super.init(frame: .zero)
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false

        label.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        label.textColor = NSColor.white.withAlphaComponent(0.8)
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false

        addSubview(label)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: horizontalPadding),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -horizontalPadding),
            label.topAnchor.constraint(equalTo: topAnchor, constant: verticalPadding),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -verticalPadding)
        ])

        setContentHuggingPriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .horizontal)
    }

    required init?(coder: NSCoder) {
        return nil
    }

    override var intrinsicContentSize: NSSize {
        let labelSize = label.intrinsicContentSize
        return NSSize(width: labelSize.width + horizontalPadding * 2,
                      height: labelSize.height + verticalPadding * 2)
    }

    override func layout() {
        super.layout()
        layer?.cornerRadius = min(6, bounds.height / 2)
        layer?.backgroundColor = NSColor.white.withAlphaComponent(0.14).cgColor
        layer?.borderColor = NSColor.white.withAlphaComponent(0.2).cgColor
        layer?.borderWidth = 0.75
    }
}

private final class ActionHintPillView: NSView {
    private let label: NSTextField
    private let horizontalPadding: CGFloat = 10
    private let verticalPadding: CGFloat = 4
    private let spacing: String = "  "

    init(keyGlyph: String, text: String) {
        label = NSTextField(labelWithString: "")
        super.init(frame: .zero)
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false

        label.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize, weight: .medium)
        label.textColor = NSColor.white.withAlphaComponent(0.85)
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false

        addSubview(label)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: horizontalPadding),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -horizontalPadding),
            label.topAnchor.constraint(equalTo: topAnchor, constant: verticalPadding),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -verticalPadding)
        ])

        setContentHuggingPriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .horizontal)

        applyText(keyGlyph: keyGlyph, text: text)
    }

    required init?(coder: NSCoder) {
        return nil
    }

    private func applyText(keyGlyph: String, text: String) {
        let attributed = NSMutableAttributedString()
        let keyAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize, weight: .semibold),
            .foregroundColor: NSColor.white
        ]
        attributed.append(NSAttributedString(string: keyGlyph, attributes: keyAttributes))

        if !text.isEmpty {
            let textAttributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize, weight: .medium),
                .foregroundColor: NSColor.white.withAlphaComponent(0.85)
            ]
            let combinedText = spacing + text
            attributed.append(NSAttributedString(string: combinedText, attributes: textAttributes))
        }

        label.attributedStringValue = attributed
    }

    override var intrinsicContentSize: NSSize {
        let labelSize = label.intrinsicContentSize
        return NSSize(width: labelSize.width + horizontalPadding * 2,
                      height: labelSize.height + verticalPadding * 2)
    }

    override func layout() {
        super.layout()
        layer?.cornerRadius = min(6, bounds.height / 2)
        layer?.backgroundColor = NSColor.white.withAlphaComponent(0.14).cgColor
        layer?.borderColor = NSColor.white.withAlphaComponent(0.2).cgColor
        layer?.borderWidth = 0.75
    }
}

final class SearchResultCellView: NSTableCellView {
    struct ActionHint {
        let keyGlyph: String
        let text: String
    }

    static let reuseIdentifier = NSUserInterfaceItemIdentifier("SearchResultCell")

    let titleField = VibrantTextField()
    let descField = VibrantTextField()
    private let actionHintStack = NSStackView()
    private let actionHintsContentStack = NSStackView()
    private let titleStack = NSStackView()
    private let recentTagView = PillTagView(text: "recent")
    private let commandMenuHintView = KeycapLabel(text: "→")

    private var titleTrailingToHint: NSLayoutConstraint!
    private var descTrailingToHint: NSLayoutConstraint!
    private var titleTrailingToEdge: NSLayoutConstraint!
    private var descTrailingToEdge: NSLayoutConstraint!
    private var hintVisibilityConstraints: [NSLayoutConstraint] = []
    private var hintHiddenConstraints: [NSLayoutConstraint] = []
    private let baseTitleFont = NSFont.systemFont(ofSize: NSFont.systemFontSize)
    private let baseDescFont = NSFont.systemFont(ofSize: 13)
    private lazy var historyTitleFont: NSFont = baseTitleFont
    private lazy var historyDescFont: NSFont = baseDescFont
    private var actionHints: [ActionHint] = []
    private var hintViews: [NSView] = []

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        identifier = Self.reuseIdentifier
        wantsLayer = true

        for textField in [titleField, descField] {
            textField.isBordered = false
            textField.isEditable = false
            textField.backgroundColor = .clear
            textField.translatesAutoresizingMaskIntoConstraints = false
            textField.lineBreakMode = .byTruncatingTail
        }

        addSubview(descField)

        titleField.font = baseTitleFont
        titleField.textColor = NSColor.white.withAlphaComponent(0.92)
        titleField.maximumNumberOfLines = 1
        titleField.usesSingleLineMode = true
        titleField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        descField.font = baseDescFont
        descField.textColor = NSColor.white.withAlphaComponent(0.6)

        textField = titleField

        titleStack.orientation = .horizontal
        titleStack.alignment = .centerY
        titleStack.spacing = 6
        titleStack.translatesAutoresizingMaskIntoConstraints = false
        titleStack.addArrangedSubview(titleField)
        titleStack.addArrangedSubview(recentTagView)
        recentTagView.isHidden = true
        addSubview(titleStack)

        actionHintStack.orientation = .horizontal
        actionHintStack.alignment = .centerY
        actionHintStack.spacing = 8
        actionHintStack.translatesAutoresizingMaskIntoConstraints = false
        actionHintStack.isHidden = true

        actionHintsContentStack.orientation = .horizontal
        actionHintsContentStack.alignment = .centerY
        actionHintsContentStack.spacing = 10
        actionHintsContentStack.translatesAutoresizingMaskIntoConstraints = false

        actionHintStack.addArrangedSubview(actionHintsContentStack)
        actionHintStack.addArrangedSubview(commandMenuHintView)

        addSubview(actionHintStack)

        titleTrailingToHint = titleStack.trailingAnchor.constraint(lessThanOrEqualTo: actionHintStack.leadingAnchor, constant: -8)
        descTrailingToHint = descField.trailingAnchor.constraint(lessThanOrEqualTo: actionHintStack.leadingAnchor, constant: -8)
        titleTrailingToEdge = titleStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4)
        descTrailingToEdge = descField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4)
        let hintStackTrailing = actionHintStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4)

        hintVisibilityConstraints = [
            titleTrailingToHint,
            descTrailingToHint
        ]

        hintHiddenConstraints = [
            titleTrailingToEdge,
            descTrailingToEdge
        ]

        NSLayoutConstraint.activate([
            titleStack.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            titleStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),

            descField.topAnchor.constraint(equalTo: titleStack.bottomAnchor, constant: 2),
            descField.leadingAnchor.constraint(equalTo: titleStack.leadingAnchor),
            descField.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -4),

            actionHintStack.centerYAnchor.constraint(equalTo: centerYAnchor),
            hintStackTrailing
        ])

        setActionHints([])
    }

    func apply(title: String,
               titleColor: NSColor,
               subtitle: String?,
               subtitleColor: NSColor? = nil,
               tooltip: String? = nil) {
        titleField.stringValue = title
        titleField.textColor = titleColor
        titleField.toolTip = tooltip

        if let subtitle, !subtitle.isEmpty {
            descField.stringValue = subtitle
            descField.textColor = subtitleColor ?? NSColor.white.withAlphaComponent(0.55)
            descField.isHidden = false
        } else {
            descField.isHidden = true
        }
    }

    func configureForInstalled() {
        applyBaseFonts()
        applySingleLineTitle()
        recentTagView.isHidden = true
    }

    func configureForCask() {
        applyBaseFonts()
        applySingleLineTitle()
        recentTagView.isHidden = true
    }

    func configureForHistory(isRecent: Bool, useReducedFonts: Bool) {
        if useReducedFonts {
            titleField.font = historyTitleFont
            descField.font = historyDescFont
        } else {
            applyBaseFonts()
        }
        enableMultilineTitle()
        recentTagView.isHidden = !isRecent
    }

    func configureForPlainText() {
        applyBaseFonts()
        applySingleLineTitle()
        recentTagView.isHidden = true
    }

    func setRecentTagVisible(_ isVisible: Bool) {
        recentTagView.isHidden = !isVisible
    }

    func setActionHint(_ text: String?, keyGlyph: String = "↩︎") {
        guard let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            setActionHints([])
            return
        }
        setActionHints([ActionHint(keyGlyph: keyGlyph, text: trimmed)])
    }

    func setActionHints(_ hints: [ActionHint]) {
        actionHints = hints
        rebuildHintViews()
        updateActionHintVisibility()
    }

    func refreshActionHintVisibility() {
        updateActionHintVisibility()
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        setActionHints([])
    }

    override var backgroundStyle: NSView.BackgroundStyle {
        didSet {
            updateActionHintVisibility()
        }
    }

    private func updateActionHintVisibility() {
        let shouldShow = isCellSelected()
        actionHintStack.isHidden = !shouldShow

        if shouldShow {
            NSLayoutConstraint.deactivate(hintHiddenConstraints)
            NSLayoutConstraint.activate(hintVisibilityConstraints)
        } else {
            NSLayoutConstraint.deactivate(hintVisibilityConstraints)
            NSLayoutConstraint.activate(hintHiddenConstraints)
        }
    }

    private func enclosingTableView() -> NSTableView? {
        var current: NSView? = superview
        while let view = current {
            if let tableView = view as? NSTableView {
                return tableView
            }
            current = view.superview
        }
        return nil
    }

    private func isCellSelected() -> Bool {
        guard let tableView = enclosingTableView() else { return false }
        let row = tableView.row(for: self)
        return row >= 0 && tableView.selectedRowIndexes.contains(row)
    }

    private func applySingleLineTitle() {
        titleField.usesSingleLineMode = true
        titleField.maximumNumberOfLines = 1
        titleField.lineBreakMode = .byTruncatingTail
        if let titleCell = titleField.cell as? NSTextFieldCell {
            titleCell.wraps = false
            titleCell.isScrollable = true
            titleCell.lineBreakMode = .byTruncatingTail
        }
        titleField.toolTip = nil
    }

    private func enableMultilineTitle() {
        titleField.usesSingleLineMode = false
        titleField.maximumNumberOfLines = 2
        titleField.lineBreakMode = .byTruncatingMiddle
        if let titleCell = titleField.cell as? NSTextFieldCell {
            titleCell.wraps = true
            titleCell.isScrollable = false
            titleCell.lineBreakMode = .byTruncatingMiddle
        }
    }

    private func applyBaseFonts() {
        titleField.font = baseTitleFont
        descField.font = baseDescFont
    }

    private func rebuildHintViews() {
        hintViews.forEach { view in
            actionHintsContentStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        hintViews.removeAll()

        for hint in actionHints {
            let view = makeHintView(for: hint)
            actionHintsContentStack.addArrangedSubview(view)
            hintViews.append(view)
        }

        actionHintsContentStack.isHidden = hintViews.isEmpty
    }

    private func makeHintView(for hint: ActionHint) -> NSView {
        return ActionHintPillView(keyGlyph: hint.keyGlyph, text: hint.text)
    }

}
