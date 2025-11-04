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

final class SearchResultCellView: NSTableCellView {
    static let reuseIdentifier = NSUserInterfaceItemIdentifier("SearchResultCell")

    let titleField = VibrantTextField()
    let descField = VibrantTextField()
    private let actionHintStack = NSStackView()
    private let enterKeyLabel = NSTextField(labelWithString: "↩︎")
    private let actionHintLabel = NSTextField(labelWithString: "")
    private let titleStack = NSStackView()
    private let recentTagView = PillTagView(text: "recent")

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
    private var actionHintText: String?
    private var actionHintKeyGlyph: String = "↩︎"

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
        actionHintStack.spacing = 4
        actionHintStack.translatesAutoresizingMaskIntoConstraints = false
        actionHintStack.isHidden = true

        enterKeyLabel.font = NSFont.monospacedSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .semibold)
        enterKeyLabel.textColor = NSColor.white.withAlphaComponent(0.75)
        enterKeyLabel.alignment = .center
        enterKeyLabel.drawsBackground = true
        enterKeyLabel.backgroundColor = NSColor.white.withAlphaComponent(0.18)
        enterKeyLabel.lineBreakMode = .byClipping
        enterKeyLabel.translatesAutoresizingMaskIntoConstraints = false
        enterKeyLabel.wantsLayer = true
        enterKeyLabel.layer?.cornerRadius = 4
        enterKeyLabel.layer?.masksToBounds = true
        enterKeyLabel.setContentHuggingPriority(.required, for: .horizontal)
        enterKeyLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        NSLayoutConstraint.activate([
            enterKeyLabel.widthAnchor.constraint(equalToConstant: 24),
            enterKeyLabel.heightAnchor.constraint(equalToConstant: 16)
        ])

        actionHintLabel.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize - 1, weight: .medium)
        actionHintLabel.textColor = NSColor.white.withAlphaComponent(0.7)
        actionHintLabel.alignment = .left
        actionHintLabel.translatesAutoresizingMaskIntoConstraints = false
        actionHintLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        actionHintLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        actionHintStack.addArrangedSubview(enterKeyLabel)
        actionHintStack.addArrangedSubview(actionHintLabel)
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

        setActionHint(nil)
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

    func setActionHint(_ text: String?, keyGlyph: String = "↩︎") {
        let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmed, !trimmed.isEmpty {
            actionHintText = trimmed
            actionHintLabel.stringValue = trimmed
        } else {
            actionHintText = nil
            actionHintLabel.stringValue = ""
        }
        actionHintKeyGlyph = keyGlyph
        enterKeyLabel.stringValue = keyGlyph
        updateActionHintVisibility()
    }

    func refreshActionHintVisibility() {
        updateActionHintVisibility()
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        setActionHint(nil)
    }

    override var backgroundStyle: NSView.BackgroundStyle {
        didSet {
            updateActionHintVisibility()
        }
    }

    private func updateActionHintVisibility() {
        let shouldShow = isCellSelected() && !(actionHintText?.isEmpty ?? true)
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
}
