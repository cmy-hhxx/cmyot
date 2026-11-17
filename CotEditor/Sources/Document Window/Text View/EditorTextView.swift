//
//  EditorTextView.swift
//
//  CotEditor
//  https://coteditor.com
//
//  Created by nakamuxu on 2005-03-30.
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
import ColorCode
import Defaults
import Invisible
import LineEnding
import SyntaxFormat
import StringUtils
import TextEditing

private extension NSAttributedString.Key {
    
    static let autoBalancedClosingBracket = NSAttributedString.Key("autoBalancedClosingBracket")
}


// MARK: -

final class EditorTextView: NSTextView, CurrentLineHighlighting, MultiCursorEditing {
    
    @MainActor protocol Delegate: AnyObject {
        
        func editorTextView(_ textView: EditorTextView, readDroppedURLs URLs: [URL]) -> Bool
    }
    
    
    // MARK: Notification Messages
    
    struct DidBecomeFirstResponderMessage: NotificationCenter.MainActorMessage {
        
        typealias Subject = EditorTextView
        
        static let name = Notification.Name("TextViewDidBecomeFirstResponder")
    }
    
    
    struct DidLiveChangeSelectionMessage: NotificationCenter.MainActorMessage {
        
        typealias Subject = EditorTextView
        
        static let name = Notification.Name("TextViewDidLiveChangeSelection")
    }
    
    
    // MARK: Private Types
    
    private enum SerializationKey {
        
        static let font = "font"
        static let scale = "scale"
        static let tabWidth = "tabWidth"
        static let insertionLocations = "insertionLocations"
    }
    
    
    // MARK: Public Properties
    
    /// Whether the ⌃A prefix has been pressed and the next key is part of its sequence.
    private var isAwaitingControlAPrefix = false
    
    /// Whether AppKit is currently assembling the context menu for this view.
    ///
    /// While it is, the view reports that it offers neither auto-fill nor services, which is
    /// what keeps those items out of the menu (see ``menu(for:)``).
    private var isPreparingContextMenu = false
    
    var lineEnding: LineEnding = .lf
    var defaultFontType: FontType = .standard
    
    var theme: Theme?  { didSet { self.applyTheme() } }
    
    var isAutomaticSymbolBalancingEnabled = false
    var isAutomaticCompletionEnabled = false
    var isAutomaticIndentEnabled = false
    var isAutomaticPeriodSubstitutionEnabled = false  { didSet { self.invalidateAutomaticPeriodSubstitution() } }
    var isAutomaticTabExpansionEnabled = false
    var isAutomaticWhitespaceTrimmingEnabled = false
    var isApprovedTextChange = false
    var trimsWhitespaceOnlyLines = true
    var indentsWithTabKey = false
    
    var commentDelimiters: Syntax.Comment = Syntax.Comment()
    var commentsOutAfterIndent: Bool = false
    var appendsCommentSpacer: Bool = false
    var quoteDelimiters: [Syntax.PairDelimiter] = []  { didSet { self.invalidateQuotePairs() } }
    var indentTokens: [IndentToken] = []
    var syntaxCompletionWords: [Syntax.CompletionWord] = []
    var completionWordTypes: CompletionWordTypes = []
    
    var showsPageGuide = false  { didSet { self.setNeedsDisplay(self.frame, avoidAdditionalLayout: true) } }
    var pageGuideColumn: Int = 80  { didSet { self.setNeedsDisplay(self.frame, avoidAdditionalLayout: true)} }
    var overscrollRate: Double = 0  { didSet { self.invalidateOverscrollRate() } }
    
    var highlightsBraces = false
    var highlightsSelectionInstance = false  { didSet { self.invalidateInstanceHighlights() } }
    var selectionInstanceHighlightDelay: Double = 0.5  // seconds
    
    var highlightsCurrentLines = false  { didSet { self.setNeedsDisplay(self.frame, avoidAdditionalLayout: true) } }
    var needsUpdateLineHighlight = true {
        
        didSet {
            (self.lineHighlightRects + [self.visibleRect]).forEach { self.setNeedsDisplay($0, avoidAdditionalLayout: true) }
        }
    }
    var lineHighlightRects: [NSRect] = []
    private(set) var lineHighlightColor: NSColor?
    
    var insertionLocations: [Int] = []  { didSet { self.needsUpdateInsertionIndicators = true } }
    var selectionOrigins: [Int] = []
    var insertionIndicators: [NSTextInsertionIndicator] = []
    private(set) var isPerformingRectangularSelection = false
    
    // for Scaling extension
    var initialMagnificationScale: CGFloat = 0
    var deferredMagnification: CGFloat = 0
    
    var customSurroundPair: Pair<String>?
    
    var accessibilityHelpProvider: (() -> String?)?
    
    
    // MARK: Private Properties
    
    private static let textContainerInset = NSSize(width: 4, height: 6)
    
    private let minimumNonContiguousLayoutLength = 5_000_000
    private let minimumAutomaticCompletionLength = 3
    private let automaticCompletionDelay: TimeInterval = 0.25
    
    private let textFinder = TextFinder()
    
    private var spaceWidth: Double = 0
    
    private var quotePairRules: [QuotePairRule] = []
    private var matchingSymbolPairs: [SymbolPair]  { SymbolPair.braces + self.quotePairRules.map(\.pair) }
    private var isTypingPairedQuotes = false
    
    private var mouseDownPoint: NSPoint = .zero
    private var needsUpdateInsertionIndicators = false
    
    private lazy var overscrollResizingDebouncer = Debouncer { [weak self] in self?.invalidateOverscrollRate() }
    
    private var textHighlightColor: NSColor = .accent
    private var instanceHighlightTask: Task<Void, any Error>?
    
    private var isShowingCompletion = false
    private var partialCompletionWord: String?
    private lazy var completionDebouncer = Debouncer { [weak self] in self?.performCompletion() }
    
    private lazy var trimTrailingWhitespaceTask = Debouncer { [weak self] in
        guard let self, !self.hasMarkedText() else { return }
        self.trimTrailingWhitespace(keepingEditingPoint: true)
    }
    
    private var fontObservers: Set<AnyCancellable> = []
    private var windowOpacityObserver: NSKeyValueObservation?
    private var keyStateObservers: [any NSObjectProtocol] = []
    private var scrollClipObserver: NSObjectProtocol?
    private var inlineImageCardEntries: [(rect: NSRect, identifier: String, tokenRange: NSRange)] = []
    private weak var imagePreviewPopover: NSPopover?
    
    
    // MARK: Lifecycle
    
    required init(frame frameRect: NSRect = .zero, textStorage: NSTextStorage, lineEndingScanner: LineEndingScanner) {
        
        let textContainer = TextContainer()
        textContainer.widthTracksTextView = true
        // -> Avoid the default finite container height clipping large wrapped layouts (2026-05, macOS 26.4).
        textContainer.size.height = .greatestFiniteMagnitude
        
        let layoutManager = LayoutManager(lineEndingScanner: lineEndingScanner)
        textStorage.addLayoutManager(layoutManager)
        layoutManager.addTextContainer(textContainer)
        
        super.init(frame: frameRect, textContainer: textContainer)
        
        self.identifier = NSUserInterfaceItemIdentifier("EditorTextView")
        
        self.textFinder.client = self
        
        // set layout values (wraps lines)
        self.maxSize = .infinite
        self.isHorizontallyResizable = false
        self.isVerticallyResizable = true
        self.autoresizingMask = .width
        self.textContainerInset = Self.textContainerInset
        
        // set NSTextView behaviors
        self.allowsUndo = true
        self.isRichText = false
        self.allowedWritingToolsResultOptions = .plainText
        self.linkTextAttributes?.removeValue(forKey: .foregroundColor)
        
        // avoid AppKit falling back to Last Resort while fixing attributes during the initial setup
        self.typingAttributes[.font] = self.font ?? .systemFont(ofSize: 0)
        
        // Keep layer clipping enabled upfront so cursor/particle overlays never escape the pane
        self.wantsLayer = true
        self.layer?.masksToBounds = true
        self.registerForDraggedTypes([PaneTab.dragPasteboardType])
    }
    
    
    required init?(coder: NSCoder) {
        
        fatalError("init(coder:) has not been implemented")
    }
    
    
    override func encodeRestorableState(with coder: NSCoder, backgroundQueue queue: OperationQueue) {
        
        super.encodeRestorableState(with: coder, backgroundQueue: queue)
        
        coder.encode(self.font, forKey: SerializationKey.font)
        coder.encode(Double(self.scale), forKey: SerializationKey.scale)
        coder.encode(self.tabWidth, forKey: SerializationKey.tabWidth)
        coder.encode(self.insertionLocations, forKey: SerializationKey.insertionLocations)
    }
    
    
    override func restoreState(with coder: NSCoder) {
        
        super.restoreState(with: coder)
        
        if let font = coder.decodeObject(of: NSFont.self, forKey: SerializationKey.font),
           font != self.font
        {
            self.font = font
        }
        
        let scale = coder.decodeDouble(forKey: SerializationKey.scale)
        if scale != 1, scale > 0 {
            self.scale = scale
        }
        
        let tabWidth = coder.decodeInteger(forKey: SerializationKey.tabWidth)
        if tabWidth > 0 {
            self.tabWidth = tabWidth
        }
        
        if let insertionLocations = (coder.decodeArrayOfObjects(ofClass: NSNumber.self, forKey: SerializationKey.insertionLocations) as? [Int])?
            .filter({ $0 <= self.string.length }),
           !insertionLocations.isEmpty
        {
            self.insertionLocations = insertionLocations
        }
    }
    
    
    // MARK: Text View Methods
    
    override var textContainerOrigin: NSPoint {
        
        // append inset only to the bottom for overscroll
        NSPoint(x: super.textContainerOrigin.x, y: Self.textContainerInset.height)
            .offsetBy(dy: (self.layoutOrientation == .vertical) ? self.bounds.minY.rounded() : 0)
    }
    
    
    override var rangesForUserTextChange: [NSValue]? {
        
        // use sub-insertion points also for multi-text editing
        self.insertionRanges as [NSValue]
    }
    
    
    override var isEditable: Bool {
        
        didSet {
            self.invalidateInsertionIndicatorDisplayMode()
        }
    }
    
    
    override func accessibilityHelp() -> String? {
        
        self.accessibilityHelpProvider?() ?? super.accessibilityHelp()
    }
    
    
    override func becomeFirstResponder() -> Bool {
        
        guard super.becomeFirstResponder() else { return false }
        
        // post notification about becoming the first responder
        NotificationCenter.default.post(name: DidBecomeFirstResponderMessage.name, object: self)
        
        defer {
            self.invalidateInsertionIndicatorDisplayMode()
            self.invalidateAutomaticPeriodSubstitution()
        }
        
        return true
    }
    
    
    override func resignFirstResponder() -> Bool {
        
        guard super.resignFirstResponder() else { return false }
        
        self.funEffects.resetCursorTracking()
        self.vimEngine.clearVisualSelectionIfNeeded()
        
        defer {
            self.invalidateInsertionIndicatorDisplayMode()
            self.invalidateAutomaticPeriodSubstitution()
        }
        
        return true
    }
    
    
    override func viewDidMoveToWindow() {
        
        super.viewDidMoveToWindow()
        
        // show the editing mode right away, before the first key press
        if self.window != nil, UserDefaults.standard[.vimMode] {
            self.vimEngine.publishStatus()
        }
        
        // apply theme to window when attached
        if let window = self.window as? DocumentWindow, let theme = self.theme {
            window.contentBackgroundColor = theme.background.color
        }
        
        if let scrollObserver = self.scrollClipObserver {
            NotificationCenter.default.removeObserver(scrollObserver)
            self.scrollClipObserver = nil
        }
        
        if let window {
            self.wantsLayer = true
            self.layer?.masksToBounds = true
            if let clipView = self.enclosingScrollView?.contentView {
                clipView.wantsLayer = true
                clipView.layer?.masksToBounds = true
                clipView.postsBoundsChangedNotifications = true
                self.scrollClipObserver = NotificationCenter.default.addObserver(
                    forName: NSView.boundsDidChangeNotification,
                    object: clipView,
                    queue: .main
                ) { [weak self] _ in
                    MainActor.assumeIsolated {
                        self?.funEffects.resetCursorTracking()
                    }
                }
            }
            
            // apply window opacity
            self.windowOpacityObserver = window.observe(\.isOpaque, options: [.initial, .new]) { [unowned self] _, change in
                guard let new = change.newValue else { return }
                MainActor.assumeIsolated { [unowned self] in
                    self.drawsBackground = new
                    self.enclosingScrollView?.drawsBackground = new
                }
            }
            
            // observe key window state for insertion points drawing and automatic period substitution
            self.keyStateObservers.forEach(NotificationCenter.default.removeObserver)
            self.keyStateObservers = [
                NotificationCenter.default.addObserver(forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main) { [unowned self] _ in
                    MainActor.assumeIsolated { [unowned self] in
                        self.invalidateInsertionIndicatorDisplayMode()
                        self.invalidateAutomaticPeriodSubstitution()
                    }
                },
                NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: window, queue: .main) { [unowned self] _ in
                    MainActor.assumeIsolated { [unowned self] in
                        self.funEffects.resetCursorTracking()
                        self.invalidateInsertionIndicatorDisplayMode()
                        self.invalidateAutomaticPeriodSubstitution()
                    }
                },
            ]
        } else {
            self.funEffects.resetCursorTracking()
            self.keyStateObservers.forEach(NotificationCenter.default.removeObserver)
            self.keyStateObservers.removeAll()
            self.windowOpacityObserver = nil
            self.instanceHighlightTask?.cancel()
            self.instanceHighlightTask = nil
        }
    }
    
    
    override func setFrameSize(_ newSize: NSSize) {
        
        let oldSize = self.frame.size
        
        super.setFrameSize(newSize)
        
        guard newSize != oldSize else { return }
        
        if !self.inLiveResize {
            self.overscrollResizingDebouncer.schedule()
        }
        
        self.needsUpdateInsertionIndicators = true
        self.needsUpdateLineHighlight = true
    }
    
    
    override func viewDidEndLiveResize() {
        
        super.viewDidEndLiveResize()
        
        self.overscrollResizingDebouncer.schedule()
        self.updateTextTouchBarItems()
    }
    
    
    override func updateTextTouchBarItems() {
        
        // skip updates during live resize to avoid the performance issue in #971,
        // then perform a single update in `viewDidEndLiveResize()` (2026-03, macOS 26.3, FB7399413)
        guard !self.inLiveResize else { return }
        
        super.updateTextTouchBarItems()
    }
    
    
    override func mouseDown(with event: NSEvent) {
        
        self.mouseDownPoint = self.convert(event.locationInWindow, from: nil)
        
        // Clicking an inline image card in Plain Text opens an interactive preview popover
        if !event.modifierFlags.contains(.command),
           !event.modifierFlags.contains(.shift),
           !event.modifierFlags.contains(.option),
           event.clickCount == 1,
           (self.layoutManager as? LayoutManager)?.rendersPlainTextInlineImages == true,
           let hit = self.inlineImageCardEntries.first(where: { $0.rect.contains(self.mouseDownPoint) })
        {
            self.window?.makeFirstResponder(self)
            self.presentInlineImagePopover(for: hit)
            return
        }
        
        self.isPerformingRectangularSelection = event.modifierFlags.contains(.option)
        self.needsUpdateInsertionIndicators = true  // to draw dummy indicator for proper one while selecting
        
        let selectedRange = self.selectedRange.isEmpty ? self.selectedRange : nil
        
        super.mouseDown(with: event)
        
        // -> After `super.mouseDown(with:)` is actually the timing of `mouseUp(with:)`,
        //    which doesn't work in NSTextView subclasses. (2019-01, macOS 10.14)
        
        guard let window = self.window else { return assertionFailure() }
        
        let pointInWindow = window.convertPoint(fromScreen: NSEvent.mouseLocation)
        let point = self.convert(pointInWindow, from: nil)
        let isDragged = (point != self.mouseDownPoint)
        
        // restore the first empty insertion if it seems to disappear
        if event.modifierFlags.contains(.command),
           !self.selectedRange.isEmpty,
           let selectedRange,
           selectedRange.isEmpty,
           !self.selectedRange.contains(selectedRange.location),
           self.selectedRange.upperBound != selectedRange.location
        {
            self.insertionLocations = (self.insertionLocations + [selectedRange.location]).sorted()
        }
        
        // add/remove insertion point at clicked point
        if event.modifierFlags.contains(.command), event.clickCount == 1, !isDragged {
            self.modifyInsertionPoint(at: point)
        }
        
        self.isPerformingRectangularSelection = false
    }
    
    
    /// The Esc key is pressed.
    override func cancelOperation(_ sender: Any?) {
        
        // exit multi-cursor mode
        if self.hasMultipleInsertions {
            self.selectedRange = self.insertionRanges.first!
            self.scrollRangeToVisible(self.selectedRange)
            return
        }
        
        // -> NSTextView doesn't implement `cancelOperation(_:)`. (macOS 10.14)
    }
    
    
    override func didChangeText() {
        
        super.didChangeText()
        
        self.invalidateNonContiguousLayout()
        
        self.needsUpdateLineHighlight = true
        
        self.instanceHighlightTask?.cancel()
        
        if self.isAutomaticWhitespaceTrimmingEnabled {
            self.trimTrailingWhitespaceTask.schedule(delay: .seconds(3))
        }
    }
    
    
    /// Modal (Vim-style) editing layer, active while the `vimMode` default is on.
    private(set) lazy var vimEngine = VimEngine(textView: self)
    
    /// Built-in CoreAnimation effects controller for typewriter burst and Neovide-style Vim cursor trails.
    private(set) lazy var funEffects = EditorFunEffectsController(textView: self)
    
    
    /// The active cursor color, honoring custom user cursor color when enabled.
    var effectiveCursorColor: NSColor {
        
        if UserDefaults.standard[.usesCustomCursorColor],
           let custom = NSColor(colorCode: UserDefaults.standard[.customCursorColorHex])
        {
            return custom
        }
        return self.theme?.insertionPointColor ?? .textInsertionPointColor
    }
    
    
    /// Height of a single text line (never inflated by inline image card height).
    private var singleLineHeight: CGFloat {
        
        (self.layoutManager as? LayoutManager)?.lineHeight
            ?? max(14, (self.font?.pointSize ?? 13) * 1.3)
    }
    
    
    /// Re-applies the cursor color across native insertion point, multi-cursor indicators, and Vim blocks.
    func refreshCursorColor() {
        
        let color = self.effectiveCursorColor
        self.insertionPointColor = color
        for indicator in self.insertionIndicators {
            indicator.color = color
        }
        self.setNeedsDisplay(self.visibleRect, avoidAdditionalLayout: true)
    }
    
    
    override func drawInsertionPoint(in rect: NSRect, color: NSColor, turnedOn flag: Bool) {
        
        let cursorColor = self.effectiveCursorColor
        var caretRect = rect
        let maxLineHeight = self.singleLineHeight
        if caretRect.height > maxLineHeight + 2 {
            caretRect.size.height = maxLineHeight
        }
        
        guard UserDefaults.standard[.vimMode], VimState.shared.mode != .insert else {
            // On lines with inline image cards, AppKit's super.drawInsertionPoint can still extend
            // or ignore height; draw a crisp 2pt single-line caret directly in that case.
            if rect.height > maxLineHeight + 2 {
                guard flag else { return }
                var bar = caretRect
                bar.size.width = 2
                NSGraphicsContext.saveGraphicsState()
                cursorColor.setFill()
                NSBezierPath(roundedRect: bar, xRadius: 1, yRadius: 1).fill()
                NSGraphicsContext.restoreGraphicsState()
            } else {
                super.drawInsertionPoint(in: caretRect, color: cursorColor, turnedOn: flag)
            }
            return
        }
        
        var block = caretRect
        block.size.width = self.blockCursorWidth()
        
        NSGraphicsContext.saveGraphicsState()
        if VimState.shared.mode == .replace {
            let barHeight = max(3, round(block.height * 0.22))
            let underlineRect = NSRect(x: block.minX, y: block.maxY - barHeight, width: block.width, height: barHeight)
            cursorColor.withAlphaComponent(0.85).setFill()
            NSBezierPath(roundedRect: underlineRect, xRadius: 1, yRadius: 1).fill()
        } else {
            // Unified solid block cursor across Normal and Visual modes
            cursorColor.withAlphaComponent(VimState.shared.mode == .visual ? 0.65 : 0.55).setFill()
            NSBezierPath(roundedRect: block, xRadius: 1.5, yRadius: 1.5).fill()
        }
        NSGraphicsContext.restoreGraphicsState()
    }
    
    
    /// Width of the block cursor: the character under the caret, or a space at the line end.
    private func blockCursorWidth() -> CGFloat {
        
        let string = self.string as NSString
        let location = self.selectedRange().location
        let fallbackSpace = self.spaceWidth > 0 ? self.spaceWidth : 8
        guard location < string.length else { return fallbackSpace }
        
        let sample = string.substring(with: NSRange(location: location, length: 1))
        if sample == "\n" || sample == "\r" {
            return fallbackSpace
        }
        
        let font = self.font ?? .monospacedSystemFont(ofSize: 13, weight: .regular)
        return max((sample as NSString).size(withAttributes: [.font: font]).width, 2)
    }
    
    
    override func keyDown(with event: NSEvent) {
        
        // tmux-style prefix: ⌃A then Z / % / " works on the focused pane
        if self.handleControlAPrefix(event) { return }
        
        if UserDefaults.standard[.vimMode], self.vimEngine.handleKeyDown(event) { return }
        
        super.keyDown(with: event)
    }
    
    
    /// Handles the ⌃A prefix sequences that work on the focused pane:
    /// ⌃A Z toggles the zoom, ⌃A % splits to the right, ⌃A " splits downwards,
    /// ⌃A + arrows (or h/j/k/l) jumps between panes.
    ///
    /// - Parameter event: The key event.
    /// - Returns: `true` when the event was consumed by the prefix sequence.
    private func handleControlAPrefix(_ event: NSEvent) -> Bool {
        
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let character = event.charactersIgnoringModifiers
        
        if self.isAwaitingControlAPrefix {
            self.isAwaitingControlAPrefix = false
            
            guard !flags.contains(.command), !flags.contains(.control) else { return false }
            
            switch event.keyCode {
                case 123:  // ←
                    self.documentViewController?.focusPane(direction: .left)
                    return true
                case 124:  // →
                    self.documentViewController?.focusPane(direction: .right)
                    return true
                case 125:  // ↓
                    self.documentViewController?.focusPane(direction: .down)
                    return true
                case 126:  // ↑
                    self.documentViewController?.focusPane(direction: .up)
                    return true
                default:
                    break
            }
            
            switch character {
                case "z", "Z":
                    self.documentViewController?.togglePaneZoom(event)
                    return true
                    
                case "%":
                    self.documentViewController?.splitEditorVertically(self)
                    return true
                    
                case "\"", "\u{201D}":
                    self.documentViewController?.splitEditorHorizontally(self)
                    return true
                    
                case "h":
                    self.documentViewController?.focusPane(direction: .left)
                    return true
                    
                case "l":
                    self.documentViewController?.focusPane(direction: .right)
                    return true
                    
                case "j":
                    self.documentViewController?.focusPane(direction: .down)
                    return true
                    
                case "k":
                    self.documentViewController?.focusPane(direction: .up)
                    return true
                    
                default:
                    return false
            }
        }
        
        guard flags.contains(.control), !flags.contains(.command), character?.lowercased() == "a" else { return false }
        
        self.isAwaitingControlAPrefix = true
        return true
    }
    
    
    override func insertText(_ string: Any, replacementRange: NSRange) {
        
        // do not use this method for programmatic insertion.
        
        let plainString = String(anyString: string)!
        
        // enter multi-cursor editing
        let insertionRanges = self.insertionRanges
        if insertionRanges.count > 1 {
            self.insertText(plainString, replacementRanges: insertionRanges)
            return
        }
        
        // balance brackets and quotes
        if self.isAutomaticSymbolBalancingEnabled, replacementRange.isEmpty {
            // just move cursor if the automatically inserted closing bracket is already typed (#2121)
            if self.rangeForUserTextChange.isEmpty,
               self.matchingSymbolPairs.contains(where: { String($0.end) == plainString }),
               plainString.unicodeScalars.first == self.string.character(after: self.rangeForUserTextChange),
               self.textStorage?.attribute(.autoBalancedClosingBracket, at: self.selectedRange.location, effectiveRange: nil) as? Bool == true
            {
                self.textStorage?.removeAttribute(.autoBalancedClosingBracket, range: NSRange(location: self.selectedRange.location, length: 1))
                self.selectedRange.location += 1
                return
            }
            
            // with opening symbol input
            if let pair = self.matchingSymbolPairs.first(where: { String($0.begin) == plainString }) {
                // wrap selection with brackets if some text is selected
                if !self.rangeForUserTextChange.isEmpty {
                    self.surroundSelections(begin: String(pair.begin), end: String(pair.end))
                    return
                }
                
                // insert a bracket pair if the insertion point is not in a word
                if self.string.character(after: self.rangeForUserTextChange).map(CharacterSet.alphanumerics.contains) != true,
                   !(pair.begin == pair.end &&
                     self.string.character(before: self.rangeForUserTextChange).map(CharacterSet.alphanumerics.contains) == true)  // for "
                {
                    // raise a flag to adjust the cursor later in `handleTextCheckingResults(_:forRange:types:options:orthography:wordCount:)`
                    // -> The smart quote substitution replaces both double and single quotation marks.
                    if self.isAutomaticQuoteSubstitutionEnabled, pair.begin == "\"" || pair.begin == "'" {
                        self.isTypingPairedQuotes = true
                    }
                    
                    super.insertText(String(pair.begin) + String(pair.end), replacementRange: replacementRange)
                    self.setSelectedRangesWithUndo([NSRange(location: self.selectedRange.location - 1, length: 0)])
                    self.textStorage?.addAttribute(.autoBalancedClosingBracket, value: true,
                                                   range: NSRange(location: self.selectedRange.location, length: 1))
                    return
                }
            }
        }
        
        // smart outdent with certain symbols
        if self.isAutomaticIndentEnabled, replacementRange.isEmpty {
            let levelToReduce = self.string.smartOutdentLevel(with: plainString, indentWidth: self.tabWidth, tokens: self.indentTokens, in: self.rangeForUserTextChange)
            for _ in 0..<levelToReduce {
                // select the whole space run for a single indent level beforehand
                // -> Otherwise, `deleteBackward(_:)` deletes only a single character per level when the automatic tab expansion is disabled.
                if let deletionRange = self.string.rangeForSoftTabDeletion(in: self.rangeForUserTextChange, tabWidth: self.tabWidth) {
                    self.setSelectedRangesWithUndo(self.selectedRanges.map(\.rangeValue))
                    self.selectedRange = deletionRange
                }
                self.deleteBackward(nil)
            }
        }
        
        super.insertText(plainString, replacementRange: replacementRange)
        
        if !self.hasMarkedText(),
           plainString.count <= 4,
           var caretRect = self.boundingRect(for: self.selectedRange)
        {
            caretRect.size.height = min(caretRect.height, self.singleLineHeight)
            self.funEffects.triggerTypewriterBurst(at: caretRect, color: self.effectiveCursorColor)
        }
        
        // auto completion
        if self.isAutomaticCompletionEnabled {
            if !self.hasMarkedText(),
               self.rangeForUserCompletion.length >= self.minimumAutomaticCompletionLength
            {
                self.completionDebouncer.schedule(delay: .seconds(self.automaticCompletionDelay))
            } else {
                self.completionDebouncer.cancel()
            }
        }
    }
    
    
    override func insertTab(_ sender: Any?) {
        
        // indent with the Tab key
        if self.indentsWithTabKey, !self.rangeForUserTextChange.isEmpty {
            self.indent()
            return
        }
        
        // insert a soft tab
        if self.isAutomaticTabExpansionEnabled,
           let ranges = self.rangesForUserTextChange?.map(\.rangeValue)
        {
            let softTabs = self.string.softTabs(for: ranges, tabWidth: self.tabWidth)
            self.replace(with: softTabs, ranges: ranges, selectedRanges: nil)
            return
        }
        
        super.insertTab(sender)
    }
    
    
    /// The Shift + Tab keys are pressed.
    override func insertBacktab(_ sender: Any?) {
        
        // outdent with the Tab key
        if self.indentsWithTabKey {
            self.outdent()
            return
        }
        
        super.insertBacktab(sender)
    }
    
    
    override func insertNewline(_ sender: Any?) {
        
        guard self.isEditable else { return super.insertNewline(sender) }
        
        // insert newline
        self.insertText(self.lineEnding.string, replacementRange: self.rangeForUserTextChange)
        
        // apply auto indentation
        if self.isAutomaticIndentEnabled {
            self.smartIndent()
        }
    }
    
    
    override func deleteBackward(_ sender: Any?) {
        
        guard self.isEditable else { return super.deleteBackward(sender) }
        
        if self.multipleDelete() { return }
        
        // delete tab
        if self.isAutomaticTabExpansionEnabled,
           let deletionRange = self.string.rangeForSoftTabDeletion(in: self.rangeForUserTextChange, tabWidth: self.tabWidth)
        {
            self.setSelectedRangesWithUndo(self.selectedRanges.map(\.rangeValue))
            self.selectedRange = deletionRange
        }
        
        // balance brackets
        if self.isAutomaticSymbolBalancingEnabled,
           self.rangeForUserTextChange.isEmpty,
           let lastCharacter = self.string.character(before: self.rangeForUserTextChange),
           let nextCharacter = self.string.character(after: self.rangeForUserTextChange),
           self.matchingSymbolPairs.contains(where: { $0.begin == Character(lastCharacter) && $0.end == Character(nextCharacter) })
        {
            self.setSelectedRangesWithUndo(self.selectedRanges.map(\.rangeValue))
            self.selectedRange = NSRange(location: self.rangeForUserTextChange.location - 1, length: 2)
        }
        
        super.deleteBackward(sender)
    }
    
    
    override func cut(_ sender: Any?) {
        
        let insertionRanges = self.insertionRanges
        self.setSelectedRangesWithUndo(insertionRanges)
        
        super.cut(sender)
        
        guard insertionRanges.count > 1 else { return }
        
        // keep insertion points after cut
        let ranges = insertionRanges.enumerated()
            .map { insertionRanges[..<$0.offset].reduce(into: $0.element.location) { $0 -= $1.length } }
            .map { NSRange(location: $0, length: 0) }
        
        guard let set = self.prepareForSelectionUpdate(ranges) else { return }
        
        self.selectedRanges = set.selectedRanges
        self.insertionLocations = set.insertionLocations
    }
    
    
    override func paste(_ sender: Any?) {
        
        let pboard = NSPasteboard.general
        let document = self.textStorage.flatMap { self.documentViewController?.document(for: $0) }
        let docURL = document?.fileURL
        let rendersPlainTextImages = (self.layoutManager as? LayoutManager)?.rendersPlainTextInlineImages == true
        let isMarkdown = (document?.syntaxName == "Markdown")
        
        if (rendersPlainTextImages || isMarkdown),
           let image = PlainTextInlineImageStore.shared.extractImage(from: pboard),
           let stored = PlainTextInlineImageStore.shared.store(image: image, for: docURL)
        {
            let insertionText = rendersPlainTextImages ? stored.token : "![image](.cot-assets/\(stored.fileURL.lastPathComponent))"
            let range = self.selectedRange()
            if self.shouldChangeText(in: range, replacementString: insertionText) {
                self.replaceCharacters(in: range, with: insertionText)
                self.didChangeText()
            } else {
                self.insertText(insertionText, replacementRange: range)
            }
            self.layoutManager?.invalidateLayout(forCharacterRange: self.string.range, actualCharacterRange: nil)
            self.scrollRangeToVisible(self.selectedRange())
            self.needsDisplay = true
            return
        }
        
        super.paste(sender)
    }
    
    
    override func handleTextCheckingResults(_ results: [NSTextCheckingResult], forRange range: NSRange, types checkingTypes: NSTextCheckingTypes, options: [NSSpellChecker.OptionKey: Any] = [:], orthography: NSOrthography, wordCount: Int) {
        
        let selectedRange = self.selectedRange
        
        super.handleTextCheckingResults(results, forRange: range, types: checkingTypes, options: options, orthography: orthography, wordCount: wordCount)
        
        // move the cursor back into the middle of quotes if the paired closing quote was automatically inserted,
        // because the cursor is automatically moved after the close quote by this method (#1384)
        // -> Verify the movement to preserve user input made before this asynchronous callback.
        if self.isTypingPairedQuotes,
           self.isAutomaticQuoteSubstitutionEnabled,
           selectedRange.isEmpty,
           self.selectedRange.isEmpty,
           self.selectedRange.location == selectedRange.location + 1,
           results.contains(where: { $0.resultType.contains(.quote) && $0.range.upperBound == self.selectedRange.location })
        {
            self.selectedRange.location -= 1
        }
        self.isTypingPairedQuotes = false
    }
    
    
    override var selectedRanges: [NSValue] {
        
        willSet {
            // keep only empty ranges that super may discard for subsequent multi-cursor editing
            // -> The ranges received by `setSelectedRanges(_:affinity:stillSelecting:)` are already sanitized in the NSTextView manner.
            self.insertionLocations = newValue
                .map(\.rangeValue)
                .filter(\.isEmpty)
                .map(\.location)
        }
    }
    
    
    /// Changes selections.
    ///
    /// - Note: Update `insertionLocations` manually when you use this method.
    override func setSelectedRanges(_ ranges: [NSValue], affinity: NSSelectionAffinity, stillSelecting stillSelectingFlag: Bool) {
        
        var ranges = ranges
        
        // interrupt rectangular selection
        if self.isPerformingRectangularSelection {
            if let locations = self.insertionLocations(from: self.mouseDownPoint, candidates: ranges, affinity: affinity) {
                ranges = [NSRange(location: locations[0], length: 0)] as [NSValue]
                self.insertionLocations = Array(locations[1...])
            } else {
                // avoid putting range boundaries across CRLF (2025-12, macOS 26.2, #2000)
                ranges = ranges
                    .map(\.rangeValue)
                    .map((self.string as NSString).safeEndingRange(for:)) as [NSValue]
                self.insertionLocations = []
            }
        }
        
        let currentRanges = self.rangesForUserTextChange ?? self.selectedRanges
        
        super.setSelectedRanges(ranges, affinity: affinity, stillSelecting: stillSelectingFlag)
        
        // remove official selectedRanges from the sub insertion points
        let selectedRanges = self.selectedRanges.map(\.rangeValue)
        self.insertionLocations.removeAll { location in selectedRanges.contains { $0.touches(location) } }
        
        if !self.hasMultipleInsertions {
            let selectedRange = self.selectedRange
            let keepsOrigin = !selectedRange.isEmpty
                && self.selectionOrigins.count == 1
                && self.selectionOrigins.contains { $0 == selectedRange.lowerBound || $0 == selectedRange.upperBound }
            
            // update the selection origin
            // -> Record the origin also in the still-selecting state when the selection is empty
            //    (namely, at a drag start), and keep it as long as it stays at either bound
            //    so that the anchor of a selection made backward remains at the upper bound.
            if !keepsOrigin, selectedRange.isEmpty || !stillSelectingFlag {
                self.selectionOrigins = [selectedRange.location]
            }
        }
        
        self.needsUpdateLineHighlight = true
        
        // invalidate current instance highlights
        if self.highlightsSelectionInstance {
            self.instanceHighlightTask?.cancel()
            if let layoutManager = self.layoutManager, layoutManager.hasTemporaryAttribute(.roundedBackgroundColor) {
                layoutManager.removeTemporaryAttribute(.roundedBackgroundColor, forCharacterRange: self.string.range)
            }
        }
        
        if !stillSelectingFlag, !self.isShowingCompletion {
            // highlight matching symbol
            if self.highlightsBraces {
                self.highlightMatchingSymbol(candidates: SymbolPair.braces)
            }
            
            // update instance highlights
            if self.highlightsSelectionInstance {
                let delay: Duration = .seconds(self.selectionInstanceHighlightDelay)
                self.instanceHighlightTask?.cancel()
                self.instanceHighlightTask = Task { [weak self] in
                    try await Task.sleep(for: delay, tolerance: delay * 0.2)  // debounce
                    try await self?.highlightInstances()
                }
            }
        }
        
        // send notification on the next run loop
        // -> `self.selectedRange` may not be updated yet at this timing.
        DispatchQueue.main.async { [weak self] in
            guard self?.rangesForUserTextChange ?? self?.selectedRanges != currentRanges else { return }
            NotificationCenter.default.post(name: DidLiveChangeSelectionMessage.name, object: self)
        }
    }
    
    
    /// Sets a single selection.
    override func setSelectedRange(_ charRange: NSRange, affinity: NSSelectionAffinity, stillSelecting stillSelectingFlag: Bool) {
        
        self.insertionLocations.removeAll()
        
        super.setSelectedRange(charRange, affinity: affinity, stillSelecting: stillSelectingFlag)
    }
    
    
    override func selectionRange(forProposedRange proposedCharRange: NSRange, granularity: NSSelectionGranularity) -> NSRange {
        
        guard granularity == .selectByWord else {
            return super.selectionRange(forProposedRange: proposedCharRange, granularity: granularity)
        }
        
        // treat additional specific characters as separator (see `wordRange(at:)` for details)
        var wordRange = self.wordRange(at: proposedCharRange.location)
        if proposedCharRange.length > 1 {
            wordRange.formUnion(self.wordRange(at: proposedCharRange.upperBound - 1))
        }
        
        guard
            proposedCharRange.isEmpty,  // not on expanding selection
            wordRange.length == 1  // clicked character can be a symbol
        else { return wordRange }
        
        let characterIndex = String.Index(utf16Offset: wordRange.lowerBound, in: self.string)
        let clickedCharacter = self.string[characterIndex]
        
        // select (syntax-highlighted) quoted text
        if ["\"", "'", "`"].contains(clickedCharacter),
           let syntaxRange = self.layoutManager?.effectiveRange(of: .syntaxType, at: wordRange.location)
        {
            let syntaxCharacterRange = Range(syntaxRange, in: self.string)!
            let firstSyntaxIndex = syntaxCharacterRange.lowerBound
            let lastSyntaxIndex = self.string.index(before: syntaxCharacterRange.upperBound)
            
            if (firstSyntaxIndex == characterIndex && self.string[firstSyntaxIndex] == clickedCharacter) ||  // begin quote
                (lastSyntaxIndex == characterIndex && self.string[lastSyntaxIndex] == clickedCharacter)  // end quote
            {
                return syntaxRange
            }
        }
        if let quoteRange = self.string.rangeOfQuotePair(at: characterIndex, candidates: self.quotePairRules) {
            return NSRange(quoteRange, in: self.string)
        }
        
        // select inside of brackets
        if let pairRange = self.string.rangeOfSymbolPair(at: characterIndex, candidates: SymbolPair.braces + [.ltgt]) {
            return NSRange(pairRange, in: self.string)
        }
        
        return wordRange
    }
    
    
    override func menu(for event: NSEvent) -> NSMenu? {
        
        // AppKit asks the view whether it can offer auto-fill and services while it prepares
        // a context menu, and inserts those items into the menu it is about to show. The
        // window goes through that preparation right here, before the menu opens, so both
        // questions are answered with “no” for the length of the preparation.
        self.isPreparingContextMenu = true
        
        let menu = self.makeContextMenu()
        menu.delegate = self
        
        // Safety net for a menu AppKit builds but never shows: the flag would otherwise keep
        // the input context switched off. All the questions this suppresses are asked before
        // the main queue gets a turn, so this can only clear the flag too late, never too early.
        DispatchQueue.main.async { [weak self] in
            self?.isPreparingContextMenu = false
        }
        
        return menu
    }
    
    
    /// Builds the text view's context menu.
    ///
    /// The system's look-up, translate, share, spelling, substitution, auto-fill and
    /// services items are deliberately absent: the menu carries only what this editor
    /// actually offers — copy / paste / select all and the highlight colors.
    func makeContextMenu() -> NSMenu {
        
        let menu = NSMenu()
        // The menu manages its own enabled states below; AppKit's responder-chain
        // auto-validation would otherwise leave the standard items unusable whenever the
        // menu is opened without a focused text view.
        menu.autoenablesItems = false
        
        let hasSelection = !self.selectedRange().isEmpty
        
        // AI actions on the selection. They need a selection; when the AI is not configured
        // yet the action explains that instead of failing silently.
        if let documentViewController = self.documentViewController {
            let aiActions: [(action: AIAction, selector: Selector)] = [
                (.translate, #selector(DocumentViewController.translateSelection(_:))),
                (.summarize, #selector(DocumentViewController.summarizeSelection(_:))),
                (.explain, #selector(DocumentViewController.explainSelection(_:))),
                (.weeklyReport, #selector(DocumentViewController.generateWeeklyReport(_:))),
                (.weeklyReportItem, #selector(DocumentViewController.generateWeeklyReportItem(_:))),
            ]
            for (action, selector) in aiActions {
                let item = NSMenuItem(title: action.title, action: selector, keyEquivalent: "")
                item.target = documentViewController
                item.isEnabled = hasSelection || (action == .weeklyReport && !self.string.isEmpty)
                menu.addItem(item)
            }
            
            let alignTableItem = NSMenuItem(
                title: String(localized: "chrome.contextMenu.alignTable", defaultValue: "Align Markdown Table", table: "Chrome"),
                action: #selector(DocumentViewController.alignMarkdownTable(_:)),
                keyEquivalent: ""
            )
            alignTableItem.target = documentViewController
            alignTableItem.isEnabled = !self.string.isEmpty
            menu.addItem(alignTableItem)
            
            let chartItem = NSMenuItem(
                title: AIAction.interactiveChart.title,
                action: #selector(DocumentViewController.generateInteractiveChart(_:)),
                keyEquivalent: ""
            )
            chartItem.target = documentViewController
            chartItem.isEnabled = hasSelection || MarkdownTableFormatter.containsMarkdownTable(self.string)
            menu.addItem(chartItem)
            
            let ocrItem = NSMenuItem(
                title: AIAction.ocrPolish.title,
                action: #selector(DocumentViewController.runOCRAndAI(_:)),
                keyEquivalent: ""
            )
            ocrItem.target = documentViewController
            ocrItem.isEnabled = true
            menu.addItem(ocrItem)
            
            let organizeItem = NSMenuItem(
                title: AIAction.organizeAndMerge.title,
                action: #selector(DocumentViewController.organizeAndMergeAllDocuments(_:)),
                keyEquivalent: ""
            )
            organizeItem.target = documentViewController
            organizeItem.isEnabled = true
            menu.addItem(organizeItem)
            
            if (self.layoutManager as? LayoutManager)?.rendersPlainTextInlineImages == true {
                let insertImageItem = NSMenuItem(
                    title: String(localized: "chrome.contextMenu.insertInlineImage", defaultValue: "Insert Image (Plain Text)…", table: "Chrome"),
                    action: #selector(DocumentViewController.insertPlainTextImage(_:)),
                    keyEquivalent: ""
                )
                insertImageItem.target = documentViewController
                insertImageItem.isEnabled = self.isEditable
                menu.addItem(insertImageItem)
            }
            
            menu.addItem(.separator())
        }
        
        let copyItem = NSMenuItem(title: String(localized: "chrome.contextMenu.copy",
                                                defaultValue: "Copy", table: "Chrome"),
                                  action: #selector(copy(_:)), keyEquivalent: "c")
        copyItem.keyEquivalentModifierMask = .command
        copyItem.isEnabled = hasSelection
        menu.addItem(copyItem)
        
        let pasteItem = NSMenuItem(title: String(localized: "chrome.contextMenu.paste",
                                                 defaultValue: "Paste", table: "Chrome"),
                                   action: #selector(paste(_:)), keyEquivalent: "v")
        pasteItem.keyEquivalentModifierMask = .command
        pasteItem.isEnabled = NSPasteboard.general.string(forType: .string) != nil
            || PlainTextInlineImageStore.shared.extractImage(from: NSPasteboard.general) != nil
        menu.addItem(pasteItem)
        
        let selectAllItem = NSMenuItem(title: String(localized: "chrome.contextMenu.selectAll",
                                                     defaultValue: "Select All", table: "Chrome"),
                                       action: #selector(selectAll(_:)), keyEquivalent: "a")
        selectAllItem.keyEquivalentModifierMask = .command
        selectAllItem.isEnabled = !self.string.isEmpty
        menu.addItem(selectAllItem)
        
        if let documentViewController = self.documentViewController, hasSelection {
            menu.addItem(.separator())
            
            // The five colors are direct menu items, not a submenu: one click paints.
            for (index, color) in HighlightColor.allCases.enumerated() {
                let item = NSMenuItem(title: color.localizedName,
                                      action: #selector(DocumentViewController.applyHighlight(_:)),
                                      keyEquivalent: "")
                item.tag = index
                item.target = documentViewController
                item.image = Self.swatchImage(for: color)
                menu.addItem(item)
            }
            
            menu.addItem(.separator())
            
            let clearItem = NSMenuItem(title: String(localized: "chrome.contextMenu.clearHighlight",
                                                     defaultValue: "Clear Highlight", table: "Chrome"),
                                       action: #selector(DocumentViewController.removeHighlight(_:)),
                                       keyEquivalent: "")
            clearItem.target = documentViewController
            menu.addItem(clearItem)
        }
        
        return menu
    }
    
    
    /// Draws a small round swatch for a highlight color menu item.
    ///
    /// - Parameter color: The color to draw.
    /// - Returns: A non-template image so the menu keeps the color.
    private static func swatchImage(for color: HighlightColor) -> NSImage {
        
        let size = NSSize(width: 12, height: 12)
        let image = NSImage(size: size, flipped: false) { rect in
            color.swatchColor.setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1)).fill()
            return true
        }
        image.isTemplate = false
        
        return image
    }
    
    
    /// The editor pane view controller owning this text view, found through the responder chain.
    private var editorViewController: EditorViewController? {
        
        var responder: NSResponder? = self
        while let current = responder {
            if let pane = current as? EditorViewController {
                return pane
            }
            responder = current.nextResponder
        }
        return nil
    }
    
    
    /// The document view controller this text view belongs to, found through the responder chain.
    private var documentViewController: DocumentViewController? {
        
        var responder: NSResponder? = self
        
        while let current = responder {
            if let viewController = current as? DocumentViewController {
                return viewController
            }
            responder = current.nextResponder
        }
        
        return nil
    }
    
    
    // MARK: Context Menu System Items
    
    /// Reports no input context while the context menu is being assembled.
    ///
    /// AppKit asks for the input context to decide whether to insert its *AutoFill* item, so
    /// answering `nil` for that moment keeps the item out of the menu. Typing is unaffected:
    /// the menu is built before it opens, and the flag is cleared again by then.
    override var inputContext: NSTextInputContext? {
        
        self.isPreparingContextMenu ? nil : super.inputContext
    }
    
    
    /// Reports no services requestor while the context menu is being assembled.
    ///
    /// AppKit asks for one to decide which services to list, so answering `nil` for that
    /// moment drops the promoted services and the *Services* submenu from the menu.
    override func validRequestor(
        forSendType sendType: NSPasteboard.PasteboardType?,
        returnType: NSPasteboard.PasteboardType?
    ) -> Any? {
        self.isPreparingContextMenu
            ? nil
            : super.validRequestor(forSendType: sendType, returnType: returnType)
    }
    
    
    override var typingAttributes: [NSAttributedString.Key: Any] {
        
        didSet {
            // -> The font can differ from the specified text font while typing marked text.
            guard self.hasMarkedText() != true else { return }
            
            (self.textContainer as? TextContainer)?.indentAttributes = typingAttributes
        }
    }
    
    
    override var font: NSFont? {
        
        get {
            // make sure to return the font defined by user
            (self.layoutManager as? LayoutManager)?.textFont ?? super.font
        }
        
        set {
            guard let font = newValue else { return }
            
            self.willChangeValue(for: \.font)
            defer {
                self.didChangeValue(for: \.font)
            }
            
            self.spaceWidth = font.width(of: " ")
            (self.textContainer as? TextContainer)?.spaceWidth = self.spaceWidth
            
            if let textStorage {
                if font.isFixedPitch {
                    textStorage.addAttribute(.kern, value: 0, range: textStorage.range)
                } else {
                    textStorage.removeAttribute(.kern, range: textStorage.range)
                }
            }
            self.typingAttributes[.kern] = font.isFixedPitch ? 0 : nil
            
            // let LayoutManager keep the set font to avoid an inconsistent line height
            // -> Because NSTextView's .font returns the font used for the first character of .string when it exists,
            //    not the font defined by user but a fallback font is returned through this property
            //    when the set font doesn't have a glyph for the first character.
            (self.layoutManager as? LayoutManager)?.textFont = font
            
            self.invalidateDefaultParagraphStyle()
            self.needsUpdateLineHighlight = true
            self.needsUpdateInsertionIndicators = true
            
            // set to the super after updating textStorage attributes in `.invalidateDefaultParagraphStyle()`
            // to avoid the strange issue that letters change into undefined after specific characters.
            // Change the font in characters.md to reproduce this issue (2022-05, macOS 12)
            super.font = font
            self.typingAttributes[.font] = font
        }
    }
    
    
    override func changeFont(_ sender: Any?) {
        
        guard
            let fontManager = sender as? NSFontManager,
            let currentFont = self.font,
            let textStorage = self.textStorage
        else { return assertionFailure() }
        
        let font = fontManager.convert(currentFont)
        
        // apply to all text views sharing the same textStorage
        for textView in textStorage.layoutManagers.compactMap(\.firstTextView) {
            textView.font = font
        }
    }
    
    
    override func viewWillDraw() {
        
        super.viewWillDraw()
        
        if self.needsUpdateInsertionIndicators {
            self.updateInsertionIndicators()
            self.needsUpdateInsertionIndicators = false
        }
    }
    
    
    override func drawBackground(in rect: NSRect) {
        
        super.drawBackground(in: rect)
        
        guard let range = self.range(for: rect) else { return }
        
        if self.highlightsCurrentLines {
            self.drawCurrentLine(range: range, in: rect)
        }
        
        self.drawRoundedBackground(range: range, in: rect)
    }
    
    
    override func draw(_ dirtyRect: NSRect) {
        
        super.draw(dirtyRect)
        
        // draw page guide
        if self.showsPageGuide {
            let column = CGFloat(self.pageGuideColumn)
            let inset = self.textContainerInset.width
            let linePadding = self.textContainer?.lineFragmentPadding ?? 0
            let x = self.spaceWidth * column + inset + linePadding + 2  // +2 px for an esthetic adjustment
            let isRTL = (self.baseWritingDirection == .rightToLeft)
            
            let guideRect = NSRect(x: isRTL ? self.bounds.width - x : x,
                                   y: dirtyRect.minY,
                                   width: 1.0,
                                   height: dirtyRect.height)
            
            if guideRect.intersects(dirtyRect), let textColor = self.theme?.text.color {
                let isHighContrast = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
                let guideColor = textColor.withAlphaComponent(isHighContrast ? 0.5 : 0.2)
                
                NSGraphicsContext.saveGraphicsState()
                guideColor.setFill()
                self.centerScanRect(guideRect).intersection(dirtyRect).fill()
                NSGraphicsContext.restoreGraphicsState()
            }
        }
        
        // In visual mode the selection replaces the caret, so draw the cursor block
        // ourselves at the active end using the same unified cursor color/shape.
        if
            UserDefaults.standard[.vimMode],
            VimState.shared.mode == .visual,
            VimState.shared.visualOwnerID == ObjectIdentifier(self),
            let location = VimState.shared.visualActiveLocation,
            let rect = self.vimCursorRect(at: location)
        {
            NSGraphicsContext.saveGraphicsState()
            self.effectiveCursorColor.withAlphaComponent(0.65).setFill()
            let drawRect = self.centerScanRect(rect).intersection(dirtyRect)
            if !drawRect.isEmpty {
                NSBezierPath(roundedRect: drawRect, xRadius: 1.5, yRadius: 1.5).fill()
            }
            NSGraphicsContext.restoreGraphicsState()
        }
        
        // Draw Plain Text inline image cards below lines containing `⟦🖼 ...⟧` tokens
        if (self.layoutManager as? LayoutManager)?.rendersPlainTextInlineImages == true {
            self.drawPlainTextInlineImages(in: dirtyRect)
        } else {
            self.inlineImageCardEntries.removeAll()
        }
    }
    
    
    /// Renders inline image preview cards inside Plain Text documents for `⟦🖼 filename⟧` tokens.
    private func drawPlainTextInlineImages(in dirtyRect: NSRect) {
        
        self.inlineImageCardEntries.removeAll()
        
        guard
            let layoutManager = self.layoutManager as? LayoutManager,
            let textContainer = self.textContainer,
            let visibleCharRange = self.range(for: dirtyRect, withoutAdditionalLayout: true)
        else { return }
        
        let nsString = self.string as NSString
        let expandedRange = nsString.lineRange(for: visibleCharRange)
        let tokens = PlainTextInlineImageStore.shared.findTokens(in: nsString, range: expandedRange)
        guard !tokens.isEmpty else { return }
        
        let docURL = self.textStorage.flatMap { self.documentViewController?.document(for: $0)?.fileURL }
        let singleLineHeight = layoutManager.lineHeight
        
        for token in tokens {
            guard let image = PlainTextInlineImageStore.shared.image(for: token.identifier, documentURL: docURL) else { continue }
            
            let glyphIndex = layoutManager.glyphIndexForCharacter(at: token.range.location)
            guard layoutManager.isValidGlyphIndex(glyphIndex) else { continue }
            
            let fragmentRect = layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: nil, withoutAdditionalLayout: true)
            let tokenBounding = layoutManager.boundingRect(
                forGlyphRange: layoutManager.glyphRange(forCharacterRange: token.range, actualCharacterRange: nil),
                in: textContainer
            )
            
            let cardTopY = fragmentRect.minY + self.textContainerOrigin.y + singleLineHeight + 4
            let cardX = max(self.textContainerOrigin.x + 8, tokenBounding.minX + self.textContainerOrigin.x)
            let availableWidth = max(160, self.bounds.width - cardX - 24)
            let maxCardWidth: CGFloat = min(440, availableWidth)
            let maxCardHeight: CGFloat = 210
            
            guard let cardSize = PlainTextInlineImageStore.shared.cardSize(
                for: token.identifier,
                documentURL: docURL,
                maxImageWidth: maxCardWidth,
                maxImageHeight: maxCardHeight
            ) else { continue }
            
            let cardRect = NSRect(x: cardX, y: cardTopY, width: cardSize.width, height: cardSize.height)
            self.inlineImageCardEntries.append((rect: cardRect, identifier: token.identifier, tokenRange: token.range))
            guard cardRect.intersects(dirtyRect) else { continue }
            
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current?.imageInterpolation = .high
            let cardPath = NSBezierPath(roundedRect: cardRect, xRadius: 8, yRadius: 8)
            NSColor.controlBackgroundColor.withAlphaComponent(0.94).setFill()
            cardPath.fill()
            NSColor.separatorColor.withAlphaComponent(0.85).setStroke()
            cardPath.lineWidth = 1
            cardPath.stroke()
            
            let imageRect = cardRect.insetBy(dx: 6, dy: 6)
            let clipPath = NSBezierPath(roundedRect: imageRect, xRadius: 5, yRadius: 5)
            clipPath.addClip()
            image.draw(in: imageRect,
                       from: NSRect(origin: .zero, size: image.size),
                       operation: .sourceOver,
                       fraction: 1.0,
                       respectFlipped: true,
                       hints: nil)
            NSGraphicsContext.restoreGraphicsState()
        }
    }
    
    
    /// Opens an interactive preview popover when clicking an inline image card.
    private func presentInlineImagePopover(for entry: (rect: NSRect, identifier: String, tokenRange: NSRange)) {
        
        self.imagePreviewPopover?.performClose(nil)
        
        let docURL = self.textStorage.flatMap { self.documentViewController?.document(for: $0)?.fileURL }
        guard let image = PlainTextInlineImageStore.shared.image(for: entry.identifier, documentURL: docURL) else { return }
        let fileURL = PlainTextInlineImageStore.shared.imageURL(for: entry.identifier, documentURL: docURL)
        
        let popover = NSPopover()
        popover.behavior = .transient
        
        let contentView = InlineImagePreviewPopoverView(
            image: image,
            filename: entry.identifier,
            fileURL: fileURL,
            onCopyImage: { [weak popover] in
                let pboard = NSPasteboard.general
                pboard.clearContents()
                pboard.writeObjects([image])
                popover?.performClose(nil)
            },
            onRunOCR: { [weak self, weak popover] in
                popover?.performClose(nil)
                guard let self, let window = self.window else { return }
                self.documentViewController?.processOCR(image: image, on: window)
            },
            onRevealInFinder: { [weak popover] in
                if let fileURL {
                    NSWorkspace.shared.activateFileViewerSelecting([fileURL])
                }
                popover?.performClose(nil)
            },
            onDeleteToken: { [weak self, weak popover] in
                popover?.performClose(nil)
                guard let self else { return }
                let nsLen = (self.string as NSString).length
                if NSMaxRange(entry.tokenRange) <= nsLen,
                   self.shouldChangeText(in: entry.tokenRange, replacementString: "")
                {
                    self.replaceCharacters(in: entry.tokenRange, with: "")
                    self.didChangeText()
                }
            }
        )
        let hostingController = NSHostingController(rootView: contentView)
        hostingController.view.frame.size = hostingController.view.intrinsicContentSize
        popover.contentViewController = hostingController
        self.imagePreviewPopover = popover
        popover.show(relativeTo: entry.rect, of: self, preferredEdge: .maxY)
    }
    
    
    /// The rectangle of the character at the given location, used for the Vim block cursor.
    func vimCursorRect(at location: Int) -> NSRect? {
        
        guard let layoutManager, let textContainer else { return nil }
        let string = self.string as NSString
        let length = string.length
        let lineH = self.singleLineHeight
        let fallbackSpace = self.spaceWidth > 0 ? self.spaceWidth : 8
        
        guard length > 0 else {
            var extra = layoutManager.extraLineFragmentUsedRect
            if extra.isEmpty {
                extra = NSRect(x: 0, y: 0, width: fallbackSpace, height: lineH)
            }
            return NSRect(
                x: extra.minX + self.textContainerOrigin.x,
                y: extra.minY + self.textContainerOrigin.y,
                width: fallbackSpace,
                height: min(extra.height, lineH)
            )
        }
        
        let clampedLoc = min(max(0, location), length)
        if clampedLoc == length, string.character(at: length - 1) == 10 {
            let extra = layoutManager.extraLineFragmentUsedRect
            if !extra.isEmpty {
                return NSRect(
                    x: extra.minX + self.textContainerOrigin.x,
                    y: extra.minY + self.textContainerOrigin.y,
                    width: fallbackSpace,
                    height: min(extra.height > 0 ? extra.height : lineH, lineH)
                )
            }
        }
        
        let index = min(clampedLoc, length - 1)
        let charRange = NSRange(location: index, length: 1)
        layoutManager.ensureLayout(forCharacterRange: charRange)
        let glyphRange = layoutManager.glyphRange(forCharacterRange: charRange, actualCharacterRange: nil)
        guard glyphRange.location != NSNotFound else { return nil }
        
        var rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
        rect.origin.x += self.textContainerOrigin.x
        rect.origin.y += self.textContainerOrigin.y
        
        let character = string.substring(with: charRange)
        let isLineBreak = (character == "\n" || character == "\r")
        
        if isLineBreak {
            let usedRect = layoutManager.lineFragmentUsedRect(forGlyphAt: glyphRange.location, effectiveRange: nil)
            rect.origin.x = usedRect.maxX + self.textContainerOrigin.x
            rect.origin.y = usedRect.minY + self.textContainerOrigin.y
            rect.size = NSSize(width: fallbackSpace, height: min(usedRect.height > 0 ? usedRect.height : lineH, lineH))
        } else {
            if clampedLoc == length {
                rect.origin.x = rect.maxX
                rect.size.width = fallbackSpace
            } else if rect.width < 2 {
                rect.size.width = fallbackSpace
            }
            rect.size.height = min(rect.height > 0 ? rect.height : lineH, lineH)
        }
        
        return rect
    }
    
    
    override func scrollRangeToVisible(_ range: NSRange) {
        
        // scroll line by line if an arrow key is pressed
        // -> Perform only when the scroll target is nearby the visible area.
        //    Otherwise, the scroll doesn't reach the bottom with command+down arrow
        //    in the noncontiguous layout mode. (2018-12, macOS 10.14)
        guard NSEvent.modifierFlags.contains(.numericPad),
              range.upperBound < self.string.length,  // workaround for Command+Down arrow
              let rect = self.boundingRect(for: range)
        else { return super.scrollRangeToVisible(range) }
        
        super.scrollToVisible(rect)  // move minimum distance
    }
    
    
    override func setLayoutOrientation(_ orientation: NSLayoutManager.TextLayoutOrientation) {
        
        let didChange = orientation != self.layoutOrientation
        
        // -> Need to send KVO notification manually on Swift. (2016-09, macOS 10.12)
        self.willChangeValue(for: \.layoutOrientation)
        super.setLayoutOrientation(orientation)
        self.didChangeValue(for: \.layoutOrientation)
        
        guard didChange else { return }
        
        self.invalidateNonContiguousLayout()
        
        // reset writing direction
        if orientation == .vertical {
            self.baseWritingDirection = .leftToRight
        }
        
        // reset text wrapping width
        if self.wrapsLines {
            let keyPath = (orientation == .vertical) ? \NSSize.height : \NSSize.width
            self.frame.size[keyPath: keyPath] = self.visibleRect.width * self.scale
        }
        
        // update keyboard shortcuts
        NSApp.mainMenu?.updateAll()
    }
    
    
    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        
        if self.isDraggingPaneTab(sender.draggingPasteboard),
           let pane = self.editorViewController
        {
            return pane.paneDragEntered(sender, in: self)
        }
        return super.draggingEntered(sender)
    }
    
    
    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        
        if self.isDraggingPaneTab(sender.draggingPasteboard),
           let pane = self.editorViewController
        {
            return pane.paneDragUpdated(sender, in: self)
        }
        return super.draggingUpdated(sender)
    }
    
    
    override func draggingExited(_ sender: (any NSDraggingInfo)?) {
        
        if let sender, self.isDraggingPaneTab(sender.draggingPasteboard),
           let pane = self.editorViewController
        {
            pane.paneDragExited(sender)
            return
        }
        super.draggingExited(sender)
    }
    
    
    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        
        if self.isDraggingPaneTab(sender.draggingPasteboard),
           let pane = self.editorViewController
        {
            return pane.panePerformDragOperation(sender, in: self)
        }
        return super.performDragOperation(sender)
    }
    
    
    private func isDraggingPaneTab(_ pboard: NSPasteboard) -> Bool {
        
        if pboard.types?.contains(PaneTab.dragPasteboardType) == true {
            return true
        }
        if let raw = pboard.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines),
           raw.hasPrefix(PaneTab.dragPrefix)
        {
            return true
        }
        return false
    }
    
    
    /// Reads the pasted/dropped item from NSPasteboard (invoked in `performDragOperation(_:)`).
    override func readSelection(from pboard: NSPasteboard, type: NSPasteboard.PasteboardType) -> Bool {
        
        // on pane tab drop across panes or windows
        if pboard.name == .drag,
           let raw = (pboard.string(forType: PaneTab.dragPasteboardType) ?? pboard.string(forType: .string))?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           let tabID = PaneTab.tabID(from: raw),
           let documentViewController = self.documentViewController
        {
            _ = documentViewController.handleDroppedTab(id: tabID, ontoTextView: self)
            return true
        }
        
        // on file drop
        if pboard.name == .drag,
           let urls = pboard.readObjects(forClasses: [NSURL.self]) as? [URL],
           (self.delegate as? any Delegate)?.editorTextView(self, readDroppedURLs: urls) == true
        {
            return true
        }
        
        // paste a single string to all insertion points
        if pboard.name == .general,
           pboard.types?.contains(.multipleTextSelection) == false,
           let string = pboard.string(forType: .string),
           let ranges = self.rangesForUserTextChange?.map(\.rangeValue),
           ranges.count > 1,
           string.rangeOfCharacter(from: .newlines) == nil
        {
            return self.insertText(string, replacementRanges: ranges)
        }
        
        // keep multiple cursors after pasting multiple text
        if pboard.name == .general,
           let groupCounts = pboard.propertyList(forType: .multipleTextSelection) as? [Int],
           let string = pboard.string(forType: .string),
           let ranges = self.rangesForUserTextChange?.map(\.rangeValue),
           ranges.count > 1
        {
            let lines = string.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
            
            // ignore malformed multiple-selection metadata from the pasteboard
            guard groupCounts.allSatisfy({ 0 < $0 && $0 <= lines.count }) else {
                return super.readSelection(from: pboard, type: type)
            }
            
            let groupRanges: [Range<Int>] = groupCounts
                .reduce(into: [Range<Int>]()) { groupRanges, groupCount in
                    let location = groupRanges.last?.upperBound ?? 0
                    if groupRanges.count >= ranges.count, let last = groupRanges.last {
                        groupRanges[groupRanges.endIndex - 1] = last.lowerBound..<(last.upperBound + groupCount)
                    } else {
                        groupRanges.append(location..<(location + groupCount))
                    }
                }
            
            guard groupRanges.last?.upperBound == lines.endIndex else {
                return super.readSelection(from: pboard, type: type)
            }
            
            let multipleTexts: [String] = groupRanges
                .map { lines[$0].joined(separator: self.lineEnding.string) }
            let blanks = [String](repeating: "", count: ranges.count - multipleTexts.count)
            let strings = multipleTexts + blanks
            
            if self.replace(with: strings, ranges: ranges, selectedRanges: nil) { return true }
        }
        
        return super.readSelection(from: pboard, type: type)
    }
    
    
    override var baseWritingDirection: NSWritingDirection {
        
        willSet {
            self.willChangeValue(for: \.baseWritingDirection)
        }
        
        didSet {
            self.didChangeValue(for: \.baseWritingDirection)
            
            guard baseWritingDirection != oldValue else { return }
            
            // update textContainer size (see comment in NSTextView.infiniteSize)
            if !self.wrapsLines {
                self.textContainer?.size = self.infiniteSize
            }
            
            self.needsUpdateInsertionIndicators = true
        }
    }
    
    
    // MARK: Protocol
    
    override func validateUserInterfaceItem(_ item: any NSValidatedUserInterfaceItem) -> Bool {
        
        switch item.action {
            case #selector(paste):
                let rendersPlainText = (self.layoutManager as? LayoutManager)?.rendersPlainTextInlineImages == true
                let isMarkdown = self.textStorage.flatMap { self.documentViewController?.document(for: $0)?.syntaxName } == "Markdown"
                if self.isEditable, (rendersPlainText || isMarkdown),
                   PlainTextInlineImageStore.shared.extractImage(from: NSPasteboard.general) != nil
                {
                    return true
                }
                
            case #selector(pasteAsIs),
                 #selector(shiftRight),
                 #selector(shiftLeft),
                 #selector(shift),
                 #selector(convertIndentationToSpaces),
                 #selector(convertIndentationToTabs),
                 #selector(moveLineUp),
                 #selector(moveLineDown),
                 #selector(sortLinesAscending),
                 #selector(reverseLines),
                 #selector(shuffleLines),
                 #selector(deleteDuplicateLine),
                 #selector(duplicateLine),
                 #selector(deleteLine),
                 #selector(joinLines),
                 #selector(trimTrailingWhitespace(_:)),
                 #selector(patternSort),
                 #selector(insertSnippet),
                 #selector(surroundSelectionWithSingleQuotes),
                 #selector(surroundSelectionWithDoubleQuotes),
                 #selector(surroundSelectionWithParentheses),
                 #selector(surroundSelectionWithBraces),
                 #selector(surroundSelectionWithSquareBrackets),
                 #selector(surroundSelection),
                 #selector(encodeURL),
                 #selector(decodeURL),
                 #selector(exchangeFullwidth),
                 #selector(exchangeHalfwidth),
                 #selector(exchangeFullwidthRoman),
                 #selector(exchangeHalfwidthRoman),
                 #selector(normalizeUnicode(_:)),
                 #selector(inputBackSlash),
                 #selector(inputYenMark):
                return self.isEditable
            
            case #selector(selectColumnUp):
                if let menuItem = item as? NSMenuItem {
                    switch self.layoutOrientation {
                        case .horizontal:
                            if menuItem.keyEquivalent == NSEvent.SpecialKey.rightArrow.string {
                                menuItem.keyEquivalent = NSEvent.SpecialKey.upArrow.string
                            }
                            menuItem.title = String(localized: "Select Column Up", table: "MainMenu")
                        case .vertical:
                            if menuItem.keyEquivalent == NSEvent.SpecialKey.upArrow.string {
                                menuItem.keyEquivalent = NSEvent.SpecialKey.rightArrow.string
                            }
                            menuItem.title = String(localized: "Select Column Right", table: "MainMenu",
                                                    comment: "vertical orientation version of the Select Column Up command")
                        @unknown default:
                            assertionFailure()
                    }
                }
                return self.isEditable
                
            case #selector(selectColumnDown):
                if let menuItem = item as? NSMenuItem {
                    switch self.layoutOrientation {
                        case .horizontal:
                            if menuItem.keyEquivalent == NSEvent.SpecialKey.leftArrow.string {
                                menuItem.keyEquivalent = NSEvent.SpecialKey.downArrow.string
                            }
                            menuItem.title = String(localized: "Select Column Down", table: "MainMenu")
                        case .vertical:
                            if menuItem.keyEquivalent == NSEvent.SpecialKey.downArrow.string {
                                menuItem.keyEquivalent = NSEvent.SpecialKey.leftArrow.string
                            }
                            menuItem.title = String(localized: "Select Column Left", table: "MainMenu",
                                                    comment: "vertical orientation version of the Select Column Down command")
                        @unknown default:
                            assertionFailure()
                    }
                }
                return self.isEditable
                
            case #selector(performTextFinderAction):
                guard let action = TextFinder.Action(rawValue: item.tag) else { return false }
                return self.textFinder.validateAction(action)
                
            case #selector(copyWithStyle):
                return !self.selectedRange.isEmpty
                
            case #selector(straightenQuotesInSelection):
                // -> Although `straightenQuotesInSelection(:_)` actually works also when selections are empty,
                //    disable it to make the state same as `replaceQuotesInSelection(_:)`.
                return self.isEditable && !self.selectedRange.isEmpty
                
            case #selector(toggleComment):
                (item as? NSMenuItem)?.title = self.canUncomment(partly: false)
                    ? String(localized: "Uncomment", table: "MainMenu")
                    : String(localized: "Comment Out", table: "MainMenu")
                return self.isEditable && (!self.commentDelimiters.inlines.isEmpty || !self.commentDelimiters.blocks.isEmpty)
            
            case #selector(commentOut):
                return self.isEditable
                
            case #selector(inlineCommentOut):
                return self.isEditable && !self.commentDelimiters.inlines.isEmpty
                
            case #selector(blockCommentOut):
                return self.isEditable && !self.commentDelimiters.blocks.isEmpty
                
            case #selector(uncomment(_:)):
                return self.isEditable && self.canUncomment(partly: true)
                
            default: break
        }
        
        return super.validateUserInterfaceItem(item)
    }
    
    
    // MARK: Public Accessors
    
    /// Tab width in number of spaces.
    var tabWidth: Int = 4 {
        
        didSet {
            tabWidth = max(1, tabWidth)
            (self.layoutManager as? LayoutManager)?.tabWidth = tabWidth
            
            guard tabWidth != oldValue else { return }
            
            self.invalidateRestorableState()
            self.invalidateDefaultParagraphStyle()
            self.needsUpdateLineHighlight = true
            self.needsUpdateInsertionIndicators = true
        }
    }
    
    
    /// The line height multiple.
    var lineHeight: Double = 1.2 {
        
        didSet {
            lineHeight = (lineHeight > 0) ? lineHeight : 1
            
            guard lineHeight != oldValue else { return }
            
            self.invalidateDefaultParagraphStyle()
            self.needsUpdateLineHighlight = true
            self.needsUpdateInsertionIndicators = true
        }
    }
    
    
    /// The shown invisible characters.
    var shownInvisibles: Set<Invisible> {
        
        get { (self.layoutManager as? LayoutManager)?.shownInvisibles ?? [] }
        set { (self.layoutManager as? LayoutManager)?.shownInvisibles = newValue }
    }
    
    
    /// Whether draws indent guides.
    var showsIndentGuides: Bool {
        
        get { (self.layoutManager as? LayoutManager)?.showsIndentGuides ?? false }
        set { (self.layoutManager as? LayoutManager)?.showsIndentGuides = newValue }
    }
    
    
    /// Whether enables the hanging indent.
    var isHangingIndentEnabled: Bool {
        
        get {
            (self.textContainer as? TextContainer)?.isHangingIndentEnabled ?? false
        }
        
        set {
            guard newValue != isHangingIndentEnabled else { return }
            (self.textContainer as? TextContainer)?.isHangingIndentEnabled = newValue
            self.setNeedsDisplay(self.visibleRect, avoidAdditionalLayout: true)
        }
    }
    
    
    /// The number of characters for hanging indent.
    var hangingIndentWidth: Int {
        
        get {
            (self.textContainer as? TextContainer)?.hangingIndentWidth ?? 0
        }
        
        set {
            guard newValue != hangingIndentWidth else { return }
            (self.textContainer as? TextContainer)?.hangingIndentWidth = newValue
            self.setNeedsDisplay(self.visibleRect, avoidAdditionalLayout: true)
        }
    }
    
    
    /// Whether text is antialiased.
    var usesAntialias: Bool {
        
        get {
            (self.layoutManager as? LayoutManager)?.usesAntialias ?? true
        }
        
        set {
            guard newValue != usesAntialias else { return }
            (self.layoutManager as? LayoutManager)?.usesAntialias = newValue
            self.setNeedsDisplay(self.visibleRect, avoidAdditionalLayout: true)
        }
    }
    
    
    /// Whether invisible characters are shown.
    var showsInvisibles: Bool {
        
        get {
            (self.layoutManager as? LayoutManager)?.showsInvisibles ?? false
        }
        
        set {
            (self.layoutManager as? LayoutManager)?.showsInvisibles = newValue
            self.needsUpdateInsertionIndicators = true
        }
    }
    
    
    /// Sets the font (font, antialiasing, and ligature) to the given font type.
    ///
    /// - Parameters:
    ///   - type: The font type to change.
    ///   - defaults: The user defaults to refer to settings.
    func setFont(type: FontType, defaults: UserDefaults = .standard) {
        
        self.fontObservers = [
            defaults.publisher(for: .fontKey(for: type), initial: true)
                .sink { [unowned self] _ in self.font = defaults.font(for: type) },
            defaults.publisher(for: .ligature(for: type), initial: true)
                .sink { [unowned self] in self.ligature = $0 ? .standard : .none },
            defaults.publisher(for: .antialias(for: type), initial: true)
                .sink { [unowned self] in self.usesAntialias = $0 },
        ]
    }
    
    
    // MARK: Action Messages
    
    /// Copies the selections with syntax highlight and font style.
    @IBAction func copyWithStyle(_ sender: Any?) {
        
        let selectedRanges = self.selectedRanges.map(\.rangeValue)
        
        guard !selectedRanges.allSatisfy(\.isEmpty) else { return NSSound.beep() }
        
        // substring all selected attributed strings
        let selections: [NSAttributedString] = selectedRanges
            .map { selectedRange in
                let plainText = (self.string as NSString).substring(with: selectedRange)
                let styledText = NSMutableAttributedString(string: plainText, attributes: self.typingAttributes)
                
                // apply syntax highlight that is set as temporary attributes in layout manager to attributed string
                self.layoutManager?.enumerateTemporaryAttribute(.foregroundColor, type: NSColor.self, in: selectedRange) { color, range, _ in
                    let localRange = range.shifted(by: -selectedRange.location)
                    
                    styledText.addAttribute(.foregroundColor, value: color, range: localRange)
                }
                
                return styledText
            }
        
        // prepare objects for rectangular selection
        let pasteboardString = selections.joined(separator: self.lineEnding.string)
        let propertyList = selections.map { $0.string.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).count }
        
        // set to paste board
        let pboard = NSPasteboard.general
        pboard.clearContents()
        pboard.declareTypes([.rtf] + self.writablePasteboardTypes, owner: nil)
        if pboard.canReadItem(withDataConformingToTypes: [NSPasteboard.PasteboardType.multipleTextSelection.rawValue]) {
            pboard.setPropertyList(propertyList, forType: .multipleTextSelection)
        }
        pboard.writeObjects([pasteboardString])
    }
    
    
    /// Pastes clipboard text without any modification.
    @IBAction func pasteAsIs(_ sender: Any?) {
        
        self.isApprovedTextChange = true
        
        super.pasteAsPlainText(sender)
        
        self.isApprovedTextChange = false
    }
    
    
    /// Selects the content of the enclosing paired symbols, such as brackets or quotation marks.
    @IBAction func selectEnclosingSymbols(_ sender: Any?) {
        
        guard
            let selectedRange = Range(self.selectedRange, in: self.string),
            let enclosingRange = self.string.rangeOfEnclosingSymbolPair(at: selectedRange, candidates: SymbolPair.braces + [.ltgt])
        else { return }
        
        self.selectedRange = NSRange(enclosingRange, in: self.string)
    }
    
    
    // MARK: Private Methods
    
    /// Updates single-character quote pairs from syntax delimiters.
    private func invalidateQuotePairs() {
        
        self.quotePairRules = self.quoteDelimiters
            .compactMap { delimiter in
                guard
                    delimiter.begin.count == 1,
                    delimiter.end.count == 1,
                    let begin = delimiter.begin.first,
                    let end = delimiter.end.first
                else { return nil }
                
                // sort prefixes by descending length for longest-match-first
                let prefixes = delimiter.prefixes?.sorted { $0.count > $1.count }
                
                return QuotePairRule(pair: .init(begin, end), escapeCharacter: delimiter.escapeCharacter, prefixes: prefixes ?? [])
            }
            .distinctForMatching
    }
    
    
    /// Updates colors and related appearance settings with the current theme.
    private func applyTheme() {
        
        assert(Thread.isMainThread)
        assert(self.layoutManager != nil)
        assert(self.enclosingScrollView != nil)
        
        guard let theme = self.theme else { return assertionFailure() }
        
        // -> Reduce the text color update as much as possible since it updates
        //    the color in the Color panel (2025-11, macOS 26.2)
        if self.textColor != theme.text.color {
            self.textColor = theme.text.color
            
            // workaround for a TextKit issue where textColor update can leave
            // LastResort fallback glyphs after emoji tag sequences (2026-05, macOS 26.4).
            if let font {
                self.textStorage?.addAttribute(.font, value: font, range: self.string.nsRange)
            }
            
        } else if self.typingAttributes[.foregroundColor] as? NSColor != theme.text.color {
            // for case when the textView was created for sub split editor
            self.typingAttributes[.foregroundColor] = theme.text.color
        }
        
        self.backgroundColor = theme.background.color
        self.lineHighlightColor = theme.lineHighlight.color
        self.refreshCursorColor()
        self.selectedTextAttributes[.backgroundColor] = theme.selectionColor
        (self.layoutManager as? LayoutManager)?.invisiblesColor = theme.invisibles.color
        (self.layoutManager as? LayoutManager)?.unemphasizedSelectedContentBackgroundColor = theme.unemphasizedSelectionColor
        self.textHighlightColor = theme.highlightColor
        
        // explicitly set the foreground color to nil,
        // otherwise the syntax highlighting disappears by selecting text
        // in the Dark mode (2025-04, macOS 15).
        self.selectedTextAttributes[.foregroundColor] = nil
        
        (self.window as? DocumentWindow)?.contentBackgroundColor = theme.background.color
        self.enclosingScrollView?.backgroundColor = theme.background.color
        self.enclosingScrollView?.scrollerKnobStyle = theme.isDarkTheme ? .light : .dark
        
        self.setNeedsDisplay(self.visibleRect, avoidAdditionalLayout: true)
    }
    
    
    /// Updates the app-wide automatic period substitution behavior based on the receiver's `mode`.
    ///
    /// Workaround for that the view-specific API to customize this behavior is currently unavailable (2024-11, macOS 15, FB13669125).
    private func invalidateAutomaticPeriodSubstitution() {
        
        let key = "NSAutomaticPeriodSubstitutionEnabled"
        if self.window?.firstResponder == self {
            UserDefaults.standard.set(self.isAutomaticPeriodSubstitutionEnabled, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }
    
    
    /// Updates `defaultParagraphStyle` based on the font, tab width, and line height.
    private func invalidateDefaultParagraphStyle() {
        
        assert(Thread.isMainThread)
        
        let paragraphStyle = (self.defaultParagraphStyle ?? .default).mutable
        
        // set line height
        // -> The actual line height will be calculated in LayoutManager based on this line height multiplier.
        //    Because the default implementation calculates the line height differently
        //    if the first character is drawn with another font (typically by a composite font).
        paragraphStyle.lineHeightMultiple = self.lineHeight
        
        // calculate tab interval
        if let font = self.font {
            paragraphStyle.tabStops = []
            paragraphStyle.defaultTabInterval = CGFloat(self.tabWidth) * font.width(of: " ")
        }
        
        // -> This guard is certainly passed on the first time because the initial values of defaultParagraphStyle are zero. (2024-02, macOS 14)
        guard
            paragraphStyle.lineHeightMultiple != self.defaultParagraphStyle?.lineHeightMultiple ||
            paragraphStyle.defaultTabInterval != self.defaultParagraphStyle?.defaultTabInterval
        else { return }
        
        self.defaultParagraphStyle = paragraphStyle
        self.typingAttributes[.paragraphStyle] = paragraphStyle
        self.textStorage?.addAttribute(.paragraphStyle, value: paragraphStyle, range: self.string.range)
        (self.layoutManager as? LayoutManager)?.lineHeightMultiple = paragraphStyle.lineHeightMultiple
        
        // tell line height also to scroll view so that scroll view can scroll line by line
        if let lineHeight = (self.layoutManager as? LayoutManager)?.lineHeight {
            self.enclosingScrollView?.lineScroll = lineHeight
        }
        
        self.needsUpdateInsertionIndicators = true
    }
    
    
    /// Calculates the overscroll amount and applies it.
    private func invalidateOverscrollRate() {
        
        guard let layoutManager = self.layoutManager as? LayoutManager else { return }
        
        let visibleRect = self.visibleRect
        let inset = self.overscrollRate * (visibleRect.height - layoutManager.lineHeight)
        
        // halve inset since the input value will be added to both top and bottom
        let height = max((inset / 2).rounded(.down), Self.textContainerInset.height)
        let diff = height - self.textContainerInset.height
        
        guard diff != 0 else { return }
        
        let heightPath = (self.layoutOrientation == .vertical) ? \NSSize.width : \NSSize.height
        self.textContainerInset.height = height
        self.frame.size[keyPath: heightPath] += 2 * diff
        
        // invoke `setToFit()` but only when needed to avoid heavy calculation by large document
        // -> `setToFit()` is required to remove the extra height of the frame that contains a blank margin already
        //    due to the smaller text content than the visible rect (macOS 10.15).
        guard let textContainer = self.textContainer else { return assertionFailure() }
        let maxVisibleYGlyphIndex = layoutManager.glyphIndex(for: NSPoint(x: 0, y: visibleRect.height), in: textContainer)
        let maxVisibleY = layoutManager.isValidGlyphIndex(maxVisibleYGlyphIndex)
            ? layoutManager.lineFragmentRect(forGlyphAt: maxVisibleYGlyphIndex, effectiveRange: nil, withoutAdditionalLayout: true).maxY
            : 0
        if maxVisibleY < visibleRect.height {
            self.sizeToFit()
        }
        
        self.scrollToVisible(visibleRect)
    }
    
    
    /// Validates whether turns the non-contiguous layout on.
    private func invalidateNonContiguousLayout() {
        
        // disable non-contiguous layout on vertical layout (2016-06, OS X 10.11 - macOS 26)
        // -> Otherwise by vertical layout, the view scrolls occasionally a bit on typing.
        self.layoutManager?.allowsNonContiguousLayout = (self.layoutOrientation == .vertical)
            ? false
            : self.string.length > self.minimumNonContiguousLayoutLength
    }
    
    
    /// Highlights all instances of the selection.
    private func highlightInstances() async throws {
        
        guard
            self.highlightsSelectionInstance,
            !self.string.isEmpty,  // important to avoid crash after closing editor
            !self.selectedRange.isEmpty,
            !self.hasMarkedText(),
            self.insertionLocations.isEmpty,
            self.selectedRanges.count == 1
        else { return }
        
        let string = self.string.immutable
        let selectedRange = self.selectedRange
        let task: Task<[NSRange], any Error> = .detached {
            try string.instanceRangesOfWord(at: selectedRange)
                .filter { $0 != selectedRange }
        }
        let ranges: [NSRange] = try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
        
        try Task.checkCancellation()
        
        guard
            self.highlightsSelectionInstance,
            self.selectedRange == selectedRange,
            !self.hasMarkedText(),
            self.insertionLocations.isEmpty,
            self.selectedRanges.count == 1,
            let lower = ranges.first?.lowerBound,
            let upper = ranges.last?.upperBound
        else { return }
        
        guard let layoutManager = self.layoutManager else { return }
        
        let color = self.textHighlightColor.withAlphaComponent(0.3)
        layoutManager.groupTemporaryAttributesUpdate(in: NSRange(lower..<upper)) {
            for range in ranges {
                layoutManager.addTemporaryAttribute(.roundedBackgroundColor, value: color, forCharacterRange: range)
            }
        }
    }
    
    
    /// Updates the selection instance highlighting state.
    private func invalidateInstanceHighlights() {
        
        if !self.highlightsSelectionInstance {
            self.instanceHighlightTask?.cancel()
            self.instanceHighlightTask = nil
            self.layoutManager?.removeTemporaryAttribute(.roundedBackgroundColor, forCharacterRange: self.string.range)
        }
    }
}


// MARK: - Context Menu

extension EditorTextView: NSMenuDelegate {
    
    /// Ends the suppression window as soon as the menu is about to open.
    ///
    /// Everything AppKit asks on the way to opening the menu happens before this call, so the
    /// view can offer auto-fill and services again while the menu is on screen.
    func menuWillOpen(_ menu: NSMenu) {
        
        self.isPreparingContextMenu = false
    }
    
    
    func menuDidClose(_ menu: NSMenu) {
        
        self.isPreparingContextMenu = false
    }
}


// MARK: - Text Find

extension EditorTextView: TextFinderClient {
    
    /// Delivers standard Cocoa text find action messages to the TextFinder instance.
    override func performTextFinderAction(_ sender: Any?) {
        
        self.performEditorTextFinderAction(sender)
    }
    
    
    /// Delivers EditorTextView-specific text find actions to the TextFinder instance.
    @IBAction func performEditorTextFinderAction(_ sender: Any?) {
        
        guard
            let tag = (sender as? any NSValidatedUserInterfaceItem)?.tag ?? (sender as? NSControl)?.tag,
            let action = TextFinder.Action(rawValue: tag)
        else { return }
        
        self.textFinder.performAction(action, representedItem: (sender as? NSMenuItem)?.representedObject)
    }
    
    
    /// Performs find next.
    @IBAction func matchNext(_ sender: Any?) {
        
        self.textFinder.performAction(.nextMatch)
    }
    
    
    /// Performs find previous.
    @IBAction func matchPrevious(_ sender: Any?) {
        
        self.textFinder.performAction(.previousMatch)
    }
    
    
    /// Performs incremental search.
    @IBAction func incrementalSearch(_ sender: Any?) {
        
        self.textFinder.incrementalSearch()
    }
}


// MARK: - Word Completion

extension EditorTextView {
    
    // MARK: Text View Methods
    
    override var rangeForUserCompletion: NSRange {
        
        let range = super.rangeForUserCompletion
        
        guard !self.string.isEmpty else { return range }
        
        let firstSyntaxLetters = self.syntaxCompletionWords.compactMap(\.text.unicodeScalars.first)
        let wordCompletionSet = CharacterSet(firstSyntaxLetters).union(.alphanumerics).union(.init(["_"]))
        
        // expand range until hitting a character that isn't in the word completion candidates
        let searchRange = NSRange(location: 0, length: range.upperBound)
        let invalidRange = (self.string as NSString).rangeOfCharacter(from: wordCompletionSet.inverted, options: .backwards, range: searchRange)
        
        guard !invalidRange.isNotFound else { return range }
        
        return NSRange(invalidRange.upperBound..<range.upperBound)
    }
    
    
    override func completions(forPartialWordRange charRange: NSRange, indexOfSelectedItem index: UnsafeMutablePointer<Int>) -> [String]? {
        
        guard
            !charRange.isEmpty,
            !self.completionWordTypes.isEmpty
        else { return nil }
        
        let string = self.string as NSString
        let partialWord = string.substring(with: charRange)
        
        var candidateWords: [String] = []
        
        // add words in document
        if self.completionWordTypes.contains(.document),
           // do nothing if the partial word is a symbol
           charRange.length > 1 || partialWord.first?.isLetter == true
        {
            let pattern = "\\b" + NSRegularExpression.escapedPattern(for: partialWord) + "\\w+\\b"
            
            candidateWords += try! NSRegularExpression(pattern: pattern)
                .matches(in: self.string, range: self.string.range)
                .map(\.range)
                .map(string.substring(with:))
        }
        
        // add words defined in syntax
        if self.completionWordTypes.contains(.syntax) {
            candidateWords += self.syntaxCompletionWords
                .map(\.text)
                .filter { $0.range(of: partialWord, options: [.caseInsensitive, .anchored]) != nil }
        }
        
        // add the standard words from default completion words
        if self.completionWordTypes.contains(.standard) {
            candidateWords += super.completions(forPartialWordRange: charRange, indexOfSelectedItem: index) ?? []
        }
        
        candidateWords.unique()
        
        // provide nothing if there is only a candidate which is same as input word
        if let word = candidateWords.first,
           candidateWords.count == 1,
           word.caseInsensitiveCompare(partialWord) == .orderedSame
        {
            return []
        }
        
        return candidateWords
    }
    
    
    override func insertCompletion(_ word: String, forPartialWordRange charRange: NSRange, movement: Int, isFinal flag: Bool) {
        
        self.completionDebouncer.cancel()
        
        self.isShowingCompletion = !flag
        
        // store original string
        if self.partialCompletionWord == nil {
            self.partialCompletionWord = (self.string as NSString).substring(with: charRange)
        }
        
        // fix that underscore is treated as the right arrow key
        let movement = if flag,
                          let event = self.window?.currentEvent,
                          event.type == .keyDown,
                          !event.modifierFlags.contains(.command),
                          event.charactersIgnoringModifiers == event.characters,  // exclude key-bindings
                          event.characters == "_", movement == NSRightTextMovement
        {
            NSIllegalTextMovement
        } else {
            movement
        }
        
        var word = word
        var didComplete = false
        if flag {
            switch movement {
                case NSIllegalTextMovement, NSRightTextMovement:  // treat as cancelled
                    // restore original input
                    // -> In case if the letter case is changed from the original.
                    if let originalWord = self.partialCompletionWord {
                        word = originalWord
                    }
                default:
                    didComplete = true
            }
            
            // discard stored original word
            self.partialCompletionWord = nil
        }
        
        super.insertCompletion(word, forPartialWordRange: charRange, movement: movement, isFinal: flag)
        
        guard didComplete else { return }
        
        // select inside of "()" if completion word has ()
        var rangeToSelect = (word as NSString).range(of: "(?<=\\().*(?=\\))", options: .regularExpression)
        if rangeToSelect.location != NSNotFound {
            rangeToSelect.location += charRange.location
            self.selectedRange = rangeToSelect
        }
    }
    
    
    // MARK: Private Methods
    
    /// Displays the word completion candidates list.
    private func performCompletion() {
        
        guard
            !self.hasMarkedText(),
            self.selectedRange.isEmpty,
            self.rangeForUserCompletion.length >= self.minimumAutomaticCompletionLength,
            self.string.character(before: self.selectedRange)
                .map(CharacterSet.whitespacesAndNewlines.contains) != true,  // last character is blank
            self.string.character(after: self.selectedRange)
                .map(CharacterSet.alphanumerics.contains) != true  // cursor is (probably) at the middle of a word
        else { return }
        
        self.complete(self)
    }
}


// MARK: - Inline Image Preview Popover

private struct InlineImagePreviewPopoverView: View {
    
    let image: NSImage
    let filename: String
    let fileURL: URL?
    let onCopyImage: () -> Void
    let onRunOCR: () -> Void
    let onRevealInFinder: () -> Void
    let onDeleteToken: () -> Void
    
    var body: some View {
        
        VStack(alignment: .leading, spacing: 10) {
            Image(nsImage: self.image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: 440, maxHeight: 320)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.2), lineWidth: 1))
            
            HStack(spacing: 8) {
                Text(self.filename)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                
                Spacer()
                
                Button("OCR + AI", action: self.onRunOCR)
                Button("拷贝图片", action: self.onCopyImage)
                if self.fileURL != nil {
                    Button("Finder", action: self.onRevealInFinder)
                }
                Button(role: .destructive, action: self.onDeleteToken) {
                    Image(systemName: "trash")
                }
            }
            .controlSize(.small)
        }
        .padding(12)
    }
}
