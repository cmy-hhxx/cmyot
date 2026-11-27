//
//  MeetingRoomQualityTests.swift
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
import Testing
@testable import CotEditor

@Suite(.serialized)
struct MeetingRoomQualityTests {
    
    @Test
    func workDigestStripsWhimsicalPlaceholderTitlesAndUsesRealContent() {
        let now = Date()
        let startOfDay = Calendar.current.startOfDay(for: now).timeIntervalSince1970
        let docs = [
            StoredDocumentRecord(
                id: "doc-1",
                title: "雀跃的风铃",
                filePath: nil,
                syntax: "Markdown",
                content: "AIME 评测数据梳理：\nstep1: 清洗评测输入到 eval_input 下面\nstep2: 进行评测输出到 eval_output",
                highlightsJSON: "[]",
                updatedAt: now
            ),
            StoredDocumentRecord(
                id: "doc-2",
                title: "喝茶的睡袋",
                filePath: nil,
                syntax: "Markdown",
                content: "修复总管发消息卡死与数据看板背景断层问题",
                highlightsJSON: "[]",
                updatedAt: now.addingTimeInterval(-60)
            ),
            StoredDocumentRecord(
                id: "doc-3",
                title: "发呆的小熊",
                filePath: nil,
                syntax: "Markdown",
                content: "",
                highlightsJSON: "[]",
                updatedAt: now.addingTimeInterval(-120)
            ),
        ]
        
        let digest = MeetingWorkEvidenceBuilder.buildTodayWorkDigest(
            documents: docs,
            startOfDay: startOfDay
        )
        #expect(digest.meaningfulCount == 2)
        #expect(digest.untitledCount == 2)
        #expect(digest.digestText.contains("AIME 评测数据梳理"))
        #expect(digest.digestText.contains("eval_input"))
        #expect(digest.digestText.contains("修复总管发消息卡死"))
        #expect(!digest.digestText.contains("雀跃的风铃"))
        #expect(!digest.digestText.contains("喝茶的睡袋"))
        #expect(!digest.digestText.contains("发呆的小熊"))
    }
    
    
    @Test
    func capableSpeakersFilterOutIdleBotsOnWorkAnalysis() {
        let botIDs: [AIBotID] = [.organizeAndMerge, .ghost, .weeklyReport, .persona, .readingCompanion]
        let candidates = botIDs.map { bid in
            UnifiedBotDescriptor(
                id: bid.rawValue,
                isBuiltIn: true,
                builtInID: bid,
                customProfile: nil,
                name: bid.displayName,
                nickname: bid.defaultNickname,
                handle: bid.handle,
                roleLabel: bid.defaultNickname,
                accentHex: bid.accentHex,
                personaPrompt: "",
                preferredStickerCategories: [],
                emotion: BotEmotionEngine.initialState(
                    botID: bid.rawValue,
                    baseline: BotEmotionEngine.defaultBaseline(for: bid)
                ),
                isEnabled: true
            )
        }
        let telemetry: [AIBotID: MeetingBotDailyTelemetry] = [
            .organizeAndMerge: MeetingBotDailyTelemetry(
                botID: .organizeAndMerge, todayCallCount: 0, todayTokens: 0,
                badgeText: "今日 2 篇", evidenceSummary: "AIME 评测数据梳理", hasTodayActivity: true
            ),
            .ghost: MeetingBotDailyTelemetry(
                botID: .ghost, todayCallCount: 0, todayTokens: 0,
                badgeText: "2100 字", evidenceSummary: "暂未触发 AI 续写", hasTodayActivity: false
            ),
            .weeklyReport: MeetingBotDailyTelemetry(
                botID: .weeklyReport, todayCallCount: 0, todayTokens: 0,
                badgeText: "2 项记录", evidenceSummary: "今天完成 AIME 与看板修复", hasTodayActivity: true
            ),
            .persona: MeetingBotDailyTelemetry(
                botID: .persona, todayCallCount: 0, todayTokens: 0,
                badgeText: "2 记忆", evidenceSummary: "还在观察", hasTodayActivity: false
            ),
            .readingCompanion: MeetingBotDailyTelemetry(
                botID: .readingCompanion, todayCallCount: 0, todayTokens: 0,
                badgeText: "待命", evidenceSummary: "订阅源待命", hasTodayActivity: false
            ),
        ]
        
        let selected = MeetingWorkEvidenceBuilder.selectCapableStandupBots(
            for: "来，分析下今天都干了啥",
            candidates: candidates,
            telemetryMap: telemetry,
            isProgressCheck: true
        )
        let selectedIDs = selected.compactMap(\.builtInID)
        #expect(selectedIDs == [.weeklyReport, .organizeAndMerge])
    }
    
    
    @Test
    func personaPromptForbidsWhimsicalTitlesAndAllowsOptionalButlerPass() {
        let organizePrompt = MeetingRoomPersona.systemPrompt(
            bot: .organizeAndMerge,
            name: "整理",
            isMentioned: false,
            isButlerSynthesis: false,
            isProgressCheck: true
        )
        #expect(organizePrompt.contains("严禁提及系统临时趣味名"))
        #expect(organizePrompt.contains("[PASS]"))
        
        let optionalButler = MeetingRoomPersona.systemPrompt(
            bot: .butler,
            name: "总管",
            isMentioned: false,
            isButlerSynthesis: true,
            isProgressCheck: true
        )
        #expect(optionalButler.contains("只回复 [PASS]"))
    }
    
    
    @Test
    func customPersonaPromptOverridesCannedEmotionDirectives() {
        let customText = "说话极简、直截了当，永远只给可执行结论。"
        let builtInPrompt = MeetingRoomPersona.systemPrompt(
            bot: .weeklyReport,
            name: "周报搭档",
            isMentioned: true,
            isButlerSynthesis: false,
            customPersona: customText,
            isProgressCheck: true
        )
        #expect(builtInPrompt.contains("你的性格与情绪风格（严格遵循）：\(customText)"))
        #expect(!builtInPrompt.contains("你的底色与当下状态"))
        
        let customDescriptor = UnifiedBotDescriptor(
            id: "custom_concise",
            isBuiltIn: false,
            builtInID: nil,
            customProfile: nil,
            name: "直白",
            nickname: "直白",
            handle: "@直白",
            roleLabel: "",
            accentHex: "#2F6BFF",
            personaPrompt: customText,
            preferredStickerCategories: [],
            emotion: BotEmotionEngine.initialState(botID: "custom_concise", baseline: .calm),
            isEnabled: true
        )
        let customPrompt = MeetingRoomPersona.systemPrompt(
            bot: customDescriptor,
            isMentioned: true,
            isButlerSynthesis: false,
            isProgressCheck: false
        )
        #expect(customPrompt.contains("你的性格与情绪风格（严格遵循）：\(customText)"))
        #expect(!customPrompt.contains("你的底色与当下状态"))
    }
    
    
    @MainActor
    @Test
    func meetingRoomRosterAndWebUIBundleOmitMoodStatusBadges() {
        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: "cot_mr_roster_\(UUID().uuidString)", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        let db = CotLocalDatabase(customURL: tempDir.appending(path: "roster.sqlite3"))
        let botStore = AIBotStore(database: db)
        let manager = ButlerMeetingRoomManager(database: db)
        let roster = manager.participantRoster(botStore: botStore)
        #expect(!roster.isEmpty)
        #expect(roster.allSatisfy { $0.moodLabel == nil })
        
        let html = BeautifulAgentUIBundle.htmlDocument()
        #expect(html.contains("@文档"))
        #expect(html.contains("@Bots"))
        #expect(html.contains("新建工作区"))
        #expect(!html.contains("正在输入"))
    }
    
    
    @MainActor
    @Test
    func abortMeetingRemovesEmptySpeakingPlaceholders() {
        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: "cot_mr_abort_\(UUID().uuidString)", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        let db = CotLocalDatabase(customURL: tempDir.appending(path: "abort.sqlite3"))
        let manager = ButlerMeetingRoomManager(database: db)
        manager.appendExternalMessage(MeetingRoomMessage(
            id: "msg-empty-speaking",
            role: "bot",
            botID: "ghost",
            botName: "幽灵",
            botHandle: "@幽灵",
            botAccentHex: "#0EA5E9",
            botRoleLabel: "续写",
            botMoodLabel: nil,
            botAvatarURL: nil,
            text: "   ",
            status: "speaking",
            receipts: [],
            delegatedFromButler: false,
            createdAtMs: 100
        ))
        manager.appendExternalMessage(MeetingRoomMessage(
            id: "msg-nonempty-speaking",
            role: "bot",
            botID: "butler",
            botName: "曜",
            botHandle: "@曜",
            botAccentHex: "#3B82F6",
            botRoleLabel: "总管",
            botMoodLabel: nil,
            botAvatarURL: nil,
            text: "已经输出的部分结论",
            status: "speaking",
            receipts: [],
            delegatedFromButler: false,
            createdAtMs: 200
        ))
        
        manager.abortMeeting()
        
        #expect(!manager.messages.contains(where: { $0.id == "msg-empty-speaking" }))
        #expect(!manager.messages.contains(where: { $0.text.contains("已中止发言") }))
        let kept = manager.messages.first(where: { $0.id == "msg-nonempty-speaking" })
        #expect(kept?.status == "done")
        #expect(kept?.text == "已经输出的部分结论")
    }
}
