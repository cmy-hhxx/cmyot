//
//  Round33FeatureTests.swift
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
import Shortcut
import SwiftUI
import Testing
@testable import CotEditor

@Suite(.serialized)
@MainActor
struct Round33FeatureTests {
    
    // MARK: 1. KeyBindingModel Single-Click Recorder State Machine
    
    @Test func keyBindingModelSingleClickRecordingCancelAndClearLifecycle() throws {
        let model = KeyBindingModel()
        let initialShortcut = Shortcut(keySpecChars: "@k")
        let item = KeyBindingItem(
            action: NSSelectorFromString("dummyTestAction:"),
            tag: 0,
            shortcut: initialShortcut,
            defaultShortcut: initialShortcut
        )
        defer { model.stopRecording() }
        
        // Single-click toggle enters and exits recording cleanly
        #expect(!model.isRecording(item))
        model.toggleRecording(item)
        #expect(model.isRecording(item))
        #expect(model.recordingItemID == ObjectIdentifier(item))
        
        model.toggleRecording(item)
        #expect(!model.isRecording(item))
        #expect(model.recordingItemID == nil)
        
        // Esc cancels recording without altering shortcut
        model.startRecording(item)
        let escEvent = try #require(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "\u{1B}",
            charactersIgnoringModifiers: "\u{1B}",
            isARepeat: false,
            keyCode: 53
        ))
        #expect(model.handleRecordedKeyEvent(escEvent) == true)
        #expect(!model.isRecording(item))
        #expect(item.shortcut == initialShortcut)
        
        // Backspace clears shortcut and exits recording cleanly
        model.startRecording(item)
        let deleteEvent = try #require(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "\u{7F}",
            charactersIgnoringModifiers: "\u{7F}",
            isARepeat: false,
            keyCode: 51
        ))
        #expect(model.handleRecordedKeyEvent(deleteEvent) == true)
        #expect(!model.isRecording(item))
        #expect(item.shortcut == nil)
    }
    
    
    // MARK: 2. Star-Map Document Center Mounts & Lays Out Cleanly
    
    @Test func starMapDocumentCenterMountsAndComputesCleanConstellation() throws {
        let state = DocumentCenterState()
        let view = DocumentCenterView(
            state: state,
            onOpenDocument: { _, _ in },
            onCreateNewDocument: { },
            onDismiss: { }
        )
        
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1120, height: 720),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        defer { window.close() }
        
        let host = NSHostingController(rootView: view)
        host.sizingOptions = []
        window.contentViewController = host
        window.setContentSize(NSSize(width: 1120, height: 720))
        
        let contentView = try #require(window.contentView)
        contentView.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.15))
        contentView.layoutSubtreeIfNeeded()
        
        #expect(abs(contentView.bounds.width - 1120) <= 2)
        #expect(abs(contentView.bounds.height - 720) <= 2)
        
        // Verify StarMapLayoutEngine keeps cluster & leaf nodes well-separated
        let layout = StarMapLayoutEngine.compute(
            clusterIDs: ["g1", "g2", "g3"],
            leafCountsByCluster: ["g1": 3, "g2": 2, "g3": 1],
            collapsedClusterIDs: [],
            leafIDsByCluster: ["g1": ["d1", "d2", "d3"], "g2": ["d4", "d5"], "g3": ["d6"]]
        )
        #expect(layout.clusters.count == 3)
        #expect(layout.leaves.count == 6)
        #expect(layout.bounds.width > 360)
        #expect(layout.bounds.height > 280)
    }
    
    
    // MARK: 3. Star-Map Weekly Report Center Mounts & Lays Out Cleanly
    
    @Test func starMapWeeklyReportCenterMountsCleanly() throws {
        let state = WeeklyReportCenterState()
        let view = WeeklyReportCenterView(
            state: state,
            onOpenReport: { _ in },
            onDismiss: { }
        )
        
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1120, height: 720),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        defer { window.close() }
        
        let host = NSHostingController(rootView: view)
        host.sizingOptions = []
        window.contentViewController = host
        window.setContentSize(NSSize(width: 1120, height: 720))
        
        let contentView = try #require(window.contentView)
        contentView.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.15))
        contentView.layoutSubtreeIfNeeded()
        
        #expect(abs(contentView.bounds.width - 1120) <= 2)
        #expect(abs(contentView.bounds.height - 720) <= 2)
    }
    
    
    // MARK: 4. OpenCode Go & Mainstream cc-switch Presets
    
    @Test func aiProviderIncludesOpenCodeGoFlagshipAndMainstreamPresets() {
        #expect(AIProvider.curatedPresets.first == .openCodeGo)
        #expect(AIProvider.curatedPresets.count >= 12)
        
        let openAIProfile = AIProvider.openCodeGo.makeProfile()
        #expect(openAIProfile.endpoint == .openAIChatCompletions)
        #expect(openAIProfile.baseURL == "https://opencode.ai/zen/go/v1")
        #expect(!openAIProfile.savedModels.isEmpty)
        #expect(openAIProfile.customHeaders["x-opencode-session"] != nil)
        #expect(AIProvider.detect(endpoint: openAIProfile.endpoint, baseURL: openAIProfile.baseURL) == .openCodeGo)
        
        let anthropicProfile = AIProvider.openCodeGo.makeProfile(useAnthropicProtocol: true)
        #expect(anthropicProfile.endpoint == .anthropicMessages)
        #expect(anthropicProfile.baseURL == "https://opencode.ai/zen/go")
        #expect(AIProvider.detect(endpoint: anthropicProfile.endpoint, baseURL: anthropicProfile.baseURL) == .openCodeGo)
        
        #expect(AIProvider.detect(endpoint: .openAIChatCompletions, baseURL: AIProvider.zhipu.defaultBaseURL) == .zhipu)
        #expect(AIProvider.detect(endpoint: .openAIChatCompletions, baseURL: AIProvider.siliconFlow.defaultBaseURL) == .siliconFlow)
    }
    
    
    // MARK: 5. Star Map Zero-Overlap AABB Guarantee
    
    @Test func starMapLayoutResolvesAllHubClusterAndLeafOverlaps() {
        let clusterIDs = ["c1", "c2", "c3", "c4"]
        let leafIDsByCluster: [String: [String]] = [
            "c1": (1...6).map { "c1-l\($0)" },
            "c2": (1...5).map { "c2-l\($0)" },
            "c3": (1...5).map { "c3-l\($0)" },
            "c4": (1...4).map { "c4-l\($0)" },
        ]
        let counts = leafIDsByCluster.mapValues(\.count)
        let layout = StarMapLayoutEngine.compute(
            clusterIDs: clusterIDs,
            leafCountsByCluster: counts,
            collapsedClusterIDs: [],
            leafIDsByCluster: leafIDsByCluster
        )
        
        var rects: [CGRect] = [
            CGRect(
                x: -StarMapLayoutEngine.hubFootprint.width * 0.5,
                y: -StarMapLayoutEngine.hubFootprint.height * 0.5,
                width: StarMapLayoutEngine.hubFootprint.width,
                height: StarMapLayoutEngine.hubFootprint.height
            ),
        ]
        for c in layout.clusters {
            rects.append(CGRect(
                x: c.worldPoint.x - StarMapLayoutEngine.clusterFootprint.width * 0.5,
                y: c.worldPoint.y - StarMapLayoutEngine.clusterFootprint.height * 0.5,
                width: StarMapLayoutEngine.clusterFootprint.width,
                height: StarMapLayoutEngine.clusterFootprint.height
            ))
        }
        for l in layout.leaves {
            rects.append(CGRect(
                x: l.worldPoint.x - StarMapLayoutEngine.leafFootprint.width * 0.5,
                y: l.worldPoint.y - StarMapLayoutEngine.leafFootprint.height * 0.5,
                width: StarMapLayoutEngine.leafFootprint.width,
                height: StarMapLayoutEngine.leafFootprint.height
            ))
        }
        
        var overlapCount = 0
        for i in 0..<rects.count {
            for j in (i + 1)..<rects.count {
                if rects[i].intersects(rects[j]) {
                    overlapCount += 1
                }
            }
        }
        #expect(overlapCount == 0, "Expected zero overlapping star-map nodes, found \(overlapCount)")
    }
    
    
    // MARK: 6. Real-Time Mood Flow & Official API Cost Pricing
    
    @Test func moodFlowTimeSlotsStrictlyFollowCurrentWallClockHour() {
        let slices = (0..<12).map { i in
            BusynessHourSlice(index: i, label: "\(i * 2):00", intensity: 0.4, rawChars: 100, rawAIRequests: 1)
        }
        
        let morning8 = EmotionSankeyChartView.timeSlotDescriptors(slices: slices, currentHour: 8)
        #expect(morning8.map(\.label) == ["清晨"])
        #expect(!morning8.map(\.label).contains("夜间"))
        #expect(!morning8.map(\.label).contains("午后"))
        
        let morning10 = EmotionSankeyChartView.timeSlotDescriptors(slices: slices, currentHour: 10)
        #expect(morning10.map(\.label) == ["清晨", "上午"])
        #expect(!morning10.map(\.label).contains("夜间"))
        
        let afternoon14 = EmotionSankeyChartView.timeSlotDescriptors(slices: slices, currentHour: 14)
        #expect(afternoon14.map(\.label) == ["晨间", "午后"])
        #expect(!afternoon14.map(\.label).contains("夜间"))
        
        let evening21 = EmotionSankeyChartView.timeSlotDescriptors(slices: slices, currentHour: 21)
        #expect(evening21.map(\.label) == ["晨间", "午后", "夜间"])
    }
    
    
    @Test func officialAPIPricingCatalogComputesUSDAndRMBCosts() {
        let claude = AIModelPricingCatalog.estimateCost(model: "claude-sonnet-4-5", inputTokens: 1_000_000, outputTokens: 1_000_000)
        #expect(abs(claude.usd - 18.0) < 0.01)
        #expect(abs(claude.rmb - 18.0 * AIModelPricingCatalog.usdToRMBRate) < 0.1)
        #expect(claude.formattedRMB.hasPrefix("¥"))
        #expect(claude.formattedUSD.hasPrefix("$"))
        
        let deepseek = AIModelPricingCatalog.estimateCost(model: "deepseek-chat", inputTokens: 1_000_000, outputTokens: 1_000_000)
        #expect(deepseek.usd > 1.0 && deepseek.usd < 2.0)
        
        let local = AIModelPricingCatalog.estimateCost(model: "qwen2.5:7b", inputTokens: 500_000, outputTokens: 500_000)
        #expect(local.usd == 0)
        #expect(local.rmb == 0)
    }
    
    
    // MARK: 7. Prism Pass, Bots Deck & NEWS Reasoning Effort Slider Mount Cleanly
    
    @Test func prismPassBotsAndNewsReasoningSliderMountCleanly() throws {
        let profile = UserProfileManager.shared.activeProfile
        let passView = CotPassCardView(
            theme: CotPassTheme.resolve(index: 0),
            profile: profile,
            avatarImage: nil,
            serialCode: "A1B2-C3V1",
            statusText: "LANDED",
            joinedText: "2026.11.23",
            accessText: "FULL"
        )
        
        let sliderHost = NSHostingController(rootView: VStack {
            passView
            LeiBoxReasoningEffortSlider(effort: .constant(.deep), accent: .blue, isDark: false)
                .frame(width: 280)
        })
        sliderHost.sizingOptions = []
        
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 420),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        defer { window.close() }
        window.contentViewController = sliderHost
        window.setContentSize(NSSize(width: 520, height: 420))
        
        let contentView = try #require(window.contentView)
        contentView.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.15))
        #expect(abs(contentView.bounds.width - 520) <= 2)
        
        // Verify orphan headings like "所属事件" are stripped while valid sections remain
        let rawBlocks: [NewsArticleBlock] = [
            .heading(level: 2, text: "核心结论"),
            .paragraph("模型推理能力持续翻倍。"),
            .heading(level: 2, text: "所属事件"),
        ]
        let sanitized = AIHotNewsService.sanitizedArticleBlocks(rawBlocks)
        #expect(sanitized.count == 2)
        if case .heading(_, let h) = sanitized.first {
            #expect(h == "核心结论")
        } else {
            Issue.record("Expected first valid heading to remain")
        }
    }
    
    
    // MARK: 8. Reasoning Effort Wire Mapping Across All Protocols & Rich Markdown Parser
    
    @Test func reasoningEffortMapsAccuratelyAcrossOpenAIAnthropicAndGeminiWireBodies() throws {
        let msgs: [AIMessage] = [.system("sys"), .user("hello")]
        
        // 1. OpenAI Responses (gpt-5 + high)
        let oaiRespCfg = AIConfiguration(
            endpoint: .openAIResponses,
            baseURL: "https://api.openai.com/v1",
            model: "gpt-5",
            apiKey: "sk-test",
            reasoningEffort: NewsReasoningEffort.deep.apiValue
        )
        let oaiRespBody = AIClient(configuration: oaiRespCfg).debugRequestBody(for: msgs)
        let reasoningDict = try #require(oaiRespBody["reasoning"] as? [String: String])
        #expect(reasoningDict["effort"] == "high")
        
        // 2. OpenAI Chat Completions (deepseek-reasoner + medium)
        let dsCfg = AIConfiguration(
            endpoint: .openAIChatCompletions,
            baseURL: "https://api.deepseek.com/v1",
            model: "deepseek-reasoner",
            apiKey: "sk-test",
            reasoningEffort: NewsReasoningEffort.balanced.apiValue
        )
        let dsBody = AIClient(configuration: dsCfg).debugRequestBody(for: msgs)
        #expect(dsBody["reasoning_effort"] as? String == "medium")
        
        // 3. Anthropic Messages (claude-sonnet-4-5 + high -> thinking enabled, temperature omitted)
        let claudeHigh = AIConfiguration(
            endpoint: .anthropicMessages,
            baseURL: "https://api.anthropic.com/v1",
            model: "claude-sonnet-4-5",
            apiKey: "sk-ant-test",
            temperature: 0.7,
            reasoningEffort: NewsReasoningEffort.deep.apiValue
        )
        let claudeBody = AIClient(configuration: claudeHigh).debugRequestBody(for: msgs)
        let thinking = try #require(claudeBody["thinking"] as? [String: Any])
        #expect(thinking["type"] as? String == "enabled")
        #expect(thinking["budget_tokens"] as? Int == 12288)
        #expect(claudeBody["temperature"] == nil)
        
        // 4. Google Gemini (gemini-2.5-pro + medium -> thinkingBudget 4096)
        let geminiCfg = AIConfiguration(
            endpoint: .googleGemini,
            baseURL: "https://generativelanguage.googleapis.com/v1beta",
            model: "gemini-2.5-pro",
            apiKey: "AIza-test",
            reasoningEffort: NewsReasoningEffort.balanced.apiValue
        )
        let geminiBody = AIClient(configuration: geminiCfg).debugRequestBody(for: msgs)
        let genCfg = try #require(geminiBody["generationConfig"] as? [String: Any])
        let tCfg = try #require(genCfg["thinkingConfig"] as? [String: Any])
        #expect(tCfg["thinkingBudget"] as? Int == 4096)
    }
    
    
    @Test func newsMarkdownParserHandlesHeadingsListsQuotesTablesCodeAndStreamingFences() {
        let md = """
        ## 核心结论
        这是一段带 **加粗** 和 `inline` 的摘要。

        - 要点一
        - 要点二

        1. 第一步
        2. 第二步

        > 一句犀利引用

        | 模型 | 速度 |
        | --- | --- |
        | GPT-5 | 快 |
        | Claude | 稳 |

        ---

        ```swift
        let x = 42
        ```
        """
        
        let blocks = NewsMarkdownParser.parse(md)
        #expect(blocks.count == 8)
        #expect(blocks[0] == .heading(level: 2, text: "核心结论"))
        if case .bulletList(let bullets) = blocks[2] {
            #expect(bullets == ["要点一", "要点二"])
        } else {
            Issue.record("Expected bullet list at index 2")
        }
        if case .orderedList(let ordered) = blocks[3] {
            #expect(ordered.count == 2 && ordered[0].number == "1")
        } else {
            Issue.record("Expected ordered list at index 3")
        }
        if case .blockquote(let q) = blocks[4] {
            #expect(q == "一句犀利引用")
        } else {
            Issue.record("Expected blockquote at index 4")
        }
        if case .table(let headers, let rows) = blocks[5] {
            #expect(headers == ["模型", "速度"])
            #expect(rows.count == 2)
        } else {
            Issue.record("Expected table at index 5")
        }
        #expect(blocks[6] == .divider)
        #expect(blocks[7] == .codeBlock(language: "swift", code: "let x = 42"))
        
        // Mid-stream unclosed code fence must still render safely without crashing
        let partial = "```python\nprint('hi')"
        let partialBlocks = NewsMarkdownParser.parse(partial)
        #expect(partialBlocks == [.codeBlock(language: "python", code: "print('hi')")])
    }
    
    
    // MARK: 10. Document Center Agent Auto-Organize Plan Parsing & Local Fallback
    
    @Test func documentCenterAgentOrganizerParsesJSONAndClassifiesFallback() throws {
        let fencedJSON = """
        ```json
        {
          "assignments": [
            {"id": "doc:1", "group": "项目方案", "suggestedTitle": "Q4 架构设计"},
            {"id": "doc:2", "group": "会议纪要", "suggestedTitle": null},
            {"id": "doc:ignored", "group": "无效", "suggestedTitle": null}
          ]
        }
        ```
        """
        let plan = try #require(
            DocumentCenterAgentOrganizer.parsePlan(from: fencedJSON, validIDs: ["doc:1", "doc:2"])
        )
        #expect(plan.assignments.count == 2)
        #expect(plan.assignments[0].group == "项目方案")
        #expect(plan.assignments[0].suggestedTitle == "Q4 架构设计")
        #expect(plan.assignments[1].group == "会议纪要")
        #expect(plan.assignments[1].suggestedTitle == nil)
        
        #expect(DocumentCenterAgentOrganizer.isGenericUntitled("未命名 2", hasFilePath: false))
        #expect(DocumentCenterAgentOrganizer.isGenericUntitled("Untitled", hasFilePath: false))
        #expect(!DocumentCenterAgentOrganizer.isGenericUntitled("Untitled.md", hasFilePath: true))
        
        let fallback = DocumentCenterAgentOrganizer.buildLocalFallbackPlan(
            items: [
                .init(id: "a", title: "未命名", syntax: "Markdown", currentGroup: "", excerpt: "# 产品需求方案\n核心目标", isUntitled: true),
                .init(id: "b", title: "sync.md", syntax: "Markdown", currentGroup: "", excerpt: "周三会议纪要：确认上线时间", isUntitled: false),
                .init(id: "c", title: "main.swift", syntax: "Swift", currentGroup: "", excerpt: "import Foundation\nfunc run() {}", isUntitled: false),
            ],
            existingGroups: []
        )
        #expect(fallback.assignments.count == 3)
        #expect(fallback.assignments[0].group == "项目方案")
        #expect(fallback.assignments[0].suggestedTitle == "产品需求方案")
        #expect(fallback.assignments[1].group == "会议纪要")
        #expect(fallback.assignments[2].group == "代码开发")
    }
    
    
    // MARK: 11. Dashboard Action Text Sanitizer Strips Replacement Chars & Preserves Full Sentences
    
    @Test func dashboardActionSanitizerStripsBrokenUnicodeAndAvoidsMidSentenceTruncation() {
        let broken = "停用 UNIT_CONCURRENCY \u{FFFD}\u{FFFD}复制 runner，改成每个任务独立进程执行并补齐回归验证"
        let cleaned = AnalyticsManager.sanitizeDashboardActionText(
            broken,
            knownTitles: [],
            maxLength: nil,
            fallback: ""
        )
        #expect(!cleaned.contains("\u{FFFD}"))
        #expect(cleaned.contains("停用 UNIT_CONCURRENCY"))
        #expect(cleaned.hasSuffix("补齐回归验证"))
    }
    
    
    // MARK: 12. Dashboard Complete-Sentence Guard (No Unfinished Sentences in 干了啥 / 要干啥)
    
    @Test func dashboardCompleteSentenceGuardRejectsTruncatedAndUnfinishedPhrases() {
        #expect(AnalyticsManager.isCompleteDashboardSentence("补全灰度发布与异常回滚演练的验证流程清单"))
        #expect(AnalyticsManager.isCompleteDashboardSentence("推进后端接口联调并补齐回归验证。"))
        #expect(AnalyticsManager.isCompleteDashboardSentence("核对是否需要补充跨区域灾备演练？"))
        #expect(AnalyticsManager.isCompleteDashboardSentence("Finalize rollout verification checklist"))
        
        // Unfinished / truncated / dangling-connector phrases must be rejected
        #expect(!AnalyticsManager.isCompleteDashboardSentence("补全灰度发布与异常回滚演练的"))
        #expect(!AnalyticsManager.isCompleteDashboardSentence("梳理登录鉴权和"))
        #expect(!AnalyticsManager.isCompleteDashboardSentence("排查性能瓶颈，以及"))
        #expect(!AnalyticsManager.isCompleteDashboardSentence("今天推进了核心模块重构..."))
        #expect(!AnalyticsManager.isCompleteDashboardSentence("继续完善（灰度回滚"))
        #expect(!AnalyticsManager.isCompleteDashboardSentence("Finish API migration and"))
        
        let doc = StoredDocumentRecord(
            id: "doc-complete",
            title: "规划.md",
            filePath: nil,
            syntax: "Markdown",
            content: """
            # 一段超过十八个字并且不应该被硬截断的超级长标题内容梳理
            - [ ] 排查登录鉴权流程以及
            - [ ] 补全灰度发布与异常回滚演练的验证流程清单
            是否需要补充跨区域灾备演练？
            """,
            highlightsJSON: "[]",
            updatedAt: Date(),
            createdAt: Date()
        )
        let heuristic = AnalyticsManager.buildHeuristicActionPredictions(
            documents: [doc],
            weeklyReports: [],
            reminders: []
        )
        #expect(!heuristic.isEmpty)
        for pred in heuristic {
            #expect(AnalyticsManager.isCompleteDashboardSentence(pred.action))
            #expect(!pred.action.contains("以及"))
            #expect(!pred.action.hasSuffix("…"))
        }
        
        let aiPredJSON = """
        {"predictions":[
          {"action":"推进核心接口联调的","documentTitle":"规划.md"},
          {"action":"完成灰度发布与回滚验证清单。","documentTitle":"规划.md"}
        ]}
        """
        let parsedPreds = AnalyticsManager.parseActionPredictions(from: aiPredJSON, documents: [doc])
        #expect(parsedPreds.count == 1)
        #expect(parsedPreds[0].action == "完成灰度发布与回滚验证清单。")
        
        let aiDoneJSON = """
        {"points":[
          "完成了数据看板性能排查，但是",
          "完成了输入链路去抖和主线程卡顿优化。"
        ]}
        """
        let parsedDone = AnalyticsManager.parseDoneTodayCommentary(from: aiDoneJSON, knownTitles: ["规划.md"])
        #expect(parsedDone.count == 1)
        #expect(parsedDone[0] == "完成了输入链路去抖和主线程卡顿优化。")
    }
    
    
    // MARK: 13. Hero Banner Fluted Prism Coordinated Whitespace & Lower Typography Contrast
    
    @Test func uniformBannerFlutedPrismBalancesAiryWhitespaceAndDeepLowerBand() throws {
        let width = 180
        let height = 48
        let palettes: [(palette: FlutedGlassPalette, maxLowerLuma: Double)] = [
            (.cobaltBlue, 0.42),
            (.pineEmerald, 0.42),
            (.nebulaViolet, 0.42),
            (.amberGold, 0.52),
        ]
        
        for entry in palettes {
            let image = try #require(BlueFlutedGlassRenderer.renderFrame(
                time: 4.5,
                palette: entry.palette,
                width: width,
                height: height,
                ribCount: 66.0,
                uniformBannerMode: true
            ))
            let rep = NSBitmapImageRep(cgImage: image)
            
            var upperAiryPixels = 0
            var totalAiryPixels = 0
            var maxLowerLuma = 0.0
            let upperCutoffY = Int(Double(height) * 0.50)
            let lowerStartY = Int(Double(height) * 0.56)
            
            for y in 0..<height {
                for x in 0..<width {
                    let color = try #require(rep.colorAt(x: x, y: y)?.usingColorSpace(NSColorSpace.sRGB))
                    let r = Double(color.redComponent)
                    let g = Double(color.greenComponent)
                    let b = Double(color.blueComponent)
                    let luma = 0.2126 * r + 0.7152 * g + 0.0722 * b
                    if luma > 0.65 {
                        totalAiryPixels += 1
                        if y < upperCutoffY {
                            upperAiryPixels += 1
                        }
                    }
                    if y >= lowerStartY {
                        maxLowerLuma = max(maxLowerLuma, luma)
                    }
                }
            }
            
            let airyRatio = Double(totalAiryPixels) / Double(width * height)
            #expect(upperAiryPixels > 0, "Expected airy fluted-glass breathing space in upper hero band")
            #expect(airyRatio < 0.42, "Airy light area (\(airyRatio)) should remain balanced")
            #expect(maxLowerLuma < entry.maxLowerLuma, "Lower text band luma \(maxLowerLuma) too bright for crisp white text")
        }
    }
    
    
    // MARK: 13B. Predicted Action Sanitizer Strips All Brackets & Condenses Concisely
    
    @Test func predictedActionSanitizerStripsAllBracketsAndCondenses() {
        let cases: [(raw: String, expectedContains: String)] = [
            ("（2）推进接口联调（需先对齐字段和错误码定义）", "推进接口联调"),
            ("[高优] 补全【灰度发布】回滚单测(明天上线前)", "补全回滚单测"),
            ("1. 趁热把「架构设计」与《需求评审》收个尾，顺便把所有边界单测补齐", "把架构设计与收个尾"),
        ]
        let brackets = CharacterSet(charactersIn: "()（）[]【】「」『』《》〈〉")
        
        for item in cases {
            let cleaned = AnalyticsManager.sanitizePredictedActionText(
                item.raw,
                knownTitles: [],
                maxLength: 20
            )
            #expect(cleaned.count >= 4 && cleaned.count <= 20)
            #expect(cleaned.rangeOfCharacter(from: brackets) == nil)
            #expect(AnalyticsManager.isCompleteDashboardSentence(cleaned))
        }
        
        let exactShort = AnalyticsManager.sanitizePredictedActionText(
            "完成灰度发布与回滚验证清单。",
            knownTitles: [],
            maxLength: 20
        )
        #expect(exactShort == "完成灰度发布与回滚验证清单。")
    }
    
    
    // MARK: 13C. Dashboard & News Center Mount Cleanly Across Light/Dark Modes
    
    @Test func dashboardAndNewsCenterMountCleanlyInLightAndDarkAppearances() throws {
        let intrinsicH = HeatmapGridLayout.intrinsicHeight(forWidth: 560, weekCount: 52)
        #expect(intrinsicH >= 84 && intrinsicH <= 120)
        
        let appearances: [NSAppearance.Name] = [.aqua, .darkAqua]
        for appearanceName in appearances {
            let dashView = AnalyticsDashboardView(isEmbeddedInSettings: false, onDismiss: {})
            let dashHost = NSHostingController(rootView: dashView)
            dashHost.sizingOptions = []
            
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 1220, height: 820),
                styleMask: [.titled, .closable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.isReleasedWhenClosed = false
            window.appearance = NSAppearance(named: appearanceName)
            defer { window.close() }
            window.contentViewController = dashHost
            window.setContentSize(NSSize(width: 1220, height: 820))
            
            let dashContent = try #require(window.contentView)
            dashContent.layoutSubtreeIfNeeded()
            RunLoop.current.run(until: Date().addingTimeInterval(0.12))
            dashContent.layoutSubtreeIfNeeded()
            #expect(abs(dashContent.bounds.width - 1220) <= 2)
            #expect(abs(dashContent.bounds.height - 820) <= 2)
            
            let newsView = DashboardNewsCenterView(
                newsService: AIHotNewsService.shared,
                tokens: DashPalette(appearanceName == .darkAqua ? .dark : .light).tokens,
                initialSelectedID: nil,
                onClose: {}
            )
            let newsHost = NSHostingController(rootView: newsView)
            newsHost.sizingOptions = []
            window.contentViewController = newsHost
            window.setContentSize(NSSize(width: 1220, height: 820))
            
            let newsContent = try #require(window.contentView)
            newsContent.layoutSubtreeIfNeeded()
            RunLoop.current.run(until: Date().addingTimeInterval(0.12))
            newsContent.layoutSubtreeIfNeeded()
            #expect(abs(newsContent.bounds.width - 1220) <= 2)
        }
    }
    
    
    // MARK: 14. Typing Hot-Path Telemetry Buffers Without Per-Keystroke Revision Churn
    
    @Test func typingHotPathBuffersStatsWithoutImmediateRevisionOrDBReload() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: "CotTypingPerf-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        let db = CotLocalDatabase(customURL: tempDir.appending(path: "perf.sqlite3"))
        db.set("v1", forKey: "typing.perf.test")
        #expect(db.string(forKey: "typing.perf.test") == "v1")
        // Idempotent re-write should keep cached value intact
        db.set("v1", forKey: "typing.perf.test")
        #expect(db.string(forKey: "typing.perf.test") == "v1")
        
        let analytics = AnalyticsManager(database: db)
        let baselineRev = analytics.revision
        let baselineTyped = analytics.todayStats.typedChars
        let baselineHits = analytics.todayStats.localHits
        
        for _ in 0..<25 {
            analytics.recordTypedCharacters(1)
        }
        analytics.recordLocalCompletionHit()
        
        // Live computed todayStats reflects buffered deltas immediately, while revision stays untouched until flush
        #expect(analytics.todayStats.typedChars == baselineTyped + 25)
        #expect(analytics.todayStats.localHits == baselineHits + 1)
        #expect(analytics.revision == baselineRev)
        
        analytics.flushPendingStats()
        #expect(analytics.revision == baselineRev + 1)
        #expect(analytics.todayStats.typedChars == baselineTyped + 25)
        #expect(analytics.todayStats.localHits == baselineHits + 1)
    }
    
    
    // MARK: 15. Streamlined OpenCode Go Catalog, 1:1 Bitmap Bot Avatars, & Multi-Level Preference Tree
    
    @Test func openCodeGoCatalogMatchesCuratedModels() {
        #expect(AIProvider.openCodeGo.defaultModel == "deepseek-v4.1-flash")
        let models = AIProvider.openCodeGo.recommendedModels
        #expect(models.contains("deepseek-v4.1-flash"))
        #expect(models.contains("glm-5.3"))
        #expect(models.contains("claude-sonnet-4-5"))
        #expect(models.contains("gpt-5.2"))
        #expect(models.contains("gemini-2.5-pro"))
        #expect(!models.contains("kimi-k2.5"))
        #expect(!models.contains("minimax-m2.5"))
        #expect(AIProvider.openCodeGoModelGroups.count == 4)
        
        let profile = AIProvider.openCodeGo.makeProfile()
        #expect(profile.baseURL == "https://opencode.ai/zen/go/v1")
        #expect(profile.model == "deepseek-v4.1-flash")
    }
    
    
    @Test func botSquareAvatarsRenderAs1To1BitmapImages() throws {
        let characters: [AIGijinkaCharacter] = [.deepseek, .claude, .gpt, .gemini, .glm]
        for character in characters {
            let art = try #require(character.artworks.first)
            let square = try #require(AIGijinkaImageLoader.shared.squareAvatar(for: art, pointSize: 122))
            #expect(abs(square.size.width - 122) <= 0.5)
            #expect(abs(square.size.height - 122) <= 0.5)
            let hasBitmap = square.representations.contains { $0 is NSBitmapImageRep }
            #expect(hasBitmap, "Expected pre-rasterized NSBitmapImageRep for \(art.id)")
        }
    }
    
    
    @Test func preferenceHierarchyBuildsFourLevelsWithoutReadOnlyText() throws {
        let now = Date()
        let memories = [
            UserKYCMemoryRecord(
                id: "m1",
                dimension: .writingStyle,
                factKey: "direct_tone",
                title: "直白干练",
                detail: "优先输出清晰要点",
                confidence: 0.92,
                source: "user_explicit",
                evidenceRef: nil,
                isPinned: true,
                isArchived: false,
                reinforcementCount: 4,
                createdAt: now,
                updatedAt: now
            ),
            UserKYCMemoryRecord(
                id: "m2",
                dimension: .cognition,
                factKey: "systems_thinking",
                title: "结构化拆解",
                detail: "先确定主干层次再细化模块",
                confidence: 0.88,
                source: "persona_bot",
                evidenceRef: "deepseek-v4.1-flash",
                isPinned: false,
                isArchived: false,
                reinforcementCount: 2,
                createdAt: now,
                updatedAt: now
            ),
        ]
        let stocks = [
            MarketInstrument(
                namespace: .hongKong,
                symbol: "HSTECH",
                name: "恒生科技指数",
                eastmoneySecID: "124.HSTECH",
                tencentCode: "hkHSTECH"
            ).toRecord(sortOrder: 0, thesisNote: "持续追踪港股科技权重表现", addedBy: "user")
        ]
        let domains = MemoryStarMapSettingsView.buildPreferenceDomains(
            memories: memories,
            stocks: stocks,
            podcasts: [],
            feeds: [],
            creators: []
        )
        #expect(domains.count == 3)
        #expect(domains.reduce(0) { $0 + $1.totalItemCount } == 3)
        
        for domain in domains {
            #expect(!domain.title.contains("只读"))
            #expect(!domain.title.contains("Read-Only"))
            for cat in domain.categories {
                for item in cat.items {
                    #expect(!item.title.contains("只读"))
                    #expect(item.hasExpandableDetail)
                    #expect(!item.attributes.isEmpty)
                    for attr in item.attributes {
                        #expect(!attr.label.contains("只读"))
                    }
                }
            }
        }
    }
    
    
    @Test func sidebarSettingsWindowMountsOpenCodeGoSquareBotsAndPreferences() throws {
        #expect(SidebarSettingsItem.memory.title == AppLanguage.text("偏好记忆", en: "Preferences"))
        #expect(!SidebarSettingsItem.memory.title.contains("与"))
        #expect(NSImage(systemSymbolName: SidebarSettingsItem.memory.symbolName, accessibilityDescription: nil) != nil)
        
        let controller = SidebarSettingsWindowController()
        let window = try #require(controller.window)
        defer { window.close() }
        
        for tab: SidebarSettingsItem in [.models, .bots, .memory] {
            controller.openItem(tab)
            let contentView = try #require(window.contentView)
            contentView.layoutSubtreeIfNeeded()
            RunLoop.current.run(until: Date().addingTimeInterval(0.08))
            contentView.layoutSubtreeIfNeeded()
            #expect(abs(contentView.bounds.width - 780) <= 1)
            #expect(abs(contentView.bounds.height - 560) <= 1)
        }
    }
    
    
    // MARK: 7. Document & Weekly Star-Map, Relations, Full-Text Search & Highlighting
    
    @Test func starMapFullTextMultiKeywordSearchFindsDeepBodyMatchesAndSnippets() {
        let padding = String(repeating: "这是一段常规的项目推进记录文本，用来填充文章前置内容以超出两千字符限制。", count: 140)
        let deepContent = padding + "\n\n核心进展：本周在 星图拓扑 引擎中接入 棱纹玻璃 渲染管线并完成性能优化。"
        
        let terms = StarMapSearchEngine.parseTerms("  星图拓扑   棱纹玻璃 ")
        #expect(terms == ["星图拓扑", "棱纹玻璃"])
        
        let deepEval = StarMapSearchEngine.evaluate(
            queryTerms: terms,
            title: "技术架构方案",
            category: "架构设计",
            secondaryMeta: "architecture/design.md",
            content: deepContent
        )
        #expect(deepEval.isMatch)
        #expect(deepEval.totalHits >= 2)
        #expect(deepEval.score > 0)
        #expect(deepEval.snippet != nil)
        #expect(deepEval.snippet?.contains("星图拓扑") == true)
        
        let missingTermEval = StarMapSearchEngine.evaluate(
            queryTerms: StarMapSearchEngine.parseTerms("星图拓扑 不存在的锚点词"),
            title: "技术架构方案",
            category: "架构设计",
            secondaryMeta: "architecture/design.md",
            content: deepContent
        )
        #expect(!missingTermEval.isMatch)
        
        let titleEval = StarMapSearchEngine.evaluate(
            queryTerms: terms,
            title: "星图拓扑 与 棱纹玻璃",
            category: "架构设计",
            secondaryMeta: "",
            content: "正文概要"
        )
        #expect(titleEval.isMatch)
        #expect(titleEval.score > deepEval.score)
    }
    
    
    @Test func starMapRelationEngineDiscoversTitleMentionsAndSharedTopicEdges() {
        let docs: [StarMapRelationEngine.CorpusDocument] = [
            .init(
                id: "d1",
                title: "星图架构设计",
                group: "架构",
                folderPath: "/workspace/arch",
                content: "# 总体方案\n本文引用了 文档中心 以及 OpenCode 网关协议，采用 语义拓扑 索引。",
                sortTimestamp: 300
            ),
            .init(
                id: "d2",
                title: "文档中心",
                group: "模块",
                folderPath: "/workspace/ui",
                content: "# 文档中心\n提供 语义拓扑 可视化与 空格预览 能力。",
                sortTimestamp: 200
            ),
            .init(
                id: "d3",
                title: "研发周报",
                group: "周报",
                folderPath: "/workspace/weekly",
                content: "完成了 文档中心 与 OpenCode 网关协议 的对接，增强了 语义拓扑 检索。",
                sortTimestamp: 100
            ),
            .init(
                id: "d4",
                title: "生活随笔",
                group: "日记",
                folderPath: "/personal/life",
                content: "今天天气晴朗，去公园散步。",
                sortTimestamp: 50
            ),
        ]
        
        let edges = StarMapRelationEngine.buildRelations(for: docs, maxEdgesPerNode: 3)
        #expect(!edges.isEmpty)
        
        let linksD1AndD2 = edges.contains {
            ($0.sourceID == "d1" && $0.targetID == "d2") || ($0.sourceID == "d2" && $0.targetID == "d1")
        }
        let linksD3AndD2 = edges.contains {
            ($0.sourceID == "d3" && $0.targetID == "d2") || ($0.sourceID == "d2" && $0.targetID == "d3")
        }
        #expect(linksD1AndD2)
        #expect(linksD3AndD2)
        #expect(!edges.contains { $0.sourceID == "d4" || $0.targetID == "d4" })
        #expect(edges.allSatisfy { !$0.reason.isEmpty && $0.strength > 0 })
        
        var degreeByNode: [String: Int] = [:]
        for edge in edges {
            degreeByNode[edge.sourceID, default: 0] += 1
            degreeByNode[edge.targetID, default: 0] += 1
        }
        #expect(degreeByNode.values.allSatisfy { $0 <= 3 })
    }
    
    
    @Test func documentAndWeeklyCentersBuildStarMapAndHighlightMatches() async {
        let db = CotLocalDatabase.shared
        let id1 = "__test_sm_w1"
        let id2 = "__test_sm_w2"
        let docID = "doc:__test_star_map_async_search"
        defer {
            db.deleteWeeklyReport(id: id1)
            db.deleteWeeklyReport(id: id2)
            db.permanentlyDeleteDocument(id: docID, filePath: nil)
        }
        
        let longLead = String(repeating: "本周开展日常代码评审与稳定性治理。", count: 140)
        db.saveWeeklyReport(
            id: id1,
            periodLabel: "20261116-1122",
            yearMonth: "202611",
            title: "第47周 星图引擎周报",
            content: longLead + "\n\n重点突破：完成 星图关系连线 与 Deepseek 多词检索整合。",
            sourcePath: nil,
            isEnhanced: false,
            createdAt: Date(timeIntervalSinceNow: -3600),
            reloadAfter: true
        )
        db.saveWeeklyReport(
            id: id2,
            periodLabel: "20261109-1115",
            yearMonth: "202611",
            title: "第46周 原型验证",
            content: "前期回顾：为 第47周 星图引擎周报 准备了 星图关系连线 数据结构与测试样本。",
            sourcePath: nil,
            isEnhanced: false,
            createdAt: Date(timeIntervalSinceNow: -7200),
            reloadAfter: true
        )
        
        let reportState = WeeklyReportCenterState()
        reportState.rebuildGroups()
        
        let hasPairRelation = reportState.relations.contains {
            ($0.sourceID == id1 && $0.targetID == id2) || ($0.sourceID == id2 && $0.targetID == id1)
        }
        #expect(hasPairRelation)
        
        reportState.searchText = "星图关系连线 Deepseek"
        #expect(reportState.searchHits.contains(where: { $0.id == id1 }))
        #expect((reportState.searchMatchesByID[id1]?.totalHits ?? 0) >= 2)
        // 1-hop neighbor should remain visible in displayedRows to preserve relation arcs
        #expect(reportState.displayedRows.contains(where: { $0.id == id2 }))
        
        let tokens = DashPalette.editorialTokens(isDark: false)
        let reportClusters = reportState.buildStarMapClusters(tokens: tokens)
        let leaf1 = reportClusters.flatMap(\.leaves).first(where: { $0.id == id1 })
        #expect(leaf1?.isHighlighted == true)
        #expect(leaf1?.statusBadge?.contains("命中") == true)
        
        let reportHost = NSHostingView(rootView: WeeklyReportCenterView(state: reportState))
        reportHost.frame = NSRect(x: 0, y: 0, width: 1120, height: 720)
        reportHost.layoutSubtreeIfNeeded()
        #expect(reportHost.bounds.width == 1120)

        db.saveWeeklyReport(
            id: id1,
            periodLabel: "20261116-1122",
            yearMonth: "202611",
            title: "第47周 星图引擎周报",
            content: "替换后的内容包含独立检索词 cucumber。"
        )
        reportState.rebuildGroups()
        #expect(!reportState.searchHits.contains(where: { $0.id == id1 }))
        #expect(await reportState.applySearch("cucumber"))
        #expect(reportState.searchHits.contains(where: { $0.id == id1 }))
        #expect(reportState.displayedRows.first(where: { $0.id == id1 })?.report.content.contains("cucumber") == true)
        
        let docState = DocumentCenterState()
        db.saveDocument(id: docID, title: "星图搜索", filePath: nil, syntax: "Markdown", content: "uniqueDocumentCenterTerm")
        docState.refresh()
        let docClusters = docState.buildStarMapClusters(tokens: tokens)
        #expect(docClusters.allSatisfy { !$0.title.isEmpty })
        #expect(await docState.applySearch("uniqueDocumentCenterTerm"))
        let expectedDocumentID = DocumentCenterState.canonicalKey(filePath: nil, rawID: docID)
        #expect(docState.searchHits.contains(where: { $0.id == expectedDocumentID }))
        let cancelledSearch = Task { await docState.applySearch("discardThisQuery") }
        cancelledSearch.cancel()
        #expect(await cancelledSearch.value == false)
        #expect(docState.searchText == "uniqueDocumentCenterTerm")
        let docHost = NSHostingView(rootView: DocumentCenterView(state: docState))
        docHost.frame = NSRect(x: 0, y: 0, width: 1120, height: 720)
        docHost.layoutSubtreeIfNeeded()
        #expect(docHost.bounds.width == 1120)
    }
    
    
    // MARK: 8. Unified Beautiful UI + LeiBox Orbs, Simplified Bot Config & OpenCode Go Models
    
    @Test func agentUIComponentLibraryRendersOrbsAndUnifiedChatSurface() throws {
        let light = BeautifulUITokens.resolve(isDark: false)
        let dark = BeautifulUITokens.resolve(isDark: true)
        #expect(light != dark)
        
        for orbState in AgentOrbState.allCases {
            let orbHost = NSHostingView(rootView: DissolveThinkingOrbView(state: orbState, size: 52, paused: true))
            orbHost.frame = NSRect(x: 0, y: 0, width: 52, height: 52)
            orbHost.layoutSubtreeIfNeeded()
            #expect(orbHost.bounds.size == NSSize(width: 52, height: 52))
        }
        
        for particleMode in ThinkingOrbsMode.allCases {
            let particleHost = NSHostingView(rootView: ThinkingOrbsParticleView(mode: particleMode, size: 28, paused: true))
            particleHost.frame = NSRect(x: 0, y: 0, width: 28, height: 28)
            particleHost.layoutSubtreeIfNeeded()
            #expect(particleHost.bounds.size == NSSize(width: 28, height: 28))
        }
        
        let loaderTrace = VStack(spacing: 12) {
            BeautifulUIPixelLoader(label: "Working", variant: .drive, showTimer: true)
            BeautifulUIThinkingTrace(
                isWorking: true,
                activeLabel: "Thinking",
                doneLabel: "Done",
                mode: .working,
                steps: [
                    BeautifulUIThinkingStep(primary: "Inspecting workspace", secondary: "2 files", isCompleted: true),
                    BeautifulUIThinkingStep(primary: "Streaming response", isCompleted: false),
                ]
            )
        }
        let traceHost = NSHostingView(rootView: loaderTrace)
        traceHost.frame = NSRect(x: 0, y: 0, width: 420, height: 220)
        traceHost.layoutSubtreeIfNeeded()
        #expect(traceHost.bounds.width == 420)
        
        let models = [AgentModelOption(modelID: "deepseek-v4.1-flash"), AgentModelOption(modelID: "glm-5.3")]
        let emptySurface = AgentChatTranscriptSurface(
            messages: [],
            isStreaming: false,
            streamingDraft: nil,
            errorMessage: nil,
            placeholder: "Hello",
            availableModels: models,
            selectedModelTitle: "deepseek-v4.1-flash",
            orbColor: light.ink,
            tokens: light,
            onSend: { _ in }
        )
        let emptyHost = NSHostingView(rootView: emptySurface)
        emptyHost.frame = NSRect(x: 0, y: 0, width: 480, height: 420)
        emptyHost.layoutSubtreeIfNeeded()
        #expect(emptyHost.bounds.height == 420)
        
        let populatedSurface = AgentChatTranscriptSurface(
            messages: [
                AgentChatMessageItem(id: "u1", isUser: true, text: "帮我总结这段修改"),
                AgentChatMessageItem(
                    id: "a1",
                    isUser: false,
                    text: "## 总结\n已完成 **Beautiful UI** 与粒子系统接入。",
                    toolChips: [AgentToolChipItem(id: "t1", label: "读取工作区")]
                ),
            ],
            isStreaming: false,
            streamingDraft: nil,
            errorMessage: nil,
            placeholder: "@总管",
            availableModels: models,
            selectedModelTitle: "glm-5.3",
            orbColor: dark.ink,
            tokens: dark,
            onSend: { _ in }
        )
        let popHost = NSHostingView(rootView: populatedSurface)
        popHost.frame = NSRect(x: 0, y: 0, width: 480, height: 420)
        popHost.layoutSubtreeIfNeeded()
        #expect(popHost.bounds.width == 480)
    }
    
    
    @Test func botSimplifiedIdentityAndOpenCodeGoModelSelectionPersistCleanly() throws {
        #expect(AIBotID.allCases.count == 12)
        #expect(AIBotID.allCases.first == .butler)
        #expect(AIBotID.allCases.contains(.readingCompanion))
        
        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: "cot-bot-identity-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        let db = CotLocalDatabase(customURL: tempDir.appending(path: "bots.sqlite3"))
        let store = AIBotStore(database: db)
        
        var cfg = store.config(for: .readingCompanion)
        cfg.customName = "夜读助手"
        cfg.customNickname = "夜读"
        cfg.modelOverride = "glm-5.3"
        store.updateConfig(cfg, for: .readingCompanion)
        
        let reloadedStore = AIBotStore(database: db)
        #expect(reloadedStore.resolvedName(for: .readingCompanion) == "夜读助手")
        #expect(reloadedStore.resolvedNickname(for: .readingCompanion) == "夜读")
        #expect(reloadedStore.config(for: .readingCompanion).modelOverride == "glm-5.3")
        
        let testImage = NSImage(size: NSSize(width: 64, height: 64))
        testImage.lockFocus()
        NSColor.systemBlue.setFill()
        NSRect(x: 0, y: 0, width: 64, height: 64).fill()
        testImage.unlockFocus()
        let tiffData = try #require(testImage.tiffRepresentation)
        let rep = try #require(NSBitmapImageRep(data: tiffData))
        let pngData = try #require(rep.representation(using: .png, properties: [:]))
        
        reloadedStore.setCustomAvatarData(pngData, for: .readingCompanion)
        #expect(reloadedStore.customAvatarImage(for: .readingCompanion) != nil)
        #expect(reloadedStore.resolvedAvatarImage(for: .readingCompanion, pointSize: 80) != nil)
        
        let catalog = reloadedStore.openCodeGoSelectableModels()
        #expect(catalog.models.contains("deepseek-v4.1-flash"))
        #expect(catalog.models.contains("glm-5.3"))
        #expect(catalog.models.contains("claude-sonnet-4-5"))
        #expect(catalog.models.contains("gpt-5.2"))
        #expect(catalog.models.contains("gemini-2.5-pro"))
        
        reloadedStore.resetBotToDefaults(.readingCompanion)
        #expect(reloadedStore.resolvedName(for: .readingCompanion) == AIBotID.readingCompanion.displayName)
        #expect(reloadedStore.customAvatarImage(for: .readingCompanion) == nil)
    }
    
    
    @Test func butlerAndNewsCompanionMountUnifiedChatWithoutStarterClutter() throws {
        let butlerHost = NSHostingView(rootView: ButlerCommandHubView(hostWindow: nil, onDismiss: {}))
        butlerHost.frame = NSRect(x: 0, y: 0, width: 492, height: 560)
        butlerHost.layoutSubtreeIfNeeded()
        #expect(butlerHost.bounds.width == 492)
        #expect(butlerHost.bounds.height == 560)
        
        let settingsState = SidebarSettingsState()
        settingsState.pendingBotID = .readingCompanion
        let botsHost = NSHostingView(rootView: AIBotsSettingsView(settingsState: settingsState))
        botsHost.frame = NSRect(x: 0, y: 0, width: 527, height: 480)
        botsHost.layoutSubtreeIfNeeded()
        #expect(botsHost.bounds.width == 527)
        
        let gatewayHost = NSHostingView(rootView: AIModelsSettingsView())
        gatewayHost.frame = NSRect(x: 0, y: 0, width: 527, height: 480)
        gatewayHost.layoutSubtreeIfNeeded()
        #expect(gatewayHost.bounds.width == 527)
        
        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: "cot-news-unified-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let db = CotLocalDatabase(customURL: tempDir.appending(path: "news.sqlite3"))
        let newsService = AIHotNewsService(database: db, cacheRootDirectory: tempDir.appending(path: "cache"))
        let newsView = DashboardNewsCenterView(
            newsService: newsService,
            tokens: DashPalette.editorialTokens(isDark: false),
            initialSelectedID: nil,
            onClose: {}
        )
        let newsHost = NSHostingView(rootView: newsView)
        newsHost.frame = NSRect(x: 0, y: 0, width: 1200, height: 760)
        newsHost.layoutSubtreeIfNeeded()
        #expect(newsHost.bounds.width == 1200)
    }
    
    
    // MARK: 7. Backend Database, Granular Memory Store, Pi Kernel & Render Cache Optimizations
    
    @Test func databaseTransactionsFetchRecordAndBoundedUsageEvents() throws {
        struct ForcedRollback: Error {}
        
        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: "cot-r33-db-opt-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        let db = CotLocalDatabase(customURL: tempDir.appending(path: "opt.sqlite3"))
        let docPath = tempDir.appending(path: "note.md").path(percentEncoded: false)
        
        db.withTransaction {
            db.withTransaction {
                db.saveDocument(
                    id: "doc:opt-1",
                    title: "Optimization Note",
                    filePath: docPath,
                    syntax: "Markdown",
                    content: "SQLite WAL and single-row lookup"
                )
            }
        }
        
        let byID = try #require(db.fetchDocumentRecord(id: "doc:opt-1", filePath: nil))
        #expect(byID.title == "Optimization Note")
        let byPath = try #require(db.fetchDocumentRecord(id: nil, filePath: docPath))
        #expect(byPath.id == "doc:opt-1")
        
        do {
            try db.withTransaction {
                db.saveDocument(
                    id: "doc:rolled-back",
                    title: "Should Rollback",
                    filePath: nil,
                    syntax: "Markdown",
                    content: "transient"
                )
                throw ForcedRollback()
            }
            Issue.record("Expected nested transaction error")
        } catch is ForcedRollback {
        }
        #expect(db.fetchDocumentRecord(id: "doc:rolled-back", filePath: nil) == nil)
        
        let now = Date()
        for idx in 0..<5 {
            db.insertAIUsageEvent(AIUsageEvent(
                dateKey: "2026-11-20",
                timestamp: now.addingTimeInterval(Double(idx)),
                feature: "chat",
                model: "glm-5.3",
                provider: "OpenCode Go",
                inputTokens: 100 + idx,
                outputTokens: 50 + idx,
                latencyMs: 120,
                success: true
            ))
        }
        db.insertAIUsageEvent(AIUsageEvent(
            dateKey: "2026-10-01",
            timestamp: now.addingTimeInterval(-3_000_000),
            feature: "summarize",
            model: "deepseek-v4.1-flash",
            provider: "OpenCode Go",
            inputTokens: 40,
            outputTokens: 20,
            latencyMs: 80,
            success: true
        ))
        
        #expect(db.fetchAIUsageEvents(sinceDateKey: "2026-11-01", limit: 3).count == 3)
        let octEvents = db.fetchAIUsageEvents(forDateKey: "2026-10-01")
        #expect(octEvents.count == 1)
        #expect(octEvents.first?.model == "deepseek-v4.1-flash")
    }
    
    
    @Test func memoryStoreGranularReloadsAndPiKernelWriteIfChangedIdempotency() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: "cot-r33-mem-pi-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        let db = CotLocalDatabase(customURL: tempDir.appending(path: "granular.sqlite3"))
        let store = CotMemoryStore(database: db)
        let now = Date()
        
        db.upsertKYCMemory(
            id: "kyc:opt",
            dimension: .writingStyle,
            factKey: "concise_output",
            title: "偏好简洁输出",
            detail: "直接给结论",
            confidence: 0.9,
            source: "test",
            evidenceRef: nil,
            isPinned: true
        )
        store.reloadMemoriesAndJournal()
        #expect(store.memories.contains(where: { $0.id == "kyc:opt" }))
        
        let stock = MarketInstrument(
            namespace: .hongKong,
            symbol: "00700",
            name: "腾讯控股",
            eastmoneySecID: "116.00700",
            tencentCode: "hk00700"
        ).toRecord(sortOrder: 99, thesisNote: "test", addedBy: "user")
        db.upsertWatchlistStock(stock)
        store.reloadStocks()
        #expect(store.stocks.contains(where: { $0.symbol == "00700" }))
        
        let podcast = StoredPodcastRecord(
            id: "pod:opt-1",
            itemKind: "episode",
            platform: "apple",
            title: "Performance Engineering",
            showName: "Systems Pod",
            sourceURL: "https://example.com/pod",
            audioURL: "https://example.com/pod.mp3",
            artworkURL: "",
            durationSec: 1200,
            playbackPositionSec: 42,
            isSaved: true,
            topicTag: "engineering",
            notes: "",
            lastPlayedAt: now,
            createdAt: now,
            updatedAt: now
        )
        db.upsertStoredPodcast(podcast)
        store.reloadPodcasts()
        #expect(store.podcasts.contains(where: { $0.id == "pod:opt-1" }))
        
        // PiKernel syncWorkspace writeIfChanged idempotency
        let piDir = tempDir.appending(path: "PiKernel", directoryHint: .isDirectory)
        let kernel = PiKernelManager(customAgentDirectoryURL: piDir, database: db)
        let botStore = AIBotStore(database: db)
        let gw = AIProvider.openCodeGo.makeProfile()
        
        let summary1 = try kernel.syncWorkspace(endpoints: [gw], botStore: botStore, keyLookup: { _ in "sk-opt" })
        let modelsURL = piDir.appending(path: "models.json")
        let sentinelDate = Date(timeIntervalSince1970: 1_700_000_000)
        try FileManager.default.setAttributes([.modificationDate: sentinelDate], ofItemAtPath: modelsURL.path)
        
        let summary2 = try kernel.syncWorkspace(endpoints: [gw], botStore: botStore, keyLookup: { _ in "sk-opt" })
        #expect(summary2.modelCount == summary1.modelCount)
        let attrsAfterUnchangedSync = try FileManager.default.attributesOfItem(atPath: modelsURL.path)
        #expect(attrsAfterUnchangedSync[.modificationDate] as? Date == sentinelDate)
        
        // Changing a model override invalidates cache & updates models.json
        var modifiedCfg = botStore.config(for: .summarize)
        modifiedCfg.modelOverride = "custom-fast-model"
        botStore.updateConfig(modifiedCfg, for: .summarize)
        _ = try kernel.syncWorkspace(endpoints: [gw], botStore: botStore, keyLookup: { _ in "sk-opt" })
        let attrsAfterChange = try FileManager.default.attributesOfItem(atPath: modelsURL.path)
        #expect(attrsAfterChange[.modificationDate] as? Date != sentinelDate)
    }
    
    
    @Test func markdownRenderCacheAndNewsBlockSanitization() {
        let md = """
        # Headline
        
        Paragraph with **bold** and `code`.
        """
        let first = MarkdownRenderCache.blocks(for: md)
        let second = MarkdownRenderCache.blocks(for: md)
        #expect(first == second)
        #expect(first.count == 2)
        #expect(MarkdownRenderCache.attributedInline(for: "**bold** text") != nil)
        
        let rawNewsBlocks: [NewsArticleBlock] = [
            .heading(level: 2, text: "Main Section"),
            .paragraph("Body content that stays."),
            .heading(level: 3, text: "延伸阅读"),
            .heading(level: 3, text: "Empty Trailing Section"),
        ]
        let cleaned = AIHotNewsService.sanitizedArticleBlocks(rawNewsBlocks)
        #expect(cleaned.count == 2)
    }
    
    
    @Test func starMapRelationEngineKeyTermCacheAndDeterminism() {
        let titleA = "SQLite WAL Architecture"
        let contentA = "Using WAL journaling with busy_timeout and partial indexes speeds up reads."
        let termsA1 = StarMapRelationEngine.extractKeyTerms(title: titleA, content: contentA)
        let termsA2 = StarMapRelationEngine.extractKeyTerms(title: titleA, content: contentA)
        #expect(termsA1 == termsA2)
        #expect(termsA1.contains("SQLite"))
        
        let editedTerms = StarMapRelationEngine.extractKeyTerms(
            title: titleA,
            content: "Completely different topic about CoreAnimation Metal shader pausing."
        )
        #expect(editedTerms != termsA1)
        
        let docs = [
            StarMapRelationEngine.CorpusDocument(
                id: "d1",
                title: "Doc One",
                group: "Perf",
                folderPath: nil,
                content: "Metal framebuffer pipeline caching reduces GPU power.",
                sortTimestamp: 100
            ),
            StarMapRelationEngine.CorpusDocument(
                id: "d2",
                title: "Doc Two",
                group: "Perf",
                folderPath: nil,
                content: "Doc One notes show Metal framebuffer pipeline caching gains.",
                sortTimestamp: 200
            ),
        ]
        let edges1 = StarMapRelationEngine.buildRelations(for: docs)
        let edges2 = StarMapRelationEngine.buildRelations(for: docs)
        #expect(edges1 == edges2)
        #expect(!edges1.isEmpty)
    }
    
    
    // MARK: 15. Multi-Subscription Gateway, 3:4 Portrait Bots, Structured Star-Map & Stable NEWS Waterfall
    
    @Test func collapsibleMultiSubscriptionGatewayAndPortraitBotCardsRenderCleanly() throws {
        #expect(AIProvider.starterSubscriptions == [.openCodeGo, .deepSeek])
        #expect(AIProvider.openCodeGo.subscriptionTitle == "OpenCode Go")
        #expect(AIProvider.deepSeek.subscriptionTitle == "DeepSeek 官方 API")
        #expect(AIProvider.openAI.subscriptionTitle == "OpenAI 官方 API")
        #expect(AIProvider.anthropic.subscriptionTitle == "Anthropic 官方 API")
        
        // Verify vertical 9:16 character illustration crops isotropically into ~3:4 portrait card without squashing
        let tallSource = NSImage(size: NSSize(width: 90, height: 160))
        tallSource.lockFocus()
        NSColor.systemRed.setFill()
        NSRect(x: 0, y: 120, width: 90, height: 40).fill() // Top head band in AppKit bottom-left coords
        NSColor.systemBlue.setFill()
        NSRect(x: 0, y: 0, width: 90, height: 120).fill()
        tallSource.unlockFocus()
        
        let portrait = try #require(
            AIGijinkaImageLoader.renderPortraitBitmap(
                from: tallSource,
                cropAnchor: .top,
                pointWidth: 122,
                pointHeight: 166
            )
        )
        #expect(portrait.size == NSSize(width: 122, height: 166))
        #expect(portrait.representations.first is NSBitmapImageRep)
        
        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: "cot-bot-portrait-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        let savedProfiles = AIEndpointStore.profiles
        let savedActiveID = AIEndpointStore.activeID
        if savedProfiles.isEmpty {
            let seeded = AIProvider.openCodeGo.makeProfile(customName: AIProvider.openCodeGo.subscriptionTitle)
            AIEndpointStore.profiles = [seeded]
            AIEndpointStore.activeID = seeded.id
        }
        defer {
            AIEndpointStore.profiles = savedProfiles
            AIEndpointStore.activeID = savedActiveID
        }
        
        let db = CotLocalDatabase(customURL: tempDir.appending(path: "bots-portrait.sqlite3"))
        let store = AIBotStore(database: db)
        let cardImg = store.resolvedPortraitImage(for: .butler, pointWidth: 126, pointHeight: 170)
        #expect(cardImg != nil)
        if let cardImg {
            #expect(cardImg.size.height > cardImg.size.width)
        }
        #expect(!store.selectableGatewayGroups().isEmpty)
        
        for mode in BotCollectionLayoutMode.allCases {
            let botsHost = NSHostingView(
                rootView: AIBotsSettingsView(settingsState: SidebarSettingsState(), initialLayoutMode: mode)
            )
            botsHost.frame = NSRect(x: 0, y: 0, width: 527, height: 500)
            botsHost.layoutSubtreeIfNeeded()
            #expect(botsHost.bounds.width == 527)
        }
    }
    
    
    @Test func structuredBidirectionalStarMapHasZeroOverlapsAndNewsWaterfallStaysStable() throws {
        let clusterIDs = ["c0", "c1", "c2", "c3"]
        var counts: [String: Int] = [:]
        var leafIDsByCluster: [String: [String]] = [:]
        for cID in clusterIDs {
            counts[cID] = 12
            leafIDsByCluster[cID] = (0..<12).map { "\(cID)-l\($0)" }
        }
        
        let layout = StarMapLayoutEngine.compute(
            clusterIDs: clusterIDs,
            leafCountsByCluster: counts,
            collapsedClusterIDs: [],
            leafIDsByCluster: leafIDsByCluster
        )
        #expect(layout.clusters.count == 4)
        #expect(layout.leaves.count == 48)
        // Bidirectional balance: clusters split cleanly across right (+x) and left (-x)
        let c0Point = try #require(layout.clusters.first(where: { $0.id == "c0" })?.worldPoint)
        let c1Point = try #require(layout.clusters.first(where: { $0.id == "c1" })?.worldPoint)
        #expect(c0Point.x > 0)
        #expect(c1Point.x < 0)
        
        // Verify zero pairwise leaf AABB overlap (214 x 50 cards)
        let positions = layout.leaves.map(\.worldPoint)
        for i in 0..<positions.count {
            for j in (i + 1)..<positions.count {
                let dx = abs(positions[i].x - positions[j].x)
                let dy = abs(positions[i].y - positions[j].y)
                let overlaps = (dx < 214) && (dy < 50)
                #expect(!overlaps)
            }
        }
        
        // Verify NEWS waterfall cover heights are 100% deterministic & cache holds all 60 feed items without eviction
        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: "cot-news-stable-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        let db = CotLocalDatabase(customURL: tempDir.appending(path: "news-stable.sqlite3"))
        let service = AIHotNewsService(database: db, cacheRootDirectory: tempDir.appending(path: "cache"))
        let sampleItems: [AIHotNewsItem] = (0..<60).map { idx in
            AIHotNewsItem(
                id: "news-\(idx)",
                title: "High Signal AI Systems Update Number \(idx)",
                source: "HN",
                urlString: "https://example.com/\(idx)",
                publishedAt: Date(),
                heatScore: 100 + idx,
                tag: nil,
                coverURLString: nil,
                category: .ai,
                summary: "Detailed architectural summary for item \(idx)."
            )
        }
        
        let dummyCover = NSImage(size: NSSize(width: 320, height: 180))
        for item in sampleItems {
            let hBefore = DashboardNewsCenterView.waterfallCoverHeight(for: item, cardWidth: 240)
            service.storeCoverImage(dummyCover, for: item.id)
            let hAfter = DashboardNewsCenterView.waterfallCoverHeight(for: item, cardWidth: 240)
            #expect(hBefore == hAfter)
        }
        // All 60 active feed covers stay resident without thrashing eviction
        #expect(service.coverImages.count == 60)
    }
    
    
    @Test func gatewayAllowsDeletingAllProfilesWithoutResurrectionAndNewsPagesCleanly() throws {
        let savedProfiles = AIEndpointStore.profiles
        let savedActiveID = AIEndpointStore.activeID
        defer {
            AIEndpointStore.profiles = savedProfiles
            AIEndpointStore.activeID = savedActiveID
        }
        
        let p1 = AIProvider.openCodeGo.makeProfile(customName: AIProvider.openCodeGo.subscriptionTitle)
        let p2 = AIProvider.deepSeek.makeProfile(customName: AIProvider.deepSeek.subscriptionTitle)
        AIEndpointStore.profiles = [p1, p2]
        AIEndpointStore.activeID = p1.id
        
        // Deleting all configured subscriptions leaves an empty list without legacy resurrection
        AIEndpointStore.delete(id: p1.id)
        #expect(AIEndpointStore.profiles.count == 1)
        #expect(AIEndpointStore.activeID == p2.id)
        
        AIEndpointStore.delete(id: p2.id)
        #expect(AIEndpointStore.profiles.isEmpty)
        #expect(AIEndpointStore.activeID == nil)
        AIEndpointStore.migrateLegacyConfigurationIfNeeded()
        #expect(AIEndpointStore.profiles.isEmpty)
        
        // Responsive 2-row fullscreen NEWS pagination column counts
        #expect(DashboardNewsCenterView.columnsForWidth(520) == 2)
        #expect(DashboardNewsCenterView.columnsForWidth(720) == 3)
        #expect(DashboardNewsCenterView.columnsForWidth(1020) == 4)
        #expect(DashboardNewsCenterView.columnsForWidth(1260) == 5)
    }
    
    
    // MARK: 14. Timeline Spine + Default Collapsed Star-Map + 03:00 Scheduled AI Organizer
    
    @Test func timelineStarMapDefaultsToCollapsedAndMaintainsChronologicalOrder() {
        let db = CotLocalDatabase.shared
        let docID1 = "doc:__timeline_test_1"
        let docID2 = "doc:__timeline_test_2"
        let repID1 = "__timeline_rep_1"
        let repID2 = "__timeline_rep_2"
        defer {
            db.permanentlyDeleteDocument(id: docID1, filePath: nil)
            db.permanentlyDeleteDocument(id: docID2, filePath: nil)
            db.deleteWeeklyReport(id: repID1)
            db.deleteWeeklyReport(id: repID2)
        }
        
        db.saveDocument(
            id: docID1,
            title: "核心网关限流架构设计",
            filePath: nil,
            syntax: "Markdown",
            content: "# 核心网关限流架构设计\n引入令牌桶算法保护核心接口。",
            groupName: "项目方案"
        )
        Thread.sleep(forTimeInterval: 0.02)
        db.saveDocument(
            id: docID2,
            title: "客户端冷启动排查记录",
            filePath: nil,
            syntax: "Markdown",
            content: "# 客户端冷启动排查记录\n定位主线程同步 I/O 耗时。",
            groupName: "技术笔记"
        )
        
        let tokens = DashPalette.editorialTokens(isDark: false)
        let docState = DocumentCenterState()
        docState.refresh()
        
        let initialDocClusters = docState.buildStarMapClusters(tokens: tokens)
        #expect(initialDocClusters.count >= 2)
        // All clusters must start collapsed by default for maximum visual clarity
        #expect(initialDocClusters.allSatisfy { $0.isCollapsed })
        // Every cluster carries a non-empty timeline milestone label, sorted newest-first
        #expect(initialDocClusters.allSatisfy { ($0.timelineLabel?.isEmpty == false) })
        for idx in 1..<initialDocClusters.count {
            #expect(initialDocClusters[idx - 1].sortTimestamp >= initialDocClusters[idx].sortTimestamp)
        }
        
        // Active search query auto-expands matching clusters, and clearing folds them back
        docState.searchText = "令牌桶算法"
        let searchedClusters = docState.buildStarMapClusters(tokens: tokens)
        #expect(searchedClusters.contains(where: { !$0.isCollapsed }))
        docState.searchText = ""
        let refoldedClusters = docState.buildStarMapClusters(tokens: tokens)
        #expect(refoldedClusters.allSatisfy { $0.isCollapsed })
        
        // 1-click Expand All / Collapse All
        docState.expandAllClusters(refoldedClusters.map(\.id))
        #expect(docState.buildStarMapClusters(tokens: tokens).allSatisfy { !$0.isCollapsed })
        docState.collapseAllClusters(refoldedClusters.map(\.id))
        #expect(docState.buildStarMapClusters(tokens: tokens).allSatisfy { $0.isCollapsed })
        
        // Weekly Report Center also defaults to collapsed with monthly timeline badges
        db.saveWeeklyReport(
            id: repID1,
            periodLabel: "20261019-1025",
            yearMonth: "202610",
            title: "10月第三周研发周报",
            content: "完成时间轴布局改造与性能压测。",
            sourcePath: nil,
            isEnhanced: false,
            createdAt: Date(timeIntervalSinceNow: -86_400 * 30),
            reloadAfter: true
        )
        db.saveWeeklyReport(
            id: repID2,
            periodLabel: "20261116-1122",
            yearMonth: "202611",
            title: "11月第三周研发周报",
            content: "上线默认折叠星图与凌晨自动整理。",
            sourcePath: nil,
            isEnhanced: false,
            createdAt: Date(),
            reloadAfter: true
        )
        
        let weeklyState = WeeklyReportCenterState()
        weeklyState.rebuildGroups()
        let weeklyClusters = weeklyState.buildStarMapClusters(tokens: tokens)
        #expect(weeklyClusters.count >= 2)
        #expect(weeklyClusters.allSatisfy { $0.isCollapsed })
        #expect(weeklyClusters.first?.timelineLabel == "2026 · 11月")
        
        // Verify Timeline Spine layout maintains strict top-to-bottom Y order and zero overlaps even when expanded
        let timelineLayout = StarMapLayoutEngine.compute(
            clusterIDs: ["c1", "c2", "c3", "c4"],
            leafCountsByCluster: ["c1": 3, "c2": 4, "c3": 2, "c4": 3],
            collapsedClusterIDs: [],
            leafIDsByCluster: [
                "c1": ["l1", "l2", "l3"],
                "c2": ["l4", "l5", "l6", "l7"],
                "c3": ["l8", "l9"],
                "c4": ["l10", "l11", "l12"],
            ],
            usesTimelineSpine: true
        )
        #expect(timelineLayout.usesTimelineSpine == true)
        #expect(timelineLayout.hubPoint.y < timelineLayout.clusters[0].worldPoint.y)
        for idx in 1..<timelineLayout.clusters.count {
            #expect(timelineLayout.clusters[idx - 1].worldPoint.y < timelineLayout.clusters[idx].worldPoint.y)
        }
        
        var rects: [CGRect] = [
            CGRect(
                x: timelineLayout.hubPoint.x - StarMapLayoutEngine.hubFootprint.width * 0.5,
                y: timelineLayout.hubPoint.y - StarMapLayoutEngine.hubFootprint.height * 0.5,
                width: StarMapLayoutEngine.hubFootprint.width,
                height: StarMapLayoutEngine.hubFootprint.height
            ),
        ]
        for c in timelineLayout.clusters {
            rects.append(CGRect(
                x: -StarMapLayoutEngine.milestoneFootprint.width * 0.5,
                y: c.worldPoint.y - StarMapLayoutEngine.milestoneFootprint.height * 0.5,
                width: StarMapLayoutEngine.milestoneFootprint.width,
                height: StarMapLayoutEngine.milestoneFootprint.height
            ))
            rects.append(CGRect(
                x: c.worldPoint.x - StarMapLayoutEngine.clusterFootprint.width * 0.5,
                y: c.worldPoint.y - StarMapLayoutEngine.clusterFootprint.height * 0.5,
                width: StarMapLayoutEngine.clusterFootprint.width,
                height: StarMapLayoutEngine.clusterFootprint.height
            ))
        }
        for l in timelineLayout.leaves {
            rects.append(CGRect(
                x: l.worldPoint.x - StarMapLayoutEngine.leafFootprint.width * 0.5,
                y: l.worldPoint.y - StarMapLayoutEngine.leafFootprint.height * 0.5,
                width: StarMapLayoutEngine.leafFootprint.width,
                height: StarMapLayoutEngine.leafFootprint.height
            ))
        }
        var overlaps = 0
        for i in 0..<rects.count {
            for j in (i + 1)..<rects.count where rects[i].intersects(rects[j]) {
                overlaps += 1
            }
        }
        #expect(overlaps == 0)
    }
    
    
    @Test func scheduledAIDocumentOrganizerTriggersAt3AMAndRunsFourStagePipeline() async throws {
        let tempURL = FileManager.default.temporaryDirectory
            .appending(path: "cot_sched_organize_test_\(UUID().uuidString).sqlite3")
        defer { try? FileManager.default.removeItem(at: tempURL) }
        
        let tempDB = CotLocalDatabase(customURL: tempURL)
        let tempAnalytics = AnalyticsManager(database: tempDB)
        let organizer = ScheduledAIDocumentOrganizer(database: tempDB, analytics: tempAnalytics)
        
        // 1. Default config: enabled at 03:00 AM
        #expect(organizer.isEnabled == true)
        #expect(organizer.scheduledHour == 3)
        #expect(organizer.scheduledMinute == 0)
        #expect(organizer.formattedScheduledTime == "03:00")
        
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone.current
        let yesterdayHandled = "2026-11-23@03:00"
        tempDB.set(yesterdayHandled, forKey: CotLocalDatabase.ConfigKey.aiScheduledOrganizeLastCycleKey)
        let freshOrganizer = ScheduledAIDocumentOrganizer(database: tempDB, analytics: tempAnalytics)
        
        let at0259 = try #require(cal.date(from: DateComponents(year: 2026, month: 11, day: 24, hour: 2, minute: 59)))
        let at0300 = try #require(cal.date(from: DateComponents(year: 2026, month: 11, day: 24, hour: 3, minute: 0, second: 5)))
        let at0830Wake = try #require(cal.date(from: DateComponents(year: 2026, month: 11, day: 24, hour: 8, minute: 30)))
        
        #expect(freshOrganizer.dueCycleKey(now: at0259, calendar: cal) == nil)
        #expect(freshOrganizer.dueCycleKey(now: at0300, calendar: cal) == "2026-11-24@03:00")
        #expect(freshOrganizer.dueCycleKey(now: at0830Wake, calendar: cal) == "2026-11-24@03:00")
        
        // Toggling off suppresses scheduled execution
        freshOrganizer.setEnabled(false, now: at0259)
        #expect(freshOrganizer.dueCycleKey(now: at0300, calendar: cal) == nil)
        freshOrganizer.setEnabled(true, now: at0259)
        
        // 2. Seed untitled & placeholder-named documents and run the full 4-stage pipeline
        tempDB.saveDocument(
            id: "doc:untitled_1",
            title: "未命名",
            filePath: nil,
            syntax: "Markdown",
            content: "# 支付回调幂等架构设计方案\n\n- [ ] 敲定支付回调重试上限并补齐单元测试\n需要重点验证并发重复通知场景。"
        )
        tempDB.saveDocument(
            id: "doc:draft_111",
            title: "111",
            filePath: nil,
            syntax: "Markdown",
            content: "# 周一架构评审会议纪要\n\n讨论了时间轴折叠视图以及凌晨定时 AI 整理策略。"
        )
        
        let dueKey = try #require(freshOrganizer.dueCycleKey(now: at0300, calendar: cal))
        let report = await freshOrganizer.runOrganizePipeline(
            markCycleKey: dueKey,
            referenceDate: at0300,
            allowRemoteAI: false
        )
        
        // Stage 1: Both generic/placeholder titles renamed cleanly from content
        #expect(report.renamedCount == 2)
        let titlesAfter = Set(tempDB.documents.map(\.title))
        #expect(titlesAfter.contains("支付回调幂等架构设计方案"))
        #expect(titlesAfter.contains("周一架构评审会议纪要"))
        
        // Stage 2: Star-Map groups assigned cleanly
        #expect(report.regroupedCount == 2)
        #expect(tempDB.documents.allSatisfy { !$0.groupName.isEmpty })
        
        // Stage 3 & 4: "干了啥" & "要干啥" refreshed
        #expect(!tempAnalytics.doneTodayPoints.isEmpty)
        #expect(!tempAnalytics.actionPredictions.isEmpty)
        #expect(!freshOrganizer.lastSummary.isEmpty)
        
        // Same day's 03:00 cycle will not double-fire
        #expect(freshOrganizer.dueCycleKey(now: at0830Wake, calendar: cal) == nil)
        
        // Custom scheduled time configuration works cleanly
        freshOrganizer.updateScheduledTime(hour: 4, minute: 30, now: at0259)
        #expect(freshOrganizer.formattedScheduledTime == "04:30")
        let at0430 = try #require(cal.date(from: DateComponents(year: 2026, month: 11, day: 24, hour: 4, minute: 30, second: 10)))
        #expect(freshOrganizer.dueCycleKey(now: at0430, calendar: cal) == "2026-11-24@04:30")
        
        // Dedicated Scheduled Tasks sidebar item exists with valid SF Symbol and clean title
        #expect(SidebarSettingsItem.allCases.contains(.scheduledTasks))
        #expect(SidebarSettingsItem.scheduledTasks.title == AppLanguage.text("定时任务", en: "Schedules"))
        #expect(NSImage(systemSymbolName: SidebarSettingsItem.scheduledTasks.symbolName, accessibilityDescription: nil) != nil)
        
        // Frequency filter & next-run label work cleanly
        freshOrganizer.frequency = .weekends
        // 2026-11-24 is Tuesday -> not a weekend
        #expect(freshOrganizer.dueCycleKey(now: at0430, calendar: cal) == nil)
        freshOrganizer.frequency = .daily
        #expect(freshOrganizer.nextScheduledLabel(now: at0259, calendar: cal).contains("04:30"))
        
        // Step toggles persist and disable scheduled run when all steps are off
        freshOrganizer.renameUntitledEnabled = false
        freshOrganizer.organizeStarMapEnabled = false
        freshOrganizer.refreshDashboardEnabled = false
        #expect(!freshOrganizer.hasAnyStepEnabled)
        #expect(freshOrganizer.dueCycleKey(now: at0430, calendar: cal) == nil)
        freshOrganizer.renameUntitledEnabled = true
        freshOrganizer.organizeStarMapEnabled = true
        freshOrganizer.refreshDashboardEnabled = true
        
        // Settings card mounts cleanly
        let cardHost = NSHostingView(rootView: ScheduledAIOrganizeSettingsCard(isEmbeddedInGroupCard: false))
        cardHost.frame = NSRect(x: 0, y: 0, width: 520, height: 420)
        cardHost.layoutSubtreeIfNeeded()
        #expect(cardHost.bounds.width == 520)
    }
    
    
    @Test func dashboardHeroCoverStorePersistsUploadedImageAndFocalAlignment() throws {
        let tempURL = FileManager.default.temporaryDirectory
            .appending(path: "cot_hero_cover_test_\(UUID().uuidString).sqlite3")
        defer { try? FileManager.default.removeItem(at: tempURL) }
        
        let tempDB = CotLocalDatabase(customURL: tempURL)
        let store = DashboardHeroCoverStore(database: tempDB)
        #expect(store.coverImage == nil)
        
        let sample = NSImage(size: NSSize(width: 320, height: 180))
        sample.lockFocus()
        NSColor.systemTeal.setFill()
        NSRect(x: 0, y: 0, width: 320, height: 180).fill()
        sample.unlockFocus()
        
        #expect(store.setCoverImage(sample) == true)
        #expect(store.coverImage != nil)
        store.focalY = 0.15
        
        let reloaded = DashboardHeroCoverStore(database: tempDB)
        #expect(reloaded.coverImage != nil)
        #expect(abs(reloaded.focalY - 0.15) < 0.02)
        
        reloaded.clearCoverImage()
        #expect(reloaded.coverImage == nil)
        let afterClear = DashboardHeroCoverStore(database: tempDB)
        #expect(afterClear.coverImage == nil)
    }
    
    
    @Test func butlerSystemPromptIncludesLocalTimeAndModelWithoutInternalJargonNoise() throws {
        let tempURL = FileManager.default.temporaryDirectory
            .appending(path: "cot_butler_prompt_test_\(UUID().uuidString).sqlite3")
        defer { try? FileManager.default.removeItem(at: tempURL) }
        
        let tempDB = CotLocalDatabase(customURL: tempURL)
        let memStore = CotMemoryStore(database: tempDB)
        let manager = CotButlerManager(database: tempDB, memoryStore: memStore)
        let config = AIConfiguration(
            endpoint: .openAIChatCompletions,
            baseURL: "https://example.com",
            model: "glm-5.3",
            apiKey: "test",
            temperature: 0.4
        )
        
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone.current
        let fixedNow = try #require(cal.date(from: DateComponents(year: 2026, month: 11, day: 24, hour: 14, minute: 5)))
        
        let casualPrompt = manager.buildButlerSystemPrompt(
            resolvedConfig: config,
            userMessage: "你是啥模型?",
            now: fixedNow
        )
        #expect(casualPrompt.contains("14:05"))
        #expect(casualPrompt.contains("glm-5.3"))
        #expect(!casualPrompt.contains("众 Bot 当前编队状态"))
        #expect(!casualPrompt.contains("全部助手配置"))
        
        let managePrompt = manager.buildButlerSystemPrompt(
            resolvedConfig: config,
            userMessage: "把翻译助手的模型换成 deepseek",
            now: fixedNow
        )
        #expect(managePrompt.contains("全部助手配置"))
        #expect(managePrompt.contains("双语翻译官"))
    }
    
    
    @Test func vimSmoothScrollConvergesMonotonicallyWithoutOvershoot() {
        var y: CGFloat = 100
        let target: CGFloat = 160
        let dt: CGFloat = 1.0 / 120.0
        var settled = false
        for _ in 0..<120 {
            let step = EditorFunEffectsController.stepSmoothScrollOrigin(currentY: y, targetY: target, rate: 20.0, dt: dt)
            #expect(step.nextY >= y)
            #expect(step.nextY <= target)
            y = step.nextY
            if step.settled {
                settled = true
                break
            }
        }
        #expect(settled)
        #expect(abs(y - target) < 0.01)
    }
}
