//
//  StructuredBrainAndBoardsTests.swift
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
struct StructuredBrainAndBoardsTests {
    
    private func makeIsolatedDatabaseURL() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appending(path: "coteditor-brain-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appending(path: "cot_user_data.sqlite3")
    }
    
    
    // MARK: 1. Structured SQLite Schema, Multi-Angle KYC & Single-File Portability
    
    @Test func structuredDatabaseCRUDAndSingleFileExportImport() throws {
        let urlA = self.makeIsolatedDatabaseURL()
        let urlB = self.makeIsolatedDatabaseURL()
        let exportURL = self.makeIsolatedDatabaseURL().deletingLastPathComponent().appending(path: "portable_backup.sqlite3")
        defer {
            try? FileManager.default.removeItem(at: urlA.deletingLastPathComponent())
            try? FileManager.default.removeItem(at: urlB.deletingLastPathComponent())
            try? FileManager.default.removeItem(at: exportURL)
        }
        
        let dbA = CotLocalDatabase(customURL: urlA)
        dbA.seedStarterWatchlistIfNeeded(allowDuringTests: true)
        
        // Starter watchlist is seeded once on fresh database
        let seeded = dbA.fetchWatchlistStocks()
        #expect(seeded.contains(where: { $0.instrumentID == "hk:HSTECH" }))
        #expect(seeded.contains(where: { $0.instrumentID == "us:NVDA" }))
        
        // Multi-dimension KYC upsert + reinforcement + audit journal
        dbA.upsertKYCMemory(
            dimension: .taboos,
            factKey: "no_small_captions",
            title: "禁止界面小字解释",
            detail: "让排版与层级自身解释信息",
            confidence: 0.96,
            source: "user_explicit",
            isPinned: true,
            actorBot: "Butler"
        )
        dbA.upsertKYCMemory(
            dimension: .finance,
            factKey: "hk_tech_focus",
            title: "长期跟踪恒生科技与港股龙头",
            detail: "关注估值修复与周期切换",
            confidence: 0.88,
            source: "board_intent",
            isPinned: false,
            actorBot: "Butler"
        )
        
        let taboos = dbA.fetchKYCMemories(dimension: .taboos)
        #expect(taboos.count == 1)
        #expect(taboos.first?.title == "禁止界面小字解释")
        #expect(taboos.first?.isPinned == true)
        
        let journal = dbA.fetchMemoryJournal(limit: 10)
        #expect(journal.count >= 2)
        
        // Portable interest tables: custom stock, podcast, blog/feed, X creator, Butler chat
        let customStock = MarketInstrument(
            namespace: .hongKong,
            symbol: "09988",
            name: "阿里巴巴-W",
            eastmoneySecID: "116.09988",
            tencentCode: "hk09988"
        ).toRecord(sortOrder: 10, thesisNote: "港股消费与云计算反转", addedBy: "user")
        dbA.upsertWatchlistStock(customStock)
        
        let now = Date()
        let podcast = StoredPodcastRecord(
            id: "pod:test-1",
            itemKind: "episode",
            platform: "apple",
            title: "关于人生焦虑与长期主义",
            showName: "纵横四海",
            sourceURL: "https://podcasts.apple.com/test",
            audioURL: "https://example.com/test.m4a",
            artworkURL: "",
            durationSec: 3600,
            playbackPositionSec: 420,
            isSaved: true,
            topicTag: "人生困惑",
            notes: "睡前听",
            lastPlayedAt: now,
            createdAt: now,
            updatedAt: now
        )
        dbA.upsertStoredPodcast(podcast)
        
        let feed = FollowedFeedRecord(
            id: "feed:paulgraham",
            title: "Paul Graham Essays",
            siteURL: "https://paulgraham.com",
            feedURL: "https://paulgraham.com/rss.html",
            category: "Essays",
            author: "Paul Graham",
            notes: "First-principles thinking",
            isPinned: true,
            addedBy: "user",
            createdAt: now,
            updatedAt: now
        )
        dbA.upsertFollowedFeed(feed)
        
        let creator = FollowedCreatorRecord(
            id: "x:karpathy",
            platform: "x",
            handle: "@karpathy",
            displayName: "Andrej Karpathy",
            profileURL: "https://x.com/karpathy",
            avatarURL: "",
            focusTags: "AI, LLM",
            whyFollowing: "Deep systems clarity",
            isPinned: true,
            addedBy: "user",
            createdAt: now,
            updatedAt: now
        )
        dbA.upsertFollowedCreator(creator)
        
        dbA.appendButlerMessage(ButlerChatMessage(
            id: "msg-1",
            role: "user",
            content: "以后叫你阿白，关注 @karpathy",
            actionsJSON: "",
            createdAt: now
        ))
        
        // Export single portable sqlite file and import into clean DB B
        try dbA.exportDatabase(to: exportURL)
        #expect(FileManager.default.fileExists(atPath: exportURL.path(percentEncoded: false)))
        
        let dbB = CotLocalDatabase(customURL: urlB)
        try dbB.importDatabase(from: exportURL)
        
        #expect(dbB.fetchKYCMemories(dimension: .taboos).first?.title == "禁止界面小字解释")
        #expect(dbB.fetchWatchlistStocks().contains(where: { $0.instrumentID == "hk:09988" }))
        #expect(dbB.fetchStoredPodcasts().first?.playbackPositionSec == 420)
        #expect(dbB.fetchFollowedFeeds().first?.title == "Paul Graham Essays")
        #expect(dbB.fetchFollowedCreators().first?.handle == "@karpathy")
        #expect(dbB.fetchButlerMessages().first?.content == "以后叫你阿白，关注 @karpathy")
    }
    
    
    // MARK: 2. Pane Board Intent Extraction & Persistence
    
    @Test func boardIntentExtractionForMarketPodcastAndNews() throws {
        // "恒生科技" converts cleanly into Market board focused on hk:HSTECH
        let marketState = PaneBoardIntentAnalyzer.initialState(for: .market, text: "最近想重点看下 恒生科技 的趋势和估值")
        #expect(marketState.kind == .market)
        #expect(marketState.selectedInstrumentID == "hk:HSTECH")
        #expect(marketState.dynamicTitle == "恒生科技指数")
        
        // Reflection/confusion text condenses into Podcast board search query & topic chips
        let podcastState = PaneBoardIntentAnalyzer.initialState(
            for: .podcast,
            text: "最近在想人生方向有点迷茫，焦虑怎么找到内驱力"
        )
        #expect(podcastState.kind == .podcast)
        #expect(!podcastState.query.isEmpty)
        #expect(!podcastState.topicChips.isEmpty)
        
        // Podcast URL preservation
        let podcastLinkState = PaneBoardIntentAnalyzer.initialState(
            for: .podcast,
            text: "https://www.xiaoyuzhoufm.com/episode/67b1234567890abcdef12345"
        )
        #expect(podcastLinkState.query.contains("xiaoyuzhoufm.com/episode/"))
        
        // News category routing
        let aiNewsState = PaneBoardIntentAnalyzer.initialState(for: .news, text: "Claude Code 与 Agent Workflow 最新进展")
        #expect(aiNewsState.newsCategoryRaw == NewsFeedCategory.ai.rawValue)
        
        // Pi JSON parsing resilience (including markdown fence stripping)
        let rawPiJSON = """
        ```json
        {"searchQueries":["内心秩序","抗焦虑"],"kycTitle":"关注内在稳定感","kycDetail":"对职业转型与意义感有深度思考"}
        ```
        """
        let refined = PaneBoardIntentAnalyzer.parseIntentJSON(rawPiJSON, kind: .podcast)
        #expect(refined?.primaryQuery == "内心秩序")
        #expect(refined?.additionalQueries == ["内心秩序", "抗焦虑"])
        #expect(refined?.kycDimension == .goals)
        #expect(refined?.kycTitle == "关注内在稳定感")
        
        // PersistedPaneTabItem Codable round-trip preserves boardState
        let item = PersistedPaneTabItem(
            title: "恒生科技指数",
            filePath: nil,
            syntax: "Plain Text",
            content: "",
            isPinned: false,
            paneIndex: 0,
            highlightsJSON: nil,
            databaseID: nil,
            boardState: marketState
        )
        let encoded = try JSONEncoder().encode(item)
        let decoded = try JSONDecoder().decode(PersistedPaneTabItem.self, from: encoded)
        #expect(decoded.boardState == marketState)
    }
    
    
    // MARK: 3. Butler Action Extraction & Agent Command Queue Takeover
    
    @Test func butlerActionsAndSQLiteCommandQueueExecution() async throws {
        let url = self.makeIsolatedDatabaseURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        
        let db = CotLocalDatabase(customURL: url)
        let memoryStore = CotMemoryStore(database: db)
        let coordinator = CotAgentCoordinator(database: db, memoryStore: memoryStore)
        
        // Extract <cot_actions> block cleanly from Butler response
        let rawReply = """
        好，已为你改名为「阿曜」并记住这条偏好。
        <cot_actions>
        [
          {"type":"rename_butler","name":"阿曜","nickname":"智囊"},
          {"type":"upsert_memory","dimension":"writingStyle","key":"concise_chinese","title":"极简中文输出","detail":"不写铺垫"},
          {"type":"follow_creator","platform":"x","handle":"karpathy","displayName":"Andrej Karpathy","why":"Systems AI"}
        ]
        </cot_actions>
        """
        let extracted = CotButlerManager.extractActions(from: rawReply)
        #expect(extracted.cleanText == "好，已为你改名为「阿曜」并记住这条偏好。")
        #expect(extracted.actions.count == 3)
        
        let receipts = await coordinator.execute(extracted.actions)
        #expect(receipts.count == 3)
        #expect(db.string(forKey: CotLocalDatabase.ConfigKey.butlerName) == "阿曜")
        #expect(db.string(forKey: CotLocalDatabase.ConfigKey.butlerNickname) == "智囊")
        #expect(memoryStore.memories.contains(where: { $0.factKey == "concise_chinese" && $0.dimension == .writingStyle }))
        #expect(memoryStore.creators.contains(where: { $0.handle == "@karpathy" }))
        
        // Enqueue external Pi command in SQLite agent_command_queue and drain
        let cmdID = db.enqueueAgentCommand(
            actionType: "watch_stock",
            payloadJSON: #"{"type":"watch_stock","query":"恒生科技","thesis":"Pi Agent 自动加入自选"}"#
        )
        #expect(cmdID > 0)
        #expect(db.fetchPendingAgentCommands().count == 1)
        
        await coordinator.drainCommandQueueNow()
        #expect(db.fetchPendingAgentCommands().isEmpty)
        let hasQueuedStock = memoryStore.stocks.contains {
            $0.instrumentID == "hk:HSTECH" && $0.thesisNote == "Pi Agent 自动加入自选"
        }
        #expect(hasQueuedStock)
        
        // Compiled KYC context contains both structured memories and assets
        let context = memoryStore.compiledKYCContext()
        #expect(context.contains("极简中文输出"))
        #expect(context.contains("@karpathy"))
        #expect(context.contains("恒生科技指数"))
    }
    
    
    // MARK: 4. Butler Multi-Session Lifecycle & Single-File Portability
    
    @Test func butlerSessionManagementAndCustomAvatarPortability() throws {
        let urlA = self.makeIsolatedDatabaseURL()
        let urlB = self.makeIsolatedDatabaseURL()
        let exportURL = self.makeIsolatedDatabaseURL().deletingLastPathComponent().appending(path: "butler_sessions.sqlite3")
        defer {
            try? FileManager.default.removeItem(at: urlA.deletingLastPathComponent())
            try? FileManager.default.removeItem(at: urlB.deletingLastPathComponent())
            try? FileManager.default.removeItem(at: exportURL)
        }
        
        let dbA = CotLocalDatabase(customURL: urlA)
        let storeA = CotMemoryStore(database: dbA)
        let manager = CotButlerManager(database: dbA, memoryStore: storeA)
        
        // Initial bootstrap creates first session
        let firstSessionID = manager.activeSessionID
        #expect(!firstSessionID.isEmpty)
        #expect(manager.sessions.count == 1)
        
        // Append first message into session 1 so startNewSession() allocates a second distinct session
        let msg1 = ButlerChatMessage(
            id: "s1-m1",
            sessionID: firstSessionID,
            role: "user",
            content: "追踪恒生科技和 Anthropic 协议更新",
            actionsJSON: "",
            createdAt: Date()
        )
        dbA.appendButlerMessage(msg1)
        manager.renameSession(firstSessionID, to: "市场与网关")
        manager.togglePinSession(firstSessionID)
        manager.reloadFromDatabase()
        #expect(manager.messages.count == 1)
        
        // Create session 2 & verify clean empty message isolation
        manager.startNewSession()
        let secondSessionID = manager.activeSessionID
        #expect(secondSessionID != firstSessionID)
        #expect(manager.sessions.count == 2)
        #expect(manager.messages.isEmpty)
        
        dbA.appendButlerMessage(ButlerChatMessage(
            id: "s2-m1",
            sessionID: secondSessionID,
            role: "assistant",
            content: "新会话已就绪",
            actionsJSON: "",
            createdAt: Date()
        ))
        manager.reloadFromDatabase()
        #expect(manager.messages.first?.content == "新会话已就绪")
        
        // Switch back to session 1 and verify session isolation
        manager.selectSession(firstSessionID)
        #expect(manager.messages.count == 1)
        #expect(manager.messages.first?.id == "s1-m1")
        
        // Custom avatar PNG persistence round-trip
        let sampleImage = NSImage(size: NSSize(width: 24, height: 24), flipped: false) { rect in
            NSColor.systemIndigo.setFill()
            rect.fill()
            return true
        }
        if let tiff = sampleImage.tiffRepresentation,
           let rep = NSBitmapImageRep(data: tiff),
           let pngData = rep.representation(using: .png, properties: [:])
        {
            manager.setCustomAvatarData(pngData)
            #expect(manager.customAvatarImage != nil)
        }
        
        // Export single SQLite file & import into DB B preserving sessions + session-scoped messages + custom avatar
        try dbA.exportDatabase(to: exportURL)
        let dbB = CotLocalDatabase(customURL: urlB)
        try dbB.importDatabase(from: exportURL)
        let importedManager = CotButlerManager(database: dbB, memoryStore: CotMemoryStore(database: dbB))
        #expect(importedManager.sessions.count == 2)
        #expect(importedManager.sessions.first(where: { $0.id == firstSessionID })?.title == "市场与网关")
        #expect(importedManager.sessions.first(where: { $0.id == firstSessionID })?.isPinned == true)
        #expect(dbB.fetchButlerMessages(sessionID: firstSessionID).first?.content == "追踪恒生科技和 Anthropic 协议更新")
        #expect(dbB.fetchButlerMessages(sessionID: secondSessionID).first?.content == "新会话已就绪")
        #expect(importedManager.customAvatarImage != nil)
        
        // Deleting session 2 leaves session 1 cleanly selected
        importedManager.deleteSession(secondSessionID)
        #expect(importedManager.sessions.count == 1)
        #expect(importedManager.activeSessionID == firstSessionID)
    }
    
    
    // MARK: 5. OpenCode Go Protocol Override & Butler Bot Routing
    
    @Test func openCodeGoProtocolOverrideAndButlerBotConfig() {
        #expect(AIBotID.allCases.first == .butler)
        #expect(AIBotID.butler.defaultPiToolProfile == .autonomousAgent)
        
        let responsesProfile = AIProvider.openCodeGo.makeProfile(protocolOverride: .openAIResponses)
        #expect(responsesProfile.endpoint == .openAIResponses)
        #expect(responsesProfile.baseURL == "https://opencode.ai/zen/go/v1")
        #expect(responsesProfile.provider == .openCodeGo)
        
        let anthropicProfile = AIProvider.openCodeGo.makeProfile(protocolOverride: .anthropicMessages)
        #expect(anthropicProfile.endpoint == .anthropicMessages)
        #expect(anthropicProfile.baseURL == "https://opencode.ai/zen/go")
        #expect(anthropicProfile.provider == .openCodeGo)
        
        let completionsProfile = AIProvider.openCodeGo.makeProfile(protocolOverride: .openAIChatCompletions)
        #expect(completionsProfile.endpoint == .openAIChatCompletions)
        #expect(completionsProfile.baseURL == "https://opencode.ai/zen/go/v1")
        #expect(completionsProfile.provider == .openCodeGo)
    }
    
    
    // MARK: 6. Read-Only Memory Star Map & Sunburst Geometry
    
    @Test func memoryStarMapConstellationAndSunburstRadialLayout() {
        let now = Date()
        let memories = [
            UserKYCMemoryRecord(
                id: "m1",
                dimension: .goals,
                factKey: "build_calm_tools",
                title: "打造安静高效的本地写作环境",
                detail: "单机 SQLite 为核心",
                confidence: 0.94,
                source: "user_explicit",
                evidenceRef: nil,
                isPinned: true,
                isArchived: false,
                reinforcementCount: 3,
                createdAt: now,
                updatedAt: now
            ),
            UserKYCMemoryRecord(
                id: "m2",
                dimension: .taboos,
                factKey: "no_small_captions",
                title: "界面禁止小字解释",
                detail: "用排版直接表达结构",
                confidence: 0.98,
                source: "user_explicit",
                evidenceRef: nil,
                isPinned: true,
                isArchived: false,
                reinforcementCount: 5,
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
            ).toRecord(sortOrder: 0, thesisNote: "Core watch", addedBy: "user")
        ]
        let built = MemoryStarMapSettingsView.buildConstellationClusters(
            memories: memories,
            stocks: stocks,
            podcasts: [],
            feeds: [],
            creators: []
        )
        #expect(built.clusters.count == 3)
        #expect(built.detailsByLeafID.count == 3)
        
        var counts: [String: Int] = [:]
        var leafIDs: [String: [String]] = [:]
        var clusterIDs: [String] = []
        for cluster in built.clusters {
            clusterIDs.append(cluster.id)
            counts[cluster.id] = cluster.leaves.count
            leafIDs[cluster.id] = cluster.leaves.map(\.id)
        }
        let starLayout = StarMapLayoutEngine.compute(
            clusterIDs: clusterIDs,
            leafCountsByCluster: counts,
            collapsedClusterIDs: [],
            leafIDsByCluster: leafIDs
        )
        #expect(starLayout.clusters.count == 3)
        #expect(starLayout.leaves.count == 3)
        
        // No two leaf footprints overlap in computed star map
        let fw = StarMapLayoutEngine.leafFootprint.width
        let fh = StarMapLayoutEngine.leafFootprint.height
        let leafRects = starLayout.leaves.map { CGRect(x: $0.worldPoint.x - fw * 0.5, y: $0.worldPoint.y - fh * 0.5, width: fw, height: fh) }
        for i in leafRects.indices {
            for j in (i + 1)..<leafRects.count {
                #expect(!leafRects[i].intersects(leafRects[j]))
            }
        }
        
        // Sunburst non-jumpy radial layout & gapless polar hit-testing
        let subA = EvalSunburstLayoutEngine.Node(id: "claude", name: "claude", value: 600, outputValue: 240, requests: 6)
        let subB = EvalSunburstLayoutEngine.Node(id: "gpt", name: "gpt", value: 400, outputValue: 160, requests: 4)
        let featureA = EvalSunburstLayoutEngine.Node(id: "Butler", name: "总管", value: 1000, outputValue: 400, requests: 10, children: [subA, subB])
        let featureB = EvalSunburstLayoutEngine.Node(id: "Ask", name: "问答", value: 500, outputValue: 200, requests: 5)
        let root = EvalSunburstLayoutEngine.Node(id: "root", name: "Total", value: 1500, outputValue: 600, requests: 15, children: [featureA, featureB])
        
        let sunburst = EvalSunburstLayoutEngine.radialLayout(focus: root)
        #expect(sunburst.arcs.contains(where: { !$0.isMark && $0.ring == .inner && $0.node.id == "Butler" }))
        #expect(sunburst.arcs.contains(where: { !$0.isMark && $0.ring == .outer && $0.node.id == "claude" }))
        #expect(sunburst.rows.count == 2)
        #expect(sunburst.hueMap["Butler"] != sunburst.hueMap["Ask"])
        
        // Polar sample inside first wedge (top-right inner ring & outer ring)
        let center = CGPoint(x: 120, y: 120)
        let radius: CGFloat = 110
        let innerSample = CGPoint(x: center.x + 12, y: center.y - 64)
        let outerSample = CGPoint(x: center.x + 16, y: center.y - 88)
        let hitInner = EvalSunburstLayoutEngine.gaplessHitTest(innerSample, center: center, radius: radius, arcs: sunburst.arcs)
        let hitOuter = EvalSunburstLayoutEngine.gaplessHitTest(outerSample, center: center, radius: radius, arcs: sunburst.arcs)
        #expect(hitInner?.ring == .inner)
        #expect(hitInner?.node.id == "Butler")
        #expect(hitOuter?.ring == .outer)
        #expect(hitOuter?.node.id == "claude")
    }
}
