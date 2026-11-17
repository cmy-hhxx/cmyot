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
        
        self.splitViewItems = [
            NSSplitViewItem(viewController: .viewController(document: document)),
        ]
    }
    
    
    required init?(coder: NSCoder) {
        
        fatalError("init(coder:) has not been implemented")
    }
    
    
    override func loadView() {
        
        let container = NSView()
        container.frame.size = NSSize(width: 640, height: 600)
        self.splitView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(self.splitView)
        self.view = container
    }
    
    
    override func viewDidLoad() {
        
        super.viewDidLoad()
        
        self.splitView.isVertical = false
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
            onSwitchKind: { [weak self] newKind in
                self?.showInWindowCenter(newKind)
            },
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
            onCreateNewDocument: { [weak self] in
                guard let self, let docVC = self.documentViewController else { return }
                if let created = try? (NSDocumentController.shared as? DocumentController)?.openUntitledDocumentAndDisplay(false) as? Document {
                    docVC.openOrFocusDocument(created, splitRight: false)
                }
                self.hideInWindowCenter()
            },
            onOpenDiskURLs: { [weak self] urls in
                guard let self, let docVC = self.documentViewController else { return }
                for url in urls {
                    if let existing = NSDocumentController.shared.document(for: url) as? Document {
                        docVC.openOrFocusDocument(existing, splitRight: false)
                    } else if let doc = try? Document(contentsOf: url, ofType: "public.plain-text") {
                        NSDocumentController.shared.addDocument(doc)
                        docVC.openOrFocusDocument(doc, splitRight: false)
                    }
                }
                self.hideInWindowCenter()
            }
        )
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
    
    var onSwitchKind: (WorkspaceCenterKind) -> Void
    var onDismiss: () -> Void
    var onOpenWeeklyReport: (StoredWeeklyReport) -> Void
    var onOpenManagedDocument: (Document?, StoredDocumentRecord?, _ splitRight: Bool) -> Void
    var onCreateNewDocument: () -> Void
    var onOpenDiskURLs: ([URL]) -> Void
    
    var body: some View {
        
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button {
                    self.onDismiss()
                } label: {
                    Label("返回编辑器", systemImage: "chevron.left")
                }
                .controlSize(.small)
                .keyboardShortcut(.cancelAction)
                
                Spacer()
                
                Picker("", selection: Binding(
                    get: { self.selectedKind },
                    set: { newKind in
                        if newKind != self.selectedKind {
                            self.onSwitchKind(newKind)
                        }
                    }
                )) {
                    ForEach(WorkspaceCenterKind.allCases) { kind in
                        Text(kind.rawValue).tag(kind)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 220)
                
                Spacer()
                
                Text("Esc 返回编辑")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .background(.bar)
            
            Divider()
            
            Group {
                switch self.selectedKind {
                    case .weeklyReports:
                        WeeklyReportCenterView(
                            state: self.weeklyReportState,
                            onOpenReport: self.onOpenWeeklyReport
                        )
                    case .documents:
                        DocumentCenterView(
                            state: self.documentCenterState,
                            onOpenDocument: self.onOpenManagedDocument,
                            onCreateNewDocument: self.onCreateNewDocument,
                            onOpenDiskURLs: self.onOpenDiskURLs
                        )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
