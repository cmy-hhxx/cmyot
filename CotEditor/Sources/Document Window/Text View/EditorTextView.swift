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
    var syntaxCompletionWords: [Syntax.CompletionWord] = []  { didSet { self.cachedSyntaxCompletionTexts = self.syntaxCompletionWords.map(\.text) } }
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
            guard self.needsUpdateLineHighlight, !oldValue, self.highlightsCurrentLines else { return }
            // Expand invalidation bounds slightly to cover centerScanRect / rounded corner anti-aliasing
            // so moving between lines never leaves a 1px horizontal hairline residue.
            self.lineHighlightRects.forEach {
                self.setNeedsDisplay($0.insetBy(dx: -4, dy: -4), avoidAdditionalLayout: true)
            }
            if let band = self.currentCaretHighlightBandWithoutAdditionalLayout() {
                self.setNeedsDisplay(band, avoidAdditionalLayout: true)
            } else {
                self.setNeedsDisplay(self.visibleRect, avoidAdditionalLayout: true)
            }
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
    private var cachedSyntaxCompletionTexts: [String] = []
    private lazy var completionDebouncer = Debouncer { [weak self] in self?.performCompletion() }
    private var ghostRefreshTask: Task<Void, Never>?
    private static let formattingListPrefixRegex = try! NSRegularExpression(
        pattern: #"^\s*(?:[-*+•‣▪︎>]|\d+[\.、\)）]|#{1,6})\s*$"#
    )
    private(set) var activeGhostSuggestion: String?
    private(set) var ghostTextVersion: UInt64 = 0
    private var isUpdatingGhostSuggestion = false
    private var isCurrentGhostFromAI = false
    private var lastLocalHitCaretLocation: Int = -1
    private var lastFormattingTabUptime: TimeInterval = 0
    var dismissedGhostCaretLocation: Int?
    
    private lazy var trimTrailingWhitespaceTask = Debouncer { [weak self] in
        guard let self, !self.hasMarkedText() else { return }
        self.trimTrailingWhitespace(keepingEditingPoint: true)
    }
    
    /// Cancels any delayed trailing-whitespace trim so a post-save timer cannot re-dirty the document.
    func cancelScheduledTrailingWhitespaceTrim() {
        self.trimTrailingWhitespaceTask.cancel()
    }
    
    private var fontObservers: Set<AnyCancellable> = []
    private var wallpaperObserver: AnyCancellable?
    private var windowOpacityObserver: NSKeyValueObservation?
    private var keyStateObservers: [any NSObjectProtocol] = []
    private var scrollClipObserver: (any NSObjectProtocol)?
    private var inlineImageCardEntries: [InlineImageCardEntry] = []
    private var selectedInlineImageIdentifier: String?
    private var liveInlineImageHUDText: String?
    private var showInlineImageCenterGuide = false
    private weak var imagePreviewPopover: NSPopover?
    private weak var imageTransformPopover: NSPopover?
    
    // Bounding Box Resize & handle morph animation state
    private var inlineImageTrackingArea: NSTrackingArea?
    private var hoveredInlineImageIdentifier: String?
    private var hoveredResizeHandle: BoundingBoxHandle?
    private var activeDraggingResizeHandle: BoundingBoxHandle?
    private var isLiveManipulatingInlineImage = false
    private var activePinchImageID: String?
    private var activePinchWidth: CGFloat?
    private var didCrossPinch100Percent = false
    private var resizeMorphSprings: [BoundingBoxHandle: BoundingBoxMorphSpring] = {
        Dictionary(uniqueKeysWithValues: BoundingBoxHandle.allCases.map { ($0, BoundingBoxMorphSpring()) })
    }()
    private var resizePressSprings: [BoundingBoxHandle: BoundingBoxMorphSpring] = {
        Dictionary(uniqueKeysWithValues: BoundingBoxHandle.allCases.map { ($0, BoundingBoxMorphSpring()) })
    }()
    private var resizeSpringTimer: Timer?
    private var resizeSpringLastTimestamp: TimeInterval = 0
    private var visibleDimensionPills: (showWidth: Bool, showHeight: Bool, anchorCorner: BoundingBoxHandle) = (false, false, .bottomRight)
    private var dimensionPillHideWorkItem: DispatchWorkItem?
    private var widthPillRect: NSRect = .zero
    private var heightPillRect: NSRect = .zero
    private weak var inlineDimensionEditor: NSTextField?
    private var editingDimensionIsWidth: Bool?
    
    private static let diagonalNWSECursor: NSCursor = EditorTextView.makeDiagonalResizeCursor(angleDegrees: -45)
    private static let diagonalNESWCursor: NSCursor = EditorTextView.makeDiagonalResizeCursor(angleDegrees: 45)
    
    private static func makeDiagonalResizeCursor(angleDegrees: CGFloat) -> NSCursor {
        let side: CGFloat = 22
        let img = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            NSGraphicsContext.saveGraphicsState()
            let transform = NSAffineTransform()
            transform.translateX(by: rect.midX, yBy: rect.midY)
            transform.rotate(byDegrees: angleDegrees)
            transform.concat()
            
            let path = NSBezierPath()
            // Double-headed resize arrow along horizontal axis before rotation
            path.move(to: NSPoint(x: -7.5, y: 0))
            path.line(to: NSPoint(x: -3.2, y: 3.6))
            path.line(to: NSPoint(x: -3.2, y: 1.3))
            path.line(to: NSPoint(x: 3.2, y: 1.3))
            path.line(to: NSPoint(x: 3.2, y: 3.6))
            path.line(to: NSPoint(x: 7.5, y: 0))
            path.line(to: NSPoint(x: 3.2, y: -3.6))
            path.line(to: NSPoint(x: 3.2, y: -1.3))
            path.line(to: NSPoint(x: -3.2, y: -1.3))
            path.line(to: NSPoint(x: -3.2, y: -3.6))
            path.close()
            path.lineJoinStyle = .round
            
            NSColor.white.setStroke()
            path.lineWidth = 2.2
            path.stroke()
            
            NSColor.black.setFill()
            path.fill()
            NSGraphicsContext.restoreGraphicsState()
            return true
        }
        return NSCursor(image: img, hotSpot: NSPoint(x: side * 0.5, y: side * 0.5))
    }
    
    private func cursorForResizeHandle(_ handle: BoundingBoxHandle, rotationDegrees: CGFloat = 0) -> NSCursor {
        let baseAngle: CGFloat = switch handle {
            case .middleLeft, .middleRight: 0
            case .topCenter, .bottomCenter: 90
            case .topLeft, .bottomRight: 45
            case .topRight, .bottomLeft: 135
        }
        var total = (baseAngle + rotationDegrees).truncatingRemainder(dividingBy: 180)
        if total < 0 { total += 180 }
        if total < 22.5 || total >= 157.5 {
            return .resizeLeftRight
        } else if total < 67.5 {
            return Self.diagonalNWSECursor
        } else if total < 112.5 {
            return .resizeUpDown
        } else {
            return Self.diagonalNESWCursor
        }
    }
    
    // Cmd-key link preview underline state
    private var isCommandKeyHeld = false
    private var commandLinkUnderlineRanges: [NSRange] = []
    private var hoveredCommandLinkRange: NSRange?
    private var commandFlagsMonitor: Any?
    
    
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
        self.isAutomaticLinkDetectionEnabled = false
        self.linkTextAttributes = [:]
        
        // avoid AppKit falling back to Last Resort while fixing attributes during the initial setup
        self.typingAttributes[.font] = self.font ?? .systemFont(ofSize: 0)
        
        // Keep layer clipping enabled upfront so cursor/particle overlays never escape the pane
        self.wantsLayer = true
        self.layer?.masksToBounds = true
        self.registerForDraggedTypes(self.registeredDraggedTypes + [PaneTab.dragPasteboardType])
    }
    
    
    required init?(coder: NSCoder) {
        
        fatalError("init(coder:) has not been implemented")
    }
    
    
    isolated deinit {
        self.ghostRefreshTask?.cancel()
        self.ghostRefreshTask = nil
        self.resizeSpringTimer?.invalidate()
        self.resizeSpringTimer = nil
        self.dimensionPillHideWorkItem?.cancel()
        self.dimensionPillHideWorkItem = nil
        if let monitor = self.commandFlagsMonitor {
            NSEvent.removeMonitor(monitor)
            self.commandFlagsMonitor = nil
        }
        if let scrollClipObserver = self.scrollClipObserver {
            NotificationCenter.default.removeObserver(scrollClipObserver)
            self.scrollClipObserver = nil
        }
        self.keyStateObservers.forEach(NotificationCenter.default.removeObserver)
        self.keyStateObservers.removeAll()
        self.windowOpacityObserver = nil
        self.wallpaperObserver = nil
    }
    
    
    override func updateTrackingAreas() {
        
        super.updateTrackingAreas()
        
        if let existing = self.inlineImageTrackingArea {
            self.removeTrackingArea(existing)
        }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseMoved, .mouseEnteredAndExited, .cursorUpdate, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        self.addTrackingArea(area)
        self.inlineImageTrackingArea = area
    }
    
    
    override func cursorUpdate(with event: NSEvent) {
        
        let point = self.convert(event.locationInWindow, from: nil)
        if (self.layoutManager as? LayoutManager)?.rendersPlainTextInlineImages == true {
            if let dragging = self.activeDraggingResizeHandle {
                let deg = self.selectedInlineImageEntry()?.rotationDegrees ?? 0
                self.cursorForResizeHandle(dragging, rotationDegrees: deg).set()
                return
            }
            if let hit = self.inlineImageHoverTarget(at: point) {
                if let handle = hit.handle {
                    self.cursorForResizeHandle(handle, rotationDegrees: hit.entry.rotationDegrees).set()
                } else {
                    NSCursor.openHand.set()
                }
                return
            }
        }
        if self.isCommandKeyHeld, self.urlMatchAtPoint(point) != nil {
            NSCursor.pointingHand.set()
            return
        }
        super.cursorUpdate(with: event)
    }
    
    
    private func inlineImageHoverTarget(at point: NSPoint) -> (entry: InlineImageCardEntry, handle: BoundingBoxHandle?)? {
        if let selected = self.selectedInlineImageEntry() {
            if let handle = selected.hitTestHandle(at: point) {
                return (selected, handle)
            }
            if selected.hitTestImage(point: point) {
                return (selected, nil)
            }
        }
        for entry in self.inlineImageCardEntries {
            if let handle = entry.hitTestHandle(at: point) {
                return (entry, handle)
            }
            if entry.hitTestImage(point: point) {
                return (entry, nil)
            }
        }
        return nil
    }
    
    
    override func mouseMoved(with event: NSEvent) {
        
        let point = self.convert(event.locationInWindow, from: nil)
        if (self.layoutManager as? LayoutManager)?.rendersPlainTextInlineImages == true,
           self.activeDraggingResizeHandle == nil
        {
            if let target = self.inlineImageHoverTarget(at: point) {
                let nextImageID = target.entry.identifier
                let nextHandle = target.handle
                let imageChanged = (nextImageID != self.hoveredInlineImageIdentifier)
                let handleChanged = (nextHandle != self.hoveredResizeHandle)
                if imageChanged || handleChanged {
                    self.hoveredInlineImageIdentifier = nextImageID
                    self.hoveredResizeHandle = nextHandle
                    if target.entry.identifier == self.selectedInlineImageIdentifier {
                        for handle in BoundingBoxHandle.allCases {
                            self.resizeMorphSprings[handle]?.target = (handle == nextHandle) ? 1.0 : 0.0
                        }
                        self.startResizeSpringTimerIfNeeded()
                    }
                    self.needsDisplay = true
                }
                if let handle = nextHandle {
                    self.cursorForResizeHandle(handle, rotationDegrees: target.entry.rotationDegrees).set()
                } else {
                    NSCursor.openHand.set()
                }
                return
            } else if self.hoveredInlineImageIdentifier != nil || self.hoveredResizeHandle != nil {
                self.hoveredInlineImageIdentifier = nil
                self.hoveredResizeHandle = nil
                for handle in BoundingBoxHandle.allCases {
                    self.resizeMorphSprings[handle]?.target = 0.0
                }
                self.startResizeSpringTimerIfNeeded()
                self.window?.invalidateCursorRects(for: self)
                NSCursor.iBeam.set()
                self.needsDisplay = true
            }
        } else if self.hoveredInlineImageIdentifier != nil || self.hoveredResizeHandle != nil {
            self.hoveredInlineImageIdentifier = nil
            self.hoveredResizeHandle = nil
            for handle in BoundingBoxHandle.allCases {
                self.resizeMorphSprings[handle]?.target = 0.0
            }
            self.startResizeSpringTimerIfNeeded()
            self.window?.invalidateCursorRects(for: self)
            self.needsDisplay = true
        }
        
        if self.isCommandKeyHeld {
            let hoveredRange = self.urlMatchAtPoint(point)?.range
            if hoveredRange != self.hoveredCommandLinkRange {
                self.refreshCommandLinkUnderlines(hoveredRange: hoveredRange)
                if hoveredRange == nil {
                    self.window?.invalidateCursorRects(for: self)
                }
            }
            if hoveredRange != nil {
                NSCursor.pointingHand.set()
                return
            }
        }
        
        super.mouseMoved(with: event)
    }
    
    
    override func mouseExited(with event: NSEvent) {
        
        if (self.hoveredInlineImageIdentifier != nil || self.hoveredResizeHandle != nil),
           self.activeDraggingResizeHandle == nil
        {
            self.hoveredInlineImageIdentifier = nil
            self.hoveredResizeHandle = nil
            for handle in BoundingBoxHandle.allCases {
                self.resizeMorphSprings[handle]?.target = 0.0
            }
            self.startResizeSpringTimerIfNeeded()
            self.window?.invalidateCursorRects(for: self)
            self.needsDisplay = true
        }
        if self.isCommandKeyHeld, self.hoveredCommandLinkRange != nil {
            self.refreshCommandLinkUnderlines(hoveredRange: nil)
            self.window?.invalidateCursorRects(for: self)
        }
        super.mouseExited(with: event)
    }
    
    
    override func flagsChanged(with event: NSEvent) {
        
        super.flagsChanged(with: event)
        self.updateCommandKeyLinkState(
            modifierFlags: event.modifierFlags,
            mouseLocationInWindow: self.window?.mouseLocationOutsideOfEventStream
        )
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
            self.syncNativeCaretVisibility()
            self.funEffects.syncVimCursor(animated: false)
        }
        
        return true
    }
    
    
    override func resignFirstResponder() -> Bool {
        
        guard super.resignFirstResponder() else { return false }
        
        self.clearGhostSuggestion(animated: false)
        self.clearCommandLinkUnderlines()
        self.funEffects.resetCursorTracking()
        self.vimEngine.handleFocusLost()
        
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
        if let monitor = self.commandFlagsMonitor {
            NSEvent.removeMonitor(monitor)
            self.commandFlagsMonitor = nil
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
                        if self?.activeGhostSuggestion != nil || self?.funEffects.isShowingGhostThinking == true {
                            self?.clearGhostSuggestion(animated: false, cancelAI: false)
                        }
                        if self?.isPerformingVimCursorMove == false {
                            self?.vimEngine.resyncVisualOverlayIfNeeded(animated: false)
                        }
                        if self?.isCommandKeyHeld == true {
                            self?.refreshCommandLinkUnderlines(hoveredRange: self?.hoveredCommandLinkRange)
                        }
                    }
                }
            }
            
            self.commandFlagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
                guard let self, let window = self.window, window.isKeyWindow else { return event }
                self.updateCommandKeyLinkState(
                    modifierFlags: event.modifierFlags,
                    mouseLocationInWindow: window.mouseLocationOutsideOfEventStream
                )
                return event
            }
            
            // apply window opacity & global editor wallpaper transparency
            self.windowOpacityObserver = window.observe(\.isOpaque, options: [.initial, .new]) { [weak self] _, _ in
                MainActor.assumeIsolated {
                    self?.refreshWallpaperTransparency()
                }
            }
            
            self.wallpaperObserver = NotificationCenter.default.publisher(for: WallpaperManager.didChangeNotification)
                .sink { [weak self] _ in
                    self?.refreshWallpaperTransparency()
                }
            
            self.refreshWallpaperTransparency()
            
            // observe key window state for insertion points drawing and automatic period substitution
            self.keyStateObservers.forEach(NotificationCenter.default.removeObserver)
            self.keyStateObservers = [
                NotificationCenter.default.addObserver(forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated {
                        guard let self else { return }
                        self.invalidateInsertionIndicatorDisplayMode()
                        self.invalidateAutomaticPeriodSubstitution()
                        self.syncNativeCaretVisibility()
                        self.funEffects.syncVimCursor(animated: false)
                    }
                },
                NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: window, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated {
                        guard let self else { return }
                        self.clearGhostSuggestion(animated: false)
                        self.clearCommandLinkUnderlines()
                        self.funEffects.resetCursorTracking()
                        self.invalidateInsertionIndicatorDisplayMode()
                        self.invalidateAutomaticPeriodSubstitution()
                    }
                },
            ]
        } else {
            self.clearGhostSuggestion(animated: false)
            self.clearCommandLinkUnderlines()
            self.funEffects.resetCursorTracking()
            self.keyStateObservers.forEach(NotificationCenter.default.removeObserver)
            self.keyStateObservers.removeAll()
            self.wallpaperObserver = nil
            self.windowOpacityObserver = nil
            self.instanceHighlightTask?.cancel()
            self.instanceHighlightTask = nil
        }
    }
    
    
    override func setFrameSize(_ newSize: NSSize) {
        
        let oldSize = self.frame.size
        
        super.setFrameSize(newSize)
        
        guard newSize != oldSize else { return }
        
        if newSize.width != oldSize.width {
            self.clearGhostSuggestion(animated: false)
        }
        
        if !self.inLiveResize {
            self.overscrollResizingDebouncer.schedule()
        }
        
        self.needsUpdateInsertionIndicators = true
        self.needsUpdateLineHighlight = true
        if self.funEffects.ownsVimCursorDrawing {
            self.funEffects.syncVimCursor(animated: false)
        }
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
    
    
    override func clicked(onLink link: Any, at charIndex: Int) {
        
        // Ignore plain clicks on any `.link` attribute; only Cmd + Click opens links.
        guard NSApp.currentEvent?.modifierFlags.intersection(.deviceIndependentFlagsMask) == [.command] else { return }
        
        super.clicked(onLink: link, at: charIndex)
    }
    
    
    override func mouseDown(with event: NSEvent) {
        
        self.clearGhostSuggestion(animated: false)
        if UserDefaults.standard[.vimMode] {
            self.vimEngine.handleExternalMouseInteraction()
        }
        self.mouseDownPoint = self.convert(event.locationInWindow, from: nil)
        
        // Cmd + Click on a URL jumps directly without highlighting links or showing tooltips
        if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == [.command],
           event.clickCount == 1,
           let url = self.urlAtPoint(self.mouseDownPoint)
        {
            NSWorkspace.shared.open(url)
            return
        }
        
        // Direct manipulation on inline images (left-click selects / drags position, 8 handles morph & resize, knob rotates; zooming popover is right-click only)
        if !event.modifierFlags.contains(.command),
           event.clickCount >= 1,
           (self.layoutManager as? LayoutManager)?.rendersPlainTextInlineImages == true,
           self.handleInlineImageMouseDown(at: self.mouseDownPoint, modifiers: event.modifierFlags)
        {
            NotesTextColorPaletteController.shared.dismiss(animated: false)
            self.window?.makeFirstResponder(self)
            return
        }
        
        if self.selectedInlineImageIdentifier != nil {
            self.selectedInlineImageIdentifier = nil
            self.dismissInlineDimensionEditor(commit: false)
            self.clearInlineImageDimensionPills()
            self.needsDisplay = true
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
        
        // Text highlighting is intentionally right-click only (never auto-popped on selection)
        if NotesTextColorPaletteController.shared.isVisible {
            NotesTextColorPaletteController.shared.dismiss(animated: true)
        }
    }
    
    
    /// The Esc key is pressed.
    override func cancelOperation(_ sender: Any?) {
        
        if self.hasMarkedText() {
            self.inputContext?.discardMarkedText()
            self.unmarkText()
            self.inputContext?.invalidateCharacterCoordinates()
            return
        }
        
        if self.inlineDimensionEditor != nil {
            self.dismissInlineDimensionEditor(commit: false)
            return
        }
        
        if NotesTextColorPaletteController.shared.isVisible {
            NotesTextColorPaletteController.shared.dismiss(animated: true)
            return
        }
        
        if self.selectedInlineImageIdentifier != nil {
            self.selectedInlineImageIdentifier = nil
            self.liveInlineImageHUDText = nil
            self.showInlineImageCenterGuide = false
            self.clearInlineImageDimensionPills()
            self.hoveredResizeHandle = nil
            for handle in BoundingBoxHandle.allCases {
                self.resizeMorphSprings[handle]?.target = 0
                self.resizePressSprings[handle]?.target = 0
            }
            self.window?.invalidateCursorRects(for: self)
            self.needsDisplay = true
            return
        }
        
        if self.activeGhostSuggestion != nil {
            self.dismissedGhostCaretLocation = self.selectedRange.location
            self.clearGhostSuggestion(animated: true)
            return
        }
        
        // exit multi-cursor mode
        if self.hasMultipleInsertions {
            self.selectedRange = self.insertionRanges.first!
            self.scrollRangeToVisible(self.selectedRange)
            return
        }
        
        // -> NSTextView doesn't implement `cancelOperation(_:)`. (macOS 10.14)
    }
    
    
    override func didChangeText() {
        
        NotesTextColorPaletteController.shared.dismiss(animated: false)
        self.ghostTextVersion &+= 1
        if !self.isUpdatingGhostSuggestion {
            self.clearGhostSuggestion(animated: false)
        }
        
        super.didChangeText()
        
        self.invalidateNonContiguousLayout()
        
        self.needsUpdateLineHighlight = true
        
        self.instanceHighlightTask?.cancel()
        
        if self.isAutomaticWhitespaceTrimmingEnabled {
            self.trimTrailingWhitespaceTask.schedule(delay: .seconds(3))
        }
        
        if self.funEffects.ownsVimCursorDrawing {
            self.funEffects.syncVimCursor(animated: true)
        }
        
        if self.isCommandKeyHeld {
            self.refreshCommandLinkUnderlines(hoveredRange: self.hoveredCommandLinkRange)
        }
    }
    
    
    /// Modal (Vim-style) editing layer, active while the `vimMode` default is on.
    private(set) lazy var vimEngine = VimEngine(textView: self)
    
    /// Built-in CoreAnimation effects controller for typewriter burst and Neovide-style Vim cursor trails.
    private(set) lazy var funEffects = EditorFunEffectsController(textView: self)
    
    /// Guards against duplicate cursor animation passes while `VimEngine` executes a move + scroll.
    var isPerformingVimCursorMove = false
    
    
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
    
    
    /// `true` when GPU-composited Vim visual selection bands own selection rendering for this text view.
    var usesElasticVimVisualOverlay: Bool {
        self.funEffects.ownsVimCursorDrawing
            && VimState.shared.mode == .visual
            && VimState.shared.visualOwnerID == ObjectIdentifier(self)
    }
    
    
    /// Suppresses AppKit's native 1–2pt insertion line & internal `NSTextInsertionIndicator`
    /// while our GPU Vim cursor owns rendering so no thin vertical caret line lingers after moves.
    func syncNativeCaretVisibility() {
        
        let hideNative = self.funEffects.ownsVimCursorDrawing
        let targetColor: NSColor = hideNative ? .clear : self.effectiveCursorColor
        if self.insertionPointColor != targetColor {
            self.insertionPointColor = targetColor
        }
        if hideNative {
            self.updateInsertionPointStateAndRestartTimer(false)
            for subview in self.subviews where subview is NSTextInsertionIndicator && !self.insertionIndicators.contains(where: { $0 === subview }) {
                (subview as? NSTextInsertionIndicator)?.displayMode = .hidden
            }
        }
        
        // Suppress AppKit's static sharp-cornered selection fill while our GPU Visual bands render
        let useElasticVisualOverlay = self.usesElasticVimVisualOverlay
        let desiredSelectionBg: NSColor = useElasticVisualOverlay
            ? .clear
            : (self.theme?.selectionColor ?? NSColor.selectedTextBackgroundColor)
        if self.selectedTextAttributes[.backgroundColor] as? NSColor != desiredSelectionBg {
            self.selectedTextAttributes[.backgroundColor] = desiredSelectionBg
            self.needsUpdateLineHighlight = true
            for rect in self.lineHighlightRects {
                let band = NSRect(x: self.visibleRect.minX, y: rect.minY - 6, width: self.visibleRect.width, height: rect.height + 12)
                self.setNeedsDisplay(band, avoidAdditionalLayout: true)
            }
            if !useElasticVisualOverlay, let curRect = self.vimCursorRect(at: self.selectedRange().location) {
                let band = NSRect(x: self.visibleRect.minX, y: curRect.minY - 6, width: self.visibleRect.width, height: curRect.height + 12)
                self.setNeedsDisplay(band, avoidAdditionalLayout: true)
            }
        }
    }
    
    
    /// Updates caret, visual bands, and modal state immediately when UserDefaults `.vimMode` toggles.
    func applyVimModeSetting(_ enabled: Bool) {
        
        if !enabled {
            let ownID = ObjectIdentifier(self)
            if VimState.shared.visualOwnerID == ownID {
                VimState.shared.visualActiveLocation = nil
                VimState.shared.visualOwnerID = nil
            }
            if VimState.shared.mode != .normal || VimState.shared.commandLine != nil {
                VimState.shared.commandLine = nil
                VimState.shared.mode = .normal
            }
            self.funEffects.hideVimVisualSelection(withYankPulse: false)
        }
        
        self.funEffects.syncVimCursor(animated: false)
        self.syncNativeCaretVisibility()
        self.updateInsertionPointStateAndRestartTimer(self.isEditable && !self.funEffects.ownsVimCursorDrawing)
        self.needsDisplay = true
    }
    
    
    /// Locks or unlocks editing in presentation mode: clears interactive overlays & hides carets when read-only.
    func applyEditableLockState(_ editable: Bool) {
        
        self.isEditable = editable
        self.isSelectable = true
        
        if !editable {
            self.clearGhostSuggestion(animated: false, cancelAI: true)
            self.selectedInlineImageIdentifier = nil
            self.liveInlineImageHUDText = nil
            self.showInlineImageCenterGuide = false
            self.dismissInlineDimensionEditor(commit: false)
            self.clearInlineImageDimensionPills()
            NotesTextColorPaletteController.shared.dismiss(animated: false)
            
            if UserDefaults.standard[.vimMode],
               VimState.shared.mode == .insert || VimState.shared.mode == .replace
            {
                VimState.shared.mode = .normal
            }
            self.updateInsertionPointStateAndRestartTimer(false)
            for subview in self.subviews where subview is NSTextInsertionIndicator && !self.insertionIndicators.contains(where: { $0 === subview }) {
                (subview as? NSTextInsertionIndicator)?.displayMode = .hidden
            }
        } else {
            self.updateInsertionPointStateAndRestartTimer(!self.funEffects.ownsVimCursorDrawing)
        }
        
        self.funEffects.syncVimCursor(animated: false)
        self.syncNativeCaretVisibility()
        self.needsDisplay = true
    }
    
    
    /// Re-applies the cursor color across native insertion point, multi-cursor indicators, and Vim blocks.
    func refreshCursorColor() {
        
        let color = self.effectiveCursorColor
        self.insertionPointColor = self.funEffects.ownsVimCursorDrawing ? .clear : color
        for indicator in self.insertionIndicators {
            indicator.color = color
        }
        self.funEffects.syncVimCursor(animated: false)
        if !self.funEffects.ownsVimCursorDrawing {
            self.setNeedsDisplay(self.visibleRect, avoidAdditionalLayout: true)
        }
    }
    
    
    override var shouldDrawInsertionPoint: Bool {
        
        if !self.isEditable {
            return false
        }
        if self.funEffects.ownsVimCursorDrawing {
            return false
        }
        return super.shouldDrawInsertionPoint
    }
    
    
    /// Zero-copy `NSString` view of the underlying `NSTextStorage` backing store when available.
    private var backingNSString: NSString {
        self.textStorage?.mutableString ?? (self.string as NSString)
    }
    
    
    /// Computes an adaptive caret rect aligned with an inline image card when the insertion point sits directly before/after it.
    private func inlineImageCaretFrame(for location: Int) -> NSRect? {
        
        guard
            let layoutManager = self.layoutManager as? LayoutManager,
            layoutManager.rendersPlainTextInlineImages,
            let textContainer = self.textContainer
        else { return nil }
        
        let nsString = self.backingNSString
        guard nsString.length > 0 else { return nil }
        
        let clampedLoc = min(max(0, location), nsString.length)
        if clampedLoc == nsString.length, nsString.character(at: clampedLoc - 1) == 0x0A {
            return nil
        }
        
        let probeLoc = min(clampedLoc, nsString.length - 1)
        let lineRange = nsString.lineRange(for: NSRange(location: probeLoc, length: 0))
        let tokens = PlainTextInlineImageStore.shared.findTokens(in: nsString, range: lineRange)
        guard !tokens.isEmpty else { return nil }
        
        var matched: (token: (range: NSRange, identifier: String), edge: CaretImageEdge)?
        for token in tokens {
            if clampedLoc == token.range.location {
                matched = (token, .leading)
                break
            } else if clampedLoc == token.range.upperBound || NSLocationInRange(clampedLoc, token.range) {
                matched = (token, .trailing)
                break
            }
        }
        guard let matched else { return nil }
        
        let cardRect: NSRect
        let docURL = self.currentInlineImageDocURL
        guard PlainTextInlineImageStore.shared.image(for: matched.token.identifier, documentURL: docURL) != nil else {
            return nil
        }
        layoutManager.ensureLayout(forCharacterRange: matched.token.range)
        let glyphIndex = layoutManager.glyphIndexForCharacter(at: matched.token.range.location)
        guard layoutManager.isValidGlyphIndex(glyphIndex) else { return nil }
        
        let fragmentRect = layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: nil, withoutAdditionalLayout: true)
        let glyphLocation = layoutManager.location(forGlyphAt: glyphIndex)
        let rawContainerW = textContainer.size.width
        let finiteContainerW = (rawContainerW.isFinite && rawContainerW > 0 && rawContainerW <= 100_000)
            ? rawContainerW
            : (self.enclosingScrollView?.documentVisibleRect.width ?? self.bounds.width)
        let containerWidth = max(160, finiteContainerW.isFinite ? min(16_384, finiteContainerW) : 800)
        let maxCardWidth = PlainTextInlineImageStore.effectiveMaxImageWidth(
            containerWidth: containerWidth,
            glyphX: glyphLocation.x
        )
        guard let geom = PlainTextInlineImageStore.shared.displayGeometry(
            for: matched.token.identifier,
            documentURL: docURL,
            containerWidth: containerWidth,
            maxImageWidth: maxCardWidth
        ) else { return nil }
        
        let tx = geom.transform
        let boxW = geom.rotatedBoxSize.width + 8
        let boxH = geom.rotatedBoxSize.height + 8
        let baseX = fragmentRect.minX + self.textContainerOrigin.x + glyphLocation.x
        let minX = self.textContainerOrigin.x + 8
        let maxX = max(minX, self.textContainerOrigin.x + containerWidth - boxW - 8)
        let clampedX = min(maxX, max(minX, baseX + tx.offsetX))
        let cardTopY = fragmentRect.minY + self.textContainerOrigin.y + 4 + max(0, tx.offsetY)
        cardRect = NSRect(x: clampedX, y: cardTopY, width: boxW, height: boxH)
        
        return BoundingBoxResizeMath.adaptiveCaretRect(
            forImageCardRect: cardRect,
            edge: matched.edge,
            singleLineHeight: self.singleLineHeight,
            textContainerMinX: self.textContainerOrigin.x
        )
    }
    
    
    override func layout() {
        
        super.layout()
        
        let maxHeight = self.singleLineHeight
        let shouldHide = !self.isEditable || self.funEffects.ownsVimCursorDrawing
        let adaptiveCaret: NSRect? = (!shouldHide && self.selectedRanges.count == 1 && self.selectedRange().length == 0)
            ? self.inlineImageCaretFrame(for: self.selectedRange().location)
            : nil
        for subview in self.subviews where subview is NSTextInsertionIndicator && !self.insertionIndicators.contains(where: { $0 === subview }) {
            guard let indicator = subview as? NSTextInsertionIndicator else { continue }
            if shouldHide {
                indicator.displayMode = .hidden
            } else if let adaptiveCaret {
                indicator.frame = adaptiveCaret
            } else if indicator.frame.height > maxHeight + 2 {
                var frame = indicator.frame
                frame.size.height = maxHeight
                indicator.frame = frame
            }
        }
    }
    
    
    override func drawInsertionPoint(in rect: NSRect, color: NSColor, turnedOn flag: Bool) {
        
        guard self.isEditable else { return }
        let cursorColor = self.effectiveCursorColor
        let adaptiveCaret: NSRect? = (self.selectedRanges.count == 1 && self.selectedRange().length == 0)
            ? self.inlineImageCaretFrame(for: self.selectedRange().location)
            : nil
        var caretRect = rect
        let maxLineHeight = self.singleLineHeight
        if adaptiveCaret == nil, caretRect.height > maxLineHeight + 2 {
            caretRect.size.height = maxLineHeight
        }
        
        guard UserDefaults.standard[.vimMode], VimState.shared.mode != .insert else {
            if let adaptiveCaret {
                guard flag else { return }
                NSGraphicsContext.saveGraphicsState()
                cursorColor.setFill()
                NSBezierPath(
                    roundedRect: adaptiveCaret,
                    xRadius: adaptiveCaret.width * 0.5,
                    yRadius: adaptiveCaret.width * 0.5
                ).fill()
                NSGraphicsContext.restoreGraphicsState()
                return
            }
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
        
        // When the persistent 120Hz GPU Vim cursor layer owns rendering, do not draw a second
        // static block via AppKit's blinking `drawInsertionPoint` (prevents overlap & blink flicker).
        if self.funEffects.ownsVimCursorDrawing {
            return
        }
        
        var block = caretRect
        if let adaptiveCaret {
            block.origin.x = adaptiveCaret.minX
            block.origin.y = adaptiveCaret.minY
            block.size.height = adaptiveCaret.height
        }
        block.size.width = max(4, self.blockCursorWidth())
        
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
        
        let charRange = string.rangeOfComposedCharacterSequence(at: location)
        let sample = string.substring(with: charRange)
        if sample == "\n" || sample == "\r" {
            return fallbackSpace
        }
        
        let font = self.font ?? .monospacedSystemFont(ofSize: 13, weight: .regular)
        return max((sample as NSString).size(withAttributes: [.font: font]).width, 2)
    }
    
    
    override func keyDown(with event: NSEvent) {
        
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        
        // Strictly block unintended edits while in Presentation Lock Mode, allowing only read-only navigation & Cmd shortcuts.
        if !self.isEditable {
            if self.handleControlAPrefix(event) { return }
            if flags.contains(.command) {
                super.keyDown(with: event)
                return
            }
            if UserDefaults.standard[.vimMode], self.vimEngine.handleKeyDown(event) {
                return
            }
            let navKeyCodes: Set<UInt16> = [115, 116, 119, 121, 123, 124, 125, 126, 53] // Home/PgUp/End/PgDn/Arrows/Esc
            if navKeyCodes.contains(event.keyCode) {
                super.keyDown(with: event)
            } else {
                NSSound.beep()
            }
            return
        }
        
        if !self.hasMarkedText(), event.keyCode == 48 {
            // Option+Tab always forces literal Tab formatting even when a ghost candidate is visible.
            if flags == .option {
                self.dismissedGhostCaretLocation = self.selectedRange.location
                self.lastFormattingTabUptime = ProcessInfo.processInfo.systemUptime
                self.clearGhostSuggestion(animated: false, cancelAI: true)
                self.performFormattingTab(nil)
                return
            }
            if flags.isEmpty {
                if self.shouldTabAcceptActiveGhost(), self.acceptGhostSuggestionIfPresent() {
                    return
                }
                if self.activeGhostSuggestion != nil || self.funEffects.isShowingGhostThinking {
                    self.lastFormattingTabUptime = ProcessInfo.processInfo.systemUptime
                    self.clearGhostSuggestion(animated: false, cancelAI: true)
                }
            }
        }
        
        // Clear stale ghost suggestion when leaving Vim insert mode via Esc
        if event.keyCode == 53, self.activeGhostSuggestion != nil {
            if self.isCurrentGhostFromAI {
                AINextTokenPredictor.shared.recordSuggestionIgnored()
            }
            self.dismissedGhostCaretLocation = self.selectedRange.location
            self.clearGhostSuggestion(animated: true)
        }
        
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
                    if self.documentViewController?.isPaneZoomed == true {
                        NSSound.beep()
                        return true
                    }
                    self.documentViewController?.splitEditorVertically(self)
                    return true
                    
                case "\"", "\u{201D}":
                    if self.documentViewController?.isPaneZoomed == true {
                        NSSound.beep()
                        return true
                    }
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
    
    
    override func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        
        let markedLength = (string as? NSAttributedString)?.length ?? (string as? String)?.count ?? 0
        if markedLength > 0 {
            self.ghostTextVersion &+= 1
            self.clearGhostSuggestion(animated: false)
        }
        super.setMarkedText(string, selectedRange: selectedRange, replacementRange: replacementRange)
    }
    
    
    override func insertText(_ string: Any, replacementRange: NSRange) {
        
        // do not use this method for programmatic insertion.
        
        let plainString = String(anyString: string)!
        let previousGhost = (!self.hasMarkedText() && replacementRange.isEmpty) ? self.activeGhostSuggestion : nil
        let wasFromAI = previousGhost != nil ? self.isCurrentGhostFromAI : false
        
        if self.activeGhostSuggestion != nil
            || self.funEffects.isShowingGhostThinking
            || (self.layoutManager as? LayoutManager)?.inlineGhostShift != nil
        {
            self.clearGhostSuggestion(animated: false)
        }
        
        // enter multi-cursor editing
        let insertionRanges = self.insertionRanges
        if insertionRanges.count > 1 {
            let typedCount = Self.visibleTypedScalarCount(in: plainString)
            if typedCount > 0 {
                AnalyticsManager.shared.recordTypedCharacters(typedCount * insertionRanges.count)
            }
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
                self.isUpdatingGhostSuggestion = true
                self.selectedRange.location += 1
                self.isUpdatingGhostSuggestion = false
                AnalyticsManager.shared.recordTypedCharacters(1)
                self.scheduleHabitGhostRefresh(animateEntrance: true, allowAIRefresh: true)
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
                    self.isUpdatingGhostSuggestion = true
                    self.setSelectedRangesWithUndo([NSRange(location: self.selectedRange.location - 1, length: 0)])
                    self.isUpdatingGhostSuggestion = false
                    self.textStorage?.addAttribute(.autoBalancedClosingBracket, value: true,
                                                   range: NSRange(location: self.selectedRange.location, length: 1))
                    AnalyticsManager.shared.recordTypedCharacters(1)
                    self.scheduleHabitGhostRefresh(animateEntrance: true, allowAIRefresh: true)
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
        
        self.dismissedGhostCaretLocation = nil
        if plainString.contains(where: { !$0.isWhitespace && !$0.isNewline }) {
            self.lastFormattingTabUptime = 0
        } else if plainString.contains("\t") {
            self.lastFormattingTabUptime = ProcessInfo.processInfo.systemUptime
        }
        
        self.isUpdatingGhostSuggestion = true
        super.insertText(plainString, replacementRange: replacementRange)
        self.isUpdatingGhostSuggestion = false
        
        let typedCount = Self.visibleTypedScalarCount(in: plainString)
        if typedCount > 0 {
            AnalyticsManager.shared.recordTypedCharacters(typedCount)
        }
        
        if self.funEffects.isTypewriterEffectEnabled,
           !self.hasMarkedText(),
           !plainString.isEmpty,
           plainString.count <= 24,
           !plainString.contains("\n"),
           var caretRect = self.boundingRect(for: self.selectedRange)
        {
            caretRect.size.height = min(caretRect.height, self.singleLineHeight)
            self.funEffects.triggerTypewriterBurst(at: caretRect, color: self.effectiveCursorColor)
        }
        
        if let previousGhost,
           !plainString.isEmpty,
           previousGhost.hasPrefix(plainString),
           previousGhost.count > plainString.count
        {
            let remaining = String(previousGhost.dropFirst(plainString.count))
            self.showGhostCandidate(remaining, animateEntrance: false, isFromAI: wasFromAI)
        } else {
            if previousGhost != nil, wasFromAI, !plainString.isEmpty {
                AINextTokenPredictor.shared.recordSuggestionIgnored()
            }
            self.scheduleHabitGhostRefresh(animateEntrance: true, allowAIRefresh: true)
        }
        
        // Cancel any popup completion list — inline ghost completion shows only the single highest-probability candidate
        self.completionDebouncer.cancel()
    }
    
    
    override func insertTab(_ sender: Any?) {
        
        if !self.hasMarkedText(), self.shouldTabAcceptActiveGhost(), self.acceptGhostSuggestionIfPresent() {
            return
        }
        
        self.lastFormattingTabUptime = ProcessInfo.processInfo.systemUptime
        self.clearGhostSuggestion(animated: false, cancelAI: true)
        self.performFormattingTab(sender)
    }
    
    
    /// Performs pure indentation / Tab insertion without triggering or accepting inline ghost completion.
    private func performFormattingTab(_ sender: Any?) {
        
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
        
        self.lastFormattingTabUptime = ProcessInfo.processInfo.systemUptime
        self.clearGhostSuggestion(animated: false, cancelAI: true)
        
        // outdent with the Tab key
        if self.indentsWithTabKey {
            self.outdent()
            return
        }
        
        super.insertBacktab(sender)
    }
    
    
    override func insertNewline(_ sender: Any?) {
        
        guard self.isEditable else { return super.insertNewline(sender) }
        
        self.clearGhostSuggestion(animated: false)
        
        // Capture only the just-completed single line (O(1)) before inserting the newline.
        let nsBefore = self.string as NSString
        let preLoc = min(self.rangeForUserTextChange.location, nsBefore.length)
        let completedLine: String? = if preLoc > 0, nsBefore.length > 0 {
            {
                let lr = nsBefore.lineRange(for: NSRange(location: max(0, preLoc - 1), length: 0))
                return (lr.length >= 6 && lr.length <= 320) ? nsBefore.substring(with: lr) : nil
            }()
        } else {
            nil
        }
        
        // insert newline
        self.insertText(self.lineEnding.string, replacementRange: self.rangeForUserTextChange)
        
        // apply auto indentation
        if self.isAutomaticIndentEnabled {
            self.smartIndent()
        }
        
        if self.funEffects.isTypewriterEffectEnabled,
           !self.hasMarkedText(),
           var caretRect = self.boundingRect(for: self.selectedRange)
        {
            caretRect.size.height = min(caretRect.height, self.singleLineHeight)
            self.funEffects.triggerTypewriterBurst(at: caretRect, color: self.effectiveCursorColor, intensityScale: 0.9)
        }
        
        // Learn only the just-completed line lazily & asynchronously so pressing Enter never stalls typing.
        if let completedLine {
            UserHabitPredictor.shared.scheduleLearn(line: completedLine)
        }
    }
    
    
    override func deleteBackward(_ sender: Any?) {
        
        guard self.isEditable else { return super.deleteBackward(sender) }
        
        self.clearGhostSuggestion(animated: false)
        self.dismissedGhostCaretLocation = nil
        
        if !self.hasMultipleInsertions,
           self.selectedRange.isEmpty,
           let tokenRange = self.resolvedInlineImageTokenRangeForDeletion(backward: true),
           self.shouldChangeText(in: tokenRange, replacementString: "")
        {
            self.clearGhostSuggestion(animated: false)
            self.replaceCharacters(in: tokenRange, with: "")
            self.didChangeText()
            return
        }
        
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
        
        self.isUpdatingGhostSuggestion = true
        super.deleteBackward(sender)
        self.isUpdatingGhostSuggestion = false
        
        if self.funEffects.isTypewriterEffectEnabled,
           !self.hasMarkedText(),
           var caretRect = self.boundingRect(for: self.selectedRange)
        {
            caretRect.size.height = min(caretRect.height, self.singleLineHeight)
            self.funEffects.triggerTypewriterBurst(at: caretRect, color: self.effectiveCursorColor, intensityScale: 0.65)
        }
        self.scheduleHabitGhostRefresh(animateEntrance: true, allowAIRefresh: true)
    }
    
    
    override func cut(_ sender: Any?) {
        
        self.clearGhostSuggestion(animated: false)
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
        
        guard self.isEditable else {
            NSSound.beep()
            return
        }
        self.clearGhostSuggestion(animated: false)
        let pboard = NSPasteboard.general
        let document = self.textStorage.flatMap { self.documentViewController?.document(for: $0) }
        let docURL = document?.fileURL
        let syntaxName = document?.syntaxName ?? SyntaxName.none
        let rendersInlineImages = (self.layoutManager as? LayoutManager)?.rendersPlainTextInlineImages == true
        let isMarkdown = syntaxName.caseInsensitiveCompare("Markdown") == .orderedSame
        
        if (rendersInlineImages || isMarkdown),
           PlainTextInlineImageStore.hasPasteableImage(in: pboard),
           let image = PlainTextInlineImageStore.shared.extractImage(from: pboard),
           let stored = PlainTextInlineImageStore.shared.store(image: image, for: docURL)
        {
            if rendersInlineImages {
                self.insertInlineImageTokenCleanly(stored.token)
            } else {
                let insertionText = "![image](.cot-assets/\(stored.fileURL.lastPathComponent))"
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
            }
            return
        }
        
        super.paste(sender)
    }
    
    
    /// Inserts an inline image token onto its own clean line and positions the caret on a normal-height line directly below it.
    func insertInlineImageTokenCleanly(_ token: String) {
        
        guard self.isEditable else {
            NSSound.beep()
            return
        }
        
        let nsString = self.string as NSString
        let raw = self.selectedRange()
        let clampedLoc = min(max(0, raw.location), nsString.length)
        let clampedEnd = min(max(clampedLoc, raw.upperBound), nsString.length)
        let range = NSRange(location: clampedLoc, length: clampedEnd - clampedLoc)
        let needsLeadingNewline = range.location > 0 && nsString.character(at: range.location - 1) != 0x0A
        let hasFollowingNewline = range.upperBound < nsString.length && nsString.character(at: range.upperBound) == 0x0A
        
        let leading = needsLeadingNewline ? "\n" : ""
        let trailing = hasFollowingNewline ? "" : "\n"
        let insertionText = leading + token + trailing
        let postInsertCaret = range.location + (leading as NSString).length + (token as NSString).length + 1
        
        if self.shouldChangeText(in: range, replacementString: insertionText) {
            self.replaceCharacters(in: range, with: insertionText)
            self.didChangeText()
        } else {
            self.insertText(insertionText, replacementRange: range)
        }
        
        let finalLength = (self.string as NSString).length
        let clampedCaret = min(max(0, postInsertCaret), finalLength)
        self.setSelectedRange(NSRange(location: clampedCaret, length: 0))
        (self.layoutManager as? LayoutManager)?.invalidateInlineImageLayout()
        self.scrollRangeToVisible(self.selectedRange())
        self.needsDisplay = true
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
        let previousSelectedRanges = self.selectedRanges.map(\.rangeValue)
        let previousLocation = self.selectedRange.location
        let previousHadSelection = !self.selectedRange.isEmpty
        let previousLineRects = self.lineHighlightRects
        let previousSelectionRect: NSRect? = previousHadSelection ? self.boundingRect(for: self.selectedRange) : nil
        
        if !stillSelectingFlag,
           !self.isUpdatingGhostSuggestion,
           ranges.count == 1,
           var proposed = ranges.first?.rangeValue,
           proposed.isEmpty,
           let snapped = self.snappedLocationOutsideInlineImageToken(proposed.location, previousLocation: previousLocation)
        {
            proposed.location = snapped
            ranges = [proposed as NSValue]
        }
        
        let shouldTrackVimCursor = !stillSelectingFlag
            && !self.isPerformingVimCursorMove
            && self.window?.isKeyWindow == true
            && UserDefaults.standard[.vimMode]
            && (VimState.shared.mode == .normal || VimState.shared.mode == .replace)
        let previousVimRect = shouldTrackVimCursor ? self.vimCursorRect(at: previousLocation) : nil
        
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
        
        let hasEmptySelection = selectedRanges.allSatisfy { $0.isEmpty }
        if !stillSelectingFlag, hasEmptySelection, NotesTextColorPaletteController.shared.isVisible {
            NotesTextColorPaletteController.shared.dismiss(animated: true)
        }
        if selectedRanges != previousSelectedRanges, previousHadSelection || !hasEmptySelection {
            if self.usesElasticVimVisualOverlay {
                // GPU CAShapeLayer renders the Visual selection; only clear the prior single-line
                // highlight when first entering Visual mode (zero full-viewport CPU redraws on j/k!).
                if !previousHadSelection {
                    for rect in previousLineRects {
                        let band = NSRect(x: self.visibleRect.minX,
                                          y: rect.minY - 6,
                                          width: self.visibleRect.width,
                                          height: rect.height + 12)
                        self.setNeedsDisplay(band, avoidAdditionalLayout: true)
                    }
                }
            } else {
                for rect in previousLineRects {
                    let band = NSRect(x: self.visibleRect.minX,
                                      y: rect.minY - 6,
                                      width: self.visibleRect.width,
                                      height: rect.height + 12)
                    self.setNeedsDisplay(band, avoidAdditionalLayout: true)
                }
                if let previousSelectionRect {
                    let band = NSRect(x: self.visibleRect.minX,
                                      y: previousSelectionRect.minY - 6,
                                      width: self.visibleRect.width,
                                      height: previousSelectionRect.height + 12)
                    self.setNeedsDisplay(band, avoidAdditionalLayout: true)
                }
                if !self.selectedRange.isEmpty, let currentSelectionRect = self.boundingRect(for: self.selectedRange) {
                    let band = NSRect(x: self.visibleRect.minX,
                                      y: currentSelectionRect.minY - 6,
                                      width: self.visibleRect.width,
                                      height: currentSelectionRect.height + 12)
                    self.setNeedsDisplay(band, avoidAdditionalLayout: true)
                }
            }
        }
        
        if !self.isUpdatingGhostSuggestion, selectedRanges != previousSelectedRanges {
            self.clearGhostSuggestion(animated: false)
        }
        
        // invalidate current instance highlights
        if self.highlightsSelectionInstance {
            self.instanceHighlightTask?.cancel()
        }
        // When the user clears or resizes a selection, force a repaint if rounded highlights were
        // present: TextKit can leave a 1px colored hairline where a rounded instance highlight sat.
        let hadRoundedHighlights = self.layoutManager?.hasTemporaryAttribute(.roundedBackgroundColor) == true
        if self.highlightsSelectionInstance || (previousHadSelection && hasEmptySelection) {
            self.clearSelectionInstanceHighlight(
                redraw: previousHadSelection && (hasEmptySelection || (hadRoundedHighlights && selectedRanges != previousSelectedRanges))
            )
        }
        
        let isRapidVimCursorSweep = self.isPerformingVimCursorMove && self.vimEngine.isContinuousMovement
        if !stillSelectingFlag, !self.isShowingCompletion, !isRapidVimCursorSweep {
            // highlight matching symbol
            if self.highlightsBraces {
                self.highlightMatchingSymbol(candidates: SymbolPair.braces)
            }
            
            // update instance highlights (skip while actively sweeping a Vim visual selection)
            let isVimVisual = UserDefaults.standard[.vimMode] && VimState.shared.mode == .visual
            if self.highlightsSelectionInstance, !isVimVisual {
                let delay: Duration = .seconds(self.selectionInstanceHighlightDelay)
                self.instanceHighlightTask?.cancel()
                self.instanceHighlightTask = Task { [weak self] in
                    try await Task.sleep(for: delay, tolerance: delay * 0.2)  // debounce
                    try await self?.highlightInstances()
                }
            }
        }
        
        if (self.layoutManager as? LayoutManager)?.rendersPlainTextInlineImages == true,
           !stillSelectingFlag,
           selectedRanges.count == 1,
           let newLoc = selectedRanges.first?.location,
           self.inlineImageCaretFrame(for: newLoc) != nil || self.inlineImageCaretFrame(for: previousLocation) != nil
        {
            self.needsLayout = true
            self.invalidateInsertionIndicatorDisplayMode()
        }
        
        if shouldTrackVimCursor,
           let newLocation = selectedRanges.first?.location,
           newLocation != previousLocation,
           let newVimRect = self.vimCursorRect(at: newLocation)
        {
            self.syncNativeCaretVisibility()
            self.funEffects.animateVimCursorTransition(
                from: previousVimRect,
                to: newVimRect,
                color: self.effectiveCursorColor
            )
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
        
        // Check right-click directly over an inline image first
        if (self.layoutManager as? LayoutManager)?.rendersPlainTextInlineImages == true {
            let point = self.convert(event.locationInWindow, from: nil)
            if let hit = self.inlineImageCardEntries.first(where: { $0.hitTestImage(point: point) }) {
                self.window?.makeFirstResponder(self)
                self.selectedInlineImageIdentifier = hit.identifier
                self.needsDisplay = true
                return self.makeInlineImageContextMenu(for: hit.identifier, tokenRange: hit.tokenRange)
            }
        }
        
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
    
    
    /// Computes a fast, zero-decode state snapshot used to drive context menu grouping and edge cases.
    func currentContextMenuState() -> EditorContextMenuState {
        
        let nsString = self.backingNSString
        let isEmpty = (nsString.length == 0)
        let selectedRange = self.selectedRange()
        let hasSelection = !selectedRange.isEmpty && selectedRange.upperBound <= nsString.length
        let selectedSnippet = hasSelection ? nsString.substring(with: selectedRange) : ""
        let canHighlight = hasSelection && NotesTextColorPaletteController.shouldPresent(for: selectedSnippet)
        
        let pboard = NSPasteboard.general
        let hasClipboardText = (pboard.types ?? []).contains(.string)
        let hasClipboardImage = PlainTextInlineImageStore.hasPasteableImage(in: pboard)
        
        let rendersInlineImages = (self.layoutManager as? LayoutManager)?.rendersPlainTextInlineImages == true
        let syntaxName = self.textStorage.flatMap { self.documentViewController?.document(for: $0)?.syntaxName }
        let inlineImagesPref = UserDefaults.standard.object(forKey: CotLocalDatabase.ConfigKey.plainTextInlineImagesEnabled) == nil
            ? true
            : UserDefaults.standard.bool(forKey: CotLocalDatabase.ConfigKey.plainTextInlineImagesEnabled)
        let supportsInlineImages = rendersInlineImages
            || (inlineImagesPref && syntaxName.map { PlainTextInlineImageStore.supportsInlineImages(syntaxName: $0) } == true)
        
        let hasTable: Bool
        if hasSelection, selectedSnippet.contains("|"), MarkdownTableFormatter.containsAnyTable(selectedSnippet) {
            hasTable = true
        } else if !isEmpty, nsString.range(of: "|", options: .literal).location != NSNotFound {
            hasTable = MarkdownTableFormatter.containsAnyTable(self.string)
        } else {
            hasTable = false
        }
        
        let controller = self.documentViewController
        return EditorContextMenuState(
            isEditable: self.isEditable,
            isEmptyDocument: isEmpty,
            hasSelection: hasSelection,
            selectedCharacterCount: selectedSnippet.count,
            canHighlightSelection: canHighlight,
            hasClipboardText: hasClipboardText,
            hasClipboardImage: hasClipboardImage,
            supportsInlineImages: supportsInlineImages,
            hasTable: hasTable,
            splitPaneCount: controller?.editorViewControllers.count ?? 1,
            showsLineNumber: controller?.showsLineNumber ?? true,
            hasDocumentController: controller != nil
        )
    }
    
    
    /// Builds the text view's categorized, high-craft right-click menu.
    ///
    /// Top hero 4-tile edit dock, contextual highlight bar, categorized AI/Structure/Media/View sections,
    /// zero tiny explainers, cached SF Symbols, and instant zero-decode clipboard detection.
    func makeContextMenu() -> NSMenu {
        
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.minimumWidth = EditorContextMenuMetrics.menuWidth
        let state = self.currentContextMenuState()
        
        // 1. Hero Top 4-Tile Edit Dock (Cut / Copy / Paste / Select All)
        let dockItem = NSMenuItem(title: AppLanguage.text("编辑", en: "Edit"), action: nil, keyEquivalent: "")
        dockItem.view = ContextMenuActionDockView(actions: [
            ContextMenuDockAction(
                title: AppLanguage.text("剪切", en: "Cut"),
                symbolName: "scissors",
                toolTip: AppLanguage.text("剪切 (⌘X)", en: "Cut (⌘X)"),
                isEnabled: state.canCut
            ) { [weak self, weak menu] in
                menu?.cancelTracking()
                self?.cut(nil)
            },
            ContextMenuDockAction(
                title: AppLanguage.text("拷贝", en: "Copy"),
                symbolName: "doc.on.doc",
                toolTip: AppLanguage.text("拷贝 (⌘C)", en: "Copy (⌘C)"),
                isEnabled: state.canCopy
            ) { [weak self, weak menu] in
                menu?.cancelTracking()
                self?.copy(nil)
            },
            ContextMenuDockAction(
                title: AppLanguage.text("粘贴", en: "Paste"),
                symbolName: state.showsClipboardImageHint ? "photo.on.rectangle" : "doc.on.clipboard",
                toolTip: state.showsClipboardImageHint
                    ? AppLanguage.text("粘贴图片 (⌘V)", en: "Paste Image (⌘V)")
                    : AppLanguage.text("粘贴 (⌘V)", en: "Paste (⌘V)"),
                isEnabled: state.canPaste,
                showsAccentDot: state.showsClipboardImageHint
            ) { [weak self, weak menu] in
                menu?.cancelTracking()
                self?.paste(nil)
            },
            ContextMenuDockAction(
                title: AppLanguage.text("全选", en: "All"),
                symbolName: "selection.pin.in.out",
                toolTip: AppLanguage.text("全选 (⌘A)", en: "Select All (⌘A)"),
                isEnabled: state.canSelectAll
            ) { [weak self, weak menu] in
                menu?.cancelTracking()
                self?.selectAll(nil)
            },
        ])
        menu.addItem(dockItem)
        
        // 2. Contextual 1-Click Highlight Swatch Row (selection-only & editable-only)
        if let documentViewController = self.documentViewController, state.showsHighlightBar {
            let swatchRowItem = NSMenuItem()
            swatchRowItem.view = ContextMenuQuickHighlightRowView(
                target: documentViewController,
                onSelectColorIndex: { [weak documentViewController, weak menu] index in
                    menu?.cancelTracking()
                    let dummy = NSMenuItem()
                    dummy.tag = index
                    documentViewController?.applyHighlight(dummy)
                },
                onOpenPalette: { [weak documentViewController, weak menu] in
                    menu?.cancelTracking()
                    documentViewController?.openHighlightColorPalette(nil)
                },
                onClearHighlight: { [weak documentViewController, weak menu] in
                    menu?.cancelTracking()
                    documentViewController?.removeHighlight(nil)
                }
            )
            menu.addItem(swatchRowItem)
        }
        
        guard let documentViewController = self.documentViewController else {
            menu.addItem(.separator())
            menu.addItem(.sectionHeader(title: AppLanguage.text("行编辑", en: "Line Actions")))
            for item in self.makeLineActionMenuItems(state: state) {
                menu.addItem(item)
            }
            return menu
        }
        
        self.appendAIContextMenuSection(to: menu, state: state, controller: documentViewController)
        self.appendStructureAndLineMenuSection(to: menu, state: state, controller: documentViewController)
        self.appendMediaAndWorkflowMenuSection(to: menu, state: state, controller: documentViewController)
        self.appendViewMenuSection(to: menu, state: state, controller: documentViewController)
        
        return menu
    }
    
    
    private func makeContextMenuItem(
        title: String,
        symbol: String,
        action: Selector?,
        target: AnyObject? = nil,
        keyEquivalent: String = "",
        modifiers: NSEvent.ModifierFlags = .command,
        enabled: Bool = true
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        if !keyEquivalent.isEmpty {
            item.keyEquivalentModifierMask = modifiers
        }
        item.target = target
        item.isEnabled = enabled
        item.image = Self.contextMenuSymbol(symbol)
        return item
    }
    
    
    private func makeLineActionMenuItems(state: EditorContextMenuState) -> [NSMenuItem] {
        [
            self.makeContextMenuItem(
                title: AppLanguage.text("复制当前行", en: "Duplicate Line"),
                symbol: "plus.square.on.square",
                action: #selector(duplicateLine(_:)),
                target: self,
                enabled: state.canEditLines
            ),
            self.makeContextMenuItem(
                title: AppLanguage.text("删除当前行", en: "Delete Line"),
                symbol: "minus.square",
                action: #selector(deleteLine(_:)),
                target: self,
                enabled: state.canEditLines
            ),
            self.makeContextMenuItem(
                title: AppLanguage.text("去除行尾空格", en: "Trim Trailing Whitespace"),
                symbol: "text.badge.minus",
                action: #selector(trimTrailingWhitespace(_:)),
                target: self,
                enabled: state.canEditLines
            ),
            self.makeContextMenuItem(
                title: AppLanguage.text("按行升序排列", en: "Sort Lines Ascending"),
                symbol: "arrow.up.arrow.down",
                action: #selector(sortLinesAscending(_:)),
                target: self,
                enabled: state.canEditLines
            ),
        ]
    }
    
    
    private func appendAIContextMenuSection(
        to menu: NSMenu,
        state: EditorContextMenuState,
        controller: DocumentViewController
    ) {
        menu.addItem(.separator())
        menu.addItem(.sectionHeader(title: AppLanguage.text("AI 助手", en: "AI Assistant")))
        
        let isEnglish = (AppLanguage.current(in: .standard) == .english)
        let butlerItem = NSMenuItem(title: AppLanguage.text("问总管", en: "Ask Butler"), action: nil, keyEquivalent: "")
        butlerItem.view = ContextMenuFeaturedActionRowView(
            title: AppLanguage.text("问总管", en: "Ask Butler"),
            symbolName: "bubble.left.and.text.bubble.right",
            badgeText: state.butlerContextBadge(isEnglish: isEnglish)
        ) { [weak controller, weak menu] in
            menu?.cancelTracking()
            controller?.askButlerWithSelection(nil)
        }
        menu.addItem(butlerItem)
        
        let chipsItem = NSMenuItem(title: AppLanguage.text("选区快捷指令", en: "Quick AI"), action: nil, keyEquivalent: "")
        chipsItem.view = ContextMenuChipStripView(chips: [
            ContextMenuChipAction(
                title: AppLanguage.text("翻译", en: "Translate"),
                symbolName: "character.bubble",
                isEnabled: state.hasSelection
            ) { [weak controller, weak menu] in
                menu?.cancelTracking()
                controller?.translateSelection(nil)
            },
            ContextMenuChipAction(
                title: AppLanguage.text("总结", en: "Summarize"),
                symbolName: "text.alignleft",
                isEnabled: state.hasSelection
            ) { [weak controller, weak menu] in
                menu?.cancelTracking()
                controller?.summarizeSelection(nil)
            },
            ContextMenuChipAction(
                title: AppLanguage.text("解释", en: "Explain"),
                symbolName: "lightbulb",
                isEnabled: state.hasSelection
            ) { [weak controller, weak menu] in
                menu?.cancelTracking()
                controller?.explainSelection(nil)
            },
        ])
        menu.addItem(chipsItem)
    }
    
    
    private func appendStructureAndLineMenuSection(
        to menu: NSMenu,
        state: EditorContextMenuState,
        controller: DocumentViewController
    ) {
        menu.addItem(.separator())
        menu.addItem(.sectionHeader(title: AppLanguage.text("排版与规整", en: "Format & Structure")))
        
        menu.addItem(self.makeContextMenuItem(
            title: AppLanguage.text("清洗规整", en: "Clean & Structure"),
            symbol: "list.bullet.indent",
            action: #selector(DocumentViewController.cleanAndStructureText(_:)),
            target: controller,
            enabled: state.canCleanStructure
        ))
        
        menu.addItem(self.makeContextMenuItem(
            title: AppLanguage.text("语义规整", en: "Semantic Restructure"),
            symbol: "doc.plaintext",
            action: #selector(DocumentViewController.semanticRestructureText(_:)),
            target: controller,
            enabled: state.canSemanticRestructure
        ))
        
        if state.hasTable {
            menu.addItem(self.makeContextMenuItem(
                title: AppLanguage.text("一键对齐表格", en: "Align Table"),
                symbol: "arrow.left.and.right.text.vertical",
                action: #selector(DocumentViewController.alignMarkdownTable(_:)),
                target: controller,
                enabled: state.canAlignTable
            ))
        }
        
        let lineSubmenu = NSMenu()
        lineSubmenu.autoenablesItems = false
        for item in self.makeLineActionMenuItems(state: state) {
            lineSubmenu.addItem(item)
        }
        lineSubmenu.addItem(self.makeContextMenuItem(
            title: AppLanguage.text("合并行", en: "Join Lines"),
            symbol: "arrow.triangle.merge",
            action: #selector(joinLines(_:)),
            target: self,
            enabled: state.canEditLines
        ))
        let lineRoot = self.makeContextMenuItem(
            title: AppLanguage.text("行编辑", en: "Line Actions"),
            symbol: "text.line.first.and.arrowtriangle.forward",
            action: nil,
            enabled: state.canEditLines
        )
        lineRoot.submenu = lineSubmenu
        menu.addItem(lineRoot)
    }
    
    
    private func appendMediaAndWorkflowMenuSection(
        to menu: NSMenu,
        state: EditorContextMenuState,
        controller: DocumentViewController
    ) {
        menu.addItem(.separator())
        menu.addItem(.sectionHeader(title: AppLanguage.text("媒体与工作流", en: "Media & Workflows")))
        
        if state.supportsInlineImages {
            menu.addItem(self.makeContextMenuItem(
                title: AppLanguage.text("插入图片…", en: "Insert Image…"),
                symbol: "photo.badge.plus",
                action: #selector(DocumentViewController.insertPlainTextImage(_:)),
                target: controller,
                enabled: state.canInsertInlineImage
            ))
        }
        
        menu.addItem(self.makeContextMenuItem(
            title: AIAction.ocrPolish.title,
            symbol: "doc.text.viewfinder",
            action: #selector(DocumentViewController.runOCRAndAI(_:)),
            target: controller,
            enabled: true
        ))
        
        let tableSubmenu = NSMenu()
        tableSubmenu.autoenablesItems = false
        tableSubmenu.addItem(self.makeContextMenuItem(
            title: AppLanguage.text("对齐 Markdown 表格", en: "Align Markdown Table"),
            symbol: "arrow.left.and.right.text.vertical",
            action: #selector(DocumentViewController.alignMarkdownTable(_:)),
            target: controller,
            enabled: state.canAlignTable
        ))
        tableSubmenu.addItem(self.makeContextMenuItem(
            title: AIAction.interactiveChart.title,
            symbol: "chart.xyaxis.line",
            action: #selector(DocumentViewController.generateInteractiveChart(_:)),
            target: controller,
            enabled: state.canInteractiveChart
        ))
        let tableRoot = self.makeContextMenuItem(
            title: AppLanguage.text("表格与图表", en: "Tables & Charts"),
            symbol: "tablecells",
            action: nil
        )
        tableRoot.submenu = tableSubmenu
        menu.addItem(tableRoot)
        
        let weeklySubmenu = NSMenu()
        weeklySubmenu.autoenablesItems = false
        weeklySubmenu.addItem(self.makeContextMenuItem(
            title: AIAction.weeklyReportItem.title,
            symbol: "text.badge.plus",
            action: #selector(DocumentViewController.generateWeeklyReportItem(_:)),
            target: controller,
            enabled: state.hasSelection
        ))
        weeklySubmenu.addItem(self.makeContextMenuItem(
            title: AIAction.weeklyReport.title,
            symbol: "doc.text.image",
            action: #selector(DocumentViewController.generateWeeklyReport(_:)),
            target: controller,
            enabled: true
        ))
        let weeklyRoot = self.makeContextMenuItem(
            title: AppLanguage.text("周报助手", en: "Weekly Report"),
            symbol: "calendar.badge.checkmark",
            action: nil
        )
        weeklyRoot.submenu = weeklySubmenu
        menu.addItem(weeklyRoot)
        
        menu.addItem(self.makeContextMenuItem(
            title: AIAction.organizeAndMerge.title,
            symbol: "square.stack.3d.up",
            action: #selector(DocumentViewController.organizeAndMergeAllDocuments(_:)),
            target: controller,
            enabled: true
        ))
        
        if PiKernelManager.shared.isAvailable {
            let piSubmenu = NSMenu()
            piSubmenu.autoenablesItems = false
            for botID in AIBotID.allCases where botID != .ghost && botID != .persona && botID != .readingCompanion {
                guard AIBotStore.shared.config(for: botID).isEnabled else { continue }
                let botItem = self.makeContextMenuItem(
                    title: "\(botID.displayName)  \(botID.handle)",
                    symbol: botID.symbolName,
                    action: #selector(DocumentViewController.launchPiBotFromMenu(_:)),
                    target: controller,
                    enabled: true
                )
                botItem.representedObject = botID.rawValue
                piSubmenu.addItem(botItem)
            }
            if !piSubmenu.items.isEmpty {
                let piRoot = self.makeContextMenuItem(
                    title: AppLanguage.text("终端 Pi Bot", en: "Pi Bot in Terminal"),
                    symbol: "terminal",
                    action: nil
                )
                piRoot.submenu = piSubmenu
                menu.addItem(piRoot)
            }
        }
    }
    
    
    private func appendViewMenuSection(
        to menu: NSMenu,
        state: EditorContextMenuState,
        controller: DocumentViewController
    ) {
        menu.addItem(.separator())
        let viewSubmenu = NSMenu()
        viewSubmenu.autoenablesItems = false
        viewSubmenu.addItem(self.makeContextMenuItem(
            title: AppLanguage.text("向右分屏", en: "Split Right"),
            symbol: "rectangle.split.2x1",
            action: #selector(DocumentViewController.splitEditorVertically(_:)),
            target: controller,
            enabled: true
        ))
        viewSubmenu.addItem(self.makeContextMenuItem(
            title: AppLanguage.text("向下分屏", en: "Split Down"),
            symbol: "rectangle.split.1x2",
            action: #selector(DocumentViewController.splitEditorHorizontally(_:)),
            target: controller,
            enabled: true
        ))
        if state.splitPaneCount > 1 {
            viewSubmenu.addItem(self.makeContextMenuItem(
                title: AppLanguage.text("关闭当前分栏", en: "Close Split Pane"),
                symbol: "xmark.rectangle",
                action: #selector(DocumentViewController.closeSplitTextView(_:)),
                target: controller,
                enabled: true
            ))
        }
        viewSubmenu.addItem(.separator())
        viewSubmenu.addItem(self.makeContextMenuItem(
            title: state.showsLineNumber
                ? AppLanguage.text("隐藏行号", en: "Hide Line Numbers")
                : AppLanguage.text("显示行号", en: "Show Line Numbers"),
            symbol: "list.number",
            action: #selector(DocumentViewController.toggleLineNumber(_:)),
            target: controller,
            enabled: true
        ))
        let viewRoot = self.makeContextMenuItem(
            title: AppLanguage.text("分屏与视图", en: "Split & View"),
            symbol: "rectangle.split.2x1",
            action: nil
        )
        viewRoot.submenu = viewSubmenu
        menu.addItem(viewRoot)
    }
    
    
    /// Returns a consistently sized cached template SF Symbol image for context menu items.
    private static func contextMenuSymbol(_ name: String) -> NSImage? {
        EditorContextMenuSymbols.image(named: name, pointSize: 13, weight: .medium)
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
            self.clearGhostSuggestion(animated: false)
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
        
        guard let rawRange = self.range(for: rect) else { return }
        let storageLength = self.textStorage?.length ?? (self.string as NSString).length
        let range = NSIntersectionRange(rawRange, NSRange(location: 0, length: storageLength))
        guard range.location != NSNotFound else { return }
        
        if self.highlightsCurrentLines, !self.usesElasticVimVisualOverlay {
            self.drawCurrentLine(range: range, in: rect)
        }
        
        if range.length > 0 {
            self.drawNotesHighlights(range: range, in: rect)
            self.drawRoundedBackground(range: range, in: rect)
        }
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
            !self.funEffects.isVimCursorInFlight,
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
    
    
    /// Handles trackpad pinch gesture when an inline image is selected or under the pointer.
    func handleInlineImageMagnify(with event: NSEvent) -> Bool {
        
        guard self.isEditable,
              (self.layoutManager as? LayoutManager)?.rendersPlainTextInlineImages == true else {
            return false
        }
        let point = self.convert(event.locationInWindow, from: nil)
        let targetEntry: InlineImageCardEntry? = {
            if let activeID = self.activePinchImageID,
               let active = self.inlineImageCardEntries.first(where: { $0.identifier == activeID })
            {
                return active
            }
            return self.inlineImageCardEntries.first(where: { $0.hitTestImage(point: point) })
                ?? self.selectedInlineImageEntry()
        }()
        guard let entry = targetEntry else {
            return false
        }
        
        let isEnded = (event.phase == .ended || event.phase == .cancelled)
        self.selectedInlineImageIdentifier = entry.identifier
        self.isLiveManipulatingInlineImage = !isEnded
        
        let docURL = self.currentInlineImageDocURL
        let currentTx = PlainTextInlineImageStore.shared.transform(for: entry.identifier, documentURL: docURL)
        let factor = max(0.5, min(2.0, 1.0 + event.magnification))
        let containerW = self.effectiveInlineImageContainerWidth
        let maxImgW = PlainTextInlineImageStore.effectiveMaxImageWidth(containerWidth: containerW, glyphX: 0)
        
        let updatedTx: InlineImageTransform
        if let naturalSize = PlainTextInlineImageStore.shared.naturalSize(for: entry.identifier, documentURL: docURL),
           naturalSize.width > 0, naturalSize.height > 0
        {
            let base = InlineImageZoomMath.baseDrawSize(naturalSize: naturalSize, maxImageWidth: maxImgW)
            let canvasMaxW = InlineImageZoomMath.canvasMaxWidth(containerWidth: containerW, maxImageWidth: maxImgW)
            let minSize = InlineImageZoomMath.clampedAspectSize(
                desiredWidth: max(1, base.width * InlineImageZoomMath.minScaleFloor),
                naturalSize: naturalSize,
                maxWidth: canvasMaxW
            )
            let maxSize = InlineImageZoomMath.clampedAspectSize(
                desiredWidth: base.width * InlineImageZoomMath.maxScaleCeiling,
                naturalSize: naturalSize,
                maxWidth: canvasMaxW
            )
            
            // Accumulate continuous floating-point width across the pinch so micro-deltas never stall on integer rounding.
            let seedWidth: CGFloat
            if self.activePinchImageID == entry.identifier, let existing = self.activePinchWidth {
                seedWidth = existing
            } else {
                let liveGeom = PlainTextInlineImageStore.shared.displayGeometry(
                    for: entry.identifier,
                    documentURL: docURL,
                    containerWidth: containerW,
                    maxImageWidth: maxImgW
                )
                seedWidth = liveGeom?.drawSize.width ?? entry.drawSize.width
                self.activePinchImageID = entry.identifier
                self.didCrossPinch100Percent = abs(seedWidth - base.width) < 3.0
            }
            let prevScale = seedWidth / max(1, base.width)
            let nextWidth = max(minSize.width, min(maxSize.width, seedWidth * factor))
            self.activePinchWidth = nextWidth
            let nextScale = nextWidth / max(1, base.width)
            
            if !self.didCrossPinch100Percent,
               (prevScale < 1.0 && nextScale >= 1.0) || (prevScale > 1.0 && nextScale <= 1.0)
            {
                self.didCrossPinch100Percent = true
                NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
            } else if abs(nextScale - 1.0) > 0.08 {
                self.didCrossPinch100Percent = false
            }
            
            updatedTx = InlineImageZoomMath.transformForTargetScale(
                nextScale,
                baseTransform: currentTx,
                naturalSize: naturalSize,
                containerWidth: containerW,
                maxImageWidth: maxImgW
            )
        } else {
            var fallback = currentTx
            fallback.scale = max(InlineImageZoomMath.minScaleFloor, min(InlineImageZoomMath.maxScaleCeiling, currentTx.scale * factor))
            fallback.customWidth = nil
            fallback.customHeight = nil
            updatedTx = fallback.clamped()
        }
        
        PlainTextInlineImageStore.shared.setTransform(
            updatedTx,
            for: entry.identifier,
            documentURL: docURL,
            persist: isEnded
        )
        
        if isEnded {
            self.activePinchImageID = nil
            self.activePinchWidth = nil
            self.didCrossPinch100Percent = false
            self.liveInlineImageHUDText = nil
            self.applyInlineImageLayoutUpdate(in: entry.tokenRange, isLiveManipulation: false)
        } else {
            let pct = Int((updatedTx.scale * 100).rounded())
            if let cw = updatedTx.customWidth, let ch = updatedTx.customHeight {
                self.liveInlineImageHUDText = "\(pct)% · \(Int(round(cw))) × \(Int(round(ch)))"
            } else {
                self.liveInlineImageHUDText = "\(pct)%"
            }
            self.applyInlineImageLayoutUpdate(in: entry.tokenRange, isLiveManipulation: true)
        }
        return true
    }
    
    
    /// Handles two-finger double-tap on an inline image to toggle between `100%` and fit-width.
    func handleInlineImageSmartMagnify(with event: NSEvent) -> Bool {
        
        guard self.isEditable,
              (self.layoutManager as? LayoutManager)?.rendersPlainTextInlineImages == true else {
            return false
        }
        let point = self.convert(event.locationInWindow, from: nil)
        let targetEntry = self.inlineImageCardEntries.first(where: { $0.hitTestImage(point: point) })
            ?? self.selectedInlineImageEntry()
        guard let entry = targetEntry else {
            return false
        }
        
        let docURL = self.currentInlineImageDocURL
        guard let naturalSize = PlainTextInlineImageStore.shared.naturalSize(for: entry.identifier, documentURL: docURL),
              naturalSize.width > 0, naturalSize.height > 0
        else { return false }
        
        let containerW = self.effectiveInlineImageContainerWidth
        let maxImgW = PlainTextInlineImageStore.effectiveMaxImageWidth(containerWidth: containerW, glyphX: 0)
        let bounds = InlineImageZoomMath.scaleBounds(
            naturalSize: naturalSize,
            containerWidth: containerW,
            maxImageWidth: maxImgW
        )
        let currentScale = InlineImageZoomMath.effectiveScale(
            drawWidth: entry.drawSize.width,
            naturalSize: naturalSize,
            maxImageWidth: maxImgW
        )
        let nextScale: CGFloat = (abs(currentScale - 1.0) < 0.08 && bounds.upperBound > 1.08)
            ? bounds.upperBound
            : 1.0
        
        self.applyInlineImageSteplessScale(nextScale, for: entry.identifier, tokenRange: entry.tokenRange)
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
        return true
    }
    
    
    /// Applies a stepless target scale to an inline image, keeping `scale` and `customWidth`/`customHeight` synchronized.
    @discardableResult
    func applyInlineImageSteplessScale(
        _ requestedScale: CGFloat,
        for identifier: String,
        tokenRange: NSRange? = nil
    ) -> InlineImageTransform {
        
        let docURL = self.currentInlineImageDocURL
        let currentTx = PlainTextInlineImageStore.shared.transform(for: identifier, documentURL: docURL)
        let containerW = self.effectiveInlineImageContainerWidth
        let maxImgW = PlainTextInlineImageStore.effectiveMaxImageWidth(containerWidth: containerW, glyphX: 0)
        
        let resolved: InlineImageTransform
        if let naturalSize = PlainTextInlineImageStore.shared.naturalSize(for: identifier, documentURL: docURL),
           naturalSize.width > 0, naturalSize.height > 0
        {
            resolved = InlineImageZoomMath.transformForTargetScale(
                requestedScale,
                baseTransform: currentTx,
                naturalSize: naturalSize,
                containerWidth: containerW,
                maxImageWidth: maxImgW
            )
        } else {
            var copy = currentTx
            copy.scale = max(InlineImageZoomMath.minScaleFloor, min(InlineImageZoomMath.maxScaleCeiling, requestedScale))
            copy.customWidth = nil
            copy.customHeight = nil
            resolved = copy.clamped()
        }
        
        PlainTextInlineImageStore.shared.setTransform(resolved, for: identifier, documentURL: docURL)
        self.selectedInlineImageIdentifier = identifier
        self.applyInlineImageLayoutUpdate(in: tokenRange)
        return resolved
    }
    
    
    /// Trackpad two-finger rotation gesture on a selected or hovered inline image performs stepless angle adjustment.
    override func rotate(with event: NSEvent) {
        
        guard self.isEditable,
              (self.layoutManager as? LayoutManager)?.rendersPlainTextInlineImages == true else {
            super.rotate(with: event)
            return
        }
        let point = self.convert(event.locationInWindow, from: nil)
        let targetEntry = self.selectedInlineImageEntry()
            ?? self.inlineImageCardEntries.first(where: { $0.hitTestImage(point: point) })
        guard let entry = targetEntry else {
            super.rotate(with: event)
            return
        }
        
        self.selectedInlineImageIdentifier = entry.identifier
        let docURL = self.currentInlineImageDocURL
        var tx = PlainTextInlineImageStore.shared.transform(for: entry.identifier, documentURL: docURL)
        var rawDeg = tx.rotationDegrees - CGFloat(event.rotation)
        if rawDeg > 180 { rawDeg -= 360 }
        if rawDeg < -180 { rawDeg += 360 }
        if event.phase == .ended {
            rawDeg = Self.snappedImageAngleIfNearCardinal(rawDeg)
            self.liveInlineImageHUDText = nil
        } else {
            self.liveInlineImageHUDText = String(format: "%.1f°", rawDeg)
        }
        tx.rotationDegrees = rawDeg
        PlainTextInlineImageStore.shared.setTransform(tx, for: entry.identifier, documentURL: docURL)
        self.applyInlineImageLayoutUpdate()
    }
    
    
    /// Returns a finite, bounded container width for inline image layout & manipulation even when line wrapping is disabled.
    private var effectiveInlineImageContainerWidth: CGFloat {
        let rawContainerW = self.textContainer?.size.width ?? self.bounds.width
        let finiteContainerW = (rawContainerW.isFinite && rawContainerW > 0 && rawContainerW <= 100_000)
            ? rawContainerW
            : (self.enclosingScrollView?.documentVisibleRect.width ?? self.bounds.width)
        return max(160, finiteContainerW.isFinite ? min(16_384, finiteContainerW) : 800)
    }
    
    
    /// Renders inline image cards (supporting stepless scale, offset, rotation, and Freeform selection handles).
    private func drawPlainTextInlineImages(in dirtyRect: NSRect) {
        
        self.inlineImageCardEntries.removeAll()
        
        // Scan `visibleRect` (falling back to `dirtyRect`) so partial repaints (caret blink / line highlight)
        // never wipe `inlineImageCardEntries` and break hit-testing for visible images.
        let scanRect = self.visibleRect.isEmpty ? dirtyRect : self.visibleRect.union(dirtyRect)
        guard
            let layoutManager = self.layoutManager as? LayoutManager,
            let rawVisibleCharRange = self.range(for: scanRect, withoutAdditionalLayout: true)
        else { return }
        
        let nsString = self.backingNSString
        guard nsString.length > 0 else { return }
        
        let visibleCharRange = NSIntersectionRange(rawVisibleCharRange, NSRange(location: 0, length: nsString.length))
        guard visibleCharRange.location != NSNotFound, visibleCharRange.length > 0 else { return }
        
        let expandedRange = nsString.lineRange(for: visibleCharRange)
        let tokens = PlainTextInlineImageStore.shared.findTokens(in: nsString, range: expandedRange)
        guard !tokens.isEmpty else { return }
        
        let docURL = self.currentInlineImageDocURL
        let borderColor = (self.theme?.text.color ?? .labelColor).withAlphaComponent(0.12)
        let fillColor = self.theme?.background.color ?? .controlBackgroundColor
        let accentColor = StudioPaletteManager.shared.activeNSAccentColor
        let containerWidth = self.effectiveInlineImageContainerWidth
        let canvasMidX = self.textContainerOrigin.x + containerWidth * 0.5
        
        if self.showInlineImageCenterGuide {
            NSGraphicsContext.saveGraphicsState()
            let guide = NSBezierPath()
            guide.setLineDash([4, 4], count: 2, phase: 0)
            guide.lineWidth = 1.0
            guide.move(to: NSPoint(x: canvasMidX, y: dirtyRect.minY))
            guide.line(to: NSPoint(x: canvasMidX, y: dirtyRect.maxY))
            accentColor.withAlphaComponent(0.65).setStroke()
            guide.stroke()
            NSGraphicsContext.restoreGraphicsState()
        }
        
        for token in tokens {
            guard let image = PlainTextInlineImageStore.shared.image(for: token.identifier, documentURL: docURL) else { continue }
            
            let glyphIndex = layoutManager.glyphIndexForCharacter(at: token.range.location)
            guard layoutManager.isValidGlyphIndex(glyphIndex) else { continue }
            
            let fragmentRect = layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: nil, withoutAdditionalLayout: true)
            let glyphLocation = layoutManager.location(forGlyphAt: glyphIndex)
            let maxCardWidth = PlainTextInlineImageStore.effectiveMaxImageWidth(
                containerWidth: containerWidth,
                glyphX: glyphLocation.x
            )
            
            guard let geom = PlainTextInlineImageStore.shared.displayGeometry(
                for: token.identifier,
                documentURL: docURL,
                containerWidth: containerWidth,
                maxImageWidth: maxCardWidth
            ) else { continue }
            
            let tx = geom.transform
            let boxW = geom.rotatedBoxSize.width + 8
            let boxH = geom.rotatedBoxSize.height + 8
            let baseX = fragmentRect.minX + self.textContainerOrigin.x + glyphLocation.x
            let minX = self.textContainerOrigin.x + 8
            let maxX = max(minX, self.textContainerOrigin.x + containerWidth - boxW - 8)
            let clampedX = min(maxX, max(minX, baseX + tx.offsetX))
            let cardTopY = fragmentRect.minY + self.textContainerOrigin.y + 4 + max(0, tx.offsetY)
            
            let cardRect = NSRect(x: clampedX, y: cardTopY, width: boxW, height: boxH)
            let center = NSPoint(x: cardRect.midX, y: cardRect.midY)
            let unrotatedCardRect = NSRect(
                x: -geom.drawSize.width * 0.5 - 4,
                y: -geom.drawSize.height * 0.5 - 4,
                width: geom.drawSize.width + 8,
                height: geom.drawSize.height + 8
            )
            let entry = InlineImageCardEntry(
                rect: cardRect,
                unrotatedCardSize: unrotatedCardRect.size,
                drawSize: geom.drawSize,
                center: center,
                rotationDegrees: tx.rotationDegrees,
                scale: tx.scale,
                baseAnchorX: baseX,
                identifier: token.identifier,
                tokenRange: token.range
            )
            self.inlineImageCardEntries.append(entry)
            
            let isSelected = (self.selectedInlineImageIdentifier == token.identifier)
            let isHoveredImage = (!isSelected && self.hoveredInlineImageIdentifier == token.identifier)
            let repaintBounds = (isSelected || isHoveredImage) ? cardRect.insetBy(dx: -48, dy: -52) : cardRect
            guard repaintBounds.intersects(dirtyRect) else { continue }
            
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current?.imageInterpolation = self.isLiveManipulatingInlineImage ? .medium : .high
            
            let xform = NSAffineTransform()
            xform.translateX(by: center.x, yBy: center.y)
            xform.rotate(byDegrees: tx.rotationDegrees)
            xform.concat()
            
            let cardPath = NSBezierPath(roundedRect: unrotatedCardRect, xRadius: isSelected ? 2 : 6, yRadius: isSelected ? 2 : 6)
            fillColor.setFill()
            cardPath.fill()
            if !isSelected {
                let frameStroke = isHoveredImage
                    ? NSColor.labelColor.withAlphaComponent(0.32)
                    : borderColor
                frameStroke.setStroke()
                cardPath.lineWidth = isHoveredImage ? 1.25 : 0.75
                cardPath.stroke()
            }
            
            let drawRect = unrotatedCardRect.insetBy(dx: 4, dy: 4)
            let clipPath = NSBezierPath(roundedRect: drawRect, xRadius: isSelected ? 1 : 4, yRadius: isSelected ? 1 : 4)
            clipPath.addClip()
            image.draw(
                in: drawRect,
                from: .zero,
                operation: .sourceOver,
                fraction: 1.0,
                respectFlipped: true,
                hints: nil
            )
            NSGraphicsContext.restoreGraphicsState()
            
            if isSelected {
                self.drawSelectionHandles(for: entry, accentColor: accentColor, haloColor: fillColor)
            } else if isHoveredImage {
                self.drawHoverAffordance(for: entry, haloColor: fillColor)
            }
        }
    }
    
    
    /// Draws clear hover feedback on an unselected inline image: architectural corner resize ticks,
    /// highlighted corner handle when pointer nears a corner/edge, and a quiet size readout pill.
    private func drawHoverAffordance(for entry: InlineImageCardEntry, haloColor: NSColor) {
        let unrotatedRect = NSRect(
            x: -entry.unrotatedCardSize.width * 0.5,
            y: -entry.unrotatedCardSize.height * 0.5,
            width: entry.unrotatedCardSize.width,
            height: entry.unrotatedCardSize.height
        )
        let activeHandle = self.hoveredResizeHandle
        let neutralInk = NSColor.labelColor.withAlphaComponent(0.68)
        let accentBlue = NSColor(srgbRed: 30.0 / 255.0, green: 137.0 / 255.0, blue: 245.0 / 255.0, alpha: 1.0)
        
        NSGraphicsContext.saveGraphicsState()
        let xform = NSAffineTransform()
        xform.translateX(by: entry.center.x, yBy: entry.center.y)
        xform.rotate(byDegrees: entry.rotationDegrees)
        xform.concat()
        
        // 1. Four crisp corner brackets communicating immediate resize affordance
        let arm: CGFloat = min(13, max(8, min(unrotatedRect.width, unrotatedRect.height) * 0.14))
        let corners: [(BoundingBoxHandle, NSPoint, CGFloat, CGFloat)] = [
            (.topLeft, NSPoint(x: unrotatedRect.minX, y: unrotatedRect.minY), 1, 1),
            (.topRight, NSPoint(x: unrotatedRect.maxX, y: unrotatedRect.minY), -1, 1),
            (.bottomLeft, NSPoint(x: unrotatedRect.minX, y: unrotatedRect.maxY), 1, -1),
            (.bottomRight, NSPoint(x: unrotatedRect.maxX, y: unrotatedRect.maxY), -1, -1),
        ]
        for (handle, pt, sx, sy) in corners {
            let isHot = (activeHandle == handle)
            let bracket = NSBezierPath()
            bracket.lineCapStyle = .round
            bracket.lineJoinStyle = .round
            bracket.move(to: NSPoint(x: pt.x + sx * arm, y: pt.y))
            bracket.line(to: pt)
            bracket.line(to: NSPoint(x: pt.x, y: pt.y + sy * arm))
            
            haloColor.withAlphaComponent(0.92).setStroke()
            bracket.lineWidth = isHot ? 4.4 : 3.2
            bracket.stroke()
            
            (isHot ? accentBlue : neutralInk).setStroke()
            bracket.lineWidth = isHot ? 2.4 : 1.75
            bracket.stroke()
        }
        
        // 2. If pointer is over any corner/edge handle, highlight the exact grab knob
        if let activeHandle {
            let localPt = activeHandle.localPoint(size: entry.unrotatedCardSize)
            let haloRect = NSRect(x: localPt.x - 8, y: localPt.y - 8, width: 16, height: 16)
            accentBlue.withAlphaComponent(0.20).setFill()
            NSBezierPath(ovalIn: haloRect).fill()
            
            let knobRect = NSRect(x: localPt.x - 5, y: localPt.y - 5, width: 10, height: 10)
            let knobPath = NSBezierPath(ovalIn: knobRect)
            NSColor.white.setFill()
            knobPath.fill()
            accentBlue.setStroke()
            knobPath.lineWidth = 1.6
            knobPath.stroke()
        }
        NSGraphicsContext.restoreGraphicsState()
        
        // 3. Quiet bottom-right scale & pixel readout pill inside card bounds
        let pct = Int((entry.scale * 100).rounded())
        let label = "\(pct)% · \(Int(round(entry.drawSize.width)))×\(Int(round(entry.drawSize.height)))"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .medium),
            .foregroundColor: NSColor.white.withAlphaComponent(0.95),
        ]
        let attrStr = NSAttributedString(string: label, attributes: attrs)
        let sz = attrStr.size()
        let pillW = sz.width + 12
        let pillH: CGFloat = 18
        if entry.rect.width >= pillW + 18 && entry.rect.height >= 44 {
            let pillRect = NSRect(
                x: entry.rect.maxX - pillW - 8,
                y: entry.rect.maxY - pillH - 8,
                width: pillW,
                height: pillH
            )
            NSColor.black.withAlphaComponent(0.62).setFill()
            NSBezierPath(roundedRect: pillRect, xRadius: pillH * 0.5, yRadius: pillH * 0.5).fill()
            attrStr.draw(at: NSPoint(x: pillRect.minX + 6, y: pillRect.minY + (pillH - sz.height) * 0.5))
        }
    }
    
    
    private func drawSelectionHandles(
        for entry: InlineImageCardEntry,
        accentColor: NSColor,
        haloColor: NSColor
    ) {
        
        let specBlue = NSColor(srgbRed: 30.0 / 255.0, green: 137.0 / 255.0, blue: 245.0 / 255.0, alpha: 1.0)
        let unrotatedRect = NSRect(
            x: -entry.unrotatedCardSize.width * 0.5,
            y: -entry.unrotatedCardSize.height * 0.5,
            width: entry.unrotatedCardSize.width,
            height: entry.unrotatedCardSize.height
        )
        
        // 1. Rotated box perimeter (`1px` sharp dashed `[4, 3]`), center axis guide during edge drag, & rotation knob
        NSGraphicsContext.saveGraphicsState()
        let xform = NSAffineTransform()
        xform.translateX(by: entry.center.x, yBy: entry.center.y)
        xform.rotate(byDegrees: entry.rotationDegrees)
        xform.concat()
        
        let dashedBox = NSBezierPath(rect: unrotatedRect)
        dashedBox.lineWidth = 1.0
        dashedBox.setLineDash([4, 3], count: 2, phase: 0)
        specBlue.setStroke()
        dashedBox.stroke()
        
        if let dragging = self.activeDraggingResizeHandle {
            if dragging.isHorizontalEdge {
                let guide = NSBezierPath()
                guide.lineWidth = 0.8
                guide.setLineDash([1.2, 3], count: 2, phase: 0)
                guide.move(to: NSPoint(x: unrotatedRect.minX, y: 0))
                guide.line(to: NSPoint(x: unrotatedRect.maxX, y: 0))
                specBlue.withAlphaComponent(0.42).setStroke()
                guide.stroke()
            } else if dragging.isVerticalEdge {
                let guide = NSBezierPath()
                guide.lineWidth = 0.8
                guide.setLineDash([1.2, 3], count: 2, phase: 0)
                guide.move(to: NSPoint(x: 0, y: unrotatedRect.minY))
                guide.line(to: NSPoint(x: 0, y: unrotatedRect.maxY))
                specBlue.withAlphaComponent(0.42).setStroke()
                guide.stroke()
            }
        }
        
        let topMidLocal = NSPoint(x: 0, y: unrotatedRect.minY)
        let rotKnobLocal = NSPoint(x: 0, y: unrotatedRect.minY - 22)
        let stem = NSBezierPath()
        stem.lineWidth = 1.25
        stem.move(to: topMidLocal)
        stem.line(to: rotKnobLocal)
        specBlue.withAlphaComponent(0.82).setStroke()
        stem.stroke()
        
        let knobRect = NSRect(x: rotKnobLocal.x - 7.5, y: rotKnobLocal.y - 7.5, width: 15, height: 15)
        let knobPath = NSBezierPath(ovalIn: knobRect)
        NSColor.windowBackgroundColor.setFill()
        knobPath.fill()
        specBlue.setStroke()
        knobPath.lineWidth = 1.4
        knobPath.stroke()
        if let rotateIcon = NSImage(systemSymbolName: "arrow.trianglehead.2.clockwise.rotate.90", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 8.5, weight: .bold))
        {
            rotateIcon.tinted(with: specBlue).draw(
                in: knobRect.insetBy(dx: 3, dy: 3),
                from: .zero,
                operation: .sourceOver,
                fraction: 1.0,
                respectFlipped: true,
                hints: nil
            )
        }
        NSGraphicsContext.restoreGraphicsState()
        
        // 2. Eight morphing 10-vertex handles (10×10 square <-> rotated directional double-arrow)
        NSGraphicsContext.saveGraphicsState()
        for handle in BoundingBoxHandle.allCases {
            let center = entry.handlePoint(for: handle)
            let morph = self.resizeMorphSprings[handle]?.value
                ?? ((self.activeDraggingResizeHandle == handle || self.hoveredResizeHandle == handle) ? 1 : 0)
            let press = self.resizePressSprings[handle]?.value
                ?? ((self.activeDraggingResizeHandle == handle) ? 1 : 0)
            let poly = BoundingBoxHandleMorph.bezierPath(
                for: handle,
                center: center,
                progress: morph,
                extraRotationDegrees: entry.rotationDegrees
            )
            poly.lineJoinStyle = .round
            poly.lineCapStyle = .round
            
            haloColor.setStroke()
            poly.lineWidth = 3.0
            poly.stroke()
            
            let fillColor = NSColor.white.blended(withFraction: max(0, min(1, press)), of: specBlue) ?? .white
            fillColor.setFill()
            poly.fill()
            
            specBlue.setStroke()
            poly.lineWidth = 0.9
            poly.stroke()
        }
        
        // 3. Interactive `18pt` rounded integer dimension pills (clickable to type exact W/H)
        self.widthPillRect = .zero
        self.heightPillRect = .zero
        let isEditingAnyDimension = (self.editingDimensionIsWidth != nil)
        let showW = self.visibleDimensionPills.showWidth || isEditingAnyDimension
        let showH = self.visibleDimensionPills.showHeight || isEditingAnyDimension
        let anchorHandle = isEditingAnyDimension ? .bottomRight : self.visibleDimensionPills.anchorCorner
        let anchorPt = entry.handlePoint(for: anchorHandle)
        
        func drawDimensionPill(text: String, center: NSPoint, fill: NSColor) -> NSRect {
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold),
                .foregroundColor: NSColor.white,
            ]
            let attrStr = NSAttributedString(string: text, attributes: attrs)
            let sz = attrStr.size()
            let pillW = max(28, ceil(sz.width) + 12)
            let pillH: CGFloat = 18
            let x = max(self.bounds.minX + 6, min(self.bounds.maxX - pillW - 6, center.x - pillW * 0.5))
            let y = max(self.bounds.minY + 4, min(self.bounds.maxY - pillH - 4, center.y - pillH * 0.5))
            let pillRect = NSRect(x: x, y: y, width: pillW, height: pillH)
            fill.setFill()
            NSBezierPath(roundedRect: pillRect, xRadius: pillH * 0.5, yRadius: pillH * 0.5).fill()
            attrStr.draw(at: NSPoint(x: pillRect.minX + (pillW - sz.width) * 0.5, y: pillRect.minY + (pillH - sz.height) * 0.5))
            return pillRect
        }
        
        if showW && self.editingDimensionIsWidth != true {
            let inwardX: CGFloat = anchorHandle.isWest ? 32 : -32
            let centerW = NSPoint(x: anchorPt.x + inwardX, y: anchorPt.y)
            self.widthPillRect = drawDimensionPill(
                text: "\(Int(round(entry.drawSize.width)))",
                center: centerW,
                fill: specBlue
            )
        }
        if showH && self.editingDimensionIsWidth != false {
            let inwardY: CGFloat = anchorHandle.isNorth ? 25 : -25
            let centerH = NSPoint(x: anchorPt.x, y: anchorPt.y + inwardY)
            self.heightPillRect = drawDimensionPill(
                text: "\(Int(round(entry.drawSize.height)))",
                center: centerH,
                fill: specBlue
            )
        }
        
        // Live HUD readout pill during rotation or free move
        if let hud = self.liveInlineImageHUDText {
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 10.5, weight: .semibold),
                .foregroundColor: NSColor.white,
            ]
            let attrStr = NSAttributedString(string: hud, attributes: attrs)
            let sz = attrStr.size()
            let pillW = sz.width + 14
            let pillH: CGFloat = 20
            let pillRect = NSRect(
                x: entry.center.x - pillW * 0.5,
                y: entry.rect.maxY + 6,
                width: pillW,
                height: pillH
            )
            NSColor.black.withAlphaComponent(0.76).setFill()
            NSBezierPath(roundedRect: pillRect, xRadius: pillH * 0.5, yRadius: pillH * 0.5).fill()
            attrStr.draw(at: NSPoint(x: pillRect.minX + 7, y: pillRect.minY + (pillH - sz.height) * 0.5))
        }
        
        NSGraphicsContext.restoreGraphicsState()
    }
    
    
    // MARK: Inline Image Direct Manipulation (Scale / Rotate / Move) & Right-Click Menu
    
    private var currentInlineImageDocURL: URL? {
        self.textStorage.flatMap { self.documentViewController?.document(for: $0)?.fileURL }
            ?? (self.layoutManager as? LayoutManager)?.inlineImageDocumentURL
    }
    
    
    private func selectedInlineImageEntry() -> InlineImageCardEntry? {
        guard let selectedID = self.selectedInlineImageIdentifier else { return nil }
        return self.inlineImageCardEntries.first { $0.identifier == selectedID }
    }
    
    
    private func applyInlineImageLayoutUpdate(in tokenRange: NSRange? = nil, isLiveManipulation: Bool = false) {
        if let lm = self.layoutManager as? LayoutManager {
            lm.invalidateInlineImageLayout(in: tokenRange)
            if let tc = self.textContainer {
                if tokenRange != nil, !self.visibleRect.isEmpty {
                    lm.ensureLayout(forBoundingRect: self.visibleRect, in: tc)
                } else {
                    lm.ensureLayout(for: tc)
                }
            }
        }
        if !isLiveManipulation {
            self.sizeToFit()
            self.needsLayout = true
            self.invalidateInsertionIndicatorDisplayMode()
        }
        self.needsDisplay = true
        if isLiveManipulation {
            self.displayIfNeeded()
        }
        if self.funEffects.ownsVimCursorDrawing {
            self.funEffects.syncVimCursor(animated: false)
        }
    }
    
    
    private static func snappedImageAngleIfNearCardinal(_ degrees: CGFloat) -> CGFloat {
        for target in [-180.0, -90.0, 0.0, 90.0, 180.0] as [CGFloat] {
            if abs(degrees - target) <= 3.0 {
                return target == -180.0 ? 180.0 : target
            }
        }
        return degrees
    }
    
    
    private func handleInlineImageMouseDown(at point: NSPoint, modifiers: NSEvent.ModifierFlags) -> Bool {
        guard self.isEditable else { return false }
        // 1. Check active selection's dimension pills (click to type exact pixels), rotation knob & 8 resize handles
        if let selected = self.selectedInlineImageEntry() {
            if !self.widthPillRect.isEmpty, self.widthPillRect.insetBy(dx: -4, dy: -4).contains(point) {
                self.beginInlineDimensionEdit(for: selected, isWidth: true)
                return true
            }
            if !self.heightPillRect.isEmpty, self.heightPillRect.insetBy(dx: -4, dy: -4).contains(point) {
                self.beginInlineDimensionEdit(for: selected, isWidth: false)
                return true
            }
            
            self.dismissInlineDimensionEditor(commit: true)
            
            let rotCenter = selected.rotationKnobCenter()
            if hypot(point.x - rotCenter.x, point.y - rotCenter.y) <= 11 {
                self.trackInlineImageRotation(for: selected, initialPoint: point)
                return true
            }
            if let handle = selected.hitTestHandle(at: point) {
                self.trackInlineImageResize(for: selected, handle: handle, startPoint: point)
                return true
            }
        }
        
        // 2. Allow immediate 1-click corner/edge resize on ANY hovered image (even before selecting!)
        for entry in self.inlineImageCardEntries {
            if let handle = entry.hitTestHandle(at: point) {
                self.dismissInlineDimensionEditor(commit: false)
                self.selectedInlineImageIdentifier = entry.identifier
                self.needsDisplay = true
                self.trackInlineImageResize(for: entry, handle: handle, startPoint: point)
                return true
            }
        }
        
        // 3. Check clicking inside any inline image body -> select + smooth position drag (NO zoom popup!)
        guard let hit = self.inlineImageCardEntries.first(where: { $0.hitTestImage(point: point) }) else {
            return false
        }
        self.dismissInlineDimensionEditor(commit: false)
        self.selectedInlineImageIdentifier = hit.identifier
        self.needsDisplay = true
        self.trackInlineImageDragMove(for: hit, startPoint: point)
        return true
    }
    
    
    private func startResizeSpringTimerIfNeeded() {
        
        guard self.resizeSpringTimer == nil else { return }
        self.resizeSpringLastTimestamp = ProcessInfo.processInfo.systemUptime
        self.resizeSpringTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.stepResizeSprings()
            }
        }
    }
    
    
    private func stepResizeSprings() {
        
        let now = ProcessInfo.processInfo.systemUptime
        let dt = CGFloat(min(0.032, max(0.001, now - self.resizeSpringLastTimestamp)))
        self.resizeSpringLastTimestamp = now
        
        var anyMoving = false
        for handle in BoundingBoxHandle.allCases {
            if self.resizeMorphSprings[handle]?.step(dt: dt) == true {
                anyMoving = true
            }
            if self.resizePressSprings[handle]?.step(dt: dt) == true {
                anyMoving = true
            }
        }
        
        self.needsDisplay = true
        if !anyMoving {
            self.resizeSpringTimer?.invalidate()
            self.resizeSpringTimer = nil
        }
    }
    
    
    private func clearInlineImageDimensionPills() {
        
        self.dimensionPillHideWorkItem?.cancel()
        self.dimensionPillHideWorkItem = nil
        self.visibleDimensionPills = (false, false, .bottomRight)
        self.widthPillRect = .zero
        self.heightPillRect = .zero
    }
    
    
    private func scheduleHideDimensionPills() {
        
        self.dimensionPillHideWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self, self.activeDraggingResizeHandle == nil, self.editingDimensionIsWidth == nil else { return }
            self.clearInlineImageDimensionPills()
            self.needsDisplay = true
        }
        self.dimensionPillHideWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.3, execute: item)
    }
    
    
    private func beginInlineDimensionEdit(for entry: InlineImageCardEntry, isWidth: Bool) {
        
        self.dismissInlineDimensionEditor(commit: true)
        self.dimensionPillHideWorkItem?.cancel()
        self.dimensionPillHideWorkItem = nil
        self.visibleDimensionPills = (true, true, .bottomRight)
        self.editingDimensionIsWidth = isWidth
        
        let cornerPt = entry.handlePoint(for: .bottomRight)
        let center = isWidth
            ? NSPoint(x: cornerPt.x - 32, y: cornerPt.y)
            : NSPoint(x: cornerPt.x, y: cornerPt.y - 25)
        let fieldRect = NSRect(x: center.x - 27, y: center.y - 10, width: 54, height: 20)
        
        let currentValue = Int(round(isWidth ? entry.drawSize.width : entry.drawSize.height))
        let identifier = entry.identifier
        let field = InlineDimensionEditorField(frame: fieldRect)
        field.stringValue = "\(currentValue)"
        field.onCommit = { [weak self] raw in
            self?.commitInlineDimensionEdit(raw: raw, identifier: identifier, isWidth: isWidth)
        }
        field.onCancel = { [weak self] in
            self?.dismissInlineDimensionEditor(commit: false)
        }
        self.addSubview(field)
        self.inlineDimensionEditor = field
        self.window?.makeFirstResponder(field)
        field.selectText(nil)
        self.needsDisplay = true
    }
    
    
    private func commitInlineDimensionEdit(raw: String, identifier: String, isWidth: Bool) {
        
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let parsed = Double(trimmed).map { CGFloat($0) }
        self.dismissInlineDimensionEditor(commit: false)
        
        if let parsed, parsed.isFinite {
            let docURL = self.currentInlineImageDocURL
            var tx = PlainTextInlineImageStore.shared.transform(for: identifier, documentURL: docURL)
            let containerWidth = self.effectiveInlineImageContainerWidth
            let maxCardW = max(BoundingBoxResizeMath.minWidth, containerWidth - 24)
            
            if let natural = PlainTextInlineImageStore.shared.naturalSize(for: identifier, documentURL: docURL),
               natural.width > 0, natural.height > 0
            {
                let aspect = natural.width / natural.height
                let candidate: NSSize
                if isWidth {
                    let w = max(BoundingBoxResizeMath.minWidth, min(maxCardW, round(parsed)))
                    candidate = NSSize(width: w, height: max(BoundingBoxResizeMath.minHeight, round(w / aspect)))
                } else {
                    let h = max(BoundingBoxResizeMath.minHeight, min(1600, round(parsed)))
                    candidate = NSSize(width: max(BoundingBoxResizeMath.minWidth, round(h * aspect)), height: h)
                }
                let optimal = BoundingBoxResizeMath.optimalRestoredSize(
                    currentSize: candidate,
                    naturalSize: natural,
                    maxWidth: maxCardW,
                    maxHeight: 1600
                )
                let prevHeight = self.inlineImageCardEntries.first(where: { $0.identifier == identifier })?.drawSize.height
                let maxImgW = PlainTextInlineImageStore.effectiveMaxImageWidth(containerWidth: containerWidth, glyphX: 0)
                tx.customWidth = optimal.width
                tx.customHeight = optimal.height
                tx.scale = InlineImageZoomMath.effectiveScale(
                    drawWidth: optimal.width,
                    naturalSize: natural,
                    maxImageWidth: maxImgW
                )
                if let prevHeight, prevHeight > 0, optimal.height < prevHeight, tx.offsetY > 0 {
                    let scaled = tx.offsetY * (optimal.height / prevHeight)
                    tx.offsetY = scaled < 2 ? 0 : round(scaled)
                }
            } else if isWidth {
                tx.customWidth = max(BoundingBoxResizeMath.minWidth, min(2400, round(parsed)))
            } else {
                let nextH = max(BoundingBoxResizeMath.minHeight, min(1600, round(parsed)))
                let prevHeight = self.inlineImageCardEntries.first(where: { $0.identifier == identifier })?.drawSize.height
                tx.customHeight = nextH
                if let prevHeight, prevHeight > 0, nextH < prevHeight, tx.offsetY > 0 {
                    let scaled = tx.offsetY * (nextH / prevHeight)
                    tx.offsetY = scaled < 2 ? 0 : round(scaled)
                }
            }
            PlainTextInlineImageStore.shared.setTransform(tx, for: identifier, documentURL: docURL)
            self.applyInlineImageLayoutUpdate()
        }
        self.scheduleHideDimensionPills()
    }
    
    
    private func dismissInlineDimensionEditor(commit: Bool) {
        
        guard let editor = self.inlineDimensionEditor else {
            self.editingDimensionIsWidth = nil
            return
        }
        let isWidth = self.editingDimensionIsWidth ?? true
        let identifier = self.selectedInlineImageIdentifier
        let rawText = editor.currentEditor()?.string ?? editor.stringValue
        self.editingDimensionIsWidth = nil
        self.inlineDimensionEditor = nil
        // Silence delegate callbacks before ending editing / removing so cancel never commits and commit never fires twice.
        (editor as? InlineDimensionEditorField)?.finishSilently()
        self.window?.endEditing(for: editor)
        editor.removeFromSuperview()
        if commit, let identifier {
            self.commitInlineDimensionEdit(raw: rawText, identifier: identifier, isWidth: isWidth)
        } else {
            self.window?.makeFirstResponder(self)
            self.scheduleHideDimensionPills()
            self.needsDisplay = true
        }
    }
    
    
    /// Resolves `offsetY` after bounding-box resize so shrinking never converts shrunk height into trapped top padding.
    nonisolated static func resolvedOffsetYAfterResize(
        startOffsetY: CGFloat,
        startFrame: NSRect,
        nextFrame: NSRect,
        handle: BoundingBoxHandle
    ) -> CGFloat {
        guard startOffsetY > 0 else { return 0 }
        let ratio = max(0, min(1, nextFrame.height / max(1, startFrame.height)))
        var resolved = startOffsetY
        if handle.isNorth {
            let deltaMinY = nextFrame.minY - startFrame.minY
            if deltaMinY < 0 {
                // Enlarging upward via a North handle consumes existing top blank space first.
                resolved = max(0, startOffsetY + deltaMinY)
            } else if deltaMinY > 0 {
                // Shrinking via a North handle releases blank space above rather than pushing the card down.
                resolved = min(startOffsetY * ratio, max(0, startOffsetY - deltaMinY))
            }
        } else if nextFrame.height < startFrame.height {
            resolved = startOffsetY * ratio
        }
        return resolved < 2 ? 0 : min(240, round(resolved))
    }
    
    
    private func trackInlineImageResize(
        for entry: InlineImageCardEntry,
        handle: BoundingBoxHandle,
        startPoint: NSPoint
    ) {
        guard let window = self.window else { return }
        let docURL = self.currentInlineImageDocURL
        let startTx = PlainTextInlineImageStore.shared.transform(for: entry.identifier, documentURL: docURL)
        let startImageFrame = NSRect(
            x: entry.center.x - entry.drawSize.width * 0.5,
            y: entry.center.y - entry.drawSize.height * 0.5,
            width: entry.drawSize.width,
            height: entry.drawSize.height
        )
        let containerWidth = self.effectiveInlineImageContainerWidth
        let maxImgW = PlainTextInlineImageStore.effectiveMaxImageWidth(containerWidth: containerWidth, glyphX: 0)
        let minXBound = self.textContainerOrigin.x + 8
        let maxXBound = self.textContainerOrigin.x + max(180, containerWidth) - 8
        let minYBound = startImageFrame.minY - InlineImageZoomMath.maxCardHeight
        let maxYBound = startImageFrame.minY + InlineImageZoomMath.maxCardHeight
        let naturalSize = PlainTextInlineImageStore.shared.naturalSize(for: entry.identifier, documentURL: docURL)
        let naturalAspectRatio: CGFloat = {
            if let naturalSize, naturalSize.height > 0 {
                return naturalSize.width / naturalSize.height
            }
            return startImageFrame.height > 0 ? (startImageFrame.width / startImageFrame.height) : 1
        }()
        
        self.activeDraggingResizeHandle = handle
        self.isLiveManipulatingInlineImage = true
        self.dimensionPillHideWorkItem?.cancel()
        self.dimensionPillHideWorkItem = nil
        self.visibleDimensionPills = (
            showWidth: handle.isCorner || handle.isHorizontalEdge,
            showHeight: handle.isCorner || handle.isVerticalEdge,
            anchorCorner: handle
        )
        for candidate in BoundingBoxHandle.allCases {
            self.resizeMorphSprings[candidate]?.target = (candidate == handle) ? 1.0 : 0.0
            self.resizePressSprings[candidate]?.target = (candidate == handle) ? 1.0 : 0.0
        }
        self.startResizeSpringTimerIfNeeded()
        self.cursorForResizeHandle(handle, rotationDegrees: entry.rotationDegrees).set()
        self.needsDisplay = true
        
        let negRad = -entry.rotationDegrees * .pi / 180.0
        let cosR = cos(negRad)
        let sinR = sin(negRad)
        var wasCancelled = false
        var latestTransform = startTx
        var prevScale = startTx.scale
        var crossed100 = abs(startTx.scale - 1.0) < 0.02
        
        while var event = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp, .keyDown]) {
            if event.type == .keyDown {
                if event.keyCode == 53 { // Escape cancels current resize
                    wasCancelled = true
                    break
                }
                continue
            }
            
            // Drain any immediately queued drag events so the image locks 1:1 to the pointer with zero lag.
            if event.type == .leftMouseDragged {
                while let newer = window.nextEvent(
                    matching: .leftMouseDragged,
                    until: .distantPast,
                    inMode: .eventTracking,
                    dequeue: true
                ) {
                    event = newer
                }
            }
            
            let curPt = self.convert(event.locationInWindow, from: nil)
            let worldDx = curPt.x - startPoint.x
            let worldDy = curPt.y - startPoint.y
            let localDelta = NSPoint(
                x: worldDx * cosR - worldDy * sinR,
                y: worldDx * sinR + worldDy * cosR
            )
            
            let nextFrame = BoundingBoxResizeMath.aspectPreservingResizedFrame(
                startFrame: startImageFrame,
                naturalAspectRatio: naturalAspectRatio,
                handle: handle,
                delta: localDelta,
                minXBound: minXBound,
                minYBound: minYBound,
                maxXBound: maxXBound,
                maxYBound: maxYBound
            )
            
            var updated = startTx
            updated.customWidth = nextFrame.width
            updated.customHeight = nextFrame.height
            if let naturalSize, naturalSize.width > 0, naturalSize.height > 0 {
                updated.scale = InlineImageZoomMath.effectiveScale(
                    drawWidth: nextFrame.width,
                    naturalSize: naturalSize,
                    maxImageWidth: maxImgW
                )
            }
            updated.offsetX = startTx.offsetX + (nextFrame.minX - startImageFrame.minX)
            updated.offsetY = Self.resolvedOffsetYAfterResize(
                startOffsetY: startTx.offsetY,
                startFrame: startImageFrame,
                nextFrame: nextFrame,
                handle: handle
            )
            
            if !crossed100,
               (prevScale < 1.0 && updated.scale >= 1.0) || (prevScale > 1.0 && updated.scale <= 1.0)
            {
                crossed100 = true
                NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
            } else if abs(updated.scale - 1.0) > 0.08 {
                crossed100 = false
            }
            prevScale = updated.scale
            latestTransform = updated
            
            // Pure in-memory update during live drag (zero disk I/O per pixel)
            PlainTextInlineImageStore.shared.setTransform(updated, for: entry.identifier, documentURL: docURL, persist: false)
            self.liveInlineImageHUDText = "\(Int((updated.scale * 100).rounded()))% · \(Int(round(nextFrame.width))) × \(Int(round(nextFrame.height)))"
            
            self.stepResizeSprings()
            self.applyInlineImageLayoutUpdate(in: entry.tokenRange, isLiveManipulation: true)
            
            if event.type == .leftMouseUp { break }
        }
        
        self.isLiveManipulatingInlineImage = false
        self.liveInlineImageHUDText = nil
        if wasCancelled {
            PlainTextInlineImageStore.shared.setTransform(startTx, for: entry.identifier, documentURL: docURL, persist: true)
            self.applyInlineImageLayoutUpdate(in: entry.tokenRange, isLiveManipulation: false)
        } else {
            // Single atomic flush + high-quality final repaint and sizeToFit on release
            PlainTextInlineImageStore.shared.setTransform(latestTransform, for: entry.identifier, documentURL: docURL, persist: true)
            self.applyInlineImageLayoutUpdate(in: entry.tokenRange, isLiveManipulation: false)
        }
        
        self.activeDraggingResizeHandle = nil
        let endPt = self.convert(window.convertPoint(fromScreen: NSEvent.mouseLocation), from: nil)
        let hoverAfter = self.inlineImageHoverTarget(at: endPt)
        let stillHoveringHandle = hoverAfter?.handle
        self.hoveredInlineImageIdentifier = hoverAfter?.entry.identifier
        self.hoveredResizeHandle = stillHoveringHandle
        for candidate in BoundingBoxHandle.allCases {
            self.resizeMorphSprings[candidate]?.target = (candidate == stillHoveringHandle) ? 1.0 : 0.0
            self.resizePressSprings[candidate]?.target = 0.0
        }
        self.startResizeSpringTimerIfNeeded()
        if let stillHoveringHandle, let target = hoverAfter {
            self.cursorForResizeHandle(stillHoveringHandle, rotationDegrees: target.entry.rotationDegrees).set()
        } else if hoverAfter != nil {
            NSCursor.openHand.set()
        } else {
            self.window?.invalidateCursorRects(for: self)
            NSCursor.iBeam.set()
        }
        if wasCancelled {
            self.clearInlineImageDimensionPills()
        } else {
            self.scheduleHideDimensionPills()
        }
        self.needsDisplay = true
    }
    
    
    private func trackInlineImageRotation(for entry: InlineImageCardEntry, initialPoint: NSPoint) {
        guard let window = self.window else { return }
        let docURL = self.currentInlineImageDocURL
        let startAngleRad = atan2(initialPoint.y - entry.center.y, initialPoint.x - entry.center.x)
        let baseTransform = PlainTextInlineImageStore.shared.transform(for: entry.identifier, documentURL: docURL)
        let initialDegrees = baseTransform.rotationDegrees
        
        while let event = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
            let curPt = self.convert(event.locationInWindow, from: nil)
            let curRad = atan2(curPt.y - entry.center.y, curPt.x - entry.center.x)
            var deg = initialDegrees + (curRad - startAngleRad) * 180.0 / .pi
            while deg > 180 { deg -= 360 }
            while deg < -180 { deg += 360 }
            if !event.modifierFlags.contains(.option) {
                deg = Self.snappedImageAngleIfNearCardinal(deg)
            }
            var updated = PlainTextInlineImageStore.shared.transform(for: entry.identifier, documentURL: docURL)
            updated.rotationDegrees = deg
            PlainTextInlineImageStore.shared.setTransform(updated, for: entry.identifier, documentURL: docURL)
            self.liveInlineImageHUDText = String(format: "%.1f°", deg)
            self.applyInlineImageLayoutUpdate(in: entry.tokenRange)
            
            if event.type == .leftMouseUp { break }
        }
        self.liveInlineImageHUDText = nil
        self.needsDisplay = true
    }
    
    
    private func trackInlineImageDragMove(for entry: InlineImageCardEntry, startPoint: NSPoint) {
        guard let window = self.window else { return }
        let docURL = self.currentInlineImageDocURL
        let startTx = PlainTextInlineImageStore.shared.transform(for: entry.identifier, documentURL: docURL)
        let containerWidth = self.effectiveInlineImageContainerWidth
        let canvasMidX = self.textContainerOrigin.x + containerWidth * 0.5
        var didMove = false
        
        while let event = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
            let curPt = self.convert(event.locationInWindow, from: nil)
            let dx = curPt.x - startPoint.x
            let dy = curPt.y - startPoint.y
            
            if didMove || hypot(dx, dy) > 2.5 {
                didMove = true
                var updated = PlainTextInlineImageStore.shared.transform(for: entry.identifier, documentURL: docURL)
                var proposedOffsetX = startTx.offsetX + dx
                let proposedCenterX = entry.baseAnchorX + proposedOffsetX + entry.rect.width * 0.5
                if !event.modifierFlags.contains(.option), abs(proposedCenterX - canvasMidX) <= 7.0 {
                    proposedOffsetX = (canvasMidX - entry.rect.width * 0.5) - entry.baseAnchorX
                    self.showInlineImageCenterGuide = true
                } else {
                    self.showInlineImageCenterGuide = false
                }
                updated.offsetX = proposedOffsetX
                updated.offsetY = max(0, min(200, startTx.offsetY + dy))
                PlainTextInlineImageStore.shared.setTransform(updated, for: entry.identifier, documentURL: docURL)
                self.liveInlineImageHUDText = "X:\(Int(updated.offsetX.rounded())) Y:\(Int(updated.offsetY.rounded()))"
                self.applyInlineImageLayoutUpdate(in: entry.tokenRange)
            }
            
            if event.type == .leftMouseUp { break }
        }
        
        self.showInlineImageCenterGuide = false
        self.liveInlineImageHUDText = nil
        self.needsDisplay = true
    }
    
    
    /// Builds the dedicated right-click menu for inline images (action dock + live stepless zoom rail + categorized geometry/file actions).
    func makeInlineImageContextMenu(for identifier: String, tokenRange: NSRange) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.minimumWidth = EditorContextMenuMetrics.menuWidth
        let docURL = self.currentInlineImageDocURL
        let currentTx = PlainTextInlineImageStore.shared.transform(for: identifier, documentURL: docURL)
        let editable = self.isEditable
        let payload = InlineImageMenuPayload(identifier: identifier, tokenRange: tokenRange)
        
        func item(
            _ title: String,
            systemImage: String? = nil,
            action: Selector,
            tag: Int = 0,
            enabled: Bool = true
        ) -> NSMenuItem {
            let m = NSMenuItem(title: title, action: action, keyEquivalent: "")
            m.target = self
            m.tag = tag
            m.isEnabled = enabled
            m.representedObject = payload
            if let systemImage {
                m.image = Self.contextMenuSymbol(systemImage)
            }
            return m
        }
        
        // 1. Hero Top 4-Tile Image Action Dock
        let dockItem = NSMenuItem(title: AppLanguage.text("查看大图", en: "Zoom Preview"), action: nil, keyEquivalent: "")
        dockItem.view = ContextMenuActionDockView(actions: [
            ContextMenuDockAction(
                title: AppLanguage.text("大图", en: "Zoom"),
                symbolName: "arrow.up.left.and.arrow.down.right",
                toolTip: AppLanguage.text("查看大图", en: "Zoom Preview")
            ) { [weak self, weak menu] in
                menu?.cancelTracking()
                guard let self, let entry = self.entry(for: payload) else { return }
                self.presentInlineImagePopover(for: entry)
            },
            ContextMenuDockAction(
                title: AppLanguage.text("拷贝", en: "Copy"),
                symbolName: "doc.on.doc",
                toolTip: AppLanguage.text("拷贝图片", en: "Copy Image")
            ) { [weak self, weak menu] in
                menu?.cancelTracking()
                guard let self,
                      let image = PlainTextInlineImageStore.shared.image(for: identifier, documentURL: self.currentInlineImageDocURL)
                else { return }
                let pboard = NSPasteboard.general
                pboard.clearContents()
                pboard.writeObjects([image])
            },
            ContextMenuDockAction(
                title: "OCR",
                symbolName: "text.viewfinder",
                toolTip: AppLanguage.text("OCR 识别文字", en: "OCR & AI Polish")
            ) { [weak self, weak menu] in
                menu?.cancelTracking()
                guard let self,
                      let image = PlainTextInlineImageStore.shared.image(for: identifier, documentURL: self.currentInlineImageDocURL),
                      let window = self.window
                else { return }
                self.documentViewController?.processOCR(image: image, on: window)
            },
            ContextMenuDockAction(
                title: AppLanguage.text("删除", en: "Delete"),
                symbolName: "trash",
                toolTip: AppLanguage.text("删除图片", en: "Delete Image"),
                isEnabled: editable,
                isDestructive: true
            ) { [weak self, weak menu] in
                menu?.cancelTracking()
                self?.deleteInlineImageToken(range: tokenRange, identifier: identifier)
            },
        ])
        menu.addItem(dockItem)
        
        // 2. Live Stepless Zoom Rail (continuous slider + quick scale presets)
        if editable {
            let containerW = self.effectiveInlineImageContainerWidth
            let maxImgW = PlainTextInlineImageStore.effectiveMaxImageWidth(containerWidth: containerW, glyphX: 0)
            let naturalSize = PlainTextInlineImageStore.shared.naturalSize(for: identifier, documentURL: docURL)
                ?? self.inlineImageCardEntries.first(where: { $0.identifier == identifier })?.drawSize
                ?? NSSize(width: 320, height: 200)
            let scaleBounds = InlineImageZoomMath.scaleBounds(
                naturalSize: naturalSize,
                containerWidth: containerW,
                maxImageWidth: maxImgW
            )
            let currentDrawW = self.inlineImageCardEntries.first(where: { $0.identifier == identifier })?.drawSize.width
                ?? PlainTextInlineImageStore.shared.displayGeometry(
                    for: identifier,
                    documentURL: docURL,
                    containerWidth: containerW,
                    maxImageWidth: maxImgW
                )?.drawSize.width
                ?? naturalSize.width
            let effectiveScale = InlineImageZoomMath.effectiveScale(
                drawWidth: currentDrawW,
                naturalSize: naturalSize,
                maxImageWidth: maxImgW
            )
            
            menu.addItem(.separator())
            menu.addItem(.sectionHeader(title: AppLanguage.text("无极缩放", en: "Stepless Zoom")))
            let zoomItem = NSMenuItem(title: AppLanguage.text("无极缩放", en: "Stepless Zoom"), action: nil, keyEquivalent: "")
            zoomItem.view = ContextMenuInlineImageZoomView(
                initialScale: effectiveScale,
                scaleBounds: scaleBounds,
                isIdentity: currentTx.isIdentity,
                onScaleChange: { [weak self] targetScale in
                    guard let self else { return currentTx }
                    return self.applyInlineImageSteplessScale(targetScale, for: identifier, tokenRange: tokenRange)
                },
                onReset: { [weak self] in
                    guard let self else { return }
                    PlainTextInlineImageStore.shared.resetTransform(for: identifier, documentURL: self.currentInlineImageDocURL)
                    self.applyInlineImageLayoutUpdate(in: tokenRange)
                }
            )
            menu.addItem(zoomItem)
        }
        
        // 3. Geometry & Layout
        menu.addItem(.separator())
        menu.addItem(.sectionHeader(title: AppLanguage.text("几何与排版", en: "Transform & Layout")))
        
        menu.addItem(item(
            AppLanguage.text("调整大小、位置与角度…", en: "Adjust Size, Position & Angle…"),
            systemImage: "slider.horizontal.3",
            action: #selector(inlineImageContextOpenTransformPanel(_:)),
            enabled: editable
        ))
        menu.addItem(item(
            AppLanguage.text("向左旋转 90°", en: "Rotate Left 90°"),
            systemImage: "rotate.left",
            action: #selector(inlineImageContextRotateByTag(_:)),
            tag: -90,
            enabled: editable
        ))
        menu.addItem(item(
            AppLanguage.text("向右旋转 90°", en: "Rotate Right 90°"),
            systemImage: "rotate.right",
            action: #selector(inlineImageContextRotateByTag(_:)),
            tag: 90,
            enabled: editable
        ))
        
        let alignMenu = NSMenu()
        alignMenu.autoenablesItems = false
        alignMenu.addItem(item(AppLanguage.text("靠左对齐", en: "Align Left"), systemImage: "align.horizontal.left", action: #selector(inlineImageContextAlignByTag(_:)), tag: 0, enabled: editable))
        alignMenu.addItem(item(AppLanguage.text("水平居中", en: "Align Center"), systemImage: "align.horizontal.center", action: #selector(inlineImageContextAlignByTag(_:)), tag: 1, enabled: editable))
        alignMenu.addItem(item(AppLanguage.text("靠右对齐", en: "Align Right"), systemImage: "align.horizontal.right", action: #selector(inlineImageContextAlignByTag(_:)), tag: 2, enabled: editable))
        let alignParent = NSMenuItem(
            title: AppLanguage.text("水平对齐", en: "Align Position"),
            action: nil,
            keyEquivalent: ""
        )
        alignParent.image = Self.contextMenuSymbol("rectangle.center.inset.filled")
        alignParent.submenu = alignMenu
        alignParent.isEnabled = editable
        menu.addItem(alignParent)
        
        menu.addItem(item(
            AppLanguage.text("恢复原始大小与角度", en: "Reset Transform"),
            systemImage: "arrow.counterclockwise",
            action: #selector(inlineImageContextResetTransform(_:)),
            enabled: editable && !currentTx.isIdentity
        ))
        
        // 4. File
        menu.addItem(.separator())
        let fileURL = PlainTextInlineImageStore.shared.imageURL(for: identifier, documentURL: docURL)
        menu.addItem(item(
            AppLanguage.text("在访达中显示", en: "Reveal in Finder"),
            systemImage: "folder",
            action: #selector(inlineImageContextRevealInFinder(_:)),
            enabled: fileURL != nil
        ))
        
        return menu
    }
    
    
    @objc private func inlineImageContextZoomPreview(_ sender: NSMenuItem) {
        guard let payload = sender.representedObject as? InlineImageMenuPayload,
              let entry = self.entry(for: payload)
        else { return }
        self.presentInlineImagePopover(for: entry)
    }
    
    
    @objc private func inlineImageContextOpenTransformPanel(_ sender: NSMenuItem) {
        guard let payload = sender.representedObject as? InlineImageMenuPayload,
              let entry = self.entry(for: payload)
        else { return }
        self.presentInlineImageTransformPopover(for: entry)
    }
    
    
    @objc private func inlineImageContextRotateByTag(_ sender: NSMenuItem) {
        guard let payload = sender.representedObject as? InlineImageMenuPayload else { return }
        let docURL = self.currentInlineImageDocURL
        var tx = PlainTextInlineImageStore.shared.transform(for: payload.identifier, documentURL: docURL)
        tx.rotationDegrees += CGFloat(sender.tag)
        PlainTextInlineImageStore.shared.setTransform(tx, for: payload.identifier, documentURL: docURL)
        self.selectedInlineImageIdentifier = payload.identifier
        self.applyInlineImageLayoutUpdate(in: payload.tokenRange)
    }
    
    
    @objc private func inlineImageContextAlignByTag(_ sender: NSMenuItem) {
        guard let payload = sender.representedObject as? InlineImageMenuPayload,
              let entry = self.entry(for: payload)
        else { return }
        let docURL = self.currentInlineImageDocURL
        let containerWidth = self.effectiveInlineImageContainerWidth
        let maxOffset = max(0, (self.textContainerOrigin.x + containerWidth - entry.rect.width - 8) - entry.baseAnchorX)
        var tx = PlainTextInlineImageStore.shared.transform(for: payload.identifier, documentURL: docURL)
        switch sender.tag {
            case 0: tx.offsetX = 0
            case 1: tx.offsetX = maxOffset * 0.5
            default: tx.offsetX = maxOffset
        }
        PlainTextInlineImageStore.shared.setTransform(tx, for: payload.identifier, documentURL: docURL)
        self.selectedInlineImageIdentifier = payload.identifier
        self.applyInlineImageLayoutUpdate(in: payload.tokenRange)
    }
    
    
    @objc private func inlineImageContextResetTransform(_ sender: NSMenuItem) {
        guard let payload = sender.representedObject as? InlineImageMenuPayload else { return }
        PlainTextInlineImageStore.shared.resetTransform(for: payload.identifier, documentURL: self.currentInlineImageDocURL)
        self.applyInlineImageLayoutUpdate(in: payload.tokenRange)
    }
    
    
    @objc private func inlineImageContextRunOCR(_ sender: NSMenuItem) {
        guard let payload = sender.representedObject as? InlineImageMenuPayload,
              let image = PlainTextInlineImageStore.shared.image(for: payload.identifier, documentURL: self.currentInlineImageDocURL),
              let window = self.window
        else { return }
        self.documentViewController?.processOCR(image: image, on: window)
    }
    
    
    @objc private func inlineImageContextCopy(_ sender: NSMenuItem) {
        guard let payload = sender.representedObject as? InlineImageMenuPayload,
              let image = PlainTextInlineImageStore.shared.image(for: payload.identifier, documentURL: self.currentInlineImageDocURL)
        else { return }
        let pboard = NSPasteboard.general
        pboard.clearContents()
        pboard.writeObjects([image])
    }
    
    
    @objc private func inlineImageContextRevealInFinder(_ sender: NSMenuItem) {
        guard let payload = sender.representedObject as? InlineImageMenuPayload,
              let url = PlainTextInlineImageStore.shared.imageURL(for: payload.identifier, documentURL: self.currentInlineImageDocURL)
        else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
    
    
    @objc private func inlineImageContextDelete(_ sender: NSMenuItem) {
        guard let payload = sender.representedObject as? InlineImageMenuPayload else { return }
        self.deleteInlineImageToken(range: payload.tokenRange, identifier: payload.identifier)
    }
    
    
    private func entry(for payload: InlineImageMenuPayload) -> InlineImageCardEntry? {
        self.inlineImageCardEntries.first(where: { $0.identifier == payload.identifier })
            ?? InlineImageCardEntry(
                rect: NSRect(x: 20, y: 20, width: 220, height: 140),
                unrotatedCardSize: NSSize(width: 220, height: 140),
                drawSize: NSSize(width: 212, height: 132),
                center: NSPoint(x: 130, y: 90),
                rotationDegrees: 0,
                scale: 1,
                baseAnchorX: 20,
                identifier: payload.identifier,
                tokenRange: payload.tokenRange
            )
    }
    
    
    private func deleteInlineImageToken(range: NSRange, identifier: String) {
        let nsString = self.string as NSString
        guard NSMaxRange(range) <= nsString.length else { return }
        let snippet = nsString.substring(with: range)
        guard snippet.contains(identifier),
              self.shouldChangeText(in: range, replacementString: "")
        else { return }
        self.replaceCharacters(in: range, with: "")
        self.didChangeText()
        if self.selectedInlineImageIdentifier == identifier {
            self.selectedInlineImageIdentifier = nil
        }
    }
    
    
    /// Opens the stepless Transform Inspector popover from the right-click context menu.
    private func presentInlineImageTransformPopover(for entry: InlineImageCardEntry) {
        self.imageTransformPopover?.performClose(nil)
        self.imagePreviewPopover?.performClose(nil)
        
        let docURL = self.currentInlineImageDocURL
        var current = PlainTextInlineImageStore.shared.transform(for: entry.identifier, documentURL: docURL)
        let containerWidth = self.effectiveInlineImageContainerWidth
        let maxImgW = PlainTextInlineImageStore.effectiveMaxImageWidth(containerWidth: containerWidth, glyphX: 0)
        let naturalSize = PlainTextInlineImageStore.shared.naturalSize(for: entry.identifier, documentURL: docURL) ?? entry.drawSize
        let scaleBounds = InlineImageZoomMath.scaleBounds(
            naturalSize: naturalSize,
            containerWidth: containerWidth,
            maxImageWidth: maxImgW
        )
        let effectiveInitialScale = InlineImageZoomMath.effectiveScale(
            drawWidth: entry.drawSize.width,
            naturalSize: naturalSize,
            maxImageWidth: maxImgW
        )
        current.scale = max(scaleBounds.lowerBound, min(scaleBounds.upperBound, effectiveInitialScale))
        let maxOffset = max(120, (self.textContainerOrigin.x + containerWidth - entry.rect.width - 8) - entry.baseAnchorX)
        
        let popover = NSPopover()
        popover.behavior = .transient
        
        let view = InlineImageTransformPopoverView(
            initialTransform: current,
            naturalSize: naturalSize,
            containerWidth: containerWidth,
            maxImageWidth: maxImgW,
            scaleBounds: Double(scaleBounds.lowerBound)...Double(scaleBounds.upperBound),
            maxOffsetX: maxOffset,
            onChange: { [weak self] nextTransform, scaleDidChange in
                guard let self else { return }
                let prev = PlainTextInlineImageStore.shared.transform(for: entry.identifier, documentURL: docURL)
                var resolved: InlineImageTransform
                if scaleDidChange {
                    resolved = InlineImageZoomMath.transformForTargetScale(
                        nextTransform.scale,
                        baseTransform: prev,
                        naturalSize: naturalSize,
                        containerWidth: containerWidth,
                        maxImageWidth: maxImgW
                    )
                    resolved.offsetX = nextTransform.offsetX
                    resolved.rotationDegrees = nextTransform.rotationDegrees
                    if abs(nextTransform.offsetY - prev.offsetY) > 0.001 {
                        resolved.offsetY = nextTransform.offsetY
                    }
                } else {
                    resolved = nextTransform
                    resolved.customWidth = prev.customWidth
                    resolved.customHeight = prev.customHeight
                }
                PlainTextInlineImageStore.shared.setTransform(resolved, for: entry.identifier, documentURL: docURL)
                self.selectedInlineImageIdentifier = entry.identifier
                self.applyInlineImageLayoutUpdate(in: entry.tokenRange)
            },
            onReset: { [weak self] in
                guard let self else { return }
                PlainTextInlineImageStore.shared.resetTransform(for: entry.identifier, documentURL: docURL)
                self.selectedInlineImageIdentifier = entry.identifier
                self.applyInlineImageLayoutUpdate(in: entry.tokenRange)
            },
            onClose: { [weak popover] in
                popover?.performClose(nil)
            }
        )
        let host = NSHostingController(rootView: view)
        host.view.frame.size = host.view.intrinsicContentSize
        popover.contentViewController = host
        self.imageTransformPopover = popover
        popover.show(relativeTo: entry.rect, of: self, preferredEdge: .maxY)
    }
    
    
    /// Opens the high-resolution zoomable preview popover (invoked exclusively from the right-click menu).
    private func presentInlineImagePopover(for entry: InlineImageCardEntry) {
        
        self.imagePreviewPopover?.performClose(nil)
        
        let docURL = self.currentInlineImageDocURL
        guard let image = PlainTextInlineImageStore.shared.image(for: entry.identifier, documentURL: docURL) else { return }
        let fileURL = PlainTextInlineImageStore.shared.imageURL(for: entry.identifier, documentURL: docURL)
        
        let popover = NSPopover()
        popover.behavior = .transient
        
        let contentView = InlineImagePreviewPopoverView(
            image: image,
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
                self?.deleteInlineImageToken(range: entry.tokenRange, identifier: entry.identifier)
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
        if let adaptive = self.inlineImageCaretFrame(for: location) {
            let caretWidth: CGFloat = 4.5
            return NSRect(x: adaptive.minX, y: adaptive.minY, width: caretWidth, height: adaptive.height)
        }
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
        let charRange = string.rangeOfComposedCharacterSequence(at: index)
        layoutManager.ensureLayout(forCharacterRange: charRange)
        let glyphRange = layoutManager.glyphRange(forCharacterRange: charRange, actualCharacterRange: nil)
        guard glyphRange.location != NSNotFound, layoutManager.isValidGlyphIndex(glyphRange.location) else { return nil }
        
        if glyphRange.length == 0 {
            let usedRect = layoutManager.lineFragmentUsedRect(forGlyphAt: glyphRange.location, effectiveRange: nil)
            return NSRect(
                x: usedRect.maxX + self.textContainerOrigin.x,
                y: usedRect.minY + self.textContainerOrigin.y,
                width: fallbackSpace,
                height: min(usedRect.height > 0 ? usedRect.height : lineH, lineH)
            )
        }
        
        var rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
        rect.origin.x += self.textContainerOrigin.x
        rect.origin.y += self.textContainerOrigin.y
        
        let character = string.substring(with: charRange)
        let isLineBreak = (character == "\n" || character == "\r" || character == "\r\n")
        
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
    
    
    override func prepareForDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        
        if self.isDraggingPaneTab(sender.draggingPasteboard),
           let pane = self.editorViewController
        {
            return pane.canAcceptPaneTabDrop(sender)
        }
        return super.prepareForDragOperation(sender)
    }
    
    
    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        
        if self.isDraggingPaneTab(sender.draggingPasteboard),
           let pane = self.editorViewController
        {
            return pane.panePerformDragOperation(sender, in: self)
        }
        return super.performDragOperation(sender)
    }
    
    
    override func concludeDragOperation(_ sender: (any NSDraggingInfo)?) {
        
        if let sender, self.isDraggingPaneTab(sender.draggingPasteboard) {
            return
        }
        super.concludeDragOperation(sender)
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
                let rendersInlineImages = (self.layoutManager as? LayoutManager)?.rendersPlainTextInlineImages == true
                let syntaxName = self.textStorage.flatMap { self.documentViewController?.document(for: $0)?.syntaxName } ?? ""
                let supportsInlineImages = rendersInlineImages || PlainTextInlineImageStore.supportsInlineImages(syntaxName: syntaxName)
                if self.isEditable, supportsInlineImages,
                   PlainTextInlineImageStore.hasPasteableImage(in: NSPasteboard.general)
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
            self.clearGhostSuggestion(animated: false)
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
            self.clearGhostSuggestion(animated: false)
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
        
        self.clearGhostSuggestion(animated: false)
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
    
    
    // MARK: Inline Habit Ghost Completion
    
    /// Forces non-contiguous layout up to the caret's line and returns exact caret rect + trailing advance.
    func exactCaretGeometry(at caretLocation: Int) -> (caretRect: NSRect, trailingReserve: CGFloat)? {
        
        guard let layoutManager = self.layoutManager as? LayoutManager else { return nil }
        
        let nsString = self.string as NSString
        let safeLocation = max(0, min(caretLocation, nsString.length))
        if nsString.length > 0 {
            let lineRange = nsString.lineRange(for: NSRange(location: min(safeLocation, max(0, nsString.length - 1)), length: 0))
            layoutManager.ensureLayout(forCharacterRange: lineRange)
        } else {
            layoutManager.ensureLayout(forCharacterRange: NSRange(location: 0, length: 0))
        }
        
        guard var caretRect = self.boundingRect(for: NSRange(location: safeLocation, length: 0)) else { return nil }
        caretRect.size.height = min(caretRect.height > 0 ? caretRect.height : self.singleLineHeight, self.singleLineHeight)
        
        var trailingReserve: CGFloat = 0
        if safeLocation < nsString.length {
            let nextChar = nsString.character(at: safeLocation)
            if nextChar != 0xA, nextChar != 0xD {
                let caretGlyphIndex = layoutManager.glyphIndexForCharacter(at: safeLocation)
                if layoutManager.isValidGlyphIndex(caretGlyphIndex) {
                    let usedRect = layoutManager.lineFragmentUsedRect(forGlyphAt: caretGlyphIndex, effectiveRange: nil, withoutAdditionalLayout: true)
                    let caretContainerX = caretRect.minX - self.textContainerOrigin.x
                    trailingReserve = max(0, usedRect.maxX - caretContainerX)
                }
            }
        }
        
        return (caretRect, trailingReserve)
    }
    
    
    /// Shows a subtle `"···"` loading indicator while an asynchronous AI Next Token request is running.
    func showAIGhostLoadingIndicator() {
        
        guard
            AINextTokenPredictor.isInlineCompletionEnabled,
            self.isEditable,
            self.window?.isKeyWindow == true,
            !self.hasMarkedText(),
            !self.hasMultipleInsertions,
            self.selectedRange.isEmpty,
            (!UserDefaults.standard[.vimMode] || VimState.shared.mode == .insert),
            self.activeGhostSuggestion == nil,
            let geometry = self.exactCaretGeometry(at: self.selectedRange.location)
        else { return }
        
        let font = self.font ?? .monospacedSystemFont(ofSize: 13, weight: .regular)
        let baselineOffset = (self.layoutManager as? LayoutManager)?.baselineOffset(for: .horizontal) ?? max(11, font.ascender)
        self.funEffects.showGhostThinkingIndicator(
            at: geometry.caretRect,
            font: font,
            lineHeight: self.singleLineHeight,
            baselineOffset: baselineOffset
        )
    }
    
    
    /// Hides the thinking indicator if no real ghost suggestion replaced it.
    func hideAIGhostLoadingIndicatorIfNeeded() {
        
        if self.activeGhostSuggestion == nil, self.funEffects.isShowingGhostThinking {
            self.funEffects.hideGhostSuggestion(animated: false)
        }
    }
    
    
    /// Displays an AI-predicted ghost continuation delivered asynchronously for the active caret.
    func applyAIGhostSuggestion(_ candidate: String) {
        
        guard
            AINextTokenPredictor.isInlineCompletionEnabled,
            self.isEditable,
            self.window?.isKeyWindow == true,
            !self.hasMarkedText(),
            !self.hasMultipleInsertions,
            self.selectedRange.isEmpty,
            self.dismissedGhostCaretLocation != self.selectedRange.location,
            (!UserDefaults.standard[.vimMode] || VimState.shared.mode == .insert),
            !candidate.isEmpty
        else { return }
        
        self.showGhostCandidate(candidate, animateEntrance: true, isFromAI: true)
    }
    
    
    /// Returns `true` when the caret sits in an indentation / alignment / list-formatting context
    /// where `Tab` should format layout instead of accepting an inline ghost completion.
    static func isFormattingTabContext(
        linePrefix: String,
        lineSuffix: String,
        selectedRange: NSRange
    ) -> Bool {
        
        if !selectedRange.isEmpty {
            return true
        }
        // Start of line or inside leading whitespace indentation
        if linePrefix.isEmpty || linePrefix.allSatisfy(\.isWhitespace) {
            return true
        }
        // Immediately after a tab or consecutive spaces used for column alignment
        if linePrefix.hasSuffix("\t") || linePrefix.hasSuffix("  ") {
            return true
        }
        // Bare outline / bullet / numbered-list / quote / heading marker with no body text yet
        let nsPrefix = linePrefix as NSString
        if Self.formattingListPrefixRegex.firstMatch(in: linePrefix, range: NSRange(location: 0, length: nsPrefix.length)) != nil {
            return true
        }
        // Cursor positioned before existing text after whitespace (pushing text right to align)
        if !lineSuffix.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           linePrefix.last?.isWhitespace == true
        {
            return true
        }
        return false
    }
    
    
    private static func visibleTypedScalarCount(in string: String) -> Int {
        var count = 0
        for scalar in string.unicodeScalars where !CharacterSet.controlCharacters.contains(scalar) {
            count += 1
        }
        return count
    }
    
    
    /// Extracts the current line's prefix and suffix around `caretLocation`.
    private func currentLineContext(at caretLocation: Int) -> (linePrefix: String, lineSuffix: String) {
        
        let nsText = self.backingNSString
        guard nsText.length > 0 else { return ("", "") }
        let clampedCaret = max(0, min(caretLocation, nsText.length))
        let safeIndex = min(clampedCaret, max(0, nsText.length - 1))
        let lineRange = nsText.lineRange(for: NSRange(location: safeIndex, length: 0))
        // When caret sits right after a trailing newline at EOF, it is on a new empty line.
        if clampedCaret == NSMaxRange(lineRange),
           lineRange.length > 0,
           let lastChar = nsText.substring(with: NSRange(location: NSMaxRange(lineRange) - 1, length: 1)).first,
           lastChar.isNewline
        {
            return ("", "")
        }
        let linePrefix = nsText.substring(with: NSRange(location: lineRange.location, length: max(0, clampedCaret - lineRange.location)))
        let lineEnd = NSMaxRange(lineRange)
        let lineSuffix = (clampedCaret < lineEnd)
            ? nsText.substring(with: NSRange(location: clampedCaret, length: lineEnd - clampedCaret)).trimmingCharacters(in: .newlines)
            : ""
        return (linePrefix, lineSuffix)
    }
    
    
    /// Determines whether pressing `Tab` right now should accept the active ghost suggestion
    /// or perform standard Tab indentation/alignment.
    func shouldTabAcceptActiveGhost() -> Bool {
        
        guard
            self.isEditable,
            !self.hasMarkedText(),
            self.selectedRange.isEmpty,
            let suggestion = self.activeGhostSuggestion,
            !suggestion.isEmpty
        else { return false }
        
        let (linePrefix, lineSuffix) = self.currentLineContext(at: self.selectedRange.location)
        if Self.isFormattingTabContext(linePrefix: linePrefix, lineSuffix: lineSuffix, selectedRange: self.selectedRange) {
            return false
        }
        return true
    }
    
    
    /// Debounces inline ghost prediction slightly during rapid keystrokes so typing stays at zero latency,
    /// while preserving instant 0ms type-through on any already visible suggestion.
    func scheduleHabitGhostRefresh(animateEntrance: Bool = true, allowAIRefresh: Bool = true) {
        
        self.ghostRefreshTask?.cancel()
        self.ghostRefreshTask = nil
        
        guard
            AINextTokenPredictor.isInlineCompletionEnabled,
            self.isEditable,
            self.window?.isKeyWindow == true,
            !self.hasMarkedText(),
            !self.hasMultipleInsertions,
            self.selectedRange.isEmpty,
            (!UserDefaults.standard[.vimMode] || VimState.shared.mode == .insert)
        else {
            self.clearGhostSuggestion(animated: false)
            return
        }
        
        let expectedVersion = self.ghostTextVersion
        let expectedRange = self.selectedRange
        self.ghostRefreshTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(85))
            guard let self, !Task.isCancelled else { return }
            self.ghostRefreshTask = nil
            guard self.ghostTextVersion == expectedVersion,
                  self.selectedRange == expectedRange
            else { return }
            self.refreshHabitGhostSuggestion(animateEntrance: animateEntrance, allowAIRefresh: allowAIRefresh)
        }
    }
    
    
    /// Recomputes and displays or hides the hybrid Tier-1 (local habit) + Tier-2 (AI FIM) ghost candidate.
    func refreshHabitGhostSuggestion(animateEntrance: Bool = true, allowAIRefresh: Bool = true) {
        
        self.ghostRefreshTask?.cancel()
        self.ghostRefreshTask = nil
        
        guard
            AINextTokenPredictor.isInlineCompletionEnabled,
            self.isEditable,
            self.window?.isKeyWindow == true,
            !self.hasMarkedText(),
            !self.hasMultipleInsertions,
            self.selectedRange.isEmpty,
            (!UserDefaults.standard[.vimMode] || VimState.shared.mode == .insert)
        else {
            self.clearGhostSuggestion(animated: false)
            return
        }
        
        // Respect active Tab/Shift+Tab formatting cadence so consecutive layout Tabs are never hijacked.
        if ProcessInfo.processInfo.systemUptime - self.lastFormattingTabUptime < 1.5 {
            self.clearGhostSuggestion(animated: false, cancelAI: true)
            return
        }
        
        let caretLocation = self.selectedRange.location
        if self.dismissedGhostCaretLocation == caretLocation {
            self.clearGhostSuggestion(animated: false)
            return
        }
        
        let (linePrefix, lineSuffix) = self.currentLineContext(at: caretLocation)
        if Self.isFormattingTabContext(linePrefix: linePrefix, lineSuffix: lineSuffix, selectedRange: self.selectedRange) {
            self.clearGhostSuggestion(animated: false, cancelAI: true)
            return
        }
        
        let nsText = self.backingNSString
        let syntaxWords = self.cachedSyntaxCompletionTexts
        if let localCandidate = UserHabitPredictor.shared.predictNextPhrase(
            in: nsText,
            caretLocation: caretLocation,
            precomputedLineContext: (linePrefix, lineSuffix),
            syntaxWords: syntaxWords,
            siblingTextsProvider: { [weak self] in
                guard let self else { return [] }
                return NSDocumentController.shared.documents
                    .compactMap { $0 as? Document }
                    .filter { $0.textStorage !== self.textStorage }
                    .prefix(5)
                    .map { doc in
                        let siblingNS = doc.textStorage.mutableString as NSString
                        return siblingNS.substring(with: NSRange(location: 0, length: min(3_000, siblingNS.length))) as NSString
                    }
            }
        ), !localCandidate.isEmpty {
            AINextTokenPredictor.shared.cancel()
            self.showGhostCandidate(localCandidate, animateEntrance: animateEntrance, isFromAI: false)
            if self.lastLocalHitCaretLocation != caretLocation {
                self.lastLocalHitCaretLocation = caretLocation
                AINextTokenPredictor.shared.recordLocalHit()
                AnalyticsManager.shared.recordLocalCompletionHit()
            }
            return
        }
        
        if nsText.length > 0 {
            switch AINextTokenPredictor.shared.lookupCache(linePrefix: linePrefix, lineSuffix: lineSuffix) {
                case .hit(let cachedAI) where !cachedAI.isEmpty:
                    self.showGhostCandidate(cachedAI, animateEntrance: animateEntrance, isFromAI: false)
                    if self.lastLocalHitCaretLocation != caretLocation {
                        self.lastLocalHitCaretLocation = caretLocation
                        AINextTokenPredictor.shared.recordLocalHit()
                        AnalyticsManager.shared.recordLocalCompletionHit()
                    }
                    return
                case .knownEmpty:
                    self.clearGhostSuggestion(animated: false, cancelAI: false)
                    return
                case .hit, .miss:
                    break
            }
        }
        
        self.clearGhostSuggestion(animated: false, cancelAI: false)
        
        if allowAIRefresh {
            let doc = self.textStorage.flatMap { self.documentViewController?.document(for: $0) }
            AINextTokenPredictor.shared.schedulePrediction(
                for: self,
                syntaxName: doc?.syntaxName ?? SyntaxName.none,
                documentTitle: doc?.displayName ?? "",
                precomputedLineContext: (linePrefix, lineSuffix),
                skipCacheLookup: true
            )
        }
    }
    
    
    func showGhostCandidate(_ candidate: String, animateEntrance: Bool, isFromAI: Bool = false) {
        
        guard !candidate.isEmpty else {
            self.clearGhostSuggestion(animated: false, cancelAI: false)
            return
        }
        
        let layoutManager = self.layoutManager as? LayoutManager
        // Clear any prior inline shift before computing exact caret coordinates so re-predictions never drift.
        layoutManager?.inlineGhostShift = nil
        
        let caretLocation = self.selectedRange.location
        guard let geometry = self.exactCaretGeometry(at: caretLocation) else {
            self.clearGhostSuggestion(animated: false, cancelAI: false)
            return
        }
        
        let font = self.font ?? .monospacedSystemFont(ofSize: 13, weight: .regular)
        let baselineOffset = layoutManager?.baselineOffset(for: .horizontal) ?? max(11, font.ascender)
        
        self.activeGhostSuggestion = candidate
        self.isCurrentGhostFromAI = isFromAI
        let shiftWidth = self.funEffects.showGhostSuggestion(
            candidate,
            at: geometry.caretRect,
            font: font,
            lineHeight: self.singleLineHeight,
            baselineOffset: baselineOffset,
            trailingLineAdvance: geometry.trailingReserve,
            animateEntrance: animateEntrance
        )
        
        if geometry.trailingReserve > 0, shiftWidth > 0 {
            layoutManager?.inlineGhostShift = LayoutManager.InlineGhostShift(
                caretLocation: caretLocation,
                shiftWidth: shiftWidth
            )
        } else {
            layoutManager?.inlineGhostShift = nil
        }
    }
    
    
    /// Clears any visible inline ghost suggestion.
    func clearGhostSuggestion(animated: Bool = false, cancelAI: Bool = true) {
        
        self.ghostRefreshTask?.cancel()
        self.ghostRefreshTask = nil
        self.activeGhostSuggestion = nil
        self.isCurrentGhostFromAI = false
        (self.layoutManager as? LayoutManager)?.inlineGhostShift = nil
        self.funEffects.hideGhostSuggestion(animated: animated)
        if cancelAI {
            AINextTokenPredictor.shared.cancel()
        }
    }
    
    
    /// Accepts the visible inline ghost suggestion with a subtle completion sweep micro-animation.
    @discardableResult
    func acceptGhostSuggestionIfPresent() -> Bool {
        
        guard
            self.isEditable,
            !self.hasMarkedText(),
            self.selectedRange.isEmpty,
            let suggestion = self.activeGhostSuggestion,
            !suggestion.isEmpty
        else { return false }
        
        let caretLocation = self.selectedRange.location
        let wasFromAI = self.isCurrentGhostFromAI
        let nsText = self.string as NSString
        let lineRange = nsText.lineRange(for: NSRange(location: min(caretLocation, nsText.length), length: 0))
        let prefixContext = nsText.substring(with: NSRange(location: lineRange.location, length: max(0, caretLocation - lineRange.location)))
        
        var startRect = self.exactCaretGeometry(at: caretLocation)?.caretRect ?? .zero
        startRect.size.height = min(startRect.height > 0 ? startRect.height : self.singleLineHeight, self.singleLineHeight)
        
        AINextTokenPredictor.shared.recordSuggestionAccepted()
        self.clearGhostSuggestion(animated: false, cancelAI: true)
        
        self.isUpdatingGhostSuggestion = true
        super.insertText(suggestion, replacementRange: self.selectedRange)
        self.isUpdatingGhostSuggestion = false
        
        UserHabitPredictor.shared.recordAcceptedCompletion(prefixContext: prefixContext, acceptedPhrase: suggestion)
        AnalyticsManager.shared.recordGhostCompletionAccepted(charCount: suggestion.count, isFromAI: wasFromAI)
        
        var endRect = self.exactCaretGeometry(at: self.selectedRange.location)?.caretRect ?? startRect
        endRect.size.height = min(endRect.height > 0 ? endRect.height : self.singleLineHeight, self.singleLineHeight)
        self.funEffects.animateGhostCompletionAccept(from: startRect, to: endRect, color: self.effectiveCursorColor)
        
        self.refreshHabitGhostSuggestion(animateEntrance: true, allowAIRefresh: false)
        return true
    }
    
    
    // MARK: Private Methods
    
    /// Computes the horizontal band around the current caret without forcing additional TextKit layout.
    private func currentCaretHighlightBandWithoutAdditionalLayout() -> NSRect? {
        
        guard let layoutManager = self.layoutManager else { return nil }
        let length = self.textStorage?.length ?? (self.string as NSString).length
        let loc = self.selectedRange.location
        let fragmentRect: NSRect
        if length == 0 || loc >= length {
            let extra = layoutManager.extraLineFragmentRect
            if !extra.isEmpty {
                fragmentRect = extra
            } else if length > 0 {
                let glyphIdx = layoutManager.glyphIndexForCharacter(at: length - 1)
                guard layoutManager.isValidGlyphIndex(glyphIdx) else { return nil }
                fragmentRect = layoutManager.lineFragmentRect(forGlyphAt: glyphIdx, effectiveRange: nil, withoutAdditionalLayout: true)
            } else {
                return nil
            }
        } else {
            let glyphIdx = layoutManager.glyphIndexForCharacter(at: loc)
            guard layoutManager.isValidGlyphIndex(glyphIdx) else { return nil }
            fragmentRect = layoutManager.lineFragmentRect(forGlyphAt: glyphIdx, effectiveRange: nil, withoutAdditionalLayout: true)
        }
        guard fragmentRect.height > 0 else { return nil }
        let origin = self.textContainerOrigin
        return NSRect(
            x: self.visibleRect.minX,
            y: fragmentRect.minY + origin.y - 4,
            width: self.visibleRect.width,
            height: fragmentRect.height + 8
        )
    }
    
    
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
            if let font, let textStorage = self.textStorage, textStorage.length > 0 {
                textStorage.addAttribute(.font, value: font, range: textStorage.range)
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
        self.refreshWallpaperTransparency()
        
        self.setNeedsDisplay(self.visibleRect, avoidAdditionalLayout: true)
    }
    
    
    /// Allows the window's blurred `EditorWallpaperBackdropView` to shine cleanly behind all split panes when enabled.
    private func refreshWallpaperTransparency() {
        
        let isWindowOpaque = self.window?.isOpaque ?? true
        let wallpaperActive = WallpaperManager.shared.spec.isEnabled
        let shouldDrawSolid = isWindowOpaque && !wallpaperActive
        
        if self.drawsBackground != shouldDrawSolid {
            self.drawsBackground = shouldDrawSolid
        }
        if self.enclosingScrollView?.drawsBackground != shouldDrawSolid {
            self.enclosingScrollView?.drawsBackground = shouldDrawSolid
        }
        self.needsDisplay = true
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
    
    
    /// Removes the rounded instance highlight and, when asked, repaints the visible area.
    ///
    /// The forced repaint covers the TextKit edge case where the temporary attribute is
    /// already removed but a 1px tinted hairline survives until the next invalidation.
    private func clearSelectionInstanceHighlight(redraw: Bool = false) {
        
        guard let layoutManager = self.layoutManager else { return }
        
        let range = self.string.range
        if layoutManager.hasTemporaryAttribute(.roundedBackgroundColor) {
            layoutManager.removeTemporaryAttribute(.roundedBackgroundColor, forCharacterRange: range)
            layoutManager.invalidateDisplay(forCharacterRange: range)
        }
        
        if redraw {
            self.setNeedsDisplay(self.visibleRect, avoidAdditionalLayout: true)
        }
    }
    
    
    /// Updates the selection instance highlighting state.
    private func invalidateInstanceHighlights() {
        
        if !self.highlightsSelectionInstance {
            self.instanceHighlightTask?.cancel()
            self.instanceHighlightTask = nil
            self.clearSelectionInstanceHighlight()
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
    
    
    /// Updates the single highest-probability inline ghost candidate (never opens a popup list).
    private func performCompletion() {
        
        self.refreshHabitGhostSuggestion()
    }
    
    
    /// Detects a URL directly under `point` in view coordinates for `Cmd + Click` navigation.
    private func urlAtPoint(_ point: NSPoint) -> URL? {
        
        self.urlMatchAtPoint(point)?.url
    }
    
    
    /// Detects both the URL and its document character range under `point` in view coordinates.
    private func urlMatchAtPoint(_ point: NSPoint) -> (url: URL, range: NSRange)? {
        
        guard
            let layoutManager = self.layoutManager,
            let textContainer = self.textContainer,
            !self.string.isEmpty
        else { return nil }
        
        let containerPoint = point.offsetBy(dx: -self.textContainerOrigin.x, dy: -self.textContainerOrigin.y)
        var fraction: CGFloat = 0
        let glyphIndex = layoutManager.glyphIndex(for: containerPoint, in: textContainer, fractionOfDistanceThroughGlyph: &fraction)
        guard layoutManager.isValidGlyphIndex(glyphIndex) else { return nil }
        
        let usedRect = layoutManager.lineFragmentUsedRect(forGlyphAt: glyphIndex, effectiveRange: nil, withoutAdditionalLayout: true)
        guard usedRect.insetBy(dx: -2, dy: -2).contains(containerPoint) else { return nil }
        
        let charIndex = layoutManager.characterIndexForGlyph(at: glyphIndex)
        let nsString = self.string as NSString
        guard charIndex >= 0, charIndex < nsString.length else { return nil }
        
        let lineRange = nsString.lineRange(for: NSRange(location: charIndex, length: 0))
        let lineString = nsString.substring(with: lineRange)
        let localOffset = charIndex - lineRange.location
        guard let match = URLDetector.detectedLinkMatches(in: lineString)
            .first(where: { NSLocationInRange(localOffset, $0.range) })
        else { return nil }
        
        let globalRange = NSRange(location: lineRange.location + match.range.location, length: match.range.length)
        return (match.url, globalRange)
    }
    
    
    private func isPureCommandModifier(_ flags: NSEvent.ModifierFlags) -> Bool {
        
        flags.intersection(.deviceIndependentFlagsMask) == [.command]
    }
    
    
    private func updateCommandKeyLinkState(modifierFlags: NSEvent.ModifierFlags, mouseLocationInWindow: NSPoint?) {
        
        let shouldHighlight = self.isPureCommandModifier(modifierFlags) && (self.window?.isKeyWindow == true)
        guard shouldHighlight else {
            let hadCmd = self.isCommandKeyHeld || !self.commandLinkUnderlineRanges.isEmpty
            self.clearCommandLinkUnderlines()
            if hadCmd {
                self.window?.invalidateCursorRects(for: self)
            }
            return
        }
        
        var hoveredRange: NSRange?
        if let mouseLocationInWindow {
            let point = self.convert(mouseLocationInWindow, from: nil)
            if self.bounds.contains(point) {
                hoveredRange = self.urlMatchAtPoint(point)?.range
            }
        }
        
        let needsRefresh = !self.isCommandKeyHeld || hoveredRange != self.hoveredCommandLinkRange
        self.isCommandKeyHeld = true
        if needsRefresh {
            self.refreshCommandLinkUnderlines(hoveredRange: hoveredRange)
        }
        
        if hoveredRange != nil {
            NSCursor.pointingHand.set()
        } else if needsRefresh {
            self.window?.invalidateCursorRects(for: self)
        }
    }
    
    
    private func removeTemporaryLinkUnderlines(in layoutManager: NSLayoutManager, fullRange: NSRange) {
        let marked = self.markedRange()
        if marked.length == 0 || marked.location == NSNotFound {
            layoutManager.removeTemporaryAttribute(.underlineStyle, forCharacterRange: fullRange)
            layoutManager.removeTemporaryAttribute(.underlineColor, forCharacterRange: fullRange)
        } else {
            let safeMarked = NSIntersectionRange(marked, fullRange)
            if safeMarked.location > 0 {
                let prefix = NSRange(location: 0, length: safeMarked.location)
                layoutManager.removeTemporaryAttribute(.underlineStyle, forCharacterRange: prefix)
                layoutManager.removeTemporaryAttribute(.underlineColor, forCharacterRange: prefix)
            }
            let suffixStart = NSMaxRange(safeMarked)
            if suffixStart < fullRange.length {
                let suffix = NSRange(location: suffixStart, length: fullRange.length - suffixStart)
                layoutManager.removeTemporaryAttribute(.underlineStyle, forCharacterRange: suffix)
                layoutManager.removeTemporaryAttribute(.underlineColor, forCharacterRange: suffix)
            }
        }
    }
    
    
    private func refreshCommandLinkUnderlines(hoveredRange: NSRange?) {
        
        guard let layoutManager = self.layoutManager else { return }
        let nsString = self.string as NSString
        let totalLength = nsString.length
        guard totalLength > 0 else {
            self.commandLinkUnderlineRanges = []
            self.hoveredCommandLinkRange = nil
            return
        }
        
        let fullRange = NSRange(location: 0, length: totalLength)
        let rawVisible = self.range(for: self.visibleRect, withoutAdditionalLayout: true) ?? NSRange(location: 0, length: 0)
        let clampedVisible = NSIntersectionRange(rawVisible, fullRange)
        let scanRange: NSRange = clampedVisible.length > 0 ? nsString.lineRange(for: clampedVisible) : NSRange(location: 0, length: 0)
        
        let marked = self.markedRange()
        let detectedRanges: [NSRange] = scanRange.length > 0
            ? URLDetector.detectedLinkRanges(in: self.string, range: scanRange).filter {
                marked.length == 0 || NSIntersectionRange($0, marked).length == 0
            }
            : []
        
        let hadPrevious = !self.commandLinkUnderlineRanges.isEmpty
        self.hoveredCommandLinkRange = hoveredRange
        self.commandLinkUnderlineRanges = detectedRanges
        
        guard hadPrevious || !detectedRanges.isEmpty else { return }
        
        let isDark = self.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let accentColor = StudioPaletteManager.shared.chromePalette(for: self.theme, isDark: isDark).accent
        let subtleColor = accentColor.withAlphaComponent(0.68)
        
        layoutManager.groupTemporaryAttributesUpdate(in: fullRange) {
            self.removeTemporaryLinkUnderlines(in: layoutManager, fullRange: fullRange)
            for linkRange in detectedRanges {
                let color = (hoveredRange == linkRange) ? accentColor : subtleColor
                layoutManager.addTemporaryAttributes([
                    .underlineStyle: NSUnderlineStyle.single.rawValue,
                    .underlineColor: color,
                ], forCharacterRange: linkRange)
            }
        }
    }
    
    
    private func clearCommandLinkUnderlines() {
        
        let hadUnderlines = !self.commandLinkUnderlineRanges.isEmpty || self.isCommandKeyHeld
        self.isCommandKeyHeld = false
        self.commandLinkUnderlineRanges = []
        self.hoveredCommandLinkRange = nil
        
        guard hadUnderlines, let layoutManager = self.layoutManager else { return }
        let totalLength = (self.string as NSString).length
        guard totalLength > 0 else { return }
        
        let fullRange = NSRange(location: 0, length: totalLength)
        layoutManager.groupTemporaryAttributesUpdate(in: fullRange) {
            self.removeTemporaryLinkUnderlines(in: layoutManager, fullRange: fullRange)
        }
    }
    
    
    /// Snaps single-caret movement out of hidden `⟦🖼 ...⟧` inline image tokens so tokens remain atomic.
    private func snappedLocationOutsideInlineImageToken(_ location: Int, previousLocation: Int) -> Int? {
        
        guard (self.layoutManager as? LayoutManager)?.rendersPlainTextInlineImages == true else { return nil }
        let nsString = self.backingNSString
        guard location > 0, location < nsString.length else { return nil }
        
        let lineRange = nsString.lineRange(for: NSRange(location: location, length: 0))
        guard nsString.range(of: "⟦🖼", options: .literal, range: lineRange).location != NSNotFound,
              nsString.range(of: "⟧", options: .literal, range: lineRange).location != NSNotFound
        else { return nil }
        
        let docURL = self.currentInlineImageDocURL
        for token in PlainTextInlineImageStore.shared.findTokens(in: nsString, range: lineRange) {
            guard location > token.range.location, location < token.range.upperBound,
                  PlainTextInlineImageStore.shared.image(for: token.identifier, documentURL: docURL) != nil
            else { continue }
            return (previousLocation >= location) ? token.range.location : token.range.upperBound
        }
        return nil
    }
    
    
    /// Returns the full range of a resolved `⟦🖼 ...⟧` inline image token adjacent to the caret for atomic deletion.
    func resolvedInlineImageTokenRangeForDeletion(backward: Bool) -> NSRange? {
        
        guard (self.layoutManager as? LayoutManager)?.rendersPlainTextInlineImages == true else { return nil }
        let nsString = self.backingNSString
        let loc = self.selectedRange.location
        guard loc >= 0, loc <= nsString.length else { return nil }
        
        let probe = backward ? max(0, loc - 1) : min(loc, max(0, nsString.length - 1))
        guard nsString.length > 0 else { return nil }
        let lineRange = nsString.lineRange(for: NSRange(location: probe, length: 0))
        guard nsString.range(of: "⟦🖼", options: .literal, range: lineRange).location != NSNotFound,
              nsString.range(of: "⟧", options: .literal, range: lineRange).location != NSNotFound
        else { return nil }
        
        let docURL = self.currentInlineImageDocURL
        for token in PlainTextInlineImageStore.shared.findTokens(in: nsString, range: lineRange) {
            guard PlainTextInlineImageStore.shared.image(for: token.identifier, documentURL: docURL) != nil else { continue }
            if backward {
                if loc > token.range.location && loc <= token.range.upperBound {
                    return token.range
                }
            } else {
                if loc >= token.range.location && loc < token.range.upperBound {
                    return token.range
                }
            }
        }
        return nil
    }
}


// MARK: - Inline Image Card Geometry & Popover Views

private struct InlineImageCardEntry {
    
    let rect: NSRect
    let unrotatedCardSize: NSSize
    let drawSize: NSSize
    let center: NSPoint
    let rotationDegrees: CGFloat
    let scale: CGFloat
    let baseAnchorX: CGFloat
    let identifier: String
    let tokenRange: NSRange
    
    
    func rotatedPoint(local: NSPoint) -> NSPoint {
        let rad = self.rotationDegrees * .pi / 180.0
        let c = cos(rad)
        let s = sin(rad)
        return NSPoint(
            x: self.center.x + local.x * c - local.y * s,
            y: self.center.y + local.x * s + local.y * c
        )
    }
    
    
    func handlePoint(for handle: BoundingBoxHandle) -> NSPoint {
        self.rotatedPoint(local: handle.localPoint(size: self.unrotatedCardSize))
    }
    
    
    func hitTestHandle(at point: NSPoint) -> BoundingBoxHandle? {
        for handle in BoundingBoxHandle.allCases {
            let pt = self.handlePoint(for: handle)
            if abs(point.x - pt.x) <= 15 && abs(point.y - pt.y) <= 15 {
                return handle
            }
        }
        return nil
    }
    
    
    func rotationKnobCenter() -> NSPoint {
        self.rotatedPoint(local: NSPoint(x: 0, y: -self.unrotatedCardSize.height * 0.5 - 22))
    }
    
    
    func hitTestImage(point: NSPoint) -> Bool {
        let rad = -self.rotationDegrees * .pi / 180.0
        let dx = point.x - self.center.x
        let dy = point.y - self.center.y
        let lx = dx * cos(rad) - dy * sin(rad)
        let ly = dx * sin(rad) + dy * cos(rad)
        let hw = self.unrotatedCardSize.width * 0.5 + 3
        let hh = self.unrotatedCardSize.height * 0.5 + 3
        return abs(lx) <= hw && abs(ly) <= hh
    }
}


private final class InlineDimensionEditorField: NSTextField, NSTextFieldDelegate {
    
    var onCommit: ((String) -> Void)?
    var onCancel: (() -> Void)?
    private var didFinish = false
    
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        self.isBordered = false
        self.isBezeled = false
        self.drawsBackground = false
        self.focusRingType = .none
        self.alignment = .center
        self.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        self.textColor = NSColor(srgbRed: 0.09, green: 0.09, blue: 0.09, alpha: 1)
        self.wantsLayer = true
        self.layer?.backgroundColor = NSColor(srgbRed: 0.957, green: 0.957, blue: 0.957, alpha: 1).cgColor
        self.layer?.borderColor = NSColor(srgbRed: 30.0 / 255.0, green: 137.0 / 255.0, blue: 245.0 / 255.0, alpha: 1).cgColor
        self.layer?.borderWidth = 1.3
        self.layer?.cornerRadius = 9
        self.delegate = self
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func finishSilently() {
        self.didFinish = true
        self.delegate = nil
        self.onCommit = nil
        self.onCancel = nil
    }
    
    override func cancelOperation(_ sender: Any?) {
        guard !self.didFinish else { return }
        self.didFinish = true
        self.onCancel?()
    }
    
    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            guard !self.didFinish else { return true }
            self.didFinish = true
            self.onCommit?(self.stringValue)
            return true
        }
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            guard !self.didFinish else { return true }
            self.didFinish = true
            self.onCancel?()
            return true
        }
        return false
    }
    
    func controlTextDidEndEditing(_ obj: Notification) {
        guard !self.didFinish else { return }
        self.didFinish = true
        self.onCommit?(self.stringValue)
    }
}


private final class InlineImageMenuPayload: NSObject {
    
    let identifier: String
    let tokenRange: NSRange
    
    init(identifier: String, tokenRange: NSRange) {
        self.identifier = identifier
        self.tokenRange = tokenRange
    }
}


private struct InlineImagePreviewPopoverView: View {
    
    let image: NSImage
    let fileURL: URL?
    let onCopyImage: () -> Void
    let onRunOCR: () -> Void
    let onRevealInFinder: () -> Void
    let onDeleteToken: () -> Void
    
    @State private var previewZoom: CGFloat = 1.0
    
    var body: some View {
        
        VStack(alignment: .leading, spacing: 10) {
            ScrollView([.horizontal, .vertical], showsIndicators: self.previewZoom > 1.01) {
                Image(nsImage: self.image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(
                        width: 460 * self.previewZoom,
                        height: 320 * self.previewZoom
                    )
            }
            .frame(width: 460, height: 320)
            .background(Color.black.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color.secondary.opacity(0.18), lineWidth: 1))
            
            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Slider(value: self.$previewZoom, in: 1.0...4.0)
                        .frame(width: 96)
                    Text("\(Int((self.previewZoom * 100).rounded()))%")
                        .font(.system(size: 10.5).monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 38, alignment: .leading)
                }
                
                Spacer()
                
                Button("OCR 识别", action: self.onRunOCR)
                Button(AppLanguage.text("拷贝图片", en: "Copy"), action: self.onCopyImage)
                if self.fileURL != nil {
                    Button(AppLanguage.text("访达", en: "Finder"), action: self.onRevealInFinder)
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


private struct InlineImageTransformPopoverView: View {
    
    @State private var scale: Double
    @State private var offsetX: Double
    @State private var offsetY: Double
    @State private var rotationDegrees: Double
    
    let naturalSize: NSSize
    let containerWidth: CGFloat
    let maxImageWidth: CGFloat
    let scaleBounds: ClosedRange<Double>
    let maxOffsetX: CGFloat
    let onChange: (InlineImageTransform, Bool) -> Void
    let onReset: () -> Void
    let onClose: () -> Void
    
    
    init(
        initialTransform: InlineImageTransform,
        naturalSize: NSSize,
        containerWidth: CGFloat,
        maxImageWidth: CGFloat,
        scaleBounds: ClosedRange<Double>,
        maxOffsetX: CGFloat,
        onChange: @escaping (InlineImageTransform, Bool) -> Void,
        onReset: @escaping () -> Void,
        onClose: @escaping () -> Void
    ) {
        let clampedOffsetMax = max(120, maxOffsetX)
        let clampedScale = max(scaleBounds.lowerBound, min(scaleBounds.upperBound, Double(initialTransform.scale)))
        let clampedX = max(0, min(Double(clampedOffsetMax), Double(initialTransform.offsetX)))
        let clampedY = max(0, min(160, Double(initialTransform.offsetY)))
        let clampedRot = max(-180, min(180, Double(initialTransform.rotationDegrees)))
        
        self._scale = State(initialValue: clampedScale)
        self._offsetX = State(initialValue: clampedX)
        self._offsetY = State(initialValue: clampedY)
        self._rotationDegrees = State(initialValue: clampedRot)
        self.naturalSize = naturalSize
        self.containerWidth = containerWidth
        self.maxImageWidth = maxImageWidth
        self.scaleBounds = scaleBounds
        self.maxOffsetX = clampedOffsetMax
        self.onChange = onChange
        self.onReset = onReset
        self.onClose = onClose
    }
    
    
    private var liveDimensionsText: String {
        let base = InlineImageZoomMath.baseDrawSize(
            naturalSize: self.naturalSize,
            maxImageWidth: self.maxImageWidth
        )
        let maxW = InlineImageZoomMath.canvasMaxWidth(
            containerWidth: self.containerWidth,
            maxImageWidth: self.maxImageWidth
        )
        let size = InlineImageZoomMath.clampedAspectSize(
            desiredWidth: base.width * CGFloat(self.scale),
            naturalSize: self.naturalSize,
            maxWidth: maxW
        )
        return "\(Int(round(size.width))) × \(Int(round(size.height))) pt"
    }
    
    
    private func emitChange(scaleDidChange: Bool) {
        self.onChange(
            InlineImageTransform(
                scale: CGFloat(self.scale),
                offsetX: CGFloat(self.offsetX),
                offsetY: CGFloat(self.offsetY),
                rotationDegrees: CGFloat(self.rotationDegrees)
            ),
            scaleDidChange
        )
    }
    
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text(AppLanguage.text("无极精调", en: "Transform"))
                    .font(.system(size: 13, weight: .semibold))
                Text(self.liveDimensionsText)
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.primary.opacity(0.06), in: Capsule())
                Spacer()
                Button(AppLanguage.text("重置", en: "Reset")) {
                    self.scale = max(self.scaleBounds.lowerBound, min(self.scaleBounds.upperBound, 1.0))
                    self.offsetX = 0.0
                    self.offsetY = 0.0
                    self.rotationDegrees = 0.0
                    self.onReset()
                }
                .controlSize(.small)
                
                Button(AppLanguage.text("完成", en: "Done"), action: self.onClose)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
            
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 10) {
                GridRow {
                    Text(AppLanguage.text("无极缩放", en: "Scale"))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Slider(value: self.$scale, in: self.scaleBounds)
                        .frame(width: 170)
                        .onChange(of: self.scale) { _, _ in self.emitChange(scaleDidChange: true) }
                    Text("\(Int((self.scale * 100).rounded()))%")
                        .font(.system(size: 11.5).monospacedDigit())
                        .frame(width: 44, alignment: .trailing)
                }
                
                GridRow {
                    Text(AppLanguage.text("水平位置", en: "Offset X"))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Slider(value: self.$offsetX, in: 0...Double(self.maxOffsetX))
                        .frame(width: 170)
                        .onChange(of: self.offsetX) { _, _ in self.emitChange(scaleDidChange: false) }
                    Text("\(Int(self.offsetX.rounded())) pt")
                        .font(.system(size: 11.5).monospacedDigit())
                        .frame(width: 44, alignment: .trailing)
                }
                
                GridRow {
                    Text(AppLanguage.text("上方留白", en: "Offset Y"))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Slider(value: self.$offsetY, in: 0...160)
                        .frame(width: 170)
                        .onChange(of: self.offsetY) { _, _ in self.emitChange(scaleDidChange: false) }
                    Text("\(Int(self.offsetY.rounded())) pt")
                        .font(.system(size: 11.5).monospacedDigit())
                        .frame(width: 44, alignment: .trailing)
                }
                
                GridRow {
                    Text(AppLanguage.text("旋转角度", en: "Angle"))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Slider(value: self.$rotationDegrees, in: -180...180)
                        .frame(width: 170)
                        .onChange(of: self.rotationDegrees) { _, _ in self.emitChange(scaleDidChange: false) }
                    Text("\(Int(self.rotationDegrees.rounded()))°")
                        .font(.system(size: 11.5).monospacedDigit())
                        .frame(width: 44, alignment: .trailing)
                }
            }
            
            HStack(spacing: 5) {
                let presets = InlineImageZoomMath.quickScalePresets(
                    for: CGFloat(self.scaleBounds.lowerBound)...CGFloat(self.scaleBounds.upperBound),
                    fitLabel: AppLanguage.text("适配宽", en: "Fit")
                )
                ForEach(Array(presets.enumerated()), id: \.offset) { _, preset in
                    Button(preset.label) {
                        self.scale = Double(preset.scale)
                        self.emitChange(scaleDidChange: true)
                    }
                    .controlSize(.small)
                }
                Spacer()
                Button(AppLanguage.text("居左", en: "Left")) {
                    self.offsetX = 0
                    self.emitChange(scaleDidChange: false)
                }
                .controlSize(.small)
                Button(AppLanguage.text("居中", en: "Center")) {
                    self.offsetX = Double(self.maxOffsetX) * 0.5
                    self.emitChange(scaleDidChange: false)
                }
                .controlSize(.small)
            }
        }
        .padding(14)
        .frame(width: 332)
    }
}
