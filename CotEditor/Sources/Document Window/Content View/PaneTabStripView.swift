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
        return view
    }
    
    
    func updateNSView(_ nsView: PaneTabStripNSView, context: Context) {
        
        // Observe observable properties so SwiftUI re-renders whenever tabs, selection, or revision change
        _ = self.state.tabs.map { ($0.id, $0.title, $0.isPinned, $0.isEdited, $0.isClosable) }
        _ = self.state.selectedTab?.id
        _ = self.state.refreshRevision
        
        nsView.state = self.state
        nsView.reloadTabs()
    }
}


// MARK: - Native AppKit Tab Strip

@MainActor final class PaneTabStripNSView: NSView, NSDraggingSource, NSTextFieldDelegate {
    
    var state: PaneTabState?
    
    private let scrollView = NSScrollView()
    private let documentContainer = TabStripContainerView()
    private let newTabButton = NSButton()
    private let insertionIndicator = NSView()
    
    private var tabViews: [UUID: PaneTabItemView] = [:]
    private var orderedTabIDs: [UUID] = []
    private var tabFrames: [UUID: NSRect] = [:]
    
    // Inline rename state
    private var renamingTabID: UUID?
    private weak var renameField: NSTextField?
    
    // Drag state
    private var draggingTab: PaneTab?
    private var dragStartScreenPoint: NSPoint?
    private var dropInsertionIndex: Int?
    
    private static let tabHeight: CGFloat = 20
    private static let tabSpacing: CGFloat = 3
    private static let minTabWidth: CGFloat = 68
    private static let maxTabWidth: CGFloat = 176
    
    
    override init(frame frameRect: NSRect) {
        
        super.init(frame: frameRect)
        self.setupViews()
    }
    
    
    required init?(coder: NSCoder) {
        
        fatalError("init(coder:) has not been implemented")
    }
    
    
    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { true }
    
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
        
        self.newTabButton.bezelStyle = .inline
        self.newTabButton.isBordered = false
        self.newTabButton.image = NSImage(systemSymbolName: "plus", accessibilityDescription: "New Tab")?
            .withSymbolConfiguration(.init(pointSize: 10.5, weight: .medium))
        self.newTabButton.contentTintColor = .secondaryLabelColor
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
        
        var cursorX: CGFloat = 2
        var newFrames: [UUID: NSRect] = [:]
        
        for tab in state.tabs {
            guard let itemView = self.tabViews[tab.id] else { continue }
            let width = itemView.preferredWidth(minWidth: Self.minTabWidth, maxWidth: Self.maxTabWidth)
            let frame = NSRect(x: cursorX, y: 1, width: width, height: Self.tabHeight - 2)
            newFrames[tab.id] = frame
            cursorX += width + Self.tabSpacing
        }
        
        self.tabFrames = newFrames
        self.newTabButton.frame = NSRect(x: cursorX + 1, y: 1, width: 20, height: Self.tabHeight - 2)
        let totalWidth = max(self.scrollView.bounds.width, cursorX + 26)
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
        
        self.commitInlineRenameIfNeeded()
        self.state?.onSelect(tab)
    }
    
    
    func closeTab(_ tab: PaneTab) {
        
        self.commitInlineRenameIfNeeded()
        self.state?.onClose(tab)
    }
    
    
    func togglePin(_ tab: PaneTab) {
        
        self.commitInlineRenameIfNeeded()
        self.state?.onTogglePin(tab)
    }
    
    
    func beginInlineRename(for tab: PaneTab) {
        
        self.commitInlineRenameIfNeeded()
        guard let itemView = self.tabViews[tab.id] else { return }
        
        self.renamingTabID = tab.id
        let field = itemView.enterRenameMode(initialTitle: tab.title, delegate: self)
        self.renameField = field
        self.layoutTabViews(animated: false)
        
        self.window?.makeFirstResponder(field)
        field.selectText(nil)
    }
    
    
    private func commitInlineRenameIfNeeded() {
        
        guard
            let tabID = self.renamingTabID,
            let field = self.renameField,
            let tab = self.state?.tabs.first(where: { $0.id == tabID })
        else {
            self.cancelInlineRename()
            return
        }
        
        let proposed = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        self.renamingTabID = nil
        self.renameField = nil
        self.tabViews[tabID]?.exitRenameMode()
        self.layoutTabViews(animated: false)
        
        if !proposed.isEmpty, proposed != tab.title {
            self.state?.onRename(tab, proposed)
        }
    }
    
    
    private func cancelInlineRename() {
        
        if let tabID = self.renamingTabID {
            self.tabViews[tabID]?.exitRenameMode()
        }
        self.renamingTabID = nil
        self.renameField = nil
        self.layoutTabViews(animated: false)
    }
    
    
    // MARK: NSTextFieldDelegate
    
    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            self.commitInlineRenameIfNeeded()
            return true
        }
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            self.cancelInlineRename()
            return true
        }
        return false
    }
    
    
    func controlTextDidEndEditing(_ obj: Notification) {
        
        self.commitInlineRenameIfNeeded()
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
        self.beginInlineRename(for: tab)
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

private final class TabStripContainerView: NSView {
    
    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { true }
}


@MainActor final class PaneTabItemView: NSView {
    
    weak var stripView: PaneTabStripNSView?
    
    private var tab: PaneTab?
    private var isSelected = false
    private var isHovered = false
    private var isRenaming = false
    
    private let pinButton = NSButton()
    private let titleLabel = NSTextField(labelWithString: "")
    private let editedDot = NSView()
    private let closeButton = NSButton()
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
    
    
    private func setupViews() {
        
        self.wantsLayer = true
        self.layer?.cornerRadius = 4
        
        self.pinButton.bezelStyle = .inline
        self.pinButton.isBordered = false
        self.pinButton.image = NSImage(systemSymbolName: "pin.fill", accessibilityDescription: "Pinned")?
            .withSymbolConfiguration(.init(pointSize: 8.5, weight: .semibold))
        self.pinButton.contentTintColor = .controlAccentColor
        self.pinButton.target = self
        self.pinButton.action = #selector(pinClicked(_:))
        self.pinButton.toolTip = String(localized: "chrome.tab.pinnedHelp", defaultValue: "Pinned; click to unpin", table: "Chrome")
        self.addSubview(self.pinButton)
        
        self.titleLabel.font = .systemFont(ofSize: 11)
        self.titleLabel.lineBreakMode = .byTruncatingMiddle
        self.titleLabel.maximumNumberOfLines = 1
        self.titleLabel.isEditable = false
        self.titleLabel.isSelectable = false
        self.addSubview(self.titleLabel)
        
        self.editedDot.wantsLayer = true
        self.editedDot.layer?.cornerRadius = 2
        self.editedDot.layer?.backgroundColor = NSColor.tertiaryLabelColor.cgColor
        self.addSubview(self.editedDot)
        
        self.closeButton.bezelStyle = .inline
        self.closeButton.isBordered = false
        self.closeButton.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Close")?
            .withSymbolConfiguration(.init(pointSize: 8, weight: .semibold))
        self.closeButton.contentTintColor = .secondaryLabelColor
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
        self.toolTip = tab.document.fileURL?.path(percentEncoded: false) ?? tab.title
        
        self.pinButton.isHidden = !tab.isPinned
        self.editedDot.isHidden = !tab.isEdited || tab.isPinned
        self.closeButton.isHidden = tab.isPinned || !tab.isClosable || isRenaming
        self.titleLabel.isHidden = isRenaming
        
        self.updateBackground()
        self.needsLayout = true
    }
    
    
    func preferredWidth(minWidth: CGFloat, maxWidth: CGFloat) -> CGFloat {
        
        if self.isRenaming {
            return max(120, min(maxWidth, 160))
        }
        let titleSize = (self.titleLabel.stringValue as NSString).size(withAttributes: [.font: self.titleLabel.font ?? .systemFont(ofSize: 11)])
        var extra: CGFloat = 12  // horizontal padding
        if self.tab?.isPinned == true { extra += 14 }
        if self.tab?.isEdited == true && self.tab?.isPinned == false { extra += 7 }
        if self.tab?.isPinned == false && self.tab?.isClosable == true { extra += 16 }
        return min(maxWidth, max(minWidth, ceil(titleSize.width) + extra))
    }
    
    
    override func layout() {
        
        super.layout()
        
        var x: CGFloat = 5
        let h = self.bounds.height
        
        if !self.pinButton.isHidden {
            self.pinButton.frame = NSRect(x: x, y: (h - 12) / 2, width: 12, height: 12)
            x += 14
        }
        
        var trailingX = self.bounds.width - 4
        if !self.closeButton.isHidden {
            trailingX -= 14
            self.closeButton.frame = NSRect(x: trailingX, y: (h - 14) / 2, width: 14, height: 14)
            trailingX -= 2
        }
        
        if !self.editedDot.isHidden {
            trailingX -= 6
            self.editedDot.frame = NSRect(x: trailingX, y: (h - 4) / 2, width: 4, height: 4)
            trailingX -= 3
        }
        
        let titleWidth = max(20, trailingX - x)
        let titleFrame = NSRect(x: x, y: 2, width: titleWidth, height: h - 4)
        self.titleLabel.frame = titleFrame
        self.inlineTextField?.frame = NSRect(x: x - 1, y: 1, width: max(70, self.bounds.width - x - 3), height: h - 2)
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
            self.stripView?.selectTab(tab)
            self.stripView?.beginInlineRename(for: tab)
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
        self.closeButton.isHidden = true
        
        let field = NSTextField(string: initialTitle)
        field.font = .systemFont(ofSize: 11)
        field.isBezeled = false
        field.drawsBackground = true
        field.backgroundColor = .textBackgroundColor
        field.wantsLayer = true
        field.layer?.cornerRadius = 3
        field.layer?.borderWidth = 1
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
        self.inlineTextField?.removeFromSuperview()
        self.inlineTextField = nil
        self.titleLabel.isHidden = false
        if let tab = self.tab {
            self.closeButton.isHidden = tab.isPinned || !tab.isClosable
        }
        self.needsLayout = true
    }
    
    
    func dragSnapshotImage() -> NSImage {
        
        let size = NSSize(width: max(60, self.bounds.width), height: self.bounds.height)
        let image = NSImage(size: size, flipped: true) { rect in
            NSColor.windowBackgroundColor.withAlphaComponent(0.92).setFill()
            let path = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: 5, yRadius: 5)
            path.fill()
            NSColor.controlAccentColor.withAlphaComponent(0.75).setStroke()
            path.lineWidth = 1
            path.stroke()
            
            let title = (self.tab?.title ?? "") as NSString
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 11, weight: .medium),
                .foregroundColor: NSColor.labelColor,
            ]
            let textRect = NSRect(x: 8, y: 2, width: rect.width - 16, height: rect.height - 4)
            title.draw(with: textRect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], attributes: attrs)
            return true
        }
        return image
    }
    
    
    private func updateBackground() {
        
        if self.isSelected {
            self.layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.11).cgColor
        } else if self.isHovered {
            self.layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.05).cgColor
        } else {
            self.layer?.backgroundColor = NSColor.clear.cgColor
        }
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
