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

private enum DashMotion {
    
    static let quick = Animation.timingCurve(0.2, 0, 0, 1, duration: 0.14)
    static let standard = Animation.timingCurve(0.2, 0, 0, 1, duration: 0.24)
    static let spring = Animation.spring(response: 0.34, dampingFraction: 0.84)
    static let enter = Animation.timingCurve(0.2, 0, 0, 1, duration: 0.32)
}


/// Frosted sage-mint & deep forest-pine Bento palette (paired with an atmospheric dark counterpart).
private struct DashPalette {
    
    let isDark: Bool
    
    init(_ scheme: ColorScheme) {
        
        self.isDark = (scheme == .dark)
    }
    
    var canvasTop: Color {
        self.isDark
            ? Color(red: 0.067, green: 0.086, blue: 0.082)
            : Color(red: 0.945, green: 0.965, blue: 0.955)
    }
    var canvasBottom: Color {
        self.isDark
            ? Color(red: 0.075, green: 0.094, blue: 0.090)
            : Color(red: 0.969, green: 0.980, blue: 0.974)
    }
    var mistMint: Color {
        self.isDark
            ? Color(red: 0.14, green: 0.42, blue: 0.30).opacity(0.22)
            : Color(red: 0.72, green: 0.89, blue: 0.79).opacity(0.42)
    }
    var mistWarm: Color {
        self.isDark
            ? Color(red: 0.48, green: 0.38, blue: 0.22).opacity(0.10)
            : Color(red: 0.98, green: 0.92, blue: 0.76).opacity(0.45)
    }
    
    var card: Color {
        self.isDark
            ? Color(red: 0.102, green: 0.129, blue: 0.122)
            : Color.white.opacity(0.95)
    }
    var cardShadow: Color {
        self.isDark
            ? Color.black.opacity(0.26)
            : Color(red: 0.06, green: 0.18, blue: 0.14).opacity(0.055)
    }
    var inset: Color {
        self.isDark
            ? Color.white.opacity(0.048)
            : Color(red: 0.953, green: 0.969, blue: 0.961)
    }
    var insetHover: Color {
        self.isDark
            ? Color.white.opacity(0.075)
            : Color(red: 0.925, green: 0.953, blue: 0.941)
    }
    var hairline: Color {
        self.isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.055)
    }
    var hairlineStrong: Color {
        self.isDark ? self.emerald.opacity(0.55) : self.pine.opacity(0.32)
    }
    
    var pine: Color {
        self.isDark
            ? Color(red: 0.43, green: 0.91, blue: 0.72)
            : Color(red: 0.059, green: 0.180, blue: 0.153)
    }
    var emerald: Color {
        self.isDark
            ? Color(red: 0.20, green: 0.83, blue: 0.60)
            : Color(red: 0.176, green: 0.541, blue: 0.384)
    }
    var mint: Color {
        self.isDark
            ? Color(red: 0.12, green: 0.54, blue: 0.38)
            : Color(red: 0.388, green: 0.725, blue: 0.557)
    }
    var paleMint: Color {
        self.isDark
            ? Color(red: 0.11, green: 0.32, blue: 0.24)
            : Color(red: 0.710, green: 0.875, blue: 0.780)
    }
    var emptyDot: Color {
        self.isDark
            ? Color.white.opacity(0.075)
            : Color(red: 0.898, green: 0.933, blue: 0.914)
    }
    var coral: Color {
        self.isDark
            ? Color(red: 0.97, green: 0.44, blue: 0.44)
            : Color(red: 0.878, green: 0.424, blue: 0.424)
    }
    var positivePillBg: Color {
        self.isDark
            ? Color(red: 0.18, green: 0.58, blue: 0.42).opacity(0.24)
            : Color(red: 0.86, green: 0.95, blue: 0.90)
    }
    var negativePillBg: Color {
        self.isDark
            ? Color(red: 0.90, green: 0.35, blue: 0.35).opacity(0.20)
            : Color(red: 0.98, green: 0.90, blue: 0.90)
    }
    var neutralPillBg: Color {
        self.isDark ? Color.white.opacity(0.07) : Color.black.opacity(0.045)
    }
    
    
    func heat(_ level: Int) -> Color {
        
        if self.isDark {
            switch level {
                case 4: Color(red: 0.43, green: 0.91, blue: 0.72)
                case 3: Color(red: 0.20, green: 0.72, blue: 0.52)
                case 2: Color(red: 0.13, green: 0.48, blue: 0.35)
                case 1: Color(red: 0.10, green: 0.29, blue: 0.22)
                default: self.emptyDot
            }
        } else {
            switch level {
                case 4: Color(red: 0.059, green: 0.180, blue: 0.153)
                case 3: Color(red: 0.176, green: 0.541, blue: 0.384)
                case 2: Color(red: 0.388, green: 0.725, blue: 0.557)
                case 1: Color(red: 0.710, green: 0.875, blue: 0.780)
                default: self.emptyDot
            }
        }
    }
    
    
    func matrixStep(fraction: Double, isPeak: Bool) -> Color {
        
        if isPeak { return self.pine }
        if fraction >= 0.75 { return self.emerald }
        if fraction >= 0.40 { return self.mint }
        return self.paleMint
    }
}


// MARK: - Precomputed Snapshot

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
    var rollingHeatmap: RollingHeatmapData
    var orderedCells: [HeatmapDayCell]
    var aiToday: AISlice
    var ai30: AISlice
    var reminders: [UserReminder]
    var detectedTodos: [DetectedNoteTodo]
    
    
    @MainActor static func build(analytics: AnalyticsManager, heatmapWeeks: Int) -> DashboardSnapshot {
        
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
        
        let heatmap = analytics.rollingHeatmap(weeks: heatmapWeeks)
        let ordered = analytics.orderedVisibleCells(in: heatmap)
        let reminders = Array((analytics.overdueReminders + analytics.todayReminders + analytics.tomorrowReminders).prefix(4))
        
        return DashboardSnapshot(
            today: today,
            typedBaseline7: baseline,
            days14: chartDays,
            days7: Array(chartDays.suffix(7)),
            series7: series7,
            rollingHeatmap: heatmap,
            orderedCells: ordered,
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
            reminders: reminders,
            detectedTodos: reminders.isEmpty ? analytics.detectedNoteTodos(limit: 3) : []
        )
    }
}


// MARK: - Dashboard

/// Frosted sage-mint Bento writing dashboard with centered profile, rolling heatmap, and heatmap-linked daily stories.
struct AnalyticsDashboardView: View {
    
    fileprivate enum KPIKind: String, Identifiable {
        
        case typed
        case completion
        case consumption
        
        var id: String { self.rawValue }
    }
    
    fileprivate enum AIRange: String, CaseIterable, Identifiable {
        
        case today = "今日"
        case thirtyDays = "近 30 天"
        
        var id: String { self.rawValue }
    }
    
    fileprivate enum HeatmapRange: String, CaseIterable, Identifiable {
        
        case halfYear = "近半年"
        case oneYear = "近一年"
        
        var id: String { self.rawValue }
        var weeks: Int { self == .halfYear ? 26 : 52 }
    }
    
    let isEmbeddedInSettings: Bool
    var onDismiss: (() -> Void)?
    
    @Environment(\.colorScheme) private var colorScheme
    
    @State private var analytics = AnalyticsManager.shared
    @State private var profileManager = UserProfileManager.shared
    @State private var snapshot: DashboardSnapshot?
    @State private var expandedKPI: KPIKind?
    @State private var aiRange: AIRange = .thirtyDays
    @State private var heatmapRange: HeatmapRange = .halfYear
    @State private var selectedDateKey: String = AnalyticsManager.dateKey()
    @State private var hasAppeared = false
    
    
    init(isEmbeddedInSettings: Bool, onDismiss: (() -> Void)? = nil) {
        
        self.isEmbeddedInSettings = isEmbeddedInSettings
        self.onDismiss = onDismiss
    }
    
    
    private var palette: DashPalette { DashPalette(self.colorScheme) }
    private var compact: Bool { self.isEmbeddedInSettings }
    private var outerPadding: CGFloat { self.compact ? 16 : 24 }
    private var gap: CGFloat { self.compact ? 12 : 16 }
    private var cardPadding: CGFloat { self.compact ? 15 : 20 }
    private var cornerRadius: CGFloat { self.compact ? 16 : 20 }
    
    
    var body: some View {
        
        ZStack {
            self.ambientBackground
                .ignoresSafeArea()
            
            ScrollView {
                Group {
                    if let snapshot = self.snapshot {
                        self.content(snapshot)
                            .opacity(self.hasAppeared ? 1 : 0)
                            .offset(y: self.hasAppeared ? 0 : 8)
                    } else {
                        Color.clear.frame(height: 480)
                    }
                }
                .padding(self.outerPadding)
                .frame(maxWidth: 1080, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .onAppear {
            self.analytics.flushPendingStats()
            self.analytics.reloadFromDatabase()
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
        .onChange(of: self.heatmapRange) { _, _ in
            self.rebuild()
        }
        .onKeyPress(.escape) {
            if self.expandedKPI != nil {
                withAnimation(DashMotion.standard) {
                    self.expandedKPI = nil
                }
                return .handled
            }
            return .ignored
        }
    }
    
    
    private var ambientBackground: some View {
        
        ZStack {
            LinearGradient(
                colors: [self.palette.canvasTop, self.palette.canvasBottom],
                startPoint: .top,
                endPoint: .bottom
            )
            
            GeometryReader { proxy in
                RadialGradient(
                    colors: [self.palette.mistMint, .clear],
                    center: .topLeading,
                    startRadius: 20,
                    endRadius: max(360, proxy.size.width * 0.58)
                )
                RadialGradient(
                    colors: [self.palette.mistWarm, .clear],
                    center: .top,
                    startRadius: 10,
                    endRadius: max(300, proxy.size.width * 0.45)
                )
                RadialGradient(
                    colors: [self.palette.mistMint.opacity(0.65), .clear],
                    center: .topTrailing,
                    startRadius: 20,
                    endRadius: max(340, proxy.size.width * 0.5)
                )
            }
        }
    }
    
    
    private func rebuild() {
        
        let built = DashboardSnapshot.build(analytics: self.analytics, heatmapWeeks: self.heatmapRange.weeks)
        self.snapshot = built
        if self.analytics.cell(forDateKey: self.selectedDateKey, in: built.rollingHeatmap) == nil {
            self.selectedDateKey = built.today.dateKey
        }
    }
    
    
    // MARK: Layout
    
    private func content(_ s: DashboardSnapshot) -> some View {
        
        let activeCell = self.resolvedSelectedCell(in: s)
        let story = self.analytics.humanDayStory(for: activeCell, baselineDailyChars: s.typedBaseline7)
        
        return VStack(alignment: .leading, spacing: self.gap) {
            self.header
                .padding(.bottom, self.compact ? 2 : 6)
            
            self.kpiRow(s)
            
            if let kind = self.expandedKPI {
                self.detailPanel(kind, s)
                    .id(kind)
                    .transition(.opacity.combined(with: .scale(scale: 0.985, anchor: .top)))
            }
            
            RollingHeatmapCard(
                heatmap: s.rollingHeatmap,
                selectedKey: activeCell.dateKey,
                range: self.$heatmapRange,
                palette: self.palette,
                compact: self.compact,
                padding: self.cardPadding,
                cornerRadius: self.cornerRadius
            ) { tappedCell in
                withAnimation(DashMotion.spring) {
                    self.selectedDateKey = tappedCell.dateKey
                }
            }
            
            self.dailyStoryCard(story, snapshot: s)
                .id(story.dateKey)
                .transition(.opacity)
        }
    }
    
    
    private func resolvedSelectedCell(in s: DashboardSnapshot) -> HeatmapDayCell {
        
        if let matched = self.analytics.cell(forDateKey: self.selectedDateKey, in: s.rollingHeatmap) {
            return matched
        }
        if let todayCell = self.analytics.cell(forDateKey: s.today.dateKey, in: s.rollingHeatmap) {
            return todayCell
        }
        return s.orderedCells.last ?? HeatmapDayCell(
            dateKey: s.today.dateKey,
            date: Date(),
            typedChars: s.today.typedChars,
            aiCompletedChars: s.today.aiCompletedChars,
            aiCompletionAccepts: s.today.aiCompletionAccepts,
            filesCreated: s.today.filesCreated,
            documentsSaved: s.today.documentsSaved,
            aiRequests: s.today.aiRequests,
            inputTokens: s.today.inputTokens,
            outputTokens: s.today.outputTokens,
            localHits: s.today.localHits,
            level: 0,
            isFuture: false
        )
    }
    
    
    // MARK: Header (Centered Identity + Left Back Pill)
    
    private var header: some View {
        
        let profile = self.profileManager.activeProfile
        
        return ZStack(alignment: .topLeading) {
            VStack(spacing: self.compact ? 6 : 8) {
                UserAvatarCircleView(profile: profile, size: self.compact ? 42 : 52)
                    .padding(3)
                    .background(
                        Circle()
                            .fill(self.palette.card)
                            .shadow(color: self.palette.cardShadow, radius: 10, y: 4)
                    )
                    .overlay(
                        Circle()
                            .strokeBorder(self.palette.paleMint, lineWidth: 1.5)
                    )
                
                Text(profile.displayName)
                    .font(.system(size: self.compact ? 16 : 18, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                
                Text(Self.todayTitle())
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            
            if let onDismiss = self.onDismiss {
                BackPillButton(palette: self.palette, action: onDismiss)
                    .help("返回编辑器 (Esc)")
            }
        }
    }
    
    
    // MARK: KPI Bento Row
    
    private func kpiRow(_ s: DashboardSnapshot) -> some View {
        
        let today = s.today
        let produced = today.typedChars + today.aiCompletedChars
        let aiShare = produced > 0 ? Int((Double(today.aiCompletedChars) * 100 / Double(produced)).rounded()) : 0
        
        let typedBadge: (String, Color, Color) = {
            guard s.typedBaseline7 > 0 else { return ("刚刚开始", .secondary, self.palette.neutralPillBg) }
            let pct = Int((Double(today.typedChars - s.typedBaseline7) * 100 / Double(s.typedBaseline7)).rounded())
            if pct >= 0 {
                return ("+\(pct)%", self.palette.emerald, self.palette.positivePillBg)
            } else {
                return ("\(pct)%", self.palette.coral, self.palette.negativePillBg)
            }
        }()
        
        let completionBadge: (String, Color, Color) = today.aiCompletionAccepts > 0
            ? ("采纳 \(today.aiCompletionAccepts) 次 · \(aiShare)%", self.palette.emerald, self.palette.positivePillBg)
            : ("暂无采纳", .secondary, self.palette.neutralPillBg)
        
        let consumptionBadge: (String, Color, Color) = today.aiRequests > 0
            ? ("\(today.aiRequests) 次调用", self.palette.pine, self.palette.positivePillBg)
            : ("暂无调用", .secondary, self.palette.neutralPillBg)
        
        let typedSpark = s.days7.map { Double($0.typed) }
        let aiSpark = s.days7.map { Double($0.ai) }
        let tokenSpark = s.days7.map { Double($0.input + $0.output) }
        
        return HStack(alignment: .top, spacing: self.gap) {
            KPICard(
                title: "今日手写",
                value: Self.int(today.typedChars),
                unit: "字",
                badgeText: typedBadge.0,
                badgeTextColor: typedBadge.1,
                badgeBackground: typedBadge.2,
                sparkValues: typedSpark,
                sparkTint: .emerald,
                isExpanded: self.expandedKPI == .typed,
                compact: self.compact,
                padding: self.cardPadding,
                cornerRadius: self.cornerRadius,
                palette: self.palette
            ) { self.toggle(.typed) }
            
            KPICard(
                title: "AI 帮写",
                value: Self.int(today.aiCompletedChars),
                unit: "字",
                badgeText: completionBadge.0,
                badgeTextColor: completionBadge.1,
                badgeBackground: completionBadge.2,
                sparkValues: aiSpark,
                sparkTint: .mint,
                isExpanded: self.expandedKPI == .completion,
                compact: self.compact,
                padding: self.cardPadding,
                cornerRadius: self.cornerRadius,
                palette: self.palette
            ) { self.toggle(.completion) }
            
            KPICard(
                title: "AI 用量",
                value: AnalyticsManager.formatCompactTokenCount(today.totalTokens),
                unit: "Tokens",
                badgeText: consumptionBadge.0,
                badgeTextColor: consumptionBadge.1,
                badgeBackground: consumptionBadge.2,
                sparkValues: tokenSpark,
                sparkTint: .coralSplit,
                isExpanded: self.expandedKPI == .consumption,
                compact: self.compact,
                padding: self.cardPadding,
                cornerRadius: self.cornerRadius,
                palette: self.palette
            ) { self.toggle(.consumption) }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
    
    
    private func toggle(_ kind: KPIKind) {
        
        withAnimation(DashMotion.spring) {
            self.expandedKPI = (self.expandedKPI == kind) ? nil : kind
        }
    }
    
    
    // MARK: Expanded KPI Detail Panels
    
    @ViewBuilder
    private func detailPanel(_ kind: KPIKind, _ s: DashboardSnapshot) -> some View {
        
        VStack(alignment: .leading, spacing: 14) {
            switch kind {
                case .typed:
                    TypedDetailPanel(days: s.days14, today: s.today, compact: self.compact, palette: self.palette) {
                        withAnimation(DashMotion.standard) { self.expandedKPI = nil }
                    }
                case .completion:
                    CompletionDetailPanel(days: s.days7, series7: s.series7, today: s.today, compact: self.compact, palette: self.palette) {
                        withAnimation(DashMotion.standard) { self.expandedKPI = nil }
                    }
                case .consumption:
                    ConsumptionDetailPanel(
                        days: s.days7,
                        slice: (self.aiRange == .today) ? s.aiToday : s.ai30,
                        aiRange: self.$aiRange,
                        compact: self.compact,
                        palette: self.palette
                    ) {
                        withAnimation(DashMotion.standard) { self.expandedKPI = nil }
                    }
            }
        }
        .modifier(DashCard(palette: self.palette, padding: self.cardPadding, cornerRadius: self.cornerRadius))
    }
    
    
    // MARK: Heatmap-Linked Daily Story Card
    
    private func dailyStoryCard(_ story: DailyHumanStory, snapshot s: DashboardSnapshot) -> some View {
        
        let cells = s.orderedCells
        let index = cells.firstIndex(where: { $0.dateKey == story.dateKey })
        let canStepBack = (index ?? 0) > 0
        let canStepForward = index.map { $0 < cells.count - 1 } ?? false
        let isToday = (story.dateKey == s.today.dateKey)
        
        return VStack(alignment: .leading, spacing: self.compact ? 14 : 16) {
            // Card Header with date, mood pill, quick jump to today, and < > day stepping
            HStack(alignment: .center, spacing: 8) {
                Text(story.dateBadge)
                    .font(.system(size: self.compact ? 14 : 15, weight: .semibold))
                    .foregroundStyle(.primary)
                
                Text(story.moodTag)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(self.palette.emerald)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 3)
                    .background(self.palette.positivePillBg, in: Capsule())
                
                Spacer(minLength: 8)
                
                if !isToday {
                    Button {
                        withAnimation(DashMotion.spring) {
                            self.selectedDateKey = s.today.dateKey
                        }
                    } label: {
                        Text("回到今天")
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(self.palette.emerald)
                            .padding(.horizontal, 10)
                            .frame(height: 24)
                            .background(self.palette.positivePillBg, in: Capsule())
                    }
                    .buttonStyle(PressStyle())
                    .pointerStyle(.link)
                }
                
                HStack(spacing: 4) {
                    StepCircleButton(systemImage: "chevron.left", isEnabled: canStepBack, palette: self.palette) {
                        if let index, cells.indices.contains(index - 1) {
                            withAnimation(DashMotion.spring) {
                                self.selectedDateKey = cells[index - 1].dateKey
                            }
                        }
                    }
                    .help("前一天")
                    
                    StepCircleButton(systemImage: "chevron.right", isEnabled: canStepForward, palette: self.palette) {
                        if let index, cells.indices.contains(index + 1) {
                            withAnimation(DashMotion.spring) {
                                self.selectedDateKey = cells[index + 1].dateKey
                            }
                        }
                    }
                    .help("后一天")
                }
            }
            
            if self.compact {
                VStack(alignment: .leading, spacing: 14) {
                    self.storyNarrativeColumn(story)
                    Rectangle().fill(self.palette.hairline).frame(height: 1)
                    self.storyActivityColumn(story, snapshot: s, isToday: isToday)
                }
            } else {
                HStack(alignment: .top, spacing: 24) {
                    self.storyNarrativeColumn(story)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                    
                    Rectangle()
                        .fill(self.palette.hairline)
                        .frame(width: 1)
                    
                    self.storyActivityColumn(story, snapshot: s, isToday: isToday)
                        .frame(width: 340, alignment: .topLeading)
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .modifier(DashCard(palette: self.palette, padding: self.cardPadding, cornerRadius: self.cornerRadius))
    }
    
    
    private func storyNarrativeColumn(_ story: DailyHumanStory) -> some View {
        
        VStack(alignment: .leading, spacing: 12) {
            Text(story.headline)
                .font(.system(size: self.compact ? 14.5 : 16, weight: .medium))
                .foregroundStyle(.primary)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
            
            if !story.highlights.isEmpty {
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(Array(story.highlights.enumerated()), id: \.offset) { _, point in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Circle()
                                .fill(self.palette.emerald)
                                .frame(width: 5, height: 5)
                                .alignmentGuide(.firstTextBaseline) { $0[.bottom] + 4 }
                            Text(point)
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            
            // Tactile dot-composition meter splitting hand-typed vs AI chars
            if story.totalChars > 0 || story.savedCount > 0 {
                VStack(alignment: .leading, spacing: 7) {
                    DotCompositionBar(
                        primaryRatio: story.totalChars > 0 ? Double(story.handTypedChars) / Double(story.totalChars) : 0,
                        secondaryRatio: story.totalChars > 0 ? Double(story.aiChars) / Double(story.totalChars) : 0,
                        palette: self.palette
                    )
                    
                    HStack(spacing: 12) {
                        if story.handTypedChars > 0 {
                            HStack(spacing: 4) {
                                Circle().fill(self.palette.pine).frame(width: 6, height: 6)
                                Text("手写 \(Self.int(story.handTypedChars)) 字")
                            }
                        }
                        if story.aiChars > 0 {
                            HStack(spacing: 4) {
                                Circle().fill(self.palette.mint).frame(width: 6, height: 6)
                                Text("AI 帮补 \(Self.int(story.aiChars)) 字")
                            }
                        }
                        if story.savedCount > 0 {
                            Text("保存 \(story.savedCount) 次")
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .font(.system(size: 11.5))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                }
                .padding(11)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(self.palette.inset, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
    }
    
    
    private func storyActivityColumn(_ story: DailyHumanStory, snapshot s: DashboardSnapshot, isToday: Bool) -> some View {
        
        let entries = self.documentEntries(for: story)
        
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("这天动过的文档")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if !entries.isEmpty {
                    Text("\(entries.count) 篇")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                }
            }
            
            if entries.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "leaf")
                        .font(.system(size: 13))
                        .foregroundStyle(self.palette.mint)
                        .frame(width: 30, height: 30)
                        .background(self.palette.card, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    Text("这天没有留下文档改动记录")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(self.palette.inset, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            } else {
                VStack(spacing: 6) {
                    ForEach(entries.prefix(self.compact ? 3 : 4)) { entry in
                        TransactionDocRow(entry: entry, palette: self.palette)
                    }
                }
            }
            
            if isToday {
                if !s.reminders.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("顺手记住")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .padding(.top, 2)
                        ForEach(s.reminders.prefix(3)) { reminder in
                            ReminderRow(reminder: reminder, palette: self.palette) {
                                self.analytics.toggleReminderCompleted(id: reminder.id)
                            }
                        }
                    }
                } else if !s.detectedTodos.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("笔记里的待办")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .padding(.top, 2)
                        ForEach(s.detectedTodos.prefix(2)) { todo in
                            HStack(spacing: 8) {
                                Text(todo.text)
                                    .font(.system(size: 12))
                                    .lineLimit(1)
                                Spacer(minLength: 6)
                                Button("记下来") {
                                    _ = self.analytics.addReminder(
                                        title: todo.text,
                                        dueDate: todo.suggestedForTomorrow ? AnalyticsManager.tomorrowDate() : Date()
                                    )
                                }
                                .buttonStyle(.plain)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(self.palette.emerald)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(self.palette.positivePillBg, in: Capsule())
                                .pointerStyle(.link)
                            }
                            .padding(.horizontal, 10)
                            .frame(height: 32)
                            .background(self.palette.inset, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                    }
                }
            }
        }
    }
    
    
    private struct DocumentEntry: Identifiable {
        let id: String
        let title: String
        let subtitle: String
        let countLabel: String
        let symbolName: String
    }
    
    
    private func documentEntries(for story: DailyHumanStory) -> [DocumentEntry] {
        
        var items: [DocumentEntry] = []
        for doc in story.documents {
            let isCreatedSameDay = doc.createdAt.map { AnalyticsManager.dateKey(for: $0) == story.dateKey } ?? false
            let subtitle = isCreatedSameDay ? "这天新建" : "改过内容"
            let chars = doc.content.count
            let countLabel = chars >= 1000 ? String(format: "%.1fk 字", Double(chars) / 1000.0) : "\(chars) 字"
            items.append(DocumentEntry(
                id: "doc:\(doc.id)",
                title: doc.title,
                subtitle: subtitle,
                countLabel: countLabel,
                symbolName: isCreatedSameDay ? "doc.badge.plus" : "doc.text"
            ))
        }
        for report in story.weeklyReports {
            let chars = report.content.count
            let countLabel = chars >= 1000 ? String(format: "%.1fk 字", Double(chars) / 1000.0) : "\(chars) 字"
            items.append(DocumentEntry(
                id: "rep:\(report.id)",
                title: report.title,
                subtitle: "周报记录",
                countLabel: countLabel,
                symbolName: "calendar"
            ))
        }
        return items
    }
    
    
    private struct TransactionDocRow: View {
        
        let entry: DocumentEntry
        let palette: DashPalette
        @State private var isHovered = false
        
        var body: some View {
            HStack(spacing: 10) {
                Image(systemName: self.entry.symbolName)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(self.palette.pine)
                    .frame(width: 30, height: 30)
                    .background(self.palette.card, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .strokeBorder(self.palette.hairline, lineWidth: 0.75)
                    )
                
                VStack(alignment: .leading, spacing: 1) {
                    Text(self.entry.title)
                        .font(.system(size: 12.5, weight: .medium))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(self.entry.subtitle)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                }
                
                Spacer(minLength: 6)
                
                Text(self.entry.countLabel)
                    .font(.system(size: 11.5, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(self.palette.emerald)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(self.isHovered ? self.palette.insetHover : self.palette.inset)
            )
            .onHover { hovering in
                withAnimation(DashMotion.quick) { self.isHovered = hovering }
            }
        }
    }
    
    
    // MARK: Formatting
    
    fileprivate static func int(_ value: Int) -> String {
        
        value.formatted(.number.grouping(.automatic))
    }
    
    
    private static func todayTitle() -> String {
        
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M 月 d 日 · EEEE"
        return formatter.string(from: Date())
    }
}


// MARK: - Bento Card & Controls

private struct DashCard: ViewModifier {
    
    var palette: DashPalette
    var padding: CGFloat
    var cornerRadius: CGFloat = 20
    var isHighlighted = false
    var isHovered = false
    
    
    func body(content: Content) -> some View {
        
        content
            .padding(self.padding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background {
                RoundedRectangle(cornerRadius: self.cornerRadius, style: .continuous)
                    .fill(self.palette.card)
                    .overlay(
                        RoundedRectangle(cornerRadius: self.cornerRadius, style: .continuous)
                            .fill(self.palette.emerald.opacity(self.isHovered ? 0.025 : 0))
                    )
                    .shadow(color: self.palette.cardShadow, radius: self.isHovered ? 18 : 14, y: self.isHovered ? 7 : 5)
            }
            .overlay(
                RoundedRectangle(cornerRadius: self.cornerRadius, style: .continuous)
                    .strokeBorder(self.isHighlighted ? self.palette.hairlineStrong : self.palette.hairline, lineWidth: self.isHighlighted ? 1.25 : 1)
            )
    }
}


/// Top-left ergonomic back pill button.
private struct BackPillButton: View {
    
    let palette: DashPalette
    let action: () -> Void
    @State private var isHovered = false
    
    
    var body: some View {
        
        Button(action: self.action) {
            HStack(spacing: 5) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 11, weight: .semibold))
                    .offset(x: self.isHovered ? -2 : 0)
                Text("返回")
                    .font(.system(size: 12.5, weight: .medium))
            }
            .foregroundStyle(self.isHovered ? self.palette.pine : .secondary)
            .padding(.horizontal, 12)
            .frame(height: 30)
            .background(
                Capsule()
                    .fill(self.palette.card)
                    .shadow(color: self.palette.cardShadow, radius: 8, y: 3)
            )
            .overlay(
                Capsule()
                    .strokeBorder(self.palette.hairline, lineWidth: 1)
            )
            .contentShape(Capsule())
        }
        .buttonStyle(PressStyle())
        .pointerStyle(.link)
        .onHover { hovering in
            withAnimation(DashMotion.quick) { self.isHovered = hovering }
        }
    }
}


private enum SparkTint {
    
    case emerald
    case mint
    case coralSplit
}


/// Bento KPI card: title + delta badge + ↗ action circle + hero value + 7-day pixel-matrix sparkbar.
private struct KPICard: View {
    
    let title: String
    let value: String
    let unit: String
    let badgeText: String
    let badgeTextColor: Color
    let badgeBackground: Color
    let sparkValues: [Double]
    let sparkTint: SparkTint
    let isExpanded: Bool
    let compact: Bool
    let padding: CGFloat
    let cornerRadius: CGFloat
    let palette: DashPalette
    let action: () -> Void
    
    @State private var isHovered = false
    
    
    var body: some View {
        
        Button(action: self.action) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center, spacing: 6) {
                    Text(self.title)
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(.secondary)
                    
                    Text(self.badgeText)
                        .font(.system(size: 10.5, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(self.badgeTextColor)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(self.badgeBackground, in: Capsule())
                        .lineLimit(1)
                    
                    Spacer(minLength: 4)
                    
                    Circle()
                        .fill(self.isExpanded ? self.palette.pine : (self.isHovered ? self.palette.insetHover : self.palette.inset))
                        .frame(width: 24, height: 24)
                        .overlay(
                            Image(systemName: self.isExpanded ? "chevron.up" : "arrow.up.right")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(self.isExpanded ? Color(nsColor: .windowBackgroundColor) : .secondary)
                        )
                }
                
                HStack(alignment: .lastTextBaseline, spacing: 8) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(self.value)
                            .font(.system(size: self.compact ? 23 : 27, weight: .bold))
                            .monospacedDigit()
                            .contentTransition(.numericText())
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        Text(self.unit)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    
                    Spacer(minLength: 4)
                    
                    PixelSparkMatrix(
                        values: self.sparkValues,
                        tint: self.sparkTint,
                        palette: self.palette
                    )
                    .frame(width: self.compact ? 48 : 58, height: 26)
                }
            }
            .modifier(DashCard(
                palette: self.palette,
                padding: self.padding,
                cornerRadius: self.cornerRadius,
                isHighlighted: self.isExpanded,
                isHovered: self.isHovered
            ))
            .contentShape(RoundedRectangle(cornerRadius: self.cornerRadius, style: .continuous))
        }
        .buttonStyle(PressStyle())
        .pointerStyle(.link)
        .onHover { hovering in
            withAnimation(DashMotion.quick) {
                self.isHovered = hovering
            }
        }
    }
}


/// Mini 7-column × 5-row stacked pixel-matrix sparkbar matching the reference image's top strip.
private struct PixelSparkMatrix: View {
    
    let values: [Double]
    let tint: SparkTint
    let palette: DashPalette
    
    
    var body: some View {
        
        Canvas { context, size in
            let cols = max(1, self.values.count)
            let rows = 5
            let gap: CGFloat = 2
            let cellW = (size.width - gap * CGFloat(cols - 1)) / CGFloat(cols)
            let cellH = (size.height - gap * CGFloat(rows - 1)) / CGFloat(rows)
            let cellSide = max(2.5, min(cellW, cellH))
            let radius = max(1, cellSide * 0.28)
            
            let peak = max(1.0, self.values.max() ?? 1.0)
            let totalWidth = CGFloat(cols) * cellSide + CGFloat(cols - 1) * gap
            let startX = size.width - totalWidth
            let startY = size.height - (CGFloat(rows) * cellSide + CGFloat(rows - 1) * gap)
            
            for col in 0..<cols {
                let val = self.values[col]
                let activeRows = val > 0 ? max(1, Int((val / peak * Double(rows)).rounded(.up))) : 0
                for row in 0..<rows {
                    let yIndex = rows - 1 - row
                    let rect = CGRect(
                        x: startX + CGFloat(col) * (cellSide + gap),
                        y: startY + CGFloat(yIndex) * (cellSide + gap),
                        width: cellSide,
                        height: cellSide
                    )
                    let color: Color
                    if row < activeRows {
                        let frac = Double(row + 1) / Double(rows)
                        switch self.tint {
                            case .emerald:
                                color = self.palette.matrixStep(fraction: frac, isPeak: row == rows - 1 && val >= peak * 0.92)
                            case .mint:
                                color = frac >= 0.8 ? self.palette.emerald : (frac >= 0.45 ? self.palette.mint : self.palette.paleMint)
                            case .coralSplit:
                                color = (col == cols - 1) ? self.palette.pine : (frac >= 0.7 ? self.palette.coral.opacity(0.82) : self.palette.coral.opacity(0.35))
                        }
                    } else {
                        color = self.palette.emptyDot.opacity(0.75)
                    }
                    context.fill(Path(roundedRect: rect, cornerRadius: radius, style: .continuous), with: .color(color))
                }
            }
        }
    }
}


// MARK: - Detail Panels (Reference-Inspired Visualizations)

/// Panel 1: Stacked pixel-matrix 14-day overview ("Monthly Overview" style) + 2x2 Bento stat tiles.
private struct TypedDetailPanel: View {
    
    let days: [DashboardSnapshot.ChartDay]
    let today: DailyWritingStats
    let compact: Bool
    let palette: DashPalette
    let onClose: () -> Void
    
    @State private var hoveredIndex: Int?
    
    
    var body: some View {
        
        let total = self.days.reduce(0) { $0 + $1.typed }
        let activeDays = self.days.filter { $0.typed > 0 }.count
        let average = activeDays > 0 ? total / activeDays : 0
        let peak = self.days.map(\.typed).max() ?? 0
        
        let statusNote: String = {
            if let idx = self.hoveredIndex, self.days.indices.contains(idx) {
                let d = self.days[idx]
                return "\(Self.shortDate(d.date)) · 手写 \(AnalyticsDashboardView.int(d.typed)) 字"
            }
            return "近 14 天合计 \(AnalyticsDashboardView.int(total)) 字 · 活跃日均 \(AnalyticsDashboardView.int(average)) 字"
        }()
        
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 10) {
                Text("近两周手写节奏")
                    .font(.system(size: 14, weight: .semibold))
                Text(statusNote)
                    .font(.system(size: 12))
                    .monospacedDigit()
                    .foregroundStyle(self.hoveredIndex == nil ? .secondary : .primary)
                    .lineLimit(1)
                
                Spacer(minLength: 8)
                
                if !self.compact {
                    HStack(spacing: 10) {
                        HStack(spacing: 4) {
                            RoundedRectangle(cornerRadius: 2, style: .continuous)
                                .fill(self.palette.pine)
                                .frame(width: 7, height: 7)
                            Text("跃升")
                        }
                        HStack(spacing: 4) {
                            RoundedRectangle(cornerRadius: 2, style: .continuous)
                                .strokeBorder(self.palette.emerald, lineWidth: 1.4)
                                .frame(width: 7, height: 7)
                            Text("回落")
                        }
                    }
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .padding(.trailing, 4)
                }
                
                IconButton(systemImage: "xmark", palette: self.palette, isClose: true, action: self.onClose)
            }
            
            HStack(alignment: .top, spacing: self.compact ? 14 : 22) {
                PixelMatrixBarChart(
                    days: self.days,
                    palette: self.palette,
                    hoveredIndex: self.$hoveredIndex
                )
                .frame(height: 156)
                .frame(maxWidth: .infinity)
                
                LazyVGrid(
                    columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)],
                    spacing: 8
                ) {
                    MiniStatTile(label: "今天新建", value: "\(self.today.filesCreated) 篇", palette: self.palette)
                    MiniStatTile(label: "今日保存", value: "\(self.today.documentsSaved) 次", palette: self.palette)
                    MiniStatTile(label: "两周峰值", value: "\(AnalyticsDashboardView.int(peak)) 字", palette: self.palette)
                    MiniStatTile(label: "动笔天数", value: "\(activeDays) / 14", palette: self.palette)
                }
                .frame(width: self.compact ? 196 : 236)
            }
        }
    }
    
    
    private static func shortDate(_ date: Date) -> String {
        
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M 月 d 日"
        return formatter.string(from: date)
    }
}


/// Canvas-drawn stacked micro-square bar matrix with jump/drop caps and column hover.
private struct PixelMatrixBarChart: View {
    
    let days: [DashboardSnapshot.ChartDay]
    let palette: DashPalette
    @Binding var hoveredIndex: Int?
    
    
    var body: some View {
        
        GeometryReader { proxy in
            let cols = max(1, self.days.count)
            let rows = 9
            let labelHeight: CGFloat = 18
            let gap: CGFloat = 4
            let gridHeight = max(40, proxy.size.height - labelHeight)
            let rawCellW = (proxy.size.width - gap * CGFloat(cols - 1)) / CGFloat(cols)
            let rawCellH = (gridHeight - gap * CGFloat(rows - 1)) / CGFloat(rows)
            let cellSize = max(5, min(14, min(rawCellW, rawCellH)))
            let colStep = (proxy.size.width - cellSize) / CGFloat(max(1, cols - 1))
            let topOffset = max(0, gridHeight - (CGFloat(rows) * cellSize + CGFloat(rows - 1) * gap))
            
            Canvas { context, size in
                let maxVal = max(120, self.days.map(\.typed).max() ?? 120)
                let radius = max(1.5, cellSize * 0.24)
                
                for col in 0..<cols {
                    let day = self.days[col]
                    let x = CGFloat(col) * colStep
                    let isHovered = (self.hoveredIndex == col)
                    let prevVal = col > 0 ? self.days[col - 1].typed : day.typed
                    let isJump = col > 0 && day.typed > max(120, Int(Double(prevVal) * 1.25))
                    let isDrop = col > 0 && prevVal > 0 && day.typed < Int(Double(prevVal) * 0.72)
                    
                    let filledCount = day.typed > 0
                        ? max(1, min(rows, Int((Double(day.typed) / Double(maxVal) * Double(rows)).rounded(.up))))
                        : 0
                    
                    for row in 0..<rows {
                        let yIndex = rows - 1 - row
                        let y = topOffset + CGFloat(yIndex) * (cellSize + gap)
                        let rect = CGRect(x: x, y: y, width: cellSize, height: cellSize)
                        let path = Path(roundedRect: rect, cornerRadius: radius, style: .continuous)
                        
                        if row < filledCount {
                            let isTop = (row == filledCount - 1)
                            if isTop && isDrop && filledCount >= 2 {
                                context.fill(path, with: .color(self.palette.card))
                                context.stroke(
                                    Path(roundedRect: rect.insetBy(dx: 0.75, dy: 0.75), cornerRadius: max(1, radius - 0.5), style: .continuous),
                                    with: .color(self.palette.emerald),
                                    lineWidth: 1.5
                                )
                            } else {
                                let frac = Double(row + 1) / Double(rows)
                                let color = self.palette.matrixStep(fraction: frac, isPeak: isTop && (isJump || day.isToday))
                                context.fill(path, with: .color(isHovered ? self.palette.pine : color))
                            }
                        } else {
                            context.fill(path, with: .color(self.palette.emptyDot.opacity(isHovered ? 0.95 : 0.65)))
                        }
                    }
                    
                    if col % 2 == 1 || col == cols - 1 {
                        let cal = Calendar.current
                        let labelStr = day.isToday ? "今" : "\(cal.component(.day, from: day.date))"
                        let text = context.resolve(
                            Text(labelStr)
                                .font(.system(size: 9.5, weight: day.isToday || isHovered ? .semibold : .regular))
                                .foregroundStyle(day.isToday || isHovered ? self.palette.pine : .secondary)
                        )
                        context.draw(text, at: CGPoint(x: x + cellSize / 2, y: size.height - 2), anchor: .bottom)
                    }
                }
            }
            .onContinuousHover { phase in
                switch phase {
                    case .active(let pt):
                        let idx = Int((pt.x / max(1, colStep)).rounded())
                        if self.days.indices.contains(idx) {
                            self.hoveredIndex = idx
                        }
                    case .ended:
                        self.hoveredIndex = nil
                }
            }
        }
    }
}


/// Panel 2: Semi-circular concentric dot-arch gauge ("Spending" style) + 7-day proportional bubbles.
private struct CompletionDetailPanel: View {
    
    let days: [DashboardSnapshot.ChartDay]
    let series7: [DailyWritingStats]
    let today: DailyWritingStats
    let compact: Bool
    let palette: DashPalette
    let onClose: () -> Void
    
    
    var body: some View {
        
        let accepts7 = self.series7.reduce(0) { $0 + $1.aiCompletionAccepts }
        let ai7 = self.series7.reduce(0) { $0 + $1.aiCompletedChars }
        let typed7 = self.series7.reduce(0) { $0 + $1.typedChars }
        let local7 = self.series7.reduce(0) { $0 + $1.localHits }
        let produced7 = ai7 + typed7
        let handPct = produced7 > 0 ? Int((Double(typed7) * 100 / Double(produced7)).rounded()) : 0
        let aiPct = produced7 > 0 ? (100 - handPct) : 0
        let perAccept = accepts7 > 0 ? ai7 / accepts7 : 0
        
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("近 7 天人机协作比例")
                    .font(.system(size: 14, weight: .semibold))
                Text("共采纳 \(accepts7) 次 · 帮写 \(AnalyticsDashboardView.int(ai7)) 字")
                    .font(.system(size: 12))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                Spacer()
                IconButton(systemImage: "xmark", palette: self.palette, isClose: true, action: self.onClose)
            }
            
            HStack(alignment: .center, spacing: self.compact ? 16 : 28) {
                VStack(spacing: 10) {
                    DotArcGauge(
                        primaryShare: produced7 > 0 ? Double(typed7) / Double(produced7) : 0,
                        totalLabel: AnalyticsDashboardView.int(produced7),
                        subtitle: "近 7 天共写出",
                        palette: self.palette
                    )
                    .frame(width: self.compact ? 186 : 214, height: self.compact ? 104 : 118)
                    
                    HStack(spacing: 16) {
                        HStack(spacing: 5) {
                            Circle().fill(self.palette.pine).frame(width: 7, height: 7)
                            Text("\(handPct)% 自己敲的")
                        }
                        HStack(spacing: 5) {
                            Circle().fill(self.palette.mint).frame(width: 7, height: 7)
                            Text("\(aiPct)% AI 帮补")
                        }
                    }
                    .font(.system(size: 11, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity)
                
                VStack(alignment: .leading, spacing: 12) {
                    ProportionalBubbleStrip(
                        days: self.days,
                        palette: self.palette
                    )
                    .frame(height: 62)
                    
                    LazyVGrid(
                        columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)],
                        spacing: 8
                    ) {
                        MiniStatTile(label: "今天采纳", value: "\(self.today.aiCompletionAccepts) 次", palette: self.palette)
                        MiniStatTile(label: "平均每次", value: "\(perAccept) 字", palette: self.palette)
                        MiniStatTile(label: "本地秒出", value: "\(local7) 次", palette: self.palette)
                        MiniStatTile(label: "7 日手写", value: "\(AnalyticsDashboardView.int(typed7)) 字", palette: self.palette)
                    }
                }
                .frame(width: self.compact ? 250 : 320)
            }
        }
    }
}


/// Semi-circular concentric dot-matrix gauge inspired by the "Spending" card in the reference image.
private struct DotArcGauge: View {
    
    let primaryShare: Double
    let totalLabel: String
    let subtitle: String
    let palette: DashPalette
    
    
    var body: some View {
        
        ZStack(alignment: .bottom) {
            Canvas { context, size in
                let center = CGPoint(x: size.width / 2, y: size.height - 6)
                let ringCount = 4
                let maxRadius = min(size.width * 0.45, size.height - 14)
                let ringSpacing: CGFloat = max(8, maxRadius * 0.145)
                let dotCounts = [19, 16, 13, 10]
                let dotRadius: CGFloat = 3.1
                
                for ring in 0..<ringCount {
                    let count = dotCounts[ring]
                    let radius = maxRadius - CGFloat(ring) * ringSpacing
                    for i in 0..<count {
                        let frac = Double(i) / Double(max(1, count - 1))
                        let angle = Double.pi * (1.0 - frac) // π (left) -> 0 (right)
                        let pt = CGPoint(
                            x: center.x + CGFloat(cos(angle)) * radius,
                            y: center.y - CGFloat(sin(angle)) * radius
                        )
                        let rect = CGRect(x: pt.x - dotRadius, y: pt.y - dotRadius, width: dotRadius * 2, height: dotRadius * 2)
                        let color: Color
                        if self.primaryShare <= 0 {
                            color = self.palette.emptyDot
                        } else if frac <= self.primaryShare {
                            color = self.palette.pine
                        } else {
                            color = self.palette.mint
                        }
                        context.fill(Path(ellipseIn: rect), with: .color(color))
                    }
                }
            }
            
            VStack(spacing: 1) {
                Image(systemName: "sparkles")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(self.palette.emerald)
                Text(self.subtitle)
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(.secondary)
                Text(self.totalLabel)
                    .font(.system(size: 16, weight: .bold))
                    .monospacedDigit()
            }
            .padding(.bottom, 2)
        }
    }
}


private struct ProportionalBubbleStrip: View {
    
    let days: [DashboardSnapshot.ChartDay]
    let palette: DashPalette
    
    
    var body: some View {
        
        let maxAI = max(20, self.days.map(\.ai).max() ?? 20)
        
        HStack(alignment: .bottom, spacing: 0) {
            ForEach(self.days) { day in
                let ratio = Double(day.ai) / Double(maxAI)
                let diameter = day.ai > 0 ? max(10, min(32, 10 + 22 * sqrt(ratio))) : 6
                let cal = Calendar.current
                
                VStack(spacing: 4) {
                    Spacer(minLength: 0)
                    Circle()
                        .fill(day.ai == 0 ? self.palette.emptyDot : (day.isToday ? self.palette.pine : self.palette.mint))
                        .frame(width: diameter, height: diameter)
                    Text(day.isToday ? "今" : "\(cal.component(.day, from: day.date))")
                        .font(.system(size: 9.5, weight: day.isToday ? .semibold : .regular))
                        .foregroundStyle(day.isToday ? self.palette.pine : .secondary)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(self.palette.inset, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}


/// Panel 3: Dual-tone bubble timeline ("Cash Flow" style) + "Transactions"-style Model/Feature ranked rows.
private struct ConsumptionDetailPanel: View {
    
    let days: [DashboardSnapshot.ChartDay]
    let slice: DashboardSnapshot.AISlice
    @Binding var aiRange: AnalyticsDashboardView.AIRange
    let compact: Bool
    let palette: DashPalette
    let onClose: () -> Void
    
    @State private var hoveredDayIndex: Int?
    
    
    var body: some View {
        
        let totals = self.slice.totals
        let meta: String = {
            if let idx = self.hoveredDayIndex, self.days.indices.contains(idx) {
                let d = self.days[idx]
                return "\(Self.shortDate(d.date)) · 输入 \(AnalyticsManager.formatCompactTokenCount(d.input)) · 输出 \(AnalyticsManager.formatCompactTokenCount(d.output))"
            }
            return "\(totals.requests) 次调用 · 输入 \(AnalyticsManager.formatCompactTokenCount(totals.inputTokens)) · 输出 \(AnalyticsManager.formatCompactTokenCount(totals.outputTokens))"
        }()
        
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 10) {
                Text("AI 消耗分布")
                    .font(.system(size: 14, weight: .semibold))
                Text(meta)
                    .font(.system(size: 12))
                    .monospacedDigit()
                    .foregroundStyle(self.hoveredDayIndex == nil ? .secondary : .primary)
                    .lineLimit(1)
                
                Spacer(minLength: 8)
                
                Picker("", selection: self.$aiRange) {
                    ForEach(AnalyticsDashboardView.AIRange.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .controlSize(.small)
                .frame(width: 124)
                
                IconButton(systemImage: "xmark", palette: self.palette, isClose: true, action: self.onClose)
            }
            
            BubbleDotTimeline(days: self.days, palette: self.palette, hoveredIndex: self.$hoveredDayIndex)
                .frame(height: 112)
            
            HStack(alignment: .top, spacing: 16) {
                BentoRankList(
                    title: "主力模型",
                    rows: self.slice.models.prefix(4).map {
                        (
                            id: $0.model,
                            name: $0.model,
                            share: $0.share,
                            value: AnalyticsManager.formatCompactTokenCount($0.totalTokens),
                            symbol: "cpu"
                        )
                    },
                    palette: self.palette
                )
                
                BentoRankList(
                    title: "常用功能",
                    rows: self.slice.features.prefix(4).map {
                        (
                            id: $0.feature,
                            name: $0.displayName,
                            share: $0.share,
                            value: "\($0.requests) 次",
                            symbol: "wand.and.stars"
                        )
                    },
                    palette: self.palette
                )
            }
        }
    }
    
    
    private static func shortDate(_ date: Date) -> String {
        
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M 月 d 日"
        return formatter.string(from: date)
    }
}


/// Vertical hairlines with top deep-pine input bubbles & bottom coral output bubbles (inspired by the left chart in the reference image).
private struct BubbleDotTimeline: View {
    
    let days: [DashboardSnapshot.ChartDay]
    let palette: DashPalette
    @Binding var hoveredIndex: Int?
    
    
    var body: some View {
        
        GeometryReader { proxy in
            let cols = max(1, self.days.count)
            let sidePad: CGFloat = 24
            let step = (proxy.size.width - sidePad * 2) / CGFloat(max(1, cols - 1))
            let maxIn = max(100, self.days.map(\.input).max() ?? 100)
            let maxOut = max(40, self.days.map(\.output).max() ?? 40)
            
            Canvas { context, size in
                let midY = (size.height - 20) * 0.5
                let baselineRect = CGRect(x: sidePad - 8, y: midY - 0.5, width: size.width - sidePad * 2 + 16, height: 1)
                context.fill(Path(baselineRect), with: .color(self.palette.hairline))
                
                for col in 0..<cols {
                    let day = self.days[col]
                    let x = sidePad + CGFloat(col) * step
                    let isHovered = (self.hoveredIndex == col)
                    
                    // Subtle vertical guideline
                    let linePath = Path(CGRect(x: x - 0.5, y: 6, width: 1, height: size.height - 26))
                    context.fill(linePath, with: .color(isHovered ? self.palette.emerald.opacity(0.35) : self.palette.hairline))
                    
                    // Upper bubble: input tokens
                    let inRatio = Double(day.input) / Double(maxIn)
                    let inR: CGFloat = day.input > 0 ? max(4, min(14, 4 + 10 * sqrt(inRatio))) : 2.5
                    let inY = midY - 14 - CGFloat(inRatio) * 14
                    let inRect = CGRect(x: x - inR, y: inY - inR, width: inR * 2, height: inR * 2)
                    context.fill(
                        Path(ellipseIn: inRect),
                        with: .color(day.input == 0 ? self.palette.emptyDot : (day.isToday || isHovered ? self.palette.pine : self.palette.emerald.opacity(0.75)))
                    )
                    
                    // Lower bubble: output tokens
                    let outRatio = Double(day.output) / Double(maxOut)
                    let outR: CGFloat = day.output > 0 ? max(3.5, min(11, 3.5 + 7.5 * sqrt(outRatio))) : 2.5
                    let outY = midY + 14 + CGFloat(outRatio) * 12
                    let outRect = CGRect(x: x - outR, y: outY - outR, width: outR * 2, height: outR * 2)
                    context.fill(
                        Path(ellipseIn: outRect),
                        with: .color(day.output == 0 ? self.palette.emptyDot : (day.isToday || isHovered ? self.palette.coral : self.palette.coral.opacity(0.55)))
                    )
                    
                    let cal = Calendar.current
                    let label = day.isToday ? "今" : "\(cal.component(.day, from: day.date))"
                    let text = context.resolve(
                        Text(label)
                            .font(.system(size: 9.5, weight: day.isToday || isHovered ? .semibold : .regular))
                            .foregroundStyle(day.isToday || isHovered ? self.palette.pine : .secondary)
                    )
                    context.draw(text, at: CGPoint(x: x, y: size.height - 2), anchor: .bottom)
                }
            }
            .background(self.palette.inset, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .onContinuousHover { phase in
                switch phase {
                    case .active(let pt):
                        let idx = Int(((pt.x - sidePad) / max(1, step)).rounded())
                        if self.days.indices.contains(idx) {
                            self.hoveredIndex = idx
                        }
                    case .ended:
                        self.hoveredDayHoverClear()
                }
            }
        }
    }
    
    
    private func hoveredDayHoverClear() {
        
        self.hoveredIndex = nil
    }
}


private struct BentoRankList: View {
    
    typealias Row = (id: String, name: String, share: Double, value: String, symbol: String)
    
    let title: String
    let rows: [Row]
    let palette: DashPalette
    
    
    var body: some View {
        
        VStack(alignment: .leading, spacing: 6) {
            Text(self.title)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(.secondary)
            
            if self.rows.isEmpty {
                Text("暂无记录")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(self.palette.inset, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            } else {
                ForEach(self.rows, id: \.id) { row in
                    let activeDots = max(1, min(8, Int((row.share * 8).rounded())))
                    HStack(spacing: 8) {
                        Image(systemName: row.symbol)
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(self.palette.emerald)
                            .frame(width: 24, height: 24)
                            .background(self.palette.card, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                        
                        Text(row.name)
                            .font(.system(size: 12, weight: .medium))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        
                        Spacer(minLength: 4)
                        
                        HStack(spacing: 2) {
                            ForEach(0..<8, id: \.self) { idx in
                                Circle()
                                    .fill(idx < activeDots ? self.palette.emerald : self.palette.emptyDot)
                                    .frame(width: 4, height: 4)
                            }
                        }
                        
                        Text(row.value)
                            .font(.system(size: 11.5, weight: .medium))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 48, alignment: .trailing)
                    }
                    .padding(.horizontal, 8)
                    .frame(height: 34)
                    .background(self.palette.inset, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}


private struct MiniStatTile: View {
    
    let label: String
    let value: String
    let palette: DashPalette
    
    
    var body: some View {
        
        VStack(alignment: .leading, spacing: 3) {
            Text(self.label)
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(self.value)
                .font(.system(size: 14, weight: .semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(self.palette.inset, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}


private struct DotCompositionBar: View {
    
    let primaryRatio: Double
    let secondaryRatio: Double
    let palette: DashPalette
    
    
    var body: some View {
        
        GeometryReader { proxy in
            let count = max(12, Int(proxy.size.width / 11))
            let primaryCount = Int((self.primaryRatio * Double(count)).rounded())
            let secondaryCount = min(count - primaryCount, max(0, Int((self.secondaryRatio * Double(count)).rounded())))
            
            HStack(spacing: 4) {
                ForEach(0..<count, id: \.self) { index in
                    let color: Color = if index < primaryCount {
                        self.palette.pine
                    } else if index < primaryCount + secondaryCount {
                        self.palette.mint
                    } else {
                        self.palette.emptyDot
                    }
                    RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                        .fill(color)
                        .frame(maxWidth: .infinity)
                        .frame(height: 7)
                }
            }
        }
        .frame(height: 7)
    }
}


// MARK: - Rolling Heatmap (Backwards From Today, Zero Future Empty Months)

private struct RollingHeatmapCard: View {
    
    let heatmap: RollingHeatmapData
    let selectedKey: String
    @Binding var range: AnalyticsDashboardView.HeatmapRange
    let palette: DashPalette
    let compact: Bool
    let padding: CGFloat
    let cornerRadius: CGFloat
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
        let monthBand: CGFloat = 18
        let weeks = CGFloat(max(1, self.heatmap.weeks.count))
        let gridWidth = max(200, width - labelColumn - labelGap)
        let gap: CGFloat = self.heatmap.weeks.count <= 28 ? (gridWidth > 680 ? 4 : 3) : (gridWidth > 760 ? 3 : 2)
        let raw = (gridWidth - gap * (weeks - 1)) / weeks
        let cell = max(6, min(20, (raw * 2).rounded(.down) / 2))
        
        return Layout(
            gridX: labelColumn + labelGap,
            gridY: monthBand,
            cell: cell,
            gap: gap,
            radius: max(2, min(4.5, cell * 0.24)),
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
        return cell.isFuture ? nil : cell
    }
    
    
    var body: some View {
        
        let layout = self.layout(for: self.width > 0 ? self.width : (self.compact ? 660 : 960))
        
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 10) {
                Text(self.statusLine)
                    .font(.system(size: 12.5, weight: self.hovered == nil ? .regular : .medium))
                    .monospacedDigit()
                    .foregroundStyle(self.hovered == nil ? .secondary : .primary)
                    .lineLimit(1)
                
                Spacer(minLength: 8)
                
                Picker("", selection: self.$range) {
                    ForEach(AnalyticsDashboardView.HeatmapRange.allCases) { item in
                        Text(item.rawValue).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .controlSize(.small)
                .frame(width: 126)
            }
            
            Canvas { context, _ in
                self.draw(in: &context, layout: layout)
            }
            .frame(height: layout.height)
            .frame(maxWidth: .infinity, alignment: .leading)
            .onContinuousHover { phase in
                switch phase {
                    case .active(let point):
                        let target = self.cell(at: point, layout: layout)
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
                if let target = self.cell(at: point, layout: layout) {
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
                Text("点哪天就看哪天的故事")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                Spacer()
                Text("少")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                ForEach(0..<5, id: \.self) { level in
                    RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                        .fill(self.palette.heat(level))
                        .frame(width: 10, height: 10)
                }
                Text("多")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
        .modifier(DashCard(palette: self.palette, padding: self.padding, cornerRadius: self.cornerRadius))
    }
    
    
    private var statusLine: String {
        
        if let cell = self.hovered {
            let total = cell.typedChars + cell.aiCompletedChars
            return total > 0
                ? "\(Self.shortDate(cell.date)) · 写了 \(AnalyticsDashboardView.int(total)) 字"
                : "\(Self.shortDate(cell.date)) · 休息留白的一天"
        }
        return "\(self.range.rawValue)有 \(self.heatmap.activeDays) 天动过笔"
    }
    
    
    private func draw(in context: inout GraphicsContext, layout: Layout) {
        
        let todayKey = AnalyticsManager.dateKey()
        
        for label in self.heatmap.monthLabels {
            let text = context.resolve(Text(label.label).font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary))
            context.draw(text, at: CGPoint(x: layout.gridX + CGFloat(label.weekIndex) * layout.pitch, y: 0), anchor: .topLeading)
        }
        
        for (row, name) in [(0, "一"), (2, "三"), (4, "五")] {
            let text = context.resolve(Text(name).font(.system(size: 9.5)).foregroundStyle(.secondary))
            let y = layout.gridY + CGFloat(row) * layout.pitch + layout.cell / 2
            context.draw(text, at: CGPoint(x: 0, y: y), anchor: .leading)
        }
        
        var todayRect: CGRect?
        var hoveredRect: CGRect?
        var selectedRect: CGRect?
        
        for (week, days) in self.heatmap.weeks.enumerated() {
            for (row, cell) in days.enumerated() where !cell.isFuture {
                let rect = CGRect(
                    x: layout.gridX + CGFloat(week) * layout.pitch,
                    y: layout.gridY + CGFloat(row) * layout.pitch,
                    width: layout.cell,
                    height: layout.cell
                )
                let color = self.palette.heat(cell.level)
                context.fill(Path(roundedRect: rect, cornerRadius: layout.radius, style: .continuous), with: .color(color))
                
                if cell.dateKey == todayKey { todayRect = rect }
                if cell.id == self.hovered?.id { hoveredRect = rect }
                if cell.dateKey == self.selectedKey { selectedRect = rect }
            }
        }
        
        if let rect = todayRect, self.selectedKey != todayKey {
            context.stroke(
                Path(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), cornerRadius: layout.radius, style: .continuous),
                with: .color(self.palette.emerald.opacity(0.55)),
                lineWidth: 1.1
            )
        }
        if let rect = hoveredRect, self.hovered?.dateKey != self.selectedKey {
            context.stroke(
                Path(roundedRect: rect.insetBy(dx: -1.2, dy: -1.2), cornerRadius: layout.radius + 1.2, style: .continuous),
                with: .color(self.palette.emerald.opacity(0.7)),
                lineWidth: 1.25
            )
        }
        if let rect = selectedRect {
            context.stroke(
                Path(roundedRect: rect.insetBy(dx: -1.8, dy: -1.8), cornerRadius: layout.radius + 1.8, style: .continuous),
                with: .color(self.palette.pine),
                lineWidth: 1.8
            )
        }
    }
    
    
    private static func shortDate(_ date: Date) -> String {
        
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M 月 d 日 EEE"
        return formatter.string(from: date)
    }
}


// MARK: - Small UI Helpers

private struct PressStyle: ButtonStyle {
    
    func makeBody(configuration: Configuration) -> some View {
        
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(DashMotion.quick, value: configuration.isPressed)
    }
}


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
                .foregroundStyle(self.isHovered ? (self.isClose ? Color.red : self.palette.pine) : .secondary)
                .rotationEffect(.degrees(self.isClose && self.isHovered ? 90 : 0))
                .frame(width: 24, height: 24)
                .background(
                    Circle().fill(
                        self.isHovered
                            ? (self.isClose ? Color.red.opacity(0.10) : self.palette.insetHover)
                            : self.palette.inset
                    )
                )
                .contentShape(Circle())
        }
        .buttonStyle(PressStyle())
        .pointerStyle(.link)
        .onHover { hovering in
            withAnimation(DashMotion.standard) {
                self.isHovered = hovering
            }
        }
    }
}


private struct StepCircleButton: View {
    
    let systemImage: String
    let isEnabled: Bool
    let palette: DashPalette
    let action: () -> Void
    
    @State private var isHovered = false
    
    
    var body: some View {
        
        Button(action: self.action) {
            Image(systemName: self.systemImage)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(self.isHovered && self.isEnabled ? self.palette.pine : .secondary)
                .frame(width: 24, height: 24)
                .background(
                    Circle().fill(self.isHovered && self.isEnabled ? self.palette.insetHover : self.palette.inset)
                )
                .contentShape(Circle())
        }
        .buttonStyle(PressStyle())
        .disabled(!self.isEnabled)
        .opacity(self.isEnabled ? 1 : 0.32)
        .onHover { hovering in
            withAnimation(DashMotion.quick) {
                self.isHovered = hovering && self.isEnabled
            }
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
                    .font(.system(size: 12.5))
                    .foregroundStyle(self.reminder.isCompleted ? self.palette.emerald : .secondary)
                Text(self.reminder.title)
                    .font(.system(size: 12))
                    .foregroundStyle(self.reminder.isCompleted ? .secondary : .primary)
                    .strikethrough(self.reminder.isCompleted, color: .secondary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if self.reminder.priority == .high {
                    Text("重要")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(self.palette.coral)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(self.isHovered ? self.palette.insetHover : self.palette.inset)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointerStyle(.link)
        .onHover { hovering in
            withAnimation(DashMotion.quick) {
                self.isHovered = hovering
            }
        }
    }
}
