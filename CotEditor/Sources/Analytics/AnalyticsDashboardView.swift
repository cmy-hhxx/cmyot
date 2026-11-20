//
//  AnalyticsDashboardView.swift
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
import Charts
import SwiftUI

/// Routes dashboard presentation requests into the active editor window (never opens a standalone window).
@MainActor final class AnalyticsDashboardWindowController {
    
    static let shared = AnalyticsDashboardWindowController()
    
    
    private init() {}
    
    
    func showWindow(_ sender: Any?) {
        
        self.showInWindow(preferredWindow: (sender as? NSWindow) ?? NSApp.mainWindow)
    }
    
    
    func showInWindow(preferredWindow: NSWindow? = nil) {
        
        AnalyticsManager.shared.flushPendingStats()
        AnalyticsManager.shared.reloadFromDatabase()
        
        if let activeWC = self.resolveDocumentWindowController(preferredWindow: preferredWindow),
           let contentVC = activeWC.workspaceContentViewController
        {
            contentVC.showInWindowCenter(.dashboard)
            activeWC.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        
        if let controller = NSDocumentController.shared as? DocumentController {
            _ = try? controller.openUntitledDocumentAndDisplay(true)
            if let activeWC = self.resolveDocumentWindowController(preferredWindow: nil),
               let contentVC = activeWC.workspaceContentViewController
            {
                contentVC.showInWindowCenter(.dashboard)
                activeWC.window?.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
            }
        }
    }
    
    
    private func resolveDocumentWindowController(preferredWindow: NSWindow?) -> DocumentWindowController? {
        
        if let wc = preferredWindow?.windowController as? DocumentWindowController {
            return wc
        }
        if let wc = NSApp.mainWindow?.windowController as? DocumentWindowController {
            return wc
        }
        return NSApp.orderedWindows
            .compactMap { $0.windowController as? DocumentWindowController }
            .first
    }
}


/// Settings pane wrapper matching the unified Settings pane proportions.
struct DashboardSettingsView: View {
    
    var body: some View {
        
        AnalyticsDashboardView(isEmbeddedInSettings: true)
            .frame(width: SettingsPaneLayout.width, height: SettingsPaneLayout.height)
    }
}


// MARK: - Design Tokens

/// One easing curve, three durations.
private enum DashMotion {
    
    static let quick = Animation.timingCurve(0.2, 0, 0, 1, duration: 0.14)
    static let standard = Animation.timingCurve(0.2, 0, 0, 1, duration: 0.22)
    static let enter = Animation.timingCurve(0.2, 0, 0, 1, duration: 0.32)
}


/// Graphite neutrals plus a single ink-green accent borrowed from the heatmap.
private struct DashPalette {
    
    let isDark: Bool
    
    init(_ scheme: ColorScheme) {
        
        self.isDark = (scheme == .dark)
    }
    
    var canvas: Color { Color(nsColor: .windowBackgroundColor) }
    var card: Color { self.isDark ? Color.white.opacity(0.035) : Color(nsColor: .controlBackgroundColor) }
    var hover: Color { self.isDark ? Color.white.opacity(0.03) : Color.black.opacity(0.02) }
    var inset: Color { self.isDark ? Color.white.opacity(0.03) : Color.black.opacity(0.025) }
    var hairline: Color { self.isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.08) }
    var hairlineStrong: Color { self.isDark ? Color.white.opacity(0.24) : Color.black.opacity(0.22) }
    var neutralMark: Color { self.isDark ? Color.white.opacity(0.20) : Color.black.opacity(0.14) }
    var modal: Color { self.isDark ? Color(white: 0.155) : Color(nsColor: .controlBackgroundColor) }
    var accent: Color { self.isDark ? Color(red: 0.40, green: 0.78, blue: 0.54) : Color(red: 0.12, green: 0.48, blue: 0.29) }
    
    
    func heat(_ level: Int) -> Color {
        
        if self.isDark {
            switch level {
                case 4: Color(red: 0.40, green: 0.78, blue: 0.54)
                case 3: Color(red: 0.26, green: 0.58, blue: 0.40)
                case 2: Color(red: 0.17, green: 0.40, blue: 0.28)
                case 1: Color(red: 0.12, green: 0.25, blue: 0.19)
                default: Color.white.opacity(0.06)
            }
        } else {
            switch level {
                case 4: Color(red: 0.12, green: 0.48, blue: 0.29)
                case 3: Color(red: 0.25, green: 0.63, blue: 0.40)
                case 2: Color(red: 0.52, green: 0.79, blue: 0.60)
                case 1: Color(red: 0.80, green: 0.91, blue: 0.83)
                default: Color.black.opacity(0.055)
            }
        }
    }
    
    
    var futureCell: Color { self.isDark ? Color.white.opacity(0.02) : Color.black.opacity(0.02) }
}


// MARK: - Precomputed Snapshot

/// Everything the dashboard draws, computed once per data revision so hovering never recomputes analytics.
private struct DashboardSnapshot {
    
    struct ChartDay: Identifiable {
        
        var id: String
        var date: Date
        var typed: Int
        var ai: Int
        var input: Int
        var output: Int
        var isToday: Bool
    }
    
    struct AISlice {
        
        var totals: AIUsageTotals
        var models: [ModelUsageSummary]
        var features: [FeatureUsageSummary]
        var latencyMs: Int
    }
    
    var today: DailyWritingStats
    var typedBaseline7: Int
    var days14: [ChartDay]
    var days7: [ChartDay]
    var series7: [DailyWritingStats]
    var touchedDocTitles: [String]
    var streak: Int
    var years: [Int]
    var heatmap: YearlyHeatmapData
    var orderedCells: [HeatmapDayCell]
    var longestStreak: Int
    var rhythm: [WeekdayActivityPoint]
    var aiToday: AISlice
    var ai30: AISlice
    var digest: DailyAIDigest?
    var reminders: [UserReminder]
    var detectedTodos: [DetectedNoteTodo]
    
    
    @MainActor static func build(analytics: AnalyticsManager, year: Int) -> DashboardSnapshot {
        
        let today = analytics.todayStats
        let series14 = analytics.dailySeries(days: 14)
        let series7 = Array(series14.suffix(7))
        let prior = series7.dropLast()
        let baseline = prior.isEmpty ? 0 : prior.reduce(0) { $0 + $1.typedChars } / prior.count
        
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        let chartDays: [ChartDay] = series14.map { item in
            ChartDay(
                id: item.dateKey,
                date: formatter.date(from: item.dateKey) ?? Date(),
                typed: item.typedChars,
                ai: item.aiCompletedChars,
                input: item.inputTokens,
                output: item.outputTokens,
                isToday: item.dateKey == today.dateKey
            )
        }
        
        let heatmap = analytics.yearlyHeatmap(year: year)
        let ordered = heatmap.weeks.flatMap { $0 }.filter { !$0.isOutOfYear && !$0.isFuture }
        var longest = 0
        var current = 0
        for cell in ordered {
            if cell.level > 0 {
                current += 1
                longest = max(longest, current)
            } else {
                current = 0
            }
        }
        
        let reminders = Array((analytics.overdueReminders + analytics.todayReminders + analytics.tomorrowReminders).prefix(4))
        
        return DashboardSnapshot(
            today: today,
            typedBaseline7: baseline,
            days14: chartDays,
            days7: Array(chartDays.suffix(7)),
            series7: series7,
            touchedDocTitles: analytics.todayTouchedDocuments().prefix(5).map(\.title),
            streak: analytics.currentWritingStreak,
            years: analytics.availableHeatmapYears(),
            heatmap: heatmap,
            orderedCells: ordered,
            longestStreak: longest,
            rhythm: analytics.weekdayActivityDistribution(days: 90),
            aiToday: AISlice(
                totals: analytics.aiUsageTotals(forTodayOnly: true),
                models: analytics.todayModelDistribution(),
                features: analytics.todayFeatureDistribution(),
                latencyMs: analytics.averageLatencyMs(forTodayOnly: true)
            ),
            ai30: AISlice(
                totals: analytics.aiUsageTotals(forTodayOnly: false, days: 30),
                models: analytics.modelDistribution(days: 30),
                features: analytics.featureDistribution(days: 30),
                latencyMs: analytics.averageLatencyMs(forTodayOnly: false, days: 30)
            ),
            digest: analytics.todayDigest,
            reminders: reminders,
            detectedTodos: reminders.isEmpty ? analytics.detectedNoteTodos(limit: 3) : []
        )
    }
}


// MARK: - Dashboard

/// A quiet writing ledger: three figures, one heatmap, and today's notes.
struct AnalyticsDashboardView: View {
    
    fileprivate enum KPIKind: String, Identifiable {
        
        case typed
        case completion
        case consumption
        
        var id: String { self.rawValue }
    }
    
    fileprivate enum AIRange: String, CaseIterable, Identifiable {
        
        case today = "今日"
        case thirtyDays = "30 天"
        
        var id: String { self.rawValue }
    }
    
    let isEmbeddedInSettings: Bool
    var onDismiss: (() -> Void)?
    
    @Environment(\.colorScheme) private var colorScheme
    
    @State private var analytics = AnalyticsManager.shared
    @State private var profileManager = UserProfileManager.shared
    @State private var snapshot: DashboardSnapshot?
    @State private var expandedKPI: KPIKind?
    @State private var aiRange: AIRange = .thirtyDays
    @State private var selectedYear: Int = Calendar.current.component(.year, from: Date())
    @State private var selectedDetail: HeatmapDayDetail?
    @State private var hasAppeared = false
    
    
    init(isEmbeddedInSettings: Bool, onDismiss: (() -> Void)? = nil) {
        
        self.isEmbeddedInSettings = isEmbeddedInSettings
        self.onDismiss = onDismiss
    }
    
    
    private var palette: DashPalette { DashPalette(self.colorScheme) }
    private var compact: Bool { self.isEmbeddedInSettings }
    private var outerPadding: CGFloat { self.compact ? 16 : 24 }
    private var gap: CGFloat { self.compact ? 12 : 16 }
    private var cardPadding: CGFloat { self.compact ? 16 : 20 }
    
    
    var body: some View {
        
        ZStack {
            ScrollView {
                Group {
                    if let snapshot = self.snapshot {
                        self.content(snapshot)
                            .opacity(self.hasAppeared ? 1 : 0)
                            .offset(y: self.hasAppeared ? 0 : 6)
                    } else {
                        Color.clear.frame(height: 480)
                    }
                }
                .padding(self.outerPadding)
                .frame(maxWidth: 1120, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .background(self.palette.canvas)
            
            if let detail = self.selectedDetail {
                self.detailOverlay(detail)
                    .transition(.opacity)
                    .zIndex(10)
            }
        }
        .onAppear {
            self.analytics.flushPendingStats()
            self.analytics.reloadFromDatabase()
            if !self.analytics.availableHeatmapYears().contains(self.selectedYear) {
                self.selectedYear = Calendar.current.component(.year, from: Date())
            }
            self.rebuild()
            if !self.hasAppeared {
                withAnimation(DashMotion.enter) {
                    self.hasAppeared = true
                }
            }
        }
        .onChange(of: self.analytics.revision) { _, _ in
            self.rebuild()
        }
        .onChange(of: self.selectedYear) { _, _ in
            self.rebuild()
        }
        .onKeyPress(.escape) {
            if self.selectedDetail != nil {
                self.closeDetail()
                return .handled
            }
            if self.expandedKPI != nil {
                withAnimation(DashMotion.standard) {
                    self.expandedKPI = nil
                }
                return .handled
            }
            return .ignored
        }
    }
    
    
    private func rebuild() {
        
        self.snapshot = DashboardSnapshot.build(analytics: self.analytics, year: self.selectedYear)
    }
    
    
    // MARK: Layout
    
    private func content(_ s: DashboardSnapshot) -> some View {
        
        VStack(alignment: .leading, spacing: self.gap) {
            self.header(s)
                .padding(.bottom, 4)
            
            self.kpiRow(s)
            
            if let kind = self.expandedKPI {
                self.detailPanel(kind, s)
                    .id(kind)
                    .transition(.opacity.combined(with: .offset(y: -4)))
            }
            
            HeatmapCard(
                heatmap: s.heatmap,
                longestStreak: s.longestStreak,
                canGoBack: self.selectedYear > (s.years.first ?? self.selectedYear),
                canGoForward: self.selectedYear < (s.years.last ?? self.selectedYear),
                selectedKey: self.selectedDetail?.cell.dateKey,
                palette: self.palette,
                compact: self.compact,
                padding: self.cardPadding,
                onPreviousYear: { self.selectedYear -= 1 },
                onNextYear: { self.selectedYear += 1 },
                onSelect: { self.openDetail($0) }
            )
            
            HStack(alignment: .top, spacing: self.gap) {
                self.summaryCard(s)
                self.rhythmCard(s)
                    .frame(width: self.compact ? 256 : 320)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }
    
    
    // MARK: Header
    
    private func header(_ s: DashboardSnapshot) -> some View {
        
        let profile = self.profileManager.activeProfile
        
        return HStack(alignment: .center, spacing: 12) {
            UserAvatarCircleView(profile: profile, size: 32)
            
            VStack(alignment: .leading, spacing: 2) {
                Text("数据看板")
                    .font(.system(size: self.compact ? 17 : 20, weight: .semibold))
                Text("\(profile.displayName) · \(Self.todayTitle())")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            
            Spacer(minLength: 12)
            
            HStack(spacing: 24) {
                self.headerFigure(label: "连续写作", value: "\(s.streak) 天")
                if !self.compact {
                    self.headerFigure(label: "\(self.selectedYear) 年累计", value: Self.compactChars(s.heatmap.totalTypedChars))
                }
            }
            
            if let onDismiss = self.onDismiss {
                QuietButton(title: "返回", systemImage: "chevron.left", palette: self.palette, action: onDismiss)
                    .help("返回编辑器 (Esc)")
                    .padding(.leading, 8)
            }
        }
    }
    
    
    private func headerFigure(label: String, value: String) -> some View {
        
        VStack(alignment: .trailing, spacing: 2) {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 14, weight: .medium))
                .monospacedDigit()
        }
    }
    
    
    // MARK: KPI Row
    
    private func kpiRow(_ s: DashboardSnapshot) -> some View {
        
        let today = s.today
        let produced = today.typedChars + today.aiCompletedChars
        let aiShare = produced > 0 ? Int((Double(today.aiCompletedChars) * 100 / Double(produced)).rounded()) : 0
        
        let typedNote: (String, Color) = {
            guard s.typedBaseline7 > 0 else { return ("近 7 天暂无记录", .secondary) }
            let pct = Int((Double(today.typedChars - s.typedBaseline7) * 100 / Double(s.typedBaseline7)).rounded())
            return pct >= 0
                ? ("较 7 日均值 +\(pct)%", self.palette.accent)
                : ("较 7 日均值 \(pct)%", .secondary)
        }()
        
        let completionNote = today.aiCompletionAccepts > 0
            ? "采纳 \(today.aiCompletionAccepts) 次 · 占今日产出 \(aiShare)%"
            : "今日暂无采纳"
        
        let latency = s.aiToday.latencyMs
        let consumptionNote = today.aiRequests > 0
            ? "\(today.aiRequests) 次调用" + (latency > 0 ? " · 平均 \(latency) ms" : "")
            : "今日暂无调用"
        
        return HStack(alignment: .top, spacing: self.gap) {
            KPICard(
                title: "今日输入",
                value: Self.int(today.typedChars),
                unit: "字",
                note: typedNote.0,
                noteColor: typedNote.1,
                isExpanded: self.expandedKPI == .typed,
                compact: self.compact,
                padding: self.cardPadding,
                palette: self.palette
            ) { self.toggle(.typed) }
            
            KPICard(
                title: "AI 补全",
                value: Self.int(today.aiCompletedChars),
                unit: "字",
                note: completionNote,
                noteColor: .secondary,
                isExpanded: self.expandedKPI == .completion,
                compact: self.compact,
                padding: self.cardPadding,
                palette: self.palette
            ) { self.toggle(.completion) }
            
            KPICard(
                title: "AI 消耗",
                value: AnalyticsManager.formatCompactTokenCount(today.totalTokens),
                unit: "Tokens",
                note: consumptionNote,
                noteColor: .secondary,
                isExpanded: self.expandedKPI == .consumption,
                compact: self.compact,
                padding: self.cardPadding,
                palette: self.palette
            ) { self.toggle(.consumption) }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
    
    
    private func toggle(_ kind: KPIKind) {
        
        withAnimation(DashMotion.standard) {
            self.expandedKPI = (self.expandedKPI == kind) ? nil : kind
        }
    }
    
    
    // MARK: Detail Panels
    
    @ViewBuilder
    private func detailPanel(_ kind: KPIKind, _ s: DashboardSnapshot) -> some View {
        
        VStack(alignment: .leading, spacing: 16) {
            switch kind {
                case .typed: self.typedPanel(s)
                case .completion: self.completionPanel(s)
                case .consumption: self.consumptionPanel(s)
            }
        }
        .modifier(DashCard(palette: self.palette, padding: self.cardPadding))
    }
    
    
    private func panelHeader<Trailing: View>(
        _ title: String,
        meta: String,
        @ViewBuilder trailing: () -> Trailing = { EmptyView() }
    ) -> some View {
        
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
            Text(meta)
                .font(.system(size: 12))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 8)
            trailing()
            IconButton(systemImage: "xmark", palette: self.palette, isClose: true) {
                withAnimation(DashMotion.standard) {
                    self.expandedKPI = nil
                }
            }
            .help("收起")
        }
    }
    
    
    private func typedPanel(_ s: DashboardSnapshot) -> some View {
        
        let total = s.days14.reduce(0) { $0 + $1.typed }
        let activeDays = s.days14.filter { $0.typed > 0 }.count
        let average = activeDays > 0 ? total / activeDays : 0
        let peak = s.days14.map(\.typed).max() ?? 0
        
        return VStack(alignment: .leading, spacing: 16) {
            self.panelHeader("近 14 天输入", meta: "合计 \(Self.int(total)) 字 · 活跃日均 \(Self.int(average)) 字")
            
            HStack(alignment: .top, spacing: 24) {
                Chart {
                    ForEach(s.days14) { day in
                        BarMark(
                            x: .value("日期", day.date, unit: .day),
                            y: .value("字数", day.typed),
                            width: .ratio(0.62)
                        )
                        .foregroundStyle(day.isToday ? self.palette.accent : self.palette.neutralMark)
                        .cornerRadius(3)
                    }
                    if average > 0 {
                        RuleMark(y: .value("日均", average))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                            .foregroundStyle(Color.secondary.opacity(0.6))
                    }
                }
                .chartXAxis { self.dayAxis(stride: 2) }
                .chartYAxis { self.valueAxis() }
                .frame(height: 176)
                .frame(maxWidth: .infinity)
                
                VStack(alignment: .leading, spacing: 16) {
                    StatTable(rows: [
                        ("新建文档", "\(s.today.filesCreated) 篇"),
                        ("今日保存", "\(s.today.documentsSaved) 次"),
                        ("14 日峰值", "\(Self.int(peak)) 字"),
                        ("活跃天数", "\(activeDays) / 14"),
                    ], palette: self.palette)
                    
                    if !s.touchedDocTitles.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("今日编辑")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                            ForEach(Array(s.touchedDocTitles.enumerated()), id: \.offset) { _, title in
                                Text(title)
                                    .font(.system(size: 12))
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                        }
                    }
                }
                .frame(width: self.compact ? 200 : 240)
            }
        }
    }
    
    
    private func completionPanel(_ s: DashboardSnapshot) -> some View {
        
        let accepts7 = s.series7.reduce(0) { $0 + $1.aiCompletionAccepts }
        let ai7 = s.series7.reduce(0) { $0 + $1.aiCompletedChars }
        let typed7 = s.series7.reduce(0) { $0 + $1.typedChars }
        let local7 = s.series7.reduce(0) { $0 + $1.localHits }
        let share7 = (ai7 + typed7) > 0 ? Int((Double(ai7) * 100 / Double(ai7 + typed7)).rounded()) : 0
        let perAccept = accepts7 > 0 ? ai7 / accepts7 : 0
        
        return VStack(alignment: .leading, spacing: 16) {
            self.panelHeader("近 7 天补全", meta: "补全 \(Self.int(ai7)) 字 · 采纳 \(accepts7) 次")
            
            HStack(alignment: .top, spacing: 24) {
                Chart {
                    ForEach(s.days7) { day in
                        AreaMark(
                            x: .value("日期", day.date, unit: .day),
                            y: .value("补全", day.ai)
                        )
                        .interpolationMethod(.monotone)
                        .foregroundStyle(self.palette.accent.opacity(0.08))
                        
                        LineMark(
                            x: .value("日期", day.date, unit: .day),
                            y: .value("补全", day.ai)
                        )
                        .interpolationMethod(.monotone)
                        .lineStyle(StrokeStyle(lineWidth: 1.75, lineCap: .round, lineJoin: .round))
                        .foregroundStyle(self.palette.accent)
                        
                        if day.isToday {
                            PointMark(
                                x: .value("日期", day.date, unit: .day),
                                y: .value("补全", day.ai)
                            )
                            .symbolSize(28)
                            .foregroundStyle(self.palette.accent)
                        }
                    }
                }
                .chartXAxis { self.dayAxis(stride: 1) }
                .chartYAxis { self.valueAxis() }
                .frame(height: 176)
                .frame(maxWidth: .infinity)
                
                StatTable(rows: [
                    ("今日采纳", "\(s.today.aiCompletionAccepts) 次"),
                    ("单次平均", "\(perAccept) 字"),
                    ("7 日 AI 占比", "\(share7)%"),
                    ("本地命中", "\(local7) 次"),
                ], palette: self.palette)
                .frame(width: self.compact ? 200 : 240)
            }
        }
    }
    
    
    private func consumptionPanel(_ s: DashboardSnapshot) -> some View {
        
        let slice = (self.aiRange == .today) ? s.aiToday : s.ai30
        let totals = slice.totals
        let meta = "\(totals.requests) 次 · 输入 \(AnalyticsManager.formatCompactTokenCount(totals.inputTokens)) · 输出 \(AnalyticsManager.formatCompactTokenCount(totals.outputTokens))"
            + (slice.latencyMs > 0 ? " · \(slice.latencyMs) ms" : "")
        
        return VStack(alignment: .leading, spacing: 16) {
            self.panelHeader("AI 消耗", meta: meta) {
                Picker("", selection: self.$aiRange) {
                    ForEach(AIRange.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .controlSize(.small)
                .frame(width: 112)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 16) {
                    Text("近 7 天 Tokens")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Spacer()
                    LegendSwatch(color: self.palette.neutralMark, label: "输入")
                    LegendSwatch(color: self.palette.accent, label: "输出")
                }
                
                Chart {
                    ForEach(s.days7) { day in
                        BarMark(
                            x: .value("日期", day.date, unit: .day),
                            y: .value("Tokens", day.input),
                            width: .ratio(0.5)
                        )
                        .foregroundStyle(self.palette.neutralMark)
                        
                        BarMark(
                            x: .value("日期", day.date, unit: .day),
                            y: .value("Tokens", day.output),
                            width: .ratio(0.5)
                        )
                        .foregroundStyle(self.palette.accent)
                    }
                }
                .chartXAxis { self.dayAxis(stride: 1) }
                .chartYAxis { self.valueAxis(compactTokens: true) }
                .frame(height: 136)
            }
            
            HStack(alignment: .top, spacing: 24) {
                RankTable(
                    title: "模型",
                    rows: slice.models.prefix(5).map {
                        ($0.model, "\(Int(($0.share * 100).rounded()))%", AnalyticsManager.formatCompactTokenCount($0.totalTokens))
                    },
                    palette: self.palette
                )
                RankTable(
                    title: "功能",
                    rows: slice.features.prefix(5).map {
                        ($0.displayName, "\(Int(($0.share * 100).rounded()))%", "\($0.requests) 次")
                    },
                    palette: self.palette
                )
            }
        }
    }
    
    
    private func dayAxis(stride: Int) -> some AxisContent {
        
        AxisMarks(values: .stride(by: .day, count: stride)) { _ in
            AxisValueLabel(format: .dateTime.month(.defaultDigits).day(), centered: true)
                .font(.system(size: 10).monospacedDigit())
                .foregroundStyle(Color.secondary)
        }
    }
    
    
    private func valueAxis(compactTokens: Bool = false) -> some AxisContent {
        
        AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { value in
            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                .foregroundStyle(self.palette.hairline)
            AxisValueLabel {
                if let number = value.as(Int.self) {
                    Text(compactTokens ? AnalyticsManager.formatCompactTokenCount(number) : Self.int(number))
                        .font(.system(size: 10).monospacedDigit())
                        .foregroundStyle(Color.secondary)
                }
            }
        }
    }
    
    
    // MARK: Bottom Row
    
    private func summaryCard(_ s: DashboardSnapshot) -> some View {
        
        let digest = s.digest
        let points = digest.map { AnalyticsManager.structuredSummaryPoints(from: $0.summary, maxPoints: 4) } ?? []
        let focus = digest?.tomorrowFocus.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let topics = digest?.topics.prefix(4).joined(separator: " · ") ?? ""
        
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("今日总结")
                    .font(.system(size: 14, weight: .semibold))
                if let digest {
                    Text("\(Self.timeString(digest.generatedAt)) 更新")
                        .font(.system(size: 11))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                if self.analytics.isSummarizingDigest {
                    ProgressView()
                        .controlSize(.small)
                }
                QuietButton(title: digest == nil ? "生成" : "刷新", systemImage: nil, palette: self.palette) {
                    Task { await self.analytics.refreshDailyDigest(force: true) }
                }
                .disabled(self.analytics.isSummarizingDigest)
            }
            
            if let error = self.analytics.digestErrorMessage, !error.isEmpty {
                Text(error)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
            }
            
            if points.isEmpty && focus.isEmpty {
                Text("还没有今天的总结")
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(points.enumerated()), id: \.offset) { _, point in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Circle()
                                .fill(Color.secondary.opacity(0.6))
                                .frame(width: 4, height: 4)
                                .alignmentGuide(.firstTextBaseline) { $0[.bottom] + 4 }
                            Text(point)
                                .font(.system(size: 13))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                
                if !focus.isEmpty {
                    Rectangle()
                        .fill(self.palette.hairline)
                        .frame(height: 1)
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text("明日优先")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                        Text(focus)
                            .font(.system(size: 13, weight: .medium))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                
                if !topics.isEmpty {
                    Text(topics)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .modifier(DashCard(palette: self.palette, padding: self.cardPadding))
    }
    
    
    private func rhythmCard(_ s: DashboardSnapshot) -> some View {
        
        let peak = s.rhythm.max(by: { $0.averageChars < $1.averageChars })
        let hasPeak = (peak?.averageChars ?? 0) > 0
        
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("星期节奏")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Text(hasPeak ? "\(peak?.label ?? "") 最高" : "近 90 天")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            
            Chart(s.rhythm) { point in
                BarMark(
                    x: .value("星期", String(point.label.suffix(1))),
                    y: .value("日均", point.averageChars),
                    width: .ratio(0.56)
                )
                .foregroundStyle(hasPeak && point.weekdayIndex == peak?.weekdayIndex ? self.palette.accent : self.palette.neutralMark)
                .cornerRadius(3)
            }
            .chartXAxis {
                AxisMarks { _ in
                    AxisValueLabel()
                        .font(.system(size: 10))
                        .foregroundStyle(Color.secondary)
                }
            }
            .chartYAxis(.hidden)
            .frame(height: 96)
            
            if !s.reminders.isEmpty {
                Rectangle().fill(self.palette.hairline).frame(height: 1)
                VStack(alignment: .leading, spacing: 4) {
                    Text("近期提醒")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    ForEach(s.reminders) { reminder in
                        ReminderRow(reminder: reminder, palette: self.palette) {
                            self.analytics.toggleReminderCompleted(id: reminder.id)
                        }
                    }
                }
            } else if !s.detectedTodos.isEmpty {
                Rectangle().fill(self.palette.hairline).frame(height: 1)
                VStack(alignment: .leading, spacing: 6) {
                    Text("笔记里的待办")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    ForEach(s.detectedTodos) { todo in
                        HStack(spacing: 8) {
                            Text(todo.text)
                                .font(.system(size: 12))
                                .lineLimit(1)
                            Spacer(minLength: 4)
                            Button("加入提醒") {
                                _ = self.analytics.addReminder(
                                    title: todo.text,
                                    dueDate: todo.suggestedForTomorrow ? AnalyticsManager.tomorrowDate() : Date()
                                )
                            }
                            .buttonStyle(.plain)
                            .font(.system(size: 11))
                            .foregroundStyle(self.palette.accent)
                            .pointerStyle(.link)
                        }
                    }
                }
            }
        }
        .modifier(DashCard(palette: self.palette, padding: self.cardPadding))
    }
    
    
    // MARK: Day Detail Overlay
    
    private func openDetail(_ cell: HeatmapDayCell) {
        
        let detail = self.analytics.dayDetail(for: cell)
        withAnimation(DashMotion.standard) {
            self.selectedDetail = detail
        }
    }
    
    
    private func closeDetail() {
        
        withAnimation(DashMotion.standard) {
            self.selectedDetail = nil
        }
    }
    
    
    private func stepDetail(by delta: Int) {
        
        guard let current = self.selectedDetail,
              let cells = self.snapshot?.orderedCells,
              let index = cells.firstIndex(where: { $0.dateKey == current.cell.dateKey }),
              cells.indices.contains(index + delta)
        else { return }
        self.selectedDetail = self.analytics.dayDetail(for: cells[index + delta])
    }
    
    
    private func detailOverlay(_ detail: HeatmapDayDetail) -> some View {
        
        let cells = self.snapshot?.orderedCells ?? []
        let index = cells.firstIndex(where: { $0.dateKey == detail.cell.dateKey })
        
        return ZStack {
            Color.black.opacity(self.palette.isDark ? 0.36 : 0.14)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { self.closeDetail() }
            
            DayDetailCard(
                detail: detail,
                palette: self.palette,
                canGoBack: (index ?? 0) > 0,
                canGoForward: index.map { $0 < cells.count - 1 } ?? false,
                onBack: { self.stepDetail(by: -1) },
                onForward: { self.stepDetail(by: 1) },
                onClose: { self.closeDetail() }
            )
            .frame(maxWidth: self.compact ? 500 : 540)
            .padding(24)
            .transition(.opacity.combined(with: .scale(scale: 0.98)))
        }
    }
    
    
    // MARK: Formatting
    
    fileprivate static func int(_ value: Int) -> String {
        
        value.formatted(.number.grouping(.automatic))
    }
    
    
    private static func compactChars(_ value: Int) -> String {
        
        value >= 10_000
            ? String(format: "%.1f 万字", Double(value) / 10_000)
            : "\(Self.int(value)) 字"
    }
    
    
    private static func todayTitle() -> String {
        
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M 月 d 日 EEEE"
        return formatter.string(from: Date())
    }
    
    
    private static func timeString(_ date: Date) -> String {
        
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}


// MARK: - Building Blocks

/// Card surface with an optional hover step and a hairline that strengthens when selected.
private struct DashCard: ViewModifier {
    
    var palette: DashPalette
    var padding: CGFloat
    var isHighlighted = false
    var isHovered = false
    
    
    func body(content: Content) -> some View {
        
        content
            .padding(self.padding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(self.palette.card)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(self.palette.hover)
                            .opacity(self.isHovered ? 1 : 0)
                    )
            }
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(self.isHighlighted ? self.palette.hairlineStrong : self.palette.hairline, lineWidth: 1)
            )
    }
}


/// A figure card: label, number, and what the number compares to. Clicking opens its detail panel.
private struct KPICard: View {
    
    let title: String
    let value: String
    let unit: String
    let note: String
    let noteColor: Color
    let isExpanded: Bool
    let compact: Bool
    let padding: CGFloat
    let palette: DashPalette
    let action: () -> Void
    
    @State private var isHovered = false
    
    
    var body: some View {
        
        Button(action: self.action) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text(self.title)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(self.isExpanded || self.isHovered ? Color.primary.opacity(0.7) : Color.secondary.opacity(0.6))
                        .rotationEffect(.degrees(self.isExpanded ? 180 : 0))
                }
                
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(self.value)
                        .font(.system(size: self.compact ? 24 : 28, weight: .semibold))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text(self.unit)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                
                Text(self.note)
                    .font(.system(size: 11.5))
                    .monospacedDigit()
                    .foregroundStyle(self.noteColor)
                    .lineLimit(1)
            }
            .modifier(DashCard(palette: self.palette, padding: self.padding, isHighlighted: self.isExpanded, isHovered: self.isHovered))
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(PressStyle())
        .onHover { hovering in
            withAnimation(DashMotion.quick) {
                self.isHovered = hovering
            }
        }
    }
}


/// Tiny press feedback, no bounce.
private struct PressStyle: ButtonStyle {
    
    func makeBody(configuration: Configuration) -> some View {
        
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.99 : 1)
            .animation(DashMotion.quick, value: configuration.isPressed)
    }
}


/// Quiet bordered text button used for secondary actions.
private struct QuietButton: View {
    
    let title: String
    let systemImage: String?
    let palette: DashPalette
    let action: () -> Void
    
    @State private var isHovered = false
    
    
    var body: some View {
        
        Button(action: self.action) {
            HStack(spacing: 4) {
                if let systemImage = self.systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 10, weight: .semibold))
                }
                Text(self.title)
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(self.isHovered ? Color.primary : Color.secondary)
            .padding(.horizontal, 10)
            .frame(height: 24)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(self.isHovered ? self.palette.inset : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(self.palette.hairline, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .onHover { hovering in
            withAnimation(DashMotion.quick) {
                self.isHovered = hovering
            }
        }
    }
}


/// Round icon button; the close variant turns a quarter and warms to red on hover.
private struct IconButton: View {
    
    let systemImage: String
    let palette: DashPalette
    var isClose = false
    let action: () -> Void
    
    @State private var isHovered = false
    
    
    var body: some View {
        
        Button(action: self.action) {
            Image(systemName: self.systemImage)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(self.isHovered ? (self.isClose ? Color.red : Color.primary) : Color.secondary)
                .rotationEffect(.degrees(self.isClose && self.isHovered ? 90 : 0))
                .frame(width: 24, height: 24)
                .background(
                    Circle().fill(
                        self.isHovered
                            ? (self.isClose ? Color.red.opacity(0.10) : self.palette.inset)
                            : Color.clear
                    )
                )
                .contentShape(Circle())
        }
        .buttonStyle(PressStyle())
        .onHover { hovering in
            withAnimation(DashMotion.standard) {
                self.isHovered = hovering
            }
        }
    }
}


/// Label/value rows separated by hairlines.
private struct StatTable: View {
    
    let rows: [(String, String)]
    let palette: DashPalette
    
    
    var body: some View {
        
        VStack(spacing: 0) {
            ForEach(Array(self.rows.enumerated()), id: \.offset) { index, row in
                HStack {
                    Text(row.0)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    Text(row.1)
                        .font(.system(size: 13, weight: .medium))
                        .monospacedDigit()
                }
                .frame(height: 32)
                
                if index < self.rows.count - 1 {
                    Rectangle().fill(self.palette.hairline).frame(height: 1)
                }
            }
        }
    }
}


/// Ranked list: name, share, metric. No bars.
private struct RankTable: View {
    
    let title: String
    let rows: [(String, String, String)]
    let palette: DashPalette
    
    
    var body: some View {
        
        VStack(alignment: .leading, spacing: 0) {
            Text(self.title)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .padding(.bottom, 4)
            
            if self.rows.isEmpty {
                Text("暂无记录")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(height: 32)
            } else {
                ForEach(Array(self.rows.enumerated()), id: \.offset) { index, row in
                    HStack(spacing: 8) {
                        Text(row.0)
                            .font(.system(size: 12.5))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer(minLength: 8)
                        Text(row.1)
                            .font(.system(size: 12))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 40, alignment: .trailing)
                        Text(row.2)
                            .font(.system(size: 12.5, weight: .medium))
                            .monospacedDigit()
                            .frame(width: 64, alignment: .trailing)
                    }
                    .frame(height: 32)
                    
                    if index < self.rows.count - 1 {
                        Rectangle().fill(self.palette.hairline).frame(height: 1)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}


private struct LegendSwatch: View {
    
    let color: Color
    let label: String
    
    
    var body: some View {
        
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(self.color)
                .frame(width: 8, height: 8)
            Text(self.label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }
}


private struct ReminderRow: View {
    
    let reminder: UserReminder
    let palette: DashPalette
    let toggle: () -> Void
    
    @State private var isHovered = false
    
    
    var body: some View {
        
        Button(action: self.toggle) {
            HStack(spacing: 8) {
                Image(systemName: self.reminder.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 12))
                    .foregroundStyle(self.reminder.isCompleted ? self.palette.accent : Color.secondary)
                Text(self.reminder.title)
                    .font(.system(size: 12))
                    .foregroundStyle(self.reminder.isCompleted ? Color.secondary : Color.primary)
                    .strikethrough(self.reminder.isCompleted, color: .secondary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if self.reminder.priority == .high {
                    Text("重要")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 6)
            .frame(height: 28)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(self.isHovered ? self.palette.inset : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, -6)
        .onHover { hovering in
            withAnimation(DashMotion.quick) {
                self.isHovered = hovering
            }
        }
    }
}


// MARK: - Heatmap

/// The year's writing drawn in a single `Canvas`; hover and click are hit-tested, so only this card redraws on hover.
private struct HeatmapCard: View {
    
    let heatmap: YearlyHeatmapData
    let longestStreak: Int
    let canGoBack: Bool
    let canGoForward: Bool
    let selectedKey: String?
    let palette: DashPalette
    let compact: Bool
    let padding: CGFloat
    let onPreviousYear: () -> Void
    let onNextYear: () -> Void
    let onSelect: (HeatmapDayCell) -> Void
    
    @State private var hovered: HeatmapDayCell?
    @State private var width: CGFloat = 0
    
    
    private struct Layout {
        
        var gridX: CGFloat
        var gridY: CGFloat
        var cell: CGFloat
        var gap: CGFloat
        var radius: CGFloat
        var height: CGFloat
        
        var pitch: CGFloat { self.cell + self.gap }
    }
    
    
    private func layout(for width: CGFloat) -> Layout {
        
        let labelColumn: CGFloat = 16
        let labelGap: CGFloat = 6
        let monthBand: CGFloat = 16
        let weeks = CGFloat(max(1, self.heatmap.weeks.count))
        let gridWidth = max(200, width - labelColumn - labelGap)
        let gap: CGFloat = gridWidth > 760 ? 3 : 2
        let raw = (gridWidth - gap * (weeks - 1)) / weeks
        let cell = max(6, min(15, (raw * 2).rounded(.down) / 2))
        
        return Layout(
            gridX: labelColumn + labelGap,
            gridY: monthBand,
            cell: cell,
            gap: gap,
            radius: max(1.5, min(3, cell * 0.22)),
            height: monthBand + cell * 7 + gap * 6
        )
    }
    
    
    private func cell(at point: CGPoint, layout: Layout) -> HeatmapDayCell? {
        
        let x = point.x - layout.gridX
        let y = point.y - layout.gridY
        guard x >= 0, y >= 0 else { return nil }
        let week = Int(x / layout.pitch)
        let row = Int(y / layout.pitch)
        guard x - CGFloat(week) * layout.pitch <= layout.cell,
              y - CGFloat(row) * layout.pitch <= layout.cell,
              self.heatmap.weeks.indices.contains(week),
              self.heatmap.weeks[week].indices.contains(row)
        else { return nil }
        let cell = self.heatmap.weeks[week][row]
        return cell.isOutOfYear ? nil : cell
    }
    
    
    var body: some View {
        
        let layout = self.layout(for: self.width > 0 ? self.width : (self.compact ? 660 : 960))
        
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("\(String(self.heatmap.year)) 年写作")
                    .font(.system(size: 14, weight: .semibold))
                
                Spacer(minLength: 8)
                
                Text(self.statusLine)
                    .font(.system(size: 12))
                    .monospacedDigit()
                    .foregroundStyle(self.hovered == nil ? Color.secondary : Color.primary)
                    .lineLimit(1)
                
                HStack(spacing: 0) {
                    YearStepButton(systemImage: "chevron.left", isEnabled: self.canGoBack, palette: self.palette, action: self.onPreviousYear)
                    YearStepButton(systemImage: "chevron.right", isEnabled: self.canGoForward, palette: self.palette, action: self.onNextYear)
                }
            }
            
            Canvas { context, _ in
                self.draw(in: &context, layout: layout)
            }
            .frame(height: layout.height)
            .frame(maxWidth: .infinity, alignment: .leading)
            .onContinuousHover { phase in
                switch phase {
                    case .active(let point):
                        let target = self.cell(at: point, layout: layout).flatMap { $0.isFuture ? nil : $0 }
                        if target?.id != self.hovered?.id {
                            self.hovered = target
                        }
                    case .ended:
                        if self.hovered != nil {
                            self.hovered = nil
                        }
                }
            }
            .onTapGesture { point in
                if let target = self.cell(at: point, layout: layout), !target.isFuture {
                    self.onSelect(target)
                }
            }
            .pointerStyle(self.hovered == nil ? nil : .link)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { newWidth in
                if abs(newWidth - self.width) > 0.5 {
                    self.width = newWidth
                }
            }
            
            HStack(spacing: 4) {
                Text("点击日期查看当天")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("少")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                ForEach(0..<5, id: \.self) { level in
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(self.palette.heat(level))
                        .frame(width: 10, height: 10)
                }
                Text("多")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
        .modifier(DashCard(palette: self.palette, padding: self.padding))
    }
    
    
    private var statusLine: String {
        
        if let cell = self.hovered {
            return "\(Self.shortDate(cell.date)) · 输入 \(AnalyticsDashboardView.int(cell.typedChars)) 字 · 补全 \(AnalyticsDashboardView.int(cell.aiCompletedChars)) 字 · AI \(cell.aiRequests) 次"
        }
        return "\(self.heatmap.activeDays) 个活跃日 · 最长连续 \(self.longestStreak) 天"
    }
    
    
    private func draw(in context: inout GraphicsContext, layout: Layout) {
        
        let labelColor = Color.secondary
        
        for label in self.heatmap.monthLabels {
            let text = context.resolve(Text("\(label.month)月").font(.system(size: 10)).foregroundStyle(labelColor))
            context.draw(text, at: CGPoint(x: layout.gridX + CGFloat(label.weekIndex) * layout.pitch, y: 0), anchor: .topLeading)
        }
        
        for (row, name) in [(0, "一"), (2, "三"), (4, "五")] {
            let text = context.resolve(Text(name).font(.system(size: 9.5)).foregroundStyle(labelColor))
            let y = layout.gridY + CGFloat(row) * layout.pitch + layout.cell / 2
            context.draw(text, at: CGPoint(x: 0, y: y), anchor: .leading)
        }
        
        var hoveredRect: CGRect?
        var selectedRect: CGRect?
        
        for (week, days) in self.heatmap.weeks.enumerated() {
            for (row, cell) in days.enumerated() where !cell.isOutOfYear {
                let rect = CGRect(
                    x: layout.gridX + CGFloat(week) * layout.pitch,
                    y: layout.gridY + CGFloat(row) * layout.pitch,
                    width: layout.cell,
                    height: layout.cell
                )
                let color = cell.isFuture ? self.palette.futureCell : self.palette.heat(cell.level)
                context.fill(Path(roundedRect: rect, cornerRadius: layout.radius, style: .continuous), with: .color(color))
                
                if cell.id == self.hovered?.id { hoveredRect = rect }
                if cell.dateKey == self.selectedKey { selectedRect = rect }
            }
        }
        
        if let rect = hoveredRect {
            context.stroke(
                Path(roundedRect: rect.insetBy(dx: -1, dy: -1), cornerRadius: layout.radius + 1, style: .continuous),
                with: .color(Color.primary.opacity(0.55)),
                lineWidth: 1
            )
        }
        if let rect = selectedRect {
            context.stroke(
                Path(roundedRect: rect.insetBy(dx: -1.5, dy: -1.5), cornerRadius: layout.radius + 1.5, style: .continuous),
                with: .color(Color.primary.opacity(0.85)),
                lineWidth: 1.5
            )
        }
    }
    
    
    private static func shortDate(_ date: Date) -> String {
        
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日 EEE"
        return formatter.string(from: date)
    }
}


private struct YearStepButton: View {
    
    let systemImage: String
    let isEnabled: Bool
    let palette: DashPalette
    let action: () -> Void
    
    @State private var isHovered = false
    
    
    var body: some View {
        
        Button(action: self.action) {
            Image(systemName: self.systemImage)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(self.isHovered ? Color.primary : Color.secondary)
                .frame(width: 24, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(self.isHovered ? self.palette.inset : Color.clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!self.isEnabled)
        .opacity(self.isEnabled ? 1 : 0.3)
        .onHover { hovering in
            withAnimation(DashMotion.quick) {
                self.isHovered = hovering && self.isEnabled
            }
        }
    }
}


// MARK: - Day Detail Card

private struct DayDetailCard: View {
    
    let detail: HeatmapDayDetail
    let palette: DashPalette
    let canGoBack: Bool
    let canGoForward: Bool
    let onBack: () -> Void
    let onForward: () -> Void
    let onClose: () -> Void
    
    
    var body: some View {
        
        let cell = self.detail.cell
        
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(Self.fullDate(cell.date))
                        .font(.system(size: 16, weight: .semibold))
                    HStack(spacing: 3) {
                        ForEach(1...4, id: \.self) { level in
                            RoundedRectangle(cornerRadius: 2, style: .continuous)
                                .fill(level <= cell.level ? self.palette.heat(level) : self.palette.heat(0))
                                .frame(width: 10, height: 10)
                        }
                        Text(cell.level == 0 ? "没有记录" : "活跃度 \(cell.level) / 4")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .padding(.leading, 6)
                    }
                }
                
                Spacer()
                
                IconButton(systemImage: "chevron.left", palette: self.palette, action: self.onBack)
                    .disabled(!self.canGoBack)
                    .opacity(self.canGoBack ? 1 : 0.3)
                    .help("前一天")
                IconButton(systemImage: "chevron.right", palette: self.palette, action: self.onForward)
                    .disabled(!self.canGoForward)
                    .opacity(self.canGoForward ? 1 : 0.3)
                    .help("后一天")
                IconButton(systemImage: "xmark", palette: self.palette, isClose: true, action: self.onClose)
                    .help("关闭 (Esc)")
            }
            
            Grid(horizontalSpacing: 8, verticalSpacing: 8) {
                GridRow {
                    self.figure("手动输入", AnalyticsDashboardView.int(cell.typedChars), "字")
                    self.figure("AI 补全", AnalyticsDashboardView.int(cell.aiCompletedChars), "字")
                    self.figure("AI 调用", "\(cell.aiRequests)", "次")
                }
                GridRow {
                    self.figure("Tokens", AnalyticsManager.formatCompactTokenCount(cell.totalTokens), "")
                    self.figure("新建 / 保存", "\(cell.filesCreated) / \(cell.documentsSaved)", "")
                    self.figure("采纳 / 本地命中", "\(cell.aiCompletionAccepts) / \(cell.localHits)", "")
                }
            }
            
            if !self.detail.models.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text("模型")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        Spacer()
                        if self.detail.averageLatencyMs > 0 {
                            Text("平均 \(self.detail.averageLatencyMs) ms")
                                .font(.system(size: 11))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.bottom, 4)
                    ForEach(Array(self.detail.models.prefix(3).enumerated()), id: \.offset) { index, model in
                        HStack {
                            Text(model.model)
                                .font(.system(size: 12.5))
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            Text("\(model.requests) 次 · \(AnalyticsManager.formatCompactTokenCount(model.totalTokens))")
                                .font(.system(size: 12))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                        .frame(height: 28)
                        if index < min(3, self.detail.models.count) - 1 {
                            Rectangle().fill(self.palette.hairline).frame(height: 1)
                        }
                    }
                }
            }
            
            let titles = self.detail.documents.map(\.title) + self.detail.weeklyReports.map(\.title)
            if !titles.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("相关文档")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    ForEach(Array(titles.prefix(5).enumerated()), id: \.offset) { _, title in
                        Text(title)
                            .font(.system(size: 12.5))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            }
            
            if let digest = self.detail.digest {
                let points = AnalyticsManager.structuredSummaryPoints(from: digest.summary, maxPoints: 3)
                if !points.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("当天总结")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        ForEach(Array(points.enumerated()), id: \.offset) { _, point in
                            Text(point)
                                .font(.system(size: 12.5))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(self.palette.modal)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(self.palette.hairline, lineWidth: 1)
        )
        .shadow(color: .black.opacity(self.palette.isDark ? 0.4 : 0.12), radius: 24, y: 8)
    }
    
    
    private func figure(_ label: String, _ value: String, _ unit: String) -> some View {
        
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.system(size: 17, weight: .semibold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                if !unit.isEmpty {
                    Text(unit)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(self.palette.inset))
    }
    
    
    private static func fullDate(_ date: Date) -> String {
        
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy 年 M 月 d 日 EEEE"
        return formatter.string(from: date)
    }
}
