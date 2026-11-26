//
//  ButlerDailyReportService.swift
//
//  CotEditor
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

/// Pure offline composer for the evening bot-to-butler-to-user daily digest.
nonisolated enum ButlerDailyReportComposer {
    
    static func compose(
        botReports: [(name: String, text: String)],
        butlerName: String
    ) -> String {
        let cleanName = butlerName.trimmingCharacters(in: .whitespacesAndNewlines)
        let speaker = cleanName.isEmpty ? "总管" : cleanName
        let valid = botReports.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard !valid.isEmpty else {
            return "\(speaker)来对个账：今天大家都挺安静的，手里暂时没攒下新进展，早点休息，明天有需要随时喊我们。"
        }
        let highlights = valid.prefix(3).map { item -> String in
            let snippet = item.text
                .replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return "\(item.name)那边，\(String(snippet.prefix(46)))"
        }.joined(separator: "；")
        return "今天各位都跟我碰过头了，重点帮你捋一下：\(highlights)。明天按自己节奏接着推就行，有事随时叫我。"
    }
}


/// Collects daily progress reports from active specialist bots to the Butler once a day (>= 18:00),
/// posts their reports to the Meeting Room, and delivers a concise user-facing digest in Butler chat.
@MainActor @Observable
final class ButlerDailyReportService {
    
    static let shared = ButlerDailyReportService()
    
    private let database: CotLocalDatabase
    @ObservationIgnored private var schedulerTask: Task<Void, Never>?
    private(set) var lastReportedDayKey: String = ""
    
    
    init(database: CotLocalDatabase = .shared) {
        self.database = database
        self.lastReportedDayKey = database.string(forKey: CotLocalDatabase.ConfigKey.butlerDailyReportLastDayKey)
    }
    
    
    isolated deinit {
        self.schedulerTask?.cancel()
    }
    
    
    func startBackgroundScheduler() {
        guard !CotLocalDatabase.isRunningUnitTests else { return }
        guard self.schedulerTask == nil else { return }
        
        self.schedulerTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(600))
                guard !Task.isCancelled, let self else { break }
                _ = await self.runIfDue(now: Date(), allowRemoteAI: true)
            }
        }
    }
    
    
    @discardableResult
    func runIfDue(now: Date = Date(), allowRemoteAI: Bool = true) async -> Bool {
        let hour = Calendar.current.component(.hour, from: now)
        guard hour >= 18 else { return false }
        let dayKey = AnalyticsManager.dateKey(for: now)
        let savedKey = self.database.string(forKey: CotLocalDatabase.ConfigKey.butlerDailyReportLastDayKey)
        guard savedKey != dayKey else { return false }
        
        self.database.set(dayKey, forKey: CotLocalDatabase.ConfigKey.butlerDailyReportLastDayKey)
        self.lastReportedDayKey = dayKey
        await self.generateAndDeliverDailyReport(dayKey: dayKey, now: now, allowRemoteAI: allowRemoteAI)
        return true
    }
    
    
    private func generateAndDeliverDailyReport(dayKey: String, now: Date, allowRemoteAI: Bool) async {
        let meetingRoom = ButlerMeetingRoomManager.shared
        let botStore = AIBotStore.shared
        let telemetryMap = meetingRoom.collectDailyTelemetryByBot()
        
        var collectedReports: [(name: String, text: String)] = []
        for botID in AIBotID.allCases where botID != .butler {
            guard botStore.config(for: botID).isEnabled else { continue }
            guard let telemetry = telemetryMap[botID], telemetry.hasTodayActivity else { continue }
            
            let botName = botStore.resolvedName(for: botID)
            let reportText = await self.generateBotToButlerReport(
                botID: botID,
                botName: botName,
                evidence: telemetry.evidenceSummary,
                allowRemoteAI: allowRemoteAI,
                botStore: botStore
            )
            guard !MeetingRoomPersona.isPass(reportText) else { continue }
            
            collectedReports.append((name: botName, text: reportText))
            let message = MeetingRoomMessage(
                id: "mr-daily-\(botID.rawValue)-\(UUID().uuidString)",
                role: "bot",
                botID: botID.rawValue,
                botName: botName,
                botHandle: botID.handle,
                botAccentHex: botID.accentHex,
                botRoleLabel: AppLanguage.text("向总管汇报", en: "To Chief"),
                text: reportText,
                status: "done",
                receipts: [],
                delegatedFromButler: false,
                createdAtMs: now.timeIntervalSince1970 * 1000
            )
            meetingRoom.appendExternalMessage(message)
        }
        
        let butlerName = CotButlerManager.shared.name
        let digest = await self.generateButlerDigest(
            butlerName: butlerName,
            botReports: collectedReports,
            butlerEvidence: telemetryMap[.butler]?.evidenceSummary ?? "",
            allowRemoteAI: allowRemoteAI,
            botStore: botStore
        )
        CotButlerManager.shared.postDailyReport(text: digest)
        
        let tip = ProactiveTipItem(
            id: UUID().uuidString,
            dedupKey: "daily-report:\(dayKey)",
            category: "今日汇报",
            headline: "\(butlerName) · 今日工作汇报",
            body: String(digest.prefix(48)),
            entryText: digest,
            createdAt: now
        )
        ProactiveDailyJournalService.shared.publishExternalTip(tip)
    }
    
    
    private func generateBotToButlerReport(
        botID: AIBotID,
        botName: String,
        evidence: String,
        allowRemoteAI: Bool,
        botStore: AIBotStore
    ) async -> String {
        var config = botStore.resolvedConfiguration(for: botID)
        if botStore.config(for: botID).temperature == nil {
            config.temperature = 0.85
        }
        let canCallRemote = allowRemoteAI && AIService.shared.isConfigured && !config.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        guard canCallRemote else { return evidence }
        
        let systemPrompt = MeetingRoomPersona.systemPrompt(
            bot: botID,
            name: botName,
            isMentioned: false,
            isButlerSynthesis: false,
            customPersona: botStore.config(for: botID).customPersona
        )
        let userContext = """
        向总管简短汇报你今天的进展，用 1-2 句人话讲清重点。如果没有真正有价值的新进展，只回复 \(MeetingRoomPersona.passToken)。
        【你的真实本地数据】
        \(evidence)
        """
        do {
            let raw = try await AIService.shared.chat(
                [.system(systemPrompt), .user(userContext)],
                configuration: config,
                analyticsFeature: "daily_bot_\(botID.rawValue)"
            )
            let clean = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if !clean.isEmpty { return clean }
        } catch {
            // Fall back to deterministic evidence text
        }
        return evidence
    }
    
    
    private func generateButlerDigest(
        butlerName: String,
        botReports: [(name: String, text: String)],
        butlerEvidence: String,
        allowRemoteAI: Bool,
        botStore: AIBotStore
    ) async -> String {
        var config = botStore.resolvedConfiguration(for: .butler)
        if botStore.config(for: .butler).temperature == nil {
            config.temperature = 0.85
        }
        let canCallRemote = allowRemoteAI && AIService.shared.isConfigured && !config.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        guard canCallRemote else {
            return ButlerDailyReportComposer.compose(botReports: botReports, butlerName: butlerName)
        }
        
        let systemPrompt = """
        你是用户的总管「\(butlerName)」。刚才各路助手已经向你汇报了今天的工作，现在由你转述给用户。
        \(MeetingRoomPersona.voice(for: .butler))
        要求：给用户的今日汇报：先一句话总评，然后最多3条重点（谁干了什么、有什么值得注意），可选一句明天提醒；≤150字；有人味，像靠谱同事发微信；不流水账，不罗列没进展的Bot；不要用标题、加粗、编号模板或 emoji。
        """
        let reportsBlock = botReports.isEmpty
            ? "今天各专业助手都没有额外新进展。"
            : botReports.map { "\($0.name)：\($0.text)" }.joined(separator: "\n")
        let userContext = """
        【各助手向总管的汇报】
        \(reportsBlock)
        
        【总管侧今日情况】
        \(butlerEvidence)
        """
        do {
            let raw = try await AIService.shared.chat(
                [.system(systemPrompt), .user(userContext)],
                configuration: config,
                analyticsFeature: "daily_butler_digest"
            )
            let clean = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if !clean.isEmpty { return clean }
        } catch {
            // Fall back to deterministic composer
        }
        return ButlerDailyReportComposer.compose(botReports: botReports, butlerName: butlerName)
    }
}
