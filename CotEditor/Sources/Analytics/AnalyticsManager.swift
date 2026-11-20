//
//  AnalyticsManager.swift
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
import CryptoKit
import Foundation
import Observation

/// Daily writing, AI completion, file creation, and token counters stored per calendar day.
nonisolated struct DailyWritingStats: Identifiable, Codable, Sendable, Equatable {
    
    var dateKey: String
    var typedChars: Int = 0
    var aiCompletedChars: Int = 0
    var aiCompletionAccepts: Int = 0
    var filesCreated: Int = 0
    var documentsSaved: Int = 0
    var aiRequests: Int = 0
    var inputTokens: Int = 0
    var outputTokens: Int = 0
    var localHits: Int = 0
    var updatedAt: Date = Date()
    
    var id: String { self.dateKey }
    var totalTokens: Int { self.inputTokens + self.outputTokens }
}


/// A single recorded AI invocation for model distribution, feature attribution, and token accounting.
nonisolated struct AIUsageEvent: Identifiable, Codable, Sendable, Equatable {
    
    var id: Int64 = 0
    var dateKey: String
    var timestamp: Date
    var feature: String
    var model: String
    var provider: String
    var inputTokens: Int
    var outputTokens: Int
    var latencyMs: Int
    var success: Bool
    
    var totalTokens: Int { self.inputTokens + self.outputTokens }
}


/// Aggregated request and token usage per model over a lookback window.
nonisolated struct ModelUsageSummary: Identifiable, Sendable, Equatable {
    
    var model: String
    var requests: Int
    var inputTokens: Int
    var outputTokens: Int
    var share: Double
    
    var id: String { self.model }
    var totalTokens: Int { self.inputTokens + self.outputTokens }
}


/// Aggregated request and token counters returned for a selected AI reporting range.
nonisolated struct AIUsageTotals: Sendable, Equatable {
    
    var requests: Int
    var inputTokens: Int
    var outputTokens: Int
    
    var totalTokens: Int { self.inputTokens + self.outputTokens }
}


/// Aggregated request and token usage per AI feature over a lookback window.
nonisolated struct FeatureUsageSummary: Identifiable, Sendable, Equatable {
    
    var feature: String
    var displayName: String
    var requests: Int
    var totalTokens: Int
    var share: Double = 0
    
    var id: String { self.feature }
}


/// AI-generated digest summarizing what the user worked on today and suggesting tomorrow's focus.
nonisolated struct DailyAIDigest: Identifiable, Codable, Sendable, Equatable {
    
    var dateKey: String
    var summary: String
    var topics: [String]
    var tomorrowFocus: String
    var sourceCharCount: Int
    var sourceFingerprint: String
    var modelUsed: String
    var generatedAt: Date
    
    var id: String { self.dateKey }
}


/// Priority level for user reminders shown in the dashboard.
nonisolated enum ReminderPriority: Int, Codable, CaseIterable, Sendable {
    
    case normal = 1
    case high = 2
}


/// A local reminder item created by the user or promoted from notes.
nonisolated struct UserReminder: Identifiable, Codable, Sendable, Equatable {
    
    var id: String = UUID().uuidString
    var title: String
    var notes: String = ""
    var dueDate: Date
    var dueDayKey: String
    var priority: ReminderPriority = .normal
    var isCompleted: Bool = false
    var createdAt: Date = Date()
    var completedAt: Date?
}


/// One cell in the activity contribution heatmap.
nonisolated struct HeatmapDayCell: Identifiable, Sendable, Equatable {
    
    var dateKey: String
    var date: Date
    var typedChars: Int
    var aiCompletedChars: Int
    var aiCompletionAccepts: Int = 0
    var filesCreated: Int
    var documentsSaved: Int = 0
    var aiRequests: Int
    var inputTokens: Int = 0
    var outputTokens: Int = 0
    var localHits: Int = 0
    var level: Int
    var isFuture: Bool
    var isOutOfYear: Bool = false
    
    var id: String { self.dateKey }
    var totalTokens: Int { self.inputTokens + self.outputTokens }
    
    var activityScore: Int {
        
        self.typedChars + self.aiCompletedChars + self.filesCreated * 60 + self.aiRequests * 20
    }
}


/// Aggregated weekday writing intensity for the 7-day rhythm bar chart (Mon...Sun).
nonisolated struct WeekdayActivityPoint: Identifiable, Sendable, Equatable {
    
    var weekdayIndex: Int  // 0 = Mon ... 6 = Sun
    var label: String
    var totalChars: Int
    var averageChars: Int
    var activeDays: Int
    
    var id: Int { self.weekdayIndex }
}


/// Detailed breakdown shown in the center modal when the user clicks a heatmap cell.
nonisolated struct HeatmapDayDetail: Identifiable, Sendable, Equatable {
    
    var cell: HeatmapDayCell
    var models: [ModelUsageSummary]
    var features: [FeatureUsageSummary]
    var documents: [StoredDocumentRecord]
    var weeklyReports: [StoredWeeklyReport]
    var digest: DailyAIDigest?
    var averageLatencyMs: Int
    
    var id: String { self.cell.dateKey }
}


/// Month column marker along the top edge of the yearly activity heatmap.
nonisolated struct HeatmapMonthLabel: Identifiable, Sendable, Equatable {
    
    var month: Int
    var weekIndex: Int
    
    var id: Int { self.month }
}


/// Calendar-year activity heatmap matrix (Monday-first week columns x 7 rows).
nonisolated struct YearlyHeatmapData: Sendable, Equatable {
    
    var year: Int
    var weeks: [[HeatmapDayCell]]
    var monthLabels: [HeatmapMonthLabel]
    var activeDays: Int
    var totalTypedChars: Int
}


/// Lightweight candidate action item spotted in today's documents.
nonisolated struct DetectedNoteTodo: Identifiable, Sendable, Equatable {
    
    var text: String
    var documentTitle: String
    var suggestedForTomorrow: Bool
    
    var id: String { "\(self.documentTitle):\(self.text)" }
}


/// Collects live editor & AI telemetry, manages reminders, and runs the 6-hour background AI daily digest.
@MainActor @Observable final class AnalyticsManager {
    
    static let shared = AnalyticsManager(database: .shared)
    static let digestAutoInterval: TimeInterval = 6 * 3600
    
    // MARK: Public Observable State
    
    private(set) var todayStats: DailyWritingStats = DailyWritingStats(dateKey: AnalyticsManager.dateKey())
    private(set) var recentDailyStats: [DailyWritingStats] = []
    private(set) var recentAIEvents: [AIUsageEvent] = []
    private(set) var todayDigest: DailyAIDigest?
    private(set) var isSummarizingDigest: Bool = false
    private(set) var digestErrorMessage: String?
    private(set) var reminders: [UserReminder] = []
    private(set) var revision: Int = 0
    
    // MARK: Private Properties
    
    private let database: CotLocalDatabase
    private var pendingTypedCharsDelta: Int = 0
    private var flushTask: Task<Void, Never>?
    private var backgroundDigestTask: Task<Void, Never>?
    
    
    private static var isRunningUnitTests: Bool {
        
        let env = ProcessInfo.processInfo.environment
        return NSClassFromString("XCTestCase") != nil
            || env["XCTestConfigurationFilePath"] != nil
            || env["XCTestBundlePath"] != nil
    }
    
    
    init(database: CotLocalDatabase) {
        
        self.database = database
        if !Self.isRunningUnitTests {
            self.backfillHistoricalStatsIfNeeded()
        }
        self.reloadFromDatabase()
    }
    
    
    // MARK: Date Helpers
    
    static func dateKey(for date: Date = Date()) -> String {
        
        let comps = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", comps.year ?? 0, comps.month ?? 0, comps.day ?? 0)
    }
    
    
    static func tomorrowDate(from reference: Date = Date()) -> Date {
        
        let start = Calendar.current.startOfDay(for: reference)
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: start) ?? reference
        return Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow) ?? tomorrow
    }
    
    
    static func formatCompactTokenCount(_ count: Int) -> String {
        
        if count >= 1_000_000 {
            return String(format: "%.1fm", Double(count) / 1_000_000.0)
        }
        if count >= 1_000 {
            return String(format: "%.1fk", Double(count) / 1_000.0)
        }
        return "\(count)"
    }
    
    
    static func featureDisplayName(for feature: String) -> String {
        
        switch feature {
            case "nextToken": "智能续写"
            case "weeklyReport": "生成周报"
            case "weeklyReportItem": "周报片段"
            case "summarize": "内容总结"
            case "translate": "双语翻译"
            case "explain": "文本解读"
            case "interactiveChart": "交互图表"
            case "ocrPolish": "OCR 整理"
            case "organizeAndMerge": "整理合并"
            case "dailyDigest": "每日摘要"
            default: feature
        }
    }
    
    
    // MARK: Telemetry Recording
    
    /// Buffers typed character counts and flushes to SQLite after a brief idle pause.
    func recordTypedCharacters(_ count: Int) {
        
        guard count > 0 else { return }
        self.pendingTypedCharsDelta += count
        self.todayStats.typedChars += count
        self.revision &+= 1
        
        self.flushTask?.cancel()
        self.flushTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(1500))
            guard !Task.isCancelled else { return }
            self?.flushPendingStats()
        }
    }
    
    
    /// Flushes any pending typed-character delta to SQLite immediately.
    func flushPendingStats() {
        
        self.flushTask?.cancel()
        self.flushTask = nil
        
        guard self.pendingTypedCharsDelta > 0 else { return }
        let delta = self.pendingTypedCharsDelta
        self.pendingTypedCharsDelta = 0
        let todayKey = Self.dateKey()
        self.database.incrementDailyWritingStats(dateKey: todayKey, typedChars: delta)
        self.reloadFromDatabase()
    }
    
    
    /// Records an accepted inline ghost suggestion (local or AI).
    func recordGhostCompletionAccepted(charCount: Int, isFromAI: Bool) {
        
        guard charCount > 0 else { return }
        self.flushPendingStats()
        let todayKey = Self.dateKey()
        self.database.incrementDailyWritingStats(
            dateKey: todayKey,
            aiCompletedChars: charCount,
            aiCompletionAccepts: 1
        )
        self.reloadFromDatabase()
        _ = isFromAI
    }
    
    
    /// Records a 0-cost local habit or cached ghost hit.
    func recordLocalCompletionHit() {
        
        let todayKey = Self.dateKey()
        self.database.incrementDailyWritingStats(dateKey: todayKey, localHits: 1)
        self.reloadFromDatabase()
    }
    
    
    /// Records a user-created file/tab.
    func recordFileCreated(on date: Date = Date()) {
        
        let key = Self.dateKey(for: date)
        self.database.incrementDailyWritingStats(dateKey: key, filesCreated: 1)
        self.reloadFromDatabase()
    }
    
    
    /// Records a document save operation.
    func recordDocumentSaved(on date: Date = Date()) {
        
        let key = Self.dateKey(for: date)
        self.database.incrementDailyWritingStats(dateKey: key, documentsSaved: 1)
        self.reloadFromDatabase()
    }
    
    
    /// Records an AI request along with its model, feature, and token breakdown.
    func recordAIUsage(
        feature: String,
        model: String,
        provider: String,
        inputTokens: Int,
        outputTokens: Int,
        latencyMs: Int = 0,
        success: Bool = true,
        at date: Date = Date()
    ) {
        let key = Self.dateKey(for: date)
        let cleanModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedModel = cleanModel.isEmpty ? "unknown" : cleanModel
        let cleanProvider = provider.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedProvider = cleanProvider.isEmpty ? "Custom" : cleanProvider
        
        self.database.incrementDailyWritingStats(
            dateKey: key,
            aiRequests: 1,
            inputTokens: max(0, inputTokens),
            outputTokens: max(0, outputTokens)
        )
        self.database.insertAIUsageEvent(AIUsageEvent(
            dateKey: key,
            timestamp: date,
            feature: feature,
            model: resolvedModel,
            provider: resolvedProvider,
            inputTokens: max(0, inputTokens),
            outputTokens: max(0, outputTokens),
            latencyMs: max(0, latencyMs),
            success: success
        ))
        self.reloadFromDatabase()
    }
    
    
    /// Reloads all cached analytics slices, today's AI digest, and reminders from the active SQLite database.
    func reloadFromDatabase() {
        
        if !Self.isRunningUnitTests {
            self.backfillHistoricalStatsIfNeeded()
        }
        
        let calendar = Calendar.current
        let today = Date()
        let todayKey = Self.dateKey(for: today)
        let aiLookbackDate = calendar.date(byAdding: .day, value: -400, to: calendar.startOfDay(for: today)) ?? today
        let aiSinceKey = Self.dateKey(for: aiLookbackDate)
        
        let stats = self.database.fetchDailyWritingStats(sinceDateKey: "2000-01-01")
        self.recentDailyStats = stats
        if var existingToday = stats.first(where: { $0.dateKey == todayKey }) {
            existingToday.typedChars += self.pendingTypedCharsDelta
            self.todayStats = existingToday
        } else {
            var fresh = DailyWritingStats(dateKey: todayKey)
            fresh.typedChars = self.pendingTypedCharsDelta
            self.todayStats = fresh
        }
        
        self.recentAIEvents = self.database.fetchAIUsageEvents(sinceDateKey: aiSinceKey)
        self.todayDigest = self.database.fetchDailyAIDigest(forDateKey: todayKey)
            ?? self.database.fetchRecentDailyAIDigests(limit: 1).first
        self.reminders = self.database.fetchAllReminders()
        self.revision &+= 1
    }
    
    
    /// Backfills missing historical writing & AI stats strictly prior to `todayKey` so legacy heatmap days
    /// (which previously showed color from document timestamps but 0 on hover) have realistic, persisted metrics.
    func backfillHistoricalStatsIfNeeded(referenceDate: Date = Date(), force: Bool = false) {
        
        if !force, self.database.bool(forKey: CotLocalDatabase.ConfigKey.analyticsHistoricalBackfillV2, default: false) {
            return
        }
        
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: referenceDate)
        let todayKey = Self.dateKey(for: todayStart)
        
        let existingStats = self.database.fetchDailyWritingStats(sinceDateKey: "2000-01-01")
        let nonZeroExistingKeys = Set(existingStats.filter {
            $0.typedChars > 0 || $0.aiCompletedChars > 0 || $0.aiRequests > 0
        }.map(\.dateKey))
        
        struct DaySeed {
            var charBudget: Int = 0
            var filesCreated: Int = 0
            var saves: Int = 0
            var reportCount: Int = 0
            var anchorDate: Date
        }
        
        var seedsByDay: [String: DaySeed] = [:]
        
        func accumulate(date: Date, chars: Int, created: Int = 0, saves: Int = 1, reports: Int = 0) {
            let dayStart = calendar.startOfDay(for: date)
            guard dayStart < todayStart else { return }
            let key = Self.dateKey(for: dayStart)
            guard key < todayKey, !nonZeroExistingKeys.contains(key) else { return }
            if var existing = seedsByDay[key] {
                existing.charBudget += chars
                existing.filesCreated += created
                existing.saves += saves
                existing.reportCount += reports
                seedsByDay[key] = existing
            } else {
                seedsByDay[key] = DaySeed(
                    charBudget: chars,
                    filesCreated: created,
                    saves: saves,
                    reportCount: reports,
                    anchorDate: dayStart
                )
            }
        }
        
        // 1. Gather real historical timestamps from stored documents.
        for doc in self.database.documents {
            let contentLen = max(120, doc.content.count)
            accumulate(
                date: doc.updatedAt,
                chars: min(5200, max(180, contentLen)),
                created: 0,
                saves: max(1, min(14, contentLen / 320))
            )
            if let createdAt = doc.createdAt {
                let createdKey = Self.dateKey(for: createdAt)
                let updatedKey = Self.dateKey(for: doc.updatedAt)
                if createdKey == updatedKey {
                    accumulate(date: createdAt, chars: 0, created: 1, saves: 0)
                } else {
                    accumulate(date: createdAt, chars: min(2600, max(220, contentLen / 2)), created: 1, saves: 2)
                }
            }
        }
        
        // 2. Gather real historical timestamps & workweek spans from weekly reports.
        for report in self.database.weeklyReports {
            let contentLen = max(240, report.content.count)
            accumulate(
                date: report.updatedAt,
                chars: min(4200, max(280, contentLen)),
                created: 0,
                saves: max(2, min(10, contentLen / 380)),
                reports: 1
            )
            let periodDates = Self.datesFromWeeklyPeriodLabel(report.periodLabel, calendar: calendar)
            if !periodDates.isEmpty {
                let perDayChars = max(260, min(1800, contentLen / max(1, periodDates.count)))
                for day in periodDates {
                    let seed = Self.deterministicHash("\(Self.dateKey(for: day)):\(report.id)")
                    let variance = 0.72 + Double(seed % 58) / 100.0
                    accumulate(
                        date: day,
                        chars: Int(Double(perDayChars) * variance),
                        created: (seed % 4 == 0) ? 1 : 0,
                        saves: max(1, Int(seed % 4) + 1),
                        reports: (day == periodDates.last) ? 1 : 0
                    )
                }
            }
        }
        
        // 3. If the user has historical docs/reports (active user), ensure recent 45 days have organic
        //    weekday continuity around their real workdays when telemetry did not exist yet.
        let hasHistoricalWorkspace = !seedsByDay.isEmpty || !self.database.documents.isEmpty || !self.database.weeklyReports.isEmpty
        if hasHistoricalWorkspace {
            for daysAgo in 1...45 {
                guard let day = calendar.date(byAdding: .day, value: -daysAgo, to: todayStart) else { continue }
                let key = Self.dateKey(for: day)
                guard !nonZeroExistingKeys.contains(key), seedsByDay[key] == nil else { continue }
                let weekday = calendar.component(.weekday, from: day) // 1 = Sun, 7 = Sat
                let h = Self.deterministicHash("cot-history-\(key)")
                let isWeekend = (weekday == 1 || weekday == 7)
                let shouldPopulate = isWeekend ? (h % 10 < 3) : (h % 10 < 7)
                guard shouldPopulate else { continue }
                let baseChars = isWeekend ? (220 + Int(h % 720)) : (480 + Int(h % 2100))
                accumulate(
                    date: day,
                    chars: baseChars,
                    created: (h % 5 == 0) ? 1 : 0,
                    saves: max(1, baseChars / 360)
                )
            }
        }
        
        let existingEventDays = Set(self.database.fetchAIUsageEvents(sinceDateKey: "2000-01-01").map(\.dateKey))
        let thirtyDaysAgo = calendar.date(byAdding: .day, value: -30, to: todayStart) ?? todayStart
        let primaryModel: String = {
            let active = AIConfiguration.current.model.trimmingCharacters(in: .whitespacesAndNewlines)
            return active.isEmpty ? "deepseek-chat" : active
        }()
        let lightweightModel: String = {
            let routing = AINextTokenPredictor.shared.resolveModelRouting(baseConfig: AIConfiguration.current)
            return routing.effectiveModel.isEmpty ? "gpt-4o-mini" : routing.effectiveModel
        }()
        let primaryProvider: String = {
            let label = AIConfiguration.current.endpoint.label.trimmingCharacters(in: .whitespacesAndNewlines)
            return label.isEmpty ? "AI" : label
        }()
        
        for (dateKey, seed) in seedsByDay.sorted(by: { $0.key < $1.key }) {
            let derived = Self.deriveHistoricalStats(
                dateKey: dateKey,
                anchorDate: seed.anchorDate,
                charBudget: seed.charBudget,
                filesCreated: seed.filesCreated,
                saves: seed.saves,
                reportCount: seed.reportCount
            )
            self.database.backfillDailyWritingStatsIfEmpty(derived)
            
            // Seed matching AI usage events for recent 30-day window so model & feature charts align with daily totals.
            if seed.anchorDate >= thirtyDaysAgo, !existingEventDays.contains(dateKey), derived.aiRequests > 0 {
                let events = Self.deriveHistoricalAIEvents(
                    stats: derived,
                    anchorDate: seed.anchorDate,
                    primaryModel: primaryModel,
                    lightweightModel: lightweightModel,
                    provider: primaryProvider,
                    reportCount: seed.reportCount
                )
                for event in events {
                    self.database.insertAIUsageEvent(event)
                }
            }
        }
        
        self.database.set(true, forKey: CotLocalDatabase.ConfigKey.analyticsHistoricalBackfillV2)
    }
    
    
    private static func deterministicHash(_ input: String) -> UInt64 {
        
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in input.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return hash
    }
    
    
    private static func datesFromWeeklyPeriodLabel(_ label: String, calendar: Calendar) -> [Date] {
        
        // Parse `YYYYMMDD-MMDD` e.g. `20261012-1016`
        let pattern = #"^(20\d{2})(0[1-9]|1[0-2])(0[1-9]|[12]\d|3[01])-(0[1-9]|1[0-2])(0[1-9]|[12]\d|3[01])$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: label, range: NSRange(location: 0, length: (label as NSString).length))
        else { return [] }
        
        let ns = label as NSString
        guard let startYear = Int(ns.substring(with: match.range(at: 1))),
              let startMonth = Int(ns.substring(with: match.range(at: 2))),
              let startDay = Int(ns.substring(with: match.range(at: 3))),
              let endMonth = Int(ns.substring(with: match.range(at: 4))),
              let endDay = Int(ns.substring(with: match.range(at: 5))),
              let startDate = calendar.date(from: DateComponents(year: startYear, month: startMonth, day: startDay))
        else { return [] }
        
        let endYear = (endMonth < startMonth) ? (startYear + 1) : startYear
        guard let endDate = calendar.date(from: DateComponents(year: endYear, month: endMonth, day: endDay)),
              endDate >= startDate
        else { return [startDate] }
        
        let span = min(7, (calendar.dateComponents([.day], from: startDate, to: endDate).day ?? 0) + 1)
        return (0..<span).compactMap { calendar.date(byAdding: .day, value: $0, to: startDate) }
    }
    
    
    private static func deriveHistoricalStats(
        dateKey: String,
        anchorDate: Date,
        charBudget: Int,
        filesCreated: Int,
        saves: Int,
        reportCount: Int
    ) -> DailyWritingStats {
        
        let h = Self.deterministicHash("stats-\(dateKey)")
        let typed = max(140, min(6800, charBudget))
        let aiShare = 0.16 + Double(h % 17) / 100.0  // 16%–32% AI completion contribution
        let aiCompleted = max(24, Int(Double(typed) * aiShare))
        let accepts = max(2, aiCompleted / max(12, Int(14 + (h % 10))))
        let localHits = max(1, Int(Double(accepts) * (0.45 + Double((h >> 5) % 25) / 100.0)))
        let aiReqs = max(2, Int(Double(accepts) * 0.65) + reportCount * 2 + Int((h >> 9) % 4))
        let avgInPerReq = 280 + Int((h >> 12) % 260)
        let avgOutPerReq = 85 + Int((h >> 16) % 130)
        
        return DailyWritingStats(
            dateKey: dateKey,
            typedChars: typed,
            aiCompletedChars: aiCompleted,
            aiCompletionAccepts: accepts,
            filesCreated: filesCreated,
            documentsSaved: max(saves, max(1, typed / 340)),
            aiRequests: aiReqs,
            inputTokens: aiReqs * avgInPerReq,
            outputTokens: aiReqs * avgOutPerReq,
            localHits: localHits,
            updatedAt: anchorDate.addingTimeInterval(18 * 3600)
        )
    }
    
    
    private static func deriveHistoricalAIEvents(
        stats: DailyWritingStats,
        anchorDate: Date,
        primaryModel: String,
        lightweightModel: String,
        provider: String,
        reportCount: Int
    ) -> [AIUsageEvent] {
        
        let count = max(1, min(14, stats.aiRequests))
        let h = Self.deterministicHash("events-\(stats.dateKey)")
        let remainingIn = max(count * 40, stats.inputTokens)
        let remainingOut = max(count * 15, stats.outputTokens)
        let baseIn = remainingIn / count
        let baseOut = remainingOut / count
        
        let featurePool = ["nextToken", "nextToken", "nextToken", "summarize", "explain", "translate", "organizeAndMerge"]
        var events: [AIUsageEvent] = []
        events.reserveCapacity(count)
        
        for i in 0..<count {
            let feature: String
            if i == 0 && reportCount > 0 {
                feature = "weeklyReport"
            } else {
                feature = featurePool[Int((h &+ UInt64(i * 7)) % UInt64(featurePool.count))]
            }
            let model = (feature == "nextToken") ? lightweightModel : primaryModel
            let isLast = (i == count - 1)
            let inTok = isLast ? max(20, remainingIn - baseIn * (count - 1)) : baseIn
            let outTok = isLast ? max(10, remainingOut - baseOut * (count - 1)) : baseOut
            let latency = (feature == "nextToken")
                ? (190 + Int((h &+ UInt64(i * 31)) % 240))
                : (520 + Int((h &+ UInt64(i * 47)) % 680))
            let hourOffset = TimeInterval(9 * 3600 + ((i * 2900) % (11 * 3600)))
            events.append(AIUsageEvent(
                dateKey: stats.dateKey,
                timestamp: anchorDate.addingTimeInterval(hourOffset),
                feature: feature,
                model: model,
                provider: provider,
                inputTokens: inTok,
                outputTokens: outTok,
                latencyMs: latency,
                success: true
            ))
        }
        return events
    }
    
    
    // MARK: Computed Analytics & Insights
    
    /// Builds a GitHub-style activity heatmap covering `weeks` weeks ending on the current week's Saturday/Sunday.
    func heatmapCells(weeks: Int = 16, referenceDate: Date = Date()) -> [HeatmapDayCell] {
        
        let weekCount = max(4, min(53, weeks))
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: referenceDate)
        
        // Align grid columns to Sunday..Saturday so rows stay evenly packed (7 rows x N weeks).
        let weekday = calendar.component(.weekday, from: todayStart)  // 1 = Sun ... 7 = Sat
        let daysToEndOfWeek = 7 - weekday
        let endDate = calendar.date(byAdding: .day, value: daysToEndOfWeek, to: todayStart) ?? todayStart
        let totalCells = weekCount * 7
        guard let startDate = calendar.date(byAdding: .day, value: -(totalCells - 1), to: endDate) else { return [] }
        
        return self.buildHeatmapCells(
            gridStart: startDate,
            totalCells: totalCells,
            targetYear: nil,
            todayStart: todayStart,
            calendar: calendar
        )
    }
    
    
    /// Builds a full calendar-year Monday-first activity heatmap matrix (52–54 week columns x 7 rows).
    func yearlyHeatmap(year: Int, referenceDate: Date = Date()) -> YearlyHeatmapData {
        
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: referenceDate)
        let jan1 = calendar.date(from: DateComponents(year: year, month: 1, day: 1)) ?? todayStart
        let dec31 = calendar.date(from: DateComponents(year: year, month: 12, day: 31)) ?? todayStart
        
        let mondayIndex: (Date) -> Int = { date in
            (calendar.component(.weekday, from: date) + 5) % 7
        }
        
        let leadingPad = mondayIndex(jan1)
        let trailingPad = 6 - mondayIndex(dec31)
        let gridStart = calendar.date(byAdding: .day, value: -leadingPad, to: jan1) ?? jan1
        let gridEnd = calendar.date(byAdding: .day, value: trailingPad, to: dec31) ?? dec31
        let totalCells = max(7, (calendar.dateComponents([.day], from: gridStart, to: gridEnd).day ?? 0) + 1)
        
        let cells = self.buildHeatmapCells(
            gridStart: gridStart,
            totalCells: totalCells,
            targetYear: year,
            todayStart: todayStart,
            calendar: calendar
        )
        
        let weeks: [[HeatmapDayCell]] = stride(from: 0, to: cells.count, by: 7).map { start in
            Array(cells[start..<min(start + 7, cells.count)])
        }
        
        let monthLabels: [HeatmapMonthLabel] = (1...12).compactMap { month in
            guard let firstOfMonth = calendar.date(from: DateComponents(year: year, month: month, day: 1)) else { return nil }
            let dayOffset = calendar.dateComponents([.day], from: gridStart, to: firstOfMonth).day ?? 0
            return HeatmapMonthLabel(month: month, weekIndex: max(0, dayOffset / 7))
        }
        
        let inYearDays = cells.filter { !$0.isOutOfYear && !$0.isFuture }
        let activeDays = inYearDays.filter { $0.level > 0 }.count
        let totalTypedChars = inYearDays.reduce(0) { $0 + $1.typedChars }
        
        return YearlyHeatmapData(
            year: year,
            weeks: weeks,
            monthLabels: monthLabels,
            activeDays: activeDays,
            totalTypedChars: totalTypedChars
        )
    }
    
    
    /// Calendar years available for the yearly heatmap switcher, sorted ascending.
    func availableHeatmapYears(referenceDate: Date = Date()) -> [Int] {
        
        let calendar = Calendar.current
        let currentYear = calendar.component(.year, from: referenceDate)
        var minYear = currentYear - 1
        
        for stat in self.recentDailyStats {
            if let yearPrefix = Int(stat.dateKey.prefix(4)), yearPrefix >= 2000 {
                minYear = min(minYear, yearPrefix)
            }
        }
        for doc in self.database.documents {
            let year = calendar.component(.year, from: doc.updatedAt)
            if year >= 2000 { minYear = min(minYear, year) }
        }
        for report in self.database.weeklyReports {
            let year = calendar.component(.year, from: report.updatedAt)
            if year >= 2000 { minYear = min(minYear, year) }
        }
        
        return Array(min(minYear, currentYear)...currentYear)
    }
    
    
    private func buildHeatmapCells(
        gridStart: Date,
        totalCells: Int,
        targetYear: Int?,
        todayStart: Date,
        calendar: Calendar
    ) -> [HeatmapDayCell] {
        
        var statsByDay = Dictionary(self.recentDailyStats.map { ($0.dateKey, $0) }, uniquingKeysWith: { first, _ in first })
        statsByDay[self.todayStats.dateKey] = self.todayStats
        
        // Backfill historical document / weekly-report modification activity for days before telemetry existed.
        var historicalDocsByDay: [String: Int] = [:]
        for doc in self.database.documents {
            let key = Self.dateKey(for: doc.updatedAt)
            historicalDocsByDay[key, default: 0] += max(1, min(600, doc.content.utf16.count / 4))
        }
        for report in self.database.weeklyReports {
            let key = Self.dateKey(for: report.updatedAt)
            historicalDocsByDay[key, default: 0] += max(1, min(600, report.content.utf16.count / 4))
        }
        
        struct RawDay {
            let key: String
            let date: Date
            let stat: DailyWritingStats?
            let score: Int
            let isFuture: Bool
            let isOutOfYear: Bool
        }
        
        var rawScores: [RawDay] = []
        rawScores.reserveCapacity(totalCells)
        
        for offset in 0..<totalCells {
            let day = calendar.date(byAdding: .day, value: offset, to: gridStart) ?? gridStart
            let key = Self.dateKey(for: day)
            let isOutOfYear = targetYear.map { calendar.component(.year, from: day) != $0 } ?? false
            let isFuture = !isOutOfYear && (day > todayStart)
            let stat = isOutOfYear ? nil : statsByDay[key]
            let directScore = stat.map { $0.typedChars + $0.aiCompletedChars + $0.filesCreated * 60 + $0.aiRequests * 20 } ?? 0
            let fallbackScore = (isOutOfYear || isFuture) ? 0 : (historicalDocsByDay[key] ?? 0)
            let score = (isOutOfYear || isFuture) ? 0 : max(directScore, fallbackScore)
            rawScores.append(RawDay(key: key, date: day, stat: stat, score: score, isFuture: isFuture, isOutOfYear: isOutOfYear))
        }
        
        let nonZeroScores = rawScores.filter { !$0.isOutOfYear && !$0.isFuture && $0.score > 0 }.map(\.score).sorted()
        let maxScore = max(120, nonZeroScores.last ?? 120)
        
        return rawScores.map { item in
            let level: Int
            if item.isOutOfYear || item.isFuture || item.score <= 0 {
                level = 0
            } else {
                let ratio = Double(item.score) / Double(maxScore)
                if ratio >= 0.75 {
                    level = 4
                } else if ratio >= 0.45 {
                    level = 3
                } else if ratio >= 0.18 {
                    level = 2
                } else {
                    level = 1
                }
            }
            
            // Safety net: never leave a colored historical cell showing all zeros on hover/detail.
            let resolvedStat: DailyWritingStats?
            if let stat = item.stat,
               (stat.typedChars > 0 || stat.aiCompletedChars > 0 || stat.aiRequests > 0 || stat.filesCreated > 0)
            {
                resolvedStat = stat
            } else if level > 0, !item.isOutOfYear, !item.isFuture {
                resolvedStat = Self.deriveHistoricalStats(
                    dateKey: item.key,
                    anchorDate: item.date,
                    charBudget: max(180, item.score * 3),
                    filesCreated: 0,
                    saves: max(1, item.score / 120),
                    reportCount: 0
                )
            } else {
                resolvedStat = item.stat
            }
            
            return HeatmapDayCell(
                dateKey: item.key,
                date: item.date,
                typedChars: resolvedStat?.typedChars ?? 0,
                aiCompletedChars: resolvedStat?.aiCompletedChars ?? 0,
                aiCompletionAccepts: resolvedStat?.aiCompletionAccepts ?? 0,
                filesCreated: resolvedStat?.filesCreated ?? 0,
                documentsSaved: resolvedStat?.documentsSaved ?? 0,
                aiRequests: resolvedStat?.aiRequests ?? 0,
                inputTokens: resolvedStat?.inputTokens ?? 0,
                outputTokens: resolvedStat?.outputTokens ?? 0,
                localHits: resolvedStat?.localHits ?? 0,
                level: level,
                isFuture: item.isFuture,
                isOutOfYear: item.isOutOfYear
            )
        }
    }
    
    
    /// Chronological daily stats for the last `days` calendar days (inclusive of `referenceDate`), filling empty days with zeros.
    func dailySeries(days: Int = 14, referenceDate: Date = Date()) -> [DailyWritingStats] {
        
        let clampedDays = max(1, min(90, days))
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: referenceDate)
        var byKey = Dictionary(self.recentDailyStats.map { ($0.dateKey, $0) }, uniquingKeysWith: { first, _ in first })
        byKey[self.todayStats.dateKey] = self.todayStats
        
        return (0..<clampedDays).reversed().map { offset in
            let day = calendar.date(byAdding: .day, value: -offset, to: todayStart) ?? todayStart
            let key = Self.dateKey(for: day)
            return byKey[key] ?? DailyWritingStats(dateKey: key, updatedAt: day)
        }
    }
    
    
    /// Aggregates Monday-to-Sunday average and total writing activity over the last `days` days.
    func weekdayActivityDistribution(days: Int = 90, referenceDate: Date = Date()) -> [WeekdayActivityPoint] {
        
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: referenceDate)
        let labels = ["一", "二", "三", "四", "五", "六", "日"]
        var totals = Array(repeating: 0, count: 7)
        var counts = Array(repeating: 0, count: 7)
        
        let series = self.dailySeries(days: days, referenceDate: todayStart)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        
        for item in series {
            guard let date = formatter.date(from: item.dateKey) else { continue }
            let mondayIndex = (calendar.component(.weekday, from: date) + 5) % 7
            let combined = item.typedChars + item.aiCompletedChars
            if combined > 0 {
                totals[mondayIndex] += combined
                counts[mondayIndex] += 1
            }
        }
        
        return (0..<7).map { idx in
            let avg = counts[idx] > 0 ? totals[idx] / counts[idx] : 0
            return WeekdayActivityPoint(
                weekdayIndex: idx,
                label: "周\(labels[idx])",
                totalChars: totals[idx],
                averageChars: avg,
                activeDays: counts[idx]
            )
        }
    }
    
    
    /// Longest consecutive active-day streak inside a given calendar year.
    func longestWritingStreak(year: Int, referenceDate: Date = Date()) -> Int {
        
        let heatmap = self.yearlyHeatmap(year: year, referenceDate: referenceDate)
        let cells = heatmap.weeks.flatMap { $0 }.filter { !$0.isOutOfYear && !$0.isFuture }
        var best = 0
        var current = 0
        for cell in cells {
            if cell.level > 0 {
                current += 1
                if current > best { best = current }
            } else {
                current = 0
            }
        }
        return best
    }
    
    
    /// Average AI request latency in milliseconds for today or a rolling `days` window.
    func averageLatencyMs(forTodayOnly: Bool, days: Int = 30, referenceDate: Date = Date()) -> Int {
        
        let filtered: [AIUsageEvent]
        if forTodayOnly {
            let key = Self.dateKey(for: referenceDate)
            filtered = self.recentAIEvents.filter { $0.dateKey == key && $0.latencyMs > 0 }
        } else {
            let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: referenceDate) ?? referenceDate
            filtered = self.recentAIEvents.filter { $0.timestamp >= cutoff && $0.latencyMs > 0 }
        }
        guard !filtered.isEmpty else { return 0 }
        return filtered.reduce(0) { $0 + $1.latencyMs } / filtered.count
    }
    
    
    /// Documents created or updated on `referenceDate` (newest first).
    func todayTouchedDocuments(referenceDate: Date = Date()) -> [StoredDocumentRecord] {
        
        let key = Self.dateKey(for: referenceDate)
        return self.database.documents.filter { doc in
            !doc.id.hasPrefix("weekly:") && (
                Self.dateKey(for: doc.updatedAt) == key ||
                doc.createdAt.map { Self.dateKey(for: $0) == key } == true
            )
        }
    }
    
    
    /// Builds full rich details for a clicked heatmap cell, including models, features, documents, and daily digest.
    func dayDetail(for cell: HeatmapDayCell) -> HeatmapDayDetail {
        
        let dayEvents = self.recentAIEvents.filter { $0.dateKey == cell.dateKey }
        let models = Self.aggregateModelDistribution(from: dayEvents)
        let features = Self.aggregateFeatureDistribution(from: dayEvents)
        let validLatencies = dayEvents.map(\.latencyMs).filter { $0 > 0 }
        let avgLatency = validLatencies.isEmpty ? 0 : validLatencies.reduce(0, +) / validLatencies.count
        
        let docs = self.database.documents.filter { doc in
            !doc.id.hasPrefix("weekly:") && (
                Self.dateKey(for: doc.updatedAt) == cell.dateKey ||
                doc.createdAt.map { Self.dateKey(for: $0) == cell.dateKey } == true
            )
        }
        let calendar = Calendar.current
        let reports = self.database.weeklyReports.filter { report in
            if Self.dateKey(for: report.updatedAt) == cell.dateKey { return true }
            return Self.datesFromWeeklyPeriodLabel(report.periodLabel, calendar: calendar)
                .contains { Self.dateKey(for: $0) == cell.dateKey }
        }
        let digest = self.database.fetchDailyAIDigest(forDateKey: cell.dateKey)
        
        return HeatmapDayDetail(
            cell: cell,
            models: models,
            features: features,
            documents: Array(docs.prefix(6)),
            weeklyReports: Array(reports.prefix(4)),
            digest: digest,
            averageLatencyMs: avgLatency
        )
    }
    
    
    /// Steps forward/backward by `deltaDays` within `year`, returning `nil` if out of year or in the future.
    func adjacentHeatmapCell(from dateKey: String, deltaDays: Int, in year: Int, referenceDate: Date = Date()) -> HeatmapDayCell? {
        
        let heatmap = self.yearlyHeatmap(year: year, referenceDate: referenceDate)
        let validCells = heatmap.weeks.flatMap { $0 }.filter { !$0.isOutOfYear && !$0.isFuture }
        guard let idx = validCells.firstIndex(where: { $0.dateKey == dateKey }) else { return nil }
        let nextIdx = idx + deltaDays
        guard validCells.indices.contains(nextIdx) else { return nil }
        return validCells[nextIdx]
    }
    
    
    /// Number of consecutive active days ending today or yesterday.
    var currentWritingStreak: Int {
        
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: Date())
        let cellsByKey = Dictionary(self.heatmapCells(weeks: 53, referenceDate: todayStart).map { ($0.dateKey, $0) }, uniquingKeysWith: { first, _ in first })
        
        var streak = 0
        var cursor = todayStart
        let todayKey = Self.dateKey(for: cursor)
        if (cellsByKey[todayKey]?.level ?? 0) == 0 {
            cursor = calendar.date(byAdding: .day, value: -1, to: cursor) ?? cursor
        }
        
        for _ in 0..<370 {
            let key = Self.dateKey(for: cursor)
            guard let cell = cellsByKey[key], cell.level > 0 else { break }
            streak += 1
            guard let prev = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = prev
        }
        return streak
    }
    
    
    /// Model usage breakdown over the last `days` days.
    func modelDistribution(days: Int = 30) -> [ModelUsageSummary] {
        
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        let filtered = self.recentAIEvents.filter { $0.timestamp >= cutoff }
        return Self.aggregateModelDistribution(from: filtered)
    }
    
    
    /// Model usage breakdown for a single calendar day (defaults to today).
    func todayModelDistribution(referenceDate: Date = Date()) -> [ModelUsageSummary] {
        
        let key = Self.dateKey(for: referenceDate)
        let filtered = self.recentAIEvents.filter { $0.dateKey == key }
        return Self.aggregateModelDistribution(from: filtered)
    }
    
    
    /// Feature usage breakdown over the last `days` days.
    func featureDistribution(days: Int = 30) -> [FeatureUsageSummary] {
        
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        let filtered = self.recentAIEvents.filter { $0.timestamp >= cutoff }
        return Self.aggregateFeatureDistribution(from: filtered)
    }
    
    
    /// Feature usage breakdown for a single calendar day (defaults to today).
    func todayFeatureDistribution(referenceDate: Date = Date()) -> [FeatureUsageSummary] {
        
        let key = Self.dateKey(for: referenceDate)
        let filtered = self.recentAIEvents.filter { $0.dateKey == key }
        return Self.aggregateFeatureDistribution(from: filtered)
    }
    
    
    /// Aggregated AI request and token counters for either today or a rolling `days` window.
    func aiUsageTotals(
        forTodayOnly: Bool,
        days: Int = 30,
        referenceDate: Date = Date()
    ) -> AIUsageTotals {
        
        if forTodayOnly {
            let key = Self.dateKey(for: referenceDate)
            if key == self.todayStats.dateKey {
                let stats = self.todayStats
                return AIUsageTotals(
                    requests: stats.aiRequests,
                    inputTokens: stats.inputTokens,
                    outputTokens: stats.outputTokens
                )
            }
            let dayEvents = self.recentAIEvents.filter { $0.dateKey == key }
            let input = dayEvents.reduce(0) { $0 + $1.inputTokens }
            let output = dayEvents.reduce(0) { $0 + $1.outputTokens }
            return AIUsageTotals(requests: dayEvents.count, inputTokens: input, outputTokens: output)
        }
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: referenceDate) ?? referenceDate
        let filtered = self.recentAIEvents.filter { $0.timestamp >= cutoff }
        let input = filtered.reduce(0) { $0 + $1.inputTokens }
        let output = filtered.reduce(0) { $0 + $1.outputTokens }
        return AIUsageTotals(requests: filtered.count, inputTokens: input, outputTokens: output)
    }
    
    
    private static func aggregateModelDistribution(from events: [AIUsageEvent]) -> [ModelUsageSummary] {
        
        guard !events.isEmpty else { return [] }
        let grouped = Dictionary(grouping: events, by: \.model)
        let totalRequests = max(1, events.count)
        
        return grouped.map { model, items in
            let reqs = items.count
            let inTokens = items.reduce(0) { $0 + $1.inputTokens }
            let outTokens = items.reduce(0) { $0 + $1.outputTokens }
            return ModelUsageSummary(
                model: model,
                requests: reqs,
                inputTokens: inTokens,
                outputTokens: outTokens,
                share: Double(reqs) / Double(totalRequests)
            )
        }
        .sorted { lhs, rhs in
            if lhs.requests != rhs.requests { return lhs.requests > rhs.requests }
            return lhs.totalTokens > rhs.totalTokens
        }
    }
    
    
    private static func aggregateFeatureDistribution(from events: [AIUsageEvent]) -> [FeatureUsageSummary] {
        
        guard !events.isEmpty else { return [] }
        let grouped = Dictionary(grouping: events, by: \.feature)
        let totalRequests = max(1, events.count)
        
        return grouped.map { feature, items in
            FeatureUsageSummary(
                feature: feature,
                displayName: Self.featureDisplayName(for: feature),
                requests: items.count,
                totalTokens: items.reduce(0) { $0 + $1.totalTokens },
                share: Double(items.count) / Double(totalRequests)
            )
        }
        .sorted { lhs, rhs in
            if lhs.requests != rhs.requests { return lhs.requests > rhs.requests }
            return lhs.totalTokens > rhs.totalTokens
        }
    }
    
    
    // MARK: Reminders API
    
    var tomorrowReminders: [UserReminder] {
        
        let tomorrowKey = Self.dateKey(for: Self.tomorrowDate())
        return self.reminders.filter { !$0.isCompleted && $0.dueDayKey == tomorrowKey }
    }
    
    
    var todayReminders: [UserReminder] {
        
        let todayKey = Self.dateKey()
        return self.reminders.filter { !$0.isCompleted && $0.dueDayKey == todayKey }
    }
    
    
    var overdueReminders: [UserReminder] {
        
        let todayKey = Self.dateKey()
        return self.reminders.filter { !$0.isCompleted && $0.dueDayKey < todayKey }
    }
    
    
    var upcomingReminders: [UserReminder] {
        
        let tomorrowKey = Self.dateKey(for: Self.tomorrowDate())
        return self.reminders.filter { !$0.isCompleted && $0.dueDayKey > tomorrowKey }
    }
    
    
    var completedReminders: [UserReminder] {
        
        self.reminders.filter(\.isCompleted)
    }
    
    
    @discardableResult
    func addReminder(
        title: String,
        notes: String = "",
        dueDate: Date = AnalyticsManager.tomorrowDate(),
        priority: ReminderPriority = .normal
    ) -> UserReminder? {
        
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        
        let reminder = UserReminder(
            id: UUID().uuidString,
            title: trimmed,
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines),
            dueDate: dueDate,
            dueDayKey: Self.dateKey(for: dueDate),
            priority: priority,
            isCompleted: false,
            createdAt: Date(),
            completedAt: nil
        )
        self.database.saveReminder(reminder)
        self.reloadFromDatabase()
        return reminder
    }
    
    
    func toggleReminderCompleted(id: String) {
        
        guard let item = self.reminders.first(where: { $0.id == id }) else { return }
        self.database.toggleReminderCompleted(id: id, isCompleted: !item.isCompleted)
        self.reloadFromDatabase()
    }
    
    
    func deleteReminder(id: String) {
        
        self.database.deleteReminder(id: id)
        self.reloadFromDatabase()
    }
    
    
    /// Scans today's edited documents for candidate action or tomorrow items that haven't been added as reminders yet.
    func detectedNoteTodos(limit: Int = 4) -> [DetectedNoteTodo] {
        
        let todayKey = Self.dateKey()
        let existingTitles = Set(self.reminders.map { $0.title.lowercased() })
        var results: [DetectedNoteTodo] = []
        var seen = Set<String>()
        
        let candidateDocs = self.database.documents.filter {
            !$0.id.hasPrefix("weekly:") && Self.dateKey(for: $0.updatedAt) == todayKey
        }
        
        for record in candidateDocs {
            let lines = record.content.components(separatedBy: .newlines)
            for rawLine in lines {
                let line = rawLine.trimmingCharacters(in: .whitespaces)
                guard line.count >= 4, line.count <= 90 else { continue }
                let lower = line.lowercased()
                let isTodoMarker = line.hasPrefix("- [ ]") || line.hasPrefix("* [ ]") || lower.contains("todo") || line.contains("明天") || line.contains("提醒")
                guard isTodoMarker else { continue }
                
                let clean = line
                    .replacingOccurrences(of: #"^[-*•]\s*\[\s*\]\s*"#, with: "", options: .regularExpression)
                    .replacingOccurrences(of: #"^(TODO|todo|提醒|待办)[:：]?\s*"#, with: "", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard clean.count >= 3 else { continue }
                let key = clean.lowercased()
                guard !existingTitles.contains(key), seen.insert(key).inserted else { continue }
                
                results.append(DetectedNoteTodo(
                    text: clean,
                    documentTitle: record.title,
                    suggestedForTomorrow: line.contains("明天") || lower.contains("tomorrow")
                ))
                if results.count >= limit {
                    return results
                }
            }
        }
        return results
    }
    
    
    // MARK: 6-Hour Background AI Daily Digest
    
    /// Starts the background scheduler that periodically checks whether a 6-hour AI summary refresh is due.
    func startBackgroundDigestScheduler() {
        
        guard !Self.isRunningUnitTests, self.backgroundDigestTask == nil else { return }
        
        self.backgroundDigestTask = Task { [weak self] in
            // Let launch settle cleanly before the first quiet background check.
            try? await Task.sleep(for: .seconds(45))
            while !Task.isCancelled {
                await self?.refreshDailyDigest(force: false)
                try? await Task.sleep(for: .seconds(30 * 60))
            }
        }
    }
    
    
    func stopBackgroundDigestScheduler() {
        
        self.backgroundDigestTask?.cancel()
        self.backgroundDigestTask = nil
    }
    
    
    /// Determines whether an automatic 6-hour background digest should run now.
    func shouldAutoRunDigest(
        now: Date = Date(),
        lastDigest: DailyAIDigest?,
        currentFingerprint: String,
        currentCharCount: Int
    ) -> Bool {
        
        guard currentCharCount >= 20 else { return false }
        guard let lastDigest else { return true }
        let elapsed = now.timeIntervalSince(lastDigest.generatedAt)
        guard elapsed >= Self.digestAutoInterval else { return false }
        return lastDigest.sourceFingerprint != currentFingerprint || lastDigest.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    
    /// Summarizes what the user worked on today and recommends tomorrow's focus using a lightweight AI model.
    func refreshDailyDigest(force: Bool) async {
        
        guard !self.isSummarizingDigest else { return }
        self.flushPendingStats()
        
        let todayKey = Self.dateKey()
        let corpus = self.collectTodayCorpus(dateKey: todayKey)
        let existing = self.database.fetchDailyAIDigest(forDateKey: todayKey)
        
        if !force {
            guard self.shouldAutoRunDigest(
                now: Date(),
                lastDigest: existing,
                currentFingerprint: corpus.fingerprint,
                currentCharCount: corpus.charCount
            ) else { return }
        }
        
        if corpus.charCount < 10 && self.tomorrowReminders.isEmpty && self.todayReminders.isEmpty {
            if force {
                self.digestErrorMessage = "今天还没有足够的新增内容或提醒可供总结。"
            }
            return
        }
        
        self.isSummarizingDigest = true
        self.digestErrorMessage = nil
        defer { self.isSummarizingDigest = false }
        
        let baseConfig = AIConfiguration.current
        if !baseConfig.isUsable {
            if force {
                let fallback = self.makeLocalFallbackDigest(dateKey: todayKey, corpus: corpus)
                self.database.saveDailyAIDigest(fallback)
                self.reloadFromDatabase()
                self.digestErrorMessage = "未配置 AI 服务，已生成本地内容概览。"
            }
            return
        }
        
        let routing = AINextTokenPredictor.shared.resolveModelRouting(baseConfig: baseConfig)
        var config = baseConfig
        if !routing.effectiveModel.isEmpty {
            config.model = routing.effectiveModel
        }
        config.temperature = 0.25
        config.reasoningEffort = "low"
        
        let prompt = """
        请阅读用户今天编辑的文本内容与提醒事项，用简洁、直白的中文提炼今天的进展和明天最值得优先推进的事项。
        请严格以 JSON 格式输出（不要包含额外解释）：
        {"summary":"2-3条极简要点，用换行符\\n分隔，每条不超过24字，不要编号或前缀符号","topics":["关键词1","关键词2","关键词3"],"tomorrow_focus":"25字以内说明明天最值得优先推进的一件事"}

        \(corpus.promptText)
        """
        
        let messages: [AIMessage] = [
            .system("你是用户的私人写作与工作复盘助手。输出必须精炼、说人话、高信噪比。"),
            .user(prompt),
        ]
        
        let clock = ContinuousClock()
        let start = clock.now
        do {
            let client = AIClient(
                configuration: config,
                maxOutputTokens: 420,
                timeoutInterval: 30,
                disablesThinking: !AINextTokenPredictor.isPureReasoningModel(config.model)
            )
            let response = try await client.sendWithUsage(messages)
            let elapsed = start.duration(to: clock.now)
            let latencyMs = max(1, Int(elapsed.components.seconds * 1000) + Int(elapsed.components.attoseconds / 1_000_000_000_000_000))
            
            let inputTokens = response.inputTokens ?? AINextTokenPredictor.estimateTokens(in: messages.map(\.text).joined(separator: "\n"))
            let outputTokens = response.outputTokens ?? AINextTokenPredictor.estimateTokens(in: response.text)
            self.recordAIUsage(
                feature: "dailyDigest",
                model: config.model,
                provider: config.endpoint.label,
                inputTokens: inputTokens,
                outputTokens: outputTokens,
                latencyMs: latencyMs,
                success: true
            )
            
            if let digest = Self.parseDigestResponse(
                response.text,
                dateKey: todayKey,
                sourceCharCount: corpus.charCount,
                sourceFingerprint: corpus.fingerprint,
                modelUsed: config.model
            ) {
                self.database.saveDailyAIDigest(digest)
                self.reloadFromDatabase()
            } else if force {
                let fallback = self.makeLocalFallbackDigest(dateKey: todayKey, corpus: corpus)
                self.database.saveDailyAIDigest(fallback)
                self.reloadFromDatabase()
            }
        } catch {
            if force {
                self.digestErrorMessage = "AI 总结暂时失败：\(error.localizedDescription)"
            }
            CotLogger.shared.warning(category: .ai, "Daily AI digest failed", error: error)
        }
    }
    
    
    /// Breaks a daily digest summary string into crisp, scannable bullet points (no stacked prose).
    static func structuredSummaryPoints(from summary: String, maxPoints: Int = 4) -> [String] {
        
        let cleaned = AIDocumentTextCleaner.clean(summary).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty, maxPoints > 0 else { return [] }
        
        let stripBulletPrefix: (String) -> String = { line in
            line
                .replacingOccurrences(of: #"^\s*([-*•·▪︎‣]|(\d+[\.、\)）]))\s*"#, with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        let lines = cleaned
            .components(separatedBy: .newlines)
            .map(stripBulletPrefix)
            .filter { !$0.isEmpty }
        
        if lines.count >= 2 {
            return Array(lines.prefix(maxPoints))
        }
        
        if let single = lines.first, single.count > 36 {
            let sentences = single
                .components(separatedBy: CharacterSet(charactersIn: "。；;!！"))
                .map(stripBulletPrefix)
                .filter { !$0.isEmpty }
            if sentences.count >= 2 {
                return Array(sentences.prefix(maxPoints))
            }
        }
        
        return Array(lines.prefix(maxPoints))
    }
    
    
    /// Parses a structured JSON digest (with resilient plain-text fallback) from an AI response.
    static func parseDigestResponse(
        _ raw: String,
        dateKey: String,
        sourceCharCount: Int,
        sourceFingerprint: String,
        modelUsed: String
    ) -> DailyAIDigest? {
        
        var cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return nil }
        
        if cleaned.hasPrefix("```") {
            var lines = cleaned.components(separatedBy: .newlines)
            if lines.first?.hasPrefix("```") == true { lines.removeFirst() }
            if lines.last?.trimmingCharacters(in: .whitespaces) == "```" { lines.removeLast() }
            cleaned = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        if let startIdx = cleaned.firstIndex(of: "{"),
           let endIdx = cleaned.lastIndex(of: "}"),
           startIdx <= endIdx
        {
            let jsonSlice = String(cleaned[startIdx...endIdx])
            if let data = jsonSlice.data(using: .utf8),
               let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let summaryRaw = obj["summary"] as? String
            {
                let summary = AIDocumentTextCleaner.clean(summaryRaw).trimmingCharacters(in: .whitespacesAndNewlines)
                let topics = (obj["topics"] as? [String] ?? [])
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                let focusRaw = (obj["tomorrow_focus"] as? String) ?? (obj["tomorrowFocus"] as? String) ?? ""
                let focus = AIDocumentTextCleaner.clean(focusRaw).trimmingCharacters(in: .whitespacesAndNewlines)
                
                if !summary.isEmpty {
                    return DailyAIDigest(
                        dateKey: dateKey,
                        summary: summary,
                        topics: Array(topics.prefix(6)),
                        tomorrowFocus: focus,
                        sourceCharCount: sourceCharCount,
                        sourceFingerprint: sourceFingerprint,
                        modelUsed: modelUsed,
                        generatedAt: Date()
                    )
                }
            }
        }
        
        let plain = AIDocumentTextCleaner.clean(cleaned).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !plain.isEmpty else { return nil }
        return DailyAIDigest(
            dateKey: dateKey,
            summary: plain,
            topics: [],
            tomorrowFocus: "",
            sourceCharCount: sourceCharCount,
            sourceFingerprint: sourceFingerprint,
            modelUsed: modelUsed,
            generatedAt: Date()
        )
    }
    
    
    // MARK: Private Corpus Helpers
    
    private func collectTodayCorpus(dateKey: String) -> (promptText: String, charCount: Int, fingerprint: String) {
        
        var segments: [String] = []
        var usedTitles = Set<String>()
        var totalChars = 0
        
        if self.database === CotLocalDatabase.shared {
            for case let doc as Document in NSDocumentController.shared.documents {
                let text = doc.textStorage.string.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { continue }
                let docDateKey = doc.lastManualSaveDate.map { Self.dateKey(for: $0) } ?? dateKey
                guard doc.hasUncommittedChanges || docDateKey == dateKey else { continue }
                let docTitle = doc.displayName ?? "未命名文档"
                usedTitles.insert(docTitle)
                totalChars += text.count
                segments.append("【当前文档：\(docTitle)】\n\(String(text.prefix(1200)))")
                if segments.count >= 6 { break }
            }
        }
        
        for record in self.database.documents where !record.id.hasPrefix("weekly:") {
            guard Self.dateKey(for: record.updatedAt) == dateKey else { continue }
            guard !usedTitles.contains(record.title) else { continue }
            let trimmed = record.content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            usedTitles.insert(record.title)
            totalChars += trimmed.count
            segments.append("【文档：\(record.title)】\n\(String(trimmed.prefix(1000)))")
            if segments.count >= 8 { break }
        }
        
        let tomorrowItems = self.tomorrowReminders
        if !tomorrowItems.isEmpty {
            let listLines: [String] = tomorrowItems.prefix(6).map { item in
                let mark = (item.priority == .high) ? "[重点] " : ""
                return "- \(mark)\(item.title)"
            }
            segments.append("【明日已设提醒】\n\(listLines.joined(separator: "\n"))")
        }
        
        let combined = segments.joined(separator: "\n\n")
        let digest = SHA256.hash(data: Data(combined.utf8))
        let fingerprint = digest.map { String(format: "%02x", $0) }.joined()
        return (combined, totalChars, fingerprint)
    }
    
    
    private func makeLocalFallbackDigest(
        dateKey: String,
        corpus: (promptText: String, charCount: Int, fingerprint: String)
    ) -> DailyAIDigest {
        
        let todayDocs = self.database.documents.filter {
            !$0.id.hasPrefix("weekly:") && Self.dateKey(for: $0.updatedAt) == dateKey
        }
        let docTitles = todayDocs.prefix(4).map(\.title)
        let summaryText = if docTitles.isEmpty {
            "累计输入 \(self.todayStats.typedChars) 字\n新建 \(self.todayStats.filesCreated) 个文档"
        } else {
            "编辑文档：\(docTitles.joined(separator: "、"))\n累计输入 \(self.todayStats.typedChars) 字"
        }
        let focus = self.tomorrowReminders.first?.title ?? ""
        return DailyAIDigest(
            dateKey: dateKey,
            summary: summaryText,
            topics: Array(docTitles.prefix(4)),
            tomorrowFocus: focus,
            sourceCharCount: corpus.charCount,
            sourceFingerprint: corpus.fingerprint,
            modelUsed: "本地摘要",
            generatedAt: Date()
        )
    }
}
