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
    
    private let scrollView = NSScrollView()
    private let documentContainer = TabStripContainerView()
    private let newTabButton = CenteredIconButton(symbolName: "plus", pointSize: 10.5, weight: .semibold, accessibilityDescription: "New Tab")
    private let insertionIndicator = NSView()
    
    private var tabViews: [UUID: PaneTabItemView] = [:]
    private var orderedTabIDs: [UUID] = []
    private var tabFrames: [UUID: NSRect] = [:]
    
    // Inline rename state
    private var renamingTabID: UUID?
    private weak var renameField: NSTextField?
    private var isEndingRename = false
    private var suppressControlEndEditing = false
    
    // Drag state
    private var draggingTab: PaneTab?
    private var dragStartScreenPoint: NSPoint?
    private var dropInsertionIndex: Int?
    
    private static let tabHeight: CGFloat = 24
    private static let tabSpacing: CGFloat = 4
    private static let minTabWidth: CGFloat = 80
    private static let maxTabWidth: CGFloat = 200
    
    
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
            self.window?.makeFirstResponder(existingField)
            existingField.selectText(nil)
            return
        }
        
        self.commitInlineRenameIfNeeded(restoreEditorFocus: false)
        guard let itemView = self.tabViews[tab.id] else { return }
        
        self.renamingTabID = tab.id
        let field = itemView.enterRenameMode(initialTitle: tab.title, delegate: self)
        self.renameField = field
        
        self.layoutTabViews(animated: false)
        self.documentContainer.layoutSubtreeIfNeeded()
        itemView.layoutSubtreeIfNeeded()
        self.documentContainer.scrollToVisible(itemView.frame.insetBy(dx: -8, dy: 0))
        
        self.window?.makeFirstResponder(field)
        field.selectText(nil)
        
        // Re-assert first responder on the next runloop turn in case an asynchronous
        // editor selection focus restore runs during the same event cycle.
        let targetTabID = tab.id
        DispatchQueue.main.async { [weak self, weak field] in
            guard
                let self,
                let field,
                self.renamingTabID == targetTabID,
                self.renameField === field,
                let window = self.window,
                window.firstResponder !== field,
                window.firstResponder !== field.currentEditor()
            else { return }
            window.makeFirstResponder(field)
            field.selectText(nil)
        }
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
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
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
    
    private let iconView = NSImageView()
    
    override var mouseDownCanMoveWindow: Bool { false }
    
    
    init(symbolName: String, pointSize: CGFloat, weight: NSFont.Weight, accessibilityDescription: String) {
        
        super.init(frame: .zero)
        self.isBordered = false
        self.bezelStyle = .regularSquare
        self.focusRingType = .none
        self.title = ""
        self.image = nil
        
        self.iconView.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: accessibilityDescription)?
            .withSymbolConfiguration(.init(pointSize: pointSize, weight: weight))
        self.iconView.imageScaling = .scaleNone
        self.iconView.translatesAutoresizingMaskIntoConstraints = false
        self.addSubview(self.iconView)
        
        NSLayoutConstraint.activate([
            self.iconView.centerXAnchor.constraint(equalTo: self.centerXAnchor),
            self.iconView.centerYAnchor.constraint(equalTo: self.centerYAnchor),
        ])
    }
    
    
    required init?(coder: NSCoder) {
        
        fatalError("init(coder:) has not been implemented")
    }
    
    
    override var contentTintColor: NSColor? {
        didSet {
            self.iconView.contentTintColor = self.contentTintColor
        }
    }
    
    
    override func hitTest(_ point: NSPoint) -> NSView? {
        
        let local = self.convert(point, from: self.superview)
        return (!self.isHidden && self.bounds.contains(local)) ? self : nil
    }
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
    
    private let pinButton = CenteredIconButton(symbolName: "pin.fill", pointSize: 9, weight: .semibold, accessibilityDescription: "Pinned")
    private let titleLabel: NonDraggableLabel = {
        let label = NonDraggableLabel(labelWithString: "")
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return label
    }()
    private let editedDot = NSView()
    private let closeButton = CenteredIconButton(symbolName: "xmark", pointSize: 9, weight: .semibold, accessibilityDescription: "Close")
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
        
        self.editedDot.wantsLayer = true
        self.editedDot.layer?.cornerRadius = 3
        self.editedDot.layer?.backgroundColor = NSColor.systemGreen.withAlphaComponent(0.75).cgColor
        self.addSubview(self.editedDot)
        
        self.closeButton.contentTintColor = .secondaryLabelColor
        self.closeButton.wantsLayer = true
        self.closeButton.layer?.cornerRadius = 4
        self.closeButton.target = self
        self.closeButton.action = #selector(closeClicked(_:))
        self.closeButton.toolTip = String(localized: "chrome.tab.close", defaultValue: "Close Tab", table: "Chrome")
        self.addSubview(self.closeButton)
    }
    
    
    func configure(tab: PaneTab, isSelected: Bool, isRenaming: Bool) {
        
        self.tab = tab
        self.isSelected = isSelected
        self.isRenaming = isRenaming
        
        self.titleLabel.stringValue = tab.title
        self.titleLabel.textColor = isSelected ? .labelColor : .secondaryLabelColor
        self.titleLabel.font = .systemFont(ofSize: 12, weight: isSelected ? .medium : .regular)
        let baseTip = tab.document.fileURL?.path(percentEncoded: false) ?? tab.title
        self.toolTip = tab.isEdited ? "\(baseTip) · 未保存 (按 ⌘S 保存)" : "\(baseTip) · 已保存"
        
        self.pinButton.isHidden = !tab.isPinned
        self.editedDot.isHidden = isRenaming
        self.editedDot.layer?.backgroundColor = tab.isEdited
            ? NSColor.systemOrange.cgColor
            : NSColor.systemGreen.withAlphaComponent(0.6).cgColor
        self.editedDot.toolTip = tab.isEdited ? "未保存（按 ⌘S 保存）" : "已保存 (⌘S)"
        self.closeButton.isHidden = tab.isPinned || !tab.isClosable || isRenaming
        self.titleLabel.isHidden = isRenaming
        
        self.updateBackground()
        self.needsLayout = true
    }
    
    
    func preferredWidth(minWidth: CGFloat, maxWidth: CGFloat) -> CGFloat {
        
        if self.isRenaming {
            return max(136, min(maxWidth, 188))
        }
        let titleSize = (self.titleLabel.stringValue as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 12, weight: .medium)])
        var extra: CGFloat = 8 + 8 + 6 + 6  // leading/trailing padding + persistent save status dot + gap
        if self.tab?.isPinned == true { extra += 16 }
        if self.tab?.isPinned == false && self.tab?.isClosable == true { extra += 18 }
        return min(maxWidth, max(minWidth, ceil(titleSize.width) + extra))
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
            self.editedDot.frame = NSRect(x: trailingX, y: (h - 6) / 2, width: 6, height: 6)
            trailingX -= 6
        }
        
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
        self.updateBackground()
    }
    
    
    override func mouseExited(with event: NSEvent) {
        
        self.isHovered = false
        self.updateBackground()
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
        field.isEditable = true
        field.isSelectable = true
        field.usesSingleLineMode = true
        field.maximumNumberOfLines = 1
        field.lineBreakMode = .byTruncatingTail
        if let cell = field.cell as? NSTextFieldCell {
            cell.wraps = false
            cell.isScrollable = true
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
    
    
    private func updateBackground() {
        
        self.effectiveAppearance.performAsCurrentDrawingAppearance {
            if self.isSelected {
                self.layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.09).cgColor
                self.layer?.borderColor = NSColor.separatorColor.cgColor
                self.layer?.borderWidth = 1 / max(self.window?.backingScaleFactor ?? 2, 1)
            } else if self.isHovered {
                self.layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.05).cgColor
                self.layer?.borderWidth = 0
            } else {
                self.layer?.backgroundColor = NSColor.clear.cgColor
                self.layer?.borderWidth = 0
            }
        }
        self.titleLabel.textColor = (self.isSelected || self.isHovered) ? .labelColor : .secondaryLabelColor
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
