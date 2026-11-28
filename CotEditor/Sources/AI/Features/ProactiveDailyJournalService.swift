//
//  ProactiveDailyJournalService.swift
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
import Observation

// MARK: - Pure Data Models & Deterministic Plain-Text Daily Journal Composer

/// A single lightweight tip emitted by the proactive agent and logged into today's plain-text daily journal.
nonisolated struct ProactiveTipItem: Codable, Equatable, Identifiable, Sendable {
    
    var id: String
    var dedupKey: String
    var category: String
    var headline: String
    var body: String
    var entryText: String
    var createdAt: Date
    var isRead: Bool = false
}


/// Snapshot of live workspace/user signals consumed by the deterministic journal composer.
nonisolated struct ProactiveJournalSignals: Sendable {
    
    var butlerName: String
    var todayChars: Int
    var writingStreakDays: Int
    var activeDocTitle: String?
    var watchlist: [WatchlistStockRecord]
    var quotes: [String: MarketQuoteSnapshot]
    var unreadPodcasts: [AgentPodcastRecommendation]
    var recentNews: [AIHotNewsItem]
    var memories: [UserKYCMemoryRecord]
    var pendingActions: [DocumentActionPrediction]
}


/// Persisted daily tip queue for a single calendar day.
nonisolated struct ProactiveDailyTipLedger: Codable, Equatable, Sendable {
    
    var dayKey: String
    var tips: [ProactiveTipItem]
}


/// Pure offline engine composing plain-text daily journal entries and deduplicated speech-bubble tips.
nonisolated enum ProactiveJournalComposer {
    
    static let journalGroupName = "总管随记"
    
    private static let clockFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm"
        return f
    }()
    
    private static let headingPrefixRegex = try! NSRegularExpression(pattern: #"(?m)^\s{0,3}#{1,6}\s+"#)
    private static let listBulletPrefixRegex = try! NSRegularExpression(pattern: #"(?m)^\s*[-*•]\s+"#)
    
    
    static func dayKey(for date: Date, calendar: Calendar = .current) -> String {
        let comps = calendar.dateComponents([.year, .month, .day], from: date)
        let y = comps.year ?? 2026
        let m = comps.month ?? 1
        let d = comps.day ?? 1
        return String(format: "%04d-%02d-%02d", y, m, d)
    }
    
    
    static func clockText(for date: Date) -> String {
        Self.clockFormatter.string(from: date)
    }
    
    
    static func dailyDocumentID(for date: Date, calendar: Calendar = .current) -> String {
        "doc:butler-daily-\(Self.dayKey(for: date, calendar: calendar))"
    }
    
    
    static func dailyDocumentTitle(for date: Date, butlerName: String, calendar: Calendar = .current) -> String {
        let cleanName = butlerName.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefix = cleanName.isEmpty ? "总管" : cleanName
        return "\(prefix)随记 · \(Self.dayKey(for: date, calendar: calendar))"
    }
    
    
    /// Clean plain-text header without any Markdown `#` or `*` markup.
    static func initialHeader(for date: Date, butlerName: String, calendar: Calendar = .current) -> String {
        let title = Self.dailyDocumentTitle(for: date, butlerName: butlerName, calendar: calendar)
        return "\(title)\n\n"
    }
    
    
    /// Strips Markdown syntax clutter (`#`, `*`, `**`, `` ` ``, leading `- `) to keep notes clean plain text.
    static func sanitizePlainText(_ raw: String) -> String {
        var text = raw.replacingOccurrences(of: "\r\n", with: "\n")
        let fullRange = NSRange(text.startIndex..<text.endIndex, in: text)
        text = Self.headingPrefixRegex.stringByReplacingMatches(in: text, range: fullRange, withTemplate: "")
        let afterHeading = NSRange(text.startIndex..<text.endIndex, in: text)
        text = Self.listBulletPrefixRegex.stringByReplacingMatches(in: text, range: afterHeading, withTemplate: "")
        text = text
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "__", with: "")
            .replacingOccurrences(of: "*", with: "")
            .replacingOccurrences(of: "`", with: "")
            .replacingOccurrences(of: "#", with: "")
        let lines = text
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
        var cleaned: [String] = []
        var previousBlank = false
        for line in lines {
            if line.isEmpty {
                if !previousBlank && !cleaned.isEmpty {
                    cleaned.append("")
                }
                previousBlank = true
            } else {
                cleaned.append(line)
                previousBlank = false
            }
        }
        return cleaned.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    
    /// Appends a clean plain-text timestamped section to today's journal content.
    static func appendEntry(
        tip: ProactiveTipItem,
        to existingContent: String,
        date: Date,
        butlerName: String,
        calendar: Calendar = .current
    ) -> String {
        let base = existingContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? Self.initialHeader(for: date, butlerName: butlerName, calendar: calendar)
            : existingContent.trimmingCharacters(in: .newlines) + "\n\n"
        let clock = Self.clockText(for: tip.createdAt)
        let cleanHeadline = Self.sanitizePlainText(tip.headline)
        let cleanBody = Self.sanitizePlainText(tip.entryText)
        let block = "[\(clock)] \(tip.category) · \(cleanHeadline)\n\(cleanBody)"
        return base + block + "\n"
    }
    
    
    /// Synthesizes the next non-duplicate proactive observation & concise speech-bubble tip from live signals.
    static func synthesizeNextTip(
        signals: ProactiveJournalSignals,
        seenKeys: Set<String>,
        now: Date = Date()
    ) -> ProactiveTipItem? {
        let candidates = Self.buildCandidates(signals: signals, now: now)
        if let fresh = candidates.first(where: { !seenKeys.contains($0.dedupKey) }) {
            return fresh
        }
        return Self.buildPeriodicCheckIn(signals: signals, seenCount: seenKeys.count, now: now)
    }
    
    
    private static func buildCandidates(
        signals: ProactiveJournalSignals,
        now: Date
    ) -> [ProactiveTipItem] {
        var items: [ProactiveTipItem] = []
        
        if let podcast = signals.unreadPodcasts.first {
            let key = "podcast:\(podcast.id)"
            let body = "已离线缓存，话题：\(podcast.topic)"
            let plain = "节目：\(podcast.episodeTitle)\n主题：\(podcast.topic)\n音频已离线缓存，休息或通勤时可以随时收听。"
            items.append(ProactiveTipItem(
                id: UUID().uuidString,
                dedupKey: key,
                category: "播客就绪",
                headline: String(podcast.episodeTitle.prefix(26)),
                body: String(body.prefix(48)),
                entryText: plain,
                createdAt: now
            ))
        }
        
        if let action = signals.pendingActions.first(where: { !$0.action.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            let cleanTitle = Self.sanitizePlainText(action.action)
            let key = "action:\(cleanTitle.prefix(24))"
            let sourceNote = Self.sanitizePlainText(action.sourceDocumentTitle)
            let body = sourceNote.isEmpty ? "已在今日随记中记下跟进要点" : "来自《\(sourceNote)》，已记入今日随记"
            let plain = sourceNote.isEmpty
                ? "待跟进：\(cleanTitle)\n可以先用 15 分钟推进最关键的一小步。"
                : "待跟进：\(cleanTitle)\n来源文档：\(sourceNote)\n可以先用 15 分钟推进最关键的一小步。"
            items.append(ProactiveTipItem(
                id: UUID().uuidString,
                dedupKey: key,
                category: "待办提醒",
                headline: String(cleanTitle.prefix(26)),
                body: String(body.prefix(48)),
                entryText: plain,
                createdAt: now
            ))
        }
        
        if !signals.watchlist.isEmpty {
            let picked = Array(signals.watchlist.prefix(3))
            let summaryLines: [String] = picked.map { stock in
                let price = signals.quotes[stock.instrumentID]?.lastPrice ?? stock.lastPrice
                let pct = signals.quotes[stock.instrumentID]?.changePercent ?? stock.lastChangePct
                if let price, let pct {
                    let sign = pct >= 0 ? "+" : ""
                    return "\(stock.name) (\(stock.symbol))  \(String(format: "%.2f", price)) (\(sign)\(String(format: "%.2f%%", pct)))"
                }
                return "\(stock.name) (\(stock.symbol))  已纳入自选观察"
            }
            let firstStock = picked[0]
            let pct = signals.quotes[firstStock.instrumentID]?.changePercent ?? firstStock.lastChangePct
            let headline = picked.map(\.name).prefix(2).joined(separator: " / ")
            let body: String = if let pct {
                "\(firstStock.name) \(pct >= 0 ? "+" : "")\(String(format: "%.2f%%", pct))，盘面记录已更新"
            } else {
                "已同步 \(picked.count) 只关注标的动态"
            }
            items.append(ProactiveTipItem(
                id: UUID().uuidString,
                dedupKey: "market:\(picked.map(\.instrumentID).joined(separator: ","))",
                category: "行情速览",
                headline: String("\(headline) 动态".prefix(26)),
                body: String(body.prefix(48)),
                entryText: summaryLines.joined(separator: "\n"),
                createdAt: now
            ))
        }
        
        if let news = signals.recentNews.first {
            let key = "news:\(news.id.prefix(24))"
            let pub = news.displayPublisherLabel
            let summary = Self.sanitizePlainText(news.summary ?? "")
            let plain = summary.isEmpty
                ? "标题：\(news.title)\n来源：\(pub)"
                : "标题：\(news.title)\n来源：\(pub)\n摘要：\(summary)"
            items.append(ProactiveTipItem(
                id: UUID().uuidString,
                dedupKey: key,
                category: "热点观察",
                headline: String(news.title.prefix(26)),
                body: "\(pub) · 已摘录到今日随记",
                entryText: plain,
                createdAt: now
            ))
        }
        
        if signals.todayChars > 0 || (signals.activeDocTitle?.isEmpty == false) {
            let docTitle = Self.sanitizePlainText(signals.activeDocTitle ?? "")
            let headline = signals.todayChars > 0
                ? "今日已写 \(signals.todayChars.formatted()) 字"
                : "正在推进《\(docTitle.prefix(16))》"
            let body = signals.writingStreakDays > 1
                ? "连续创作第 \(signals.writingStreakDays) 天，节奏保持得不错"
                : "已记录当前写作进展，随时可回头复盘"
            let plain = docTitle.isEmpty
                ? "今日字数：\(signals.todayChars.formatted()) 字（连续 \(max(1, signals.writingStreakDays)) 天）\n写完这一段记得抬头歇一分钟，保持手感。"
                : "今日字数：\(signals.todayChars.formatted()) 字（连续 \(max(1, signals.writingStreakDays)) 天）\n当前文档：\(docTitle)\n写完这一段记得抬头歇一分钟，保持手感。"
            items.append(ProactiveTipItem(
                id: UUID().uuidString,
                dedupKey: "writing:\(signals.todayChars / 300):\(docTitle.prefix(16))",
                category: "写作节奏",
                headline: String(headline.prefix(26)),
                body: String(body.prefix(48)),
                entryText: plain,
                createdAt: now
            ))
        }
        
        if let memory = signals.memories.first(where: { !$0.isArchived }) {
            let key = "memory:\(memory.id)"
            let detail = Self.sanitizePlainText(memory.detail)
            let plain = "长期关注：\(memory.title)（\(memory.dimension.label)）\n\(detail.isEmpty ? "持续沉淀相关资料与思考。" : detail)"
            items.append(ProactiveTipItem(
                id: UUID().uuidString,
                dedupKey: key,
                category: "灵感笔记",
                headline: String(memory.title.prefix(26)),
                body: "结合长期记忆记下了一条延伸思考",
                entryText: plain,
                createdAt: now
            ))
        }
        
        return items
    }
    
    
    private static func buildPeriodicCheckIn(
        signals: ProactiveJournalSignals,
        seenCount: Int,
        now: Date
    ) -> ProactiveTipItem {
        let clock = Self.clockText(for: now)
        let activeDoc = Self.sanitizePlainText(signals.activeDocTitle ?? "")
        let headline = activeDoc.isEmpty ? "今日阶段小结" : "《\(activeDoc.prefix(14))》进展记录"
        let body = signals.todayChars > 0
            ? "累计 \(signals.todayChars.formatted()) 字，刚记下一条工作脉络"
            : "刚更新了今日随记，点开看看"
        let plain = activeDoc.isEmpty
            ? "时间节点：\(clock)，今日输出 \(signals.todayChars.formatted()) 字。\n重要想法随时留档。"
            : "时间节点：\(clock)，今日输出 \(signals.todayChars.formatted()) 字。\n关注文档：\(activeDoc)。"
        return ProactiveTipItem(
            id: UUID().uuidString,
            dedupKey: "checkin:\(seenCount):\(clock)",
            category: "总管随记",
            headline: String(headline.prefix(26)),
            body: String(body.prefix(48)),
            entryText: plain,
            createdAt: now
        )
    }
}


// MARK: - Stateful Proactive Daily Journal Service

/// Allocates one plain-text daily journal document per calendar day for the proactive agent,
/// appends periodic observations in the background, and emits speech-bubble tips from the Butler toolbar icon.
@MainActor @Observable
final class ProactiveDailyJournalService {
    
    static let shared = ProactiveDailyJournalService()
    
    private let database: CotLocalDatabase
    @ObservationIgnored private var schedulerTask: Task<Void, Never>?
    @ObservationIgnored var onTipPublished: ((ProactiveTipItem) -> Void)?
    
    var tipsEnabled: Bool {
        didSet {
            guard self.tipsEnabled != oldValue else { return }
            self.database.set(self.tipsEnabled ? "true" : "false", forKey: CotLocalDatabase.ConfigKey.proactiveMenuBarTipsEnabled)
        }
    }
    
    private(set) var activeDayKey: String = ""
    private(set) var todayDocumentID: String = ""
    private(set) var todayDocumentTitle: String = ""
    private(set) var todayTips: [ProactiveTipItem] = []
    private(set) var activeFloatingTip: ProactiveTipItem?
    private(set) var revision: Int = 0
    
    var unreadCount: Int {
        self.todayTips.filter { !$0.isRead }.count
    }
    
    
    init(database: CotLocalDatabase = .shared) {
        self.database = database
        let rawEnabled = database.string(forKey: CotLocalDatabase.ConfigKey.proactiveMenuBarTipsEnabled, default: "true")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        self.tipsEnabled = (rawEnabled != "false" && rawEnabled != "0")
        self.reloadLedger(for: Date())
    }
    
    
    func reloadFromDatabase() {
        let rawEnabled = self.database.string(forKey: CotLocalDatabase.ConfigKey.proactiveMenuBarTipsEnabled, default: "true")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        self.tipsEnabled = (rawEnabled != "false" && rawEnabled != "0")
        self.activeFloatingTip = nil
        self.reloadLedger(for: Date())
        self.revision &+= 1
    }
    
    
    isolated deinit {
        self.schedulerTask?.cancel()
    }
    
    
    // MARK: Daily Document Allocation & Updates
    
    /// Ensures today's dedicated plain-text daily document exists in `CotLocalDatabase` and returns it.
    @discardableResult
    func ensureTodayDocument(now: Date = Date(), butlerName: String? = nil) -> StoredDocumentRecord {
        let dayKey = ProactiveJournalComposer.dayKey(for: now)
        if dayKey != self.activeDayKey {
            self.reloadLedger(for: now)
        }
        let resolvedName = butlerName ?? self.resolvedButlerName()
        let docID = ProactiveJournalComposer.dailyDocumentID(for: now)
        let title = ProactiveJournalComposer.dailyDocumentTitle(for: now, butlerName: resolvedName)
        self.todayDocumentID = docID
        self.todayDocumentTitle = title
        
        if let existing = self.database.documents.first(where: { $0.id == docID && $0.deletedAt == nil }) {
            if existing.syntax != SyntaxName.none {
                let cleaned = ProactiveJournalComposer.sanitizePlainText(existing.content)
                let migratedContent = cleaned.isEmpty ? ProactiveJournalComposer.initialHeader(for: now, butlerName: resolvedName) : cleaned + "\n"
                self.database.saveDocument(
                    id: existing.id,
                    title: existing.title,
                    filePath: existing.filePath,
                    syntax: SyntaxName.none,
                    content: migratedContent,
                    groupName: existing.groupName.isEmpty ? ProactiveJournalComposer.journalGroupName : existing.groupName
                )
                return self.database.documents.first(where: { $0.id == docID }) ?? existing
            }
            return existing
        }
        
        let header = ProactiveJournalComposer.initialHeader(for: now, butlerName: resolvedName)
        self.database.saveDocument(
            id: docID,
            title: title,
            filePath: nil,
            syntax: SyntaxName.none,
            content: header,
            groupName: ProactiveJournalComposer.journalGroupName
        )
        return self.database.documents.first(where: { $0.id == docID }) ?? StoredDocumentRecord(
            id: docID,
            title: title,
            filePath: nil,
            syntax: SyntaxName.none,
            content: header,
            highlightsJSON: "[]",
            updatedAt: now,
            groupName: ProactiveJournalComposer.journalGroupName
        )
    }
    
    
    /// Synthesizes one proactive plain-text note, appends it into today's daily journal document,
    /// syncs any open editor tab for that document, and optionally triggers the Butler toolbar speech bubble.
    @discardableResult
    func recordProactiveNote(
        signals explicitSignals: ProactiveJournalSignals? = nil,
        now: Date = Date(),
        allowRemoteAI: Bool = false,
        showFloatingTip: Bool = true
    ) async -> ProactiveTipItem? {
        let signals = explicitSignals ?? self.collectLiveSignals(now: now)
        let doc = self.ensureTodayDocument(now: now, butlerName: signals.butlerName)
        let seenKeys = Set(self.todayTips.map(\.dedupKey))
        
        guard var tip = ProactiveJournalComposer.synthesizeNextTip(signals: signals, seenKeys: seenKeys, now: now) else {
            return nil
        }
        
        if allowRemoteAI, AIService.shared.isConfigured {
            if let polished = await self.enrichTipWithAI(tip: tip, signals: signals) {
                tip = polished
            }
        }
        
        let updatedContent = ProactiveJournalComposer.appendEntry(
            tip: tip,
            to: doc.content,
            date: now,
            butlerName: signals.butlerName
        )
        
        self.database.saveDocument(
            id: doc.id,
            title: doc.title,
            filePath: doc.filePath,
            syntax: SyntaxName.none,
            content: updatedContent,
            groupName: doc.groupName.isEmpty ? ProactiveJournalComposer.journalGroupName : doc.groupName
        )
        self.syncLiveOpenJournalDocument(id: doc.id, content: updatedContent)
        
        self.todayTips.insert(tip, at: 0)
        if self.todayTips.count > 24 {
            self.todayTips = Array(self.todayTips.prefix(24))
        }
        self.activeFloatingTip = tip
        self.persistLedger()
        self.revision &+= 1
        
        if showFloatingTip && self.tipsEnabled {
            self.onTipPublished?(tip)
        }
        return tip
    }
    
    
    /// Publishes an external tip (such as the evening daily report digest) to the unread badge and floating bubble.
    func publishExternalTip(_ tip: ProactiveTipItem, showFloatingTip: Bool = true) {
        guard !self.todayTips.contains(where: { $0.dedupKey == tip.dedupKey }) else { return }
        self.todayTips.insert(tip, at: 0)
        if self.todayTips.count > 24 {
            self.todayTips = Array(self.todayTips.prefix(24))
        }
        self.activeFloatingTip = tip
        self.persistLedger()
        self.revision &+= 1
        if showFloatingTip && self.tipsEnabled {
            self.onTipPublished?(tip)
        }
    }
    
    
    /// Opens today's daily plain-text journal document inside CotEditor, marks tips read, and dismisses active bubbles.
    func openTodayJournalWindow(preferredWindow: NSWindow? = nil, now: Date = Date()) {
        let record = self.ensureTodayDocument(now: now)
        self.markAllRead()
        self.dismissFloatingTip()
        
        if let wc = self.resolveDocumentWindowController(preferredWindow: preferredWindow),
           let docVC = wc.workspaceContentViewController?.documentViewController
        {
            docVC.openStoredDocumentRecord(record)
            wc.workspaceContentViewController?.hideInWindowCenter()
            wc.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        
        if let controller = NSDocumentController.shared as? DocumentController {
            _ = try? controller.openUntitledDocumentAndDisplay(true)
            if let wc = self.resolveDocumentWindowController(preferredWindow: nil),
               let docVC = wc.workspaceContentViewController?.documentViewController
            {
                docVC.openStoredDocumentRecord(record)
                wc.workspaceContentViewController?.hideInWindowCenter()
                wc.window?.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
            }
        }
    }
    
    
    func markAllRead() {
        var changed = false
        for idx in self.todayTips.indices where !self.todayTips[idx].isRead {
            self.todayTips[idx].isRead = true
            changed = true
        }
        if changed {
            self.persistLedger()
            self.revision &+= 1
        }
    }
    
    
    func dismissFloatingTip() {
        if self.activeFloatingTip != nil {
            self.activeFloatingTip = nil
            self.revision &+= 1
        }
    }
    
    
    // MARK: Periodic Background Scheduler
    
    func startBackgroundScheduler() {
        guard !CotLocalDatabase.isRunningUnitTests else { return }
        guard self.schedulerTask == nil else { return }
        
        self.schedulerTask = Task { @MainActor [weak self] in
            // Initial gentle check shortly after launch
            try? await Task.sleep(for: .seconds(18))
            guard !Task.isCancelled, let self else { return }
            _ = self.ensureTodayDocument()
            if self.todayTips.isEmpty {
                _ = await self.recordProactiveNote(allowRemoteAI: false, showFloatingTip: self.tipsEnabled)
            }
            
            // Periodic observation every 22 minutes
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1320))
                guard !Task.isCancelled else { break }
                guard self.tipsEnabled else { continue }
                _ = await self.recordProactiveNote(allowRemoteAI: true, showFloatingTip: true)
            }
        }
    }
    
    
    // MARK: Private Helpers
    
    private func resolvedButlerName() -> String {
        let saved = self.database.string(forKey: CotLocalDatabase.ConfigKey.butlerName, default: "曜")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return saved.isEmpty ? "曜" : saved
    }
    
    
    private func collectLiveSignals(now: Date) -> ProactiveJournalSignals {
        let analytics = AnalyticsManager.shared
        let snap = CotAgentCoordinator.shared.lastWorkspaceSnapshot
        let activeDoc = snap?.activeDocumentTitle
        let ignoreSelfDoc = (activeDoc == self.todayDocumentTitle) ? nil : activeDoc
        return ProactiveJournalSignals(
            butlerName: self.resolvedButlerName(),
            todayChars: analytics.todayStats.typedChars + analytics.todayStats.aiCompletedChars,
            writingStreakDays: analytics.writingStreak(referenceDate: now),
            activeDocTitle: ignoreSelfDoc,
            watchlist: CotMarketService.shared.watchlist,
            quotes: CotMarketService.shared.quotes,
            unreadPodcasts: CotPodcastService.shared.unreadReminders,
            recentNews: AIHotNewsService.shared.items,
            memories: CotMemoryStore.shared.memories,
            pendingActions: analytics.actionPredictions
        )
    }
    
    
    private func enrichTipWithAI(tip: ProactiveTipItem, signals: ProactiveJournalSignals) async -> ProactiveTipItem? {
        let system = """
        你是 CotEditor 的主动式总管助手（\(signals.butlerName)），每天在一篇纯文本随记里给用户写简短观察与提醒。
        请润色成自然、温和、克制的纯文本条目，只返回严格 JSON：
        {"headline":"14字以内简短标题","body":"26字以内气泡一句话提示","entryText":"1-2句干净纯文本内容"}
        严禁使用任何 #、*、**、-、反引号等 Markdown 符号，严禁使用表情符号。
        """
        let user = "类别：\(tip.category)\n原标题：\(tip.headline)\n原内容：\n\(tip.entryText)"
        do {
            let raw = try await AIService.shared.chat(
                [.system(system), .user(user)],
                analyticsFeature: "proactiveDailyJournal"
            )
            guard let start = raw.firstIndex(of: "{"), let end = raw.lastIndex(of: "}"), start < end else {
                return nil
            }
            struct Enriched: Decodable {
                var headline: String?
                var body: String?
                var entryText: String?
            }
            let data = Data(raw[start...end].utf8)
            let decoded = try JSONDecoder().decode(Enriched.self, from: data)
            var next = tip
            if let h = decoded.headline.map(ProactiveJournalComposer.sanitizePlainText), !h.isEmpty {
                next.headline = String(h.prefix(24))
            }
            if let b = decoded.body.map(ProactiveJournalComposer.sanitizePlainText), !b.isEmpty {
                next.body = String(b.prefix(46))
            }
            if let txt = decoded.entryText.map(ProactiveJournalComposer.sanitizePlainText), !txt.isEmpty {
                next.entryText = txt
            }
            return next
        } catch {
            return nil
        }
    }
    
    
    private func syncLiveOpenJournalDocument(id: String, content: String) {
        guard !CotLocalDatabase.isRunningUnitTests else { return }
        let cleanID = id.hasPrefix("doc:") ? String(id.dropFirst(4)) : id
        for wc in NSApp?.orderedWindows.compactMap({ $0.windowController as? DocumentWindowController }) ?? [] {
            guard let docVC = wc.documentViewController else { continue }
            for pane in docVC.editorViewControllers {
                for tab in pane.tabs {
                    let doc = tab.document
                    let docClean = doc.databaseDocumentID.hasPrefix("doc:")
                        ? String(doc.databaseDocumentID.dropFirst(4))
                        : doc.databaseDocumentID
                    guard docClean == cleanID || doc.databaseDocumentID == id else { continue }
                    guard !doc.needsUserSavePrompt else { continue }
                    if doc.syntaxName != SyntaxName.none {
                        doc.setSyntax(name: SyntaxName.none)
                    }
                    doc.textStorage.replaceCharacters(
                        in: NSRange(location: 0, length: doc.textStorage.length),
                        with: content
                    )
                    doc.updateChangeCount(.changeCleared)
                    doc.hasUncommittedChanges = false
                    doc.isDraft = false
                }
            }
        }
    }
    
    
    private func resolveDocumentWindowController(preferredWindow: NSWindow?) -> DocumentWindowController? {
        if let wc = preferredWindow?.windowController as? DocumentWindowController {
            return wc
        }
        if let wc = NSApp?.mainWindow?.windowController as? DocumentWindowController {
            return wc
        }
        return NSApp?.orderedWindows
            .compactMap { $0.windowController as? DocumentWindowController }
            .first
    }
    
    
    private func reloadLedger(for date: Date) {
        let key = ProactiveJournalComposer.dayKey(for: date)
        self.activeDayKey = key
        let butlerName = self.resolvedButlerName()
        self.todayDocumentID = ProactiveJournalComposer.dailyDocumentID(for: date)
        self.todayDocumentTitle = ProactiveJournalComposer.dailyDocumentTitle(for: date, butlerName: butlerName)
        
        let raw = self.database.string(forKey: CotLocalDatabase.ConfigKey.proactiveDailyTipsStateJSON)
        if !raw.isEmpty,
           let data = raw.data(using: .utf8),
           let ledger = try? JSONDecoder().decode(ProactiveDailyTipLedger.self, from: data),
           ledger.dayKey == key
        {
            self.todayTips = ledger.tips
        } else {
            self.todayTips = []
        }
    }
    
    
    private func persistLedger() {
        let ledger = ProactiveDailyTipLedger(dayKey: self.activeDayKey, tips: self.todayTips)
        if let data = try? JSONEncoder().encode(ledger),
           let json = String(data: data, encoding: .utf8)
        {
            self.database.set(json, forKey: CotLocalDatabase.ConfigKey.proactiveDailyTipsStateJSON)
        }
    }
}
