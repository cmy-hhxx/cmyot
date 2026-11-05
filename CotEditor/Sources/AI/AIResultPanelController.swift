//
//  AIResultPanelController.swift
//
//  CotEditor
//  https://coteditor.com
//
//  Created by 1024jp on 2026-11-05.
//
//  ---------------------------------------------------------------------------
//
//  © 2026 1024jp
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

/// The sheet that shows an AI answer and lets the user apply it.
///
/// The answer is never written into the document on its own: the user decides whether to
/// replace the selection, insert it at the caret, copy it, or throw it away.
final class AIResultPanelController: NSWindowController {
    
    // MARK: Public Properties
    
    /// Called with the answer when the user chooses to replace the selection.
    var onReplace: ((String) -> Void)?
    
    /// Called with the answer when the user chooses to insert it at the caret.
    var onInsert: ((String) -> Void)?
    
    
    // MARK: Private Properties
    
    private let action: AIAction
    private let titleLabel = NSTextField(labelWithString: "")
    private let statusLabel = NSTextField(labelWithString: "")
    private let textView = NSTextView()
    private let scrollView = NSScrollView()
    private let progressIndicator = NSProgressIndicator()
    private let replaceButton = NSButton(title: "替换选中", target: nil, action: nil)
    private let insertButton = NSButton(title: "插入", target: nil, action: nil)
    private let copyButton = NSButton(title: "拷贝", target: nil, action: nil)
    private let cancelButton = NSButton(title: "取消", target: nil, action: nil)
    
    
    // MARK: Lifecycle
    
    /// Creates the panel for one action.
    ///
    /// - Parameter action: The action whose answer will be shown.
    init(action: AIAction) {
        
        self.action = action
        
        let window = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 520, height: 380),
                             styleMask: [.titled, .resizable],
                             backing: .buffered,
                             defer: false)
        window.title = action.title
        window.isFloatingPanel = false
        window.hidesOnDeactivate = false
        
        super.init(window: window)
        
        self.buildContent()
        self.updateButtons(canApply: false)
    }
    
    
    required init?(coder: NSCoder) {
        
        fatalError("init(coder:) has not been implemented")
    }
    
    
    // MARK: Public Methods
    
    /// Shows the panel as a sheet on the given window, while the request runs.
    ///
    /// - Parameter parent: The window to attach to.
    func present(on parent: NSWindow) {
        
        guard let window else { return }
        
        self.titleLabel.stringValue = "正在请求「\(self.action.title)」…"
        self.statusLabel.stringValue = ""
        self.progressIndicator.startAnimation(nil)
        self.progressIndicator.isHidden = false
        
        parent.beginSheet(window)
    }
    
    
    /// Fills in the answer.
    ///
    /// - Parameter result: The answer text.
    func present(result: String) {
        
        self.progressIndicator.stopAnimation(nil)
        self.progressIndicator.isHidden = true
        self.titleLabel.stringValue = self.action.title
        self.statusLabel.stringValue = ""
        self.textView.string = result
        self.updateButtons(canApply: true)
    }
    
    
    /// Shows why the request failed.
    ///
    /// - Parameter error: The error to describe.
    func present(error: any Error) {
        
        self.progressIndicator.stopAnimation(nil)
        self.progressIndicator.isHidden = true
        self.titleLabel.stringValue = "「\(self.action.title)」没有完成"
        self.statusLabel.stringValue = error.localizedDescription
        self.textView.string = ""
        self.updateButtons(canApply: false)
    }
    
    
    // MARK: Private Methods
    
    /// Builds the sheet's views once.
    private func buildContent() {
        
        guard let contentView = self.window?.contentView else { return }
        
        self.titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        
        self.statusLabel.textColor = .secondaryLabelColor
        self.statusLabel.font = .systemFont(ofSize: 11)
        self.statusLabel.lineBreakMode = .byWordWrapping
        self.statusLabel.maximumNumberOfLines = 3
        
        self.progressIndicator.style = .spinning
        self.progressIndicator.controlSize = .small
        
        self.textView.isEditable = false
        self.textView.isRichText = false
        self.textView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        self.textView.textContainerInset = NSSize(width: 8, height: 8)
        self.textView.isAutomaticQuoteSubstitutionEnabled = false
        self.textView.isAutomaticDashSubstitutionEnabled = false
        self.textView.textContainer?.widthTracksTextView = true
        
        self.scrollView.documentView = self.textView
        self.scrollView.hasVerticalScroller = true
        self.scrollView.borderType = .bezelBorder
        self.scrollView.translatesAutoresizingMaskIntoConstraints = false
        
        self.replaceButton.target = self
        self.replaceButton.action = #selector(replace(_:))
        self.replaceButton.bezelStyle = .rounded
        self.replaceButton.keyEquivalent = "\r"
        
        self.insertButton.target = self
        self.insertButton.action = #selector(insert(_:))
        self.insertButton.bezelStyle = .rounded
        
        self.copyButton.target = self
        self.copyButton.action = #selector(copyResult(_:))
        self.copyButton.bezelStyle = .rounded
        
        self.cancelButton.target = self
        self.cancelButton.action = #selector(cancel(_:))
        self.cancelButton.bezelStyle = .rounded
        self.cancelButton.keyEquivalent = "\u{1b}"
        
        let buttons = NSStackView(views: [self.replaceButton, self.insertButton, self.copyButton, NSView(), self.cancelButton])
        buttons.orientation = .horizontal
        buttons.spacing = 8
        buttons.translatesAutoresizingMaskIntoConstraints = false
        
        let header = NSStackView(views: [self.titleLabel, NSView(), self.progressIndicator])
        header.orientation = .horizontal
        header.spacing = 8
        header.translatesAutoresizingMaskIntoConstraints = false
        
        contentView.addSubview(header)
        contentView.addSubview(self.statusLabel)
        contentView.addSubview(self.scrollView)
        contentView.addSubview(buttons)
        
        self.statusLabel.translatesAutoresizingMaskIntoConstraints = false
        
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 16),
            header.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            header.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            
            self.statusLabel.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 6),
            self.statusLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            self.statusLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            
            self.scrollView.topAnchor.constraint(equalTo: self.statusLabel.bottomAnchor, constant: 10),
            self.scrollView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            self.scrollView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            self.scrollView.bottomAnchor.constraint(equalTo: buttons.topAnchor, constant: -12),
            
            buttons.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            buttons.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            buttons.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -16),
        ])
    }
    
    
    /// Enables the apply buttons only when there is an answer.
    ///
    /// - Parameter canApply: Whether the answer can be applied.
    private func updateButtons(canApply: Bool) {
        
        self.replaceButton.isEnabled = canApply
        self.insertButton.isEnabled = canApply
        self.copyButton.isEnabled = canApply
    }
    
    
    /// Closes the sheet.
    private func dismiss() {
        
        guard let window, let parent = window.sheetParent else { return }
        
        parent.endSheet(window)
    }
    
    
    // MARK: Private Actions
    
    @objc private func replace(_ sender: Any?) {
        
        self.onReplace?(self.textView.string)
        self.dismiss()
    }
    
    
    @objc private func insert(_ sender: Any?) {
        
        self.onInsert?(self.textView.string)
        self.dismiss()
    }
    
    
    @objc private func copyResult(_ sender: Any?) {
        
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(self.textView.string, forType: .string)
    }
    
    
    @objc private func cancel(_ sender: Any?) {
        
        self.dismiss()
    }
}
