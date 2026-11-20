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

/// SwiftUI wrapper around the native AppKit `PaneTabStripNSView`, kept for previews and compatibility.
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
    
    var isRenaming: Bool { self.renamingTabID != nil }
    
    private let scrollView = NonDraggableScrollView()
    private let documentContainer = TabStripContainerView()
    private let newTabButton = CenteredIconButton(symbolName: "plus", pointSize: 10.5, weight: .semibold, accessibilityDescription: "New Tab", hoverStyle: .newTab)
    private let insertionIndicator = NSView()
    
    private var tabViews: [UUID: PaneTabItemView] = [:]
    private var orderedTabIDs: [UUID] = []
    private var baseTabFrames: [UUID: NSRect] = [:]
    private var tabFrames: [UUID: NSRect] = [:]
    
    // Inline rename state
    private var renamingTabID: UUID?
    private weak var renameField: NSTextField?
    private var renameOriginalTitle: String = ""
    private var renameBeganUptime: TimeInterval = 0
    private var isEndingRename = false
    private var suppressControlEndEditing = false
    private var didClickOutsideDuringRename = false
    private var renameOutsideClickMonitor: Any?
    
    // Drag state
    private var draggingTab: PaneTab?
    private var activeDragTabID: UUID?
    private var dragStartScreenPoint: NSPoint?
    private var dropInsertionIndex: Int?
    
    private static let tabHeight: CGFloat = 24
    private static let tabSpacing: CGFloat = 4
    private static let minTabWidth: CGFloat = 80
    private static let maxTabWidth: CGFloat = 240
    private static let externalDragGapWidth: CGFloat = 26
    
    
    override init(frame frameRect: NSRect) {
        
        super.init(frame: frameRect)
        self.setupViews()
    }
    
    
    required init?(coder: NSCoder) {
        
        fatalError("init(coder:) has not been implemented")
    }
    
    
    isolated deinit {
        
        if let monitor = self.renameOutsideClickMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }
    
    
    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }
    
    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: Self.tabHeight)
    }
    
    
    private func setupViews() {
        
        self.wantsLayer = true
        
        let clipView = NonDraggableClipView()
        clipView.automaticallyAdjustsContentInsets = false
        clipView.contentInsets = NSEdgeInsetsZero
        
        self.scrollView.contentView = clipView
        self.scrollView.automaticallyAdjustsContentInsets = false
        self.scrollView.contentInsets = NSEdgeInsetsZero
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
        self.insertionIndicator.layer?.cornerRadius = 1.5
        self.insertionIndicator.layer?.shadowColor = NSColor.controlAccentColor.cgColor
        self.insertionIndicator.layer?.shadowOpacity = 0.55
        self.insertionIndicator.layer?.shadowRadius = 4
        self.insertionIndicator.layer?.shadowOffset = .zero
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
    
    
    func reloadTabs(animated: Bool = false) {
        
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
            
            let isTabRenaming = (self.renamingTabID == tab.id)
            itemView.configure(
                tab: tab,
                isSelected: tab === state.selectedTab,
                isRenaming: isTabRenaming
            )
            itemView.setDragSourceActive(self.draggingTab?.id == tab.id, animated: false)
        }
        
        self.layoutTabViews(animated: animated)
    }
    
    
    private func layoutTabViews(animated: Bool) {
        
        guard let state = self.state else { return }
        
        // Compute un-parted resting frames first for stable drag hit-testing.
        var restingCursorX: CGFloat = 0
        var restingFrames: [UUID: NSRect] = [:]
        for tab in state.tabs {
            guard let itemView = self.tabViews[tab.id] else { continue }
            let width = itemView.preferredWidth(minWidth: Self.minTabWidth, maxWidth: Self.maxTabWidth)
            restingFrames[tab.id] = NSRect(x: restingCursorX, y: 1, width: width, height: Self.tabHeight - 2)
            restingCursorX += width + Self.tabSpacing
        }
        self.baseTabFrames = restingFrames
        
        // Compute preview frames (with magnetic parting or live local reorder during drag).
        var previewTabs = state.tabs
        var externalGapIndex: Int?
        
        if let gapIndex = self.dropInsertionIndex, let dragID = self.activeDragTabID {
            if let fromIdx = previewTabs.firstIndex(where: { $0.id == dragID }) {
                let moving = previewTabs.remove(at: fromIdx)
                var dest = max(0, min(gapIndex, previewTabs.count))
                if fromIdx < gapIndex {
                    dest = max(0, min(gapIndex - 1, previewTabs.count))
                }
                previewTabs.insert(moving, at: dest)
            } else {
                externalGapIndex = max(0, min(gapIndex, previewTabs.count))
            }
        }
        
        var cursorX: CGFloat = 0
        var visualFrames: [UUID: NSRect] = [:]
        for (idx, tab) in previewTabs.enumerated() {
            if externalGapIndex == idx {
                cursorX += Self.externalDragGapWidth
            }
            guard let itemView = self.tabViews[tab.id] else { continue }
            let width = restingFrames[tab.id]?.width ?? itemView.preferredWidth(minWidth: Self.minTabWidth, maxWidth: Self.maxTabWidth)
            visualFrames[tab.id] = NSRect(x: cursorX, y: 1, width: width, height: Self.tabHeight - 2)
            cursorX += width + Self.tabSpacing
        }
        if externalGapIndex == previewTabs.count {
            cursorX += Self.externalDragGapWidth
        }
        
        self.tabFrames = visualFrames
        let newTabFrame = NSRect(x: cursorX, y: 1, width: 22, height: Self.tabHeight - 2)
        let totalWidth = max(self.scrollView.bounds.width, cursorX + 28)
        self.documentContainer.frame = NSRect(x: 0, y: 0, width: totalWidth, height: Self.tabHeight)
        
        let shouldAnimate = animated && !AnimationConstants.isReducedMotionEnabled
        let applyFrames = {
            for (id, frame) in visualFrames {
                guard let view = self.tabViews[id] else { continue }
                if shouldAnimate {
                    view.animator().frame = frame
                } else {
                    view.frame = frame
                }
            }
            if shouldAnimate {
                self.newTabButton.animator().frame = newTabFrame
            } else {
                self.newTabButton.frame = newTabFrame
            }
        }
        
        if shouldAnimate {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.18
                ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 1.0, 0.36, 1.0)
                applyFrames()
            }
        } else {
            applyFrames()
        }
        
        if self.renamingTabID == nil,
           let selected = state.selectedTab,
           let selectedFrame = visualFrames[selected.id]
        {
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
    
    
    func selectTabForRename(_ tab: PaneTab) {
        
        guard self.renamingTabID != tab.id else { return }
        self.commitInlineRenameIfNeeded(restoreEditorFocus: false)
        self.state?.onSelectForRename(tab)
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
            self.focusRenameField(existingField, selectAll: true)
            return
        }
        
        self.commitInlineRenameIfNeeded(restoreEditorFocus: false)
        guard let itemView = self.tabViews[tab.id] else { return }
        
        self.renamingTabID = tab.id
        self.renameOriginalTitle = tab.title
        self.renameBeganUptime = ProcessInfo.processInfo.systemUptime
        self.didClickOutsideDuringRename = false
        
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
        self.focusRenameField(field, selectAll: true)
        self.installRenameOutsideClickMonitor(for: field)
        
        let targetTabID = tab.id
        let initialTitle = tab.title
        for delayMs in [0, 60] {
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(delayMs)) { [weak self, weak field] in
                guard
                    let self,
                    let field,
                    !self.didClickOutsideDuringRename,
                    self.renamingTabID == targetTabID,
                    self.renameField === field,
                    let window = self.window,
                    window.firstResponder !== field,
                    window.firstResponder !== field.currentEditor()
                else { return }
                let untouched = (field.currentEditor()?.string ?? field.stringValue) == initialTitle
                self.focusRenameField(field, selectAll: untouched)
            }
        }
    }
    
    
    private func focusRenameField(_ field: NSTextField, selectAll: Bool) {
        
        guard let window = self.window else { return }
        if window.firstResponder !== field && window.firstResponder !== field.currentEditor() {
            window.makeFirstResponderDiscardingMarkedText(field)
        }
        guard selectAll else { return }
        if let editor = field.currentEditor() as? NSTextView {
            editor.selectAll(nil)
        } else {
            field.selectText(nil)
        }
    }
    
    
    private func installRenameOutsideClickMonitor(for field: NSTextField) {
        
        self.removeRenameOutsideClickMonitor()
        self.renameOutsideClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self, weak field] event in
            guard
                let self,
                let field,
                self.renamingTabID != nil,
                event.window === self.window
            else { return event }
            
            let pointInField = field.convert(event.locationInWindow, from: nil)
            if !field.bounds.contains(pointInField) {
                self.didClickOutsideDuringRename = true
                self.commitInlineRenameIfNeeded(restoreEditorFocus: false)
            }
            return event
        }
    }
    
    
    private func removeRenameOutsideClickMonitor() {
        
        if let monitor = self.renameOutsideClickMonitor {
            NSEvent.removeMonitor(monitor)
            self.renameOutsideClickMonitor = nil
        }
    }
    
    
    @objc private func commitRenameFromFieldAction(_ sender: Any?) {
        
        self.commitInlineRenameIfNeeded(restoreEditorFocus: true)
    }
    
    
    private func commitInlineRenameIfNeeded(restoreEditorFocus: Bool = false) {
        
        guard !self.isEndingRename else { return }
        self.isEndingRename = true
        defer { self.isEndingRename = false }
        
        self.removeRenameOutsideClickMonitor()
        
        guard
            let tabID = self.renamingTabID,
            let field = self.renameField,
            let tab = self.state?.tabs.first(where: { $0.id == tabID })
        else {
            self.cancelInlineRename(restoreEditorFocus: restoreEditorFocus)
            return
        }
        
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
        
        self.removeRenameOutsideClickMonitor()
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
        
        let movement = (obj.userInfo?["NSTextMovement"] as? Int).flatMap(NSTextMovement.init(rawValue:))
        if movement == .cancel {
            self.cancelInlineRename(restoreEditorFocus: true)
            return
        }
        if movement == .return || movement == .tab || movement == .backtab {
            self.commitInlineRenameIfNeeded(restoreEditorFocus: true)
            return
        }
        
        if !self.didClickOutsideDuringRename,
           ProcessInfo.processInfo.systemUptime - self.renameBeganUptime < 0.45,
           let targetTabID = self.renamingTabID,
           let field = self.renameField
        {
            let originalTitle = self.renameOriginalTitle
            DispatchQueue.main.async { [weak self, weak field] in
                guard
                    let self,
                    let field,
                    !self.didClickOutsideDuringRename,
                    self.renamingTabID == targetTabID,
                    self.renameField === field
                else { return }
                let untouched = (field.currentEditor()?.string ?? field.stringValue) == originalTitle
                self.focusRenameField(field, selectAll: untouched)
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
        self.activeDragTabID = tab.id
        self.dragStartScreenPoint = NSEvent.mouseLocation
        itemView.setDragSourceActive(true, animated: true)
        
        let pboardItem = NSPasteboardItem()
        pboardItem.setString(tab.id.uuidString, forType: PaneTab.dragPasteboardType)
        pboardItem.setString(tab.dragPayload, forType: .string)
        
        let draggingItem = NSDraggingItem(pasteboardWriter: pboardItem)
        let shadowPad: CGFloat = 6
        let previewImage = itemView.dragSnapshotImage(shadowPadding: shadowPad)
        let itemFrameInSelf = self.convert(itemView.bounds, from: itemView).insetBy(dx: -shadowPad, dy: -shadowPad)
        draggingItem.setDraggingFrame(itemFrameInSelf, contents: previewImage)
        
        let session = self.beginDraggingSession(with: [draggingItem], event: event, source: self)
        session.animatesToStartingPositionsOnCancelOrFail = false
    }
    
    
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        
        context == .withinApplication ? [.move] : []
    }
    
    
    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        
        let detachedTab = self.draggingTab
        self.draggingTab = nil
        self.activeDragTabID = nil
        self.dragStartScreenPoint = nil
        self.dropInsertionIndex = nil
        self.hideInsertionIndicator()
        for view in self.tabViews.values {
            view.setDragSourceActive(false, animated: true)
        }
        self.layoutTabViews(animated: true)
        
        guard operation == [], let tab = detachedTab else { return }
        
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
        
        guard let draggedID = self.extractTabID(from: sender.draggingPasteboard) else { return [] }
        self.activeDragTabID = draggedID
        self.updateInsertionIndicator(for: sender)
        return .move
    }
    
    
    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        
        guard let draggedID = self.extractTabID(from: sender.draggingPasteboard) else { return [] }
        self.activeDragTabID = draggedID
        self.updateInsertionIndicator(for: sender)
        return .move
    }
    
    
    override func draggingExited(_ sender: (any NSDraggingInfo)?) {
        
        self.dropInsertionIndex = nil
        self.hideInsertionIndicator()
        if self.draggingTab == nil {
            self.activeDragTabID = nil
        }
        self.layoutTabViews(animated: true)
    }
    
    
    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        
        let targetIndex = self.insertionIndex(for: sender)
        self.dropInsertionIndex = nil
        self.activeDragTabID = nil
        self.hideInsertionIndicator()
        for view in self.tabViews.values {
            view.setDragSourceActive(false, animated: true)
        }
        
        guard let draggedID = self.extractTabID(from: sender.draggingPasteboard),
              let state = self.state
        else {
            self.layoutTabViews(animated: true)
            return false
        }
        
        let accepted: Bool
        if let localTab = state.tabs.first(where: { $0.id == draggedID }) {
            state.onMoveToIndex(localTab, targetIndex)
            accepted = true
        } else {
            accepted = state.onDropTab(draggedID, targetIndex)
        }
        
        self.reloadTabs(animated: true)
        if accepted {
            let landedID = state.tabs.first(where: { $0.id == draggedID })?.id ?? state.selectedTab?.id
            if let landedID {
                self.tabViews[landedID]?.animateDropArrival()
            }
        }
        return accepted
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
            let frame = self.baseTabFrames[tab.id] ?? self.tabFrames[tab.id]
            if let frame, pointInContainer.x < frame.midX {
                return index
            }
        }
        return state.tabs.count
    }
    
    
    private func updateInsertionIndicator(for draggingInfo: any NSDraggingInfo) {
        
        guard let state = self.state else { return }
        let index = self.insertionIndex(for: draggingInfo)
        let indexChanged = (self.dropInsertionIndex != index)
        self.dropInsertionIndex = index
        
        if indexChanged {
            self.layoutTabViews(animated: true)
        }
        
        let isLocalDrag = self.activeDragTabID.map { id in state.tabs.contains(where: { $0.id == id }) } ?? false
        if isLocalDrag {
            // Local tabs glide smoothly into their target slot directly; no vertical bar needed.
            self.insertionIndicator.isHidden = true
            return
        }
        
        let indicatorX: CGFloat
        if index == 0 {
            indicatorX = (Self.externalDragGapWidth - 3) * 0.5
        } else if index >= state.tabs.count, let lastTab = state.tabs.last, let lastFrame = self.tabFrames[lastTab.id] {
            indicatorX = lastFrame.maxX + Self.tabSpacing + (Self.externalDragGapWidth - 3) * 0.5
        } else if let targetTab = state.tabs[safe: index], let targetFrame = self.tabFrames[targetTab.id] {
            indicatorX = targetFrame.minX - (Self.externalDragGapWidth * 0.5) - 1.5
        } else {
            indicatorX = 2
        }
        
        let targetFrame = NSRect(x: max(1, indicatorX), y: 2, width: 3, height: Self.tabHeight - 4)
        let wasHidden = self.insertionIndicator.isHidden
        self.insertionIndicator.isHidden = false
        if wasHidden || AnimationConstants.isReducedMotionEnabled {
            self.insertionIndicator.frame = targetFrame
        } else {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.14
                ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 1.0, 0.36, 1.0)
                self.insertionIndicator.animator().frame = targetFrame
            }
        }
    }
    
    
    private func hideInsertionIndicator() {
        
        self.insertionIndicator.isHidden = true
    }
}


// MARK: - Container & Individual Tab Item View

private final class NonDraggableLabel: NSTextField {
    
    override var mouseDownCanMoveWindow: Bool { false }
}


private final class TabRenameTextField: NSTextField {
    
    override var mouseDownCanMoveWindow: Bool { false }
    override var acceptsFirstResponder: Bool { true }
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
    private var isDragSourceActive = false
    private var lastConfiguredTitle: String?
    private var lastConfiguredEdited: Bool?
    private var activeBreathingKey: String?
    
    private let activeAccentBar = CALayer()
    private let breathingAuraLayer = CALayer()
    private let editedHaloLayer = CALayer()
    private let statusDotLayer = CALayer()
    private let pinButton = CenteredIconButton(symbolName: "pin.fill", pointSize: 8.5, weight: .semibold, accessibilityDescription: "Pinned", hoverStyle: .pin)
    private let titleLabel: NonDraggableLabel = {
        let label = NonDraggableLabel(labelWithString: "")
        label.wantsLayer = true
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return label
    }()
    private let editedDot = NSView()
    private let closeButton = CenteredIconButton(symbolName: "xmark", pointSize: 7.5, weight: .medium, accessibilityDescription: "Close", hoverStyle: .close)
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
        return self
    }
    
    
    override func viewDidMoveToWindow() {
        
        super.viewDidMoveToWindow()
        self.activeBreathingKey = nil
        if let tab = self.tab {
            self.updateBreathingAnimation(isEdited: tab.isEdited, isSelected: self.isSelected, isRenaming: self.isRenaming)
        }
    }
    
    
    private func setupViews() {
        
        self.wantsLayer = true
        self.layer?.cornerRadius = 6
        self.layer?.cornerCurve = .continuous
        
        self.activeAccentBar.cornerRadius = 1.0
        self.activeAccentBar.opacity = 0
        self.layer?.addSublayer(self.activeAccentBar)
        
        self.breathingAuraLayer.cornerRadius = 6
        self.breathingAuraLayer.opacity = 0
        self.layer?.addSublayer(self.breathingAuraLayer)
        
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
        
        self.addSubview(self.editedDot)
        self.statusDotLayer.cornerRadius = 3.25
        self.layer?.addSublayer(self.statusDotLayer)
        
        self.closeButton.contentTintColor = .secondaryLabelColor
        self.closeButton.wantsLayer = true
        self.closeButton.layer?.cornerRadius = 7
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
        self.effectiveAppearance.performAsCurrentDrawingAppearance {
            self.statusDotLayer.backgroundColor = tab.isEdited
                ? NSColor.systemOrange.cgColor
                : NSColor.systemGreen.withAlphaComponent(0.86).cgColor
            self.breathingAuraLayer.backgroundColor = tab.isEdited
                ? NSColor.systemOrange.cgColor
                : NSColor.systemGreen.cgColor
        }
        self.editedDot.toolTip = tab.isEdited ? "未保存（按 ⌘S 保存）" : "已保存 (⌘S)"
        self.closeButton.isHidden = tab.isPinned || !tab.isClosable || isRenaming
        self.titleLabel.isHidden = isRenaming
        
        self.updateBackground(animated: wasSelected != isSelected)
        self.updateStatusDotAnimation(isEdited: tab.isEdited, previousEdited: previousEdited, isRenaming: isRenaming)
        self.updateBreathingAnimation(isEdited: tab.isEdited, isSelected: isSelected, isRenaming: isRenaming)
        
        if !AnimationConstants.isReducedMotionEnabled && !isRenaming {
            if !wasSelected && isSelected {
                self.animateTitleSelectionPop()
            } else if let previousTitle, previousTitle != tab.title {
                self.animateTitleRenameCelebrate()
            }
        }
        
        self.needsLayout = true
    }
    
    
    func setDragSourceActive(_ active: Bool, animated: Bool) {
        
        guard self.isDragSourceActive != active else { return }
        self.isDragSourceActive = active
        
        let apply = {
            self.alphaValue = active ? 0.28 : 1.0
        }
        if animated && !AnimationConstants.isReducedMotionEnabled {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.14
                self.animator().alphaValue = active ? 0.28 : 1.0
            }
        } else {
            apply()
        }
    }
    
    
    func animateDropArrival() {
        
        guard !AnimationConstants.isReducedMotionEnabled, let layer = self.layer else { return }
        let pop = CAKeyframeAnimation(keyPath: "transform.scale")
        pop.values = [0.95, 1.03, 1.0]
        pop.keyTimes = [0, 0.55, 1]
        pop.duration = 0.24
        pop.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 1.0, 0.36, 1.0)
        layer.add(pop, forKey: "dropArrival")
    }
    
    
    func preferredWidth(minWidth: CGFloat, maxWidth: CGFloat) -> CGFloat {
        
        if self.isRenaming {
            return max(136, min(maxWidth, 188))
        }
        
        let previousFont = self.titleLabel.font
        self.titleLabel.font = .systemFont(ofSize: 12, weight: .medium)
        let labelWidth = ceil(self.titleLabel.intrinsicContentSize.width)
        self.titleLabel.font = previousFont
        
        let isPinned = (self.tab?.isPinned == true)
        let showsClose = !isPinned && (self.tab?.isClosable == true)
        
        // Leading (8 + optional pin) + trailing (14 status slot + 4 gap + optional 14 close slot + 10 breath)
        let leadingOverhead: CGFloat = 8 + (isPinned ? 14 : 0)
        let trailingOverhead: CGFloat = 14 + (showsClose ? 24 : 10)
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
        
        // Unified 14x14 optical slots for status jewel & close icon along the exact midline.
        var trailingX = self.bounds.width - 5
        if !self.closeButton.isHidden {
            trailingX -= 14
            self.closeButton.frame = NSRect(x: trailingX, y: ((h - 14) / 2).rounded(), width: 14, height: 14)
            trailingX -= 4
        } else {
            trailingX -= 2
        }
        
        if !self.editedDot.isHidden {
            trailingX -= 14
            let slotFrame = NSRect(x: trailingX, y: ((h - 14) / 2).rounded(), width: 14, height: 14)
            self.editedDot.frame = slotFrame
            let center = CGPoint(x: slotFrame.midX, y: slotFrame.midY)
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            self.breathingAuraLayer.bounds = CGRect(x: 0, y: 0, width: 12, height: 12)
            self.breathingAuraLayer.position = center
            self.breathingAuraLayer.cornerRadius = 6
            self.editedHaloLayer.bounds = CGRect(x: 0, y: 0, width: 6.5, height: 6.5)
            self.editedHaloLayer.position = center
            self.editedHaloLayer.cornerRadius = 3.25
            self.statusDotLayer.bounds = CGRect(x: 0, y: 0, width: 6.5, height: 6.5)
            self.statusDotLayer.position = center
            self.statusDotLayer.cornerRadius = 3.25
            CATransaction.commit()
            trailingX -= 4
        }
        
        let barWidth = max(16, min(32, self.bounds.width * 0.34))
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        self.statusDotLayer.isHidden = self.editedDot.isHidden
        self.breathingAuraLayer.isHidden = self.editedDot.isHidden
        self.editedHaloLayer.isHidden = self.editedDot.isHidden
        self.activeAccentBar.bounds = CGRect(x: 0, y: 0, width: barWidth, height: 1.5)
        self.activeAccentBar.position = CGPoint(x: self.bounds.width * 0.5, y: h - 1)
        CATransaction.commit()
        
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
        
        guard !self.isRenaming, let tab = self.tab else { return }
        self.mouseDownLocation = self.convert(event.locationInWindow, from: nil)
        self.didStartDrag = false
        
        if event.clickCount == 2 {
            if self.stripView?.state?.selectedTab !== tab {
                self.stripView?.selectTabForRename(tab)
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
        self.updateBreathingAnimation(isEdited: self.tab?.isEdited == true, isSelected: self.isSelected, isRenaming: true)
        self.inlineTextField?.removeFromSuperview()
        
        let field = TabRenameTextField(string: initialTitle)
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
            self.updateBreathingAnimation(isEdited: tab.isEdited, isSelected: self.isSelected, isRenaming: false)
        }
        self.needsLayout = true
    }
    
    
    func dragSnapshotImage(shadowPadding: CGFloat = 6) -> NSImage {
        
        let cardSize = NSSize(width: max(64, self.bounds.width), height: self.bounds.height)
        let imageSize = NSSize(width: cardSize.width + shadowPadding * 2, height: cardSize.height + shadowPadding * 2)
        let isEdited = (self.tab?.isEdited == true)
        let title = (self.tab?.title ?? "") as NSString
        
        return NSImage(size: imageSize, flipped: true) { _ in
            let cardRect = NSRect(origin: NSPoint(x: shadowPadding, y: shadowPadding), size: cardSize)
            let path = NSBezierPath(roundedRect: cardRect.insetBy(dx: 0.5, dy: 0.5), xRadius: 7, yRadius: 7)
            
            NSGraphicsContext.saveGraphicsState()
            let shadow = NSShadow()
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.22)
            shadow.shadowBlurRadius = 5
            shadow.shadowOffset = NSSize(width: 0, height: -2)
            shadow.set()
            NSColor.windowBackgroundColor.withAlphaComponent(0.95).setFill()
            path.fill()
            NSGraphicsContext.restoreGraphicsState()
            
            NSColor.controlAccentColor.withAlphaComponent(0.75).setStroke()
            path.lineWidth = 1.1
            path.stroke()
            
            let dotRect = NSRect(x: cardRect.maxX - 15, y: cardRect.midY - 3, width: 6, height: 6)
            (isEdited ? NSColor.systemOrange : NSColor.systemGreen.withAlphaComponent(0.85)).setFill()
            NSBezierPath(ovalIn: dotRect).fill()
            
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 12, weight: .medium),
                .foregroundColor: NSColor.labelColor,
            ]
            let lineHeight = ceil(NSFont.systemFont(ofSize: 12, weight: .medium).boundingRectForFont.height)
            let textRect = NSRect(
                x: cardRect.minX + 9,
                y: cardRect.minY + ((cardRect.height - lineHeight) / 2).rounded(),
                width: max(20, cardRect.width - 30),
                height: lineHeight
            )
            title.draw(with: textRect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], attributes: attrs)
            return true
        }
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
    
    
    private func animateTitleSelectionPop() {
        
        guard let titleLayer = self.titleLabel.layer else { return }
        let settle = CABasicAnimation(keyPath: "transform.translation.y")
        settle.fromValue = 2
        settle.toValue = 0
        settle.duration = 0.2
        settle.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0, 0, 1)
        titleLayer.add(settle, forKey: "titleSelectSettle")
    }
    
    
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
    
    
    /// Gentle breathing aura & core pulse for the status jewel: warm amber while unsaved, calm zen jade when saved.
    private func updateBreathingAnimation(isEdited: Bool, isSelected: Bool, isRenaming: Bool) {
        
        guard !isRenaming, self.window != nil, !AnimationConstants.isReducedMotionEnabled else {
            self.activeBreathingKey = nil
            self.statusDotLayer.removeAnimation(forKey: "breatheCore")
            self.breathingAuraLayer.removeAnimation(forKey: "breatheAura")
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            self.statusDotLayer.opacity = isEdited ? 0.95 : (isSelected ? 0.84 : 0.65)
            self.breathingAuraLayer.opacity = isEdited ? 0.16 : 0.06
            CATransaction.commit()
            return
        }
        
        let stateKey = "\(isEdited)-\(isSelected)"
        guard self.activeBreathingKey != stateKey else { return }
        self.activeBreathingKey = stateKey
        
        self.statusDotLayer.removeAnimation(forKey: "breatheCore")
        self.breathingAuraLayer.removeAnimation(forKey: "breatheAura")
        
        let duration: CFTimeInterval = isEdited ? 2.8 : 4.2
        let timing = CAMediaTimingFunction(name: .easeInEaseOut)
        
        let coreScale = CABasicAnimation(keyPath: "transform.scale")
        coreScale.fromValue = isEdited ? 0.90 : 0.96
        coreScale.toValue = isEdited ? 1.08 : 1.04
        
        let coreAlpha = CABasicAnimation(keyPath: "opacity")
        coreAlpha.fromValue = isEdited ? 0.80 : (isSelected ? 0.64 : 0.48)
        coreAlpha.toValue = isEdited ? 1.00 : (isSelected ? 0.88 : 0.70)
        
        let coreGroup = CAAnimationGroup()
        coreGroup.animations = [coreScale, coreAlpha]
        coreGroup.duration = duration
        coreGroup.autoreverses = true
        coreGroup.repeatCount = .infinity
        coreGroup.timingFunction = timing
        self.statusDotLayer.add(coreGroup, forKey: "breatheCore")
        
        let auraScale = CABasicAnimation(keyPath: "transform.scale")
        auraScale.fromValue = isEdited ? 0.85 : 0.90
        auraScale.toValue = isEdited ? 1.45 : 1.32
        
        let auraAlpha = CABasicAnimation(keyPath: "opacity")
        auraAlpha.fromValue = isEdited ? 0.04 : 0.02
        auraAlpha.toValue = isEdited ? (isSelected ? 0.34 : 0.22) : (isSelected ? 0.18 : 0.10)
        
        let auraGroup = CAAnimationGroup()
        auraGroup.animations = [auraScale, auraAlpha]
        auraGroup.duration = duration
        auraGroup.autoreverses = true
        auraGroup.repeatCount = .infinity
        auraGroup.timingFunction = timing
        self.breathingAuraLayer.add(auraGroup, forKey: "breatheAura")
    }
    
    
    /// One-shot status feedback: the dot pops when a document becomes unsaved, and sends out a single emerald ring on save.
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
        self.editedHaloLayer.borderWidth = 1.1
        self.editedHaloLayer.borderColor = NSColor.systemGreen.withAlphaComponent(0.75).cgColor
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
