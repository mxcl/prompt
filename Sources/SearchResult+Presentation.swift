import Cocoa

extension SearchResult {
    func configureCell(_ cell: SearchResultCellView, controller: MainViewController) {
        let hints = actionHints

        switch self {
        case .installedAppMetadata(let name, let path, _, let description, let cask):
            let title = decoratedTitle(for: name)
            let subtitle = SearchResult.subtitleForInstalledApp(path: path, description: description)
            cell.apply(title: title, titleColor: NSColor.white, subtitle: subtitle)
            cell.configureForInstalled()
            cell.setDeprecatedTagVisible(cask?.isDeprecated == true)

        case .availableCask(let cask):
            let baseTitle = cask.displayName
            let title = decoratedTitle(for: baseTitle)

            let subtitle = SearchResult.subtitleForCask(cask)

            cell.apply(title: title, titleColor: NSColor.systemGreen.withAlphaComponent(0.85), subtitle: subtitle)
            cell.configureForCask()
            cell.setDeprecatedTagVisible(cask.isDeprecated)

        case .historyCommand(let command, let display, let storedSubtitle, _, let isRecent):
            if let contextResult = historyContextResult {
                contextResult.configureCell(cell, controller: controller)
                cell.setRecentTagVisible(isRecent)
                return
            }
            let trimmedCommand = command.trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedDisplay = display?.trimmingCharacters(in: .whitespacesAndNewlines)
            let titleSource = (trimmedDisplay?.isEmpty == false) ? trimmedDisplay! : trimmedCommand
            let title = SearchResult.replacingHomeDirectoryPath(in: titleSource)
            let trimmedStoredSubtitle = storedSubtitle?.trimmingCharacters(in: .whitespacesAndNewlines)
            var subtitle: String?
            if let trimmedStoredSubtitle, !trimmedStoredSubtitle.isEmpty {
                subtitle = SearchResult.replacingHomeDirectoryPath(in: trimmedStoredSubtitle)
            } else if let trimmedDisplay, !trimmedDisplay.isEmpty,
                      !trimmedCommand.isEmpty,
                      trimmedDisplay.caseInsensitiveCompare(trimmedCommand) != .orderedSame {
                subtitle = SearchResult.replacingHomeDirectoryPath(in: trimmedCommand)
            }

            cell.apply(
                title: title,
                titleColor: NSColor.white,
                subtitle: subtitle,
                tooltip: trimmedCommand.isEmpty ? nil : SearchResult.replacingHomeDirectoryPath(in: trimmedCommand)
            )
            let useReducedFonts = controller.shouldUseReducedRecentFont(isRecentResult: isRecent)
            cell.configureForHistory(isRecent: isRecent, useReducedFonts: useReducedFonts)
            let decorated = decoratedTitle(for: cell.titleField.stringValue)
            cell.titleField.stringValue = decorated
            cell.setDeprecatedTagVisible(false)

        case .url(let url):
            let title = decoratedTitle(for: url.absoluteString)
            let subtitle = SearchResult.subtitleForURL(url)
            cell.apply(title: title, titleColor: NSColor.systemBlue, subtitle: subtitle)
            cell.configureForPlainText()
            cell.setDeprecatedTagVisible(false)

        case .filesystemEntry(let entry):
            let title = decoratedTitle(for: entry.displayName)
            let subtitle = SearchResult.subtitleForFilesystemEntry(entry)
            let color: NSColor = entry.isDirectory ? NSColor.systemOrange : NSColor.white
            cell.apply(title: title, titleColor: color, subtitle: subtitle, tooltip: entry.url.path)
            cell.configureForPlainText()
            cell.setDeprecatedTagVisible(false)

        @unknown default:
            let title = decoratedTitle(for: displayName)
            cell.apply(title: title, titleColor: NSColor.white, subtitle: nil)
            cell.configureForInstalled()
            cell.setDeprecatedTagVisible(false)
        }

        cell.setActionHints(hints)
    }

    var preferredRowHeight: CGFloat {
        let subtitleHeight: CGFloat = 44
        let titleOnlyHeight: CGFloat = 40

        switch self {
        case .availableCask(let cask):
            if let desc = cask.desc, !desc.isEmpty { return subtitleHeight }
            if let homepage = cask.homepage, !homepage.isEmpty { return subtitleHeight }
            return titleOnlyHeight
        case .installedAppMetadata(_, let path, _, let description, _):
            if path != nil { return subtitleHeight }
            if let description, !description.isEmpty { return subtitleHeight }
            return titleOnlyHeight
        case .historyCommand:
            if let contextual = historyContextResult {
                return contextual.preferredRowHeight
            }
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
            if let contextual = historyContextResult {
                return contextual.enterActionHint
            }
            return "Open"
        case .url:
            return "Open"
        case .filesystemEntry(let entry):
            return entry.isDirectory ? "Reveal in Finder" : "Open"
        @unknown default:
            return "Open"
        }
    }

    var actionHints: [SearchResultCellView.ActionHint] {
        switch self {
        case .installedAppMetadata:
            return [SearchResultCellView.ActionHint(keyGlyph: "⏎", text: enterActionHint)]
        case .availableCask:
            return [
                SearchResultCellView.ActionHint(keyGlyph: "⏎", text: "Homepage"),
                SearchResultCellView.ActionHint(keyGlyph: "⌥⏎", text: "Install")
            ]
        case .historyCommand:
            if let contextual = historyContextResult {
                return contextual.actionHints
            }
            return [SearchResultCellView.ActionHint(keyGlyph: "⏎", text: enterActionHint)]
        default:
            return [SearchResultCellView.ActionHint(keyGlyph: "⏎", text: enterActionHint)]
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
        case .installedAppMetadata(let name, let path, let bundleID, let appDescription, let cask):
            guard controller.launchInstalledApp(bundleId: bundleID, path: path) else { return false }
            let subtitle = SearchResult.subtitleForInstalledApp(path: path, description: appDescription)
            let context = CommandHistoryEntry.Context.installedApp(
                name: name,
                path: path,
                bundleID: bundleID,
                description: appDescription,
                caskToken: cask?.token
            )
            controller.recordSuccessfulRun(command: commandText, displayName: displayName, subtitle: subtitle, context: context)
            controller.resetSearchFieldAndResults()
            return true

        case .availableCask(let cask):
            guard controller.openCaskHomepage(cask) else { return false }
            let subtitle = SearchResult.subtitleForCask(cask)
            let context = CommandHistoryEntry.Context.availableCask(token: cask.token)
            controller.recordSuccessfulRun(command: commandText, displayName: displayName, subtitle: subtitle, context: context)
            controller.resetSearchFieldAndResults()
            return true

        case .historyCommand(let command, let display, _, _, _):
            if let contextual = historyContextResult {
                return contextual.handlePrimaryAction(commandText: command, controller: controller)
            }
            return controller.executeHistoryCommand(command, display: display)

        case .url(let url):
            return controller.openURL(url, originalInput: commandText)

        case .filesystemEntry(let entry):
            let subtitle = SearchResult.subtitleForFilesystemEntry(entry)
            if entry.isDirectory {
                guard controller.openDirectoryInFinder(entry.url) else { return false }
            } else {
                guard controller.openFile(at: entry.url) else { return false }
            }
            controller.recordSuccessfulRun(command: entry.url.path, displayName: entry.displayName, subtitle: subtitle)
            controller.resetSearchFieldAndResults()
            return true

        @unknown default:
            return false
        }
    }

    @discardableResult
    func handleAlternateAction(commandText: String, controller: MainViewController) -> Bool {
        switch self {
        case .installedAppMetadata(_, let path, _, _, _):
            if let path, !path.isEmpty {
                controller.revealInFinder(path: path)
                return true
            }
            return handlePrimaryAction(commandText: commandText, controller: controller)
        case .availableCask(let cask):
            guard let context = controller.installCask(cask) else { return false }
            let subtitle: String?
            let recordedName: String
            if case let .installedApp(name, path, _, description, _) = context {
                subtitle = SearchResult.subtitleForInstalledApp(path: path, description: description)
                recordedName = name
            } else {
                subtitle = SearchResult.subtitleForCask(cask)
                recordedName = displayName
            }
            controller.recordSuccessfulRun(command: commandText, displayName: recordedName, subtitle: subtitle, context: context)
            controller.resetSearchFieldAndResults()
            return true
        case .historyCommand(let command, let display, _, _, _):
            if let contextual = historyContextResult {
                return contextual.handleAlternateAction(commandText: command, controller: controller)
            }
            return controller.executeHistoryCommand(command, display: display)
        case .filesystemEntry(let entry):
            if entry.isDirectory {
                let subtitle = SearchResult.subtitleForFilesystemEntry(entry)
                if controller.openDirectoryInVSCode(entry.url) {
                    controller.recordSuccessfulRun(command: entry.url.path, displayName: entry.displayName, subtitle: subtitle)
                    controller.resetSearchFieldAndResults()
                    return true
                }
                guard controller.openDirectoryInFinder(entry.url) else { return false }
                controller.recordSuccessfulRun(command: entry.url.path, displayName: entry.displayName, subtitle: subtitle)
                controller.resetSearchFieldAndResults()
                return true
            }
            return handlePrimaryAction(commandText: commandText, controller: controller)
        default:
            return handlePrimaryAction(commandText: commandText, controller: controller)
        }
    }
}

extension SearchResult {
    static func subtitleForInstalledApp(path: String?, description: String?) -> String? {
        let sanitizedPath = sanitizedSubtitleComponent(path).map { replacingHomeDirectoryPath(in: $0) }
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

    private static var homeDirectoryPath: String {
        FileManager.default.homeDirectoryForCurrentUser.path
    }

    private static func replacingHomeDirectoryPath(in text: String) -> String {
        let homePath = homeDirectoryPath
        guard !homePath.isEmpty else { return text }
        return text.replacingOccurrences(of: homePath, with: "~")
    }
}
