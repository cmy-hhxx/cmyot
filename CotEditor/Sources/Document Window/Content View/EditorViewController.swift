//
//  EditorViewController.swift
//
//  CotEditor
//  https://coteditor.com
//
//  Created by nakamuxu on 2006-03-18.
//
//  ---------------------------------------------------------------------------
//
//  © 2004-2007 nakamuxu
//  © 2014-2026 1024jp
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
import Defaults

/// One pane of a document window: a tab bar on top and one document per tab.
///
/// A pane is a tab group in the browser sense. Only the selected tab's text view is in
/// the view hierarchy; the other tabs keep their text view controller alive so that
/// scroll position, selection and undo history survive switching back and forth.
final class EditorViewController: NSSplitViewController {
    
    // MARK: Public Properties
    
    /// The document of the selected tab.
    var document: Document  { self.selectedTab.document }
    
    /// The text view of the selected tab.
    var textView: EditorTextView?  { self.textViewController(for: self.selectedTab)?.textView }
    
    /// The text views of every tab, including the ones not currently shown.
    var allTextViews: [EditorTextView]  {
        self.tabs.compactMap { self.textViewControllers[ObjectIdentifier($0)]?.textView }
    }
    
    /// Whether at least one tab in this pane is pinned.
    var hasPinnedTab: Bool  {
        self.tabs.contains(where: \.isPinned)
    }
    
    /// The tabs of this pane in visual order.
    private(set) var tabs: [PaneTab]
    
    /// The tab whose document is currently shown.
    private(set) var selectedTab: PaneTab
    
    
    // MARK: Callbacks
    
    /// Requests a new tab in this pane.
    var requestNewTab: (() -> Void)?
    
    /// Requests closing one of the tabs.
    var requestCloseTab: ((PaneTab) -> Void)?
    
    /// Requests closing this pane as a whole.
    var requestClosePane: (() -> Void)?
    
    /// Called after the user switched the tab.
    var didSelectTab: ((PaneTab) -> Void)?
    
    /// Requests renaming the document backing a tab.
    var requestRenameTab: ((PaneTab, String) -> Void)?
    
    /// Requests moving a dragged tab (from any pane or window) onto this pane's tab bar at an optional insertion index.
    var requestDropTabAtIndex: ((UUID, Int?) -> Bool)?
    
    /// Requests dropping a dragged tab (from any pane or window) onto this pane's content area or split edge.
    var requestDropTabInZone: ((UUID, PaneDropZone) -> Bool)?
    
    /// Requests detaching a tab into its own window at the given screen coordinate.
    var requestDetachTabToNewWindow: ((PaneTab, NSPoint) -> Void)?
    
    /// Called when tab order or pin state changes inside this pane.
    var didChangeTabLayout: (() -> Void)?
    
    
    // MARK: Private Properties
    
    private let splitState: SplitState
    private let tabState = PaneTabState()
    
    private lazy var outlineNavigator = OutlineNavigator()
    private lazy var contentViewController = PaneContentViewController()
    private lazy var navigationBarViewController = PaneNavigationBarViewController(
        outlineNavigator: self.outlineNavigator,
        splitState: self.splitState,
        tabs: self.tabState
    )
    @ViewLoading private var navigationBarItem: NSSplitViewItem
    
    private var textViewControllers: [ObjectIdentifier: EditorTextViewController] = [:]
    private weak var contentChild: EditorTextViewController?
    private weak var dropOverlayView: PaneDropOverlayView?
    private var dropOverlayGeneration = 0
    
    private var outlineObserver: AnyCancellable?
    private var defaultObservers: Set<AnyCancellable> = []
    
    var isRenamingTab: Bool { self.navigationBarViewController.isRenamingTab }
    private(set) var suppressesEditorFocusOnTabSelect = false
    
    
    // MARK: Lifecycle
    
    init(document: Document, splitState: SplitState) {
        
        let tab = PaneTab(document: document)
        self.tabs = [tab]
        self.selectedTab = tab
        self.splitState = splitState
        
        super.init(nibName: nil, bundle: nil)
    }
    
    
    required init?(coder: NSCoder) {
        
        fatalError("init(coder:) has not been implemented")
    }
    
    
    override func viewDidLoad() {
        
        super.viewDidLoad()
        
        self.splitView.isVertical = false
        
        // the text view of the initial tab is created first so that the tab bar can bind
        // its outline navigator to it right away
        self.textViewController(for: self.selectedTab)?.loadViewIfNeeded()
        
        // setup the tab bar
        self.tabState.onSelect = { [weak self] tab in self?.select(tab: tab) }
        self.tabState.onSelectForRename = { [weak self] tab in self?.select(tab: tab, focusEditor: false) }
        self.tabState.onClose = { [weak self] tab in self?.requestCloseTab?(tab) }
        self.tabState.onNewTab = { [weak self] in self?.requestNewTab?() }
        self.tabState.onTogglePin = { [weak self] tab in self?.togglePin(of: tab) }
        self.tabState.onRename = { [weak self] tab, newName in
            self?.requestRenameTab?(tab, newName)
        }
        self.tabState.onMove = { [weak self] draggedTab, targetTab in
            self?.move(tab: draggedTab, onto: targetTab)
        }
        self.tabState.onMoveToIndex = { [weak self] draggedTab, index in
            self?.move(tab: draggedTab, toIndex: index)
        }
        self.tabState.onDropTab = { [weak self] draggedID, targetIndex in
            guard let self else { return false }
            if let localTab = self.tabs.first(where: { $0.id == draggedID }) {
                if let targetIndex {
                    self.move(tab: localTab, toIndex: targetIndex)
                }
                return true
            }
            return self.requestDropTabAtIndex?(draggedID, targetIndex) ?? false
        }
        self.tabState.onDetachToNewWindow = { [weak self] tab, screenPoint in
            self?.requestDetachTabToNewWindow?(tab, screenPoint)
        }
        self.tabState.onClosePane = { [weak self] in self?.requestClosePane?() }
        
        self.outlineNavigator.textView = self.textView
        self.navigationBarItem = NSSplitViewItem(viewController: self.navigationBarViewController)
        self.navigationBarItem.isCollapsed = true  // reconsidered below
        let barHeight: CGFloat = isLiquidGlass ? 30 : 28
        self.navigationBarItem.minimumThickness = barHeight
        self.navigationBarItem.maximumThickness = barHeight
        self.navigationBarItem.holdingPriority = NSLayoutConstraint.Priority(260)
        self.addSplitViewItem(self.navigationBarItem)
        
        // setup the content area that hosts the selected tab's text view
        self.contentViewController.pane = self
        let contentItem = NSSplitViewItem(viewController: self.contentViewController)
        contentItem.canCollapse = false
        self.addSplitViewItem(contentItem)
        
        self.installContent(of: self.selectedTab)
        self.updateTabState()
        
        // set accessibility
        self.view.setAccessibilityElement(true)
        self.view.setAccessibilityRole(.group)
        self.view.setAccessibilityLabel(String(localized: "Editor", table: "Document", comment: "accessibility label"))
    }
    
    
    override func viewWillAppear() {
        
        super.viewWillAppear()
        
        // the text views only exist from here on, so this is the first moment the stored
        // highlights can be painted
        self.document.applyHighlightRendering()
        
        self.observeOutline(of: self.selectedTab.document)
        self.defaultObservers = [
            UserDefaults.standard.publisher(for: .showNavigationBar)
                .sink { [weak self] _ in self?.updateNavigationBarVisibility() },
            
            // keep the tab titles and dirty dots in sync with the documents
            NotificationCenter.default.publisher(for: NSDocument.DidChangeFileURLMessage.name)
                .sink { [weak self] notification in
                    guard
                        let self,
                        let document = notification.object as? Document,
                        self.tabs.contains(where: { $0.document === document })
                    else { return }
                    
                    self.updateTabState()
                },
            NotificationCenter.default.publisher(for: Document.DidUpdateChangeMessage.name)
                .sink { [weak self] notification in
                    guard
                        let self,
                        let document = notification.object as? Document,
                        self.tabs.contains(where: { $0.document === document })
                    else { return }
                    
                    self.updateTabState()
                },
        ]
        
        self.updateNavigationBarVisibility()
    }
    
    
    override func viewDidDisappear() {
        
        super.viewDidDisappear()
        
        self.outlineObserver?.cancel()
        self.defaultObservers.removeAll()
    }
    
    
    // MARK: Tab Management
    
    /// Adds a document as a new tab and selects it.
    ///
    /// - Parameters:
    ///   - document: The document the new tab shows.
    ///   - index: Optional target index to insert the tab at.
    /// - Returns: The created tab.
    @discardableResult
    func addTab(document: Document, at index: Int? = nil) -> PaneTab {
        
        let tab = PaneTab(document: document)
        self.makeTextViewController(for: tab).loadViewIfNeeded()
        
        if let index, index >= 0, index <= self.tabs.count {
            self.tabs.insert(tab, at: index)
        } else {
            self.tabs.append(tab)
        }
        self.select(tab: tab)
        
        return tab
    }
    
    
    /// Returns the text view of the given tab, loading it when needed.
    ///
    /// - Parameter tab: The tab to get the text view for.
    /// - Returns: The text view of the tab, or `nil` if the tab is foreign.
    func textView(for tab: PaneTab) -> EditorTextView? {
        
        self.textViewController(for: tab)?.textView
    }
    
    
    /// Removes a tab from the pane.
    ///
    /// The caller is responsible for closing the document itself; this only detaches the
    /// document from the pane.
    ///
    /// - Parameter tab: The tab to remove.
    func removeTab(_ tab: PaneTab) {
        
        guard let index = self.tabs.firstIndex(where: { $0 === tab }) else { return }
        
        self.tabs.remove(at: index)
        
        let selectedWasRemoved = (self.selectedTab === tab)
        
        if let textViewController = self.textViewControllers.removeValue(forKey: ObjectIdentifier(tab)),
           self.contentChild === textViewController
        {
            textViewController.view.removeFromSuperview()
            textViewController.removeFromParent()
            self.contentChild = nil
        }
        
        if selectedWasRemoved {
            let nextTab = self.tabs[safe: index] ?? self.tabs.last
            if let nextTab {
                self.selectedTab = nextTab
                self.installContent(of: nextTab)
                self.observeOutline(of: nextTab.document)
                nextTab.document.applyHighlightRendering()
            }
        }
        
        self.updateTabState()
        self.updateNavigationBarVisibility(animated: true)
    }
    
    
    /// Selects the given tab and shows its document.
    ///
    /// - Parameters:
    ///   - tab: The tab to select.
    ///   - focusEditor: Whether selecting the tab should move responder focus into the editor text view.
    func select(tab: PaneTab, focusEditor: Bool = true) {
        
        guard self.tabs.contains(where: { $0 === tab }) else { return }
        
        let didChange = (tab !== self.selectedTab)
        self.suppressesEditorFocusOnTabSelect = !focusEditor
        defer { self.suppressesEditorFocusOnTabSelect = false }
        
        self.selectedTab = tab
        
        self.installContent(of: tab)
        self.updateTabState()
        self.observeOutline(of: tab.document)
        tab.document.applyHighlightRendering()
        self.updateNavigationBarVisibility()
        
        if focusEditor, let textView = self.textView {
            textView.updateInsertionPointStateAndRestartTimer(true)
            textView.needsDisplay = true
        }
        
        if didChange {
            self.didSelectTab?(tab)
        }
    }
    
    
    /// Starts inline tab renaming for the tab displaying `document` in this pane.
    @discardableResult
    func beginInlineRename(for document: Document) -> Bool {
        
        guard let tab = self.tabs.first(where: { $0.document === document }) else { return false }
        self.select(tab: tab, focusEditor: false)
        DispatchQueue.main.async { [weak self] in
            self?.tabState.onRequestInlineRename?(tab)
        }
        return true
    }
    
    
    /// Tells whether the given text view belongs to this pane.
    ///
    /// - Parameter textView: The text view to test.
    /// - Returns: `true` if one of the tabs of this pane owns the text view.
    func contains(_ textView: NSTextView) -> Bool {
        
        self.textViewControllers.values.contains { $0.textView === textView }
    }
    
    
    /// Returns the document that owns the given text view.
    ///
    /// - Parameter textView: A text view shown in one of the tabs.
    /// - Returns: The document of the tab, or `nil` if the text view is foreign.
    func document(for textView: NSTextView) -> Document? {
        
        self.tabs.first { self.textViewControllers[ObjectIdentifier($0)]?.textView === textView }?.document
    }
    
    
    /// Toggles whether the whole pane can be closed.
    ///
    /// - Parameter canClose: `true` when the window is split and this pane does not
    ///   contain the window's own document.
    func setCanClosePane(_ canClose: Bool) {
        
        guard self.tabState.canClosePane != canClose else { return }
        
        self.tabState.canClosePane = canClose
        self.updateNavigationBarVisibility()
    }
    
    
    /// Pushes the current tab list to the tab bar.
    func updateTabState() {
        
        self.tabState.tabs = self.tabs
        self.tabState.selectedTab = self.selectedTab
        self.tabState.refreshRevision &+= 1
        self.navigationBarViewController.reloadTabs()
        self.updateNavigationBarVisibility(animated: true)
    }
    
    
    // MARK: Split View Controller Methods
    
    override func splitView(_ splitView: NSSplitView, effectiveRect proposedEffectiveRect: NSRect, forDrawnRect drawnRect: NSRect, ofDividerAt dividerIndex: Int) -> NSRect {
        
        // avoid showing draggable cursor for the tab bar boundary
        .zero
    }
    
    
    override func validateUserInterfaceItem(_ item: any NSValidatedUserInterfaceItem) -> Bool {
        
        switch item.action {
            case #selector(save), #selector(saveAs):
                // this pane forwards the action to its own document
                return true
                
            case #selector(NSDocument.move(_:)):
                return !self.tabs.isEmpty
                
            case #selector(toggleNavigationBar):
                (item as? NSMenuItem)?.title = !self.navigationBarItem.isCollapsed
                    ? String(localized: "Hide Navigation Bar", table: "MainMenu")
                    : String(localized: "Show Navigation Bar", table: "MainMenu")
                
            case #selector(openOutlineMenu):
                return self.outlineNavigator.items?.isEmpty == false
                
            case #selector(selectPrevItemOfOutlineMenu):
                return self.outlineNavigator.canSelectPreviousItem
                
            case #selector(selectNextItemOfOutlineMenu):
                return self.outlineNavigator.canSelectNextItem
                
            default: break
        }
        
        return super.validateUserInterfaceItem(item)
    }
    
    
    // MARK: Public Methods
    
    /// Whether line number view is visible in this pane.
    ///
    /// Line numbers belong to the pane, so `:set number` in one pane leaves the panes beside it
    /// alone. The most recent choice is also written back to the shared default, which is what
    /// a new window (and a new pane) starts with.
    var showsLineNumber: Bool {
        
        get { self.textViewController(for: self.selectedTab)?.showsLineNumber ?? false }
        set {
            // every tab gets the toggle, so switching tabs does not flip the setting
            self.textViewControllers.values.forEach { $0.showsLineNumber = newValue }
            
            if UserDefaults.standard[.showLineNumbers] != newValue {
                UserDefaults.standard[.showLineNumbers] = newValue
            }
        }
    }
    
    
    /// Shows the tab bar only when it has something to offer: more than one tab, a split,
    /// outline navigation or a pinned tab. An empty bar is pure visual noise.
    ///
    /// - Parameter animated: `true` to animate the collapse.
    func updateNavigationBarVisibility(animated: Bool = false) {
        
        guard self.isViewLoaded else { return }
        
        let hasContent = !self.tabs.isEmpty
            || self.splitState.canClose
            || self.hasPinnedTab
            || self.outlineNavigator.items?.isEmpty == false
        let shouldShow = UserDefaults.standard[.showNavigationBar] && hasContent
        
        guard shouldShow != !self.navigationBarItem.isCollapsed else { return }
        
        if animated {
            NSAnimationContext.withStandardTiming {
                self.navigationBarItem.animator().isCollapsed = !shouldShow
            }
        } else {
            self.navigationBarItem.isCollapsed = !shouldShow
        }
    }
    
    
    // MARK: Action Messages
    
    /// Saves the document this pane edits, whatever window it is shown in.
    @objc(saveDocument:) @IBAction func save(_ sender: Any?) {
        
        self.document.performQuickSave(sender)
        self.updateTabState()
    }
    
    
    /// Saves the document this pane edits under a new name.
    @objc(saveDocumentAs:) @IBAction func saveAs(_ sender: Any?) {
        
        self.document.saveAs(sender)
    }
    
    
    /// Starts inline tab renaming for this pane's active document (File → Rename…).
    @objc func move(_ sender: Any?) {
        
        if self.beginInlineRename(for: self.selectedTab.document) {
            return
        }
        self.document.move(sender)
    }
    
    
    /// Changes the syntax of the document this pane edits.
    @IBAction func changeSyntax(_ sender: NSMenuItem) {
        
        self.document.changeSyntax(sender)
    }
    
    
    /// Toggles visibility of navigation bar with fancy animation (sync all documents).
    @IBAction func toggleNavigationBar(_ sender: Any?) {
        
        UserDefaults.standard[.showNavigationBar].toggle()
    }
    
    
    /// Shows the menu items of the outline menu in the navigation bar.
    @IBAction func openOutlineMenu(_ sender: Any) {
        
        self.navigationBarItem.isCollapsed = false
        self.outlineNavigator.isOutlinePickerPresented = true
    }
    
    
    /// Selects the previous outline item.
    @IBAction func selectPrevItemOfOutlineMenu(_ sender: Any?) {
        
        self.outlineNavigator.selectPreviousItem()
    }
    
    
    /// Selects the next outline item.
    @IBAction func selectNextItemOfOutlineMenu(_ sender: Any?) {
        
        self.outlineNavigator.selectNextItem()
    }
    
    
    // MARK: Private Methods
    
    /// Returns the text view controller of the given tab, creating it when needed.
    ///
    /// - Parameter tab: The tab to get the text view controller for.
    /// - Returns: The controller showing the tab's document.
    private func textViewController(for tab: PaneTab) -> EditorTextViewController? {
        
        guard self.tabs.contains(where: { $0 === tab }) else { return nil }
        
        if let textViewController = self.textViewControllers[ObjectIdentifier(tab)] {
            return textViewController
        }
        
        return self.makeTextViewController(for: tab)
    }
    
    
    /// Creates and caches the text view controller of the given tab.
    ///
    /// - Parameter tab: The tab to create the text view controller for.
    /// - Returns: The created controller.
    private func makeTextViewController(for tab: PaneTab) -> EditorTextViewController {
        
        if let textViewController = self.textViewControllers[ObjectIdentifier(tab)] {
            return textViewController
        }
        
        let textViewController = EditorTextViewController(document: tab.document)
        self.textViewControllers[ObjectIdentifier(tab)] = textViewController
        
        return textViewController
    }
    
    
    /// Installs the text view of the given tab in the content area.
    ///
    /// - Parameter tab: The tab to show.
    private func installContent(of tab: PaneTab) {
        
        guard let textViewController = self.textViewController(for: tab) else { return }
        
        if let current = self.contentChild, current !== textViewController {
            current.view.removeFromSuperview()
            current.removeFromParent()
        }
        
        if self.contentChild !== textViewController {
            self.contentViewController.addChild(textViewController)
            
            let view = textViewController.view
            view.translatesAutoresizingMaskIntoConstraints = false
            self.contentViewController.view.addSubview(view)
            
            NSLayoutConstraint.activate([
                view.leadingAnchor.constraint(equalTo: self.contentViewController.view.leadingAnchor),
                view.trailingAnchor.constraint(equalTo: self.contentViewController.view.trailingAnchor),
                view.topAnchor.constraint(equalTo: self.contentViewController.view.topAnchor),
                view.bottomAnchor.constraint(equalTo: self.contentViewController.view.bottomAnchor),
            ])
            
            self.contentChild = textViewController
        }
        
        self.outlineNavigator.textView = textViewController.textView
    }
    
    
    /// Observes the outline of the given document, replacing the previous observation.
    ///
    /// - Parameter document: The document of the selected tab.
    private func observeOutline(of document: Document) {
        
        self.outlineNavigator.items = document.syntaxController.outlineItems
        self.outlineObserver = document.syntaxController.$outlineItems
            .removeDuplicates()
            .sink { [weak self] items in
                self?.outlineNavigator.items = items
                self?.updateNavigationBarVisibility(animated: true)
            }
    }
    
    
    #if DEBUG
    /// Drives the tab bar callbacks in the demo self-test.
    func debugSelect(_ tab: PaneTab) {
        
        self.tabState.onSelect(tab)
    }
    
    
    /// Drives the tab bar callbacks in the demo self-test.
    func debugTogglePin(_ tab: PaneTab) {
        
        self.tabState.onTogglePin(tab)
    }
    #endif
    
    
    /// Moves a dragged tab next to the tab it was dropped on.
    func reorderTab(_ tab: PaneTab, onto target: PaneTab) {
        
        self.move(tab: tab, onto: target)
    }
    
    
    /// Moves a dragged tab next to the tab it was dropped on.
    ///
    /// Dragging to the right inserts the tab after the target; dragging to the left
    /// inserts it before, which is the direction users expect from the drop position.
    ///
    /// - Parameters:
    ///   - tab: The dragged tab.
    ///   - target: The tab it was dropped on.
    private func move(tab: PaneTab, onto target: PaneTab) {
        
        guard
            tab !== target,
            let from = self.tabs.firstIndex(where: { $0 === tab }),
            let to = self.tabs.firstIndex(where: { $0 === target })
        else { return }
        
        self.tabs.remove(at: from)
        self.tabs.insert(tab, at: to)
        
        self.updateTabState()
        self.updateNavigationBarVisibility(animated: true)
        self.didChangeTabLayout?()
    }
    
    
    /// Moves a dragged tab to an insertion index captured prior to removal.
    private func move(tab: PaneTab, toIndex insertionIndex: Int) {
        
        guard let from = self.tabs.firstIndex(where: { $0 === tab }) else { return }
        var destination = max(0, min(insertionIndex, self.tabs.count))
        if from < destination {
            destination -= 1
        }
        guard from != destination, destination >= 0, destination < self.tabs.count else { return }
        
        self.tabs.remove(at: from)
        self.tabs.insert(tab, at: destination)
        
        self.updateTabState()
        self.updateNavigationBarVisibility(animated: true)
        self.didChangeTabLayout?()
    }
    
    
    // MARK: Pane Content Drop Handling
    
    func canAcceptPaneTabDrop(_ sender: any NSDraggingInfo) -> Bool {
        
        guard let draggedID = Self.extractTabID(from: sender.draggingPasteboard) else { return false }
        return !self.tabs.contains(where: { $0.id == draggedID })
    }
    
    
    func paneDragEntered(_ sender: any NSDraggingInfo, in textView: EditorTextView? = nil) -> NSDragOperation {
        
        self.paneDragUpdated(sender, in: textView)
    }
    
    
    func paneDragUpdated(_ sender: any NSDraggingInfo, in textView: EditorTextView? = nil) -> NSDragOperation {
        
        guard self.canAcceptPaneTabDrop(sender) else {
            self.hideDropOverlay()
            return []
        }
        
        self.showDropOverlay(for: .center)
        return .move
    }
    
    
    func paneDragExited(_ sender: (any NSDraggingInfo)?) {
        
        self.hideDropOverlay()
    }
    
    
    func panePerformDragOperation(_ sender: any NSDraggingInfo, in textView: EditorTextView? = nil) -> Bool {
        
        defer { self.hideDropOverlay() }
        
        guard
            let draggedID = Self.extractTabID(from: sender.draggingPasteboard),
            !self.tabs.contains(where: { $0.id == draggedID })
        else { return false }
        
        return self.requestDropTabInZone?(draggedID, .center) ?? false
    }
    
    
    private static func extractTabID(from pasteboard: NSPasteboard) -> UUID? {
        
        if let raw = pasteboard.string(forType: PaneTab.dragPasteboardType),
           let id = UUID(uuidString: raw.trimmingCharacters(in: .whitespacesAndNewlines))
        {
            return id
        }
        if let raw = pasteboard.string(forType: .string) {
            return PaneTab.tabID(from: raw)
        }
        return nil
    }
    
    
    private func showDropOverlay(for zone: PaneDropZone) {
        
        self.dropOverlayGeneration &+= 1
        let containerView = self.contentViewController.view
        let overlay: PaneDropOverlayView
        let isNewOverlay: Bool
        if let existing = self.dropOverlayView, existing.superview === containerView {
            overlay = existing
            isNewOverlay = false
        } else {
            let created = PaneDropOverlayView(frame: containerView.bounds)
            created.autoresizingMask = [.width, .height]
            created.alphaValue = AnimationConstants.isReducedMotionEnabled ? 1 : 0
            containerView.addSubview(created, positioned: .above, relativeTo: nil)
            self.dropOverlayView = created
            overlay = created
            isNewOverlay = true
        }
        overlay.frame = containerView.bounds
        overlay.zone = zone
        
        if !AnimationConstants.isReducedMotionEnabled && (isNewOverlay || overlay.alphaValue < 0.99) {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.16
                ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 1.0, 0.36, 1.0)
                overlay.animator().alphaValue = 1
            }
        } else {
            overlay.alphaValue = 1
        }
    }
    
    
    private func hideDropOverlay() {
        
        guard let overlay = self.dropOverlayView else { return }
        self.dropOverlayGeneration &+= 1
        let expectedGeneration = self.dropOverlayGeneration
        
        if AnimationConstants.isReducedMotionEnabled {
            overlay.removeFromSuperview()
            self.dropOverlayView = nil
            return
        }
        
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.14
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            overlay.animator().alphaValue = 0
        } completionHandler: { [weak self, weak overlay] in
            MainActor.assumeIsolated {
                guard let self, self.dropOverlayGeneration == expectedGeneration, let overlay else { return }
                overlay.removeFromSuperview()
                if self.dropOverlayView === overlay {
                    self.dropOverlayView = nil
                }
            }
        }
    }
    
    
    /// Pins or unpins the given tab during session restoration.
    func togglePinForRestoration(of tab: PaneTab) {
        
        self.togglePin(of: tab)
    }
    
    
    /// Pins or unpins the given tab.
    ///
    /// Pinning just marks the tab and moves it to the front of the bar; the tab keeps its
    /// title and only gains a pin. Unpinning leaves the tab where it is.
    ///
    /// - Parameter tab: The tab to toggle.
    private func togglePin(of tab: PaneTab) {
        
        tab.isPinned.toggle()
        
        if tab.isPinned, let index = self.tabs.firstIndex(where: { $0 === tab }), index > 0 {
            self.tabs.remove(at: index)
            self.tabs.insert(tab, at: 0)
        }
        
        self.updateTabState()
        self.updateNavigationBarVisibility(animated: true)
        self.didChangeTabLayout?()
    }
}


/// A plain container that fills its pane, hosts the selected tab's text view,
/// and accepts pane-tab drops across gutters and padding around the text view.
private final class PaneContentViewController: NSViewController {
    
    weak var pane: EditorViewController?
    
    override func loadView() {
        
        let container = PaneDropContainerView()
        container.paneProvider = { [weak self] in self?.pane }
        self.view = container
    }
}


private final class PaneDropContainerView: NSView {
    
    var paneProvider: (() -> EditorViewController?)?
    
    override init(frame frameRect: NSRect) {
        
        super.init(frame: frameRect)
        self.registerForDraggedTypes([PaneTab.dragPasteboardType])
    }
    
    required init?(coder: NSCoder) {
        
        fatalError("init(coder:) has not been implemented")
    }
    
    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        self.paneProvider?()?.paneDragEntered(sender) ?? []
    }
    
    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        self.paneProvider?()?.paneDragUpdated(sender) ?? []
    }
    
    override func draggingExited(_ sender: (any NSDraggingInfo)?) {
        self.paneProvider?()?.paneDragExited(sender)
    }
    
    override func prepareForDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        self.paneProvider?()?.canAcceptPaneTabDrop(sender) ?? false
    }
    
    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        self.paneProvider?()?.panePerformDragOperation(sender) ?? false
    }
}


/// Translucent edge/center drop zone indicator drawn above a pane during tab drag-and-drop.
private final class PaneDropOverlayView: NSView {
    
    var zone: PaneDropZone = .center {
        didSet {
            if self.zone != oldValue {
                self.needsDisplay = true
            }
        }
    }
    
    override var isOpaque: Bool { false }
    
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    
    override func draw(_ dirtyRect: NSRect) {
        
        let bounds = self.bounds.insetBy(dx: 6, dy: 6)
        guard bounds.width > 12, bounds.height > 12 else { return }
        
        let highlightRect: NSRect
        let label: String
        switch self.zone {
            case .center:
                highlightRect = bounds
                label = String(localized: "chrome.dropZone.moveToPane", defaultValue: "移动到此分栏", table: "Chrome")
            case .left:
                highlightRect = NSRect(x: bounds.minX, y: bounds.minY, width: bounds.width * 0.48, height: bounds.height)
                label = String(localized: "chrome.dropZone.splitLeft", defaultValue: "Split Left", table: "Chrome")
            case .right:
                highlightRect = NSRect(x: bounds.minX + bounds.width * 0.52, y: bounds.minY, width: bounds.width * 0.48, height: bounds.height)
                label = String(localized: "chrome.dropZone.splitRight", defaultValue: "Split Right", table: "Chrome")
            case .top:
                highlightRect = NSRect(x: bounds.minX, y: bounds.minY + bounds.height * 0.52, width: bounds.width, height: bounds.height * 0.48)
                label = String(localized: "chrome.dropZone.splitTop", defaultValue: "Split Top", table: "Chrome")
            case .bottom:
                highlightRect = NSRect(x: bounds.minX, y: bounds.minY, width: bounds.width, height: bounds.height * 0.48)
                label = String(localized: "chrome.dropZone.splitBottom", defaultValue: "Split Bottom", table: "Chrome")
        }
        
        let accent = NSColor.controlAccentColor
        let path = NSBezierPath(roundedRect: highlightRect, xRadius: 12, yRadius: 12)
        accent.withAlphaComponent(0.11).setFill()
        path.fill()
        
        accent.withAlphaComponent(0.75).setStroke()
        path.lineWidth = 1.75
        path.stroke()
        
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
            .foregroundColor: NSColor.labelColor,
        ]
        let attrString = NSAttributedString(string: label, attributes: attrs)
        let textSize = attrString.size()
        let symbolImage = NSImage(systemSymbolName: "arrow.down.doc", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 13, weight: .semibold))
        let iconGap: CGFloat = symbolImage == nil ? 0 : 20
        let badgeWidth = textSize.width + 28 + iconGap
        let badgeHeight = max(34, textSize.height + 16)
        let badgeRect = NSRect(
            x: highlightRect.midX - badgeWidth / 2,
            y: highlightRect.midY - badgeHeight / 2,
            width: badgeWidth,
            height: badgeHeight
        )
        let badgePath = NSBezierPath(roundedRect: badgeRect, xRadius: badgeHeight / 2, yRadius: badgeHeight / 2)
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.16)
        shadow.shadowBlurRadius = 10
        shadow.shadowOffset = NSSize(width: 0, height: -2)
        shadow.set()
        NSColor.windowBackgroundColor.withAlphaComponent(0.96).setFill()
        badgePath.fill()
        NSGraphicsContext.restoreGraphicsState()
        
        accent.withAlphaComponent(0.45).setStroke()
        badgePath.lineWidth = 1
        badgePath.stroke()
        
        var textOriginX = badgeRect.minX + 14
        if let symbol = symbolImage {
            let tinted = symbol.withSymbolConfiguration(.init(paletteColors: [accent])) ?? symbol
            let iconSize = tinted.size
            let iconRect = NSRect(
                x: textOriginX,
                y: badgeRect.midY - iconSize.height / 2,
                width: iconSize.width,
                height: iconSize.height
            )
            tinted.draw(in: iconRect)
            textOriginX += iconSize.width + 6
        }
        attrString.draw(at: NSPoint(x: textOriginX, y: badgeRect.midY - textSize.height / 2))
    }
}
