import Cocoa

class MainViewController: NSViewController {
    private var searchField: NSTextField!
    private var tableView: NSTableView!
    private var scrollView: NSScrollView!
    private var apps: [NSMetadataItem] = []

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        setupUI()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.wantsLayer = true
    }

    private func setupUI() {
        // Create search field
        searchField = NSTextField(frame: NSRect(x: 20, y: 350, width: 560, height: 24))
        searchField.placeholderString = "Run"
        searchField.target = self
        searchField.action = #selector(searchFieldChanged(_:))

        // Add continuous text change monitoring
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(textDidChange(_:)),
            name: NSControl.textDidChangeNotification,
            object: searchField
        )

        view.addSubview(searchField)

        // Create table view
        tableView = NSTableView()
        tableView.delegate = self
        tableView.dataSource = self
        tableView.target = self
        tableView.doubleAction = #selector(tableViewDoubleClicked(_:))

        // Create table column
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("AppName"))
        column.title = "Applications"
        column.width = 560
        tableView.addTableColumn(column)

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

            // Scroll view constraints
            scrollView.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 10),
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
        print("Searching for: '\(searchText)'")

        guard !searchText.isEmpty else {
            apps = []
            tableView.reloadData()
            return
        }

        searchApplications(queryString: searchText) { [weak self] results in
            DispatchQueue.main.async {
                print("Found \(results.count) apps")
                self?.apps = results
                self?.tableView.reloadData()
            }
        }
    }

    @objc private func tableViewDoubleClicked(_ sender: NSTableView) {
        let row = sender.clickedRow
        guard row >= 0 && row < apps.count else { return }

        let app = apps[row]
        launchApplication(app)
    }

    private func launchApplication(_ item: NSMetadataItem) {
        guard let bundleId = item.value(forAttribute: kMDItemCFBundleIdentifier as String) as? String else {
            print("No bundle identifier found")
            return
        }

        let workspace = NSWorkspace.shared
        workspace.launchApplication(withBundleIdentifier: bundleId, options: [], additionalEventParamDescriptor: nil, launchIdentifier: nil)
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
            cellView?.textField?.stringValue = app.value(forAttribute: kMDItemDisplayName as String) as? String ?? "Unknown App"
        }

        return cellView
    }
}
