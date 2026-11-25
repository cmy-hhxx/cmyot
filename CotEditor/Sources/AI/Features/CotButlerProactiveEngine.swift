//
//  CotButlerProactiveEngine.swift
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

import Foundation
import Observation

/// Proactive Super-Agent suggestion card surfaced on the Butler home stage (max 3 per DeepSeek attention-capping).
nonisolated struct ButlerProactiveCardPayload: Codable, Equatable, Identifiable, Sendable {
    
    var id: String
    var badge: String
    var title: String
    var subtitle: String
    var prompt: String
    /// `"market" | "podcast" | "news" | "memory" | "sparkle"`
    var icon: String
}


/// Background Worker telemetry strip item (watchdog visibility for async agent jobs such as podcast downloads).
nonisolated struct ButlerBackgroundWorkerPayload: Codable, Equatable, Identifiable, Sendable {
    
    var id: String
    var title: String
    /// `"running" | "done" | "error"`
    var status: String
    var detail: String?
    var actionBoard: String?
    var actionQuery: String?
    var updatedAtMs: Double
}


/// Coordinates DeepSeek Super-Agent–inspired proactive task cards, deep personal context assembly,
/// and background worker status visibility for CotButler.
@MainActor @Observable
final class CotButlerProactiveEngine {
    
    static let shared = CotButlerProactiveEngine()
    
    private(set) var workers: [ButlerBackgroundWorkerPayload] = []
    private(set) var dismissedCardIDs: Set<String> = []
    private(set) var revision: Int = 0
    
    
    func startWorker(
        id: String,
        title: String,
        detail: String? = nil,
        actionBoard: String? = nil,
        actionQuery: String? = nil
    ) {
        let item = ButlerBackgroundWorkerPayload(
            id: id,
            title: title,
            status: "running",
            detail: detail,
            actionBoard: actionBoard,
            actionQuery: actionQuery,
            updatedAtMs: Date().timeIntervalSince1970 * 1000
        )
        self.workers.removeAll { $0.id == id }
        self.workers.insert(item, at: 0)
        if self.workers.count > 4 {
            self.workers = Array(self.workers.prefix(4))
        }
        self.revision &+= 1
    }
    
    
    func finishWorker(
        id: String,
        title: String,
        detail: String? = nil,
        isError: Bool = false,
        actionBoard: String? = nil,
        actionQuery: String? = nil
    ) {
        let item = ButlerBackgroundWorkerPayload(
            id: id,
            title: title,
            status: isError ? "error" : "done",
            detail: detail,
            actionBoard: actionBoard,
            actionQuery: actionQuery,
            updatedAtMs: Date().timeIntervalSince1970 * 1000
        )
        if let idx = self.workers.firstIndex(where: { $0.id == id }) {
            self.workers[idx] = item
        } else {
            self.workers.insert(item, at: 0)
        }
        self.revision &+= 1
    }
    
    
    func dismissWorker(id: String) {
        self.workers.removeAll { $0.id == id }
        self.revision &+= 1
    }
    
    
    func dismissCard(id: String) {
        self.dismissedCardIDs.insert(id)
        self.revision &+= 1
    }
    
    
    /// Generates at most 3 high-signal proactive task cards from the user's live focus,
    /// memories, downloaded podcast queue, and news stream.
    func buildProactiveCards(
        watchlist: [WatchlistStockRecord],
        quotes: [String: MarketQuoteSnapshot],
        memories: [UserKYCMemoryRecord],
        unreadPodcasts: [AgentPodcastRecommendation],
        recentNews: [AIHotNewsItem]
    ) -> [ButlerProactiveCardPayload] {
        var cards: [ButlerProactiveCardPayload] = []
        
        // 1. Unread Bot-curated podcast reminder (highest urgency if present)
        if let unread = unreadPodcasts.first {
            let id = "proactive-podcast-\(unread.id)"
            if !self.dismissedCardIDs.contains(id) {
                cards.append(ButlerProactiveCardPayload(
                    id: id,
                    badge: AppLanguage.text("播客已就绪", en: "Podcast Ready"),
                    title: unread.episodeTitle,
                    subtitle: AppLanguage.text("已为你离线缓存 · \(unread.topic)", en: "Downloaded · \(unread.topic)"),
                    prompt: AppLanguage.text("帮我打开播客看板并简介这期《\(unread.episodeTitle)》的核心看点", en: "Open podcast board and brief \(unread.episodeTitle)"),
                    icon: "podcast"
                ))
            }
        }
        
        // 2. Focus Watchlist card (prioritizing 三安光电 & 京东方A)
        let focusStocks = watchlist.filter { $0.instrumentID == "sh:600703" || $0.instrumentID == "sz:000725" }
        let chosenStocks = focusStocks.isEmpty ? Array(watchlist.prefix(2)) : focusStocks
        if !chosenStocks.isEmpty {
            let id = "proactive-market-focus"
            if !self.dismissedCardIDs.contains(id) {
                let names = chosenStocks.map(\.name).joined(separator: " / ")
                let subtitleParts: [String] = chosenStocks.map { stock in
                    let pct = quotes[stock.instrumentID]?.changePercent ?? stock.lastChangePct
                    if let pct {
                        let sign = pct >= 0 ? "+" : ""
                        return "\(stock.name) \(sign)\(String(format: "%.2f%%", pct))"
                    }
                    return "\(stock.name) (\(stock.symbol))"
                }
                cards.append(ButlerProactiveCardPayload(
                    id: id,
                    badge: AppLanguage.text("重点关注行情", en: "Watchlist Focus"),
                    title: AppLanguage.text("查看 \(names) 最新盘面", en: "Check \(names) Live Quotes"),
                    subtitle: subtitleParts.joined(separator: " · "),
                    prompt: AppLanguage.text("帮我查一下 \(names) 的最新行情与近期K线走势，并分析关键支撑和看点", en: "Check live quote and recent K-line trend for \(names)"),
                    icon: "market"
                ))
            }
        }
        
        // 3. Personalized Podcast Discovery or News Brief from KYC Memory
        if let firstNews = recentNews.first, cards.count < 3 {
            let id = "proactive-news-\(firstNews.id.prefix(16))"
            if !self.dismissedCardIDs.contains(id) {
                cards.append(ButlerProactiveCardPayload(
                    id: id,
                    badge: AppLanguage.text("今日热点速递", en: "News Pulse"),
                    title: firstNews.title,
                    subtitle: firstNews.displayPublisherLabel,
                    prompt: AppLanguage.text("用 3 条要点帮我提炼这篇资讯的核心价值：《\(firstNews.title)》", en: "Summarize \(firstNews.title) in 3 bullets"),
                    icon: "news"
                ))
            }
        }
        
        if cards.count < 3 {
            let topicSeed = memories.first(where: { !$0.isArchived })?.title ?? "大模型训练与 AI 系统架构"
            let id = "proactive-podcast-discover"
            if !self.dismissedCardIDs.contains(id) {
                cards.append(ButlerProactiveCardPayload(
                    id: id,
                    badge: AppLanguage.text("深度知识收听", en: "Deep Listening"),
                    title: AppLanguage.text("让我帮你找并下载深度播客", en: "Find & Download a Podcast"),
                    subtitle: AppLanguage.text("结合兴趣：\(topicSeed)", en: "Based on: \(topicSeed)"),
                    prompt: AppLanguage.text("帮我找一期关于「\(topicSeed)」的高质量中文或英文播客，下载进来后提醒我听", en: "Find and download a high-quality podcast about \(topicSeed) and remind me"),
                    icon: "sparkle"
                ))
            }
        }
        
        return Array(cards.prefix(3))
    }
    
    
    /// Builds a concise, structured personal-understanding block injected into Butler turns
    /// so Butler inherently knows the user's memories, holdings, podcast queue, and reading focus.
    func buildDeepPersonalContextSummary(
        watchlist: [WatchlistStockRecord],
        quotes: [String: MarketQuoteSnapshot],
        memories: [UserKYCMemoryRecord],
        unreadPodcasts: [AgentPodcastRecommendation],
        browsingHistory: [NewsBrowsingHistoryItem],
        activeDocTitle: String?
    ) -> String {
        var sections: [String] = []
        
        let pinnedMemories = memories.filter { !$0.isArchived }.prefix(8)
        if !pinnedMemories.isEmpty {
            let lines = pinnedMemories.map { "• [\($0.dimension.label)] \($0.title): \($0.detail)" }.joined(separator: "\n")
            sections.append("【长期偏好与记忆】\n\(lines)")
        }
        
        if !watchlist.isEmpty {
            let lines = watchlist.prefix(6).map { s in
                let pct = quotes[s.instrumentID]?.changePercent ?? s.lastChangePct
                let price = quotes[s.instrumentID]?.lastPrice ?? s.lastPrice
                let quoteText: String = if let price, let pct {
                    String(format: "现价 %.2f (%@%.2f%%)", price, pct >= 0 ? "+" : "", pct)
                } else {
                    "代码 \(s.symbol)"
                }
                return "• \(s.name) (\(s.symbol)): \(quoteText)"
            }.joined(separator: "\n")
            sections.append("【关注标的】\n\(lines)")
        }
        
        if !unreadPodcasts.isEmpty {
            let lines = unreadPodcasts.prefix(3).map { "• \($0.episodeTitle)（话题：\($0.topic)）" }.joined(separator: "\n")
            sections.append("【待收听离线播客】\n\(lines)")
        }
        
        if !browsingHistory.isEmpty {
            let titles = browsingHistory.prefix(4).map(\.item.title).joined(separator: "；")
            sections.append("【近期资讯浏览】\(titles)")
        }
        
        if let activeDocTitle, !activeDocTitle.isEmpty {
            sections.append("【当前编辑器文档】\(activeDocTitle)")
        }
        
        return sections.joined(separator: "\n\n")
    }
}
