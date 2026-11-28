//
//  CotProactiveDispatchService.swift
//
//  CotEditor
//  https://coteditor.com
//

import Foundation
import Observation

/// User-configurable global proactive messaging & Do-Not-Disturb preferences.
nonisolated struct ProactiveDispatchSettings: Equatable, Sendable {
    var enabled: Bool = true
    var dndEnabled: Bool = true
    var dndStartHour: Int = 23
    var dndEndHour: Int = 8
}


/// Daily per-bot send counter & last-send timestamps persisted in `CotLocalDatabase`.
nonisolated struct ProactiveCooldownLedger: Codable, Equatable, Sendable {
    var dayKey: String = ""
    var sentCountByBot: [String: Int] = [:]
    var lastSentAtByBot: [String: TimeInterval] = [:]
}


/// Lightweight local signal snapshot gathered without triggering network I/O.
nonisolated struct ProactiveSignalSnapshot: Sendable {
    var weeklyFragments: [String] = []
    var hotNewsHeadlines: [String] = []
    var unreadPodcastTitles: [String] = []
    var butlerTipText: String? = nil
    var butlerName: String = "曜"
    var todayChars: Int = 0
}


/// Pure deterministic scheduling, cooldown, DND, and message-composition rules for proactive DMs.
nonisolated enum ProactiveDispatchPlanner {
    
    static func isWithinDND(hour: Int, start: Int, end: Int) -> Bool {
        let h = ((hour % 24) + 24) % 24
        let s = ((start % 24) + 24) % 24
        let e = ((end % 24) + 24) % 24
        if s == e {
            return false
        }
        if s < e {
            return h >= s && h < e
        }
        return h >= s || h < e
    }
    
    
    static func limits(for level: BotProactiveLevel) -> (maxPerDay: Int, cooldown: TimeInterval) {
        switch level {
            case .off:
                (0, 0)
            case .restrained:
                (1, 4 * 3600)
            case .active:
                (3, 90 * 60)
        }
    }
    
    
    static func dayKey(for date: Date, calendar: Calendar = .current) -> String {
        let comps = calendar.dateComponents([.year, .month, .day], from: date)
        let y = comps.year ?? 1970
        let m = comps.month ?? 1
        let d = comps.day ?? 1
        return String(format: "%04d-%02d-%02d", y, m, d)
    }
    
    
    static func rollover(
        _ ledger: ProactiveCooldownLedger,
        now: Date,
        calendar: Calendar = .current
    ) -> ProactiveCooldownLedger {
        let today = Self.dayKey(for: now, calendar: calendar)
        if ledger.dayKey == today {
            return ledger
        }
        return ProactiveCooldownLedger(
            dayKey: today,
            sentCountByBot: [:],
            lastSentAtByBot: ledger.lastSentAtByBot
        )
    }
    
    
    static func canSend(
        botID: String,
        level: BotProactiveLevel,
        ledger: ProactiveCooldownLedger,
        now: Date,
        calendar: Calendar = .current
    ) -> Bool {
        let (maxPerDay, cooldown) = Self.limits(for: level)
        guard maxPerDay > 0 else { return false }
        let rolled = Self.rollover(ledger, now: now, calendar: calendar)
        if (rolled.sentCountByBot[botID] ?? 0) >= maxPerDay {
            return false
        }
        if let lastSent = rolled.lastSentAtByBot[botID] {
            if now.timeIntervalSince1970 - lastSent < cooldown {
                return false
            }
        }
        return true
    }
    
    
    static func recordingSend(
        _ ledger: ProactiveCooldownLedger,
        botID: String,
        now: Date,
        calendar: Calendar = .current
    ) -> ProactiveCooldownLedger {
        var next = Self.rollover(ledger, now: now, calendar: calendar)
        next.sentCountByBot[botID, default: 0] += 1
        next.lastSentAtByBot[botID] = now.timeIntervalSince1970
        return next
    }
    
    
    static func composeMessage(
        forBotID botID: String,
        botName: String,
        level: BotProactiveLevel,
        signals: ProactiveSignalSnapshot,
        now: Date,
        calendar: Calendar = .current,
        hasUsableAI: Bool = true
    ) -> String? {
        if botID == AIBotID.butler.rawValue {
            guard let tip = signals.butlerTipText?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !tip.isEmpty
            else { return nil }
            return tip
        }
        
        if botID == AIBotID.weeklyReport.rawValue {
            guard !signals.weeklyFragments.isEmpty else { return nil }
            let weekday = calendar.component(.weekday, from: now) // 5=Thu, 6=Fri
            let hour = calendar.component(.hour, from: now)
            let isThuFriAfternoon = (weekday == 5 || weekday == 6) && hour >= 14
            if level == .restrained && !isThuFriAfternoon && signals.weeklyFragments.count < 2 {
                return nil
            }
            return "\(botName)：本周已攒下 \(signals.weeklyFragments.count) 条周报片段，要现在帮你梳理成周报吗？"
        }
        
        if botID == AIBotID.readingCompanion.rawValue {
            if let headline = signals.hotNewsHeadlines.first {
                let clipped = String(headline.trimmingCharacters(in: .whitespacesAndNewlines).prefix(36))
                return "\(botName)：已缓存 \(signals.hotNewsHeadlines.count) 条热点资讯，其中「\(clipped)」值得关注，要聊聊重点吗？"
            }
            if let title = signals.unreadPodcastTitles.first {
                let clipped = String(title.trimmingCharacters(in: .whitespacesAndNewlines).prefix(36))
                return "\(botName)：你订阅的播客有未读更新「\(clipped)」，要看下要点吗？"
            }
            return nil
        }
        
        guard level == .active, hasUsableAI else { return nil }
        if botID == AIBotID.organizeAndMerge.rawValue, !signals.weeklyFragments.isEmpty {
            return "\(botName)：当前有 \(signals.weeklyFragments.count) 条零散工作片段，需要我顺手分类归档吗？"
        }
        if let headline = signals.hotNewsHeadlines.first {
            let clipped = String(headline.trimmingCharacters(in: .whitespacesAndNewlines).prefix(34))
            return "\(botName)：刚才看到「\(clipped)」，有需要我协助拆解的地方随时叫我。"
        }
        return nil
    }
}


/// Unified per-bot proactive messaging coordinator enforcing cooldowns, daily caps, and Do-Not-Disturb.
@MainActor
@Observable
final class CotProactiveDispatchService {
    
    static let shared = CotProactiveDispatchService()
    
    private let database: CotLocalDatabase
    private let butler: CotButlerManager
    private let botStore: AIBotStore
    private let journalService: ProactiveDailyJournalService
    private let nowProvider: () -> Date
    
    @ObservationIgnored private var schedulerTask: Task<Void, Never>?
    
    
    init(
        database: CotLocalDatabase = .shared,
        butler: CotButlerManager = .shared,
        botStore: AIBotStore = .shared,
        journalService: ProactiveDailyJournalService = .shared,
        now: @escaping () -> Date = { Date() }
    ) {
        self.database = database
        self.butler = butler
        self.botStore = botStore
        self.journalService = journalService
        self.nowProvider = now
    }
    
    
    isolated deinit {
        self.schedulerTask?.cancel()
    }
    
    
    func startBackgroundScheduler() {
        guard !CotLocalDatabase.isRunningUnitTests else { return }
        guard self.schedulerTask == nil else { return }
        
        self.schedulerTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(90))
            guard !Task.isCancelled, let self else { return }
            _ = await self.tick(manual: false)
            
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(900))
                guard !Task.isCancelled else { break }
                _ = await self.tick(manual: false)
            }
        }
    }
    
    
    func stop() {
        self.schedulerTask?.cancel()
        self.schedulerTask = nil
    }
    
    
    func loadSettings() -> ProactiveDispatchSettings {
        let enabledRaw = self.database.string(forKey: CotLocalDatabase.ConfigKey.proactiveMessagingEnabled, default: "true")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let dndRaw = self.database.string(forKey: CotLocalDatabase.ConfigKey.proactiveDndEnabled, default: "true")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let startRaw = self.database.string(forKey: CotLocalDatabase.ConfigKey.proactiveDndStartHour, default: "23")
        let endRaw = self.database.string(forKey: CotLocalDatabase.ConfigKey.proactiveDndEndHour, default: "8")
        return ProactiveDispatchSettings(
            enabled: enabledRaw != "false" && enabledRaw != "0",
            dndEnabled: dndRaw != "false" && dndRaw != "0",
            dndStartHour: Int(startRaw) ?? 23,
            dndEndHour: Int(endRaw) ?? 8
        )
    }
    
    
    func loadLedger() -> ProactiveCooldownLedger {
        let raw = self.database.string(forKey: CotLocalDatabase.ConfigKey.proactiveCooldownStateJSON)
        guard !raw.isEmpty,
              let data = raw.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(ProactiveCooldownLedger.self, from: data)
        else {
            return ProactiveCooldownLedger()
        }
        return decoded
    }
    
    
    func saveLedger(_ ledger: ProactiveCooldownLedger) {
        guard let data = try? JSONEncoder().encode(ledger),
              let json = String(data: data, encoding: .utf8)
        else { return }
        self.database.set(json, forKey: CotLocalDatabase.ConfigKey.proactiveCooldownStateJSON)
    }
    
    
    @discardableResult
    func tick(manual: Bool = false, onlyBotID: String? = nil) async -> [String] {
        let now = self.nowProvider()
        let calendar = Calendar.current
        let settings = self.loadSettings()
        if !manual {
            guard settings.enabled else { return [] }
            let hour = calendar.component(.hour, from: now)
            if settings.dndEnabled && ProactiveDispatchPlanner.isWithinDND(
                hour: hour,
                start: settings.dndStartHour,
                end: settings.dndEndHour
            ) {
                return []
            }
        }
        
        var ledger = ProactiveDispatchPlanner.rollover(self.loadLedger(), now: now, calendar: calendar)
        let targetFilter = onlyBotID ?? (manual ? AIBotID.butler.rawValue : nil)
        let candidates = self.buildCandidates(filterBotID: targetFilter)
        var signals = self.collectSignals(now: now)
        var delivered: [String] = []
        
        for candidate in candidates {
            if !manual {
                guard ProactiveDispatchPlanner.canSend(
                    botID: candidate.id,
                    level: candidate.level,
                    ledger: ledger,
                    now: now,
                    calendar: calendar
                ) else {
                    continue
                }
            }
            if candidate.id == AIBotID.butler.rawValue {
                signals.butlerTipText = await self.resolveButlerTipText(now: now, signals: signals, manual: manual)
            }
            let effectiveLevel: BotProactiveLevel = manual ? .active : candidate.level
            guard let text = ProactiveDispatchPlanner.composeMessage(
                forBotID: candidate.id,
                botName: candidate.name,
                level: effectiveLevel,
                signals: signals,
                now: now,
                calendar: calendar,
                hasUsableAI: candidate.hasUsableAI
            ) else {
                continue
            }
            let countsAsUnread = !ToolbarButlerBotButtonView.isAnyPanelVisible
            _ = self.butler.receiveProactiveMessage(
                fromBotID: candidate.id,
                text: text,
                countsAsUnread: countsAsUnread
            )
            ledger = ProactiveDispatchPlanner.recordingSend(ledger, botID: candidate.id, now: now, calendar: calendar)
            delivered.append(candidate.id)
        }
        
        if !delivered.isEmpty {
            self.saveLedger(ledger)
        }
        return delivered
    }
    
    
    private struct BotCandidate {
        var id: String
        var name: String
        var level: BotProactiveLevel
        var hasUsableAI: Bool
    }
    
    
    private func buildCandidates(filterBotID: String?) -> [BotCandidate] {
        var list: [BotCandidate] = []
        for botID in AIBotID.allCases {
            if let filterBotID, botID.rawValue != filterBotID { continue }
            let cfg = self.botStore.config(for: botID)
            guard cfg.isEnabled else { continue }
            let resolvedCfg = self.botStore.resolvedConfiguration(for: botID)
            list.append(BotCandidate(
                id: botID.rawValue,
                name: self.botStore.resolvedName(for: botID),
                level: cfg.effectiveProactiveLevel(for: botID),
                hasUsableAI: resolvedCfg.isUsable
            ))
        }
        for custom in self.botStore.customBots {
            if let filterBotID, custom.id != filterBotID { continue }
            guard custom.isEnabled else { continue }
            let resolvedCfg = self.botStore.resolvedConfiguration(forBotID: custom.id)
            list.append(BotCandidate(
                id: custom.id,
                name: custom.name,
                level: custom.proactiveLevel,
                hasUsableAI: resolvedCfg.isUsable
            ))
        }
        return list
    }
    
    
    private func collectSignals(now: Date) -> ProactiveSignalSnapshot {
        let rawFragments = self.database.string(forKey: CotLocalDatabase.ConfigKey.weeklyReportFragments)
        let fragments = rawFragments
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        
        var headlines: [String] = []
        let rawNews = self.database.string(forKey: CotLocalDatabase.ConfigKey.aiHotNewsCacheJSON)
        if !rawNews.isEmpty,
           let newsData = rawNews.data(using: .utf8),
           let decoded = try? JSONDecoder().decode([AIHotNewsItem].self, from: newsData)
        {
            headlines = decoded.map(\.title).filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        }
        
        var podcastTitles: [String] = []
        let rawPodcast = self.database.string(forKey: CotLocalDatabase.ConfigKey.podcastAgentRemindersJSON)
        if !rawPodcast.isEmpty,
           let podData = rawPodcast.data(using: .utf8),
           let items = try? JSONSerialization.jsonObject(with: podData) as? [[String: Any]]
        {
            podcastTitles = items.compactMap { $0["episodeTitle"] as? String ?? $0["title"] as? String }
                .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        }
        
        let butlerName = self.database.string(forKey: CotLocalDatabase.ConfigKey.butlerName, default: "曜")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let todayChars = (self.database === CotLocalDatabase.shared)
            ? (AnalyticsManager.shared.todayStats.typedChars + AnalyticsManager.shared.todayStats.aiCompletedChars)
            : 0
        
        return ProactiveSignalSnapshot(
            weeklyFragments: fragments,
            hotNewsHeadlines: headlines,
            unreadPodcastTitles: podcastTitles,
            butlerTipText: nil,
            butlerName: butlerName.isEmpty ? "曜" : butlerName,
            todayChars: todayChars
        )
    }
    
    
    private func resolveButlerTipText(
        now: Date,
        signals: ProactiveSignalSnapshot,
        manual: Bool
    ) async -> String? {
        let isShared = (self.database === CotLocalDatabase.shared)
        let journalSignals = ProactiveJournalSignals(
            butlerName: signals.butlerName,
            todayChars: signals.todayChars,
            writingStreakDays: isShared ? AnalyticsManager.shared.writingStreak(referenceDate: now) : 0,
            activeDocTitle: nil,
            watchlist: isShared ? CotMarketService.shared.watchlist : [],
            quotes: isShared ? CotMarketService.shared.quotes : [:],
            unreadPodcasts: isShared ? CotPodcastService.shared.unreadReminders : [],
            recentNews: isShared ? AIHotNewsService.shared.items : [],
            memories: isShared ? CotMemoryStore.shared.memories : [],
            pendingActions: isShared ? AnalyticsManager.shared.actionPredictions : []
        )
        if let tip = await self.journalService.recordProactiveNote(
            signals: journalSignals,
            now: now,
            allowRemoteAI: false,
            showFloatingTip: manual || self.journalService.tipsEnabled
        ) {
            return tip.entryText
        }
        if manual {
            let fresh = ProactiveJournalComposer.synthesizeNextTip(
                signals: journalSignals,
                seenKeys: [],
                now: now
            )
            return fresh?.entryText
        }
        return nil
    }
}
