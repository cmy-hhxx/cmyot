//
//  ContentViewController.swift
//
//  CotEditor
//  https://coteditor.com
//
//  Created by 1024jp on 2024-05-04.
//
//  ---------------------------------------------------------------------------
//
//  © 2024-2026 1024jp
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
import ControlUI
import SwiftUI

enum WorkspaceCenterKind: String, CaseIterable, Identifiable {
    case weeklyReports = "周报中心"
    case documents = "文档中心"
    case dashboard = "数据看板"
    
    var id: String { self.rawValue }
}


enum WorkspaceCenterIcons {
    
    private static let defaultSize = NSSize(width: 18, height: 18)
    
    private struct DynamicTint: Sendable {
        let light: (CGFloat, CGFloat, CGFloat, CGFloat)
        let dark: (CGFloat, CGFloat, CGFloat, CGFloat)
        
        func resolve(for appearance: NSAppearance) -> NSColor {
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let c = isDark ? self.dark : self.light
            return NSColor(srgbRed: c.0, green: c.1, blue: c.2, alpha: c.3)
        }
    }
    
    
    /// Renders a uniform-stroke linear SF Symbol centered inside an exact `18 × 18` toolbar canvas
    /// with dynamic appearance-aware semantic coloring so dark/light transitions update live.
    @MainActor
    private static func appleToolbarSymbol(
        _ symbolName: String,
        fallback: String? = nil,
        pointSize: CGFloat = 14.0,
        weight: NSFont.Weight = .medium,
        dynamicTint: DynamicTint? = nil,
        fixedColor: NSColor? = nil,
        isTemplate: Bool = false,
        size: NSSize = defaultSize
    ) -> NSImage {
        let base = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)
            ?? fallback.flatMap { NSImage(systemSymbolName: $0, accessibilityDescription: nil) }
        let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: weight)
        let configured = base?.withSymbolConfiguration(config)
        
        let image = NSImage(size: size, flipped: false) { rect in
            NSGraphicsContext.current?.shouldAntialias = true
            NSGraphicsContext.current?.imageInterpolation = .high
            guard let sym = configured else { return true }
            
            let symSize = sym.size
            let scale = min(1.0, min((rect.width - 1.5) / max(1, symSize.width), (rect.height - 1.5) / max(1, symSize.height)))
            let drawW = symSize.width * scale
            let drawH = symSize.height * scale
            let drawRect = NSRect(
                x: (rect.width - drawW) * 0.5,
                y: (rect.height - drawH) * 0.5,
                width: drawW,
                height: drawH
            )
            sym.draw(in: drawRect, from: .zero, operation: .sourceOver, fraction: 1.0)
            
            if !isTemplate {
                let tint = fixedColor ?? dynamicTint?.resolve(for: NSAppearance.currentDrawing())
                if let tint {
                    tint.setFill()
                    drawRect.fill(using: .sourceIn)
                }
            }
            return true
        }
        image.isTemplate = isTemplate
        return image
    }
    
    
    /// Linear icon for 编辑 / 只读 (`editable` toolbar item): slate-blue `pencil.line` vs amber `lock`.
    @MainActor
    static func editableIcon(isEditable: Bool, size: NSSize = defaultSize) -> NSImage {
        let tint = isEditable
            ? DynamicTint(light: (0.28, 0.41, 0.56, 0.94), dark: (0.56, 0.70, 0.84, 0.94))
            : DynamicTint(light: (0.74, 0.45, 0.12, 0.96), dark: (0.92, 0.68, 0.30, 0.96))
        return self.appleToolbarSymbol(
            isEditable ? "pencil.line" : "lock",
            fallback: isEditable ? "square.and.pencil" : "lock.fill",
            pointSize: 14.0,
            weight: .medium,
            dynamicTint: tint,
            size: size
        )
    }
    
    
    /// Linear icon for 数据看板 (`chart.bar.xaxis`), muted teal in rest state and accent-tinted when active.
    @MainActor
    static func analyticsDashboardIcon(isActive: Bool, size: NSSize = defaultSize) -> NSImage {
        let tint = DynamicTint(light: (0.14, 0.49, 0.53, 0.94), dark: (0.38, 0.77, 0.80, 0.94))
        return self.appleToolbarSymbol(
            "chart.bar.xaxis",
            fallback: "chart.bar",
            pointSize: 14.0,
            weight: isActive ? .semibold : .medium,
            dynamicTint: isActive ? nil : tint,
            fixedColor: isActive ? StudioPaletteManager.shared.activeNSAccentColor : nil,
            size: size
        )
    }
    
    
    /// Linear icon for 深浅外观 (`sun.max` warm amber / `moon.stars` muted indigo).
    @MainActor
    static func appearanceModeIcon(isDark: Bool, size: NSSize = defaultSize) -> NSImage {
        let tint = isDark
            ? DynamicTint(light: (0.34, 0.31, 0.65, 0.94), dark: (0.64, 0.60, 0.92, 0.94))
            : DynamicTint(light: (0.72, 0.48, 0.10, 0.94), dark: (0.92, 0.72, 0.34, 0.94))
        return self.appleToolbarSymbol(
            isDark ? "moon.stars" : "sun.max",
            pointSize: 14.2,
            weight: .medium,
            dynamicTint: tint,
            size: size
        )
    }
    
    
    /// Linear icon for 周报中心 (`calendar`), muted terracotta-rose in rest state.
    @MainActor
    static func weeklyReportIcon(isActive: Bool, size: NSSize = defaultSize) -> NSImage {
        let tint = DynamicTint(light: (0.70, 0.31, 0.28, 0.94), dark: (0.90, 0.54, 0.49, 0.94))
        return self.appleToolbarSymbol(
            "calendar",
            pointSize: 14.0,
            weight: isActive ? .semibold : .medium,
            dynamicTint: isActive ? nil : tint,
            fixedColor: isActive ? StudioPaletteManager.shared.activeNSAccentColor : nil,
            size: size
        )
    }
    
    
    /// Linear icon for 文档中心 (`books.vertical`), muted cobalt blue in rest state.
    @MainActor
    static func documentCenterIcon(isActive: Bool, size: NSSize = defaultSize) -> NSImage {
        let tint = DynamicTint(light: (0.20, 0.39, 0.68, 0.94), dark: (0.47, 0.67, 0.93, 0.94))
        return self.appleToolbarSymbol(
            "books.vertical",
            fallback: "doc.on.doc",
            pointSize: 13.8,
            weight: isActive ? .semibold : .medium,
            dynamicTint: isActive ? nil : tint,
            fixedColor: isActive ? StudioPaletteManager.shared.activeNSAccentColor : nil,
            size: size
        )
    }
    
    
    /// Linear icon for 终端 (`apple.terminal`), muted emerald green.
    @MainActor
    static func terminalIcon(size: NSSize = defaultSize) -> NSImage {
        let tint = DynamicTint(light: (0.16, 0.48, 0.32, 0.94), dark: (0.38, 0.77, 0.56, 0.94))
        return self.appleToolbarSymbol(
            "apple.terminal",
            fallback: "terminal",
            pointSize: 14.0,
            weight: .medium,
            dynamicTint: tint,
            size: size
        )
    }
    
    
    /// Linear icon for 设置 (`gearshape`), neutral slate-graphite.
    @MainActor
    static func settingsIcon(size: NSSize = defaultSize) -> NSImage {
        let tint = DynamicTint(light: (0.35, 0.38, 0.43, 0.92), dark: (0.65, 0.69, 0.74, 0.92))
        return self.appleToolbarSymbol(
            "gearshape",
            pointSize: 14.0,
            weight: .medium,
            dynamicTint: tint,
            size: size
        )
    }
}


final class ContentViewController: NSSplitViewController {
    
    static let didChangeActiveCenterNotification = Notification.Name("CotEditorContentViewControllerDidChangeActiveCenter")
    
    // MARK: Public Properties
    
    var document: DataDocument?  { didSet { self.updateDocument(from: oldValue) } }
    
    /// Whether the terminal panel is currently part of the window.
    var isTerminalVisible: Bool  { self.terminalItem != nil }
    
    /// Which in-window workspace center (if any) is currently open.
    private(set) var activeCenter: WorkspaceCenterKind?
    
    var documentViewController: DocumentViewController? {
        
        self.splitViewItems.first?.viewController as? DocumentViewController
    }
    
    
    // MARK: Private Properties
    
    private var terminalItem: NSSplitViewItem?
    private var terminalViewController: TerminalViewController?
    private var windowCloseObserver: (any NSObjectProtocol)?
    private var centerEscMonitor: Any?
    private var centerHostView: NSHostingView<WorkspaceCenterHostView>?
    private var wallpaperBackdropView: EditorWallpaperBackdropView?
    private let centerHostModel = WorkspaceCenterHostModel()
    private lazy var weeklyReportState = WeeklyReportCenterState()
    private lazy var documentCenterState = DocumentCenterState()
    
    
    // MARK: Lifecycle
    
    init(document: DataDocument?) {
        
        self.document = document
        
        super.init(nibName: nil, bundle: nil)
    }
    
    
    required init?(coder: NSCoder) {
        
        fatalError("init(coder:) has not been implemented")
    }
    
    
    override func loadView() {
        
        let container = NSView()
        container.frame.size = NSSize(width: 640, height: 600)
        self.view = container
        
        let splitView = self.splitView
        splitView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(splitView)
        NSLayoutConstraint.activate([
            splitView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            splitView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            splitView.topAnchor.constraint(equalTo: container.topAnchor),
            splitView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
    }
    
    
    override func viewDidLoad() {
        
        super.viewDidLoad()
        
        self.splitView.isVertical = false
        self.splitViewItems = [
            NSSplitViewItem(viewController: .viewController(document: self.document)),
        ]
        
        let wallpaperView = EditorWallpaperBackdropView(frame: .zero)
        wallpaperView.translatesAutoresizingMaskIntoConstraints = false
        self.view.addSubview(wallpaperView, positioned: .below, relativeTo: self.splitView)
        NSLayoutConstraint.activate([
            wallpaperView.leadingAnchor.constraint(equalTo: self.view.leadingAnchor),
            wallpaperView.trailingAnchor.constraint(equalTo: self.view.trailingAnchor),
            wallpaperView.topAnchor.constraint(equalTo: self.view.topAnchor),
            wallpaperView.bottomAnchor.constraint(equalTo: self.view.bottomAnchor),
        ])
        self.wallpaperBackdropView = wallpaperView
    }
    
    
    override func viewDidAppear() {
        
        super.viewDidAppear()
        
        if self.windowCloseObserver == nil, let window = self.view.window {
            self.windowCloseObserver = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification,
                                                                             object: window,
                                                                             queue: .main)
            { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.hideTerminal()
                }
            }
        }
        if self.activeCenter != nil {
            self.installCenterEscMonitor()
        }
    }
    
    
    override func viewDidDisappear() {
        
        super.viewDidDisappear()
        
        if let observer = self.windowCloseObserver {
            NotificationCenter.default.removeObserver(observer)
            self.windowCloseObserver = nil
        }
        
        // never leave a shell alive behind a closed or replaced window
        self.hideTerminal()
        self.removeCenterEscMonitor()
    }
    
    
    isolated deinit {
        
        if let observer = self.windowCloseObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let monitor = self.centerEscMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }
    
    
    // MARK: Toolbar & UI Validation
    
    override func validateUserInterfaceItem(_ item: any NSValidatedUserInterfaceItem) -> Bool {
        
        if let toolbarItem = item as? NSToolbarItem,
           toolbarItem.action == #selector(toggleWeeklyReportCenter(_:))
            || toolbarItem.action == #selector(toggleDocumentCenter(_:))
            || toolbarItem.action == #selector(toggleAnalyticsDashboard(_:))
        {
            return self.validateCenterToolbarItem(toolbarItem)
        }
        return super.validateUserInterfaceItem(item)
    }
    
    
    /// Updates the toggle state of the in-window Weekly Report Center, Document Center, and Analytics Dashboard toolbar items.
    func validateCenterToolbarItem(_ item: NSToolbarItem) -> Bool {
        
        switch item.action {
            case #selector(toggleWeeklyReportCenter(_:)):
                (item as? StatableToolbarItem)?.state = (self.activeCenter == .weeklyReports) ? .on : .off
                return true
            case #selector(toggleDocumentCenter(_:)):
                (item as? StatableToolbarItem)?.state = (self.activeCenter == .documents) ? .on : .off
                return true
            case #selector(toggleAnalyticsDashboard(_:)):
                (item as? StatableToolbarItem)?.state = (self.activeCenter == .dashboard) ? .on : .off
                return true
            default:
                return true
        }
    }
    
    
    // MARK: In-Window Workspace Centers (Weekly Reports, Documents & Analytics Dashboard)
    
    @IBAction func toggleWeeklyReportCenter(_ sender: Any?) {
        
        if self.activeCenter == .weeklyReports {
            self.hideInWindowCenter()
        } else {
            self.showInWindowCenter(.weeklyReports)
        }
    }
    
    
    @IBAction func toggleDocumentCenter(_ sender: Any?) {
        
        if self.activeCenter == .documents {
            self.hideInWindowCenter()
        } else {
            self.showInWindowCenter(.documents)
        }
    }
    
    
    @IBAction func toggleAnalyticsDashboard(_ sender: Any?) {
        
        if self.activeCenter == .dashboard {
            self.hideInWindowCenter()
        } else {
            self.showInWindowCenter(.dashboard)
        }
    }
    
    
    /// Opens Weekly Report Center, Document Center, or Analytics Dashboard directly inside this window (no separate window).
    func showInWindowCenter(
        _ kind: WorkspaceCenterKind,
        weeklyMode: WeeklyReportWindowController.InitialMode = .history,
        selectingReportID: String? = nil
    ) {
        self.activeCenter = kind
        
        switch kind {
            case .weeklyReports:
                if CotLocalDatabase.shared.weeklyReports.isEmpty {
                    CotLocalDatabase.shared.reloadWeeklyReports()
                }
                self.weeklyReportState.isGeneratorActive = (weeklyMode == .generator)
                self.weeklyReportState.rebuildGroups()
                if let selectingReportID {
                    self.weeklyReportState.selectedReportID = selectingReportID
                } else if self.weeklyReportState.selectedReportID == nil {
                    self.weeklyReportState.selectedReportID = CotLocalDatabase.shared.weeklyReports.first?.id
                }
                self.weeklyReportState.refreshOpenSources()
            case .documents:
                self.documentCenterState.refresh()
            case .dashboard:
                AnalyticsManager.shared.flushPendingStats()
                AnalyticsManager.shared.reloadFromDatabase()
        }
        
        self.centerHostModel.selectedKind = kind
        if let existing = self.centerHostView {
            existing.alphaValue = 1
            existing.isHidden = false
        } else {
            let rootView = self.makeCenterHostView()
            let hostingView = NSHostingView(rootView: rootView)
            hostingView.translatesAutoresizingMaskIntoConstraints = false
            hostingView.wantsLayer = true
            self.view.addSubview(hostingView, positioned: .above, relativeTo: self.splitView)
            NSLayoutConstraint.activate([
                hostingView.leadingAnchor.constraint(equalTo: self.view.leadingAnchor),
                hostingView.trailingAnchor.constraint(equalTo: self.view.trailingAnchor),
                hostingView.topAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.topAnchor),
                hostingView.bottomAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.bottomAnchor),
            ])
            self.centerHostView = hostingView
        }
        
        if let host = self.centerHostView, let layer = host.layer {
            host.layoutSubtreeIfNeeded()
            let anim = CAKeyframeAnimation(keyPath: "transform.scale")
            anim.values = [0.988, 1.0]
            anim.keyTimes = [0.0, 1.0]
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 0.0
            fade.toValue = 1.0
            let group = CAAnimationGroup()
            group.animations = [anim, fade]
            group.duration = 0.20
            group.timingFunction = CAMediaTimingFunction(controlPoints: 0.25, 0.8, 0.25, 1.0)
            layer.removeAllAnimations()
            layer.add(group, forKey: "centerArrive")
        }
        
        self.splitView.isHidden = true
        self.view.window?.invalidateCursorRects(for: self.view)
        NSCursor.arrow.set()
        
        self.installCenterEscMonitor()
        self.view.window?.toolbar?.validateVisibleItems()
        NotificationCenter.default.post(name: Self.didChangeActiveCenterNotification, object: self)
    }
    
    
    /// Closes any open in-window center and returns focus to the active editor pane.
    func hideInWindowCenter() {
        
        self.activeCenter = nil
        self.centerHostModel.selectedKind = nil
        self.centerHostModel.popSubLayer = nil
        self.removeCenterEscMonitor()
        self.splitView.isHidden = false
        self.centerHostView?.isHidden = true
        self.view.window?.invalidateCursorRects(for: self.view)
        
        self.view.window?.toolbar?.validateVisibleItems()
        NotificationCenter.default.post(name: Self.didChangeActiveCenterNotification, object: self)
        if let textView = self.documentViewController?.focusedTextView {
            self.view.window?.makeFirstResponderDiscardingMarkedText(textView)
        }
    }
    
    
    private func makeCenterHostView() -> WorkspaceCenterHostView {
        
        WorkspaceCenterHostView(
            hostModel: self.centerHostModel,
            weeklyReportState: self.weeklyReportState,
            documentCenterState: self.documentCenterState,
            onDismiss: { [weak self] in
                self?.hideInWindowCenter()
            },
            onOpenWeeklyReport: { [weak self] report in
                guard let self else { return }
                self.documentViewController?.openStoredWeeklyReport(report)
                self.hideInWindowCenter()
            },
            onOpenManagedDocument: { [weak self] liveDoc, record in
                guard let self, let docVC = self.documentViewController else { return }
                if let liveDoc {
                    docVC.openOrFocusDocument(liveDoc)
                } else if let record {
                    docVC.openStoredDocumentRecord(record)
                }
                self.hideInWindowCenter()
            },
            onOpenAllManagedDocuments: { [weak self] items in
                guard let self, let docVC = self.documentViewController else { return }
                let entries = items.map { item in
                    (liveDoc: self.documentCenterState.liveDocument(for: item.id), record: item.storedRecord)
                }
                let preferredRecordID = items.first(where: { $0.id == self.documentCenterState.selectedID })?.dbRecordID
                docVC.openAllManagedDocuments(entries, focusing: preferredRecordID)
                self.hideInWindowCenter()
            },
            onDeleteManagedDocument: { [weak self] item in
                self?.deleteManagedDocument(item)
            },
            onCreateNewDocument: { [weak self] in
                guard let self, let docVC = self.documentViewController else { return }
                if let created = try? (NSDocumentController.shared as? DocumentController)?.openUntitledDocumentAndDisplay(false) as? Document {
                    docVC.openOrFocusDocument(created, splitRight: false)
                    AnalyticsManager.shared.recordFileCreated()
                }
                self.hideInWindowCenter()
            }
        )
    }
    
    
    private func deleteManagedDocument(_ item: DocumentCenterState.ManagedDocumentItem) {
        
        let liveDoc = self.documentCenterState.liveDocument(for: item.id)
        
        let finishDeletion: () -> Void = { [weak self] in
            if let liveDoc {
                var closedInPane = false
                for window in NSApp.orderedWindows {
                    guard let docVC = (window.windowController as? DocumentWindowController)?.documentViewController else { continue }
                    if docVC.paneDocuments.contains(where: { $0 === liveDoc }) {
                        docVC.closeDocumentFromCenter(liveDoc)
                        closedInPane = true
                    }
                }
                if !closedInPane {
                    liveDoc.updateChangeCount(.changeCleared)
                    liveDoc.hasUncommittedChanges = false
                    liveDoc.close()
                }
            }
            
            CotLocalDatabase.shared.trashDocument(id: item.dbRecordID ?? item.id, filePath: item.filePath)
            self?.documentCenterState.refresh()
        }
        
        if let liveDoc, item.filePath != nil, item.isDirty, let docVC = self.documentViewController {
            docVC.reviewDocuments([liveDoc]) { canClose in
                guard canClose else { return }
                finishDeletion()
            }
        } else {
            finishDeletion()
        }
    }
    
    
    private func installCenterEscMonitor() {
        
        self.removeCenterEscMonitor()
        self.centerEscMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard
                let self,
                self.activeCenter != nil,
                event.window === self.view.window,
                event.keyCode == 53  // Escape
            else { return event }
            
            if let responder = event.window?.firstResponder as? NSTextView {
                if responder.hasMarkedText() {
                    return event
                }
                if responder.isEditable {
                    event.window?.makeFirstResponder(nil)
                    return nil
                }
            }
            if self.centerHostModel.popSubLayer?() == true {
                return nil
            }
            self.hideInWindowCenter()
            return nil
        }
    }
    
    
    private func removeCenterEscMonitor() {
        
        if let monitor = self.centerEscMonitor {
            NSEvent.removeMonitor(monitor)
            self.centerEscMonitor = nil
        }
    }
    
    
    // MARK: Split View Controller Methods
    
    override func splitView(_ splitView: NSSplitView, effectiveRect proposedEffectiveRect: NSRect, forDrawnRect drawnRect: NSRect, ofDividerAt dividerIndex: Int) -> NSRect {
        
        // The terminal panel is resizable; the status bar boundary is not.
        if let terminalItem = self.terminalItem,
           let index = self.splitViewItems.firstIndex(where: { $0 === terminalItem }),
           dividerIndex == index - 1
        {
            return proposedEffectiveRect
        }
        
        // avoid showing draggable cursor for the status bar boundary
        return .zero
    }
    
    
    // MARK: Terminal
    
    /// Shows the terminal panel when hidden, and hides (and terminates) it when shown.
    ///
    /// - Parameter sender: The action sender.
    @IBAction func toggleTerminal(_ sender: Any?) {
        
        if self.isTerminalVisible {
            self.hideTerminal()
        } else {
            self.showTerminal()
        }
    }
    
    
    /// Inserts the terminal panel below the editor and starts a fresh shell.
    func showTerminal() {
        
        guard
            self.terminalItem == nil,
            self.view.window != nil
        else { return }
        
        let viewController = TerminalViewController()
        viewController.onProcessTerminated = { [weak self] in
            self?.hideTerminal()
        }
        viewController.themeProvider = { [weak self] in
            self?.documentViewController?.currentTheme
        }
        viewController.fontProvider = { [weak self] in
            self?.documentViewController?.focusedTextView?.font
        }
        
        let item = NSSplitViewItem(viewController: viewController)
        item.canCollapse = false
        item.minimumThickness = 80
        // the editor takes the extra height when the window resizes; the panel keeps its own
        item.holdingPriority = NSLayoutConstraint.Priority(260)
        
        self.insertSplitViewItem(item, at: min(1, self.splitViewItems.count))

        self.terminalItem = item
        self.terminalViewController = viewController
        NotificationCenter.default.post(name: Self.didChangeActiveCenterNotification, object: self)
        
        viewController.start(in: self.terminalWorkingDirectory)
        
        // The split view only knows the new item's size after a layout pass, so set the
        // divider on the next run loop turn and once more after the panel is drawn.
        DispatchQueue.main.async { [weak self] in
            self?.view.layoutSubtreeIfNeeded()
            self?.applyTerminalHeight()
            
            DispatchQueue.main.async {
                self?.view.layoutSubtreeIfNeeded()
                self?.applyTerminalHeight()
            }
        }
    }
    
    
    /// Opens the built-in terminal panel if needed, focuses it, and dispatches `command` into the shell.
    func launchCommandInTerminal(_ command: String) {
        
        let wasHidden = !self.isTerminalVisible
        if wasHidden {
            self.showTerminal()
        }
        let delay: TimeInterval = wasHidden ? 0.35 : 0.05
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self else { return }
            self.view.window?.makeKeyAndOrderFront(nil)
            self.terminalViewController?.focus()
            self.terminalViewController?.sendCommand(command)
        }
    }
    
    
    /// Removes the terminal panel and terminates its shell.
    func hideTerminal() {
        
        guard let item = self.terminalItem else { return }
        
        self.terminalItem = nil
        let viewController = self.terminalViewController
        self.terminalViewController = nil
        NotificationCenter.default.post(name: Self.didChangeActiveCenterNotification, object: self)
        
        // terminate the shell before the view (and its PTY) goes away
        viewController?.shutdown()
        self.removeSplitViewItem(item)
        
        if let textView = self.documentViewController?.focusedTextView {
            self.view.window?.makeFirstResponder(textView)
        }
    }
    
    
    /// The process identifier of the terminal's shell, for tests and diagnostics.
    var terminalShellProcessIdentifier: pid_t? {
        
        self.terminalViewController?.shellProcessIdentifier
    }
    
    
    /// The folder a new terminal starts in: the document's folder, or the home folder.
    private var terminalWorkingDirectory: URL? {
        
        guard let fileURL = (self.document as? Document)?.fileURL else { return nil }
        
        return fileURL.deletingLastPathComponent()
    }
    
    
    /// Gives the terminal panel a sensible share of the window height.
    private func applyTerminalHeight() {
        
        guard
            let item = self.terminalItem,
            let index = self.splitViewItems.firstIndex(where: { $0 === item }),
            index > 0
        else { return }
        
        let height = self.splitView.bounds.height
        guard height > 0 else { return }
        
        let statusBarHeight = (self.parent as? WindowContentViewController)?.statusBarHeight ?? 0
        let panelHeight = min(240, max(140, height * 0.3))
        
        self.splitView.setPosition(max(0, height - statusBarHeight - panelHeight), ofDividerAt: index - 1)
    }
    
    
    // MARK: Private Methods
    
    /// Updates the document in children.
    ///
    /// - Parameter oldDocument: The previous document.
    private func updateDocument(from oldDocument: DataDocument?) {
        
        guard oldDocument != self.document else { return }
        
        if let existing = self.documentViewController,
           let newDocument = self.document as? Document,
           existing.document === newDocument || existing.paneDocuments.contains(where: { $0 === newDocument })
        {
            return
        }
        
        guard self.isViewLoaded, !self.splitViewItems.isEmpty else { return }
        self.splitViewItems[0] = NSSplitViewItem(viewController: .viewController(document: self.document))
    }
}


private extension NSViewController {
    
    /// Creates a new view controller with the passed-in document.
    ///
    /// - Parameter document: The represented document.
    /// - Returns: A view controller.
    static func viewController(document: DataDocument?) -> sending NSViewController {
        
        switch document {
            case let document as Document:
                DocumentViewController(document: document)
            case let document as PreviewDocument:
                NSHostingController(rootView: FilePreviewView(item: document))
            case .none:
                NSHostingController(rootView: NoDocumentView())
            default:
                preconditionFailure()
        }
    }
}


@MainActor @Observable
private final class WorkspaceCenterHostModel {
    var selectedKind: WorkspaceCenterKind?
    var popSubLayer: (() -> Bool)?
}


private struct WorkspaceCenterHostView: View {
    
    let hostModel: WorkspaceCenterHostModel
    let weeklyReportState: WeeklyReportCenterState
    let documentCenterState: DocumentCenterState
    
    var onDismiss: () -> Void
    var onOpenWeeklyReport: (StoredWeeklyReport) -> Void
    var onOpenManagedDocument: (Document?, StoredDocumentRecord?) -> Void
    var onOpenAllManagedDocuments: ([DocumentCenterState.ManagedDocumentItem]) -> Void
    var onDeleteManagedDocument: (DocumentCenterState.ManagedDocumentItem) -> Void
    var onCreateNewDocument: () -> Void
    
    var body: some View {
        
        Group {
            switch self.hostModel.selectedKind {
                case .weeklyReports:
                    WeeklyReportCenterView(
                        state: self.weeklyReportState,
                        onOpenReport: self.onOpenWeeklyReport,
                        onDismiss: self.onDismiss
                    )
                case .documents:
                    DocumentCenterView(
                        state: self.documentCenterState,
                        onOpenDocument: self.onOpenManagedDocument,
                        onOpenAllDocuments: self.onOpenAllManagedDocuments,
                        onDeleteDocument: self.onDeleteManagedDocument,
                        onCreateNewDocument: self.onCreateNewDocument,
                        onDismiss: self.onDismiss
                    )
                case .dashboard:
                    AnalyticsDashboardView(
                        isEmbeddedInSettings: false,
                        onDismiss: self.onDismiss,
                        onOpenDocument: { record in
                            self.onOpenManagedDocument(nil, record)
                        },
                        onOpenWeeklyReport: self.onOpenWeeklyReport
                    )
                case nil:
                    Color.clear
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor))
        .environment(\.registerWorkspaceCenterEscPop) { [weak hostModel = self.hostModel] handler in
            hostModel?.popSubLayer = handler
        }
    }
}


/// Draws the active editor theme ground composited with `WallpaperManager`'s pre-blurred artwork
/// underneath split panes so text readability and cursor contrast stay effortless.
@MainActor
private final class EditorWallpaperBackdropView: NSView {
    
    private var wallpaperObserver: (any NSObjectProtocol)?
    private var themeBgObserver: NSKeyValueObservation?
    
    
    override init(frame frameRect: NSRect) {
        
        super.init(frame: frameRect)
        
        self.wantsLayer = true
        self.wallpaperObserver = NotificationCenter.default.addObserver(
            forName: WallpaperManager.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.needsDisplay = true
            }
        }
    }
    
    
    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    
    isolated deinit {
        if let observer = self.wallpaperObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }
    
    
    override func viewDidMoveToWindow() {
        
        super.viewDidMoveToWindow()
        self.themeBgObserver = nil
        if let docWindow = self.window as? DocumentWindow {
            self.themeBgObserver = docWindow.observe(\.backgroundColor, options: [.new]) { [weak self] _, _ in
                MainActor.assumeIsolated {
                    self?.needsDisplay = true
                }
            }
        }
        self.needsDisplay = true
    }
    
    
    override func draw(_ dirtyRect: NSRect) {
        
        let baseColor = (self.window as? DocumentWindow)?.contentBackgroundColor ?? .textBackgroundColor
        baseColor.setFill()
        dirtyRect.fill()
        
        let spec = WallpaperManager.shared.spec
        guard spec.isEnabled,
              let artwork = WallpaperManager.shared.activeBackdropImage()
        else { return }
        
        let imgSize = artwork.size
        let drawRect = WallpaperManager.framedDrawRect(
            imageSize: imgSize,
            viewportSize: self.bounds.size,
            scale: spec.scale,
            panX: spec.panX,
            panY: spec.panY,
            isFlippedY: self.isFlipped,
            displayMode: spec.displayMode
        )
        guard !drawRect.isEmpty else { return }
        
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: self.bounds).addClip()
        NSGraphicsContext.current?.imageInterpolation = .high
        artwork.draw(in: drawRect, from: .zero, operation: .sourceOver, fraction: CGFloat(spec.opacity))
        NSGraphicsContext.restoreGraphicsState()
    }
}
