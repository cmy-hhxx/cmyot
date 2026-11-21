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
    
    
    func openDocument(_ record: StoredDocumentRecord, preferredWindow: NSWindow? = nil) {
        
        if let activeWC = self.resolveDocumentWindowController(preferredWindow: preferredWindow),
           let docVC = activeWC.workspaceContentViewController?.documentViewController
        {
            docVC.openStoredDocumentRecord(record)
            activeWC.workspaceContentViewController?.hideInWindowCenter()
            activeWC.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }
    
    
    func openWeeklyReport(_ report: StoredWeeklyReport, preferredWindow: NSWindow? = nil) {
        
        if let activeWC = self.resolveDocumentWindowController(preferredWindow: preferredWindow),
           let docVC = activeWC.workspaceContentViewController?.documentViewController
        {
            docVC.openStoredWeeklyReport(report)
            activeWC.workspaceContentViewController?.hideInWindowCenter()
            activeWC.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
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


/// Calm architectural neutrals with charcoal ink, muted sage charts, and a single botanical pine-sage accent.
private struct DashPalette {
    
    let isDark: Bool
    
    init(_ scheme: ColorScheme) {
        
        self.isDark = (scheme == .dark)
    }
    
    var canvasTop: Color {
        self.isDark
            ? Color(red: 0.067, green: 0.075, blue: 0.078)
            : Color(red: 0.965, green: 0.969, blue: 0.969)
    }
    var canvasBottom: Color {
        self.isDark
            ? Color(red: 0.078, green: 0.086, blue: 0.090)
            : Color(red: 0.976, green: 0.980, blue: 0.980)
    }
    var mistMint: Color {
        self.isDark
            ? Color(red: 0.22, green: 0.44, blue: 0.35).opacity(0.11)
            : Color(red: 0.76, green: 0.85, blue: 0.80).opacity(0.16)
    }
    
    var card: Color {
        self.isDark
            ? Color(red: 0.105, green: 0.115, blue: 0.118)
            : Color.white
    }
    var cardShadow: Color {
        self.isDark
            ? Color.black.opacity(0.26)
            : Color.black.opacity(0.045)
    }
    var inset: Color {
        self.isDark
            ? Color.white.opacity(0.045)
            : Color(red: 0.955, green: 0.960, blue: 0.960)
    }
    var insetHover: Color {
        self.isDark
            ? Color.white.opacity(0.075)
            : Color(red: 0.925, green: 0.933, blue: 0.933)
    }
    var hairline: Color {
        self.isDark ? Color.white.opacity(0.085) : Color.black.opacity(0.06)
    }
    var hairlineStrong: Color {
        self.isDark ? self.emerald.opacity(0.55) : self.pine.opacity(0.28)
    }
    var topSpecular: Color {
        self.isDark ? Color.white.opacity(0.07) : Color.white.opacity(0.88)
    }
    var architecturalDot: Color {
        self.isDark ? Color.white.opacity(0.045) : Color.black.opacity(0.04)
    }
    
    var pine: Color {
        self.isDark
            ? Color(red: 0.88, green: 0.91, blue: 0.90)
            : Color(red: 0.125, green: 0.155, blue: 0.150)
    }
    var emerald: Color {
        self.isDark
            ? Color(red: 0.40, green: 0.74, blue: 0.59)
            : Color(red: 0.21, green: 0.45, blue: 0.35)
    }
    var mint: Color {
        self.isDark
            ? Color(red: 0.28, green: 0.50, blue: 0.41)
            : Color(red: 0.52, green: 0.69, blue: 0.61)
    }
    var paleMint: Color {
        self.isDark
            ? Color(red: 0.17, green: 0.29, blue: 0.24)
            : Color(red: 0.80, green: 0.88, blue: 0.84)
    }
    var emptyDot: Color {
        self.isDark
            ? Color.white.opacity(0.07)
            : Color(red: 0.905, green: 0.915, blue: 0.912)
    }
    var positivePillBg: Color {
        self.isDark
            ? Color(red: 0.21, green: 0.45, blue: 0.35).opacity(0.22)
            : Color(red: 0.91, green: 0.95, blue: 0.93)
    }
    var neutralPillBg: Color {
        self.isDark ? Color.white.opacity(0.07) : Color.black.opacity(0.045)
    }
    
    
    func heat(_ level: Int) -> Color {
        
        if self.isDark {
            switch level {
                case 4: Color(red: 0.373, green: 0.722, blue: 0.576)
                case 3: Color(red: 0.231, green: 0.455, blue: 0.369)
                case 2: Color(red: 0.157, green: 0.294, blue: 0.243)
                case 1: Color(red: 0.110, green: 0.184, blue: 0.157)
                default: self.emptyDot
            }
        } else {
            switch level {
                case 4: Color(red: 0.141, green: 0.294, blue: 0.235)
                case 3: Color(red: 0.302, green: 0.502, blue: 0.416)
                case 2: Color(red: 0.573, green: 0.714, blue: 0.643)
                case 1: Color(red: 0.831, green: 0.890, blue: 0.859)
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
    var yearlyHeatmap: YearlyHeatmapData
    var availableYears: [Int]
    var orderedCells: [HeatmapDayCell]
    var aiHeatmap12: RollingHeatmapData
    var aiToday: AISlice
    var ai30: AISlice
    
    
    @MainActor static func build(analytics: AnalyticsManager, selectedYear: Int) -> DashboardSnapshot {
        
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
        
        let availableYears = analytics.availableHeatmapYears()
        let resolvedYear = availableYears.contains(selectedYear)
            ? selectedYear
            : (availableYears.last ?? Calendar.current.component(.year, from: Date()))
        let yearly = analytics.yearlyHeatmap(year: resolvedYear, trimFutureWeeks: true)
        let ordered = yearly.weeks.flatMap { $0 }.filter { !$0.isOutOfYear && !$0.isFuture }
        let aiHeatmap = analytics.aiConsumptionHeatmap(weeks: 12)
        
        return DashboardSnapshot(
            today: today,
            typedBaseline7: baseline,
            days14: chartDays,
            days7: Array(chartDays.suffix(7)),
            series7: series7,
            yearlyHeatmap: yearly,
            availableYears: availableYears,
            orderedCells: ordered,
            aiHeatmap12: aiHeatmap,
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
            )
        )
    }
}


// MARK: - Dashboard

/// Frosted sage-mint architectural Bento writing dashboard with yearly calendar heatmap, miniature AI heatmap, clickable documents, and editorial daily story.
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
    
    let isEmbeddedInSettings: Bool
    var onDismiss: (() -> Void)?
    var onOpenDocument: ((StoredDocumentRecord) -> Void)?
    var onOpenWeeklyReport: ((StoredWeeklyReport) -> Void)?
    
    @Environment(\.colorScheme) private var colorScheme
    
    @State private var analytics = AnalyticsManager.shared
    @State private var profileManager = UserProfileManager.shared
    @State private var snapshot: DashboardSnapshot?
    @State private var expandedKPI: KPIKind?
    @State private var aiRange: AIRange = .thirtyDays
    @State private var selectedYear: Int = Calendar.current.component(.year, from: Date())
    @State private var selectedDateKey: String = AnalyticsManager.dateKey()
    @State private var canvasWidth: CGFloat = 1040
    @State private var hasAppeared = false
    
    
    init(
        isEmbeddedInSettings: Bool,
        onDismiss: (() -> Void)? = nil,
        onOpenDocument: ((StoredDocumentRecord) -> Void)? = nil,
        onOpenWeeklyReport: ((StoredWeeklyReport) -> Void)? = nil
    ) {
        
        self.isEmbeddedInSettings = isEmbeddedInSettings
        self.onDismiss = onDismiss
        self.onOpenDocument = onOpenDocument
        self.onOpenWeeklyReport = onOpenWeeklyReport
    }
    
    
    private var palette: DashPalette { DashPalette(self.colorScheme) }
    private var compact: Bool { self.isEmbeddedInSettings }
    private var useAsymmetricBento: Bool { !self.compact && self.canvasWidth >= 860 }
    private var outerPadding: CGFloat { self.compact ? 16 : 24 }
    private var gap: CGFloat { self.compact ? 12 : 16 }
    private var cardPadding: CGFloat { self.compact ? 14 : 18 }
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
                .frame(maxWidth: 1120, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { newWidth in
            if abs(newWidth - self.canvasWidth) > 2 {
                self.canvasWidth = newWidth
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
        .onChange(of: self.selectedYear) { _, _ in
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
                    center: .top,
                    startRadius: 10,
                    endRadius: max(380, proxy.size.width * 0.56)
                )
            }
            
            // Subtle architectural drafting dot grid for Plane-0 spatial depth
            Canvas { context, size in
                let step: CGFloat = 20
                let radius: CGFloat = 0.85
                let dotColor = self.palette.architecturalDot
                var y: CGFloat = 12
                while y < size.height {
                    var x: CGFloat = 12
                    while x < size.width {
                        let rect = CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)
                        context.fill(Path(ellipseIn: rect), with: .color(dotColor))
                        x += step
                    }
                    y += step
                }
            }
            .allowsHitTesting(false)
        }
    }
    
    
    private func rebuild() {
        
        let built = DashboardSnapshot.build(analytics: self.analytics, selectedYear: self.selectedYear)
        if built.yearlyHeatmap.year != self.selectedYear {
            self.selectedYear = built.yearlyHeatmap.year
        }
        self.snapshot = built
        if !built.orderedCells.contains(where: { $0.dateKey == self.selectedDateKey }) {
            if built.orderedCells.contains(where: { $0.dateKey == built.today.dateKey }) {
                self.selectedDateKey = built.today.dateKey
            } else if let latestActive = built.orderedCells.last(where: { $0.level > 0 }) ?? built.orderedCells.last {
                self.selectedDateKey = latestActive.dateKey
            }
        }
    }
    
    
    // MARK: Layout
    
    private func content(_ s: DashboardSnapshot) -> some View {
        
        let activeCell = self.resolvedSelectedCell(in: s)
        let story = self.analytics.humanDayStory(for: activeCell, baselineDailyChars: s.typedBaseline7)
        
        return VStack(alignment: .leading, spacing: self.gap) {
            self.header
                .padding(.bottom, self.compact ? 2 : 4)
            
            self.kpiRow(s)
            
            if let kind = self.expandedKPI {
                self.detailPanel(kind, s)
                    .id(kind)
                    .transition(.opacity.combined(with: .scale(scale: 0.985, anchor: .top)))
            }
            
            if self.useAsymmetricBento {
                // Asymmetric 2-column Bento Architecture:
                // Left (~66%): Calendar-Year Heatmap on top + Balanced Twin Row below (DotArcGauge & Clickable Docs)
                // Right (~34%): Full-height Editorial Daily Story Pillar with bottom-anchored 2x2 Footprints
                HStack(alignment: .top, spacing: self.gap) {
                    VStack(alignment: .leading, spacing: self.gap) {
                        self.yearlyHeatmapCard(s, activeCell: activeCell)
                        
                        self.twinBentoRow(story)
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    
                    self.editorialStoryPillar(story, snapshot: s, isSidePillar: true)
                        .frame(width: 332, alignment: .topLeading)
                }
                .fixedSize(horizontal: false, vertical: true)
            } else {
                self.yearlyHeatmapCard(s, activeCell: activeCell)
                
                self.twinBentoRow(story)
                
                self.editorialStoryPillar(story, snapshot: s, isSidePillar: false)
            }
        }
    }
    
    
    private func yearlyHeatmapCard(_ s: DashboardSnapshot, activeCell: HeatmapDayCell) -> some View {
        
        YearlyHeatmapCard(
            heatmap: s.yearlyHeatmap,
            availableYears: s.availableYears,
            selectedYear: self.$selectedYear,
            selectedKey: activeCell.dateKey,
            palette: self.palette,
            compact: self.compact,
            padding: self.cardPadding,
            cornerRadius: self.cornerRadius
        ) { tappedCell in
            withAnimation(DashMotion.spring) {
                self.selectedDateKey = tappedCell.dateKey
            }
        }
    }
    
    
    private func resolvedSelectedCell(in s: DashboardSnapshot) -> HeatmapDayCell {
        
        if let matched = s.orderedCells.first(where: { $0.dateKey == self.selectedDateKey }) {
            return matched
        }
        if let todayCell = s.orderedCells.first(where: { $0.dateKey == s.today.dateKey }) {
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
                            .strokeBorder(self.palette.hairline, lineWidth: 1)
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
        let typedSpark = s.days7.map { Double($0.typed) }
        let aiSpark = s.days7.map { Double($0.ai) }
        let tokenSpark = s.days7.map { Double($0.input + $0.output) }
        
        return HStack(alignment: .top, spacing: self.gap) {
            KPICard(
                title: "今日手写",
                value: Self.int(today.typedChars),
                unit: "字",
                sparkValues: typedSpark,
                sparkTint: .ink,
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
                sparkValues: aiSpark,
                sparkTint: .sage,
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
                sparkValues: tokenSpark,
                sparkTint: .ink,
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
                        aiHeatmap: s.aiHeatmap12,
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
    
    
    // MARK: Asymmetric Left Twin Row (Balance Gauge + Clickable Documents)
    
    private func twinBentoRow(_ story: DailyHumanStory) -> some View {
        
        let entries = self.documentEntries(for: story)
        let primaryShare = story.totalChars > 0 ? Double(story.handTypedChars) / Double(story.totalChars) : 0
        let handPercent = story.totalChars > 0 ? Int((primaryShare * 100).rounded()) : 0
        let aiPercent = story.totalChars > 0 ? max(0, 100 - handPercent) : 0
        
        return Group {
            if self.compact {
                HStack(alignment: .top, spacing: self.gap) {
                    self.dayBalanceCard(story, primaryShare: primaryShare, handPercent: handPercent, aiPercent: aiPercent)
                        .frame(width: 210)
                    
                    self.dayDocumentsCard(entries)
                        .frame(maxWidth: .infinity)
                }
                .fixedSize(horizontal: false, vertical: true)
            } else {
                HStack(alignment: .top, spacing: self.gap) {
                    self.dayBalanceCard(story, primaryShare: primaryShare, handPercent: handPercent, aiPercent: aiPercent)
                        .frame(width: self.canvasWidth >= 980 ? 228 : 204)
                    
                    self.dayDocumentsCard(entries)
                        .frame(maxWidth: .infinity)
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
    
    
    private func dayBalanceCard(
        _ story: DailyHumanStory,
        primaryShare: Double,
        handPercent: Int,
        aiPercent: Int
    ) -> some View {
        
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text("写作构成")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
            }
            
            DotArcGauge(
                primaryShare: primaryShare,
                totalLabel: Self.int(story.totalChars),
                palette: self.palette
            )
            .frame(height: 106)
            .frame(maxWidth: .infinity)
            
            Spacer(minLength: 0)
            
            HStack(spacing: 8) {
                HStack(spacing: 4) {
                    Circle().fill(self.palette.pine).frame(width: 6, height: 6)
                    Text("手写 \(handPercent)%")
                }
                Spacer(minLength: 4)
                HStack(spacing: 4) {
                    Circle().fill(self.palette.mint).frame(width: 6, height: 6)
                    Text("AI \(aiPercent)%")
                }
            }
            .font(.system(size: 11, weight: .medium))
            .monospacedDigit()
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(self.palette.inset, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(self.palette.hairline, lineWidth: 0.75)
            )
        }
        .modifier(DashCard(palette: self.palette, padding: self.cardPadding, cornerRadius: self.cornerRadius))
    }
    
    
    private func dayDocumentsCard(_ entries: [DocumentEntry]) -> some View {
        
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 6) {
                Text("这天动过的文档")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                if !entries.isEmpty {
                    Text("\(entries.count) 篇")
                        .font(.system(size: 10.5, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2.5)
                        .background(self.palette.neutralPillBg, in: Capsule())
                }
            }
            
            if entries.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "leaf")
                        .font(.system(size: 15))
                        .foregroundStyle(.secondary)
                    Text("这天没有留下文档改动记录")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 132)
                .background(self.palette.inset, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(self.palette.hairline, lineWidth: 0.75)
                )
            } else {
                VStack(spacing: 6) {
                    ForEach(entries.prefix(self.compact ? 3 : 4)) { entry in
                        TransactionDocRow(entry: entry, palette: self.palette) {
                            self.openDocumentEntry(entry)
                        }
                    }
                }
            }
            
            Spacer(minLength: 0)
        }
        .modifier(DashCard(palette: self.palette, padding: self.cardPadding, cornerRadius: self.cornerRadius))
    }
    
    
    // MARK: Asymmetric Right Editorial Daily Story Pillar
    
    private func editorialStoryPillar(
        _ story: DailyHumanStory,
        snapshot s: DashboardSnapshot,
        isSidePillar: Bool
    ) -> some View {
        
        let cells = s.orderedCells
        let index = cells.firstIndex(where: { $0.dateKey == story.dateKey })
        let canStepBack = (index ?? 0) > 0
        let canStepForward = index.map { $0 < cells.count - 1 } ?? false
        let isToday = (story.dateKey == s.today.dateKey)
        let docTotal = story.documents.count + story.weeklyReports.count
        
        return VStack(alignment: .leading, spacing: 14) {
            // Top bar: date + day steppers
            HStack(alignment: .center, spacing: 6) {
                HStack(spacing: 8) {
                    Text(story.dateBadge)
                        .font(.system(size: self.compact ? 13.5 : 14.5, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    
                    if !isToday {
                        Button {
                            withAnimation(DashMotion.spring) {
                                self.selectedYear = Calendar.current.component(.year, from: Date())
                                self.selectedDateKey = s.today.dateKey
                            }
                        } label: {
                            Text("回到今天")
                                .font(.system(size: 10.5, weight: .medium))
                                .foregroundStyle(self.palette.pine)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(self.palette.inset, in: Capsule())
                        }
                        .buttonStyle(PressStyle())
                        .pointerStyle(.link)
                    }
                }
                
                Spacer(minLength: 4)
                
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
            
            Rectangle()
                .fill(self.palette.hairline)
                .frame(height: 1)
            
            // Editorial spine headline
            HStack(alignment: .top, spacing: 10) {
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(self.palette.emerald)
                    .frame(width: 3)
                
                Text(story.headline)
                    .font(.system(size: self.compact ? 14 : 15.5, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineSpacing(4.5)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .fixedSize(horizontal: false, vertical: true)
            
            if isSidePillar {
                Spacer(minLength: 10)
            }
            
            // Bottom-anchored Plane-2 recessed Day Footprints well
            VStack(alignment: .leading, spacing: 9) {
                DotCompositionBar(
                    primaryRatio: story.totalChars > 0 ? Double(story.handTypedChars) / Double(story.totalChars) : 0,
                    secondaryRatio: story.totalChars > 0 ? Double(story.aiChars) / Double(story.totalChars) : 0,
                    palette: self.palette
                )
                
                LazyVGrid(
                    columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)],
                    spacing: 8
                ) {
                    MiniStatTile(label: "手写字数", value: "\(Self.int(story.handTypedChars)) 字", palette: self.palette)
                    MiniStatTile(label: "AI 帮补", value: "\(Self.int(story.aiChars)) 字", palette: self.palette)
                    MiniStatTile(label: "保存打磨", value: "\(story.savedCount) 次", palette: self.palette)
                    MiniStatTile(label: "涉及文档", value: "\(docTotal) 篇", palette: self.palette)
                }
            }
        }
        .frame(maxHeight: isSidePillar ? .infinity : nil, alignment: .topLeading)
        .modifier(DashCard(palette: self.palette, padding: self.cardPadding, cornerRadius: self.cornerRadius))
        .id(story.dateKey)
        .transition(.opacity)
    }
    
    
    private struct DocumentEntry: Identifiable {
        
        enum Payload {
            case document(StoredDocumentRecord)
            case weeklyReport(StoredWeeklyReport)
        }
        
        let id: String
        let title: String
        let subtitle: String
        let countLabel: String
        let symbolName: String
        let payload: Payload
    }
    
    
    private func openDocumentEntry(_ entry: DocumentEntry) {
        
        switch entry.payload {
            case .document(let record):
                if let onOpenDocument = self.onOpenDocument {
                    onOpenDocument(record)
                } else {
                    AnalyticsDashboardWindowController.shared.openDocument(record)
                }
            case .weeklyReport(let report):
                if let onOpenWeeklyReport = self.onOpenWeeklyReport {
                    onOpenWeeklyReport(report)
                } else {
                    AnalyticsDashboardWindowController.shared.openWeeklyReport(report)
                }
        }
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
                symbolName: isCreatedSameDay ? "doc.badge.plus" : "doc.text",
                payload: .document(doc)
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
                symbolName: "calendar",
                payload: .weeklyReport(report)
            ))
        }
        return items
    }
    
    
    private struct TransactionDocRow: View {
        
        let entry: DocumentEntry
        let palette: DashPalette
        let onOpen: () -> Void
        @State private var isHovered = false
        
        var body: some View {
            Button(action: self.onOpen) {
                HStack(spacing: 10) {
                    Image(systemName: self.entry.symbolName)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(self.isHovered ? self.palette.pine : .secondary)
                        .frame(width: 28, height: 28)
                        .background(self.palette.card, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(self.palette.hairline, lineWidth: 0.75)
                        )
                    
                    Text(self.entry.title)
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    
                    Spacer(minLength: 6)
                    
                    HStack(spacing: 4) {
                        Text(self.entry.countLabel)
                            .font(.system(size: 11, weight: .medium))
                            .monospacedDigit()
                            .foregroundStyle(self.isHovered ? .primary : .secondary)
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 9.5, weight: .semibold))
                            .foregroundStyle(self.isHovered ? self.palette.pine : .secondary)
                            .opacity(self.isHovered ? 0.9 : 0.35)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(self.isHovered ? self.palette.insetHover : self.palette.inset)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .strokeBorder(self.isHovered ? self.palette.hairlineStrong : self.palette.hairline, lineWidth: 0.75)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(PressStyle())
            .pointerStyle(.link)
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
                            .fill(
                                LinearGradient(
                                    colors: [self.palette.topSpecular, .clear],
                                    startPoint: .top,
                                    endPoint: .center
                                )
                            )
                    )
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
    
    case ink
    case sage
}


/// Bento KPI card: title + ↗ action circle + hero value + 7-day pixel-matrix sparkbar.
private struct KPICard: View {
    
    let title: String
    let value: String
    let unit: String
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
                            case .ink:
                                color = (col == cols - 1) ? self.palette.pine : (frac >= 0.65 ? self.palette.pine.opacity(0.75) : self.palette.mint)
                            case .sage:
                                color = self.palette.matrixStep(fraction: frac, isPeak: row == rows - 1 && val >= peak * 0.92)
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
        
        let activeDays = self.days.filter { $0.typed > 0 }.count
        let peak = self.days.map(\.typed).max() ?? 0
        
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 10) {
                Text("近两周手写节奏")
                    .font(.system(size: 14, weight: .semibold))
                
                if let idx = self.hoveredIndex, self.days.indices.contains(idx) {
                    let d = self.days[idx]
                    Text("\(Self.shortDate(d.date)) · \(AnalyticsDashboardView.int(d.typed)) 字")
                        .font(.system(size: 12))
                        .monospacedDigit()
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }
                
                Spacer(minLength: 8)
                
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
                Text("近 7 天帮写占比")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                IconButton(systemImage: "xmark", palette: self.palette, isClose: true, action: self.onClose)
            }
            
            HStack(alignment: .center, spacing: self.compact ? 16 : 28) {
                VStack(spacing: 10) {
                    DotArcGauge(
                        primaryShare: produced7 > 0 ? Double(typed7) / Double(produced7) : 0,
                        totalLabel: AnalyticsDashboardView.int(produced7),
                        palette: self.palette
                    )
                    .frame(width: self.compact ? 186 : 214, height: self.compact ? 104 : 118)
                    
                    HStack(spacing: 16) {
                        HStack(spacing: 5) {
                            Circle().fill(self.palette.pine).frame(width: 7, height: 7)
                            Text("手写 \(handPct)%")
                        }
                        HStack(spacing: 5) {
                            Circle().fill(self.palette.mint).frame(width: 7, height: 7)
                            Text("AI \(aiPct)%")
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
            
            VStack(spacing: 2) {
                Image(systemName: "sparkles")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(self.palette.emerald)
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


/// Panel 3: 12-week miniature AI consumption heatmap + Input/Output token composition + ranked Model/Feature breakdowns.
private struct ConsumptionDetailPanel: View {
    
    let aiHeatmap: RollingHeatmapData
    let slice: DashboardSnapshot.AISlice
    @Binding var aiRange: AnalyticsDashboardView.AIRange
    let compact: Bool
    let palette: DashPalette
    let onClose: () -> Void
    
    @State private var hoveredDay: HeatmapDayCell?
    
    
    var body: some View {
        
        let totals = self.slice.totals
        let totalTokens = max(1, totals.inputTokens + totals.outputTokens)
        let inputShare = Double(totals.inputTokens) / Double(totalTokens)
        let outputShare = Double(totals.outputTokens) / Double(totalTokens)
        
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 10) {
                Text("AI 消耗热力图")
                    .font(.system(size: 14, weight: .semibold))
                
                if let cell = self.hoveredDay {
                    let dayTokens = cell.inputTokens + cell.outputTokens
                    Text("\(Self.shortDate(cell.date)) · \(AnalyticsManager.formatCompactTokenCount(dayTokens)) Tokens")
                        .font(.system(size: 12))
                        .monospacedDigit()
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }
                
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
            
            if self.compact {
                VStack(alignment: .leading, spacing: 12) {
                    self.heatmapColumn(totals: totals, inputShare: inputShare, outputShare: outputShare)
                    self.rankingsRow
                }
            } else {
                HStack(alignment: .top, spacing: 16) {
                    self.heatmapColumn(totals: totals, inputShare: inputShare, outputShare: outputShare)
                        .frame(width: 310)
                    
                    self.rankingsRow
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }
    
    
    private func heatmapColumn(
        totals: AIUsageTotals,
        inputShare: Double,
        outputShare: Double
    ) -> some View {
        
        VStack(alignment: .leading, spacing: 10) {
            MiniAIHeatmap(heatmap: self.aiHeatmap, palette: self.palette, hovered: self.$hoveredDay)
            
            VStack(alignment: .leading, spacing: 6) {
                DotCompositionBar(
                    primaryRatio: totals.requests > 0 ? inputShare : 0,
                    secondaryRatio: totals.requests > 0 ? outputShare : 0,
                    palette: self.palette
                )
                
                HStack(spacing: 10) {
                    HStack(spacing: 4) {
                        Circle().fill(self.palette.pine).frame(width: 6, height: 6)
                        Text("输入 \(AnalyticsManager.formatCompactTokenCount(totals.inputTokens))")
                    }
                    HStack(spacing: 4) {
                        Circle().fill(self.palette.mint).frame(width: 6, height: 6)
                        Text("输出 \(AnalyticsManager.formatCompactTokenCount(totals.outputTokens))")
                    }
                    Spacer()
                    if self.slice.latencyMs > 0 {
                        Text("\(self.slice.latencyMs)ms")
                            .foregroundStyle(.tertiary)
                    }
                }
                .font(.system(size: 11))
                .monospacedDigit()
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(self.palette.inset, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(self.palette.hairline, lineWidth: 0.75)
            )
        }
    }
    
    
    private var rankingsRow: some View {
        
        HStack(alignment: .top, spacing: 12) {
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
    
    
    private static func shortDate(_ date: Date) -> String {
        
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M 月 d 日"
        return formatter.string(from: date)
    }
}


/// Compact 12-week Monday-first AI token consumption heatmap embedded in ConsumptionDetailPanel.
private struct MiniAIHeatmap: View {
    
    let heatmap: RollingHeatmapData
    let palette: DashPalette
    @Binding var hovered: HeatmapDayCell?
    
    
    var body: some View {
        
        VStack(alignment: .leading, spacing: 8) {
            ActivityHeatmapCanvas(
                weeks: self.heatmap.weeks,
                monthLabels: self.heatmap.monthLabels.map { .init(weekIndex: $0.weekIndex, text: $0.label) },
                selectedKey: nil,
                hideOutOfYear: false,
                maxCellSize: 16,
                minGap: 3,
                palette: self.palette,
                hovered: self.$hovered,
                onSelect: nil
            )
            
            HStack(spacing: 4) {
                Spacer()
                Text("少")
                    .font(.system(size: 9.5))
                    .foregroundStyle(.secondary)
                ForEach(0..<5, id: \.self) { level in
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(self.palette.heat(level))
                        .frame(width: 9, height: 9)
                }
                Text("多")
                    .font(.system(size: 9.5))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .background(self.palette.inset, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(self.palette.hairline, lineWidth: 0.75)
        )
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
                            .foregroundStyle(.secondary)
                            .frame(width: 24, height: 24)
                            .background(self.palette.card, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                        
                        Text(row.name)
                            .font(.system(size: 12, weight: .medium))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        
                        Spacer(minLength: 4)
                        
                        HStack(spacing: 2) {
                            ForEach(0..<8, id: \.self) { idx in
                                let dotColor: Color = idx < activeDots
                                    ? (idx >= 5 ? self.palette.pine : self.palette.mint)
                                    : self.palette.emptyDot
                                Circle()
                                    .fill(dotColor)
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
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(self.palette.hairline, lineWidth: 0.75)
        )
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


// MARK: - Calendar-Year Heatmap & Shared Grid Canvas

/// Calendar-year Monday-first activity heatmap with year switcher (< YYYY >).
private struct YearlyHeatmapCard: View {
    
    let heatmap: YearlyHeatmapData
    let availableYears: [Int]
    @Binding var selectedYear: Int
    let selectedKey: String
    let palette: DashPalette
    let compact: Bool
    let padding: CGFloat
    let cornerRadius: CGFloat
    let onSelect: (HeatmapDayCell) -> Void
    
    @State private var hovered: HeatmapDayCell?
    
    
    var body: some View {
        
        let currentIndex = self.availableYears.firstIndex(of: self.selectedYear)
        let canStepBack = currentIndex.map { $0 > 0 } ?? false
        let canStepForward = currentIndex.map { $0 < self.availableYears.count - 1 } ?? false
        
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 10) {
                Text(self.statusLine)
                    .font(.system(size: 12.5, weight: self.hovered == nil ? .regular : .medium))
                    .monospacedDigit()
                    .foregroundStyle(self.hovered == nil ? .secondary : .primary)
                    .lineLimit(1)
                
                Spacer(minLength: 8)
                
                HStack(spacing: 4) {
                    StepCircleButton(systemImage: "chevron.left", isEnabled: canStepBack, palette: self.palette) {
                        if let currentIndex, self.availableYears.indices.contains(currentIndex - 1) {
                            withAnimation(DashMotion.spring) {
                                self.selectedYear = self.availableYears[currentIndex - 1]
                            }
                        }
                    }
                    .help("上一年")
                    
                    Text("\(String(self.heatmap.year)) 年")
                        .font(.system(size: 12, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(.primary)
                        .frame(minWidth: 52)
                    
                    StepCircleButton(systemImage: "chevron.right", isEnabled: canStepForward, palette: self.palette) {
                        if let currentIndex, self.availableYears.indices.contains(currentIndex + 1) {
                            withAnimation(DashMotion.spring) {
                                self.selectedYear = self.availableYears[currentIndex + 1]
                            }
                        }
                    }
                    .help("下一年")
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 3)
                .background(self.palette.inset, in: Capsule())
                .overlay(
                    Capsule()
                        .strokeBorder(self.palette.hairline, lineWidth: 0.75)
                )
            }
            
            ActivityHeatmapCanvas(
                weeks: self.heatmap.weeks,
                monthLabels: self.heatmap.monthLabels.map { .init(weekIndex: $0.weekIndex, text: "\($0.month)月") },
                selectedKey: self.selectedKey,
                hideOutOfYear: true,
                maxCellSize: self.compact ? 11.5 : 14,
                minGap: self.compact ? 2 : 2.5,
                palette: self.palette,
                hovered: self.$hovered,
                onSelect: self.onSelect
            )
            
            HStack(spacing: 4) {
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
            return "\(Self.shortDate(cell.date)) · \(AnalyticsDashboardView.int(total)) 字"
        }
        let charsText = self.heatmap.totalTypedChars >= 1000
            ? String(format: "%.1fk", Double(self.heatmap.totalTypedChars) / 1000.0)
            : AnalyticsDashboardView.int(self.heatmap.totalTypedChars)
        return "\(charsText) 字 · \(self.heatmap.activeDays) 天"
    }
    
    
    private static func shortDate(_ date: Date) -> String {
        
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M 月 d 日 EEE"
        return formatter.string(from: date)
    }
}


/// Shared Monday-first Canvas heatmap renderer powering both YearlyHeatmapCard and MiniAIHeatmap.
private struct ActivityHeatmapCanvas: View {
    
    struct MonthMarker {
        let weekIndex: Int
        let text: String
    }
    
    let weeks: [[HeatmapDayCell]]
    let monthLabels: [MonthMarker]
    let selectedKey: String?
    let hideOutOfYear: Bool
    let maxCellSize: CGFloat
    let minGap: CGFloat
    let palette: DashPalette
    @Binding var hovered: HeatmapDayCell?
    let onSelect: ((HeatmapDayCell) -> Void)?
    
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
        
        let labelColumn: CGFloat = 15
        let labelGap: CGFloat = 6
        let monthBand: CGFloat = 16
        let weekCount = CGFloat(max(1, self.weeks.count))
        let gridWidth = max(140, width - labelColumn - labelGap)
        let gap: CGFloat = self.weeks.count <= 20 ? max(self.minGap, 3) : (gridWidth > 620 ? max(self.minGap, 2.5) : self.minGap)
        let raw = (gridWidth - gap * (weekCount - 1)) / weekCount
        let cell = max(6.5, min(self.maxCellSize, (raw * 2).rounded(.down) / 2))
        
        return Layout(
            gridX: labelColumn + labelGap,
            gridY: monthBand,
            cell: cell,
            gap: gap,
            radius: max(2, min(4, cell * 0.25)),
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
              self.weeks.indices.contains(week),
              self.weeks[week].indices.contains(row)
        else { return nil }
        let cell = self.weeks[week][row]
        guard !cell.isFuture, (!self.hideOutOfYear || !cell.isOutOfYear) else { return nil }
        return cell
    }
    
    
    var body: some View {
        
        let resolvedWidth = self.width > 0 ? self.width : 600
        let layout = self.layout(for: resolvedWidth)
        
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
            if let onSelect = self.onSelect, let target = self.cell(at: point, layout: layout) {
                onSelect(target)
            }
        }
        .pointerStyle(self.onSelect != nil && self.hovered != nil ? .link : nil)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { newWidth in
            if abs(newWidth - self.width) > 0.5 {
                self.width = newWidth
            }
        }
    }
    
    
    private func draw(in context: inout GraphicsContext, layout: Layout) {
        
        let todayKey = AnalyticsManager.dateKey()
        
        var lastLabelX: CGFloat = -40
        for label in self.monthLabels {
            let x = layout.gridX + CGFloat(label.weekIndex) * layout.pitch
            guard x - lastLabelX >= 22 else { continue }
            lastLabelX = x
            let text = context.resolve(Text(label.text).font(.system(size: 9.5, weight: .medium)).foregroundStyle(.secondary))
            context.draw(text, at: CGPoint(x: x, y: 0), anchor: .topLeading)
        }
        
        for (row, name) in [(0, "一"), (2, "三"), (4, "五")] {
            let text = context.resolve(Text(name).font(.system(size: 9)).foregroundStyle(.secondary))
            let y = layout.gridY + CGFloat(row) * layout.pitch + layout.cell / 2
            context.draw(text, at: CGPoint(x: 0, y: y), anchor: .leading)
        }
        
        var todayRect: CGRect?
        var hoveredRect: CGRect?
        var selectedRect: CGRect?
        
        for (week, days) in self.weeks.enumerated() {
            for (row, cell) in days.enumerated() where !cell.isFuture && (!self.hideOutOfYear || !cell.isOutOfYear) {
                let rect = CGRect(
                    x: layout.gridX + CGFloat(week) * layout.pitch,
                    y: layout.gridY + CGFloat(row) * layout.pitch,
                    width: layout.cell,
                    height: layout.cell
                )
                context.fill(
                    Path(roundedRect: rect, cornerRadius: layout.radius, style: .continuous),
                    with: .color(self.palette.heat(cell.level))
                )
                
                if cell.dateKey == todayKey { todayRect = rect }
                if cell.id == self.hovered?.id { hoveredRect = rect }
                if cell.dateKey == self.selectedKey { selectedRect = rect }
            }
        }
        
        if let rect = todayRect, self.selectedKey != todayKey, self.hovered?.dateKey != todayKey {
            context.stroke(
                Path(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), cornerRadius: layout.radius, style: .continuous),
                with: .color(self.palette.emerald.opacity(0.6)),
                lineWidth: 1.1
            )
        }
        if let rect = hoveredRect, self.hovered?.dateKey != self.selectedKey {
            context.stroke(
                Path(roundedRect: rect.insetBy(dx: -1.3, dy: -1.3), cornerRadius: layout.radius + 1.2, style: .continuous),
                with: .color(self.palette.emerald.opacity(0.75)),
                lineWidth: 1.3
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
