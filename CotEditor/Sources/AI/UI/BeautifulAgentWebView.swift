//
//  BeautifulAgentWebView.swift
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
import Foundation
import SwiftUI
import WebKit

// MARK: - Serializable Bridge Payloads (Matches WebUI/beautiful-agent/src/types.ts)

nonisolated struct BeautifulAgentThinkingStep: Codable, Equatable, Hashable, Identifiable, Sendable {
    var id: String
    var label: String
    var chip: String?
    var status: String // "running" | "done" | "error"
    var mono: Bool
    var detail: [String]?
    var durationMs: Int?
    
    init(
        id: String = UUID().uuidString,
        label: String,
        chip: String? = nil,
        status: String = "running",
        mono: Bool = false,
        detail: [String]? = nil,
        durationMs: Int? = nil
    ) {
        self.id = id
        self.label = label
        self.chip = chip
        self.status = status
        self.mono = mono
        self.detail = detail
        self.durationMs = durationMs
    }
}


nonisolated struct BeautifulAgentToolReceipt: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var label: String
    var detail: String?
    var status: String? // "done" | "error"
    
    init(id: String = UUID().uuidString, label: String, detail: String? = nil, status: String? = "done") {
        self.id = id
        self.label = label
        self.detail = detail
        self.status = status
    }
}


nonisolated struct BeautifulAgentMessagePayload: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var role: String // "user" | "assistant"
    var text: String
    var thinking: String?
    var thinkingDurationMs: Int?
    var steps: [BeautifulAgentThinkingStep]?
    var toolChips: [BeautifulAgentToolReceipt]?
    var followUps: [String]?
    var isStreaming: Bool?
    var isError: Bool?
    var quoteContext: String?
    var createdAt: Double?
}


nonisolated struct BeautifulAgentSessionPayload: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var title: String
    var isPinned: Bool
    var messageCount: Int?
    var updatedAt: Double?
}


nonisolated struct BeautifulAgentModelPayload: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var modelID: String
    var title: String
    var endpointID: String?
    var tag: String?
    var isFlagship: Bool?
}


nonisolated struct BeautifulAgentSuggestionPayload: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var label: String
    var prompt: String
    var icon: String?
}


nonisolated struct BeautifulAgentContextSourcePayload: Codable, Equatable, Sendable {
    var key: String
    var name: String
    var desc: String
    var glyph: String
    var insertText: String
}


nonisolated struct BeautifulAgentSlashCommandPayload: Codable, Equatable, Sendable {
    var key: String
    var name: String
    var desc: String
    var insertText: String
}


nonisolated struct BeautifulAgentHostStatePayload: Codable, Equatable, Sendable {
    var mode: String // "butler" | "news"
    var isDark: Bool
    var locale: String // "zh" | "en"
    var botName: String
    var botNickname: String
    var botAvatarDataURL: String?
    var piAvailable: Bool
    var piStatusLabel: String?
    var isPinnedPanel: Bool?
    var isDockedPane: Bool?
    var showSidebar: Bool?
    var sessions: [BeautifulAgentSessionPayload]
    var activeSessionID: String
    var messages: [BeautifulAgentMessagePayload]
    var isStreaming: Bool
    var streamingStatusLabel: String?
    var errorMessage: String?
    var placeholder: String
    var greetingName: String?
    var greetingSubtitle: String?
    var articleTitle: String?
    var articleSource: String?
    var quotedExcerpt: String?
    var availableModels: [BeautifulAgentModelPayload]
    var selectedModelID: String
    var selectedModelTitle: String
    var effort: String? // "simple" | "balanced" | "deep"
    var suggestions: [BeautifulAgentSuggestionPayload]
    var contextSources: [BeautifulAgentContextSourcePayload]
    var slashCommands: [BeautifulAgentSlashCommandPayload]
}


nonisolated struct BeautifulAgentStreamPatchPayload: Codable, Equatable, Sendable {
    var messageId: String
    var text: String?
    var thinking: String?
    var thinkingDurationMs: Int?
    var steps: [BeautifulAgentThinkingStep]?
    var statusLabel: String?
}


// MARK: - Native Actions Emitted by the Beautiful UI React App

struct BeautifulAgentWebActionCallbacks {
    var onSend: (String, String) -> Void = { _, _ in } // (prompt, quote)
    var onAbort: () -> Void = { }
    var onRetry: () -> Void = { }
    var onClearChat: () -> Void = { }
    var onClearQuote: () -> Void = { }
    var onSelectModel: (BeautifulAgentModelPayload) -> Void = { _ in }
    var onSelectEffort: (String) -> Void = { _ in }
    var onNewSession: () -> Void = { }
    var onSelectSession: (String) -> Void = { _ in }
    var onDeleteSession: (String) -> Void = { _ in }
    var onRenameSession: (String, String) -> Void = { _, _ in }
    var onTogglePinSession: (String) -> Void = { _ in }
    var onInsertToEditor: (String) -> Void = { _ in }
    var onOpenNewDocument: (String) -> Void = { _ in }
    var onOpenSettings: (String) -> Void = { _ in }
    var onTogglePinPanel: () -> Void = { }
    var onDockToPane: () -> Void = { }
    var onQuickAction: (String) -> Void = { _ in }
}


// MARK: - Imperative High-Frequency Bridge Controller (60fps Stream Patches + Draft Injection)

@MainActor
final class BeautifulAgentWebController {
    
    fileprivate weak var webView: WKWebView?
    fileprivate var isBridgeReady: Bool = false
    fileprivate var pendingStateJSON: String?
    fileprivate var lastPushedState: BeautifulAgentHostStatePayload?
    fileprivate var pendingDraftInjection: (text: String, quote: String?)?
    fileprivate var pendingFocusComposer: Bool = false
    
    private static let encoder: JSONEncoder = {
        let enc = JSONEncoder()
        return enc
    }()
    
    
    func syncState(_ state: BeautifulAgentHostStatePayload, force: Bool = false) {
        if !force, self.lastPushedState == state {
            return
        }
        self.lastPushedState = state
        guard let json = Self.encodeJSON(state) else { return }
        if self.isBridgeReady, let webView = self.webView {
            webView.evaluateJavaScript("window.CotAgentBridge && window.CotAgentBridge.setState(\(json));", completionHandler: nil)
        } else {
            self.pendingStateJSON = json
        }
    }
    
    
    func pushStreamPatch(_ patch: BeautifulAgentStreamPatchPayload) {
        guard self.isBridgeReady, let webView = self.webView,
              let json = Self.encodeJSON(patch)
        else { return }
        webView.evaluateJavaScript("window.CotAgentBridge && window.CotAgentBridge.patchStreaming(\(json));", completionHandler: nil)
    }
    
    
    func injectDraft(_ text: String, quote: String? = nil) {
        if self.isBridgeReady, let webView = self.webView {
            let textJSON = Self.encodeJSON(text) ?? "\"\""
            let quoteJSON = quote.flatMap { Self.encodeJSON($0) } ?? "null"
            webView.evaluateJavaScript(
                "window.CotAgentBridge && window.CotAgentBridge.injectDraft(\(textJSON), \(quoteJSON));",
                completionHandler: nil
            )
        } else {
            self.pendingDraftInjection = (text, quote)
        }
    }
    
    
    func focusComposer() {
        if self.isBridgeReady, let webView = self.webView {
            webView.evaluateJavaScript("window.CotAgentBridge && window.CotAgentBridge.focusComposer();", completionHandler: nil)
        } else {
            self.pendingFocusComposer = true
        }
    }
    
    
    fileprivate func markReady() {
        self.isBridgeReady = true
        if let pendingStateJSON {
            self.pendingStateJSON = nil
            self.webView?.evaluateJavaScript(
                "window.CotAgentBridge && window.CotAgentBridge.setState(\(pendingStateJSON));",
                completionHandler: nil
            )
        } else if let last = self.lastPushedState, let json = Self.encodeJSON(last) {
            self.webView?.evaluateJavaScript(
                "window.CotAgentBridge && window.CotAgentBridge.setState(\(json));",
                completionHandler: nil
            )
        }
        if let draft = self.pendingDraftInjection {
            self.pendingDraftInjection = nil
            self.injectDraft(draft.text, quote: draft.quote)
        }
        if self.pendingFocusComposer {
            self.pendingFocusComposer = false
            self.focusComposer()
        }
    }
    
    
    private static func encodeJSON<T: Encodable>(_ value: T) -> String? {
        guard let data = try? Self.encoder.encode(value),
              let raw = String(data: data, encoding: .utf8)
        else { return nil }
        // Escape U+2028/U+2029 so evaluateJavaScript never splits JS literals
        return raw
            .replacingOccurrences(of: "\u{2028}", with: "\\u2028")
            .replacingOccurrences(of: "\u{2029}", with: "\\u2029")
    }
}


// MARK: - Resource Loader & Avatar Helper

enum BeautifulAgentUIBundle {
    
    private static var cachedHTML: String?
    
    static func htmlDocument() -> String {
        if let cached = self.cachedHTML {
            return cached
        }
        let bundles = [Bundle.main, Bundle(for: BeautifulAgentWebController.self)]
        for bundle in bundles {
            if let url = bundle.url(forResource: "BeautifulAgentUI", withExtension: "html"),
               let content = try? String(contentsOf: url, encoding: .utf8),
               !content.isEmpty
            {
                self.cachedHTML = content
                return content
            }
        }
        return """
        <!doctype html>
        <html><body style="font-family:-apple-system,sans-serif;padding:24px;color:#666;">
        BeautifulAgentUI.html not found in application bundle.
        </body></html>
        """
    }
    
    
    @MainActor
    static func avatarDataURL(from image: NSImage?) -> String? {
        guard let image,
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:])
        else { return nil }
        return "data:image/png;base64,\(png.base64EncodedString())"
    }
}


// MARK: - SwiftUI NSViewRepresentable Host

struct BeautifulAgentWebView: NSViewRepresentable {
    
    let state: BeautifulAgentHostStatePayload
    let controller: BeautifulAgentWebController
    let callbacks: BeautifulAgentWebActionCallbacks
    
    
    func makeCoordinator() -> Coordinator {
        Coordinator(controller: self.controller, callbacks: self.callbacks)
    }
    
    
    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.preferences.setValue(true, forKey: "developerExtrasEnabled")
        let userContent = WKUserContentController()
        userContent.add(WeakScriptMessageProxy(target: context.coordinator), name: "cotAgent")
        config.userContentController = userContent
        
        let webView = CotAgentWKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")
        webView.allowsBackForwardNavigationGestures = false
        webView.allowsMagnification = false
        
        self.controller.webView = webView
        self.controller.isBridgeReady = false
        self.controller.syncState(self.state, force: true)
        
        let html = BeautifulAgentUIBundle.htmlDocument()
        webView.loadHTMLString(html, baseURL: URL(string: "https://cot.local/"))
        return webView
    }
    
    
    func updateNSView(_ nsView: WKWebView, context: Context) {
        context.coordinator.callbacks = self.callbacks
        self.controller.webView = nsView
        self.controller.syncState(self.state)
    }
    
    
    static func dismantleNSView(_ nsView: WKWebView, coordinator: Coordinator) {
        nsView.configuration.userContentController.removeScriptMessageHandler(forName: "cotAgent")
        nsView.navigationDelegate = nil
        if coordinator.controller.webView === nsView {
            coordinator.controller.webView = nil
            coordinator.controller.isBridgeReady = false
        }
    }
    
    
    // MARK: - Coordinator
    
    @MainActor
    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        
        let controller: BeautifulAgentWebController
        var callbacks: BeautifulAgentWebActionCallbacks
        
        init(controller: BeautifulAgentWebController, callbacks: BeautifulAgentWebActionCallbacks) {
            self.controller = controller
            self.callbacks = callbacks
        }
        
        
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "cotAgent",
                  let dict = message.body as? [String: Any],
                  let type = dict["type"] as? String
            else { return }
            
            switch type {
                case "ready":
                    self.controller.markReady()
                    
                case "send":
                    let text = (dict["text"] as? String) ?? ""
                    let quote = (dict["quote"] as? String) ?? ""
                    self.callbacks.onSend(text, quote)
                    
                case "abort":
                    self.callbacks.onAbort()
                    
                case "retry":
                    self.callbacks.onRetry()
                    
                case "clearChat":
                    self.callbacks.onClearChat()
                    
                case "clearQuote":
                    self.callbacks.onClearQuote()
                    
                case "selectModel":
                    if let modelObj = dict["model"],
                       let data = try? JSONSerialization.data(withJSONObject: modelObj),
                       let decoded = try? JSONDecoder().decode(BeautifulAgentModelPayload.self, from: data)
                    {
                        self.callbacks.onSelectModel(decoded)
                    }
                    
                case "selectEffort":
                    if let effort = dict["effort"] as? String {
                        self.callbacks.onSelectEffort(effort)
                    }
                    
                case "newSession":
                    self.callbacks.onNewSession()
                    
                case "selectSession":
                    if let id = dict["id"] as? String {
                        self.callbacks.onSelectSession(id)
                    }
                    
                case "deleteSession":
                    if let id = dict["id"] as? String {
                        self.callbacks.onDeleteSession(id)
                    }
                    
                case "renameSession":
                    if let id = dict["id"] as? String, let title = dict["title"] as? String {
                        self.callbacks.onRenameSession(id, title)
                    }
                    
                case "togglePinSession":
                    if let id = dict["id"] as? String {
                        self.callbacks.onTogglePinSession(id)
                    }
                    
                case "copyText":
                    if let text = dict["text"] as? String {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(text, forType: .string)
                    }
                    
                case "insertToEditor":
                    if let text = dict["text"] as? String {
                        self.callbacks.onInsertToEditor(text)
                    }
                    
                case "openNewDocument":
                    if let text = dict["text"] as? String {
                        self.callbacks.onOpenNewDocument(text)
                    }
                    
                case "openURL":
                    if let raw = dict["url"] as? String,
                       let url = URL(string: raw),
                       let scheme = url.scheme?.lowercased(),
                       scheme == "http" || scheme == "https"
                    {
                        NSWorkspace.shared.open(url)
                    }
                    
                case "openSettings":
                    let target = (dict["target"] as? String) ?? "bot"
                    self.callbacks.onOpenSettings(target)
                    
                case "togglePinPanel":
                    self.callbacks.onTogglePinPanel()
                    
                case "dockToPane":
                    self.callbacks.onDockToPane()
                    
                case "quickAction":
                    if let action = dict["action"] as? String {
                        self.callbacks.onQuickAction(action)
                    }
                    
                default:
                    break
            }
        }
        
        
        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
        ) {
            if navigationAction.navigationType == .linkActivated,
               let url = navigationAction.request.url,
               let scheme = url.scheme?.lowercased(),
               scheme == "http" || scheme == "https"
            {
                NSWorkspace.shared.open(url)
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }
    }
}


private final class WeakScriptMessageProxy: NSObject, WKScriptMessageHandler {
    private weak var target: (any WKScriptMessageHandler)?
    
    init(target: any WKScriptMessageHandler) {
        self.target = target
    }
    
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        self.target?.userContentController(userContentController, didReceive: message)
    }
}


/// WKWebView subclass that suppresses default noisy browser context menu items ("Reload", etc.)
/// while keeping native Copy/Paste/Inspect cleanly usable inside CotEditor.
private final class CotAgentWKWebView: WKWebView {
    
    override func willOpenMenu(_ menu: NSMenu, with event: NSEvent) {
        let blocked = Set(["WKMenuItemIdentifierReload", "WKMenuItemIdentifierGoBack", "WKMenuItemIdentifierGoForward"])
        for item in menu.items.reversed() {
            if let id = item.identifier?.rawValue, blocked.contains(id) {
                menu.removeItem(item)
            }
        }
        super.willOpenMenu(menu, with: event)
    }
}
