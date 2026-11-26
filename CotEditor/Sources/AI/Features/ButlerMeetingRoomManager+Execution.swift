//
//  ButlerMeetingRoomManager+Execution.swift
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
import SQLite3

extension ButlerMeetingRoomManager {
    
    struct MeetingTurnContext {
        let rawPrompt: String
        let llmPrompt: String
        let currentUserMessageID: String
        let userSentSticker: Bool
        let isProgressCheck: Bool
        let isMentioned: Bool
        let isButlerSynthesis: Bool
        let delegatedFromButler: Bool
        let shouldRefresh: Bool
        let generation: UInt64
        let allowRemoteAI: Bool
        let telemetryMap: [AIBotID: MeetingBotDailyTelemetry]
        let subordinateReports: [(botID: String, messageID: String, name: String, text: String)]
    }
    
    
    func runMeetingDispatch(
        rawPrompt: String,
        llmPrompt: String,
        userMessageID: String,
        userSentSticker: Bool,
        explicitBotID: String?,
        generation: UInt64,
        allowRemoteAI: Bool,
        botStore: AIBotStore
    ) async {
        let telemetryMap = self.collectDailyTelemetryByBot()
        let activeTodayBots = Set(telemetryMap.values.filter { $0.todayCallCount > 0 }.map(\.botID))
        let enabledBuiltIns = AIBotID.allCases.filter { $0 == .butler || botStore.config(for: $0).isEnabled }
        var customAliases: [AIBotID: [String]] = [:]
        for botID in enabledBuiltIns where botID != .butler {
            customAliases[botID] = [botStore.resolvedName(for: botID), botStore.resolvedNickname(for: botID)]
        }
        
        // Check if an explicit or @mentioned custom Bot is targeted
        let allUnified = botStore.allUnifiedBots(includeDisabled: false)
        let customMentions = Self.detectMentionedCustomBots(
            in: rawPrompt,
            explicitBotID: explicitBotID,
            customBots: allUnified.filter { !$0.isBuiltIn }
        )
        
        let explicitBuiltIn = explicitBotID.flatMap(AIBotID.init(rawValue:))
        let plan = MeetingRoomRouter.parsePrompt(
            rawPrompt,
            explicitBotID: explicitBuiltIn,
            butlerAliases: [CotButlerManager.shared.name, CotButlerManager.shared.nickname, "总管", "Butler"],
            availableBots: enabledBuiltIns,
            activeTodayBots: activeTodayBots,
            customBotAliases: customAliases
        )
        
        let isProgress = MeetingRoomRouter.isProgressCheckIntent(rawPrompt)
        let selectedSet = Set(self.activeParticipantIDs)
        var stickerOnlyCount = 0
        var stickersUsedInTurn = 0
        
        if !customMentions.isEmpty && explicitBuiltIn == nil && plan.mentionedBots.isEmpty {
            for bot in customMentions {
                guard self.activeGeneration == generation, !Task.isCancelled else { return }
                let ctx = MeetingTurnContext(
                    rawPrompt: rawPrompt, llmPrompt: llmPrompt, currentUserMessageID: userMessageID,
                    userSentSticker: userSentSticker, isProgressCheck: isProgress,
                    isMentioned: true, isButlerSynthesis: false, delegatedFromButler: false,
                    shouldRefresh: false, generation: generation, allowRemoteAI: allowRemoteAI,
                    telemetryMap: telemetryMap, subordinateReports: []
                )
                _ = await self.runUnifiedBotTurn(
                    bot: bot,
                    context: ctx,
                    stickerOnlyCount: &stickerOnlyCount,
                    stickersUsedInTurn: &stickersUsedInTurn,
                    botStore: botStore
                )
            }
            return
        }
        
        await self.dispatchByMode(
            plan: plan,
            rawPrompt: rawPrompt,
            llmPrompt: llmPrompt,
            userMessageID: userMessageID,
            userSentSticker: userSentSticker,
            isProgress: isProgress,
            selectedSet: selectedSet,
            allUnified: allUnified,
            customMentions: customMentions,
            telemetryMap: telemetryMap,
            generation: generation,
            allowRemoteAI: allowRemoteAI,
            stickerOnlyCount: &stickerOnlyCount,
            stickersUsedInTurn: &stickersUsedInTurn,
            botStore: botStore
        )
    }
    
    
    private func dispatchByMode(
        plan: MeetingDispatchPlan,
        rawPrompt: String,
        llmPrompt: String,
        userMessageID: String,
        userSentSticker: Bool,
        isProgress: Bool,
        selectedSet: Set<String>,
        allUnified: [UnifiedBotDescriptor],
        customMentions: [UnifiedBotDescriptor],
        telemetryMap: [AIBotID: MeetingBotDailyTelemetry],
        generation: UInt64,
        allowRemoteAI: Bool,
        stickerOnlyCount: inout Int,
        stickersUsedInTurn: inout Int,
        botStore: AIBotStore
    ) async {
        switch plan.mode {
            case .allHandsStandup(let participants):
                let butlerConfig = botStore.resolvedConfiguration(for: .butler)
                let remoteEnabled = allowRemoteAI && AIService.shared.isConfigured
                    && !butlerConfig.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                
                var candidateBots: [UnifiedBotDescriptor] = participants.compactMap { bid in
                    guard selectedSet.contains(bid.rawValue) else { return nil }
                    return allUnified.first { $0.id == bid.rawValue }
                }
                for custom in allUnified where !custom.isBuiltIn && selectedSet.contains(custom.id) {
                    candidateBots.append(custom)
                }
                
                var reports: [(botID: String, messageID: String, name: String, text: String)] = []
                for bot in candidateBots {
                    guard self.activeGeneration == generation, !Task.isCancelled else { return }
                    if !isProgress && remoteEnabled && reports.count >= 2 { break }
                    let ctx = MeetingTurnContext(
                        rawPrompt: rawPrompt, llmPrompt: llmPrompt, currentUserMessageID: userMessageID,
                        userSentSticker: userSentSticker, isProgressCheck: isProgress,
                        isMentioned: false, isButlerSynthesis: false, delegatedFromButler: false,
                        shouldRefresh: false, generation: generation, allowRemoteAI: allowRemoteAI,
                        telemetryMap: telemetryMap, subordinateReports: []
                    )
                    if let rep = await self.runUnifiedBotTurn(
                        bot: bot,
                        context: ctx,
                        stickerOnlyCount: &stickerOnlyCount,
                        stickersUsedInTurn: &stickersUsedInTurn,
                        botStore: botStore
                    ) {
                        reports.append(rep)
                    }
                }
                guard self.activeGeneration == generation, !Task.isCancelled else { return }
                if let butler = allUnified.first(where: { $0.id == AIBotID.butler.rawValue }) {
                    let runAsSynthesis = isProgress || !remoteEnabled || reports.isEmpty
                    let ctx = MeetingTurnContext(
                        rawPrompt: rawPrompt, llmPrompt: llmPrompt, currentUserMessageID: userMessageID,
                        userSentSticker: userSentSticker, isProgressCheck: isProgress,
                        isMentioned: runAsSynthesis, isButlerSynthesis: runAsSynthesis, delegatedFromButler: false,
                        shouldRefresh: false, generation: generation, allowRemoteAI: allowRemoteAI,
                        telemetryMap: telemetryMap, subordinateReports: reports
                    )
                    _ = await self.runUnifiedBotTurn(
                        bot: butler,
                        context: ctx,
                        stickerOnlyCount: &stickerOnlyCount,
                        stickersUsedInTurn: &stickersUsedInTurn,
                        botStore: botStore
                    )
                }
                
            case .directCallout(let targets, let shouldRefresh):
                var bots: [UnifiedBotDescriptor] = targets.compactMap { bid in allUnified.first { $0.id == bid.rawValue } }
                for c in customMentions where !bots.contains(where: { $0.id == c.id }) { bots.append(c) }
                for bot in bots {
                    guard self.activeGeneration == generation, !Task.isCancelled else { return }
                    let ctx = MeetingTurnContext(
                        rawPrompt: rawPrompt, llmPrompt: llmPrompt, currentUserMessageID: userMessageID,
                        userSentSticker: userSentSticker, isProgressCheck: shouldRefresh || isProgress,
                        isMentioned: true, isButlerSynthesis: false, delegatedFromButler: false,
                        shouldRefresh: shouldRefresh, generation: generation, allowRemoteAI: allowRemoteAI,
                        telemetryMap: telemetryMap, subordinateReports: []
                    )
                    _ = await self.runUnifiedBotTurn(
                        bot: bot,
                        context: ctx,
                        stickerOnlyCount: &stickerOnlyCount,
                        stickersUsedInTurn: &stickersUsedInTurn,
                        botStore: botStore
                    )
                }
                
            case .butlerGoverned(let subordinates, let shouldRefresh):
                var reports: [(botID: String, messageID: String, name: String, text: String)] = []
                let explicitlyTargeted = subordinates.count <= 3
                for bid in subordinates {
                    guard self.activeGeneration == generation, !Task.isCancelled else { return }
                    guard let bot = allUnified.first(where: { $0.id == bid.rawValue }) else { continue }
                    let mustReply = plan.mentionedBots.contains(bid) || explicitlyTargeted
                    let ctx = MeetingTurnContext(
                        rawPrompt: rawPrompt, llmPrompt: llmPrompt, currentUserMessageID: userMessageID,
                        userSentSticker: userSentSticker, isProgressCheck: true,
                        isMentioned: mustReply, isButlerSynthesis: false, delegatedFromButler: true,
                        shouldRefresh: shouldRefresh, generation: generation, allowRemoteAI: allowRemoteAI,
                        telemetryMap: telemetryMap, subordinateReports: []
                    )
                    if let rep = await self.runUnifiedBotTurn(
                        bot: bot,
                        context: ctx,
                        stickerOnlyCount: &stickerOnlyCount,
                        stickersUsedInTurn: &stickersUsedInTurn,
                        botStore: botStore
                    ) {
                        reports.append(rep)
                    }
                }
                guard self.activeGeneration == generation, !Task.isCancelled else { return }
                if let butler = allUnified.first(where: { $0.id == AIBotID.butler.rawValue }) {
                    let ctx = MeetingTurnContext(
                        rawPrompt: rawPrompt, llmPrompt: llmPrompt, currentUserMessageID: userMessageID,
                        userSentSticker: userSentSticker, isProgressCheck: true,
                        isMentioned: true, isButlerSynthesis: true, delegatedFromButler: false,
                        shouldRefresh: shouldRefresh, generation: generation, allowRemoteAI: allowRemoteAI,
                        telemetryMap: telemetryMap, subordinateReports: reports
                    )
                    _ = await self.runUnifiedBotTurn(
                        bot: butler,
                        context: ctx,
                        stickerOnlyCount: &stickerOnlyCount,
                        stickersUsedInTurn: &stickersUsedInTurn,
                        botStore: botStore
                    )
                }
        }
    }
    
    
    private func runUnifiedBotTurn(
        bot: UnifiedBotDescriptor,
        context: MeetingTurnContext,
        stickerOnlyCount: inout Int,
        stickersUsedInTurn: inout Int,
        botStore: AIBotStore
    ) async -> (botID: String, messageID: String, name: String, text: String)? {
        let builtIn = bot.builtInID
        var receipts: [String] = []
        if context.shouldRefresh, let builtIn, let receipt = self.executeBotRefreshAction(for: builtIn) {
            receipts.append(receipt)
        }
        
        let telemetry = builtIn.flatMap { bid in
            context.shouldRefresh ? (self.collectDailyTelemetryByBot()[bid] ?? context.telemetryMap[bid]) : context.telemetryMap[bid]
        }
        let config = botStore.resolvedConfiguration(forBotID: bot.id)
        let canCallRemote = context.allowRemoteAI && AIService.shared.isConfigured
            && !config.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        
        if !canCallRemote && !context.isMentioned && !context.isButlerSynthesis && !(telemetry?.hasTodayActivity ?? false) && receipts.isEmpty {
            return nil
        }
        
        let avatarRev = botStore.avatarRevision &+ botStore.customBotsRevision
        let msgID = "mr-bot-\(bot.id)-\(UUID().uuidString)"
        let placeholder = MeetingRoomMessage(
            id: msgID,
            role: "bot",
            botID: bot.id,
            botName: bot.name,
            botHandle: bot.handle,
            botAccentHex: bot.accentHex,
            botRoleLabel: context.isButlerSynthesis ? AppLanguage.text("总管收口", en: "Chief") : bot.roleLabel,
            botMoodLabel: bot.emotion.mood.displayLabel,
            botAvatarURL: CotMediaSchemeHandler.botAvatarURLString(botID: bot.id, revision: avatarRev),
            text: "",
            status: "speaking",
            receipts: receipts,
            delegatedFromButler: context.delegatedFromButler,
            createdAtMs: Date().timeIntervalSince1970 * 1000
        )
        self.messages.append(placeholder)
        self.botStatuses[bot.id] = "speaking"
        self.revision &+= 1
        
        let candidates = self.stickerCandidatesForTurn(
            bot: bot,
            context: context,
            stickersUsedInTurn: stickersUsedInTurn
        )
        let allowStickerOnly = !context.isProgressCheck && !context.shouldRefresh && receipts.isEmpty && !context.isButlerSynthesis
        let rawReply = await self.generateUnifiedBotReply(
            bot: bot,
            context: context,
            telemetry: telemetry,
            receipts: receipts,
            placeholderID: msgID,
            stickerCandidates: candidates,
            allowStickerOnly: allowStickerOnly,
            botStore: botStore
        )
        guard self.activeGeneration == context.generation else { return nil }
        
        if !context.isMentioned && !context.isButlerSynthesis && MeetingRoomPersona.isPass(rawReply) {
            self.messages.removeAll { $0.id == msgID }
            self.botStatuses[bot.id] = "idle"
            self.persistActiveMessages()
            self.revision &+= 1
            return nil
        }
        
        return await self.finalizeBotReplyMessage(
            msgID: msgID,
            rawReply: rawReply,
            bot: bot,
            context: context,
            candidates: candidates,
            allowStickerOnly: allowStickerOnly,
            hadReceipts: !receipts.isEmpty,
            stickerOnlyCount: &stickerOnlyCount,
            stickersUsedInTurn: &stickersUsedInTurn,
            botStore: botStore
        )
    }
    
    
    private func stickerCandidatesForTurn(
        bot: UnifiedBotDescriptor,
        context: MeetingTurnContext,
        stickersUsedInTurn: Int
    ) -> [StickerAsset] {
        guard stickersUsedInTurn < 2 else { return [] }
        let lastFromThisBot = self.messages.last { $0.role == "bot" && $0.botID == bot.id && $0.status == "done" }
        if !context.userSentSticker, lastFromThisBot?.stickerID != nil {
            // Cooldown: prevent any single Bot from sending stickers in back-to-back replies
            return []
        }
        return CotStickerLibraryStore.shared.searchRelevantForReply(
            query: context.rawPrompt,
            mood: bot.emotion.mood.displayLabel,
            preferredCategories: bot.preferredStickerCategories,
            limit: 5
        )
    }
    
    
    private func finalizeBotReplyMessage(
        msgID: String,
        rawReply: String,
        bot: UnifiedBotDescriptor,
        context: MeetingTurnContext,
        candidates: [StickerAsset],
        allowStickerOnly: Bool,
        hadReceipts: Bool,
        stickerOnlyCount: inout Int,
        stickersUsedInTurn: inout Int,
        botStore: AIBotStore
    ) async -> (botID: String, messageID: String, name: String, text: String)? {
        let allowStickerBudget = stickersUsedInTurn < 2
        let parsed = BotReplyDirectiveParser.parse(
            raw: rawReply,
            allowedStickerIDs: allowStickerBudget ? Set(candidates.map(\.id)) : [],
            allowStickerOnly: allowStickerOnly,
            stickerOnlyCountInTurn: stickerOnlyCount,
            allowOnlineSearch: allowStickerBudget && OnlineStickerSearchService.isAutoExpansionEnabled
        )
        var resolvedSticker = allowStickerBudget
            ? parsed.stickerID.flatMap { CotStickerLibraryStore.shared.sticker(id: $0) }
            : nil
        if allowStickerBudget, resolvedSticker == nil, let searchQ = parsed.searchStickerQuery {
            resolvedSticker = await OnlineStickerSearchService.searchAndAutoExpand(
                query: searchQ,
                preferredCategory: bot.preferredStickerCategories.first ?? "reaction"
            )
            guard self.activeGeneration == context.generation else { return nil }
        }
        if let resolvedSticker {
            CotStickerLibraryStore.shared.recordUse(id: resolvedSticker.id)
            stickersUsedInTurn += 1
            if parsed.text.isEmpty { stickerOnlyCount += 1 }
        }
        
        var finalText = parsed.text
        if finalText.isEmpty && resolvedSticker == nil {
            if !context.isMentioned && !context.isButlerSynthesis {
                self.messages.removeAll { $0.id == msgID }
                self.botStatuses[bot.id] = "idle"
                self.persistActiveMessages()
                self.revision &+= 1
                return nil
            }
            finalText = AppLanguage.text("收到，先看着。", en: "Noted.")
        }
        
        botStore.updateEmotion(
            for: bot.id,
            userPrompt: context.rawPrompt,
            botReply: finalText,
            explicitMood: parsed.mood
        )
        let latestMood = botStore.emotionState(for: bot.id).mood.displayLabel
        
        if let idx = self.messages.firstIndex(where: { $0.id == msgID }) {
            self.messages[idx].text = finalText
            self.messages[idx].botMoodLabel = latestMood
            self.messages[idx].stickerID = resolvedSticker?.id
            self.messages[idx].stickerURL = resolvedSticker.map { CotMediaSchemeHandler.stickerURLString(id: $0.id) }
            self.messages[idx].stickerCaption = resolvedSticker?.searchableSummary
            self.messages[idx].status = "done"
        }
        self.botStatuses[bot.id] = hadReceipts ? "updated" : "done"
        self.persistActiveMessages()
        self.revision &+= 1
        return (bot.id, msgID, bot.name, finalText.isEmpty ? (resolvedSticker?.searchableSummary ?? "[表情包]") : finalText)
    }
    
    
    private func generateUnifiedBotReply(
        bot: UnifiedBotDescriptor,
        context: MeetingTurnContext,
        telemetry: MeetingBotDailyTelemetry?,
        receipts: [String],
        placeholderID: String,
        stickerCandidates: [StickerAsset],
        allowStickerOnly: Bool,
        botStore: AIBotStore
    ) async -> String {
        let evidence = telemetry?.evidenceSummary ?? ""
        var config = botStore.resolvedConfiguration(forBotID: bot.id)
        if let builtIn = bot.builtInID, botStore.config(for: builtIn).temperature == nil {
            config.temperature = 0.92
        }
        let canCallRemote = context.allowRemoteAI && AIService.shared.isConfigured
            && !config.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        
        guard canCallRemote else {
            return Self.buildOfflineFallbackReport(
                bot: bot,
                evidence: evidence,
                isButlerSynthesis: context.isButlerSynthesis,
                subordinateReports: context.subordinateReports,
                receipts: receipts
            )
        }
        
        let systemPrompt = MeetingRoomPersona.systemPrompt(
            bot: bot,
            isMentioned: context.isMentioned,
            isButlerSynthesis: context.isButlerSynthesis,
            isProgressCheck: context.isProgressCheck,
            stickerCandidates: stickerCandidates,
            allowStickerOnly: allowStickerOnly,
            allowOnlineSearch: !stickerCandidates.isEmpty && OnlineStickerSearchService.isAutoExpansionEnabled
        )
        var excludedIDs = Set([placeholderID, context.currentUserMessageID])
        for rep in context.subordinateReports {
            excludedIDs.insert(rep.messageID)
        }
        let recentChat = self.recentGroupChatContext(excludingMessageIDs: excludedIDs, limit: 10)
        var contextLines = ["【用户刚说】\(context.llmPrompt)"]
        if !evidence.isEmpty {
            if context.isProgressCheck {
                contextLines.append("【你的本地背景（挑最值得说的一点聊，不要念流水账）】\n\(evidence)")
            } else if context.rawPrompt.count > 8 {
                contextLines.append("【静默背景（仅当话题直接相关时参考，严禁主动报数字）】\n\(evidence)")
            }
        }
        if !recentChat.isEmpty { contextLines.append("【群聊最近消息】\n\(recentChat)") }
        if !receipts.isEmpty { contextLines.append("【刚完成的动作】\(receipts.joined(separator: "；"))") }
        if !context.subordinateReports.isEmpty {
            let merged = context.subordinateReports.map { "\($0.name)：\($0.text)" }.joined(separator: "\n")
            contextLines.append("【刚才同事已经发在群里的话（严禁复述或照抄里面的数字）】\n\(merged)")
        }
        let userContext = contextLines.joined(separator: "\n\n")
        
        var lastStreamPush = Date.distantPast
        do {
            let raw = try await AIService.shared.chat(
                [.system(systemPrompt), .user(userContext)],
                configuration: config,
                analyticsFeature: "meeting_\(bot.id)"
            ) { [weak self] partial in
                guard let self, self.activeGeneration == context.generation else { return }
                let now = Date()
                guard now.timeIntervalSince(lastStreamPush) >= 0.08 else { return }
                lastStreamPush = now
                let sanitized = BotReplyDirectiveParser.stripDirectivesForLiveDisplay(partial)
                if let idx = self.messages.firstIndex(where: { $0.id == placeholderID }) {
                    self.messages[idx].text = sanitized
                    self.revision &+= 1
                }
            }
            let clean = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if context.isMentioned && MeetingRoomPersona.isPass(clean) {
                let retryRaw = try await AIService.shared.chat(
                    [.system(systemPrompt), .user(userContext + "\n\n注意：用户明确点名了你，必须给出自然答复，禁止回复 [PASS]。")],
                    configuration: config,
                    analyticsFeature: "meeting_\(bot.id)"
                )
                let retryClean = retryRaw.trimmingCharacters(in: .whitespacesAndNewlines)
                if !MeetingRoomPersona.isPass(retryClean) { return retryClean }
            } else if !clean.isEmpty {
                return clean
            }
        } catch {
            // Fall back cleanly
        }
        
        return Self.buildOfflineFallbackReport(
            bot: bot,
            evidence: evidence,
            isButlerSynthesis: context.isButlerSynthesis,
            subordinateReports: context.subordinateReports,
            receipts: receipts
        )
    }
    
    
    private static func detectMentionedCustomBots(
        in prompt: String,
        explicitBotID: String?,
        customBots: [UnifiedBotDescriptor]
    ) -> [UnifiedBotDescriptor] {
        var matched: [UnifiedBotDescriptor] = []
        if let explicitBotID, let exact = customBots.first(where: { $0.id == explicitBotID }) {
            matched.append(exact)
        }
        let lower = prompt.lowercased()
        for bot in customBots {
            if matched.contains(where: { $0.id == bot.id }) { continue }
            let tokens = [bot.name.lowercased(), bot.nickname.lowercased(), bot.id.lowercased()].filter { !$0.isEmpty }
            if tokens.contains(where: { lower.contains("@\($0)") }) {
                matched.append(bot)
            }
        }
        return matched
    }
    
    
    private func recentGroupChatContext(excludingMessageIDs: Set<String>, limit: Int) -> String {
        let history = self.messages
            .filter { !excludingMessageIDs.contains($0.id) && (!$0.text.isEmpty || $0.stickerCaption != nil) }
            .suffix(limit)
        return history.map { msg in
            let speaker = msg.role == "user" ? "用户" : (msg.botName ?? msg.botID ?? "Bot")
            let body: String = if !msg.text.isEmpty && msg.stickerCaption != nil {
                "\(msg.text) [表情包:\(msg.stickerCaption ?? "")]"
            } else if msg.text.isEmpty {
                "[表情包:\(msg.stickerCaption ?? "")]"
            } else {
                msg.text
            }
            let snippet = String(body.replacingOccurrences(of: "\n", with: " ").prefix(140))
            return "\(speaker)：\(snippet)"
        }.joined(separator: "\n")
    }
    
    
    private static func buildOfflineFallbackReport(
        bot: UnifiedBotDescriptor,
        evidence: String,
        isButlerSynthesis: Bool,
        subordinateReports: [(botID: String, messageID: String, name: String, text: String)],
        receipts: [String]
    ) -> String {
        if bot.builtInID == .butler && isButlerSynthesis {
            if subordinateReports.isEmpty {
                return AppLanguage.text(
                    "大家手头都挺稳，有什么需要直接点名就好。",
                    en: "All quiet across the team—ping any of us whenever needed."
                )
            }
            let names = subordinateReports.map(\.name).joined(separator: "、")
            var summary = AppLanguage.text("刚听完 \(names) 冒泡，重点已经对齐。", en: "Synced up with \(names).")
            if !receipts.isEmpty { summary += " " + receipts.joined(separator: "、") + "。" }
            return summary
        }
        if !evidence.isEmpty {
            return evidence.replacingOccurrences(of: "\n", with: " ")
        }
        return AppLanguage.text("收到，先看着。", en: "Noted.")
    }
    
    
    // MARK: Real Per-Bot Refresh Actions & Daily Telemetry
    
    func executeBotRefreshAction(for botID: AIBotID) -> String? {
        switch botID {
            case .organizeAndMerge:
                self.database.reloadDocuments()
                let activeCount = self.database.documents.filter { $0.deletedAt == nil }.count
                return AppLanguage.text("已重扫文档库（\(activeCount) 篇）", en: "Rescanned docs (\(activeCount))")
            case .ghost:
                if self.database === CotLocalDatabase.shared { AnalyticsManager.shared.flushPendingStats() }
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
                return (badge, "今天手写了 \(stats.typed) 字，采纳了 \(stats.aiChars) 字续写。", stats.typed > 0 || stats.aiChars > 0 || callCount > 0)
            case .weeklyReport:
                let reports = self.database.weeklyReports
                let openTasks = self.queryInt("SELECT COUNT(*) FROM user_reminders WHERE is_completed = 0;")
                let latestTitle = reports.first?.title ?? "暂无周报"
                return ("\(reports.count) 份", "手头存着 \(reports.count) 份周报（最近是「\(latestTitle)」），还有 \(openTasks) 项未完待办。", callCount > 0 || openTasks > 0)
            case .persona:
                let memories = self.queryTopMemoryTitles(limit: 4)
                let todayJournals = self.queryInt("SELECT COUNT(*) FROM user_memory_journal WHERE timestamp >= \(startOfDay);")
                let memText = memories.isEmpty ? "还在慢慢熟悉你的习惯" : memories.joined(separator: "、")
                return ("\(memories.count) 记忆", "最近对你的印象是：\(memText)。", todayJournals > 0 || callCount > 0)
            case .readingCompanion:
                let stocks = self.queryInt("SELECT COUNT(*) FROM user_watchlist_stocks;")
                let podcasts = self.queryInt("SELECT COUNT(*) FROM user_podcasts;")
                let feeds = self.queryInt("SELECT COUNT(*) FROM user_followed_feeds;")
                let badge = stocks + podcasts + feeds > 0 ? "\(stocks + podcasts + feeds) 订阅" : "待命"
                return (badge, "目前盯着 \(stocks) 只自选股、\(podcasts) 条播客和 \(feeds) 个资讯源。", callCount > 0)
            case .butler:
                let todayMsgs = self.queryInt("SELECT COUNT(*) FROM butler_messages WHERE created_at >= \(startOfDay);")
                let openReminders = self.queryOpenReminderTitles(limit: 3)
                let badge = todayMsgs > 0 ? "\(todayMsgs) 条" : "在线"
                let remText = openReminders.isEmpty ? "眼下没有卡住的待办" : openReminders.joined(separator: "、")
                return (badge, "今天总管这边聊了 \(todayMsgs) 条，手头待办是：\(remText)。", todayMsgs > 0 || !openReminders.isEmpty)
            default:
                let badge = callCount > 0 ? "\(callCount) 次" : "待命"
                let evidence = callCount > 0 ? "今天帮了 \(callCount) 次忙（\(tokens) tokens）。" : "今天先候着。"
                return (badge, evidence, callCount > 0)
        }
    }
    
    
    // MARK: Lightweight SQLite Queries
    
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
                result[feature] = (Int(sqlite3_column_int64(stmt, 1)), Int(sqlite3_column_int64(stmt, 2)))
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
                res = (Int(sqlite3_column_int64(stmt, 0)), Int(sqlite3_column_int64(stmt, 1)), Int(sqlite3_column_int64(stmt, 2)))
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
}
