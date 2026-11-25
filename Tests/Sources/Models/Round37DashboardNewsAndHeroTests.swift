//
//  Round37DashboardNewsAndHeroTests.swift
//
//  Tests
//  https://coteditor.com
//

import AppKit
import Foundation
import Testing
@testable import CotEditor

@MainActor
struct Round37DashboardNewsAndHeroTests {
    
    @Test func newsToolsAndFastBotHaveExpectedResilienceFixes() throws {
        let ext = PiCotToolsExtension.source
        #expect(ext.contains("item?.urlString || item?.url"))
        #expect(ext.contains("api.fxtwitter.com"))
        #expect(ext.contains("hn.algolia.com/api/v1/items/"))
        #expect(ext.contains("https://r.jina.ai/"))
        #expect(ext.contains("news.google.com/rss/search"))
        
        // Verify compiled WebUI bundle sets `showEffort: !1` (false) on both PromptBar instances
        let html = BeautifulAgentUIBundle.htmlDocument()
        #expect(html.contains("showEffort:!1"))
        #expect(NewsReasoningEffort.simple.apiValue == "low")
    }
    
    
    @Test func feedRefreshRotatesFinanceAndXCardsLikeShortVideoFeed() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: "cot_news_refresh_\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        let db = CotLocalDatabase(customURL: tempDir.appending(path: "news.sqlite3"))
        let service = AIHotNewsService(database: db, cacheRootDirectory: tempDir.appending(path: "cache"))
        
        var seeded: [AIHotNewsItem] = []
        for idx in 1...8 {
            seeded.append(AIHotNewsItem(
                id: "fin-\(idx)",
                title: "Wall Street Q3 Earnings Update #\(idx)",
                source: "CNBC Markets",
                urlString: "https://cnbc.com/news/\(idx)",
                publishedAt: Date(),
                heatScore: 90 - idx,
                category: .finance,
                summary: "Finance summary #\(idx)"
            ))
            seeded.append(AIHotNewsItem(
                id: "x-\(idx)",
                title: "X Engineering Deep Dive Thread #\(idx)",
                source: "X (@dev\(idx))",
                urlString: "https://x.com/dev\(idx)/status/\(1000 + idx)",
                publishedAt: Date(),
                heatScore: 80 - idx,
                category: .xSocial,
                summary: "X thread #\(idx)"
            ))
            seeded.append(AIHotNewsItem(
                id: "ai-\(idx)",
                title: "Open Weight Reasoning Model Benchmark #\(idx)",
                source: "AI Research",
                urlString: "https://example.com/ai/\(idx)",
                publishedAt: Date(),
                heatScore: 95 - idx,
                category: .ai,
                summary: "AI summary #\(idx)"
            ))
        }
        service.replaceItemsForTesting(seeded)
        
        let initialFinanceHead = Array(service.feedItems(for: .finance).prefix(4).map(\.id))
        let initialToken = service.feedRefreshToken
        
        await service.refreshFeed(for: .finance, visibleCount: 4, forceNetwork: false)
        let refreshedFinanceHead = Array(service.feedItems(for: .finance).prefix(4).map(\.id))
        #expect(service.feedRefreshToken > initialToken)
        #expect(Set(refreshedFinanceHead) != Set(initialFinanceHead))
        
        let initialXHead = Array(service.feedItems(for: .xSocial).prefix(4).map(\.id))
        await service.refreshFeed(for: .xSocial, visibleCount: 4, forceNetwork: false)
        let refreshedXHead = Array(service.feedItems(for: .xSocial).prefix(4).map(\.id))
        #expect(Set(refreshedXHead) != Set(initialXHead))
    }
    
    
    @Test func browsingHistoryPersistsVisitOrderCountAndLookup() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: "cot_news_hist_\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        let db = CotLocalDatabase(customURL: tempDir.appending(path: "news-history.sqlite3"))
        let first = AIHotNewsItem(
            id: "hist-1",
            title: "Understanding Transformer KV Cache Compression",
            source: "Blog",
            urlString: "https://example.com/kv-cache",
            category: .ai,
            summary: "Detailed notes on grouped-query attention and quantization."
        )
        let second = AIHotNewsItem(
            id: "hist-2",
            title: "Fed Rate Path & Treasury Yield Curve Analysis",
            source: "WSJ",
            urlString: "https://wsj.com/articles/rates",
            category: .finance,
            summary: "Macro yield overview."
        )
        
        do {
            let service = AIHotNewsService(database: db, cacheRootDirectory: tempDir.appending(path: "cache"))
            service.recordBrowsingHistory(first)
            service.recordBrowsingHistory(second)
            service.recordBrowsingHistory(first)
            
            #expect(service.browsingHistory.count == 2)
            #expect(service.browsingHistory[0].id == "hist-1")
            #expect(service.browsingHistory[0].visitCount == 2)
            #expect(service.browsingHistory[1].id == "hist-2")
            #expect(service.isRead(first))
            #expect(service.findItem(byID: "hist-2")?.title == second.title)
        }
        
        let reloaded = AIHotNewsService(database: db, cacheRootDirectory: tempDir.appending(path: "cache"))
        #expect(reloaded.browsingHistory.count == 2)
        #expect(reloaded.browsingHistory[0].id == "hist-1")
        #expect(reloaded.browsingHistory[0].visitCount == 2)
        
        reloaded.removeBrowsingHistory(id: "hist-1")
        #expect(reloaded.browsingHistory.count == 1)
        #expect(reloaded.browsingHistory[0].id == "hist-2")
        
        reloaded.clearBrowsingHistory()
        #expect(reloaded.browsingHistory.isEmpty)
    }
    
    
    @Test func robustExtractorHandlesDivBlogsSSRAndJinaMarkdownAndRejectsStubs() {
        // 1. Leaf `<div>` blog paragraphs when `<p>` tags are absent
        let divBlogHTML = """
        <html><body><main>
        <div class="post-line">First deep architectural observation describing sparse mixture-of-experts routing latency across multi-node InfiniBand clusters.</div>
        <div class="post-line">Second empirical benchmark showing token throughput scaling with speculative decoding and KV cache paging enabled in production.</div>
        </main></body></html>
        """
        let divResult = NewsArticleExtractor.extractFromWebPageHTML(divBlogHTML)
        #expect(divResult.blocks.count == 2)
        #expect(NewsArticleContent(blocks: divResult.blocks, leadExcerpt: nil, author: nil, extractedAt: .now).isSubstantial)
        
        // 2. `__NEXT_DATA__` SSR hydration payload
        let longBody = "Server-side hydrated technical article explaining deterministic scheduling in distributed actor runtimes, memory isolation guarantees, and backpressure propagation under sustained bursts."
        let nextHTML = """
        <html><head></head><body><div id="__next"></div>
        <script id="__NEXT_DATA__" type="application/json">{"props":{"pageProps":{"article":{"body":"\(longBody)"}}}}</script>
        </body></html>
        """
        let ssrResult = NewsArticleExtractor.extractFromWebPageHTML(nextHTML)
        #expect(!ssrResult.blocks.isEmpty)
        #expect(NewsArticleContent(blocks: ssrResult.blocks, leadExcerpt: nil, author: nil, extractedAt: .now).isSubstantial)
        
        // 3. Rejects anti-bot JS gate stub
        let botStubHTML = "<html><body><p>JavaScript is not available. Please enable JavaScript and cookies to continue.</p></body></html>"
        let botResult = NewsArticleExtractor.extractFromWebPageHTML(botStubHTML)
        #expect(botResult.blocks.isEmpty)
        
        // 4. Strips Jina Reader preamble and parses structured Markdown cleanly
        let jinaMarkdown = """
        Title: Deep Systems Architecture
        URL Source: https://example.com/systems
        Markdown Content:

        ## Core Finding

        This [research benchmark](https://example.com/bench) demonstrates sustained throughput gains when batching memory writes.

        * [Home](/)
        * [About](/about)

        - Eliminate redundant copies
        - Coalesce metadata flushes
        """
        let mdBlocks = NewsArticleExtractor.extractBlocksFromMarkdown(jinaMarkdown)
        let combined = NewsArticleContent(blocks: mdBlocks, leadExcerpt: nil, author: nil, extractedAt: .now).markdownBody
        #expect(!combined.contains("URL Source:"))
        #expect(combined.contains("Core Finding"))
        #expect(combined.contains("research benchmark"))
        #expect(!combined.contains("https://example.com/bench"))
    }
    
    
    @Test func heroCoverStorePersistsFocalXFitModeAndSmartAutoFocus() throws {
        let tempURL = FileManager.default.temporaryDirectory
            .appending(path: "cot_hero_adapt_\(UUID().uuidString).sqlite3")
        defer { try? FileManager.default.removeItem(at: tempURL) }
        
        let db = CotLocalDatabase(customURL: tempURL)
        let store = DashboardHeroCoverStore(database: db)
        
        // Create a 300x400 portrait image with a bright focal rectangle near the top-right
        let img = NSImage(size: NSSize(width: 300, height: 400))
        img.lockFocus()
        NSColor(white: 0.12, alpha: 1.0).setFill()
        NSRect(x: 0, y: 0, width: 300, height: 400).fill()
        NSColor.systemOrange.setFill()
        NSRect(x: 180, y: 260, width: 90, height: 90).fill()
        img.unlockFocus()
        
        #expect(store.setCoverImage(img))
        store.focalX = 0.72
        store.focalY = 0.22
        store.fitMode = .fit
        
        let reloaded = DashboardHeroCoverStore(database: db)
        #expect(reloaded.coverImage != nil)
        #expect(abs(reloaded.focalX - 0.72) < 0.02)
        #expect(abs(reloaded.focalY - 0.22) < 0.02)
        #expect(reloaded.fitMode == .fit)
        
        if let cg = DashboardHeroCoverStore.underlyingCGImage(from: try #require(reloaded.coverImage)) {
            if let smart = DashboardHeroCoverStore.detectSmartFocalPoint(for: cg) {
                #expect((0.0...1.0).contains(smart.x))
                #expect((0.0...1.0).contains(smart.y))
            }
        }
        
        let tones = HeroCoverToneSampler.sample(
            image: reloaded.coverImage,
            focalX: 0.72,
            focalY: 0.22,
            fitMode: .fit,
            canvasAspect: 4.0,
            fallbackRGB: (0.95, 0.95, 0.95)
        )
        #expect(tones.hasPhoto)
        
        reloaded.clearCoverImage()
        #expect(reloaded.coverImage == nil)
        #expect(reloaded.fitMode == .fill)
        #expect(abs(reloaded.focalX - 0.50) < 0.02)
    }
}
