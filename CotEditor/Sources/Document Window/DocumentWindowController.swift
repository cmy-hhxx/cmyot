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
    private var focusObserver: AnyCancellable?
    private var editedStateObserver: AnyCancellable?
    private var isReviewingPaneDocuments = false
    private var splitLayoutObserver: AnyCancellable?
    private var pendingTitleVisibility: NSWindow.TitleVisibility?
    private var syntaxListObserver: AnyCancellable?
    private weak var syntaxPopUpButton: NSPopUpButton?
    
    
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
        
        
        if self.isDirectoryDocument {
            window.tabbingMode = .disallowed
        }
        
        
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
            .map { value in
                switch value {
                    case .default: nil
                    case .light: NSAppearance(named: .aqua)
                    case .dark: NSAppearance(named: .darkAqua)
                }
            }
            .assign(to: \.appearance, on: window)
        
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
        if let titleVisibility = self.pendingTitleVisibility {
            self.pendingTitleVisibility = nil
            self.window?.titleVisibility = titleVisibility
        }
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
            alert.messageText = "有固定的标签页，不能关闭窗口"
            alert.informativeText = "请先取消固定。"
            alert.alertStyle = .informational
            alert.addButton(withTitle: "好")
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
        
        // Lets the title bar offer the proxy icon and rename-on-double-click.
        self.window?.representedURL = self.fileDocument?.fileURL
        
        if self.isDirectoryDocument {
            // display current document title as window subtitle
            self.window?.subtitle = self.fileDocument?.fileURL?.lastPathComponent
                ?? self.fileDocument?.displayName
                ?? ""
        }
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
        }
        
        self.updateRestorability()
        self.updateTitleVisibility()
    }
    
    
    /// The document view controller of this window, if the window shows one.
    var documentViewController: DocumentViewController? {
        
        (self.contentViewController as? WindowContentViewController)?.documentViewController
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
    
    
    /// Hides the window title while the window is split into panes.
    ///
    /// Every pane names its document in its own navigation bar, so a window title would
    /// only duplicate one of them. The subtitle (the vim mode indicator) is left alone.
    private func updateTitleVisibility() {
        
        let titleVisibility: NSWindow.TitleVisibility = (self.documentViewController?.isSplit == true) ? .hidden : .visible
        
        guard let window = self.window else {
            // the split state can change before the window finishes loading
            self.pendingTitleVisibility = titleVisibility
            return
        }
        
        window.titleVisibility = titleVisibility
    }
    
    
    #if DEBUG
    /// Builds the scripted demo layout used for screenshot verification.
    ///
    /// Enabled by launching the app with `COT_UI_DEMO=1`. The delay lets the window and
    /// its pane tabs finish their first layout pass before the demo state is built.
    private func scheduleDemoLayoutIfNeeded() {
        
        // `open --args --ui-demo` is the reliable way to reach a sandboxed app
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
    #endif
    
    
    /// Makes the toolbar reflect the document of the focused pane.
    ///
    /// - Parameter document: The document the focused pane edits.
    private func followFocusedDocument(_ document: Document) {
        
        self.documentSyntaxObserver = document.$syntaxName
            .sink { [weak self] in self?.selectSyntaxPopUpItem(with: $0) }
        self.selectSyntaxPopUpItem(with: document.syntaxName)
        self.synchronizeWindowTitleWithDocumentName()
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
    
    static let document = Self("Document.personal.6")
    static let directoryDocument = Self("DirectoryDocument")
}


private extension NSToolbarItem.Identifier {
    
    private static let prefix = "com.coteditor.CotEditor.ToolbarItem."
    
    
    static let syntax = Self(Self.prefix + "syntaxStyle")
    static let quickEmoji = Self(Self.prefix + "quickEmoji")
    static let textScale = Self(Self.prefix + "textScale")
    static let more = Self(Self.prefix + "more")
    static let inspector = Self(Self.prefix + "inspector")
    
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
            .flexibleSpace,
        ])
    }
    
    
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        
        self.directoryIdentifiers + [
            .editable,
            .quickEmoji,
            .syntax,
            .textScale,
            .terminal,
            .aiSettings,
            .inspector,
            .more,
            .flexibleSpace,
        ]
    }
    
    
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        
        // Personal build: keep the toolbar minimal; Emoji & Symbols stays.
        var identifiers = self.directoryIdentifiers + [
            .editable,
            .quickEmoji,
            .syntax,
            .textScale,
            .textSize,
            .inspector,
            .terminal,
            .aiSettings,
            .more,
            .space,
            .flexibleSpace,
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
                item.label = String(localized: "Toolbar.syntax.label",
                                    defaultValue: "Syntax", table: "Document")
                item.toolTip = String(localized: "Toolbar.syntax.tooltip",
                                      defaultValue: "Change syntax", table: "Document")
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
                slider.toolTip = "文字大小（无极）"
                slider.translatesAutoresizingMaskIntoConstraints = false
                NSLayoutConstraint.activate([slider.widthAnchor.constraint(equalToConstant: 96)])
                
                let item = NSToolbarItem(itemIdentifier: itemIdentifier)
                item.label = "文字大小"
                item.toolTip = "拖动调整文字大小"
                item.view = slider
                item.isNavigational = true
                item.visibilityPriority = .high
                return item
                
            case .quickEmoji:
                let item = NSMenuToolbarItem(itemIdentifier: itemIdentifier)
                item.isBordered = true
                item.showsIndicator = false
                item.isNavigational = true
                item.label = "Emoji"
                item.toolTip = "常用 Emoji"
                item.image = NSImage(systemSymbolName: "face.smiling.inverse", accessibilityDescription: item.label)
                    ?? NSImage(systemSymbolName: "face.smiling", accessibilityDescription: item.label)
                item.menu = Self.quickEmojiMenu()
                return item
                
            case .more:
                let item = NSMenuToolbarItem(itemIdentifier: itemIdentifier)
                item.isBordered = true
                item.showsIndicator = false
                item.label = "更多"
                item.toolTip = "更多操作"
                item.image = NSImage(systemSymbolName: "ellipsis.circle", accessibilityDescription: item.label)
                item.menu = Self.moreMenu()
                return item
                
            case .aiSettings:
                let item = NSToolbarItem(itemIdentifier: itemIdentifier)
                item.isBordered = true
                item.label = "AI"
                item.toolTip = "配置 AI：接口地址、模型、API Key"
                item.image = NSImage(systemSymbolName: "sparkles", accessibilityDescription: item.label)
                item.target = NSApp.delegate
                item.action = #selector(AppDelegate.showAIPreferences(_:))
                item.isNavigational = true
                item.visibilityPriority = .high
                return item
                
            case .terminal:
                let item = NSToolbarItem(itemIdentifier: itemIdentifier)
                item.isBordered = true
                item.label = "终端"
                item.toolTip = "在当前窗口显示或隐藏终端"
                item.image = NSImage(systemSymbolName: "terminal", accessibilityDescription: item.label)
                item.action = #selector(ContentViewController.toggleTerminal(_:))
                // keep it next to the other leading controls, and out of the overflow menu
                item.isNavigational = true
                item.visibilityPriority = .high
                return item
                
            case .inspector:
                let item = NSToolbarItem(itemIdentifier: itemIdentifier)
                item.isBordered = true
                item.label = String(localized: "Toolbar.inspector.label",
                                    defaultValue: "Inspector", table: "Document")
                item.toolTip = String(localized: "Toolbar.inspector.tooltip",
                                      defaultValue: "Show inspector", table: "Document")
                item.image = NSImage(systemSymbolName: "info.circle", accessibilityDescription: item.label)
                item.action = #selector(NSSplitViewController.toggleInspector)
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
                item.label = String(localized: "Toolbar.editable.label",
                                    defaultValue: "Edit", table: "Document")
                item.toolTip = String(localized: "Toolbar.editable.tooltip.off",
                                      defaultValue: "Prevent the document from being edited", table: "Document")
                item.stateImages[.on] = NSImage(systemSymbolName: "pencil", accessibilityDescription: item.label)
                item.stateImages[.off] = NSImage(systemSymbolName: "pencil.slash", accessibilityDescription: item.label)
                item.action = #selector(Document.toggleEditable)
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
    
    /// A titled group of curated emoji in the toolbar's quick-insert menu.
    ///
    /// Groups carry a heading so the menu reads as sections rather than one long
    /// undifferentiated wall of rows.
    private struct QuickEmojiSection {
        
        let title: String
        let rows: [[String]]
    }
    
    
    /// Curated emoji grouped by purpose, laid out as compact rows instead of one long column.
    ///
    /// Ordered from the palettes used most often while writing notes — progress and
    /// priority first — down to the general-purpose markers.
    private static let quickEmojiSections: [QuickEmojiSection] = [
        QuickEmojiSection(title: "进度", rows: [
            ["○", "◔", "◑", "◕", "●", "◌"],
        ]),
        QuickEmojiSection(title: "优先级", rows: [
            ["🔴", "🟠", "🟡", "🟢", "🔵", "⚪"],
        ]),
        QuickEmojiSection(title: "状态", rows: [
            ["✅", "❌", "✔️", "✖️", "☐", "☑"],
        ]),
        QuickEmojiSection(title: "标记", rows: [
            ["⭐", "🔥", "📌", "📝", "💡"],
            ["⚠️", "❓", "❗", "🚧", "🐛", "🔖"],
        ]),
        QuickEmojiSection(title: "流程", rows: [
            ["⏳", "⏰", "📚", "🔧", "🚀", "📦"],
        ]),
    ]
    
    
    static func quickEmojiMenu() -> NSMenu {
        
        let menu = NSMenu()
        for (index, section) in Self.quickEmojiSections.enumerated() {
            if index > 0 {
                menu.addItem(.separator())
            }
            menu.addItem(EmojiMenuSectionHeaderView.makeItem(title: section.title))
            
            for emojis in section.rows {
                let item = NSMenuItem()
                item.view = EmojiMenuRowView(emojis: emojis)
                menu.addItem(item)
            }
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
        
        let appearanceItem = NSMenuItem(title: "外观", action: nil, keyEquivalent: "")
        let appearanceMenu = NSMenu()
        for (title, mode) in [("跟随系统", AppearanceMode.default), ("浅色", .light), ("深色", .dark)] {
            let item = NSMenuItem(title: title,
                                  action: #selector(DocumentViewController.changeAppearance(_:)),
                                  keyEquivalent: "")
            item.target = nil
            item.tag = mode.rawValue
            appearanceMenu.addItem(item)
        }
        appearanceItem.submenu = appearanceMenu
        menu.addItem(appearanceItem)
        
        add("折行", #selector(DocumentViewController.toggleLineWrap(_:)))
        add("不可见字符", #selector(DocumentViewController.toggleInvisibleChars(_:)))
        add("缩进参考线", #selector(DocumentViewController.toggleIndentGuides(_:)))
        add("页面参考线", #selector(DocumentViewController.togglePageGuide(_:)))
        menu.addItem(.separator())
        add("并排两个窗口", #selector(DocumentController.tileDocumentWindows(_:)))
        add("切换分割方向", #selector(DocumentViewController.toggleSplitOrientation(_:)))
        add("关闭分割", #selector(DocumentViewController.closeSplitTextView(_:)))
        menu.addItem(.separator())
        add("重置文字大小", #selector(EditorTextView.resetFont(_:)))
        add("打印…", #selector(NSDocument.printDocument(_:)))
        add("进入全屏", #selector(NSWindow.toggleFullScreen(_:)))
        
        return menu
    }
}


/// Section heading shown above each group in the toolbar's emoji menu.
final class EmojiMenuSectionHeaderView: NSView {
    
    static func makeItem(title: String) -> NSMenuItem {
        
        let item = NSMenuItem()
        item.view = EmojiMenuSectionHeaderView(title: title)
        return item
    }
    
    
    private init(title: String) {
        
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 11, weight: .semibold)
        label.textColor = .secondaryLabelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        
        super.init(frame: .zero)
        
        self.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: self.leadingAnchor, constant: 10),
            label.topAnchor.constraint(equalTo: self.topAnchor, constant: 2),
            label.bottomAnchor.constraint(equalTo: self.bottomAnchor, constant: -4),
        ])
    }
    
    
    @available(*, unavailable)
    required init?(coder: NSCoder) {
        
        fatalError("init(coder:) has not been implemented")
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
            button.font = Self.font(for: emoji)
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
    
    
    /// Font for one emoji button.
    ///
    /// The geometric progress glyphs (`◔` `◑` `◕`) are not in the system font and
    /// render noticeably smaller and thinner than the emoji beside them, so they get a
    /// monospaced font at a larger size to match the emoji's visual weight.
    private static func font(for emoji: String) -> NSFont {
        
        guard let scalar = emoji.unicodeScalars.first, scalar.value < 0x2B00 else {
            return .systemFont(ofSize: 17)
        }
        
        let size: CGFloat = 22
        return NSFont(name: "Menlo", size: size)
            ?? NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
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
