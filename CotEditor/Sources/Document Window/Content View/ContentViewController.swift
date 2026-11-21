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
    
    
    /// Renders an Apple SF Symbol centered inside an exact `18 × 18` toolbar canvas with crisp Apple optical weights.
    @MainActor
    private static func appleToolbarSymbol(
        _ symbolName: String,
        fallback: String? = nil,
        pointSize: CGFloat = 14.2,
        weight: NSFont.Weight = .medium,
        tintColor: NSColor? = nil,
        isTemplate: Bool,
        size: NSSize = defaultSize
    ) -> NSImage {
        let base = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)
            ?? fallback.flatMap { NSImage(systemSymbolName: $0, accessibilityDescription: nil) }
        let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: weight)
        let configured = base?.withSymbolConfiguration(config)
        let finalSymbol: NSImage? = if let tintColor, !isTemplate, let configured {
            configured.tinted(with: tintColor)
        } else {
            configured
        }
        
        let image = NSImage(size: size, flipped: false) { rect in
            NSGraphicsContext.current?.shouldAntialias = true
            NSGraphicsContext.current?.imageInterpolation = .high
            if let sym = finalSymbol {
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
            }
            return true
        }
        image.isTemplate = isTemplate
        return image
    }
    
    
    /// Apple HIG icon for 编辑 / 只读 (`editable` toolbar item): `pencil.line` vs unmistakable `lock.fill`.
    @MainActor
    static func editableIcon(isEditable: Bool, size: NSSize = defaultSize) -> NSImage {
        self.appleToolbarSymbol(
            isEditable ? "pencil.line" : "lock.fill",
            fallback: isEditable ? "square.and.pencil" : "lock",
            pointSize: 14.0,
            weight: .medium,
            isTemplate: true,
            size: size
        )
    }
    
    
    /// Apple HIG icon for Emoji (`quickEmoji` toolbar item).
    @MainActor
    static func quickEmojiIcon(size: NSSize = defaultSize) -> NSImage {
        self.appleToolbarSymbol(
            "face.smiling",
            pointSize: 14.5,
            weight: .medium,
            isTemplate: true,
            size: size
        )
    }
    
    
    /// Apple HIG icon for 数据看板: unboxed bar chart (`chart.bar.xaxis` / filled tinted accent when open).
    @MainActor
    static func analyticsDashboardIcon(isActive: Bool, size: NSSize = defaultSize) -> NSImage {
        let tint = StudioPaletteManager.shared.activeNSAccentColor
        return self.appleToolbarSymbol(
            isActive ? "chart.bar.fill" : "chart.bar.xaxis",
            fallback: "chart.bar",
            pointSize: 14.0,
            weight: .medium,
            tintColor: isActive ? tint : nil,
            isTemplate: !isActive,
            size: size
        )
    }
    
    
    /// Apple HIG icon for 深浅外观 (`sun.max` / `moon.stars.fill`).
    @MainActor
    static func appearanceModeIcon(isDark: Bool, size: NSSize = defaultSize) -> NSImage {
        self.appleToolbarSymbol(
            isDark ? "moon.stars.fill" : "sun.max",
            pointSize: 14.5,
            weight: .medium,
            isTemplate: true,
            size: size
        )
    }
    
    
    /// Apple HIG icon for 周报中心 (`calendar`).
    @MainActor
    static func weeklyReportIcon(isActive: Bool, size: NSSize = defaultSize) -> NSImage {
        let tint = StudioPaletteManager.shared.activeNSAccentColor
        return self.appleToolbarSymbol(
            "calendar",
            pointSize: 14.2,
            weight: .medium,
            tintColor: isActive ? tint : nil,
            isTemplate: !isActive,
            size: size
        )
    }
    
    
    /// Apple HIG icon for 文档中心 (`books.vertical` / `books.vertical.fill`) — distinct book-spine silhouette.
    @MainActor
    static func documentCenterIcon(isActive: Bool, size: NSSize = defaultSize) -> NSImage {
        let tint = StudioPaletteManager.shared.activeNSAccentColor
        return self.appleToolbarSymbol(
            isActive ? "books.vertical.fill" : "books.vertical",
            fallback: "doc.on.doc",
            pointSize: 14.0,
            weight: .medium,
            tintColor: isActive ? tint : nil,
            isTemplate: !isActive,
            size: size
        )
    }
    
    
    /// Apple HIG icon for 终端 (`apple.terminal` / `terminal`).
    @MainActor
    static func terminalIcon(size: NSSize = defaultSize) -> NSImage {
        self.appleToolbarSymbol(
            "apple.terminal",
            fallback: "terminal",
            pointSize: 14.2,
            weight: .medium,
            isTemplate: true,
            size: size
        )
    }
    
    
    /// Apple HIG icon for AI 设置 (`sparkles`).
    @MainActor
    static func aiSettingsIcon(size: NSSize = defaultSize) -> NSImage {
        self.appleToolbarSymbol(
            "sparkles",
            pointSize: 14.2,
            weight: .medium,
            isTemplate: true,
            size: size
        )
    }
    
    
    /// Apple HIG icon for 右侧检查器 (`sidebar.trailing`).
    @MainActor
    static func inspectorIcon(size: NSSize = defaultSize) -> NSImage {
        self.appleToolbarSymbol(
            "sidebar.trailing",
            fallback: "sidebar.right",
            pointSize: 14.5,
            weight: .medium,
            isTemplate: true,
            size: size
        )
    }
    
    
    /// Apple HIG icon for 更多 (`ellipsis.circle`).
    @MainActor
    static func moreIcon(size: NSSize = defaultSize) -> NSImage {
        self.appleToolbarSymbol(
            "ellipsis.circle",
            pointSize: 14.5,
            weight: .medium,
            isTemplate: true,
            size: size
        )
    }
}


final class ContentViewController: NSSplitViewController {
    
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
    private var windowCloseObserver: NSObjectProtocol?
    private var centerEscMonitor: Any?
    private var centerHostView: NSHostingView<WorkspaceCenterHostView>?
    private var pinnedTodoOverlayView: PinnedTodoOverlayContainerView?
    private let centerHostModel = WorkspaceCenterHostModel()
    private let weeklyReportState = WeeklyReportCenterState()
    private let documentCenterState = DocumentCenterState()
    
    
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
        
        let todoOverlay = PinnedTodoOverlayContainerView(frame: .zero)
        todoOverlay.translatesAutoresizingMaskIntoConstraints = false
        self.view.addSubview(todoOverlay, positioned: .above, relativeTo: self.splitView)
        NSLayoutConstraint.activate([
            todoOverlay.leadingAnchor.constraint(equalTo: self.view.leadingAnchor),
            todoOverlay.trailingAnchor.constraint(equalTo: self.view.trailingAnchor),
            todoOverlay.topAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.topAnchor),
            todoOverlay.bottomAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.bottomAnchor),
        ])
        self.pinnedTodoOverlayView = todoOverlay
    }
    
    
    override func viewDidAppear() {
        
        super.viewDidAppear()
        
        if self.windowCloseObserver == nil, let window = self.view.window {
            self.windowCloseObserver = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification,
                                                                             object: window,
                                                                             queue: .main)
            { [weak self] _ in
                self?.hideTerminal()
            }
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
            self.view.addSubview(hostingView, positioned: .above, relativeTo: self.splitView)
            NSLayoutConstraint.activate([
                hostingView.leadingAnchor.constraint(equalTo: self.view.leadingAnchor),
                hostingView.trailingAnchor.constraint(equalTo: self.view.trailingAnchor),
                hostingView.topAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.topAnchor),
                hostingView.bottomAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.bottomAnchor),
            ])
            self.centerHostView = hostingView
        }
        
        self.splitView.isHidden = true
        if let overlay = self.pinnedTodoOverlayView, let host = self.centerHostView {
            self.view.addSubview(overlay, positioned: .above, relativeTo: host)
        }
        self.view.window?.invalidateCursorRects(for: self.view)
        NSCursor.arrow.set()
        
        self.installCenterEscMonitor()
        self.view.window?.toolbar?.validateVisibleItems()
    }
    
    
    /// Closes any open in-window center and returns focus to the active editor pane.
    func hideInWindowCenter() {
        
        self.activeCenter = nil
        self.removeCenterEscMonitor()
        self.splitView.isHidden = false
        self.centerHostView?.isHidden = true
        self.view.window?.invalidateCursorRects(for: self.view)
        
        self.view.window?.toolbar?.validateVisibleItems()
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
            
            if let responder = event.window?.firstResponder as? NSTextView, responder.hasMarkedText() {
                return event
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
    
    
    /// Removes the terminal panel and terminates its shell.
    func hideTerminal() {
        
        guard let item = self.terminalItem else { return }
        
        self.terminalItem = nil
        let viewController = self.terminalViewController
        self.terminalViewController = nil
        
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
    var selectedKind: WorkspaceCenterKind = .documents
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
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor))
    }
}
