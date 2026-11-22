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
import UniformTypeIdentifiers
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
        static let showsLineNumber = "showsLineNumber"
    }
    
    
    // MARK: Public Properties
    
    private(set) var document: Document
    
    
    // MARK: Private Properties
    
    /// Posted when the pane that has the focus starts editing another document.
    static let focusedDocumentDidChangeNotification = Notification.Name("DocumentViewControllerFocusedDocumentDidChange")
    
    /// Posted when the window is split or un-split, or when a pane changes its tabs.
    static let splitLayoutDidChangeNotification = Notification.Name("DocumentViewControllerSplitLayoutDidChange")
    
    /// Posted when the harmonized window chrome palette updates for theme, appearance, or Studio Palette changes.
    static let didUpdateChromePaletteNotification = Notification.Name("DocumentViewControllerDidUpdateChromePalette")
    
    private static let maximumNumberOfSplitEditors = 4
    private static let maximumNumberOfTabsPerPane = 8
    
    private let splitState = SplitState()
    
    private weak var focusedChild: EditorViewController?
    
    /// The line-number value to give the first pane of a restored window.
    private var rememberedShowsLineNumber: Bool?
    
    /// The pane that currently fills the window while zoomed, if any.
    private var zoomedPane: EditorViewController?
    
    /// Whether a split pane is currently zoomed to fill the window (`⌃A Z`).
    var isPaneZoomed: Bool { self.zoomedPane != nil }
    
    /// The split view items hidden by the zoom, restored when zooming out.
    private var itemsCollapsedByZoom: [NSSplitViewItem] = []
    private var aiResultPanel: AIResultPanelController?
    
    private var themeName: String?
    private var theme: Theme?  { self.focusedTextView?.theme }
    
    /// The theme applied to the editor, for views that should match its look.
    var currentTheme: Theme?  { self.theme }
    
    /// Unified chrome palette shared across titlebar, tab strip, status bar, and toolbar pills.
    private(set) var currentChromePalette: WindowChromePalette?
    
    
    private var observers: Set<AnyCancellable> = []
    private var defaultsObservers: Set<AnyCancellable> = []
    private var windowCloseObserver: AnyCancellable?
    private var sessionSaveTask: Task<Void, Never>?
    
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
    private var didRestorePersistedPaneTabs = false
    private var isRestoringPersistedPaneTabs = false
    private var proportionConstraintsBySplitView: [ObjectIdentifier: [NSLayoutConstraint]] = [:]
    private var isApplyingSplitPaneSizes = false
    private static var didRestoreAppPaneTabsThisLaunch = false
    
    
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
        
        self.observeTextStorage(of: self.document)
        
        // observe
        self.observers = [
            // observe theme change
            UserDefaults.standard.publisher(for: .theme, initial: false)
                .sink { [weak self] themeName in
                    guard let self else { return }
                    if let window = self.viewIfLoaded?.window, window.isVisible, !window.isAppearanceTransitionActive {
                        window.performSmoothAppearanceTransition(duration: 0.22) {
                            self.setTheme(name: themeName)
                        }
                    } else {
                        self.setTheme(name: themeName)
                    }
                },
            NotificationCenter.default.publisher(for: .didUpdateSettingNotification, object: ThemeManager.shared)
                .map { $0.userInfo!["change"] as! SettingChange }
                .filter { [weak self] in $0.old == self?.themeName }
                .compactMap(\.new)
                .throttle(for: 0.1, scheduler: DispatchQueue.main, latest: true)
                .sink { [weak self] in self?.setTheme(name: $0) },
            
            // observe appearance change for theme toggle
            self.view.publisher(for: \.effectiveAppearance)
                .sink { [weak self] appearance in
                    guard let self, self.viewIfLoaded?.window != nil else { return }
                    guard
                        !UserDefaults.standard[.pinsThemeAppearance],
                        let currentThemeName = self.themeName,
                        let themeName = ThemeManager.shared.equivalentSettingName(to: currentThemeName, forDark: appearance.isDark),
                        currentThemeName != themeName
                    else {
                        self.updateWindowChromePalette()
                        return
                    }
                    
                    if let window = self.viewIfLoaded?.window, window.isVisible, !window.isAppearanceTransitionActive {
                        window.performSmoothAppearanceTransition(duration: 0.28) {
                            self.setTheme(name: themeName)
                        }
                    } else {
                        self.setTheme(name: themeName)
                    }
                },
            
            NotificationCenter.default.publisher(for: StudioPaletteManager.paletteDidChangeNotification)
                .sink { [weak self] _ in
                    self?.updateWindowChromePalette()
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
            
            // release programmatic split-proportion constraints as soon as the user drags a divider manually
            NotificationCenter.default.publisher(for: NSSplitView.willResizeSubviewsNotification)
                .compactMap { $0.object as? NSSplitView }
                .filter { [weak self] splitView in
                    guard let self, self.viewIfLoaded?.window != nil else { return false }
                    guard !self.isApplyingSplitPaneSizes else { return false }
                    guard NSEvent.pressedMouseButtons != 0, !(self.view.window?.inLiveResize ?? false) else { return false }
                    return splitView === self.splitView || splitView.isDescendant(of: self.view)
                }
                .sink { [weak self] splitView in
                    self?.clearProportionConstraints(for: splitView)
                },
            
            // persist divider proportions when the user drags a split divider
            NotificationCenter.default.publisher(for: NSSplitView.didResizeSubviewsNotification)
                .compactMap { $0.object as? NSSplitView }
                .filter { [weak self] splitView in
                    guard let self, self.viewIfLoaded?.window != nil else { return false }
                    return splitView === self.splitView || splitView.isDescendant(of: self.view)
                }
                .debounce(for: .milliseconds(250), scheduler: RunLoop.main)
                .sink { [weak self] _ in
                    self?.savePaneTabsSessionToDatabase()
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
        
        // Bring the previous tabs back into a single pane. The old split/window tree is not
        // recreated, so restarting never reopens a cluttered multi-pane layout.
        self.restorePersistedPaneTabsIfNeeded()
        
        self.updateWindowChromePalette()
        
        DispatchQueue.main.async { [weak self] in
            guard let self, let window = self.view.window else { return }
            self.view.layoutSubtreeIfNeeded()
            let isCenterOpen = (window.windowController as? DocumentWindowController)?.workspaceContentViewController?.activeCenter != nil
            guard !isCenterOpen, let textView = self.focusedTextView else { return }
            if window.firstResponder as? EditorTextView == nil {
                window.makeFirstResponderDiscardingMarkedText(textView)
            }
            textView.updateInsertionPointStateAndRestartTimer(true)
            textView.needsDisplay = true
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
            case #keyPath(showsPageGuide),
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
        
        coder.encode(self.showsLineNumber, forKey: SerializationKey.showsLineNumber)
    }
    
    
    override func restoreState(with coder: NSCoder) {
        
        super.restoreState(with: coder)
        
        if coder.containsValue(forKey: SerializationKey.showsLineNumber) {
            let showsLineNumbers = coder.decodeBool(forKey: SerializationKey.showsLineNumber)
            self.rememberedShowsLineNumber = showsLineNumbers
            
            // the panes usually exist by now; otherwise the first one picks the value up when
            // it is created and reads `showsLineNumber`
            self.editorViewControllers.first?.showsLineNumber = showsLineNumbers
        }
        
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
            case #selector(toggleEditable), #selector(Document.toggleEditable(_:)):
                let editable = self.focusedDocument.isEditable
                if let menuItem = item as? NSMenuItem {
                    menuItem.title = editable
                        ? AppLanguage.text("锁定文档（演示防误触）", en: "Lock Document (Presentation Mode)")
                        : AppLanguage.text("解除文档锁定", en: "Unlock Document")
                    menuItem.image = NSImage(
                        systemSymbolName: editable ? "lock" : "lock.open",
                        accessibilityDescription: nil
                    )
                    if #unavailable(macOS 26) {
                        menuItem.image = nil
                    }
                } else if let toolbarItem = item as? StatableToolbarItem {
                    toolbarItem.state = editable ? .off : .on
                    toolbarItem.toolTip = editable
                        ? AppLanguage.text("点击锁定当前文档，防止演示/讲解时误操作", en: "Lock current document to prevent accidental edits")
                        : AppLanguage.text("当前处于只读锁定模式，点击解锁编辑", en: "Document is locked read-only; click to unlock")
                }
                return true
                
            case #selector(toggleAppearanceMode):
                let isDark = (self.view.window?.effectiveAppearance ?? NSApp.effectiveAppearance).isDark
                (item as? StatableToolbarItem)?.state = isDark ? .on : .off
                (item as? NSToolbarItem)?.toolTip = isDark ? "深色模式（点击切换浅色）" : "浅色模式（点击切换深色）"
                
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
                
            case #selector(openSplitTextView),
                 #selector(splitEditorVertically),
                 #selector(splitEditorHorizontally):
                return false
                
            case #selector(saveDocument(_:)), #selector(saveDocumentAs(_:)):
                return true
                
            case #selector(closeSplitTextView):
                return self.editorViewControllers.count > 1
                
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
            if !self.isRestoringPersistedPaneTabs {
                document.markEditedByUser()
            }
            document.scheduleDatabaseSync()
            self.schedulePaneTabsSessionSave()
            
            guard self.focusedTextView?.hasMarkedText() != true else { return }
            
            document.counter.invalidateContent()
            if document.textStorage.length <= 100_000 {
                document.counter.refreshNow()
            }
            document.syntaxController.parseIfNeeded()
        }
    }
    
    
    /// Invoked when the selection did change.
    @objc private func textViewDidLiveChangeSelection(_ notification: Notification) {
        
        let textView = notification.object as? NSTextView
        let document = textView.flatMap { self.document(for: $0) } ?? self.document
        
        if document.textStorage.length <= 100_000 {
            document.counter.refreshNow()
        } else {
            document.counter.invalidateSelection()
        }
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
    
    
    /// Whether the focused pane shows line numbers.
    ///
    /// The setting belongs to a pane (see `EditorViewController.showsLineNumber`), so this is a
    /// view onto the focused one: `:set number`, the View menu item and the print settings all
    /// act on that pane and leave its siblings alone. A window keeps only a remembered value,
    /// for the moment before its first pane exists (state restoration).
    var showsLineNumber: Bool {
        
        get {
            self.focusedChild?.showsLineNumber
                ?? self.editorViewControllers.first?.showsLineNumber
                ?? self.rememberedShowsLineNumber
                ?? UserDefaults.standard[.showLineNumbers]
        }
        set {
            guard let pane = self.focusedChild ?? self.editorViewControllers.first else {
                self.rememberedShowsLineNumber = newValue
                return
            }
            
            pane.showsLineNumber = newValue
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
    
    /// Reset the syntax parse for the currently focused document.
    @IBAction func recolorAll(_ sender: Any?) {
        
        self.focusedDocument.syntaxController.parseAll()
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
        
        StudioPaletteManager.shared.applyAppearanceMode(mode)
    }
    
    
    /// Toggles directly between Light and Dark appearance from the toolbar button.
    @IBAction func toggleAppearanceMode(_ sender: Any?) {
        
        let isDark = (self.view.window?.effectiveAppearance ?? NSApp.effectiveAppearance).isDark
        StudioPaletteManager.shared.applyAppearanceMode(isDark ? .light : .dark)
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
    
    
    /// Opens the floating custom highlight color palette only when explicitly requested from the context menu.
    @IBAction func openHighlightColorPalette(_ sender: Any?) {
        
        guard let textView = self.focusedChild?.textView else { return }
        let range = textView.selectedRange()
        guard range.length > 0, let document = self.document(for: textView) else { return }
        
        NotesTextColorPaletteController.shared.present(
            for: textView,
            document: document,
            selectedRange: range
        )
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
        
        guard !tab.isPinned else {
            NSSound.beep()
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
    
    
    /// Aggregates weekly-report-relevant work across all open windows and documents.
    @IBAction func generateWeeklyReport(_ sender: Any?) {
        
        self.runAllWindowsWeeklyReportSummary()
    }
    
    
    /// Condenses the selected text into a weekly report bullet item and saves it to the weekly report accumulator.
    @IBAction func generateWeeklyReportItem(_ sender: Any?) {
        
        self.runAIAction(.weeklyReportItem)
    }
    
    
    /// Organizes and merges similar documents across all open windows, renames tabs cleanly, and creates a Map document.
    @IBAction func organizeAndMergeAllDocuments(_ sender: Any?) {
        
        WorkspaceOrganizer.runOrganizeAndMerge(from: self.view.window)
    }
    
    
    /// One-click aligns Markdown tables in the selection (or throughout the whole document if nothing is selected).
    @IBAction func alignMarkdownTable(_ sender: Any?) {
        
        guard let textView = self.focusedTextView else {
            NSSound.beep()
            return
        }
        
        let selectedRange = textView.selectedRange()
        let targetRange = selectedRange.length > 0 ? selectedRange : NSRange(location: 0, length: (textView.string as NSString).length)
        guard targetRange.length > 0 else {
            NSSound.beep()
            return
        }
        
        let original = (textView.string as NSString).substring(with: targetRange)
        let aligned = MarkdownTableFormatter.formatTables(in: original)
        guard aligned != original else { return }
        
        textView.insertText(aligned, replacementRange: targetRange)
        textView.window?.makeFirstResponder(textView)
    }
    
    
    /// Renders an interactive HTML chart from the selected Markdown table (or document table) and asks AI for insights.
    @IBAction func generateInteractiveChart(_ sender: Any?) {
        
        guard let textView = self.focusedTextView, let window = textView.window else {
            NSSound.beep()
            return
        }
        
        let sourceText = textView.selectedRange().length > 0 ? textView.selectedString : textView.string
        guard !sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            NSSound.beep()
            return
        }
        
        let panel = AIResultPanelController(action: .interactiveChart)
        panel.onReplace = { [weak self] result in self?.applyAIResult(result, replacingSelection: true) }
        panel.onInsert = { [weak self] result in self?.applyAIResult(result, replacingSelection: false) }
        self.aiResultPanel = panel
        
        panel.present(on: window)
        // Render an immediate interactive chart from the table data right away so the user doesn't wait
        let instantHTML = MarkdownTableFormatter.generateInstantChartHTML(from: sourceText)
        panel.presentChart(html: instantHTML)
        
        if AIService.shared.isConfigured {
            Task {
                do {
                    let result = try await AIService.shared.run(.interactiveChart, on: sourceText) { partial in
                        panel.presentPartial(result: partial)
                    }
                    panel.present(result: result)
                } catch {
                    // Keep the instant interactive chart usable and show the aligned table below
                    panel.present(result: MarkdownTableFormatter.formatTables(in: sourceText))
                }
            }
        } else {
            panel.present(result: MarkdownTableFormatter.formatTables(in: sourceText))
        }
    }
    
    
    /// Saves the currently focused pane's document (`⌘S`).
    @objc(saveDocument:) @IBAction func saveDocument(_ sender: Any?) {
        
        self.focusedDocument.performQuickSave(sender)
        self.editorViewControllers.forEach { $0.updateTabState() }
    }
    
    
    /// Opens Save As for the currently focused pane's document (`⌘⇧S`).
    @objc(saveDocumentAs:) @IBAction func saveDocumentAs(_ sender: Any?) {
        
        self.focusedDocument.saveAs(sender)
    }
    
    
    /// Runs the embedded Vision OCR model on a clipboard or chosen image, then connects to AI for smart structuring.
    @IBAction func runOCRAndAI(_ sender: Any?) {
        
        guard let textView = self.focusedTextView, let window = textView.window else {
            NSSound.beep()
            return
        }
        
        if let clipboardImage = NSImage(pasteboard: .general) {
            self.processOCR(image: clipboardImage, on: window)
            return
        }
        
        let openPanel = NSOpenPanel()
        openPanel.allowedContentTypes = [.image, .png, .jpeg, .tiff]
        openPanel.allowsMultipleSelection = false
        openPanel.message = String(localized: "ai.ocr.openPanel.message",
                                   defaultValue: "Choose an image to run local OCR + AI recognition",
                                   table: "AI")
        openPanel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = openPanel.url, let image = NSImage(contentsOf: url) else { return }
            Task { @MainActor in
                self?.processOCR(image: image, on: window)
            }
        }
    }
    
    
    /// Toggles read-only lock mode on the currently focused document tab/pane so presentations never suffer accidental edits.
    @IBAction func toggleEditable(_ sender: Any?) {
        
        self.focusedDocument.toggleEditable(sender)
        self.view.window?.toolbar?.validateVisibleItems()
    }
    
    
    /// Inserts an image into a Plain Text document as an inline `⟦🖼 ...⟧` card.
    @IBAction func insertPlainTextImage(_ sender: Any?) {
        
        guard let textView = self.focusedTextView, let window = textView.window, textView.isEditable else {
            NSSound.beep()
            return
        }
        
        let docURL = self.document(for: textView)?.fileURL
        if let clipboardImage = PlainTextInlineImageStore.shared.extractImage(from: .general),
           let stored = PlainTextInlineImageStore.shared.store(image: clipboardImage, for: docURL)
        {
            textView.insertInlineImageTokenCleanly(stored.token)
            return
        }
        
        let openPanel = NSOpenPanel()
        openPanel.allowedContentTypes = [.image, .png, .jpeg]
        openPanel.allowsMultipleSelection = false
        openPanel.beginSheetModal(for: window) { [weak textView] response in
            guard response == .OK, let url = openPanel.url else { return }
            Task { @MainActor in
                guard let textView, textView.isEditable,
                      let stored = PlainTextInlineImageStore.shared.storeImageFile(at: url, for: docURL)
                else { return }
                textView.insertInlineImageTokenCleanly(stored.token)
            }
        }
    }
    
    
    /// Executes local Vision OCR followed by AI polishing in the result sheet.
    func processOCR(image: NSImage, on window: NSWindow) {
        
        let panel = AIResultPanelController(action: .ocrPolish)
        panel.onReplace = { [weak self] result in self?.applyAIResult(result, replacingSelection: true) }
        panel.onInsert = { [weak self] result in self?.applyAIResult(result, replacingSelection: false) }
        self.aiResultPanel = panel
        panel.present(on: window)
        
        Task {
            do {
                let ocr = try await LocalVisionOCR.recognizeText(in: image)
                let rawText = ocr.text.trimmingCharacters(in: .whitespacesAndNewlines)
                
                if !rawText.isEmpty {
                    panel.presentPartial(result: rawText)
                }
                
                guard AIService.shared.isConfigured else {
                    panel.present(result: rawText.isEmpty ? "（未检测到文字）" : rawText)
                    return
                }
                
                let aiImages: [AIImage] = ocr.pngData.map { [AIImage(data: $0, mimeType: "image/png")] } ?? []
                let promptInput = rawText.isEmpty ? "请识别并整理图片中的文字与表格内容。" : "本地 OCR 初步识别结果如下，请校对并结构化整理：\n\n\(rawText)"
                let polished = try await AIService.shared.run(.ocrPolish, on: promptInput, images: aiImages) { partial in
                    panel.presentPartial(result: partial)
                }
                panel.present(result: polished)
            } catch {
                panel.present(error: error)
            }
        }
    }
    
    
    /// Runs one AI action on the selection and shows the answer in a sheet.
    ///
    /// - Parameters:
    ///   - action: The action to run.
    ///   - allowFullDocumentFallback: Whether to use the whole document when the selection is empty.
    private func runAIAction(_ action: AIAction, allowFullDocumentFallback: Bool = false) {
        
        guard let textView = self.focusedTextView, let window = textView.window else {
            NSSound.beep()
            return
        }
        
        let selected = textView.selectedString
        let text = (!selected.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !allowFullDocumentFallback)
            ? selected
            : textView.string
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
        
        Task { [weak panel, weak self] in
            do {
                let result = try await AIService.shared.run(action, on: text) { partial in
                    panel?.presentPartial(result: partial)
                }
                panel?.present(result: result)
            } catch {
                panel?.present(error: error)
            }
        }
    }
    
    
    /// Aggregates weekly-report-relevant material across every open window, pane, and tab (plus recent DB notes if needed).
    private func runAllWindowsWeeklyReportSummary() {
        
        guard let window = self.view.window else {
            NSSound.beep()
            return
        }
        
        guard AIService.shared.isConfigured else {
            self.presentAIConfigurationAlert(on: window)
            return
        }
        
        var seenDocIDs = Set<ObjectIdentifier>()
        var sections: [String] = []
        var totalChars = 0
        let maxTotalChars = 55_000
        
        if let focusedSelection = self.focusedTextView?.selectedString.trimmingCharacters(in: .whitespacesAndNewlines),
           !focusedSelection.isEmpty
        {
            sections.append("【当前光标重点选中内容】\n\(String(focusedSelection.prefix(8_000)))")
            totalChars += min(focusedSelection.count, 8_000)
        }
        
        let windowControllers = NSApp.orderedWindows
            .compactMap { $0.windowController as? DocumentWindowController }
        
        for (winIndex, wc) in windowControllers.enumerated() {
            guard let docVC = wc.documentViewController else { continue }
            for (paneIndex, pane) in docVC.editorViewControllers.enumerated() {
                for tab in pane.tabs {
                    let doc = tab.document
                    guard !doc.databaseDocumentID.hasPrefix("weekly:") else { continue }
                    guard seenDocIDs.insert(ObjectIdentifier(doc)).inserted else { continue }
                    let trimmed = doc.textStorage.string.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { continue }
                    
                    let remaining = maxTotalChars - totalChars
                    guard remaining > 200 else { break }
                    let clipped = String(trimmed.prefix(min(12_000, remaining)))
                    totalChars += clipped.count
                    
                    let pathNote = doc.fileURL?.path(percentEncoded: false) ?? "未落盘笔记"
                    sections.append("""
                    【窗口 \(winIndex + 1) · 分栏 \(paneIndex + 1) · 文档：\(doc.displayName)（\(doc.syntaxName) | \(pathNote)）】
                    \(clipped)
                    """)
                }
            }
        }
        
        for case let doc as Document in NSDocumentController.shared.documents {
            guard seenDocIDs.insert(ObjectIdentifier(doc)).inserted else { continue }
            let trimmed = doc.textStorage.string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let remaining = maxTotalChars - totalChars
            guard remaining > 200 else { break }
            let clipped = String(trimmed.prefix(min(10_000, remaining)))
            totalChars += clipped.count
            sections.append("【已打开文档：\(doc.displayName)（\(doc.syntaxName)）】\n\(clipped)")
        }
        
        let savedFragments = CotLocalDatabase.shared.string(forKey: CotLocalDatabase.ConfigKey.weeklyReportFragments)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        if sections.isEmpty, savedFragments.isEmpty {
            for record in CotLocalDatabase.shared.documents.prefix(6) {
                let trimmed = record.content.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }
                let clipped = String(trimmed.prefix(6_000))
                sections.append("【历史文档记录：\(record.title)】\n\(clipped)")
            }
        }
        
        let rawInput: String
        if !sections.isEmpty {
            rawInput = "以下是当前所有窗口与打开文档的内容，请筛选出与本周工作/周报相关的要点并汇总成一份完整的周报：\n\n"
                + sections.joined(separator: "\n\n---\n\n")
        } else if !savedFragments.isEmpty {
            rawInput = "【本周积累的周报片段】\n\(savedFragments)"
        } else {
            NSSound.beep()
            return
        }
        
        let panel = AIResultPanelController(action: .weeklyReport)
        panel.onReplace = { [weak self] result in self?.applyAIResult(result, replacingSelection: true) }
        panel.onInsert = { [weak self] result in self?.applyAIResult(result, replacingSelection: false) }
        self.aiResultPanel = panel
        panel.present(on: window)
        
        Task { [weak panel] in
            do {
                let result = try await AIService.shared.run(.weeklyReport, on: rawInput) { partial in
                    panel?.presentPartial(result: partial)
                }
                panel?.present(result: result)
            } catch {
                panel?.present(error: error)
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
        alert.messageText = String(localized: "chrome.aiAlert.title",
                                   defaultValue: "AI Is Not Configured", table: "Chrome")
        alert.informativeText = String(localized: "chrome.aiAlert.message",
                                       defaultValue: "Set the endpoint, model, and API key in Settings before using Translate, Summarize, or Explain.",
                                       table: "Chrome")
        alert.addButton(withTitle: String(localized: "chrome.aiAlert.openSettings",
                                          defaultValue: "Open AI Settings", table: "Chrome"))
        alert.addButton(withTitle: String(localized: "chrome.alert.cancel",
                                          defaultValue: "Cancel", table: "Chrome"))
        
        alert.beginSheetModal(for: window) { response in
            guard response == .alertFirstButtonReturn else { return }
            
            (NSApp.delegate as? AppDelegate)?.showAIPreferences(nil)
        }
    }
    
    
    /// Toggles the visibility of the line number views of the focused pane.
    @IBAction func toggleLineNumber(_ sender: Any?) {
        
        self.showsLineNumber.toggle()
    }
    
    
    /// Shows or hides the line numbers of the pane that holds a given text view.
    ///
    /// Used by the vim command line: `:set number` changes the pane it was typed in, not the
    /// window and not the app.
    ///
    /// - Parameters:
    ///   - shows: Whether line numbers should be visible.
    ///   - textView: A text view of the pane to change.
    func setShowsLineNumber(_ shows: Bool, inPaneContaining textView: NSTextView) {
        
        self.editorViewControllers
            .first { $0.contains(textView) }?
            .showsLineNumber = shows
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
        
        // Splitting is reserved strictly for explicit ⌃A % / ⌃A " commands from the active editor.
        guard sender is EditorTextView else { return }
        guard self.zoomedPane == nil else {
            NSSound.beep()
            return
        }
        guard self.editorViewControllers.count < Self.maximumNumberOfSplitEditors else { return NSSound.beep() }
        
        guard
            let currentViewController = self.baseEditorViewController(for: sender),
            let window = self.view.window
        else { return assertionFailure() }
        
        let document: Document
        do {
            document = try self.makePaneDocument()
        } catch {
            NSApp.presentError(error)
            return
        }
        
        let newEditorViewController = self.makeEditorViewController(document: document, copying: currentViewController)
        self.insertPane(newEditorViewController, beside: currentViewController, isVertical: isVertical)
        AnalyticsManager.shared.recordFileCreated()
        
        self.splitState.isVertical = isVertical
        self.updateSplitState()
        self.view.layoutSubtreeIfNeeded()
        self.rebalancePanes(in: self)
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
    ///   - sourceTextView: The text view whose editor preferences are copied to the new one.
    ///   - index: Optional target index in the pane's tab bar.
    /// - Returns: The created tab.
    @discardableResult
    private func addTab(_ document: Document, to pane: EditorViewController, copying sourceTextView: EditorTextView?, at index: Int? = nil) -> PaneTab {
        
        document.isTransient = false
        document.syntaxController.setupParser()
        
        self.observeTextStorage(of: document)
        if !self.isRestoringPersistedPaneTabs {
            document.syncToLocalDatabase()
        }
        document.counter.refreshNow()
        
        let showsLineNumbers = pane.showsLineNumber
        let tab = pane.addTab(document: document, at: index)
        tab.isClosable = true
        
        if let textView = pane.textView {
            self.configureTextView(textView, copying: sourceTextView)
            // the new tab joins the pane as it is, rather than with the focused pane's setting
            pane.showsLineNumber = showsLineNumbers
            
            // observe cursor
            NotificationCenter.default.addObserver(self, selector: #selector(textViewDidLiveChangeSelection),
                                                   name: EditorTextView.DidLiveChangeSelectionMessage.name,
                                                   object: textView)
        }
        
        self.focusedChild = pane
        self.updateSplitState()
        self.view.window?.makeFirstResponderDiscardingMarkedText(pane.textView)
        
        NotificationCenter.default.post(name: Self.focusedDocumentDidChangeNotification, object: self)
        return tab
    }
    
    
    /// Promotes another open document in this window to become the window's primary `NSDocument`
    /// so the previous primary document can be closed or moved to another window freely.
    func promotePrimaryDocument(to replacement: Document) {
        
        guard replacement !== self.document else { return }
        let oldPrimary = self.document
        self.document = replacement
        self.observeTextStorage(of: replacement)
        
        if let windowController = self.view.window?.windowController as? DocumentWindowController {
            oldPrimary.removeWindowController(windowController)
            replacement.addWindowController(windowController)
            windowController.fileDocument = replacement
            windowController.synchronizeWindowTitleWithDocumentName()
        }
        replacement.syncToLocalDatabase()
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
        AnalyticsManager.shared.recordFileCreated()
        
        return true
    }
    
    
    /// Closes one tab of a pane, closing the pane when its last tab goes away (or the window when it is the very last tab).
    ///
    /// - Parameters:
    ///   - tab: The tab to close.
    ///   - pane: The pane that hosts the tab.
    private func closeTab(_ tab: PaneTab, in pane: EditorViewController) {
        
        guard !tab.isPinned else { return NSSound.beep() }
        
        // When this is the very last tab in the entire window, closing the tab closes the window.
        if self.editorViewControllers.count == 1, pane.tabs.count == 1 {
            self.view.window?.performClose(nil)
            return
        }
        
        // Ask about unsaved changes *before* taking the tab away: otherwise a cancelled
        // save prompt would leave an invisible document behind that can never be saved.
        if pane === self.zoomedPane, pane.tabs.count == 1 {
            self.unzoomPane()
        }
        
        self.reviewDocuments([tab.document]) { [weak self, weak pane] canClose in
            guard canClose, let self, let pane else { return }
            
            if tab.document === self.document {
                let replacement = pane.tabs.first(where: { $0 !== tab })?.document
                    ?? self.editorViewControllers.first(where: { $0 !== pane })?.selectedTab.document
                if let replacement {
                    self.promotePrimaryDocument(to: replacement)
                }
            }
            
            self.stopObservingTextStorage(of: tab.document)
            
            if let textView = pane.textView(for: tab) {
                NotificationCenter.default.removeObserver(self, name: EditorTextView.DidLiveChangeSelectionMessage.name, object: textView)
                textView.undoManager?.removeAllActions(withTarget: textView)
            }
            
            let wasLastTab = (pane.tabs.count == 1)
            pane.removeTab(tab)
            tab.document.close()
            
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
        
        guard !pane.tabs.contains(where: \.isPinned) else {
            NSSound.beep()
            let alert = NSAlert()
            alert.messageText = String(localized: "chrome.pinnedPaneAlert.title",
                                       defaultValue: "Pinned Tabs", table: "Chrome")
            alert.informativeText = String(localized: "chrome.pinnedPaneAlert.message",
                                           defaultValue: "This pane contains pinned tabs. Unpin them before closing the pane.",
                                           table: "Chrome")
            alert.alertStyle = .informational
            alert.addButton(withTitle: String(localized: "chrome.alert.ok",
                                              defaultValue: "OK", table: "Chrome"))
            alert.runModal()
            return
        }
        
        let documents = pane.tabs.map(\.document)
        
        self.reviewDocuments(documents) { [weak self, weak pane] canClose in
            guard canClose, let self, let pane else { return }
            
            if pane.tabs.contains(where: { $0.document === self.document }),
               let replacementPane = self.editorViewControllers.first(where: { $0 !== pane })
            {
                self.promotePrimaryDocument(to: replacementPane.selectedTab.document)
            }
            
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
    ///   - isVertical: `true` to split horizontally side-by-side, `false` to stack vertically.
    ///   - insertBefore: `true` to place before `currentViewController` (left/top), `false` to place after (right/bottom).
    private func insertPane(
        _ newViewController: EditorViewController,
        beside currentViewController: EditorViewController,
        isVertical: Bool,
        insertBefore: Bool = false
    ) {
        
        let parentGroup = self.splitGroup(containing: currentViewController) ?? self
        let item = self.makeSplitViewItem(for: newViewController)
        
        guard let index = parentGroup.splitViewItems.firstIndex(where: { $0.viewController === currentViewController }) else {
            return assertionFailure()
        }
        
        let insertionIndex = insertBefore ? index : index + 1
        
        if parentGroup.splitViewItems.count == 1 {
            // a lone pane simply adopts the requested direction
            parentGroup.splitView.isVertical = isVertical
            parentGroup.insertSplitViewItem(item, at: insertionIndex)
        } else if parentGroup.splitView.isVertical == isVertical {
            // same direction: put the new pane beside the current one
            parentGroup.insertSplitViewItem(item, at: insertionIndex)
        } else {
            // other direction: wrap the current pane and the new one in a nested container
            let group = SplitGroupViewController(isVertical: isVertical)
            self.removeItem(for: currentViewController, from: parentGroup)
            parentGroup.insertSplitViewItem(self.makeSplitViewItem(for: group), at: index)
            if insertBefore {
                group.addSplitViewItem(item)
                group.addSplitViewItem(self.makeSplitViewItem(for: currentViewController))
            } else {
                group.addSplitViewItem(self.makeSplitViewItem(for: currentViewController))
                group.addSplitViewItem(item)
            }
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
        let splitView = group.splitView
        
        if items.count > 1 {
            let isVertical = splitView.isVertical
            let thickness = isVertical ? splitView.bounds.width : splitView.bounds.height
            let dividerThickness = splitView.dividerThickness
            
            var leadingInset: CGFloat = 0
            var trailingInset: CGFloat = 0
            if !isVertical, group === self {
                let insets = group.view.safeAreaInsets
                leadingInset = max(0, insets.top)
                trailingInset = max(0, insets.bottom)
            }
            
            let totalDivider = dividerThickness * CGFloat(items.count - 1)
            let available = thickness - totalDivider - leadingInset - trailingInset
            
            if available > CGFloat(items.count) * 40 {
                let equalWeights = Array(repeating: CGFloat(1), count: items.count)
                self.applySplitPaneSizes(
                    weights: equalWeights,
                    leadingInset: leadingInset,
                    trailingInset: trailingInset,
                    in: group
                )
            }
        } else {
            self.clearProportionConstraints(for: splitView)
        }
        
        // let the containers take their new size before touching their dividers
        group.view.layoutSubtreeIfNeeded()
        
        for item in items {
            if let nested = item.viewController as? SplitGroupViewController {
                self.rebalancePanes(in: nested)
            }
        }
    }
    
    
    private func clearProportionConstraints(for splitView: NSSplitView) {
        
        let key = ObjectIdentifier(splitView)
        guard let existing = self.proportionConstraintsBySplitView.removeValue(forKey: key), !existing.isEmpty else { return }
        NSLayoutConstraint.deactivate(existing)
    }
    
    
    /// Enforces exact proportional thicknesses across every pane in `group` so macOS 26's
    /// `NSSplitView.FallbackSize` cannot override divider positions while keeping window resize smooth
    /// and releasing automatically when the user drags a divider manually.
    private func applySplitPaneSizes(
        weights: [CGFloat],
        leadingInset: CGFloat = 0,
        trailingInset: CGFloat = 0,
        in group: NSSplitViewController
    ) {
        let items = group.splitViewItems
        guard items.count > 1, weights.count == items.count else { return }
        
        let splitView = group.splitView
        let isVertical = splitView.isVertical
        let thickness = isVertical ? splitView.bounds.width : splitView.bounds.height
        let dividerThickness = splitView.dividerThickness
        let available = thickness - dividerThickness * CGFloat(items.count - 1) - leadingInset - trailingInset
        guard available > CGFloat(items.count) * 20 else { return }
        
        let weightSum = max(0.001, weights.reduce(0, +))
        let baseWeight = max(0.001, weights[0])
        
        func paneInset(at index: Int) -> CGFloat {
            if index == 0 { return leadingInset }
            if index == items.count - 1 { return trailingInset }
            return 0
        }
        
        let targetSizes: [CGFloat] = (0..<items.count).map { index in
            available * (weights[index] / weightSum) + paneInset(at: index)
        }
        
        self.clearProportionConstraints(for: splitView)
        
        // Priority 251 sits right above NSSplitView.FallbackSize (249/250) so programmatic splits
        // divide cleanly, while remaining below required window constraints and detaching on user drag.
        let basePaneView = items[0].viewController.view
        let baseAnchor = isVertical ? basePaneView.widthAnchor : basePaneView.heightAnchor
        let baseInset = paneInset(at: 0)
        var newConstraints: [NSLayoutConstraint] = []
        
        for index in 1..<items.count {
            let paneView = items[index].viewController.view
            let anchor = isVertical ? paneView.widthAnchor : paneView.heightAnchor
            let ratio = weights[index] / baseWeight
            let insetOffset = paneInset(at: index) - ratio * baseInset
            let constraint = anchor.constraint(equalTo: baseAnchor, multiplier: ratio, constant: insetOffset)
            constraint.priority = NSLayoutConstraint.Priority(251)
            newConstraints.append(constraint)
        }
        
        self.proportionConstraintsBySplitView[ObjectIdentifier(splitView)] = newConstraints
        self.isApplyingSplitPaneSizes = true
        defer { self.isApplyingSplitPaneSizes = false }
        
        NSLayoutConstraint.activate(newConstraints)
        splitView.layoutSubtreeIfNeeded()
        
        var cumulative: CGFloat = 0
        for index in 0..<(items.count - 1) {
            cumulative += targetSizes[index]
            let position = cumulative + dividerThickness * CGFloat(index)
            splitView.setPosition(position, ofDividerAt: index)
        }
        splitView.layoutSubtreeIfNeeded()
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
    var editorViewControllers: [EditorViewController] {
        
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
        splitViewItem.minimumThickness = 80
        // Keep holdingPriority below 250 (PreferredSize's priority on macOS 26) so `setPosition(_:ofDividerAt:)`
        // always takes precedence over AppKit's stale `FallbackSize` constraint.
        splitViewItem.holdingPriority = NSLayoutConstraint.Priority(249)
        
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
            
            self.clearProportionConstraints(for: group.splitView)
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
                tab.isClosable = true
            }
            
            editorViewController.setCanClosePane(isSplit)
            editorViewController.updateTabState()
            editorViewController.updateNavigationBarVisibility(animated: true)
        }
        
        NotificationCenter.default.post(name: Self.splitLayoutDidChangeNotification, object: self)
        self.savePaneTabsSessionToDatabase()
    }
    
    
    // MARK: Cross-Pane & Cross-Window Tab Drag-and-Drop
    
    /// Locates the window, pane, and tab matching the given `PaneTab` UUID across all open windows.
    private static func locateTab(withID tabID: UUID) -> (windowVC: DocumentViewController, pane: EditorViewController, tab: PaneTab)? {
        
        let windowControllers = NSApp.windows.compactMap { $0.windowController as? DocumentWindowController }
        for windowController in windowControllers {
            guard let docVC = windowController.documentViewController else { continue }
            for pane in docVC.editorViewControllers {
                if let tab = pane.tabs.first(where: { $0.id == tabID }) {
                    return (docVC, pane, tab)
                }
            }
        }
        return nil
    }
    
    
    /// Handles a tab dropped onto an `EditorTextView` inside this window.
    func handleDroppedTab(id tabID: UUID, ontoTextView textView: EditorTextView) -> Bool {
        
        guard let targetPane = self.editorViewControllers.first(where: { $0.contains(textView) }) else {
            return false
        }
        return self.handleDroppedTab(id: tabID, onto: targetPane, before: nil)
    }
    
    
    /// Starts inline tab renaming for the pane tab hosting `document`.
    @discardableResult
    func beginInlineRename(for document: Document) -> Bool {
        
        for pane in self.editorViewControllers {
            if pane.beginInlineRename(for: document) {
                self.focusedChild = pane
                return true
            }
        }
        return false
    }
    
    
    /// Renames either an untitled document or a saved file behind `tab` and keeps tabs/DB/window title synchronized.
    func renameTab(_ tab: PaneTab, to newName: String, in pane: EditorViewController) {
        
        do {
            try WorkspaceOrganizer.renameDocument(tab.document, to: newName)
            pane.updateTabState()
            if tab.document === self.document {
                self.view.window?.windowController?.synchronizeWindowTitleWithDocumentName()
            }
            self.savePaneTabsSessionToDatabase()
        } catch {
            CotLogger.shared.error(category: .document, "Pane tab rename failed", error: error, context: ["targetName": newName])
            if let window = self.view.window {
                self.presentError(error, modalFor: window, delegate: nil, didPresent: nil, contextInfo: nil)
            } else {
                NSApp.presentError(error)
            }
        }
    }
    
    
    /// Safely closes a redundant untitled tab whose content has already been merged into another document.
    @discardableResult
    func closeMergedTabSafely(_ tab: PaneTab, in pane: EditorViewController) -> Bool {
        
        guard tab.document.fileURL == nil else { return false }
        let totalTabs = self.editorViewControllers.reduce(0) { $0 + $1.tabs.count }
        guard totalTabs > 1 else { return false }
        
        let closedDocument = tab.document
        closedDocument.updateChangeCount(.changeCleared)
        
        if closedDocument === self.document {
            let replacement = pane.tabs.first(where: { $0 !== tab })?.document
                ?? self.editorViewControllers.first(where: { $0 !== pane })?.selectedTab.document
            if let replacement {
                self.promotePrimaryDocument(to: replacement)
            }
        }
        
        if let oldTextView = pane.textView(for: tab) {
            NotificationCenter.default.removeObserver(self, name: EditorTextView.DidLiveChangeSelectionMessage.name, object: oldTextView)
        }
        NotificationCenter.default.removeObserver(self, name: NSTextStorage.didProcessEditingNotification, object: closedDocument.textStorage)
        
        pane.removeTab(tab)
        if pane.tabs.isEmpty, self.editorViewControllers.count > 1 {
            self.removePane(pane)
        }
        self.updateSplitState()
        closedDocument.close()
        return true
    }
    
    
    /// Moves a tab onto `targetPane` using a pre-removal insertion index (for tab strip drag-and-drop).
    func handleDroppedTab(id tabID: UUID, onto targetPane: EditorViewController, atIndex targetIndex: Int?) -> Bool {
        
        let targetTab = targetIndex.flatMap { targetPane.tabs[safe: $0] }
        return self.handleDroppedTab(id: tabID, onto: targetPane, before: targetTab)
    }
    
    
    /// Moves a dragged tab into `targetPane` without creating a new split pane.
    func handleDroppedTab(id tabID: UUID, onto targetPane: EditorViewController, zone: PaneDropZone) -> Bool {
        
        self.handleDroppedTab(id: tabID, onto: targetPane, before: nil)
    }
    
    
    /// Moves a tab (from any pane in this window or another window) into `targetPane` before `targetTab` (or at the end if `nil`).
    func handleDroppedTab(id tabID: UUID, onto targetPane: EditorViewController, before targetTab: PaneTab?) -> Bool {
        
        guard let source = Self.locateTab(withID: tabID) else { return false }
        let sourceWindowVC = source.windowVC
        let sourcePane = source.pane
        let sourceTab = source.tab
        
        // Same pane: reorder in place
        if sourcePane === targetPane {
            if let targetTab, sourceTab !== targetTab {
                targetPane.reorderTab(sourceTab, onto: targetTab)
                self.savePaneTabsSessionToDatabase()
                return true
            } else if targetTab == nil, let lastTab = targetPane.tabs.last, sourceTab !== lastTab {
                targetPane.reorderTab(sourceTab, onto: lastTab)
                self.savePaneTabsSessionToDatabase()
                return true
            }
            return false
        }
        
        let movedDocument = sourceTab.document
        let wasPinned = sourceTab.isPinned
        let targetIndex = targetTab.flatMap { target in
            targetPane.tabs.firstIndex(where: { $0 === target })
        }
        
        // Same window, different pane
        if sourceWindowVC === self {
            let sourcePaneRectInWindow = sourcePane.tabFrameInWindow(for: sourceTab)
                ?? sourcePane.view.convert(sourcePane.view.bounds, to: nil)
            let sourcePaneBoundsInWindow = sourcePane.view.convert(sourcePane.view.bounds, to: nil)
            let sourcePaneCenterInWindow = CGPoint(x: sourcePaneBoundsInWindow.midX, y: sourcePaneBoundsInWindow.midY)
            let dropPointInWindow = self.view.window?.convertPoint(fromScreen: NSEvent.mouseLocation)
            
            if let oldTextView = sourcePane.textView(for: sourceTab) {
                NotificationCenter.default.removeObserver(self, name: EditorTextView.DidLiveChangeSelectionMessage.name, object: oldTextView)
            }
            let wasLastInSourcePane = (sourcePane.tabs.count == 1)
            sourcePane.removeTab(sourceTab)
            
            let newTab = self.addTab(movedDocument, to: targetPane, copying: targetPane.textView, at: targetIndex)
            if wasPinned {
                newTab.isPinned = true
                targetPane.updateTabState()
            }
            
            if wasLastInSourcePane, self.editorViewControllers.count > 1 {
                if self.zoomedPane === sourcePane {
                    self.unzoomPane()
                }
                self.removePane(sourcePane)
            }
            self.updateSplitState()
            self.savePaneTabsSessionToDatabase()
            
            self.view.layoutSubtreeIfNeeded()
            targetPane.view.layoutSubtreeIfNeeded()
            if let window = self.view.window {
                let targetPaneFrameInWindow = targetPane.view.convert(targetPane.view.bounds, to: nil)
                let fallbackTargetRect = NSRect(
                    x: targetPaneFrameInWindow.minX + 12,
                    y: targetPaneFrameInWindow.maxY - 26,
                    width: 110,
                    height: 22
                )
                let targetTabRectInWindow = targetPane.tabFrameInWindow(for: newTab) ?? fallbackTargetRect
                let resolvedDropPoint = dropPointInWindow ?? CGPoint(x: targetTabRectInWindow.midX, y: targetTabRectInWindow.midY)
                PaneTransferTrailEffect.play(
                    in: window,
                    sourceTabRectInWindow: sourcePaneRectInWindow,
                    dropPointInWindow: resolvedDropPoint,
                    targetTabRectInWindow: targetTabRectInWindow
                )
                targetPane.animateTabDropArrival(for: newTab, crossPane: true)
                let targetPaneCenterInWindow = CGPoint(x: targetPaneFrameInWindow.midX, y: targetPaneFrameInWindow.midY)
                let delta = CGPoint(
                    x: sourcePaneCenterInWindow.x - targetPaneCenterInWindow.x,
                    y: sourcePaneCenterInWindow.y - targetPaneCenterInWindow.y
                )
                targetPane.animateCrossPaneArrival(fromDelta: delta)
            }
            return true
        }
        
        // Cross-window tab move
        let dropPointInWindow = self.view.window?.convertPoint(fromScreen: NSEvent.mouseLocation)
        let sourceTotalTabs = sourceWindowVC.editorViewControllers.reduce(0) { $0 + $1.tabs.count }
        if movedDocument === sourceWindowVC.document {
            if sourceTotalTabs > 1 {
                let replacement = sourcePane.tabs.first(where: { $0 !== sourceTab })?.document
                    ?? sourceWindowVC.editorViewControllers.first(where: { $0 !== sourcePane })?.selectedTab.document
                if let replacement {
                    sourceWindowVC.promotePrimaryDocument(to: replacement)
                }
            } else if let sourceWC = sourceWindowVC.view.window?.windowController as? DocumentWindowController {
                movedDocument.removeWindowController(sourceWC)
            }
        }
        
        if let oldTextView = sourcePane.textView(for: sourceTab) {
            NotificationCenter.default.removeObserver(sourceWindowVC, name: EditorTextView.DidLiveChangeSelectionMessage.name, object: oldTextView)
        }
        NotificationCenter.default.removeObserver(sourceWindowVC, name: NSTextStorage.didProcessEditingNotification, object: movedDocument.textStorage)
        
        let wasLastInSourcePane = (sourcePane.tabs.count == 1)
        sourcePane.removeTab(sourceTab)
        
        if sourceTotalTabs <= 1 {
            sourceWindowVC.view.window?.close()
        } else {
            if wasLastInSourcePane, sourceWindowVC.editorViewControllers.count > 1 {
                if sourceWindowVC.zoomedPane === sourcePane {
                    sourceWindowVC.unzoomPane()
                }
                sourceWindowVC.removePane(sourcePane)
            }
            sourceWindowVC.updateSplitState()
            sourceWindowVC.savePaneTabsSessionToDatabase()
        }
        
        let newTab = self.addTab(movedDocument, to: targetPane, copying: targetPane.textView, at: targetIndex)
        if wasPinned {
            newTab.isPinned = true
            targetPane.updateTabState()
        }
        self.view.window?.makeKeyAndOrderFront(nil)
        self.view.window?.makeFirstResponderDiscardingMarkedText(targetPane.textView)
        self.updateSplitState()
        self.savePaneTabsSessionToDatabase()
        
        self.view.layoutSubtreeIfNeeded()
        targetPane.view.layoutSubtreeIfNeeded()
        if let window = self.view.window {
            let targetPaneFrameInWindow = targetPane.view.convert(targetPane.view.bounds, to: nil)
            let fallbackTargetRect = NSRect(
                x: targetPaneFrameInWindow.minX + 12,
                y: targetPaneFrameInWindow.maxY - 26,
                width: 110,
                height: 22
            )
            let targetTabRectInWindow = targetPane.tabFrameInWindow(for: newTab) ?? fallbackTargetRect
            let resolvedDropPoint = dropPointInWindow ?? CGPoint(x: targetTabRectInWindow.midX, y: targetTabRectInWindow.midY)
            PaneTransferTrailEffect.play(
                in: window,
                sourceTabRectInWindow: nil,
                dropPointInWindow: resolvedDropPoint,
                targetTabRectInWindow: targetTabRectInWindow
            )
            targetPane.animateTabDropArrival(for: newTab, crossPane: true)
            targetPane.animateCrossPaneArrival(fromDelta: .zero)
        }
        return true
    }
    
    
    /// Detaches the given tab from its pane and opens it in a brand-new window near `screenPoint` when provided.
    private func detachTabToNewWindow(_ tab: PaneTab, from sourcePane: EditorViewController, atScreenPoint screenPoint: NSPoint?) {
        
        let totalTabs = self.editorViewControllers.reduce(0) { $0 + $1.tabs.count }
        guard totalTabs > 1 else {
            NSSound.beep()
            return
        }
        
        let movedDocument = tab.document
        if movedDocument === self.document {
            let replacement = sourcePane.tabs.first(where: { $0 !== tab })?.document
                ?? self.editorViewControllers.first(where: { $0 !== sourcePane })?.selectedTab.document
            if let replacement {
                self.promotePrimaryDocument(to: replacement)
            }
        }
        
        if let oldTextView = sourcePane.textView(for: tab) {
            NotificationCenter.default.removeObserver(self, name: EditorTextView.DidLiveChangeSelectionMessage.name, object: oldTextView)
        }
        NotificationCenter.default.removeObserver(self, name: NSTextStorage.didProcessEditingNotification, object: movedDocument.textStorage)
        
        let wasLastInSourcePane = (sourcePane.tabs.count == 1)
        sourcePane.removeTab(tab)
        if wasLastInSourcePane, self.editorViewControllers.count > 1 {
            self.removePane(sourcePane)
        }
        
        movedDocument.makeWindowControllers()
        movedDocument.showWindows()
        if let newWindow = movedDocument.windowControllers.first?.window,
           let currentWindow = self.view.window
        {
            var frame = currentWindow.frame
            if let screenPoint {
                frame.origin.x = screenPoint.x - frame.width * 0.35
                frame.origin.y = screenPoint.y - frame.height + 36
                if let visible = (NSScreen.screens.first { $0.frame.contains(screenPoint) } ?? currentWindow.screen ?? NSScreen.main)?.visibleFrame {
                    frame.origin.x = min(max(frame.origin.x, visible.minX), max(visible.minX, visible.maxX - frame.width))
                    frame.origin.y = min(max(frame.origin.y, visible.minY), max(visible.minY, visible.maxY - frame.height))
                }
            } else {
                frame.origin.x += 28
                frame.origin.y -= 28
            }
            newWindow.setFrame(frame, display: true)
            newWindow.makeKeyAndOrderFront(nil)
        }
        
        self.updateSplitState()
    }
    
    
    // MARK: Workspace & Split Layout Persistence
    
    /// Captures the recursive split/pane layout of `group`.
    private func captureLayoutNode(from group: NSSplitViewController, paneCounter: inout Int) -> PersistedLayoutNode {
        
        var children: [PersistedLayoutNode] = []
        var rawSizes: [Double] = []
        
        for item in group.splitViewItems {
            let viewFrame = item.viewController.view.frame
            let dimension = Double(group.splitView.isVertical ? max(1, viewFrame.width) : max(1, viewFrame.height))
            rawSizes.append(dimension)
            
            if let editor = item.viewController as? EditorViewController {
                let currentPaneIndex = paneCounter
                paneCounter += 1
                
                let tabItems: [PersistedPaneTabItem] = editor.tabs.map { tab in
                    let doc = tab.document
                    let highlightsData = try? JSONEncoder().encode(doc.textHighlights)
                    let highlightsJSON = highlightsData.flatMap { String(data: $0, encoding: .utf8) }
                    return PersistedPaneTabItem(
                        title: doc.displayName,
                        filePath: doc.fileURL?.path(percentEncoded: false),
                        syntax: doc.syntaxName,
                        content: doc.textStorage.string,
                        isPinned: tab.isPinned,
                        paneIndex: currentPaneIndex,
                        highlightsJSON: highlightsJSON,
                        databaseID: doc.databaseDocumentID
                    )
                }
                let selectedIdx = editor.tabs.firstIndex(where: { $0 === editor.selectedTab }) ?? 0
                children.append(.pane(
                    tabs: tabItems,
                    selectedTabIndex: selectedIdx,
                    showsLineNumber: editor.showsLineNumber
                ))
            } else if let nested = item.viewController as? NSSplitViewController {
                children.append(self.captureLayoutNode(from: nested, paneCounter: &paneCounter))
            }
        }
        
        let total = max(1, rawSizes.reduce(0, +))
        let weights = rawSizes.map { $0 / total }
        return .split(isVertical: group.splitView.isVertical, children: children, weights: weights)
    }
    
    
    /// Debounces session snapshots during continuous typing so SQLite JSON encoding never stalls Vim keystrokes.
    private func schedulePaneTabsSessionSave() {
        
        self.sessionSaveTask?.cancel()
        self.sessionSaveTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            guard let self, !Task.isCancelled else { return }
            self.savePaneTabsSessionToDatabase()
        }
    }
    
    
    /// Snapshots the entire split layout tree and all open tabs across document windows into `CotLocalDatabase`.
    func savePaneTabsSessionToDatabase() {
        
        self.sessionSaveTask?.cancel()
        self.sessionSaveTask = nil
        
        guard
            !self.isRestoringPersistedPaneTabs,
            Self.didRestoreAppPaneTabsThisLaunch,
            self.view.window != nil
        else { return }
        
        let docWindowVCs: [DocumentViewController] = NSApp.orderedWindows
            .compactMap { ($0.windowController as? DocumentWindowController)?.documentViewController }
        guard !docWindowVCs.isEmpty else { return }
        
        var windowLayouts: [PersistedWindowLayout] = []
        var flatItems: [PersistedPaneTabItem] = []
        
        for winVC in docWindowVCs {
            var paneCounter = 0
            let rootNode = winVC.captureLayoutNode(from: winVC, paneCounter: &paneCounter)
            let focusedIndex = winVC.focusedChild.flatMap { winVC.editorViewControllers.firstIndex(of: $0) } ?? 0
            let frameString = winVC.view.window.map { NSStringFromRect($0.frame) }
            windowLayouts.append(PersistedWindowLayout(
                root: rootNode,
                focusedPaneIndex: focusedIndex,
                windowFrame: frameString
            ))
            
            for (paneIdx, pane) in winVC.editorViewControllers.enumerated() {
                for tab in pane.tabs {
                    let doc = tab.document
                    let content = doc.textStorage.string
                    guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || doc.fileURL != nil else { continue }
                    let highlightsData = try? JSONEncoder().encode(doc.textHighlights)
                    let highlightsJSON = highlightsData.flatMap { String(data: $0, encoding: .utf8) }
                    flatItems.append(PersistedPaneTabItem(
                        title: doc.displayName,
                        filePath: doc.fileURL?.path(percentEncoded: false),
                        syntax: doc.syntaxName,
                        content: content,
                        isPinned: tab.isPinned,
                        paneIndex: paneIdx,
                        highlightsJSON: highlightsJSON,
                        databaseID: doc.databaseDocumentID
                    ))
                }
            }
        }
        
        guard !flatItems.isEmpty else { return }
        let session = PersistedWorkspaceSession(windows: windowLayouts)
        if let sessionData = try? JSONEncoder().encode(session),
           let sessionJSON = String(data: sessionData, encoding: .utf8)
        {
            CotLocalDatabase.shared.set(sessionJSON, forKey: CotLocalDatabase.ConfigKey.windowLayoutTree)
        }
        if let flatData = try? JSONEncoder().encode(flatItems),
           let flatJSON = String(data: flatData, encoding: .utf8)
        {
            CotLocalDatabase.shared.set(flatJSON, forKey: CotLocalDatabase.ConfigKey.activePaneTabsSession)
        }
    }
    
    
    /// Reloads this window's panes and tabs from the newly active user's `CotLocalDatabase`.
    func reloadWorkspaceForActiveUser() {
        
        self.sessionSaveTask?.cancel()
        self.sessionSaveTask = nil
        
        let outgoingDocs = self.paneDocuments
        let outgoingTextViews = self.textViews
        
        self.isRestoringPersistedPaneTabs = true
        defer {
            self.isRestoringPersistedPaneTabs = false
            self.updateSplitState()
            self.focusedDocument.counter.refreshNow()
            NotificationCenter.default.post(name: Self.focusedDocumentDidChangeNotification, object: self)
        }
        
        self.unzoomPane()
        
        for tv in outgoingTextViews {
            NotificationCenter.default.removeObserver(self, name: EditorTextView.DidLiveChangeSelectionMessage.name, object: tv)
        }
        
        if let freshDoc = try? self.makePaneDocument() {
            self.promotePrimaryDocument(to: freshDoc)
            let tabs = self.loadPersistedPaneTabItems()
            if !tabs.isEmpty {
                let layout = PersistedWindowLayout(
                    root: .pane(tabs: tabs, selectedTabIndex: 0, showsLineNumber: self.showsLineNumber),
                    focusedPaneIndex: 0,
                    windowFrame: nil
                )
                self.applyPersistedWindowLayout(layout)
            } else {
                let paneVC = self.makeEditorViewController(document: freshDoc, copying: self.editorViewControllers.first)
                let oldItems = self.splitViewItems
                self.addSplitViewItem(self.makeSplitViewItem(for: paneVC))
                for oldItem in oldItems {
                    self.removeSplitViewItem(oldItem)
                }
                self.focusedChild = paneVC
                self.view.window?.makeFirstResponderDiscardingMarkedText(paneVC.textView)
            }
        }
        
        let activeDocs = Set(self.paneDocuments.map(ObjectIdentifier.init))
        for doc in outgoingDocs where !activeDocs.contains(ObjectIdentifier(doc)) {
            self.stopObservingTextStorage(of: doc)
            doc.updateChangeCount(.changeCleared)
            doc.hasUncommittedChanges = false
            doc.close()
        }
    }
    
    
    /// Restores the saved tabs from `CotLocalDatabase` once on launch.
    ///
    /// The previous split/window layout is deliberately flattened into a single pane: restarting
    /// should never rebuild a wall of panes, but it should still bring the documents back.
    private func restorePersistedPaneTabsIfNeeded() {
        
        guard !self.didRestorePersistedPaneTabs, !Self.didRestoreAppPaneTabsThisLaunch else { return }
        self.didRestorePersistedPaneTabs = true
        Self.didRestoreAppPaneTabsThisLaunch = true
        
        self.isRestoringPersistedPaneTabs = true
        defer {
            self.isRestoringPersistedPaneTabs = false
            self.updateSplitState()
            self.focusedDocument.counter.refreshNow()
            NotificationCenter.default.post(name: Self.focusedDocumentDidChangeNotification, object: self)
        }
        
        let tabs = self.loadPersistedPaneTabItems()
        guard !tabs.isEmpty else { return }
        
        let layout = PersistedWindowLayout(
            root: .pane(tabs: tabs, selectedTabIndex: 0, showsLineNumber: self.showsLineNumber),
            focusedPaneIndex: 0,
            windowFrame: nil
        )
        self.applyPersistedWindowLayout(layout)
    }
    
    
    private func loadPersistedPaneTabItems() -> [PersistedPaneTabItem] {
        
        var restoredItems: [PersistedPaneTabItem] = []
        
        // 1. The flat session already contains every tab across every window and pane.
        let raw = CotLocalDatabase.shared.string(forKey: CotLocalDatabase.ConfigKey.activePaneTabsSession)
        if let data = raw.data(using: .utf8),
           let items = try? JSONDecoder().decode([PersistedPaneTabItem].self, from: data),
           !items.isEmpty
        {
            restoredItems = items
        }
        
        // 2. Fall back to the recursive tree and collect its leaves.
        if restoredItems.isEmpty {
            let treeRaw = CotLocalDatabase.shared.string(forKey: CotLocalDatabase.ConfigKey.windowLayoutTree)
            if let treeData = treeRaw.data(using: .utf8),
               let workspace = try? JSONDecoder().decode(PersistedWorkspaceSession.self, from: treeData)
            {
                func collect(from node: PersistedLayoutNode, into items: inout [PersistedPaneTabItem]) {
                    switch node {
                        case .pane(let tabs, _, _):
                            items.append(contentsOf: tabs)
                        case .split(_, let children, _):
                            for child in children {
                                collect(from: child, into: &items)
                            }
                    }
                }
                for window in workspace.windows {
                    collect(from: window.root, into: &restoredItems)
                }
            }
        }
        
        guard !restoredItems.isEmpty else { return [] }
        
        var seen = Set<String>()
        return restoredItems.compactMap { item -> PersistedPaneTabItem? in
            let key = item.filePath ?? item.databaseID ?? item.title
            guard seen.insert(key).inserted else { return nil }
            var normalized = item
            normalized.paneIndex = 0
            return normalized
        }
    }
    
    
    /// Applies a `PersistedWindowLayout` to this `DocumentViewController`, replacing any empty launch placeholder document.
    private func applyPersistedWindowLayout(_ layout: PersistedWindowLayout) {
        
        if let frameStr = layout.windowFrame, let window = self.view.window {
            let rect = NSRectFromString(frameStr)
            if rect.width >= 300, rect.height >= 200 {
                window.setFrame(rect, display: true)
            }
        }
        
        let initialDoc = self.document
        let initialIsBlankPlaceholder = (initialDoc.fileURL == nil && !initialDoc.isDocumentEdited && initialDoc.textStorage.length == 0)
        var didReuseOrPromotePrimary = !initialIsBlankPlaceholder
        var placeholderToClose: Document? = initialIsBlankPlaceholder ? initialDoc : nil
        
        let templateEditor = self.editorViewControllers.first
        
        guard let builtRoot = self.buildRestoredNode(
            layout.root,
            templateEditor: templateEditor,
            didPromotePrimary: &didReuseOrPromotePrimary
        ) else { return }
        
        // Replace existing splitViewItems with the restored hierarchy
        let oldItems = self.splitViewItems
        if let rootSplit = builtRoot as? SplitGroupViewController {
            self.splitView.isVertical = rootSplit.splitView.isVertical
            self.splitState.isVertical = rootSplit.splitView.isVertical
            let transferredItems = rootSplit.splitViewItems
            for item in transferredItems {
                rootSplit.removeSplitViewItem(item)
                self.addSplitViewItem(item)
            }
        } else {
            self.addSplitViewItem(self.makeSplitViewItem(for: builtRoot))
        }
        for oldItem in oldItems {
            self.removeSplitViewItem(oldItem)
        }
        
        // Close the blank launch placeholder document if we promoted a restored document in its place
        if didReuseOrPromotePrimary, let placeholder = placeholderToClose, placeholder !== self.document {
            self.stopObservingTextStorage(of: placeholder)
            placeholder.close()
            placeholderToClose = nil
        }
        
        let editors = self.editorViewControllers
        if let targetEditor = editors[safe: layout.focusedPaneIndex] ?? editors.first {
            self.focusedChild = targetEditor
            self.view.window?.makeFirstResponderDiscardingMarkedText(targetEditor.textView)
        }
        
        self.scheduleApplySavedWeights(from: layout.root)
    }
    
    
    /// Recursively constructs a `SplitGroupViewController` or `EditorViewController` from a `PersistedLayoutNode`.
    private func buildRestoredNode(
        _ node: PersistedLayoutNode,
        templateEditor: EditorViewController?,
        didPromotePrimary: inout Bool
    ) -> NSViewController? {
        
        switch node {
            case .pane(let tabItems, let selectedTabIndex, let showsLineNumber):
                var createdDocs: [(doc: Document, item: PersistedPaneTabItem)] = []
                for item in tabItems {
                    if let doc = self.instantiateRestoredDocument(for: item) {
                        createdDocs.append((doc, item))
                    }
                }
                if createdDocs.isEmpty {
                    guard let fallbackDoc = try? self.makePaneDocument() else { return nil }
                    let fallbackItem = PersistedPaneTabItem(title: fallbackDoc.displayName, filePath: nil, syntax: fallbackDoc.syntaxName, content: "", isPinned: false, paneIndex: 0)
                    createdDocs.append((fallbackDoc, fallbackItem))
                }
                
                let firstEntry = createdDocs[0]
                if !didPromotePrimary {
                    didPromotePrimary = true
                    self.promotePrimaryDocument(to: firstEntry.doc)
                }
                
                let paneVC = self.makeEditorViewController(document: firstEntry.doc, copying: templateEditor)
                paneVC.showsLineNumber = showsLineNumber
                if firstEntry.item.isPinned, let firstTab = paneVC.tabs.first {
                    firstTab.isPinned = true
                }
                
                for entry in createdDocs.dropFirst() {
                    let addedTab = self.addTab(entry.doc, to: paneVC, copying: paneVC.textView)
                    if entry.item.isPinned {
                        addedTab.isPinned = true
                    }
                }
                
                paneVC.updateTabState()
                if let targetTab = paneVC.tabs[safe: selectedTabIndex] ?? paneVC.tabs.first {
                    paneVC.select(tab: targetTab)
                }
                return paneVC
                
            case .split(let isVertical, let children, _):
                let builtChildren = children.compactMap { child in
                    self.buildRestoredNode(child, templateEditor: templateEditor, didPromotePrimary: &didPromotePrimary)
                }
                guard !builtChildren.isEmpty else { return nil }
                if builtChildren.count == 1 {
                    return builtChildren[0]
                }
                let group = SplitGroupViewController(isVertical: isVertical)
                for childVC in builtChildren {
                    group.addSplitViewItem(self.makeSplitViewItem(for: childVC))
                }
                return group
        }
    }
    
    
    /// Instantiates or reuses a `Document` for a `PersistedPaneTabItem`.
    private func instantiateRestoredDocument(for item: PersistedPaneTabItem) -> Document? {
        
        // Check if `self.document` already matches this file or title with non-empty content
        if let path = item.filePath, self.document.fileURL?.path(percentEncoded: false) == path {
            if let dbID = item.databaseID, !dbID.isEmpty {
                self.document.databaseDocumentID = dbID
            }
            return self.document
        }
        if self.document.displayName == item.title, self.document.textStorage.length > 0 {
            if let dbID = item.databaseID, !dbID.isEmpty {
                self.document.databaseDocumentID = dbID
            }
            return self.document
        }
        
        // If backed by a file on disk that still exists, open or read from it
        if let path = item.filePath, FileManager.default.fileExists(atPath: path) {
            let fileURL = URL(filePath: path)
            if let existing = NSDocumentController.shared.document(for: fileURL) as? Document {
                return existing
            }
            let typeName = (try? NSDocumentController.shared.typeForContents(of: fileURL)) ?? UTType.plainText.identifier
            if let fileDoc = try? Document(contentsOf: fileURL, ofType: typeName) {
                NSDocumentController.shared.addDocument(fileDoc)
                fileDoc.isTransient = false
                fileDoc.syntaxController.setupParser()
                return fileDoc
            }
        }
        
        guard let doc = try? self.makePaneDocument() else { return nil }
        if let dbID = item.databaseID, !dbID.isEmpty {
            doc.databaseDocumentID = dbID
        }
        doc.displayName = item.title
        doc.setSyntax(name: item.syntax)
        if !item.content.isEmpty {
            doc.textStorage.replaceCharacters(in: doc.textStorage.range, with: item.content)
            doc.updateChangeCount(.changeCleared)
        }
        if let highlightsJSON = item.highlightsJSON,
           let highlightsData = highlightsJSON.data(using: .utf8),
           let decoded = try? JSONDecoder().decode([TextHighlight].self, from: highlightsData),
           !decoded.isEmpty
        {
            doc.restoreHighlightsFromDatabase(decoded)
        }
        return doc
    }
    
    
    /// Applies the saved divider weights across multiple layout passes so split panes keep their exact proportions.
    private func scheduleApplySavedWeights(from rootNode: PersistedLayoutNode) {
        
        Task { @MainActor [weak self] in
            for delayMs in [16, 60, 220] {
                try? await Task.sleep(for: .milliseconds(delayMs))
                guard let self else { return }
                self.view.layoutSubtreeIfNeeded()
                self.applyWeights(from: rootNode, to: self)
            }
        }
    }
    
    
    private func applyWeights(from node: PersistedLayoutNode, to group: NSSplitViewController) {
        
        guard case .split(_, let children, let weights) = node else { return }
        let items = group.splitViewItems
        guard items.count > 1, items.count == children.count, weights.count == items.count else { return }
        
        if !weights.isEmpty {
            let splitView = group.splitView
            var leadingInset: CGFloat = 0
            var trailingInset: CGFloat = 0
            if !splitView.isVertical, group === self {
                let insets = group.view.safeAreaInsets
                leadingInset = max(0, insets.top)
                trailingInset = max(0, insets.bottom)
            }
            self.applySplitPaneSizes(
                weights: weights.map { CGFloat($0) },
                leadingInset: leadingInset,
                trailingInset: trailingInset,
                in: group
            )
        }
        
        group.view.layoutSubtreeIfNeeded()
        for (index, item) in items.enumerated() {
            if let nested = item.viewController as? SplitGroupViewController {
                self.applyWeights(from: children[index], to: nested)
            }
        }
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
        viewController.requestRenameTab = { [weak self, weak viewController] tab, newName in
            guard let self, let viewController else { return }
            self.renameTab(tab, to: newName, in: viewController)
        }
        viewController.requestDropTabAtIndex = { [weak self, weak viewController] draggedID, targetIndex in
            guard let self, let viewController else { return false }
            return self.handleDroppedTab(id: draggedID, onto: viewController, atIndex: targetIndex)
        }
        viewController.requestDropTabInZone = { [weak self, weak viewController] draggedID, zone in
            guard let self, let viewController else { return false }
            return self.handleDroppedTab(id: draggedID, onto: viewController, zone: zone)
        }
        viewController.requestDetachTabToNewWindow = { [weak self, weak viewController] tab, screenPoint in
            guard let self, let viewController else { return }
            self.detachTabToNewWindow(tab, from: viewController, atScreenPoint: screenPoint)
        }
        viewController.didChangeTabLayout = { [weak self] in
            self?.savePaneTabsSessionToDatabase()
        }
        viewController.didSelectTab = { [weak self, weak viewController] _ in
            guard let self, let viewController else { return }
            self.focusedChild = viewController
            if !viewController.isRenamingTab && !viewController.suppressesEditorFocusOnTabSelect {
                self.view.window?.makeFirstResponderDiscardingMarkedText(viewController.textView)
            }
            NotificationCenter.default.post(name: Self.focusedDocumentDidChangeNotification, object: self)
            self.savePaneTabsSessionToDatabase()
        }
        
        // observe edits so each document keeps its own syntax parse up to date
        self.observeTextStorage(of: document)
        
        // setup textView
        if let textView = viewController.textView {
            self.configureTextView(textView, copying: otherViewController?.textView)
            // the value of the pane this one was split from, or the window's default
            viewController.showsLineNumber = otherViewController?.showsLineNumber ?? self.showsLineNumber  // need to be set after setting text orientation
        }
        
        // observe cursor
        NotificationCenter.default.addObserver(self, selector: #selector(textViewDidLiveChangeSelection),
                                               name: EditorTextView.DidLiveChangeSelectionMessage.name,
                                               object: viewController.textView)
        
        if let palette = self.currentChromePalette {
            viewController.applyChromePalette(palette)
        }
        
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
    
    
    /// Observes the text storage of a document shown in a pane.
    ///
    /// Remove before adding so calling this for a second tab/pane on the same document never
    /// registers a duplicate observer (which would shift `textHighlights` twice per edit).
    ///
    /// - Parameter document: The document to observe.
    private func observeTextStorage(of document: Document) {
        
        NotificationCenter.default.removeObserver(self, name: NSTextStorage.didProcessEditingNotification,
                                                  object: document.textStorage)
        NotificationCenter.default.addObserver(self, selector: #selector(textStorageDidProcessEditing),
                                               name: NSTextStorage.didProcessEditingNotification,
                                               object: document.textStorage)
    }
    
    
    /// Stops observing the text storage of a document that leaves the window.
    ///
    /// - Parameter document: The document to stop observing.
    private func stopObservingTextStorage(of document: Document) {
        
        guard document !== self.document else { return }
        
        // Keep observing if another tab in this window still displays the same document.
        let remainingTabs = self.editorViewControllers.flatMap(\.tabs).filter { $0.document === document }
        guard remainingTabs.count <= 1 else { return }
        
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
    
    
    /// Direction for spatial pane navigation (`⌃A` + arrows / `h j k l`).
    enum PaneNavigationDirection {
        
        case left
        case right
        case up
        case down
    }
    
    
    /// Moves focus to the adjacent pane in the given spatial direction.
    ///
    /// - Parameter direction: The spatial direction to jump towards.
    func focusPane(direction: PaneNavigationDirection) {
        
        let panes = self.editorViewControllers
        guard panes.count > 1, let window = self.view.window else {
            NSSound.beep()
            return
        }
        
        if self.zoomedPane != nil {
            self.unzoomPane()
        }
        
        guard let current = self.focusedChild ?? panes.first else { return }
        let currentRect = current.view.convert(current.view.bounds, to: nil)
        let currentCenter = NSPoint(x: currentRect.midX, y: currentRect.midY)
        
        var bestCandidate: EditorViewController?
        var bestScore = CGFloat.greatestFiniteMagnitude
        
        for candidate in panes where candidate !== current {
            let rect = candidate.view.convert(candidate.view.bounds, to: nil)
            let center = NSPoint(x: rect.midX, y: rect.midY)
            let dx = center.x - currentCenter.x
            let dy = center.y - currentCenter.y  // window coordinates: +y is up, -y is down
            
            let primaryDistance: CGFloat
            let secondaryDistance: CGFloat
            let overlapsPerpendicularly: Bool
            
            switch direction {
                case .left:
                    guard dx < -4 else { continue }
                    primaryDistance = -dx
                    secondaryDistance = abs(dy)
                    overlapsPerpendicularly = min(currentRect.maxY, rect.maxY) > max(currentRect.minY, rect.minY)
                case .right:
                    guard dx > 4 else { continue }
                    primaryDistance = dx
                    secondaryDistance = abs(dy)
                    overlapsPerpendicularly = min(currentRect.maxY, rect.maxY) > max(currentRect.minY, rect.minY)
                case .up:
                    guard dy > 4 else { continue }
                    primaryDistance = dy
                    secondaryDistance = abs(dx)
                    overlapsPerpendicularly = min(currentRect.maxX, rect.maxX) > max(currentRect.minX, rect.minX)
                case .down:
                    guard dy < -4 else { continue }
                    primaryDistance = -dy
                    secondaryDistance = abs(dx)
                    overlapsPerpendicularly = min(currentRect.maxX, rect.maxX) > max(currentRect.minX, rect.minX)
            }
            
            let penalty: CGFloat = overlapsPerpendicularly ? 0 : 1000
            let score = primaryDistance + secondaryDistance * 0.5 + penalty
            if score < bestScore {
                bestScore = score
                bestCandidate = candidate
            }
        }
        
        guard let target = bestCandidate else {
            NSSound.beep()
            return
        }
        
        self.focusedChild = target
        window.makeFirstResponderDiscardingMarkedText(target.textView)
        NotificationCenter.default.post(name: Self.focusedDocumentDidChangeNotification, object: self)
    }
    
    
    /// Applies the given theme to child text views.
    ///
    /// - Parameter name: The name of the theme to apply.
    private func setTheme(name: String) {
        
        assert(Thread.isMainThread)
        
        let theme: Theme
        let resolvedName: String
        do {
            theme = try ThemeManager.shared.setting(name: name)
            resolvedName = name
        } catch {
            // Built-in themes belong to the application bundle rather than the migrated SQLite DB;
            // fall back cleanly to the app's default theme instead of presenting a missing-resource alert.
            let fallbackName = ThemeManager.shared.userDefaultSettingName(inDarkMode: self.view.effectiveAppearance.isDark)
            if fallbackName != name, let fallbackTheme = try? ThemeManager.shared.setting(name: fallbackName) {
                theme = fallbackTheme
                resolvedName = fallbackName
            } else if let bundledName = ThemeManager.shared.bundledSettingNames.first,
                      let bundledTheme = try? ThemeManager.shared.setting(name: bundledName)
            {
                theme = bundledTheme
                resolvedName = bundledName
            } else {
                return self.presentErrorAsSheet(error)
            }
        }
        
        self.themeName = resolvedName
        self.document.syntaxController.theme = theme
        for doc in self.paneDocuments where doc !== self.document {
            doc.syntaxController.theme = theme
        }
        
        for textView in self.textViews {
            textView.theme = theme
            textView.layoutManager?.invalidateHighlight(theme: theme)
        }
        
        self.updateWindowChromePalette()
        self.invalidateRestorableState()
    }
    
    
    /// Recomputes and broadcasts the unified window chrome palette across titlebar, tab strip, status bar, and toolbar pills.
    func updateWindowChromePalette() {
        
        let isDark = (self.viewIfLoaded?.effectiveAppearance ?? NSApp.effectiveAppearance).isDark
        let palette = StudioPaletteManager.shared.chromePalette(for: self.theme, isDark: isDark)
        self.currentChromePalette = palette
        
        if let docWindow = self.viewIfLoaded?.window as? DocumentWindow {
            docWindow.chromeBackgroundColor = palette.titlebarBackground
        }
        for editorVC in self.editorViewControllers {
            editorVC.applyChromePalette(palette)
        }
        NotificationCenter.default.post(name: Self.didUpdateChromePaletteNotification, object: self)
    }
    
    
    // MARK: In-Window Document & Report Opening
    
    /// Opens all provided documents as tabs in the focused pane in one batch, then focuses the preferred item.
    func openAllManagedDocuments(
        _ entries: [(liveDoc: Document?, record: StoredDocumentRecord?)],
        focusing preferredRecordID: String? = nil
    ) {
        guard !entries.isEmpty,
              let targetPane = self.focusedChild ?? self.editorViewControllers.first
        else { return }
        
        var openedDocs: [Document] = []
        var preferredDoc: Document?
        
        self.isRestoringPersistedPaneTabs = true
        defer {
            self.isRestoringPersistedPaneTabs = false
            self.savePaneTabsSessionToDatabase()
        }
        
        for entry in entries {
            let resolvedDoc: Document?
            if let liveDoc = entry.liveDoc {
                if !self.editorViewControllers.contains(where: { $0.tabs.contains(where: { $0.document === liveDoc }) }) {
                    self.addTab(liveDoc, to: targetPane, copying: targetPane.textView)
                }
                resolvedDoc = liveDoc
            } else if let record = entry.record {
                resolvedDoc = self.resolveOrCreateDocument(for: record, in: targetPane)
            } else {
                resolvedDoc = nil
            }
            
            if let doc = resolvedDoc {
                openedDocs.append(doc)
                if let preferredRecordID,
                   (doc.databaseDocumentID == preferredRecordID || entry.record?.id == preferredRecordID)
                {
                    preferredDoc = doc
                }
            }
        }
        
        if let docToFocus = preferredDoc ?? openedDocs.first {
            self.openOrFocusDocument(docToFocus, splitRight: false)
        }
    }
    
    
    /// Finds an existing open document for `record` in this window or creates/loads one into `targetPane`.
    private func resolveOrCreateDocument(for record: StoredDocumentRecord, in targetPane: EditorViewController) -> Document? {
        
        let normalizedRecordID = record.id.hasPrefix("doc:") ? String(record.id.dropFirst(4)) : record.id
        
        for pane in self.editorViewControllers {
            for tab in pane.tabs {
                let doc = tab.document
                let matchesPath = record.filePath.map { doc.fileURL?.path(percentEncoded: false) == $0 } ?? false
                let docCleanID = doc.databaseDocumentID.hasPrefix("doc:") ? String(doc.databaseDocumentID.dropFirst(4)) : doc.databaseDocumentID
                let matchesID = (docCleanID == normalizedRecordID) || (doc.databaseDocumentID == record.id)
                if matchesPath || matchesID {
                    return doc
                }
            }
        }
        
        if let filePath = record.filePath, FileManager.default.fileExists(atPath: filePath) {
            let fileURL = URL(filePath: filePath)
            if let existing = NSDocumentController.shared.document(for: fileURL) as? Document {
                if !self.editorViewControllers.contains(where: { $0.tabs.contains(where: { $0.document === existing }) }) {
                    self.addTab(existing, to: targetPane, copying: targetPane.textView)
                }
                return existing
            }
            let typeName = (try? NSDocumentController.shared.typeForContents(of: fileURL)) ?? UTType.plainText.identifier
            if let fileDoc = try? Document(contentsOf: fileURL, ofType: typeName) {
                NSDocumentController.shared.addDocument(fileDoc)
                self.addTab(fileDoc, to: targetPane, copying: targetPane.textView)
                return fileDoc
            }
        }
        
        guard let doc = try? self.makePaneDocument() else { return nil }
        doc.databaseDocumentID = record.id
        doc.displayName = record.title
        doc.setSyntax(name: record.syntax)
        if !record.content.isEmpty {
            doc.textStorage.replaceCharacters(in: doc.textStorage.range, with: record.content)
        }
        doc.updateChangeCount(.changeCleared)
        doc.hasUncommittedChanges = false
        
        if let highlightsData = record.highlightsJSON.data(using: .utf8),
           let decoded = try? JSONDecoder().decode([TextHighlight].self, from: highlightsData),
           !decoded.isEmpty
        {
            doc.restoreHighlightsFromDatabase(decoded)
        }
        
        self.addTab(doc, to: targetPane, copying: targetPane.textView)
        return doc
    }
    
    
    /// Opens or focuses a live `Document` directly inside the focused pane (never splits).
    func openOrFocusDocument(_ document: Document, splitRight: Bool = false) {
        
        // Check if already hosted as a tab in this window
        for pane in self.editorViewControllers {
            if let existingTab = pane.tabs.first(where: { $0.document === document }) {
                pane.select(tab: existingTab)
                self.focusedChild = pane
                self.view.window?.makeKeyAndOrderFront(nil)
                self.view.window?.makeFirstResponderDiscardingMarkedText(pane.textView)
                NotificationCenter.default.post(name: Self.focusedDocumentDidChangeNotification, object: self)
                document.counter.refreshNow()
                return
            }
        }
        
        guard let targetPane = self.focusedChild ?? self.editorViewControllers.first else { return }
        self.addTab(document, to: targetPane, copying: targetPane.textView)
    }
    
    
    /// Opens a document stored in `CotLocalDatabase` (or on disk) directly inside this window.
    func openStoredDocumentRecord(_ record: StoredDocumentRecord, splitRight: Bool = false) {
        
        let normalizedRecordID = record.id.hasPrefix("doc:") ? String(record.id.dropFirst(4)) : record.id
        
        // 1. Check live open documents across all windows first
        for wc in NSApp.orderedWindows.compactMap({ $0.windowController as? DocumentWindowController }) {
            guard let docVC = wc.documentViewController else { continue }
            for pane in docVC.editorViewControllers {
                for tab in pane.tabs {
                    let doc = tab.document
                    let matchesPath = record.filePath.map { doc.fileURL?.path(percentEncoded: false) == $0 } ?? false
                    let docCleanID = doc.databaseDocumentID.hasPrefix("doc:") ? String(doc.databaseDocumentID.dropFirst(4)) : doc.databaseDocumentID
                    let matchesID = (docCleanID == normalizedRecordID) || (doc.databaseDocumentID == record.id)
                    if matchesPath || matchesID {
                        if docVC === self {
                            pane.select(tab: tab)
                            self.focusedChild = pane
                            self.view.window?.makeFirstResponderDiscardingMarkedText(pane.textView)
                            NotificationCenter.default.post(name: Self.focusedDocumentDidChangeNotification, object: self)
                            return
                        } else if !splitRight {
                            // Bring tab cleanly into current window if single-pane / consistent experience,
                            // or focus it if moving would close the other window? Wait: move cleanly only if user wants it here;
                            // if other window has >1 tab or we focus the window, let's check: bringing it in-window is best,
                            // or if it's disk-backed / untitled in another window, activate that window's tab if moving isn't needed.
                            // Better yet: switch focus cleanly if it's already live there, unless it's single-click from Document Center:
                            pane.select(tab: tab)
                            docVC.focusedChild = pane
                            wc.window?.makeKeyAndOrderFront(nil)
                            wc.window?.makeFirstResponderDiscardingMarkedText(pane.textView)
                            return
                        }
                    }
                }
            }
        }
        
        // 2. If backed by a file on disk, open via Document(contentsOf:)
        if let filePath = record.filePath, FileManager.default.fileExists(atPath: filePath) {
            let fileURL = URL(filePath: filePath)
            if let existing = NSDocumentController.shared.document(for: fileURL) as? Document {
                self.openOrFocusDocument(existing, splitRight: splitRight)
                return
            }
            let typeName = (try? NSDocumentController.shared.typeForContents(of: fileURL)) ?? UTType.plainText.identifier
            if let fileDoc = try? Document(contentsOf: fileURL, ofType: typeName) {
                NSDocumentController.shared.addDocument(fileDoc)
                self.openOrFocusDocument(fileDoc, splitRight: splitRight)
                return
            }
        }
        
        // 3. Otherwise recreate untitled/snapshot document from database inside this window
        guard let doc = try? self.makePaneDocument() else { return NSSound.beep() }
        doc.databaseDocumentID = record.id
        doc.displayName = record.title
        doc.setSyntax(name: record.syntax)
        if !record.content.isEmpty {
            doc.textStorage.replaceCharacters(in: doc.textStorage.range, with: record.content)
        }
        doc.updateChangeCount(.changeCleared)
        doc.hasUncommittedChanges = false
        
        if let highlightsData = record.highlightsJSON.data(using: .utf8),
           let decoded = try? JSONDecoder().decode([TextHighlight].self, from: highlightsData),
           !decoded.isEmpty
        {
            doc.restoreHighlightsFromDatabase(decoded)
        }
        
        self.openOrFocusDocument(doc, splitRight: splitRight)
    }
    
    
    /// Opens a generated Markdown/text document (such as Organize & Merge Map) as a tab in the
    /// currently focused pane without modifying the existing split pane layout.
    func openGeneratedTab(
        title: String,
        content: String,
        syntaxName: String = SyntaxName.markdown,
        databaseID: String? = nil
    ) {
        
        if let databaseID {
            for pane in self.editorViewControllers {
                if let existingTab = pane.tabs.first(where: { $0.document.databaseDocumentID == databaseID }) {
                    let doc = existingTab.document
                    doc.displayName = title
                    doc.isExplicitlyNamed = true
                    doc.setSyntax(name: syntaxName)
                    doc.textStorage.replaceCharacters(in: doc.textStorage.range, with: content)
                    doc.updateChangeCount(.changeCleared)
                    doc.hasUncommittedChanges = false
                    pane.select(tab: existingTab)
                    self.focusedChild = pane
                    pane.updateTabState()
                    doc.syncToLocalDatabase(force: true)
                    self.savePaneTabsSessionToDatabase()
                    return
                }
            }
        }
        
        guard let doc = try? self.makePaneDocument() else { return NSSound.beep() }
        if let databaseID {
            doc.databaseDocumentID = databaseID
        }
        doc.displayName = title
        doc.isExplicitlyNamed = true
        doc.setSyntax(name: syntaxName)
        if !content.isEmpty {
            doc.textStorage.replaceCharacters(in: doc.textStorage.range, with: content)
        }
        doc.updateChangeCount(.changeCleared)
        doc.hasUncommittedChanges = false
        
        self.openOrFocusDocument(doc, splitRight: false)
        doc.syncToLocalDatabase(force: true)
        self.savePaneTabsSessionToDatabase()
    }
    
    
    /// Opens a historical or newly generated weekly report directly inside this window.
    func openStoredWeeklyReport(_ report: StoredWeeklyReport, splitRight: Bool = false) {
        
        let reportDocID = "weekly:\(report.id)"
        
        for pane in self.editorViewControllers {
            if let existingTab = pane.tabs.first(where: { $0.document.databaseDocumentID == reportDocID }) {
                pane.select(tab: existingTab)
                self.focusedChild = pane
                self.view.window?.makeFirstResponderDiscardingMarkedText(pane.textView)
                NotificationCenter.default.post(name: Self.focusedDocumentDidChangeNotification, object: self)
                return
            }
        }
        
        guard let doc = try? self.makePaneDocument() else { return NSSound.beep() }
        doc.databaseDocumentID = reportDocID
        doc.displayName = report.title.hasSuffix(".md") ? report.title : "\(report.title).md"
        doc.setSyntax(name: SyntaxName.markdown)
        if !report.content.isEmpty {
            doc.textStorage.replaceCharacters(in: doc.textStorage.range, with: report.content)
        }
        doc.updateChangeCount(.changeCleared)
        doc.hasUncommittedChanges = false
        
        self.openOrFocusDocument(doc, splitRight: splitRight)
    }
    
    
    /// Closes a document directly from Document Center without closing the host window when it is the last tab.
    func closeDocumentFromCenter(_ document: Document) {
        
        for pane in self.editorViewControllers {
            guard let tab = pane.tabs.first(where: { $0.document === document }) else { continue }
            
            if pane === self.zoomedPane, pane.tabs.count == 1 {
                self.unzoomPane()
            }
            
            // Keep the host window alive with an empty scratch tab if this was the sole tab.
            if self.editorViewControllers.count == 1, pane.tabs.count == 1 {
                guard let replacement = try? self.makePaneDocument() else { return }
                self.addTab(replacement, to: pane, copying: pane.textView)
                self.promotePrimaryDocument(to: replacement)
            }
            
            if tab.document === self.document {
                let replacement = pane.tabs.first(where: { $0 !== tab })?.document
                    ?? self.editorViewControllers.first(where: { $0 !== pane })?.selectedTab.document
                if let replacement {
                    self.promotePrimaryDocument(to: replacement)
                }
            }
            
            self.stopObservingTextStorage(of: tab.document)
            
            if let textView = pane.textView(for: tab) {
                NotificationCenter.default.removeObserver(self, name: EditorTextView.DidLiveChangeSelectionMessage.name, object: textView)
                textView.undoManager?.removeAllActions(withTarget: textView)
            }
            
            let wasLastTab = (pane.tabs.count == 1)
            pane.removeTab(tab)
            tab.document.updateChangeCount(.changeCleared)
            tab.document.hasUncommittedChanges = false
            tab.document.close()
            
            if wasLastTab {
                self.removePane(pane)
            }
            
            self.updateSplitState()
            NotificationCenter.default.post(name: Self.focusedDocumentDidChangeNotification, object: self)
            return
        }
    }
}
