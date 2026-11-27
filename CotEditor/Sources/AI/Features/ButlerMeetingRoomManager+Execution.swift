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
        let userSticker: StickerAsset?
        let isProgressCheck: Bool
        let isMentioned: Bool
        let mustRespond: Bool
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
        userSticker: StickerAsset? = nil,
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
            customBotAliases: customAliases,
            userSentSticker: userSentSticker
        )
        
        let isProgress = MeetingRoomRouter.isProgressCheckIntent(rawPrompt, userSentSticker: userSentSticker)
        let selectedSet = Set(self.activeParticipantIDs)
        var stickerOnlyCount = 0
        var stickersUsedInTurn = 0
        
        if !customMentions.isEmpty && explicitBuiltIn == nil && plan.mentionedBots.isEmpty {
            for bot in customMentions {
                guard self.activeGeneration == generation, !Task.isCancelled else { return }
                let ctx = MeetingTurnContext(
                    rawPrompt: rawPrompt, llmPrompt: llmPrompt, currentUserMessageID: userMessageID,
                    userSentSticker: userSentSticker, userSticker: userSticker, isProgressCheck: isProgress,
                    isMentioned: true, mustRespond: true, isButlerSynthesis: false, delegatedFromButler: false,
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
        
        switch plan.mode {
            case .allHandsStandup(let participants):
                await self.runAllHandsTurn(
                    participants: participants,
                    rawPrompt: rawPrompt,
                    llmPrompt: llmPrompt,
                    userMessageID: userMessageID,
                    userSentSticker: userSentSticker,
                    userSticker: userSticker,
                    isProgress: isProgress,
                    selectedSet: selectedSet,
                    allUnified: allUnified,
                    telemetryMap: telemetryMap,
                    generation: generation,
                    allowRemoteAI: allowRemoteAI,
                    stickerOnlyCount: &stickerOnlyCount,
                    stickersUsedInTurn: &stickersUsedInTurn,
                    botStore: botStore
                )
            case .directCallout(let targets, let shouldRefresh):
                await self.runDirectCalloutTurn(
                    targets: targets,
                    shouldRefresh: shouldRefresh,
                    rawPrompt: rawPrompt,
                    llmPrompt: llmPrompt,
                    userMessageID: userMessageID,
                    userSentSticker: userSentSticker,
                    userSticker: userSticker,
                    isProgress: isProgress,
                    allUnified: allUnified,
                    customMentions: customMentions,
                    telemetryMap: telemetryMap,
                    generation: generation,
                    allowRemoteAI: allowRemoteAI,
                    stickerOnlyCount: &stickerOnlyCount,
                    stickersUsedInTurn: &stickersUsedInTurn,
                    botStore: botStore
                )
            case .butlerGoverned(let subordinates, let shouldRefresh):
                await self.runButlerGovernedTurn(
                    subordinates: subordinates,
                    shouldRefresh: shouldRefresh,
                    plan: plan,
                    rawPrompt: rawPrompt,
                    llmPrompt: llmPrompt,
                    userMessageID: userMessageID,
                    userSentSticker: userSentSticker,
                    userSticker: userSticker,
                    allUnified: allUnified,
                    telemetryMap: telemetryMap,
                    generation: generation,
                    allowRemoteAI: allowRemoteAI,
                    stickerOnlyCount: &stickerOnlyCount,
                    stickersUsedInTurn: &stickersUsedInTurn,
                    botStore: botStore
                )
        }
    }
    
    
    private func runAllHandsTurn(
        participants: [AIBotID],
        rawPrompt: String,
        llmPrompt: String,
        userMessageID: String,
        userSentSticker: Bool,
        userSticker: StickerAsset?,
        isProgress: Bool,
        selectedSet: Set<String>,
        allUnified: [UnifiedBotDescriptor],
        telemetryMap: [AIBotID: MeetingBotDailyTelemetry],
        generation: UInt64,
        allowRemoteAI: Bool,
        stickerOnlyCount: inout Int,
        stickersUsedInTurn: inout Int,
        botStore: AIBotStore
    ) async {
        let butlerConfig = botStore.resolvedConfiguration(for: .butler)
        let remoteEnabled = allowRemoteAI && AIService.shared.isConfigured
            && !butlerConfig.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        
        var builtInSelected: [UnifiedBotDescriptor] = participants.compactMap { bid in
            guard selectedSet.contains(bid.rawValue) else { return nil }
            return allUnified.first { $0.id == bid.rawValue }
        }
        let customSelected = allUnified.filter { !$0.isBuiltIn && selectedSet.contains($0.id) }
        let lowerPrompt = rawPrompt.lowercased()
        let isExplicitAllHands = ["所有", "各位", "大家", "挨个", "每个", "/meeting", "开会"]
            .contains { lowerPrompt.contains($0) }
        
        let candidateBots: [UnifiedBotDescriptor]
        if !isProgress {
            let combined = customSelected + builtInSelected
            let topicSeed = [rawPrompt, userSticker?.stickerSearchTerms ?? ""].joined(separator: " ")
            candidateBots = MeetingWorkEvidenceBuilder.selectResponsiveChatBots(
                for: topicSeed,
                candidates: combined,
                isStickerTurn: userSentSticker
            )
        } else if remoteEnabled && !isExplicitAllHands {
            builtInSelected = MeetingWorkEvidenceBuilder.selectCapableStandupBots(
                for: rawPrompt,
                candidates: builtInSelected,
                telemetryMap: telemetryMap,
                isProgressCheck: true
            )
            candidateBots = builtInSelected + customSelected
        } else {
            candidateBots = builtInSelected + customSelected
        }
        
        let maxSubordinateSpeakers = isExplicitAllHands ? candidateBots.count : 3
        let guaranteedActiveCount = (!isProgress && (remoteEnabled || userSentSticker)) ? 2 : 0
        var reports: [(botID: String, messageID: String, name: String, text: String)] = []
        
        for (index, bot) in candidateBots.enumerated() {
            guard self.activeGeneration == generation, !Task.isCancelled else { return }
            if remoteEnabled && !isExplicitAllHands && reports.count >= maxSubordinateSpeakers { break }
            if !remoteEnabled && !isProgress && reports.count >= 2 { break }
            let mustReply = index < guaranteedActiveCount && reports.count < guaranteedActiveCount
            let ctx = MeetingTurnContext(
                rawPrompt: rawPrompt, llmPrompt: llmPrompt, currentUserMessageID: userMessageID,
                userSentSticker: userSentSticker, userSticker: userSticker, isProgressCheck: isProgress,
                isMentioned: false, mustRespond: mustReply, isButlerSynthesis: false, delegatedFromButler: false,
                shouldRefresh: false, generation: generation, allowRemoteAI: allowRemoteAI,
                telemetryMap: telemetryMap, subordinateReports: reports
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
            let mustWrapUp = !remoteEnabled || reports.isEmpty || isExplicitAllHands || (userSentSticker && reports.count < 2)
            let ctx = MeetingTurnContext(
                rawPrompt: rawPrompt, llmPrompt: llmPrompt, currentUserMessageID: userMessageID,
                userSentSticker: userSentSticker, userSticker: userSticker, isProgressCheck: isProgress,
                isMentioned: mustWrapUp, mustRespond: mustWrapUp, isButlerSynthesis: true, delegatedFromButler: false,
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
    }
    
    
    private func runDirectCalloutTurn(
        targets: [AIBotID],
        shouldRefresh: Bool,
        rawPrompt: String,
        llmPrompt: String,
        userMessageID: String,
        userSentSticker: Bool,
        userSticker: StickerAsset?,
        isProgress: Bool,
        allUnified: [UnifiedBotDescriptor],
        customMentions: [UnifiedBotDescriptor],
        telemetryMap: [AIBotID: MeetingBotDailyTelemetry],
        generation: UInt64,
        allowRemoteAI: Bool,
        stickerOnlyCount: inout Int,
        stickersUsedInTurn: inout Int,
        botStore: AIBotStore
    ) async {
        var bots: [UnifiedBotDescriptor] = targets.compactMap { bid in allUnified.first { $0.id == bid.rawValue } }
        for c in customMentions where !bots.contains(where: { $0.id == c.id }) { bots.append(c) }
        for bot in bots {
            guard self.activeGeneration == generation, !Task.isCancelled else { return }
            let ctx = MeetingTurnContext(
                rawPrompt: rawPrompt, llmPrompt: llmPrompt, currentUserMessageID: userMessageID,
                userSentSticker: userSentSticker, userSticker: userSticker, isProgressCheck: shouldRefresh || isProgress,
                isMentioned: true, mustRespond: true, isButlerSynthesis: false, delegatedFromButler: false,
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
    }
    
    
    private func runButlerGovernedTurn(
        subordinates: [AIBotID],
        shouldRefresh: Bool,
        plan: MeetingDispatchPlan,
        rawPrompt: String,
        llmPrompt: String,
        userMessageID: String,
        userSentSticker: Bool,
        userSticker: StickerAsset?,
        allUnified: [UnifiedBotDescriptor],
        telemetryMap: [AIBotID: MeetingBotDailyTelemetry],
        generation: UInt64,
        allowRemoteAI: Bool,
        stickerOnlyCount: inout Int,
        stickersUsedInTurn: inout Int,
        botStore: AIBotStore
    ) async {
        var reports: [(botID: String, messageID: String, name: String, text: String)] = []
        let explicitlyTargeted = subordinates.count <= 3
        for bid in subordinates {
            guard self.activeGeneration == generation, !Task.isCancelled else { return }
            guard let bot = allUnified.first(where: { $0.id == bid.rawValue }) else { continue }
            let mustReply = plan.mentionedBots.contains(bid) || explicitlyTargeted
            let ctx = MeetingTurnContext(
                rawPrompt: rawPrompt, llmPrompt: llmPrompt, currentUserMessageID: userMessageID,
                userSentSticker: userSentSticker, userSticker: userSticker, isProgressCheck: true,
                isMentioned: mustReply, mustRespond: mustReply, isButlerSynthesis: false, delegatedFromButler: true,
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
                userSentSticker: userSentSticker, userSticker: userSticker, isProgressCheck: true,
                isMentioned: true, mustRespond: true, isButlerSynthesis: true, delegatedFromButler: false,
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
        
        if !canCallRemote && !context.isMentioned && !context.mustRespond && !context.isButlerSynthesis && !(telemetry?.hasTodayActivity ?? false) && receipts.isEmpty {
            return nil
        }
        
        let avatarRev = botStore.avatarRevision &+ botStore.customBotsRevision
        let msgID = "mr-bot-\(bot.id)-\(UUID().uuidString)"
        let roleLabel = context.isButlerSynthesis ? AppLanguage.text("总管收口", en: "Chief") : bot.roleLabel
        let botAvatarURL = CotMediaSchemeHandler.botAvatarURLString(botID: bot.id, revision: avatarRev)
        let makeMessage: (String, String) -> MeetingRoomMessage = { text, status in
            MeetingRoomMessage(
                id: msgID,
                role: "bot",
                botID: bot.id,
                botName: bot.name,
                botHandle: bot.handle,
                botAccentHex: bot.accentHex,
                botRoleLabel: roleLabel,
                botMoodLabel: nil,
                botAvatarURL: botAvatarURL,
                text: text,
                status: status,
                receipts: receipts,
                delegatedFromButler: context.delegatedFromButler,
                createdAtMs: Date().timeIntervalSince1970 * 1000
            )
        }
        
        self.botStatuses[bot.id] = "thinking"
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
            makeStreamingMessage: { makeMessage($0, "speaking") },
            stickerCandidates: candidates,
            allowStickerOnly: allowStickerOnly,
            botStore: botStore
        )
        guard self.activeGeneration == context.generation else {
            self.botStatuses[bot.id] = "idle"
            return nil
        }
        
        if !context.isMentioned && !context.mustRespond && MeetingRoomPersona.isPass(rawReply) {
            let hadMessage = self.messages.contains { $0.id == msgID }
            if hadMessage {
                self.messages.removeAll { $0.id == msgID }
                self.persistActiveMessages()
            }
            if self.botStatuses[bot.id] != "idle" || hadMessage {
                self.botStatuses[bot.id] = "idle"
                self.revision &+= 1
            }
            return nil
        }
        
        return await self.finalizeBotReplyMessage(
            msgID: msgID,
            rawReply: rawReply,
            bot: bot,
            context: context,
            makeCompletedMessage: { makeMessage($0, "done") },
            candidates: candidates,
            allowStickerOnly: allowStickerOnly,
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
        let maxStickers = context.userSentSticker ? 3 : 2
        guard stickersUsedInTurn < maxStickers else { return [] }
        let lastFromThisBot = self.messages.last { $0.role == "bot" && $0.botID == bot.id && $0.status == "done" }
        if !context.userSentSticker, lastFromThisBot?.stickerID != nil {
            // Cooldown: prevent any single Bot from sending stickers in back-to-back replies
            return []
        }
        let combinedQuery = [context.rawPrompt, context.userSticker?.stickerSearchTerms ?? ""]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        var matches = CotStickerLibraryStore.shared.searchRelevantForReply(
            query: combinedQuery,
            mood: bot.emotion.mood.displayLabel,
            preferredCategories: bot.preferredStickerCategories,
            limit: 6
        )
        if matches.isEmpty, context.userSentSticker {
            matches = CotStickerLibraryStore.shared.search(
                query: combinedQuery,
                mood: context.userSticker?.moods.first ?? bot.emotion.mood.displayLabel,
                preferredCategories: bot.preferredStickerCategories,
                limit: 6
            )
        }
        if let userStickerID = context.userSticker?.id {
            let distinct = matches.filter { $0.id != userStickerID }
            if !distinct.isEmpty {
                matches = distinct
            }
        }
        return Array(matches.prefix(5))
    }
    
    
    private func finalizeBotReplyMessage(
        msgID: String,
        rawReply: String,
        bot: UnifiedBotDescriptor,
        context: MeetingTurnContext,
        makeCompletedMessage: (String) -> MeetingRoomMessage,
        candidates: [StickerAsset],
        allowStickerOnly: Bool,
        stickerOnlyCount: inout Int,
        stickersUsedInTurn: inout Int,
        botStore: AIBotStore
    ) async -> (botID: String, messageID: String, name: String, text: String)? {
        let maxStickers = context.userSentSticker ? 3 : 2
        let allowStickerBudget = stickersUsedInTurn < maxStickers
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
            if !context.isMentioned && !context.mustRespond && !context.isButlerSynthesis {
                let hadMessage = self.messages.contains { $0.id == msgID }
                if hadMessage {
                    self.messages.removeAll { $0.id == msgID }
                    self.persistActiveMessages()
                }
                self.botStatuses[bot.id] = "idle"
                self.revision &+= 1
                return nil
            }
            finalText = context.userSentSticker
                ? AppLanguage.text("怎么啦？来抱抱，有啥事儿直接丢给我分担。", en: "Hey, what's up? I'm right here if you want to vent or hand something off.")
                : AppLanguage.text("在的，你说，我这边随时帮你接手。", en: "I'm here—tell me what you need.")
        }
        
        botStore.updateEmotion(
            for: bot.id,
            userPrompt: context.llmPrompt,
            botReply: finalText,
            explicitMood: parsed.mood
        )
        
        if let idx = self.messages.firstIndex(where: { $0.id == msgID }) {
            self.messages[idx].text = finalText
            self.messages[idx].botMoodLabel = nil
            self.messages[idx].stickerID = resolvedSticker?.id
            self.messages[idx].stickerURL = resolvedSticker.map { CotMediaSchemeHandler.stickerURLString(id: $0.id) }
            self.messages[idx].stickerCaption = resolvedSticker?.searchableSummary
            self.messages[idx].status = "done"
        } else {
            var completed = makeCompletedMessage(finalText)
            completed.stickerID = resolvedSticker?.id
            completed.stickerURL = resolvedSticker.map { CotMediaSchemeHandler.stickerURLString(id: $0.id) }
            completed.stickerCaption = resolvedSticker?.searchableSummary
            self.messages.append(completed)
        }
        self.botStatuses[bot.id] = "idle"
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
        makeStreamingMessage: @escaping (String) -> MeetingRoomMessage,
        stickerCandidates: [StickerAsset],
        allowStickerOnly: Bool,
        botStore: AIBotStore
    ) async -> String {
        let evidence = telemetry?.evidenceSummary ?? ""
        var config = botStore.resolvedConfiguration(forBotID: bot.id)
        if let builtIn = bot.builtInID, botStore.config(for: builtIn).temperature == nil {
            config.temperature = context.isProgressCheck ? 0.58 : 0.72
        }
        let canCallRemote = context.allowRemoteAI && AIService.shared.isConfigured
            && !config.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        
        guard canCallRemote else {
            return Self.buildOfflineFallbackReport(
                bot: bot,
                evidence: evidence,
                context: context,
                receipts: receipts
            )
        }
        
        let systemPrompt = MeetingRoomPersona.systemPrompt(
            bot: bot,
            isMentioned: context.isMentioned,
            isButlerSynthesis: context.isButlerSynthesis,
            isProgressCheck: context.isProgressCheck,
            userSentSticker: context.userSentSticker,
            mustRespond: context.mustRespond,
            stickerCandidates: stickerCandidates,
            allowStickerOnly: allowStickerOnly,
            allowOnlineSearch: !stickerCandidates.isEmpty && OnlineStickerSearchService.isAutoExpansionEnabled
        )
        var excludedIDs = Set([placeholderID, context.currentUserMessageID])
        for rep in context.subordinateReports {
            excludedIDs.insert(rep.messageID)
        }
        let recentChat = self.recentGroupChatContext(excludingMessageIDs: excludedIDs, limit: 10)
        var contextLines = ["【用户刚发的内容（最优先回应）】\(context.llmPrompt)"]
        if !evidence.isEmpty && context.isProgressCheck {
            contextLines.append("【今日真实工作记录（站在用户视角挑关键进展、风险或下一步用大白话讲清，绝不要提系统临时趣味名）】\n\(evidence)")
        }
        if !recentChat.isEmpty { contextLines.append("【群聊最近消息】\n\(recentChat)") }
        if !receipts.isEmpty { contextLines.append("【刚完成的动作】\(receipts.joined(separator: "；"))") }
        if !context.subordinateReports.isEmpty {
            let merged = context.subordinateReports.map { "\($0.name)：\($0.text)" }.joined(separator: "\n")
            if context.isProgressCheck {
                contextLines.append("【群里同事刚刚已经说过的（严禁重复原话；若有新视角、风险提醒或下一步建议再补充，否则只回复 [PASS]）】\n\(merged)")
            } else {
                contextLines.append("【群里同事刚刚已经回应的（请换你自己的性格或专长角度直接回应用户，不要复读同事原话）】\n\(merged)")
            }
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
                guard !sanitized.isEmpty else { return }
                if let idx = self.messages.firstIndex(where: { $0.id == placeholderID }) {
                    self.messages[idx].text = sanitized
                    self.revision &+= 1
                } else {
                    self.messages.append(makeStreamingMessage(sanitized))
                    self.botStatuses[bot.id] = "speaking"
                    self.revision &+= 1
                }
            }
            let clean = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if (context.isMentioned || context.mustRespond) && MeetingRoomPersona.isPass(clean) {
                let retryNote = context.userSentSticker
                    ? "注意：用户刚发了表情包，请直接看懂画面情绪并自然回应（或回一张贴切表情包），禁止回复 [PASS]，也不要汇报工作。"
                    : "注意：请站在用户视角直接给出自然、有帮助的答复，禁止回复 [PASS]。"
                let retryRaw = try await AIService.shared.chat(
                    [.system(systemPrompt), .user(userContext + "\n\n" + retryNote)],
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
            context: context,
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
        context: MeetingTurnContext,
        receipts: [String]
    ) -> String {
        if context.userSentSticker && !context.isProgressCheck {
            let caption = context.userSticker?.searchableSummary ?? ""
            if bot.builtInID == .butler {
                return caption.isEmpty
                    ? AppLanguage.text("看到你发的图啦，先歇口气，有啥事儿尽管跟我说。", en: "Saw your sticker—take a breather and tell me what's on your mind.")
                    : AppLanguage.text("看你发了「\(caption)」，怎么啦？有啥烦心事直接丢给我帮着分担。", en: "Saw your \"\(caption)\" sticker—what's up? I'm right here.")
            }
            return caption.isEmpty
                ? AppLanguage.text("怎么啦，感觉你有点小情绪，先歇会儿，需要我搭把手随时喊。", en: "Hey, take it easy—I'm here whenever you want a hand.")
                : AppLanguage.text("拍拍你，「\(caption)」看着有点累，先喘口气，有事儿直接交给我。", en: "Pat pat—\"\(caption)\" looks rough. Take a breather and let me help.")
        }
        if !context.isProgressCheck {
            if bot.builtInID == .butler {
                return AppLanguage.text("明白你的意思了，我先盯着，需要我直接动手推进哪一步？", en: "Got it—which part should I tackle first?")
            }
            return AppLanguage.text("收到你的想法了，我这边随时待命配合。", en: "Got your point—ready to jump in whenever you need.")
        }
        if bot.builtInID == .butler && context.isButlerSynthesis {
            if context.subordinateReports.isEmpty {
                return AppLanguage.text(
                    "大家手头都挺稳，有什么需要直接点名就好。",
                    en: "All quiet across the team—ping any of us whenever needed."
                )
            }
            let names = context.subordinateReports.map(\.name).joined(separator: "、")
            var summary = AppLanguage.text("刚听完 \(names) 冒泡，重点已经对齐。", en: "Synced up with \(names).")
            if !receipts.isEmpty { summary += " " + receipts.joined(separator: "、") + "。" }
            return summary
        }
        if !evidence.isEmpty {
            return evidence.replacingOccurrences(of: "\n", with: " ")
        }
        return AppLanguage.text("在的，随时听你安排。", en: "Ready whenever you need.")
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
        let todayWork = MeetingWorkEvidenceBuilder.buildTodayWorkDigest(
            documents: self.database.documents,
            startOfDay: startOfDay
        )
        let openReminders = self.queryOpenReminderTitles(limit: 4)
        
        var map: [AIBotID: MeetingBotDailyTelemetry] = [:]
        for botID in AIBotID.allCases {
            let featureKey = botID.analyticsFeatureKey.lowercased()
            let usage = usageByFeature.first { $0.key.lowercased().contains(featureKey) }?.value ?? (0, 0)
            let result = self.buildBotEvidence(
                botID: botID,
                todayKey: todayKey,
                startOfDay: startOfDay,
                callCount: usage.0,
                tokens: usage.1,
                precomputedWork: todayWork,
                precomputedReminders: openReminders
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
        tokens: Int,
        precomputedWork: MeetingWorkEvidenceBuilder.TodayWorkDigest? = nil,
        precomputedReminders: [String]? = nil
    ) -> (badge: String, evidence: String, hasTodayActivity: Bool) {
        let todayWork = precomputedWork ?? MeetingWorkEvidenceBuilder.buildTodayWorkDigest(
            documents: self.database.documents,
            startOfDay: startOfDay
        )
        switch botID {
            case .organizeAndMerge:
                let activeDocs = self.database.documents.filter { $0.deletedAt == nil }
                let badge = todayWork.meaningfulCount > 0 ? "今日 \(todayWork.meaningfulCount) 篇" : "\(activeDocs.count) 篇"
                let summary: String
                if todayWork.items.isEmpty {
                    summary = "今天文档库暂时没有新增实质内容（库里一共 \(activeDocs.count) 篇）。"
                } else {
                    var block = "今天实际写或改了 \(todayWork.meaningfulCount) 篇有内容的文档：\n\(todayWork.digestText)"
                    if todayWork.untitledCount > 0 {
                        block += "\n（其中 \(todayWork.untitledCount) 篇暂时没起正式标题）"
                    }
                    summary = block
                }
                return (badge, summary, todayWork.meaningfulCount > 0 || callCount > 0)
            case .ghost:
                let stats = self.queryTodayWritingRow(dateKey: todayKey)
                let badge = stats.aiChars > 0 ? "续写 \(stats.aiChars) 字" : (stats.typed > 0 ? "\(stats.typed) 字" : "待命")
                let docHint = todayWork.items.first.map { "主要在写：\($0)。" } ?? ""
                let summary = stats.aiChars > 0
                    ? "今天辅助续写了 \(stats.aiChars) 字（用户自己写了 \(stats.typed) 字）。\(docHint)"
                    : "今天暂未触发 AI 续写（用户自己手写了 \(stats.typed) 字）。"
                return (badge, summary, stats.aiChars > 0 || callCount > 0)
            case .weeklyReport:
                let reports = self.database.weeklyReports
                let openReminders = precomputedReminders ?? self.queryOpenReminderTitles(limit: 4)
                let latestTitle = reports.first?.title ?? "暂无周报"
                var parts: [String] = []
                if !todayWork.digestText.isEmpty {
                    parts.append("今天实际推进过的事情：\n\(todayWork.digestText)")
                } else {
                    parts.append("今天暂未查到有实质内容的文档记录。")
                }
                if !openReminders.isEmpty {
                    parts.append("还在跟进的待办：\(openReminders.joined(separator: "、"))。")
                }
                if !reports.isEmpty {
                    parts.append("历史归档周报 \(reports.count) 份（最近「\(latestTitle)」）。")
                }
                let badge = todayWork.meaningfulCount > 0 ? "\(todayWork.meaningfulCount) 项记录" : "\(openReminders.count) 待办"
                return (badge, parts.joined(separator: "\n"), todayWork.meaningfulCount > 0 || !openReminders.isEmpty || callCount > 0)
            case .persona:
                let memories = self.queryTopMemoryTitles(limit: 4)
                let todayJournals = self.queryInt("SELECT COUNT(*) FROM user_memory_journal WHERE timestamp >= \(startOfDay);")
                let memText = memories.isEmpty ? "还在慢慢熟悉你的习惯" : memories.joined(separator: "、")
                return ("\(memories.count) 记忆", "最近观察到的偏好：\(memText)。", todayJournals > 0 || callCount > 0)
            case .readingCompanion:
                let stocks = self.queryInt("SELECT COUNT(*) FROM user_watchlist_stocks;")
                let podcasts = self.queryInt("SELECT COUNT(*) FROM user_podcasts;")
                let feeds = self.queryInt("SELECT COUNT(*) FROM user_followed_feeds;")
                let badge = stocks + podcasts + feeds > 0 ? "\(stocks + podcasts + feeds) 订阅" : "待命"
                return (badge, "目前盯着 \(stocks) 只自选股、\(podcasts) 条播客和 \(feeds) 个资讯源。", callCount > 0)
            case .butler:
                let todayMsgs = self.queryInt("SELECT COUNT(*) FROM butler_messages WHERE created_at >= \(startOfDay);")
                let openReminders = precomputedReminders ?? self.queryOpenReminderTitles(limit: 4)
                let badge = todayMsgs > 0 ? "\(todayMsgs) 条" : "在线"
                var parts: [String] = []
                if !todayWork.digestText.isEmpty {
                    parts.append("今天实际推进过的文档工作：\n\(todayWork.digestText)")
                }
                let remText = openReminders.isEmpty ? "眼下没有挂着的待办" : openReminders.joined(separator: "、")
                parts.append("手头待办：\(remText)（今天总管对话 \(todayMsgs) 条）。")
                return (badge, parts.joined(separator: "\n"), todayWork.meaningfulCount > 0 || todayMsgs > 0 || !openReminders.isEmpty)
            default:
                let badge = callCount > 0 ? "\(callCount) 次" : "待命"
                let evidence = callCount > 0 ? "今天实际协助了 \(callCount) 次（\(tokens) tokens）。" : "今天未参与具体任务。"
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
