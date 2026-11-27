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

/// Structured reference to a document attached via `@文档` in the Butler composer.
nonisolated struct ButlerDocumentAttachment: Codable, Sendable, Equatable, Identifiable {
    var id: String
    var title: String
    /// `"open_tab" | "stored_doc" | "weekly_report" | "workspace_file"`
    var sourceKind: String
    var filePath: String? = nil
}


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
    var attachedDocuments: [String] = []
    var delegatedBotID: String? = nil
    var delegatedBotName: String? = nil
    var delegatedModel: String? = nil
    var stickerID: String? = nil
    var stickerURL: String? = nil
    var stickerCaption: String? = nil
    
    init(
        receipts: [AppliedActionReceipt] = [],
        thinking: String? = nil,
        thinkingDurationMs: Int? = nil,
        steps: [BeautifulAgentThinkingStep] = [],
        toolChips: [String] = [],
        quoteContext: String? = nil,
        followUps: [String] = [],
        errorMessage: String? = nil,
        attachedDocuments: [String] = [],
        delegatedBotID: String? = nil,
        delegatedBotName: String? = nil,
        delegatedModel: String? = nil,
        stickerID: String? = nil,
        stickerURL: String? = nil,
        stickerCaption: String? = nil
    ) {
        self.receipts = receipts
        self.thinking = thinking
        self.thinkingDurationMs = thinkingDurationMs
        self.steps = steps
        self.toolChips = toolChips
        self.quoteContext = quoteContext
        self.followUps = followUps
        self.errorMessage = errorMessage
        self.attachedDocuments = attachedDocuments
        self.delegatedBotID = delegatedBotID
        self.delegatedBotName = delegatedBotName
        self.delegatedModel = delegatedModel
        self.stickerID = stickerID
        self.stickerURL = stickerURL
        self.stickerCaption = stickerCaption
    }
    
    enum CodingKeys: String, CodingKey {
        case receipts, thinking, thinkingDurationMs, steps, toolChips, quoteContext, followUps, errorMessage
        case attachedDocuments, delegatedBotID, delegatedBotName, delegatedModel
        case stickerID, stickerURL, stickerCaption
    }
    
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.receipts = try c.decodeIfPresent([AppliedActionReceipt].self, forKey: .receipts) ?? []
        self.thinking = try c.decodeIfPresent(String.self, forKey: .thinking)
        self.thinkingDurationMs = try c.decodeIfPresent(Int.self, forKey: .thinkingDurationMs)
        self.steps = try c.decodeIfPresent([BeautifulAgentThinkingStep].self, forKey: .steps) ?? []
        self.toolChips = try c.decodeIfPresent([String].self, forKey: .toolChips) ?? []
        self.quoteContext = try c.decodeIfPresent(String.self, forKey: .quoteContext)
        self.followUps = try c.decodeIfPresent([String].self, forKey: .followUps) ?? []
        self.errorMessage = try c.decodeIfPresent(String.self, forKey: .errorMessage)
        self.attachedDocuments = try c.decodeIfPresent([String].self, forKey: .attachedDocuments) ?? []
        self.delegatedBotID = try c.decodeIfPresent(String.self, forKey: .delegatedBotID)
        self.delegatedBotName = try c.decodeIfPresent(String.self, forKey: .delegatedBotName)
        self.delegatedModel = try c.decodeIfPresent(String.self, forKey: .delegatedModel)
        self.stickerID = try c.decodeIfPresent(String.self, forKey: .stickerID)
        self.stickerURL = try c.decodeIfPresent(String.self, forKey: .stickerURL)
        self.stickerCaption = try c.decodeIfPresent(String.self, forKey: .stickerCaption)
    }
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
    private(set) var workspaces: [ButlerWorkspaceRecord] = []
    private(set) var sessions: [ButlerSessionRecord] = []
    private(set) var activeSessionID: String = ""
    private(set) var messages: [ButlerChatMessage] = []
    private(set) var isStreaming: Bool = false
    private(set) var streamingSessionID: String?
    private(set) var streamingMessageID: String?
    @ObservationIgnored private(set) var streamingDraft: String = ""
    @ObservationIgnored private(set) var streamingThinking: String = ""
    @ObservationIgnored private(set) var streamingSteps: [BeautifulAgentThinkingStep] = []
    @ObservationIgnored private(set) var streamingStatusLabel: String = ""
    private(set) var streamingStartedAt: Date?
    private(set) var lastErrorMessage: String?
    @ObservationIgnored private var lastStreamPatchSentAt: Date = .distantPast
    
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
    @ObservationIgnored private var cachedAvatarDataURLKey: String?
    @ObservationIgnored private var cachedAvatarDataURLValue: String?
    
    
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
    
    
    private func emitStreamPatch(force: Bool = false) {
        guard let msgID = self.streamingMessageID else { return }
        let now = Date()
        if !force && now.timeIntervalSince(self.lastStreamPatchSentAt) < 0.028 {
            return
        }
        self.lastStreamPatchSentAt = now
        let elapsedMs = self.streamingStartedAt.map { max(0, Int(now.timeIntervalSince($0) * 1000)) } ?? 0
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
        self.cachedAvatarDataURLKey = nil
        self.cachedAvatarDataURLValue = nil
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
        self.cachedAvatarDataURLKey = nil
        self.cachedAvatarDataURLValue = nil
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
        let cfg = AIBotStore.shared.config(for: .butler)
        let customID = self.customAvatarImage.map { String(UInt(bitPattern: ObjectIdentifier($0))) } ?? "none"
        let cacheKey = "\(Int(pointSize))|\(self.avatarVariantIndex ?? -1)|\(customID)|\(cfg.artworkVariantIndex ?? -1)|\(cfg.endpointID?.uuidString ?? "")|\(cfg.modelOverride)"
        if self.cachedAvatarDataURLKey == cacheKey {
            return self.cachedAvatarDataURLValue
        }
        let image = AIBotStore.shared.resolvedAvatarImage(for: .butler, pointSize: pointSize)
            ?? self.customAvatarImage
            ?? AIGijinkaImageLoader.shared.thumbnail(for: self.resolvedArtwork(), maxPixelSize: pointSize)
        guard let image,
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:])
        else {
            self.cachedAvatarDataURLKey = cacheKey
            self.cachedAvatarDataURLValue = nil
            return nil
        }
        let dataURL = "data:image/png;base64,\(png.base64EncodedString())"
        self.cachedAvatarDataURLKey = cacheKey
        self.cachedAvatarDataURLValue = dataURL
        return dataURL
    }
    
    
    private static func decodeAvatarImage(from base64: String) -> NSImage? {
        let trimmed = base64.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let data = Data(base64Encoded: trimmed) else { return nil }
        return NSImage(data: data)
    }
    
    
    // MARK: - Session & Logical Workspace Management
    
    private func bootstrapSessionsAndMessages() {
        self.workspaces = self.database.fetchButlerWorkspaces()
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
    
    
    var activeSession: ButlerSessionRecord? {
        self.sessions.first(where: { $0.id == self.activeSessionID })
    }
    
    var activeWorkspaceID: String? {
        self.activeSession?.workspaceID
    }
    
    var activeWorkspace: ButlerWorkspaceRecord? {
        guard let wid = self.activeWorkspaceID else { return nil }
        return self.workspaces.first(where: { $0.id == wid })
    }
    
    var activeWorkspacePath: String? {
        self.activeSession?.workspacePath
    }
    
    
    private func resolveWorkspaceTarget(workspaceID: String?, workspacePath: String?) -> (id: String?, folderPath: String?) {
        if let rawID = workspaceID?.trimmingCharacters(in: .whitespacesAndNewlines), !rawID.isEmpty {
            if let ws = self.workspaces.first(where: { $0.id == rawID }) {
                return (ws.id, ws.folderPath)
            }
            let fresh = self.database.fetchButlerWorkspaces()
            self.workspaces = fresh
            if let ws = fresh.first(where: { $0.id == rawID }) {
                return (ws.id, ws.folderPath)
            }
        }
        if let rawPath = workspacePath?.trimmingCharacters(in: .whitespacesAndNewlines), !rawPath.isEmpty {
            let std = URL(filePath: rawPath).standardizedFileURL.path(percentEncoded: false)
            if let existing = self.workspaces.first(where: { $0.folderPath == std })
                ?? self.database.findButlerWorkspace(folderPath: std)
            {
                self.workspaces = self.database.fetchButlerWorkspaces()
                return (existing.id, existing.folderPath ?? std)
            }
            let baseName = URL(filePath: std).lastPathComponent
            let created = self.database.createButlerWorkspace(
                name: baseName.isEmpty ? std : baseName,
                folderPath: std
            )
            self.workspaces = self.database.fetchButlerWorkspaces()
            return (created.id, created.folderPath)
        }
        return (nil, nil)
    }
    
    
    func startNewSession(workspaceID: String? = nil, workspacePath: String? = nil) {
        self.lastErrorMessage = nil
        let hadStreaming = self.isStreaming
        if hadStreaming {
            self.cancelAndResetStreaming(savePartial: true, resetRPC: true)
        }
        let target = self.resolveWorkspaceTarget(workspaceID: workspaceID, workspacePath: workspacePath)
        if let active = self.sessions.first(where: { $0.id == self.activeSessionID }),
           self.messages.isEmpty,
           active.messageCount == 0
        {
            if active.workspaceID != target.id || active.workspacePath != target.folderPath {
                self.database.updateButlerSessionWorkspace(
                    id: active.id,
                    workspaceID: target.id,
                    workspacePath: target.folderPath
                )
                self.sessions = self.database.fetchButlerSessions()
            }
            if !hadStreaming, self.database === CotLocalDatabase.shared {
                PiKernelManager.shared.resetRPCSession(channel: .butler, forceAbort: true)
            }
            return
        }
        let created = self.database.createButlerSession(
            title: AppLanguage.text("新对话", en: "New Chat"),
            workspaceID: target.id,
            workspacePath: target.folderPath
        )
        self.activeSessionID = created.id
        self.database.set(created.id, forKey: CotLocalDatabase.ConfigKey.butlerActiveSessionID)
        self.sessions = self.database.fetchButlerSessions()
        self.messages = []
        if !hadStreaming, self.database === CotLocalDatabase.shared {
            PiKernelManager.shared.resetRPCSession(channel: .butler, forceAbort: true)
        }
    }
    
    
    func setSessionWorkspace(_ sessionID: String, workspaceID: String?) {
        let targetID = sessionID.isEmpty ? self.activeSessionID : sessionID
        guard !targetID.isEmpty,
              let previous = self.sessions.first(where: { $0.id == targetID })
        else { return }
        let resolved = self.resolveWorkspaceTarget(workspaceID: workspaceID, workspacePath: nil)
        guard previous.workspaceID != resolved.id || previous.workspacePath != resolved.folderPath else { return }
        self.database.updateButlerSessionWorkspace(
            id: targetID,
            workspaceID: resolved.id,
            workspacePath: resolved.folderPath
        )
        self.sessions = self.database.fetchButlerSessions()
        if targetID == self.activeSessionID,
           previous.workspacePath != resolved.folderPath,
           self.database === CotLocalDatabase.shared
        {
            PiKernelManager.shared.resetRPCSession(channel: .butler, forceAbort: false)
        }
    }
    
    
    func setSessionWorkspace(_ sessionID: String, workspacePath: String?) {
        let targetID = sessionID.isEmpty ? self.activeSessionID : sessionID
        guard !targetID.isEmpty,
              let previous = self.sessions.first(where: { $0.id == targetID })
        else { return }
        let resolved = self.resolveWorkspaceTarget(workspaceID: nil, workspacePath: workspacePath)
        guard previous.workspaceID != resolved.id || previous.workspacePath != resolved.folderPath else { return }
        self.database.updateButlerSessionWorkspace(
            id: targetID,
            workspaceID: resolved.id,
            workspacePath: resolved.folderPath
        )
        self.sessions = self.database.fetchButlerSessions()
        if targetID == self.activeSessionID,
           previous.workspacePath != resolved.folderPath,
           self.database === CotLocalDatabase.shared
        {
            PiKernelManager.shared.resetRPCSession(channel: .butler, forceAbort: false)
        }
    }
    
    
    @discardableResult
    func createWorkspace(
        name: String,
        folderPath: String? = nil,
        startSession: Bool = false,
        assignSessionID: String? = nil
    ) -> ButlerWorkspaceRecord? {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return nil }
        let created = self.database.createButlerWorkspace(name: trimmedName, folderPath: folderPath)
        self.workspaces = self.database.fetchButlerWorkspaces()
        if let assignSessionID, !assignSessionID.isEmpty {
            self.setSessionWorkspace(assignSessionID, workspaceID: created.id)
        } else if startSession {
            self.startNewSession(workspaceID: created.id)
        }
        return created
    }
    
    
    func renameWorkspace(_ workspaceID: String, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !workspaceID.isEmpty, !trimmed.isEmpty else { return }
        self.database.renameButlerWorkspace(id: workspaceID, name: trimmed)
        self.workspaces = self.database.fetchButlerWorkspaces()
        self.sessions = self.database.fetchButlerSessions()
    }
    
    
    func updateWorkspaceFolder(_ workspaceID: String, folderPath: String?) {
        guard !workspaceID.isEmpty,
              self.workspaces.contains(where: { $0.id == workspaceID })
        else { return }
        let previousActivePath = self.activeWorkspacePath
        self.database.updateButlerWorkspaceFolder(id: workspaceID, folderPath: folderPath)
        self.workspaces = self.database.fetchButlerWorkspaces()
        self.sessions = self.database.fetchButlerSessions()
        if self.activeWorkspaceID == workspaceID,
           previousActivePath != self.activeWorkspacePath,
           self.database === CotLocalDatabase.shared
        {
            PiKernelManager.shared.resetRPCSession(channel: .butler, forceAbort: false)
        }
    }
    
    
    func deleteWorkspace(_ workspaceID: String) {
        guard !workspaceID.isEmpty else { return }
        let previousActivePath = self.activeWorkspacePath
        self.database.deleteButlerWorkspace(id: workspaceID)
        self.workspaces = self.database.fetchButlerWorkspaces()
        self.sessions = self.database.fetchButlerSessions()
        if previousActivePath != self.activeWorkspacePath,
           self.database === CotLocalDatabase.shared
        {
            PiKernelManager.shared.resetRPCSession(channel: .butler, forceAbort: false)
        }
    }
    
    
    func reorderWorkspaces(_ orderedIDs: [String]) {
        guard !orderedIDs.isEmpty else { return }
        self.database.reorderButlerWorkspaces(orderedIDs: orderedIDs)
        self.workspaces = self.database.fetchButlerWorkspaces()
    }
    
    
    func moveSession(
        _ sessionID: String,
        toWorkspaceID targetWorkspaceID: String?,
        orderedSessionIDs: [String],
        isPinned: Bool? = nil
    ) {
        guard !sessionID.isEmpty,
              let previous = self.sessions.first(where: { $0.id == sessionID })
        else { return }
        let cleanTargetWS: String? = {
            guard let raw = targetWorkspaceID?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
                return nil
            }
            return raw
        }()
        let previousActivePath = self.activeWorkspacePath
        self.database.moveButlerSession(
            id: sessionID,
            toWorkspaceID: cleanTargetWS,
            orderedSessionIDs: orderedSessionIDs,
            isPinned: isPinned
        )
        self.sessions = self.database.fetchButlerSessions()
        if sessionID == self.activeSessionID,
           previousActivePath != self.activeWorkspacePath,
           previous.workspaceID != cleanTargetWS,
           self.database === CotLocalDatabase.shared
        {
            PiKernelManager.shared.resetRPCSession(channel: .butler, forceAbort: false)
        }
    }
    
    
    struct WorkspaceOption: Sendable, Equatable {
        let id: String
        let name: String
        let folderPath: String?
        let subtitle: String
        let isFolderBacked: Bool
        let isOpenInEditor: Bool
        
        var path: String { self.folderPath ?? "" }
    }
    
    
    func availableWorkspaces() -> [WorkspaceOption] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path(percentEncoded: false)
        let compactSubtitle: (String) -> String = { fullPath in
            if fullPath.hasPrefix(home) {
                return "~" + fullPath.dropFirst(home.count)
            }
            return fullPath
        }
        let openDirs: Set<String> = (self.database === CotLocalDatabase.shared)
            ? Set(CotAgentCoordinator.shared.openWorkspaceDirectories().map { $0.standardizedFileURL.path(percentEncoded: false) })
            : []
        
        return self.workspaces.map { ws in
            let cleanFolder = ws.folderPath?.trimmingCharacters(in: .whitespacesAndNewlines)
            let hasFolder = (cleanFolder?.isEmpty == false)
            let stdFolder = hasFolder ? URL(filePath: cleanFolder!).standardizedFileURL.path(percentEncoded: false) : nil
            let subtitle = stdFolder.map(compactSubtitle) ?? AppLanguage.text("逻辑工作区", en: "Logical workspace")
            let isOpen = stdFolder.map { openDirs.contains($0) } ?? false
            return WorkspaceOption(
                id: ws.id,
                name: ws.name,
                folderPath: stdFolder,
                subtitle: subtitle,
                isFolderBacked: hasFolder,
                isOpenInEditor: isOpen
            )
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
            await self.sendMessage(
                lastUser.content,
                quote: meta.quoteContext,
                delegatedBotID: meta.delegatedBotID
            )
        }
    }
    
    
    /// Resolves which specialized Bot (if any) the user targeted via chip selection or inline `@BotName` / `@Nickname` / `@Handle`.
    static func resolveDelegatedBot(
        in text: String,
        explicitBotID: String?,
        botStore: AIBotStore = .shared
    ) -> AIBotID? {
        if let raw = explicitBotID?.trimmingCharacters(in: .whitespacesAndNewlines),
           !raw.isEmpty,
           let parsed = AIBotID(rawValue: raw),
           parsed != .butler
        {
            return parsed
        }
        guard text.contains("@") else { return nil }
        let pattern = #"@([^\s@，,。！？!?：:;；()（）\[\]【】]+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let nsText = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))
        guard !matches.isEmpty else { return nil }
        
        let candidates = AIBotID.allCases.filter { $0 != .butler && $0 != .ghost }
        for match in matches {
            let token = nsText.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !token.isEmpty else { continue }
            let lower = token.lowercased()
            for botID in candidates {
                let resolvedName = botStore.resolvedName(for: botID).lowercased()
                let resolvedNick = botStore.resolvedNickname(for: botID).lowercased()
                let handleBare = botID.handle.dropFirst().lowercased()
                if lower == botID.rawValue.lowercased()
                    || lower == handleBare
                    || lower == botID.displayName.lowercased()
                    || lower == botID.defaultNickname.lowercased()
                    || lower == resolvedName
                    || lower == resolvedNick
                {
                    return botID
                }
            }
        }
        return nil
    }
    
    
    /// Matches inline `@文档名` tokens against open tabs, workspace files, stored documents, and weekly reports.
    func resolveInlineDocumentMentions(
        in text: String,
        excluding existing: [ButlerDocumentAttachment],
        workspacePath: String?
    ) -> [ButlerDocumentAttachment] {
        guard text.contains("@") else { return [] }
        let pattern = #"@([^\s@，,。！？!?：:;；()（）\[\]【】]+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let nsText = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))
        guard !matches.isEmpty else { return [] }
        
        let reserved: Set<String> = ["当前文档", "选区", "自选股", "资讯", "active", "selection", "watchlist", "news"]
        var existingIDs = Set(existing.map(\.id))
        var existingTitles = Set(existing.map { $0.title.lowercased() })
        var found: [ButlerDocumentAttachment] = []
        
        let openDocs = (self.database === CotLocalDatabase.shared)
            ? CotAgentCoordinator.shared.openEditorDocuments(maxContentChars: 200)
            : []
        let workspaceFiles: [CotAgentCoordinator.WorkspaceFileCandidate] = {
            guard let wp = workspacePath, !wp.isEmpty else { return [] }
            return CotAgentCoordinator.listWorkspaceFiles(at: URL(filePath: wp), limit: 48)
        }()
        
        for match in matches {
            let token = nsText.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
            let lower = token.lowercased()
            guard !token.isEmpty, !reserved.contains(lower), !existingTitles.contains(lower) else { continue }
            if Self.resolveDelegatedBot(in: "@\(token)", explicitBotID: nil) != nil { continue }
            
            if let openMatch = openDocs.first(where: {
                $0.title.lowercased() == lower || URL(filePath: $0.title).deletingPathExtension().lastPathComponent.lowercased() == lower
            }) {
                let att = ButlerDocumentAttachment(id: openMatch.id, title: openMatch.title, sourceKind: "open_tab", filePath: openMatch.filePath)
                if existingIDs.insert(att.id).inserted {
                    existingTitles.insert(att.title.lowercased())
                    found.append(att)
                }
                continue
            }
            if let wsMatch = workspaceFiles.first(where: {
                $0.title.lowercased() == lower || $0.relativePath.lowercased() == lower
            }) {
                let att = ButlerDocumentAttachment(id: "ws:\(wsMatch.fullPath)", title: wsMatch.title, sourceKind: "workspace_file", filePath: wsMatch.fullPath)
                if existingIDs.insert(att.id).inserted {
                    existingTitles.insert(att.title.lowercased())
                    found.append(att)
                }
                continue
            }
            if let storedMatch = self.database.documents.first(where: {
                $0.deletedAt == nil && ($0.title.lowercased() == lower || $0.title.lowercased().contains(lower))
            }) {
                let att = ButlerDocumentAttachment(id: "doc:\(storedMatch.id)", title: storedMatch.title, sourceKind: "stored_doc", filePath: storedMatch.filePath)
                if existingIDs.insert(att.id).inserted {
                    existingTitles.insert(att.title.lowercased())
                    found.append(att)
                }
                continue
            }
            if let reportMatch = self.database.weeklyReports.first(where: {
                $0.title.lowercased() == lower || $0.periodLabel.lowercased() == lower
            }) {
                let att = ButlerDocumentAttachment(id: "report:\(reportMatch.id)", title: reportMatch.title, sourceKind: "weekly_report", filePath: reportMatch.sourcePath)
                if existingIDs.insert(att.id).inserted {
                    existingTitles.insert(att.title.lowercased())
                    found.append(att)
                }
            }
        }
        return found
    }
    
    
    /// Loads full readable text for a `@文档` attachment (live open tab, local workspace file, stored document, or weekly report).
    func resolveDocumentContent(
        for attachment: ButlerDocumentAttachment,
        maxChars: Int = 36_000
    ) -> (title: String, sourceLabel: String, path: String?, content: String)? {
        switch attachment.sourceKind {
            case "open_tab":
                if self.database === CotLocalDatabase.shared {
                    let openDocs = CotAgentCoordinator.shared.openEditorDocuments(maxContentChars: maxChars)
                    if let matched = openDocs.first(where: { $0.id == attachment.id || $0.title == attachment.title }) {
                        return (matched.title, AppLanguage.text("当前打开", en: "Open Tab"), matched.filePath, matched.content)
                    }
                }
                if let path = attachment.filePath,
                   let diskText = try? String(contentsOfFile: path, encoding: .utf8)
                {
                    return (attachment.title, AppLanguage.text("本地文件", en: "File"), path, String(diskText.prefix(maxChars)))
                }
                return nil
                
            case "workspace_file":
                let rawPath = attachment.filePath ?? (attachment.id.hasPrefix("ws:") ? String(attachment.id.dropFirst(3)) : "")
                guard !rawPath.isEmpty,
                      let diskText = try? String(contentsOfFile: rawPath, encoding: .utf8)
                else { return nil }
                return (attachment.title, AppLanguage.text("工作区文件", en: "Workspace File"), rawPath, String(diskText.prefix(maxChars)))
                
            case "weekly_report":
                let cleanID = attachment.id.hasPrefix("report:") ? String(attachment.id.dropFirst(7)) : attachment.id
                if let report = self.database.weeklyReports.first(where: { $0.id == cleanID || $0.title == attachment.title }) {
                    return (report.title, AppLanguage.text("周报库", en: "Weekly Report"), report.sourcePath, String(report.content.prefix(maxChars)))
                }
                return nil
                
            default: // "stored_doc"
                let cleanID = attachment.id.hasPrefix("doc:") ? String(attachment.id.dropFirst(4)) : attachment.id
                if let record = self.database.fetchDocumentRecord(id: cleanID, filePath: attachment.filePath)
                    ?? self.database.documents.first(where: { $0.deletedAt == nil && ($0.id == cleanID || $0.title == attachment.title) })
                {
                    return (record.title, record.groupName.isEmpty ? AppLanguage.text("文档库", en: "Document") : record.groupName, record.filePath, String(record.content.prefix(maxChars)))
                }
                if let path = attachment.filePath,
                   let diskText = try? String(contentsOfFile: path, encoding: .utf8)
                {
                    return (attachment.title, AppLanguage.text("本地文件", en: "File"), path, String(diskText.prefix(maxChars)))
                }
                return nil
        }
    }
    
    
    func sendMessage(
        _ rawText: String,
        quote: String? = nil,
        contextSources: [String] = [],
        attachedDocuments: [ButlerDocumentAttachment] = [],
        delegatedBotID: String? = nil,
        stickerID: String? = nil
    ) async {
        let trimmedInput = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanStickerID = stickerID?.trimmingCharacters(in: .whitespacesAndNewlines)
        let userSticker = cleanStickerID.flatMap { CotStickerLibraryStore.shared.sticker(id: $0) }
        if let userSticker {
            CotStickerLibraryStore.shared.recordUse(id: userSticker.id)
        }
        
        let targetBot = Self.resolveDelegatedBot(in: trimmedInput, explicitBotID: delegatedBotID)
        let targetCustomBot = targetBot == nil
            ? Self.resolveDelegatedCustomBot(in: trimmedInput, explicitBotID: delegatedBotID)
            : nil
        
        if self.activeSessionID.isEmpty {
            self.bootstrapSessionsAndMessages()
        }
        let targetSessionID = self.activeSessionID
        let sessionRecord = self.sessions.first(where: { $0.id == targetSessionID })
        let sessionWorkspacePath = sessionRecord?.workspacePath
        let sessionWorkspaceName = sessionRecord?.workspaceName
        
        let inlineDocs = self.resolveInlineDocumentMentions(
            in: trimmedInput,
            excluding: attachedDocuments,
            workspacePath: sessionWorkspacePath
        )
        let allAttachedDocs = attachedDocuments + inlineDocs
        
        let text: String = {
            if !trimmedInput.isEmpty {
                let botDisplay = targetBot.map { AIBotStore.shared.resolvedName(for: $0) } ?? targetCustomBot?.name
                let botNick = targetBot.map { AIBotStore.shared.resolvedNickname(for: $0) } ?? targetCustomBot?.nickname
                if let botDisplay {
                    let lower = trimmedInput.lowercased()
                    let alreadyMentioned = [botDisplay, botNick ?? ""]
                        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                        .filter { !$0.isEmpty }
                        .contains { lower.contains("@\($0)") }
                    return alreadyMentioned ? trimmedInput : "@\(botDisplay) \(trimmedInput)"
                }
                return trimmedInput
            }
            if let targetBot {
                let botName = AIBotStore.shared.resolvedName(for: targetBot)
                if !allAttachedDocs.isEmpty {
                    let docList = allAttachedDocs.map { "「\($0.title)」" }.joined(separator: "、")
                    return AppLanguage.text("请 @\(botName) 处理 \(docList)", en: "Ask @\(botName) to process \(docList)")
                }
                return AppLanguage.text("请 @\(botName) 协助处理", en: "Ask @\(botName) to help")
            }
            if let targetCustomBot {
                return AppLanguage.text("请 @\(targetCustomBot.name) 聊聊", en: "Chat with @\(targetCustomBot.name)")
            }
            if !allAttachedDocs.isEmpty {
                let docList = allAttachedDocs.map { "「\($0.title)」" }.joined(separator: "、")
                return AppLanguage.text("帮我看看 \(docList)", en: "Review \(docList)")
            }
            return ""
        }()
        guard !text.isEmpty || userSticker != nil else { return }
        
        if self.isStreaming {
            if self.activeTurnTask == nil || self.streamingSessionID != self.activeSessionID {
                self.cancelAndResetStreaming(savePartial: true, resetRPC: false)
            } else {
                return
            }
        }
        
        let cleanQuote = quote?.trimmingCharacters(in: .whitespacesAndNewlines)
        _ = CotAgentCoordinator.shared.captureWorkspaceSnapshot()
        
        let targetBotName = targetBot.map { AIBotStore.shared.resolvedName(for: $0) } ?? targetCustomBot?.name
        let effectiveDelegatedID = targetBot?.rawValue ?? targetCustomBot?.id
        let userMeta = ButlerMessageMetadata(
            quoteContext: (cleanQuote?.isEmpty == false) ? cleanQuote : nil,
            attachedDocuments: allAttachedDocs.map(\.title),
            delegatedBotID: effectiveDelegatedID,
            delegatedBotName: targetBotName,
            stickerID: userSticker?.id,
            stickerURL: userSticker.map { CotMediaSchemeHandler.stickerURLString(id: $0.id) },
            stickerCaption: userSticker?.searchableSummary
        )
        let userMsg = ButlerChatMessage(
            id: UUID().uuidString,
            sessionID: targetSessionID,
            role: "user",
            content: text,
            actionsJSON: Self.encodeMetadata(userMeta),
            createdAt: Date()
        )
        let effectiveBotID: AIBotID = targetBot ?? .butler
        self.database.appendButlerMessage(userMsg)
        self.database.appendAIConversationLog(AIConversationLogRecord(
            id: "butler:\(userMsg.id)",
            channel: "butler",
            sessionID: targetSessionID,
            workspaceName: sessionWorkspaceName ?? "",
            botID: effectiveDelegatedID ?? effectiveBotID.rawValue,
            role: "user",
            content: text.isEmpty ? "[表情包:\(userSticker?.searchableSummary ?? "")]" : text,
            createdAt: userMsg.createdAt,
            memoryExtracted: false
        ))
        self.messages.append(userMsg)
        self.sessions = self.database.fetchButlerSessions()
        self.lastErrorMessage = nil
        let resolvedConfig = targetCustomBot.map { AIBotStore.shared.resolvedConfiguration(forBotID: $0.id) }
            ?? AIBotStore.shared.resolvedConfiguration(for: effectiveBotID)
        let llmUserText: String = {
            if let userSticker {
                return text.isEmpty
                    ? "用户发了一张表情包（\(userSticker.promptDescription)）"
                    : "\(text)（附带表情包：\(userSticker.searchableSummary)）"
            }
            return text
        }()
        guard resolvedConfig.isUsable else {
            await self.handleOfflineCommand(llmUserText, sessionID: targetSessionID)
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
        self.streamingStatusLabel = if let targetBotName {
            AppLanguage.text("\(targetBotName) 正在处理…", en: "\(targetBotName) is working...")
        } else {
            AppLanguage.text("正在思考…", en: "Thinking...")
        }
        self.streamingStartedAt = Date()
        
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            if let targetBot {
                await self.performDelegatedBotTurn(
                    botID: targetBot,
                    userText: llmUserText,
                    quote: cleanQuote,
                    contextSources: contextSources,
                    attachedDocuments: allAttachedDocs,
                    sessionID: targetSessionID,
                    workspacePath: sessionWorkspacePath,
                    resolvedConfig: resolvedConfig,
                    generation: turnGeneration
                )
            } else if let targetCustomBot {
                await self.performDelegatedCustomBotTurn(
                    bot: targetCustomBot,
                    userText: llmUserText,
                    quote: cleanQuote,
                    attachedDocuments: allAttachedDocs,
                    sessionID: targetSessionID,
                    resolvedConfig: resolvedConfig,
                    generation: turnGeneration
                )
            } else {
                await self.performTurn(
                    userText: llmUserText,
                    quote: cleanQuote,
                    contextSources: contextSources,
                    attachedDocuments: allAttachedDocs,
                    sessionID: targetSessionID,
                    workspacePath: sessionWorkspacePath,
                    resolvedConfig: resolvedConfig,
                    generation: turnGeneration
                )
            }
        }
        self.activeTurnTask = task
        await task.value
        if self.activeTurnGeneration == turnGeneration {
            self.activeTurnTask = nil
        }
    }
    
    
    static func resolveDelegatedCustomBot(
        in text: String,
        explicitBotID: String?,
        botStore: AIBotStore = .shared
    ) -> CustomBotProfile? {
        if let raw = explicitBotID?.trimmingCharacters(in: .whitespacesAndNewlines),
           !raw.isEmpty,
           let matched = botStore.customBots.first(where: { $0.id == raw && $0.isEnabled })
        {
            return matched
        }
        let lower = text.lowercased()
        guard lower.contains("@") else { return nil }
        return botStore.customBots.first { bot in
            guard bot.isEnabled else { return false }
            let n = bot.name.lowercased()
            let nick = bot.nickname.lowercased()
            return (!n.isEmpty && lower.contains("@\(n)")) || (!nick.isEmpty && lower.contains("@\(nick)"))
        }
    }
    
    
    private func performDelegatedCustomBotTurn(
        bot: CustomBotProfile,
        userText: String,
        quote: String?,
        attachedDocuments: [ButlerDocumentAttachment],
        sessionID: String,
        resolvedConfig: AIConfiguration,
        generation: UInt64
    ) async {
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
        let emotion = AIBotStore.shared.emotionState(for: bot.id)
        let candidates = CotStickerLibraryStore.shared.searchRelevantForReply(
            query: userText,
            mood: emotion.mood.displayLabel,
            preferredCategories: bot.preferredStickerCategories,
            limit: 5
        )
        let stickerBlock = MeetingRoomPersona.buildStickerProtocolBlock(
            candidates: candidates,
            allowStickerOnly: true,
            allowOnlineSearch: !candidates.isEmpty && OnlineStickerSearchService.isAutoExpansionEnabled
        )
        let systemPrompt = """
        你是「\(bot.name)」。\(bot.personaPrompt)
        \(emotion.baseline.promptDirective) 当前心情「\(emotion.mood.displayLabel)」，\(emotion.mood.toneDirective)
        说话原则：
        - 像熟络靠谱的真人搭档，直接说重点、不啰嗦；闲聊短句直给，涉及多条事项或方案分析时主动用 `- ` 短分点，每条 1 句话。
        - 严禁 AI 客套起手（“好的！”“当然可以”“明白你的意思了”）和套话收尾（“综上所述”“希望对你有帮助”“随时告诉我”）。
        \(stickerBlock)
        """
        let prompt = self.buildTurnUserPrompt(
            userText: userText,
            quote: quote,
            contextSources: [],
            attachedDocuments: attachedDocuments
        )
        do {
            let raw = try await AIService.shared.chat(
                [.system(systemPrompt), .user(prompt)],
                configuration: resolvedConfig,
                analyticsFeature: "custom_bot_\(bot.id)"
            ) { [weak self] partial in
                guard let self, self.activeTurnGeneration == generation else { return }
                self.streamingDraft = BotReplyDirectiveParser.stripDirectivesForLiveDisplay(partial)
                self.emitStreamPatch()
            }
            guard self.activeTurnGeneration == generation else { return }
            let parsed = BotReplyDirectiveParser.parse(
                raw: raw,
                allowedStickerIDs: Set(candidates.map(\.id)),
                allowStickerOnly: true,
                stickerOnlyCountInTurn: 0,
                allowOnlineSearch: OnlineStickerSearchService.isAutoExpansionEnabled
            )
            var sticker = parsed.stickerID.flatMap { CotStickerLibraryStore.shared.sticker(id: $0) }
            if sticker == nil, let sq = parsed.searchStickerQuery {
                sticker = await OnlineStickerSearchService.searchAndAutoExpand(
                    query: sq,
                    preferredCategory: bot.preferredStickerCategories.first ?? "reaction"
                )
            }
            if let sticker { CotStickerLibraryStore.shared.recordUse(id: sticker.id) }
            AIBotStore.shared.updateEmotion(for: bot.id, userPrompt: userText, botReply: parsed.text, explicitMood: parsed.mood)
            let meta = ButlerMessageMetadata(
                delegatedBotID: bot.id,
                delegatedBotName: bot.name,
                delegatedModel: resolvedConfig.wireConfiguration.model,
                stickerID: sticker?.id,
                stickerURL: sticker.map { CotMediaSchemeHandler.stickerURLString(id: $0.id) },
                stickerCaption: sticker?.searchableSummary
            )
            self.appendAssistantMessage(parsed.text, metadata: meta, sessionID: sessionID)
        } catch {
            guard self.activeTurnGeneration == generation else { return }
            let meta = ButlerMessageMetadata(errorMessage: error.localizedDescription, delegatedBotID: bot.id, delegatedBotName: bot.name)
            self.appendAssistantMessage(error.localizedDescription, metadata: meta, sessionID: sessionID)
        }
    }
    
    
    private func resolveWorkingDirectory(sessionWorkspacePath: String?) -> URL? {
        if let raw = sessionWorkspacePath?.trimmingCharacters(in: .whitespacesAndNewlines),
           !raw.isEmpty,
           FileManager.default.fileExists(atPath: raw)
        {
            return URL(filePath: raw).standardizedFileURL
        }
        return nil
    }
    
    
    private func performDelegatedBotTurn(
        botID: AIBotID,
        userText: String,
        quote: String?,
        contextSources: [String],
        attachedDocuments: [ButlerDocumentAttachment],
        sessionID: String,
        workspacePath: String?,
        resolvedConfig: AIConfiguration,
        generation: UInt64
    ) async {
        let turnClockStart = ContinuousClock.now
        let botName = AIBotStore.shared.resolvedName(for: botID)
        let effectiveModel = resolvedConfig.wireConfiguration.model
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
        
        let docTitles = attachedDocuments.map(\.title)
        let stepChip = docTitles.isEmpty ? effectiveModel : "\(botName) · \(docTitles.prefix(2).joined(separator: "、"))"
        let delegateStepID = "delegate-\(botID.rawValue)"
        let delegateStepStart = Date().timeIntervalSince1970 * 1000
        self.streamingSteps = [
            BeautifulAgentThinkingStep(
                id: delegateStepID,
                label: AppLanguage.text("调度助手", en: "Delegating Bot"),
                chip: stepChip,
                status: "running",
                mono: false,
                detail: docTitles.isEmpty ? nil : docTitles.map { "📄 \($0)" },
                durationMs: nil,
                kind: "tool",
                startedAtMs: delegateStepStart
            ),
        ]
        self.streamingStatusLabel = AppLanguage.text("\(botName) 正在处理…", en: "\(botName) is working...")
        self.emitStreamPatch(force: true)
        
        let botSystemPrompt = self.buildDelegatedBotSystemPrompt(
            for: botID,
            workspacePath: workspacePath
        )
        let augmentedUserPrompt = self.buildTurnUserPrompt(
            userText: userText,
            quote: quote,
            contextSources: contextSources,
            attachedDocuments: attachedDocuments,
            delegatedBotID: botID
        )
        
        let toolProfile = AIBotStore.shared.config(for: botID).effectiveToolProfile(for: botID)
        let shouldTryPiRPC = self.database === CotLocalDatabase.shared
            && PiKernelManager.shared.canRunRPC
            && toolProfile != .pureChat
            && (workspacePath != nil || attachedDocuments.isEmpty)
        
        if shouldTryPiRPC,
           let endpointProfile = AIBotStore.shared.resolvedEndpointProfile(for: botID)
        {
            let workingDir = self.resolveWorkingDirectory(sessionWorkspacePath: workspacePath)
            do {
                let result = try await PiKernelManager.shared.runRPCTurn(
                    channel: .butler,
                    logicalSessionKey: "\(sessionID):bot:\(botID.rawValue)",
                    systemPrompt: botSystemPrompt,
                    userPrompt: augmentedUserPrompt,
                    priorHistoryContext: nil,
                    endpointProfile: endpointProfile,
                    configuration: resolvedConfig,
                    workingDirectory: workingDir
                ) { [weak self] event in
                    guard let self, self.activeTurnGeneration == generation else { return }
                    self.handlePiStreamEvent(event)
                }
                guard self.activeTurnGeneration == generation else { return }
                await CotAgentCoordinator.shared.drainCommandQueueNow()
                guard self.activeTurnGeneration == generation else { return }
                
                let extracted = Self.extractActions(from: result.text)
                let receipts = extracted.actions.isEmpty ? [] : await CotAgentCoordinator.shared.execute(extracted.actions)
                guard self.activeTurnGeneration == generation else { return }
                
                let replyText = extracted.cleanText.isEmpty
                    ? (result.aborted ? AppLanguage.text("已停止生成。", en: "Stopped.") : AppLanguage.text("已处理完毕。", en: "Done."))
                    : extracted.cleanText
                
                let elapsed = turnClockStart.duration(to: .now)
                let latencyMs = max(1, Int(elapsed.components.seconds * 1000) + Int(elapsed.components.attoseconds / 1_000_000_000_000_000))
                AnalyticsManager.shared.recordAIUsage(
                    feature: botID.analyticsFeatureKey,
                    model: effectiveModel,
                    provider: "Pi RPC · \(resolvedConfig.wireConfiguration.endpoint.label)",
                    inputTokens: AINextTokenPredictor.estimateTokens(in: botSystemPrompt + "\n" + augmentedUserPrompt),
                    outputTokens: AINextTokenPredictor.estimateTokens(in: replyText + "\n" + result.thinking),
                    latencyMs: latencyMs,
                    success: true
                )
                
                var finalSteps = result.steps
                finalSteps.insert(
                    BeautifulAgentThinkingStep(
                        id: delegateStepID,
                        label: AppLanguage.text("调度助手", en: "Delegated Bot"),
                        chip: stepChip,
                        status: "done",
                        mono: false,
                        detail: docTitles.isEmpty ? nil : docTitles.map { "📄 \($0)" },
                        durationMs: latencyMs,
                        kind: "tool",
                        startedAtMs: delegateStepStart
                    ),
                    at: 0
                )
                let meta = ButlerMessageMetadata(
                    receipts: receipts,
                    thinking: result.thinking.isEmpty ? nil : result.thinking,
                    thinkingDurationMs: result.thinkingDurationMs > 0 ? result.thinkingDurationMs : latencyMs,
                    steps: finalSteps,
                    toolChips: [botName] + result.toolNames.map { PiToolDisplayMeta.label(for: $0) },
                    followUps: [],
                    attachedDocuments: docTitles,
                    delegatedBotID: botID.rawValue,
                    delegatedBotName: botName,
                    delegatedModel: effectiveModel
                )
                self.appendAssistantMessage(replyText, metadata: meta, sessionID: sessionID)
                return
            } catch is CancellationError {
                guard self.activeTurnGeneration == generation else { return }
                let partial = Self.stripActionEnvelope(self.streamingDraft)
                let final = partial.isEmpty ? AppLanguage.text("已停止生成。", en: "Stopped.") : partial
                let meta = ButlerMessageMetadata(
                    thinking: self.streamingThinking.isEmpty ? nil : self.streamingThinking,
                    steps: self.streamingSteps,
                    attachedDocuments: docTitles,
                    delegatedBotID: botID.rawValue,
                    delegatedBotName: botName,
                    delegatedModel: effectiveModel
                )
                self.appendAssistantMessage(final, metadata: meta, sessionID: sessionID)
                return
            } catch {
                guard self.activeTurnGeneration == generation, !Task.isCancelled else { return }
                self.streamingDraft = ""
                self.streamingThinking = ""
            }
        }
        
        guard self.activeTurnGeneration == generation, !Task.isCancelled else { return }
        
        let aiMessages: [AIMessage] = [
            .system(botSystemPrompt),
            .user(augmentedUserPrompt),
        ]
        var lastDraftFlushAt: Date = .distantPast
        do {
            let fullRaw = try await AIService.shared.chat(
                aiMessages,
                configuration: resolvedConfig,
                analyticsFeature: botID.analyticsFeatureKey
            ) { [weak self] partial in
                guard let self, self.activeTurnGeneration == generation else { return }
                let now = Date()
                guard now.timeIntervalSince(lastDraftFlushAt) >= 0.04 else { return }
                lastDraftFlushAt = now
                self.streamingDraft = BotReplyDirectiveParser.stripDirectivesForLiveDisplay(Self.stripActionEnvelope(partial))
                self.emitStreamPatch()
            }
            guard self.activeTurnGeneration == generation else { return }
            let elapsed = turnClockStart.duration(to: .now)
            let latencyMs = max(1, Int(elapsed.components.seconds * 1000) + Int(elapsed.components.attoseconds / 1_000_000_000_000_000))
            let cleanReply = Self.stripActionEnvelope(fullRaw)
            let doneStep = BeautifulAgentThinkingStep(
                id: delegateStepID,
                label: AppLanguage.text("调度助手", en: "Delegated Bot"),
                chip: stepChip,
                status: "done",
                mono: false,
                detail: docTitles.isEmpty ? nil : docTitles.map { "📄 \($0)" },
                durationMs: latencyMs,
                kind: "tool",
                startedAtMs: delegateStepStart
            )
            let meta = ButlerMessageMetadata(
                thinkingDurationMs: latencyMs,
                steps: [doneStep],
                toolChips: [botName],
                followUps: [],
                attachedDocuments: docTitles,
                delegatedBotID: botID.rawValue,
                delegatedBotName: botName,
                delegatedModel: effectiveModel
            )
            self.appendAssistantMessage(cleanReply.isEmpty ? AppLanguage.text("已处理完毕。", en: "Done.") : cleanReply, metadata: meta, sessionID: sessionID)
        } catch is CancellationError {
            guard self.activeTurnGeneration == generation else { return }
            let partial = Self.stripActionEnvelope(self.streamingDraft)
            if !partial.isEmpty {
                let meta = ButlerMessageMetadata(
                    steps: self.streamingSteps,
                    attachedDocuments: docTitles,
                    delegatedBotID: botID.rawValue,
                    delegatedBotName: botName,
                    delegatedModel: effectiveModel
                )
                self.appendAssistantMessage(partial, metadata: meta, sessionID: sessionID)
            }
        } catch {
            guard self.activeTurnGeneration == generation else { return }
            self.lastErrorMessage = error.localizedDescription
            let meta = ButlerMessageMetadata(
                errorMessage: error.localizedDescription,
                attachedDocuments: docTitles,
                delegatedBotID: botID.rawValue,
                delegatedBotName: botName,
                delegatedModel: effectiveModel
            )
            self.appendAssistantMessage(error.localizedDescription, metadata: meta, sessionID: sessionID)
        }
    }
    
    
    func buildDelegatedBotSystemPrompt(for botID: AIBotID, workspacePath: String?) -> String {
        let botName = AIBotStore.shared.resolvedName(for: botID)
        let stagePrompt = AIBotStore.shared.systemPrompt(for: botID).trimmingCharacters(in: .whitespacesAndNewlines)
        let customPersona = AIBotStore.shared.config(for: botID).customPersona.trimmingCharacters(in: .whitespacesAndNewlines)
        let globalPersona = self.database.aiPersona.trimmingCharacters(in: .whitespacesAndNewlines)
        
        var parts: [String] = [
            "你现在以 CotEditor 专业助手「\(botName)」的身份执行用户指派的任务。",
        ]
        if !stagePrompt.isEmpty {
            parts.append(stagePrompt)
        }
        if botID == .organizeAndMerge {
            parts.append("注意：本次是在对话面板中由用户直接调用，除非用户明确要求 JSON，请直接输出清晰整理后的文档正文与简明合并说明，方便用户一键插入或存为新笔记。")
        }
        if !customPersona.isEmpty {
            parts.append("角色风格要求：\(customPersona)")
        }
        if !globalPersona.isEmpty {
            parts.append("用户的全局表达偏好：\(globalPersona)")
        }
        if let wp = workspacePath?.trimmingCharacters(in: .whitespacesAndNewlines), !wp.isEmpty {
            let url = URL(filePath: wp)
            let overview = CotAgentCoordinator.workspaceDirectoryOverview(at: url)
            var wsBlock = "当前会话绑定的工作区：\(url.lastPathComponent)（\(wp)）"
            if !overview.isEmpty {
                wsBlock += "\n顶层目录：\(overview)"
            }
            parts.append(wsBlock)
        } else if let wsName = self.activeSession?.workspaceName, !wsName.isEmpty {
            parts.append("当前会话所在逻辑工作区：\(wsName)（逻辑主题分区，围绕用户的提问自由展开解答）。")
        }
        return parts.joined(separator: "\n\n")
    }
    
    
    private func performTurn(
        userText: String,
        quote: String?,
        contextSources: [String],
        attachedDocuments: [ButlerDocumentAttachment],
        sessionID: String,
        workspacePath: String?,
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
            contextSources: contextSources,
            attachedDocuments: attachedDocuments
        )
        let priorHistory = self.buildPriorHistoryContext(excludingLastUserMessage: true)
        let workingDir = self.resolveWorkingDirectory(sessionWorkspacePath: workspacePath)
        
        // 1. Primary path: Warm Persistent Pi RPC Kernel with native Cot tools
        if self.database === CotLocalDatabase.shared,
           PiKernelManager.shared.canRunRPC,
           let endpointProfile = AIBotStore.shared.resolvedEndpointProfile(for: .butler)
        {
            let piSystemPrompt = self.buildButlerSystemPrompt(
                resolvedConfig: resolvedConfig,
                userMessage: userText,
                piToolsAvailable: true,
                workspacePath: workspacePath
            )
            
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
                    followUps: []
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
                self.emitStreamPatch(force: true)
            }
        }
        
        guard self.activeTurnGeneration == generation, !Task.isCancelled else { return }
        
        // 2. Resilient fallback path: Native Swift tool lookup (real quotes + news) + direct SSE streaming
        let enriched = await CotSwiftToolFallback.enrichIfNeeded(for: userText)
        guard self.activeTurnGeneration == generation, !Task.isCancelled else { return }
        if !enriched.steps.isEmpty {
            self.streamingSteps = enriched.steps
            self.streamingStatusLabel = AppLanguage.text("正在整理回复…", en: "Composing reply...")
            self.emitStreamPatch(force: true)
        }
        
        let systemPrompt = self.buildButlerSystemPrompt(
            resolvedConfig: resolvedConfig,
            userMessage: userText,
            piToolsAvailable: false,
            workspacePath: workspacePath
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
                self.streamingDraft = BotReplyDirectiveParser.stripDirectivesForLiveDisplay(Self.stripActionEnvelope(partial))
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
            let meta = ButlerMessageMetadata(
                receipts: receipts,
                thinkingDurationMs: totalToolMs > 0 ? totalToolMs : nil,
                steps: enriched.steps,
                toolChips: enriched.steps.map(\.label),
                followUps: []
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
                self.emitStreamPatch(force: true)
                
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
                self.emitStreamPatch(force: true)
                
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
                self.emitStreamPatch(force: false)
                
            case .thinkingEnd(let thinking, let durationMs):
                self.streamingThinking = thinking
                self.closeRunningThinkingSteps(explicitDurationMs: durationMs)
                self.emitStreamPatch(force: true)
                
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
                self.emitStreamPatch(force: true)
                
            case .toolUpdate(let id, let preview):
                if let idx = self.streamingSteps.firstIndex(where: { $0.id == id }) {
                    let lines = Array(preview.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.prefix(4))
                    self.streamingSteps[idx].detail = lines.isEmpty ? nil : lines
                    self.emitStreamPatch(force: false)
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
                self.emitStreamPatch(force: true)
                
            case .textDelta(let text):
                self.closeRunningThinkingSteps()
                self.streamingDraft = Self.stripActionEnvelope(text)
                self.emitStreamPatch(force: false)
                
            case .textEnd(let text):
                self.closeRunningThinkingSteps()
                self.streamingDraft = Self.stripActionEnvelope(text)
                self.emitStreamPatch(force: true)
                
            case .error(let msg):
                self.lastErrorMessage = msg
                
            case .settled:
                break
        }
    }
    
    
    /// Posts a proactive daily report message from the Butler into the active session.
    func postDailyReport(text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if self.activeSessionID.isEmpty {
            self.startNewSession()
        }
        guard !self.activeSessionID.isEmpty else { return }
        self.appendAssistantMessage(trimmed, metadata: ButlerMessageMetadata(), sessionID: self.activeSessionID)
    }
    
    
    private func appendAssistantMessage(_ text: String, metadata: ButlerMessageMetadata, sessionID: String) {
        // Enrich with emotion & optional sticker directive resolution
        var enrichedMeta = metadata
        let isUserStickerTurn = text.contains("表情包") || self.messages.last?.actionsJSON.contains("stickerID") == true
        if metadata.errorMessage == nil && !text.isEmpty {
            let botKey = metadata.delegatedBotID ?? AIBotID.butler.rawValue
            let allowedIDs = Set(CotStickerLibraryStore.shared.stickers.map(\.id))
            let parsed = BotReplyDirectiveParser.parse(
                raw: text,
                allowedStickerIDs: allowedIDs,
                allowStickerOnly: true,
                stickerOnlyCountInTurn: 0,
                allowOnlineSearch: OnlineStickerSearchService.isAutoExpansionEnabled
            )
            var resolvedText = parsed.text
            if let sid = parsed.stickerID, let stk = CotStickerLibraryStore.shared.sticker(id: sid) {
                CotStickerLibraryStore.shared.recordUse(id: stk.id)
                enrichedMeta.stickerID = stk.id
                enrichedMeta.stickerURL = CotMediaSchemeHandler.stickerURLString(id: stk.id)
                enrichedMeta.stickerCaption = stk.searchableSummary
            }
            AIBotStore.shared.updateEmotion(for: botKey, userPrompt: self.messages.last?.content ?? "", botReply: resolvedText, explicitMood: parsed.mood)
            let assistantMsg = ButlerChatMessage(
                id: UUID().uuidString,
                sessionID: sessionID,
                role: "assistant",
                content: resolvedText,
                actionsJSON: Self.encodeMetadata(enrichedMeta),
                createdAt: Date()
            )
            self.database.appendButlerMessage(assistantMsg)
            let wsName = self.sessions.first(where: { $0.id == sessionID })?.workspaceName ?? ""
            self.database.appendAIConversationLog(AIConversationLogRecord(
                id: "butler:\(assistantMsg.id)",
                channel: "butler",
                sessionID: sessionID,
                workspaceName: wsName,
                botID: enrichedMeta.delegatedBotID ?? "butler",
                role: "assistant",
                content: resolvedText,
                createdAt: assistantMsg.createdAt,
                memoryExtracted: false
            ))
            if self.database === CotLocalDatabase.shared && !CotLocalDatabase.isRunningUnitTests {
                CotMemoryExtractionAgent.shared.scheduleExtractionIfNeeded(reason: "butler_turn")
            }
            if self.activeSessionID == sessionID {
                self.messages.append(assistantMsg)
            }
            self.sessions = self.database.fetchButlerSessions()
            return
        }
        let assistantMsg = ButlerChatMessage(
            id: UUID().uuidString,
            sessionID: sessionID,
            role: "assistant",
            content: text,
            actionsJSON: Self.encodeMetadata(enrichedMeta),
            createdAt: Date()
        )
        self.database.appendButlerMessage(assistantMsg)
        if self.activeSessionID == sessionID {
            self.messages.append(assistantMsg)
        }
        self.sessions = self.database.fetchButlerSessions()
    }
    
    
    func buildTurnUserPrompt(
        userText: String,
        quote: String?,
        contextSources: [String],
        attachedDocuments: [ButlerDocumentAttachment] = [],
        delegatedBotID: AIBotID? = nil
    ) -> String {
        var sections: [String] = []
        if let quote, !quote.isEmpty {
            sections.append("<quoted_excerpt>\n\(quote)\n</quoted_excerpt>")
        }
        for doc in attachedDocuments {
            if let resolved = self.resolveDocumentContent(for: doc) {
                let pathAttr = resolved.path.map { " path=\"\($0)\"" } ?? ""
                sections.append("<attached_document title=\"\(resolved.title)\" source=\"\(resolved.sourceLabel)\"\(pathAttr)>\n\(resolved.content)\n</attached_document>")
            }
        }
        if delegatedBotID == .weeklyReport {
            let recentReports = self.database.weeklyReports.prefix(2)
            if !recentReports.isEmpty {
                let styleSamples = recentReports.map { rep in
                    "--- 历史周报示例：\(rep.title) (\(rep.periodLabel)) ---\n\(String(rep.content.prefix(1800)))"
                }.joined(separator: "\n\n")
                sections.append("<historical_weekly_report_style>\n\(styleSamples)\n</historical_weekly_report_style>")
            }
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
        piToolsAvailable: Bool = false,
        workspacePath: String? = nil,
        workspaceName: String? = nil
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
        - **说人话、去 AI 味、简练直给**：像一个脑子快、靠谱、懂分寸的真人搭档，别端着也别写长篇大论。
        - **严禁 AI 套话**：不要用「好的！」「没问题！」「当然可以」「这是一个很好的问题」「明白你的意思了」起手；不要用「综上所述」「总的来说」「希望对你有帮助」「如果你还有任何问题随时告诉我」收尾。
        - **结论先行，善用短分点**：简单问题 1～2 句直接给答案；涉及 2 个以上要点、方案对比、排查步骤或数据解读时，先抛 1 句核心判断，再用干净的 `- ` 短分点或精简表格呈现，每条控制在 1～2 句，一眼能扫完，不堆文字墙。
        - **绝对禁止光说不做、空口画饼！** 绝不能回复「好的，我这就去帮你查」「这就打开看盘看看」却不给出真实查询结果。每次回复都必须交付具体信息或实际结果。
        - 问什么答什么：
          - 问现在几点、今天星期几，直接用上面的「当前本地时间」答。
          - 问你是什么模型，直接报当前模型名，不扯无关配置。
        - 严禁暴露内部技术黑话或标签（不要出现「SQLite」「数据库」「KYC」「Action」「JSON」「<cot_actions>」「Pi RPC」及英文内部 ID）；提到助手时一律用中文名（如「续写幽灵」「双语翻译官」「周报搭子」）。
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
            8. `find_and_download_podcast(topic, reason?, openBoard?)` — 当用户说「帮我找一期关于某知识的播客、下载进来并提醒我听」时调用此工具；后台会自动搜索、下载音频到播客看板并发送收听提醒。
            9. 你还具备本地文件阅读与命令行能力，用户要求分析本地项目/代码/日志时可直接动手。
            - **原则**：凡是能通过工具查到真实信息的问题，先调用工具，拿到结果后再整理成清晰回答；无需输出 `<cot_actions>`。
            """)
        } else {
            lines.append("""
            ## 帮用户执行操作（仅在需要时使用）
            - 当用户明确需要操作编辑器（打开看盘/播客/资讯、新建文档、插入文本、改名、记住偏好、加自选股、找并下载播客等）时，在回复末尾附带 `<cot_actions>[...]</cot_actions>` JSON 数组，系统会自动执行。
            - 可用操作：`open_board`、`convert_tab`、`open_document`、`insert_to_editor`、`rename_butler`、`update_global_persona`、`update_bot`、`upsert_memory`、`delete_memory`、`watch_stock`、`unwatch_stock`、`follow_feed`、`follow_creator`、`play_podcast`、`curate_podcast`。
            """)
        }
        
        if self.database === CotLocalDatabase.shared {
            let snap = CotAgentCoordinator.shared.lastWorkspaceSnapshot
            let personal = CotButlerProactiveEngine.shared.buildDeepPersonalContextSummary(
                watchlist: CotMarketService.shared.watchlist,
                quotes: CotMarketService.shared.quotes,
                memories: self.memoryStore.memories,
                unreadPodcasts: CotPodcastService.shared.unreadReminders,
                browsingHistory: AIHotNewsService.shared.browsingHistory,
                activeDocTitle: snap?.activeDocumentTitle
            )
            if !personal.isEmpty {
                lines.append("## 你对这位用户的深度了解（自然融入对话与主动建议中，勿机械复读）\n\(personal)")
            }
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
        if let wp = workspacePath?.trimmingCharacters(in: .whitespacesAndNewlines), !wp.isEmpty {
            let url = URL(filePath: wp)
            let overview = CotAgentCoordinator.workspaceDirectoryOverview(at: url)
            let label = workspaceName ?? self.activeSession?.workspaceName ?? url.lastPathComponent
            var wsSection = "## 当前会话绑定的工作区\n工作区名：\(label)\n本地目录：\(wp)"
            if !overview.isEmpty {
                wsSection += "\n顶层内容：\(overview)"
            }
            wsSection += "\n请优先围绕这个工作区回答问题或使用文件/检索工具。"
            lines.append(wsSection)
        } else if let wsName = (workspaceName ?? self.activeSession?.workspaceName)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !wsName.isEmpty
        {
            lines.append("""
            ## 当前会话所在工作区
            工作区名称：\(wsName)
            这是一个逻辑主题工作区（未绑定本地磁盘目录）。请围绕用户在这个工作区里提出的问题自由展开讨论、分析与回答，无需假定本地文件系统路径。
            """)
        }
        if !workspaceSummary.isEmpty {
            lines.append("## 用户当前正在看的文档与页面（仅供背景参考）\n\(workspaceSummary)")
        }
        
        let butlerEmotion = AIBotStore.shared.emotionState(for: AIBotID.butler.rawValue)
        let stickerCandidates = CotStickerLibraryStore.shared.searchRelevantForReply(
            query: userMessage,
            mood: butlerEmotion.mood.displayLabel,
            limit: 5
        )
        if !stickerCandidates.isEmpty {
            lines.append(MeetingRoomPersona.buildStickerProtocolBlock(
                candidates: stickerCandidates,
                allowStickerOnly: true,
                allowOnlineSearch: OnlineStickerSearchService.isAutoExpansionEnabled
            ))
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
           meta.errorMessage == nil,
           meta.attachedDocuments.isEmpty,
           meta.delegatedBotID == nil,
           meta.delegatedBotName == nil,
           meta.delegatedModel == nil
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
