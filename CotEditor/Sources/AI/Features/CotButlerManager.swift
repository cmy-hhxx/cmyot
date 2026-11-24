//
//  CotButlerManager.swift
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
import Observation

/// Structured persisted metadata stored inside `ButlerChatMessage.actionsJSON`.
///
/// Backward-compatible with legacy `[AppliedActionReceipt]` JSON arrays.
nonisolated struct ButlerMessageMetadata: Codable, Sendable, Equatable {
    var receipts: [AppliedActionReceipt] = []
    var thinking: String? = nil
    var thinkingDurationMs: Int? = nil
    var steps: [BeautifulAgentThinkingStep] = []
    var toolChips: [String] = []
    var quoteContext: String? = nil
    var followUps: [String] = []
    var errorMessage: String? = nil
}


/// Chief Butler Bot manager: persistent warm Pi RPC kernel with native CotEditor tools,
/// multi-session persisted conversations, custom avatar/name/nickname, multi-bot governance,
/// multi-angle KYC memory evolution, and real-time workspace takeover.
@MainActor @Observable
final class CotButlerManager {
    
    static let shared = CotButlerManager()
    static let identityDidChangeNotification = Notification.Name("CotButlerManagerIdentityDidChange")
    static let openHubRequestedNotification = Notification.Name("CotButlerManagerOpenHubRequested")
    
    var name: String {
        didSet {
            guard !self.isSyncingIdentity else { return }
            let trimmed = self.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let resolved = trimmed.isEmpty ? "曜" : trimmed
            self.database.set(resolved, forKey: CotLocalDatabase.ConfigKey.butlerName)
            NotificationCenter.default.post(name: Self.identityDidChangeNotification, object: self)
        }
    }
    
    var nickname: String {
        didSet {
            guard !self.isSyncingIdentity else { return }
            let trimmed = self.nickname.trimmingCharacters(in: .whitespacesAndNewlines)
            let resolved = trimmed.isEmpty ? "总管" : trimmed
            self.database.set(resolved, forKey: CotLocalDatabase.ConfigKey.butlerNickname)
            NotificationCenter.default.post(name: Self.identityDidChangeNotification, object: self)
        }
    }
    
    var avatarVariantIndex: Int? {
        didSet {
            guard !self.isSyncingIdentity else { return }
            let value = self.avatarVariantIndex.map(String.init) ?? ""
            self.database.set(value, forKey: CotLocalDatabase.ConfigKey.butlerAvatarVariant)
            if self.database === CotLocalDatabase.shared {
                var cfg = AIBotStore.shared.config(for: .butler)
                if cfg.artworkVariantIndex != self.avatarVariantIndex {
                    cfg.artworkVariantIndex = self.avatarVariantIndex
                    AIBotStore.shared.updateConfig(cfg, for: .butler)
                }
            }
            NotificationCenter.default.post(name: Self.identityDidChangeNotification, object: self)
        }
    }
    
    private(set) var customAvatarImage: NSImage?
    private(set) var sessions: [ButlerSessionRecord] = []
    private(set) var activeSessionID: String = ""
    private(set) var messages: [ButlerChatMessage] = []
    private(set) var isStreaming: Bool = false
    private(set) var streamingSessionID: String?
    private(set) var streamingMessageID: String?
    private(set) var streamingDraft: String = ""
    private(set) var streamingThinking: String = ""
    private(set) var streamingSteps: [BeautifulAgentThinkingStep] = []
    private(set) var streamingStatusLabel: String = ""
    private(set) var streamingStartedAt: Date?
    private(set) var lastErrorMessage: String?
    
    /// Pending draft/quote handoff injected from Editor selection, Result Panel, or NEWS center.
    var pendingDraftText: String?
    var pendingQuoteExcerpt: String?
    
    private let database: CotLocalDatabase
    private let memoryStore: CotMemoryStore
    private var dbObserver: (any NSObjectProtocol)?
    private var isSyncingIdentity = false
    @ObservationIgnored private var activeTurnTask: Task<Void, Never>?
    @ObservationIgnored private var activeTurnGeneration: UInt64 = 0
    @ObservationIgnored private var streamPatchListeners: [UUID: @MainActor (BeautifulAgentStreamPatchPayload) -> Void] = [:]
    
    
    init(
        database: CotLocalDatabase = .shared,
        memoryStore: CotMemoryStore = .shared
    ) {
        self.database = database
        self.memoryStore = memoryStore
        
        let storedName = database.string(forKey: CotLocalDatabase.ConfigKey.butlerName, default: "曜")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        self.name = storedName.isEmpty ? "曜" : storedName
        
        let storedNick = database.string(forKey: CotLocalDatabase.ConfigKey.butlerNickname, default: "总管")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        self.nickname = storedNick.isEmpty ? "总管" : storedNick
        
        let variantRaw = database.string(forKey: CotLocalDatabase.ConfigKey.butlerAvatarVariant)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        self.avatarVariantIndex = Int(variantRaw)
        self.customAvatarImage = Self.decodeAvatarImage(from: database.string(forKey: CotLocalDatabase.ConfigKey.butlerCustomAvatarBase64))
        
        self.bootstrapSessionsAndMessages()
        
        if database === CotLocalDatabase.shared {
            self.dbObserver = NotificationCenter.default.addObserver(
                forName: CotLocalDatabase.structuredAssetsDidChangeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.reloadFromDatabase()
                }
            }
        }
    }
    
    
    isolated deinit {
        if let dbObserver {
            NotificationCenter.default.removeObserver(dbObserver)
        }
        self.activeTurnTask?.cancel()
    }
    
    
    // MARK: - Stream Patch Subscription (Zero-Lag WebView Sync)
    
    @discardableResult
    func addStreamPatchListener(_ listener: @escaping @MainActor (BeautifulAgentStreamPatchPayload) -> Void) -> UUID {
        let id = UUID()
        self.streamPatchListeners[id] = listener
        return id
    }
    
    
    func removeStreamPatchListener(_ id: UUID) {
        self.streamPatchListeners.removeValue(forKey: id)
    }
    
    
    private func emitStreamPatch() {
        guard let msgID = self.streamingMessageID else { return }
        let elapsedMs = self.streamingStartedAt.map { max(0, Int(Date().timeIntervalSince($0) * 1000)) } ?? 0
        let patch = BeautifulAgentStreamPatchPayload(
            messageId: msgID,
            text: self.streamingDraft,
            thinking: self.streamingThinking.isEmpty ? nil : self.streamingThinking,
            thinkingDurationMs: elapsedMs,
            steps: self.streamingSteps,
            statusLabel: self.streamingStatusLabel.isEmpty ? nil : self.streamingStatusLabel
        )
        for listener in self.streamPatchListeners.values {
            listener(patch)
        }
    }
    
    
    // MARK: - Cross-Editor Handoff Entrypoint
    
    /// Requests opening the Butler Hub (or focusing an existing docked Butler split pane) with optional draft/quote.
    func requestOpenHub(
        draft: String? = nil,
        quote: String? = nil,
        autoSend: Bool = false,
        startFreshSession: Bool = false
    ) {
        if startFreshSession {
            self.startNewSession()
        }
        self.pendingDraftText = draft
        self.pendingQuoteExcerpt = quote
        NotificationCenter.default.post(
            name: Self.openHubRequestedNotification,
            object: self,
            userInfo: [
                "draft": draft ?? "",
                "quote": quote ?? "",
                "autoSend": autoSend,
            ]
        )
    }
    
    
    func consumePendingDraftAndQuote() -> (draft: String?, quote: String?) {
        let pair = (self.pendingDraftText, self.pendingQuoteExcerpt)
        self.pendingDraftText = nil
        self.pendingQuoteExcerpt = nil
        return pair
    }
    
    
    func reloadFromDatabase() {
        self.isSyncingIdentity = true
        let storedName = self.database.string(forKey: CotLocalDatabase.ConfigKey.butlerName, default: "曜")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedName = storedName.isEmpty ? "曜" : storedName
        if self.name != resolvedName {
            self.name = resolvedName
        }
        
        let storedNick = self.database.string(forKey: CotLocalDatabase.ConfigKey.butlerNickname, default: "总管")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedNick = storedNick.isEmpty ? "总管" : storedNick
        if self.nickname != resolvedNick {
            self.nickname = resolvedNick
        }
        
        let variantRaw = self.database.string(forKey: CotLocalDatabase.ConfigKey.butlerAvatarVariant)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let botVariant = self.database === CotLocalDatabase.shared ? AIBotStore.shared.config(for: .butler).artworkVariantIndex : nil
        self.avatarVariantIndex = Int(variantRaw) ?? botVariant
        self.customAvatarImage = Self.decodeAvatarImage(from: self.database.string(forKey: CotLocalDatabase.ConfigKey.butlerCustomAvatarBase64))
        self.isSyncingIdentity = false
        
        self.bootstrapSessionsAndMessages()
        NotificationCenter.default.post(name: Self.identityDidChangeNotification, object: self)
    }
    
    
    // MARK: - Custom Identity & Artwork
    
    func setCustomAvatarData(_ data: Data?) {
        if let data,
           let rawImage = NSImage(data: data),
           let pngData = UserProfileManager.processedAvatarPNGData(from: rawImage)
        {
            self.database.set(pngData.base64EncodedString(), forKey: CotLocalDatabase.ConfigKey.butlerCustomAvatarBase64)
            self.customAvatarImage = NSImage(data: pngData)
        } else {
            self.database.set("", forKey: CotLocalDatabase.ConfigKey.butlerCustomAvatarBase64)
            self.customAvatarImage = nil
        }
        NotificationCenter.default.post(name: Self.identityDidChangeNotification, object: self)
    }
    
    
    func syncArtworkVariant(_ variantIndex: Int?) {
        self.avatarVariantIndex = variantIndex
    }
    
    
    func cycleAvatarVariant() {
        let count = max(1, self.resolvedCharacter().artworks.count)
        let current = self.avatarVariantIndex ?? 0
        self.avatarVariantIndex = (current + 1) % count
    }
    
    
    func resolvedCharacter() -> AIGijinkaCharacter {
        let botCfg = AIBotStore.shared.config(for: .butler)
        let endpoint = AIBotStore.shared.resolvedEndpointProfile(for: .butler)
        let overrideModel = botCfg.modelOverride.trimmingCharacters(in: .whitespacesAndNewlines)
        return AIGijinkaCharacter.resolve(
            modelName: overrideModel.isEmpty ? endpoint?.displayModel : overrideModel,
            endpointName: endpoint?.displayName,
            baseURL: endpoint?.baseURL
        ) ?? .deepseek
    }
    
    
    func resolvedArtwork() -> AIGijinkaArtwork {
        let variant = self.avatarVariantIndex ?? AIBotStore.shared.config(for: .butler).artworkVariantIndex
        return self.resolvedCharacter().artwork(for: .butler, variantOverride: variant)
    }
    
    
    func resolvedAvatarDataURL(pointSize: CGFloat = 64) -> String? {
        let image = AIBotStore.shared.resolvedAvatarImage(for: .butler, pointSize: pointSize)
            ?? self.customAvatarImage
            ?? AIGijinkaImageLoader.shared.thumbnail(for: self.resolvedArtwork(), maxPixelSize: pointSize)
        guard let image,
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:])
        else { return nil }
        return "data:image/png;base64,\(png.base64EncodedString())"
    }
    
    
    private static func decodeAvatarImage(from base64: String) -> NSImage? {
        let trimmed = base64.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let data = Data(base64Encoded: trimmed) else { return nil }
        return NSImage(data: data)
    }
    
    
    // MARK: - Session Management
    
    private func bootstrapSessionsAndMessages() {
        var loaded = self.database.fetchButlerSessions()
        if loaded.isEmpty {
            let initial = self.database.createButlerSession(title: AppLanguage.text("新对话", en: "New Chat"))
            loaded = [initial]
        }
        self.sessions = loaded
        
        let savedActive = self.database.string(forKey: CotLocalDatabase.ConfigKey.butlerActiveSessionID)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !savedActive.isEmpty, loaded.contains(where: { $0.id == savedActive }) {
            self.activeSessionID = savedActive
        } else {
            self.activeSessionID = loaded.first?.id ?? ""
            self.database.set(self.activeSessionID, forKey: CotLocalDatabase.ConfigKey.butlerActiveSessionID)
        }
        self.messages = self.database.fetchButlerMessages(sessionID: self.activeSessionID)
    }
    
    
    private func cancelAndResetStreaming(savePartial: Bool, resetRPC: Bool) {
        let wasStreaming = self.isStreaming
        let priorSessionID = self.streamingSessionID ?? self.activeSessionID
        let partial = Self.stripActionEnvelope(self.streamingDraft)
        let priorThinking = self.streamingThinking
        var priorSteps = self.streamingSteps
        let priorStartedAt = self.streamingStartedAt
        let priorTask = self.activeTurnTask
        
        self.activeTurnGeneration &+= 1
        self.isStreaming = false
        self.streamingSessionID = nil
        self.streamingMessageID = nil
        self.streamingDraft = ""
        self.streamingThinking = ""
        self.streamingSteps = []
        self.streamingStatusLabel = ""
        self.streamingStartedAt = nil
        self.activeTurnTask = nil
        
        priorTask?.cancel()
        
        if savePartial, wasStreaming, !partial.isEmpty, !priorSessionID.isEmpty {
            let nowMs = Date().timeIntervalSince1970 * 1000
            for idx in priorSteps.indices where priorSteps[idx].status == "running" {
                priorSteps[idx].status = "done"
                if priorSteps[idx].durationMs == nil, let startedAtMs = priorSteps[idx].startedAtMs {
                    priorSteps[idx].durationMs = max(1, Int(nowMs - startedAtMs))
                }
            }
            let elapsedMs = priorStartedAt.map { max(1, Int(Date().timeIntervalSince($0) * 1000)) }
            let meta = ButlerMessageMetadata(
                thinking: priorThinking.isEmpty ? nil : priorThinking,
                thinkingDurationMs: elapsedMs,
                steps: priorSteps
            )
            self.appendAssistantMessage(partial, metadata: meta, sessionID: priorSessionID)
        }
        
        if self.database === CotLocalDatabase.shared {
            if resetRPC {
                PiKernelManager.shared.resetRPCSession(channel: .butler, forceAbort: true)
            } else if wasStreaming {
                PiKernelManager.shared.abortRPCTurn(channel: .butler)
            }
        }
    }
    
    
    func startNewSession() {
        self.lastErrorMessage = nil
        let hadStreaming = self.isStreaming
        if hadStreaming {
            self.cancelAndResetStreaming(savePartial: true, resetRPC: true)
        }
        if let active = self.sessions.first(where: { $0.id == self.activeSessionID }),
           self.messages.isEmpty,
           active.messageCount == 0
        {
            if !hadStreaming, self.database === CotLocalDatabase.shared {
                PiKernelManager.shared.resetRPCSession(channel: .butler, forceAbort: true)
            }
            return
        }
        let created = self.database.createButlerSession(title: AppLanguage.text("新对话", en: "New Chat"))
        self.activeSessionID = created.id
        self.database.set(created.id, forKey: CotLocalDatabase.ConfigKey.butlerActiveSessionID)
        self.sessions = self.database.fetchButlerSessions()
        self.messages = []
        if !hadStreaming, self.database === CotLocalDatabase.shared {
            PiKernelManager.shared.resetRPCSession(channel: .butler, forceAbort: true)
        }
    }
    
    
    func selectSession(_ sessionID: String) {
        guard self.activeSessionID != sessionID,
              self.sessions.contains(where: { $0.id == sessionID })
        else { return }
        if self.isStreaming {
            self.cancelAndResetStreaming(savePartial: true, resetRPC: false)
        }
        self.lastErrorMessage = nil
        self.activeSessionID = sessionID
        self.database.set(sessionID, forKey: CotLocalDatabase.ConfigKey.butlerActiveSessionID)
        self.messages = self.database.fetchButlerMessages(sessionID: sessionID)
    }
    
    
    func renameSession(_ sessionID: String, to title: String) {
        self.database.renameButlerSession(id: sessionID, title: title)
        self.sessions = self.database.fetchButlerSessions()
    }
    
    
    func togglePinSession(_ sessionID: String) {
        guard let session = self.sessions.first(where: { $0.id == sessionID }) else { return }
        self.database.toggleButlerSessionPinned(id: sessionID, isPinned: !session.isPinned)
        self.sessions = self.database.fetchButlerSessions()
    }
    
    
    func deleteSession(_ sessionID: String) {
        let shouldResetStreaming = self.isStreaming && (self.streamingSessionID == sessionID || self.activeSessionID == sessionID)
        if shouldResetStreaming {
            self.cancelAndResetStreaming(savePartial: false, resetRPC: true)
        }
        self.database.deleteButlerSession(id: sessionID)
        var remaining = self.database.fetchButlerSessions()
        if remaining.isEmpty {
            let fresh = self.database.createButlerSession(title: AppLanguage.text("新对话", en: "New Chat"))
            remaining = [fresh]
        }
        self.sessions = remaining
        if self.activeSessionID == sessionID || !remaining.contains(where: { $0.id == self.activeSessionID }) {
            self.activeSessionID = remaining.first?.id ?? ""
            self.database.set(self.activeSessionID, forKey: CotLocalDatabase.ConfigKey.butlerActiveSessionID)
        }
        self.messages = self.database.fetchButlerMessages(sessionID: self.activeSessionID)
        if !shouldResetStreaming, self.database === CotLocalDatabase.shared {
            PiKernelManager.shared.resetRPCSession(channel: .butler, forceAbort: true)
        }
    }
    
    
    func clearCurrentSession() {
        guard !self.activeSessionID.isEmpty else { return }
        self.lastErrorMessage = nil
        self.cancelAndResetStreaming(savePartial: false, resetRPC: true)
        self.database.clearButlerMessages(sessionID: self.activeSessionID)
        self.messages = []
        self.sessions = self.database.fetchButlerSessions()
    }
    
    
    func clearConversation() {
        self.clearCurrentSession()
    }
    
    
    func applyGlobalPersonaToAllBots(_ persona: String, clearPerBotOverrides: Bool = true) {
        let clean = persona.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        self.database.aiPersona = clean
        if clearPerBotOverrides {
            for botID in AIBotID.allCases {
                var cfg = AIBotStore.shared.config(for: botID)
                if !cfg.customPersona.isEmpty {
                    cfg.customPersona = ""
                    AIBotStore.shared.updateConfig(cfg, for: botID)
                }
            }
        }
        if self.database === CotLocalDatabase.shared {
            _ = try? PiKernelManager.shared.syncWorkspace()
        }
    }
    
    
    // MARK: - Conversation & Takeover Execution (Warm Pi RPC + Native Fallback)
    
    func abortStreaming() {
        guard self.isStreaming else { return }
        self.cancelAndResetStreaming(savePartial: true, resetRPC: false)
    }
    
    
    func retryLastMessage() {
        guard !self.isStreaming else { return }
        guard let lastUser = self.messages.last(where: { $0.role == "user" }) else { return }
        let meta = Self.decodeMetadata(from: lastUser.actionsJSON)
        Task {
            await self.sendMessage(lastUser.content, quote: meta.quoteContext)
        }
    }
    
    
    func sendMessage(
        _ rawText: String,
        quote: String? = nil,
        contextSources: [String] = []
    ) async {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        
        if self.isStreaming {
            // Self-heal stale streaming flags or cleanly cancel a background turn on another session.
            if self.activeTurnTask == nil || self.streamingSessionID != self.activeSessionID {
                self.cancelAndResetStreaming(savePartial: true, resetRPC: false)
            } else {
                return
            }
        }
        
        if self.activeSessionID.isEmpty {
            self.bootstrapSessionsAndMessages()
        }
        let targetSessionID = self.activeSessionID
        let cleanQuote = quote?.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Refresh live workspace snapshot before every turn so Pi tools read the freshest editor state
        _ = CotAgentCoordinator.shared.captureWorkspaceSnapshot()
        
        let userMeta = ButlerMessageMetadata(quoteContext: (cleanQuote?.isEmpty == false) ? cleanQuote : nil)
        let userMsg = ButlerChatMessage(
            id: UUID().uuidString,
            sessionID: targetSessionID,
            role: "user",
            content: text,
            actionsJSON: Self.encodeMetadata(userMeta),
            createdAt: Date()
        )
        self.database.appendButlerMessage(userMsg)
        self.messages.append(userMsg)
        self.sessions = self.database.fetchButlerSessions()
        self.lastErrorMessage = nil
        
        let resolvedConfig = AIBotStore.shared.resolvedConfiguration(for: .butler)
        guard resolvedConfig.isUsable else {
            await self.handleOfflineCommand(text, sessionID: targetSessionID)
            return
        }
        
        self.activeTurnGeneration &+= 1
        let turnGeneration = self.activeTurnGeneration
        let streamID = "stream-\(UUID().uuidString)"
        self.isStreaming = true
        self.streamingSessionID = targetSessionID
        self.streamingMessageID = streamID
        self.streamingDraft = ""
        self.streamingThinking = ""
        self.streamingSteps = []
        self.streamingStatusLabel = AppLanguage.text("正在思考…", en: "Thinking...")
        self.streamingStartedAt = Date()
        
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.performTurn(
                userText: text,
                quote: cleanQuote,
                contextSources: contextSources,
                sessionID: targetSessionID,
                resolvedConfig: resolvedConfig,
                generation: turnGeneration
            )
        }
        self.activeTurnTask = task
        await task.value
        if self.activeTurnGeneration == turnGeneration {
            self.activeTurnTask = nil
        }
    }
    
    
    private func performTurn(
        userText: String,
        quote: String?,
        contextSources: [String],
        sessionID: String,
        resolvedConfig: AIConfiguration,
        generation: UInt64
    ) async {
        let turnClockStart = ContinuousClock.now
        defer {
            if self.activeTurnGeneration == generation {
                self.isStreaming = false
                self.streamingSessionID = nil
                self.streamingMessageID = nil
                self.streamingDraft = ""
                self.streamingThinking = ""
                self.streamingSteps = []
                self.streamingStatusLabel = ""
                self.streamingStartedAt = nil
            }
        }
        
        let augmentedUserPrompt = self.buildTurnUserPrompt(
            userText: userText,
            quote: quote,
            contextSources: contextSources
        )
        let priorHistory = self.buildPriorHistoryContext(excludingLastUserMessage: true)
        
        // 1. Primary path: Warm Persistent Pi RPC Kernel with native Cot tools
        if self.database === CotLocalDatabase.shared,
           PiKernelManager.shared.canRunRPC,
           let endpointProfile = AIBotStore.shared.resolvedEndpointProfile(for: .butler)
        {
            let piSystemPrompt = self.buildButlerSystemPrompt(
                resolvedConfig: resolvedConfig,
                userMessage: userText,
                piToolsAvailable: true
            )
            let workingDir = CotAgentCoordinator.shared.activeWorkingDirectoryURL()
            
            do {
                let result = try await PiKernelManager.shared.runRPCTurn(
                    channel: .butler,
                    logicalSessionKey: sessionID,
                    systemPrompt: piSystemPrompt,
                    userPrompt: augmentedUserPrompt,
                    priorHistoryContext: priorHistory,
                    endpointProfile: endpointProfile,
                    configuration: resolvedConfig,
                    workingDirectory: workingDir
                ) { [weak self] event in
                    guard let self, self.activeTurnGeneration == generation else { return }
                    self.handlePiStreamEvent(event)
                }
                
                guard self.activeTurnGeneration == generation else { return }
                
                // Drain any editor_action queued by Pi right before finalizing
                await CotAgentCoordinator.shared.drainCommandQueueNow()
                guard self.activeTurnGeneration == generation else { return }
                
                let extracted = Self.extractActions(from: result.text)
                let legacyReceipts = extracted.actions.isEmpty
                    ? []
                    : await CotAgentCoordinator.shared.execute(extracted.actions)
                guard self.activeTurnGeneration == generation else { return }
                
                let replyText: String = {
                    if !extracted.cleanText.isEmpty {
                        return extracted.cleanText
                    }
                    if result.aborted {
                        return AppLanguage.text("已停止生成。", en: "Generation stopped.")
                    }
                    if !legacyReceipts.isEmpty {
                        return legacyReceipts.map(\.summary).joined(separator: " · ")
                    }
                    return AppLanguage.text("已处理完毕。", en: "Done.")
                }()
                
                let elapsed = turnClockStart.duration(to: .now)
                let latencyMs = max(1, Int(elapsed.components.seconds * 1000) + Int(elapsed.components.attoseconds / 1_000_000_000_000_000))
                let effective = resolvedConfig.wireConfiguration
                AnalyticsManager.shared.recordAIUsage(
                    feature: "butler",
                    model: effective.model,
                    provider: "Pi RPC · \(effective.endpoint.label)",
                    inputTokens: AINextTokenPredictor.estimateTokens(in: piSystemPrompt + "\n" + augmentedUserPrompt),
                    outputTokens: AINextTokenPredictor.estimateTokens(in: replyText + "\n" + result.thinking),
                    latencyMs: latencyMs,
                    success: true
                )
                
                let toolChips = result.toolNames.map { PiToolDisplayMeta.label(for: $0) }
                let meta = ButlerMessageMetadata(
                    receipts: legacyReceipts,
                    thinking: result.thinking.isEmpty ? nil : result.thinking,
                    thinkingDurationMs: result.thinkingDurationMs,
                    steps: result.steps,
                    toolChips: toolChips,
                    followUps: Self.suggestFollowUps(userText: userText, toolNames: result.toolNames)
                )
                
                self.appendAssistantMessage(replyText, metadata: meta, sessionID: sessionID)
                return
            } catch is CancellationError {
                guard self.activeTurnGeneration == generation else { return }
                let partial = Self.stripActionEnvelope(self.streamingDraft)
                let final = partial.isEmpty ? AppLanguage.text("已停止生成。", en: "Stopped.") : partial
                let meta = ButlerMessageMetadata(
                    thinking: self.streamingThinking.isEmpty ? nil : self.streamingThinking,
                    steps: self.streamingSteps
                )
                self.appendAssistantMessage(final, metadata: meta, sessionID: sessionID)
                return
            } catch {
                // If user manually aborted or started a new session, do not fall back
                guard self.activeTurnGeneration == generation, !Task.isCancelled else { return }
                // Reset streaming state cleanly before falling back to Swift Tool Assist + Direct SSE
                self.streamingDraft = ""
                self.streamingThinking = ""
                self.streamingSteps = []
                self.streamingStatusLabel = AppLanguage.text("正在检索实时数据…", en: "Fetching live data...")
                self.emitStreamPatch()
            }
        }
        
        guard self.activeTurnGeneration == generation, !Task.isCancelled else { return }
        
        // 2. Resilient fallback path: Native Swift tool lookup (real quotes + news) + direct SSE streaming
        let enriched = await CotSwiftToolFallback.enrichIfNeeded(for: userText)
        guard self.activeTurnGeneration == generation, !Task.isCancelled else { return }
        if !enriched.steps.isEmpty {
            self.streamingSteps = enriched.steps
            self.streamingStatusLabel = AppLanguage.text("正在整理回复…", en: "Composing reply...")
            self.emitStreamPatch()
        }
        
        let systemPrompt = self.buildButlerSystemPrompt(
            resolvedConfig: resolvedConfig,
            userMessage: userText,
            piToolsAvailable: false
        )
        var aiMessages: [AIMessage] = [.system(systemPrompt)]
        let recent = Array(self.messages.dropLast().suffix(10))
        for turn in recent {
            if turn.role == "assistant" {
                aiMessages.append(AIMessage(role: .assistant, text: turn.content))
            } else {
                aiMessages.append(.user(turn.content))
            }
        }
        var finalTurnUserText = augmentedUserPrompt
        if !enriched.injectedDataBlock.isEmpty {
            finalTurnUserText += "\n\n<live_fetched_data>\n\(enriched.injectedDataBlock)\n</live_fetched_data>\n请直接基于以上实时查询到的数据回复用户，给出关键数字与清晰解读。"
        }
        aiMessages.append(.user(finalTurnUserText))
        
        var lastDraftFlushAt: Date = .distantPast
        do {
            let fullRaw = try await AIService.shared.chat(
                aiMessages,
                configuration: resolvedConfig,
                analyticsFeature: "butler"
            ) { [weak self] partial in
                guard let self, self.activeTurnGeneration == generation else { return }
                let now = Date()
                guard now.timeIntervalSince(lastDraftFlushAt) >= 0.04 else { return }
                lastDraftFlushAt = now
                self.streamingDraft = Self.stripActionEnvelope(partial)
                self.emitStreamPatch()
            }
            
            guard self.activeTurnGeneration == generation else { return }
            let extracted = Self.extractActions(from: fullRaw)
            let receipts = await CotAgentCoordinator.shared.execute(extracted.actions)
            guard self.activeTurnGeneration == generation else { return }
            let replyText = extracted.cleanText.isEmpty
                ? (receipts.isEmpty ? "已处理。" : receipts.map(\.summary).joined(separator: " · "))
                : extracted.cleanText
            let totalToolMs = enriched.steps.compactMap(\.durationMs).reduce(0, +)
            let toolNames: [String] = enriched.steps.map { step in
                if step.id.hasPrefix("fallback-quote-") { return "lookup_stock_quote" }
                if step.id == "fallback-news" { return "search_news" }
                return step.label
            }
            let meta = ButlerMessageMetadata(
                receipts: receipts,
                thinkingDurationMs: totalToolMs > 0 ? totalToolMs : nil,
                steps: enriched.steps,
                toolChips: enriched.steps.map(\.label),
                followUps: Self.suggestFollowUps(userText: userText, toolNames: toolNames)
            )
            self.appendAssistantMessage(replyText, metadata: meta, sessionID: sessionID)
        } catch is CancellationError {
            guard self.activeTurnGeneration == generation else { return }
            let partial = Self.stripActionEnvelope(self.streamingDraft)
            if !partial.isEmpty {
                self.appendAssistantMessage(partial, metadata: ButlerMessageMetadata(steps: self.streamingSteps), sessionID: sessionID)
            }
        } catch {
            guard self.activeTurnGeneration == generation else { return }
            self.lastErrorMessage = error.localizedDescription
            let meta = ButlerMessageMetadata(errorMessage: error.localizedDescription)
            self.appendAssistantMessage(error.localizedDescription, metadata: meta, sessionID: sessionID)
        }
    }
    
    
    private func closeRunningThinkingSteps(explicitDurationMs: Int? = nil) {
        let nowMs = Date().timeIntervalSince1970 * 1000
        for idx in self.streamingSteps.indices where self.streamingSteps[idx].id == "think-live" && self.streamingSteps[idx].status == "running" {
            self.streamingSteps[idx].status = "done"
            if let explicitDurationMs, explicitDurationMs > 0 {
                self.streamingSteps[idx].durationMs = explicitDurationMs
            } else if self.streamingSteps[idx].durationMs == nil, let startedAtMs = self.streamingSteps[idx].startedAtMs {
                self.streamingSteps[idx].durationMs = max(1, Int(nowMs - startedAtMs))
            }
        }
    }
    
    
    private func handlePiStreamEvent(_ event: PiAgentStreamEvent) {
        switch event {
            case .status(let label):
                self.streamingStatusLabel = label
                self.emitStreamPatch()
                
            case .thinkingStart(let startedAtMs):
                self.streamingStatusLabel = AppLanguage.text("正在深度思考…", en: "Thinking deeply...")
                if !self.streamingSteps.contains(where: { $0.id == "think-live" }) {
                    self.streamingSteps.append(BeautifulAgentThinkingStep(
                        id: "think-live",
                        label: AppLanguage.text("推理思考", en: "Reasoning"),
                        chip: nil,
                        status: "running",
                        mono: false,
                        detail: nil,
                        durationMs: nil,
                        kind: "thinking",
                        startedAtMs: startedAtMs
                    ))
                }
                self.emitStreamPatch()
                
            case .thinkingDelta(let thinking):
                self.streamingThinking = thinking
                self.streamingStatusLabel = AppLanguage.text("正在深度思考…", en: "Thinking deeply...")
                let previewLines = thinking
                    .components(separatedBy: .newlines)
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                    .suffix(3)
                    .map { String($0.prefix(140)) }
                if let idx = self.streamingSteps.firstIndex(where: { $0.id == "think-live" }) {
                    self.streamingSteps[idx].detail = previewLines.isEmpty ? nil : previewLines
                    self.streamingSteps[idx].status = "running"
                } else {
                    self.streamingSteps.append(BeautifulAgentThinkingStep(
                        id: "think-live",
                        label: AppLanguage.text("推理思考", en: "Reasoning"),
                        chip: nil,
                        status: "running",
                        mono: false,
                        detail: previewLines.isEmpty ? nil : previewLines,
                        durationMs: nil,
                        kind: "thinking",
                        startedAtMs: Date().timeIntervalSince1970 * 1000
                    ))
                }
                self.emitStreamPatch()
                
            case .thinkingEnd(let thinking, let durationMs):
                self.streamingThinking = thinking
                self.closeRunningThinkingSteps(explicitDurationMs: durationMs)
                self.emitStreamPatch()
                
            case .toolStart(let id, let name, let label, let detail, let startedAtMs):
                self.closeRunningThinkingSteps()
                self.streamingStatusLabel = detail.map { "\(label)：\($0)" } ?? label
                let step = BeautifulAgentThinkingStep(
                    id: id,
                    label: label,
                    chip: detail ?? name,
                    status: "running",
                    mono: ["bash", "grep", "read", "edit", "write"].contains(name),
                    detail: nil,
                    durationMs: nil,
                    kind: "tool",
                    startedAtMs: startedAtMs
                )
                if let idx = self.streamingSteps.firstIndex(where: { $0.id == id }) {
                    self.streamingSteps[idx] = step
                } else {
                    self.streamingSteps.append(step)
                }
                self.emitStreamPatch()
                
            case .toolUpdate(let id, let preview):
                if let idx = self.streamingSteps.firstIndex(where: { $0.id == id }) {
                    let lines = Array(preview.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.prefix(4))
                    self.streamingSteps[idx].detail = lines.isEmpty ? nil : lines
                    self.emitStreamPatch()
                }
                
            case .toolEnd(let id, _, let isError, let durationMs, let preview):
                if let idx = self.streamingSteps.firstIndex(where: { $0.id == id }) {
                    self.streamingSteps[idx].status = isError ? "error" : "done"
                    if let durationMs {
                        self.streamingSteps[idx].durationMs = durationMs
                    } else if let startedAtMs = self.streamingSteps[idx].startedAtMs {
                        self.streamingSteps[idx].durationMs = max(1, Int(Date().timeIntervalSince1970 * 1000 - startedAtMs))
                    }
                    if let preview {
                        let lines = Array(preview.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.prefix(4))
                        self.streamingSteps[idx].detail = lines.isEmpty ? nil : lines
                    }
                }
                self.streamingStatusLabel = AppLanguage.text("正在整合结果…", en: "Synthesizing answer...")
                self.emitStreamPatch()
                
            case .textDelta(let text), .textEnd(let text):
                self.closeRunningThinkingSteps()
                self.streamingDraft = Self.stripActionEnvelope(text)
                self.emitStreamPatch()
                
            case .error(let msg):
                self.lastErrorMessage = msg
                
            case .settled:
                break
        }
    }
    
    
    private func appendAssistantMessage(_ text: String, metadata: ButlerMessageMetadata, sessionID: String) {
        let assistantMsg = ButlerChatMessage(
            id: UUID().uuidString,
            sessionID: sessionID,
            role: "assistant",
            content: text,
            actionsJSON: Self.encodeMetadata(metadata),
            createdAt: Date()
        )
        self.database.appendButlerMessage(assistantMsg)
        if self.activeSessionID == sessionID {
            self.messages.append(assistantMsg)
        }
        self.sessions = self.database.fetchButlerSessions()
    }
    
    
    private func buildTurnUserPrompt(userText: String, quote: String?, contextSources: [String]) -> String {
        var sections: [String] = []
        if let quote, !quote.isEmpty {
            sections.append("<quoted_excerpt>\n\(quote)\n</quoted_excerpt>")
        }
        if !contextSources.isEmpty {
            let snap = CotAgentCoordinator.shared.lastWorkspaceSnapshot ?? CotAgentCoordinator.shared.captureWorkspaceSnapshot()
            for source in contextSources {
                switch source {
                    case "doc":
                        if let title = snap.activeDocumentTitle, let excerpt = snap.activeDocumentExcerpt {
                            sections.append("<attached_active_document title=\"\(title)\">\n\(excerpt)\n</attached_active_document>")
                        }
                    case "selection":
                        if let sel = snap.activeDocumentSelection {
                            sections.append("<attached_selection>\n\(sel)\n</attached_selection>")
                        }
                    case "watchlist":
                        let stocks = CotMarketService.shared.watchlist.prefix(12)
                            .map { "\($0.name)(\($0.symbol))" }.joined(separator: ", ")
                        if !stocks.isEmpty {
                            sections.append("<attached_watchlist>\(stocks)</attached_watchlist>")
                        }
                    case "news":
                        let items = AIHotNewsService.shared.items.prefix(8)
                            .map { "- [\($0.resolvedCategory.label)] \($0.title)" }.joined(separator: "\n")
                        if !items.isEmpty {
                            sections.append("<attached_latest_news>\n\(items)\n</attached_latest_news>")
                        }
                    default:
                        break
                }
            }
        }
        sections.append(userText)
        return sections.joined(separator: "\n\n")
    }
    
    
    private func buildPriorHistoryContext(excludingLastUserMessage: Bool) -> String? {
        let slice = excludingLastUserMessage ? self.messages.dropLast() : self.messages[...]
        let recent = Array(slice.suffix(10))
        guard !recent.isEmpty else { return nil }
        return recent.map { msg in
            let speaker = msg.role == "user" ? "用户" : self.name
            return "[\(speaker)]: \(String(msg.content.prefix(700)))"
        }.joined(separator: "\n\n")
    }
    
    
    private static func suggestFollowUps(userText: String, toolNames: [String]) -> [String] {
        if toolNames.contains("lookup_stock_quote") {
            return [
                AppLanguage.text("顺便在右侧打开看盘 K 线", en: "Open Market K-Line"),
                AppLanguage.text("查一下相关最新新闻与公告", en: "Check latest news"),
                AppLanguage.text("加入我的自选股清单", en: "Add to watchlist"),
            ]
        }
        if toolNames.contains("search_news") || toolNames.contains("web_search") {
            return [
                AppLanguage.text("把这些要点整理成新笔记", en: "Save as Markdown note"),
                AppLanguage.text("帮我深挖背后的影响与风险", en: "Analyze deeper impact"),
            ]
        }
        if toolNames.contains("read_document") || toolNames.contains("search_documents") {
            return [
                AppLanguage.text("提炼行动清单并插入编辑器", en: "Insert action items"),
                AppLanguage.text("帮我润色或重写重点段落", en: "Polish key paragraphs"),
            ]
        }
        if userText.count > 24 {
            return [
                AppLanguage.text("展开具体细节", en: "Expand details"),
                AppLanguage.text("整理成笔记保存", en: "Save as note"),
            ]
        }
        return []
    }
    
    
    private func handleOfflineCommand(_ text: String, sessionID: String) async {
        var actions: [CotAgentAction] = []
        let lower = text.lowercased()
        
        if let range = text.range(of: "以后叫你") ?? text.range(of: "改名叫") {
            let newName = text[range.upperBound...].trimmingCharacters(in: CharacterSet(charactersIn: " ：:，,。!！\"'"))
            if !newName.isEmpty {
                actions.append(CotAgentAction(type: "rename_butler", name: newName))
            }
        } else if lower.contains("看盘") || lower.contains("k线") || lower.contains("股票") {
            let query = text
                .replacingOccurrences(of: "看盘", with: "")
                .replacingOccurrences(of: "打开", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            actions.append(CotAgentAction(type: "convert_tab", board: "market", query: query))
        } else if lower.contains("播客") {
            let query = text
                .replacingOccurrences(of: "播客", with: "")
                .replacingOccurrences(of: "打开", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            actions.append(CotAgentAction(type: "convert_tab", board: "podcast", query: query))
        } else if lower.contains("news") || lower.contains("新闻") || lower.contains("资讯") {
            actions.append(CotAgentAction(type: "convert_tab", board: "news"))
        } else if text.contains("@") {
            let tokens = text.split(separator: " ").map(String.init)
            if let handle = tokens.first(where: { $0.hasPrefix("@") }) {
                actions.append(CotAgentAction(type: "follow_creator", platform: "x", handle: handle))
            }
        }
        
        let receipts = await CotAgentCoordinator.shared.execute(actions)
        let reply = receipts.isEmpty
            ? AppLanguage.text("请先在设置中为总管接入 API 订阅", en: "Configure API gateway for Butler in Settings")
            : receipts.map(\.summary).joined(separator: " · ")
        self.appendAssistantMessage(reply, metadata: ButlerMessageMetadata(receipts: receipts), sessionID: sessionID)
    }
    
    
    private static let localClockFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy年M月d日 EEEE HH:mm (ZZZZ)"
        return formatter
    }()
    
    
    func buildButlerSystemPrompt(
        resolvedConfig: AIConfiguration? = nil,
        userMessage: String = "",
        now: Date = Date(),
        piToolsAvailable: Bool = false
    ) -> String {
        let workspaceSummary = CotAgentCoordinator.shared.workspaceContextSummary()
        let kyc = self.memoryStore.compiledKYCContext()
        let globalPersona = self.database.aiPersona.trimmingCharacters(in: .whitespacesAndNewlines)
        let butlerCfg = AIBotStore.shared.config(for: .butler)
        let customPersona = butlerCfg.customPersona.trimmingCharacters(in: .whitespacesAndNewlines)
        let stagePrompt = AIBotStore.shared.systemPrompt(for: .butler).trimmingCharacters(in: .whitespacesAndNewlines)
        let activeModel = resolvedConfig?.model.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let timeString = Self.localClockFormatter.string(from: now)
        
        let lowerMsg = userMessage.lowercased()
        let botManagementKeywords = [
            "bot", "助手", "续写", "翻译", "提炼", "解释", "周报", "图表",
            "识图", "整理", "人设", "风格", "全局", "性格", "调教", "切换模型", "换模型",
        ]
        let includeBotRoster = botManagementKeywords.contains { lowerMsg.contains($0) }
        
        var lines: [String] = [
            "你是用户在 CotEditor 里的私人助手「\(self.name)」（昵称「@\(self.nickname)」）。",
            "当前本地时间：\(timeString)",
        ]
        if !activeModel.isEmpty {
            lines.append("你当前使用的模型：\(activeModel)")
        }
        if !customPersona.isEmpty {
            lines.append("用户为你设定的风格：\(customPersona)")
        }
        if !stagePrompt.isEmpty {
            lines.append("补充要求：\(stagePrompt)")
        }
        
        lines.append("""
        ## 说话方式与核心铁律（非常重要）
        - 用自然、顺耳、好懂的日常中文聊天，像一个靠谱、能真正办事的个人总管；不要端着、不要敷衍。
        - **绝对禁止光说不做、空口画饼！** 绝不能回复「好的，我这就去帮你查」「这就打开看盘看看」却不给出真实查询结果。每次回复都必须交付具体信息或实际结果。
        - 问什么答什么，直截了当：
          - 用户问现在几点、今天星期几，直接根据上面的「当前本地时间」回答。
          - 用户问你是什么模型，直接说当前模型名称，不要主动扯出其他助手配置。
        - 严禁在给用户看的回复里暴露内部技术黑话或标签：不要出现「SQLite」「数据库」「KYC」「Action」「JSON」「<cot_actions>」「Pi RPC」及英文内部 ID（如 `ghost`、`butler`、`ocrPolish`）。需要提到助手时一律用中文名（如「续写幽灵」「双语翻译官」「周报搭子」）。
        - 排版干净利落：适合用短段落、要点列表或 Markdown 表格呈现数据（尤其是行情报价与对比）。
        """)
        
        if piToolsAvailable {
            lines.append("""
            ## 你拥有的真实工具（优先直接调用，用事实说话）
            1. `lookup_stock_quote(query, period?)` — **查询 A股/港股/美股/指数的实时最新价、涨跌幅、今开最高最低与近期 K 线**。用户问任何股票现状（如「三安光电啥情况」「英伟达今天怎么样」），必须先调用本工具拿到实时行情再回答！如用户希望顺便看图，可再配合调用 `editor_action(type:"open_board", board:"market", query:...)`。
            2. `search_news(query?, category?, limit?)` — 检索 CotEditor 本地 NEWS 热点缓存与最新科技/财经资讯。
            3. `web_search(query, limit?)` & `web_fetch(url)` — 全网实时检索最新事件、财报、公告与技术文档，并可抓取网页正文精读。
            4. `get_workspace_context()` — 读取用户当前打开的标签页、正在编辑的文档正文与选中文本。
            5. `search_documents(query?, limit?)` & `read_document(idOrTitle)` — 搜索并阅读用户的本地笔记与历史周报。
            6. `read_memory()` — 读取用户已保存的长期记忆画像、股票自选池、关注信息源与创作者。
            7. `editor_action(type, ...)` — 即时控制 CotEditor 界面与记忆：
               - `open_board` / `convert_tab` (`board: "market"|"podcast"|"news"|"butler"|"document"`, `query`, `splitRight`)
               - `open_document` (`title`, `content`, `splitRight`)
               - `insert_to_editor` (`text`, `replaceSelection`)
               - `watch_stock` / `unwatch_stock`
               - `upsert_memory` / `delete_memory`
               - `rename_butler` / `update_bot` / `update_global_persona` / `play_podcast` / `follow_feed` / `follow_creator`
            8. 你还具备本地文件阅读与命令行能力，用户要求分析本地项目/代码/日志时可直接动手。
            - **原则**：凡是能通过工具查到真实信息的问题，先调用工具，拿到结果后再整理成清晰回答；无需输出 `<cot_actions>`。
            """)
        } else {
            lines.append("""
            ## 帮用户执行操作（仅在需要时使用）
            - 当用户明确需要操作编辑器（打开看盘/播客/资讯、新建文档、插入文本、改名、记住偏好、加自选股等）时，在回复末尾附带 `<cot_actions>[...]</cot_actions>` JSON 数组，系统会自动执行。
            - 可用操作：`open_board`、`convert_tab`、`open_document`、`insert_to_editor`、`rename_butler`、`update_global_persona`、`update_bot`、`upsert_memory`、`delete_memory`、`watch_stock`、`unwatch_stock`、`follow_feed`、`follow_creator`、`play_podcast`。
            """)
        }
        
        if !globalPersona.isEmpty {
            lines.append("## 用户的全局回复偏好\n\(globalPersona)")
        }
        if includeBotRoster {
            let botLines = AIBotID.allCases.map { botID -> String in
                let cfg = AIBotStore.shared.config(for: botID)
                let displayName = AIBotStore.shared.resolvedName(for: botID)
                let status = cfg.isEnabled ? "已开启" : "已关闭"
                let model = cfg.modelOverride.isEmpty ? "跟随默认模型" : cfg.modelOverride
                return "- \(displayName)（内部ID: \(botID.rawValue)）：\(status)，模型：\(model)"
            }.joined(separator: "\n")
            lines.append("## 全部助手配置（回复用户时一律使用中文名，不要说出内部ID）\n\(botLines)")
        }
        if !kyc.isEmpty {
            lines.append(kyc)
        }
        if !workspaceSummary.isEmpty {
            lines.append("## 用户当前正在看的文档与页面（仅供背景参考）\n\(workspaceSummary)")
        }
        
        return lines.joined(separator: "\n\n")
    }
    
    
    // MARK: - Action Tag Extraction & Metadata Coding
    
    static func stripActionEnvelope(_ raw: String) -> String {
        if let open = raw.range(of: "<cot_actions>") {
            return String(raw[..<open.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    
    static func extractActions(from raw: String) -> (cleanText: String, actions: [CotAgentAction]) {
        guard let start = raw.range(of: "<cot_actions>"),
              let end = raw.range(of: "</cot_actions>", range: start.upperBound..<raw.endIndex)
        else {
            return (Self.stripActionEnvelope(raw), [])
        }
        let jsonBody = String(raw[start.upperBound..<end.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let before = String(raw[..<start.lowerBound])
        let after = String(raw[end.upperBound...])
        let cleanText = (before + "\n" + after).trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard let data = jsonBody.data(using: .utf8),
              let actions = try? JSONDecoder().decode([CotAgentAction].self, from: data)
        else {
            return (cleanText, [])
        }
        return (cleanText, actions)
    }
    
    
    static func encodeMetadata(_ meta: ButlerMessageMetadata) -> String {
        if meta.thinking == nil,
           meta.thinkingDurationMs == nil,
           meta.steps.isEmpty,
           meta.toolChips.isEmpty,
           meta.quoteContext == nil,
           meta.followUps.isEmpty,
           meta.errorMessage == nil
        {
            return (try? String(data: JSONEncoder().encode(meta.receipts), encoding: .utf8)) ?? "[]"
        }
        return (try? String(data: JSONEncoder().encode(meta), encoding: .utf8)) ?? "[]"
    }
    
    
    static func decodeMetadata(from json: String) -> ButlerMessageMetadata {
        let trimmed = json.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else {
            return ButlerMessageMetadata()
        }
        if trimmed.hasPrefix("{"),
           let decoded = try? JSONDecoder().decode(ButlerMessageMetadata.self, from: data)
        {
            return decoded
        }
        if let receipts = try? JSONDecoder().decode([AppliedActionReceipt].self, from: data) {
            return ButlerMessageMetadata(receipts: receipts)
        }
        return ButlerMessageMetadata()
    }
    
    
    static func decodeReceipts(from json: String) -> [AppliedActionReceipt] {
        Self.decodeMetadata(from: json).receipts
    }
}
