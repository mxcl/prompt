import Cocoa

// Custom table view that can navigate back to search field
class NavigableTableView: NSTableView {
    weak var navigationDelegate: TableViewNavigationDelegate?

    override func becomeFirstResponder() -> Bool {
        let didBecome = super.becomeFirstResponder()
        if didBecome {
            refreshVisibleActionHints()
        }
        return didBecome
    }

    override func resignFirstResponder() -> Bool {
        let didResign = super.resignFirstResponder()
        if didResign {
            refreshVisibleActionHints()
        }
        return didResign
    }

    func refreshVisibleActionHints() {
        let visibleRange = rows(in: visibleRect)
        guard visibleRange.location != NSNotFound, visibleRange.length > 0 else { return }

        let endIndex = visibleRange.location + visibleRange.length
        for row in visibleRange.location..<endIndex where row >= 0 && row < numberOfRows {
            if let cell = view(atColumn: 0, row: row, makeIfNecessary: false) as? SearchResultCellView {
                cell.refreshActionHintVisibility()
            }
        }
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 126: // Up arrow
            let selectedRow = self.selectedRow
            if selectedRow == 0 {
                // At first item, go back to search field
                navigationDelegate?.tableViewShouldReturnToSearchField(self)
                return
            }
        case 125: // Down arrow
            let lastRowIndex = numberOfRows - 1
            if lastRowIndex >= 0, self.selectedRow == lastRowIndex {
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
            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let navigationModifiers: NSEvent.ModifierFlags = [.command, .control, .option, .function]
            if modifiers.isDisjoint(with: navigationModifiers) {
                navigationDelegate?.tableViewShouldReturnToSearchField(self)
                if let responder = window?.firstResponder, responder !== self {
                    responder.keyDown(with: event)
                }
                return
            }
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
    private var searchContainer: NSView!
    private var apps: [SearchResult] = []
    private let commandHistory = CommandHistory.shared
    private var isApplyingAutocomplete = false
    private let autocompleteSkipKeyCodes: Set<UInt16> = [51, 117] // delete, forward delete
    private var lastManualQuery: String = ""
    private var preferredHistoryCommand: String?
    private var suppressNextManualUpdate = false
    private var preferredHistoryQuery: String?
    private let isAutocompleteEnabled = false // Temporary toggle while debugging autocomplete behavior

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
        // Container for search field to maintain consistent insets regardless of focus state
        searchContainer = NSView(frame: .zero)
        searchContainer.translatesAutoresizingMaskIntoConstraints = false
        searchContainer.wantsLayer = true
        searchContainer.layer?.backgroundColor = NSColor.clear.cgColor
        view.addSubview(searchContainer)

        // Create search field
        searchField = NSTextField(frame: NSRect(x: 0, y: 0, width: 0, height: 0))
        searchField.target = self
        searchField.action = #selector(searchFieldChanged(_:))
        searchField.delegate = self
        searchField.isBordered = false
        searchField.isBezeled = false
        searchField.focusRingType = .none
        searchField.drawsBackground = false
        searchField.font = NSFont.systemFont(ofSize: 24, weight: .semibold)
        searchField.isEditable = true
        searchField.isSelectable = true
        searchField.textColor = NSColor.white
        searchField.placeholderAttributedString = NSAttributedString(
            string: "Run",
            attributes: [
                .foregroundColor: NSColor.white.withAlphaComponent(0.55),
                .font: NSFont.systemFont(ofSize: 24, weight: .semibold)
            ]
        )
        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchContainer.addSubview(searchField)

        // Add continuous text change monitoring
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(textDidChange(_:)),
            name: NSControl.textDidChangeNotification,
            object: searchField
        )

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
        scrollView.contentInsets = NSEdgeInsets(top: 4, left: 0, bottom: 12, right: 0)
        view.addSubview(scrollView)

        // Setup Auto Layout
        setupConstraints()
    }

    private func setupConstraints() {
        searchContainer.translatesAutoresizingMaskIntoConstraints = false
        searchField.translatesAutoresizingMaskIntoConstraints = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            // Search field container constraints
            searchContainer.topAnchor.constraint(equalTo: view.topAnchor, constant: 12),
            searchContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            searchContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            searchContainer.heightAnchor.constraint(equalToConstant: 44),

            searchField.leadingAnchor.constraint(equalTo: searchContainer.leadingAnchor, constant: 18),
            searchField.trailingAnchor.constraint(equalTo: searchContainer.trailingAnchor, constant: -18),
            searchField.centerYAnchor.constraint(equalTo: searchContainer.centerYAnchor),
            searchField.heightAnchor.constraint(equalToConstant: 26),

            // Scroll view constraints - moved up to be against search field
            scrollView.topAnchor.constraint(equalTo: searchContainer.bottomAnchor, constant: 12),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -12)
        ])
    }

    @objc private func searchFieldChanged(_ sender: NSTextField) {
        let current = sender.stringValue
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

    func recordSuccessfulRun(command: String, displayName: String? = nil, subtitle: String? = nil) {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        #if DEBUG
        if let displayName, !displayName.isEmpty {
            print("[CommandHistory] Recording command='\(trimmed)' display='\(displayName)'")
        } else {
            print("[CommandHistory] Recording command='\(trimmed)'")
        }
        #endif
        commandHistory.record(command: trimmed, display: displayName, subtitle: subtitle)
    }

    func shouldUseReducedRecentFont(isRecentResult: Bool) -> Bool {
        guard isRecentResult else { return false }
        let trimmedQuery = searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedQuery.isEmpty
    }

    func resetSearchFieldAndResults() {
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
        return openURL(url, originalInput: input)
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
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)

        if let filesystemResults = directoryListingResults(for: trimmed) {
            applyResults(filesystemResults)
            return
        }

        SearchConductor.shared.search(query: searchText) { [weak self] results in
            DispatchQueue.main.async {
                guard let self = self else { return }
                var finalResults = results
                if let preferred = self.preferredHistoryCommand?.lowercased(),
                   let preferredQuery = self.preferredHistoryQuery?.lowercased(),
                   preferredQuery == searchText.lowercased(),
                   let index = finalResults.firstIndex(where: {
                       if case .historyCommand(let cmd, _, _, _) = $0 {
                           return cmd.lowercased() == preferred
                       }
                       return false
                   }) {
                    let match = finalResults.remove(at: index)
                    finalResults.insert(match, at: 0)
                }

                if let urlResult = self.urlResult(for: searchText) {
                    let alreadyPresent = finalResults.contains { $0.identifierHash == urlResult.identifierHash }
                    if !alreadyPresent {
                        finalResults.insert(urlResult, at: 0)
                    }
                }

                self.applyResults(finalResults)
            }
        }
    }

    private func applyResults(_ results: [SearchResult]) {
        apps = results
        tableView.reloadData()

        if results.isEmpty {
            tableView.deselectAll(nil)
        } else {
            tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
            tableView.scrollRowToVisible(0)
        }

        DispatchQueue.main.async { [weak self] in
            self?.tableView.refreshVisibleActionHints()
        }
    }

    private func urlResult(for input: String) -> SearchResult? {
        guard let url = resolvedURL(from: input) else { return nil }
        return .url(url)
    }

    private func directoryListingResults(for input: String) -> [SearchResult]? {
        guard !input.isEmpty, looksLikePath(input) else { return nil }

        let expanded = (input as NSString).expandingTildeInPath
        let standardized = (expanded as NSString).standardizingPath
        let fileManager = FileManager.default
        var isDir: ObjCBool = false

        if fileManager.fileExists(atPath: standardized, isDirectory: &isDir) {
            let url = URL(fileURLWithPath: standardized, isDirectory: isDir.boolValue)
            if isDir.boolValue {
                return contentsOfDirectory(at: url, filter: nil)
            } else {
                return [.filesystemEntry(FileSystemEntry(url: url, isDirectory: false))]
            }
        }

        if standardized.hasSuffix("/") {
            let directoryURL = URL(fileURLWithPath: standardized)
            if fileManager.fileExists(atPath: directoryURL.path, isDirectory: &isDir), isDir.boolValue {
                return contentsOfDirectory(at: directoryURL, filter: nil)
            }
        }

        let candidateURL = URL(fileURLWithPath: standardized)
        let parentURL = candidateURL.deletingLastPathComponent()
        let prefix = candidateURL.lastPathComponent

        guard !prefix.isEmpty else { return nil }

        if fileManager.fileExists(atPath: parentURL.path, isDirectory: &isDir), isDir.boolValue {
            return contentsOfDirectory(at: parentURL, filter: prefix)
        }

        return nil
    }

    private func contentsOfDirectory(at directoryURL: URL, filter: String?) -> [SearchResult] {
        let fileManager = FileManager.default
        let resourceKeys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey, .isPackageKey]
        let options: FileManager.DirectoryEnumerationOptions = [.skipsHiddenFiles]

        let keySet = Set(resourceKeys)

        guard let urls = try? fileManager.contentsOfDirectory(at: directoryURL, includingPropertiesForKeys: resourceKeys, options: options) else {
            return []
        }

        let lowercaseFilter = filter?.lowercased()
        let entries: [FileSystemEntry] = urls.compactMap { url in
            if let lowercaseFilter, !lowercaseFilter.isEmpty {
                if !url.lastPathComponent.lowercased().hasPrefix(lowercaseFilter) {
                    return nil
                }
            }

            let values = try? url.resourceValues(forKeys: keySet)
            let isDirectoryValue = values?.isDirectory ?? url.hasDirectoryPath
            let isPackage = values?.isPackage ?? false
            let isDirectory = isDirectoryValue && !isPackage
            return FileSystemEntry(url: url, isDirectory: isDirectory)
        }

        let sorted = entries.sorted { lhs, rhs in
            if lhs.isDirectory != rhs.isDirectory {
                return lhs.isDirectory && !rhs.isDirectory
            }
            return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
        }

        return sorted.map { SearchResult.filesystemEntry($0) }
    }

    private func looksLikePath(_ input: String) -> Bool {
        if input.isEmpty { return false }
        if input.contains("://") { return false }
        if input.hasPrefix("/") || input.hasPrefix("~") { return true }
        if input.hasPrefix(".") { return true }
        if let colonRange = input.range(of: ":") {
            let prefix = input[..<colonRange.lowerBound]
            if prefix.allSatisfy({ $0.isLetter }) {
                return false
            }
        }
        if input.contains("/") { return true }
        return false
    }

    @discardableResult
    func openURL(_ url: URL, originalInput: String) -> Bool {
        let success = NSWorkspace.shared.open(url)
        if success {
            let subtitle = SearchResult.subtitleForURL(url)
            recordSuccessfulRun(command: originalInput, displayName: url.absoluteString, subtitle: subtitle)
            resetSearchFieldAndResults()
        }
        return success
    }

    @discardableResult
    func openFile(at url: URL) -> Bool {
        return NSWorkspace.shared.open(url)
    }

    func drillDownIntoDirectory(_ url: URL) {
        var path = url.path
        if !path.hasSuffix("/") {
            path.append("/")
        }

        suppressNextManualUpdate = true
        searchField.stringValue = path
        lastManualQuery = path
        preferredHistoryCommand = nil
        preferredHistoryQuery = nil

        performSearch(path)

        if let window = view.window {
            window.makeFirstResponder(searchField)
            if let editor = window.fieldEditor(true, for: searchField) as? NSTextView {
                editor.selectedRange = NSRange(location: path.count, length: 0)
            }
        }
    }

    @objc private func tableViewDoubleClicked(_ sender: NSTableView) {
        let row = sender.clickedRow
        guard row >= 0 && row < apps.count else { return }

        let app = apps[row]
        let commandText = searchField.stringValue
        _ = app.handlePrimaryAction(commandText: commandText, controller: self)
    }

    func launchInstalledApp(bundleId: String?, path: String?) -> Bool {
        let workspace = NSWorkspace.shared

        if #available(macOS 11.0, *) {
            // Use Launch Services reopen semantics so running apps behave like Spotlight
            func openApplication(at appURL: URL) -> Bool {
                let configuration = NSWorkspace.OpenConfiguration()
                configuration.activates = true
                configuration.addsToRecentItems = false
                workspace.openApplication(at: appURL, configuration: configuration) { runningApp, error in
                    #if DEBUG
                    if let error = error {
                        print("[Launch] openApplication failed: \(error.localizedDescription)")
                    } else if let launchedBundleId = runningApp?.bundleIdentifier {
                        print("[Launch] openApplication succeeded for \(launchedBundleId)")
                    } else {
                        print("[Launch] openApplication requested launch")
                    }
                    #endif
                }
                return true
            }

            if let bundleId = bundleId {
                #if DEBUG
                print("[Launch] Attempting bundle id \(bundleId)")
                #endif
                if let appURL = workspace.urlForApplication(withBundleIdentifier: bundleId) {
                    return openApplication(at: appURL)
                }

                if let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).first {
                    running.activate(options: [.activateIgnoringOtherApps, .activateAllWindows])
                    #if DEBUG
                    print("[Launch] bundle id running; activated existing instance")
                    #endif
                    return true
                }

                #if DEBUG
                print("[Launch] bundle id lookup failed; checking path")
                #endif
            }

            if let path = path {
                let appURL = URL(fileURLWithPath: path)
                #if DEBUG
                print("[Launch] Attempting path \(appURL.path)")
                #endif
                return openApplication(at: appURL)
            }

            #if DEBUG
            print("[Launch] launch failed for bundleId=\(bundleId ?? "nil") path=\(path ?? "nil")")
            #endif
            return false
        }

        if let bundleId = bundleId {
            #if DEBUG
            print("[Launch] Attempting bundle id \(bundleId)")
            #endif
            if workspace.launchApplication(withBundleIdentifier: bundleId,
                                           options: [],
                                           additionalEventParamDescriptor: nil,
                                           launchIdentifier: nil) {
                #if DEBUG
                print("[Launch] legacy bundle id launch succeeded")
                #endif
                return true
            }
            #if DEBUG
            print("[Launch] legacy bundle id launch failed; checking path")
            #endif
        }

        if let path = path {
            #if DEBUG
            print("[Launch] Attempting path \(path)")
            #endif
            if workspace.launchApplication(path) {
                #if DEBUG
                print("[Launch] legacy path launch succeeded")
                #endif
                return true
            }
            #if DEBUG
            print("[Launch] legacy path launch failed")
            #endif
        }

        #if DEBUG
        print("[Launch] launch failed for bundleId=\(bundleId ?? "nil") path=\(path ?? "nil")")
        #endif
        return false
    }

    func installCask(_ cask: CaskData.CaskItem) -> Bool {
        // For now, just open the homepage or show info
        // You could implement actual Homebrew installation here
        if let homepage = cask.homepage, let url = URL(string: homepage) {
            return NSWorkspace.shared.open(url)
        }
        return false
    }

    func executeHistoryCommand(_ command: String, display: String?) -> Bool {
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
                    if case .historyCommand(let storedCommand, _, _, _) = $0 {
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

                _ = target.handlePrimaryAction(commandText: trimmed, controller: self)
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
        guard row < apps.count else { return nil }

        let identifier = SearchResultCellView.reuseIdentifier
        let cell = (tableView.makeView(withIdentifier: identifier, owner: self) as? SearchResultCellView) ?? SearchResultCellView()
        cell.identifier = identifier

        apps[row].configureCell(cell, controller: self)
        return cell
    }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        guard row < apps.count else { return 24 }
        return apps[row].preferredRowHeight
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard let tableView = notification.object as? NavigableTableView,
              tableView === self.tableView else { return }
        tableView.refreshVisibleActionHints()
    }
}

// MARK: - NSTextFieldDelegate
extension MainViewController: NSTextFieldDelegate {
    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        switch commandSelector {
        case #selector(NSResponder.moveDown(_:)): // Down arrow
            if apps.count > 0 {
                if tableView.selectedRow != 0 {
                    tableView.scrollRowToVisible(0)
                    tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
                    view.window?.makeFirstResponder(tableView)
                } else {
                    view.window?.makeFirstResponder(tableView)
                    if let event = NSApp.currentEvent, event.type == .keyDown {
                        tableView.keyDown(with: event)
                    } else {
                        tableView.moveDown(nil)
                    }
                }
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
                    _ = app.handlePrimaryAction(commandText: commandText, controller: self)
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
        guard case .historyCommand(let command, _, _, _) = apps[row] else { return false }

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
            let commandText = searchField.stringValue
            _ = app.handlePrimaryAction(commandText: commandText, controller: self)
        }
    }
}
