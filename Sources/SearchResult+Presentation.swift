import Cocoa

extension SearchResult {
    func configureCell(_ cell: SearchResultCellView, controller: MainViewController) {
        let actionHint = enterActionHint

        switch self {
        case .installedAppMetadata(let name, let path, _, let description):
            let title = decoratedTitle(for: name)
            let subtitle = SearchResult.subtitleForInstalledApp(path: path, description: description)
            cell.apply(title: title, titleColor: NSColor.white, subtitle: subtitle)
            cell.configureForInstalled()

        case .availableCask(let cask):
            let baseTitle = "\(cask.displayName) (install)"
            let title = decoratedTitle(for: baseTitle)

            let subtitle = SearchResult.subtitleForCask(cask)

            cell.apply(title: title, titleColor: NSColor.systemGreen.withAlphaComponent(0.85), subtitle: subtitle)
            cell.configureForCask()

        case .historyCommand(let command, let display, let storedSubtitle, let isRecent):
            let trimmedCommand = command.trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedDisplay = display?.trimmingCharacters(in: .whitespacesAndNewlines)
            let title = (trimmedDisplay?.isEmpty == false) ? trimmedDisplay! : trimmedCommand
            let trimmedStoredSubtitle = storedSubtitle?.trimmingCharacters(in: .whitespacesAndNewlines)
            var subtitle: String?
            if let trimmedStoredSubtitle, !trimmedStoredSubtitle.isEmpty {
                subtitle = trimmedStoredSubtitle
            } else if let trimmedDisplay, !trimmedDisplay.isEmpty,
                      !trimmedCommand.isEmpty,
                      trimmedDisplay.caseInsensitiveCompare(trimmedCommand) != .orderedSame {
                subtitle = trimmedCommand
            }

            cell.apply(
                title: title,
                titleColor: NSColor.white,
                subtitle: subtitle,
                tooltip: trimmedCommand.isEmpty ? nil : trimmedCommand
            )
            let useReducedFonts = controller.shouldUseReducedRecentFont(isRecentResult: isRecent)
            cell.configureForHistory(isRecent: isRecent, useReducedFonts: useReducedFonts)
            let decorated = decoratedTitle(for: cell.titleField.stringValue)
            cell.titleField.stringValue = decorated

        case .url(let url):
            let title = decoratedTitle(for: url.absoluteString)
            let subtitle = SearchResult.subtitleForURL(url)
            cell.apply(title: title, titleColor: NSColor.systemBlue, subtitle: subtitle)
            cell.configureForPlainText()

        case .filesystemEntry(let entry):
            let title = decoratedTitle(for: entry.displayName)
            let subtitle = SearchResult.subtitleForFilesystemEntry(entry)
            let color: NSColor = entry.isDirectory ? NSColor.systemOrange : NSColor.white
            cell.apply(title: title, titleColor: color, subtitle: subtitle, tooltip: entry.url.path)
            cell.configureForPlainText()

        @unknown default:
            let title = decoratedTitle(for: displayName)
            cell.apply(title: title, titleColor: NSColor.white, subtitle: nil)
            cell.configureForInstalled()
        }

        cell.setActionHint(actionHint)
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
        case .url:
            return subtitleHeight
        case .filesystemEntry:
            return subtitleHeight
        @unknown default:
            return titleOnlyHeight
        }
    }

    var enterActionHint: String {
        switch self {
        case .installedAppMetadata:
            return "Open"
        case .availableCask:
            return "Homepage"
        case .historyCommand:
            return "Open"
        case .url:
            return "Open"
        case .filesystemEntry(let entry):
            return entry.isDirectory ? "Activate" : "Open"
        @unknown default:
            return "Open"
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
        case .installedAppMetadata(_, let path, let bundleID, let appDescription):
            guard controller.launchInstalledApp(bundleId: bundleID, path: path) else { return false }
            let subtitle = SearchResult.subtitleForInstalledApp(path: path, description: appDescription)
            controller.recordSuccessfulRun(command: commandText, displayName: displayName, subtitle: subtitle)
            controller.resetSearchFieldAndResults()
            return true

        case .availableCask(let cask):
            guard controller.installCask(cask) else { return false }
            let subtitle = SearchResult.subtitleForCask(cask)
            controller.recordSuccessfulRun(command: commandText, displayName: displayName, subtitle: subtitle)
            controller.resetSearchFieldAndResults()
            return true

        case .historyCommand(let command, let display, _, _):
            return controller.executeHistoryCommand(command, display: display)

        case .url(let url):
            return controller.openURL(url, originalInput: commandText)

        case .filesystemEntry(let entry):
            if entry.isDirectory {
                controller.drillDownIntoDirectory(entry.url)
                return true
            } else {
                guard controller.openFile(at: entry.url) else { return false }
                let subtitle = SearchResult.subtitleForFilesystemEntry(entry)
                controller.recordSuccessfulRun(command: entry.url.path, displayName: entry.displayName, subtitle: subtitle)
                controller.resetSearchFieldAndResults()
                return true
            }

        @unknown default:
            return false
        }
    }
}

extension SearchResult {
    static func subtitleForInstalledApp(path: String?, description: String?) -> String? {
        let sanitizedPath = sanitizedSubtitleComponent(path)
        let sanitizedDescription = sanitizedSubtitleComponent(description)

        switch (sanitizedPath, sanitizedDescription) {
        case let (path?, description?):
            return "\(path) — \(description)"
        case let (path?, nil):
            return path
        case let (nil, description?):
            return description
        case (nil, nil):
            return nil
        }
    }

    static func subtitleForCask(_ cask: CaskData.CaskItem) -> String? {
        if let desc = sanitizedSubtitleComponent(cask.desc) {
            return desc
        }
        if let homepage = sanitizedSubtitleComponent(cask.homepage) {
            return homepage
        }
        return nil
    }

    static func subtitleForURL(_ url: URL) -> String? {
        return "Opens in default browser"
    }

    static func subtitleForFilesystemEntry(_ entry: FileSystemEntry) -> String? {
        return "Opens in Finder"
    }

    static func sanitizedSubtitleComponent(_ text: String?) -> String? {
        guard let text = text else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return trimmed.replacingOccurrences(of: "\n", with: " ")
    }
}
