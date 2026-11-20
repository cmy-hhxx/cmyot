//
//  PaneTabStripView.swift
//
//  CotEditor
//  https://coteditor.com
//
//  ---------------------------------------------------------------------------
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

/// SwiftUI wrapper around the native AppKit `PaneTabStripNSView`, providing instant
/// click selection, double-click / context-menu inline renaming, smooth drag reordering,
/// cross-pane/window dropping, and drag-out-to-new-window detachment.
struct PaneTabStripView: NSViewRepresentable {
    
    var state: PaneTabState
    
    func makeNSView(context: Context) -> PaneTabStripNSView {
        
        let view = PaneTabStripNSView()
        view.state = self.state
        self.state.onRequestInlineRename = { [weak view] tab in
            view?.beginInlineRename(for: tab)
        }
        return view
    }
    
    
    func updateNSView(_ nsView: PaneTabStripNSView, context: Context) {
        
        // Observe observable properties so SwiftUI re-renders whenever tabs, selection, or revision change
        _ = self.state.tabs.map { ($0.id, $0.title, $0.isPinned, $0.isEdited, $0.isClosable) }
        _ = self.state.selectedTab?.id
        _ = self.state.refreshRevision
        
        nsView.state = self.state
        self.state.onRequestInlineRename = { [weak nsView] tab in
            nsView?.beginInlineRename(for: tab)
        }
        nsView.reloadTabs()
    }
}


// MARK: - Native AppKit Tab Strip

@MainActor final class PaneTabStripNSView: NSView, NSDraggingSource, NSTextFieldDelegate {
    
    var state: PaneTabState?
    
    private let scrollView = NonDraggableScrollView()
    private let documentContainer = TabStripContainerView()
    private let newTabButton = CenteredIconButton(symbolName: "plus", pointSize: 10.5, weight: .semibold, accessibilityDescription: "New Tab", hoverStyle: .newTab)
    private let insertionIndicator = NSView()
    
    private var tabViews: [UUID: PaneTabItemView] = [:]
    private var orderedTabIDs: [UUID] = []
    private var tabFrames: [UUID: NSRect] = [:]
    
    // Inline rename state
    private var renamingTabID: UUID?
    private weak var renameField: NSTextField?
    private var renameBeganUptime: TimeInterval = 0
    private var isEndingRename = false
    private var suppressControlEndEditing = false
    
    // Drag state
    private var draggingTab: PaneTab?
    private var dragStartScreenPoint: NSPoint?
    private var dropInsertionIndex: Int?
    
    private static let tabHeight: CGFloat = 24
    private static let tabSpacing: CGFloat = 4
    private static let minTabWidth: CGFloat = 80
    private static let maxTabWidth: CGFloat = 240
    
    
    override init(frame frameRect: NSRect) {
        
        super.init(frame: frameRect)
        self.setupViews()
    }
    
    
    required init?(coder: NSCoder) {
        
        fatalError("init(coder:) has not been implemented")
    }
    
    
    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }
    
    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: Self.tabHeight)
    }
    
    
    private func setupViews() {
        
        self.wantsLayer = true
        
        self.scrollView.contentView = NonDraggableClipView()
        self.scrollView.drawsBackground = false
        self.scrollView.hasVerticalScroller = false
        self.scrollView.hasHorizontalScroller = false
        self.scrollView.borderType = .noBorder
        self.scrollView.documentView = self.documentContainer
        self.scrollView.translatesAutoresizingMaskIntoConstraints = false
        self.addSubview(self.scrollView)
        
        self.newTabButton.contentTintColor = .secondaryLabelColor
        self.newTabButton.wantsLayer = true
        self.newTabButton.layer?.cornerRadius = 6
        self.newTabButton.layer?.cornerCurve = .continuous
        self.newTabButton.target = self
        self.newTabButton.action = #selector(addNewTab(_:))
        self.newTabButton.toolTip = String(localized: "chrome.tab.newTabHelp", defaultValue: "New Tab", table: "Chrome")
        self.documentContainer.addSubview(self.newTabButton)
        
        self.insertionIndicator.wantsLayer = true
        self.insertionIndicator.layer?.backgroundColor = NSColor.controlAccentColor.cgColor
        self.insertionIndicator.layer?.cornerRadius = 1
        self.insertionIndicator.isHidden = true
        self.documentContainer.addSubview(self.insertionIndicator)
        
        NSLayoutConstraint.activate([
            self.scrollView.leadingAnchor.constraint(equalTo: self.leadingAnchor),
            self.scrollView.topAnchor.constraint(equalTo: self.topAnchor),
            self.scrollView.bottomAnchor.constraint(equalTo: self.bottomAnchor),
            self.scrollView.trailingAnchor.constraint(equalTo: self.trailingAnchor),
        ])
        
        self.registerForDraggedTypes([PaneTab.dragPasteboardType, .string])
    }
    
    
    override func layout() {
        
        super.layout()
        self.layoutTabViews(animated: false)
    }
    
    
    func reloadTabs() {
        
        guard let state = self.state else { return }
        
        let currentIDs = Set(state.tabs.map(\.id))
        for (id, view) in self.tabViews where !currentIDs.contains(id) {
            if self.renamingTabID == id {
                self.cancelInlineRename()
            }
            view.removeFromSuperview()
            self.tabViews.removeValue(forKey: id)
        }
        
        self.orderedTabIDs = state.tabs.map(\.id)
        
        for tab in state.tabs {
            let itemView: PaneTabItemView
            if let existing = self.tabViews[tab.id] {
                itemView = existing
            } else {
                itemView = PaneTabItemView()
                itemView.stripView = self
                self.documentContainer.addSubview(itemView)
                self.tabViews[tab.id] = itemView
            }
            
            itemView.configure(
                tab: tab,
                isSelected: tab === state.selectedTab,
                isRenaming: self.renamingTabID == tab.id
            )
        }
        
        self.layoutTabViews(animated: false)
    }
    
    
    private func layoutTabViews(animated: Bool) {
        
        guard let state = self.state else { return }
        
        var cursorX: CGFloat = 0
        var newFrames: [UUID: NSRect] = [:]
        
        for tab in state.tabs {
            guard let itemView = self.tabViews[tab.id] else { continue }
            let width = itemView.preferredWidth(minWidth: Self.minTabWidth, maxWidth: Self.maxTabWidth)
            let frame = NSRect(x: cursorX, y: 1, width: width, height: Self.tabHeight - 2)
            newFrames[tab.id] = frame
            cursorX += width + Self.tabSpacing
        }
        
        self.tabFrames = newFrames
        self.newTabButton.frame = NSRect(x: cursorX, y: 1, width: 22, height: Self.tabHeight - 2)
        let totalWidth = max(self.scrollView.bounds.width, cursorX + 28)
        self.documentContainer.frame = NSRect(x: 0, y: 0, width: totalWidth, height: Self.tabHeight)
        
        let applyFrames = {
            for (id, frame) in newFrames {
                guard let view = self.tabViews[id] else { continue }
                if animated {
                    view.animator().frame = frame
                } else {
                    view.frame = frame
                }
            }
        }
        
        if animated {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.14
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                applyFrames()
            }
        } else {
            applyFrames()
        }
        
        if let selected = state.selectedTab, let selectedFrame = newFrames[selected.id] {
            self.documentContainer.scrollToVisible(selectedFrame.insetBy(dx: -8, dy: 0))
        }
    }
    
    
    // MARK: Actions
    
    @objc private func addNewTab(_ sender: Any?) {
        
        self.commitInlineRenameIfNeeded()
        self.state?.onNewTab()
    }
    
    
    func selectTab(_ tab: PaneTab) {
        
        guard self.renamingTabID != tab.id else { return }
        self.commitInlineRenameIfNeeded(restoreEditorFocus: false)
        self.state?.onSelect(tab)
    }
    
    
    func closeTab(_ tab: PaneTab) {
        
        self.commitInlineRenameIfNeeded(restoreEditorFocus: false)
        self.state?.onClose(tab)
    }
    
    
    func togglePin(_ tab: PaneTab) {
        
        self.commitInlineRenameIfNeeded(restoreEditorFocus: false)
        self.state?.onTogglePin(tab)
    }
    
    
    func beginInlineRename(for tab: PaneTab) {
        
        if self.renamingTabID == tab.id, let existingField = self.renameField {
            if self.window?.isKeyWindow == false {
                self.window?.makeKey()
            }
            self.window?.makeFirstResponderDiscardingMarkedText(existingField)
            existingField.selectText(nil)
            return
        }
        
        self.commitInlineRenameIfNeeded(restoreEditorFocus: false)
        guard let itemView = self.tabViews[tab.id] else { return }
        
        self.renamingTabID = tab.id
        self.renameBeganUptime = ProcessInfo.processInfo.systemUptime
        let field = itemView.enterRenameMode(initialTitle: tab.title, delegate: self)
        field.target = self
        field.action = #selector(commitRenameFromFieldAction(_:))
        self.renameField = field
        
        self.layoutTabViews(animated: false)
        self.documentContainer.layoutSubtreeIfNeeded()
        itemView.layoutSubtreeIfNeeded()
        self.documentContainer.scrollToVisible(itemView.frame.insetBy(dx: -8, dy: 0))
        
        if self.window?.isKeyWindow == false {
            self.window?.makeKey()
        }
        self.window?.makeFirstResponderDiscardingMarkedText(field)
        field.selectText(nil)
        
        // Re-assert first responder on the next runloop turns in case an asynchronous
        // editor selection focus restore or context-menu teardown runs during the same event cycle.
        let targetTabID = tab.id
        for delayMs in [0, 50] {
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(delayMs)) { [weak self, weak field] in
                guard
                    let self,
                    let field,
                    self.renamingTabID == targetTabID,
                    self.renameField === field,
                    let window = self.window,
                    window.firstResponder !== field,
                    window.firstResponder !== field.currentEditor()
                else { return }
                window.makeFirstResponderDiscardingMarkedText(field)
                field.selectText(nil)
            }
        }
    }
    
    
    @objc private func commitRenameFromFieldAction(_ sender: Any?) {
        
        self.commitInlineRenameIfNeeded(restoreEditorFocus: true)
    }
    
    
    private func commitInlineRenameIfNeeded(restoreEditorFocus: Bool = false) {
        
        guard !self.isEndingRename else { return }
        self.isEndingRename = true
        defer { self.isEndingRename = false }
        
        guard
            let tabID = self.renamingTabID,
            let field = self.renameField,
            let tab = self.state?.tabs.first(where: { $0.id == tabID })
        else {
            self.cancelInlineRename(restoreEditorFocus: restoreEditorFocus)
            return
        }
        
        // Read active field editor string when available so uncommitted IME/editor text is never dropped.
        let editedString = (field.currentEditor()?.string ?? field.stringValue)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        self.suppressControlEndEditing = true
        self.renamingTabID = nil
        self.renameField = nil
        if self.window?.firstResponder === field || self.window?.firstResponder === field.currentEditor() {
            self.window?.endEditing(for: field)
        }
        self.tabViews[tabID]?.exitRenameMode()
        self.layoutTabViews(animated: false)
        self.suppressControlEndEditing = false
        
        if !editedString.isEmpty, editedString != tab.title {
            self.state?.onRename(tab, editedString)
            self.reloadTabs()
        }
        
        if restoreEditorFocus {
            self.restoreFocusedEditorResponder()
        }
    }
    
    
    private func cancelInlineRename(restoreEditorFocus: Bool = false) {
        
        let hadActiveRename = (self.renamingTabID != nil || self.renameField != nil)
        self.suppressControlEndEditing = true
        if let tabID = self.renamingTabID, let field = self.renameField {
            if self.window?.firstResponder === field || self.window?.firstResponder === field.currentEditor() {
                self.window?.endEditing(for: field)
            }
            self.tabViews[tabID]?.exitRenameMode()
        } else if let tabID = self.renamingTabID {
            self.tabViews[tabID]?.exitRenameMode()
        }
        self.renamingTabID = nil
        self.renameField = nil
        if hadActiveRename {
            self.layoutTabViews(animated: false)
        }
        self.suppressControlEndEditing = false
        
        if restoreEditorFocus, hadActiveRename {
            self.restoreFocusedEditorResponder()
        }
    }
    
    
    private func restoreFocusedEditorResponder() {
        
        if let docVC = (self.window?.windowController as? DocumentWindowController)?.documentViewController,
           let textView = docVC.focusedTextView
        {
            self.window?.makeFirstResponderDiscardingMarkedText(textView)
        }
    }
    
    
    // MARK: NSTextFieldDelegate
    
    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        
        if textView.hasMarkedText() {
            return false
        }
        if commandSelector == #selector(NSResponder.insertNewline(_:))
            || commandSelector == #selector(NSResponder.insertTab(_:))
            || commandSelector == #selector(NSResponder.insertBacktab(_:))
        {
            self.commitInlineRenameIfNeeded(restoreEditorFocus: true)
            return true
        }
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            self.cancelInlineRename(restoreEditorFocus: true)
            return true
        }
        return false
    }
    
    
    func controlTextDidEndEditing(_ obj: Notification) {
        
        guard !self.suppressControlEndEditing, !self.isEndingRename else { return }
        // Ignore transient focus churn immediately after starting inline rename (e.g. from double-click
        // selection or context menu teardown) so the text field stays open for user input.
        if ProcessInfo.processInfo.systemUptime - self.renameBeganUptime < 0.25,
           let targetTabID = self.renamingTabID,
           let field = self.renameField
        {
            DispatchQueue.main.async { [weak self, weak field] in
                guard
                    let self,
                    let field,
                    self.renamingTabID == targetTabID,
                    self.renameField === field,
                    let window = self.window
                else { return }
                window.makeFirstResponderDiscardingMarkedText(field)
                field.selectText(nil)
            }
            return
        }
        self.commitInlineRenameIfNeeded(restoreEditorFocus: false)
    }
    
    
    // MARK: Tab Context Menu
    
    func contextMenu(for tab: PaneTab) -> NSMenu {
        
        let menu = NSMenu()
        menu.autoenablesItems = false
        
        let renameItem = NSMenuItem(
            title: String(localized: "chrome.tab.rename", defaultValue: "Rename…", table: "Chrome"),
            action: #selector(contextMenuRename(_:)),
            keyEquivalent: ""
        )
        renameItem.target = self
        renameItem.representedObject = tab
        menu.addItem(renameItem)
        
        let pinTitle = tab.isPinned
            ? String(localized: "chrome.tab.unpin", defaultValue: "Unpin Tab", table: "Chrome")
            : String(localized: "chrome.tab.pin", defaultValue: "Pin Tab", table: "Chrome")
        let pinItem = NSMenuItem(title: pinTitle, action: #selector(contextMenuTogglePin(_:)), keyEquivalent: "")
        pinItem.target = self
        pinItem.representedObject = tab
        menu.addItem(pinItem)
        
        menu.addItem(.separator())
        
        let closeItem = NSMenuItem(
            title: String(localized: "chrome.tab.close", defaultValue: "Close Tab", table: "Chrome"),
            action: #selector(contextMenuClose(_:)),
            keyEquivalent: ""
        )
        closeItem.target = self
        closeItem.representedObject = tab
        closeItem.isEnabled = !tab.isPinned && tab.isClosable
        menu.addItem(closeItem)
        
        return menu
    }
    
    
    @objc private func contextMenuRename(_ sender: NSMenuItem) {
        
        guard let tab = sender.representedObject as? PaneTab else { return }
        // Defer one turn so AppKit finishes closing the popup menu before focusing the field editor.
        DispatchQueue.main.async { [weak self] in
            self?.beginInlineRename(for: tab)
        }
    }
    
    
    @objc private func contextMenuTogglePin(_ sender: NSMenuItem) {
        
        guard let tab = sender.representedObject as? PaneTab else { return }
        self.togglePin(tab)
    }
    
    
    @objc private func contextMenuClose(_ sender: NSMenuItem) {
        
        guard let tab = sender.representedObject as? PaneTab else { return }
        self.closeTab(tab)
    }
    
    
    // MARK: Drag Initiation (NSDraggingSource)
    
    func startDrag(for tab: PaneTab, from itemView: PaneTabItemView, event: NSEvent) {
        
        self.commitInlineRenameIfNeeded()
        self.draggingTab = tab
        self.dragStartScreenPoint = NSEvent.mouseLocation
        
        let pboardItem = NSPasteboardItem()
        pboardItem.setString(tab.id.uuidString, forType: PaneTab.dragPasteboardType)
        pboardItem.setString(tab.dragPayload, forType: .string)
        
        let draggingItem = NSDraggingItem(pasteboardWriter: pboardItem)
        let previewImage = itemView.dragSnapshotImage()
        let itemFrameInSelf = self.convert(itemView.bounds, from: itemView)
        draggingItem.setDraggingFrame(itemFrameInSelf, contents: previewImage)
        
        let session = self.beginDraggingSession(with: [draggingItem], event: event, source: self)
        session.animatesToStartingPositionsOnCancelOrFail = false
    }
    
    
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        
        context == .withinApplication ? [.move] : []
    }
    
    
    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        
        defer {
            self.draggingTab = nil
            self.dragStartScreenPoint = nil
            self.hideInsertionIndicator()
        }
        
        guard operation == [], let tab = self.draggingTab else { return }
        
        // Check that the user dragged meaningfully outside the source tab bar (tear-off into new window)
        if let window = self.window {
            let stripInWindow = self.convert(self.bounds, to: nil)
            let stripOnScreen = window.convertToScreen(stripInWindow).insetBy(dx: -24, dy: -28)
            if !stripOnScreen.contains(screenPoint) {
                self.state?.onDetachToNewWindow(tab, screenPoint)
            }
        }
    }
    
    
    // MARK: Drop Target (NSDraggingDestination)
    
    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        
        guard self.extractTabID(from: sender.draggingPasteboard) != nil else { return [] }
        self.updateInsertionIndicator(for: sender)
        return .move
    }
    
    
    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        
        guard self.extractTabID(from: sender.draggingPasteboard) != nil else { return [] }
        self.updateInsertionIndicator(for: sender)
        return .move
    }
    
    
    override func draggingExited(_ sender: (any NSDraggingInfo)?) {
        
        self.hideInsertionIndicator()
    }
    
    
    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        
        let targetIndex = self.insertionIndex(for: sender)
        self.hideInsertionIndicator()
        
        guard let draggedID = self.extractTabID(from: sender.draggingPasteboard),
              let state = self.state
        else { return false }
        
        if let localTab = state.tabs.first(where: { $0.id == draggedID }) {
            state.onMoveToIndex(localTab, targetIndex)
            return true
        }
        
        return state.onDropTab(draggedID, targetIndex)
    }
    
    
    private func extractTabID(from pasteboard: NSPasteboard) -> UUID? {
        
        if let raw = pasteboard.string(forType: PaneTab.dragPasteboardType),
           let id = UUID(uuidString: raw.trimmingCharacters(in: .whitespacesAndNewlines))
        {
            return id
        }
        if let raw = pasteboard.string(forType: .string),
           raw.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix(PaneTab.dragPrefix),
           let id = PaneTab.tabID(from: raw)
        {
            return id
        }
        return nil
    }
    
    
    private func insertionIndex(for draggingInfo: any NSDraggingInfo) -> Int {
        
        guard let state = self.state, !state.tabs.isEmpty else { return 0 }
        let pointInContainer = self.documentContainer.convert(draggingInfo.draggingLocation, from: nil)
        
        for (index, tab) in state.tabs.enumerated() {
            if let frame = self.tabFrames[tab.id], pointInContainer.x < frame.midX {
                return index
            }
        }
        return state.tabs.count
    }
    
    
    private func updateInsertionIndicator(for draggingInfo: any NSDraggingInfo) {
        
        guard let state = self.state else { return }
        let index = self.insertionIndex(for: draggingInfo)
        self.dropInsertionIndex = index
        
        let indicatorX: CGFloat
        if index == 0 {
            indicatorX = 1
        } else if index >= state.tabs.count, let lastTab = state.tabs.last, let lastFrame = self.tabFrames[lastTab.id] {
            indicatorX = lastFrame.maxX + 1
        } else if let targetTab = state.tabs[safe: index], let targetFrame = self.tabFrames[targetTab.id] {
            indicatorX = targetFrame.minX - 2
        } else {
            indicatorX = 1
        }
        
        self.insertionIndicator.frame = NSRect(x: indicatorX, y: 2, width: 2.5, height: Self.tabHeight - 4)
        self.insertionIndicator.isHidden = false
    }
    
    
    private func hideInsertionIndicator() {
        
        self.dropInsertionIndex = nil
        self.insertionIndicator.isHidden = true
    }
}


// MARK: - Container & Individual Tab Item View

private final class NonDraggableLabel: NSTextField {
    
    override var mouseDownCanMoveWindow: Bool { false }
}


private final class CenteredIconButton: NSButton {
    
    enum HoverStyle {
        case standard
        case close
        case newTab
        case pin
    }
    
    /// Standalone layers (not view-backed), so transforms rotate around their true center and implicit fades work.
    private let hoverLayer = CALayer()
    private let iconLayer = CALayer()
    private let baseImage: NSImage?
    private let hoverStyle: HoverStyle
    private var baseTintColor: NSColor = .secondaryLabelColor
    private var trackingArea: NSTrackingArea?
    private var isPointerHovered = false
    
    private static let ease = CAMediaTimingFunction(controlPoints: 0.2, 0, 0, 1)
    
    override var mouseDownCanMoveWindow: Bool { false }
    
    
    init(
        symbolName: String,
        pointSize: CGFloat,
        weight: NSFont.Weight,
        accessibilityDescription: String,
        hoverStyle: HoverStyle = .standard
    ) {
        self.hoverStyle = hoverStyle
        self.baseImage = NSImage(systemSymbolName: symbolName, accessibilityDescription: accessibilityDescription)?
            .withSymbolConfiguration(.init(pointSize: pointSize, weight: weight))
        super.init(frame: .zero)
        self.isBordered = false
        self.bezelStyle = .regularSquare
        self.focusRingType = .none
        self.title = ""
        self.image = nil
        self.wantsLayer = true
        self.setAccessibilityLabel(accessibilityDescription)
        
        self.hoverLayer.opacity = 0
        self.hoverLayer.cornerCurve = .continuous
        self.layer?.addSublayer(self.hoverLayer)
        self.iconLayer.contentsGravity = .center
        self.layer?.addSublayer(self.iconLayer)
    }
    
    
    required init?(coder: NSCoder) {
        
        fatalError("init(coder:) has not been implemented")
    }
    
    
    override var contentTintColor: NSColor? {
        didSet {
            self.baseTintColor = self.contentTintColor ?? .secondaryLabelColor
            self.refreshIcon()
        }
    }
    
    
    override func layout() {
        
        super.layout()
        
        let scale = self.window?.backingScaleFactor ?? 2
        let size = self.baseImage?.size ?? .zero
        let side = min(self.bounds.width, self.bounds.height)
        
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        self.hoverLayer.frame = (self.hoverStyle == .close)
            ? CGRect(x: (self.bounds.width - side) / 2, y: (self.bounds.height - side) / 2, width: side, height: side)
            : self.bounds
        self.hoverLayer.cornerRadius = (self.hoverStyle == .close) ? side / 2 : 6
        self.iconLayer.bounds = CGRect(origin: .zero, size: size)
        self.iconLayer.position = CGPoint(x: self.bounds.midX, y: self.bounds.midY)
        self.iconLayer.contentsScale = scale
        CATransaction.commit()
        
        if self.iconLayer.contents == nil {
            self.refreshIcon()
        }
    }
    
    
    override func viewDidChangeEffectiveAppearance() {
        
        super.viewDidChangeEffectiveAppearance()
        self.refreshIcon()
        self.refreshHoverFill()
    }
    
    
    override func viewDidMoveToWindow() {
        
        super.viewDidMoveToWindow()
        self.needsLayout = true
        self.refreshIcon()
    }
    
    
    override func updateTrackingAreas() {
        
        super.updateTrackingAreas()
        if let existing = self.trackingArea {
            self.removeTrackingArea(existing)
        }
        let area = NSTrackingArea(rect: self.bounds, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self)
        self.addTrackingArea(area)
        self.trackingArea = area
    }
    
    
    override func mouseEntered(with event: NSEvent) {
        
        super.mouseEntered(with: event)
        self.setHovered(true)
    }
    
    
    override func mouseExited(with event: NSEvent) {
        
        super.mouseExited(with: event)
        self.setHovered(false)
    }
    
    
    override func mouseDown(with event: NSEvent) {
        
        // pressed: deepen the fill instead of scaling the view
        let previous = self.hoverLayer.backgroundColor
        self.effectiveAppearance.performAsCurrentDrawingAppearance {
            self.hoverLayer.backgroundColor = self.hoverFillColor(pressed: true).cgColor
        }
        self.hoverLayer.opacity = 1
        CATransaction.flush()
        super.mouseDown(with: event)
        self.hoverLayer.backgroundColor = previous
        if !self.isPointerHovered {
            self.hoverLayer.opacity = 0
        }
    }
    
    
    override func hitTest(_ point: NSPoint) -> NSView? {
        
        let local = self.convert(point, from: self.superview)
        return (!self.isHidden && self.bounds.contains(local)) ? self : nil
    }
    
    
    // MARK: Private
    
    private var currentTint: NSColor {
        
        guard self.isPointerHovered else { return self.baseTintColor }
        switch self.hoverStyle {
            case .close: return .systemRed
            case .newTab, .standard: return .labelColor
            case .pin: return .controlAccentColor
        }
    }
    
    
    private func hoverFillColor(pressed: Bool = false) -> NSColor {
        
        switch self.hoverStyle {
            case .close: NSColor.systemRed.withAlphaComponent(pressed ? 0.2 : 0.12)
            default: NSColor.labelColor.withAlphaComponent(pressed ? 0.14 : 0.08)
        }
    }
    
    
    private func refreshHoverFill() {
        
        self.effectiveAppearance.performAsCurrentDrawingAppearance {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            self.hoverLayer.backgroundColor = self.hoverFillColor().cgColor
            CATransaction.commit()
        }
    }
    
    
    private func refreshIcon() {
        
        guard let baseImage = self.baseImage else { return }
        let scale = self.window?.backingScaleFactor ?? 2
        var image: CGImage?
        self.effectiveAppearance.performAsCurrentDrawingAppearance {
            let resolved = NSColor(cgColor: self.currentTint.cgColor) ?? self.currentTint
            guard let tinted = baseImage.withSymbolConfiguration(.init(paletteColors: [resolved])) else { return }
            var rect = NSRect(origin: .zero, size: tinted.size)
            let transform = NSAffineTransform()
            transform.scale(by: scale)
            image = tinted.cgImage(forProposedRect: &rect, context: nil, hints: [.ctm: transform])
        }
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.14)
        CATransaction.setAnimationTimingFunction(Self.ease)
        self.iconLayer.contents = image
        CATransaction.commit()
    }
    
    
    private func setHovered(_ hovered: Bool) {
        
        self.isPointerHovered = hovered
        self.refreshHoverFill()
        self.refreshIcon()
        
        let reduceMotion = AnimationConstants.isReducedMotionEnabled
        CATransaction.begin()
        CATransaction.setAnimationDuration(reduceMotion ? 0 : 0.14)
        CATransaction.setAnimationTimingFunction(Self.ease)
        self.hoverLayer.opacity = hovered ? 1 : 0
        CATransaction.commit()
        
        // Only the close button moves: a quarter turn that says "this closes".
        guard self.hoverStyle == .close else { return }
        let angle: CGFloat = hovered ? .pi / 2 : 0
        let from = self.iconLayer.presentation()?.value(forKeyPath: "transform.rotation.z") as? CGFloat ?? (hovered ? 0 : .pi / 2)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        self.iconLayer.transform = CATransform3DMakeRotation(angle, 0, 0, 1)
        CATransaction.commit()
        guard !reduceMotion else { return }
        let spin = CABasicAnimation(keyPath: "transform.rotation.z")
        spin.fromValue = from
        spin.toValue = angle
        spin.duration = 0.22
        spin.timingFunction = Self.ease
        self.iconLayer.add(spin, forKey: "hoverSpin")
    }
}


private final class NonDraggableScrollView: NSScrollView {
    
    override var mouseDownCanMoveWindow: Bool { false }
}


private final class NonDraggableClipView: NSClipView {
    
    override var mouseDownCanMoveWindow: Bool { false }
}


private final class TabStripContainerView: NSView {
    
    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }
}


@MainActor final class PaneTabItemView: NSView {
    
    weak var stripView: PaneTabStripNSView?
    
    private var tab: PaneTab?
    private var isSelected = false
    private var isHovered = false
    private var isRenaming = false
    private var lastConfiguredTitle: String?
    private var lastConfiguredEdited: Bool?
    
    private let activeAccentBar = CALayer()
    private let editedHaloLayer = CALayer()
    private let statusDotLayer = CALayer()
    private let pinButton = CenteredIconButton(symbolName: "pin.fill", pointSize: 9, weight: .semibold, accessibilityDescription: "Pinned", hoverStyle: .pin)
    private let titleLabel: NonDraggableLabel = {
        let label = NonDraggableLabel(labelWithString: "")
        label.wantsLayer = true
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return label
    }()
    private let editedDot = NSView()
    private let closeButton = CenteredIconButton(symbolName: "xmark", pointSize: 9, weight: .semibold, accessibilityDescription: "Close", hoverStyle: .close)
    private var inlineTextField: NSTextField?
    
    private var trackingArea: NSTrackingArea?
    private var mouseDownLocation: NSPoint?
    private var didStartDrag = false
    
    
    override init(frame frameRect: NSRect) {
        
        super.init(frame: frameRect)
        self.setupViews()
    }
    
    
    required init?(coder: NSCoder) {
        
        fatalError("init(coder:) has not been implemented")
    }
    
    
    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }
    
    
    override func hitTest(_ point: NSPoint) -> NSView? {
        
        let local = self.convert(point, from: self.superview)
        guard !self.isHidden, self.bounds.contains(local) else { return nil }
        
        if self.isRenaming, let inlineField = self.inlineTextField {
            if let subhit = super.hitTest(point), subhit.isDescendant(of: inlineField) {
                return subhit
            }
            return self
        }
        if !self.closeButton.isHidden, self.closeButton.frame.contains(local) {
            return self.closeButton
        }
        if !self.pinButton.isHidden, self.pinButton.frame.contains(local) {
            return self.pinButton
        }
        // Keep all clicks over the title label or save-status dot inside `self`
        // so double-clicks and drags never get hijacked by `titleLabel.mouseDownCanMoveWindow`.
        return self
    }
    
    
    private func setupViews() {
        
        self.wantsLayer = true
        self.layer?.cornerRadius = 6
        self.layer?.cornerCurve = .continuous
        
        self.activeAccentBar.cornerRadius = 1.0
        self.activeAccentBar.opacity = 0
        self.layer?.addSublayer(self.activeAccentBar)
        
        self.editedHaloLayer.opacity = 0
        self.layer?.addSublayer(self.editedHaloLayer)
        
        self.pinButton.contentTintColor = .controlAccentColor
        self.pinButton.target = self
        self.pinButton.action = #selector(pinClicked(_:))
        self.pinButton.toolTip = String(localized: "chrome.tab.pinnedHelp", defaultValue: "Pinned; click to unpin", table: "Chrome")
        self.addSubview(self.pinButton)
        
        self.titleLabel.font = .systemFont(ofSize: 12)
        self.titleLabel.cell?.truncatesLastVisibleLine = true
        self.titleLabel.lineBreakMode = .byTruncatingMiddle
        self.titleLabel.maximumNumberOfLines = 1
        self.titleLabel.isEditable = false
        self.titleLabel.isSelectable = false
        self.addSubview(self.titleLabel)
        
        // The dot itself is a standalone layer so it scales around its center; the view only reserves space.
        self.addSubview(self.editedDot)
        self.statusDotLayer.cornerRadius = 3
        self.layer?.addSublayer(self.statusDotLayer)
        
        self.closeButton.contentTintColor = .secondaryLabelColor
        self.closeButton.wantsLayer = true
        self.closeButton.layer?.cornerRadius = 8
        self.closeButton.target = self
        self.closeButton.action = #selector(closeClicked(_:))
        self.closeButton.toolTip = String(localized: "chrome.tab.close", defaultValue: "Close Tab", table: "Chrome")
        self.addSubview(self.closeButton)
    }
    
    
    func configure(tab: PaneTab, isSelected: Bool, isRenaming: Bool) {
        
        let wasSelected = self.isSelected
        let previousTitle = self.lastConfiguredTitle
        let previousEdited = self.lastConfiguredEdited
        
        self.tab = tab
        self.isSelected = isSelected
        self.isRenaming = isRenaming
        self.lastConfiguredTitle = tab.title
        self.lastConfiguredEdited = tab.isEdited
        
        self.titleLabel.stringValue = tab.title
        self.titleLabel.textColor = isSelected ? .labelColor : .secondaryLabelColor
        self.titleLabel.font = .systemFont(ofSize: 12, weight: isSelected ? .medium : .regular)
        let baseTip = tab.document.fileURL?.path(percentEncoded: false) ?? tab.title
        self.toolTip = tab.isEdited ? "\(baseTip) · 未保存 (按 ⌘S 保存)" : "\(baseTip) · 已保存"
        
        self.pinButton.isHidden = !tab.isPinned
        self.editedDot.isHidden = isRenaming
        self.statusDotLayer.backgroundColor = tab.isEdited
            ? NSColor.systemOrange.cgColor
            : NSColor.systemGreen.withAlphaComponent(0.72).cgColor
        self.editedDot.toolTip = tab.isEdited ? "未保存（按 ⌘S 保存）" : "已保存 (⌘S)"
        self.closeButton.isHidden = tab.isPinned || !tab.isClosable || isRenaming
        self.titleLabel.isHidden = isRenaming
        
        self.updateBackground(animated: wasSelected != isSelected)
        self.updateStatusDotAnimation(isEdited: tab.isEdited, previousEdited: previousEdited, isRenaming: isRenaming)
        
        if !AnimationConstants.isReducedMotionEnabled && !isRenaming {
            if !wasSelected && isSelected {
                self.animateTitleSelectionPop()
            } else if let previousTitle, previousTitle != tab.title {
                self.animateTitleRenameCelebrate()
            }
        }
        
        self.needsLayout = true
    }
    
    
    func preferredWidth(minWidth: CGFloat, maxWidth: CGFloat) -> CGFloat {
        
        if self.isRenaming {
            return max(136, min(maxWidth, 188))
        }
        
        // Measure using the medium-weight intrinsic label width so AppKit's cell padding
        // is accounted for accurately and 6-8 char titles never truncate with "…".
        let previousFont = self.titleLabel.font
        self.titleLabel.font = .systemFont(ofSize: 12, weight: .medium)
        let labelWidth = ceil(self.titleLabel.intrinsicContentSize.width)
        self.titleLabel.font = previousFont
        
        let isPinned = (self.tab?.isPinned == true)
        let showsClose = !isPinned && (self.tab?.isClosable == true)
        
        // Mirror exact insets reserved inside `layout()` plus 4pt breathing room.
        let leadingOverhead: CGFloat = 8 + (isPinned ? 14 : 0)
        let trailingOverhead: CGFloat = 4 + (showsClose ? 20 : 4) + 12
        let neededWidth = labelWidth + leadingOverhead + trailingOverhead + 4
        return min(maxWidth, max(minWidth, neededWidth))
    }
    
    
    override func layout() {
        
        super.layout()
        
        var x: CGFloat = 8
        let h = self.bounds.height
        
        if !self.pinButton.isHidden {
            self.pinButton.frame = NSRect(x: x - 2, y: ((h - 14) / 2).rounded(), width: 14, height: 14)
            x += 14
        }
        
        var trailingX = self.bounds.width - 4
        if !self.closeButton.isHidden {
            trailingX -= 16
            self.closeButton.frame = NSRect(x: trailingX, y: (h - 16) / 2, width: 16, height: 16)
            trailingX -= 4
        } else {
            trailingX -= 4
        }
        
        if !self.editedDot.isHidden {
            trailingX -= 6
            let dotFrame = NSRect(x: trailingX, y: (h - 6) / 2, width: 6, height: 6)
            self.editedDot.frame = dotFrame
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            self.editedHaloLayer.bounds = CGRect(x: 0, y: 0, width: 6, height: 6)
            self.editedHaloLayer.position = CGPoint(x: dotFrame.midX, y: dotFrame.midY)
            self.editedHaloLayer.cornerRadius = 3
            self.statusDotLayer.bounds = CGRect(x: 0, y: 0, width: 6, height: 6)
            self.statusDotLayer.position = CGPoint(x: dotFrame.midX, y: dotFrame.midY)
            CATransaction.commit()
            trailingX -= 6
        }
        
        // Active tab: a short accent hairline under the name
        let barWidth = max(16, min(32, self.bounds.width * 0.34))
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        self.statusDotLayer.isHidden = self.editedDot.isHidden
        self.editedHaloLayer.isHidden = self.editedDot.isHidden
        self.activeAccentBar.bounds = CGRect(x: 0, y: 0, width: barWidth, height: 1.5)
        self.activeAccentBar.position = CGPoint(x: self.bounds.width * 0.5, y: h - 1)
        CATransaction.commit()
        
        // vertically center the label on the exact same horizontal line as the status dot & close button
        let titleWidth = max(20, trailingX - x)
        let lineHeight = ceil(self.titleLabel.intrinsicContentSize.height)
        let titleFrame = NSRect(x: x, y: (h - lineHeight) / 2, width: titleWidth, height: lineHeight)
        self.titleLabel.frame = titleFrame
        let fieldHeight = min(h - 2, lineHeight + 4)
        let fieldX = max(3, x - 4)
        let fieldWidth = max(48, self.bounds.width - fieldX - 3)
        self.inlineTextField?.frame = NSRect(x: fieldX, y: (h - fieldHeight) / 2, width: fieldWidth, height: fieldHeight)
    }
    
    
    override func updateTrackingAreas() {
        
        super.updateTrackingAreas()
        if let existing = self.trackingArea {
            self.removeTrackingArea(existing)
        }
        let area = NSTrackingArea(rect: self.bounds, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self)
        self.addTrackingArea(area)
        self.trackingArea = area
    }
    
    
    override func mouseEntered(with event: NSEvent) {
        
        self.isHovered = true
        self.updateBackground(animated: true)
    }
    
    
    override func mouseExited(with event: NSEvent) {
        
        self.isHovered = false
        self.updateBackground(animated: true)
    }
    
    
    override func mouseDown(with event: NSEvent) {
        
        guard let tab = self.tab else { return }
        self.mouseDownLocation = self.convert(event.locationInWindow, from: nil)
        self.didStartDrag = false
        
        if event.clickCount == 2 {
            // Select only if needed, then defer inline rename past mouse tracking so selection doesn't fight the field editor.
            if self.stripView?.state?.selectedTab !== tab {
                self.stripView?.selectTab(tab)
            }
            DispatchQueue.main.async { [weak self] in
                self?.stripView?.beginInlineRename(for: tab)
            }
            return
        }
        
        self.stripView?.selectTab(tab)
    }
    
    
    override func mouseDragged(with event: NSEvent) {
        
        guard
            !self.isRenaming,
            !self.didStartDrag,
            let tab = self.tab,
            let start = self.mouseDownLocation
        else { return }
        
        let current = self.convert(event.locationInWindow, from: nil)
        if hypot(current.x - start.x, current.y - start.y) >= 5 {
            self.didStartDrag = true
            self.stripView?.startDrag(for: tab, from: self, event: event)
        }
    }
    
    
    override func menu(for event: NSEvent) -> NSMenu? {
        
        guard let tab = self.tab else { return nil }
        return self.stripView?.contextMenu(for: tab)
    }
    
    
    func enterRenameMode(initialTitle: String, delegate: any NSTextFieldDelegate) -> NSTextField {
        
        self.isRenaming = true
        self.titleLabel.isHidden = true
        self.editedDot.isHidden = true
        self.closeButton.isHidden = true
        self.inlineTextField?.removeFromSuperview()
        
        let field = NSTextField(string: initialTitle)
        field.font = .systemFont(ofSize: 12)
        field.textColor = .labelColor
        field.isEditable = true
        field.isSelectable = true
        field.usesSingleLineMode = true
        field.maximumNumberOfLines = 1
        field.lineBreakMode = .byTruncatingTail
        if let cell = field.cell as? NSTextFieldCell {
            cell.wraps = false
            cell.isScrollable = true
            cell.sendsActionOnEndEditing = false
        }
        field.isBezeled = false
        field.drawsBackground = true
        field.backgroundColor = .textBackgroundColor
        field.wantsLayer = true
        field.layer?.cornerRadius = 4
        field.layer?.borderWidth = 1.5
        field.layer?.borderColor = NSColor.controlAccentColor.cgColor
        field.focusRingType = .none
        field.delegate = delegate
        self.addSubview(field)
        self.inlineTextField = field
        self.needsLayout = true
        return field
    }
    
    
    func exitRenameMode() {
        
        self.isRenaming = false
        self.inlineTextField?.delegate = nil
        self.inlineTextField?.removeFromSuperview()
        self.inlineTextField = nil
        self.titleLabel.isHidden = false
        self.editedDot.isHidden = false
        if let tab = self.tab {
            self.closeButton.isHidden = tab.isPinned || !tab.isClosable
        }
        self.needsLayout = true
    }
    
    
    func dragSnapshotImage() -> NSImage {
        
        let size = NSSize(width: max(60, self.bounds.width), height: self.bounds.height)
        let image = NSImage(size: size, flipped: true) { rect in
            NSColor.windowBackgroundColor.withAlphaComponent(0.92).setFill()
            let path = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: 6, yRadius: 6)
            path.fill()
            NSColor.controlAccentColor.withAlphaComponent(0.75).setStroke()
            path.lineWidth = 1
            path.stroke()
            
            let title = (self.tab?.title ?? "") as NSString
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 12, weight: .medium),
                .foregroundColor: NSColor.labelColor,
            ]
            let lineHeight = ceil(NSFont.systemFont(ofSize: 12, weight: .medium).boundingRectForFont.height)
            let textRect = NSRect(x: 8, y: ((rect.height - lineHeight) / 2).rounded(), width: rect.width - 16, height: lineHeight)
            title.draw(with: textRect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], attributes: attrs)
            return true
        }
        return image
    }
    
    
    private func updateBackground(animated: Bool = false) {
        
        guard let layer = self.layer else { return }
        let duration: CFTimeInterval = (animated && !AnimationConstants.isReducedMotionEnabled) ? 0.14 : 0
        let ease = CAMediaTimingFunction(controlPoints: 0.2, 0, 0, 1)
        
        self.effectiveAppearance.performAsCurrentDrawingAppearance {
            let fill: NSColor = self.isSelected
                ? NSColor.labelColor.withAlphaComponent(0.09)
                : (self.isHovered ? NSColor.labelColor.withAlphaComponent(0.05) : .clear)
            let target = fill.cgColor
            
            // View-backed layers don't animate implicitly, so fade the fill explicitly.
            if duration > 0 {
                let fade = CABasicAnimation(keyPath: "backgroundColor")
                fade.fromValue = layer.presentation()?.backgroundColor ?? layer.backgroundColor
                fade.toValue = target
                fade.duration = duration
                fade.timingFunction = ease
                layer.add(fade, forKey: "backgroundFade")
            }
            layer.backgroundColor = target
            layer.borderColor = NSColor.separatorColor.cgColor
            layer.borderWidth = self.isSelected ? 1 / max(self.window?.backingScaleFactor ?? 2, 1) : 0
            
            CATransaction.begin()
            CATransaction.setAnimationDuration(duration)
            CATransaction.setAnimationTimingFunction(ease)
            self.activeAccentBar.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.8).cgColor
            self.activeAccentBar.opacity = self.isSelected ? 1 : 0
            CATransaction.commit()
        }
        self.titleLabel.textColor = (self.isSelected || self.isHovered) ? .labelColor : .secondaryLabelColor
    }
    
    
    /// The document name settles in from 2pt below when its tab becomes active.
    private func animateTitleSelectionPop() {
        
        guard let titleLayer = self.titleLabel.layer else { return }
        let settle = CABasicAnimation(keyPath: "transform.translation.y")
        settle.fromValue = 2
        settle.toValue = 0
        settle.duration = 0.2
        settle.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0, 0, 1)
        titleLayer.add(settle, forKey: "titleSelectSettle")
    }
    
    
    /// After a rename, the new name fades up once.
    private func animateTitleRenameCelebrate() {
        
        guard let titleLayer = self.titleLabel.layer else { return }
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0.2
        fade.toValue = 1
        fade.duration = 0.24
        fade.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0, 0, 1)
        titleLayer.add(fade, forKey: "titleRenameFade")
        
        let rise = CABasicAnimation(keyPath: "transform.translation.y")
        rise.fromValue = 3
        rise.toValue = 0
        rise.duration = 0.24
        rise.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0, 0, 1)
        titleLayer.add(rise, forKey: "titleRenameRise")
    }
    
    
    /// One-shot status feedback: the dot pops when a document becomes unsaved, and sends out a single green ring on save.
    private func updateStatusDotAnimation(isEdited: Bool, previousEdited: Bool?, isRenaming: Bool) {
        
        guard !isRenaming, !AnimationConstants.isReducedMotionEnabled,
              let previousEdited, previousEdited != isEdited
        else { return }
        
        let ease = CAMediaTimingFunction(controlPoints: 0.2, 0, 0, 1)
        
        let pop = CAKeyframeAnimation(keyPath: "transform.scale")
        pop.values = isEdited ? [0.4, 1.25, 1.0] : [0.6, 1.3, 1.0]
        pop.keyTimes = [0, 0.5, 1]
        pop.duration = 0.28
        pop.timingFunction = ease
        self.statusDotLayer.add(pop, forKey: "statusPop")
        
        guard !isEdited else { return }
        
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        self.editedHaloLayer.backgroundColor = nil
        self.editedHaloLayer.borderWidth = 1
        self.editedHaloLayer.borderColor = NSColor.systemGreen.withAlphaComponent(0.7).cgColor
        self.editedHaloLayer.opacity = 0
        CATransaction.commit()
        
        let grow = CABasicAnimation(keyPath: "transform.scale")
        grow.fromValue = 1
        grow.toValue = 2.6
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0.9
        fade.toValue = 0
        let ring = CAAnimationGroup()
        ring.animations = [grow, fade]
        ring.duration = 0.42
        ring.timingFunction = ease
        self.editedHaloLayer.add(ring, forKey: "savedRing")
    }
    
    
    @objc private func pinClicked(_ sender: Any?) {
        
        guard let tab = self.tab else { return }
        self.stripView?.togglePin(tab)
    }
    
    
    @objc private func closeClicked(_ sender: Any?) {
        
        guard let tab = self.tab else { return }
        self.stripView?.closeTab(tab)
    }
}
