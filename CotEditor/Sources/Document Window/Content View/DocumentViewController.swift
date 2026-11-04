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
    
    private static let maximumNumberOfSplitEditors = 4
    
    private let splitState = SplitState()
    
    private weak var focusedChild: EditorViewController?
    
    private var themeName: String?
    private var theme: Theme?  { self.focusedTextView?.theme }
    
    
    private var observers: Set<AnyCancellable> = []
    private var defaultsObservers: Set<AnyCancellable> = []
    private var windowCloseObserver: AnyCancellable?
    
    
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
                .compactMap { [weak self] textView in self?.editorViewControllers.first { $0.textView == textView } }
                .sink { [weak self] in
                    self?.focusedChild = $0
                    NotificationCenter.default.post(name: Self.focusedDocumentDidChangeNotification, object: self)
                },
        ]
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
                return self.splitViewItems.count > 1
                
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
    
    /// The array of all child text views.
    var textViews: [EditorTextView] {
        
        self.editorViewControllers.compactMap(\.textView)
    }
    
    /// The text view currently focused on.
    var focusedTextView: EditorTextView? {
        
        self.focusedChild?.textView ?? self.textViews.first
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
        
        let opened: NSDocument
        do {
            opened = try NSDocumentController.shared.openUntitledDocumentAndDisplay(false)
        } catch {
            NSApp.presentError(error)
            return
        }
        
        guard let document = opened as? Document else { return assertionFailure() }
        
        // the new document belongs to this pane, never to a window of its own
        document.isTransient = false
        document.syntaxController.setupParser()
        
        let newEditorViewController = self.makeEditorViewController(document: document, copying: currentViewController)
        self.insertPane(newEditorViewController, beside: currentViewController, isVertical: isVertical)
        
        self.splitState.isVertical = isVertical
        self.updateSplitState()
        self.scheduleRatioRebalance()
        
        window.makeFirstResponderDiscardingMarkedText(newEditorViewController.textView)
    }
    
    
    /// Gives a pane another document without touching the layout.
    ///
    /// - Parameters:
    ///   - viewController: The pane to refill.
    ///   - document: The document it should show from now on.
    private func replaceDocument(of viewController: EditorViewController, with document: Document) {
        
        guard
            let parentGroup = self.splitGroup(containing: viewController),
            let index = parentGroup.splitViewItems.firstIndex(where: { $0.viewController === viewController })
        else { return assertionFailure() }
        
        let previousDocument = viewController.document
        
        document.syntaxController.setupParser()
        
        let newViewController = self.makeEditorViewController(document: document, copying: viewController)
        self.removeItem(for: viewController, from: parentGroup)
        parentGroup.insertSplitViewItem(self.makeSplitViewItem(for: newViewController), at: index)
        
        self.focusedChild = newViewController
        self.updateSplitState()
        self.scheduleRatioRebalance()
        self.view.window?.makeFirstResponderDiscardingMarkedText(newViewController.textView)
        
        NotificationCenter.default.post(name: Self.focusedDocumentDidChangeNotification, object: self)
        
        // the empty placeholder document has no reason to live on
        if previousDocument !== self.document {
            previousDocument.close()
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
        
        if let textView = currentViewController.textView {
            NotificationCenter.default.removeObserver(self, name: EditorTextView.DidLiveChangeSelectionMessage.name, object: textView)
            textView.undoManager?.removeAllActions(withTarget: textView)
        }
        
        // end current editing
        NSTextInputContext.current?.discardMarkedText()
        
        // move focus to the next text view if the view to close has a focus
        if self.focusedChild == currentViewController {
            let children = self.editorViewControllers
            let deleteIndex = children.firstIndex(of: currentViewController) ?? 0
            let newFocusEditorViewController = children[safe: deleteIndex - 1] ?? children.last!
            
            self.view.window?.makeFirstResponder(newFocusEditorViewController.textView)
        }
        
        guard
            let parentGroup = self.splitGroup(containing: currentViewController),
            parentGroup.splitViewItems.contains(where: { $0.viewController === currentViewController })
        else { return }
        
        self.removeItem(for: currentViewController, from: parentGroup)
        self.collapseSingleChildGroups(from: parentGroup)
        self.updateSplitState()
        self.scheduleRatioRebalance()
        
        // a pane that edits another file owns a window-less document: let it go
        if currentViewController.document !== self.document {
            currentViewController.document.close()
        }
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
            let available = thickness - dividerThickness * CGFloat(items.count - 1)
            
            if available > 0 {
                let share = available / CGFloat(items.count)
                
                for index in 0..<(items.count - 1) {
                    let position = share * CGFloat(index + 1) + dividerThickness * CGFloat(index)
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
    
    
    /// Closes the documents that exist only because a pane shows them.
    private func closeSecondaryDocuments() {
        
        for editorViewController in self.editorViewControllers where editorViewController.document !== self.document {
            editorViewController.document.close()
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
            let focusedChild
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
        
        self.replaceDocument(of: viewController, with: document)
        
        return true
    }
    
    
    /// The documents this window shows, in pane order.
    var paneDocuments: [Document] {
        
        self.editorViewControllers.map(\.document)
    }
    
    
    /// The document the focused pane edits.
    var focusedDocument: Document {
        
        self.focusedChild?.document ?? self.document
    }
    
    
    /// Returns the document that owns the given text storage.
    ///
    /// - Parameter textStorage: A text storage shown in one of the panes.
    /// - Returns: The document owning it, or `nil` if the text storage is foreign.
    func document(for textStorage: NSTextStorage) -> Document? {
        
        self.editorViewControllers.first { $0.document.textStorage === textStorage }?.document
    }
    
    
    /// Returns the document the given text view belongs to.
    ///
    /// - Parameter textView: A text view in one of the panes.
    /// - Returns: The document the pane edits, or `nil` if the text view is foreign.
    func document(for textView: NSTextView) -> Document? {
        
        self.editorViewControllers.first { $0.textView === textView }?.document
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
    
    
    /// Syncs the shared state observed by the navigation bar with the actual layout.
    private func updateSplitState() {
        
        self.splitState.canClose = self.editorViewControllers.count > 1
        
        if let focusedChild = self.focusedChild, let group = self.splitGroup(containing: focusedChild) {
            self.splitState.isVertical = group.splitView.isVertical
        }
        
        // an empty navigation bar is noise: let each pane decide whether to show it
        for editorViewController in self.editorViewControllers {
            editorViewController.updateNavigationBarVisibility(animated: true)
        }
    }
    
    
    /// Creates a new editor view for a pane.
    ///
    /// - Parameters:
    ///   - document: The document the pane edits.
    ///   - otherViewController: The editor whose state is copied.
    /// - Returns: The editor view controller created.
    @discardableResult private func makeEditorViewController(document: Document, copying otherViewController: EditorViewController?) -> sending EditorViewController {
        
        let viewController = EditorViewController(document: document, splitState: self.splitState)
        
        // observe cursor
        NotificationCenter.default.addObserver(self, selector: #selector(textViewDidLiveChangeSelection),
                                               name: EditorTextView.DidLiveChangeSelectionMessage.name,
                                               object: viewController.textView)
        
        // observe edits so each document keeps its own syntax parse up to date
        if document !== self.document {
            NotificationCenter.default.addObserver(self, selector: #selector(textStorageDidProcessEditing),
                                                   name: NSTextStorage.didProcessEditingNotification,
                                                   object: document.textStorage)
        }
        
        // setup textView
        let textView = viewController.textView!
        textView.isEditable = document.isEditable
        textView.wrapsLines = self.wrapsLines
        textView.showsInvisibles = self.showsInvisibles
        textView.setLayoutOrientation(self.verticalLayoutOrientation ? .vertical : .horizontal)
        textView.showsPageGuide = self.showsPageGuide
        textView.showsIndentGuides = self.showsIndentGuides
        viewController.showsLineNumber = self.showsLineNumber  // need to be set after setting text orientation
        
        // copy base textView states
        if let baseTextView = otherViewController?.textView {
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
        }
        
        if textView.baseWritingDirection != self.writingDirection {
            textView.baseWritingDirection = self.writingDirection
        }
        
        // the syntax controller belongs to the document, so give it the pane's theme
        if document !== self.document {
            document.syntaxController.theme = textView.theme
        }
        
        return viewController
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
