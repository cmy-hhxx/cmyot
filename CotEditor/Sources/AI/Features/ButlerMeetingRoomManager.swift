//
//  ButlerMeetingRoomManager.swift
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

import Foundation
import Observation
import SQLite3

// MARK: - Meeting Room Pure Models & Routing

nonisolated enum MeetingDispatchMode: Equatable, Sendable {
    /// All active core Bots report directly to the user (hub-and-spoke, no Bot-to-Bot chatter),
    /// followed by Chief Butler's executive synthesis.
    case allHandsStandup(participants: [AIBotID])
    /// User directly @-mentioned one or more specific Bots to report or refresh.
    case directCallout(targets: [AIBotID], shouldRefresh: Bool)
    /// User instructed Chief Butler to govern/coordinate other Bots on their behalf.
    case butlerGoverned(subordinates: [AIBotID], shouldRefresh: Bool)
}


nonisolated struct MeetingDispatchPlan: Equatable, Sendable {
    let mode: MeetingDispatchMode
    let cleanedPrompt: String
    let mentionedBots: [AIBotID]
}


nonisolated struct MeetingRoomMessage: Identifiable, Codable, Equatable, Sendable {
    var id: String
    /// `"user"` or `"bot"`
    var role: String
    var botID: String?
    var botName: String?
    var botHandle: String?
    var botAccentHex: String?
    var botRoleLabel: String?
    var botMoodLabel: String?
    var botAvatarURL: String?
    var text: String
    var stickerID: String?
    var stickerURL: String?
    var stickerCaption: String?
    /// `"speaking"` | `"done"` | `"error"`
    var status: String
    var receipts: [String]
    var delegatedFromButler: Bool
    var createdAtMs: Double
    
    init(
        id: String,
        role: String,
        botID: String?,
        botName: String?,
        botHandle: String?,
        botAccentHex: String?,
        botRoleLabel: String?,
        botMoodLabel: String? = nil,
        botAvatarURL: String? = nil,
        text: String,
        stickerID: String? = nil,
        stickerURL: String? = nil,
        stickerCaption: String? = nil,
        status: String,
        receipts: [String],
        delegatedFromButler: Bool,
        createdAtMs: Double
    ) {
        self.id = id
        self.role = role
        self.botID = botID
        self.botName = botName
        self.botHandle = botHandle
        self.botAccentHex = botAccentHex
        self.botRoleLabel = botRoleLabel
        self.botMoodLabel = botMoodLabel
        self.botAvatarURL = botAvatarURL
        self.text = text
        self.stickerID = stickerID
        self.stickerURL = stickerURL
        self.stickerCaption = stickerCaption
        self.status = status
        self.receipts = receipts
        self.delegatedFromButler = delegatedFromButler
        self.createdAtMs = createdAtMs
    }
    
    enum CodingKeys: String, CodingKey {
        case id, role, botID, botName, botHandle, botAccentHex, botRoleLabel
        case botMoodLabel, botAvatarURL, text, stickerID, stickerURL, stickerCaption
        case status, receipts, delegatedFromButler, createdAtMs
    }
    
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(String.self, forKey: .id)
        self.role = try c.decode(String.self, forKey: .role)
        self.botID = try c.decodeIfPresent(String.self, forKey: .botID)
        self.botName = try c.decodeIfPresent(String.self, forKey: .botName)
        self.botHandle = try c.decodeIfPresent(String.self, forKey: .botHandle)
        self.botAccentHex = try c.decodeIfPresent(String.self, forKey: .botAccentHex)
        self.botRoleLabel = try c.decodeIfPresent(String.self, forKey: .botRoleLabel)
        self.botMoodLabel = try c.decodeIfPresent(String.self, forKey: .botMoodLabel)
        self.botAvatarURL = try c.decodeIfPresent(String.self, forKey: .botAvatarURL)
        self.text = try c.decodeIfPresent(String.self, forKey: .text) ?? ""
        self.stickerID = try c.decodeIfPresent(String.self, forKey: .stickerID)
        self.stickerURL = try c.decodeIfPresent(String.self, forKey: .stickerURL)
        self.stickerCaption = try c.decodeIfPresent(String.self, forKey: .stickerCaption)
        self.status = try c.decodeIfPresent(String.self, forKey: .status) ?? "done"
        self.receipts = try c.decodeIfPresent([String].self, forKey: .receipts) ?? []
        self.delegatedFromButler = try c.decodeIfPresent(Bool.self, forKey: .delegatedFromButler) ?? false
        self.createdAtMs = try c.decodeIfPresent(Double.self, forKey: .createdAtMs) ?? 0
    }
}


nonisolated struct MeetingBotDailyTelemetry: Equatable, Sendable {
    let botID: AIBotID
    let todayCallCount: Int
    let todayTokens: Int
    let badgeText: String
    let evidenceSummary: String
    let hasTodayActivity: Bool
}


/// Deterministic offline router for Meeting Room prompts (`@Bot` callouts, Butler governance,
/// refresh intent detection, and natural-language meeting triggers from normal Butler chat).
nonisolated enum MeetingRoomRouter {
    
    static let coreStandupOrder: [AIBotID] = [
        .organizeAndMerge,
        .ghost,
        .weeklyReport,
        .persona,
        .readingCompanion,
    ]
    
    private static let refreshKeywords: [String] = [
        "更新", "刷新", "同步", "重扫", "重新整理", "拉齐", "校准", "更新一下",
        "refresh", "update", "sync", "recheck",
    ]
    
    private static let governanceKeywords: [String] = [
        "帮我管", "你去管", "管一下", "管好", "调度", "统筹", "安排一下",
        "让其他", "让所有", "让各位", "让他们", "让它们", "拉齐", "叫他们",
        "orchestrate", "coordinate", "manage", "dispatch",
    ]
    
    private static let butlerTriggerPhrases: [String] = [
        "/meeting",
        "汇总一下信息",
        "汇总今日信息",
        "汇总今天信息",
        "汇总今天的信息",
        "拉所有bot开会",
        "拉所有 bot 开会",
        "叫所有bot开会",
        "大家开个会",
        "开个复盘会",
        "召开会议",
        "进入会议室",
        "打开会议室",
    ]
    
    
    static func isMeetingTriggerInButlerChat(_ prompt: String) -> Bool {
        let lower = prompt.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !lower.isEmpty else { return false }
        if lower == "/meeting" || lower.hasPrefix("/meeting ") {
            return true
        }
        return Self.butlerTriggerPhrases.contains { lower.contains($0.lowercased()) }
    }
    
    
    private static let progressCheckKeywords: [String] = [
        "进展", "进度", "汇报", "复盘", "总结", "站会", "日报", "周报",
        "统计", "数据", "干了啥", "干了什么", "做了什么", "做了啥", "工作",
        "待办", "整理", "文档", "刷新", "更新", "同步", "今天", "本周",
        "standup", "report", "progress", "summary", "status", "todo", "stats",
    ]
    
    
    static func isProgressCheckIntent(_ rawPrompt: String) -> Bool {
        let trimmed = rawPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return true
        }
        let lower = trimmed.lowercased()
        return Self.progressCheckKeywords.contains { lower.contains($0) }
    }
    
    
    static func parsePrompt(
        _ rawPrompt: String,
        explicitBotID: AIBotID? = nil,
        butlerAliases: [String] = ["总管", "Butler"],
        availableBots: [AIBotID],
        activeTodayBots: Set<AIBotID> = [],
        customBotAliases: [AIBotID: [String]] = [:]
    ) -> MeetingDispatchPlan {
        let trimmed = rawPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()
        let shouldRefresh = Self.refreshKeywords.contains { lower.contains($0) }
        let hasGovernanceCue = Self.governanceKeywords.contains { lower.contains($0) }
        
        var mentioned: [AIBotID] = []
        if let explicitBotID, !mentioned.contains(explicitBotID) {
            mentioned.append(explicitBotID)
        }
        
        let normalizedAliases = butlerAliases
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
        for alias in normalizedAliases + ["butler", "总管"] {
            if lower.contains("@\(alias)") && !mentioned.contains(.butler) {
                mentioned.append(.butler)
                break
            }
        }
        
        for botID in availableBots where botID != .butler {
            let tokens = Self.mentionTokens(for: botID, extraAliases: customBotAliases[botID] ?? [])
            if tokens.contains(where: { lower.contains("@\($0)") }), !mentioned.contains(botID) {
                mentioned.append(botID)
            }
        }
        
        var namedSubordinates: [AIBotID] = mentioned.filter { $0 != .butler }
        if hasGovernanceCue || mentioned.contains(.butler) {
            for botID in availableBots where botID != .butler {
                if namedSubordinates.contains(botID) { continue }
                let extra = (customBotAliases[botID] ?? []).map { $0.lowercased() }
                let names = [botID.displayName.lowercased(), botID.defaultNickname.lowercased()] + extra
                if names.contains(where: { $0.count >= 2 && lower.contains($0) }) {
                    namedSubordinates.append(botID)
                }
            }
        }
        
        let defaultStandupParticipants = Self.resolveStandupParticipants(
            availableBots: availableBots,
            activeTodayBots: activeTodayBots
        )
        
        if hasGovernanceCue || (mentioned.contains(.butler) && !namedSubordinates.isEmpty) {
            let targets = namedSubordinates.isEmpty ? defaultStandupParticipants : namedSubordinates
            return MeetingDispatchPlan(
                mode: .butlerGoverned(subordinates: targets, shouldRefresh: shouldRefresh || hasGovernanceCue),
                cleanedPrompt: trimmed,
                mentionedBots: mentioned
            )
        }
        
        if !mentioned.isEmpty {
            return MeetingDispatchPlan(
                mode: .directCallout(targets: mentioned, shouldRefresh: shouldRefresh),
                cleanedPrompt: trimmed,
                mentionedBots: mentioned
            )
        }
        
        return MeetingDispatchPlan(
            mode: .allHandsStandup(participants: defaultStandupParticipants),
            cleanedPrompt: trimmed.isEmpty
                ? AppLanguage.text("聊聊今天各自手里有什么新进展。", en: "Share anything new on your plate today.")
                : trimmed,
            mentionedBots: []
        )
    }
    
    
    static func resolveStandupParticipants(
        availableBots: [AIBotID],
        activeTodayBots: Set<AIBotID>
    ) -> [AIBotID] {
        let enabledSet = Set(availableBots.filter { $0 != .butler })
        var ordered: [AIBotID] = []
        for core in Self.coreStandupOrder where enabledSet.contains(core) {
            ordered.append(core)
        }
        for active in availableBots where active != .butler && activeTodayBots.contains(active) && !ordered.contains(active) {
            ordered.append(active)
        }
        if ordered.isEmpty {
            ordered = Array(availableBots.filter { $0 != .butler }.prefix(5))
        }
        return ordered
    }
    
    
    private static func mentionTokens(for botID: AIBotID, extraAliases: [String] = []) -> [String] {
        let rawHandle = botID.handle.hasPrefix("@") ? String(botID.handle.dropFirst()) : botID.handle
        let extras = extraAliases
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
        return [
            rawHandle.lowercased(),
            botID.displayName.lowercased(),
            botID.defaultNickname.lowercased(),
            botID.rawValue.lowercased(),
        ] + extras
    }
}


// MARK: - Meeting Room Manager (Multi-Session Workspace + Stickers + Emotions)

@MainActor @Observable
final class ButlerMeetingRoomManager {
    
    static let shared = ButlerMeetingRoomManager()
    static let defaultMeetingTitle = "新会议"
    
    var isActive: Bool = false
    private(set) var sessions: [MeetingRoomSession] = []
    private(set) var activeSessionID: String = ""
    var messages: [MeetingRoomMessage] = []
    private(set) var isConvening: Bool = false
    var botStatuses: [String: String] = [:]
    var revision: Int = 0
    
    let database: CotLocalDatabase
    @ObservationIgnored var activeTask: Task<Void, Never>?
    @ObservationIgnored var activeGeneration: UInt64 = 0
    @ObservationIgnored private var cachedRosterKey: String?
    @ObservationIgnored private var cachedRosterAt: Date = .distantPast
    @ObservationIgnored private var cachedRoster: [MeetingRoomParticipantPayload] = []
    
    static let encoder = JSONEncoder()
    static let decoder = JSONDecoder()
    
    
    init(database: CotLocalDatabase = .shared) {
        self.database = database
        self.bootstrapSessionsAndMessages()
    }
    
    
    private func bootstrapSessionsAndMessages() {
        var loaded = self.database.fetchMeetingRoomSessions()
        if loaded.isEmpty {
            let legacyRaw = self.database.string(forKey: CotLocalDatabase.ConfigKey.butlerMeetingRoomJSON, default: "")
            let nowMs = Date().timeIntervalSince1970 * 1000
            let defaultIDs = Self.defaultParticipantIDs(botStore: .shared)
            let initial = MeetingRoomSession(
                id: "mr-sess-\(UUID().uuidString.prefix(8).lowercased())",
                title: AppLanguage.text("复盘例会", en: "Standup"),
                isPinned: false,
                participantIDs: defaultIDs,
                createdAtMs: nowMs,
                updatedAtMs: nowMs
            )
            self.database.upsertMeetingRoomSession(initial)
            if !legacyRaw.isEmpty, let data = legacyRaw.data(using: .utf8),
               let legacyMsgs = try? Self.decoder.decode([MeetingRoomMessage].self, from: data),
               !legacyMsgs.isEmpty
            {
                self.persistMessages(legacyMsgs, for: initial.id)
            }
            loaded = [initial]
        }
        self.sessions = loaded
        self.activeSessionID = loaded.first?.id ?? ""
        self.loadMessagesForActiveSession()
    }
    
    
    private static func defaultParticipantIDs(botStore: AIBotStore) -> [String] {
        var ids = [AIBotID.butler.rawValue]
        ids.append(contentsOf: MeetingRoomRouter.coreStandupOrder.filter { botStore.config(for: $0).isEnabled }.map(\.rawValue))
        for custom in botStore.customBots where custom.isEnabled {
            ids.append(custom.id)
        }
        return ids
    }
    
    
    var activeSession: MeetingRoomSession? {
        self.sessions.first { $0.id == self.activeSessionID }
    }
    
    
    var activeParticipantIDs: [String] {
        self.activeSession?.participantIDs ?? Self.defaultParticipantIDs(botStore: .shared)
    }
    
    
    func setActive(_ active: Bool) {
        if self.isActive != active {
            self.isActive = active
            self.revision &+= 1
        }
    }
    
    
    @discardableResult
    func createSession(title: String? = nil, botStore: AIBotStore = .shared) -> MeetingRoomSession {
        self.abortMeeting()
        let nowMs = Date().timeIntervalSince1970 * 1000
        let cleanTitle = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let session = MeetingRoomSession(
            id: "mr-sess-\(UUID().uuidString.prefix(8).lowercased())",
            title: cleanTitle.isEmpty ? AppLanguage.text(Self.defaultMeetingTitle, en: "New Meeting") : cleanTitle,
            isPinned: false,
            participantIDs: Self.defaultParticipantIDs(botStore: botStore),
            createdAtMs: nowMs,
            updatedAtMs: nowMs
        )
        self.database.upsertMeetingRoomSession(session)
        self.sessions = self.database.fetchMeetingRoomSessions()
        self.activeSessionID = session.id
        self.messages = []
        self.botStatuses = [:]
        self.isActive = true
        self.revision &+= 1
        return session
    }
    
    
    func selectSession(_ sessionID: String) {
        guard self.sessions.contains(where: { $0.id == sessionID }) else { return }
        if self.activeSessionID != sessionID {
            self.abortMeeting()
            self.activeSessionID = sessionID
            self.botStatuses = [:]
            self.loadMessagesForActiveSession()
        }
        self.isActive = true
        self.revision &+= 1
    }
    
    
    func renameSession(_ sessionID: String, title: String) {
        guard var target = self.sessions.first(where: { $0.id == sessionID }) else { return }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        target.title = String(trimmed.prefix(32))
        target.updatedAtMs = Date().timeIntervalSince1970 * 1000
        self.database.upsertMeetingRoomSession(target)
        self.sessions = self.database.fetchMeetingRoomSessions()
        self.revision &+= 1
    }
    
    
    func togglePinSession(_ sessionID: String) {
        guard var target = self.sessions.first(where: { $0.id == sessionID }) else { return }
        target.isPinned.toggle()
        self.database.upsertMeetingRoomSession(target)
        self.sessions = self.database.fetchMeetingRoomSessions()
        self.revision &+= 1
    }
    
    
    func deleteSession(_ sessionID: String) {
        if self.activeSessionID == sessionID {
            self.abortMeeting()
        }
        self.database.deleteMeetingRoomSession(id: sessionID)
        var remaining = self.database.fetchMeetingRoomSessions()
        if remaining.isEmpty {
            let fresh = self.createSession()
            remaining = [fresh]
        }
        self.sessions = remaining
        if self.activeSessionID == sessionID || !remaining.contains(where: { $0.id == self.activeSessionID }) {
            self.activeSessionID = remaining.first?.id ?? ""
            self.loadMessagesForActiveSession()
        }
        self.revision &+= 1
    }
    
    
    func toggleParticipant(_ botID: String) {
        guard var session = self.activeSession else { return }
        if let idx = session.participantIDs.firstIndex(of: botID) {
            if session.participantIDs.count > 1 {
                session.participantIDs.remove(at: idx)
            }
        } else {
            session.participantIDs.append(botID)
        }
        self.database.upsertMeetingRoomSession(session)
        self.sessions = self.database.fetchMeetingRoomSessions()
        self.cachedRosterKey = nil
        self.revision &+= 1
    }
    
    
    func clearMeeting() {
        self.abortMeeting()
        self.messages = []
        self.botStatuses = [:]
        self.persistActiveMessages()
        self.revision &+= 1
    }
    
    
    func abortMeeting() {
        self.activeGeneration &+= 1
        self.activeTask?.cancel()
        self.activeTask = nil
        self.isConvening = false
        for idx in self.messages.indices where self.messages[idx].status == "speaking" {
            self.messages[idx].status = "done"
            if self.messages[idx].text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && self.messages[idx].stickerID == nil {
                self.messages[idx].text = AppLanguage.text("已中止发言。", en: "Stopped.")
            }
        }
        for key in self.botStatuses.keys where self.botStatuses[key] == "speaking" {
            self.botStatuses[key] = "idle"
        }
        self.persistActiveMessages()
        self.revision &+= 1
    }
    
    
    func participantRoster(botStore: AIBotStore = .shared) -> [MeetingRoomParticipantPayload] {
        let avatarRev = botStore.avatarRevision &+ botStore.customBotsRevision
        let todayKey = AnalyticsManager.dateKey()
        let selectedSet = Set(self.activeParticipantIDs)
        let unified = botStore.allUnifiedBots(includeDisabled: false)
        let identityKey = unified.map { bot in
            let status = self.botStatuses[bot.id] ?? "idle"
            let sel = selectedSet.contains(bot.id) ? "1" : "0"
            return "\(bot.id):\(bot.name):\(bot.nickname):\(bot.emotion.mood.rawValue):\(status):\(sel)"
        }.joined(separator: "|")
        let cacheKey = "\(self.revision)|\(avatarRev)|\(self.activeSessionID)|\(todayKey)|\(identityKey)"
        let now = Date()
        if self.cachedRosterKey == cacheKey, now.timeIntervalSince(self.cachedRosterAt) < 2.0 {
            return self.cachedRoster
        }
        
        let telemetryMap = self.collectDailyTelemetryByBot()
        let roster = unified.map { bot in
            let telemetry = bot.builtInID.flatMap { telemetryMap[$0] }
            return MeetingRoomParticipantPayload(
                id: bot.id,
                name: bot.name,
                nickname: bot.nickname,
                handle: bot.handle,
                roleLabel: bot.roleLabel,
                accentHex: bot.accentHex,
                status: self.botStatuses[bot.id] ?? "idle",
                todayBadge: telemetry?.badgeText ?? "",
                moodLabel: bot.emotion.mood.displayLabel,
                avatarURL: CotMediaSchemeHandler.botAvatarURLString(botID: bot.id, revision: avatarRev),
                isSelected: selectedSet.contains(bot.id),
                isCustom: !bot.isBuiltIn
            )
        }
        self.cachedRosterKey = cacheKey
        self.cachedRosterAt = now
        self.cachedRoster = roster
        return roster
    }
    
    
    func appendExternalMessage(_ message: MeetingRoomMessage) {
        self.messages.append(message)
        self.persistActiveMessages()
        self.revision &+= 1
    }
    
    
    func submitPrompt(
        _ rawPrompt: String,
        stickerID: String? = nil,
        explicitBotID: String? = nil,
        allowRemoteAI: Bool = true,
        botStore: AIBotStore = .shared
    ) async {
        let trimmed = rawPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanStickerID = stickerID?.trimmingCharacters(in: .whitespacesAndNewlines)
        let sticker = cleanStickerID.flatMap { CotStickerLibraryStore.shared.sticker(id: $0) }
        guard !trimmed.isEmpty || sticker != nil else { return }
        
        if self.activeSessionID.isEmpty {
            _ = self.createSession(botStore: botStore)
        }
        if let sticker {
            CotStickerLibraryStore.shared.recordUse(id: sticker.id)
        }
        
        self.abortMeeting()
        self.activeGeneration &+= 1
        let generation = self.activeGeneration
        self.isConvening = true
        
        let effectivePromptForLLM: String = {
            if !trimmed.isEmpty, let sticker {
                return "\(trimmed)（附带表情包：\(sticker.searchableSummary)）"
            }
            if let sticker {
                return "用户发了一张表情包（\(sticker.promptDescription)）"
            }
            return trimmed
        }()
        
        self.autoTitleActiveSessionIfNeeded(from: trimmed.isEmpty ? (sticker?.searchableSummary ?? "表情讨论") : trimmed)
        
        let userMsg = MeetingRoomMessage(
            id: "mr-user-\(UUID().uuidString)",
            role: "user",
            botID: nil,
            botName: nil,
            botHandle: nil,
            botAccentHex: nil,
            botRoleLabel: nil,
            text: trimmed,
            stickerID: sticker?.id,
            stickerURL: sticker.map { CotMediaSchemeHandler.stickerURLString(id: $0.id) },
            stickerCaption: sticker?.searchableSummary,
            status: "done",
            receipts: [],
            delegatedFromButler: false,
            createdAtMs: Date().timeIntervalSince1970 * 1000
        )
        self.messages.append(userMsg)
        self.persistActiveMessages()
        self.revision &+= 1
        
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.runMeetingDispatch(
                rawPrompt: trimmed,
                llmPrompt: effectivePromptForLLM,
                explicitBotID: explicitBotID,
                generation: generation,
                allowRemoteAI: allowRemoteAI,
                botStore: botStore
            )
            if self.activeGeneration == generation {
                self.isConvening = false
                self.persistActiveMessages()
                self.revision &+= 1
            }
        }
        self.activeTask = task
        await task.value
    }
    
    
    private func autoTitleActiveSessionIfNeeded(from seedText: String) {
        guard var session = self.activeSession else { return }
        let defaults = Set([Self.defaultMeetingTitle, "New Meeting", "复盘例会", "Standup"])
        guard self.messages.isEmpty || defaults.contains(session.title) else { return }
        let clean = seedText
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        session.title = String(clean.prefix(18))
        session.updatedAtMs = Date().timeIntervalSince1970 * 1000
        self.database.upsertMeetingRoomSession(session)
        self.sessions = self.database.fetchMeetingRoomSessions()
    }
    
    
    private func loadMessagesForActiveSession() {
        let payloads = self.database.fetchMeetingRoomMessagePayloads(sessionID: self.activeSessionID)
        self.messages = payloads.compactMap { raw in
            guard let data = raw.data(using: .utf8),
                  var msg = try? Self.decoder.decode(MeetingRoomMessage.self, from: data)
            else { return nil }
            if msg.status == "speaking" { msg.status = "done" }
            return msg
        }
    }
    
    
    func persistActiveMessages() {
        guard !self.activeSessionID.isEmpty else { return }
        self.persistMessages(self.messages, for: self.activeSessionID)
        if var session = self.activeSession {
            session.updatedAtMs = Date().timeIntervalSince1970 * 1000
            self.database.upsertMeetingRoomSession(session)
            self.sessions = self.database.fetchMeetingRoomSessions()
        }
    }
    
    
    private func persistMessages(_ list: [MeetingRoomMessage], for sessionID: String) {
        let capped = Array(list.suffix(100))
        let entries: [(id: String, json: String, createdAtMs: Double)] = capped.compactMap { msg in
            guard let data = try? Self.encoder.encode(msg),
                  let json = String(data: data, encoding: .utf8)
            else { return nil }
            return (msg.id, json, msg.createdAtMs)
        }
        self.database.replaceMeetingRoomMessagePayloads(sessionID: sessionID, entries: entries)
    }
}
