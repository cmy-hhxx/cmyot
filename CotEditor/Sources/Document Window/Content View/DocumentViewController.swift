//
//  DocumentViewController.swift
//
//  CotEditor
//  https://coteditor.com
//
//  Created by 1024jp on 2016-06-05.
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
import Combine
import SwiftUI
import ControlUI
import Defaults
import StringUtils
import TextEditing

/// A split container that can hold editors *and* other split containers,
/// which is what makes tmux-like nested pane layouts possible.
final class SplitGroupViewController: NSSplitViewController {
    
    private let isVertical: Bool
    
    
    init(isVertical: Bool) {
        
        self.isVertical = isVertical
        
        super.init(nibName: nil, bundle: nil)
    }
    
    
    @available(*, unavailable)
    required init?(coder: NSCoder) {
        
        fatalError("init(coder:) has not been implemented")
    }
    
    
    override func viewDidLoad() {
        
        super.viewDidLoad()
        
        // Configure after the split view exists; touching `splitView` inside `init`
        // would force the view to load before the controller is fully initialised.
        self.splitView.isVertical = self.isVertical
        self.splitView.dividerStyle = .thin
    }
}


@Observable final class SplitState {
    
    var isVertical: Bool
    var canClose: Bool
    
    
    init(isVertical: Bool = false, canClose: Bool = false) {
        
        self.isVertical = isVertical
        self.canClose = canClose
    }
}


final class DocumentViewController: NSSplitViewController, ThemeChanging, NSToolbarItemValidation {
    
    private enum SerializationKey {
        
        static let theme = "theme"
    }
    
    
    // MARK: Public Properties
    
    let document: Document
    
    
    // MARK: Private Properties
    
    /// Posted when the pane that has the focus starts editing another document.
    static let focusedDocumentDidChangeNotification = Notification.Name("DocumentViewControllerFocusedDocumentDidChange")
    
    /// Posted when the window is split or un-split, or when a pane changes its tabs.
    static let splitLayoutDidChangeNotification = Notification.Name("DocumentViewControllerSplitLayoutDidChange")
    
    private static let maximumNumberOfSplitEditors = 4
    private static let maximumNumberOfTabsPerPane = 8
    
    private let splitState = SplitState()
    
    private weak var focusedChild: EditorViewController?
    
    /// The pane that currently fills the window while zoomed, if any.
    private var zoomedPane: EditorViewController?
    
    /// The split view items hidden by the zoom, restored when zooming out.
    private var itemsCollapsedByZoom: [NSSplitViewItem] = []
    private var aiResultPanel: AIResultPanelController?
    
    private var themeName: String?
    private var theme: Theme?  { self.focusedTextView?.theme }
    
    /// The theme applied to the editor, for views that should match its look.
    var currentTheme: Theme?  { self.theme }
    
    
    private var observers: Set<AnyCancellable> = []
    private var defaultsObservers: Set<AnyCancellable> = []
    private var windowCloseObserver: AnyCancellable?
    
    #if DEBUG
    private var didRunDemo = false
    
    /// Whether this launch was started for visual verification.
    private static var isDemoLaunchRequested: Bool {
        
        ProcessInfo.processInfo.arguments.contains("--ui-demo")
            || ProcessInfo.processInfo.environment["COT_UI_DEMO"] == "1"
            || UserDefaults.standard.bool(forKey: "COTUIDemo")
    }
    #endif
    
    private var pendingReviewDocuments: [Document] = []
    private var reviewCompletion: ((Bool) -> Void)?
    
    
    // MARK: Lifecycle
    
    init(document: Document) {
        
        self.document = document
        
        super.init(nibName: nil, bundle: nil)
        
        // set identifier for state restoration
        self.identifier = NSUserInterfaceItemIdentifier("DocumentViewController")
        
        switch UserDefaults.standard[.writingDirection] {
            case .leftToRight:
                break
            case .rightToLeft:
                self.writingDirection = .rightToLeft
            case .vertical:
                self.verticalLayoutOrientation = true
        }
    }
    
    
    required init?(coder: NSCoder) {
        
        fatalError("init(coder:) has not been implemented")
    }
    
    
    isolated deinit {
        NotificationCenter.default.removeObserver(self, name: NSTextStorage.didProcessEditingNotification, object: nil)
        NotificationCenter.default.removeObserver(self, name: EditorTextView.DidLiveChangeSelectionMessage.name, object: nil)
    }
    
    
    override func viewDidLoad() {
        
        super.viewDidLoad()
        
        self.splitView.isVertical = UserDefaults.standard[.splitViewVertical]
        self.splitState.isVertical = self.splitView.isVertical
        
        // set first editor view
        let initialViewController = self.makeEditorViewController(document: self.document, copying: nil)
        self.insertSplitViewItem(self.makeSplitViewItem(for: initialViewController), at: 0)
        
        // set theme
        let isDark = NSApp.effectiveAppearance.isDark
        let themeName = ThemeManager.shared.userDefaultSettingName(inDarkMode: isDark)
        self.setTheme(name: themeName)
        
        // detect indent style
        if UserDefaults.standard[.detectsIndentStyle],
           let indentStyle = self.document.textStorage.string.detectedIndentStyle
        {
            self.isAutoTabExpandEnabled = switch indentStyle {
                case .tab: false
                case .space: true
            }
        }
        
        // start parsing
        self.document.syntaxController.setupParser()
        
        NotificationCenter.default.addObserver(self, selector: #selector(textStorageDidProcessEditing),
                                               name: NSTextStorage.didProcessEditingNotification,
                                               object: self.document.textStorage)
        
        // observe
        self.observers = [
            // observe theme change
            UserDefaults.standard.publisher(for: .theme, initial: false)
                .sink { [weak self] in self?.setTheme(name: $0) },
            NotificationCenter.default.publisher(for: .didUpdateSettingNotification, object: ThemeManager.shared)
                .map { $0.userInfo!["change"] as! SettingChange }
                .filter { [weak self] in $0.old == self?.themeName }
                .compactMap(\.new)
                .throttle(for: 0.1, scheduler: DispatchQueue.main, latest: true)
                .sink { [weak self] in self?.setTheme(name: $0) },
            
            // observe editable change
            self.document.$isEditable
                .sink { [weak self] isEditable in
                    self?.textViews.forEach { $0.isEditable = isEditable }
                },
            
            // observe appearance change for theme toggle
            self.view.publisher(for: \.effectiveAppearance)
                .sink { [weak self] appearance in
                    guard
                        let self,
                        !UserDefaults.standard[.pinsThemeAppearance],
                        self.viewIfLoaded?.window != nil,
                        let currentThemeName = self.themeName,
                        let themeName = ThemeManager.shared.equivalentSettingName(to: currentThemeName, forDark: appearance.isDark),
                        currentThemeName != themeName
                    else { return }
                    
                    self.setTheme(name: themeName)
                },
            
            // observe focus change
            NotificationCenter.default.publisher(for: EditorTextView.DidBecomeFirstResponderMessage.name)
                .map { $0.object as! EditorTextView }
                .compactMap { [weak self] textView in self?.editorViewControllers.first { $0.contains(textView) } }
                .sink { [weak self] in
                    guard let self, self.focusedChild !== $0 else { return }
                    self.focusedChild = $0
                    NotificationCenter.default.post(name: Self.focusedDocumentDidChangeNotification, object: self)
                },
        ]
        
        self.updateSplitState()
    }
    
    
    override func viewWillAppear() {
        
        super.viewWillAppear()
        
        // observe user defaults
        self.defaultsObservers = [
            UserDefaults.standard.publisher(for: .showInvisibles, initial: true)
                .sink { [weak self] in self?.showsInvisibles = $0 },
            UserDefaults.standard.publisher(for: .showLineNumbers, initial: true)
                .sink { [weak self] in self?.showsLineNumber = $0 },
            UserDefaults.standard.publisher(for: .wrapLines, initial: true)
                .sink { [weak self] in self?.wrapsLines = $0 },
            UserDefaults.standard.publisher(for: .showPageGuide, initial: true)
                .sink { [weak self] in self?.showsPageGuide = $0 },
            UserDefaults.standard.publisher(for: .showIndentGuides, initial: true)
                .sink { [weak self] in self?.showsIndentGuides = $0 },
        ]
    }
    
    
    override func viewDidAppear() {
        
        super.viewDidAppear()
        
        // release the extra documents when the window goes away, so they never
        // linger invisible and unsavable in the document controller
        if self.windowCloseObserver == nil, let window = self.view.window {
            self.windowCloseObserver = NotificationCenter.default
                .publisher(for: NSWindow.willCloseNotification, object: window)
                .sink { [weak self] _ in self?.closeSecondaryDocuments() }
        }
        
        #if DEBUG
        if !self.didRunDemo, UserDefaults.standard.bool(forKey: "COTUIDemoTabs") {
            self.didRunDemo = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.setUpDemoTabsOnly()
            }
        }
        
        if !self.didRunDemo, let zoomMode = UserDefaults.standard.string(forKey: "COTUIDemoZoom"), !zoomMode.isEmpty {
            self.didRunDemo = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                guard let self else { return }
                self.setUpDemoLayout()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                    guard let self, self.editorViewControllers.count > 1 else { return }
                    self.view.window?.makeFirstResponder(self.editorViewControllers[1].textView)
                    self.togglePaneZoom(nil)
                    if zoomMode == "2" {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                            self?.togglePaneZoom(nil)
                        }
                    }
                }
            }
        }
        
        if !self.didRunDemo, UserDefaults.standard.bool(forKey: "COTUIDemoMenu") {
            self.didRunDemo = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                self?.setUpDemoMenu()
            }
        }
        
        if !self.didRunDemo, Self.isDemoLaunchRequested {
            self.didRunDemo = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.setUpDemoLayout()
            }
        }
        #endif
    }
    
    
    override func viewDidDisappear() {
        
        super.viewDidDisappear()
        
        self.defaultsObservers.removeAll()
    }
    
    
    override static var restorableStateKeyPaths: [String] {
        
        super.restorableStateKeyPaths + [
            #keyPath(showsLineNumber),
            #keyPath(showsPageGuide),
            #keyPath(showsIndentGuides),
            #keyPath(showsInvisibles),
            #keyPath(wrapsLines),
            #keyPath(verticalLayoutOrientation),
            #keyPath(isAutoTabExpandEnabled),
            #keyPath(writingDirection),
        ]
    }
    
    
    override static func allowedClasses(forRestorableStateKeyPath keyPath: String) -> [AnyClass] {
        
        switch keyPath {
            case #keyPath(showsLineNumber),
                #keyPath(showsPageGuide),
                #keyPath(showsIndentGuides),
                #keyPath(showsInvisibles),
                #keyPath(wrapsLines),
                #keyPath(verticalLayoutOrientation),
                #keyPath(isAutoTabExpandEnabled),
                #keyPath(writingDirection):
                // -> Bool is also an NSNumber
                [NSNumber.self]
            default:
                super.allowedClasses(forRestorableStateKeyPath: keyPath)
        }
    }
    
    
    override func encodeRestorableState(with coder: NSCoder, backgroundQueue queue: OperationQueue) {
        
        super.encodeRestorableState(with: coder, backgroundQueue: queue)
        
        if let themeName = self.themeName {
            coder.encode(themeName, forKey: SerializationKey.theme)
        }
    }
    
    
    override func restoreState(with coder: NSCoder) {
        
        super.restoreState(with: coder)
        
        if let storedThemeName = coder.decodeObject(of: NSString.self, forKey: SerializationKey.theme) as? String {
            let themeName = UserDefaults.standard[.pinsThemeAppearance]
                ? storedThemeName
                : ThemeManager.shared.equivalentSettingName(to: storedThemeName, forDark: self.view.effectiveAppearance.isDark) ?? storedThemeName
            
            if themeName != self.themeName {
                self.setTheme(name: themeName)
            }
        }
    }
    
    
    // MARK: Split View Controller Methods
    
    func validateToolbarItem(_ item: NSToolbarItem) -> Bool {
        
        // manually pass toolbar items to `validateUserInterfaceItem(_:)`,
        // because they actually doesn't use it for validation (2020-08, macOS 10.15)
        self.validateUserInterfaceItem(item)
    }
    
    
    /// Keeps the checkmark of the appearance menu items in sync.
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        
        if menuItem.action == #selector(changeAppearance) {
            menuItem.state = (menuItem.tag == UserDefaults.standard[.documentAppearance].rawValue) ? .on : .off
        }
        
        return true
    }
    
    
    override func validateUserInterfaceItem(_ item: any NSValidatedUserInterfaceItem) -> Bool {
        
        switch item.action {
            case #selector(toggleLineNumber):
                (item as? NSMenuItem)?.title = self.showsLineNumber
                    ? String(localized: "Hide Line Numbers", table: "MainMenu")
                    : String(localized: "Show Line Numbers", table: "MainMenu")
                
            case #selector(togglePageGuide):
                (item as? NSMenuItem)?.title = self.showsPageGuide
                    ? String(localized: "Hide Page Guide", table: "MainMenu")
                    : String(localized: "Show Page Guide", table: "MainMenu")
                (item as? StatableToolbarItem)?.state = self.showsPageGuide ? .on : .off
                
            case #selector(toggleIndentGuides):
                (item as? NSMenuItem)?.title = self.showsIndentGuides
                    ? String(localized: "Hide Indent Guides", table: "MainMenu")
                    : String(localized: "Show Indent Guides", table: "MainMenu")
                (item as? NSToolbarItem)?.toolTip = self.showsIndentGuides
                    ? String(localized: "Toolbar.indentGuides.tooltip.on",
                             defaultValue: "Hide indent guide lines", table: "Document")
                    : String(localized: "Toolbar.indentGuides.tooltip.off",
                             defaultValue: "Show indent guide lines", table: "Document")
                (item as? StatableToolbarItem)?.state = self.showsIndentGuides ? .on : .off
                
            case #selector(toggleLineWrap):
                (item as? NSMenuItem)?.title = self.wrapsLines
                    ? String(localized: "Unwrap Lines", table: "MainMenu")
                    : String(localized: "Wrap Lines", table: "MainMenu")
                (item as? NSToolbarItem)?.toolTip = self.wrapsLines
                    ? String(localized: "Toolbar.wrapLines.tooltip.on",
                             defaultValue: "Unwrap lines", table: "Document")
                    : String(localized: "Toolbar.wrapLines.tooltip.off",
                             defaultValue: "Wrap lines", table: "Document")
                (item as? StatableToolbarItem)?.state = self.wrapsLines ? .on : .off
                
            case #selector(toggleInvisibleChars):
                (item as? NSMenuItem)?.title = self.showsInvisibles
                    ? String(localized: "Hide Invisibles", table: "MainMenu")
                    : String(localized: "Show Invisibles", table: "MainMenu")
                (item as? NSMenuItem)?.image = self.showsInvisibles
                    ? NSImage(resource: .paragraphsignSlash)
                    : NSImage(systemSymbolName: "paragraphsign", accessibilityDescription: nil)
                if #unavailable(macOS 26) {
                    (item as? NSMenuItem)?.image = nil
                }
                (item as? StatableToolbarItem)?.state = self.showsInvisibles ? .on : .off
                
                // disable if item cannot be enabled
                let canActivateShowInvisibles = !UserDefaults.standard.shownInvisible.isEmpty
                item.toolTip = canActivateShowInvisibles
                    ? nil
                    : String(localized: "To show invisible characters, set them in Window settings",
                             table: "MainMenu",
                             comment: "tooltip for the “Show Invisibles” menu item and toolbar item for when all invisible settings are disabled")
                if canActivateShowInvisibles {
                    (item as? NSToolbarItem)?.toolTip = self.showsInvisibles
                        ? String(localized: "Toolbar.invisibles.tooltip.on",
                                 defaultValue: "Hide invisible characters", table: "Document")
                        : String(localized: "Toolbar.invisibles.tooltip.off",
                                 defaultValue: "Show invisible characters", table: "Document")
                }
                return canActivateShowInvisibles
                
            case #selector(toggleAntialias):
                (item as? any StatableItem)?.state = (self.focusedTextView?.usesAntialias ?? false) ? .on : .off
                
            case #selector(toggleLigatures):
                (item as? any StatableItem)?.state = (self.focusedTextView?.ligature != NSTextView.LigatureMode.none) ? .on : .off
                
            case #selector(toggleAutoTabExpand):
                (item as? any StatableItem)?.state = self.isAutoTabExpandEnabled ? .on : .off
                (item as? NSToolbarItem)?.toolTip = self.isAutoTabExpandEnabled
                    ? String(localized: "Toolbar.tabStyle.tooltip.on",
                             defaultValue: "Use tabs for indentation", table: "Document")
                    : String(localized: "Toolbar.tabStyle.tooltip.off",
                             defaultValue: "Use spaces for indentation", table: "Document")
                
            case #selector(changeTabWidth):
                (item as? any StatableItem)?.state = (self.tabWidth == item.tag) ? .on : .off
                
            case #selector(makeFontStandard):
                let standardFont = UserDefaults.standard.font(for: .standard)
                let monospacedFont = UserDefaults.standard.font(for: .monospaced)
                (item as? NSMenuItem)?.state = (self.font == standardFont && standardFont != monospacedFont) ? .on : .off
                
            case #selector(makeFontMonospaced):
                let monospacedFont = UserDefaults.standard.font(for: .monospaced)
                (item as? NSMenuItem)?.state = (self.font == monospacedFont) ? .on : .off
                
            case #selector(makeLayoutOrientationHorizontal):
                (item as? any StatableItem)?.state = self.verticalLayoutOrientation ? .off : .on
                
            case #selector(makeLayoutOrientationVertical):
                (item as? any StatableItem)?.state = self.verticalLayoutOrientation ? .on : .off
                
            case #selector(makeWritingDirectionLeftToRight):
                (item as? any StatableItem)?.state = (self.writingDirection == .leftToRight) ? .on : .off
                
            case #selector(makeWritingDirectionRightToLeft):
                (item as? any StatableItem)?.state = (self.writingDirection == .rightToLeft) ? .on : .off
                
            case #selector(changeWritingDirection):
                (item as? NSToolbarItemGroup)?.selectedIndex = switch self.writingDirection {
                    case _ where self.verticalLayoutOrientation: -1
                    case .rightToLeft: 1
                    default: 0
                }
                
            case #selector(changeOrientation):
                (item as? NSToolbarItemGroup)?.selectedIndex = self.verticalLayoutOrientation ? 1 : 0
                
            case #selector(changeTheme):
                if let item = item as? NSMenuItem {
                    item.state = (self.themeName == item.title) ? .on : .off
                }
                
            case #selector(toggleSplitOrientation):
                (item as? NSMenuItem)?.title = self.splitView.isVertical
                    ? String(localized: "Stack Editors Horizontally", table: "MainMenu")
                    : String(localized: "Stack Editors Vertically", table: "MainMenu")
                (item as? NSMenuItem)?.image = self.splitView.isVertical
                    ? NSImage(systemSymbolName: "rectangle.split.1x2", accessibilityDescription: nil)
                    : NSImage(systemSymbolName: "rectangle.split.2x1", accessibilityDescription: nil)
                if #unavailable(macOS 26) {
                    (item as? NSMenuItem)?.image = nil
                }
                
            case #selector(openSplitTextView):
                (item as? NSMenuItem)?.image = self.splitView.isVertical
                    ? NSImage(systemSymbolName: "rectangle.split.2x1", accessibilityDescription: nil)
                    : NSImage(systemSymbolName: "rectangle.split.1x2", accessibilityDescription: nil)
                if #unavailable(macOS 26) {
                    (item as? NSMenuItem)?.image = nil
                }
                
            case #selector(closeSplitTextView):
                // the pane showing the window's own document has to stay
                return self.splitViewItems.count > 1 && (self.focusedChild?.document ?? self.document) !== self.document
                
            default: break
        }
        
        return super.validateUserInterfaceItem(item)
    }
    
    
    // MARK: Notifications
    
    /// Invoked when the text was edited (invoked right **before** notifying layout managers).
    nonisolated override func textStorageDidProcessEditing(_ notification: Notification) {
        
        assert(Thread.isMainThread)
        
        let textStorage = notification.object as! NSTextStorage
        
        guard textStorage.editedMask.contains(.editedCharacters) else { return }
        
        MainActor.assumeIsolated { [range = textStorage.editedRange, length = textStorage.changeInLength] in
            guard let document = self.document(for: textStorage) else { return }
            
            // tell the parser that text was changed
            document.syntaxController.invalidate(in: range, changeInLength: length)
            
            // keep painted highlights attached to the text they were drawn on
            document.adjustHighlights(forEditIn: range, changeInLength: length)
            
            guard self.focusedTextView?.hasMarkedText() != true else { return }
            
            document.counter.invalidateContent()
            document.syntaxController.parseIfNeeded()
        }
    }
    
    
    /// Invoked when the selection did change.
    @objc private func textViewDidLiveChangeSelection(_ notification: Notification) {
        
        let textView = notification.object as? NSTextView
        let document = textView.flatMap { self.document(for: $0) } ?? self.document
        
        document.counter.invalidateSelection()
    }
    
    
    // MARK: Public Methods
    
    /// The array of all child text views, including the ones of the tabs not shown.
    var textViews: [EditorTextView] {
        
        self.editorViewControllers.flatMap(\.allTextViews)
    }
    
    /// The text view currently focused on.
    var focusedTextView: EditorTextView? {
        
        self.focusedChild?.textView ?? self.editorViewControllers.first?.textView
    }
    
    
    /// The editor's font.
    var font: NSFont? {
        
        self.focusedTextView?.font
    }
    
    
    /// The visibility of line numbers views.
    @objc dynamic var showsLineNumber = false {
        
        didSet {
            for viewController in self.editorViewControllers {
                viewController.showsLineNumber = showsLineNumber
            }
            // Store the toggle in the shared default so that the `Show Line Numbers`
            // menu item keeps in sync with the Settings pane and survives relaunch.
            if UserDefaults.standard[.showLineNumbers] != self.showsLineNumber {
                UserDefaults.standard[.showLineNumbers] = self.showsLineNumber
            }
        }
    }
    
    
    /// Whether lines soft-wrap at the window edge.
    @objc dynamic var wrapsLines = true {
        
        didSet {
            for textView in self.textViews {
                textView.wrapsLines = wrapsLines
            }
        }
    }
    
    
    /// The visibility of page guide lines in text views.
    @objc dynamic var showsPageGuide = false {
        
        didSet {
            for textView in self.textViews {
                textView.showsPageGuide = showsPageGuide
            }
        }
    }
    
    
    /// The visibility of indent guides in the text views.
    @objc dynamic var showsIndentGuides = false {
        
        didSet {
            for textView in self.textViews {
                textView.showsIndentGuides = showsIndentGuides
            }
        }
    }
    
    
    /// The visibility of invisible characters.
    @objc dynamic var showsInvisibles = false {
        
        didSet {
            for textView in self.textViews {
                textView.showsInvisibles = showsInvisibles
            }
        }
    }
    
    
    /// Whether the text orientation in the text views is vertical.
    @objc dynamic var verticalLayoutOrientation: Bool = false {
        
        didSet {
            self.document.isVerticalText = verticalLayoutOrientation
            
            let orientation: NSLayoutManager.TextLayoutOrientation = verticalLayoutOrientation ? .vertical : .horizontal
            
            for textView in self.textViews {
                textView.setLayoutOrientation(orientation)
            }
        }
    }
    
    
    /// The writing direction of the text views.
    @objc dynamic var writingDirection: NSWritingDirection = .leftToRight {
        
        didSet {
            for textView in self.textViews where textView.baseWritingDirection != writingDirection {
                textView.baseWritingDirection = writingDirection
            }
        }
    }
    
    
    /// The tab width of the text views.
    var tabWidth: Int {
        
        get {
            self.focusedTextView?.tabWidth ?? UserDefaults.standard[.tabWidth]
        }
        
        set {
            for textView in self.textViews {
                textView.tabWidth = newValue
            }
        }
    }
    
    
    /// Whether tabs are replaced with spaces.
    @objc dynamic var isAutoTabExpandEnabled: Bool {
        
        get {
            self.focusedTextView?.isAutomaticTabExpansionEnabled ?? UserDefaults.standard[.autoExpandTab]
        }
        
        set {
            for textView in self.textViews {
                textView.isAutomaticTabExpansionEnabled = newValue
            }
        }
    }
    
    
    /// Applies editor styles to the text storage and update editor views.
    func invalidateStyleInTextStorage() {
        
        assert(Thread.isMainThread)
        
        guard
            let textView = self.focusedTextView,
            let textStorage = textView.textStorage,
            textStorage.length > 0
        else { return }
        
        textStorage.addAttributes(textView.typingAttributes, range: textStorage.range)
    }
    
    
    // MARK: Action Messages
    
    /// Reset the syntax parse for the entire document.
    @IBAction func recolorAll(_ sender: Any?) {
        
        self.document.syntaxController.parseAll()
    }
    
    
    /// Sets new theme from a menu item.
    @IBAction func changeTheme(_ sender: NSMenuItem) {
        
        self.setTheme(name: sender.title)
    }
    
    
    /// Switches the document appearance between system / light / dark.
    ///
    /// - Parameter sender: The menu item whose tag is the `AppearanceMode`.
    @IBAction func changeAppearance(_ sender: NSMenuItem) {
        
        guard let mode = AppearanceMode(rawValue: sender.tag) else { return }
        
        UserDefaults.standard[.documentAppearance] = mode
    }
    
    
    /// Sets the text size from the continuous slider in the toolbar.
    ///
    /// - Parameter sender: The slider whose value is the new scale (0.6–3.0).
    @IBAction func changeTextScale(_ sender: NSSlider) {
        
        self.focusedChild?.textView?.setScaleKeepingVisibleArea(CGFloat(sender.doubleValue))
    }
    
    
    /// Inserts one of the curated emoji from the toolbar's emoji grid.
    ///
    /// - Parameter sender: The emoji button that was pressed.
    @IBAction func insertQuickEmojiFromButton(_ sender: NSButton) {
        
        self.insert(emoji: sender.title)
    }
    
    
    /// Inserts one of the curated emoji used by the toolbar's quick emoji menu.
    ///
    /// - Parameter sender: The menu item whose title is the emoji to insert.
    @IBAction func insertQuickEmoji(_ sender: NSMenuItem) {
        
        self.insert(emoji: sender.title)
    }
    
    
    private func insert(emoji: String) {
        
        guard let textView = self.focusedChild?.textView, !emoji.isEmpty else { return }
        
        textView.insertText(emoji, replacementRange: textView.selectedRange())
    }
    
    
    // MARK: Text Highlight
    
    /// Paints the selection with the highlight color carried by the sender's tag.
    @IBAction func applyHighlight(_ sender: NSMenuItem) {
        
        let colors = HighlightColor.allCases
        guard colors.indices.contains(sender.tag) else { return }
        
        self.highlightSelection { document, range in
            document.addHighlight(range: range, color: colors[sender.tag])
        }
    }
    
    
    /// Removes the highlights touching the selection.
    @IBAction func removeHighlight(_ sender: Any?) {
        
        self.highlightSelection { document, range in
            document.removeHighlights(in: range)
        }
    }
    
    
    private func highlightSelection(_ action: (Document, NSRange) -> Void) {
        
        guard let textView = self.focusedChild?.textView else { return }
        
        let range = textView.selectedRange()
        guard range.length > 0 else { return }
        
        guard let document = self.document(for: textView) else { return }
        
        action(document, range)
    }
    
    
    // MARK: Pane Zoom

    /// Toggles the focused pane between filling the window and the usual split layout.
    ///
    /// Bound to the tmux-style ⌃A, Z sequence in the text view; there is deliberately no
    /// toolbar item or menu entry.
    @IBAction func togglePaneZoom(_ sender: Any?) {
        
        if self.zoomedPane != nil {
            self.unzoomPane()
        } else {
            self.zoomFocusedPane()
        }
    }
    
    
    /// Expands the focused pane to the whole editing area by collapsing its siblings.
    private func zoomFocusedPane() {
        
        guard self.editorViewControllers.count > 1 else { return NSSound.beep() }
        guard let pane = self.focusedChild ?? self.editorViewControllers.first else { return }
        
        // The path from the pane up to this split view controller, so that nested
        // containers on the way are reduced to the one child the pane lives in.
        var path: [(group: NSSplitViewController, item: NSSplitViewItem)] = []
        var child: NSViewController = pane
        while let parent = child.parent as? NSSplitViewController {
            guard let item = parent.splitViewItems.first(where: { $0.viewController === child }) else { break }
            path.append((parent, item))
            if parent === self { break }
            child = parent
        }
        
        guard !path.isEmpty else { return }
        
        var collapsed: [NSSplitViewItem] = []
        NSAnimationContext.withStandardTiming {
            for (group, pathItem) in path {
                for item in group.splitViewItems where item !== pathItem && !item.isCollapsed {
                    item.animator().isCollapsed = true
                    collapsed.append(item)
                }
            }
        }
        
        self.zoomedPane = pane
        self.itemsCollapsedByZoom = collapsed
        self.view.window?.makeFirstResponderDiscardingMarkedText(pane.textView)
    }
    
    
    /// Restores the split layout hidden by the zoom.
    private func unzoomPane() {
        
        guard let pane = self.zoomedPane else { return }
        
        let items = self.itemsCollapsedByZoom
        self.itemsCollapsedByZoom = []
        self.zoomedPane = nil
        
        NSAnimationContext.withStandardTiming {
            items.forEach { $0.animator().isCollapsed = false }
        }
        
        self.view.window?.makeFirstResponderDiscardingMarkedText(pane.textView)
    }
    
    
    /// Forgets the zoom without touching the layout, for when the zoomed pane goes away.
    private func resetZoomState() {
        
        self.zoomedPane = nil
        self.itemsCollapsedByZoom = []
    }
    
    
    // MARK: Window Actions

    /// Closes only the focused pane while the window is split.
    ///
    /// ⌘W used to close the whole window, taking every other pane and tab with it. With
    /// panes this destructive, the shortcut now closes just the pane the user is in; an
    /// unsplit window keeps the usual close-the-window behaviour.
    @IBAction func performClose(_ sender: Any?) {
        
        guard let pane = self.focusedChild ?? self.editorViewControllers.first else {
            self.view.window?.performClose(sender)
            return
        }
        
        let tab = pane.selectedTab
        
        // ⌘W always closes one document at a time — the focused tab. A pane goes away
        // with its last tab, so this never throws away the other documents of a pane or
        // the other panes of the window.
        guard tab.isClosable, !tab.isPinned else {
            // The window's own document tab cannot be closed. Once it is the only tab left,
            // ⌘W closes the window; otherwise there is nothing for it to close here.
            if self.editorViewControllers.count == 1, pane.tabs.count == 1, !tab.isPinned {
                self.view.window?.performClose(sender)
            } else {
                NSSound.beep()
            }
            return
        }
        
        self.closeTab(tab, in: pane)
    }
    
    
    // MARK: AI Actions
    
    /// Translates the selected text.
    ///
    /// - Parameter sender: The action sender.
    @IBAction func translateSelection(_ sender: Any?) {
        
        self.runAIAction(.translate)
    }
    
    
    /// Summarizes the selected text.
    ///
    /// - Parameter sender: The action sender.
    @IBAction func summarizeSelection(_ sender: Any?) {
        
        self.runAIAction(.summarize)
    }
    
    
    /// Rewrites the selected text in plain language.
    ///
    /// - Parameter sender: The action sender.
    @IBAction func explainSelection(_ sender: Any?) {
        
        self.runAIAction(.explain)
    }
    
    
    /// Runs one AI action on the selection and shows the answer in a sheet.
    ///
    /// - Parameter action: The action to run.
    private func runAIAction(_ action: AIAction) {
        
        guard let textView = self.focusedTextView, let window = textView.window else {
            NSSound.beep()
            return
        }
        
        let text = textView.selectedString
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            NSSound.beep()
            return
        }
        
        guard AIService.shared.isConfigured else {
            self.presentAIConfigurationAlert(on: window)
            return
        }
        
        let panel = AIResultPanelController(action: action)
        panel.onReplace = { [weak self] result in self?.applyAIResult(result, replacingSelection: true) }
        panel.onInsert = { [weak self] result in self?.applyAIResult(result, replacingSelection: false) }
        self.aiResultPanel = panel
        
        panel.present(on: window)
        
        Task {
            do {
                let result = try await AIService.shared.run(action, on: text)
                panel.present(result: result)
            } catch {
                panel.present(error: error)
            }
        }
    }
    
    
    /// Puts the answer into the focused text view.
    ///
    /// The insertion goes through `insertText(_:replacementRange:)` so the change is undoable
    /// and the text view keeps handling its own editing state.
    ///
    /// - Parameters:
    ///   - result: The answer text.
    ///   - replacingSelection: Whether to replace the selection instead of inserting at the caret.
    private func applyAIResult(_ result: String, replacingSelection: Bool) {
        
        guard let textView = self.focusedTextView else { return }
        
        let range = replacingSelection ? textView.selectedRange() : NSRange(location: textView.selectedRange().upperBound, length: 0)
        
        textView.insertText(result, replacementRange: range)
        textView.window?.makeFirstResponder(textView)
    }
    
    
    /// Explains that the AI has not been configured yet.
    ///
    /// - Parameter window: The window to attach the alert to.
    private func presentAIConfigurationAlert(on window: NSWindow) {
        
        let alert = NSAlert()
        alert.messageText = "还没有配置 AI"
        alert.informativeText = "请先在设置里填写接口地址、模型和 API Key，再使用翻译、总结和说人话。"
        alert.addButton(withTitle: "打开 AI 设置")
        alert.addButton(withTitle: "取消")
        
        alert.beginSheetModal(for: window) { response in
            guard response == .alertFirstButtonReturn else { return }
            
            (NSApp.delegate as? AppDelegate)?.showAIPreferences(nil)
        }
    }
    
    
    /// Toggles the visibility of the line number views.
    @IBAction func toggleLineNumber(_ sender: Any?) {
        
        self.showsLineNumber.toggle()
    }
    
    
    /// Toggles the visibility of page guide line in the text views.
    @IBAction func togglePageGuide(_ sender: Any?) {
        
        self.showsPageGuide.toggle()
    }
    
    
    /// Toggles the visibility of indent guides in the text views.
    @IBAction func toggleIndentGuides(_ sender: Any?) {
        
        self.showsIndentGuides.toggle()
    }
    
    
    /// Toggles if lines wrap at the window edge.
    @IBAction func toggleLineWrap(_ sender: Any?) {
        
        self.wrapsLines.toggle()
    }
    
    
    /// Toggles the visibility of invisible characters in the text views.
    @IBAction func toggleInvisibleChars(_ sender: Any?) {
        
        self.showsInvisibles.toggle()
    }
    
    
    /// Toggles if antialias text in the text views.
    @IBAction func toggleAntialias(_ sender: Any?) {
        
        for textView in self.textViews {
            textView.usesAntialias.toggle()
        }
    }
    
    
    /// Toggles the ligature mode in the text views.
    @IBAction func toggleLigatures(_ sender: Any?) {
        
        for textView in self.textViews {
            textView.ligature = (textView.ligature == .none) ? .standard : .none
        }
    }
    
    
    /// Toggles if the text views expand tab input.
    @IBAction func toggleAutoTabExpand(_ sender: Any?) {
        
        self.isAutoTabExpandEnabled.toggle()
    }
    
    
    /// Changes the tab width from a menu item.
    @IBAction func changeTabWidth(_ sender: NSMenuItem) {
        
        self.tabWidth = sender.tag
    }
    
    
    /// Changes the tab width to desired number through a sheet.
    @IBAction func customizeTabWidth(_ sender: Any?) {
        
        let view = CustomTabWidthView(tabWidth: self.tabWidth) { [weak self] tabWidth in
            self?.tabWidth = tabWidth
        }
        let viewController = NSHostingController(rootView: view)
        viewController.rootView.dismiss = { [weak viewController] in viewController?.dismiss(nil) }
        
        self.presentAsSheet(viewController)
    }
    
    
    /// Changes the font to the user's standard font.
    @IBAction func makeFontStandard(_ sender: Any?) {
        
        for textView in self.textViews {
            textView.setFont(type: .standard)
        }
    }
    
    
    /// Changes the font to the user's monospaced font.
    @IBAction func makeFontMonospaced(_ sender: Any?) {
        
        for textView in self.textViews {
            textView.setFont(type: .monospaced)
        }
    }
    
    
    /// Makes text layout orientation horizontal.
    @IBAction func makeLayoutOrientationHorizontal(_ sender: Any?) {
        
        self.verticalLayoutOrientation = false
    }
    
    
    /// Makes the text layout orientation vertical.
    @IBAction func makeLayoutOrientationVertical(_ sender: Any?) {
        
        self.verticalLayoutOrientation = true
    }
    
    
    /// Makes the entire writing direction left-to-right.
    @IBAction func makeWritingDirectionLeftToRight(_ sender: Any?) {
        
        self.writingDirection = .leftToRight
    }
    
    
    /// Makes the entire writing direction right-to-left.
    @IBAction func makeWritingDirectionRightToLeft(_ sender: Any?) {
        
        self.verticalLayoutOrientation = false
        self.writingDirection = .rightToLeft
    }
    
    
    /// Changes writing direction by a grouped toolbar item.
    @IBAction func changeWritingDirection(_ sender: NSToolbarItemGroup) {
        
        assertionFailure("This is a dummy action designed to be used just for the segmentation selection validation.")
    }
    
    
    /// Changes layout orientation by a grouped toolbar item.
    @IBAction func changeOrientation(_ sender: NSToolbarItemGroup) {
        
        assertionFailure("This is a dummy action designed to be used just for the segmentation selection validation.")
    }
    
    
    /// Toggles divider orientation.
    @IBAction func toggleSplitOrientation(_ sender: Any?) {
        
        // Only the container of the focused pane flips, so other rows/columns keep
        // their own direction (tmux-style nested layouts).
        let group = self.focusedChild.flatMap { self.splitGroup(containing: $0) } ?? self
        group.splitView.isVertical.toggle()
        
        self.splitState.isVertical = group.splitView.isVertical
        UserDefaults.standard[.splitViewVertical] = group.splitView.isVertical
    }
    
    
    /// Moves focus to the next text view.
    @IBAction func focusNextEditor(_ sender: Any?) {
        
        self.focusNextSplitEditor()
    }
    
    
    /// Moves focus to the previous text view.
    @IBAction func focusPreviousEditor(_ sender: Any?) {
        
        self.focusNextSplitEditor(reverse: true)
    }
    
    
    /// Splits the focused editor.
    ///
    /// The new pane is added along the current split direction. When the focused pane lives
    /// in a container with the other direction, the pane is wrapped into a nested container
    /// instead — that is what gives tmux-like layouts (e.g. a column of two stacked panes
    /// next to a full-height pane).
    @IBAction func openSplitTextView(_ sender: Any?) {
        
        self.openSplitEditor(for: sender, isVertical: self.splitState.isVertical)
    }
    
    
    /// Splits the focused pane to the right (panes side by side).
    @IBAction func splitEditorVertically(_ sender: Any?) {
        
        self.openSplitEditor(for: sender, isVertical: true)
    }
    
    
    /// Splits the focused pane downwards (panes stacked vertically).
    @IBAction func splitEditorHorizontally(_ sender: Any?) {
        
        self.openSplitEditor(for: sender, isVertical: false)
    }
    
    
    /// Splits the focused pane in the given direction, giving the new pane an empty document.
    ///
    /// - Parameters:
    ///   - sender: The action sender.
    ///   - isVertical: `true` to place the new pane to the right, `false` to place it below.
    private func openSplitEditor(for sender: Any?, isVertical: Bool) {
        
        guard self.editorViewControllers.count < Self.maximumNumberOfSplitEditors else { return NSSound.beep() }
        
        guard
            let currentViewController = self.baseEditorViewController(for: sender),
            let window = self.view.window
        else { return assertionFailure() }
        
        self.unzoomPane()
        
        let document: Document
        do {
            document = try self.makePaneDocument()
        } catch {
            NSApp.presentError(error)
            return
        }
        
        let newEditorViewController = self.makeEditorViewController(document: document, copying: currentViewController)
        self.insertPane(newEditorViewController, beside: currentViewController, isVertical: isVertical)
        
        self.splitState.isVertical = isVertical
        self.updateSplitState()
        self.scheduleRatioRebalance()
        
        window.makeFirstResponderDiscardingMarkedText(newEditorViewController.textView)
    }
    
    
    /// Creates a document that belongs to a pane rather than to a window of its own.
    ///
    /// - Returns: The new untitled document.
    private func makePaneDocument() throws -> Document {
        
        let opened = try NSDocumentController.shared.openUntitledDocumentAndDisplay(false)
        
        guard let document = opened as? Document else {
            throw CocoaError(.featureUnsupported)
        }
        
        // the new document belongs to this pane, never to a window of its own
        document.isTransient = false
        document.syntaxController.setupParser()
        
        return document
    }
    
    
    /// Adds a new tab showing the given document to the given pane.
    ///
    /// - Parameters:
    ///   - document: The document the new tab shows.
    ///   - pane: The pane to add the tab to.
    ///   - copying: The text view whose editor preferences are copied to the new one.
    private func addTab(_ document: Document, to pane: EditorViewController, copying sourceTextView: EditorTextView?) {
        
        document.isTransient = false
        document.syntaxController.setupParser()
        
        self.observeTextStorage(of: document)
        
        let tab = pane.addTab(document: document)
        tab.isClosable = (document !== self.document)
        
        if let textView = pane.textView {
            self.configureTextView(textView, copying: sourceTextView)
            pane.showsLineNumber = self.showsLineNumber
            
            // observe cursor
            NotificationCenter.default.addObserver(self, selector: #selector(textViewDidLiveChangeSelection),
                                                   name: EditorTextView.DidLiveChangeSelectionMessage.name,
                                                   object: textView)
        }
        
        self.focusedChild = pane
        self.updateSplitState()
        self.view.window?.makeFirstResponderDiscardingMarkedText(pane.textView)
        
        NotificationCenter.default.post(name: Self.focusedDocumentDidChangeNotification, object: self)
    }
    
    
    /// Creates a new document and adds it as a tab to the given pane.
    ///
    /// - Parameter pane: The pane to add the tab to.
    /// - Returns: `false` when the pane already holds as many tabs as it may.
    @discardableResult
    private func newTab(in pane: EditorViewController) -> Bool {
        
        guard pane.tabs.count < Self.maximumNumberOfTabsPerPane else {
            NSSound.beep()
            return false
        }
        
        let sourceTextView = pane.textView
        
        let document: Document
        do {
            document = try self.makePaneDocument()
        } catch {
            NSApp.presentError(error)
            return false
        }
        
        self.addTab(document, to: pane, copying: sourceTextView)
        
        return true
    }
    
    
    /// Closes one tab of a pane, closing the pane when its last tab goes away.
    ///
    /// - Parameters:
    ///   - tab: The tab to close.
    ///   - pane: The pane that hosts the tab.
    private func closeTab(_ tab: PaneTab, in pane: EditorViewController) {
        
        guard tab.isClosable, !tab.isPinned else { return NSSound.beep() }
        
        // Ask about unsaved changes *before* taking the tab away: otherwise a cancelled
        // save prompt would leave an invisible document behind that can never be saved.
        if pane === self.zoomedPane, pane.tabs.count == 1 {
            self.unzoomPane()
        }
        
        self.reviewDocuments([tab.document]) { [weak self, weak pane] canClose in
            guard canClose, let self, let pane else { return }
            
            self.stopObservingTextStorage(of: tab.document)
            
            if let textView = pane.textView(for: tab) {
                NotificationCenter.default.removeObserver(self, name: EditorTextView.DidLiveChangeSelectionMessage.name, object: textView)
                textView.undoManager?.removeAllActions(withTarget: textView)
            }
            
            tab.document.close()
            
            let wasLastTab = (pane.tabs.count == 1)
            pane.removeTab(tab)
            
            if wasLastTab {
                self.removePane(pane)
            } else {
                self.view.window?.makeFirstResponderDiscardingMarkedText(pane.textView)
            }
            
            self.updateSplitState()
            NotificationCenter.default.post(name: Self.focusedDocumentDidChangeNotification, object: self)
        }
    }
    
    
    /// Closes a whole pane of a split window.
    ///
    /// - Parameter pane: The pane to close.
    private func closePane(_ pane: EditorViewController) {
        
        guard self.editorViewControllers.count > 1 else { return NSSound.beep() }
        
        // The pane that shows the window's own document cannot be closed at all.
        guard !pane.tabs.contains(where: { $0.document === self.document }) else { return NSSound.beep() }
        
        guard !pane.tabs.contains(where: \.isPinned) else {
            NSSound.beep()
            let alert = NSAlert()
            alert.messageText = "标签页已固定"
            alert.informativeText = "这个窗格里有固定的标签页。请先取消固定，再关闭窗格。"
            alert.alertStyle = .informational
            alert.addButton(withTitle: "好")
            alert.runModal()
            return
        }
        
        let documents = pane.tabs.map(\.document)
        
        self.reviewDocuments(documents) { [weak self, weak pane] canClose in
            guard canClose, let self, let pane else { return }
            
            for tab in pane.tabs {
                self.stopObservingTextStorage(of: tab.document)
                tab.document.close()
            }
            
            self.removePane(pane)
            self.updateSplitState()
        }
    }
    
    
    /// Places a pane next to another one, nesting a container when the directions differ.
    ///
    /// - Parameters:
    ///   - newViewController: The pane to insert.
    ///   - currentViewController: The pane it is placed next to.
    ///   - isVertical: `true` to place it to the right, `false` to place it below.
    private func insertPane(_ newViewController: EditorViewController, beside currentViewController: EditorViewController, isVertical: Bool) {
        
        let parentGroup = self.splitGroup(containing: currentViewController) ?? self
        let item = self.makeSplitViewItem(for: newViewController)
        
        guard let index = parentGroup.splitViewItems.firstIndex(where: { $0.viewController === currentViewController }) else {
            return assertionFailure()
        }
        
        if parentGroup.splitViewItems.count == 1 {
            // a lone pane simply adopts the requested direction
            parentGroup.splitView.isVertical = isVertical
            parentGroup.insertSplitViewItem(item, at: index + 1)
        } else if parentGroup.splitView.isVertical == isVertical {
            // same direction: put the new pane beside the current one
            parentGroup.insertSplitViewItem(item, at: index + 1)
        } else {
            // other direction: wrap the current pane and the new one in a nested container
            let group = SplitGroupViewController(isVertical: isVertical)
            self.removeItem(for: currentViewController, from: parentGroup)
            parentGroup.insertSplitViewItem(self.makeSplitViewItem(for: group), at: index)
            group.addSplitViewItem(self.makeSplitViewItem(for: currentViewController))
            group.addSplitViewItem(item)
        }
    }
    
    
    /// Closes one of the split editors, collapsing any container left with a single child.
    @IBAction func closeSplitTextView(_ sender: Any?) {
        
        guard
            self.editorViewControllers.count > 1,
            let currentViewController = self.baseEditorViewController(for: sender)
        else { return }
        
        self.closePane(currentViewController)
    }
    
    
    /// Removes a pane from the layout and gives the freed space to its siblings.
    ///
    /// The pane's documents have already been reviewed and closed by the caller.
    ///
    /// - Parameter viewController: The pane to remove.
    private func removePane(_ viewController: EditorViewController) {
        
        if viewController === self.zoomedPane {
            self.resetZoomState()
        }
        
        for textView in viewController.allTextViews {
            NotificationCenter.default.removeObserver(self, name: EditorTextView.DidLiveChangeSelectionMessage.name, object: textView)
            textView.undoManager?.removeAllActions(withTarget: textView)
        }
        
        // end current editing
        NSTextInputContext.current?.discardMarkedText()
        
        // move focus to the next text view if the view to close has a focus
        if self.focusedChild == viewController {
            let children = self.editorViewControllers
            let deleteIndex = children.firstIndex(of: viewController) ?? 0
            let newFocusEditorViewController = children[safe: deleteIndex - 1] ?? children.last!
            
            self.view.window?.makeFirstResponderDiscardingMarkedText(newFocusEditorViewController.textView)
        }
        
        guard
            let parentGroup = self.splitGroup(containing: viewController),
            parentGroup.splitViewItems.contains(where: { $0.viewController === viewController })
        else { return }
        
        self.removeItem(for: viewController, from: parentGroup)
        self.collapseSingleChildGroups(from: parentGroup)
        self.updateSplitState()
        self.scheduleRatioRebalance()
    }
    
    
    // MARK: Public Methods
    
    /// Asks the user what to do with the given documents, one after another.
    ///
    /// A pane's document has no window of its own, so AppKit never gets the chance to
    /// review it; it has to be reviewed here, before the pane or the window goes away.
    ///
    /// - Parameters:
    ///   - documents: The documents to review.
    ///   - completion: Called with `true` when every one of them may be closed.
    func reviewDocuments(_ documents: [Document], completion: @escaping (Bool) -> Void) {
        
        let pending = documents.filter(\.isDocumentEdited)
        guard !pending.isEmpty else {
            completion(true)
            return
        }
        
        self.pendingReviewDocuments = pending
        self.reviewCompletion = completion
        self.reviewNextDocument()
    }
    
    
    // MARK: Private Methods
    
    /// Gives every editor pane the same share of the container it sits in.
    ///
    /// `NSSplitViewController` squeezes an existing pane down to its minimum thickness and
    /// hands the rest to the newly inserted item, so the dividers have to be reset by hand
    /// after a split. Each container is divided evenly among its direct children, so nested
    /// containers end up with equal shares at every level as well.
    ///
    /// - Parameter group: The container to rebalance, including its nested containers.
    private func rebalancePanes(in group: NSSplitViewController) {
        
        let items = group.splitViewItems
        
        if items.count > 1 {
            let splitView = group.splitView
            let thickness = splitView.isVertical ? splitView.bounds.width : splitView.bounds.height
            let dividerThickness = splitView.dividerThickness
            
            // The toolbar, tab bar and status bar are laid out over the top and bottom of the
            // window, so the panes at those edges show less than their split item's height.
            // Balance the visible areas instead of the raw split item frames.
            var leadingInset: CGFloat = 0
            var trailingInset: CGFloat = 0
            if !splitView.isVertical, group === self, let window = self.view.window {
                let content = self.view.convert(window.contentLayoutRect, from: nil)
                leadingInset = max(0, self.view.bounds.maxY - content.maxY)
                trailingInset = (window.windowController?.contentViewController as? WindowContentViewController)?.statusBarHeight ?? 0
            }
            
            let available = thickness - dividerThickness * CGFloat(items.count - 1) - leadingInset - trailingInset
            
            if available > 0 {
                let share = available / CGFloat(items.count)
                
                for index in 0..<(items.count - 1) {
                    let position = leadingInset + share * CGFloat(index + 1) + dividerThickness * CGFloat(index)
                    splitView.setPosition(position, ofDividerAt: index)
                }
            }
        }
        
        // let the containers take their new size before touching their dividers
        group.view.layoutSubtreeIfNeeded()
        
        for item in items {
            if let nested = item.viewController as? SplitGroupViewController {
                self.rebalancePanes(in: nested)
            }
        }
    }
    
    
    /// Presents the next pending review, or reports success.
    private func reviewNextDocument() {
        
        guard let document = self.pendingReviewDocuments.popLast() else {
            let completion = self.reviewCompletion
            self.reviewCompletion = nil
            completion?(true)
            return
        }
        
        document.canClose(withDelegate: self,
                          shouldClose: #selector(document(_:shouldClose:contextInfo:)),
                          contextInfo: nil)
    }
    
    
    /// Callback for the review of a pane document.
    @objc private func document(_ document: NSDocument, shouldClose: Bool, contextInfo: UnsafeMutableRawPointer?) {
        
        guard shouldClose else {
            self.pendingReviewDocuments = []
            let completion = self.reviewCompletion
            self.reviewCompletion = nil
            completion?(false)
            return
        }
        
        // the user has been asked already; closing must not ask a second time
        document.updateChangeCount(.changeCleared)
        
        self.reviewNextDocument()
    }
    
    
    /// Closes the documents that exist only because a pane shows them.
    private func closeSecondaryDocuments() {
        
        for editorViewController in self.editorViewControllers {
            for tab in editorViewController.tabs where tab.document !== self.document {
                tab.document.close()
            }
        }
    }
    
    
    /// Balances every container, retrying briefly so that freshly inserted panes and
    /// containers, which only get their size on a later layout pass, are included.
    private func scheduleRatioRebalance() {
        
        Task { @MainActor [weak self] in
            for _ in 0..<3 {
                guard let self else { return }
                
                self.view.layoutSubtreeIfNeeded()
                self.rebalancePanes(in: self)
                
                try? await Task.sleep(for: .milliseconds(16))
            }
            
            // The navigation bar animates in after a split, which changes the pane's inner
            // layout; balance once more after it settled so nested splits end up even, too.
            try? await Task.sleep(for: .milliseconds(300))
            
            guard let self else { return }
            self.view.layoutSubtreeIfNeeded()
            self.rebalancePanes(in: self)
        }
    }
    
    
    /// All editors in visual order, flattened across nested containers.
    private var editorViewControllers: [EditorViewController] {
        
        var editors: [EditorViewController] = []
        
        func collect(_ group: NSSplitViewController) {
            for item in group.splitViewItems {
                if let editor = item.viewController as? EditorViewController {
                    editors.append(editor)
                } else if let nested = item.viewController as? NSSplitViewController {
                    collect(nested)
                }
            }
        }
        
        collect(self)
        
        return editors
    }
    
    
    /// The pane the user is in, provided it is an empty split pane waiting for content.
    ///
    /// Opening a document while such a pane has the focus loads that document into the pane
    /// instead of creating a window for it.
    var focusedBlankEditor: EditorViewController? {
        
        guard
            self.editorViewControllers.count > 1,
            let focusedChild,
            focusedChild.tabs.count == 1
        else { return nil }
        
        let document = focusedChild.document
        guard document.fileURL == nil, !document.isDocumentEdited, document.textStorage.length == 0 else { return nil }
        
        return focusedChild
    }
    
    
    /// Fills the blank focused pane with the given document.
    ///
    /// - Parameter document: The document that was opened for the pane.
    /// - Returns: `false` if the pane disappeared in the meantime and the document is still homeless.
    func absorb(_ document: Document) -> Bool {
        
        guard let viewController = self.focusedBlankEditor else { return false }
        
        let placeholderTab = viewController.selectedTab
        let sourceTextView = viewController.textView
        
        self.stopObservingTextStorage(of: placeholderTab.document)
        viewController.removeTab(placeholderTab)
        
        self.addTab(document, to: viewController, copying: sourceTextView)
        
        // the empty placeholder document has no reason to live on
        placeholderTab.document.close()
        
        return true
    }
    
    
    /// Whether the window is split into more than one pane.
    var isSplit: Bool {
        
        self.editorViewControllers.count > 1
    }
    
    
    /// Whether any tab in the window is pinned.
    var hasPinnedTabs: Bool {
        
        self.editorViewControllers.contains(where: \.hasPinnedTab)
    }
    
    
    /// Opens a new document as a tab in the focused pane.
    ///
    /// - Returns: `false` when there is no pane to add the tab to.
    @discardableResult
    func newTabInFocusedPane() -> Bool {
        
        guard let pane = self.focusedChild ?? self.editorViewControllers.first else { return false }
        
        return self.newTab(in: pane)
    }
    
    
    /// The documents this window shows, in pane and tab order.
    var paneDocuments: [Document] {
        
        self.editorViewControllers.flatMap { $0.tabs.map(\.document) }
    }
    
    
    #if DEBUG
    /// Builds a representative three-pane layout with extra tabs and a pinned tab.
    ///
    /// Only used for visual verification (see the `COT_UI_DEMO` environment flag).
    func setUpDemoLayout() {
        
        guard
            let window = self.view.window,
            let topPane = self.editorViewControllers.first,
            self.editorViewControllers.count == 1
        else { return }
        
        window.setFrame(NSRect(x: 200, y: 140, width: 1200, height: 820), display: true)
        
        do {
            // two more tabs in the top pane
            self.newTab(in: topPane)
            self.newTab(in: topPane)
            
            // bottom pane: two panes side by side below the top one
            let bottomDocument = try self.makePaneDocument()
            let bottomPane = self.makeEditorViewController(document: bottomDocument, copying: topPane)
            self.insertPane(bottomPane, beside: topPane, isVertical: false)
            self.addTab(try self.makePaneDocument(), to: bottomPane, copying: bottomPane.textView)
            
            let rightDocument = try self.makePaneDocument()
            let rightPane = self.makeEditorViewController(document: rightDocument, copying: bottomPane)
            self.insertPane(rightPane, beside: bottomPane, isVertical: true)
            
            // a pinned tab in the right pane
            self.addTab(try self.makePaneDocument(), to: rightPane, copying: rightPane.textView)
            if let pinnedTab = rightPane.tabs.last {
                rightPane.debugTogglePin(pinnedTab)  // pins it and moves it to the front
            }
            if let firstTab = rightPane.tabs.first {
                rightPane.select(tab: firstTab)
            }
            
            topPane.select(tab: topPane.tabs[0])
        } catch {
            NSApp.presentError(error)
        }
        
        self.updateSplitState()
        self.scheduleRatioRebalance()
        self.view.window?.makeFirstResponder(topPane.textView)
    }
    
    
    /// Adds two more tabs to the single pane, for a screenshot of an un-split window.
    func setUpDemoTabsOnly() {
        
        guard let pane = self.editorViewControllers.first else { return }
        
        self.newTab(in: pane)
        self.newTab(in: pane)
        
        if let first = pane.tabs.first {
            pane.select(tab: first)
        }
    }
    
    
    /// Pops up the text view's context menu for a screenshot, closing it again afterwards.
    func setUpDemoMenu() {
        
        guard let textView = self.focusedTextView else { return }
        
        NSApp.activate(ignoringOtherApps: true)
        self.view.window?.makeKeyAndOrderFront(nil)
        self.view.window?.makeFirstResponder(textView)
        
        let menu = textView.makeContextMenu()
        
        // Menu tracking runs in the event-tracking run loop mode, so the timer has to
        // live there to fire while the menu is open.
        let timer = Timer(timeInterval: 3, repeats: false) { _ in menu.cancelTracking() }
        RunLoop.main.add(timer, forMode: .eventTracking)
        
        menu.popUp(positioning: nil, at: NSPoint(x: 60, y: 120), in: textView)
    }
    #endif
    
    
    /// The document the focused pane edits.
    var focusedDocument: Document {
        
        self.focusedChild?.document ?? self.document
    }
    
    
    /// Returns the document that owns the given text storage.
    ///
    /// - Parameter textStorage: A text storage shown in one of the panes.
    /// - Returns: The document owning it, or `nil` if the text storage is foreign.
    func document(for textStorage: NSTextStorage) -> Document? {
        
        for pane in self.editorViewControllers {
            for tab in pane.tabs where tab.document.textStorage === textStorage {
                return tab.document
            }
        }
        
        return nil
    }
    
    
    /// Returns the document the given text view belongs to.
    ///
    /// - Parameter textView: A text view in one of the panes.
    /// - Returns: The document the pane edits, or `nil` if the text view is foreign.
    func document(for textView: NSTextView) -> Document? {
        
        for pane in self.editorViewControllers {
            if let document = pane.document(for: textView) {
                return document
            }
        }
        
        return nil
    }
    
    
    /// Returns the split container that holds the given view controller.
    ///
    /// - Parameter viewController: The view controller whose container is searched.
    /// - Returns: The nearest enclosing split view controller.
    private func splitGroup(containing viewController: NSViewController) -> NSSplitViewController? {
        
        var current = viewController.parent
        while let parent = current {
            if let group = parent as? NSSplitViewController { return group }
            current = parent.parent
        }
        
        return nil
    }
    
    
    /// Removes the split view item that hosts the given view controller.
    ///
    /// - Parameters:
    ///   - viewController: The hosted view controller.
    ///   - group: The split view controller to remove it from.
    private func removeItem(for viewController: NSViewController, from group: NSSplitViewController) {
        
        guard let item = group.splitViewItems.first(where: { $0.viewController === viewController }) else { return }
        
        group.removeSplitViewItem(item)
    }
    
    
    /// Creates a split view item for an editor or a nested container.
    ///
    /// - Parameter viewController: The view controller to place in the split view.
    /// - Returns: The configured split view item.
    private func makeSplitViewItem(for viewController: NSViewController) -> NSSplitViewItem {
        
        let splitViewItem = NSSplitViewItem(viewController: viewController)
        splitViewItem.minimumThickness = 100
        
        return splitViewItem
    }
    
    
    /// Moves lone children up while a container is left with a single pane.
    ///
    /// - Parameter group: The container to start from.
    private func collapseSingleChildGroups(from group: NSSplitViewController) {
        
        var group = group
        while group !== self, group.splitViewItems.count == 1 {
            let remaining = group.splitViewItems[0].viewController
            
            guard
                let parentGroup = group.parent as? NSSplitViewController,
                let index = parentGroup.splitViewItems.firstIndex(where: { $0.viewController === group })
            else { break }
            
            group.removeSplitViewItem(group.splitViewItems[0])
            self.removeItem(for: group, from: parentGroup)
            parentGroup.insertSplitViewItem(self.makeSplitViewItem(for: remaining), at: index)
            
            group = parentGroup
        }
    }
    
    
    /// Syncs the shared state observed by the tab bars with the actual layout.
    private func updateSplitState() {
        
        let isSplit = self.editorViewControllers.count > 1
        self.splitState.canClose = isSplit
        
        if let focusedChild = self.focusedChild, let group = self.splitGroup(containing: focusedChild) {
            self.splitState.isVertical = group.splitView.isVertical
        }
        
        for editorViewController in self.editorViewControllers {
            for tab in editorViewController.tabs {
                tab.isClosable = (tab.document !== self.document)
            }
            
            let containsWindowDocument = editorViewController.tabs.contains { $0.document === self.document }
            editorViewController.setCanClosePane(isSplit && !containsWindowDocument)
            editorViewController.updateTabState()
            editorViewController.updateNavigationBarVisibility(animated: true)
        }
        
        NotificationCenter.default.post(name: Self.splitLayoutDidChangeNotification, object: self)
    }
    
    
    /// Creates a new editor (tab group) for a pane.
    ///
    /// - Parameters:
    ///   - document: The document the pane edits.
    ///   - otherViewController: The editor whose state is copied.
    /// - Returns: The editor view controller created.
    @discardableResult private func makeEditorViewController(document: Document, copying otherViewController: EditorViewController?) -> sending EditorViewController {
        
        let viewController = EditorViewController(document: document, splitState: self.splitState)
        
        // wire the tab bar commands to this document view controller
        viewController.requestNewTab = { [weak self, weak viewController] in
            guard let self, let viewController else { return }
            self.newTab(in: viewController)
        }
        viewController.requestCloseTab = { [weak self, weak viewController] tab in
            guard let self, let viewController else { return }
            self.closeTab(tab, in: viewController)
        }
        viewController.requestClosePane = { [weak self, weak viewController] in
            guard let self, let viewController else { return }
            self.closePane(viewController)
        }
        viewController.didSelectTab = { [weak self, weak viewController] _ in
            guard let self, let viewController else { return }
            self.focusedChild = viewController
            self.view.window?.makeFirstResponderDiscardingMarkedText(viewController.textView)
            NotificationCenter.default.post(name: Self.focusedDocumentDidChangeNotification, object: self)
        }
        
        // observe edits so each document keeps its own syntax parse up to date
        self.observeTextStorage(of: document)
        
        // setup textView
        if let textView = viewController.textView {
            self.configureTextView(textView, copying: otherViewController?.textView)
            viewController.showsLineNumber = self.showsLineNumber  // need to be set after setting text orientation
        }
        
        // observe cursor
        NotificationCenter.default.addObserver(self, selector: #selector(textViewDidLiveChangeSelection),
                                               name: EditorTextView.DidLiveChangeSelectionMessage.name,
                                               object: viewController.textView)
        
        return viewController
    }
    
    
    /// Applies the window-wide editor settings to a text view of a pane or a tab.
    ///
    /// - Parameters:
    ///   - textView: The text view to configure.
    ///   - baseTextView: The text view whose states are copied, or `nil` for a fresh one.
    private func configureTextView(_ textView: EditorTextView, copying baseTextView: EditorTextView?) {
        
        let document = textView.textStorage.flatMap { self.document(for: $0) } ?? self.document
        textView.isEditable = document.isEditable
        textView.wrapsLines = self.wrapsLines
        textView.showsInvisibles = self.showsInvisibles
        textView.setLayoutOrientation(self.verticalLayoutOrientation ? .vertical : .horizontal)
        textView.showsPageGuide = self.showsPageGuide
        textView.showsIndentGuides = self.showsIndentGuides
        
        // copy base textView states
        if let baseTextView {
            textView.font = baseTextView.font
            textView.usesAntialias = baseTextView.usesAntialias
            textView.ligature = baseTextView.ligature
            textView.theme = baseTextView.theme
            textView.tabWidth = baseTextView.tabWidth
            textView.isAutomaticTabExpansionEnabled = baseTextView.isAutomaticTabExpansionEnabled
            
            // copy parsed syntax highlight
            if let highlights = baseTextView.layoutManager?.syntaxHighlights(), !highlights.isEmpty {
                textView.layoutManager?.apply(highlights: highlights, theme: self.theme, in: textView.string.range)
            }
        } else if let theme = self.theme {
            textView.theme = theme
        }
        
        if textView.baseWritingDirection != self.writingDirection {
            textView.baseWritingDirection = self.writingDirection
        }
        
        // the syntax controller belongs to the document, so give it the pane's theme
        if let theme = textView.theme {
            document.syntaxController.theme = theme
        }
    }
    
    
    /// Observes the text storage of a document that lives only in a pane.
    ///
    /// - Parameter document: The document to observe.
    private func observeTextStorage(of document: Document) {
        
        guard document !== self.document else { return }
        
        NotificationCenter.default.addObserver(self, selector: #selector(textStorageDidProcessEditing),
                                               name: NSTextStorage.didProcessEditingNotification,
                                               object: document.textStorage)
    }
    
    
    /// Stops observing the text storage of a document that leaves the window.
    ///
    /// - Parameter document: The document to stop observing.
    private func stopObservingTextStorage(of document: Document) {
        
        guard document !== self.document else { return }
        
        NotificationCenter.default.removeObserver(self, name: NSTextStorage.didProcessEditingNotification,
                                                  object: document.textStorage)
    }
    
    
    /// Finds the base `EditorViewController` for split editor management actions.
    ///
    /// - Parameter sender: The action sender.
    /// - Returns: An editor view controller, or `nil` if not found.
    private func baseEditorViewController(for sender: Any?) -> EditorViewController? {
        
        if let view = sender as? NSView,
           let controller = self.editorViewControllers.first(where: { view.isDescendant(of: $0.view) })
        {
            controller
        } else {
            self.focusedChild
        }
    }
    
    
    /// Moves focus to the next/previous text view, or if not split, refocuses the current text view.
    ///
    /// - Parameter reverse: If `true`, move to the previous editor.
    private func focusNextSplitEditor(reverse: Bool = false) {
        
        let children = self.editorViewControllers
        
        guard let focusedChild = self.focusedChild,
              let focusIndex = children.firstIndex(of: focusedChild),
              let nextChild = reverse
                ? children[safe: focusIndex - 1] ?? children.last
                : children[safe: focusIndex + 1] ?? children.first
        else { return assertionFailure() }
        
        self.view.window?.makeFirstResponderDiscardingMarkedText(nextChild.textView)
    }
    
    
    /// Applies the given theme to child text views.
    ///
    /// - Parameter name: The name of the theme to apply.
    private func setTheme(name: String) {
        
        assert(Thread.isMainThread)
        
        let theme: Theme
        do {
            theme = try ThemeManager.shared.setting(name: name)
        } catch {
            return self.presentErrorAsSheet(error)
        }
        
        self.themeName = name
        self.document.syntaxController.theme = theme
        
        for textView in self.textViews {
            textView.theme = theme
            textView.layoutManager?.invalidateHighlight(theme: theme)
        }
        
        self.invalidateRestorableState()
    }
}
