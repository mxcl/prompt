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
        case 51: // Delete / backspace
            let row = self.selectedRow
            if row >= 0,
               navigationDelegate?.tableView(self, shouldDeleteRow: row) == true {
                return
            }
            navigationDelegate?.tableViewShouldReturnToSearchField(self)
            if let editor = window?.firstResponder as? NSTextView {
                editor.deleteBackward(nil)
            } else {
                NSApp.sendAction(#selector(NSText.deleteBackward(_:)), to: nil, from: self)
            }
            return
        case 117: // Forward delete
            let row = self.selectedRow
            if row >= 0,
               navigationDelegate?.tableView(self, shouldDeleteRow: row) == true {
                return
            }
            navigationDelegate?.tableViewShouldReturnToSearchField(self)
            if let editor = window?.firstResponder as? NSTextView {
                editor.deleteForward(nil)
            } else {
                NSApp.sendAction(#selector(NSText.deleteForward(_:)), to: nil, from: self)
            }
            return
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

class VibrantTextField: NSTextField {
    override var allowsVibrancy: Bool { true }
}

protocol TableViewNavigationDelegate: AnyObject {
    func tableViewShouldReturnToSearchField(_ tableView: NSTableView)
    func tableViewShouldLaunchSelectedApp(_ tableView: NSTableView)
    func tableView(_ tableView: NSTableView, shouldDeleteRow row: Int) -> Bool
}

class MainViewController: NSViewController {
    private var searchField: NSTextField!
    private var tableView: NavigableTableView!
    private var scrollView: NSScrollView!
    private var apps: [SearchResult] = []
    private let commandHistory = CommandHistory.shared
    private var isApplyingAutocomplete = false
    private let autocompleteSkipKeyCodes: Set<UInt16> = [51, 117] // delete, forward delete
    private var lastManualQuery: String = ""
    private var preferredHistoryCommand: String?
    private var suppressNextManualUpdate = false
    private var preferredHistoryQuery: String?
    private let isAutocompleteEnabled = false // Temporary toggle while debugging autocomplete behavior

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
            _ = installCask(cask)
        }
    }

    override func loadView() {
        let effectView = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        effectView.material = .hudWindow
        effectView.blendingMode = .withinWindow
        effectView.state = .active
        effectView.wantsLayer = true
        effectView.layer?.cornerRadius = 18
        effectView.layer?.masksToBounds = true
        if #available(macOS 11.0, *) {
            effectView.layer?.cornerCurve = .continuous
        }
        view = effectView
        setupUI()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupNotifications()
        performSearch("")
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
        searchField = NSTextField(frame: NSRect(x: 0, y: 0, width: 0, height: 0))
        searchField.target = self
        searchField.action = #selector(searchFieldChanged(_:))
        searchField.delegate = self
        searchField.isBordered = false
        searchField.isBezeled = false
        searchField.focusRingType = .none
        searchField.drawsBackground = false
        searchField.font = NSFont.systemFont(ofSize: 20, weight: .medium)
        searchField.wantsLayer = true
        searchField.layer?.cornerRadius = 12
        searchField.layer?.masksToBounds = true
        searchField.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.08).cgColor
        searchField.textColor = NSColor.white
        searchField.placeholderAttributedString = NSAttributedString(
            string: "Run",
            attributes: [
                .foregroundColor: NSColor.white.withAlphaComponent(0.45)
            ]
        )
        if let cell = searchField.cell as? NSTextFieldCell {
            cell.usesSingleLineMode = true
            cell.isScrollable = true
            cell.wraps = false
            cell.lineBreakMode = .byTruncatingTail
        }

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
        tableView.headerView = nil
        tableView.rowHeight = 52
        tableView.intercellSpacing = NSSize(width: 0, height: 8)
        tableView.backgroundColor = .clear
        tableView.selectionHighlightStyle = .regular
        tableView.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        tableView.allowsEmptySelection = false

        // Create table column
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("AppName"))
        column.title = ""
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)

        // Create scroll view
        scrollView = NSScrollView(frame: .zero)
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.contentInsets = NSEdgeInsets(top: 8, left: 0, bottom: 16, right: 0)
        view.addSubview(scrollView)

        // Setup Auto Layout
        setupConstraints()
    }

    private func setupConstraints() {
        searchField.translatesAutoresizingMaskIntoConstraints = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            // Search field constraints
            searchField.topAnchor.constraint(equalTo: view.topAnchor, constant: 24),
            searchField.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            searchField.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            searchField.heightAnchor.constraint(equalToConstant: 44),

            // Scroll view constraints - moved up to be against search field
            scrollView.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 16),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -24)
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
        let currentEvent = NSApp.currentEvent
        let isKeyDown = currentEvent?.type == .keyDown
        let fieldEditor = view.window?.fieldEditor(true, for: textField) as? NSTextView
        let typedText = fieldEditor?.string ?? textField.stringValue

        if isApplyingAutocomplete {
            performSearch(lastManualQuery)
            return
        }

        if isKeyDown && !suppressNextManualUpdate {
            lastManualQuery = typedText
        }
        suppressNextManualUpdate = false

        var skipAutocomplete = !isAutocompleteEnabled
        if isKeyDown, let event = currentEvent {
            if autocompleteSkipKeyCodes.contains(event.keyCode) {
                skipAutocomplete = true
            }
        } else if !isKeyDown {
            skipAutocomplete = true
        }

        var appliedCompletion = false
        preferredHistoryCommand = nil
        preferredHistoryQuery = nil
        if !skipAutocomplete {
            appliedCompletion = applyAutocompleteIfNeeded(for: textField, originalText: typedText)
            if appliedCompletion {
                preferredHistoryCommand = textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
                preferredHistoryQuery = lastManualQuery
                suppressNextManualUpdate = true
            }
        }

        performSearch(lastManualQuery)
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

    private func recordSuccessfulRun(command: String, displayName: String? = nil) {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        #if DEBUG
        if let displayName, !displayName.isEmpty {
            print("[CommandHistory] Recording command='\(trimmed)' display='\(displayName)'")
        } else {
            print("[CommandHistory] Recording command='\(trimmed)'")
        }
        #endif
        commandHistory.record(command: trimmed, display: displayName)
    }

    private func resetSearchFieldAndResults() {
        searchField.stringValue = ""
        lastManualQuery = ""
        preferredHistoryCommand = nil
        preferredHistoryQuery = nil
        suppressNextManualUpdate = false
        apps = []
        tableView.reloadData()
        focusAndSelectSearchField()
        performSearch("")
    }

    private func openURLIfPossible(from input: String) -> Bool {
        guard let url = resolvedURL(from: input) else { return false }
        let success = NSWorkspace.shared.open(url)
        if success {
            recordSuccessfulRun(command: input)
        }
        resetSearchFieldAndResults()
        return success
    }

    private func applyAutocompleteIfNeeded(for textField: NSTextField, originalText: String) -> Bool {
        guard let fieldEditor = view.window?.fieldEditor(true, for: textField) as? NSTextView else { return false }
        let currentText = originalText
        guard !currentText.isEmpty else { return false }

        let selection = fieldEditor.selectedRange
        guard selection.location == (fieldEditor.string as NSString).length, selection.length == 0 else { return false }

        guard let completion = commandHistory.bestCompletion(for: currentText),
              completion.count > currentText.count else { return false }
        if completion.lowercased() == currentText.lowercased() {
            return false
        }

        isApplyingAutocomplete = true
        defer { isApplyingAutocomplete = false }

        fieldEditor.string = completion
        textField.stringValue = completion
        let highlightRange = NSRange(location: currentText.count, length: completion.count - currentText.count)
        fieldEditor.setSelectedRange(highlightRange)
        return true
    }

    private func performSearch(_ searchText: String) {
        SearchConductor.shared.search(query: searchText) { [weak self] results in
            DispatchQueue.main.async {
                guard let self = self else { return }
                var finalResults = results
                if let preferred = self.preferredHistoryCommand?.lowercased(),
                   let preferredQuery = self.preferredHistoryQuery?.lowercased(),
                   preferredQuery == searchText.lowercased(),
                   let index = finalResults.firstIndex(where: {
                       if case .historyCommand(let cmd, _) = $0 {
                           return cmd.lowercased() == preferred
                       }
                       return false
                   }) {
                    let match = finalResults.remove(at: index)
                    finalResults.insert(match, at: 0)
                }

                self.apps = finalResults
                self.tableView.reloadData()

                // Always select the first item if there are results
                if finalResults.count > 0 {
                    self.tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
                }
            }
        }
    }

    @objc private func tableViewDoubleClicked(_ sender: NSTableView) {
        let row = sender.clickedRow
        guard row >= 0 && row < apps.count else { return }

        let app = apps[row]
        let commandText = searchField.stringValue
        if launchApplication(app) {
            if case .historyCommand = app {
                // already handled in executeHistoryCommand
            } else {
                recordSuccessfulRun(command: commandText, displayName: app.displayName)
                resetSearchFieldAndResults()
            }
        }
    }

    @discardableResult
    private func launchApplication(_ searchResult: SearchResult) -> Bool {
        switch searchResult {
        case .installedAppMetadata(_, let path, let bundleID, _):
            return launchInstalledApp(bundleId: bundleID, path: path)
        case .availableCask(let cask):
            return installCask(cask)
        case .historyCommand(let command, let display):
            return executeHistoryCommand(command, display: display)
        @unknown default:
            return false
        }
    }

    private func launchInstalledApp(bundleId: String?, path: String?) -> Bool {
        let workspace = NSWorkspace.shared

        if let bundleId = bundleId {
            #if DEBUG
            print("[Launch] Attempting bundle id \(bundleId)")
            #endif
            if let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).first {
                running.activate(options: [.activateIgnoringOtherApps])
                #if DEBUG
                print("[Launch] bundle id already running; activated")
                #endif
                return true
            }

            if #available(macOS 11.0, *) {
                if let appURL = workspace.urlForApplication(withBundleIdentifier: bundleId) {
                    let configuration = NSWorkspace.OpenConfiguration()
                    configuration.activates = true
                    workspace.openApplication(at: appURL, configuration: configuration) { runningApp, error in
                        #if DEBUG
                        if let error = error {
                            print("[Launch] bundle id launch failed with error: \(error.localizedDescription)")
                        } else if let launchedBundleId = runningApp?.bundleIdentifier {
                            print("[Launch] bundle id launch succeeded for \(launchedBundleId)")
                        } else {
                            print("[Launch] bundle id launch requested")
                        }
                        #endif
                    }
                    return true
                }
            } else if workspace.launchApplication(withBundleIdentifier: bundleId,
                                                  options: [],
                                                  additionalEventParamDescriptor: nil,
                                                  launchIdentifier: nil) {
                #if DEBUG
                print("[Launch] bundle id launch succeeded")
                #endif
                return true
            }
            #if DEBUG
            print("[Launch] bundle id launch failed; checking path")
            #endif
        }

        if let path = path {
            let url = URL(fileURLWithPath: path)
            #if DEBUG
            print("[Launch] Attempting path \(path)")
            #endif
            if workspace.open(url) {
                #if DEBUG
                print("[Launch] path open succeeded")
                #endif
                return true
            }
            #if DEBUG
            print("[Launch] path open failed")
            #endif
        }

        #if DEBUG
        print("[Launch] launch failed for bundleId=\(bundleId ?? "nil") path=\(path ?? "nil")")
        #endif
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

    private func executeHistoryCommand(_ command: String, display: String?) -> Bool {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        if openURLIfPossible(from: trimmed) {
            return true
        }

        searchField.stringValue = trimmed
        lastManualQuery = trimmed

        SearchConductor.shared.search(query: trimmed) { [weak self] results in
            guard let self = self else { return }

            DispatchQueue.main.async {
                self.apps = results
                self.tableView.reloadData()

                if let historyIndex = results.firstIndex(where: {
                    if case .historyCommand(let storedCommand, _) = $0 {
                        return storedCommand.caseInsensitiveCompare(trimmed) == .orderedSame
                    }
                    return false
                }) {
                    self.tableView.selectRowIndexes(IndexSet(integer: historyIndex), byExtendingSelection: false)
                    self.tableView.scrollRowToVisible(historyIndex)
                }

                func findTarget(for results: [SearchResult]) -> SearchResult? {
                    if let display = display?.trimmingCharacters(in: .whitespacesAndNewlines),
                       !display.isEmpty {
                        let loweredDisplay = display.lowercased()
                        if let match = results.first(where: {
                            !$0.isHistory && $0.displayName.lowercased() == loweredDisplay
                        }) {
                            return match
                        }
                    }

                    let loweredCommand = trimmed.lowercased()
                    if let commandMatch = results.first(where: {
                        !$0.isHistory && $0.displayName.lowercased() == loweredCommand
                    }) {
                        return commandMatch
                    }

                    return results.first(where: { !$0.isHistory })
                }

                guard let target = findTarget(for: results) else {
                    #if DEBUG
                    print("[HistoryCommand] No launchable target for '\(trimmed)'")
                    #endif
                    return
                }

                if target.isHistory {
                    #if DEBUG
                    print("[HistoryCommand] Target is history entry; aborting to prevent recursion")
                    #endif
                    return
                }

                if self.launchApplication(target) {
                    self.recordSuccessfulRun(command: trimmed, displayName: target.displayName)
                    self.resetSearchFieldAndResults()
                }
            }
        }

        return true
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
            let titleField = VibrantTextField()
            let descField = VibrantTextField()
            let homepageButton = NSButton(title: "Homepage", target: nil, action: nil)
            let installButton = NSButton(title: "Install", target: nil, action: nil)
            let buttonStack = NSStackView()
            private var trackingAdded = false
            private var isCask = false
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
                titleField.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
                titleField.textColor = NSColor.white.withAlphaComponent(0.92)
                titleField.maximumNumberOfLines = 1
                titleField.usesSingleLineMode = true
                descField.font = NSFont.systemFont(ofSize: 13)
                descField.textColor = NSColor.white.withAlphaComponent(0.6)

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
                setButtonsVisible(false)
                applySingleLineTitle()
            }
            func configureForCask(homepageAvailable: Bool, row: Int) {
                isCask = true
                setButtonsVisible(true)
                homepageButton.isHidden = !homepageAvailable
                installButton.isHidden = false
                homepageButton.tag = row
                installButton.tag = row
                setButtonBorders(visible: false)
                applySingleLineTitle()
            }

            func configureForHistory(command: String, display: String?) {
                isCask = false
                setButtonsVisible(false)
                enableMultilineTitle()
                let title = display?.isEmpty == false ? display! : command
                titleField.stringValue = title
                if display?.isEmpty == false && display != command {
                    titleField.toolTip = "Command: \(command)"
                } else {
                    titleField.toolTip = command
                }
                descField.stringValue = "Recent command"
                descField.textColor = NSColor.white.withAlphaComponent(0.55)
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
            cell.titleField.textColor = NSColor.white
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
                cell.descField.textColor = NSColor.white.withAlphaComponent(0.55)
                cell.descField.isHidden = false
            } else {
                cell.descField.isHidden = true
            }
            cell.configureForInstalled()
        case .availableCask(let cask):
            cell.titleField.stringValue = displayName + " (install)"
            cell.titleField.textColor = NSColor.systemGreen.withAlphaComponent(0.85)
            if let desc = cask.desc, !desc.isEmpty {
                let singleLine = desc.replacingOccurrences(of: "\n", with: " ")
                cell.descField.stringValue = singleLine
                cell.descField.isHidden = false
                cell.descField.textColor = NSColor.white.withAlphaComponent(0.55)
            } else if let homepage = cask.homepage, !homepage.isEmpty {
                let singleLine = homepage.replacingOccurrences(of: "\n", with: " ")
                cell.descField.stringValue = singleLine
                cell.descField.isHidden = false
                cell.descField.textColor = NSColor.white.withAlphaComponent(0.55)
            } else {
                cell.descField.isHidden = true
            }
            // Buttons
            cell.homepageButton.target = self
            cell.homepageButton.action = #selector(homepageButtonPressed(_:))
            cell.installButton.target = self
            cell.installButton.action = #selector(installButtonPressed(_:))
            cell.configureForCask(homepageAvailable: cask.homepage != nil, row: row)
        case .historyCommand(let command, let display):
            cell.titleField.textColor = NSColor.white
            cell.descField.isHidden = false
            cell.descField.textColor = NSColor.white.withAlphaComponent(0.55)
            cell.configureForHistory(command: command, display: display)
        @unknown default:
            cell.titleField.stringValue = displayName
            cell.descField.isHidden = true
            cell.configureForInstalled()
        }

        return cell
    }

    // Dynamic row height to accommodate description for uninstalled apps
    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        guard row < apps.count else { return 24 }
        switch apps[row] {
        case .availableCask(let cask):
            if let desc = cask.desc, !desc.isEmpty { return 48 }
            if let homepage = cask.homepage, !homepage.isEmpty { return 48 }
            return 32
        case .installedAppMetadata(_, let path, _, let desc):
            if (path != nil) || (desc != nil && !(desc?.isEmpty ?? true)) { return 40 }
            return 24
        case .historyCommand:
            return 48
        @unknown default:
            return 32
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
                    let commandText = searchField.stringValue
                    if launchApplication(app) {
                        if case .historyCommand = app {
                            // handled within executeHistoryCommand
                        } else {
                            recordSuccessfulRun(command: commandText, displayName: app.displayName)
                            resetSearchFieldAndResults()
                        }
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
                 indexOfSelectedItem index: UnsafeMutablePointer<Int>) -> [String] {
        let fullText = textView.string as NSString
        guard charRange.location != NSNotFound,
              NSMaxRange(charRange) <= fullText.length else {
            return []
        }
        let prefix = fullText.substring(with: charRange)
        let matches = commandHistory.completions(matching: prefix)
        index.pointee = matches.isEmpty ? NSNotFound : 0
        return matches
    }
}

// MARK: - TableViewNavigationDelegate
extension MainViewController: TableViewNavigationDelegate {
    func tableView(_ tableView: NSTableView, shouldDeleteRow row: Int) -> Bool {
        guard row >= 0 && row < apps.count else { return false }
        guard case .historyCommand(let command, _) = apps[row] else { return false }

        let removed = commandHistory.remove(command: command)
        guard removed else { return false }

        apps.remove(at: row)
        tableView.removeRows(at: IndexSet(integer: row), withAnimation: .effectFade)

        if apps.isEmpty {
            tableView.deselectAll(nil)
            focusAndSelectSearchField()
        } else {
            let nextIndex = min(row, apps.count - 1)
            tableView.selectRowIndexes(IndexSet(integer: nextIndex), byExtendingSelection: false)
            tableView.scrollRowToVisible(nextIndex)
        }

        // Re-run search to ensure fresh results from providers.
        performSearch(searchField.stringValue)
        return true
    }

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
                if case .historyCommand = app {
                    // handled within executeHistoryCommand
                } else {
                    let commandText = searchField.stringValue
                    recordSuccessfulRun(command: commandText, displayName: app.displayName)
                    resetSearchFieldAndResults()
                }
            }
        }
    }
}
