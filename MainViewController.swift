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
        performSearch(sender.stringValue)
    }

    @objc private func textDidChange(_ notification: Notification) {
        guard let textField = notification.object as? NSTextField else { return }
        performSearch(textField.stringValue)
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
        launchApplication(app)
    }

    private func launchApplication(_ searchResult: SearchResult) {
        switch searchResult {
        case .installedApp(let item):
            launchInstalledApp(item)
        case .availableCask(let cask):
            installCask(cask)
        }
    }

    private func launchInstalledApp(_ item: NSMetadataItem) {
        guard let bundleId = item.value(forAttribute: kMDItemCFBundleIdentifier as String) as? String else {
            return
        }

        let workspace = NSWorkspace.shared
        workspace.launchApplication(withBundleIdentifier: bundleId, options: [], additionalEventParamDescriptor: nil, launchIdentifier: nil)
    }

    private func installCask(_ cask: CaskData.CaskItem) {
        // For now, just open the homepage or show info
        // You could implement actual Homebrew installation here
        if let homepage = cask.homepage, let url = URL(string: homepage) {
            NSWorkspace.shared.open(url)
        }
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

        var cellView = tableView.makeView(withIdentifier: identifier, owner: nil) as? NSTableCellView

        if cellView == nil {
            cellView = NSTableCellView()
            cellView?.identifier = identifier

            let textField = NSTextField()
            textField.isBordered = false
            textField.isEditable = false
            textField.backgroundColor = .clear
            textField.translatesAutoresizingMaskIntoConstraints = false

            cellView?.addSubview(textField)
            cellView?.textField = textField

            NSLayoutConstraint.activate([
                textField.leadingAnchor.constraint(equalTo: cellView!.leadingAnchor, constant: 4),
                textField.trailingAnchor.constraint(equalTo: cellView!.trailingAnchor, constant: -4),
                textField.centerYAnchor.constraint(equalTo: cellView!.centerYAnchor)
            ])
        }

        if row < apps.count {
            let app = apps[row]
            let displayName = app.displayName
            let suffix = app.isInstalled ? "" : " (install)"
            cellView?.textField?.stringValue = displayName + suffix

            // Style differently for installed vs available apps
            if app.isInstalled {
                cellView?.textField?.textColor = .labelColor
            } else {
                cellView?.textField?.textColor = .secondaryLabelColor
            }
        }

        return cellView
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
            if apps.count > 0 {
                let selectedRow = tableView.selectedRow
                if selectedRow >= 0 && selectedRow < apps.count {
                    let app = apps[selectedRow]
                    launchApplication(app)
                }
            }
            return true
        default:
            return false
        }
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
            launchApplication(app)
        }
    }
}
