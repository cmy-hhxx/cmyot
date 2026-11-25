//
//  Round39BoardsAndSuperAgentTests.swift
//
//  Tests
//  https://coteditor.com
//

import Foundation
import Testing
@testable import CotEditor

@MainActor
struct Round39BoardsAndSuperAgentTests {
    
    @Test func tradingViewLightweightChartsBundleAndHTMLShellAreValid() {
        let js = TradingViewLightweightChartView.bundledLibraryJS()
        #expect(!js.isEmpty)
        #expect(js.contains("createChart"))
        #expect(js.contains("CandlestickSeries"))
        
        let html = TradingViewLightweightChartView.chartHTMLDocument()
        #expect(html.contains("CandlestickSeries"))
        #expect(html.contains("HistogramSeries"))
        #expect(html.contains("AreaSeries"))
        #expect(html.contains("CotChartBridge"))
    }
    
    
    @Test func focusStocksResolveAndSeedIntoCleanDatabaseWithoutDuplicates() throws {
        let sanan = try #require(MarketAliasCatalog.resolve("三安光电"))
        #expect(sanan.instrumentID == "sh:600703")
        #expect(sanan.tencentCode == "sh600703")
        #expect(sanan.eastmoneySecID == "1.600703")
        
        let boe1 = try #require(MarketAliasCatalog.resolve("京东方"))
        let boe2 = try #require(MarketAliasCatalog.resolve("京东方A"))
        #expect(boe1.instrumentID == "sz:000725")
        #expect(boe2.instrumentID == "sz:000725")
        #expect(boe1.tencentCode == "sz000725")
        
        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: "cot_r39_market_\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        let db = CotLocalDatabase(customURL: tempDir.appending(path: "market.sqlite3"))
        db.seedUserFocusStocksIfNeeded(allowDuringTests: true)
        db.seedUserFocusStocksIfNeeded(allowDuringTests: true)
        
        let stocks = db.fetchWatchlistStocks()
        #expect(stocks.filter { $0.instrumentID == "sh:600703" }.count == 1)
        #expect(stocks.filter { $0.instrumentID == "sz:000725" }.count == 1)
    }
    
    
    @Test func marketDataOfflineParsersHandleTencentGBKEastMoneyAndSina() throws {
        let cfEncoding = CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)
        let gbkEncoding = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(cfEncoding))
        var tencentFields = Array(repeating: "0", count: 50)
        tencentFields[1] = "三安光电"
        tencentFields[2] = "600703"
        tencentFields[3] = "14.28"
        tencentFields[4] = "13.95"
        tencentFields[5] = "14.02"
        tencentFields[6] = "421580"
        tencentFields[33] = "14.45"
        tencentFields[34] = "13.88"
        tencentFields[37] = "59820"
        tencentFields[38] = "1.85"
        tencentFields[39] = "36.4"
        tencentFields[45] = "712.4"
        let rawTencent = "v_sh600703=\"\(tencentFields.joined(separator: "~"))\";"
        let gbkData = try #require(rawTencent.data(using: gbkEncoding))
        
        let decoded = try #require(CotMarketDataClient.decodeGBKString(from: gbkData))
        #expect(decoded.contains("三安光电"))
        
        let quote = try #require(CotMarketDataClient.parseTencentQuoteResponse(decoded))
        #expect(quote.lastPrice == 14.28)
        #expect(quote.previousClose == 13.95)
        #expect(quote.dayOpen == 14.02)
        #expect(quote.turnoverRate == 1.85)
        #expect(quote.peRatio == 36.4)
        #expect(quote.marketCap == 712.4)
        
        let shTZ = MarketRegion.aShare.timeZone
        let emIntradayJSON = """
        {
          "rc": 0,
          "data": {
            "preKPrice": 13.95,
            "klines": [
              "2026-11-24 14:59,13.90,13.95,13.98,13.89,1200,16700,0",
              "2026-11-25 09:30,14.02,14.10,14.12,14.00,3500,49200,0",
              "2026-11-25 09:31,14.10,14.28,14.30,14.09,4200,59800,0"
            ]
          }
        }
        """.data(using: .utf8)!
        let intraday = try #require(
            CotMarketDataClient.parseEastMoneyKlinePayload(emIntradayJSON, period: .intraday, timeZone: shTZ)
        )
        #expect(intraday.bars.count == 2)
        #expect(intraday.bars.first?.timeLabel == "09:30")
        #expect(intraday.bars.last?.close == 14.28)
        #expect(intraday.previousClose == 13.95)
        
        let emDailyJSON = """
        {
          "rc": 0,
          "data": {
            "preKPrice": 13.50,
            "klines": [
              "2026-11-24,13.60,13.95,14.00,13.55,310000,430000000,0",
              "2026-11-25,14.02,14.28,14.45,13.88,421580,598200000,0"
            ]
          }
        }
        """.data(using: .utf8)!
        let daily = try #require(
            CotMarketDataClient.parseEastMoneyKlinePayload(emDailyJSON, period: .day, timeZone: shTZ)
        )
        #expect(daily.bars.count == 2)
        #expect(daily.bars.last?.timeLabel == "2026-11-25")
        
        let sinaJSON = """
        [
          {"day":"2026-11-25 09:35:00","open":"4.18","high":"4.24","low":"4.16","close":"4.22","volume":"1250000"},
          {"day":"2026-11-25 09:40:00","open":"4.22","high":"4.27","low":"4.20","close":"4.25","volume":"980000"}
        ]
        """.data(using: .utf8)!
        let fiveMin = CotMarketDataClient.parseSinaKlineJSON(sinaJSON, period: .fiveMin, timeZone: shTZ)
        #expect(fiveMin.count == 2)
        #expect(fiveMin.first?.timeLabel == "2026-11-25 09:35")
        #expect(fiveMin.last?.close == 4.25)
    }
    
    
    @Test func podcastOfflineCacheLayoutModesAndAgentRemindersWork() throws {
        #expect(PodcastLayoutMode.allCases.contains(.split))
        #expect(PodcastLayoutMode.allCases.contains(.immersive))
        #expect(PodcastLayoutMode.allCases.contains(.compactMini))
        
        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: "cot_r39_podcast_\(UUID().uuidString)", directoryHint: .isDirectory)
        let downloadsDir = tempDir.appending(path: "Downloads", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: downloadsDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        let db = CotLocalDatabase(customURL: tempDir.appending(path: "podcast.sqlite3"))
        let store = CotMemoryStore(database: db)
        let service = CotPodcastService(
            database: db,
            memoryStore: store,
            downloadsDirectory: downloadsDir
        )
        
        let episode = PodcastEpisodeItem(
            id: "pod-llm-scale-01",
            platform: "Apple",
            title: "大模型分布式训练实战与 Scaling Laws",
            showName: "AI Engineering Pod",
            sourceURL: "https://example.com/episodes/llm-scale",
            audioURL: "https://example.com/audio/llm-scale.mp3",
            duration: 2400,
            summary: "探讨万卡集群通信拓扑与 FP8 训练稳定性。",
            topicTag: "大模型训练"
        )
        
        #expect(!service.isDownloaded(episode))
        let localURL = CotPodcastService.preferredLocalURL(for: episode, in: downloadsDir)
        #expect(localURL.pathExtension == "mp3")
        try Data("FAKE_MP3_BYTES".utf8).write(to: localURL)
        
        #expect(service.isDownloaded(episode))
        #expect(service.localAudioURL(for: episode)?.path == localURL.path)
        
        service.recordAgentRecommendation(
            episode,
            topic: "大模型训练",
            reason: "已按你的要求找好并离线下载",
            localPath: localURL.path
        )
        #expect(service.unreadReminders.count == 1)
        let reminderID = try #require(service.unreadReminders.first?.id)
        
        service.markReminderRead(id: reminderID)
        #expect(service.unreadReminders.isEmpty)
        #expect(service.agentReminders.count == 1)
        
        service.dismissReminder(id: reminderID)
        #expect(service.agentReminders.isEmpty)
        
        let ext = PiCotToolsExtension.source
        #expect(ext.contains("find_and_download_podcast"))
        #expect(ext.contains("curate_podcast"))
        #expect(ext.contains("push2his.eastmoney.com"))
        #expect(ext.contains("600703"))
        #expect(ext.contains("000725"))
    }
    
    
    @Test func butlerProactiveEngineAndWebUIBundleSupportSuperAgent() {
        let engine = CotButlerProactiveEngine()
        
        let sananInst = MarketAliasCatalog.resolve("三安光电")!
        let sananRecord = sananInst.toRecord(sortOrder: 0, thesisNote: "SiC衬底", addedBy: "seed")
        let quote = MarketQuoteSnapshot(
            instrument: sananInst,
            lastPrice: 14.28,
            previousClose: 13.95,
            dayOpen: 14.02,
            high: 14.45,
            low: 13.88,
            volume: 421580,
            barsByPeriod: [:],
            updatedAt: Date(),
            turnoverRate: 1.85,
            peRatio: 36.4,
            marketCap: 712.4
        )
        let memory = UserKYCMemoryRecord(
            id: "mem-1",
            dimension: .goals,
            factKey: "goal.llm_training",
            title: "深入研究大模型预训练架构",
            detail: "重点关注 MoE 负载均衡与 FP8 混合精度",
            confidence: 0.95,
            source: "user",
            evidenceRef: nil,
            isPinned: true,
            isArchived: false,
            reinforcementCount: 2,
            createdAt: Date(),
            updatedAt: Date()
        )
        let podcastRec = AgentPodcastRecommendation(
            id: "rec-1",
            episodeID: "pod-1",
            topic: "大模型训练",
            reason: "已下载",
            episodeTitle: "Infra 深度拆解",
            showName: "Systems Pod",
            artworkURL: "",
            localFilePath: "/tmp/ep.mp3",
            createdAt: Date(),
            isRead: false
        )
        let newsItem = AIHotNewsItem(
            id: "news-1",
            title: "DeepSeek 开源新一代推理引擎优化",
            source: "Hacker News",
            urlString: "https://example.com/ds",
            publishedAt: Date(),
            heatScore: 98,
            category: .ai,
            summary: "大幅降低 KV Cache 显存占用。"
        )
        let history = NewsBrowsingHistoryItem(
            id: newsItem.id,
            item: newsItem,
            visitedAt: Date(),
            visitCount: 1
        )
        
        let cards = engine.buildProactiveCards(
            watchlist: [sananRecord],
            quotes: [sananRecord.instrumentID: quote],
            memories: [memory],
            unreadPodcasts: [podcastRec],
            recentNews: [newsItem]
        )
        #expect(cards.count == 3)
        #expect(cards.first?.icon == "podcast")
        #expect(cards.contains { $0.id == "proactive-market-focus" })
        
        engine.dismissCard(id: "proactive-market-focus")
        let afterDismiss = engine.buildProactiveCards(
            watchlist: [sananRecord],
            quotes: [sananRecord.instrumentID: quote],
            memories: [memory],
            unreadPodcasts: [podcastRec],
            recentNews: [newsItem]
        )
        #expect(!afterDismiss.contains { $0.id == "proactive-market-focus" })
        #expect(afterDismiss.count <= 3)
        
        engine.startWorker(id: "w-1", title: "搜寻播客", detail: "下载中", actionBoard: "podcast", actionQuery: "LLM")
        #expect(engine.workers.count == 1)
        #expect(engine.workers.first?.status == "running")
        
        engine.finishWorker(id: "w-1", title: "播客就绪", detail: "已完成", isError: false, actionBoard: "podcast")
        #expect(engine.workers.first?.status == "done")
        
        engine.dismissWorker(id: "w-1")
        #expect(engine.workers.isEmpty)
        
        let personalContext = engine.buildDeepPersonalContextSummary(
            watchlist: [sananRecord],
            quotes: [sananRecord.instrumentID: quote],
            memories: [memory],
            unreadPodcasts: [podcastRec],
            browsingHistory: [history],
            activeDocTitle: "TrainingNotes.md"
        )
        #expect(personalContext.contains("深入研究大模型预训练架构"))
        #expect(personalContext.contains("三安光电"))
        #expect(personalContext.contains("Infra 深度拆解"))
        #expect(personalContext.contains("DeepSeek 开源新一代推理引擎优化"))
        #expect(personalContext.contains("TrainingNotes.md"))
        
        let webHTML = BeautifulAgentUIBundle.htmlDocument()
        #expect(webHTML.contains("proactiveCards"))
        #expect(webHTML.contains("backgroundWorkers"))
        #expect(webHTML.contains("requestAnimationFrame"))
    }
}
