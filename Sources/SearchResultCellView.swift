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
    let homepageButton = NSButton(title: "Homepage", target: nil, action: nil)
    let installButton = NSButton(title: "Install", target: nil, action: nil)
    private let buttonStack = NSStackView()
    private let titleStack = NSStackView()
    private let recentTagView = PillTagView(text: "recent")

    private var trackingAdded = false
    private var isHoverHighlightEnabled = false

    private var titleTrailingToButtons: NSLayoutConstraint!
    private var descTrailingToButtons: NSLayoutConstraint!
    private var titleTrailingToEdge: NSLayoutConstraint!
    private var descTrailingToEdge: NSLayoutConstraint!
    private var buttonVisibilityConstraints: [NSLayoutConstraint] = []
    private var buttonHiddenConstraints: [NSLayoutConstraint] = []
    private let baseTitleFont = NSFont.systemFont(ofSize: NSFont.systemFontSize)
    private let baseDescFont = NSFont.systemFont(ofSize: 13)
    private lazy var historyTitleFont: NSFont = baseTitleFont
    private lazy var historyDescFont: NSFont = baseDescFont

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

        let smallFont = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize - 1)
        for button in [homepageButton, installButton] {
            button.isBordered = false
            button.bezelStyle = .inline
            button.font = smallFont
            button.contentTintColor = .tertiaryLabelColor
            button.setButtonType(.momentaryChange)
            button.focusRingType = .none
        }

        if let homeImage = NSImage(systemSymbolName: "house", accessibilityDescription: "Homepage") {
            homepageButton.image = homeImage
            homepageButton.imagePosition = .imageOnly
            homepageButton.title = ""
        } else {
            homepageButton.title = "Home"
        }

        installButton.title = "Install…"
        installButton.contentTintColor = .secondaryLabelColor

        titleStack.orientation = .horizontal
        titleStack.alignment = .centerY
        titleStack.spacing = 6
        titleStack.translatesAutoresizingMaskIntoConstraints = false
        titleStack.addArrangedSubview(titleField)
        titleStack.addArrangedSubview(recentTagView)
        recentTagView.isHidden = true
        addSubview(titleStack)

        buttonStack.orientation = .horizontal
        buttonStack.alignment = .centerY
        buttonStack.spacing = 4
        buttonStack.translatesAutoresizingMaskIntoConstraints = false
        buttonStack.addArrangedSubview(homepageButton)
        buttonStack.addArrangedSubview(installButton)
        addSubview(buttonStack)

        buttonStack.alphaValue = 1

        titleTrailingToButtons = titleStack.trailingAnchor.constraint(lessThanOrEqualTo: buttonStack.leadingAnchor, constant: -8)
        descTrailingToButtons = descField.trailingAnchor.constraint(lessThanOrEqualTo: buttonStack.leadingAnchor, constant: -8)
        titleTrailingToEdge = titleStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4)
        descTrailingToEdge = descField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4)
        let buttonStackTrailing = buttonStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4)

        buttonVisibilityConstraints = [
            titleTrailingToButtons,
            descTrailingToButtons
        ]

        buttonHiddenConstraints = [
            titleTrailingToEdge,
            descTrailingToEdge
        ]

        NSLayoutConstraint.activate([
            titleStack.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            titleStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),

            descField.topAnchor.constraint(equalTo: titleStack.bottomAnchor, constant: 2),
            descField.leadingAnchor.constraint(equalTo: titleStack.leadingAnchor),
            descField.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -4),

            buttonStack.centerYAnchor.constraint(equalTo: centerYAnchor),
            buttonStackTrailing
        ])

        setButtonsVisible(false)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas {
            removeTrackingArea(area)
        }

        guard isHoverHighlightEnabled else { return }

        let options: NSTrackingArea.Options = [.mouseEnteredAndExited, .inVisibleRect, .activeAlways]
        let area = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingAdded = true
    }

    override func mouseEntered(with event: NSEvent) {
        guard isHoverHighlightEnabled else { return }
        setButtonBorders(visible: true)
    }

    override func mouseExited(with event: NSEvent) {
        guard isHoverHighlightEnabled else { return }
        setButtonBorders(visible: false)
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
        isHoverHighlightEnabled = false
        setButtonsVisible(false)
        applyBaseFonts()
        applySingleLineTitle()
        recentTagView.isHidden = true
    }

    func configureForCask(homepageAvailable: Bool, row: Int, target: AnyObject, homepageSelector: Selector, installSelector: Selector) {
        isHoverHighlightEnabled = true
        setButtonsVisible(true)
        homepageButton.isHidden = !homepageAvailable
        installButton.isHidden = false
        homepageButton.tag = row
        installButton.tag = row
        homepageButton.target = target
        homepageButton.action = homepageSelector
        installButton.target = target
        installButton.action = installSelector
        setButtonBorders(visible: false)
        applyBaseFonts()
        applySingleLineTitle()
        recentTagView.isHidden = true
    }

    func configureForHistory(isRecent: Bool, useReducedFonts: Bool) {
        isHoverHighlightEnabled = false
        setButtonsVisible(false)
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
        isHoverHighlightEnabled = false
        setButtonsVisible(false)
        applyBaseFonts()
        applySingleLineTitle()
        recentTagView.isHidden = true
    }

    private func setButtonsVisible(_ visible: Bool) {
        buttonStack.isHidden = !visible

        if visible {
            NSLayoutConstraint.deactivate(buttonHiddenConstraints)
            NSLayoutConstraint.activate(buttonVisibilityConstraints)
            homepageButton.isHidden = false
            installButton.isHidden = false
        } else {
            NSLayoutConstraint.deactivate(buttonVisibilityConstraints)
            NSLayoutConstraint.activate(buttonHiddenConstraints)
            homepageButton.isHidden = true
            installButton.isHidden = true
        }

        setButtonBorders(visible: false)
    }

    private func setButtonBorders(visible: Bool) {
        for button in [homepageButton, installButton] {
            button.isBordered = visible
        }
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
