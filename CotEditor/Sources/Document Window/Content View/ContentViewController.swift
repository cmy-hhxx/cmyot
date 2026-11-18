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
    
    var id: String { self.rawValue }
}


enum WorkspaceCenterIcons {
    
    /// Custom vector icon for 周报中心 (a clean weekly report sheet with 3 structured summary bars).
    @MainActor
    static func weeklyReportIcon(isActive: Bool, size: NSSize = NSSize(width: 18, height: 18)) -> NSImage {
        
        let image = NSImage(size: size, flipped: true) { _ in
            let strokeColor: NSColor = isActive ? .controlAccentColor : .labelColor
            let scaleX = size.width / 18.0
            let scaleY = size.height / 18.0
            
            let transform = NSAffineTransform()
            transform.scaleX(by: scaleX, yBy: scaleY)
            transform.concat()
            
            let cardRect = NSRect(x: 2.75, y: 3.2, width: 12.5, height: 12.3)
            let cardPath = NSBezierPath(roundedRect: cardRect, xRadius: 2.6, yRadius: 2.6)
            
            if isActive {
                NSGraphicsContext.saveGraphicsState()
                cardPath.addClip()
                NSColor.controlAccentColor.withAlphaComponent(0.20).setFill()
                NSRect(x: 2.75, y: 3.2, width: 12.5, height: 3.3).fill()
                NSGraphicsContext.restoreGraphicsState()
            }
            
            strokeColor.setStroke()
            cardPath.lineWidth = 1.4
            cardPath.stroke()
            
            // Top binding ticks
            let ticks = NSBezierPath()
            ticks.lineWidth = 1.4
            ticks.lineCapStyle = .round
            ticks.move(to: NSPoint(x: 6.25, y: 1.7))
            ticks.line(to: NSPoint(x: 6.25, y: 3.5))
            ticks.move(to: NSPoint(x: 11.75, y: 1.7))
            ticks.line(to: NSPoint(x: 11.75, y: 3.5))
            ticks.stroke()
            
            // Header divider rule
            let divider = NSBezierPath()
            divider.lineWidth = 1.25
            divider.move(to: NSPoint(x: 2.75, y: 6.5))
            divider.line(to: NSPoint(x: 15.25, y: 6.5))
            divider.stroke()
            
            // Three ascending summary bars representing weekly progress
            let bars = NSBezierPath()
            bars.lineWidth = 1.6
            bars.lineCapStyle = .round
            bars.move(to: NSPoint(x: 6.2, y: 12.9))
            bars.line(to: NSPoint(x: 6.2, y: 10.6))
            bars.move(to: NSPoint(x: 9.0, y: 12.9))
            bars.line(to: NSPoint(x: 9.0, y: 8.7))
            bars.move(to: NSPoint(x: 11.8, y: 12.9))
            bars.line(to: NSPoint(x: 11.8, y: 9.7))
            bars.stroke()
            
            return true
        }
        image.isTemplate = !isActive
        return image
    }
    
    
    /// Custom vector icon for 文档中心 (a split master-detail document library card).
    @MainActor
    static func documentCenterIcon(isActive: Bool, size: NSSize = NSSize(width: 18, height: 18)) -> NSImage {
        
        let image = NSImage(size: size, flipped: true) { _ in
            let strokeColor: NSColor = isActive ? .controlAccentColor : .labelColor
            let scaleX = size.width / 18.0
            let scaleY = size.height / 18.0
            
            let transform = NSAffineTransform()
            transform.scaleX(by: scaleX, yBy: scaleY)
            transform.concat()
            
            let frameRect = NSRect(x: 2.25, y: 3.0, width: 13.5, height: 12.0)
            let framePath = NSBezierPath(roundedRect: frameRect, xRadius: 2.6, yRadius: 2.6)
            
            if isActive {
                NSGraphicsContext.saveGraphicsState()
                framePath.addClip()
                NSColor.controlAccentColor.withAlphaComponent(0.18).setFill()
                NSRect(x: 2.25, y: 3.0, width: 4.75, height: 12.0).fill()
                NSGraphicsContext.restoreGraphicsState()
            }
            
            strokeColor.setStroke()
            framePath.lineWidth = 1.4
            framePath.stroke()
            
            // Vertical sidebar divider
            let divider = NSBezierPath()
            divider.lineWidth = 1.25
            divider.move(to: NSPoint(x: 7.0, y: 3.0))
            divider.line(to: NSPoint(x: 7.0, y: 15.0))
            divider.stroke()
            
            // Left list ticks
            let listTicks = NSBezierPath()
            listTicks.lineWidth = 1.35
            listTicks.lineCapStyle = .round
            for y in [6.2, 9.0, 11.8] {
                listTicks.move(to: NSPoint(x: 3.9, y: y))
                listTicks.line(to: NSPoint(x: 5.35, y: y))
            }
            listTicks.stroke()
            
            // Right document preview lines
            let docLines = NSBezierPath()
            docLines.lineWidth = 1.35
            docLines.lineCapStyle = .round
            docLines.move(to: NSPoint(x: 8.85, y: 6.7))
            docLines.line(to: NSPoint(x: 13.65, y: 6.7))
            docLines.move(to: NSPoint(x: 8.85, y: 9.3))
            docLines.line(to: NSPoint(x: 13.65, y: 9.3))
            docLines.move(to: NSPoint(x: 8.85, y: 11.9))
            docLines.line(to: NSPoint(x: 11.9, y: 11.9))
            docLines.stroke()
            
            return true
        }
        image.isTemplate = !isActive
        return image
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
           (toolbarItem.action == #selector(toggleWeeklyReportCenter(_:)) || toolbarItem.action == #selector(toggleDocumentCenter(_:)))
        {
            return self.validateCenterToolbarItem(toolbarItem)
        }
        return super.validateUserInterfaceItem(item)
    }
    
    
    /// Updates the toggle state of the in-window Weekly Report Center and Document Center toolbar items.
    func validateCenterToolbarItem(_ item: NSToolbarItem) -> Bool {
        
        switch item.action {
            case #selector(toggleWeeklyReportCenter(_:)):
                (item as? StatableToolbarItem)?.state = (self.activeCenter == .weeklyReports) ? .on : .off
                return true
            case #selector(toggleDocumentCenter(_:)):
                (item as? StatableToolbarItem)?.state = (self.activeCenter == .documents) ? .on : .off
                return true
            default:
                return true
        }
    }
    
    
    // MARK: In-Window Workspace Centers (Weekly Reports & Documents)
    
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
    
    
    /// Opens Weekly Report Center or Document Center directly inside this window (no separate window).
    func showInWindowCenter(
        _ kind: WorkspaceCenterKind,
        weeklyMode: WeeklyReportWindowController.InitialMode = .history,
        selectingReportID: String? = nil
    ) {
        self.activeCenter = kind
        
        switch kind {
            case .weeklyReports:
                CotLocalDatabase.shared.reloadWeeklyReports()
                self.weeklyReportState.isGeneratorActive = (weeklyMode == .generator)
                if let selectingReportID {
                    self.weeklyReportState.selectedReportID = selectingReportID
                } else if self.weeklyReportState.selectedReportID == nil {
                    self.weeklyReportState.selectedReportID = CotLocalDatabase.shared.weeklyReports.first?.id
                }
                self.weeklyReportState.refreshOpenSources()
            case .documents:
                self.documentCenterState.refresh()
        }
        
        let rootView = self.makeCenterHostView(selectedKind: kind)
        if let existing = self.centerHostView {
            existing.rootView = rootView
            existing.isHidden = false
        } else {
            let hostingView = NSHostingView(rootView: rootView)
            hostingView.translatesAutoresizingMaskIntoConstraints = false
            self.view.addSubview(hostingView, positioned: .above, relativeTo: self.splitView)
            NSLayoutConstraint.activate([
                hostingView.leadingAnchor.constraint(equalTo: self.view.leadingAnchor),
                hostingView.trailingAnchor.constraint(equalTo: self.view.trailingAnchor),
                hostingView.topAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.topAnchor),
                hostingView.bottomAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.bottomAnchor),
            ])
            hostingView.alphaValue = 0
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.14
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                hostingView.animator().alphaValue = 1
            }
            self.centerHostView = hostingView
        }
        
        self.installCenterEscMonitor()
        self.view.window?.toolbar?.validateVisibleItems()
    }
    
    
    /// Closes any open in-window center and returns focus to the active editor pane.
    func hideInWindowCenter() {
        
        self.activeCenter = nil
        self.removeCenterEscMonitor()
        
        if let hostingView = self.centerHostView {
            self.centerHostView = nil
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.12
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                hostingView.animator().alphaValue = 0
            } completionHandler: { [weak hostingView] in
                Task { @MainActor in
                    hostingView?.removeFromSuperview()
                }
            }
        }
        
        self.view.window?.toolbar?.validateVisibleItems()
        if let textView = self.documentViewController?.focusedTextView {
            self.view.window?.makeFirstResponderDiscardingMarkedText(textView)
        }
    }
    
    
    private func makeCenterHostView(selectedKind: WorkspaceCenterKind) -> WorkspaceCenterHostView {
        
        WorkspaceCenterHostView(
            selectedKind: selectedKind,
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
            onOpenManagedDocument: { [weak self] liveDoc, record, splitRight in
                guard let self, let docVC = self.documentViewController else { return }
                if let liveDoc {
                    docVC.openOrFocusDocument(liveDoc, splitRight: splitRight)
                } else if let record {
                    docVC.openStoredDocumentRecord(record, splitRight: splitRight)
                }
                self.hideInWindowCenter()
            },
            onDeleteManagedDocument: { [weak self] item in
                self?.deleteManagedDocument(item)
            },
            onCreateNewDocument: { [weak self] in
                guard let self, let docVC = self.documentViewController else { return }
                if let created = try? (NSDocumentController.shared as? DocumentController)?.openUntitledDocumentAndDisplay(false) as? Document {
                    docVC.openOrFocusDocument(created, splitRight: false)
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
            
            CotLocalDatabase.shared.deleteDocument(id: item.dbRecordID ?? item.id, filePath: item.filePath)
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


private struct WorkspaceCenterHostView: View {
    
    let selectedKind: WorkspaceCenterKind
    let weeklyReportState: WeeklyReportCenterState
    let documentCenterState: DocumentCenterState
    
    var onDismiss: () -> Void
    var onOpenWeeklyReport: (StoredWeeklyReport) -> Void
    var onOpenManagedDocument: (Document?, StoredDocumentRecord?, _ splitRight: Bool) -> Void
    var onDeleteManagedDocument: (DocumentCenterState.ManagedDocumentItem) -> Void
    var onCreateNewDocument: () -> Void
    
    var body: some View {
        
        Group {
            switch self.selectedKind {
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
                        onDeleteDocument: self.onDeleteManagedDocument,
                        onCreateNewDocument: self.onCreateNewDocument,
                        onDismiss: self.onDismiss
                    )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor))
    }
}
