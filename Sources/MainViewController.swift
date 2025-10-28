import Cocoa

// Custom table view that can navigate back to search field
class NavigableTableView: NSTableView {
    weak var navigationDelegate: TableViewNavigationDelegate?

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 126: // Up arrow
            let selectedRow = self.selectedRow
            if selectedRow == 0 {
                // At first item, go back to search field
                navigationDelegate?.tableViewShouldReturnToSearchField(self)
                return
            }
        case 36: // Enter/Return key
            if self.selectedRow >= 0 {
                navigationDelegate?.tableViewShouldLaunchSelectedApp(self)
                return
            }
        default:
            break
        }
        super.keyDown(with: event)
    }
}

protocol TableViewNavigationDelegate: AnyObject {
    func tableViewShouldReturnToSearchField(_ tableView: NSTableView)
    func tableViewShouldLaunchSelectedApp(_ tableView: NSTableView)
}

class MainViewController: NSViewController {
    private var searchField: NSTextField!
    private var tableView: NavigableTableView!
    private var scrollView: NSScrollView!
    private var apps: [SearchResult] = []
    private let commandHistory = CommandHistory.shared
    private var isApplyingAutocomplete = false
    private let autocompleteSkipKeyCodes: Set<UInt16> = [51, 117] // delete, forward delete

    // MARK: - Button Actions
    @objc private func homepageButtonPressed(_ sender: NSButton) {
        let row = sender.tag
        guard row >= 0 && row < apps.count else { return }
        if case .availableCask(let cask) = apps[row], let homepage = cask.homepage, let url = URL(string: homepage) {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func installButtonPressed(_ sender: NSButton) {
        let row = sender.tag
        guard row >= 0 && row < apps.count else { return }
        if case .availableCask(let cask) = apps[row] {
            installCask(cask)
        }
    }

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        setupUI()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.wantsLayer = true
        setupNotifications()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        focusAndSelectSearchField()
    }

    private func setupNotifications() {
        // Hide window when another app becomes active
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(otherAppDidActivate(_:)),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )

        // Focus search field when window becomes key
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidBecomeKey(_:)),
            name: NSWindow.didBecomeKeyNotification,
            object: nil
        )
    }

    @objc private func windowDidBecomeKey(_ notification: Notification) {
        // Check if this notification is for our window
        if let window = notification.object as? NSWindow, window == view.window {
            focusAndSelectSearchField()
        }
    }

    private func focusAndSelectSearchField() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.view.window?.makeFirstResponder(self.searchField)
            self.searchField.selectText(nil)
        }
    }

    @objc private func otherAppDidActivate(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let activatedApp = userInfo[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
            return
        }

        // Don't hide if our own app is becoming active
        if activatedApp.bundleIdentifier == Bundle.main.bundleIdentifier {
            return
        }

        // Hide our window when another app becomes active
        view.window?.orderOut(nil)
    }

    deinit {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        NotificationCenter.default.removeObserver(self)
    }

    private func setupUI() {
        // Create search field
        searchField = NSTextField(frame: NSRect(x: 20, y: 350, width: 560, height: 24))
        searchField.placeholderString = "Run"
        searchField.target = self
        searchField.action = #selector(searchFieldChanged(_:))
        searchField.delegate = self

        // Add continuous text change monitoring
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(textDidChange(_:)),
            name: NSControl.textDidChangeNotification,
            object: searchField
        )

        view.addSubview(searchField)

        // Create table view
        tableView = NavigableTableView()
        tableView.delegate = self
        tableView.dataSource = self
        tableView.target = self
        tableView.doubleAction = #selector(tableViewDoubleClicked(_:))
        tableView.navigationDelegate = self

        // Configure selection behavior
        tableView.allowsEmptySelection = false

        // Create table column
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("AppName"))
        column.title = ""
        column.width = 560
        tableView.addTableColumn(column)

        // Hide the table header
        tableView.headerView = nil

        // Create scroll view
        scrollView = NSScrollView(frame: NSRect(x: 20, y: 20, width: 560, height: 320))
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        view.addSubview(scrollView)

        // Setup Auto Layout
        setupConstraints()
    }

    private func setupConstraints() {
        searchField.translatesAutoresizingMaskIntoConstraints = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            // Search field constraints
            searchField.topAnchor.constraint(equalTo: view.topAnchor, constant: 20),
            searchField.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            searchField.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            searchField.heightAnchor.constraint(equalToConstant: 24),

            // Scroll view constraints - moved up to be against search field
            scrollView.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 1),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -20)
        ])
    }

    @objc private func searchFieldChanged(_ sender: NSTextField) {
        let current = sender.stringValue
        if openURLIfPossible(from: current) {
            return
        }
        performSearch(current)
    }

    @objc private func textDidChange(_ notification: Notification) {
        guard let textField = notification.object as? NSTextField else { return }
        if isApplyingAutocomplete {
            performSearch(textField.stringValue)
            return
        }

        var skipAutocomplete = false
        if let event = NSApp.currentEvent, event.type == .keyDown {
            if autocompleteSkipKeyCodes.contains(event.keyCode) {
                skipAutocomplete = true
            }
        }
        if !skipAutocomplete {
            applyAutocompleteIfNeeded(for: textField)
        }

        performSearch(textField.stringValue)
    }

    private func resolvedURL(from input: String) -> URL? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let fullRange = NSRange(location: 0, length: trimmed.utf16.count)

        if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue),
           let match = detector.firstMatch(in: trimmed, options: [], range: fullRange),
           match.range == fullRange,
           let detectedURL = match.url {
            if let scheme = detectedURL.scheme, !scheme.isEmpty {
                return detectedURL
            }
            return URL(string: "https://\(trimmed)")
        }

        if trimmed.contains("."), !trimmed.contains(" ") {
            if let explicitURL = URL(string: trimmed), explicitURL.scheme != nil {
                return explicitURL
            }
            return URL(string: "https://\(trimmed)")
        }

        return nil
    }

    private func recordSuccessfulRun(using input: String? = nil) {
        let value = (input ?? searchField.stringValue)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        commandHistory.record(value)
    }

    private func openURLIfPossible(from input: String) -> Bool {
        guard let url = resolvedURL(from: input) else { return false }
        let success = NSWorkspace.shared.open(url)
        if success {
            recordSuccessfulRun(using: input)
        }
        searchField.stringValue = ""
        apps = []
        tableView.reloadData()
        return success
    }

    private func applyAutocompleteIfNeeded(for textField: NSTextField) {
        guard let fieldEditor = view.window?.fieldEditor(true, for: textField) as? NSTextView else { return }
        let currentText = fieldEditor.string
        guard !currentText.isEmpty else { return }

        let selection = fieldEditor.selectedRange
        guard selection.location == currentText.count, selection.length == 0 else { return }

        guard let completion = commandHistory.bestCompletion(for: currentText),
              completion.count > currentText.count else { return }
        if completion.lowercased() == currentText.lowercased() {
            return
        }

        isApplyingAutocomplete = true
        defer { isApplyingAutocomplete = false }

        fieldEditor.string = completion
        textField.stringValue = completion
        let highlightRange = NSRange(location: currentText.count, length: completion.count - currentText.count)
        fieldEditor.setSelectedRange(highlightRange)
    }

    private func performSearch(_ searchText: String) {
        guard !searchText.isEmpty else {
            apps = []
            tableView.reloadData()
            return
        }

        searchApplications(queryString: searchText) { [weak self] results in
            DispatchQueue.main.async {
                self?.apps = results
                self?.tableView.reloadData()

                // Always select the first item if there are results
                if results.count > 0 {
                    self?.tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
                }
            }
        }
    }

    @objc private func tableViewDoubleClicked(_ sender: NSTableView) {
        let row = sender.clickedRow
        guard row >= 0 && row < apps.count else { return }

        let app = apps[row]
        if launchApplication(app) {
            recordSuccessfulRun(using: app.displayName)
        }
    }

    @discardableResult
    private func launchApplication(_ searchResult: SearchResult) -> Bool {
        switch searchResult {
        case .installedAppMetadata(_, let path, let bundleID, _):
            return launchInstalledApp(bundleId: bundleID, path: path)
        case .availableCask(let cask):
            return installCask(cask)
        }
    }

    private func launchInstalledApp(bundleId: String?, path: String?) -> Bool {
        let workspace = NSWorkspace.shared

        if let bundleId = bundleId {
            if workspace.launchApplication(withBundleIdentifier: bundleId,
                                           options: [],
                                           additionalEventParamDescriptor: nil,
                                           launchIdentifier: nil) {
                return true
            }
            if let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).first {
                running.activate(options: [.activateIgnoringOtherApps])
                return true
            }
        }

        if let path = path {
            let url = URL(fileURLWithPath: path)
            if workspace.open(url) { return true }
        }

        return false
    }

    private func installCask(_ cask: CaskData.CaskItem) -> Bool {
        // For now, just open the homepage or show info
        // You could implement actual Homebrew installation here
        if let homepage = cask.homepage, let url = URL(string: homepage) {
            return NSWorkspace.shared.open(url)
        }
        return false
    }
}

// MARK: - NSTableViewDataSource
extension MainViewController: NSTableViewDataSource {
    func numberOfRows(in tableView: NSTableView) -> Int {
        return apps.count
    }
}

// MARK: - NSTableViewDelegate
extension MainViewController: NSTableViewDelegate {
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let identifier = NSUserInterfaceItemIdentifier("AppCell")

        // Custom composite cell containing primary + optional secondary label
        class AppCellView: NSTableCellView {
            let titleField = NSTextField()
            let descField = NSTextField()
            let homepageButton = NSButton(title: "Homepage", target: nil, action: nil)
            let installButton = NSButton(title: "Install", target: nil, action: nil)
            let buttonStack = NSStackView()
            private var trackingAdded = false
            private var isCask = false

            override init(frame frameRect: NSRect) {
                super.init(frame: frameRect)
                setup()
            }
            required init?(coder: NSCoder) {
                super.init(coder: coder)
                setup()
            }
            private func setup() {
                identifier = identifier ?? NSUserInterfaceItemIdentifier("AppCell")
                wantsLayer = true

                for tf in [titleField, descField] {
                    tf.isBordered = false
                    tf.isEditable = false
                    tf.backgroundColor = .clear
                    tf.translatesAutoresizingMaskIntoConstraints = false
                    tf.lineBreakMode = .byTruncatingTail
                    addSubview(tf)
                }
                descField.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
                descField.textColor = NSColor.tertiaryLabelColor

                textField = titleField
                // Configure subtle buttons stack (less imposing)
                let smallFont = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize - 1)
                for b in [homepageButton, installButton] {
                    b.isBordered = false
                    b.bezelStyle = .inline
                    b.font = smallFont
                    b.contentTintColor = .tertiaryLabelColor
                    b.setButtonType(.momentaryChange)
                    b.focusRingType = .none
                }
                if let homeImage = NSImage(systemSymbolName: "house", accessibilityDescription: "Homepage") {
                    homepageButton.image = homeImage
                    homepageButton.imagePosition = .imageOnly
                    homepageButton.title = "" // image only
                } else {
                    homepageButton.title = "Home" // fallback
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

                buttonStack.alphaValue = 1 // always visible; border appears on hover

                NSLayoutConstraint.activate([
                    titleField.topAnchor.constraint(equalTo: topAnchor, constant: 4),
                    titleField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
                    // Title should not overlap buttons
                    titleField.trailingAnchor.constraint(lessThanOrEqualTo: buttonStack.leadingAnchor, constant: -8),

                    descField.topAnchor.constraint(equalTo: titleField.bottomAnchor, constant: 2),
                    descField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
                    descField.trailingAnchor.constraint(lessThanOrEqualTo: buttonStack.leadingAnchor, constant: -8),
                    descField.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -4),

                    buttonStack.centerYAnchor.constraint(equalTo: centerYAnchor),
                    buttonStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6)
                ])
            }

            override func updateTrackingAreas() {
                super.updateTrackingAreas()
                for ta in trackingAreas { removeTrackingArea(ta) }
                let options: NSTrackingArea.Options = [.mouseEnteredAndExited, .inVisibleRect, .activeAlways]
                let area = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
                addTrackingArea(area)
                trackingAdded = true
            }
            override func mouseEntered(with event: NSEvent) {
                guard isCask else { return }
                setButtonBorders(visible: true)
            }
            override func mouseExited(with event: NSEvent) {
                guard isCask else { return }
                setButtonBorders(visible: false)
            }
            private func setButtonBorders(visible: Bool) {
                for b in [homepageButton, installButton] { b.isBordered = visible }
            }
            func configureForInstalled() {
                isCask = false
                homepageButton.isHidden = true
                installButton.isHidden = true
                setButtonBorders(visible: false)
            }
            func configureForCask(homepageAvailable: Bool, row: Int) {
                isCask = true
                homepageButton.isHidden = !homepageAvailable
                installButton.isHidden = false
                homepageButton.tag = row
                installButton.tag = row
                setButtonBorders(visible: false)
            }
        }

        var cellView = tableView.makeView(withIdentifier: identifier, owner: nil) as? AppCellView
        if cellView == nil {
            cellView = AppCellView()
            cellView?.identifier = identifier
        }

        guard row < apps.count, let cell = cellView else { return cellView }

        let app = apps[row]
        let displayName = app.displayName

        switch app {
        case .installedAppMetadata(_, let path, _, let desc):
            cell.titleField.stringValue = displayName
            cell.titleField.textColor = .labelColor
            var secondary: String? = nil
            if let p = path {
                secondary = p
            }
            if let d = desc, !d.isEmpty {
                let d1 = d.replacingOccurrences(of: "\n", with: " ")
                if let existing = secondary {
                    // Combine path and description
                    secondary = existing + " — " + d1
                } else {
                    secondary = d1
                }
            }
            if let sec = secondary, !sec.isEmpty {
                cell.descField.stringValue = sec
                cell.descField.textColor = .tertiaryLabelColor
                cell.descField.isHidden = false
            } else {
                cell.descField.isHidden = true
            }
            cell.configureForInstalled()
        case .availableCask(let cask):
            cell.titleField.stringValue = displayName + " (install)"
            cell.titleField.textColor = .secondaryLabelColor
            if let desc = cask.desc, !desc.isEmpty {
                let singleLine = desc.replacingOccurrences(of: "\n", with: " ")
                cell.descField.stringValue = singleLine
                cell.descField.isHidden = false
                cell.descField.textColor = .tertiaryLabelColor
            } else {
                cell.descField.isHidden = true
            }
            // Buttons
            cell.homepageButton.target = self
            cell.homepageButton.action = #selector(homepageButtonPressed(_:))
            cell.installButton.target = self
            cell.installButton.action = #selector(installButtonPressed(_:))
            cell.configureForCask(homepageAvailable: cask.homepage != nil, row: row)
        }

        return cell
    }

    // Dynamic row height to accommodate description for uninstalled apps
    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        guard row < apps.count else { return 24 }
        switch apps[row] {
        case .availableCask(let cask):
            if let desc = cask.desc, !desc.isEmpty { return 48 }
            return 32
        case .installedAppMetadata(_, let path, _, let desc):
            if (path != nil) || (desc != nil && !(desc?.isEmpty ?? true)) { return 40 }
            return 24
        }
    }
}

// MARK: - NSTextFieldDelegate
extension MainViewController: NSTextFieldDelegate {
    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        switch commandSelector {
        case #selector(NSResponder.moveDown(_:)): // Down arrow
            if apps.count > 0 {
                view.window?.makeFirstResponder(tableView)
                tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
                tableView.scrollRowToVisible(0)
            }
            return true
        case #selector(NSResponder.moveUp(_:)): // Up arrow
            if apps.count > 0 {
                let lastIndex = apps.count - 1
                view.window?.makeFirstResponder(tableView)
                tableView.selectRowIndexes(IndexSet(integer: lastIndex), byExtendingSelection: false)
                tableView.scrollRowToVisible(lastIndex)
            }
            return true
        case #selector(NSResponder.insertNewline(_:)): // Enter key
            let current = searchField.stringValue
            if openURLIfPossible(from: current) {
                return true
            }

            if apps.count > 0 {
                let selectedRow = tableView.selectedRow
                if selectedRow >= 0 && selectedRow < apps.count {
                    let app = apps[selectedRow]
                    if launchApplication(app) {
                        recordSuccessfulRun(using: app.displayName)
                    }
                }
            }
            return true
        default:
            return false
        }
    }

    func control(_ control: NSControl,
                 textView: NSTextView,
                 completions words: [String],
                 forPartialWordRange charRange: NSRange,
                 indexOfSelectedItem index: UnsafeMutablePointer<Int>?) -> [String] {
        let fullText = textView.string as NSString
        guard charRange.location != NSNotFound,
              NSMaxRange(charRange) <= fullText.length else {
            return []
        }
        let prefix = fullText.substring(with: charRange)
        let matches = commandHistory.completions(matching: prefix)
        if !matches.isEmpty {
            index?.pointee = 0
        }
        return matches
    }
}

// MARK: - TableViewNavigationDelegate
extension MainViewController: TableViewNavigationDelegate {
    func tableViewShouldReturnToSearchField(_ tableView: NSTableView) {
        view.window?.makeFirstResponder(searchField)
        // Position cursor at end of text
        if let fieldEditor = view.window?.fieldEditor(true, for: searchField) as? NSTextView {
            fieldEditor.selectedRange = NSRange(location: searchField.stringValue.count, length: 0)
        }
    }

    func tableViewShouldLaunchSelectedApp(_ tableView: NSTableView) {
        let selectedRow = tableView.selectedRow
        if selectedRow >= 0 && selectedRow < apps.count {
            let app = apps[selectedRow]
            if launchApplication(app) {
                recordSuccessfulRun(using: app.displayName)
            }
        }
    }
}
