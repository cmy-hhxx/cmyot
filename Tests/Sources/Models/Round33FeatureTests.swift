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
    
    
    // MARK: 13. Hero Banner Fluted Prism Uniform Luminance (No Glaring Pure-White Voids)
    
    @Test func uniformBannerFlutedPrismEliminatesPureWhitePatchesAcrossFullWidth() throws {
        let width = 180
        let height = 48
        let palettes: [FlutedGlassPalette] = [.cobaltBlue, .pineEmerald, .amberGold, .nebulaViolet]
        
        for palette in palettes {
            let image = try #require(BlueFlutedGlassRenderer.renderFrame(
                time: 4.5,
                palette: palette,
                width: width,
                height: height,
                ribCount: 66.0,
                uniformBannerMode: true
            ))
            let rep = NSBitmapImageRep(cgImage: image)
            
            var blownOutWhitePixels = 0
            var thirdLumaSums = [0.0, 0.0, 0.0]
            var thirdCounts = [0, 0, 0]
            
            for y in 0..<height {
                for x in 0..<width {
                    let color = try #require(rep.colorAt(x: x, y: y)?.usingColorSpace(NSColorSpace.sRGB))
                    let r = Double(color.redComponent)
                    let g = Double(color.greenComponent)
                    let b = Double(color.blueComponent)
                    if r > 0.92 && g > 0.92 && b > 0.92 {
                        blownOutWhitePixels += 1
                    }
                    let luma = 0.2126 * r + 0.7152 * g + 0.0722 * b
                    let third = min(2, (x * 3) / width)
                    thirdLumaSums[third] += luma
                    thirdCounts[third] += 1
                }
            }
            
            #expect(blownOutWhitePixels == 0)
            let means = zip(thirdLumaSums, thirdCounts).map { $0 / Double(max(1, $1)) }
            let spread = (means.max() ?? 0) - (means.min() ?? 0)
            #expect(spread < 0.16)
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
}
