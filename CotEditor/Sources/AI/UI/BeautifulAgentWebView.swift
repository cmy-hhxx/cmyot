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
    var kind: String? // "thinking" | "tool"
    var startedAtMs: Double?
    
    init(
        id: String = UUID().uuidString,
        label: String,
        chip: String? = nil,
        status: String = "running",
        mono: Bool = false,
        detail: [String]? = nil,
        durationMs: Int? = nil,
        kind: String? = nil,
        startedAtMs: Double? = nil
    ) {
        self.id = id
        self.label = label
        self.chip = chip
        self.status = status
        self.mono = mono
        self.detail = detail
        self.durationMs = durationMs
        self.kind = kind
        self.startedAtMs = startedAtMs
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
    var attachedDocuments: [String]? = nil
    var delegatedBotID: String? = nil
    var delegatedBotName: String? = nil
    var delegatedModel: String? = nil
    var stickerID: String? = nil
    var stickerURL: String? = nil
    var stickerCaption: String? = nil
}


nonisolated struct BeautifulAgentSessionPayload: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var title: String
    var isPinned: Bool
    var messageCount: Int?
    var updatedAt: Double?
    var workspaceID: String? = nil
    var workspacePath: String? = nil
    var workspaceName: String? = nil
    var sortOrder: Int? = nil
    var botID: String? = nil
    var unreadCount: Int? = nil
    var lastMessagePreview: String? = nil
}


nonisolated struct BeautifulAgentContactPayload: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var name: String
    var nickname: String
    var handle: String
    var tagline: String
    var accentHex: String
    var avatarURL: String? = nil
    var isCustom: Bool
    var isButler: Bool
    var sessionID: String? = nil
    var unreadCount: Int
    var lastMessagePreview: String? = nil
    var updatedAt: Double? = nil
    var isPinned: Bool
}


nonisolated struct BeautifulAgentWorkspacePayload: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var path: String
    var name: String
    var folderPath: String? = nil
    var subtitle: String
    var isFolderBacked: Bool = false
    var isOpenInEditor: Bool
}


nonisolated struct BeautifulAgentDocumentMentionPayload: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var title: String
    var desc: String
    var sourceKind: String // "open_tab" | "stored_doc" | "weekly_report" | "workspace_file"
    var filePath: String? = nil
    var isActive: Bool? = nil
}


nonisolated struct BeautifulAgentBotMentionPayload: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var name: String
    var nickname: String
    var handle: String
    var tagline: String
    var accentHex: String
    var model: String? = nil
    var avatarURL: String? = nil
    var isCustom: Bool? = nil
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


nonisolated struct MeetingRoomParticipantPayload: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var name: String
    var nickname: String
    var handle: String
    var roleLabel: String
    var accentHex: String
    var status: String // "idle" | "speaking" | "done" | "updated"
    var todayBadge: String
    var moodLabel: String? = nil
    var avatarURL: String? = nil
    var isSelected: Bool? = nil
    var isCustom: Bool? = nil
}


nonisolated struct MeetingRoomSessionPayload: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var title: String
    var isPinned: Bool
    var updatedAt: Double
    var participantIDs: [String]
}


nonisolated struct BeautifulAgentStickerPayload: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var url: String
    var category: String
    var ocrText: String
    var meaning: String
    var moods: [String]
    var tags: [String]
    var isFavorite: Bool
    var isAnimated: Bool
    var useCount: Int
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
    var availableWorkspaces: [BeautifulAgentWorkspacePayload]? = nil
    var availableDocuments: [BeautifulAgentDocumentMentionPayload]? = nil
    var availableBots: [BeautifulAgentBotMentionPayload]? = nil
    var themePageHex: String? = nil
    var themeCanvasHex: String? = nil
    var proactiveCards: [ButlerProactiveCardPayload]? = nil
    var backgroundWorkers: [ButlerBackgroundWorkerPayload]? = nil
    var meetingRoomActive: Bool? = nil
    var meetingRoomIsConvening: Bool? = nil
    var meetingRoomMessages: [MeetingRoomMessage]? = nil
    var meetingRoomBots: [MeetingRoomParticipantPayload]? = nil
    var meetingRoomSessions: [MeetingRoomSessionPayload]? = nil
    var activeMeetingSessionID: String? = nil
    var stickerCatalog: [BeautifulAgentStickerPayload]? = nil
    var userAvatarURL: String? = nil
    var onlineStickerExpansionEnabled: Bool? = nil
    var contacts: [BeautifulAgentContactPayload]? = nil
    var activeBotID: String? = nil
    var totalUnread: Int? = nil
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
    var onSendRich: ((String, String, [ButlerDocumentAttachment], String?) -> Void)? = nil
    var onAbort: () -> Void = { }
    var onRetry: () -> Void = { }
    var onClearChat: () -> Void = { }
    var onClearQuote: () -> Void = { }
    var onSelectModel: (BeautifulAgentModelPayload) -> Void = { _ in }
    var onSelectEffort: (String) -> Void = { _ in }
    var onNewSession: () -> Void = { }
    var onNewSessionInWorkspace: ((String?) -> Void)? = nil
    var onNewSessionInWorkspaceTarget: ((String?, String?) -> Void)? = nil
    var onSelectSession: (String) -> Void = { _ in }
    var onDeleteSession: (String) -> Void = { _ in }
    var onRenameSession: (String, String) -> Void = { _, _ in }
    var onTogglePinSession: (String) -> Void = { _ in }
    var onSetSessionWorkspace: (String, String?) -> Void = { _, _ in }
    var onSetSessionWorkspaceTarget: ((String, String?, String?) -> Void)? = nil
    var onChooseWorkspaceFolder: (String, Bool) -> Void = { _, _ in }
    var onCreateWorkspace: ((String, String?, Bool, String?) -> Void)? = nil
    var onRenameWorkspace: ((String, String) -> Void)? = nil
    var onDeleteWorkspace: ((String) -> Void)? = nil
    var onUpdateWorkspaceFolder: ((String, String?) -> Void)? = nil
    var onChooseWorkspaceFolderForWorkspace: ((String) -> Void)? = nil
    var onReorderWorkspaces: (([String]) -> Void)? = nil
    var onMoveSession: ((String, String?, [String], Bool?) -> Void)? = nil
    var onInsertToEditor: (String) -> Void = { _ in }
    var onOpenNewDocument: (String) -> Void = { _ in }
    var onOpenSettings: (String) -> Void = { _ in }
    var onTogglePinPanel: () -> Void = { }
    var onDockToPane: () -> Void = { }
    var onDismissPanel: (() -> Void)? = nil
    var onQuickAction: (String) -> Void = { _ in }
    var onDismissProactiveCard: ((String) -> Void)? = nil
    var onOpenWorkerAction: ((String, String?) -> Void)? = nil
    var onDismissWorker: ((String) -> Void)? = nil
    var onToggleMeetingRoom: ((Bool) -> Void)? = nil
    var onSendMeetingPrompt: ((String, String?) -> Void)? = nil
    var onSendMeetingPromptRich: ((String, String?, String?) -> Void)? = nil
    var onSendRichWithSticker: ((String, String, [ButlerDocumentAttachment], String?, String?) -> Void)? = nil
    var onClearMeetingRoom: (() -> Void)? = nil
    var onAbortMeetingRoom: (() -> Void)? = nil
    var onNewMeetingSession: (() -> Void)? = nil
    var onSelectMeetingSession: ((String) -> Void)? = nil
    var onRenameMeetingSession: ((String, String) -> Void)? = nil
    var onDeleteMeetingSession: ((String) -> Void)? = nil
    var onTogglePinMeetingSession: ((String) -> Void)? = nil
    var onToggleMeetingParticipant: ((String) -> Void)? = nil
    var onUploadSticker: (() -> Void)? = nil
    var onToggleFavoriteSticker: ((String) -> Void)? = nil
    var onSearchOnlineStickers: ((String) -> Void)? = nil
    var onOpenCreateBotSheet: (() -> Void)? = nil
    var onOpenBotConfig: ((String) -> Void)? = nil
    var onRefreshStickers: (() -> Void)? = nil
    var onOpenDirectChat: ((String) -> Void)? = nil
    var onNewTopic: (() -> Void)? = nil
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
    /// Held imperatively on the controller instead of as a stored property on `BeautifulAgentWebView`
    /// so SwiftUI's `AG::LayoutDescriptor::compare_heap_objects` never traverses closure capture graphs.
    fileprivate var callbacks = BeautifulAgentWebActionCallbacks()
    
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

struct BeautifulAgentWebView: NSViewRepresentable, Equatable {
    
    let state: BeautifulAgentHostStatePayload
    let controller: BeautifulAgentWebController
    var cornerRadius: CGFloat = 0
    
    
    @MainActor
    init(
        state: BeautifulAgentHostStatePayload,
        controller: BeautifulAgentWebController,
        callbacks: BeautifulAgentWebActionCallbacks,
        cornerRadius: CGFloat = 0
    ) {
        self.state = state
        self.controller = controller
        self.cornerRadius = cornerRadius
        controller.callbacks = callbacks
    }
    
    
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.controller === rhs.controller
            && lhs.cornerRadius == rhs.cornerRadius
            && lhs.state == rhs.state
    }
    
    
    func makeCoordinator() -> Coordinator {
        Coordinator(controller: self.controller)
    }
    
    
    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.preferences.setValue(true, forKey: "developerExtrasEnabled")
        let userContent = WKUserContentController()
        userContent.add(WeakScriptMessageProxy(target: context.coordinator), name: "cotAgent")
        
        // Apply dark class & harmonized theme surface variables before the first paint to eliminate any white flash.
        let isDarkLiteral = self.state.isDark ? "true" : "false"
        let pageHexJSON = Self.encodeJSString(self.state.themePageHex)
        let canvasHexJSON = Self.encodeJSString(self.state.themeCanvasHex)
        let bootstrapJS = """
        (function() {
          var root = document.documentElement;
          root.classList.toggle('dark', \(isDarkLiteral));
          var pageHex = \(pageHexJSON);
          var canvasHex = \(canvasHexJSON);
          if (pageHex) root.style.setProperty('--page', pageHex);
          if (canvasHex) root.style.setProperty('--canvas', canvasHex);
        })();
        """
        userContent.addUserScript(WKUserScript(source: bootstrapJS, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        config.userContentController = userContent
        config.setURLSchemeHandler(CotMediaSchemeHandler(), forURLScheme: CotMediaSchemeHandler.scheme)
        
        let webView = CotAgentWKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")
        webView.underPageBackgroundColor = .clear
        webView.wantsLayer = true
        webView.layer?.backgroundColor = NSColor.clear.cgColor
        Self.applyLayerCornerMask(to: webView, cornerRadius: self.cornerRadius)
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
        Self.applyLayerCornerMask(to: nsView, cornerRadius: self.cornerRadius)
        self.controller.webView = nsView
        self.controller.syncState(self.state)
    }
    
    
    private static func applyLayerCornerMask(to webView: WKWebView, cornerRadius: CGFloat) {
        webView.wantsLayer = true
        if cornerRadius > 0 {
            webView.layer?.cornerRadius = cornerRadius
            webView.layer?.cornerCurve = .continuous
            webView.layer?.masksToBounds = true
        } else {
            webView.layer?.cornerRadius = 0
            webView.layer?.masksToBounds = false
        }
    }
    
    
    private static func encodeJSString(_ value: String?) -> String {
        guard let value,
              let data = try? JSONEncoder().encode(value),
              let json = String(data: data, encoding: .utf8)
        else { return "null" }
        return json
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
        private var callbacks: BeautifulAgentWebActionCallbacks { self.controller.callbacks }
        
        init(controller: BeautifulAgentWebController) {
            self.controller = controller
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
                    let stickerID = (dict["stickerId"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                    let cleanStickerID = (stickerID?.isEmpty == false) ? stickerID : nil
                    var docs: [ButlerDocumentAttachment] = []
                    if let rawDocs = dict["documents"],
                       let data = try? JSONSerialization.data(withJSONObject: rawDocs),
                       let decoded = try? JSONDecoder().decode([ButlerDocumentAttachment].self, from: data)
                    {
                        docs = decoded
                    }
                    let botID = (dict["botId"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                    let cleanBotID = (botID?.isEmpty == false) ? botID : nil
                    if let onSendRichWithSticker = self.callbacks.onSendRichWithSticker {
                        onSendRichWithSticker(text, quote, docs, cleanBotID, cleanStickerID)
                    } else if let onSendRich = self.callbacks.onSendRich {
                        onSendRich(text, quote, docs, cleanBotID)
                    } else {
                        self.callbacks.onSend(text, quote)
                    }
                    
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
                    let wsID = (dict["workspaceId"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                    let wsPath = (dict["workspacePath"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                    let cleanID = (wsID?.isEmpty == false) ? wsID : nil
                    let cleanPath = (wsPath?.isEmpty == false) ? wsPath : nil
                    if let onTarget = self.callbacks.onNewSessionInWorkspaceTarget {
                        onTarget(cleanID, cleanPath)
                    } else if let onNewInWorkspace = self.callbacks.onNewSessionInWorkspace {
                        onNewInWorkspace(cleanPath)
                    } else {
                        self.callbacks.onNewSession()
                    }
                    
                case "setSessionWorkspace":
                    let sessionID = (dict["sessionId"] as? String) ?? ""
                    let wsID = (dict["workspaceId"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                    let wsPath = (dict["workspacePath"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                    let cleanID = (wsID?.isEmpty == false) ? wsID : nil
                    let cleanPath = (wsPath?.isEmpty == false) ? wsPath : nil
                    if let onTarget = self.callbacks.onSetSessionWorkspaceTarget {
                        onTarget(sessionID, cleanID, cleanPath)
                    } else {
                        self.callbacks.onSetSessionWorkspace(sessionID, cleanPath)
                    }
                    
                case "chooseWorkspaceFolder":
                    let sessionID = (dict["sessionId"] as? String) ?? ""
                    let createNew = (dict["createNew"] as? Bool) == true
                    self.callbacks.onChooseWorkspaceFolder(sessionID, createNew)
                    
                case "createWorkspace":
                    let name = ((dict["name"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    let folderRaw = (dict["folderPath"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                    let startSession = (dict["startSession"] as? Bool) ?? true
                    let assignSessionID = (dict["assignSessionId"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !name.isEmpty {
                        self.callbacks.onCreateWorkspace?(
                            name,
                            (folderRaw?.isEmpty == false) ? folderRaw : nil,
                            startSession,
                            (assignSessionID?.isEmpty == false) ? assignSessionID : nil
                        )
                    }
                    
                case "renameWorkspace":
                    if let id = dict["id"] as? String, let name = dict["name"] as? String {
                        self.callbacks.onRenameWorkspace?(id, name)
                    }
                    
                case "deleteWorkspace":
                    if let id = dict["id"] as? String {
                        self.callbacks.onDeleteWorkspace?(id)
                    }
                    
                case "updateWorkspaceFolder":
                    if let id = dict["id"] as? String {
                        let folderRaw = (dict["folderPath"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                        self.callbacks.onUpdateWorkspaceFolder?(id, (folderRaw?.isEmpty == false) ? folderRaw : nil)
                    }
                    
                case "chooseWorkspaceFolderForWorkspace":
                    if let wsID = dict["workspaceId"] as? String, !wsID.isEmpty {
                        self.callbacks.onChooseWorkspaceFolderForWorkspace?(wsID)
                    }
                    
                case "reorderWorkspaces":
                    if let orderedIDs = dict["orderedIds"] as? [String] {
                        self.callbacks.onReorderWorkspaces?(orderedIDs)
                    }
                    
                case "moveSession":
                    if let sessionID = dict["sessionId"] as? String, !sessionID.isEmpty {
                        let targetRaw = (dict["targetWorkspaceId"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                        let targetWS = (targetRaw?.isEmpty == false) ? targetRaw : nil
                        let orderedIDs = (dict["orderedSessionIds"] as? [String]) ?? []
                        let isPinned = dict["isPinned"] as? Bool
                        self.callbacks.onMoveSession?(sessionID, targetWS, orderedIDs, isPinned)
                    }
                    
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
                    
                case "dismissProactiveCard":
                    if let id = dict["id"] as? String, !id.isEmpty {
                        self.callbacks.onDismissProactiveCard?(id)
                    }
                    
                case "openWorkerAction":
                    if let board = dict["board"] as? String, !board.isEmpty {
                        let query = (dict["query"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                        self.callbacks.onOpenWorkerAction?(board, (query?.isEmpty == false) ? query : nil)
                    }
                    
                case "dismissWorker":
                    if let id = dict["id"] as? String, !id.isEmpty {
                        self.callbacks.onDismissWorker?(id)
                    }
                    
                case "toggleMeetingRoom":
                    let active = (dict["active"] as? Bool) ?? true
                    self.callbacks.onToggleMeetingRoom?(active)
                    
                case "dismissPanel":
                    self.callbacks.onDismissPanel?()
                    
                case "sendMeetingPrompt":
                    let text = (dict["text"] as? String) ?? ""
                    let botID = (dict["botId"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                    let cleanBotID = (botID?.isEmpty == false) ? botID : nil
                    let stickerID = (dict["stickerId"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                    let cleanStickerID = (stickerID?.isEmpty == false) ? stickerID : nil
                    if let onRich = self.callbacks.onSendMeetingPromptRich {
                        onRich(text, cleanStickerID, cleanBotID)
                    } else {
                        self.callbacks.onSendMeetingPrompt?(text, cleanBotID)
                    }
                    
                case "clearMeetingRoom":
                    self.callbacks.onClearMeetingRoom?()
                    
                case "abortMeetingRoom":
                    self.callbacks.onAbortMeetingRoom?()
                    
                case "newMeetingSession":
                    self.callbacks.onNewMeetingSession?()
                    
                case "selectMeetingSession":
                    if let id = dict["id"] as? String, !id.isEmpty {
                        self.callbacks.onSelectMeetingSession?(id)
                    }
                    
                case "renameMeetingSession":
                    if let id = dict["id"] as? String, let title = dict["title"] as? String {
                        self.callbacks.onRenameMeetingSession?(id, title)
                    }
                    
                case "deleteMeetingSession":
                    if let id = dict["id"] as? String, !id.isEmpty {
                        self.callbacks.onDeleteMeetingSession?(id)
                    }
                    
                case "togglePinMeetingSession":
                    if let id = dict["id"] as? String, !id.isEmpty {
                        self.callbacks.onTogglePinMeetingSession?(id)
                    }
                    
                case "toggleMeetingParticipant":
                    if let botID = dict["botId"] as? String, !botID.isEmpty {
                        self.callbacks.onToggleMeetingParticipant?(botID)
                    }
                    
                case "uploadSticker":
                    self.callbacks.onUploadSticker?()
                    
                case "toggleFavoriteSticker":
                    if let id = dict["id"] as? String, !id.isEmpty {
                        self.callbacks.onToggleFavoriteSticker?(id)
                    }
                    
                case "searchOnlineStickers":
                    let query = (dict["query"] as? String) ?? ""
                    self.callbacks.onSearchOnlineStickers?(query)
                    
                case "openCreateBotSheet":
                    self.callbacks.onOpenCreateBotSheet?()
                    
                case "openBotConfig":
                    if let botID = dict["botId"] as? String, !botID.isEmpty {
                        self.callbacks.onOpenBotConfig?(botID)
                    }
                    
                case "refreshStickers":
                    self.callbacks.onRefreshStickers?()
                    
                case "openDirectChat":
                    if let botID = dict["botId"] as? String, !botID.isEmpty {
                        self.callbacks.onOpenDirectChat?(botID)
                    }
                    
                case "newTopic":
                    self.callbacks.onNewTopic?()
                    
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
