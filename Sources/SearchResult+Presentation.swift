import Cocoa

extension SearchResult {
    func configureCell(_ cell: SearchResultCellView, controller: MainViewController, row: Int) {
        switch self {
        case .installedAppMetadata(let name, let path, _, let description):
            let title = decoratedTitle(for: name)
            var subtitle: String?

            if let path {
                subtitle = path
            }

            if let description, !description.isEmpty {
                let cleaned = description.replacingOccurrences(of: "\n", with: " ")
                if let existing = subtitle, !existing.isEmpty {
                    subtitle = existing + " — " + cleaned
                } else {
                    subtitle = cleaned
                }
            }

            cell.apply(title: title, titleColor: NSColor.white, subtitle: subtitle)
            cell.configureForInstalled()

        case .availableCask(let cask):
            let baseTitle = "\(cask.displayName) (install)"
            let title = decoratedTitle(for: baseTitle)

            var subtitle: String?
            if let desc = cask.desc, !desc.isEmpty {
                subtitle = desc.replacingOccurrences(of: "\n", with: " ")
            } else if let homepage = cask.homepage, !homepage.isEmpty {
                subtitle = homepage.replacingOccurrences(of: "\n", with: " ")
            }

            cell.apply(title: title, titleColor: NSColor.systemGreen.withAlphaComponent(0.85), subtitle: subtitle)
            cell.configureForCask(
                homepageAvailable: cask.homepage != nil,
                row: row,
                target: controller,
                homepageSelector: #selector(MainViewController.homepageButtonPressed(_:)),
                installSelector: #selector(MainViewController.installButtonPressed(_:))
            )

        case .historyCommand(let command, let display):
            cell.configureForHistory(command: command, display: display)
            let decorated = decoratedTitle(for: cell.titleField.stringValue)
            cell.titleField.stringValue = decorated

        case .url(let url):
            let title = decoratedTitle(for: url.absoluteString)
            var subtitle: String?
            if let host = url.host, !host.isEmpty {
                var components: [String] = []
                if let scheme = url.scheme?.uppercased(), !scheme.isEmpty {
                    components.append(scheme)
                }
                components.append(host)
                subtitle = components.joined(separator: " · ")
            } else if !url.path.isEmpty {
                subtitle = url.path
            }

            cell.apply(title: title, titleColor: NSColor.systemBlue, subtitle: subtitle)
            cell.configureForPlainText()

        case .filesystemEntry(let entry):
            let title = decoratedTitle(for: entry.displayName)
            let subtitle = entry.url.path
            let color: NSColor = entry.isDirectory ? NSColor.systemOrange : NSColor.white
            cell.apply(title: title, titleColor: color, subtitle: subtitle)
            cell.configureForPlainText()

        @unknown default:
            let title = decoratedTitle(for: displayName)
            cell.apply(title: title, titleColor: NSColor.white, subtitle: nil)
            cell.configureForInstalled()
        }
    }

    var preferredRowHeight: CGFloat {
        let subtitleHeight: CGFloat = 44
        let titleOnlyHeight: CGFloat = 40

        switch self {
        case .availableCask(let cask):
            if let desc = cask.desc, !desc.isEmpty { return subtitleHeight }
            if let homepage = cask.homepage, !homepage.isEmpty { return subtitleHeight }
            return titleOnlyHeight
        case .installedAppMetadata(_, let path, _, let description):
            if path != nil { return subtitleHeight }
            if let description, !description.isEmpty { return subtitleHeight }
            return titleOnlyHeight
        case .historyCommand:
            return subtitleHeight
        case .url(let url):
            if (url.host?.isEmpty ?? true) && url.path.isEmpty {
                return titleOnlyHeight
            }
            return subtitleHeight
        case .filesystemEntry:
            return subtitleHeight
        @unknown default:
            return titleOnlyHeight
        }
    }

    private func decoratedTitle(for base: String) -> String {
        #if DEBUG
        if let score = SearchConductor.shared.score(for: self) {
            return "\(base) [\(score)]"
        }
        #endif
        return base
    }

    @discardableResult
    func handlePrimaryAction(commandText: String, controller: MainViewController) -> Bool {
        switch self {
        case .installedAppMetadata(_, let path, let bundleID, _):
            guard controller.launchInstalledApp(bundleId: bundleID, path: path) else { return false }
            controller.recordSuccessfulRun(command: commandText, displayName: displayName)
            controller.resetSearchFieldAndResults()
            return true

        case .availableCask(let cask):
            guard controller.installCask(cask) else { return false }
            controller.recordSuccessfulRun(command: commandText, displayName: displayName)
            controller.resetSearchFieldAndResults()
            return true

        case .historyCommand(let command, let display):
            return controller.executeHistoryCommand(command, display: display)

        case .url(let url):
            return controller.openURL(url, originalInput: commandText)

        case .filesystemEntry(let entry):
            if entry.isDirectory {
                controller.drillDownIntoDirectory(entry.url)
                return true
            } else {
                guard controller.openFile(at: entry.url) else { return false }
                controller.recordSuccessfulRun(command: entry.url.path, displayName: entry.displayName)
                controller.resetSearchFieldAndResults()
                return true
            }

        @unknown default:
            return false
        }
    }
}
