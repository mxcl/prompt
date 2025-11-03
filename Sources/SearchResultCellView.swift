import Cocoa

final class SearchResultCellView: NSTableCellView {
    static let reuseIdentifier = NSUserInterfaceItemIdentifier("SearchResultCell")

    let titleField = VibrantTextField()
    let descField = VibrantTextField()
    let homepageButton = NSButton(title: "Homepage", target: nil, action: nil)
    let installButton = NSButton(title: "Install", target: nil, action: nil)
    private let buttonStack = NSStackView()

    private var trackingAdded = false
    private var isHoverHighlightEnabled = false

    private var titleTrailingToButtons: NSLayoutConstraint!
    private var descTrailingToButtons: NSLayoutConstraint!
    private var titleTrailingToEdge: NSLayoutConstraint!
    private var descTrailingToEdge: NSLayoutConstraint!
    private var buttonVisibilityConstraints: [NSLayoutConstraint] = []
    private var buttonHiddenConstraints: [NSLayoutConstraint] = []

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
            addSubview(textField)
        }

        titleField.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        titleField.textColor = NSColor.white.withAlphaComponent(0.92)
        titleField.maximumNumberOfLines = 1
        titleField.usesSingleLineMode = true

        descField.font = NSFont.systemFont(ofSize: 13)
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

        buttonStack.orientation = .horizontal
        buttonStack.alignment = .centerY
        buttonStack.spacing = 4
        buttonStack.translatesAutoresizingMaskIntoConstraints = false
        buttonStack.addArrangedSubview(homepageButton)
        buttonStack.addArrangedSubview(installButton)
        addSubview(buttonStack)

        buttonStack.alphaValue = 1

        titleTrailingToButtons = titleField.trailingAnchor.constraint(lessThanOrEqualTo: buttonStack.leadingAnchor, constant: -8)
        descTrailingToButtons = descField.trailingAnchor.constraint(lessThanOrEqualTo: buttonStack.leadingAnchor, constant: -8)
        titleTrailingToEdge = titleField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6)
        descTrailingToEdge = descField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6)
        let buttonStackTrailing = buttonStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6)

        buttonVisibilityConstraints = [
            titleTrailingToButtons,
            descTrailingToButtons
        ]

        buttonHiddenConstraints = [
            titleTrailingToEdge,
            descTrailingToEdge
        ]

        NSLayoutConstraint.activate([
            titleField.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            titleField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),

            descField.topAnchor.constraint(equalTo: titleField.bottomAnchor, constant: 2),
            descField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
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
        applySingleLineTitle()
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
        applySingleLineTitle()
    }

    func configureForHistory(command: String, display: String?) {
        isHoverHighlightEnabled = false
        setButtonsVisible(false)
        enableMultilineTitle()
        let title = display?.isEmpty == false ? display! : command
        titleField.stringValue = title
        titleField.toolTip = command
        descField.stringValue = "Recent command"
        descField.textColor = NSColor.white.withAlphaComponent(0.55)
        descField.isHidden = false
    }

    func configureForPlainText() {
        isHoverHighlightEnabled = false
        setButtonsVisible(false)
        applySingleLineTitle()
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
}
