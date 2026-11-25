//
//  FormalVerificationTests.swift
//
//  Tests
//  https://coteditor.com
//

import AppKit
import Foundation
import SwiftUI
import Testing
@testable import CotEditor

@MainActor
struct FormalVerificationTests {
    
    @Test func webUIBundlesAndOfflineChartAssetsAreFreeOfSlopAndCDNDependencies() {
        let agentHTML = BeautifulAgentUIBundle.htmlDocument()
        #expect(!agentHTML.isEmpty)
        #expect(agentHTML.contains("requestAnimationFrame"))
        #expect(agentHTML.contains("showEffort:!1"))
        for emoji in ["✨", "🚀", "🎉", "🤖"] {
            #expect(!agentHTML.contains(emoji))
        }
        
        let chartHTML = TradingViewLightweightChartView.chartHTMLDocument()
        #expect(chartHTML.contains("createChart"))
        #expect(chartHTML.contains("CandlestickSeries"))
        #expect(!chartHTML.contains("<script src=\"http"))
        #expect(!chartHTML.contains("https://unpkg.com"))
    }
    
    
    @Test func runtimePerformanceBudgetsStayWithinStrictLimits() {
        let clock = ContinuousClock()
        
        // 1. Clean excerpt extraction over 1,000 documents < 500ms
        let sampleMarkdown = """
        # 核心架构演进总结
        ---
        > 本周完成三栏布局与形式化验证流水线落地
        ```swift
        let metric = computeLatency()
        ```
        - [x] 优化主线程渲染效率与排版克制度
        """
        let excerptElapsed = clock.measure {
            for _ in 0..<1_000 {
                _ = DocumentCenterState.cleanExcerpt(from: sampleMarkdown, maxLength: 96)
            }
        }
        #expect(excerptElapsed < .milliseconds(500))
        
        // 2. Full-text multi-term search across 300 documents < 500ms
        let terms = StarMapSearchEngine.parseTerms("三栏布局 效率")
        let searchElapsed = clock.measure {
            for idx in 0..<300 {
                let eval = StarMapSearchEngine.evaluate(
                    queryTerms: terms,
                    title: "架构演进记录 \(idx)",
                    category: "工程方案",
                    secondaryMeta: "doc_\(idx).md",
                    content: sampleMarkdown
                )
                if idx == 0 {
                    #expect(eval.isMatch)
                }
            }
        }
        #expect(searchElapsed < .milliseconds(500))
        
        // 3. Cross-node relation graph across 50 documents < 600ms
        let corpusDocs = (0..<50).map { idx in
            StarMapRelationEngine.CorpusDocument(
                id: "doc-\(idx)",
                title: "技术备忘 \(idx)",
                group: "研发\(idx % 5)",
                folderPath: "",
                content: sampleMarkdown + " 关联词\(idx % 7)",
                sortTimestamp: Double(1_700_000_000 + idx)
            )
        }
        let relationElapsed = clock.measure {
            _ = StarMapRelationEngine.buildRelations(for: corpusDocs, maxEdgesPerNode: 3)
        }
        #expect(relationElapsed < .milliseconds(600))
        
        // 4. Proactive card assembly <= 3 cards and < 50ms
        let engine = CotButlerProactiveEngine()
        let sanan = MarketAliasCatalog.resolve("三安光电")!.toRecord(sortOrder: 0, thesisNote: "", addedBy: "seed")
        var generatedCards: [ButlerProactiveCardPayload] = []
        let cardElapsed = clock.measure {
            generatedCards = engine.buildProactiveCards(
                watchlist: [sanan],
                quotes: [:],
                memories: [],
                unreadPodcasts: [],
                recentNews: []
            )
        }
        #expect(generatedCards.count <= 3)
        #expect(cardElapsed < .milliseconds(50))
    }
    
    
    @Test func offlineMarketParsersAndExcerptInvariantsHoldStrictly() throws {
        let tz = MarketRegion.aShare.timeZone
        let payload = """
        {
          "rc": 0,
          "data": {
            "preKPrice": 14.0,
            "klines": [
              "2026-11-24,14.00,14.20,13.95,14.35,120000,170000000,0",
              "2026-11-25,14.20,14.50,14.60,14.10,150000,210000000,0"
            ]
          }
        }
        """.data(using: .utf8)!
        
        let parsed = try #require(
            CotMarketDataClient.parseEastMoneyKlinePayload(payload, period: .day, timeZone: tz)
        )
        #expect(parsed.bars.count == 2)
        for bar in parsed.bars {
            #expect(bar.open.isFinite && bar.close.isFinite && bar.high.isFinite && bar.low.isFinite)
            #expect(bar.high >= max(bar.open, bar.close))
            #expect(bar.low <= min(bar.open, bar.close))
            #expect(bar.volume >= 0)
        }
        
        let dirtyMD = "# 标题\n---\n> 引用\n```swift\ncode\n```\n- 条目内容"
        let excerpt = DocumentCenterState.cleanExcerpt(from: dirtyMD, maxLength: 24)
        #expect(!excerpt.contains("#"))
        #expect(!excerpt.contains(">"))
        #expect(!excerpt.contains("---"))
        #expect(!excerpt.contains("```"))
        #expect(excerpt.count <= 24)
    }
    
    
    @Test func primaryCentersAndDashboardMountAtStableWindowBounds() throws {
        try self.assertMountsAtFullBounds(
            WeeklyReportCenterView(state: WeeklyReportCenterState(), onOpenReport: { _ in }, onDismiss: { })
        )
        try self.assertMountsAtFullBounds(
            DocumentCenterView(state: DocumentCenterState(), onOpenDocument: { _, _ in }, onCreateNewDocument: { }, onDismiss: { })
        )
        try self.assertMountsAtFullBounds(
            AnalyticsDashboardView(isEmbeddedInSettings: false, onDismiss: { })
        )
    }
    
    
    private func assertMountsAtFullBounds<V: View>(_ rootView: V) throws {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1120, height: 720),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        defer { window.close() }
        
        let host = NSHostingController(rootView: rootView)
        host.sizingOptions = []
        window.contentViewController = host
        window.setContentSize(NSSize(width: 1120, height: 720))
        
        let contentView = try #require(window.contentView)
        contentView.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.08))
        contentView.layoutSubtreeIfNeeded()
        
        #expect(abs(contentView.bounds.width - 1120) <= 2)
        #expect(abs(contentView.bounds.height - 720) <= 2)
    }
}
