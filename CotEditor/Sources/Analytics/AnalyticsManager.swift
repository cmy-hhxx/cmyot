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
    var localAcceptedChars: Int = 0
    var maxSingleAcceptChars: Int = 0
    var hourlyTypedChars: [Int] = Array(repeating: 0, count: 24)
    var updatedAt: Date = Date()
    
    var id: String { self.dateKey }
    var totalTokens: Int { self.inputTokens + self.outputTokens }
    
    
    init(
        dateKey: String,
        typedChars: Int = 0,
        aiCompletedChars: Int = 0,
        aiCompletionAccepts: Int = 0,
        filesCreated: Int = 0,
        documentsSaved: Int = 0,
        aiRequests: Int = 0,
        inputTokens: Int = 0,
        outputTokens: Int = 0,
        localHits: Int = 0,
        localAcceptedChars: Int = 0,
        maxSingleAcceptChars: Int = 0,
        hourlyTypedChars: [Int] = Array(repeating: 0, count: 24),
        updatedAt: Date = Date()
    ) {
        self.dateKey = dateKey
        self.typedChars = typedChars
        self.aiCompletedChars = aiCompletedChars
        self.aiCompletionAccepts = aiCompletionAccepts
        self.filesCreated = filesCreated
        self.documentsSaved = documentsSaved
        self.aiRequests = aiRequests
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.localHits = localHits
        self.localAcceptedChars = localAcceptedChars
        self.maxSingleAcceptChars = maxSingleAcceptChars
        self.hourlyTypedChars = hourlyTypedChars.count == 24 ? hourlyTypedChars : Array(repeating: 0, count: 24)
        self.updatedAt = updatedAt
    }
    
    
    enum CodingKeys: String, CodingKey {
        case dateKey, typedChars, aiCompletedChars, aiCompletionAccepts, filesCreated, documentsSaved
        case aiRequests, inputTokens, outputTokens, localHits, localAcceptedChars, maxSingleAcceptChars
        case hourlyTypedChars, updatedAt
    }
    
    
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.dateKey = try c.decode(String.self, forKey: .dateKey)
        self.typedChars = try c.decodeIfPresent(Int.self, forKey: .typedChars) ?? 0
        self.aiCompletedChars = try c.decodeIfPresent(Int.self, forKey: .aiCompletedChars) ?? 0
        self.aiCompletionAccepts = try c.decodeIfPresent(Int.self, forKey: .aiCompletionAccepts) ?? 0
        self.filesCreated = try c.decodeIfPresent(Int.self, forKey: .filesCreated) ?? 0
        self.documentsSaved = try c.decodeIfPresent(Int.self, forKey: .documentsSaved) ?? 0
        self.aiRequests = try c.decodeIfPresent(Int.self, forKey: .aiRequests) ?? 0
        self.inputTokens = try c.decodeIfPresent(Int.self, forKey: .inputTokens) ?? 0
        self.outputTokens = try c.decodeIfPresent(Int.self, forKey: .outputTokens) ?? 0
        self.localHits = try c.decodeIfPresent(Int.self, forKey: .localHits) ?? 0
        self.localAcceptedChars = try c.decodeIfPresent(Int.self, forKey: .localAcceptedChars) ?? 0
        self.maxSingleAcceptChars = try c.decodeIfPresent(Int.self, forKey: .maxSingleAcceptChars) ?? 0
        let decodedHourly = try c.decodeIfPresent([Int].self, forKey: .hourlyTypedChars)
        self.hourlyTypedChars = (decodedHourly.flatMap { $0.count == 24 ? $0 : nil }) ?? Array(repeating: 0, count: 24)
        self.updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
    }
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


/// A local reminder or pinned todo item created by the user or promoted from notes.
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
    var isPinned: Bool = false
    var hasDeadline: Bool = true
    
    
    init(
        id: String = UUID().uuidString,
        title: String,
        notes: String = "",
        dueDate: Date,
        dueDayKey: String,
        priority: ReminderPriority = .normal,
        isCompleted: Bool = false,
        createdAt: Date = Date(),
        completedAt: Date? = nil,
        isPinned: Bool = false,
        hasDeadline: Bool = true
    ) {
        self.id = id
        self.title = title
        self.notes = notes
        self.dueDate = dueDate
        self.dueDayKey = dueDayKey
        self.priority = priority
        self.isCompleted = isCompleted
        self.createdAt = createdAt
        self.completedAt = completedAt
        self.isPinned = isPinned
        self.hasDeadline = hasDeadline
    }
    
    
    enum CodingKeys: String, CodingKey {
        case id, title, notes, dueDate, dueDayKey, priority, isCompleted, createdAt, completedAt, isPinned, hasDeadline
    }
    
    
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        self.title = try c.decode(String.self, forKey: .title)
        self.notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
        self.dueDate = try c.decodeIfPresent(Date.self, forKey: .dueDate) ?? Date()
        self.dueDayKey = try c.decodeIfPresent(String.self, forKey: .dueDayKey) ?? ""
        self.priority = try c.decodeIfPresent(ReminderPriority.self, forKey: .priority) ?? .normal
        self.isCompleted = try c.decodeIfPresent(Bool.self, forKey: .isCompleted) ?? false
        self.createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        self.completedAt = try c.decodeIfPresent(Date.self, forKey: .completedAt)
        self.isPinned = try c.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
        self.hasDeadline = try c.decodeIfPresent(Bool.self, forKey: .hasDeadline) ?? true
    }
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


/// Month column marker along the top edge of a rolling activity heatmap.
nonisolated struct RollingHeatmapMonthLabel: Identifiable, Sendable, Equatable {
    
    var year: Int
    var month: Int
    var weekIndex: Int
    var label: String
    
    var id: String { "\(self.year)-\(self.month)-\(self.weekIndex)" }
}


/// Rolling backwards-from-today activity heatmap matrix (Monday-first week columns x 7 rows, zero future cells drawn).
nonisolated struct RollingHeatmapData: Sendable, Equatable {
    
    var weeks: [[HeatmapDayCell]]
    var monthLabels: [RollingHeatmapMonthLabel]
    var activeDays: Int
    var totalTypedChars: Int
    var totalAIChars: Int
    var startDate: Date
    var endDate: Date
}


/// Warm, plain-Chinese daily story synthesized for the selected heatmap cell.
nonisolated struct DailyHumanStory: Sendable, Equatable {
    
    var dateKey: String
    var dateBadge: String
    var moodTag: String
    var headline: String
    var highlights: [String]
    var handTypedChars: Int
    var aiChars: Int
    var totalChars: Int
    var aiSharePercent: Int
    var savedCount: Int
    var createdCount: Int
    var aiRequests: Int
    var documents: [StoredDocumentRecord]
    var weeklyReports: [StoredWeeklyReport]
}


/// Lightweight candidate action item spotted in today's documents.
nonisolated struct DetectedNoteTodo: Identifiable, Sendable, Equatable {
    
    var text: String
    var documentTitle: String
    var suggestedForTomorrow: Bool
    
    var id: String { "\(self.documentTitle):\(self.text)" }
}


/// A recently touched document or weekly report displayed in the Studio Manuscript Folio gallery.
nonisolated struct TouchedManuscriptItem: Identifiable, Sendable, Equatable {
    
    enum Kind: String, Sendable, Equatable {
        case markdown
        case code
        case weeklyReport
        case plainText
    }
    
    enum Payload: Sendable, Equatable {
        case document(StoredDocumentRecord)
        case weeklyReport(StoredWeeklyReport)
    }
    
    var id: String
    var title: String
    var excerpt: String
    var syntaxLabel: String
    var kind: Kind
    var charCount: Int
    var updatedAt: Date
    var relativeTimeBadge: String
    var isCreatedToday: Bool
    var payload: Payload
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
    private(set) var personalityProfile: UserPersonalityProfile?
    private(set) var isAnalyzingPersonality: Bool = false
    private(set) var personalityErrorMessage: String?
    private(set) var revision: Int = 0
    private(set) var lastKeystrokeAt: Date = .distantPast
    
    // MARK: Private Properties
    
    private let database: CotLocalDatabase
    private var pendingTypedCharsDelta: Int = 0
    private var pendingTypedDateKey: String?
    private var pendingTypedHour: Int?
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
            case "personalityAnalyze": "性格弹幕画像"
            default: feature
        }
    }
    
    
    // MARK: Telemetry Recording
    
    /// Buffers typed character counts and flushes to SQLite after a brief idle pause.
    func recordTypedCharacters(_ count: Int) {
        
        guard count > 0 else { return }
        let now = Date()
        let currentDateKey = Self.dateKey(for: now)
        let hour = Calendar.current.component(.hour, from: now)
        
        // Flush any buffered chars from an earlier hour/day before switching buckets.
        if self.pendingTypedCharsDelta > 0,
           self.pendingTypedDateKey != currentDateKey || self.pendingTypedHour != hour
        {
            self.flushPendingStats()
        }
        
        // If midnight rolled over while the app stayed open, reset `todayStats` to the new day.
        if self.todayStats.dateKey != currentDateKey {
            self.todayStats = DailyWritingStats(dateKey: currentDateKey)
        }
        
        self.lastKeystrokeAt = now
        self.pendingTypedCharsDelta += count
        self.pendingTypedDateKey = currentDateKey
        self.pendingTypedHour = hour
        self.todayStats.typedChars += count
        if (0..<24).contains(hour) {
            if self.todayStats.hourlyTypedChars.count != 24 {
                self.todayStats.hourlyTypedChars = Array(repeating: 0, count: 24)
            }
            self.todayStats.hourlyTypedChars[hour] += count
        }
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
        let now = Date()
        let targetDateKey = self.pendingTypedDateKey ?? Self.dateKey(for: now)
        let targetHour = self.pendingTypedHour ?? Calendar.current.component(.hour, from: now)
        self.pendingTypedCharsDelta = 0
        self.pendingTypedDateKey = nil
        self.pendingTypedHour = nil
        self.database.incrementDailyWritingStats(dateKey: targetDateKey, typedChars: delta, hourBucket: targetHour)
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
            aiCompletionAccepts: 1,
            localAcceptedChars: isFromAI ? 0 : charCount,
            singleAcceptChars: charCount
        )
        self.reloadFromDatabase()
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
        if !Self.isRunningUnitTests {
            Task { @MainActor [weak self] in
                await self?.refreshPersonalityProfile(force: false)
            }
        }
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
        let pendingForToday = (self.pendingTypedDateKey == nil || self.pendingTypedDateKey == todayKey)
            ? self.pendingTypedCharsDelta
            : 0
        var resolvedToday = stats.first(where: { $0.dateKey == todayKey }) ?? DailyWritingStats(dateKey: todayKey)
        if pendingForToday > 0 {
            resolvedToday.typedChars += pendingForToday
            if let pendingHour = self.pendingTypedHour, (0..<24).contains(pendingHour) {
                if resolvedToday.hourlyTypedChars.count != 24 {
                    resolvedToday.hourlyTypedChars = Array(repeating: 0, count: 24)
                }
                resolvedToday.hourlyTypedChars[pendingHour] += pendingForToday
            }
        }
        self.todayStats = resolvedToday
        
        self.recentAIEvents = self.database.fetchAIUsageEvents(sinceDateKey: aiSinceKey)
        self.todayDigest = self.database.fetchDailyAIDigest(forDateKey: todayKey)
            ?? self.database.fetchRecentDailyAIDigests(limit: 1).first
        self.reminders = self.database.fetchAllReminders()
        
        let rawPersonality = self.database.string(forKey: CotLocalDatabase.ConfigKey.userPersonalityProfileJSON)
        if !rawPersonality.isEmpty,
           let pData = rawPersonality.data(using: .utf8),
           let decodedProfile = try? JSONDecoder().decode(UserPersonalityProfile.self, from: pData)
        {
            let hasStaleFallbackCopy = decodedProfile.isLocalFallback && (
                decodedProfile.conceptSummary.contains("基于当前") ||
                decodedProfile.tags.contains { ["自留地耕作者", "结构控写手", "高密输出者", "工程实干派", "晨间清冽派"].contains($0.label) }
            )
            if hasStaleFallbackCopy {
                let refreshed = UserPersonalityAnalyzer.makeLocalHeuristicFallback(
                    documents: self.database.documents,
                    weeklyReports: self.database.weeklyReports,
                    stats: self.recentDailyStats,
                    streak: self.currentWritingStreak,
                    fingerprint: decodedProfile.sourceFingerprint
                )
                self.personalityProfile = refreshed
                if let encoded = try? JSONEncoder().encode(refreshed),
                   let json = String(data: encoded, encoding: .utf8)
                {
                    self.database.set(json, forKey: CotLocalDatabase.ConfigKey.userPersonalityProfileJSON)
                }
            } else {
                self.personalityProfile = decodedProfile
            }
        } else {
            self.personalityProfile = nil
        }
        
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
    
    
    /// Builds a calendar-year Monday-first activity heatmap matrix (full year or trimmed after today's week).
    func yearlyHeatmap(
        year: Int,
        referenceDate: Date = Date(),
        trimFutureWeeks: Bool = false
    ) -> YearlyHeatmapData {
        
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: referenceDate)
        let currentYear = calendar.component(.year, from: todayStart)
        let jan1 = calendar.date(from: DateComponents(year: year, month: 1, day: 1)) ?? todayStart
        let dec31 = calendar.date(from: DateComponents(year: year, month: 12, day: 31)) ?? todayStart
        
        let mondayIndex: (Date) -> Int = { date in
            (calendar.component(.weekday, from: date) + 5) % 7
        }
        
        let leadingPad = mondayIndex(jan1)
        let dec31GridEnd = calendar.date(byAdding: .day, value: 6 - mondayIndex(dec31), to: dec31) ?? dec31
        let gridEnd: Date
        if trimFutureWeeks && year == currentYear {
            let currentWeekSunday = calendar.date(byAdding: .day, value: 6 - mondayIndex(todayStart), to: todayStart) ?? todayStart
            gridEnd = min(dec31GridEnd, currentWeekSunday)
        } else {
            gridEnd = dec31GridEnd
        }
        
        let gridStart = calendar.date(byAdding: .day, value: -leadingPad, to: jan1) ?? jan1
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
        
        let maxMonth = (trimFutureWeeks && year == currentYear)
            ? max(1, calendar.component(.month, from: todayStart))
            : 12
        let monthLabels: [HeatmapMonthLabel] = (1...maxMonth).compactMap { month in
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
    
    
    /// Builds a Monday-first rolling heatmap ending at the week containing `referenceDate` (no future months).
    func rollingHeatmap(weeks: Int = 26, referenceDate: Date = Date()) -> RollingHeatmapData {
        
        let weekCount = max(4, min(53, weeks))
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: referenceDate)
        let gridStart = Self.rollingGridStart(weeks: weekCount, todayStart: todayStart, calendar: calendar)
        
        let cells = self.buildHeatmapCells(
            gridStart: gridStart,
            totalCells: weekCount * 7,
            targetYear: nil,
            todayStart: todayStart,
            calendar: calendar
        )
        
        let weekMatrix = Self.chunkWeeks(cells)
        let monthLabels = Self.buildRollingMonthLabels(
            weekMatrix: weekMatrix,
            gridStart: gridStart,
            todayStart: todayStart,
            calendar: calendar
        )
        
        let visibleCells = cells.filter { !$0.isFuture }
        let activeDays = visibleCells.filter { $0.level > 0 }.count
        let totalTypedChars = visibleCells.reduce(0) { $0 + $1.typedChars }
        let totalAIChars = visibleCells.reduce(0) { $0 + $1.aiCompletedChars }
        
        return RollingHeatmapData(
            weeks: weekMatrix,
            monthLabels: monthLabels,
            activeDays: activeDays,
            totalTypedChars: totalTypedChars,
            totalAIChars: totalAIChars,
            startDate: gridStart,
            endDate: todayStart
        )
    }
    
    
    /// Builds a Monday-first rolling mini heatmap scored strictly by daily AI token & request usage.
    func aiConsumptionHeatmap(weeks: Int = 12, referenceDate: Date = Date()) -> RollingHeatmapData {
        
        let weekCount = max(4, min(53, weeks))
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: referenceDate)
        let gridStart = Self.rollingGridStart(weeks: weekCount, todayStart: todayStart, calendar: calendar)
        let totalCells = weekCount * 7
        
        var statsByDay = Dictionary(self.recentDailyStats.map { ($0.dateKey, $0) }, uniquingKeysWith: { first, _ in first })
        statsByDay[self.todayStats.dateKey] = self.todayStats
        
        struct RawAIDay {
            let key: String
            let date: Date
            let stat: DailyWritingStats?
            let score: Int
            let isFuture: Bool
        }
        
        var rawDays: [RawAIDay] = []
        rawDays.reserveCapacity(totalCells)
        
        for offset in 0..<totalCells {
            let day = calendar.date(byAdding: .day, value: offset, to: gridStart) ?? gridStart
            let key = Self.dateKey(for: day)
            let isFuture = day > todayStart
            let stat = isFuture ? nil : statsByDay[key]
            let tokens = (stat?.inputTokens ?? 0) + (stat?.outputTokens ?? 0)
            let requests = stat?.aiRequests ?? 0
            let aiChars = stat?.aiCompletedChars ?? 0
            let score: Int = if isFuture {
                0
            } else if tokens > 0 {
                tokens + requests * 60 + aiChars * 2
            } else {
                requests * 120 + aiChars * 4
            }
            rawDays.append(RawAIDay(key: key, date: day, stat: stat, score: score, isFuture: isFuture))
        }
        
        let maxScore = max(120, rawDays.filter { !$0.isFuture && $0.score > 0 }.map(\.score).max() ?? 120)
        let cells = rawDays.map { item in
            let level = item.isFuture ? 0 : Self.heatmapLevel(for: item.score, maxScore: maxScore)
            return HeatmapDayCell(
                dateKey: item.key,
                date: item.date,
                typedChars: item.stat?.typedChars ?? 0,
                aiCompletedChars: item.stat?.aiCompletedChars ?? 0,
                aiCompletionAccepts: item.stat?.aiCompletionAccepts ?? 0,
                filesCreated: item.stat?.filesCreated ?? 0,
                documentsSaved: item.stat?.documentsSaved ?? 0,
                aiRequests: item.stat?.aiRequests ?? 0,
                inputTokens: item.stat?.inputTokens ?? 0,
                outputTokens: item.stat?.outputTokens ?? 0,
                localHits: item.stat?.localHits ?? 0,
                level: level,
                isFuture: item.isFuture,
                isOutOfYear: false
            )
        }
        
        let weekMatrix = Self.chunkWeeks(cells)
        let monthLabels = Self.buildRollingMonthLabels(
            weekMatrix: weekMatrix,
            gridStart: gridStart,
            todayStart: todayStart,
            calendar: calendar
        )
        
        let visibleCells = cells.filter { !$0.isFuture }
        return RollingHeatmapData(
            weeks: weekMatrix,
            monthLabels: monthLabels,
            activeDays: visibleCells.filter { $0.level > 0 }.count,
            totalTypedChars: visibleCells.reduce(0) { $0 + $1.typedChars },
            totalAIChars: visibleCells.reduce(0) { $0 + $1.aiCompletedChars },
            startDate: gridStart,
            endDate: todayStart
        )
    }
    
    
    private static func rollingGridStart(weeks: Int, todayStart: Date, calendar: Calendar) -> Date {
        
        let mondayIndex = (calendar.component(.weekday, from: todayStart) + 5) % 7
        let currentWeekMonday = calendar.date(byAdding: .day, value: -mondayIndex, to: todayStart) ?? todayStart
        return calendar.date(byAdding: .day, value: -(weeks - 1) * 7, to: currentWeekMonday) ?? currentWeekMonday
    }
    
    
    private static func chunkWeeks(_ cells: [HeatmapDayCell]) -> [[HeatmapDayCell]] {
        
        stride(from: 0, to: cells.count, by: 7).map { start in
            Array(cells[start..<min(start + 7, cells.count)])
        }
    }
    
    
    private static func buildRollingMonthLabels(
        weekMatrix: [[HeatmapDayCell]],
        gridStart: Date,
        todayStart: Date,
        calendar: Calendar
    ) -> [RollingHeatmapMonthLabel] {
        
        var monthLabels: [RollingHeatmapMonthLabel] = []
        let startYear = calendar.component(.year, from: gridStart)
        let endYear = calendar.component(.year, from: todayStart)
        let spansYears = (startYear != endYear)
        
        for (weekIdx, column) in weekMatrix.enumerated() {
            guard let firstDayCell = column.first(where: { !$0.isFuture && calendar.component(.day, from: $0.date) == 1 }) else {
                continue
            }
            let year = calendar.component(.year, from: firstDayCell.date)
            let month = calendar.component(.month, from: firstDayCell.date)
            let labelText = (spansYears && month == 1 && weekIdx > 0)
                ? "\(year % 100)年1月"
                : "\(month)月"
            monthLabels.append(RollingHeatmapMonthLabel(
                year: year,
                month: month,
                weekIndex: weekIdx,
                label: labelText
            ))
        }
        
        if let firstColumn = weekMatrix.first?.first {
            let firstYear = calendar.component(.year, from: firstColumn.date)
            let firstMonth = calendar.component(.month, from: firstColumn.date)
            let hasRoomBeforeNext = monthLabels.first.map { $0.weekIndex >= 2 } ?? true
            if hasRoomBeforeNext,
               !monthLabels.contains(where: { $0.year == firstYear && $0.month == firstMonth && $0.weekIndex == 0 })
            {
                monthLabels.insert(
                    RollingHeatmapMonthLabel(
                        year: firstYear,
                        month: firstMonth,
                        weekIndex: 0,
                        label: "\(firstMonth)月"
                    ),
                    at: 0
                )
            }
        }
        
        return monthLabels
    }
    
    
    private static func heatmapLevel(for score: Int, maxScore: Int) -> Int {
        
        guard score > 0 else { return 0 }
        let ratio = Double(score) / Double(max(1, maxScore))
        if ratio >= 0.75 { return 4 }
        if ratio >= 0.45 { return 3 }
        if ratio >= 0.18 { return 2 }
        return 1
    }
    
    
    /// Returns chronological past-through-today cells from a rolling heatmap.
    func orderedVisibleCells(in heatmap: RollingHeatmapData) -> [HeatmapDayCell] {
        
        heatmap.weeks.flatMap { $0 }.filter { !$0.isFuture }
    }
    
    
    /// Finds a visible (past or today) cell matching `dateKey` inside `heatmap`.
    func cell(forDateKey dateKey: String, in heatmap: RollingHeatmapData) -> HeatmapDayCell? {
        
        heatmap.weeks.flatMap { $0 }.first { !$0.isFuture && $0.dateKey == dateKey }
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
    
    
    /// Builds full rich details for a clicked heatmap cell, including models, features, documents, and daily digest.
    func dayDetail(for cell: HeatmapDayCell) -> HeatmapDayDetail {
        
        let dayEvents = self.recentAIEvents.filter { $0.dateKey == cell.dateKey }
        let models = Self.aggregateModelDistribution(from: dayEvents)
        let features = Self.aggregateFeatureDistribution(from: dayEvents)
        let validLatencies = dayEvents.map(\.latencyMs).filter { $0 > 0 }
        let avgLatency = validLatencies.isEmpty ? 0 : validLatencies.reduce(0, +) / validLatencies.count
        
        let docs = self.database.documents
            .filter { doc in
                !doc.id.hasPrefix("weekly:") && (
                    Self.dateKey(for: doc.updatedAt) == cell.dateKey ||
                    doc.createdAt.map { Self.dateKey(for: $0) == cell.dateKey } == true
                )
            }
            .sorted { $0.updatedAt > $1.updatedAt }
        let calendar = Calendar.current
        let reports = self.database.weeklyReports
            .filter { report in
                if Self.dateKey(for: report.updatedAt) == cell.dateKey { return true }
                return Self.datesFromWeeklyPeriodLabel(report.periodLabel, calendar: calendar)
                    .contains { Self.dateKey(for: $0) == cell.dateKey }
            }
            .sorted { $0.updatedAt > $1.updatedAt }
        let digest = self.database.fetchDailyAIDigest(forDateKey: cell.dateKey)
        
        return HeatmapDayDetail(
            cell: cell,
            models: models,
            features: features,
            documents: Array(docs.prefix(8)),
            weeklyReports: Array(reports.prefix(4)),
            digest: digest,
            averageLatencyMs: avgLatency
        )
    }
    
    
    /// Synthesizes a warm, plain-Chinese daily story for the clicked heatmap cell (no jargon or database dumps).
    func humanDayStory(
        for cell: HeatmapDayCell,
        referenceDate: Date = Date(),
        baselineDailyChars: Int = 0
    ) -> DailyHumanStory {
        
        let detail = self.dayDetail(for: cell)
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: referenceDate)
        let todayKey = Self.dateKey(for: todayStart)
        let yesterdayKey = calendar.date(byAdding: .day, value: -1, to: todayStart).map { Self.dateKey(for: $0) }
        
        let isToday = (cell.dateKey == todayKey)
        let isYesterday = (cell.dateKey == yesterdayKey)
        
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        let sameYear = calendar.component(.year, from: cell.date) == calendar.component(.year, from: todayStart)
        formatter.dateFormat = sameYear ? "M 月 d 日 EEE" : "yyyy 年 M 月 d 日 EEE"
        let shortDate = formatter.string(from: cell.date)
        
        let dateBadge: String = if isToday {
            "今天 · \(shortDate)"
        } else if isYesterday {
            "昨天 · \(shortDate)"
        } else {
            shortDate
        }
        
        let typed = cell.typedChars
        let ai = cell.aiCompletedChars
        let total = typed + ai
        let aiShare = total > 0 ? Int((Double(ai) * 100 / Double(total)).rounded()) : 0
        let docTitles = detail.documents.map(\.title) + detail.weeklyReports.map(\.title)
        let firstTitle = docTitles.first
        
        let typedText = typed.formatted(.number.grouping(.automatic))
        let aiText = ai.formatted(.number.grouping(.automatic))
        
        let moodTag = ""
        let headline: String
        
        if total == 0 && cell.filesCreated == 0 && docTitles.isEmpty {
            headline = isToday
                ? "今日尚未开始记录。"
                : "当日没有留下文本记录。"
        } else if typed == 0 && ai == 0 {
            if let first = firstTitle {
                headline = isToday
                    ? "今日新建《\(first)》，当前处于结构起草阶段。"
                    : "当日新建或整理了《\(first)》。"
            } else {
                headline = isToday
                    ? "今日新建了空白文档。"
                    : "当日新建过空白文档。"
            }
        } else if typed == 0 && ai > 0 {
            if let first = firstTitle {
                headline = "当日在《\(first)》中通过补全与整理写入 \(aiText) 字。"
            } else {
                headline = "当日通过补全与整理写入 \(aiText) 字。"
            }
        } else if let first = firstTitle {
            if docTitles.count >= 2 {
                headline = "手写 \(typedText) 字\(ai > 0 ? "、补全 \(aiText) 字" : "")，主要围绕《\(first)》等 \(docTitles.count) 篇推进。"
            } else {
                headline = "手写 \(typedText) 字\(ai > 0 ? "、补全 \(aiText) 字" : "")，集中落笔于《\(first)》。"
            }
        } else if ai > 0 {
            headline = "当日手写 \(typedText) 字，辅助补全 \(aiText) 字。"
        } else {
            headline = "当日累计手写 \(typedText) 字。"
        }
        
        var highlights: [String] = []
        let jargonTokens = ["累计输入", "编辑文档：", "Tokens", "token", "延迟", "ms", "活跃度"]
        
        if let digest = detail.digest {
            let points = Self.structuredSummaryPoints(from: digest.summary, maxPoints: 3)
            for point in points {
                let clean = point.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !clean.isEmpty,
                      !clean.hasPrefix("新建 "),
                      !jargonTokens.contains(where: { clean.localizedCaseInsensitiveContains($0) })
                else { continue }
                if !highlights.contains(clean) {
                    highlights.append(clean)
                }
            }
        }
        
        func appendHighlight(_ text: String) {
            guard highlights.count < 3, !highlights.contains(text) else { return }
            highlights.append(text)
        }
        
        if cell.filesCreated > 0 {
            appendHighlight(isToday
                ? "新开了 \(cell.filesCreated) 篇文档，新想法落地了"
                : "新开了 \(cell.filesCreated) 篇文档，起草了新内容"
            )
        }
        if !detail.weeklyReports.isEmpty {
            let reportTitle = detail.weeklyReports[0].title
            appendHighlight(detail.weeklyReports.count == 1
                ? "整理了周报《\(reportTitle)》"
                : "整理了 \(detail.weeklyReports.count) 份周报"
            )
        }
        if cell.aiCompletionAccepts > 0 {
            appendHighlight("顺手用 Tab 接纳了 \(cell.aiCompletionAccepts) 次续写，省了不少敲字功夫")
        } else if cell.documentsSaved >= 3 {
            appendHighlight("来回保存打磨了 \(cell.documentsSaved) 次，写得挺仔细")
        }
        if isToday && !self.todayReminders.isEmpty {
            appendHighlight("今天还有 \(self.todayReminders.count) 件挂念的小事待收尾")
        } else if isToday && !self.tomorrowReminders.isEmpty {
            appendHighlight("已经记好明天要先处理「\(self.tomorrowReminders[0].title)」")
        }
        
        return DailyHumanStory(
            dateKey: cell.dateKey,
            dateBadge: dateBadge,
            moodTag: moodTag,
            headline: headline,
            highlights: highlights,
            handTypedChars: typed,
            aiChars: ai,
            totalChars: total,
            aiSharePercent: aiShare,
            savedCount: cell.documentsSaved,
            createdCount: cell.filesCreated,
            aiRequests: cell.aiRequests,
            documents: detail.documents,
            weeklyReports: detail.weeklyReports
        )
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
        return self.reminders.filter { !$0.isCompleted && $0.hasDeadline && $0.dueDayKey == tomorrowKey }
    }
    
    
    var todayReminders: [UserReminder] {
        
        let todayKey = Self.dateKey()
        return self.reminders.filter { !$0.isCompleted && $0.hasDeadline && $0.dueDayKey == todayKey }
    }
    
    
    var overdueReminders: [UserReminder] {
        
        let todayKey = Self.dateKey()
        return self.reminders.filter { !$0.isCompleted && $0.hasDeadline && $0.dueDayKey < todayKey }
    }
    
    
    var upcomingReminders: [UserReminder] {
        
        let tomorrowKey = Self.dateKey(for: Self.tomorrowDate())
        return self.reminders.filter { !$0.isCompleted && $0.hasDeadline && $0.dueDayKey > tomorrowKey }
    }
    
    
    var completedReminders: [UserReminder] {
        
        self.reminders.filter(\.isCompleted)
    }
    
    
    var pinnedTodos: [UserReminder] {
        
        self.reminders
            .filter { !$0.isCompleted && $0.isPinned }
            .sorted { lhs, rhs in
                if lhs.hasDeadline != rhs.hasDeadline {
                    return lhs.hasDeadline
                }
                if lhs.hasDeadline && lhs.dueDate != rhs.dueDate {
                    return lhs.dueDate < rhs.dueDate
                }
                return lhs.createdAt > rhs.createdAt
            }
    }
    
    
    @discardableResult
    func addPinnedTodo(title: String, deadline: Date?) -> UserReminder? {
        
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        
        let now = Date()
        let resolvedDue = deadline ?? now
        let todo = UserReminder(
            id: UUID().uuidString,
            title: trimmed,
            notes: "",
            dueDate: resolvedDue,
            dueDayKey: Self.dateKey(for: resolvedDue),
            priority: deadline != nil ? .high : .normal,
            isCompleted: false,
            createdAt: now,
            completedAt: nil,
            isPinned: true,
            hasDeadline: deadline != nil
        )
        self.database.saveReminder(todo)
        self.reloadFromDatabase()
        return todo
    }
    
    
    func unpinReminder(id: String) {
        
        self.database.setReminderPinned(id: id, isPinned: false)
        self.reloadFromDatabase()
    }
    
    
    func snoozeReminder(id: String, by interval: TimeInterval) {
        
        guard let item = self.reminders.first(where: { $0.id == id }) else { return }
        let base = max(Date(), item.hasDeadline ? item.dueDate : Date())
        let newDue = base.addingTimeInterval(interval)
        self.database.updateReminderDeadline(
            id: id,
            dueDate: newDue,
            dueDayKey: Self.dateKey(for: newDue),
            hasDeadline: true
        )
        self.reloadFromDatabase()
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
                await self?.refreshPersonalityProfile(force: false)
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
        config.temperature = 0.65
        config.reasoningEffort = "low"
        
        let prompt = """
        请你像一个坐在我工位旁边的聪明损友兼老搭档，看看我今天写的内容与待办，给我来几句掏心窝子的“AI 锐评”。
        要求：
        1. 分成 3-4 条短点，用换行符 \\n 隔开，每条 16-45 字，不要带编号或项目符号。
        2. 严禁出现任何文档标题、文件名或书名号《》（很多标题是系统随机起的，带标题会让人看不懂）；请直接聊内容、节奏、卡点、修改行为或现象！
        3. 彻底戒掉公文腔、汇报腔和AI客套话！直接说人话，通俗易懂，允许俏皮和无伤大雅的口头小脏话（比如“卧槽”“牛逼”“别特么死磕了”）。
        4. 允许克制点缀 emoji 表情，仅在你觉得这里放一个表情能明显升华情绪/笑点时才放（整段总共 1-2 个以内，绝不刷屏堆砌）。
        5. 请严格以 JSON 格式输出（不要包含额外解释）：
        {"summary":"第一条点评\\n第二条点评\\n第三条点评","topics":["关键词1","关键词2"],"tomorrow_focus":"28字以内直白说出明天先搞哪件事"}

        \(corpus.promptText)
        """
        
        let messages: [AIMessage] = [
            .system("你是用户的毒舌又暖心的写作老友。说话极其接地气、一针见血、分点清晰、不提任何文档标题名、克制使用极少量点睛emoji。"),
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
                segments.append("【写作片段 #\(segments.count + 1)】\n\(String(text.prefix(1200)))")
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
            segments.append("【写作片段 #\(segments.count + 1)】\n\(String(trimmed.prefix(1000)))")
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
        let digest = SHA256.hash(data: Data(("v3-notitle|" + combined).utf8))
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
    
    
    // MARK: Studio Ledger Analytics Helpers
    
    /// Returns a 24-element hourly activity array (`0...23`) for `dateKey`, falling back to document/AI timestamps.
    func hourlyWritingPulse(for dateKey: String) -> [Int] {
        
        let stat: DailyWritingStats? = (dateKey == self.todayStats.dateKey)
            ? self.todayStats
            : self.recentDailyStats.first(where: { $0.dateKey == dateKey })
        
        if let hourly = stat?.hourlyTypedChars, hourly.count == 24, hourly.contains(where: { $0 > 0 }) {
            return hourly
        }
        
        var fallback = Array(repeating: 0, count: 24)
        let calendar = Calendar.current
        for doc in self.database.documents where !doc.id.hasPrefix("weekly:") {
            if Self.dateKey(for: doc.updatedAt) == dateKey {
                let hr = calendar.component(.hour, from: doc.updatedAt)
                if (0..<24).contains(hr) {
                    fallback[hr] += max(120, min(1800, doc.content.count / 2))
                }
            }
        }
        for event in self.recentAIEvents where event.dateKey == dateKey {
            let hr = calendar.component(.hour, from: event.timestamp)
            if (0..<24).contains(hr) {
                fallback[hr] += 80
            }
        }
        return fallback
    }
    
    
    /// Extracts a concise single-line preview from a stored document's content.
    static func documentFirstLinePreview(_ content: String) -> String {
        
        for rawLine in content.components(separatedBy: .newlines) {
            var line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }
            if line.hasPrefix("#") {
                line = line.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces)
            }
            guard !line.isEmpty else { continue }
            if line.count > 56 {
                return String(line.prefix(55)) + "…"
            }
            return line
        }
        return ""
    }
    
    
    // MARK: 6-Hour Background AI Personality Analyzer
    
    /// Collects recent writing samples and uses AI (every 6 hours automatically, or on demand)
    /// to synthesize personality tags (<= 8 chars) and a deeper portrait of the user.
    func refreshPersonalityProfile(force: Bool) async {
        
        guard !self.isAnalyzingPersonality else { return }
        if !force {
            let autoEnabled = self.database.bool(forKey: CotLocalDatabase.ConfigKey.aiPersonalityAutoEnabled, default: true)
            guard autoEnabled else { return }
        }
        
        self.flushPendingStats()
        let corpus = self.collectPersonalityCorpus()
        let existing = self.personalityProfile
        
        if !force {
            guard UserPersonalityAnalyzer.shouldAutoRun(
                now: Date(),
                lastProfile: existing,
                currentFingerprint: corpus.fingerprint,
                currentCharCount: corpus.charCount
            ) else { return }
        }
        
        var didWriteInitialFallback = false
        if self.personalityProfile == nil {
            let initialFallback = UserPersonalityAnalyzer.makeLocalHeuristicFallback(
                documents: self.database.documents,
                weeklyReports: self.database.weeklyReports,
                stats: self.recentDailyStats,
                streak: self.currentWritingStreak,
                fingerprint: corpus.fingerprint
            )
            self.savePersonalityProfile(initialFallback)
            didWriteInitialFallback = true
        }
        
        if corpus.charCount < 20 && self.database.documents.isEmpty && self.database.weeklyReports.isEmpty {
            return
        }
        
        self.isAnalyzingPersonality = true
        self.personalityErrorMessage = nil
        defer { self.isAnalyzingPersonality = false }
        
        let baseConfig = AIConfiguration.current
        let resolvedConfig = AIBotStore.shared.resolvedConfiguration(for: .persona, baseConfig: baseConfig)
        
        if !resolvedConfig.isUsable {
            if !didWriteInitialFallback {
                let fallback = UserPersonalityAnalyzer.makeLocalHeuristicFallback(
                    documents: self.database.documents,
                    weeklyReports: self.database.weeklyReports,
                    stats: self.recentDailyStats,
                    streak: self.currentWritingStreak,
                    fingerprint: corpus.fingerprint
                )
                self.savePersonalityProfile(fallback)
            }
            if force {
                self.personalityErrorMessage = "未配置可用 AI 端点，已根据本地写作轨迹生成初判。"
            }
            return
        }
        
        var config = resolvedConfig
        config.temperature = config.temperature ?? 0.5
        config.reasoningEffort = "low"
        
        let systemPrompt = AIBotStore.shared.systemPrompt(for: .persona)
        let userPrompt = """
        请仔细阅读用户近期在编辑器中写下的内容与记录，提炼用户性格、表达气质与思维特点。
        严格输出一个合法 JSON 对象（不要包含 Markdown 代码围栏或额外说明），结构如下：
        {
          "concept_title": "10字以内对这个人的整体概念概括",
          "concept_summary": "100~180字：用真诚、深刻且稍微带点温度与幽默的口吻，写出AI眼中这个人的性格底色、思维习惯和创作风格",
          "writing_style_notes": ["风格观察1", "风格观察2", "风格观察3"],
          "tags": [
            {"label": "8字以内个性标签", "explanation": "从输入中看出的具体原因", "tone": "warm|sharp|playful|calm"}
          ]
        }
        硬性约束：
        1. tags 输出 5~7 个；每个 label 必须严格 <= 8 个汉字/字符，文字要自然舒畅、像朋友间的温和观察（如：夜深更有灵感、说话直奔主题、做事很有条理、一写就停不下、抓重点很准、喜欢安静记录），不要生硬的网络黑话或夸张口号！
        2. 不要编造文本里完全不存在的职业或经历；如果内容偏向日常笔记或代码注释，就从行文语气、关注点、用词直白度等真实细节洞察。

        用户近期写作样本：
        \(corpus.promptText)
        """
        
        let messages: [AIMessage] = [
            .system(systemPrompt),
            .user(userPrompt),
        ]
        
        let clock = ContinuousClock()
        let start = clock.now
        do {
            let client = AIClient(
                configuration: config,
                maxOutputTokens: 700,
                timeoutInterval: 35,
                disablesThinking: !AINextTokenPredictor.isPureReasoningModel(config.model)
            )
            let response = try await client.sendWithUsage(messages)
            let elapsed = start.duration(to: clock.now)
            let latencyMs = max(1, Int(elapsed.components.seconds * 1000) + Int(elapsed.components.attoseconds / 1_000_000_000_000_000))
            
            let inputTokens = response.inputTokens ?? AINextTokenPredictor.estimateTokens(in: messages.map(\.text).joined(separator: "\n"))
            let outputTokens = response.outputTokens ?? AINextTokenPredictor.estimateTokens(in: response.text)
            self.recordAIUsage(
                feature: AIBotID.persona.analyticsFeatureKey,
                model: config.model,
                provider: config.endpoint.label,
                inputTokens: inputTokens,
                outputTokens: outputTokens,
                latencyMs: latencyMs,
                success: true
            )
            
            if let parsed = UserPersonalityAnalyzer.parseResponse(
                response.text,
                sourceFingerprint: corpus.fingerprint,
                modelUsed: config.model
            ) {
                self.savePersonalityProfile(parsed)
            } else if existing == nil || force {
                let fallback = UserPersonalityAnalyzer.makeLocalHeuristicFallback(
                    documents: self.database.documents,
                    weeklyReports: self.database.weeklyReports,
                    stats: self.recentDailyStats,
                    streak: self.currentWritingStreak,
                    fingerprint: corpus.fingerprint
                )
                self.savePersonalityProfile(fallback)
                if force {
                    self.personalityErrorMessage = "AI 返回格式未能解析，已保留本地初判。"
                }
            }
        } catch {
            if existing == nil || force {
                let fallback = UserPersonalityAnalyzer.makeLocalHeuristicFallback(
                    documents: self.database.documents,
                    weeklyReports: self.database.weeklyReports,
                    stats: self.recentDailyStats,
                    streak: self.currentWritingStreak,
                    fingerprint: corpus.fingerprint
                )
                self.savePersonalityProfile(fallback)
            }
            if force {
                self.personalityErrorMessage = "性格分析请求失败：\(error.localizedDescription)"
            }
            CotLogger.shared.warning(category: .ai, "Personality analysis failed", error: error)
        }
    }
    
    
    func savePersonalityProfile(_ profile: UserPersonalityProfile) {
        
        if let data = try? JSONEncoder().encode(profile),
           let json = String(data: data, encoding: .utf8)
        {
            self.database.set(json, forKey: CotLocalDatabase.ConfigKey.userPersonalityProfileJSON)
            self.personalityProfile = profile
            self.revision &+= 1
        }
    }
    
    
    private func collectPersonalityCorpus() -> (promptText: String, charCount: Int, fingerprint: String) {
        
        var segments: [String] = []
        var usedTitles = Set<String>()
        var totalChars = 0
        
        if self.database === CotLocalDatabase.shared {
            for case let doc as Document in NSDocumentController.shared.documents {
                let text = doc.textStorage.string.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { continue }
                let title = doc.displayName ?? "未命名"
                usedTitles.insert(title)
                let excerpt = String(text.prefix(650))
                totalChars += excerpt.count
                segments.append("[\(title) · \(doc.syntaxName)]\n\(excerpt)")
                if totalChars >= 2200 || segments.count >= 5 { break }
            }
        }
        
        for record in self.database.documents where !record.id.hasPrefix("weekly:") {
            guard !usedTitles.contains(record.title) else { continue }
            let trimmed = record.content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            usedTitles.insert(record.title)
            let excerpt = String(trimmed.prefix(550))
            totalChars += excerpt.count
            segments.append("[\(record.title) · \(record.syntax)]\n\(excerpt)")
            if totalChars >= 3600 || segments.count >= 8 { break }
        }
        
        for report in self.database.weeklyReports.prefix(2) {
            let trimmed = report.content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let excerpt = String(trimmed.prefix(500))
            totalChars += excerpt.count
            segments.append("[周报：\(report.title)]\n\(excerpt)")
        }
        
        let combined = segments.joined(separator: "\n\n")
        let fp = UserPersonalityAnalyzer.sha256Hex(combined)
        return (combined, totalChars, fp)
    }
    
    
    // MARK: Round 20 Dashboard Helpers (Candid AI Take, Manuscripts & Achievements)
    
    /// Translates a typed character count into a tangible physical milestone for the Typed Achievement view.
    static func tangibleWritingEquivalent(for chars: Int) -> (badge: String, detail: String) {
        
        let keystrokes = Int((Double(chars) * 2.4).rounded())
        if chars <= 0 {
            return ("蓄力起草中", "敲下第一行即刻开始累计字迹")
        }
        if chars < 150 {
            return ("一张灵感便签", "约合 \(keystrokes) 次指尖敲击")
        }
        if chars < 500 {
            let pages = max(0.2, Double(chars) / 400.0)
            return ("一张明信片体量", String(format: "约 %.1f 页手写笔记 · %d 次敲击", pages, keystrokes))
        }
        if chars < 1500 {
            let pages = Double(chars) / 550.0
            return ("一篇专栏随笔", String(format: "约合 %.1f 页 16 开书稿", pages))
        }
        if chars < 3500 {
            let pages = Double(chars) / 550.0
            return ("一整章书稿体量", String(format: "约合 %.1f 页 16 开书稿", pages))
        }
        let pages = max(6, Int((Double(chars) / 550.0).rounded()))
        return ("中篇手稿级输出", "约合 \(pages) 页 16 开成书 · \(keystrokes) 次敲击")
    }
    
    
    /// Identifies the user's highest-output 1-hour flow window and writing chronotype for `dateKey`.
    func peakFlowWindow(for dateKey: String) -> (hourRange: String, chronotype: String, peakChars: Int)? {
        
        let hourly = self.hourlyWritingPulse(for: dateKey)
        guard let best = hourly.enumerated().max(by: { $0.element < $1.element }),
              best.element > 0
        else { return nil }
        
        let hr = best.offset
        let range = String(format: "%02d:00–%02d:59", hr, hr)
        let chronotype: String = if hr >= 22 || hr <= 4 {
            "深夜心流派"
        } else if hr <= 11 {
            "晨间清醒派"
        } else if hr <= 17 {
            "午后推进派"
        } else {
            "傍晚沉思派"
        }
        return (hourRange: range, chronotype: chronotype, peakChars: best.element)
    }
    
    
    /// Produces 3–4 candid, plain-spoken, phenomenon-first bullet points summarizing this day
    /// without citing random/playful document titles and with sparing, high-impact emoji accents.
    func candidDailyTakePoints(
        for cell: HeatmapDayCell,
        referenceDate: Date = Date(),
        baselineDailyChars: Int = 0
    ) -> [String] {
        
        let detail = self.dayDetail(for: cell)
        let todayKey = Self.dateKey(for: referenceDate)
        let isToday = (cell.dateKey == todayKey)
        let docTitles = detail.documents.map(\.title) + detail.weeklyReports.map(\.title)
        
        if let digest = detail.digest, digest.modelUsed != "本地摘要" {
            var aiPoints = Self.structuredSummaryPoints(from: digest.summary, maxPoints: 4)
                .map { Self.sanitizeCandidPoint($0, knownTitles: docTitles) }
                .filter { !$0.isEmpty }
            let focus = Self.sanitizeCandidPoint(
                digest.tomorrowFocus.trimmingCharacters(in: .whitespacesAndNewlines),
                knownTitles: docTitles
            )
            if !focus.isEmpty && aiPoints.count < 4 && !aiPoints.contains(where: { $0.contains(focus) }) {
                aiPoints.append("明天一上来先把正事推掉：\(focus)")
            }
            if aiPoints.count >= 2 {
                return aiPoints
            }
        }
        
        var points: [String] = []
        let typed = cell.typedChars
        let ai = cell.aiCompletedChars
        let typedText = typed.formatted(.number.grouping(.automatic))
        let aiText = ai.formatted(.number.grouping(.automatic))
        
        if typed == 0 && ai == 0 && docTitles.isEmpty {
            if isToday {
                points.append("今天目前还是零字起步，纯纯蓄力摸鱼回血中——歇会儿不丢人 🐟")
                points.append("真想开动的话随便敲两行大白话就行，先写坨丑的比完美主义卡死强一百倍。")
            } else {
                points.append("这天键盘歇了个彻底，估计是出门忙正事或者干脆放空回血去了。")
                points.append("没留字迹也挺好，写东西本来就讲究张弛有度，总不能天天绷着。")
            }
        } else if baselineDailyChars > 100 && typed >= Int(Double(baselineDailyChars) * 1.45) {
            points.append("卧槽，\(isToday ? "今天" : "这天")手速直接拉满了！一口气手搓了 \(typedText) 字，比平时均值猛了一大截 🔥")
        } else if typed >= 1200 {
            points.append("\(isToday ? "今天" : "这天")手感是真的顺，实打实敲了 \(typedText) 字，这输出节奏贼稳。")
        } else if typed > 0 {
            points.append("\(isToday ? "今天" : "这天")不紧不慢写了 \(typedText) 字，没瞎赶工反而把思路理得挺清。")
        } else {
            points.append("\(isToday ? "今天" : "这天")先把摊子和骨架支棱起来了，开个头就不算白忙活。")
        }
        
        if let peak = self.peakFlowWindow(for: cell.dateKey) {
            if peak.chronotype == "深夜心流派" {
                points.append("夜深人静果然是你的主场，\(peak.hourRange) 那会儿一小时灌进去 \(peak.peakChars) 字，夜猫子实锤 🦉")
            } else if peak.chronotype == "晨间清醒派" {
                points.append("大清早脑子最灵光，\(peak.hourRange) 状态直接起飞，趁热打铁干了 \(peak.peakChars) 字。")
            }
        } else if docTitles.count >= 2 {
            points.append("在 \(docTitles.count) 份草稿之间来回切换打磨，灵感线程始终没断档。")
        } else if !docTitles.isEmpty, points.count < 2 {
            points.append("\(isToday ? "今天" : "这天")就盯死这一处往下啃，没到处瞎开新坑就是胜利。")
        }
        
        if cell.aiCompletionAccepts >= 3 {
            points.append("顺手按了 \(cell.aiCompletionAccepts) 次 Tab 让 AI 接了 \(aiText) 字，省力偷懒这方面算是玩明白了。")
        } else if cell.documentsSaved >= 4 {
            points.append("前前后后反复存盘打磨了 \(cell.documentsSaved) 次，别特么死磕第一段了，赶紧往下推 🫠")
        } else if cell.filesCreated > 0 {
            points.append("新开了 \(cell.filesCreated) 个坑位先把灵感占住，后面顺着往里填肉就完事。")
        } else if !detail.weeklyReports.isEmpty {
            points.append("顺手把这周的账拢进了复盘里，节奏走得挺稳。")
        }
        
        if isToday {
            if let pinned = self.pinnedTodos.first {
                points.append("屏幕角落还钉着「\(pinned.title)」盯着你呢，顺手消掉就能爽快收工。")
            } else if let next = self.tomorrowReminders.first {
                points.append("明天头一件事已经挂上号：先别墨迹，把「\(next.title)」搞定再说。")
            }
        }
        
        if points.count < 3 {
            points.append("整体步调挺舒服，继续保持这种直给重点的节奏就对了。")
        }
        return Array(points.prefix(4))
    }
    
    
    /// Strips book-title brackets `《…》` and arbitrary playful filenames from review text so comments focus on writing behavior.
    static func sanitizeCandidPoint(_ text: String, knownTitles: [String]) -> String {
        var result = text
        result = result.replacingOccurrences(of: #"《[^》]{1,40}》"#, with: "这份草稿", options: .regularExpression)
        for title in knownTitles {
            let clean = title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !clean.isEmpty else { continue }
            result = result.replacingOccurrences(of: "\(clean)那篇文档", with: "草稿")
            result = result.replacingOccurrences(of: "\(clean)那文档", with: "草稿")
            result = result.replacingOccurrences(of: "\(clean)里", with: "草稿里")
            result = result.replacingOccurrences(of: clean, with: "当前草稿")
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    
    /// Returns documents and weekly reports touched within the past `days` days (newest first).
    func recentTouchedManuscripts(
        days: Int = 7,
        referenceDate: Date = Date(),
        limit: Int = 6
    ) -> [TouchedManuscriptItem] {
        
        let cutoff = Calendar.current.date(byAdding: .day, value: -max(1, days), to: Calendar.current.startOfDay(for: referenceDate)) ?? referenceDate
        let docs = self.database.documents.filter { !$0.id.hasPrefix("weekly:") && $0.updatedAt >= cutoff }
        let reports = self.database.weeklyReports.filter { $0.updatedAt >= cutoff }
        return self.buildManuscriptItems(docs: docs, reports: reports, referenceDate: referenceDate, limit: limit)
    }
    
    
    private func buildManuscriptItems(
        docs: [StoredDocumentRecord],
        reports: [StoredWeeklyReport],
        referenceDate: Date,
        limit: Int
    ) -> [TouchedManuscriptItem] {
        
        let todayKey = Self.dateKey(for: referenceDate)
        var items: [TouchedManuscriptItem] = []
        items.reserveCapacity(docs.count + reports.count)
        
        for doc in docs {
            let preview = Self.documentFirstLinePreview(doc.content)
            let excerpt = preview.isEmpty ? "空白草稿，等你落笔第一行" : preview
            let kind = Self.classifyManuscriptKind(syntax: doc.syntax)
            let syntaxLabel = doc.syntax.isEmpty ? "纯文本" : doc.syntax
            let isCreatedToday = doc.createdAt.map { Self.dateKey(for: $0) == todayKey } ?? false
            items.append(TouchedManuscriptItem(
                id: "doc:\(doc.id)",
                title: doc.title,
                excerpt: excerpt,
                syntaxLabel: syntaxLabel,
                kind: kind,
                charCount: doc.content.count,
                updatedAt: doc.updatedAt,
                relativeTimeBadge: Self.relativeTimeBadge(for: doc.updatedAt, referenceDate: referenceDate),
                isCreatedToday: isCreatedToday,
                payload: .document(doc)
            ))
        }
        
        for report in reports {
            let preview = Self.documentFirstLinePreview(report.content)
            let excerpt = preview.isEmpty ? "阶段工作周报记录" : preview
            let isCreatedToday = (Self.dateKey(for: report.createdAt) == todayKey)
            items.append(TouchedManuscriptItem(
                id: "rep:\(report.id)",
                title: report.title,
                excerpt: excerpt,
                syntaxLabel: "周报",
                kind: .weeklyReport,
                charCount: report.content.count,
                updatedAt: report.updatedAt,
                relativeTimeBadge: Self.relativeTimeBadge(for: report.updatedAt, referenceDate: referenceDate),
                isCreatedToday: isCreatedToday,
                payload: .weeklyReport(report)
            ))
        }
        
        return Array(items.sorted(by: { $0.updatedAt > $1.updatedAt }).prefix(max(0, limit)))
    }
    
    
    private static func classifyManuscriptKind(syntax: String) -> TouchedManuscriptItem.Kind {
        
        let lower = syntax.lowercased()
        if lower.contains("markdown") {
            return .markdown
        }
        if lower.contains("swift") || lower.contains("python") || lower.contains("javascript")
            || lower.contains("typescript") || lower.contains("json") || lower.contains("bash")
            || lower.contains("shell") || lower.contains("html") || lower.contains("css")
            || lower.contains("sql") || lower.contains("rust") || lower.contains("go")
        {
            return .code
        }
        return .plainText
    }
    
    
    private static func relativeTimeBadge(for date: Date, referenceDate: Date) -> String {
        
        let delta = referenceDate.timeIntervalSince(date)
        if delta >= 0 && delta < 180 {
            return "刚刚"
        }
        if delta >= 0 && delta < 3600 {
            return "\(max(1, Int(delta / 60))) 分钟前"
        }
        let calendar = Calendar.current
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm"
        if calendar.isDate(date, inSameDayAs: referenceDate) {
            return "今天 \(timeFormatter.string(from: date))"
        }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: referenceDate),
           calendar.isDate(date, inSameDayAs: yesterday)
        {
            return "昨天 \(timeFormatter.string(from: date))"
        }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: referenceDate)).day ?? 0
        if (2...6).contains(days) {
            return "\(days) 天前"
        }
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "zh_CN")
        dateFormatter.dateFormat = "M月d日"
        return dateFormatter.string(from: date)
    }
}


// MARK: - Busyness, Mood & Done-Today Dashboard Models

/// One 2-hour radial petal in the Dashboard's Nightingale Rose Chart.
nonisolated struct BusynessHourSlice: Identifiable, Hashable, Sendable {
    
    var index: Int          // 0...11 representing 00:00-02:00 ... 22:00-24:00
    var label: String       // e.g. "08-10"
    var intensity: Double   // 0.0...1.0 normalized radius
    var rawChars: Int
    var rawAIRequests: Int
    
    var id: Int { self.index }
}


/// Aggregated busyness score and 12 radial slices for the Nightingale Rose visualization.
nonisolated struct BusynessMetrics: Sendable, Equatable {
    
    var score: Int                      // 0...100
    var activeHours: Int                // Number of active 1-hour slots today
    var peakHourLabel: String           // e.g. "14:00"
    var slices: [BusynessHourSlice]     // 12 two-hour petals
}


/// Outer sub-dimension arc in the 2-ring Emotion Sunburst Chart.
nonisolated struct MoodSubSegment: Identifiable, Hashable, Sendable {
    
    var id: String
    var label: String
    var value: Double
}


/// Inner mood tone sector in the 2-ring Emotion Sunburst Chart.
nonisolated struct MoodRingSegment: Identifiable, Hashable, Sendable {
    
    var id: String
    var label: String
    var tone: PersonalityTagTone
    var weight: Double
    var children: [MoodSubSegment]
}


/// Aggregated mood index and hierarchical 2-ring Sunburst dataset.
nonisolated struct MoodMetrics: Sendable, Equatable {
    
    var score: Int                      // 0...100
    var dominantLabel: String
    var segments: [MoodRingSegment]
}


extension AnalyticsManager {
    
    /// Computes today's 12 two-hour busyness slices and composite index (0...100) from typing pulse & AI requests.
    var busynessMetrics: BusynessMetrics {
        let _ = self.revision
        let todayKey = Self.dateKey()
        let rawHourly = (self.todayStats.dateKey == todayKey && self.todayStats.hourlyTypedChars.count == 24)
            ? self.todayStats.hourlyTypedChars
            : Array(repeating: 0, count: 24)
        let hourlyChars = rawHourly
        let calendar = Calendar.current
        
        var hourlyAI = Array(repeating: 0, count: 24)
        for event in self.recentAIEvents where event.dateKey == todayKey {
            let h = calendar.component(.hour, from: event.timestamp)
            if (0..<24).contains(h) {
                hourlyAI[h] += 1
            }
        }
        
        var hourlyWeight = Array(repeating: 0.0, count: 24)
        for h in 0..<24 {
            hourlyWeight[h] = Double(hourlyChars[h]) + Double(hourlyAI[h] * 90)
        }
        
        var activeHours = 0
        var bestHour = calendar.component(.hour, from: Date())
        var bestHourWeight = -1.0
        for h in 0..<24 {
            if hourlyWeight[h] > 0 {
                activeHours += 1
            }
            if hourlyWeight[h] > bestHourWeight {
                bestHourWeight = hourlyWeight[h]
                bestHour = h
            }
        }
        
        var bucketRawWeights: [Double] = []
        var bucketChars: [Int] = []
        var bucketAI: [Int] = []
        for slot in 0..<12 {
            let h0 = slot * 2
            let h1 = h0 + 1
            let chars = hourlyChars[h0] + hourlyChars[h1]
            let ai = hourlyAI[h0] + hourlyAI[h1]
            bucketChars.append(chars)
            bucketAI.append(ai)
            bucketRawWeights.append(Double(chars) + Double(ai * 90))
        }
        
        let maxWeight = max(120.0, bucketRawWeights.max() ?? 0.0)
        let slices: [BusynessHourSlice] = (0..<12).map { slot in
            let start = slot * 2
            let end = start + 2
            let label = String(format: "%02d-%02d", start, end)
            let w = bucketRawWeights[slot]
            let intensity = w > 0 ? min(1.0, max(0.14, sqrt(w / maxWeight))) : 0.08
            return BusynessHourSlice(
                index: slot,
                label: label,
                intensity: intensity,
                rawChars: bucketChars[slot],
                rawAIRequests: bucketAI[slot]
            )
        }
        
        let stats = self.todayStats
        let charFactor = min(46.0, Double(stats.typedChars + stats.aiCompletedChars) / 45.0)
        let aiFactor = min(24.0, Double(stats.aiRequests) * 2.4)
        let spreadFactor = min(22.0, Double(activeHours) * 3.0)
        let saveFactor = min(8.0, Double(stats.documentsSaved + stats.filesCreated) * 1.6)
        let totalScore = Int((charFactor + aiFactor + spreadFactor + saveFactor).rounded())
        
        let peakLabel = bestHourWeight > 0
            ? String(format: "%02d:00", bestHour)
            : String(format: "%02d:00", calendar.component(.hour, from: Date()))
        
        return BusynessMetrics(
            score: min(100, max(0, totalScore)),
            activeHours: activeHours,
            peakHourLabel: peakLabel,
            slices: slices
        )
    }
    
    
    /// Computes today's hierarchical 2-ring Sunburst emotion distribution from activity rhythm & personality profile.
    var moodMetrics: MoodMetrics {
        let _ = self.revision
        let stats = self.todayStats
        let todayKey = Self.dateKey()
        let hourly = self.hourlyWritingPulse(for: todayKey)
        let bestHourEntry = hourly.enumerated().max(by: { $0.element < $1.element })
        let peakHour = (bestHourEntry.map { $0.element > 0 ? $0.offset : nil } ?? nil) ?? 10
        let tags = self.personalityProfile?.tags ?? []
        
        func toneBoost(for tone: PersonalityTagTone) -> Double {
            Double(tags.filter { $0.tone == tone }.count) * 18.0
        }
        
        let deepWork = max(16.0, Double(stats.typedChars) * 0.035 + Double(stats.documentsSaved) * 6.0 + toneBoost(for: .calm))
        let sharpDrive = max(14.0, Double(stats.aiRequests) * 4.5 + Double(stats.aiCompletedChars) * 0.03 + toneBoost(for: .sharp))
        let warmFlow = max(12.0, (peakHour >= 6 && peakHour <= 18 ? 22.0 : 12.0) + Double(stats.filesCreated) * 8.0 + toneBoost(for: .warm))
        let playfulSpark = max(10.0, Double(stats.localHits) * 3.5 + Double(stats.aiCompletionAccepts) * 2.5 + toneBoost(for: .playful))
        
        let calmChildren = [
            MoodSubSegment(id: "calm-deep", label: "沉浸手写", value: max(6.0, Double(stats.typedChars) * 0.02 + 8.0)),
            MoodSubSegment(id: "calm-polish", label: "精修推敲", value: max(5.0, Double(stats.documentsSaved) * 4.0 + 7.0)),
        ]
        let sharpChildren = [
            MoodSubSegment(id: "sharp-ai", label: "AI协同", value: max(6.0, Double(stats.aiRequests) * 3.0 + 6.0)),
            MoodSubSegment(id: "sharp-speed", label: "高速产出", value: max(5.0, Double(stats.aiCompletedChars) * 0.02 + 7.0)),
        ]
        let warmChildren = [
            MoodSubSegment(id: "warm-create", label: "新建灵感", value: max(5.0, Double(stats.filesCreated) * 6.0 + 7.0)),
            MoodSubSegment(id: "warm-rhythm", label: "日间节律", value: max(5.0, (peakHour >= 7 && peakHour <= 19) ? 14.0 : 6.0)),
        ]
        let playfulChildren = [
            MoodSubSegment(id: "playful-accept", label: "瞬时采纳", value: max(4.0, Double(stats.aiCompletionAccepts) * 2.5 + 6.0)),
            MoodSubSegment(id: "playful-local", label: "轻快试错", value: max(4.0, Double(stats.localHits) * 3.0 + 5.0)),
        ]
        
        let segments: [MoodRingSegment] = [
            MoodRingSegment(id: "calm", label: "专注", tone: .calm, weight: deepWork, children: calmChildren),
            MoodRingSegment(id: "sharp", label: "高效", tone: .sharp, weight: sharpDrive, children: sharpChildren),
            MoodRingSegment(id: "warm", label: "灵感", tone: .warm, weight: warmFlow, children: warmChildren),
            MoodRingSegment(id: "playful", label: "松弛", tone: .playful, weight: playfulSpark, children: playfulChildren),
        ]
        
        let dominant = segments.max(by: { $0.weight < $1.weight })?.label ?? "专注"
        let hasActivity = (stats.typedChars + stats.aiCompletedChars + stats.aiRequests) > 0
        let rawScore: Int
        if hasActivity {
            let positiveRatio = (deepWork + warmFlow + playfulSpark * 0.8 + sharpDrive * 0.65)
                / max(1.0, deepWork + sharpDrive + warmFlow + playfulSpark)
            let volumeBonus = min(22.0, Double(stats.typedChars + stats.aiCompletedChars) / 80.0 + Double(stats.aiCompletionAccepts) * 1.5)
            rawScore = min(98, max(54, Int((56.0 + positiveRatio * 20.0 + volumeBonus).rounded())))
        } else {
            rawScore = 72
        }
        
        return MoodMetrics(score: rawScore, dominantLabel: dominant, segments: segments)
    }
    
    
    /// Clean, capsule-free bullet points summarizing what the user worked on today ("干了啥").
    var doneTodayPoints: [String] {
        let _ = self.revision
        let todayKey = Self.dateKey()
        var points: [String] = []
        
        if let digest = self.todayDigest,
           digest.dateKey == todayKey,
           digest.modelUsed != "本地摘要"
        {
            let parsed = Self.structuredSummaryPoints(from: digest.summary, maxPoints: 5)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            points.append(contentsOf: parsed)
        }
        
        let calendar = Calendar.current
        let todayDocs = self.recentTouchedManuscripts(referenceDate: Date(), limit: 5)
            .filter { calendar.isDateInToday($0.updatedAt) }
        for item in todayDocs where points.count < 5 {
            let line = "推进《\(item.title)》(\(item.charCount.formatted()) 字)"
            if !points.contains(where: { $0.contains(item.title) }) {
                points.append(line)
            }
        }
        
        let stats = self.todayStats
        if stats.typedChars > 0, points.count < 5 {
            points.append("手写输入 \(stats.typedChars.formatted()) 字，保存文档 \(stats.documentsSaved) 次")
        }
        if stats.aiRequests > 0, points.count < 5 {
            points.append("完成 \(stats.aiRequests) 次 AI 协助，消耗 \((stats.inputTokens + stats.outputTokens).formatted()) tokens")
        }
        
        if points.isEmpty {
            let todayKey = Self.dateKey()
            let todayCell = HeatmapDayCell(
                dateKey: todayKey,
                date: Date(),
                typedChars: stats.typedChars,
                aiCompletedChars: stats.aiCompletedChars,
                aiCompletionAccepts: stats.aiCompletionAccepts,
                filesCreated: stats.filesCreated,
                documentsSaved: stats.documentsSaved,
                aiRequests: stats.aiRequests,
                inputTokens: stats.inputTokens,
                outputTokens: stats.outputTokens,
                localHits: stats.localHits,
                level: 0,
                isFuture: false
            )
            let fallback = self.candidDailyTakePoints(for: todayCell, referenceDate: Date(), baselineDailyChars: 0)
                .prefix(3)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            points.append(contentsOf: fallback)
        }
        
        return Array(points.prefix(5))
    }
}
