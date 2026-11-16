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
///
/// The sheet reads like a reply rather than like a log: a header names the action and the
/// service that answered, the body is rendered Markdown on a card, and the only buttons are the
/// four things the user can do with the text.
final class AIResultPanelController: NSWindowController {
    
    // MARK: Public Properties
    
    /// Called with the answer when the user chooses to replace the selection.
    var onReplace: ((String) -> Void)?
    
    /// Called with the answer when the user chooses to insert it at the caret.
    var onInsert: ((String) -> Void)?
    
    
    // MARK: Private Properties
    
    private let action: AIAction
    private var answer = ""
    private var copyResetTask: Task<Void, Never>?
    
    private let subtitleLabel = NSTextField(labelWithString: "")
    private let spinner = NSProgressIndicator()
    private let textView = NSTextView()
    private let scrollView = NSScrollView()
    private let cardView = AIResultCardView()
    private let replaceButton = NSButton(title: "", target: nil, action: nil)
    private let insertButton = NSButton(title: "", target: nil, action: nil)
    private let copyButton = NSButton(title: "", target: nil, action: nil)
    private let cancelButton = NSButton(title: "", target: nil, action: nil)
    
    
    // MARK: Lifecycle
    
    /// Creates the panel for one action.
    ///
    /// - Parameter action: The action whose answer will be shown.
    init(action: AIAction) {
        
        self.action = action
        
        let window = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 560, height: 420),
                             styleMask: [.titled, .resizable],
                             backing: .buffered,
                             defer: false)
        window.title = action.title
        window.isFloatingPanel = false
        window.hidesOnDeactivate = false
        window.contentMinSize = NSSize(width: 460, height: 320)
        
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
        
        self.subtitleLabel.stringValue = Self.serviceDescription
        self.spinner.startAnimation(nil)
        self.spinner.isHidden = false
        self.setText(Self.placeholder(String(localized: "ai.result.generating",
                                             defaultValue: "Generating…",
                                             table: "AI")))
        self.updateButtons(canApply: false)
        
        parent.beginSheet(window)
    }
    
    
    /// Fills in the answer.
    ///
    /// - Parameter result: The answer text.
    func present(result: String) {
        
        self.answer = result.trimmingCharacters(in: .whitespacesAndNewlines)
        self.spinner.stopAnimation(nil)
        self.spinner.isHidden = true
        self.setText(AIAnswerFormatter.attributedString(from: self.answer))
        self.updateButtons(canApply: !self.answer.isEmpty)
        self.scrollView.contentView.scroll(to: .zero)
        self.scrollView.reflectScrolledClipView(self.scrollView.contentView)
    }
    
    
    /// Shows why the request failed.
    ///
    /// - Parameter error: The error to describe.
    func present(error: any Error) {
        
        self.answer = ""
        self.spinner.stopAnimation(nil)
        self.spinner.isHidden = true
        self.setText(Self.failureMessage(title: self.action.title, error: error))
        self.updateButtons(canApply: false)
    }
    
    
    // MARK: Private Methods
    
    /// The line under the header that names where the answer came from.
    private static var serviceDescription: String {
        
        guard let profile = AIEndpointStore.activeProfile else { return "" }
        
        let model = profile.model.trimmingCharacters(in: .whitespacesAndNewlines)
        
        return model.isEmpty ? profile.displayName : "\(profile.displayName) · \(model)"
    }
    
    
    /// Builds the sheet's views once.
    private func buildContent() {
        
        guard let contentView = self.window?.contentView else { return }
        
        // The action's name is already the sheet's title, so this line only says where the
        // answer comes from.
        self.subtitleLabel.font = .systemFont(ofSize: 11)
        self.subtitleLabel.textColor = .secondaryLabelColor
        self.subtitleLabel.lineBreakMode = .byTruncatingMiddle
        
        self.spinner.style = .spinning
        self.spinner.controlSize = .small
        self.spinner.isHidden = true
        
        self.cardView.translatesAutoresizingMaskIntoConstraints = false
        
        self.textView.isEditable = false
        self.textView.isSelectable = true
        self.textView.drawsBackground = false
        self.textView.isRichText = true
        self.textView.textContainerInset = NSSize(width: 14, height: 12)
        self.textView.isAutomaticQuoteSubstitutionEnabled = false
        self.textView.isAutomaticDashSubstitutionEnabled = false
        self.textView.minSize = .zero
        self.textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        self.textView.isVerticallyResizable = true
        self.textView.isHorizontallyResizable = false
        self.textView.autoresizingMask = [.width]
        self.textView.textContainer?.widthTracksTextView = true
        self.textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        self.textView.delegate = self
        
        self.scrollView.documentView = self.textView
        self.scrollView.hasVerticalScroller = true
        self.scrollView.drawsBackground = false
        self.scrollView.borderType = .noBorder
        self.scrollView.scrollerStyle = .overlay
        self.scrollView.translatesAutoresizingMaskIntoConstraints = false
        
        self.cardView.addSubview(self.scrollView)
        
        let titleLabel = NSTextField(labelWithString: self.action.title)
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        
        let titleStack = NSStackView(views: [titleLabel, self.subtitleLabel])
        titleStack.orientation = .vertical
        titleStack.alignment = .leading
        titleStack.spacing = 2
        
        let header = NSStackView(views: [titleStack, NSView(), self.spinner])
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 8
        header.translatesAutoresizingMaskIntoConstraints = false
        
        self.configureButton(self.replaceButton,
                             title: String(localized: "ai.result.replace",
                                           defaultValue: "Replace Selection", table: "AI"),
                             tooltip: String(localized: "ai.result.replace.tooltip",
                                             defaultValue: "Replace the selected text; ⌘Z undoes it",
                                             table: "AI"),
                             action: #selector(replace(_:)), keyEquivalent: "\r")
        self.configureButton(self.insertButton,
                             title: String(localized: "ai.result.insert",
                                           defaultValue: "Insert", table: "AI"),
                             tooltip: String(localized: "ai.result.insert.tooltip",
                                             defaultValue: "Insert at the cursor",
                                             table: "AI"),
                             action: #selector(insert(_:)))
        self.configureButton(self.copyButton,
                             title: String(localized: "ai.result.copy",
                                           defaultValue: "Copy", table: "AI"),
                             tooltip: String(localized: "ai.result.copy.tooltip",
                                             defaultValue: "Copy the whole answer",
                                             table: "AI"),
                             action: #selector(copyResult(_:)))
        self.configureButton(self.cancelButton,
                             title: String(localized: "ai.result.cancel",
                                           defaultValue: "Cancel", table: "AI"),
                             tooltip: nil,
                             action: #selector(cancel(_:)), keyEquivalent: "\u{1b}")
        
        // macOS reads a button row from the escape hatch to the commit, and keeps it against
        // the trailing edge: 取消 · 拷贝 · 插入 · 替换选中.
        let buttons = NSStackView(views: [self.cancelButton, self.copyButton,
                                          self.insertButton, self.replaceButton])
        buttons.orientation = .horizontal
        buttons.spacing = 10
        buttons.translatesAutoresizingMaskIntoConstraints = false
        
        contentView.addSubview(header)
        contentView.addSubview(self.cardView)
        contentView.addSubview(buttons)
        
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 16),
            header.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            header.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            
            self.cardView.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 12),
            self.cardView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            self.cardView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            self.cardView.bottomAnchor.constraint(equalTo: buttons.topAnchor, constant: -12),
            
            self.scrollView.topAnchor.constraint(equalTo: self.cardView.topAnchor, constant: 1),
            self.scrollView.leadingAnchor.constraint(equalTo: self.cardView.leadingAnchor, constant: 1),
            self.scrollView.trailingAnchor.constraint(equalTo: self.cardView.trailingAnchor, constant: -1),
            self.scrollView.bottomAnchor.constraint(equalTo: self.cardView.bottomAnchor, constant: -1),
            
            buttons.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            buttons.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -16),
        ])
    }
    
    
    /// Configures one of the sheet's buttons.
    ///
    /// The buttons are `large`: at this size they are easy to hit without the row looking like
    /// a toolbar, and the default one clearly outweighs the others.
    ///
    /// - Parameters:
    ///   - button: The button to configure.
    ///   - title: Its title.
    ///   - tooltip: What the button does, for the case where the title alone is ambiguous.
    ///   - action: The action it sends.
    ///   - keyEquivalent: Its key equivalent, if it has one.
    private func configureButton(
        _ button: NSButton,
        title: String,
        tooltip: String?,
        action: Selector,
        keyEquivalent: String = ""
    ) {
        
        button.title = title
        button.target = self
        button.action = action
        button.bezelStyle = .rounded
        button.controlSize = .large
        button.keyEquivalent = keyEquivalent
        button.toolTip = tooltip
        button.translatesAutoresizingMaskIntoConstraints = false
    }
    
    
    /// Replaces the card's content.
    ///
    /// - Parameter text: The attributed text to show.
    private func setText(_ text: NSAttributedString) {
        
        self.textView.textStorage?.setAttributedString(text)
    }
    
    
    /// Renders a muted one-line status inside the card.
    private static func placeholder(_ text: String) -> NSAttributedString {
        
        NSAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: 13),
            .foregroundColor: NSColor.tertiaryLabelColor,
        ])
    }
    
    
    /// Renders the failure state: what did not finish, and why.
    private static func failureMessage(title: String, error: any Error) -> NSAttributedString {
        
        let headline = String(format: String(localized: "ai.result.failed",
                                             defaultValue: "“%@” did not finish",
                                             table: "AI"),
                              title)
        let message = NSMutableAttributedString(string: headline + "\n", attributes: [
            .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
            .foregroundColor: NSColor.labelColor,
        ])
        message.append(NSAttributedString(string: error.localizedDescription, attributes: [
            .font: NSFont.systemFont(ofSize: 12),
            .foregroundColor: NSColor.secondaryLabelColor,
        ]))
        
        return message
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
        
        self.copyResetTask?.cancel()
        
        guard let window, let parent = window.sheetParent else { return }
        
        parent.endSheet(window)
    }
    
    
    // MARK: Private Actions
    
    @objc private func replace(_ sender: Any?) {
        
        self.onReplace?(self.answer)
        self.dismiss()
    }
    
    
    @objc private func insert(_ sender: Any?) {
        
        self.onInsert?(self.answer)
        self.dismiss()
    }
    
    
    @objc private func copyResult(_ sender: Any?) {
        
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(self.answer, forType: .string)
        
        // Say that it worked, then go back to the normal title: a second click should look
        // like it did the first time.
        let title = self.copyButton.title
        self.copyButton.title = String(localized: "ai.result.copied", defaultValue: "Copied", table: "AI")
        self.copyResetTask?.cancel()
        self.copyResetTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            
            self?.copyButton.title = title
        }
    }
    
    
    @objc private func cancel(_ sender: Any?) {
        
        self.dismiss()
    }
}


// MARK: - Text View Delegate

extension AIResultPanelController: NSTextViewDelegate {
    
    /// Opens a link the answer carries in the browser instead of leaking it to the editor.
    func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
        
        guard let url = link as? URL else { return false }
        
        NSWorkspace.shared.open(url)
        
        return true
    }
}


/// The rounded panel the answer sits on.
///
/// A plain `NSScrollView` with a bezel reads as a debug dump; a card with the text background
/// and a hairline border reads as content, and it gives the text the padding it needs.
final class AIResultCardView: NSView {
    
    override init(frame frameRect: NSRect) {
        
        super.init(frame: frameRect)
        
        self.wantsLayer = true
        self.updateColors()
    }
    
    
    @available(*, unavailable)
    required init?(coder: NSCoder) {
        
        fatalError("init(coder:) has not been implemented")
    }
    
    
    override func viewDidChangeEffectiveAppearance() {
        
        super.viewDidChangeEffectiveAppearance()
        
        self.updateColors()
    }
    
    
    private func updateColors() {
        
        guard let layer else { return }
        
        self.effectiveAppearance.performAsCurrentDrawingAppearance {
            layer.cornerRadius = 10
            layer.cornerCurve = .continuous
            layer.backgroundColor = NSColor.textBackgroundColor.cgColor
            layer.borderWidth = 1
            layer.borderColor = NSColor.separatorColor.cgColor
        }
    }
}
