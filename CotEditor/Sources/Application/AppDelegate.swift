//
//  AppDelegate.swift
//
//  CotEditor
//  https://coteditor.com
//
//  Created by nakamuxu on 2004-12-13.
//
//  ---------------------------------------------------------------------------
//
//  © 2004-2007 nakamuxu
//  © 2013-2026 1024jp
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  https://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

import AppKit
import SwiftUI
import Combine
import OSLog
import UniformTypeIdentifiers
import ControlUI
import Defaults
import FileEncoding
import LineEnding
import StringUtils

@available(macOS, deprecated: 26)
let isLiquidGlass = if #available(macOS 26, *) { true } else { false }


extension Logger {
    
    static let app = Logger(subsystem: "com.coteditor.CotEditor", category: "application")
}


@MainActor @objc protocol EncodingChanging: AnyObject {
    
    func changeEncoding(_ sender: NSMenuItem)
}


@MainActor @objc protocol ThemeChanging: AnyObject {
    
    func changeTheme(_ sender: NSMenuItem)
}


@MainActor @objc protocol SyntaxChanging: AnyObject {
    
    func changeSyntax(_ sender: NSMenuItem)
    func recolorAll(_ sender: Any?)
}


@MainActor @objc protocol TextSizeChanging: AnyObject {
    
    func biggerFont(_ sender: Any?)
    func smallerFont(_ sender: Any?)
    func resetFont(_ sender: Any?)
}


@main
@MainActor final class AppDelegate: NSObject, NSApplicationDelegate, NSUserInterfaceValidations {
    
    // MARK: Enums
    
    private enum AppWebURL: String {
        
        case website = "https://coteditor.com"
        case issueTracker = "https://github.com/coteditor/CotEditor/issues"
        
        var url: URL  { URL(string: self.rawValue)! }
    }
    
    
    private enum BundleIdentifier {
        
        static let scriptEditor = "com.apple.ScriptEditor2"
    }
    
    
    // MARK: Public Properties
    
    var needsRelaunch = false
    
    
    // MARK: Private Properties
    
    private var isSettingsImporterPresented = false
    
    private var menuUpdateObservers: Set<AnyCancellable> = []
    
    private lazy var settingsWindowController = SettingsWindowController<SettingsPane>()
    private weak var aboutPanel: NSPanel?
    private weak var whatsNewPanel: NSPanel?
    private weak var exportSettingsPanel: NSPanel?
    
    @IBOutlet private weak var encodingsMenu: NSMenu?
    @IBOutlet private weak var syntaxesMenu: NSMenu?
    @IBOutlet private weak var lineEndingsMenu: NSMenu?
    @IBOutlet private weak var themesMenu: NSMenu?
    @IBOutlet private weak var normalizationMenu: NSMenu?
    @IBOutlet private weak var snippetMenu: NSMenu?
    @IBOutlet private weak var multipleReplaceMenu: NSMenu?
    @IBOutlet private weak var scriptMenu: NSMenu?
    private var weeklyReportsMenu: NSMenu?
    
    
    // MARK: Lifecycle
    
    override init() {
        
        // register default setting values
        let defaults = DefaultSettings.defaults
            .compactMapValues(\.self)
            .mapKeys(\.rawValue)
        UserDefaults.standard.register(defaults: defaults)
        NSUserDefaultsController.shared.initialValues = defaults
    }
    
    
    // MARK: Application Delegate
    
    func applicationWillFinishLaunching(_ notification: Notification) {
        
        // The app used to be sandboxed; pull the old settings out of the container first,
        // so everything else here already sees the migrated values.
        LegacyContainerMigrator.migrateIfNeeded()
        _ = CotLocalDatabase.shared
        
        // -> Setting `automaticTerminationSupportEnabled` programmatically doesn't appear to be working.
        //    (2024-11, macOS 15.1, FB15979536)
        ProcessInfo.processInfo.automaticTerminationSupportEnabled = true
        if Document.autosavesInPlace {
            ProcessInfo.processInfo.enableSuddenTermination()
        }
        
        // migrate syntax definitions to the format in CotEditor 7.0.0 (2026)
        if let lastVersion = UserDefaults.standard[.lastVersion].flatMap(Int.init), lastVersion < 809 {
            do {
                try SyntaxManager.shared.migrateUserSettings()
            } catch {
                Logger.app.error("Failed syntax definition migration: \(error)")
            }
        }
        
        _ = DocumentController.shared
        
        self.prepareMainMenu()
        
        // Monitor weekly report DB updates so the top menu bar stays synchronized
        NotificationCenter.default.publisher(for: CotLocalDatabase.weeklyReportsDidChangeNotification)
            .sink { [weak self] _ in self?.rebuildWeeklyReportsMenu() }
            .store(in: &self.menuUpdateObservers)
        
        #if SPARKLE
        UpdaterManager.shared.setup()
        #endif
    }
    
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        
        KeyBindingManager.shared.applyShortcutsToMainMenu()
        
        NSApp.servicesProvider = ServicesProvider()
        NSApp.registerServicesMenuSendTypes([.fileURL], returnTypes: [])
        NSTouchBar.isAutomaticCustomizeTouchBarMenuItemEnabled = true
        
        #if DEBUG
        self.scheduleTerminalDemoIfRequested()
        self.scheduleAISettingsDemoIfRequested()
        self.scheduleSettingsPaneDemoIfRequested()
        self.scheduleInspectorDemoIfRequested()
        self.scheduleAIResultDemoIfRequested()
        self.scheduleEmojiMenuDemoIfRequested()
        self.scheduleContextMenuDemoIfRequested()
        #endif
        
        let lastVersion = UserDefaults.standard[.lastVersion].flatMap(Int.init)
        
        // show What's New panel for the latest minor update
        if let lastVersion, lastVersion < NewFeature.buildNumber {
            self.showWhatsNew(nil)
        }
        
        // store the latest version
        // -> Migration processes should be completed up to this point.
        let thisVersion = Bundle.main.bundleVersion
        if lastVersion == nil || Int(thisVersion)! > lastVersion! {
            UserDefaults.standard[.lastVersion] = thisVersion
        }
    }
    
    
    func applicationWillTerminate(_ notification: Notification) {
        
        // Snapshot every open document and window pane/tab session into CotLocalDatabase before termination
        for window in NSApp.windows {
            if let docVC = (window.windowController as? DocumentWindowController)?.documentViewController {
                docVC.savePaneTabsSessionToDatabase()
            }
        }
        for case let document as Document in NSDocumentController.shared.documents {
            document.syncToLocalDatabase()
        }
        CotLocalDatabase.shared.syncUserPreferencesToDatabase()
        
        if self.needsRelaunch {
            NSApp.relaunch()
        }
    }
    
    
    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
        
        // be called on the open event when iCloud Drive is disabled (2024-05, macOS 14).
        // -> Otherwise, NSDocumentController.openDocument(_:) is directly called on launch.
        
        (DocumentController.shared as? DocumentController)?.performOnLaunchAction()
        
        return false
    }
    
    
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        
        // only on the *re*-open event (not called on the app launch)
        
        // Because the default reopen behavior varies depending on various conditions,
        // such as NSQuitAlwaysKeepsWindows, the iCloud Drive availability, etc,
        // execute the action directly by self (2024-05, macOS 14).
        if !flag {
            (DocumentController.shared as? DocumentController)?.performOnLaunchAction()
            return false
        } else {
            // -> bring a document in the Dock to the front if any exists.
            return true
        }
    }
    
    
    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        
        assert(Thread.isMainThread)
        
        let urls = filenames.map { URL(filePath: $0) }
        let isAutomaticTabbing = (DocumentWindow.userTabbingPreference == .inFullScreen) && (urls.count > 1)
        
        Task {
            var remainingURLs = urls[...]
            var reply: NSApplication.DelegateReply = .failure
            
            @MainActor func handleOpeningError(_ error: any Error) {
                
                if (error as? CocoaError)?.code == .userCancelled {
                    reply = (reply == .failure) ? .cancel : reply
                } else {
                    // ask user for opening file
                    NSApp.presentError(error)
                }
            }
            
            if isAutomaticTabbing {
                // open the first new window before forcing the rest into tabs
                while let url = remainingURLs.popFirst() {
                    do {
                        let (_, documentWasAlreadyOpen) = try await NSDocumentController.shared.openDocument(withContentsOf: url, display: true)
                        reply = .success
                        
                        if !documentWasAlreadyOpen {
                            DocumentWindow.tabbingPreference = .always
                            break
                        }
                    } catch {
                        handleOpeningError(error)
                    }
                }
            }
            
            await withThrowingTaskGroup { group in
                for url in remainingURLs {
                    group.addTask { try await NSDocumentController.shared.openDocument(withContentsOf: url, display: true) }
                }
                
                while let result = await group.nextResult() {
                    switch result {
                        case .success:
                            reply = .success
                        case .failure(let error):
                            handleOpeningError(error)
                    }
                }
            }
            
            if isAutomaticTabbing {
                DocumentWindow.tabbingPreference = nil
            }
            
            NSApp.reply(toOpenOrPrint: reply)
        }
    }
    
    
    // MARK: Action Messages
    
    func validateUserInterfaceItem(_ item: any NSValidatedUserInterfaceItem) -> Bool {
        
        switch item.action {
            case #selector(importSettings):
                return !self.isSettingsImporterPresented
            default: break
        }
        
        return true
    }
    
    
    /// Activates self and perform New menu action (from Dock menu).
    @IBAction func newDocumentActivatingApplication(_ sender: Any?) {
        
        NSApp.activate()
        NSDocumentController.shared.newDocument(sender)
    }
    
    
    /// Shows the about panel.
    @IBAction func showAboutPanel(_ sender: Any?) {
        
        let panel = self.aboutPanel ?? NSPanel(view: AboutView(), title: String(localized: "About \(Bundle.main.bundleName)", table: "About", comment: "%@ is app name"))
        panel.makeKeyAndOrderFront(sender)
        
        self.aboutPanel = panel
    }
    
    
    /// Shows the What's New panel.
    @IBAction func showWhatsNew(_ sender: Any?) {
        
        let panel = self.whatsNewPanel ?? NSPanel(view: WhatsNewView())
        panel.makeKeyAndOrderFront(sender)
        
        self.whatsNewPanel = panel
    }
    
    
    /// Shows the Settings window.
    @IBAction func showSettingsWindow(_ sender: Any?) {
        
        self.settingsWindowController.showWindow(sender)
    }
    
    
    /// Opens the settings window at the AI pane.
    ///
    /// - Parameter sender: The action sender.
    @IBAction func showAIPreferences(_ sender: Any?) {
        
        self.settingsWindowController.openPane(.ai)
    }
    
    
    /// Opens the Export Settings panel.
    @IBAction func exportSettings(_ sender: Any?) {
        
        let panel = self.exportSettingsPanel ?? NSPanel(
            view: ExportSettingsView(includedTypes: PortableSettingsDocument.exportableSettings),
            hidesTitleButtons: true,
            title: String(localized: "Export Settings", table: "SettingsPorting")
        )
        panel.makeKeyAndOrderFront(nil)
        
        self.exportSettingsPanel = panel
    }
    
    
    /// Opens the Import Settings panel.
    @IBAction func importSettings(_ sender: Any?) {
        
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.cotSettings]
        panel.message = String(localized: "Choose a CotEditor settings archive to import.", table: "SettingsPorting")
        panel.prompt = String(localized: "Action.import.label", defaultValue: "Import")
        
        self.isSettingsImporterPresented = true
        
        panel.begin { response in
            self.isSettingsImporterPresented = false
            
            guard response == .OK, let url = panel.url else { return }
            
            let document: PortableSettingsDocument
            do {
                document = try PortableSettingsDocument(contentsOf: url)
            } catch {
                NSApp.presentError(error)
                return
            }
            
            let name = url.deletingPathExtension().lastPathComponent
            let panel = NSPanel(
                view: ImportSettingsView(name: name, document: document),
                hidesTitleButtons: true,
                title: String(localized: "Import Settings", table: "SettingsPorting")
            )
            panel.makeKeyAndOrderFront(nil)
        }
    }
    
    
    /// Shows the Quick Action command bar.
    @IBAction func showQuickActions(_ sender: Any?) {
        
        if CommandBarWindowController.shared.window?.isVisible == true {
            CommandBarWindowController.shared.close()
        } else {
            CommandBarWindowController.shared.showWindow(sender)
        }
    }
    
    
    /// Fallback action when snippet editor menu item is invoked directly.
    @IBAction func showSnippetEditor(_ sender: Any?) {
        
        self.settingsWindowController.openPane(.edit)
    }
    
    
    /// Shows the Encoding List to customize encodings list.
    @IBAction func showEncodingsListEditor(_ sender: Any?) {
        
        self.settingsWindowController.openPane(.format)
        FormatSettingsView.Presentation.shared.requestEncodingList()
    }
    
    
    /// Shows the Color panel with the color code control.
    @IBAction func editColorCode(_ sender: Any?) {
        
        ColorCodePanelController.shared.showWindow()
    }
    
    
    /// Shows console panel.
    @IBAction func showConsolePanel(_ sender: Any?) {
        
        ConsolePanelController.shared.showWindow(sender)
    }
    
    
    /// Opens OSA script dictionary in Script Editor.
    @IBAction func openAppleScriptDictionary(_ sender: Any?) {
        
        guard let scriptEditorURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: BundleIdentifier.scriptEditor) else { return }
        
        let appURL = Bundle.main.bundleURL
        let configuration = NSWorkspace.OpenConfiguration()
        
        NSWorkspace.shared.open([appURL], withApplicationAt: scriptEditorURL, configuration: configuration)
    }
    
    
    /// Opens a specific page in the system Help viewer.
    @IBAction func openHelpAnchor(_ sender: any NSUserInterfaceItemIdentification) {
        
        guard let identifier = sender.identifier else { return assertionFailure() }
        
        NSHelpManager.shared.openHelpAnchor(identifier.rawValue, inBook: Bundle.main.helpBookName)
    }
    
    
    /// Opens the application web site (coteditor.com) in the default web browser.
    @IBAction func openWebSite(_ sender: Any?) {
        
        NSWorkspace.shared.open(AppWebURL.website.url)
    }
    
    
    /// Opens the bug report page in the default web browser.
    @IBAction func reportBug(_ sender: Any?) {
        
        NSWorkspace.shared.open(AppWebURL.issueTracker.url)
    }
    
    
    /// Opens the dedicated 周报中心 (Weekly Report Center) window.
    @IBAction func showWeeklyReportCenter(_ sender: Any?) {
        
        WeeklyReportWindowController.shared.showWindow(mode: .history)
    }
    
    
    /// Opens the Weekly Report Center directly in "Generate Weekly Report" mode.
    @IBAction func openWeeklyReportGenerator(_ sender: Any?) {
        
        WeeklyReportWindowController.shared.showWindow(mode: .generator)
    }
    
    
    /// Triggers one-click AI organize-and-merge across all open windows.
    @IBAction func organizeAndMergeAllDocumentsFromMenu(_ sender: Any?) {
        
        WorkspaceOrganizer.runOrganizeAndMerge(from: NSApp.mainWindow ?? NSApp.orderedWindows.first)
    }
    
    
    /// Lets the user import historical weekly reports from a `.zip`, folder, or `.md` files.
    @IBAction func importWeeklyReportsFromMenu(_ sender: Any?) {
        
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.zip, .folder, UTType(filenameExtension: "md") ?? .plainText, .plainText]
        panel.message = "选择历史周报 .zip 压缩包、周报文件夹或 .md 文件，自动按月份收录进「周报」菜单与数据库"
        
        guard panel.runModal() == .OK, !panel.urls.isEmpty else { return }
        do {
            let count = try CotLocalDatabase.shared.importWeeklyReports(fromURLs: panel.urls)
            let alert = NSAlert()
            alert.messageText = "历史周报导入完成"
            alert.informativeText = "本次共收录/更新 \(count) 篇周报，可在顶部菜单栏「周报」中按月份随时查阅。"
            alert.runModal()
        } catch {
            NSApp.presentError(error)
        }
    }
    
    
    /// Opens a historical weekly report chosen from the top menu bar `周报` module.
    @objc private func openStoredWeeklyReportFromMenu(_ sender: NSMenuItem) {
        
        guard let reportID = sender.representedObject as? String,
              let report = CotLocalDatabase.shared.weeklyReports.first(where: { $0.id == reportID })
        else { return }
        
        WeeklyReportWindowController.shared.openReportInEditor(report)
    }
    
    
    /// Opens a new bug report window.
    @IBAction func createBugReport(_ sender: Any?) {
        
        let report = IssueReport()
        
        // open as document
        do {
            let document = try (NSDocumentController.shared as! DocumentController).openUntitledDocument(content: report.template, title: report.title, display: true)
            document.setSyntax(name: SyntaxName.markdown)
        } catch {
            NSApp.presentError(error)
        }
    }
    
    
    #if DEBUG
    /// Opens the AI settings pane on launch, for screenshot and crash verification.
    ///
    /// Enabled by launching with `--ai-settings`; inert otherwise.
    private func scheduleAISettingsDemoIfRequested() {
        
        guard ProcessInfo.processInfo.arguments.contains("--ai-settings") else { return }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            self.settingsWindowController.openPane(.ai)
        }
    }
    
    
    /// Opens one specific settings pane on launch, for screenshot verification.
    ///
    /// Enabled by launching with `--settings-pane <pane>`, where `<pane>` is the raw value of
    /// ``SettingsPane`` (for example `general` or `ai`); inert otherwise.
    private func scheduleSettingsPaneDemoIfRequested() {
        
        let arguments = ProcessInfo.processInfo.arguments
        guard
            let index = arguments.firstIndex(of: "--settings-pane"),
            arguments.indices.contains(index + 1),
            let pane = SettingsPane(rawValue: arguments[index + 1])
        else { return }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            self.settingsWindowController.openPane(pane)
        }
    }
    
    
    /// Opens the inspector in the front document window on launch, for screenshot verification.
    ///
    /// Enabled by launching with `--show-inspector [file]`; an optional file path is opened
    /// first so the inspector has file attributes to show. Inert otherwise.
    private func scheduleInspectorDemoIfRequested() {
        
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "--show-inspector") else { return }
        let path = arguments.indices.contains(index + 1) ? arguments[index + 1] : nil
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            NSApp.activate(ignoringOtherApps: true)
            
            guard let path else {
                self.showInspectorInFrontWindow()
                return
            }
            
            NSDocumentController.shared.openDocument(withContentsOf: URL(filePath: path), display: true) { _, _, _ in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    self.showInspectorInFrontWindow()
                }
            }
        }
    }
    
    
    /// Toggles the inspector of the front document window.
    private func showInspectorInFrontWindow() {
        
        let windowControllers = NSApp.orderedWindows.compactMap { $0.windowController as? DocumentWindowController }
        guard let windowController = windowControllers.first(where: { $0.window?.isVisible == true }) else { return assertionFailure() }
        
        windowController.window?.makeKeyAndOrderFront(nil)
        
        guard let splitViewController = windowController.contentViewController as? NSSplitViewController,
              let inspectorItem = splitViewController.splitViewItems.first(where: { $0.behavior == .inspector }),
              inspectorItem.isCollapsed
        else { return }
        
        splitViewController.toggleInspector(nil)
    }
    
    
    /// Opens the terminal panel in the front document window when launched with
    /// `--show-terminal`, for screenshot verification.
    private func scheduleTerminalDemoIfRequested() {
        
        guard ProcessInfo.processInfo.arguments.contains("--show-terminal") else { return }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            NSApp.activate(ignoringOtherApps: true)
            
            let windowControllers = NSApp.orderedWindows.compactMap { $0.windowController as? DocumentWindowController }
            
            guard let windowController = windowControllers.first else { return }
            
            windowController.window?.makeKeyAndOrderFront(nil)
            windowController.toggleTerminalForDemo()
        }
    }
    
    
    /// Shows the AI result sheet with a sample answer, for screenshot verification.
    ///
    /// Enabled by launching with `--ai-result-demo`; inert otherwise.
    private func scheduleAIResultDemoIfRequested() {
        
        guard ProcessInfo.processInfo.arguments.contains("--ai-result-demo") else { return }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            NSApp.activate(ignoringOtherApps: true)
            
            guard let window = NSApp.orderedWindows.first(where: { $0.isVisible && $0.sheetParent == nil }) else {
                return assertionFailure()
            }
            
            let panel = AIResultPanelController(action: .summarize)
            panel.present(on: window)
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                panel.present(result: """
                ## 总结
                
                评测工作分为三块，互相依赖：
                
                - **评测复核**：模型给出的结论需要人工抽样确认。
                - **样式规整**：AIME 与问财数据看板统一按同一套规范排版。
                - **数据治理**：评测的输入端与输出端都纳入治理范围，而不是只管输出。
                
                需要复核的字段：
                
                ```python
                def review(row):
                    return row["score"] is None
                ```
                
                > 下一步是把三块的验收标准写进同一份检查表。
                """)
            }
        }
    }
    
    
    /// Shows the toolbar's emoji menu, for screenshot verification.
    ///
    /// Enabled by launching with `--emoji-menu`; inert otherwise.
    private func scheduleEmojiMenuDemoIfRequested() {
        
        guard ProcessInfo.processInfo.arguments.contains("--emoji-menu") else { return }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            NSApp.activate(ignoringOtherApps: true)
            
            let windowControllers = NSApp.orderedWindows.compactMap { $0.windowController as? DocumentWindowController }
            guard let windowController = windowControllers.first(where: { $0.window?.isVisible == true }) else { return }
            
            windowController.showEmojiMenuForDemo()
        }
    }
    
    
    /// Shows the text view's context menu, for screenshot verification.
    ///
    /// Enabled by launching with `--context-menu-demo`; inert otherwise. Used to confirm that
    /// AppKit's auto-fill and services items stay out of the menu.
    private func scheduleContextMenuDemoIfRequested() {
        
        guard ProcessInfo.processInfo.arguments.contains("--context-menu-demo") else { return }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            NSApp.activate(ignoringOtherApps: true)
            
            let windowControllers = NSApp.orderedWindows.compactMap { $0.windowController as? DocumentWindowController }
            guard let windowController = windowControllers.first(where: { $0.window?.isVisible == true }),
                  let window = windowController.window,
                  let viewController = windowController.documentViewController,
                  let textView = viewController.focusedTextView
            else { return }
            
            let selection = NSRange(location: 0, length: min(12, (textView.string as NSString).length))
            textView.setSelectedRange(selection)
            
            let point = textView.convert(NSPoint(x: 40, y: textView.bounds.height - 80), to: nil)
            
            guard let event = NSEvent.mouseEvent(with: .rightMouseDown,
                                                 location: point,
                                                 modifierFlags: [],
                                                 timestamp: ProcessInfo.processInfo.systemUptime,
                                                 windowNumber: window.windowNumber,
                                                 context: nil,
                                                 eventNumber: 0,
                                                 clickCount: 1,
                                                 pressure: 1)
            else { return }
            
            textView.rightMouseDown(with: event)
        }
    }
    #endif
    
    
    // MARK: Private Methods
    
    /// Prepares the main menu.
    private func prepareMainMenu() {
        
        assert(NSApp.mainMenu != nil)
        
        self.localizeCustomMenuItems()
        
        guard self.menuUpdateObservers.isEmpty else { return assertionFailure() }
        
        self.updateEncodingMenu(self.encodingsMenu!)
        
        self.lineEndingsMenu?.items = LineEnding.allCases.map { lineEnding in
            let item = NSMenuItem()
            item.title = "\(lineEnding.description) (\(lineEnding.label))"
            item.tag = lineEnding.index
            item.action = #selector(Document.changeLineEnding(_:))
            item.isHidden = !lineEnding.isBasic
            item.keyEquivalentModifierMask = lineEnding.isBasic ? [] : [.option]
            
            return item
        }
        
        SyntaxManager.shared.$settingNames
            .map { names in
                let action = #selector((any SyntaxChanging).changeSyntax)
                let noneItem = NSMenuItem(title: String(localized: "SyntaxName.none", defaultValue: "None"), action: action, keyEquivalent: "")
                noneItem.representedObject = SyntaxName.none
                let items = names.map { name in
                    let item = NSMenuItem(title: name, action: action, keyEquivalent: "")
                    item.representedObject = name
                    return item
                }
                
                return [
                    noneItem,
                    .separator()
                ] + items
            }
            .assign(to: \.items, on: self.syntaxesMenu!)
            .store(in: &self.menuUpdateObservers)
        
        ThemeManager.shared.$settingNames
            .map { $0.map { NSMenuItem(title: $0, action: #selector((any ThemeChanging).changeTheme), keyEquivalent: "") } }
            .assign(to: \.items, on: self.themesMenu!)
            .store(in: &self.menuUpdateObservers)
        
        SnippetManager.shared.menu = self.snippetMenu!
        ScriptManager.shared.menu = self.scriptMenu!
        
        // build Unicode normalization menu items
        self.normalizationMenu?.items = (UnicodeNormalizationForm.standardForms + [nil] +
                                         UnicodeNormalizationForm.modifiedForms)
        .map { form in
            guard let form else { return .separator() }
            
            let item = NSMenuItem()
            item.title = form.localizedName
            item.action = #selector(EditorTextView.normalizeUnicode(_:))
            item.representedObject = form
            item.tag = form.tag  // for the shortcut customization
            item.toolTip = form.localizedDescription
            return item
        }
        
        // build multiple replace menu items
        ReplacementManager.shared.$settingNames
            .sink { [weak self] names in
                guard let menu = self?.multipleReplaceMenu else { return }
                
                let manageItem = menu.items.last
                menu.items = names.map { name in
                    let item = NSMenuItem()
                    item.title = name
                    item.action = #selector(NSTextView.performTextFinderAction)
                    item.tag = TextFinder.Action.multipleReplace.rawValue
                    item.representedObject = name
                    return item
                } + [
                    .separator(),
                    manageItem!,
                ]
            }
            .store(in: &self.menuUpdateObservers)
        
        self.installWeeklyReportTopMenu()
    }
    
    
    /// Installs the dedicated `周报` (Weekly Report) module menu in the top menu bar.
    private func installWeeklyReportTopMenu() {
        
        guard let mainMenu = NSApp.mainMenu else { return }
        if self.weeklyReportsMenu != nil {
            self.rebuildWeeklyReportsMenu()
            return
        }
        
        let title = String(localized: "chrome.menu.weeklyReportModule", defaultValue: "周报", table: "Chrome")
        let topItem = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: title)
        submenu.autoenablesItems = false
        topItem.submenu = submenu
        self.weeklyReportsMenu = submenu
        
        // Place prominently before Script / Window / Help
        let insertionIndex = max(1, mainMenu.items.count - 3)
        mainMenu.insertItem(topItem, at: insertionIndex)
        self.rebuildWeeklyReportsMenu()
    }
    
    
    /// Rebuilds the top-level `周报` menu with actions and all historical reports grouped by year-month.
    private func rebuildWeeklyReportsMenu() {
        
        guard let submenu = self.weeklyReportsMenu else { return }
        submenu.removeAllItems()
        
        let centerItem = NSMenuItem(
            title: String(localized: "chrome.menu.openWeeklyReportCenter", defaultValue: "打开周报中心（历史与生成）…", table: "Chrome"),
            action: #selector(showWeeklyReportCenter(_:)),
            keyEquivalent: ""
        )
        centerItem.target = self
        submenu.addItem(centerItem)
        
        let generateItem = NSMenuItem(
            title: String(localized: "chrome.menu.generateWeeklyReportHuman", defaultValue: "生成本周周报（说人话版）…", table: "Chrome"),
            action: #selector(openWeeklyReportGenerator(_:)),
            keyEquivalent: ""
        )
        generateItem.target = self
        submenu.addItem(generateItem)
        
        let organizeItem = NSMenuItem(
            title: String(localized: "chrome.menu.organizeAndMergeAll", defaultValue: "AI 一键整理合并所有文档…", table: "Chrome"),
            action: #selector(organizeAndMergeAllDocumentsFromMenu(_:)),
            keyEquivalent: ""
        )
        organizeItem.target = self
        submenu.addItem(organizeItem)
        
        let importItem = NSMenuItem(
            title: String(localized: "chrome.menu.importWeeklyReports", defaultValue: "导入历史周报 (.zip / 文件夹)…", table: "Chrome"),
            action: #selector(importWeeklyReportsFromMenu(_:)),
            keyEquivalent: ""
        )
        importItem.target = self
        submenu.addItem(importItem)
        
        submenu.addItem(.separator())
        
        let reports = CotLocalDatabase.shared.weeklyReports
        let headerItem = NSMenuItem(title: "历史周报（共 \(reports.count) 篇）", action: nil, keyEquivalent: "")
        headerItem.isEnabled = false
        submenu.addItem(headerItem)
        
        if reports.isEmpty {
            let emptyItem = NSMenuItem(title: "（暂无已导入周报，请点击上方“导入历史周报…”）", action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            submenu.addItem(emptyItem)
            return
        }
        
        let byMonth = Dictionary(grouping: reports, by: \.yearMonth)
        for yearMonth in byMonth.keys.sorted(by: >) {
            let monthReports = (byMonth[yearMonth] ?? []).sorted { lhs, rhs in
                if lhs.periodLabel != rhs.periodLabel {
                    return lhs.periodLabel > rhs.periodLabel
                }
                return lhs.updatedAt > rhs.updatedAt
            }
            
            let monthItem = NSMenuItem(title: "\(yearMonth)（\(monthReports.count) 篇）", action: nil, keyEquivalent: "")
            let monthMenu = NSMenu(title: yearMonth)
            monthMenu.autoenablesItems = false
            
            for report in monthReports {
                let itemTitle = report.title == report.periodLabel
                    ? report.periodLabel
                    : "\(report.periodLabel) · \(report.title)"
                let reportItem = NSMenuItem(
                    title: itemTitle,
                    action: #selector(openStoredWeeklyReportFromMenu(_:)),
                    keyEquivalent: ""
                )
                reportItem.target = self
                reportItem.representedObject = report.id
                monthMenu.addItem(reportItem)
            }
            
            monthItem.submenu = monthMenu
            submenu.addItem(monthItem)
        }
    }
    
    
    /// Retitles the menu items this fork added to the storyboard.
    ///
    /// The storyboard's Base localization is English, but these three items were added with
    /// Chinese titles, so a Chinese title would leak into the English UI. Their titles are
    /// therefore set at launch from the `Chrome` string catalog instead. The storyboard and
    /// its catalog are left untouched.
    private func localizeCustomMenuItems() {
        
        guard let mainMenu = NSApp.mainMenu else { return assertionFailure() }
        
        let titles: [Selector: String] = [
            #selector(NSDocument.move(_:)):
                String(localized: "chrome.menu.rename", defaultValue: "Rename…", table: "Chrome"),
            #selector(DocumentViewController.splitEditorHorizontally(_:)):
                String(localized: "chrome.menu.splitDown", defaultValue: "Split Down", table: "Chrome"),
            #selector(DocumentViewController.splitEditorVertically(_:)):
                String(localized: "chrome.menu.splitRight", defaultValue: "Split Right", table: "Chrome"),
        ]
        
        func retitle(in menu: NSMenu) {
            let hiddenSelectors: Set<Selector> = [
                #selector(DocumentViewController.openSplitTextView(_:)),
                #selector(DocumentViewController.splitEditorHorizontally(_:)),
                #selector(DocumentViewController.splitEditorVertically(_:)),
                #selector(AppDelegate.showSnippetEditor(_:)),
            ]
            for item in menu.items {
                if item.submenu === self.snippetMenu {
                    item.isHidden = true
                    item.keyEquivalent = ""
                } else if let action = item.action, hiddenSelectors.contains(action) {
                    item.isHidden = true
                    item.keyEquivalent = ""
                } else if let action = item.action, let title = titles[action] {
                    item.title = title
                }
                if let submenu = item.submenu {
                    retitle(in: submenu)
                }
            }
        }
        
        retitle(in: mainMenu)
    }
}


extension AppDelegate: NSMenuDelegate {
    
    func menuNeedsUpdate(_ menu: NSMenu) {
        
        switch menu {
            case self.encodingsMenu:
                self.updateEncodingMenu(menu, checksDocument: true)
            default:
                break
        }
    }
    
    
    /// Updates the Text Encoding menu.
    ///
    /// By considering the document, if the document's file encoding isn't already in the list, it is inserted at the top of the list.
    ///
    /// - Parameters:
    ///   - menu: The menu to update.
    ///   - checksDocument: `true` to consider the currently targeted document.
    private func updateEncodingMenu(_ menu: NSMenu, checksDocument: Bool = false) {
        
        let action = #selector((any EncodingChanging).changeEncoding)
        var fileEncodings = EncodingManager.shared.fileEncodings
        
        if checksDocument,
           let document = NSApp.target(forAction: action) as? Document,
           !fileEncodings.contains(document.fileEncoding)
        {
            fileEncodings.insert(contentsOf: [document.fileEncoding, nil], at: 0)
        }
        
        menu.items = fileEncodings.map { fileEncoding in
            switch fileEncoding {
                case .some(let fileEncoding):
                    let item = NSMenuItem()
                    item.title = fileEncoding.localizedName
                    item.action = action
                    item.representedObject = fileEncoding
                    return item
                case .none:
                    return .separator()
            }
        } + [
            .separator(),
            NSMenuItem(title: String(localized: "Customize Encodings List…", table: "MainMenu"),
                       systemImage: "square.and.pencil", action: #selector(showEncodingsListEditor)),
        ]
    }
}


// MARK: - Private Extensions

private extension NSPanel {
    
    /// Instantiates a panel with a SwiftUI view.
    ///
    /// - Parameters:
    ///   - view: The SwiftUI view.
    ///   - hidesTitleButtons: If `true`, the close/miniaturize/zoom buttons are hidden.
    ///   - title: The window title mainly for the accessibility.
    convenience init(view: some View, hidesTitleButtons: Bool = false, title: String? = nil) {
        
        let viewController = NSHostingController(rootView: view)
        viewController.safeAreaRegions = []
        
        self.init(contentViewController: viewController)
        
        self.styleMask = [.closable, .titled, .fullSizeContentView]
        self.titleVisibility = .hidden
        self.titlebarAppearsTransparent = true
        self.hidesOnDeactivate = false
        self.setContentSize(viewController.view.intrinsicContentSize)
        if #available(macOS 26, *), title == nil {
            self.toolbar = NSToolbar()
        }
        
        if hidesTitleButtons {
            self.standardWindowButton(.closeButton)?.isHidden = true
            self.standardWindowButton(.miniaturizeButton)?.isHidden = true
            self.standardWindowButton(.zoomButton)?.isHidden = true
        }
        
        if let title {
            self.title = title
        }
        
        self.center()
    }
}


private extension UnicodeNormalizationForm {
    
    /// Unique identifier for menu item.
    var tag: Int {
        
        Self.allCases.firstIndex(of: self)!
    }
}
