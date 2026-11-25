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
import SwiftUI
import WebKit

/// The sheet that shows an AI answer and lets the user apply it.
///
/// The answer is never written into the document on its own: the user decides whether to
/// replace the selection, insert it at the caret, copy it, or throw it away.
///
/// The sheet reads like a reply rather than like a log: a header names the action and the
/// service that answered, the body is rendered Markdown on a card, and the only buttons are the
/// four things the user can do with the text. When the reply or source carries an interactive
/// HTML chart, a live WebView chart sits above the text card.
final class AIResultPanelController: NSWindowController {
    
    // MARK: Public Properties
    
    /// Whether the Replace button will overwrite the entire document instead of a selection.
    var replacesWholeDocument = false {
        didSet {
            let title = self.replacesWholeDocument
                ? AppLanguage.text("替换全文", en: "Replace Document")
                : String(localized: "ai.result.replace", defaultValue: "Replace Selection", table: "AI")
            self.replaceButton.title = title
        }
    }
    
    /// Called with the answer when the user chooses to replace the selection.
    var onReplace: ((String) -> Void)?
    
    /// Called with the answer when the user chooses to insert it at the caret.
    var onInsert: ((String) -> Void)?
    
    /// Called with the answer when the user chooses to hand off the result to the Butler Hub for multi-turn follow-up.
    var onContinueInButler: ((String) -> Void)?
    
    /// Called when the user cancels/dismisses the sheet so in-flight AI tasks stop immediately.
    var onCancel: (() -> Void)?
    
    
    // MARK: Private Properties
    
    private let action: AIAction
    private var answer = ""
    private var copyResetTask: Task<Void, Never>?
    private var lastPartialRenderTime: Date = .distantPast
    private var partialRenderTask: Task<Void, Never>?
    private var pendingPartialText: String?
    /// Set as soon as the request resolves, so a late streamed chunk can never revive the
    /// "generating" state or overwrite the finished answer.
    private var hasFinished = false
    
    private let subtitleLabel = NSTextField(labelWithString: "")
    private let orbHost = NSHostingView(rootView: ThinkingOrbsParticleView(mode: .composing, size: 20, paused: true))
    private let textView = NSTextView()
    private let scrollView = NSScrollView()
    private let cardView = AIResultCardView()
    private let chartCardView = AIResultCardView()
    private let webView = WKWebView(frame: .zero)
    private var chartHeightConstraint: NSLayoutConstraint?
    private let replaceButton = NSButton(title: "", target: nil, action: nil)
    private let insertButton = NSButton(title: "", target: nil, action: nil)
    private let copyButton = NSButton(title: "", target: nil, action: nil)
    private let saveReportButton = NSButton(title: "", target: nil, action: nil)
    private let continueButlerButton = NSButton(title: "", target: nil, action: nil)
    private let cancelButton = NSButton(title: "", target: nil, action: nil)
    
    
    // MARK: Lifecycle
    
    /// Creates the panel for one action.
    ///
    /// - Parameter action: The action whose answer will be shown.
    init(action: AIAction) {
        
        self.action = action
        
        let isChart = (action == .interactiveChart)
        let window = NSPanel(contentRect: NSRect(x: 0, y: 0, width: isChart ? 680 : 560, height: isChart ? 560 : 420),
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
        
        self.hasFinished = false
        self.continueButlerButton.isHidden = (self.onContinueInButler == nil)
        self.subtitleLabel.stringValue = self.serviceDescription
        self.orbHost.rootView = ThinkingOrbsParticleView(mode: .composing, size: 20, paused: false)
        self.orbHost.isHidden = false
        self.setText(Self.placeholder(String(localized: "ai.result.generating",
                                             defaultValue: "Generating…",
                                             table: "AI")))
        self.updateButtons(canApply: false)
        
        parent.beginSheet(window)
    }
    
    
    /// Updates the panel with a progressive streaming chunk while the request is still running.
    ///
    /// Throttles Markdown reflow so rapid token streams never block the main thread.
    ///
    /// - Parameter partial: The accumulated answer text so far.
    func presentPartial(result partial: String) {
        
        guard !self.hasFinished else { return }
        
        let trimmed = partial.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        
        self.pendingPartialText = trimmed
        let elapsed = Date().timeIntervalSince(self.lastPartialRenderTime)
        if elapsed >= 0.08 {
            self.flushPendingPartial()
        } else if self.partialRenderTask == nil {
            self.partialRenderTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(80))
                guard let self, !Task.isCancelled else { return }
                self.partialRenderTask = nil
                self.flushPendingPartial()
            }
        }
    }
    
    
    private func flushPendingPartial() {
        
        guard let trimmed = self.pendingPartialText, !trimmed.isEmpty else { return }
        self.pendingPartialText = nil
        self.lastPartialRenderTime = .now
        let display: String = if self.action.outputsStructuredPlainText {
            AIDocumentTextCleaner.cleanStructuredPlainText(trimmed)
        } else if self.action.outputsPlainDocumentText {
            AIDocumentTextCleaner.clean(trimmed)
        } else {
            trimmed
        }
        self.answer = display
        let formatted = self.action.outputsStructuredPlainText
            ? AIAnswerFormatter.structuredPlainTextAttributedString(from: display)
            : AIAnswerFormatter.attributedString(from: display)
        self.setText(formatted)
        self.updateButtons(canApply: true)
    }
    
    
    /// Displays an interactive HTML chart inside the top chart card.
    ///
    /// - Parameter html: Complete HTML document string.
    func presentChart(html: String) {
        
        self.chartCardView.isHidden = false
        self.chartHeightConstraint?.constant = 290
        self.webView.loadHTMLString(html, baseURL: nil)
    }
    
    
    /// Fills in the answer.
    ///
    /// - Parameter result: The answer text.
    func present(result: String) {
        
        self.hasFinished = true
        self.partialRenderTask?.cancel()
        self.partialRenderTask = nil
        self.pendingPartialText = nil
        
        let rawText: String = if self.action.outputsStructuredPlainText {
            AIDocumentTextCleaner.cleanStructuredPlainText(result)
        } else if self.action.outputsPlainDocumentText {
            AIDocumentTextCleaner.clean(result)
        } else {
            result
        }
        let raw = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        self.orbHost.rootView = ThinkingOrbsParticleView(mode: .composing, size: 20, paused: true)
        self.orbHost.isHidden = true
        
        // If the AI returned a fenced ```html block, render it in the interactive chart WebView
        if let extractedHTML = Self.extractHTMLBlock(from: raw) {
            self.presentChart(html: extractedHTML.html)
            let cleanedText = extractedHTML.remainingMarkdown.isEmpty ? raw : extractedHTML.remainingMarkdown
            self.answer = MarkdownTableFormatter.formatTables(in: cleanedText)
        } else if self.action.outputsStructuredPlainText {
            self.answer = raw
        } else {
            self.answer = MarkdownTableFormatter.formatTables(in: raw)
        }
        
        let formatted = self.action.outputsStructuredPlainText
            ? AIAnswerFormatter.structuredPlainTextAttributedString(from: self.answer)
            : AIAnswerFormatter.attributedString(from: self.answer)
        self.setText(formatted)
        self.updateButtons(canApply: !self.answer.isEmpty)
        self.scrollView.contentView.scroll(to: .zero)
        self.scrollView.reflectScrolledClipView(self.scrollView.contentView)
    }
    
    
    /// Shows why the request failed.
    ///
    /// - Parameter error: The error to describe.
    func present(error: any Error) {
        
        self.hasFinished = true
        self.partialRenderTask?.cancel()
        self.partialRenderTask = nil
        self.pendingPartialText = nil
        
        CotLogger.shared.error(
            category: .ai,
            "AI action UI error",
            error: error,
            context: ["action": self.action.title]
        )
        
        self.answer = ""
        self.orbHost.rootView = ThinkingOrbsParticleView(mode: .composing, size: 20, paused: true)
        self.orbHost.isHidden = true
        self.setText(Self.failureMessage(title: self.action.title, error: error))
        self.updateButtons(canApply: false)
    }
    
    
    // MARK: Private Methods
    
    /// The line under the header that names where the answer came from for this Bot/action.
    private var serviceDescription: String {
        let botID = AIBotID(action: self.action)
        let profile = AIBotStore.shared.resolvedEndpointProfile(for: botID) ?? AIEndpointStore.activeProfile
        let resolvedModel = AIBotStore.shared.resolvedConfiguration(for: botID).model
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let profile else { return resolvedModel }
        let model = resolvedModel.isEmpty ? profile.model.trimmingCharacters(in: .whitespacesAndNewlines) : resolvedModel
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
        
        self.orbHost.translatesAutoresizingMaskIntoConstraints = false
        self.orbHost.isHidden = true
        self.orbHost.setContentHuggingPriority(.required, for: .horizontal)
        
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
        
        let header = NSStackView(views: [titleStack, NSView(), self.orbHost])
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
        self.configureButton(self.saveReportButton,
                             title: String(localized: "ai.result.saveToWeeklyReports",
                                           defaultValue: "存入周报库", table: "AI"),
                             tooltip: "保存这篇周报到顶部「周报」菜单的历史库中",
                             action: #selector(saveToWeeklyReports(_:)))
        self.saveReportButton.isHidden = (self.action != .weeklyReport)
        self.configureButton(self.continueButlerButton,
                             title: AppLanguage.text("转交总管继续聊", en: "Continue in Butler"),
                             tooltip: AppLanguage.text("带着当前结果进入总管多轮对话继续修改或深挖", en: "Continue discussing and refining this result in Butler"),
                             action: #selector(continueInButler(_:)))
        self.continueButlerButton.isHidden = (self.onContinueInButler == nil)
        self.configureButton(self.cancelButton,
                             title: String(localized: "ai.result.cancel",
                                           defaultValue: "Cancel", table: "AI"),
                             tooltip: nil,
                             action: #selector(cancel(_:)), keyEquivalent: "\u{1b}")
        
        // macOS reads a button row from the escape hatch to the commit, and keeps it against
        // the trailing edge: 转交总管继续聊 · 取消 · 存入周报库 · 拷贝 · 插入 · 替换选中.
        let buttons = NSStackView(views: [self.continueButlerButton, self.cancelButton, self.saveReportButton,
                                          self.copyButton, self.insertButton, self.replaceButton])
        buttons.orientation = .horizontal
        buttons.spacing = 10
        buttons.translatesAutoresizingMaskIntoConstraints = false
        
        self.webView.translatesAutoresizingMaskIntoConstraints = false
        self.webView.setValue(false, forKey: "drawsBackground")
        self.chartCardView.translatesAutoresizingMaskIntoConstraints = false
        self.chartCardView.isHidden = true
        self.chartCardView.addSubview(self.webView)
        
        let chartHeight = self.chartCardView.heightAnchor.constraint(equalToConstant: 0)
        self.chartHeightConstraint = chartHeight
        
        let bodyStack = NSStackView(views: [self.chartCardView, self.cardView])
        bodyStack.orientation = .vertical
        bodyStack.spacing = 10
        bodyStack.alignment = .width
        bodyStack.translatesAutoresizingMaskIntoConstraints = false
        
        contentView.addSubview(header)
        contentView.addSubview(bodyStack)
        contentView.addSubview(buttons)
        
        NSLayoutConstraint.activate([
            self.orbHost.widthAnchor.constraint(equalToConstant: 20),
            self.orbHost.heightAnchor.constraint(equalToConstant: 20),
            header.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 16),
            header.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            header.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            
            bodyStack.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 12),
            bodyStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            bodyStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            bodyStack.bottomAnchor.constraint(equalTo: buttons.topAnchor, constant: -12),
            
            chartHeight,
            self.webView.topAnchor.constraint(equalTo: self.chartCardView.topAnchor, constant: 1),
            self.webView.leadingAnchor.constraint(equalTo: self.chartCardView.leadingAnchor, constant: 1),
            self.webView.trailingAnchor.constraint(equalTo: self.chartCardView.trailingAnchor, constant: -1),
            self.webView.bottomAnchor.constraint(equalTo: self.chartCardView.bottomAnchor, constant: -1),
            
            self.scrollView.topAnchor.constraint(equalTo: self.cardView.topAnchor, constant: 1),
            self.scrollView.leadingAnchor.constraint(equalTo: self.cardView.leadingAnchor, constant: 1),
            self.scrollView.trailingAnchor.constraint(equalTo: self.cardView.trailingAnchor, constant: -1),
            self.scrollView.bottomAnchor.constraint(equalTo: self.cardView.bottomAnchor, constant: -1),
            
            buttons.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            buttons.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -16),
        ])
    }
    
    
    /// Extracts a fenced `html` code block from a Markdown response, if present.
    private static func extractHTMLBlock(from markdown: String) -> (html: String, remainingMarkdown: String)? {
        
        let pattern = "```(?:html|HTML)\\s*\\n([\\s\\S]*?)```"
        guard
            let regex = try? NSRegularExpression(pattern: pattern),
            let match = regex.firstMatch(in: markdown, range: NSRange(location: 0, length: (markdown as NSString).length)),
            match.numberOfRanges >= 2
        else { return nil }
        
        let nsString = markdown as NSString
        let html = nsString.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
        guard html.contains("<") else { return nil }
        
        let remaining = nsString.replacingCharacters(in: match.range, with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (html, remaining)
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
        self.saveReportButton.isEnabled = canApply
        self.continueButlerButton.isEnabled = canApply
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
    
    
    @objc private func saveToWeeklyReports(_ sender: Any?) {
        
        let trimmed = self.answer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        
        CotLocalDatabase.shared.saveGeneratedWeeklyReport(content: trimmed)
        self.saveReportButton.title = "已存入周报库 ✓"
        self.saveReportButton.isEnabled = false
    }
    
    
    @objc private func continueInButler(_ sender: Any?) {
        let currentAnswer = self.answer
        let handler = self.onContinueInButler
        self.dismiss()
        if let handler {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                handler(currentAnswer)
            }
        }
    }
    
    
    @objc private func cancel(_ sender: Any?) {
        
        self.hasFinished = true
        self.partialRenderTask?.cancel()
        self.partialRenderTask = nil
        self.onCancel?()
        self.onCancel = nil
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
            layer.cornerRadius = 12
            layer.cornerCurve = .continuous
            layer.backgroundColor = NSColor.textBackgroundColor.cgColor
            layer.borderWidth = 1
            layer.borderColor = NSColor.separatorColor.withAlphaComponent(0.55).cgColor
        }
    }
}
