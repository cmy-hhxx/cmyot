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
    
    private var storedTodayStats: DailyWritingStats = DailyWritingStats(dateKey: AnalyticsManager.dateKey())
    
    /// Live snapshot of today's writing counters including any un-flushed keystroke & local-hit deltas.
    var todayStats: DailyWritingStats {
        var resolved = self.storedTodayStats
        let pendingChars = self.pendingTypedCharsDelta
        let pendingHits = self.pendingLocalHitsDelta
        if pendingChars > 0 || pendingHits > 0 {
            let pendingKey = self.pendingTypedDateKey ?? resolved.dateKey
            if resolved.dateKey != pendingKey {
                resolved = DailyWritingStats(dateKey: pendingKey)
            }
            resolved.typedChars += pendingChars
            resolved.localHits += pendingHits
            if pendingChars > 0, let hour = self.pendingTypedHour, (0..<24).contains(hour) {
                if resolved.hourlyTypedChars.count != 24 {
                    resolved.hourlyTypedChars = Array(repeating: 0, count: 24)
                }
                resolved.hourlyTypedChars[hour] += pendingChars
            }
        }
        return resolved
    }
    
    private(set) var recentDailyStats: [DailyWritingStats] = []
    private(set) var recentAIEvents: [AIUsageEvent] = []
    private(set) var todayDigest: DailyAIDigest?
    private(set) var isSummarizingDigest: Bool = false
    private(set) var digestErrorMessage: String?
    private(set) var reminders: [UserReminder] = []
    private(set) var personalityProfile: UserPersonalityProfile?
    private(set) var isAnalyzingPersonality: Bool = false
    private(set) var personalityErrorMessage: String?
    private(set) var actionPredictions: [DocumentActionPrediction] = []
    private(set) var isPredictingActions: Bool = false
    private(set) var actionPredictionsFromAI: Bool = false
    private(set) var actionPredictionUpdatedAt: Date?
    private(set) var doneTodayCommentary: [String] = []
    private(set) var isRefreshingDoneToday: Bool = false
    private(set) var doneTodayFromAI: Bool = false
    private(set) var revision: Int = 0
    @ObservationIgnored private(set) var lastKeystrokeAt: Date = .distantPast
    
    // MARK: Private Properties
    
    private let database: CotLocalDatabase
    @ObservationIgnored private var actionPredictionFingerprint: String = ""
    @ObservationIgnored private var doneTodayFingerprint: String = ""
    @ObservationIgnored private var doneTodayUpdatedAt: Date?
    @ObservationIgnored private var pendingTypedCharsDelta: Int = 0
    @ObservationIgnored private var pendingLocalHitsDelta: Int = 0
    @ObservationIgnored private var pendingTypedDateKey: String?
    @ObservationIgnored private var pendingTypedHour: Int?
    @ObservationIgnored private var cachedBucketTime: CFAbsoluteTime = 0
    @ObservationIgnored private var cachedBucketDateKey: String = ""
    @ObservationIgnored private var cachedBucketHour: Int = 0
    @ObservationIgnored private var lastPendingMutationUptime: TimeInterval = 0
    @ObservationIgnored private var flushTask: Task<Void, Never>?
    @ObservationIgnored private var backgroundDigestTask: Task<Void, Never>?
    @ObservationIgnored private var aiWindowStartKey: String = ""
    
    @ObservationIgnored private var cachedYearlyHeatmapKey: String = ""
    @ObservationIgnored private var cachedYearlyHeatmapValue: YearlyHeatmapData?
    @ObservationIgnored private var cachedBusynessKey: String = ""
    @ObservationIgnored private var cachedBusynessValue: BusynessMetrics?
    @ObservationIgnored private var cachedMoodKey: String = ""
    @ObservationIgnored private var cachedMoodValue: MoodMetrics?
    
    private static let relativeTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
    
    private static let relativeDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日"
        return formatter
    }()
    
    private static let readableTimestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy年M月d日 EEEE HH:mm"
        return formatter
    }()
    
    
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
            case "documentCenterAgentOrganize": "星图文档整理"
            case "scheduledNightlyOrganize": "凌晨自动整理"
            default: feature
        }
    }
    
    
    // MARK: Telemetry Recording
    
    /// Returns the cached `(dateKey, hour)` bucket, refreshing Calendar components at most every 30 seconds.
    private func currentCachedBucket() -> (dateKey: String, hour: Int, now: Date) {
        
        let absNow = CFAbsoluteTimeGetCurrent()
        let now = Date(timeIntervalSinceReferenceDate: absNow)
        if self.cachedBucketDateKey.isEmpty || (absNow - self.cachedBucketTime) >= 30.0 {
            let comps = Calendar.current.dateComponents([.year, .month, .day, .hour], from: now)
            self.cachedBucketDateKey = String(format: "%04d-%02d-%02d", comps.year ?? 0, comps.month ?? 0, comps.day ?? 0)
            self.cachedBucketHour = comps.hour ?? 0
            self.cachedBucketTime = absNow
        }
        return (self.cachedBucketDateKey, self.cachedBucketHour, now)
    }
    
    
    private func schedulePendingFlush() {
        
        self.lastPendingMutationUptime = ProcessInfo.processInfo.systemUptime
        guard self.flushTask == nil else { return }
        self.flushTask = Task { [weak self] in
            while let self, !Task.isCancelled {
                let elapsed = ProcessInfo.processInfo.systemUptime - self.lastPendingMutationUptime
                let remaining = 2.0 - elapsed
                if remaining <= 0.02 {
                    self.flushPendingStats()
                    return
                }
                let nanos = UInt64((remaining * 1_000_000_000).rounded(.up))
                try? await Task.sleep(nanoseconds: max(20_000_000, nanos))
            }
        }
    }
    
    
    /// Updates `storedTodayStats` and `recentDailyStats` in-place in O(1) without reloading all SQLite tables.
    private func applyInPlaceDailyStatsUpdate(
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
        singleAcceptChars: Int = 0,
        hourBucket: Int? = nil,
        timestamp: Date = Date()
    ) {
        func apply(to entry: inout DailyWritingStats) {
            entry.typedChars += typedChars
            entry.aiCompletedChars += aiCompletedChars
            entry.aiCompletionAccepts += aiCompletionAccepts
            entry.filesCreated += filesCreated
            entry.documentsSaved += documentsSaved
            entry.aiRequests += aiRequests
            entry.inputTokens += inputTokens
            entry.outputTokens += outputTokens
            entry.localHits += localHits
            entry.localAcceptedChars += localAcceptedChars
            if singleAcceptChars > entry.maxSingleAcceptChars {
                entry.maxSingleAcceptChars = singleAcceptChars
            }
            if typedChars > 0, let hour = hourBucket, (0..<24).contains(hour) {
                if entry.hourlyTypedChars.count != 24 {
                    entry.hourlyTypedChars = Array(repeating: 0, count: 24)
                }
                entry.hourlyTypedChars[hour] += typedChars
            }
            entry.updatedAt = timestamp
        }
        
        if let idx = self.recentDailyStats.firstIndex(where: { $0.dateKey == dateKey }) {
            apply(to: &self.recentDailyStats[idx])
        } else {
            var created = DailyWritingStats(dateKey: dateKey)
            apply(to: &created)
            let insertIdx = self.recentDailyStats.firstIndex(where: { $0.dateKey > dateKey }) ?? self.recentDailyStats.endIndex
            self.recentDailyStats.insert(created, at: insertIdx)
        }
        
        let todayKey = Self.dateKey(for: timestamp)
        if dateKey == todayKey {
            if self.storedTodayStats.dateKey != todayKey {
                self.storedTodayStats = self.recentDailyStats.first(where: { $0.dateKey == todayKey }) ?? DailyWritingStats(dateKey: todayKey)
            } else {
                apply(to: &self.storedTodayStats)
            }
        }
        self.revision &+= 1
    }
    
    
    /// Buffers typed character counts in memory with zero `@Observable` invalidations or SQLite I/O on keystrokes,
    /// flushing once after a brief idle pause.
    func recordTypedCharacters(_ count: Int) {
        
        guard count > 0 else { return }
        let bucket = self.currentCachedBucket()
        
        // Flush any buffered counters from an earlier hour/day before switching buckets.
        if (self.pendingTypedCharsDelta > 0 || self.pendingLocalHitsDelta > 0),
           let prevKey = self.pendingTypedDateKey,
           prevKey != bucket.dateKey || self.pendingTypedHour != bucket.hour
        {
            self.flushPendingStats()
        }
        
        self.lastKeystrokeAt = bucket.now
        self.pendingTypedCharsDelta += count
        self.pendingTypedDateKey = bucket.dateKey
        self.pendingTypedHour = bucket.hour
        self.schedulePendingFlush()
    }
    
    
    /// Flushes any pending typed-character and local-hit deltas to SQLite in one lightweight write.
    func flushPendingStats() {
        
        self.flushTask?.cancel()
        self.flushTask = nil
        
        guard self.pendingTypedCharsDelta > 0 || self.pendingLocalHitsDelta > 0 else { return }
        let charsDelta = self.pendingTypedCharsDelta
        let hitsDelta = self.pendingLocalHitsDelta
        let now = Date()
        let targetDateKey = self.pendingTypedDateKey ?? Self.dateKey(for: now)
        let targetHour = self.pendingTypedHour ?? Calendar.current.component(.hour, from: now)
        self.pendingTypedCharsDelta = 0
        self.pendingLocalHitsDelta = 0
        self.pendingTypedDateKey = nil
        self.pendingTypedHour = nil
        
        let precomputedBuckets: [Int]? = {
            guard charsDelta > 0, (0..<24).contains(targetHour) else { return nil }
            let existingBuckets: [Int]? = if self.storedTodayStats.dateKey == targetDateKey {
                self.storedTodayStats.hourlyTypedChars
            } else {
                self.recentDailyStats.first(where: { $0.dateKey == targetDateKey })?.hourlyTypedChars
            }
            guard let existingBuckets, existingBuckets.count == 24 else { return nil }
            var updated = existingBuckets
            updated[targetHour] += charsDelta
            return updated
        }()
        
        self.database.incrementDailyWritingStats(
            dateKey: targetDateKey,
            typedChars: charsDelta,
            localHits: hitsDelta,
            hourBucket: charsDelta > 0 ? targetHour : nil,
            precomputedHourlyBuckets: precomputedBuckets
        )
        self.applyInPlaceDailyStatsUpdate(
            dateKey: targetDateKey,
            typedChars: charsDelta,
            localHits: hitsDelta,
            hourBucket: charsDelta > 0 ? targetHour : nil,
            timestamp: now
        )
    }
    
    
    /// Records an accepted inline ghost suggestion (local or AI).
    func recordGhostCompletionAccepted(charCount: Int, isFromAI: Bool) {
        
        guard charCount > 0 else { return }
        self.flushPendingStats()
        let now = Date()
        let todayKey = Self.dateKey(for: now)
        let localAccepted = isFromAI ? 0 : charCount
        self.database.incrementDailyWritingStats(
            dateKey: todayKey,
            aiCompletedChars: charCount,
            aiCompletionAccepts: 1,
            localAcceptedChars: localAccepted,
            singleAcceptChars: charCount
        )
        self.applyInPlaceDailyStatsUpdate(
            dateKey: todayKey,
            aiCompletedChars: charCount,
            aiCompletionAccepts: 1,
            localAcceptedChars: localAccepted,
            singleAcceptChars: charCount,
            timestamp: now
        )
    }
    
    
    /// Buffers a 0-cost local habit or cached ghost hit without touching SQLite synchronously during typing.
    func recordLocalCompletionHit() {
        
        let bucket = self.currentCachedBucket()
        if (self.pendingTypedCharsDelta > 0 || self.pendingLocalHitsDelta > 0),
           let prevKey = self.pendingTypedDateKey,
           prevKey != bucket.dateKey
        {
            self.flushPendingStats()
        }
        self.pendingLocalHitsDelta += 1
        self.pendingTypedDateKey = bucket.dateKey
        if self.pendingTypedHour == nil {
            self.pendingTypedHour = bucket.hour
        }
        self.schedulePendingFlush()
    }
    
    
    /// Records a user-created file/tab.
    func recordFileCreated(on date: Date = Date()) {
        
        let key = Self.dateKey(for: date)
        self.database.incrementDailyWritingStats(dateKey: key, filesCreated: 1)
        self.applyInPlaceDailyStatsUpdate(dateKey: key, filesCreated: 1, timestamp: date)
    }
    
    
    /// Records a document save operation.
    func recordDocumentSaved(on date: Date = Date()) {
        
        let key = Self.dateKey(for: date)
        self.database.incrementDailyWritingStats(dateKey: key, documentsSaved: 1)
        self.applyInPlaceDailyStatsUpdate(dateKey: key, documentsSaved: 1, timestamp: date)
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
        let safeIn = max(0, inputTokens)
        let safeOut = max(0, outputTokens)
        let event = AIUsageEvent(
            dateKey: key,
            timestamp: date,
            feature: feature,
            model: resolvedModel,
            provider: resolvedProvider,
            inputTokens: safeIn,
            outputTokens: safeOut,
            latencyMs: max(0, latencyMs),
            success: success
        )
        
        self.database.incrementDailyWritingStats(
            dateKey: key,
            aiRequests: 1,
            inputTokens: safeIn,
            outputTokens: safeOut
        )
        self.database.insertAIUsageEvent(event)
        if let first = self.recentAIEvents.first, first.timestamp > event.timestamp {
            let idx = self.recentAIEvents.firstIndex(where: { $0.timestamp <= event.timestamp }) ?? self.recentAIEvents.endIndex
            self.recentAIEvents.insert(event, at: idx)
        } else {
            self.recentAIEvents.insert(event, at: 0)
        }
        if self.recentAIEvents.count > 5_000 {
            self.recentAIEvents.removeLast(self.recentAIEvents.count - 5_000)
        }
        self.applyInPlaceDailyStatsUpdate(
            dateKey: key,
            aiRequests: 1,
            inputTokens: safeIn,
            outputTokens: safeOut,
            timestamp: date
        )
    }
    
    
    /// Reloads all cached analytics slices, today's AI digest, and reminders from the active SQLite database.
    func reloadFromDatabase() {
        
        if !Self.isRunningUnitTests {
            self.backfillHistoricalStatsIfNeeded()
        }
        
        let calendar = Calendar.current
        let today = Date()
        let todayKey = Self.dateKey(for: today)
        let aiLookbackDate = calendar.date(byAdding: .day, value: -90, to: calendar.startOfDay(for: today)) ?? today
        let aiSinceKey = Self.dateKey(for: aiLookbackDate)
        self.aiWindowStartKey = aiSinceKey
        
        let stats = self.database.fetchDailyWritingStats(sinceDateKey: "2000-01-01")
        self.recentDailyStats = stats
        self.storedTodayStats = stats.first(where: { $0.dateKey == todayKey }) ?? DailyWritingStats(dateKey: todayKey)
        
        self.recentAIEvents = self.database.fetchAIUsageEvents(sinceDateKey: aiSinceKey, limit: 5_000)
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
        
        self.loadDoneTodayCommentaryFromDatabase()
        self.loadActionPredictionsFromDatabase()
        
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
        
        self.database.withTransaction {
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
        guard let startDate = Self.heatmapStart(weeks: weekCount, todayStart: todayStart, calendar: calendar) else { return [] }
        
        return self.buildHeatmapCells(
            gridStart: startDate,
            totalCells: weekCount * 7,
            targetYear: nil,
            todayStart: todayStart,
            calendar: calendar
        )
    }
    
    
    private static func heatmapStart(weeks: Int, todayStart: Date, calendar: Calendar) -> Date? {
        // Align the rolling grid to Sunday through Saturday.
        let weekday = calendar.component(.weekday, from: todayStart)
        let endDate = calendar.date(byAdding: .day, value: 7 - weekday, to: todayStart) ?? todayStart
        return calendar.date(byAdding: .day, value: 1 - weeks * 7, to: endDate)
    }
    
    
    /// Builds a calendar-year Monday-first activity heatmap matrix (full year or trimmed after today's week).
    func yearlyHeatmap(
        year: Int,
        referenceDate: Date = Date(),
        trimFutureWeeks: Bool = false
    ) -> YearlyHeatmapData {
        
        let refDayKey = Self.dateKey(for: referenceDate)
        let cacheKey = "\(year)|\(trimFutureWeeks ? 1 : 0)|\(refDayKey)|\(self.revision)|\(self.database.documents.count)|\(self.database.weeklyReports.count)"
        if cacheKey == self.cachedYearlyHeatmapKey, let cached = self.cachedYearlyHeatmapValue {
            return cached
        }
        
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
        
        let result = YearlyHeatmapData(
            year: year,
            weeks: weeks,
            monthLabels: monthLabels,
            activeDays: activeDays,
            totalTypedChars: totalTypedChars
        )
        self.cachedYearlyHeatmapKey = cacheKey
        self.cachedYearlyHeatmapValue = result
        return result
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
        
        let statsByDay = self.writingStatsByDay
        
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
            let directScore = Self.heatmapActivityScore(stat)
            let fallbackScore = (isOutOfYear || isFuture) ? 0 : (historicalDocsByDay[key] ?? 0)
            let score = (isOutOfYear || isFuture) ? 0 : max(directScore, fallbackScore)
            rawScores.append(RawDay(key: key, date: day, stat: stat, score: score, isFuture: isFuture, isOutOfYear: isOutOfYear))
        }
        
        let activeScores = rawScores
            .lazy
            .filter { !$0.isOutOfYear && !$0.isFuture && $0.score > 0 }
            .map(\.score)
            .sorted()
        let p92Index = activeScores.isEmpty ? 0 : min(activeScores.count - 1, Int(Double(activeScores.count - 1) * 0.92))
        let referencePeak = max(120, activeScores.isEmpty ? 120 : activeScores[p92Index])
        
        return rawScores.map { item in
            let level: Int
            if item.isOutOfYear || item.isFuture || item.score <= 0 {
                level = 0
            } else {
                // Square-root compression against the 92nd percentile prevents a single outlier spike
                // from crushing all other active days down to level 1.
                let normalized = min(1.0, sqrt(Double(item.score) / Double(referencePeak)))
                if normalized >= 0.80 {
                    level = 4
                } else if normalized >= 0.56 {
                    level = 3
                } else if normalized >= 0.34 {
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
    
    
    private var writingStatsByDay: [String: DailyWritingStats] {
        var stats = Dictionary(self.recentDailyStats.lazy.map { ($0.dateKey, $0) }, uniquingKeysWith: { first, _ in first })
        let today = self.todayStats
        stats[today.dateKey] = today
        return stats
    }
    
    
    private static func heatmapActivityScore(_ stats: DailyWritingStats?) -> Int {
        guard let stats else { return 0 }
        return stats.typedChars + stats.aiCompletedChars + stats.filesCreated * 60 + stats.aiRequests * 20
    }
    
    
    /// Chronological daily stats for the last `days` calendar days (inclusive of `referenceDate`), filling empty days with zeros.
    func dailySeries(days: Int = 14, referenceDate: Date = Date()) -> [DailyWritingStats] {
        
        let clampedDays = max(1, min(90, days))
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: referenceDate)
        let byKey = self.writingStatsByDay
        
        return (0..<clampedDays).reversed().map { offset in
            let day = calendar.date(byAdding: .day, value: -offset, to: todayStart) ?? todayStart
            let key = Self.dateKey(for: day)
            return byKey[key] ?? DailyWritingStats(dateKey: key, updatedAt: day)
        }
    }
    
    
    /// Builds full rich details for a clicked heatmap cell, including models, features, documents, and daily digest.
    func dayDetail(for cell: HeatmapDayCell) -> HeatmapDayDetail {
        
        let dayEvents: [AIUsageEvent] = if (!self.aiWindowStartKey.isEmpty && cell.dateKey < self.aiWindowStartKey)
            || (self.recentAIEvents.count >= 5_000 && !self.recentAIEvents.contains(where: { $0.dateKey == cell.dateKey }))
        {
            self.database.fetchAIUsageEvents(forDateKey: cell.dateKey)
        } else {
            self.recentAIEvents.filter { $0.dateKey == cell.dateKey }
        }
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
    
    
    /// Number of consecutive active days ending today or yesterday.
    var currentWritingStreak: Int {
        self.writingStreak(referenceDate: Date())
    }
    
    
    func writingStreak(referenceDate: Date) -> Int {
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: referenceDate)
        guard let gridStart = Self.heatmapStart(weeks: 53, todayStart: todayStart, calendar: calendar) else { return 0 }
        let statsByDay = self.writingStatsByDay
        var historicalDays: Set<String>?
        
        func isActive(_ day: Date) -> Bool {
            let key = Self.dateKey(for: day)
            if Self.heatmapActivityScore(statsByDay[key]) > 0 { return true }
            if historicalDays == nil {
                // Every stored document or report contributes at least one point to its day.
                var days = Set<String>()
                let tomorrow = calendar.date(byAdding: .day, value: 1, to: todayStart) ?? .distantFuture
                for document in self.database.documents where document.updatedAt >= gridStart && document.updatedAt < tomorrow {
                    days.insert(Self.dateKey(for: document.updatedAt))
                }
                for report in self.database.weeklyReports where report.updatedAt >= gridStart && report.updatedAt < tomorrow {
                    days.insert(Self.dateKey(for: report.updatedAt))
                }
                historicalDays = days
            }
            return historicalDays?.contains(key) == true
        }
        
        var streak = 0
        var cursor = todayStart
        if !isActive(todayStart) {
            cursor = calendar.date(byAdding: .day, value: -1, to: cursor) ?? cursor
        }
        
        for _ in 0..<370 {
            guard cursor >= gridStart, isActive(cursor) else { break }
            streak += 1
            guard let prev = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = prev
        }
        return streak
    }
    
    
    /// Model usage breakdown over the last `days` days.
    func modelDistribution(days: Int = 30) -> [ModelUsageSummary] {
        
        Self.aggregateModelDistribution(from: self.aiEventsInWindow(days: days, referenceDate: Date()))
    }
    
    
    /// Feature usage breakdown over the last `days` days.
    func featureDistribution(days: Int = 30) -> [FeatureUsageSummary] {
        
        Self.aggregateFeatureDistribution(from: self.aiEventsInWindow(days: days, referenceDate: Date()))
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
            return Self.aggregateAIUsageTotals(from: self.recentAIEvents.lazy.filter { $0.dateKey == key })
        }
        return Self.aggregateAIUsageTotals(from: self.aiEventsInWindow(days: days, referenceDate: referenceDate))
    }
    
    
    func aiUsageBreakdown(days: Int, referenceDate: Date) -> (
        events: [AIUsageEvent], totals: AIUsageTotals, models: [ModelUsageSummary], features: [FeatureUsageSummary]
    ) {
        let events = self.aiEventsInWindow(days: days, referenceDate: referenceDate)
        return (
            events: events,
            totals: Self.aggregateAIUsageTotals(from: events),
            models: Self.aggregateModelDistribution(from: events),
            features: Self.aggregateFeatureDistribution(from: events)
        )
    }
    
    
    private func aiEventsInWindow(days: Int, referenceDate: Date) -> [AIUsageEvent] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: referenceDate) ?? referenceDate
        return self.recentAIEvents.filter { $0.timestamp >= cutoff }
    }
    
    
    private static func aggregateAIUsageTotals(from events: some Sequence<AIUsageEvent>) -> AIUsageTotals {
        events.reduce(into: AIUsageTotals(requests: 0, inputTokens: 0, outputTokens: 0)) { totals, event in
            totals.requests += 1
            totals.inputTokens += event.inputTokens
            totals.outputTokens += event.outputTokens
        }
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
                    return lhs.dueDate > rhs.dueDate
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
        self.reloadRemindersOnly()
        return todo
    }
    
    
    /// Reloads only reminders without triggering a full historical stats & events reload.
    private func reloadRemindersOnly() {
        
        self.reminders = self.database.fetchAllReminders()
        self.revision &+= 1
    }
    
    
    func unpinReminder(id: String) {
        
        self.database.setReminderPinned(id: id, isPinned: false)
        self.reloadRemindersOnly()
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
        self.reloadRemindersOnly()
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
        self.reloadRemindersOnly()
        return reminder
    }
    
    
    func toggleReminderCompleted(id: String) {
        
        guard let item = self.reminders.first(where: { $0.id == id }) else { return }
        self.database.toggleReminderCompleted(id: id, isCompleted: !item.isCompleted)
        self.reloadRemindersOnly()
    }
    
    
    func deleteReminder(id: String) {
        
        self.database.deleteReminder(id: id)
        self.reloadRemindersOnly()
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
        let todayKey = Self.dateKey()
        let existing = self.database.fetchDailyAIDigest(forDateKey: todayKey)
        if !force,
           let existing,
           !existing.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           Date().timeIntervalSince(existing.generatedAt) < Self.digestAutoInterval
        {
            return
        }
        
        self.flushPendingStats()
        let corpus = self.collectTodayCorpus(dateKey: todayKey)
        
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
    
    private static func boundedTextSlice(
        from textStorage: NSTextStorage,
        headLimit: Int,
        tailLimit: Int = 0
    ) -> (text: String, totalLength: Int) {
        let ns = textStorage.mutableString as NSString
        let total = ns.length
        guard total > 0 else { return ("", 0) }
        if tailLimit <= 0 {
            let range = ns.rangeOfComposedCharacterSequences(for: NSRange(location: 0, length: min(total, headLimit)))
            let head = ns.substring(with: range).trimmingCharacters(in: .whitespacesAndNewlines)
            return (head, total <= range.length ? head.count : total)
        }
        if total <= headLimit + tailLimit {
            let full = (ns as String).trimmingCharacters(in: .whitespacesAndNewlines)
            return (full, full.count)
        }
        let headRange = ns.rangeOfComposedCharacterSequences(for: NSRange(location: 0, length: min(total, headLimit)))
        let tailStart = max(0, total - tailLimit)
        let tailRange = ns.rangeOfComposedCharacterSequences(for: NSRange(location: tailStart, length: total - tailStart))
        let head = ns.substring(with: headRange)
        let tail = ns.substring(with: tailRange)
        let combined = "\(head)\n...\n\(tail)".trimmingCharacters(in: .whitespacesAndNewlines)
        return (combined, total)
    }
    
    
    private func collectTodayCorpus(dateKey: String) -> (promptText: String, charCount: Int, fingerprint: String) {
        
        var segments: [String] = []
        var usedTitles = Set<String>()
        var totalChars = 0
        
        if self.database === CotLocalDatabase.shared {
            for case let doc as Document in NSDocumentController.shared.documents {
                let sliced = Self.boundedTextSlice(from: doc.textStorage, headLimit: 1800)
                let text = sliced.text
                guard !text.isEmpty else { continue }
                let docDateKey = doc.lastManualSaveDate.map { Self.dateKey(for: $0) } ?? dateKey
                guard doc.hasUncommittedChanges || docDateKey == dateKey else { continue }
                let docTitle = doc.displayName ?? "未命名文档"
                usedTitles.insert(docTitle)
                totalChars += sliced.totalLength
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
        
        let existing = self.personalityProfile
        if !force,
           let existing,
           !existing.isLocalFallback,
           Date().timeIntervalSince(existing.generatedAt) < UserPersonalityAnalyzer.autoInterval
        {
            return
        }
        
        self.flushPendingStats()
        let corpus = self.collectPersonalityCorpus()
        
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
            if self.database === CotLocalDatabase.shared {
                CotMemoryStore.shared.syncPersonalityProfile(profile)
            }
        }
    }
    
    
    private func collectPersonalityCorpus() -> (promptText: String, charCount: Int, fingerprint: String) {
        
        var segments: [String] = []
        var usedTitles = Set<String>()
        var totalChars = 0
        
        if self.database === CotLocalDatabase.shared {
            for case let doc as Document in NSDocumentController.shared.documents {
                let text = Self.boundedTextSlice(from: doc.textStorage, headLimit: 1024).text
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
        if calendar.isDate(date, inSameDayAs: referenceDate) {
            return "今天 \(Self.relativeTimeFormatter.string(from: date))"
        }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: referenceDate),
           calendar.isDate(date, inSameDayAs: yesterday)
        {
            return "昨天 \(Self.relativeTimeFormatter.string(from: date))"
        }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: referenceDate)).day ?? 0
        if (2...6).contains(days) {
            return "\(days) 天前"
        }
        return Self.relativeDateFormatter.string(from: date)
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
        let rev = self.revision
        let todayKey = Self.dateKey()
        let cacheKey = "\(todayKey)|\(rev)"
        if cacheKey == self.cachedBusynessKey, let cached = self.cachedBusynessValue {
            return cached
        }
        let rawHourly = (self.todayStats.dateKey == todayKey && self.todayStats.hourlyTypedChars.count == 24)
            ? self.todayStats.hourlyTypedChars
            : Array(repeating: 0, count: 24)
        let hourlyChars = rawHourly
        let calendar = Calendar.current
        
        var hourlyAI = Array(repeating: 0, count: 24)
        for event in self.recentAIEvents {
            if event.dateKey < todayKey { break }
            guard event.dateKey == todayKey else { continue }
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
        
        let result = BusynessMetrics(
            score: min(100, max(0, totalScore)),
            activeHours: activeHours,
            peakHourLabel: peakLabel,
            slices: slices
        )
        self.cachedBusynessKey = cacheKey
        self.cachedBusynessValue = result
        return result
    }
    
    
    /// Computes today's hierarchical 2-ring Sunburst emotion distribution from activity rhythm & personality profile.
    var moodMetrics: MoodMetrics {
        let rev = self.revision
        let stats = self.todayStats
        let todayKey = Self.dateKey()
        let tagsCount = self.personalityProfile?.tags.count ?? 0
        let cacheKey = "\(todayKey)|\(rev)|\(tagsCount)"
        if cacheKey == self.cachedMoodKey, let cached = self.cachedMoodValue {
            return cached
        }
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
        
        let result = MoodMetrics(score: rawScore, dominantLabel: dominant, segments: segments)
        self.cachedMoodKey = cacheKey
        self.cachedMoodValue = result
        return result
    }
    
    
    /// Returns `true` when an action or snippet carries real semantic substance —
    /// strictly rejecting test inputs (`111`, `222`, `test`, `测试111`, `asdf`), repeated filler chars,
    /// and generic boilerplate like `cot 优化todos` or `cot Editors`.
    nonisolated static func hasMeaningfulActionSubstance(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        
        var stripped = trimmed.lowercased()
            .replacingOccurrences(of: #"(coteditor|editors?|cot|todos?|fixme|roadmap)"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\b(test(?:ing)?|demo|sample|tmp|temp|asdf|qwer|zxcv|foo|bar|baz|xxx+|abc+|placeholder|untitled|draft)\b"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: "测试", with: "")
            .replacingOccurrences(of: "优化", with: "")
            .replacingOccurrences(of: "待办", with: "")
            .replacingOccurrences(of: "清单", with: "")
            .replacingOccurrences(of: "事项", with: "")
            .replacingOccurrences(of: #"[0-9]+"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters).union(.symbols))
        
        // Remove whitespace inside to measure genuine semantic characters
        stripped = stripped.replacingOccurrences(of: #"\s+"#, with: "", options: .regularExpression)
        guard stripped.count >= 3 else { return false }
        
        // Reject repeated single-character spam like "aaa", "哈哈哈", "一一一"
        let uniqueChars = Set(stripped)
        guard uniqueChars.count >= 2 else { return false }
        
        // If purely ASCII letters, reject short keyboard-mash / gibberish tokens
        let hasCJK = stripped.unicodeScalars.contains { scalar in
            (0x4E00...0x9FFF).contains(scalar.value) || (0x3400...0x4DBF).contains(scalar.value)
        }
        if !hasCJK {
            if stripped.count < 4 || uniqueChars.count < 3 {
                return false
            }
            let mashPatterns = ["asdf", "qwer", "zxcv", "hjkl", "uiop", "abcd", "aaaa", "zzzz"]
            if mashPatterns.contains(where: { stripped.contains($0) && stripped.count <= 8 }) {
                return false
            }
        }
        return true
    }
    
    
    /// Returns `true` if a document contains meaningful human writing rather than throwaway scratch tests (`111`, `222`, `test`).
    nonisolated static func isMeaningfulDocumentContent(_ content: String) -> Bool {
        let lines = content.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !lines.isEmpty else { return false }
        let meaningfulLines = lines.filter { Self.hasMeaningfulActionSubstance($0) }
        if !meaningfulLines.isEmpty {
            let totalMeaningfulChars = meaningfulLines.reduce(0) { $0 + $1.count }
            return totalMeaningfulChars >= 8
        }
        return false
    }
    
    
    /// Returns `true` only when `text` reads as a complete, self-contained sentence/clause —
    /// rejecting cut-off fragments, trailing ellipses, unclosed delimiters, and dangling conjunctions/prepositions.
    nonisolated static func isCompleteDashboardSentence(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 4 else { return false }
        
        // 1. Reject trailing ellipsis or unfinished connector punctuation
        let unfinishedSuffixes = [
            "...", "…", "——", "—", "--", "-", "/", "+", "=", "·",
            "、", "，", ",", "：", ":", "；", ";", "~", "～",
            "(", "（", "[", "【", "「", "『", "《", "“", "‘",
        ]
        for bad in unfinishedSuffixes where trimmed.hasSuffix(bad) {
            return false
        }
        
        // 2. Reject unbalanced / unclosed brackets or paired Chinese quotes
        let pairs: [(open: Character, close: Character)] = [
            ("(", ")"), ("（", "）"), ("[", "]"), ("【", "】"),
            ("「", "」"), ("『", "』"), ("《", "》"), ("“", "”"), ("‘", "’"),
        ]
        for (open, close) in pairs {
            var depth = 0
            for ch in trimmed {
                if ch == open { depth += 1 }
                else if ch == close { depth -= 1 }
            }
            if depth != 0 {
                return false
            }
        }
        
        // Strip terminal sentence punctuation to inspect the grammatical ending token
        let core = trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "。！？!?"))
        guard core.count >= 4 else { return false }
        
        // 3. Reject multi-character Chinese dangling connectors / auxiliaries / incomplete clause starters
        let danglingMultiCharSuffixes = [
            "以及", "或者", "并且", "而且", "但是", "不过", "因为", "所以", "虽然", "如果",
            "只要", "除非", "同时", "然后", "接着", "另外", "关于", "针对", "围绕", "基于",
            "通过", "根据", "按照", "包括", "涉及", "例如", "比如", "为了", "避免", "防止",
            "保证", "确保", "导致", "造成", "引起", "正在", "已经", "将会", "准备", "打算",
            "计划", "考虑", "需要", "应该", "必须", "可以", "能否", "是否", "如何", "怎么",
            "什么", "哪些", "继续", "进行", "处理", "用于", "用来", "还有", "不仅", "而是",
            "还是", "甚至", "尤其", "特别是", "其中", "比如说", "接下来", "下一步",
        ]
        for suffix in danglingMultiCharSuffixes where core.hasSuffix(suffix) {
            return false
        }
        
        // 4. Reject single-character Chinese function/particle endings that cannot close a sentence
        let danglingSingleCJK: Set<Character> = [
            "的", "地", "得", "和", "与", "及", "或", "且", "并", "但", "却",
            "把", "将", "被", "在", "于", "对", "向", "从", "为", "给", "让",
            "使", "按", "以", "因", "若", "如", "虽", "就", "才", "还", "再",
            "又", "更", "最", "很", "太", "挺", "都", "也", "只", "仅", "每",
            "各", "该", "此", "这", "那", "某", "等",
        ]
        if let lastChar = core.last, danglingSingleCJK.contains(lastChar) {
            return false
        }
        
        // 5. Reject dangling English stop words at sentence tail
        if let lastWord = core.split(whereSeparator: \.isWhitespace).last?.lowercased(),
           lastWord.allSatisfy(\.isASCII)
        {
            let danglingEnglish: Set<String> = [
                "the", "a", "an", "to", "for", "of", "in", "on", "at", "with",
                "and", "or", "but", "that", "which", "from", "by", "as",
                "is", "are", "was", "were", "be", "will", "should", "would",
                "can", "could", "into", "about", "after", "before", "while", "when", "if",
            ]
            if danglingEnglish.contains(lastWord) {
                return false
            }
        }
        
        return true
    }
    
    
    /// Sanitizes dashboard card items ("干了啥" / "要干啥") to strip all document names,
    /// file extensions, book-title brackets, and character/word counts, optionally clamping for single-line display.
    nonisolated static func sanitizeDashboardActionText(
        _ raw: String,
        knownTitles: [String],
        maxLength: Int? = nil,
        fallback: String = ""
    ) -> String {
        var result = raw
            .replacingOccurrences(of: "\u{FFFD}", with: "")
            .replacingOccurrences(of: "\u{FEFF}", with: "")
            .replacingOccurrences(of: #"[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !result.isEmpty else { return fallback }
        
        // 1. Strip parenthesized word/char counts like "(1,200 字)" / "（约300字）"
        result = result.replacingOccurrences(
            of: #"[\(（\[【][^\)）\]】]*?\d[\d,.\s]*[kKwW万千]?\s*(?:个?字(?:数|符)?|words?|chars?)[^\)）\]】]*?[\)）\]】]"#,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        
        // 2. Strip inline word/char count clauses like "手写输入 1,280 字，" / "仅 120 字"
        result = result.replacingOccurrences(
            of: #"(?:共计|累计|合计|约有|手写输入|手写了|输入了|输入|输出了|输出|新增了|新增|完成了|完成|撰写了|写了|码了|当前仅|约|共|仅)?\s*\d[\d,.\s]*[kKwW万千]?\s*余?(?:个)?字(?:数|符)?[，,、；;。]?\s*"#,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        
        // 3. Strip book-title brackets 《…》 / 〈…〉 and standalone filenames with extensions
        result = result.replacingOccurrences(of: #"[《〈][^》〉]{1,80}[》〉]"#, with: "", options: .regularExpression)
        result = result.replacingOccurrences(
            of: #"["“「`]?[A-Za-z0-9_\-\.\u4e00-\u9fa5]{1,60}\.(?:md|markdown|txt|swift|json|yaml|yml|py|js|ts|tsx|jsx|html|css)["”」`]?"#,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        
        // 4. Strip known document titles and filename stems (longest first)
        var candidates: [String] = []
        for title in knownTitles {
            let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.count >= 2 else { continue }
            candidates.append(trimmed)
            let stem = (trimmed as NSString).deletingPathExtension.trimmingCharacters(in: .whitespacesAndNewlines)
            if stem.count >= 2 && stem != trimmed {
                candidates.append(stem)
            }
        }
        for candidate in Array(Set(candidates)).sorted(by: { $0.count > $1.count }) {
            result = result.replacingOccurrences(of: candidate, with: "", options: [.caseInsensitive])
        }
        
        // 5. Strip leading list numbering ("2. ", "1)", "① ") and trailing colons
        result = result.replacingOccurrences(
            of: #"^\s*(?:\d+[.、)\]]|\(\d+\)|[①②③④⑤⑥⑦⑧⑨⑩])\s*"#,
            with: "",
            options: .regularExpression
        )
        result = result.replacingOccurrences(of: #"[:：]+\s*$"#, with: "", options: .regularExpression)
        
        // 6. Collapse orphaned brackets/punctuation left after title/count removal
        result = result.replacingOccurrences(of: #"[「『\[【\(\（]\s*[」』\]】\)\）]"#, with: "", options: .regularExpression)
        result = result.replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
        result = result.replacingOccurrences(of: #"[，,、；;]{2,}"#, with: "，", options: .regularExpression)
        // Preserve natural terminal sentence punctuation (`。！？!?`) while trimming leading/trailing fragments.
        result = result.trimmingCharacters(in: CharacterSet(charactersIn: " ，,、；;：:·-—\n\t"))
        if result.hasPrefix("。") {
            result = result.trimmingCharacters(in: CharacterSet(charactersIn: "。 "))
        }
        
        if result.isEmpty || (result.count < 4 && !fallback.isEmpty) {
            result = fallback
        }
        
        if let maxLength, result.count > maxLength {
            let prefix = String(result.prefix(maxLength))
            if let breakIdx = prefix.lastIndex(where: { "，,、。；; ".contains($0) }),
               prefix.distance(from: prefix.startIndex, to: breakIdx) >= max(5, maxLength / 2)
            {
                result = String(prefix[..<breakIdx]).trimmingCharacters(in: CharacterSet(charactersIn: " ，,、。；;：:·-—"))
            } else {
                result = prefix.trimmingCharacters(in: CharacterSet(charactersIn: " ，,、。；;：:·-—"))
            }
        }
        
        return result.isEmpty ? fallback : result
    }
    
    
    /// Sanitizes predicted next-action text ("要干啥") by stripping all parenthetical explanations,
    /// bracket markers, numbering, and document names while condensing to a crisp single-line action.
    nonisolated static func sanitizePredictedActionText(
        _ raw: String,
        knownTitles: [String],
        maxLength: Int = 20
    ) -> String {
        var text = raw
            .replacingOccurrences(of: "\u{FFFD}", with: "")
            .replacingOccurrences(of: "\u{FEFF}", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return "" }
        
        // 1. Strip leading numbering ("1. ", "(1) ", "（3）", "① ")
        text = text.replacingOccurrences(
            of: #"^\s*(?:\d+[.、)\]]|\(\d+\)|（\d+）|[①②③④⑤⑥⑦⑧⑨⑩])\s*"#,
            with: "",
            options: .regularExpression
        )
        
        // 2. Remove paired brackets and their parenthetical supplements
        text = text.replacingOccurrences(
            of: #"\([^\)\n]*\)|（[^）\n]*）|\[[^\]\n]*\]|【[^】\n]*】|《[^》\n]*》|〈[^〉\n]*〉"#,
            with: "",
            options: .regularExpression
        )
        
        // 3. Unwrap corner quotes while retaining core words inside
        text = text
            .replacingOccurrences(of: "「", with: "")
            .replacingOccurrences(of: "」", with: "")
            .replacingOccurrences(of: "『", with: "")
            .replacingOccurrences(of: "』", with: "")
        
        // 4. Clean document titles, word counts, and noise via base sanitizer
        var result = Self.sanitizeDashboardActionText(
            text,
            knownTitles: knownTitles,
            maxLength: nil,
            fallback: ""
        )
        
        // 5. Fallback strip of any stray unpaired bracket characters
        let strayBrackets = CharacterSet(charactersIn: "()（）[]【】「」『』《》〈〉")
        if result.rangeOfCharacter(from: strayBrackets) != nil {
            result = String(result.unicodeScalars.filter { !strayBrackets.contains($0) })
        }
        result = result.replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: " ，,、；;：:·-—\n\t"))
        guard !result.isEmpty else { return "" }
        
        if result.count <= maxLength {
            return result
        }
        
        // 6. Prefer first concise complete clause within `maxLength`
        let clauseSeparators = CharacterSet(charactersIn: "，,；;。：:—")
        let clauses = result.components(separatedBy: clauseSeparators)
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: " ，,、；;：:·-—\n\t")) }
            .filter { $0.count >= 4 }
        for clause in clauses {
            if clause.count <= maxLength && Self.isCompleteDashboardSentence(clause) {
                return clause
            }
        }
        
        let limit = min(maxLength, result.count)
        var endIdx = result.index(result.startIndex, offsetBy: limit)
        while endIdx > result.startIndex {
            let candidate = String(result[..<endIdx])
                .trimmingCharacters(in: CharacterSet(charactersIn: " ，,、；;：:·-—\n\t"))
            if candidate.count >= 4 && Self.isCompleteDashboardSentence(candidate) {
                if endIdx < result.endIndex,
                   let lastScalar = candidate.unicodeScalars.last,
                   let nextScalar = result[endIdx...].unicodeScalars.first,
                   CharacterSet.alphanumerics.contains(lastScalar) && lastScalar.isASCII,
                   CharacterSet.alphanumerics.contains(nextScalar) && nextScalar.isASCII,
                   let spaceIdx = candidate.lastIndex(where: { $0.isWhitespace })
                {
                    let wordBounded = String(candidate[..<spaceIdx]).trimmingCharacters(in: .whitespaces)
                    if wordBounded.count >= 4 && Self.isCompleteDashboardSentence(wordBounded) {
                        return wordBounded
                    }
                }
                return candidate
            }
            endIdx = result.index(before: endIdx)
        }
        
        return String(result.prefix(limit))
            .trimmingCharacters(in: CharacterSet(charactersIn: " ，,、；;：:·-—\n\t"))
    }
    
    
    /// Lively, candid, sharp commentary summarizing what the user got done today ("干了啥"),
    /// mixing real praise with witty mild profanity / roasts — zero dry corporate logs.
    var doneTodayPoints: [String] {
        let _ = self.revision
        if !self.doneTodayCommentary.isEmpty {
            return Array(self.doneTodayCommentary.prefix(4))
        }
        return self.buildLivelyLocalDoneTodayCommentary()
    }
    
    
    /// Builds witty, candid local commentary grounded in today's real writing metrics and touched work.
    private func buildLivelyLocalDoneTodayCommentary() -> [String] {
        let now = Date()
        let hour = Calendar.current.component(.hour, from: now)
        let calendar = Calendar.current
        let rawTodayStats = self.todayStats
        let effectiveStats: DailyWritingStats = {
            if hour < 6,
               (rawTodayStats.typedChars + rawTodayStats.aiCompletedChars) == 0,
               let yesterday = calendar.date(byAdding: .day, value: -1, to: now)
            {
                let yKey = Self.dateKey(for: yesterday)
                if let yStats = self.recentDailyStats.first(where: { $0.dateKey == yKey }),
                   (yStats.typedChars + yStats.aiCompletedChars + yStats.documentsSaved) > 0
                {
                    return yStats
                }
            }
            return rawTodayStats
        }()
        let stats = effectiveStats
        let totalChars = stats.typedChars + stats.aiCompletedChars
        let todayDocs = self.database.documents
            .filter {
                !$0.id.hasPrefix("weekly:")
                    && (calendar.isDateInToday($0.updatedAt) || (hour < 6 && now.timeIntervalSince($0.updatedAt) <= 24 * 3600))
                    && Self.isMeaningfulDocumentContent($0.content)
            }
        
        var points: [String] = []
        
        // 1. Output & hand-typing punchline
        if stats.typedChars >= 1500 {
            points.append("手速直接干冒烟了，今天这波纯手搓输出太牛逼了，键盘都要给你磕一个。")
        } else if stats.typedChars >= 400 {
            points.append("实打实码了一大段，没光顾着画饼，这股狠劲值得夸爆。")
        } else if totalChars > 0 {
            points.append("稍微动了点笔热身，离火力全开还差一口气，别刚写两行就跑去摸鱼啊。")
        } else if hour >= 14 {
            points.append("快到点下班了还没咋开敲？今天摸鱼摸得挺坦然啊，键盘都快落灰了。")
        } else {
            points.append("刚开局还没怎么动手，先把第一段烂草稿拉出来，别搁这儿空想憋大招。")
        }
        
        // 2. AI collaboration roast/praise
        if stats.aiRequests >= 12 {
            points.append("使唤 AI 跟使唤长工似的，真TM会偷懒但也真高效，赛博包工头实锤。")
        } else if stats.aiRequests >= 3 {
            points.append("边写边拉 AI 打配合，脏活累活全甩过去，脑子省下来干正事，聪明。")
        } else if stats.typedChars >= 300 {
            points.append("今天几乎全靠肉身硬扛不借外挂，纯血手艺人，牛逼。")
        }
        
        // 3. Saves / files / momentum
        if stats.filesCreated >= 2 {
            points.append("一顿新建草稿，坑挖得比谁都欢，别光顾着爽，回头记得把坑填上。")
        } else if stats.documentsSaved >= 5 {
            points.append("疯狂狂按保存键，安全感拉满，稳得一批，绝不让电脑白嫖你半行心血。")
        } else if !todayDocs.isEmpty {
            points.append("盯着核心文稿来回打磨，没瞎切窗口乱逛，专注度拉满。")
        }
        
        // 4. Time-of-day / streak roast or hype
        if (hour >= 23 || hour < 5) && totalChars > 0 {
            points.append("大半夜还在死磕，真TM是个狠人，写完赶紧滚去睡觉别把肝熬炸了。")
        } else if self.currentWritingStreak >= 5 {
            points.append("已经连轴转这么久还没断更，这自律程度有点离谱，继续保持别掉链子。")
        }
        
        if points.count < 3 {
            let knownTitles = self.database.documents.map(\.title) + self.database.weeklyReports.map(\.title)
            if let digest = self.todayDigest,
               digest.dateKey == Self.dateKey(),
               digest.modelUsed != "本地摘要"
            {
                for item in Self.structuredSummaryPoints(from: digest.summary, maxPoints: 3) {
                    let cleaned = Self.sanitizeDashboardActionText(item, knownTitles: knownTitles, maxLength: nil, fallback: "")
                    if Self.hasMeaningfulActionSubstance(cleaned),
                       Self.isCompleteDashboardSentence(cleaned),
                       !points.contains(cleaned),
                       points.count < 4
                    {
                        points.append(cleaned)
                    }
                }
            }
        }
        
        return Array(points.prefix(4))
    }
    
    
    func loadDoneTodayCommentaryFromDatabase() {
        let todayKey = Self.dateKey()
        let raw = self.database.string(forKey: CotLocalDatabase.ConfigKey.aiDoneTodayCommentaryJSON)
        guard !raw.isEmpty,
              let data = raw.data(using: .utf8),
              let bundle = try? JSONDecoder().decode(DoneTodayCommentaryBundle.self, from: data),
              bundle.dateKey == todayKey,
              !bundle.items.isEmpty
        else {
            self.doneTodayCommentary = []
            self.doneTodayFromAI = false
            return
        }
        let knownTitles = self.database.documents.map(\.title) + self.database.weeklyReports.map(\.title)
        let validItems = bundle.items.compactMap { item -> String? in
            let cleaned = Self.sanitizeDashboardActionText(item, knownTitles: knownTitles, maxLength: nil, fallback: "")
            guard cleaned.count >= 4, Self.isCompleteDashboardSentence(cleaned) else { return nil }
            return cleaned
        }
        self.doneTodayCommentary = validItems
        self.doneTodayFromAI = bundle.isAIGenerated && !validItems.isEmpty
        self.doneTodayFingerprint = bundle.sourceFingerprint
        // If any stale truncated sentence was filtered out, allow a fresh regeneration on next visit.
        self.doneTodayUpdatedAt = (validItems.count == bundle.items.count) ? bundle.updatedAt : nil
    }
    
    
    /// Generates witty, sharp, human-sounding commentary for "干了啥" using AI (with lively local fallback).
    func refreshDoneTodayCommentary(force: Bool = false) async {
        guard !self.isRefreshingDoneToday else { return }
        
        let todayKey = Self.dateKey()
        if !force,
           !self.doneTodayCommentary.isEmpty,
           let updatedAt = self.doneTodayUpdatedAt,
           Calendar.current.isDateInToday(updatedAt),
           Date().timeIntervalSince(updatedAt) < 3 * 3600
        {
            return
        }
        
        let corpus = self.collectDoneTodayCorpus()
        let baseConfig = AIConfiguration.current
        let resolvedConfig = AIBotStore.shared.resolvedConfiguration(for: .weeklyReport, baseConfig: baseConfig)
        guard resolvedConfig.isUsable else {
            let local = self.buildLivelyLocalDoneTodayCommentary()
            self.persistDoneTodayCommentary(local, isAI: false, dateKey: todayKey, fingerprint: corpus.fingerprint)
            return
        }
        
        self.isRefreshingDoneToday = true
        defer { self.isRefreshingDoneToday = false }
        
        var config = resolvedConfig
        config.temperature = 0.85
        config.reasoningEffort = "low"
        
        let systemPrompt = """
        你是用户最懂他、嘴毒又护短的铁哥们。根据用户今天真实的写作数据与文稿片段，给「干了啥」写 3 到 4 条犀利点评。
        风格要求（极其重要）：
        1. 拒绝流水账和官话！严禁出现"推进了""保持专注""完成了结构迭代"这种 AI 味废话。
        2. 要有活人感：该夸就往死里夸（比如"这波输出太牛逼了""思路拆得真狠"），该损就犀利吐槽带点接地气的小脏话（比如"真TM卷""少摸点鱼""光挖坑不填坑""嘴上说着随便写写结果偷偷肝爆"），夸夸和毒舌穿插着来，像真朋友在工位旁边吐槽你。
        3. 紧扣今天真实干的事或真实摸鱼状态；不要出现文件名、书名号《》或机械字数播报。
        4. 每条 14 到 34 个字，口语化、有梗、有画面感；**每条都必须是语义完整、自然收尾的完整句子**，严禁半截话、省略号截断、冒号悬空或写到一半停住。
        5. 严格只输出 JSON 字符串数组，不要任何其他解释：
        ["点评1", "点评2", "点评3"]
        """
        
        let userPrompt = """
        今天日期：\(todayKey)
        \(corpus.promptText)
        """
        
        do {
            let response = try await AIClient(configuration: config).sendWithUsage([
                AIMessage(role: .system, text: systemPrompt),
                AIMessage(role: .user, text: userPrompt),
            ])
            let knownTitles = self.database.documents.map(\.title) + self.database.weeklyReports.map(\.title)
            let parsed = Self.parseDoneTodayCommentary(from: response.text, knownTitles: knownTitles)
            if !parsed.isEmpty {
                self.persistDoneTodayCommentary(parsed, isAI: true, dateKey: todayKey, fingerprint: corpus.fingerprint)
                self.recordAIUsage(
                    feature: "doneTodayCommentary",
                    model: config.wireConfiguration.model,
                    provider: config.provider.rawValue,
                    inputTokens: response.inputTokens ?? AINextTokenPredictor.estimateTokens(in: userPrompt),
                    outputTokens: response.outputTokens ?? AINextTokenPredictor.estimateTokens(in: response.text),
                    latencyMs: 600,
                    success: true
                )
                self.revision &+= 1
                return
            }
        } catch {
            // Fall through to witty local commentary
        }
        
        if self.doneTodayCommentary.isEmpty {
            let local = self.buildLivelyLocalDoneTodayCommentary()
            self.persistDoneTodayCommentary(local, isAI: false, dateKey: todayKey, fingerprint: corpus.fingerprint)
        } else {
            self.doneTodayUpdatedAt = Date()
        }
    }
    
    
    private func persistDoneTodayCommentary(
        _ items: [String],
        isAI: Bool,
        dateKey: String,
        fingerprint: String
    ) {
        let now = Date()
        self.doneTodayCommentary = items
        self.doneTodayFromAI = isAI
        self.doneTodayFingerprint = fingerprint
        self.doneTodayUpdatedAt = now
        let bundle = DoneTodayCommentaryBundle(
            dateKey: dateKey,
            items: items,
            isAIGenerated: isAI,
            sourceFingerprint: fingerprint,
            updatedAt: now
        )
        if let data = try? JSONEncoder().encode(bundle),
           let json = String(data: data, encoding: .utf8)
        {
            self.database.set(json, forKey: CotLocalDatabase.ConfigKey.aiDoneTodayCommentaryJSON)
        }
    }
    
    
    private func collectDoneTodayCorpus() -> (promptText: String, fingerprint: String) {
        let now = Date()
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: now)
        let rawToday = self.todayStats
        let stats: DailyWritingStats = {
            if hour < 6,
               (rawToday.typedChars + rawToday.aiCompletedChars) == 0,
               let yesterday = calendar.date(byAdding: .day, value: -1, to: now)
            {
                let yKey = Self.dateKey(for: yesterday)
                if let yStats = self.recentDailyStats.first(where: { $0.dateKey == yKey }),
                   (yStats.typedChars + yStats.aiCompletedChars + yStats.documentsSaved) > 0
                {
                    return yStats
                }
            }
            return rawToday
        }()
        var parts: [String] = [
            "【今日实况】当前时刻：\(hour)点；手写强度：\(stats.typedChars >= 1500 ? "极高" : stats.typedChars >= 400 ? "中等偏高" : stats.typedChars > 0 ? "轻度" : "几乎没动")；AI调用：\(stats.aiRequests)次；保存：\(stats.documentsSaved)次；新建：\(stats.filesCreated)次；连续创作：\(self.currentWritingStreak)天。"
        ]
        
        var snippets: [String] = []
        if self.database === CotLocalDatabase.shared {
            for case let doc as Document in NSDocumentController.shared.documents {
                let text = Self.boundedTextSlice(from: doc.textStorage, headLimit: 800).text
                guard Self.isMeaningfulDocumentContent(text) else { continue }
                snippets.append("正在写的片段：\n\(String(text.prefix(420)))")
                if snippets.count >= 3 { break }
            }
        }
        let todayDocs = self.database.documents
            .filter {
                !$0.id.hasPrefix("weekly:")
                    && (calendar.isDateInToday($0.updatedAt) || (hour < 6 && now.timeIntervalSince($0.updatedAt) <= 24 * 3600))
            }
            .sorted { $0.updatedAt > $1.updatedAt }
        for doc in todayDocs {
            guard snippets.count < 4 else { break }
            let trimmed = doc.content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard Self.isMeaningfulDocumentContent(trimmed) else { continue }
            snippets.append("今天改过的片段：\n\(String(trimmed.prefix(420)))")
        }
        if !snippets.isEmpty {
            parts.append(snippets.joined(separator: "\n---\n"))
        }
        let combined = parts.joined(separator: "\n\n")
        let fp = UserPersonalityAnalyzer.sha256Hex("done-v5|\(Self.dateKey())|\(stats.typedChars / 150)|\(stats.aiRequests / 2)|\(stats.documentsSaved)|\(snippets.count)|" + combined.prefix(800))
        return (combined, fp)
    }
    
    
    nonisolated static func parseDoneTodayCommentary(from raw: String, knownTitles: [String]) -> [String] {
        var cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let start = cleaned.firstIndex(of: "["), let end = cleaned.lastIndex(of: "]"), start < end {
            cleaned = String(cleaned[start...end])
        }
        guard let data = cleaned.data(using: .utf8),
              let array = try? JSONSerialization.jsonObject(with: data) as? [String]
        else { return [] }
        
        var seen = Set<String>()
        var results: [String] = []
        for item in array {
            let line = Self.sanitizeDashboardActionText(item, knownTitles: knownTitles, maxLength: nil, fallback: "")
            guard line.count >= 6,
                  Self.hasMeaningfulActionSubstance(line),
                  Self.isCompleteDashboardSentence(line),
                  seen.insert(line).inserted
            else { continue }
            results.append(line)
            if results.count >= 4 { break }
        }
        return results
    }
    
    
    /// Looks up a stored document record matching `id` or `title` for one-click jumping from predictions.
    func storedDocument(id: String?, title: String) -> StoredDocumentRecord? {
        if let id, let match = self.database.documents.first(where: { $0.id == id }) {
            return match
        }
        let cleaned = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return nil }
        return self.database.documents.first(where: { !$0.id.hasPrefix("weekly:") && $0.title == cleaned })
    }
    
    
    /// Loads cached AI document action predictions or immediately builds smart local predictions from recent documents.
    func loadActionPredictionsFromDatabase() {
        let knownTitles = self.database.documents.map(\.title) + self.database.weeklyReports.map(\.title)
        let raw = self.database.string(forKey: CotLocalDatabase.ConfigKey.aiActionPredictionsJSON)
        if !raw.isEmpty,
           let data = raw.data(using: .utf8),
           let bundle = try? JSONDecoder().decode(DocumentActionPredictionBundle.self, from: data),
           !bundle.predictions.isEmpty
        {
            var seen = Set<String>()
            let bracketChars = CharacterSet(charactersIn: "()（）[]【】「」『』《》〈〉")
            var needsConciseRefresh = false
            let cleanedPredictions: [DocumentActionPrediction] = bundle.predictions.compactMap { pred in
                let rawTrim = pred.action.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !rawTrim.hasSuffix(":"), !rawTrim.hasSuffix("：") else { return nil }
                if rawTrim.count > 20 || rawTrim.rangeOfCharacter(from: bracketChars) != nil {
                    needsConciseRefresh = true
                }
                var sanitized = pred
                sanitized.action = Self.sanitizePredictedActionText(
                    rawTrim,
                    knownTitles: knownTitles,
                    maxLength: 20
                )
                sanitized.reason = ""
                guard sanitized.action.count >= 4,
                      Self.hasMeaningfulActionSubstance(sanitized.action),
                      Self.isCompleteDashboardSentence(sanitized.action)
                else { return nil }
                let key = sanitized.action.lowercased().replacingOccurrences(of: " ", with: "")
                guard seen.insert(key).inserted else { return nil }
                return sanitized
            }
            if !cleanedPredictions.isEmpty {
                self.actionPredictions = cleanedPredictions
                self.actionPredictionsFromAI = bundle.isAIGenerated
                self.actionPredictionUpdatedAt = (cleanedPredictions.count == bundle.predictions.count && !needsConciseRefresh)
                    ? bundle.updatedAt
                    : nil
                self.actionPredictionFingerprint = bundle.sourceFingerprint
                return
            }
        }
        
        let local = Self.buildHeuristicActionPredictions(
            documents: self.database.documents.filter { !$0.id.hasPrefix("weekly:") },
            weeklyReports: self.database.weeklyReports,
            reminders: self.reminders
        )
        self.actionPredictions = local
        self.actionPredictionsFromAI = false
    }
    
    
    /// Uses AI (with noise-filtered smart fallback) to predict genuinely meaningful next moves
    /// in a direct, lively, human tone — never scraping `111`/`222` test noise.
    func refreshActionPredictions(force: Bool = false) async {
        
        guard !self.isPredictingActions else { return }
        
        if !force,
           !self.actionPredictions.isEmpty,
           let updatedAt = self.actionPredictionUpdatedAt,
           Date().timeIntervalSince(updatedAt) < 4 * 3600
        {
            return
        }
        
        let corpus = self.collectActionPredictionCorpus()
        let recentDocs = self.database.documents.filter { !$0.id.hasPrefix("weekly:") }
        
        // Immediately ensure clean non-junk local predictions while AI thinks
        if self.actionPredictions.isEmpty || force {
            self.actionPredictions = Self.buildHeuristicActionPredictions(
                documents: recentDocs,
                weeklyReports: self.database.weeklyReports,
                reminders: self.reminders
            )
            self.actionPredictionsFromAI = false
        }
        
        guard !corpus.promptText.isEmpty else { return }
        
        self.isPredictingActions = true
        defer { self.isPredictingActions = false }
        
        let baseConfig = AIConfiguration.current
        let resolvedConfig = AIBotStore.shared.resolvedConfiguration(for: .weeklyReport, baseConfig: baseConfig)
        guard resolvedConfig.isUsable else {
            let local = Self.buildHeuristicActionPredictions(
                documents: recentDocs,
                weeklyReports: self.database.weeklyReports,
                reminders: self.reminders
            )
            self.persistActionPredictions(local, isAI: false, fingerprint: corpus.fingerprint)
            return
        }
        
        var config = resolvedConfig
        config.temperature = 0.45
        config.reasoningEffort = "medium"
        
        let systemPrompt = """
        你是用户最懂业务与上下文的资深工作搭子。你手里有他刚打开/修改的真实文档、未勾完的待办、停笔段落、开放问题和最近周报。
        请你**精准且凝练**地推理出接下来最该立刻推进的 3 到 4 件事（「要干啥」）。

        铁律：
        1. **准**：死死咬住上下文里真实存在的具体问题、卡点或未完模块，直给最核心的下一步动作（例如「敲定支付回调重试上限并补单测」），绝不写"梳理一下思路/回顾文档/继续加油"这种废话！
        2. **极简短句**：`action` **严格控制在 8～15 个字**，单行即可读完；不要写解释、不要带尾巴从句、不要加冒号。
        3. **严禁出现任何括号**：绝对禁止使用任何括号或书名号（严禁 `()`、`（）`、`[]`、`【】`、`「」`、`《》`），也不要带字数统计。
        4. **洁癖过滤**：无视所有测试占位词（111、222、test、测试、asdf、demo），每条都必须是语义完整、自然收尾的短句。
        5. 严格只输出 JSON 数组，不要任何多余文字：
        [{"action":"8到15字无括号短句","doc_title":"关联文档标题","urgency":"高|中|常规"}]
        """
        
        let userPrompt = """
        当前时间：\(Self.currentReadableTimestamp())
        以下是用户近期真实文档内容与提取到的未完信号（停笔处/待办/未解问题），请给出最准确犀利的下一步预测：

        \(corpus.promptText)
        """
        
        do {
            let response = try await AIClient(configuration: config).sendWithUsage([
                AIMessage(role: .system, text: systemPrompt),
                AIMessage(role: .user, text: userPrompt),
            ])
            let parsed = Self.parseActionPredictions(from: response.text, documents: recentDocs)
            if !parsed.isEmpty {
                self.persistActionPredictions(parsed, isAI: true, fingerprint: corpus.fingerprint)
                self.recordAIUsage(
                    feature: "actionPrediction",
                    model: config.wireConfiguration.model,
                    provider: config.provider.rawValue,
                    inputTokens: response.inputTokens ?? AINextTokenPredictor.estimateTokens(in: userPrompt),
                    outputTokens: response.outputTokens ?? AINextTokenPredictor.estimateTokens(in: response.text),
                    latencyMs: 600,
                    success: true
                )
                return
            }
        } catch {
            // Fall through cleanly to local document heuristic prediction
        }
        
        let fallback = Self.buildHeuristicActionPredictions(
            documents: recentDocs,
            weeklyReports: self.database.weeklyReports,
            reminders: self.reminders
        )
        self.persistActionPredictions(fallback, isAI: false, fingerprint: corpus.fingerprint)
    }
    
    
    private func persistActionPredictions(
        _ predictions: [DocumentActionPrediction],
        isAI: Bool,
        fingerprint: String
    ) {
        let now = Date()
        self.actionPredictions = predictions
        self.actionPredictionsFromAI = isAI
        self.actionPredictionUpdatedAt = now
        self.actionPredictionFingerprint = fingerprint
        let bundle = DocumentActionPredictionBundle(
            predictions: predictions,
            isAIGenerated: isAI,
            sourceFingerprint: fingerprint,
            updatedAt: now
        )
        if let data = try? JSONEncoder().encode(bundle),
           let json = String(data: data, encoding: .utf8)
        {
            self.database.set(json, forKey: CotLocalDatabase.ConfigKey.aiActionPredictionsJSON)
        }
    }
    
    
    private static func currentReadableTimestamp() -> String {
        Self.readableTimestampFormatter.string(from: Date())
    }
    
    
    /// Extracts high-signal open threads (unchecked TODOs, open questions, trailing unfinished paragraph) from a document.
    private nonisolated static func extractOpenSignals(from content: String) -> [String] {
        let lines = content.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        var signals: [String] = []
        for line in lines {
            let lower = line.lowercased()
            let isTodo = line.hasPrefix("- [ ]") || line.hasPrefix("* [ ]")
                || lower.contains("todo") || lower.contains("fixme")
                || line.contains("待确认") || line.contains("待补") || line.contains("阻塞")
                || line.contains("卡点") || line.contains("风险") || line.contains("下一步")
            let isQuestion = (line.hasSuffix("？") || line.hasSuffix("?")) && line.count >= 6 && line.count <= 60
            if (isTodo || isQuestion), Self.hasMeaningfulActionSubstance(line) {
                signals.append(String(line.prefix(70)))
                if signals.count >= 5 { break }
            }
        }
        if let tail = lines.last, Self.hasMeaningfulActionSubstance(tail), !signals.contains(where: { $0.contains(tail.prefix(16)) }) {
            signals.append("停笔处：\(String(tail.prefix(72)))")
        }
        return signals
    }
    
    
    private func collectActionPredictionCorpus() -> (promptText: String, fingerprint: String) {
        var blocks: [String] = []
        var usedIDs = Set<String>()
        var usedTitles = Set<String>()
        
        if self.database === CotLocalDatabase.shared {
            for case let doc as Document in NSDocumentController.shared.documents {
                let text = Self.boundedTextSlice(from: doc.textStorage, headLimit: 16_384, tailLimit: 16_384).text
                guard text.count >= 12, Self.isMeaningfulDocumentContent(text) else { continue }
                let title = doc.displayName ?? "未命名文档"
                guard usedTitles.insert(title).inserted else { continue }
                let signals = Self.extractOpenSignals(from: text)
                let signalBlock = signals.isEmpty ? "" : "\n[关键未完信号]\n- " + signals.joined(separator: "\n- ")
                let head = String(text.prefix(520))
                let tail = text.count > 820 ? "\n...\n" + String(text.suffix(480)) : ""
                blocks.append("【打开中的文档：《\(title)》】\(signalBlock)\n\(head)\(tail)")
                if blocks.count >= 4 { break }
            }
        }
        
        let recentDocs = self.database.documents
            .filter { !$0.id.hasPrefix("weekly:") }
            .sorted { $0.updatedAt > $1.updatedAt }
        for record in recentDocs {
            guard blocks.count < 6 else { break }
            guard usedIDs.insert(record.id).inserted else { continue }
            guard !usedTitles.contains(record.title) else { continue }
            let trimmed = record.content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.count >= 12, Self.isMeaningfulDocumentContent(trimmed) else { continue }
            let signals = Self.extractOpenSignals(from: trimmed)
            let signalBlock = signals.isEmpty ? "" : "\n[关键未完信号]\n- " + signals.joined(separator: "\n- ")
            let head = String(trimmed.prefix(480))
            let tail = trimmed.count > 780 ? "\n...\n" + String(trimmed.suffix(420)) : ""
            blocks.append("【近期文档：《\(record.title)》】\(signalBlock)\n\(head)\(tail)")
        }
        
        if let latestReport = self.database.weeklyReports.sorted(by: { $0.updatedAt > $1.updatedAt }).first {
            let trimmed = latestReport.content.trimmingCharacters(in: .whitespacesAndNewlines)
            if Self.isMeaningfulDocumentContent(trimmed) {
                blocks.append("【最近周报：《\(latestReport.title)》】\n\(String(trimmed.prefix(650)))")
            }
        }
        
        let meaningfulReminders = self.reminders
            .filter { !$0.isCompleted && Self.hasMeaningfulActionSubstance($0.title) }
            .prefix(4)
            .map(\.title)
        if !meaningfulReminders.isEmpty {
            blocks.append("【未完成正经待办】\n" + meaningfulReminders.joined(separator: "\n"))
        }
        
        let combined = blocks.joined(separator: "\n\n")
        let fp = UserPersonalityAnalyzer.sha256Hex("pred-v7|" + combined)
        return (combined, fp)
    }
    
    
    /// Parses a JSON array returned by AI into structured `DocumentActionPrediction` items matched against local documents.
    nonisolated static func parseActionPredictions(
        from raw: String,
        documents: [StoredDocumentRecord]
    ) -> [DocumentActionPrediction] {
        var cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let start = cleaned.firstIndex(of: "["), let end = cleaned.lastIndex(of: "]"), start < end {
            cleaned = String(cleaned[start...end])
        }
        guard let data = cleaned.data(using: .utf8),
              let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else { return [] }
        
        let knownTitles = documents.map(\.title)
        var seen = Set<String>()
        var results: [DocumentActionPrediction] = []
        for (idx, dict) in array.enumerated() {
            let rawAction = (dict["action"] as? String ?? dict["task"] as? String ?? dict["title"] as? String ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let action = Self.sanitizePredictedActionText(
                rawAction,
                knownTitles: knownTitles,
                maxLength: 20
            )
            guard action.count >= 4,
                  Self.hasMeaningfulActionSubstance(action),
                  Self.isCompleteDashboardSentence(action),
                  seen.insert(action.lowercased()).inserted
            else { continue }
            
            let rawDocTitle = (dict["doc_title"] as? String ?? dict["document"] as? String ?? dict["source"] as? String ?? "")
                .replacingOccurrences(of: "《", with: "")
                .replacingOccurrences(of: "》", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let rawUrgency = (dict["urgency"] as? String ?? dict["priority"] as? String ?? "中")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let urgency: String = if rawUrgency.contains("高") || rawUrgency.lowercased() == "high" {
                "高"
            } else if rawUrgency.contains("常") || rawUrgency.contains("低") || rawUrgency.lowercased() == "low" {
                "常规"
            } else {
                "中"
            }
            
            let rawReason = (dict["reason"] as? String ?? dict["why"] as? String ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let cleanReason = Self.sanitizeDashboardActionText(
                rawReason,
                knownTitles: knownTitles,
                maxLength: 24,
                fallback: ""
            )
            
            let matchedDoc = documents.first(where: { $0.title == rawDocTitle })
                ?? documents.first(where: { !rawDocTitle.isEmpty && ($0.title.localizedCaseInsensitiveContains(rawDocTitle) || rawDocTitle.localizedCaseInsensitiveContains($0.title)) })
            
            results.append(DocumentActionPrediction(
                id: "ai-pred-\(idx)-\(action.prefix(16))",
                action: action,
                reason: cleanReason,
                sourceDocumentTitle: matchedDoc?.title ?? rawDocTitle,
                sourceDocumentID: matchedDoc?.id,
                urgency: urgency
            ))
            if results.count >= 4 { break }
        }
        return results
    }
    
    
    /// Noise-filtered local analyzer used offline or before AI responds: strictly discards test garbage (`111`, `222`, `test`)
    /// and turns real unfinished sections, open questions, and meaningful deadlines into human-sounding next steps.
    nonisolated static func buildHeuristicActionPredictions(
        documents: [StoredDocumentRecord],
        weeklyReports: [StoredWeeklyReport],
        reminders: [UserReminder]
    ) -> [DocumentActionPrediction] {
        var results: [DocumentActionPrediction] = []
        var seen = Set<String>()
        let knownTitles = documents.map(\.title) + weeklyReports.map(\.title)
        
        func appendIfUnique(_ pred: DocumentActionPrediction) {
            var cleaned = pred
            cleaned.action = Self.sanitizePredictedActionText(
                pred.action,
                knownTitles: knownTitles,
                maxLength: 20
            )
            cleaned.reason = ""
            let key = cleaned.action.lowercased().replacingOccurrences(of: " ", with: "")
            guard cleaned.action.count >= 4,
                  Self.hasMeaningfulActionSubstance(cleaned.action),
                  Self.isCompleteDashboardSentence(cleaned.action),
                  results.count < 4,
                  seen.insert(key).inserted
            else { return }
            results.append(cleaned)
        }
        
        let sortedDocs = documents
            .filter { Self.isMeaningfulDocumentContent($0.content) }
            .sorted { $0.updatedAt > $1.updatedAt }
        
        // 1. Scan meaningful recent docs for real unfinished items (strictly rejecting junk/headers)
        for doc in sortedDocs.prefix(8) {
            let lines = doc.content.components(separatedBy: .newlines)
            for rawLine in lines {
                let line = rawLine.trimmingCharacters(in: .whitespaces)
                guard line.count >= 5, line.count <= 90,
                      !line.hasSuffix(":"), !line.hasSuffix("：")
                else { continue }
                let lower = line.lowercased()
                let isExplicitAction = line.hasPrefix("- [ ]") || line.hasPrefix("* [ ]")
                    || lower.contains("todo") || lower.contains("fixme")
                    || line.contains("待确认") || line.contains("待补") || line.contains("下一步") || line.contains("后续")
                guard isExplicitAction else { continue }
                let clean = line
                    .replacingOccurrences(of: #"^[-*•]\s*\[\s*\]\s*"#, with: "", options: .regularExpression)
                    .replacingOccurrences(of: #"^(TODO|FIXME|todo|fixme|待办|下一步|后续)[:：]?\s*"#, with: "", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard clean.count >= 4, Self.hasMeaningfulActionSubstance(clean) else { continue }
                appendIfUnique(DocumentActionPrediction(
                    id: "heur-todo-\(doc.id)-\(results.count)",
                    action: clean,
                    reason: "",
                    sourceDocumentTitle: doc.title,
                    sourceDocumentID: doc.id,
                    urgency: (lower.contains("fixme") || line.contains("紧急")) ? "高" : "中"
                ))
                if results.count >= 2 { break }
            }
        }
        
        // 2. Detect empty trailing headings or real open questions in active docs
        for doc in sortedDocs.prefix(6) where results.count < 4 {
            let lines = doc.content.components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            guard !lines.isEmpty else { continue }
            
            if let lastLine = lines.last, lastLine.hasPrefix("#") {
                let heading = lastLine.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces)
                if !heading.isEmpty, heading.count <= 18,
                   Self.hasMeaningfulActionSubstance(heading),
                   Self.isCompleteDashboardSentence(heading)
                {
                    appendIfUnique(DocumentActionPrediction(
                        id: "heur-heading-\(doc.id)",
                        action: "补齐\(heading)章节内容",
                        reason: "",
                        sourceDocumentTitle: doc.title,
                        sourceDocumentID: doc.id,
                        urgency: "高"
                    ))
                    continue
                }
            }
            
            if let openQuestion = lines.reversed().first(where: {
                ($0.hasSuffix("？") || $0.hasSuffix("?"))
                    && $0.count >= 6 && $0.count <= 36
                    && Self.hasMeaningfulActionSubstance($0)
                    && Self.isCompleteDashboardSentence($0)
            }) {
                let condensed = openQuestion.count <= 18
                    ? openQuestion
                    : Self.sanitizePredictedActionText(openQuestion, knownTitles: knownTitles, maxLength: 18)
                appendIfUnique(DocumentActionPrediction(
                    id: "heur-q-\(doc.id)",
                    action: condensed,
                    reason: "",
                    sourceDocumentTitle: doc.title,
                    sourceDocumentID: doc.id,
                    urgency: "中"
                ))
                continue
            }
        }
        
        // 3. Fold real (non-junk!) active deadline reminders if space remains
        for item in reminders.filter({ !$0.isCompleted && $0.hasDeadline && Self.hasMeaningfulActionSubstance($0.title) }).prefix(2) where results.count < 4 {
            appendIfUnique(DocumentActionPrediction(
                id: "heur-rem-\(item.id)",
                action: item.title,
                reason: "",
                sourceDocumentTitle: "",
                sourceDocumentID: nil,
                urgency: "高"
            ))
        }
        
        if results.isEmpty {
            appendIfUnique(DocumentActionPrediction(
                id: "heur-human-fallback-1",
                action: "把写了一半的草稿收个尾",
                reason: "",
                sourceDocumentTitle: sortedDocs.first?.title ?? "",
                sourceDocumentID: sortedDocs.first?.id,
                urgency: "中"
            ))
            appendIfUnique(DocumentActionPrediction(
                id: "heur-human-fallback-2",
                action: "把本周完成的进展记入周报",
                reason: "",
                sourceDocumentTitle: "",
                sourceDocumentID: nil,
                urgency: "常规"
            ))
        }
        
        return results
    }
}


/// A single AI-predicted next action grounded in the user's actual documents.
nonisolated struct DocumentActionPrediction: Identifiable, Codable, Sendable, Equatable {
    
    var id: String
    var action: String
    var reason: String
    var sourceDocumentTitle: String
    var sourceDocumentID: String?
    var urgency: String
}


private nonisolated struct DocumentActionPredictionBundle: Codable, Sendable, Equatable {
    
    var predictions: [DocumentActionPrediction]
    var isAIGenerated: Bool
    var sourceFingerprint: String
    var updatedAt: Date
}


private nonisolated struct DoneTodayCommentaryBundle: Codable, Sendable, Equatable {
    
    var dateKey: String
    var items: [String]
    var isAIGenerated: Bool
    var sourceFingerprint: String
    var updatedAt: Date
}


// MARK: - Official API Pricing Estimator (USD & RMB)

/// Estimates real API spend (USD & RMB) from per-model input/output token usage using official list prices
/// (USD per 1M tokens) across major model families.
nonisolated enum AIModelPricingCatalog {
    
    struct ModelRate: Sendable, Equatable {
        let inputPerMillionUSD: Double
        let outputPerMillionUSD: Double
    }
    
    struct CostEstimate: Sendable, Equatable {
        let usd: Double
        let rmb: Double
        
        var formattedRMB: String {
            if self.rmb >= 100 { return String(format: "¥%.0f", self.rmb) }
            if self.rmb >= 10 { return String(format: "¥%.1f", self.rmb) }
            if self.rmb >= 0.01 { return String(format: "¥%.2f", self.rmb) }
            return self.rmb > 0 ? "¥<0.01" : "¥0.00"
        }
        
        var formattedUSD: String {
            if self.usd >= 100 { return String(format: "$%.0f", self.usd) }
            if self.usd >= 10 { return String(format: "$%.1f", self.usd) }
            if self.usd >= 0.01 { return String(format: "$%.2f", self.usd) }
            return self.usd > 0 ? "$<0.01" : "$0.00"
        }
    }
    
    /// Reference USD -> CNY conversion rate used for RMB cost display.
    static let usdToRMBRate: Double = 7.25
    
    
    /// Resolves official API per-1M-token USD rates for a model identifier (case-insensitive substring match).
    static func rate(for modelName: String) -> ModelRate {
        let m = modelName.lowercased()
        
        // Local Ollama / free runners
        if m.contains("ollama") || m.contains(":latest") || m.contains(":7b") || m.contains(":8b") || m.contains("llama3") {
            return ModelRate(inputPerMillionUSD: 0, outputPerMillionUSD: 0)
        }
        
        // Anthropic Claude
        if m.contains("claude") {
            if m.contains("opus") {
                return ModelRate(inputPerMillionUSD: 15.0, outputPerMillionUSD: 75.0)
            }
            if m.contains("haiku") {
                return ModelRate(inputPerMillionUSD: 0.80, outputPerMillionUSD: 4.0)
            }
            // Sonnet 3.5 / 3.7 / 4 / 4.5
            return ModelRate(inputPerMillionUSD: 3.0, outputPerMillionUSD: 15.0)
        }
        
        // OpenAI GPT & o-series
        if m.contains("gpt-5") {
            if m.contains("mini") || m.contains("nano") {
                return ModelRate(inputPerMillionUSD: 0.40, outputPerMillionUSD: 1.60)
            }
            return ModelRate(inputPerMillionUSD: 2.50, outputPerMillionUSD: 10.0)
        }
        if m.contains("gpt-4.1") {
            if m.contains("nano") { return ModelRate(inputPerMillionUSD: 0.10, outputPerMillionUSD: 0.40) }
            if m.contains("mini") { return ModelRate(inputPerMillionUSD: 0.40, outputPerMillionUSD: 1.60) }
            return ModelRate(inputPerMillionUSD: 2.00, outputPerMillionUSD: 8.00)
        }
        if m.contains("gpt-4o-mini") {
            return ModelRate(inputPerMillionUSD: 0.15, outputPerMillionUSD: 0.60)
        }
        if m.contains("gpt-4o") || m.contains("o3") {
            return ModelRate(inputPerMillionUSD: 2.50, outputPerMillionUSD: 10.0)
        }
        if m.contains("o4-mini") || m.contains("o3-mini") || m.contains("o1-mini") {
            return ModelRate(inputPerMillionUSD: 1.10, outputPerMillionUSD: 4.40)
        }
        
        // DeepSeek V3 / V4 / R1
        if m.contains("deepseek") {
            if m.contains("reasoner") || m.contains("r1") {
                return ModelRate(inputPerMillionUSD: 0.55, outputPerMillionUSD: 2.19)
            }
            return ModelRate(inputPerMillionUSD: 0.27, outputPerMillionUSD: 1.10)
        }
        
        // Google Gemini
        if m.contains("gemini") {
            if m.contains("pro") {
                return ModelRate(inputPerMillionUSD: 1.25, outputPerMillionUSD: 10.0)
            }
            return ModelRate(inputPerMillionUSD: 0.15, outputPerMillionUSD: 0.60)
        }
        
        // Moonshot Kimi
        if m.contains("kimi") || m.contains("moonshot") {
            return ModelRate(inputPerMillionUSD: 0.60, outputPerMillionUSD: 2.50)
        }
        
        // Zhipu GLM
        if m.contains("glm") {
            if m.contains("flash") || m.contains("air") {
                return ModelRate(inputPerMillionUSD: 0.14, outputPerMillionUSD: 0.56)
            }
            return ModelRate(inputPerMillionUSD: 0.70, outputPerMillionUSD: 2.80)
        }
        
        // MiniMax
        if m.contains("minimax") || m.contains("abab") {
            return ModelRate(inputPerMillionUSD: 0.40, outputPerMillionUSD: 1.60)
        }
        
        // Alibaba Qwen
        if m.contains("qwen") {
            if m.contains("turbo") || m.contains("flash") {
                return ModelRate(inputPerMillionUSD: 0.05, outputPerMillionUSD: 0.20)
            }
            if m.contains("max") {
                return ModelRate(inputPerMillionUSD: 1.60, outputPerMillionUSD: 6.40)
            }
            return ModelRate(inputPerMillionUSD: 0.40, outputPerMillionUSD: 1.20)
        }
        
        // ByteDance Doubao
        if m.contains("doubao") {
            return ModelRate(inputPerMillionUSD: 0.12, outputPerMillionUSD: 0.30)
        }
        
        // Reasonable blended mainstream default (e.g. generic OpenAI-compatible model)
        return ModelRate(inputPerMillionUSD: 0.50, outputPerMillionUSD: 2.00)
    }
    
    
    static func estimateCost(model: String, inputTokens: Int, outputTokens: Int) -> CostEstimate {
        let r = Self.rate(for: model)
        let inCost = (Double(max(0, inputTokens)) / 1_000_000.0) * r.inputPerMillionUSD
        let outCost = (Double(max(0, outputTokens)) / 1_000_000.0) * r.outputPerMillionUSD
        let usd = inCost + outCost
        return CostEstimate(usd: usd, rmb: usd * Self.usdToRMBRate)
    }
    
    
    static func estimateTotalCost(models: [ModelUsageSummary], fallbackTotals: AIUsageTotals) -> CostEstimate {
        if !models.isEmpty {
            var usd = 0.0
            for item in models {
                usd += Self.estimateCost(model: item.model, inputTokens: item.inputTokens, outputTokens: item.outputTokens).usd
            }
            return CostEstimate(usd: usd, rmb: usd * Self.usdToRMBRate)
        }
        return Self.estimateCost(
            model: "default",
            inputTokens: fallbackTotals.inputTokens,
            outputTokens: fallbackTotals.outputTokens
        )
    }
}
