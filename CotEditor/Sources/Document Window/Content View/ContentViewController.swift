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
import SwiftUI

final class ContentViewController: NSSplitViewController {
    
    // MARK: Public Properties
    
    var document: DataDocument?  { didSet { self.updateDocument(from: oldValue) } }
    
    /// Whether the terminal panel is currently part of the window.
    var isTerminalVisible: Bool  { self.terminalItem != nil }
    
    var documentViewController: DocumentViewController? {
        
        self.splitViewItems.first?.viewController as? DocumentViewController
    }
    
    
    // MARK: Private Properties
    
    private var terminalItem: NSSplitViewItem?
    private var terminalViewController: TerminalViewController?
    private var windowCloseObserver: NSObjectProtocol?
    
    
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
    }
    
    
    isolated deinit {
        
        if let observer = self.windowCloseObserver {
            NotificationCenter.default.removeObserver(observer)
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
