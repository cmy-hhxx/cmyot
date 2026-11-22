//
//  DocumentWindowController.swift
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
import Combine
import SwiftUI
import Defaults
import ControlUI
import URLUtils

final class DocumentWindowController: NSWindowController, NSWindowDelegate {
    
    // MARK: Public Properties
    
    var isWhitePaper = false {
        
        didSet {
            guard isWhitePaper || oldValue else { return }
            
            self.setDocumentEdited(!isWhitePaper)
        }
    }
    
    
    @objc dynamic weak var fileDocument: DataDocument? {
        
        didSet {
            if fileDocument != oldValue {
                self.updateDocument(fileDocument)
            }
        }
    }
    
    
    // MARK: Private Properties
    
    private var directoryDocument: DirectoryDocument?
    private var isDirectoryDocument: Bool
    
    private var windowAutosaveName: NSWindow.FrameAutosaveName
    
    /// The frame taken from the autosaved value, before AppKit's window restoration can replace it.
    private var autosavedFrame: NSRect?
    private var needsManualOnAppear = false
    private var uniqueDirectory: String?
    
    private lazy var editedIndicator: NSView = NSHostingView(rootView: EditedIndicator())
    
    private var opacityObserver: AnyCancellable?
    private var appearanceModeObserver: AnyCancellable?
    private var fileDocumentNameObserver: AnyCancellable?
    private var documentsObserver: AnyCancellable?
    
    private var documentSyntaxObserver: AnyCancellable?
    private var documentEditableObserver: AnyCancellable?
    private var focusObserver: AnyCancellable?
    private var editedStateObserver: AnyCancellable?
    private var isReviewingPaneDocuments = false
    private var splitLayoutObserver: AnyCancellable?
    private var pendingTitleVisibility: NSWindow.TitleVisibility?
    private var syntaxListObserver: AnyCancellable?
    private weak var syntaxPopUpButton: NSPopUpButton?
    private var toolbarClusterObservers: Set<AnyCancellable> = []
    
    
    // MARK: Lifecycle
    
    required init(document: DataDocument? = nil, directoryDocument: DirectoryDocument? = nil) {
        
        assert(document != nil || directoryDocument != nil)
        
        self.fileDocument = document
        self.directoryDocument = directoryDocument
        self.isDirectoryDocument = (directoryDocument != nil)
        
        // store own autosave name
        // -> `NSWindowController.windowFrameAutosaveName` doesn't work
        //    if multiple window instances have the same name (2024-10, macOS 15).
        self.windowAutosaveName = self.isDirectoryDocument ? "DirectoryDocument" : "Document"
        
        let viewController = WindowContentViewController(document: document, directoryDocument: directoryDocument)
        let window = DocumentWindow(contentViewController: viewController)
        window.styleMask.update(with: .fullSizeContentView)
        window.animationBehavior = .documentWindow
        window.setFrameAutosaveName(self.windowAutosaveName)
        let autosavedFrame = window.frame
        
        
        // Tabs live exclusively inside each editor pane (`PaneTabStripView`), never in AppKit's native window tab bar.
        window.tabbingMode = .disallowed
        
        
        // set window size
        if let frameSize = Self.userFrameSize(for: window) {
            window.setFrame(NSRect(origin: window.frame.origin, size: frameSize), display: false)
        }
        
        // AppKit's window restoration runs after this initializer and happily replaces the
        // frame with the one recorded in its own state, which can be older than the autosaved
        // frame and therefore smaller. Keep the autosaved frame and restore it in `showWindow`.
        self.autosavedFrame = (Self.userFrameSize(for: window) == nil) ? autosavedFrame : window.frame
        
        // cascade window position
        // -> Don't use `NSApp.mainWindow` since it returns `nil` when the app is inactive. (2025-04)
        if let lastWindow = NSApp.orderedDocuments.lazy
            .compactMap(\.windowControllers.first?.window)
            .first(where: \.isVisible)
        {
            let referenceFrame = lastWindow.cascadingReferenceFrame
            let cascadingPoint = window.cascadeTopLeft(from: referenceFrame.topLeft)
            window.cascadeTopLeft(from: cascadingPoint)
        }
        
        
        super.init(window: window)
        
        
        self.updateDocument(document)
        
        window.delegate = self
        
        // setup toolbar
        let toolbar = NSToolbar(identifier: self.isDirectoryDocument ? .directoryDocument : .document)
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = true
        toolbar.autosavesConfiguration = true
        toolbar.delegate = self
        window.toolbarStyle = .unifiedCompact
        window.toolbar = toolbar
        
        // observe opacity setting change
        // -> Keep opaque when the window was created as a browsing window (the right side ones in the browsing mode).
        if document?.isInViewingMode != true {
            self.opacityObserver = UserDefaults.standard.publisher(for: .windowAlpha, initial: true)
                .assign(to: \.backgroundAlpha, on: window)
        }
        
        // observe appearance setting change
        self.appearanceModeObserver = UserDefaults.standard.publisher(for: .documentAppearance, initial: true)
            .sink { [weak self, weak window] value in
                guard let window else { return }
                let targetAppearance: NSAppearance? = switch value {
                    case .default: nil
                    case .light: NSAppearance(named: .aqua)
                    case .dark: NSAppearance(named: .darkAqua)
                }
                let applyAppearance = {
                    window.appearance = targetAppearance
                    window.toolbar?.validateVisibleItems()
                }
                if window.isVisible, window.appearance != targetAppearance {
                    window.performSmoothAppearanceTransition(duration: 0.28, updates: applyAppearance)
                } else {
                    applyAppearance()
                }
                _ = self
            }
        
        // observe for syntax line-up change
        self.syntaxListObserver = Publishers.Merge(SyntaxManager.shared.$settingNames,
                                                   UserDefaults.standard.publisher(for: .recentSyntaxNames))
            .sink { [weak self] _ in self?.buildSyntaxPopUpButton() }
        
        // observe documents to update window title
        self.documentsObserver = Publishers.Merge(
            NotificationCenter.default.publisher(for: NSDocument.DidChangeFileURLMessage.name, object: nil),
            NotificationCenter.default.publisher(for: NSDocument.DidMakeWindowMessage.name, object: nil)
        )
        .debounce(for: .seconds(0.1), scheduler: RunLoop.main)
        .sink { [weak self] _ in self?.invalidateUniqueDirectory() }
        
        // follow the pane the user is typing in
        self.focusObserver = NotificationCenter.default
            .publisher(for: DocumentViewController.focusedDocumentDidChangeNotification)
            .compactMap { $0.object as? DocumentViewController }
            .filter { [weak self] in $0 === self?.documentViewController }
            .sink { [weak self] in self?.followFocusedDocument($0.focusedDocument) }
        
        // a pane that holds its own document edits independently: the window still
        // has to show that something in it is unsaved
        self.editedStateObserver = NotificationCenter.default
            .publisher(for: Document.DidUpdateChangeMessage.name)
            .compactMap { $0.object as? Document }
            .filter { [weak self] in self?.documentViewController?.paneDocuments.contains($0) == true }
            .sink { [weak self] _ in
                self?.updateEditedState()
                self?.updateRestorability()
            }
        
        // follow the pane layout to hide the window title while the window is split
        self.splitLayoutObserver = NotificationCenter.default
            .publisher(for: DocumentViewController.splitLayoutDidChangeNotification)
            .compactMap { $0.object as? DocumentViewController }
            .filter { [weak self] in $0 === self?.documentViewController }
            .sink { [weak self] _ in self?.updateTitleVisibility() }
        
        // Keep toolbar states synchronized with active center, editable lock, and studio palette changes
        NotificationCenter.default.publisher(for: ContentViewController.didChangeActiveCenterNotification)
            .sink { [weak self] _ in self?.window?.toolbar?.validateVisibleItems() }
            .store(in: &self.toolbarClusterObservers)
        NotificationCenter.default.publisher(for: Document.didChangeEditableNotification)
            .sink { [weak self] _ in self?.window?.toolbar?.validateVisibleItems() }
            .store(in: &self.toolbarClusterObservers)
        NotificationCenter.default.publisher(for: StudioPaletteManager.paletteDidChangeNotification)
            .sink { [weak self] _ in self?.window?.toolbar?.validateVisibleItems() }
            .store(in: &self.toolbarClusterObservers)
    }
    
    
    required init?(coder: NSCoder) {
        
        fatalError("init(coder:) has not been implemented")
    }
    
    
    // MARK: Window Controller Methods
    
    override unowned(unsafe) var document: AnyObject? {
        
        didSet {
            if let document = document as? DataDocument {
                self.fileDocument = document
            }
        }
    }
    
    
    override func windowDidLoad() {
        
        super.windowDidLoad()
        
        // Let the window be moved by dragging the chrome-like background areas (the tab
        // bar's empty space, the gap under the toolbar), not just the toolbar itself.
        self.window?.isMovableByWindowBackground = true
        
        // the split state may have been set before the window finished loading
        // Keep top-left window title and subtitle hidden because pane tabs identify documents.
        self.pendingTitleVisibility = nil
        self.window?.titleVisibility = .hidden
        self.window?.subtitle = ""
    }
    
    
    override func showWindow(_ sender: Any?) {
        
        // Put the autosaved frame back once: window restoration may have replaced it with a
        // stale size between `init` and here, which made windows open small.
        if
            let autosavedFrame = self.autosavedFrame,
            let window = self.window,
            window.frame != autosavedFrame,
            !window.styleMask.contains(.fullScreen)
        {
            self.autosavedFrame = nil
            window.setFrame(autosavedFrame, display: false)
        }
        
        super.showWindow(sender)
        
        #if DEBUG
        self.scheduleDemoLayoutIfNeeded()
        #endif
    }
    
    
    override func setDocumentEdited(_ dirtyFlag: Bool) {
        
        self.updateTabAccessoryView(isEdited: dirtyFlag)
        
        super.setDocumentEdited(self.isWhitePaper ? false : dirtyFlag)
    }
    
    
    /// Updates the badge shown on the window tab.
    func updateTabAccessoryView(isEdited: Bool? = nil) {
        
        guard let window = self.window else { return }
        
        let isEdited = isEdited ?? (self.document?.isDocumentEdited == true)
        window.tab.accessoryView = (self.isWhitePaper || !isEdited) ? nil : self.editedIndicator
    }
    
    
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        
        // A pinned pane tab refuses every user-initiated close: the close button, ⌘W and
        // the window tab's close button all end up here.
        if self.documentViewController?.hasPinnedTabs == true {
            NSSound.beep()
            
            let alert = NSAlert()
            alert.messageText = String(localized: "chrome.pinnedTabsWindowAlert.title",
                                       defaultValue: "This window contains pinned tabs", table: "Chrome")
            alert.informativeText = String(localized: "chrome.pinnedTabsWindowAlert.message",
                                           defaultValue: "Unpin them before closing the window.", table: "Chrome")
            alert.alertStyle = .informational
            alert.addButton(withTitle: String(localized: "chrome.alert.ok",
                                              defaultValue: "OK", table: "Chrome"))
            alert.runModal()
            
            return false
        }
        
        guard let viewController = self.documentViewController else { return true }
        
        let extraDocuments = viewController.paneDocuments
            .filter { $0 !== viewController.document && $0.isDocumentEdited }
        
        guard !self.isReviewingPaneDocuments, !extraDocuments.isEmpty else { return true }
        
        // A pane's document has no window, so AppKit would close the window without ever
        // asking about it. Review them first; only close the window if all of them are fine.
        self.isReviewingPaneDocuments = true
        viewController.reviewDocuments(extraDocuments) { [weak self, weak sender] canClose in
            guard let self else { return }
            
            self.isReviewingPaneDocuments = false
            
            if canClose {
                sender?.close()
            }
        }
        
        return false
    }
    
    
    override func windowTitle(forDocumentDisplayName displayName: String) -> String {
        
        // The window — and therefore its tab in the tab bar — stands for the window's own
        // document. Panes name themselves in their navigation bars, so the title must not
        // follow the focused pane; that made the tab label flip between the documents of a
        // split window.
        let name = self.fileDocument?.displayName ?? displayName
        
        if let uniqueDirectory {
            return name + " \u{2014} " + uniqueDirectory  // EM DASH
        } else {
            return name
        }
    }
    
    
    override func synchronizeWindowTitleWithDocumentName() {
        
        super.synchronizeWindowTitleWithDocumentName()
        
        self.window?.titleVisibility = .hidden
        self.window?.representedURL = nil
        self.window?.subtitle = ""
    }
    
    
    // MARK: Window Delegate
    
    func windowWillUseStandardFrame(_ window: NSWindow, defaultFrame newFrame: NSRect) -> NSRect {
        
        guard let frameSize = Self.userFrameSize(for: window) else { return newFrame }
        
        var frame = window.frame
        if frameSize.width != frame.width {
            frame.size.width = frameSize.width
        }
        
        if frameSize.height != frame.height {
            frame.origin.y = frame.minY - (frameSize.height - frame.height)
            frame.size.height = frameSize.height
        }
        
        return (frame.size != newFrame.size) ? frame : newFrame
    }
    
    
    func windowDidResize(_ notification: Notification) {
        
        self.saveWindowFrame()
    }
    
    
    func windowDidMove(_ notification: Notification) {
        
        self.saveWindowFrame()
    }
    
    
    func windowWillMiniaturize(_ notification: Notification) {
        
        // Workaround issue `viewWillAppear()` and `viewDidAppear()` are not invoked
        // on de-miniaturization when the window was initially miniaturized (2024-10, macOS 15, FB15331763)
        if self.window?.isVisible == false {
            self.needsManualOnAppear = true
        }
    }
    
    
    func windowDidDeminiaturize(_ notification: Notification) {
        
        if self.needsManualOnAppear {
            self.contentViewController?.performOnAppearProcedure()
            self.needsManualOnAppear = false
        }
    }
    
    
    func windowWillEnterFullScreen(_ notification: Notification) {
        
        self.window?.isOpaque = true
    }
    
    
    func windowWillEnterVersionBrowser(_ notification: Notification) {
        
        self.window?.isOpaque = true
    }
    
    
    func windowWillExitFullScreen(_ notification: Notification) {
        
        self.restoreWindowOpacity()
    }
    
    
    func windowWillExitVersionBrowser(_ notification: Notification) {
        
        self.restoreWindowOpacity()
    }
    
    
    // MARK: Private Methods
    
    /// Returns the user-defined frame size for the given window, if set.
    ///
    /// - Parameter window: The window to calculate the user-defined frame size for.
    /// - Returns: The user-defined frame size, or `nil` if no size is set.
    private static func userFrameSize(for window: NSWindow) -> NSSize? {
        
        let minSize = NSSize(width: max(window.minSize.width, 1),
                             height: max(window.minSize.height, 1))
        
        let width = UserDefaults.standard[.windowWidth]
            .flatMap { $0 > 0 ? max($0, minSize.width) : nil }
        let height = UserDefaults.standard[.windowHeight]
            .flatMap { $0 > 0 ? max($0, minSize.height) : nil }
        
        guard width != nil || height != nil else { return nil }
        
        return NSSize(width: width ?? window.frame.width,
                      height: height ?? window.frame.height)
    }
    
    
    /// Updates document by passing it to the content view controller and updating the observation.
    ///
    /// - Parameter document: The new document.
    private func updateDocument(_ document: DataDocument?) {
        
        if let viewController = self.contentViewController as? WindowContentViewController, viewController.document != document {
            viewController.document = document
        }
        
        self.fileDocumentNameObserver = nil
        if self.isDirectoryDocument {
            self.fileDocumentNameObserver = document?.publisher(for: \.fileURL, options: .initial)
                .sink { [weak self] _ in self?.synchronizeWindowTitleWithDocumentName() }
        }
        
        self.syntaxPopUpButton?.isEnabled = (document is Document)
        
        // let the toolbar follow whichever pane has the focus
        if let document = document as? Document {
            self.followFocusedDocument(document)
        } else {
            self.documentSyntaxObserver = nil
            self.documentEditableObserver = nil
        }
        
        self.updateRestorability()
        self.updateTitleVisibility()
    }
    
    
    /// The document view controller of this window, if the window shows one.
    var documentViewController: DocumentViewController? {
        
        (self.contentViewController as? WindowContentViewController)?.documentViewController
    }
    
    
    /// The workspace content controller hosting in-window panels and overlays.
    var workspaceContentViewController: ContentViewController? {
        
        (self.contentViewController as? WindowContentViewController)?.workspaceContentViewController
    }
    
    
    /// Reflects the unsaved state of every pane in the window's close button.
    private func updateEditedState() {
        
        let isEdited = self.documentViewController?.paneDocuments.contains { $0.isDocumentEdited } ?? false
        
        self.setDocumentEdited(isEdited)
    }
    
    
    /// Keeps an empty scratch document out of the restorable state.
    ///
    /// Restoration brings back a window for every window that was open at quit time, which
    /// otherwise made empty "未命名" documents pile up on every launch. A window with a file
    /// or with text in it stays restorable, so autosaved work still comes back.
    private func updateRestorability() {
        
        let document = self.fileDocument as? Document
        let hasContent = (document?.textStorage.length ?? 0) > 0
            || self.documentViewController?.paneDocuments.contains { $0.textStorage.length > 0 } == true
        
        self.window?.isRestorable = document?.fileURL != nil || hasContent || (self.window?.isDocumentEdited == true)
    }
    
    
    /// Keeps the redundant top-left window title and mode subtitle hidden (pane tabs already show document titles).
    private func updateTitleVisibility() {
        
        guard let window = self.window else {
            self.pendingTitleVisibility = .hidden
            return
        }
        
        window.titleVisibility = .hidden
        window.subtitle = ""
    }
    
    
    #if DEBUG
    /// Builds the scripted demo layout used for screenshot verification.
    ///
    /// Enabled by launching the app with `COT_UI_DEMO=1`. The delay lets the window and
    /// its pane tabs finish their first layout pass before the demo state is built.
    private func scheduleDemoLayoutIfNeeded() {
        
        // `open --args --ui-demo` reaches the running app without going through a terminal
        guard ProcessInfo.processInfo.arguments.contains("--ui-demo")
            || ProcessInfo.processInfo.environment["COT_UI_DEMO"] == "1"
        else { return }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            self?.documentViewController?.setUpDemoLayout()
        }
    }
    #endif
    
    
    #if DEBUG
    /// Toggles the terminal panel, for the `--show-terminal` screenshot hook.
    func toggleTerminalForDemo()  {
        
        (self.contentViewController as? WindowContentViewController)?.toggleTerminal()
    }
    
    
    /// Presents the quick emoji menu, for the `--emoji-menu` screenshot hook.
    func showEmojiMenuForDemo() {
        
        guard let contentView = self.window?.contentView else { return }
        
        Self.quickEmojiMenu().popUp(positioning: nil,
                                    at: NSPoint(x: 40, y: contentView.bounds.maxY - 120),
                                    in: contentView)
    }
    #endif
    
    
    /// Makes the toolbar reflect the document of the focused pane.
    ///
    /// - Parameter document: The document the focused pane edits.
    private func followFocusedDocument(_ document: Document) {
        
        self.documentSyntaxObserver = document.$syntaxName
            .sink { [weak self] in self?.selectSyntaxPopUpItem(with: $0) }
        self.documentEditableObserver = document.$isEditable
            .sink { [weak self] _ in
                self?.window?.toolbar?.validateVisibleItems()
            }
        self.selectSyntaxPopUpItem(with: document.syntaxName)
        self.synchronizeWindowTitleWithDocumentName()
        self.window?.toolbar?.validateVisibleItems()
    }
    
    
    /// Saves the current window frame.
    ///
    /// Workaround the issue that window frame is not saved automatically.
    private func saveWindowFrame() {
        
        assert(self.isWindowLoaded)
        
        self.window?.saveFrame(usingName: self.windowAutosaveName)
    }
    
    
    /// Restores the window opacity.
    private func restoreWindowOpacity() {
        
        (self.window as? DocumentWindow)?.applyBackgroundOpacity()
    }
    
    
    /// Updates `uniqueDirectory`.
    private func invalidateUniqueDirectory() {
        
        // apply unique folder name to the window title
        let fileURLs = NSApp.windows
            .compactMap(\.windowController)
            .compactMap { $0.document as? NSDocument }
            .compactMap(\.fileURL)
        
        let uniqueDirectory = (self.document as? NSDocument)?.fileURL?
            .firstUniqueDirectoryURL(in: fileURLs)
            .map { FileManager.default.displayName(atPath: $0.path(percentEncoded: false)) }
        
        guard uniqueDirectory != self.uniqueDirectory else { return }
        
        self.uniqueDirectory = uniqueDirectory
        self.synchronizeWindowTitleWithDocumentName()
    }
    
    
    /// Builds syntax pop-up menu in toolbar.
    ///
    /// - Parameter popUpButton: The pop-up button to build the menu for, or `nil` to use the one in the toolbar.
    private func buildSyntaxPopUpButton(_ popUpButton: NSPopUpButton? = nil) {
        
        guard
            let popUpButton = popUpButton ?? self.syntaxPopUpButton,
            let menu = popUpButton.menu
        else { return }
        
        let syntaxNames = SyntaxManager.shared.settingNames
        let action = #selector((any SyntaxChanging).changeSyntax)
        
        menu.removeAllItems()
        
        let noneItem = NSMenuItem(title: String(localized: "SyntaxName.none", defaultValue: "None"), action: action, keyEquivalent: "")
        noneItem.representedObject = SyntaxName.none
        
        menu.addItem(noneItem)
        menu.addItem(.separator())
        
        menu.items += syntaxNames
            .map { name in
                let item = NSMenuItem(title: name, action: action, keyEquivalent: "")
                item.representedObject = name
                return item
            }
        
        if let document = self.fileDocument as? Document {
            self.selectSyntaxPopUpItem(with: document.syntaxName, in: popUpButton)
        }
    }
    
    
    /// Selects the given syntax in the syntax pop-up button for the toolbar.
    ///
    /// - Parameters:
    ///   - syntaxName: The name of the syntax to select.
    ///   - popUpButton: The pop-up button to select the item in, or `nil` to use the one in the toolbar.
    private func selectSyntaxPopUpItem(with syntaxName: String, in popUpButton: NSPopUpButton? = nil) {
        
        guard
            let popUpButton = popUpButton ?? self.syntaxPopUpButton,
            let menu = popUpButton.menu
        else { return }
        
        let deletedTag = -1
        
        // remove deleted items
        menu.items.removeAll { $0.tag == deletedTag }
        
        // deselect current one
        popUpButton.selectItem(at: -1)
        
        let index = popUpButton.indexOfItem(withRepresentedObject: syntaxName)
        if index >= 0 {
            popUpButton.selectItem(at: index)
            
        } else {
            // insert item by adding Deleted item section
            menu.insertItem(.init(title: syntaxName, action: nil, keyEquivalent: ""), at: 1)
            menu.item(at: 1)?.tag = deletedTag
            popUpButton.selectItem(at: 1)
            
            let title = String(localized: "Toolbar.syntax.menu.deleted.label",
                               defaultValue: "Deleted", table: "Document", comment: "menu item header")
            menu.insertItem(.sectionHeader(title: title), at: 1)
            menu.item(at: 1)?.tag = deletedTag
            
            menu.insertItem(.separator(), at: 1)
            menu.item(at: 1)?.tag = deletedTag
        }
    }
}


private extension NSViewController {
    
    /// Recursively invokes `viewWillAppear()` and `viewDidAppear()`.
    ///
    /// Workaround the issue `viewWillAppear()` and `viewDidAppear()` are not invoked
    /// on de-miniaturization when the window was initially miniaturized (2024-10, macOS 15, FB15331763).
    func performOnAppearProcedure() {
        
        // proceed only when the view is shown
        guard self.viewIfLoaded?.isHiddenOrHasHiddenAncestor == false else { return }
        
        self.viewWillAppear()
        self.viewDidAppear()
        
        for child in self.children {
            child.performOnAppearProcedure()
        }
    }
}


// MARK: - Toolbar

private extension NSToolbar.Identifier {
    
    static let document = Self("Document.personal.12")
    static let directoryDocument = Self("DirectoryDocument")
}


private extension NSToolbarItem.Identifier {
    
    private static let prefix = "com.coteditor.CotEditor.ToolbarItem."
    
    static let syntax = Self(Self.prefix + "syntaxStyle")
    static let quickEmoji = Self(Self.prefix + "quickEmoji")
    static let analyticsDashboard = Self(Self.prefix + "analyticsDashboard")
    static let appearanceMode = Self(Self.prefix + "appearanceMode")
    static let weeklyReportCenter = Self(Self.prefix + "weeklyReportCenter")
    static let documentCenter = Self(Self.prefix + "documentCenter")
    static let pinnedTodos = Self(Self.prefix + "pinnedTodos")
    static let userProfile = Self(Self.prefix + "userProfile")
    static let textScale = Self(Self.prefix + "textScale")
    static let settings = Self(Self.prefix + "settings")
    
    static let textSize = Self(Self.prefix + "textSize")
    static let smaller = Self(Self.prefix + "smaller")
    static let bigger = Self(Self.prefix + "bigger")
    
    static let writingDirection = Self(Self.prefix + "writingDirection")
    static let leftToRight = Self(Self.prefix + "leftToRight")
    static let rightToLeft = Self(Self.prefix + "rightToLeft")
    
    static let textOrientation = Self(Self.prefix + "textOrientation")
    static let horizontalText = Self(Self.prefix + "horizontalText")
    static let verticalText = Self(Self.prefix + "verticalText")
    
    static let indent = Self(Self.prefix + "indent")
    static let shiftLeft = Self(Self.prefix + "shiftLeft")
    static let shiftRight = Self(Self.prefix + "shiftRight")
    
    static let comment = Self(Self.prefix + "comment")
    
    static let tabStyle = Self(Self.prefix + "tabStyle")
    static let invisibles = Self(Self.prefix + "invisibles")
    static let wrapLines = Self(Self.prefix + "wrapLines")
    static let indentGuides = Self(Self.prefix + "indentGuides")
    
    static let keepOnTop = Self(Self.prefix + "keepOnTop")
    static let terminal = Self(Self.prefix + "terminal")
    static let aiSettings = Self(Self.prefix + "aiSettings")
    static let editable = Self(Self.prefix + "editable")
    static let spellCheck = Self(Self.prefix + "spellCheck")
    static let emojiAndSymbols = Self(Self.prefix + "emojiAndSymbols")
    static let fonts = Self(Self.prefix + "fonts")
    static let find = Self(Self.prefix + "find")
    static let print = Self(Self.prefix + "print")
    static let share = Self(Self.prefix + "share")
}


extension DocumentWindowController: NSToolbarDelegate {
    
    private var directoryIdentifiers: [NSToolbarItem.Identifier] {
        
        self.isDirectoryDocument ? [
            .flexibleSpace,
            .toggleSidebar,
            .sidebarTrackingSeparator,
        ] : []
    }
    
    
    func toolbarImmovableItemIdentifiers(_ toolbar: NSToolbar) -> Set<NSToolbarItem.Identifier> {
        
        Set(self.directoryIdentifiers).union([
            .editable,
            .quickEmoji,
            .appearanceMode,
            .analyticsDashboard,
            .weeklyReportCenter,
            .documentCenter,
            .terminal,
            .aiSettings,
            .settings,
            .flexibleSpace,
            .pinnedTodos,
            .userProfile,
        ])
    }
    
    
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        
        self.directoryIdentifiers + [
            .editable,
            .quickEmoji,
            .appearanceMode,
            .space,
            .analyticsDashboard,
            .weeklyReportCenter,
            .documentCenter,
            .space,
            .syntax,
            .textScale,
            .space,
            .terminal,
            .aiSettings,
            .settings,
            .flexibleSpace,
            .pinnedTodos,
            .userProfile,
        ]
    }
    
    
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        
        var identifiers = self.directoryIdentifiers + [
            .editable,
            .quickEmoji,
            .appearanceMode,
            .analyticsDashboard,
            .weeklyReportCenter,
            .documentCenter,
            .syntax,
            .textScale,
            .textSize,
            .terminal,
            .aiSettings,
            .settings,
            .pinnedTodos,
            .space,
            .flexibleSpace,
            .userProfile,
        ]
        
        if #available(macOS 15.2, *), NSWritingToolsCoordinator.isWritingToolsAvailable {
            identifiers.insert(.writingToolsItemIdentifier, at: identifiers.count - 3)
        }
        
        return identifiers
    }
    
    
    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        
        switch itemIdentifier {
            case .toggleSidebar:
                let item = NSToolbarItem(itemIdentifier: itemIdentifier)
                item.autovalidates = true
                return item
                
            case .syntax:
                let popUpButton = SyntaxPopUpButton()
                popUpButton.bezelStyle = .toolbar
                popUpButton.isEnabled = (self.fileDocument is Document)
                // store the reference only for the actual toolbar
                // -> this method is invoked also for creating the item copies for the customization palette.
                if flag {
                    self.syntaxPopUpButton = popUpButton
                }
                self.buildSyntaxPopUpButton(popUpButton)
                
                let item = NSToolbarItem(itemIdentifier: itemIdentifier)
                item.label = AppLanguage.text("语法", en: "Syntax")
                item.toolTip = AppLanguage.text("切换文档语法高亮", en: "Change syntax")
                item.view = popUpButton
                item.isNavigational = true
                item.visibilityPriority = .high
                
                let menuItem = NSMenuItem()
                menuItem.submenu = popUpButton.menu
                menuItem.title = item.label
                item.menuFormRepresentation = menuItem
                
                return item
                
            case .textScale:
                let slider = NSSlider(value: 1.0, minValue: 0.6, maxValue: 3.0,
                                      target: nil,
                                      action: #selector(DocumentViewController.changeTextScale(_:)))
                slider.isContinuous = true
                slider.controlSize = .small
                slider.toolTip = AppLanguage.text("无极调节字体大小", en: "Text size (continuous)")
                slider.translatesAutoresizingMaskIntoConstraints = false
                NSLayoutConstraint.activate([slider.widthAnchor.constraint(equalToConstant: 96)])
                
                let item = NSToolbarItem(itemIdentifier: itemIdentifier)
                item.label = AppLanguage.text("字号", en: "Text Size")
                item.toolTip = AppLanguage.text("拖动无极缩放编辑器文字", en: "Drag to change text size")
                item.view = slider
                item.isNavigational = true
                item.visibilityPriority = .high
                return item
                
            case .quickEmoji:
                let item = NSMenuToolbarItem(itemIdentifier: itemIdentifier)
                item.isBordered = true
                item.showsIndicator = false
                item.isNavigational = true
                item.label = AppLanguage.text("表情", en: "Emoji")
                item.toolTip = AppLanguage.text("插入常用标点与表情", en: "Frequently used emoji")
                item.image = WorkspaceCenterIcons.quickEmojiIcon()
                item.menu = Self.quickEmojiMenu()
                return item
                
            case .analyticsDashboard:
                let item = StatableToolbarItem(itemIdentifier: itemIdentifier)
                item.isBordered = true
                item.label = AppLanguage.text("数据看板", en: "Dashboard")
                item.toolTip = AppLanguage.text("打开 / 关闭数据看板", en: "Toggle Analytics Dashboard")
                item.stateImages[.off] = WorkspaceCenterIcons.analyticsDashboardIcon(isActive: false)
                item.stateImages[.on] = WorkspaceCenterIcons.analyticsDashboardIcon(isActive: true)
                item.action = #selector(ContentViewController.toggleAnalyticsDashboard(_:))
                item.isNavigational = true
                item.visibilityPriority = .high
                return item
                
            case .pinnedTodos:
                let item = NSToolbarItem(itemIdentifier: itemIdentifier)
                item.label = AppLanguage.text("待办", en: "Todos")
                item.toolTip = AppLanguage.text("胶囊待办（优先显示快到期事项，点击展开全部）", en: "Capsule Todos")
                item.view = ToolbarCapsuleTodoButtonView()
                item.isNavigational = false
                item.visibilityPriority = .high
                return item
                
            case .userProfile:
                let item = NSToolbarItem(itemIdentifier: itemIdentifier)
                item.label = AppLanguage.text("用户", en: "Profile")
                item.toolTip = AppLanguage.text("用户资料与环绕弹幕", en: "User Profile")
                item.view = UserAvatarToolbarButtonView()
                item.isNavigational = false
                item.visibilityPriority = .high
                return item
                
            case .appearanceMode:
                let item = StatableToolbarItem(itemIdentifier: itemIdentifier)
                item.isBordered = true
                item.label = AppLanguage.text("外观", en: "Appearance")
                item.toolTip = AppLanguage.text("切换深色 / 浅色外观", en: "Toggle Light / Dark Mode")
                item.stateImages[.off] = WorkspaceCenterIcons.appearanceModeIcon(isDark: false)
                item.stateImages[.on] = WorkspaceCenterIcons.appearanceModeIcon(isDark: true)
                item.action = #selector(DocumentViewController.toggleAppearanceMode(_:))
                item.isNavigational = true
                item.visibilityPriority = .high
                return item
                
            case .weeklyReportCenter:
                let item = StatableToolbarItem(itemIdentifier: itemIdentifier)
                item.isBordered = true
                item.label = AppLanguage.text("周报中心", en: "Weekly Reports")
                item.toolTip = AppLanguage.text("在当前窗口打开 / 关闭周报中心", en: "Toggle Weekly Report Center")
                item.stateImages[.off] = WorkspaceCenterIcons.weeklyReportIcon(isActive: false)
                item.stateImages[.on] = WorkspaceCenterIcons.weeklyReportIcon(isActive: true)
                item.action = #selector(ContentViewController.toggleWeeklyReportCenter(_:))
                item.isNavigational = true
                item.visibilityPriority = .high
                return item
                
            case .documentCenter:
                let item = StatableToolbarItem(itemIdentifier: itemIdentifier)
                item.isBordered = true
                item.label = AppLanguage.text("文档中心", en: "Documents")
                item.toolTip = AppLanguage.text("在当前窗口管理与浏览所有文档", en: "Toggle Document Center")
                item.stateImages[.off] = WorkspaceCenterIcons.documentCenterIcon(isActive: false)
                item.stateImages[.on] = WorkspaceCenterIcons.documentCenterIcon(isActive: true)
                item.action = #selector(ContentViewController.toggleDocumentCenter(_:))
                item.isNavigational = true
                item.visibilityPriority = .high
                return item
                
            case .settings:
                let item = NSToolbarItem(itemIdentifier: itemIdentifier)
                item.isBordered = true
                item.label = AppLanguage.text("设置", en: "Settings")
                item.toolTip = AppLanguage.text("打开个人设置", en: "Open Settings")
                item.image = WorkspaceCenterIcons.settingsIcon()
                item.target = NSApp.delegate
                item.action = #selector(AppDelegate.showSettingsWindow(_:))
                item.isNavigational = true
                item.visibilityPriority = .high
                return item
                
            case .aiSettings:
                let item = NSToolbarItem(itemIdentifier: itemIdentifier)
                item.isBordered = true
                item.label = "AI"
                item.toolTip = AppLanguage.text("配置 AI 模型、接口与智能体", en: "Configure AI models & bots")
                item.image = WorkspaceCenterIcons.aiSettingsIcon()
                item.target = NSApp.delegate
                item.action = #selector(AppDelegate.showAIPreferences(_:))
                item.isNavigational = true
                item.visibilityPriority = .high
                return item
                
            case .terminal:
                let item = NSToolbarItem(itemIdentifier: itemIdentifier)
                item.isBordered = true
                item.label = AppLanguage.text("终端", en: "Terminal")
                item.toolTip = AppLanguage.text("显示或隐藏底部内置终端", en: "Show or hide terminal")
                item.image = WorkspaceCenterIcons.terminalIcon()
                item.action = #selector(ContentViewController.toggleTerminal(_:))
                // keep it next to the other leading controls, and out of the overflow menu
                item.isNavigational = true
                item.visibilityPriority = .high
                return item
                
            case .textSize:
                let smallerItem = NSToolbarItem(itemIdentifier: .smaller)
                smallerItem.label = String(localized: "Toolbar.textSize.smaller.label",
                                           defaultValue: "Smaller", table: "Document")
                smallerItem.toolTip = String(localized: "Toolbar.textSize.smaller.tooltip",
                                             defaultValue: "Decrease text size", table: "Document")
                smallerItem.image = NSImage(systemSymbolName: "textformat.size.smaller", accessibilityDescription: smallerItem.label)!
                smallerItem.action = #selector(EditorTextView.smallerFont)
                
                let biggerItem = NSToolbarItem(itemIdentifier: .bigger)
                biggerItem.label = String(localized: "Toolbar.textSize.bigger.label",
                                          defaultValue: "Bigger", table: "Document")
                biggerItem.toolTip = String(localized: "Toolbar.textSize.small.tooltip",
                                            defaultValue: "Increase text size", table: "Document")
                biggerItem.image = NSImage(systemSymbolName: "textformat.size.larger", accessibilityDescription: biggerItem.label)!
                biggerItem.action = #selector(EditorTextView.biggerFont)
                
                let item = NSToolbarItemGroup(itemIdentifier: itemIdentifier)
                item.isBordered = true
                item.controlRepresentation = .expanded
                item.selectionMode = .momentary
                item.label = String(localized: "Toolbar.textSize.label",
                                    defaultValue: "Text Size", table: "Document")
                item.toolTip = String(localized: "Toolbar.textSize.tooltip",
                                      defaultValue: "Change text size", table: "Document")
                item.subitems = [smallerItem, biggerItem]
                return item
                
            case .writingDirection:
                let ltrItem = NSToolbarItem(itemIdentifier: .leftToRight)
                ltrItem.label = String(localized: "Toolbar.writingDirection.leftToRight.label",
                                       defaultValue: "Left to Right", table: "Document")
                ltrItem.toolTip = String(localized: "Toolbar.writingDirection.leftToRight.tooltip",
                                         defaultValue: "Left to right", table: "Document")
                ltrItem.image = NSImage(systemSymbolName: "text.alignleft", accessibilityDescription: ltrItem.label)
                ltrItem.action = #selector(DocumentViewController.makeWritingDirectionLeftToRight)
                
                let rtlItem = NSToolbarItem(itemIdentifier: .rightToLeft)
                rtlItem.label = String(localized: "Toolbar.writingDirection.rightToLeft.label",
                                       defaultValue: "Right to Left", table: "Document")
                rtlItem.toolTip = String(localized: "Toolbar.writingDirection.rightToLeft.tooltip",
                                         defaultValue: "Right to left", table: "Document")
                rtlItem.image = NSImage(systemSymbolName: "text.alignright", accessibilityDescription: rtlItem.label)
                rtlItem.action = #selector(DocumentViewController.makeWritingDirectionRightToLeft)
                
                let item = NSToolbarItemGroup(itemIdentifier: itemIdentifier)
                item.isBordered = true
                item.controlRepresentation = .expanded
                item.selectionMode = .selectOne
                item.label = String(localized: "Toolbar.writingDirection.label",
                                    defaultValue: "Writing Direction", table: "Document")
                item.toolTip = String(localized: "Toolbar.writingDirection.tooltip",
                                      defaultValue: "Change writing direction", table: "Document")
                item.action = #selector(DocumentViewController.changeWritingDirection)
                item.subitems = [ltrItem, rtlItem]
                return item
                
            case .textOrientation:
                let horizontalItem = NSToolbarItem(itemIdentifier: .horizontalText)
                horizontalItem.label = String(localized: "Toolbar.textOrientation.horizontalText.label",
                                              defaultValue: "Horizontal", table: "Document")
                horizontalItem.toolTip = String(localized: "Toolbar.textOrientation.horizontalText.tooltip",
                                                defaultValue: "Horizontal", table: "Document")
                horizontalItem.image = NSImage(systemSymbolName: "text.alignleft", accessibilityDescription: horizontalItem.label)
                horizontalItem.action = #selector(DocumentViewController.makeLayoutOrientationHorizontal)
                
                let verticalItem = NSToolbarItem(itemIdentifier: .verticalText)
                verticalItem.label = String(localized: "Toolbar.textOrientation.verticalText.label",
                                            defaultValue: "Vertical", table: "Document")
                verticalItem.toolTip = String(localized: "Toolbar.textOrientation.verticalText.tooltip",
                                              defaultValue: "Vertical", table: "Document")
                verticalItem.image = NSImage(resource: .textVertical)
                verticalItem.action = #selector(DocumentViewController.makeLayoutOrientationVertical)
                
                let item = NSToolbarItemGroup(itemIdentifier: itemIdentifier)
                item.isBordered = true
                item.controlRepresentation = .expanded
                item.selectionMode = .selectOne
                item.label = String(localized: "Toolbar.textOrientation.label",
                                    defaultValue: "Text Orientation", table: "Document")
                item.toolTip = String(localized: "Toolbar.textOrientation.tooltip",
                                      defaultValue: "Switch text orientation", table: "Document")
                item.action = #selector(DocumentViewController.changeOrientation)
                item.subitems = [horizontalItem, verticalItem]
                return item
                
            case .indent:
                let leftItem = NSToolbarItem(itemIdentifier: .shiftLeft)
                leftItem.label = String(localized: "Toolbar.indent.shiftLeft.label",
                                        defaultValue: "Shift Left", table: "Document")
                leftItem.toolTip = String(localized: "Toolbar.indent.shiftLeft.tooltip",
                                          defaultValue: "Shift lines to the left", table: "Document")
                leftItem.image = NSImage(systemSymbolName: "decrease.indent", accessibilityDescription: leftItem.label)
                leftItem.action = #selector(EditorTextView.shiftLeft)
                
                let rightItem = NSToolbarItem(itemIdentifier: .shiftRight)
                rightItem.label = String(localized: "Toolbar.indent.shiftRight.label",
                                         defaultValue: "Shift Right", table: "Document")
                rightItem.toolTip = String(localized: "Toolbar.indent.shiftRight.tooltip",
                                           defaultValue: "Shift lines to the right", table: "Document")
                rightItem.image = NSImage(systemSymbolName: "increase.indent", accessibilityDescription: rightItem.label)
                rightItem.action = #selector(EditorTextView.shiftRight)
                
                let item = NSToolbarItemGroup(itemIdentifier: itemIdentifier)
                item.isBordered = true
                item.controlRepresentation = .expanded
                item.selectionMode = .momentary
                item.label = String(localized: "Toolbar.indent.label",
                                    defaultValue: "Indent", table: "Document")
                item.toolTip = String(localized: "Toolbar.indent.tooltip",
                                      defaultValue: "Indent selection", table: "Document")
                item.subitems = (self.window?.windowTitlebarLayoutDirection == .rightToLeft) ? [rightItem, leftItem] : [leftItem, rightItem]
                return item
                
            case .comment:
                let item = NSToolbarItem(itemIdentifier: itemIdentifier)
                item.isBordered = true
                item.label = String(localized: "Toolbar.comment.label",
                                    defaultValue: "Comment", table: "Document")
                item.toolTip = String(localized: "Toolbar.comment.tooltip",
                                      defaultValue: "Comment-out or uncomment selection", table: "Document")
                item.image = NSImage(resource: .textCommentout)
                item.action = #selector(EditorTextView.toggleComment)
                return item
                
            case .tabStyle:
                let item = StatableMenuToolbarItem(itemIdentifier: itemIdentifier)
                item.isBordered = true
                item.label = String(localized: "Toolbar.tabStyle.label",
                                    defaultValue: "Tab Style", table: "Document")
                item.toolTip = String(localized: "Toolbar.tabStyle.tooltip.off",
                                      defaultValue: "Use spaces for indentation", table: "Document")
                item.stateImages[.on] = NSImage(resource: .tabForwardSplit)
                item.stateImages[.off] = NSImage(resource: .tabForward)
                item.action = #selector(DocumentViewController.toggleAutoTabExpand)
                item.menu.items = [
                    .sectionHeader(title: String(localized: "Toolbar.tabStyle.menu.tabWidth.label",
                                                 defaultValue: "Tab Width", table: "Document", comment: "menu item header")),
                ] + [2, 4, 8].map { width in
                    let item = NSMenuItem(title: width.formatted(), action: #selector(DocumentViewController.changeTabWidth), keyEquivalent: "")
                    item.tag = width
                    return item
                } + [
                    NSMenuItem(title: String(localized: "Toolbar.tabStyle.menu.custom.label",
                                             defaultValue: "Custom…", table: "Document"),
                               action: #selector(DocumentViewController.customizeTabWidth), keyEquivalent: ""),
                    .separator(),
                    NSMenuItem(title: String(localized: "Toolbar.tabStyle.menu.toggle.label",
                                             defaultValue: "Use Spaces for Indentation", table: "Document"),
                               action: #selector(DocumentViewController.toggleAutoTabExpand), keyEquivalent: ""),
                ]
                
                return item
                
            case .wrapLines:
                let item = StatableToolbarItem(itemIdentifier: itemIdentifier)
                item.isBordered = true
                item.label = String(localized: "Toolbar.wrapLines.label",
                                    defaultValue: "Line Wrapping", table: "Document")
                item.toolTip = String(localized: "Toolbar.wrapLines.tooltip.off",
                                      defaultValue: "Wrap lines", table: "Document")
                item.stateImages[.on] = NSImage(resource: .textWrapSlash)
                item.stateImages[.off] = NSImage(resource: .textWrap)
                item.action = #selector(DocumentViewController.toggleLineWrap)
                item.menuFormRepresentation = NSMenuItem(title: item.label, action: item.action, keyEquivalent: "")
                return item
                
            case .invisibles:
                let item = StatableToolbarItem(itemIdentifier: itemIdentifier)
                item.isBordered = true
                item.label = String(localized: "Toolbar.invisibles.label",
                                    defaultValue: "Invisibles", table: "Document")
                item.toolTip = String(localized: "Toolbar.invisibles.tooltip.off",
                                      defaultValue: "Show invisible characters", table: "Document")
                item.stateImages[.on] = NSImage(resource: .paragraphsignSlash)
                item.stateImages[.off] = NSImage(systemSymbolName: "paragraphsign", accessibilityDescription: item.label)
                item.action = #selector(DocumentViewController.toggleInvisibleChars)
                item.menuFormRepresentation = NSMenuItem(title: item.label, action: item.action, keyEquivalent: "")
                return item
                
            case .indentGuides:
                let item = StatableToolbarItem(itemIdentifier: itemIdentifier)
                item.isBordered = true
                item.label = String(localized: "Toolbar.indentGuides.label",
                                    defaultValue: "Indent Guides", table: "Document")
                item.toolTip = String(localized: "Toolbar.indentGuides.tooltip.off",
                                      defaultValue: "Show indent guide lines", table: "Document")
                item.stateImages[.on] = NSImage(resource: .textIndentguides)
                    .withSymbolConfiguration(.init(paletteColors: [.tertiaryLabelColor, .labelColor]))
                item.stateImages[.off] = NSImage(resource: .textIndentguides)
                item.action = #selector(DocumentViewController.toggleIndentGuides)
                item.menuFormRepresentation = NSMenuItem(title: item.label, action: item.action, keyEquivalent: "")
                return item
                
            case .keepOnTop:
                let item = StatableToolbarItem(itemIdentifier: itemIdentifier)
                item.isBordered = true
                item.label = String(localized: "Toolbar.keepOnTop.label",
                                    defaultValue: "Keep on Top", table: "Document")
                item.toolTip = String(localized: "Toolbar.keepOnTop.tooltip",
                                      defaultValue: "Keep the window always on top", table: "Document")
                item.stateImages[.on] = NSImage(systemSymbolName: "pin.slash", accessibilityDescription: item.label)
                item.stateImages[.off] = NSImage(systemSymbolName: "pin", accessibilityDescription: item.label)
                item.action = #selector(DocumentWindow.toggleKeepOnTop)
                return item
                
            case .editable:
                let item = StatableToolbarItem(itemIdentifier: itemIdentifier)
                item.isBordered = true
                item.label = AppLanguage.text("只读锁定", en: "Edit")
                item.toolTip = AppLanguage.text("切换读写状态 / 锁定防误改", en: "Prevent the document from being edited")
                item.stateImages[.on] = WorkspaceCenterIcons.editableIcon(isEditable: false)
                item.stateImages[.off] = WorkspaceCenterIcons.editableIcon(isEditable: true)
                item.action = #selector(DocumentViewController.toggleEditable)
                item.isNavigational = true
                return item
                
            case .spellCheck:
                let item = NSToolbarItem(itemIdentifier: itemIdentifier)
                item.isBordered = true
                item.label = String(localized: "Toolbar.spellCheck.label",
                                    defaultValue: "Spell Check", table: "Document")
                item.toolTip = String(localized: "Toolbar.spellCheck.tooltip",
                                      defaultValue: "Show spelling and grammar", table: "Document")
                item.image = NSImage(systemSymbolName: "textformat.abc.dottedunderline", accessibilityDescription: item.label)?
                    .withLocale(.init(identifier: "en"))  // fix the symbol with "abc"
                item.action = #selector(NSTextView.showGuessPanel)
                return item
                
            case .emojiAndSymbols:
                let item = NSToolbarItem(itemIdentifier: itemIdentifier)
                item.isBordered = true
                item.label = String(localized: "Toolbar.emojiAndSymbols.label",
                                    defaultValue: "Emoji & Symbols", table: "Document")
                item.toolTip = String(localized: "Toolbar.emojiAndSymbols.tooltip",
                                      defaultValue: "Show Emoji & Symbols", table: "Document")
                item.image = NSImage(resource: .emoji)
                item.action = #selector(NSApplication.orderFrontCharacterPalette)
                return item
                
            case .fonts:
                let item = NSMenuToolbarItem(itemIdentifier: itemIdentifier)
                item.isBordered = true
                item.label = String(localized: "Toolbar.fonts.label",
                                    defaultValue: "Fonts", table: "Document")
                item.toolTip = String(localized: "Toolbar.fonts.tooltip",
                                      defaultValue: "Change Font", table: "Document")
                item.image = NSImage(systemSymbolName: "textformat", accessibilityDescription: item.label)
                item.showsIndicator = false
                item.menu.items = [
                    NSMenuItem(),  // dummy item that will be hidden
                    .sectionHeader(title: String(localized: "Toolbar.fonts.menu.fontType.label",
                                                 defaultValue: "Font Type", table: "Document", comment: "menu item header")),
                    NSMenuItem(title: String(localized: "Toolbar.fonts.menu.standard.label",
                                             defaultValue: "Standard", table: "Document"),
                               action: #selector(DocumentViewController.makeFontStandard), keyEquivalent: ""),
                    NSMenuItem(title: String(localized: "Toolbar.fonts.menu.monospaced.label",
                                             defaultValue: "Monospaced", table: "Document"),
                               action: #selector(DocumentViewController.makeFontMonospaced), keyEquivalent: ""),
                    .separator(),
                    NSMenuItem(title: String(localized: "Toolbar.fonts.menu.showFonts.label",
                                             defaultValue: "Show Fonts", table: "Document"),
                               systemImage: "textformat",
                               action: #selector(NSFontManager.orderFrontFontPanel)),
                ]
                return item
                
            case .find:
                let item = NSToolbarItem(itemIdentifier: itemIdentifier)
                item.isBordered = true
                item.label = String(localized: "Toolbar.find.label",
                                    defaultValue: "Find", table: "Document")
                item.toolTip = String(localized: "Toolbar.find.tooltip",
                                      defaultValue: "Show Find & Replace", table: "Document")
                item.image = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: item.label)
                item.action = #selector(performTextFinderAction)
                item.tag = TextFinder.Action.showFindInterface.rawValue
                return item
                
            case .print:
                let item = NSToolbarItem(itemIdentifier: itemIdentifier)
                item.isBordered = true
                item.label = String(localized: "Toolbar.print.label",
                                    defaultValue: "Print", table: "Document")
                item.toolTip = String(localized: "Toolbar.print.tooltip",
                                      defaultValue: "Print document", table: "Document")
                item.image = NSImage(systemSymbolName: "printer", accessibilityDescription: item.label)
                item.action = #selector(NSDocument.printDocument)
                return item
                
            case .share:
                let item = NSSharingServicePickerToolbarItem(itemIdentifier: itemIdentifier)
                item.toolTip = String(localized: "Toolbar.share.tooltip",
                                      defaultValue: "Share document file", table: "Document",
                                      comment: "(label for the Share toolbar item is automatically set)")
                item.delegate = self
                return item
                
            default:
                return NSToolbarItem(itemIdentifier: itemIdentifier)
        }
    }
}


extension DocumentWindowController: NSSharingServicePickerToolbarItemDelegate {
    
    func items(for pickerToolbarItem: NSSharingServicePickerToolbarItem) -> [Any] {
        
        guard let document = self.fileDocument else { return [] }
        
        return [document]
    }
}


// MARK: - Views

private struct EditedIndicator: View {
    
    var body: some View {
        
        Circle()
            .fill(.tertiary)
            .frame(width: 4, height: 4)
            .padding(8)
            .help(String(localized: "Document has unsaved changes",
                         table: "Document",
                         comment: "tooltip for the “edited” indicator in the window tab"))
    }
}


// MARK: - Personal toolbar menus

extension DocumentWindowController {
    
    /// The curated emoji, laid out as three compact rows instead of one long column.
    ///
    /// Only color emoji are used: mixing them with text glyphs (`◔` `◑` `●`) makes the rows
    /// look uneven, because those come from a different font at a different optical size. One
    /// family also means one font size fits all of them.
    ///
    /// The rows answer the three questions a note usually asks — how far along, how important,
    /// what kind — and stop there.
    private static let quickEmojiRows: [[String]] = [
        ["✅", "⏳", "⚠️", "❌", "❓", "❗"],
        ["🔴", "🟠", "🟡", "🟢", "🔵", "⚪️"],
        ["⭐️", "📌", "📝", "💡", "🎯", "🔖"],
    ]
    
    
    static func quickEmojiMenu() -> NSMenu {
        
        let menu = NSMenu()
        for emojis in Self.quickEmojiRows {
            let item = NSMenuItem()
            item.view = EmojiMenuRowView(emojis: emojis)
            menu.addItem(item)
        }
        
        return menu
    }
    
    
    static func moreMenu() -> NSMenu {
        
        let menu = NSMenu()
        
        func add(_ title: String, _ action: Selector) {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = nil
            menu.addItem(item)
        }
        
        let appearanceItem = NSMenuItem(title: AppLanguage.text("外观模式", en: "Appearance"),
                                        action: nil, keyEquivalent: "")
        let appearanceMenu = NSMenu()
        let appearanceModes: [(title: String, mode: AppearanceMode)] = [
            (AppLanguage.text("跟随系统", en: "System"), .default),
            (AppLanguage.text("浅色模式", en: "Light"), .light),
            (AppLanguage.text("深色模式", en: "Dark"), .dark),
        ]
        for (title, mode) in appearanceModes {
            let item = NSMenuItem(title: title,
                                  action: #selector(DocumentViewController.changeAppearance(_:)),
                                  keyEquivalent: "")
            item.target = nil
            item.tag = mode.rawValue
            appearanceMenu.addItem(item)
        }
        appearanceItem.submenu = appearanceMenu
        menu.addItem(appearanceItem)
        
        add(AppLanguage.text("自动换行", en: "Wrap Lines"),
            #selector(DocumentViewController.toggleLineWrap(_:)))
        add(AppLanguage.text("显示不可见字符", en: "Show Invisibles"),
            #selector(DocumentViewController.toggleInvisibleChars(_:)))
        add(AppLanguage.text("显示缩进参考线", en: "Show Indent Guides"),
            #selector(DocumentViewController.toggleIndentGuides(_:)))
        add(AppLanguage.text("显示页面参考线", en: "Show Page Guide"),
            #selector(DocumentViewController.togglePageGuide(_:)))
        menu.addItem(.separator())
        add(AppLanguage.text("AI 一键整理合并所有文档", en: "AI Organize & Merge All Documents"),
            #selector(AppDelegate.organizeAndMergeAllDocumentsFromMenu(_:)))
        menu.addItem(.separator())
        add(AppLanguage.text("并排平铺两窗口", en: "Tile Two Windows"),
            #selector(DocumentController.tileDocumentWindows(_:)))
        add(AppLanguage.text("切换分栏方向", en: "Toggle Split Orientation"),
            #selector(DocumentViewController.toggleSplitOrientation(_:)))
        add(AppLanguage.text("关闭当前分栏", en: "Close Split Editor"),
            #selector(DocumentViewController.closeSplitTextView(_:)))
        menu.addItem(.separator())
        add(AppLanguage.text("还原默认字号", en: "Reset Text Size"),
            #selector(EditorTextView.resetFont(_:)))
        add(AppLanguage.text("打印文档", en: "Print"),
            #selector(NSDocument.printDocument(_:)))
        add(AppLanguage.text("进入全屏", en: "Enter Full Screen"),
            #selector(NSWindow.toggleFullScreen(_:)))
        
        return menu
    }
}


/// One compact horizontal row of emoji buttons, used by the toolbar's emoji menu.
final class EmojiMenuRowView: NSView {
    
    init(emojis: [String]) {
        
        let buttonSize: CGFloat = 30
        super.init(frame: NSRect(x: 0, y: 0,
                                 width: CGFloat(emojis.count) * (buttonSize + 2),
                                 height: buttonSize))
        
        let stack = NSStackView(views: emojis.map { emoji in
            let button = NSButton(title: emoji, target: nil,
                                  action: #selector(DocumentViewController.insertQuickEmojiFromButton(_:)))
            button.isBordered = false
            button.setButtonType(.momentaryPushIn)
            button.font = Self.buttonFont
            button.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                button.widthAnchor.constraint(equalToConstant: buttonSize),
                button.heightAnchor.constraint(equalToConstant: buttonSize),
            ])
            return button
        })
        
        stack.orientation = .horizontal
        stack.spacing = 2
        stack.translatesAutoresizingMaskIntoConstraints = false
        self.addSubview(stack)
        
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: self.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: self.trailingAnchor),
            stack.topAnchor.constraint(equalTo: self.topAnchor),
            stack.bottomAnchor.constraint(equalTo: self.bottomAnchor),
        ])
    }
    
    
    /// The one font every button uses.
    ///
    /// Color emoji are drawn by the system emoji font whatever font is set here, so the point
    /// size is what makes them line up: one size for all of them keeps the grid even.
    private static var buttonFont: NSFont {
        
        .systemFont(ofSize: 17)
    }
    
    
    @available(*, unavailable)
    required init?(coder: NSCoder) {
        
        fatalError("init(coder:) has not been implemented")
    }
}


/// Popup button for the document type.
///
/// A stock `NSPopUpButton` presents its menu *above* itself, aligned with the selected
/// item. When the window sits at the top of the screen that runs off the top edge and
/// the menu gets clipped, so present the menu downward from the button's bottom edge.
final class SyntaxPopUpButton: NSPopUpButton {
    
    override func mouseDown(with event: NSEvent) {
        
        guard let menu = self.menu else { return super.mouseDown(with: event) }
        
        let origin = NSPoint(x: 0, y: self.isFlipped ? self.bounds.maxY + 4 : self.bounds.minY - 4)
        
        menu.popUp(positioning: nil, at: origin, in: self)
    }
}
