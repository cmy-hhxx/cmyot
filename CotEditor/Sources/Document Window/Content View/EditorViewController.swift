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
    
    
    // MARK: Private Properties
    
    private let splitState: SplitState
    private let tabState = PaneTabState()
    
    private lazy var outlineNavigator = OutlineNavigator()
    private lazy var contentViewController = PaneContentViewController()
    @ViewLoading private var navigationBarItem: NSSplitViewItem
    
    private var textViewControllers: [ObjectIdentifier: EditorTextViewController] = [:]
    private weak var contentChild: EditorTextViewController?
    
    private var outlineObserver: AnyCancellable?
    private var defaultObservers: Set<AnyCancellable> = []
    
    
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
        self.tabState.onClose = { [weak self] tab in self?.requestCloseTab?(tab) }
        self.tabState.onNewTab = { [weak self] in self?.requestNewTab?() }
        self.tabState.onTogglePin = { [weak self] tab in self?.togglePin(of: tab) }
        self.tabState.onMove = { [weak self] draggedTab, targetTab in
            self?.move(tab: draggedTab, onto: targetTab)
        }
        self.tabState.onClosePane = { [weak self] in self?.requestClosePane?() }
        
        self.outlineNavigator.textView = self.textView
        let navigationBar = NavigationBar(outlineNavigator: self.outlineNavigator,
                                          splitState: self.splitState,
                                          tabs: self.tabState)
        self.navigationBarItem = NSSplitViewItem(viewController: NSHostingController(rootView: navigationBar))
        self.navigationBarItem.isCollapsed = true  // reconsidered below
        self.addSplitViewItem(self.navigationBarItem)
        
        // setup the content area that hosts the selected tab's text view
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
            
            // keep the tab titles in sync with the documents
            NotificationCenter.default.publisher(for: NSDocument.DidChangeFileURLMessage.name)
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
    /// - Parameter document: The document the new tab shows.
    /// - Returns: The created tab.
    @discardableResult
    func addTab(document: Document) -> PaneTab {
        
        let tab = PaneTab(document: document)
        self.makeTextViewController(for: tab).loadViewIfNeeded()
        
        self.tabs.append(tab)
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
    /// - Parameter tab: The tab to select.
    func select(tab: PaneTab) {
        
        guard self.tabs.contains(where: { $0 === tab }) else { return }
        
        let didChange = (tab !== self.selectedTab)
        
        self.selectedTab = tab
        
        self.installContent(of: tab)
        self.updateTabState()
        self.observeOutline(of: tab.document)
        tab.document.applyHighlightRendering()
        self.updateNavigationBarVisibility()
        
        if didChange {
            self.didSelectTab?(tab)
        }
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
    
    /// Whether line number view is visible.
    var showsLineNumber: Bool {
        
        get { self.textViewController(for: self.selectedTab)?.showsLineNumber ?? false }
        set {
            // every tab gets the toggle, so switching tabs does not flip the setting
            self.textViewControllers.values.forEach { $0.showsLineNumber = newValue }
        }
    }
    
    
    /// Shows the tab bar only when it has something to offer: more than one tab, a split,
    /// outline navigation or a pinned tab. An empty bar is pure visual noise.
    ///
    /// - Parameter animated: `true` to animate the collapse.
    func updateNavigationBarVisibility(animated: Bool = false) {
        
        guard self.isViewLoaded else { return }
        
        let hasContent = self.tabs.count > 1
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
    @IBAction func save(_ sender: Any?) {
        
        self.document.save(sender)
    }
    
    
    /// Saves the document this pane edits under a new name.
    @IBAction func saveAs(_ sender: Any?) {
        
        self.document.saveAs(sender)
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
    }
}


/// A plain container that fills its pane and hosts the selected tab's text view.
private final class PaneContentViewController: NSViewController {
    
    override func loadView() {
        
        self.view = NSView()
    }
}
