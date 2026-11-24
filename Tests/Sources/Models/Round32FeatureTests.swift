//
//  Round32FeatureTests.swift
//
//  Tests
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
import Testing
@testable import CotEditor

@Suite(.serialized)
@MainActor
struct Round32FeatureTests {
    
    // MARK: 1. Pi 1.6.0 Kernel Adaptation & Concise Install Prompt (< 50 lines)

    @Test func piJSONLWithoutPartialUpdatesStillAccumulatesTextInBlockOrder() {
        var state = PiKernelManager.JSONLStreamState()
        let trailing = state.ingest([
            "type": "message_update",
            "assistantMessageEvent": ["type": "text_delta", "contentIndex": 1, "delta": "world"],
        ], includePartialUpdates: false)
        let leading = state.ingest([
            "type": "message_update",
            "assistantMessageEvent": ["type": "text_delta", "contentIndex": 0, "delta": "Hello "],
        ], includePartialUpdates: false)

        #expect(trailing.partialSnapshot == nil)
        #expect(leading.partialSnapshot == nil)
        #expect(state.resolvedOutput == "Hello world")
    }
    
    
    
    @Test func piKernel16AdaptationAndConciseInstallPrompt() throws {
        let promptLines = PiKernelManager.installPrompt.components(separatedBy: .newlines)
        #expect(!promptLines.isEmpty)
        #expect(promptLines.count <= 50, "Install prompt must stay <= 50 lines, got \(promptLines.count)")
        #expect(PiKernelManager.installPrompt.contains("pi.dev/install.sh"))
        #expect(PiKernelManager.installPrompt.contains("@earendil-works/pi-coding-agent"))
        
        // Verify Pi 1.6.0 JSONL stream state reconstruction (text_delta, text_end, message_end, dict error, auto_retry_end, agent_settled)
        var state = PiKernelManager.JSONLStreamState()
        let u1 = state.ingest([
            "type": "message_update",
            "assistantMessageEvent": ["type": "text_delta", "contentIndex": 0, "delta": "Hello "],
        ])
        #expect(u1.partialSnapshot == "Hello ")
        let u2 = state.ingest([
            "type": "message_update",
            "assistantMessageEvent": ["type": "text_delta", "contentIndex": 0, "delta": "Pi"],
        ])
        #expect(u2.partialSnapshot == "Hello Pi")
        let u3 = state.ingest([
            "type": "message_update",
            "assistantMessageEvent": ["type": "text_end", "contentIndex": 0, "content": "Hello Pi 1.6"],
        ])
        #expect(u3.partialSnapshot == "Hello Pi 1.6")
        _ = state.ingest([
            "type": "message_end",
            "message": [
                "role": "assistant",
                "content": [["type": "text", "text": "Final Pi 1.6 Reply"]],
            ],
        ])
        _ = state.ingest(["type": "agent_settled", "aborted": false])
        #expect(state.resolvedOutput == "Final Pi 1.6 Reply")
        #expect(state.isSettled)
        
        var errState = PiKernelManager.JSONLStreamState()
        _ = errState.ingest([
            "type": "message_update",
            "assistantMessageEvent": [
                "type": "error",
                "reason": "error",
                "error": ["errorMessage": "Upstream gateway timeout"],
            ],
        ])
        #expect(errState.errorMessage == "Upstream gateway timeout")
        _ = errState.ingest([
            "type": "auto_retry_end",
            "success": false,
            "finalError": "Retry exhausted",
        ])
        #expect(errState.errorMessage == "Retry exhausted")
        
        // Verify workspace sync generates Pi 1.6+ settings.json and reasoning flags
        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: "cot_r32_pi_\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        let db = CotLocalDatabase(customURL: tempDir.appending(path: "test.sqlite3"))
        let botStore = AIBotStore(database: db)
        let piDir = tempDir.appending(path: "PiKernel", directoryHint: .isDirectory)
        let kernel = PiKernelManager(customAgentDirectoryURL: piDir, database: db)
        
        let gw = AIEndpointProfile(
            name: "OpenAI",
            endpoint: .openAIChatCompletions,
            baseURL: "https://api.openai.com/v1",
            model: "gpt-6.2-sol",
            savedModels: ["gpt-6.2-sol", "gpt-4o-mini"]
        )
        _ = try kernel.syncWorkspace(endpoints: [gw], botStore: botStore, keyLookup: { _ in "sk-r32" })
        
        let settingsURL = piDir.appending(path: "settings.json")
        let settingsJSON = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: settingsURL)) as? [String: Any])
        #expect(settingsJSON["quietStartup"] as? Bool == true)
        let retry = try #require(settingsJSON["retry"] as? [String: Any])
        #expect(retry["enabled"] as? Bool == false)
        
        let env = PiKernelManager.augmentedRuntimeEnvironment(agentDirectoryPath: piDir.path(percentEncoded: false))
        #expect(env["PI_CODING_AGENT_DIR"] == piDir.path(percentEncoded: false))
        #expect(env["PI_OFFLINE"] == "1")
        #expect((env["PATH"] ?? "").contains("/opt/homebrew/bin"))
    }
    
    
    // MARK: 2. Reject Test Junk (111 / 222 / test) & Lively Done Today Commentary
    
    @Test func actionSubstanceRejectsTestNoiseAndDoneTodayIsLively() throws {
        for junk in ["111", "222", "111 222", "123456", "test", "testing", "测试111", "测试", "aaa", "asdf", "qwer"] {
            #expect(!AnalyticsManager.hasMeaningfulActionSubstance(junk), "Should reject junk: \(junk)")
        }
        #expect(AnalyticsManager.hasMeaningfulActionSubstance("把首页交互卡顿那块收尾掉"))
        
        let junkDoc = StoredDocumentRecord(
            id: "doc-junk",
            title: "scratch.txt",
            filePath: nil,
            syntax: "Plain Text",
            content: "111\n222\n- [ ] 111\n- [ ] 222\nTODO: test 111\n",
            highlightsJSON: "[]",
            updatedAt: Date(),
            createdAt: Date()
        )
        let junkReminder = UserReminder(
            id: "rem-junk",
            title: "111",
            dueDate: Date().addingTimeInterval(3600),
            dueDayKey: AnalyticsManager.dateKey(),
            isCompleted: false,
            hasDeadline: true
        )
        let preds = AnalyticsManager.buildHeuristicActionPredictions(
            documents: [junkDoc],
            weeklyReports: [],
            reminders: [junkReminder]
        )
        let joined = preds.map(\.action).joined(separator: "\n")
        #expect(!joined.contains("111"))
        #expect(!joined.contains("222"))
        #expect(!joined.lowercased().contains("test"))
        
        let parsedDone = AnalyticsManager.parseDoneTodayCommentary(
            from: #"["今天手速直接开挂，这波输出太牛逼了", "光挖坑不填坑，少摸点鱼赶紧收尾"]"#,
            knownTitles: ["Roadmap"]
        )
        #expect(parsedDone.count == 2)
        
        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: "cot_r32_analytics_\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let db = CotLocalDatabase(customURL: tempDir.appending(path: "analytics.sqlite3"))
        let analytics = AnalyticsManager(database: db)
        let localPoints = analytics.doneTodayPoints
        #expect(!localPoints.isEmpty)
        #expect(!localPoints.contains("推进近期文稿内容撰写与结构迭代"))
    }
    
    
    // MARK: 3. Xiaohongshu NEWS Card Feed + Detail AI Chat Layout
    
    @Test func xiaohongshuNewsGridAndDetailAIChatRenderCleanly() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: "cot_r32_news_\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        let db = CotLocalDatabase(customURL: tempDir.appending(path: "news.sqlite3"))
        let service = AIHotNewsService(database: db, cacheRootDirectory: tempDir.appending(path: "cache"))
        let sample = AIHotNewsItem(
            id: "xhs-sample-1",
            title: "Pi 1.6.0 发布：支持 GPT-6.2 与更快的增量 JSONL 事件流",
            source: "Tech Feed",
            urlString: "https://example.com/pi-16",
            publishedAt: Date(),
            heatScore: 95,
            tag: "AI",
            summary: "新版本改进了流式事件协议与本地执行速度。"
        )
        service.setAIBrief("核心点评：增量事件更稳，直接抄作业。", for: sample.id)
        #expect(service.chatMessages(for: sample).count == 1)
        service.clearChat(for: sample.id)
        
        let tokens = DashPalette.editorialTokens(isDark: false)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1120, height: 760),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .aqua)
        let host = NSHostingController(
            rootView: DashboardNewsCenterView(
                newsService: service,
                tokens: tokens,
                initialSelectedID: nil,
                onClose: {}
            )
            .environment(\.colorScheme, .light)
        )
        host.sizingOptions = []
        window.contentViewController = host
        window.setContentSize(NSSize(width: 1120, height: 760))
        window.contentView?.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        #expect(abs((window.contentView?.bounds.height ?? 0) - 760) <= 2)
        window.close()
    }
}
