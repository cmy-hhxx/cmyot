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
    var text: String
    /// `"speaking"` | `"done"` | `"error"`
    var status: String
    var receipts: [String]
    var delegatedFromButler: Bool
    var createdAtMs: Double
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
    
    
    /// Returns true if a prompt typed in normal Butler chat clearly intends to convene the isolated Meeting Room.
    static func isMeetingTriggerInButlerChat(_ prompt: String) -> Bool {
        let lower = prompt.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !lower.isEmpty else { return false }
        if lower == "/meeting" || lower.hasPrefix("/meeting ") {
            return true
        }
        return Self.butlerTriggerPhrases.contains { lower.contains($0.lowercased()) }
    }
    
    
    /// Parses a Meeting Room user prompt into a clean hub-and-spoke dispatch plan.
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
        
        // Match explicit @mentions for Butler and specialist Bots
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
            if tokens.contains(where: { lower.contains("@\($0)") }) {
                if !mentioned.contains(botID) {
                    mentioned.append(botID)
                }
            }
        }
        
        // Also match plain Chinese role names when governance cue is present (e.g. "让整理师和周报搭子更新")
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
        
        // Case 1: Butler Governance — user manages Chief Butler, Butler manages other Bots
        if hasGovernanceCue || (mentioned.contains(.butler) && !namedSubordinates.isEmpty) {
            let targets = namedSubordinates.isEmpty ? defaultStandupParticipants : namedSubordinates
            return MeetingDispatchPlan(
                mode: .butlerGoverned(subordinates: targets, shouldRefresh: shouldRefresh || hasGovernanceCue),
                cleanedPrompt: trimmed,
                mentionedBots: mentioned
            )
        }
        
        // Case 2: Direct @Bot call-out (one or more specific Bots)
        if !mentioned.isEmpty {
            return MeetingDispatchPlan(
                mode: .directCallout(targets: mentioned, shouldRefresh: shouldRefresh),
                cleanedPrompt: trimmed,
                mentionedBots: mentioned
            )
        }
        
        // Case 3: All-hands Standup (every active specialist reports directly to user, Butler summarizes)
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


// MARK: - Meeting Room Manager (Isolated from Regular Butler Sessions)

@MainActor @Observable
final class ButlerMeetingRoomManager {
    
    static let shared = ButlerMeetingRoomManager()
    
    var isActive: Bool = false
    private(set) var messages: [MeetingRoomMessage] = []
    private(set) var isConvening: Bool = false
    private(set) var botStatuses: [String: String] = [:]
    private(set) var revision: Int = 0
    
    private let database: CotLocalDatabase
    @ObservationIgnored private var activeTask: Task<Void, Never>?
    @ObservationIgnored private var activeGeneration: UInt64 = 0
    @ObservationIgnored private var cachedRosterKey: String?
    @ObservationIgnored private var cachedRosterAt: Date = .distantPast
    @ObservationIgnored private var cachedRoster: [MeetingRoomParticipantPayload] = []
    
    private static let encoder = JSONEncoder()
    private static let decoder = JSONDecoder()
    
    
    init(database: CotLocalDatabase = .shared) {
        self.database = database
        self.loadPersistedMessages()
    }
    
    
    func setActive(_ active: Bool) {
        if self.isActive != active {
            self.isActive = active
            self.revision &+= 1
        }
    }
    
    
    func clearMeeting() {
        self.abortMeeting()
        self.messages = []
        self.botStatuses = [:]
        self.persistMessages()
        self.revision &+= 1
    }
    
    
    func abortMeeting() {
        self.activeGeneration &+= 1
        self.activeTask?.cancel()
        self.activeTask = nil
        self.isConvening = false
        for idx in self.messages.indices where self.messages[idx].status == "speaking" {
            self.messages[idx].status = "done"
            if self.messages[idx].text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                self.messages[idx].text = AppLanguage.text("已中止发言。", en: "Stopped.")
            }
        }
        for key in self.botStatuses.keys where self.botStatuses[key] == "speaking" {
            self.botStatuses[key] = "idle"
        }
        self.persistMessages()
        self.revision &+= 1
    }
    
    
    /// Builds the live participant roster shown in the Meeting Room right-side rail.
    func participantRoster(botStore: AIBotStore = .shared) -> [MeetingRoomParticipantPayload] {
        let todayKey = AnalyticsManager.dateKey()
        let orderedBots: [AIBotID] = [.butler] + AIBotID.allCases.filter {
            $0 != .butler && botStore.config(for: $0).isEnabled
        }
        let identityKey = orderedBots.map { botID in
            let name = (botID == .butler) ? CotButlerManager.shared.name : botStore.resolvedName(for: botID)
            let nickname = (botID == .butler) ? CotButlerManager.shared.nickname : botStore.resolvedNickname(for: botID)
            let status = self.botStatuses[botID.rawValue] ?? "idle"
            return "\(botID.rawValue):\(name):\(nickname):\(status)"
        }.joined(separator: "|")
        let cacheKey = "\(self.revision)|\(todayKey)|\(identityKey)"
        let now = Date()
        if self.cachedRosterKey == cacheKey, now.timeIntervalSince(self.cachedRosterAt) < 3.0 {
            return self.cachedRoster
        }
        
        let telemetryMap = self.collectDailyTelemetryByBot()
        let roster = orderedBots.map { botID in
            let name = (botID == .butler) ? CotButlerManager.shared.name : botStore.resolvedName(for: botID)
            let nickname = (botID == .butler) ? CotButlerManager.shared.nickname : botStore.resolvedNickname(for: botID)
            let telemetry = telemetryMap[botID]
            return MeetingRoomParticipantPayload(
                id: botID.rawValue,
                name: name,
                nickname: nickname,
                handle: botID.handle,
                roleLabel: botID == .butler
                    ? AppLanguage.text("总管统筹", en: "Chief")
                    : botID.defaultNickname,
                accentHex: botID.accentHex,
                status: self.botStatuses[botID.rawValue] ?? "idle",
                todayBadge: telemetry?.badgeText ?? ""
            )
        }
        self.cachedRosterKey = cacheKey
        self.cachedRosterAt = now
        self.cachedRoster = roster
        return roster
    }
    
    
    /// Appends a pre-built message (e.g. from the daily report scheduler) and persists.
    func appendExternalMessage(_ message: MeetingRoomMessage) {
        self.messages.append(message)
        self.persistMessages()
        self.revision &+= 1
    }
    
    
    /// Submits a question or directive into the isolated Meeting Room.
    func submitPrompt(
        _ rawPrompt: String,
        explicitBotID: String? = nil,
        allowRemoteAI: Bool = true,
        botStore: AIBotStore = .shared
    ) async {
        let trimmed = rawPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        
        self.abortMeeting()
        self.activeGeneration &+= 1
        let generation = self.activeGeneration
        self.isConvening = true
        
        let enabledBots = AIBotID.allCases.filter { $0 == .butler || botStore.config(for: $0).isEnabled }
        let telemetryMap = self.collectDailyTelemetryByBot()
        let activeTodayBots = Set(telemetryMap.values.filter { $0.todayCallCount > 0 }.map(\.botID))
        let explicitBot = explicitBotID.flatMap(AIBotID.init(rawValue:))
        var customBotAliases: [AIBotID: [String]] = [:]
        for botID in enabledBots where botID != .butler {
            customBotAliases[botID] = [
                botStore.resolvedName(for: botID),
                botStore.resolvedNickname(for: botID),
            ]
        }
        
        let plan = MeetingRoomRouter.parsePrompt(
            trimmed,
            explicitBotID: explicitBot,
            butlerAliases: [CotButlerManager.shared.name, CotButlerManager.shared.nickname, "总管", "Butler"],
            availableBots: enabledBots,
            activeTodayBots: activeTodayBots,
            customBotAliases: customBotAliases
        )
        
        let userMsg = MeetingRoomMessage(
            id: "mr-user-\(UUID().uuidString)",
            role: "user",
            botID: nil,
            botName: nil,
            botHandle: nil,
            botAccentHex: nil,
            botRoleLabel: nil,
            text: trimmed,
            status: "done",
            receipts: [],
            delegatedFromButler: false,
            createdAtMs: Date().timeIntervalSince1970 * 1000
        )
        self.messages.append(userMsg)
        self.persistMessages()
        self.revision &+= 1
        
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.executeDispatchPlan(
                plan,
                generation: generation,
                telemetryMap: telemetryMap,
                allowRemoteAI: allowRemoteAI,
                botStore: botStore
            )
            if self.activeGeneration == generation {
                self.isConvening = false
                self.persistMessages()
                self.revision &+= 1
            }
        }
        self.activeTask = task
        await task.value
    }
    
    
    // MARK: Dispatch Execution
    
    private func executeDispatchPlan(
        _ plan: MeetingDispatchPlan,
        generation: UInt64,
        telemetryMap: [AIBotID: MeetingBotDailyTelemetry],
        allowRemoteAI: Bool,
        botStore: AIBotStore
    ) async {
        switch plan.mode {
            case .allHandsStandup(let participants):
                var reports: [(botID: AIBotID, name: String, text: String)] = []
                for botID in participants {
                    guard self.activeGeneration == generation, !Task.isCancelled else { return }
                    let report = await self.runBotReportTurn(
                        botID: botID,
                        userPrompt: plan.cleanedPrompt,
                        telemetry: telemetryMap[botID],
                        shouldRefresh: false,
                        delegatedFromButler: false,
                        isMentioned: false,
                        isButlerSynthesis: false,
                        subordinateReports: [],
                        generation: generation,
                        allowRemoteAI: allowRemoteAI,
                        botStore: botStore
                    )
                    if let report {
                        reports.append(report)
                    }
                }
                guard self.activeGeneration == generation, !Task.isCancelled else { return }
                _ = await self.runBotReportTurn(
                    botID: .butler,
                    userPrompt: plan.cleanedPrompt,
                    telemetry: telemetryMap[.butler],
                    shouldRefresh: false,
                    delegatedFromButler: false,
                    isMentioned: true,
                    isButlerSynthesis: true,
                    subordinateReports: reports,
                    generation: generation,
                    allowRemoteAI: allowRemoteAI,
                    botStore: botStore
                )
                
            case .directCallout(let targets, let shouldRefresh):
                for botID in targets {
                    guard self.activeGeneration == generation, !Task.isCancelled else { return }
                    _ = await self.runBotReportTurn(
                        botID: botID,
                        userPrompt: plan.cleanedPrompt,
                        telemetry: telemetryMap[botID],
                        shouldRefresh: shouldRefresh,
                        delegatedFromButler: false,
                        isMentioned: true,
                        isButlerSynthesis: false,
                        subordinateReports: [],
                        generation: generation,
                        allowRemoteAI: allowRemoteAI,
                        botStore: botStore
                    )
                }
                
            case .butlerGoverned(let subordinates, let shouldRefresh):
                var reports: [(botID: AIBotID, name: String, text: String)] = []
                let explicitlyTargeted = subordinates.count <= 3
                for botID in subordinates {
                    guard self.activeGeneration == generation, !Task.isCancelled else { return }
                    let mustReply = plan.mentionedBots.contains(botID) || explicitlyTargeted
                    let report = await self.runBotReportTurn(
                        botID: botID,
                        userPrompt: plan.cleanedPrompt,
                        telemetry: telemetryMap[botID],
                        shouldRefresh: shouldRefresh,
                        delegatedFromButler: true,
                        isMentioned: mustReply,
                        isButlerSynthesis: false,
                        subordinateReports: [],
                        generation: generation,
                        allowRemoteAI: allowRemoteAI,
                        botStore: botStore
                    )
                    if let report {
                        reports.append(report)
                    }
                }
                guard self.activeGeneration == generation, !Task.isCancelled else { return }
                _ = await self.runBotReportTurn(
                    botID: .butler,
                    userPrompt: plan.cleanedPrompt,
                    telemetry: telemetryMap[.butler],
                    shouldRefresh: shouldRefresh,
                    delegatedFromButler: false,
                    isMentioned: true,
                    isButlerSynthesis: true,
                    subordinateReports: reports,
                    generation: generation,
                    allowRemoteAI: allowRemoteAI,
                    botStore: botStore
                )
        }
    }
    
    
    private func runBotReportTurn(
        botID: AIBotID,
        userPrompt: String,
        telemetry: MeetingBotDailyTelemetry?,
        shouldRefresh: Bool,
        delegatedFromButler: Bool,
        isMentioned: Bool,
        isButlerSynthesis: Bool,
        subordinateReports: [(botID: AIBotID, name: String, text: String)],
        generation: UInt64,
        allowRemoteAI: Bool,
        botStore: AIBotStore
    ) async -> (botID: AIBotID, name: String, text: String)? {
        let botName = (botID == .butler) ? CotButlerManager.shared.name : botStore.resolvedName(for: botID)
        let roleLabel: String = if botID == .butler {
            isButlerSynthesis
                ? AppLanguage.text("总管收口", en: "Chief")
                : AppLanguage.text("总管", en: "Chief")
        } else if delegatedFromButler {
            AppLanguage.text("总管调度", en: "Dispatched")
        } else {
            botID.defaultNickname
        }
        
        var receipts: [String] = []
        if shouldRefresh {
            if let receipt = self.executeBotRefreshAction(for: botID) {
                receipts.append(receipt)
            }
        }
        
        let refreshedTelemetry = shouldRefresh ? (self.collectDailyTelemetryByBot()[botID] ?? telemetry) : telemetry
        let config = botStore.resolvedConfiguration(for: botID)
        let canCallRemote = allowRemoteAI && AIService.shared.isConfigured && !config.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        
        // In offline mode, bots that were not @-mentioned and have no activity/receipts quietly stay silent.
        if !canCallRemote && !isMentioned && !isButlerSynthesis && !(refreshedTelemetry?.hasTodayActivity ?? false) && receipts.isEmpty {
            return nil
        }
        
        let msgID = "mr-bot-\(botID.rawValue)-\(UUID().uuidString)"
        let placeholder = MeetingRoomMessage(
            id: msgID,
            role: "bot",
            botID: botID.rawValue,
            botName: botName,
            botHandle: botID.handle,
            botAccentHex: botID.accentHex,
            botRoleLabel: roleLabel,
            text: "",
            status: "speaking",
            receipts: receipts,
            delegatedFromButler: delegatedFromButler,
            createdAtMs: Date().timeIntervalSince1970 * 1000
        )
        self.messages.append(placeholder)
        self.botStatuses[botID.rawValue] = "speaking"
        self.revision &+= 1
        
        let finalText = await self.generateBotReportText(
            botID: botID,
            botName: botName,
            userPrompt: userPrompt,
            telemetry: refreshedTelemetry,
            isMentioned: isMentioned,
            isButlerSynthesis: isButlerSynthesis,
            subordinateReports: subordinateReports,
            receipts: receipts,
            placeholderID: msgID,
            allowRemoteAI: allowRemoteAI,
            botStore: botStore
        )
        guard self.activeGeneration == generation else { return nil }
        
        if !isMentioned && !isButlerSynthesis && MeetingRoomPersona.isPass(finalText) {
            self.messages.removeAll { $0.id == msgID }
            self.botStatuses[botID.rawValue] = "idle"
            self.persistMessages()
            self.revision &+= 1
            return nil
        }
        
        if let idx = self.messages.firstIndex(where: { $0.id == msgID }) {
            self.messages[idx].text = finalText
            self.messages[idx].status = "done"
        }
        self.botStatuses[botID.rawValue] = receipts.isEmpty ? "done" : "updated"
        self.persistMessages()
        self.revision &+= 1
        return (botID, botName, finalText)
    }
    
    
    private func generateBotReportText(
        botID: AIBotID,
        botName: String,
        userPrompt: String,
        telemetry: MeetingBotDailyTelemetry?,
        isMentioned: Bool,
        isButlerSynthesis: Bool,
        subordinateReports: [(botID: AIBotID, name: String, text: String)],
        receipts: [String],
        placeholderID: String,
        allowRemoteAI: Bool,
        botStore: AIBotStore
    ) async -> String {
        let evidence = telemetry?.evidenceSummary ?? AppLanguage.text("今日暂无额外记录。", en: "No additional records today.")
        var config = botStore.resolvedConfiguration(for: botID)
        if botStore.config(for: botID).temperature == nil {
            config.temperature = 0.85
        }
        let canCallRemote = allowRemoteAI && AIService.shared.isConfigured && !config.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        
        guard canCallRemote else {
            return Self.buildOfflineFallbackReport(
                botID: botID,
                botName: botName,
                evidence: evidence,
                isButlerSynthesis: isButlerSynthesis,
                subordinateReports: subordinateReports,
                receipts: receipts
            )
        }
        
        let systemPrompt = MeetingRoomPersona.systemPrompt(
            bot: botID,
            name: botName,
            isMentioned: isMentioned,
            isButlerSynthesis: isButlerSynthesis,
            customPersona: botStore.config(for: botID).customPersona
        )
        
        let recentChat = self.recentGroupChatContext(excludingMessageID: placeholderID, limit: 10)
        var contextLines: [String] = [
            "【用户刚说】\(userPrompt)",
            "【你的真实本地数据】\n\(evidence)",
        ]
        if !recentChat.isEmpty {
            contextLines.append("【群聊最近消息】\n\(recentChat)")
        }
        if !receipts.isEmpty {
            contextLines.append("【刚完成的动作】\(receipts.joined(separator: "；"))")
        }
        if !subordinateReports.isEmpty {
            let merged = subordinateReports.map { "\($0.name)：\($0.text)" }.joined(separator: "\n")
            contextLines.append("【刚才有发言的同事】\n\(merged)")
        }
        let userContext = contextLines.joined(separator: "\n\n")
        
        do {
            let raw = try await AIService.shared.chat(
                [.system(systemPrompt), .user(userContext)],
                configuration: config,
                analyticsFeature: "meeting_\(botID.rawValue)"
            )
            let clean = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if isMentioned && MeetingRoomPersona.isPass(clean) {
                let retryRaw = try await AIService.shared.chat(
                    [.system(systemPrompt), .user(userContext + "\n\n注意：用户明确点名了你，必须用你自己的口吻给出自然答复，禁止回复 [PASS]。")],
                    configuration: config,
                    analyticsFeature: "meeting_\(botID.rawValue)"
                )
                let retryClean = retryRaw.trimmingCharacters(in: .whitespacesAndNewlines)
                if !MeetingRoomPersona.isPass(retryClean) {
                    return retryClean
                }
            } else if !clean.isEmpty {
                return clean
            }
        } catch {
            // Fall through cleanly to local evidence report so standup never breaks mid-meeting
        }
        
        return Self.buildOfflineFallbackReport(
            botID: botID,
            botName: botName,
            evidence: evidence,
            isButlerSynthesis: isButlerSynthesis,
            subordinateReports: subordinateReports,
            receipts: receipts
        )
    }
    
    
    private func recentGroupChatContext(excludingMessageID: String, limit: Int) -> String {
        let history = self.messages
            .filter { $0.id != excludingMessageID && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .suffix(limit)
        return history.map { msg in
            let speaker = msg.role == "user" ? "用户" : (msg.botName ?? msg.botID ?? "Bot")
            let snippet = String(msg.text.replacingOccurrences(of: "\n", with: " ").prefix(140))
            return "\(speaker)：\(snippet)"
        }.joined(separator: "\n")
    }
    
    
    private static func buildOfflineFallbackReport(
        botID: AIBotID,
        botName: String,
        evidence: String,
        isButlerSynthesis: Bool,
        subordinateReports: [(botID: AIBotID, name: String, text: String)],
        receipts: [String]
    ) -> String {
        if botID == .butler && isButlerSynthesis {
            if subordinateReports.isEmpty {
                return AppLanguage.text(
                    "今天大家手头都没太多新动静，我也先替你看着，有什么需要直接点名就好。",
                    en: "Pretty quiet across the workspace today—just ping any of us whenever you need a hand."
                )
            }
            let names = subordinateReports.map(\.name).joined(separator: "、")
            var summary = AppLanguage.text("刚听完 \(names) 冒泡，今天重点已经对齐。", en: "Heard back from \(names); we're all synced up.")
            if !evidence.isEmpty {
                summary += " " + evidence.replacingOccurrences(of: "\n", with: " ")
            }
            if !receipts.isEmpty {
                summary += " " + receipts.joined(separator: "、") + "。"
            }
            return summary
        }
        var result = evidence.replacingOccurrences(of: "\n", with: " ")
        if !receipts.isEmpty {
            result += "（\(receipts.joined(separator: "、"))）"
        }
        return result
    }
    
    
    // MARK: Real Per-Bot Refresh Actions
    
    private func executeBotRefreshAction(for botID: AIBotID) -> String? {
        switch botID {
            case .organizeAndMerge:
                self.database.reloadDocuments()
                let activeCount = self.database.documents.filter { $0.deletedAt == nil }.count
                return AppLanguage.text("已重扫文档库（\(activeCount) 篇）", en: "Rescanned docs (\(activeCount))")
            case .ghost:
                if self.database === CotLocalDatabase.shared {
                    AnalyticsManager.shared.flushPendingStats()
                }
                return AppLanguage.text("已同步写作统计", en: "Synced writing stats")
            case .weeklyReport, .weeklyReportItem:
                self.database.reloadWeeklyReports()
                return AppLanguage.text("已同步周报归档", en: "Synced weekly reports")
            case .persona:
                return AppLanguage.text("已刷新长期记忆与画像", en: "Refreshed memory profile")
            case .readingCompanion:
                return AppLanguage.text("已同步订阅与看板状态", en: "Synced feeds & boards")
            case .butler:
                self.database.reloadAll()
                return AppLanguage.text("已统筹拉齐全量本地状态", en: "Synced all local state")
            default:
                return AppLanguage.text("已刷新今日记录", en: "Refreshed today's logs")
        }
    }
    
    
    // MARK: Real Per-Bot Daily Telemetry Collection from SQLite
    
    func collectDailyTelemetryByBot() -> [AIBotID: MeetingBotDailyTelemetry] {
        let todayKey = AnalyticsManager.dateKey()
        let startOfDay = Calendar.current.startOfDay(for: Date()).timeIntervalSince1970
        let usageByFeature = self.queryTodayUsageByFeature(dateKey: todayKey)
        
        var map: [AIBotID: MeetingBotDailyTelemetry] = [:]
        for botID in AIBotID.allCases {
            let featureKey = botID.analyticsFeatureKey.lowercased()
            let usage = usageByFeature.first { $0.key.lowercased().contains(featureKey) }?.value ?? (0, 0)
            let result = self.buildBotEvidence(
                botID: botID,
                todayKey: todayKey,
                startOfDay: startOfDay,
                callCount: usage.0,
                tokens: usage.1
            )
            map[botID] = MeetingBotDailyTelemetry(
                botID: botID,
                todayCallCount: usage.0,
                todayTokens: usage.1,
                badgeText: result.badge,
                evidenceSummary: result.evidence,
                hasTodayActivity: result.hasTodayActivity
            )
        }
        return map
    }
    
    
    func buildBotEvidence(
        botID: AIBotID,
        todayKey: String,
        startOfDay: TimeInterval,
        callCount: Int,
        tokens: Int
    ) -> (badge: String, evidence: String, hasTodayActivity: Bool) {
        switch botID {
            case .organizeAndMerge:
                let activeDocs = self.database.documents.filter { $0.deletedAt == nil }
                let todayDocs = activeDocs.filter { $0.updatedAt.timeIntervalSince1970 >= startOfDay }
                let untitledCount = activeDocs.filter {
                    DocumentCenterAgentOrganizer.isGenericUntitled($0.title, hasFilePath: $0.filePath != nil)
                }.count
                let titles = todayDocs.prefix(4).map(\.title).joined(separator: "、")
                let badge = todayDocs.isEmpty ? "\(activeDocs.count) 篇" : "今日 \(todayDocs.count) 篇"
                let line1 = "今日动了 \(todayDocs.count) 篇文档（库里一共 \(activeDocs.count) 篇）" + (titles.isEmpty ? "。" : "：\(titles)。")
                let line2 = untitledCount > 0 ? "还有 \(untitledCount) 篇未命名草稿待归类。" : "文档都归拢得挺整齐。"
                return (badge, "\(line1)\(line2)", !todayDocs.isEmpty || untitledCount > 0 || callCount > 0)
                
            case .ghost:
                let stats = self.queryTodayWritingRow(dateKey: todayKey)
                let badge = stats.typed > 0 ? "\(stats.typed) 字" : "待命"
                let evidence = "今天手写了 \(stats.typed) 字，采纳了我 \(stats.aiChars) 字续写（\(stats.accepts) 次）。"
                return (badge, evidence, stats.typed > 0 || stats.aiChars > 0 || callCount > 0)
                
            case .weeklyReport:
                let reports = self.database.weeklyReports
                let openTasks = self.queryInt("SELECT COUNT(*) FROM user_reminders WHERE is_completed = 0;")
                let latestTitle = reports.first?.title ?? "暂无周报"
                let badge = "\(reports.count) 份"
                let evidence = "手头存着 \(reports.count) 份周报（最近是「\(latestTitle)」），还有 \(openTasks) 项未完待办。"
                return (badge, evidence, callCount > 0 || openTasks > 0)
                
            case .persona:
                let memories = self.queryTopMemoryTitles(limit: 4)
                let todayJournals = self.queryInt("SELECT COUNT(*) FROM user_memory_journal WHERE timestamp >= \(startOfDay);")
                let badge = "\(memories.count) 记忆"
                let memText = memories.isEmpty ? "还在慢慢熟悉你的习惯" : memories.joined(separator: "、")
                let evidence = "今天记下 \(todayJournals) 条新观察，最近对你的印象是：\(memText)。"
                return (badge, evidence, todayJournals > 0 || callCount > 0)
                
            case .readingCompanion:
                let stocks = self.queryInt("SELECT COUNT(*) FROM user_watchlist_stocks;")
                let podcasts = self.queryInt("SELECT COUNT(*) FROM user_podcasts;")
                let feeds = self.queryInt("SELECT COUNT(*) FROM user_followed_feeds;")
                let badge = stocks + podcasts + feeds > 0 ? "\(stocks + podcasts + feeds) 订阅" : "待命"
                let evidence = "目前盯着 \(stocks) 只自选股、\(podcasts) 条播客和 \(feeds) 个资讯源，今天聊了 \(callCount) 次。"
                return (badge, evidence, callCount > 0)
                
            case .butler:
                let todayMsgs = self.queryInt("SELECT COUNT(*) FROM butler_messages WHERE created_at >= \(startOfDay);")
                let openReminders = self.queryOpenReminderTitles(limit: 3)
                let badge = todayMsgs > 0 ? "\(todayMsgs) 条" : "在线"
                let remText = openReminders.isEmpty ? "眼下没有卡住的待办" : openReminders.joined(separator: "、")
                let evidence = "今天总管这边聊了 \(todayMsgs) 条，手头待办是：\(remText)。"
                return (badge, evidence, todayMsgs > 0 || !openReminders.isEmpty)
                
            default:
                let badge = callCount > 0 ? "\(callCount) 次" : "待命"
                let evidence = callCount > 0
                    ? "今天帮了 \(callCount) 次忙（用了 \(tokens) tokens）。"
                    : "今天还没派上用场，先候着。"
                return (badge, evidence, callCount > 0)
        }
    }
    
    
    // MARK: Lightweight SQLite Helpers & Persistence
    
    private func queryInt(_ sql: String) -> Int {
        guard let db = self.database.db else { return 0 }
        var stmt: OpaquePointer?
        var value = 0
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, sqlite3_step(stmt) == SQLITE_ROW {
            value = Int(sqlite3_column_int64(stmt, 0))
        }
        sqlite3_finalize(stmt)
        return value
    }
    
    
    private func queryTodayUsageByFeature(dateKey: String) -> [String: (Int, Int)] {
        guard let db = self.database.db else { return [:] }
        let sql = "SELECT feature, COUNT(*), COALESCE(SUM(input_tokens + output_tokens), 0) FROM ai_usage_events WHERE date_key = ? GROUP BY feature;"
        var result: [String: (Int, Int)] = [:]
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, (dateKey as NSString).utf8String, -1, nil)
            while sqlite3_step(stmt) == SQLITE_ROW {
                let feature = sqlite3_column_text(stmt, 0).map { String(cString: $0) } ?? ""
                let count = Int(sqlite3_column_int64(stmt, 1))
                let tokens = Int(sqlite3_column_int64(stmt, 2))
                result[feature] = (count, tokens)
            }
        }
        sqlite3_finalize(stmt)
        return result
    }
    
    
    private func queryTodayWritingRow(dateKey: String) -> (typed: Int, aiChars: Int, accepts: Int) {
        guard let db = self.database.db else { return (0, 0, 0) }
        let sql = "SELECT typed_chars, ai_completed_chars, ai_completion_accepts FROM daily_writing_stats WHERE date_key = ? LIMIT 1;"
        var stmt: OpaquePointer?
        var res = (0, 0, 0)
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, (dateKey as NSString).utf8String, -1, nil)
            if sqlite3_step(stmt) == SQLITE_ROW {
                res = (
                    Int(sqlite3_column_int64(stmt, 0)),
                    Int(sqlite3_column_int64(stmt, 1)),
                    Int(sqlite3_column_int64(stmt, 2))
                )
            }
        }
        sqlite3_finalize(stmt)
        return res
    }
    
    
    private func queryTopMemoryTitles(limit: Int) -> [String] {
        guard let db = self.database.db else { return [] }
        let sql = "SELECT title FROM user_kyc_memories WHERE is_archived = 0 ORDER BY is_pinned DESC, updated_at DESC LIMIT \(max(1, limit));"
        var titles: [String] = []
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            while sqlite3_step(stmt) == SQLITE_ROW {
                if let cStr = sqlite3_column_text(stmt, 0) {
                    let t = String(cString: cStr).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !t.isEmpty { titles.append(t) }
                }
            }
        }
        sqlite3_finalize(stmt)
        return titles
    }
    
    
    private func queryOpenReminderTitles(limit: Int) -> [String] {
        guard let db = self.database.db else { return [] }
        let sql = "SELECT title FROM user_reminders WHERE is_completed = 0 ORDER BY is_pinned DESC, due_date ASC LIMIT \(max(1, limit));"
        var titles: [String] = []
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            while sqlite3_step(stmt) == SQLITE_ROW {
                if let cStr = sqlite3_column_text(stmt, 0) {
                    let t = String(cString: cStr).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !t.isEmpty { titles.append(t) }
                }
            }
        }
        sqlite3_finalize(stmt)
        return titles
    }
    
    
    private func loadPersistedMessages() {
        let raw = self.database.string(forKey: CotLocalDatabase.ConfigKey.butlerMeetingRoomJSON, default: "")
        guard !raw.isEmpty, let data = raw.data(using: .utf8),
              let decoded = try? Self.decoder.decode([MeetingRoomMessage].self, from: data)
        else { return }
        self.messages = decoded.map { msg in
            var copy = msg
            if copy.status == "speaking" { copy.status = "done" }
            return copy
        }
    }
    
    
    private func persistMessages() {
        let capped = Array(self.messages.suffix(80))
        guard let data = try? Self.encoder.encode(capped),
              let raw = String(data: data, encoding: .utf8)
        else { return }
        self.database.set(raw, forKey: CotLocalDatabase.ConfigKey.butlerMeetingRoomJSON)
    }
}
