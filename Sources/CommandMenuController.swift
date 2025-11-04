import Cocoa

struct CommandMenuItem {
    let title: String
    let subtitle: String?
    let keyGlyph: String?
    let handler: () -> Void

    init(title: String, subtitle: String? = nil, keyGlyph: String?, handler: @escaping () -> Void) {
        self.title = title
        self.subtitle = subtitle
        self.keyGlyph = keyGlyph
        self.handler = handler
    }
}

final class CommandMenuController: NSViewController {
    private final class CommandMenuTableView: NSTableView {
        var onInvoke: (() -> Void)?
        var onCancel: (() -> Void)?

        override func keyDown(with event: NSEvent) {
            switch event.keyCode {
            case 36, 76: // Return or keypad enter
                onInvoke?()
            case 53, 123: // Escape or left arrow
                onCancel?()
            default:
                super.keyDown(with: event)
            }
        }
    }

    private final class CommandMenuCellView: NSTableCellView {
        private let titleField = NSTextField(labelWithString: "")
        private let subtitleField = NSTextField(labelWithString: "")
        private let keyLabel = NSTextField(labelWithString: "")

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            setup()
        }

        required init?(coder: NSCoder) {
            super.init(coder: coder)
            setup()
        }

        private func setup() {
            wantsLayer = true
            translatesAutoresizingMaskIntoConstraints = false

            let stack = NSStackView()
            stack.orientation = .horizontal
            stack.alignment = .centerY
            stack.spacing = 8
            stack.translatesAutoresizingMaskIntoConstraints = false

            let textStack = NSStackView()
            textStack.orientation = .vertical
            textStack.alignment = .leading
            textStack.spacing = 1
            textStack.translatesAutoresizingMaskIntoConstraints = false

            titleField.font = NSFont.systemFont(ofSize: 13, weight: .medium)
            titleField.textColor = NSColor.white
            titleField.lineBreakMode = .byTruncatingTail

            subtitleField.font = NSFont.systemFont(ofSize: 11)
            subtitleField.textColor = NSColor.white.withAlphaComponent(0.7)
            subtitleField.lineBreakMode = .byTruncatingTail
            subtitleField.isHidden = true

            keyLabel.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
            keyLabel.textColor = NSColor.white.withAlphaComponent(0.75)
            keyLabel.setContentHuggingPriority(.required, for: .horizontal)

            textStack.addArrangedSubview(titleField)
            textStack.addArrangedSubview(subtitleField)

            stack.addArrangedSubview(textStack)
            stack.addArrangedSubview(keyLabel)

            addSubview(stack)

            NSLayoutConstraint.activate([
                stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
                stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
                stack.topAnchor.constraint(equalTo: topAnchor, constant: 2),
                stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -2)
            ])
        }

        func configure(with item: CommandMenuItem) {
            titleField.stringValue = item.title
            if let subtitle = item.subtitle, !subtitle.isEmpty {
                subtitleField.stringValue = subtitle
                subtitleField.isHidden = false
            } else {
                subtitleField.stringValue = ""
                subtitleField.isHidden = true
            }
            if let glyph = item.keyGlyph, !glyph.isEmpty {
                keyLabel.stringValue = glyph
                keyLabel.isHidden = false
            } else {
                keyLabel.isHidden = true
            }
        }
    }

    private let popover = NSPopover()
    private let tableView = CommandMenuTableView()
    private var items: [CommandMenuItem] = []

    private let scrollView = NSScrollView()
    private let minWidth: CGFloat = 220
    private let preferredWidth: CGFloat = 260
    private let verticalPadding: CGFloat = 24
    private let maxVisibleItems = 6
    private let singleLineRowHeight: CGFloat = 32
    private let doubleLineRowHeight: CGFloat = 48

    var onDismiss: (() -> Void)?

    var isShown: Bool {
        popover.isShown
    }

    override func loadView() {
        let effectView = NSVisualEffectView()
        effectView.material = .hudWindow
        effectView.state = .active
        effectView.blendingMode = .withinWindow
        effectView.wantsLayer = true
        effectView.layer?.cornerRadius = 10
        effectView.layer?.masksToBounds = true
        view = effectView

        setupTableView()
        setupScrollView()
    }

    override init(nibName nibNameOrNil: NSNib.Name?, bundle nibBundleOrNil: Bundle?) {
        super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)
        popover.contentViewController = self
        popover.behavior = .transient
        popover.delegate = self
        popover.animates = true
    }

    required init?(coder: NSCoder) {
        return nil
    }

    func show(relativeTo rect: NSRect, of view: NSView, preferredEdge: NSRectEdge = .maxX, items: [CommandMenuItem]) {
        guard !items.isEmpty else { return }
        self.items = items
        tableView.reloadData()
        updatePreferredContentSize()
        if popover.isShown {
            popover.performClose(nil)
        }
        popover.show(relativeTo: rect, of: view, preferredEdge: preferredEdge)
        view.window?.makeFirstResponder(tableView)
        DispatchQueue.main.async { [weak self] in
            self?.selectInitialRowIfNeeded()
        }
    }

    func dismiss() {
        if popover.isShown {
            popover.performClose(nil)
        }
    }

    private func setupScrollView() {
        let contentView = view

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.borderType = .noBorder
        scrollView.documentView = tableView
        contentView.addSubview(scrollView)

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 8),
            scrollView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -8),
            scrollView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            scrollView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -8),
            scrollView.widthAnchor.constraint(greaterThanOrEqualToConstant: minWidth)
        ])

        if let clipView = scrollView.contentView as? NSClipView {
            tableView.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                tableView.leadingAnchor.constraint(equalTo: clipView.leadingAnchor),
                tableView.trailingAnchor.constraint(equalTo: clipView.trailingAnchor),
                tableView.topAnchor.constraint(equalTo: clipView.topAnchor),
                tableView.bottomAnchor.constraint(equalTo: clipView.bottomAnchor),
                tableView.widthAnchor.constraint(equalTo: scrollView.widthAnchor)
            ])
        }
    }

    private func setupTableView() {
        tableView.headerView = nil
        tableView.backgroundColor = .clear
        tableView.focusRingType = .none
        tableView.allowsTypeSelect = false
        tableView.allowsEmptySelection = false
        tableView.selectionHighlightStyle = .regular
        tableView.rowHeight = singleLineRowHeight
        tableView.intercellSpacing = NSSize(width: 0, height: 4)
        tableView.delegate = self
        tableView.dataSource = self
        tableView.target = self
        tableView.action = #selector(invokeSelectedItem)
        tableView.doubleAction = #selector(invokeSelectedItem)
        tableView.onInvoke = { [weak self] in self?.invokeSelectedItem() }
        tableView.onCancel = { [weak self] in self?.dismiss() }

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("Command"))
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)
    }

    private func selectInitialRowIfNeeded() {
        guard tableView.numberOfRows > 0 else { return }
        tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        tableView.scrollRowToVisible(0)
    }

    private func updatePreferredContentSize() {
        let visibleItems = Array(items.prefix(maxVisibleItems))
        if visibleItems.isEmpty {
            preferredContentSize = NSSize(width: preferredWidth, height: verticalPadding)
            return
        }

        let rowsHeight = visibleItems.reduce(0) { $0 + rowHeight(for: $1) }
        let spacing = CGFloat(max(visibleItems.count - 1, 0)) * tableView.intercellSpacing.height
        let height = rowsHeight + spacing + verticalPadding
        preferredContentSize = NSSize(width: preferredWidth, height: height)
    }

    @objc private func invokeSelectedItem() {
        let row = tableView.selectedRow
        guard row >= 0, row < items.count else { return }
        let item = items[row]
        dismiss()
        item.handler()
    }
}

extension CommandMenuController: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int {
        items.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let identifier = NSUserInterfaceItemIdentifier("CommandMenuCell")
        let cell: CommandMenuCellView
        if let existing = tableView.makeView(withIdentifier: identifier, owner: self) as? CommandMenuCellView {
            cell = existing
        } else {
            cell = CommandMenuCellView()
            cell.identifier = identifier
        }
        cell.configure(with: items[row])
        return cell
    }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
        return row >= 0 && row < items.count
    }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        guard row >= 0, row < items.count else { return singleLineRowHeight }
        return rowHeight(for: items[row])
    }
}

extension CommandMenuController: NSPopoverDelegate {
    func popoverDidClose(_ notification: Notification) {
        onDismiss?()
    }
}

private extension CommandMenuController {
    func rowHeight(for item: CommandMenuItem) -> CGFloat {
        return item.subtitle == nil ? singleLineRowHeight : doubleLineRowHeight
    }
}
