//
//  Round19FeatureTests.swift
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
import Testing
@testable import CotEditor

@Suite(.serialized)
@MainActor
struct Round19FeatureTests {
    
    // MARK: 1. Full Database Migration (Endpoints + Keys + User Profile + Bots + Todos + Personality)
    
    @Test func fullDatabaseExportImportPreservesAPIKeysAvatarBotsTodosAndPersonality() throws {
        
        let origProfiles = AIEndpointStore.profiles
        let origActiveID = AIEndpointStore.activeID
        let origKeys = AIKeychain.allAPIKeys()
        defer {
            AIEndpointStore.profiles = origProfiles
            AIEndpointStore.activeID = origActiveID
            for id in AIEndpointStore.profiles.map(\.id) {
                AIKeychain.removeAPIKey(for: id)
            }
            AIKeychain.mergeAPIKeys(origKeys, overwriteExisting: true)
        }
        
        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: "CotRound19Migration_\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        let sourceDBURL = tempDir.appending(path: "source.sqlite3")
        let exportURL = tempDir.appending(path: "portable_export.sqlite3")
        let destDBURL = tempDir.appending(path: "dest.sqlite3")
        let sourceRoot = tempDir.appending(path: "src_users", directoryHint: .isDirectory)
        let destRoot = tempDir.appending(path: "dst_users", directoryHint: .isDirectory)
        
        // 1. Seed source API endpoint + secret API key
        let endpointID = UUID()
        let endpoint = AIEndpointProfile(
            id: endpointID,
            name: "Migration Gateway",
            endpoint: .openAIChatCompletions,
            baseURL: "https://api.example.com/v1",
            model: "deepseek-chat"
        )
        AIEndpointStore.profiles = [endpoint]
        AIEndpointStore.activeID = endpointID
        AIKeychain.setAPIKey("sk-round19-secret-key-9876", for: endpointID)
        
        // 2. Seed source user avatar & profile
        let sourceUserMgr = UserProfileManager(rootDirectory: sourceRoot)
        let fakeAvatarPNG: Data? = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x01, 0x02, 0x03])
        sourceUserMgr.updateProfile(
            id: sourceUserMgr.activeProfile.id,
            displayName: "测试迁移作家",
            avatarData: fakeAvatarPNG,
            avatarColorHex: "#E06D53"
        )
        
        // 3. Seed source DB with endpoints, keys, user snapshot, bot config, pinned todo, and personality profile
        let sourceDB = CotLocalDatabase(customURL: sourceDBURL)
        sourceDB.syncAIEndpointsToDatabase()
        sourceDB.syncUserProfileToDatabase(sourceUserMgr.activeProfile)
        
        let sourceBots = AIBotStore(database: sourceDB)
        sourceBots.updateConfig(AIBotConfig(isEnabled: false, modelOverride: "gpt-4o-mini"), for: .translate)
        
        let sourceAnalytics = AnalyticsManager(database: sourceDB)
        let pinned = try #require(sourceAnalytics.addPinnedTodo(title: "发版本检查清单", deadline: Date().addingTimeInterval(1800)))
        let tag = UserPersonalityTag(label: "细节控本人", explanation: "每一步都有严格校验", tone: .sharp)
        let personality = UserPersonalityProfile(
            tags: [tag],
            conceptTitle: "务实工匠",
            conceptSummary: "重视真实闭环与细节质感。",
            writingStyleNotes: ["短句利落"],
            sourceFingerprint: "fp-round19",
            modelUsed: "deepseek-chat",
            generatedAt: Date()
        )
        sourceAnalytics.savePersonalityProfile(personality)
        
        // 4. Export database
        try sourceDB.exportDatabase(to: exportURL)
        
        // 5. Wipe in-memory endpoint/key state to prove import restores everything from exportURL alone
        AIEndpointStore.profiles = []
        AIEndpointStore.activeID = nil
        AIKeychain.removeAPIKey(for: endpointID)
        #expect(AIKeychain.apiKey(for: endpointID).isEmpty)
        
        // 6. Import into fresh destination database & UserProfileManager
        let destDB = CotLocalDatabase(customURL: destDBURL)
        try destDB.importDatabase(from: exportURL)
        
        let destUserMgr = UserProfileManager(rootDirectory: destRoot)
        destDB.restoreUserProfileFromDatabase(to: destUserMgr)
        
        #expect(AIEndpointStore.profiles.contains { $0.id == endpointID && $0.baseURL == "https://api.example.com/v1" })
        #expect(AIKeychain.apiKey(for: endpointID) == "sk-round19-secret-key-9876")
        
        #expect(destUserMgr.activeProfile.displayName == "测试迁移作家")
        #expect(destUserMgr.activeProfile.avatarData == fakeAvatarPNG)
        #expect(destUserMgr.activeProfile.avatarColorHex == "#E06D53")
        
        let destBots = AIBotStore(database: destDB)
        let restoredTranslateBot = destBots.config(for: .translate)
        #expect(restoredTranslateBot.isEnabled == false)
        #expect(restoredTranslateBot.modelOverride == "gpt-4o-mini")
        
        let destAnalytics = AnalyticsManager(database: destDB)
        #expect(destAnalytics.pinnedTodos.contains { $0.id == pinned.id && $0.title == "发版本检查清单" && $0.hasDeadline })
        #expect(destAnalytics.personalityProfile?.conceptTitle == "务实工匠")
        #expect(destAnalytics.personalityProfile?.tags.first?.label == "细节控本人")
    }
    
    
    // MARK: 2. GrokBot-Style AIBotStore Configuration & Reset
    
    @Test func aiBotStorePersistsOverridesTogglesAndResetsCleanly() throws {
        
        let tempURL = FileManager.default.temporaryDirectory
            .appending(path: "cot_bots_\(UUID().uuidString).sqlite3")
        defer { try? FileManager.default.removeItem(at: tempURL) }
        
        let db = CotLocalDatabase(customURL: tempURL)
        let store = AIBotStore(database: db)
        
        var config = store.config(for: .weeklyReport)
        #expect(config.isEnabled == true)
        config.isEnabled = false
        config.modelOverride = "claude-3-7-sonnet"
        config.temperature = 0.25
        store.updateConfig(config, for: .weeklyReport)
        store.setSystemPrompt("只输出事实列表，不要客套话。", for: .weeklyReport)
        
        let reloaded = AIBotStore(database: db)
        let loadedConfig = reloaded.config(for: .weeklyReport)
        #expect(loadedConfig.isEnabled == false)
        #expect(loadedConfig.modelOverride == "claude-3-7-sonnet")
        #expect(reloaded.systemPrompt(for: .weeklyReport) == "只输出事实列表，不要客套话。")
        
        let resolved = reloaded.resolvedConfiguration(
            for: .weeklyReport,
            baseConfig: AIConfiguration(endpoint: .openAIChatCompletions, baseURL: "https://api.example.com", model: "default-model", apiKey: "k")
        )
        #expect(resolved.model == "claude-3-7-sonnet")
        #expect(resolved.temperature == 0.25)
        
        reloaded.resetBotToDefaults(.weeklyReport)
        #expect(reloaded.config(for: .weeklyReport).isEnabled == true)
        #expect(reloaded.config(for: .weeklyReport).modelOverride.isEmpty)
    }
    
    
    // MARK: 3. ASCII Pass License & Serial Helpers
    
    @Test func cotPassLicenseValidationAndSerialFormat() {
        
        #expect(CotPassLicense.validate("COT-PRO-A1B2-C3D4") == .pro)
        #expect(CotPassLicense.validate("  cot-founder-9x8y-z1w2 ") == .founder)
        #expect(CotPassLicense.validate("COT-FOUNDER-ABCD") == .founder)
        #expect(CotPassLicense.validate("INVALID-KEY") == nil)
        #expect(CotPassLicense.validate("") == nil)
        
        let serial = CotPassLicense.generateSerialCode()
        #expect(serial.hasSuffix("V1"))
        #expect(serial.count == 9)
        #expect(CotPassTheme.allThemes.count >= 4)
    }
    
    
    // MARK: 4. Dashboard Telemetry, Local vs Cloud Split, and Zero Template Fluff
    
    @Test func dashboardMetricsTrackLocalVsCloudAndHourlyBucketsWithoutFluff() throws {
        
        let tempURL = FileManager.default.temporaryDirectory
            .appending(path: "cot_dash_\(UUID().uuidString).sqlite3")
        defer { try? FileManager.default.removeItem(at: tempURL) }
        
        let db = CotLocalDatabase(customURL: tempURL)
        let analytics = AnalyticsManager(database: db)
        
        // Simulate typing and completions
        analytics.recordTypedCharacters(420)
        analytics.recordGhostCompletionAccepted(charCount: 30, isFromAI: false)
        analytics.recordGhostCompletionAccepted(charCount: 95, isFromAI: true)
        analytics.recordLocalCompletionHit()
        analytics.flushPendingStats()
        
        let stats = analytics.todayStats
        #expect(stats.typedChars >= 420)
        #expect(stats.aiCompletedChars == 125)
        #expect(stats.aiCompletionAccepts == 2)
        #expect(stats.localAcceptedChars == 30)
        #expect(stats.maxSingleAcceptChars == 95)
        #expect(stats.localHits == 1)
        
        let currentHour = Calendar.current.component(.hour, from: Date())
        let pulse = analytics.hourlyWritingPulse(for: stats.dateKey)
        #expect(pulse.count == 24)
        #expect(pulse[currentHour] >= 420)
        
        // Verify daily story contains zero template buzzwords
        let hm = analytics.yearlyHeatmap(year: Calendar.current.component(.year, from: Date()), trimFutureWeeks: true)
        let todayCell = try #require(hm.weeks.flatMap(\.self).first(where: { $0.dateKey == stats.dateKey }))
        let story = analytics.humanDayStory(for: todayCell)
        #expect(story.moodTag.isEmpty)
        #expect(!story.headline.contains("火力全开"))
        #expect(!story.headline.contains("人机协作"))
        #expect(!story.headline.contains("点击跳转"))
    }
    
    
    // MARK: 5. 6-Hour AI Personality Analyzer (<= 8 Char Clamping & Scheduling)
    
    @Test func personalityAnalyzerClampsTagsAndHonorsSixHourSchedule() throws {
        
        #expect(UserPersonalityAnalyzer.clampTagLabel("  #「极度喜欢追求完美细节的人格类型」  ").count <= 8)
        #expect(UserPersonalityAnalyzer.clampTagLabel("1. 说人话专家。") == "说人话专家")
        
        let rawJSON = """
        ```json
        {
          "concept_title": "清醒实干派",
          "concept_summary": "习惯先把复杂问题拆解再逐步落笔，重视可验证结果。",
          "writing_style_notes": ["高频复盘", "直奔主题"],
          "tags": [
            {"label": "超长个性标签超过八个字的测试", "explanation": "长标签应自动截断", "tone": "sharp"},
            {"label": "行动派", "explanation": "说干就干", "tone": "warm"}
          ]
        }
        ```
        """
        let parsed = try #require(UserPersonalityAnalyzer.parseResponse(rawJSON, sourceFingerprint: "fp-1", modelUsed: "test-model"))
        #expect(parsed.conceptTitle == "清醒实干派")
        #expect(parsed.tags.count == 2)
        #expect(parsed.tags.allSatisfy { $0.label.count <= UserPersonalityAnalyzer.maxTagCharacters })
        
        let baseDate = Date(timeIntervalSince1970: 1_700_000_000)
        // Fresh AI profile should NOT auto-rerun after only 2 hours
        #expect(
            UserPersonalityAnalyzer.shouldAutoRun(
                now: baseDate.addingTimeInterval(2 * 3600),
                lastProfile: parsed,
                currentFingerprint: "fp-changed",
                currentCharCount: 500
            ) == false
        )
        // After 6 hours with changed input, should auto-run
        #expect(
            UserPersonalityAnalyzer.shouldAutoRun(
                now: baseDate.addingTimeInterval(6 * 3600 + 10),
                lastProfile: UserPersonalityProfile(
                    tags: parsed.tags,
                    conceptTitle: parsed.conceptTitle,
                    conceptSummary: parsed.conceptSummary,
                    writingStyleNotes: parsed.writingStyleNotes,
                    sourceFingerprint: "fp-1",
                    modelUsed: "test-model",
                    generatedAt: baseDate
                ),
                currentFingerprint: "fp-changed",
                currentCharCount: 500
            ) == true
        )
    }
    
    
    // MARK: 6. Featherweight Capsule Pinned Todo Escalation (Non-Intrusive)
    
    @Test func pinnedTodoFontEscalatesUntilWindowBurstingOnDeadline() {
        
        let container = CGSize(width: 1100, height: 760)
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let createdAt = now.addingTimeInterval(-3600)
        
        let timeless = PinnedTodoUrgency.metrics(createdAt: createdAt, deadline: nil, now: now, containerSize: container)
        let far = PinnedTodoUrgency.metrics(createdAt: now, deadline: now.addingTimeInterval(6 * 3600), now: now, containerSize: container)
        let approaching = PinnedTodoUrgency.metrics(createdAt: createdAt, deadline: now.addingTimeInterval(40 * 60), now: now, containerSize: container)
        let imminent = PinnedTodoUrgency.metrics(createdAt: createdAt, deadline: now.addingTimeInterval(4 * 60), now: now, containerSize: container)
        let overdue = PinnedTodoUrgency.metrics(createdAt: createdAt, deadline: now.addingTimeInterval(-30), now: now, containerSize: container)
        
        #expect(timeless.urgencyLevel == 0)
        #expect(timeless.isWindowBursting == false)
        #expect(far.fontSize > timeless.fontSize)
        #expect(approaching.fontSize > far.fontSize)
        #expect(imminent.fontSize > approaching.fontSize)
        #expect(overdue.fontSize > imminent.fontSize)
        #expect(overdue.isOverdue == true)
        #expect(overdue.isWindowBursting == false)
        #expect(timeless.fontSize >= 11.0 && overdue.fontSize <= 14.5)
    }
    
    
    // MARK: 7. Bug 1 — Pane Zoom Disables Ctrl-A " / % Splitting
    
    @Test func zoomedPaneBlocksSplitCommandsUntilUnzoomed() throws {
        
        let doc = Document()
        let docVC = DocumentViewController(document: doc)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 600),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.animationBehavior = .none
        window.contentViewController = docVC
        docVC.view.layoutSubtreeIfNeeded()
        defer { window.orderOut(nil) }
        
        let initialTV = try #require(docVC.focusedTextView)
        #expect(docVC.editorViewControllers.count == 1)
        
        // Split once -> 2 panes
        docVC.splitEditorVertically(initialTV)
        #expect(docVC.editorViewControllers.count == 2)
        
        // Zoom pane (`Ctrl-A z`)
        let activeTV = try #require(docVC.focusedTextView)
        docVC.togglePaneZoom(activeTV)
        #expect(docVC.isPaneZoomed == true)
        
        // Attempting vertical (`Ctrl-A %`) or horizontal (`Ctrl-A "`) split must be blocked while zoomed
        docVC.splitEditorVertically(activeTV)
        #expect(docVC.editorViewControllers.count == 2)
        docVC.splitEditorHorizontally(activeTV)
        #expect(docVC.editorViewControllers.count == 2)
        
        // Unzoom restores splitting
        docVC.togglePaneZoom(activeTV)
        #expect(docVC.isPaneZoomed == false)
        docVC.splitEditorHorizontally(activeTV)
        #expect(docVC.editorViewControllers.count == 3)
    }
}
