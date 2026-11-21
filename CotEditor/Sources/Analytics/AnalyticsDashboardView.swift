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


/// Resolves live editorial palette tokens from `StudioPaletteManager` for consistent luxury aesthetics.
private struct DashPalette: Sendable {
    
    let isDark: Bool
    let tokens: StudioColorTokens
    
    @MainActor init(_ scheme: ColorScheme, tokens: StudioColorTokens? = nil) {
        self.isDark = (scheme == .dark)
        self.tokens = tokens ?? StudioPaletteManager.shared.tokens(isDark: scheme == .dark)
    }
    
    var canvasTop: Color { self.tokens.canvasTop }
    var canvasBottom: Color { self.tokens.canvasBottom }
    var mistMint: Color { self.tokens.mistAccent }
    
    var card: Color { self.tokens.card }
    var cardShadow: Color { self.tokens.cardShadow }
    var inset: Color { self.tokens.inset }
    var insetHover: Color { self.tokens.insetHover }
    var hairline: Color { self.tokens.hairline }
    var hairlineStrong: Color { self.tokens.hairlineStrong }
    var topSpecular: Color { self.tokens.topSpecular }
    var architecturalDot: Color { self.tokens.architecturalDot }
    
    var pine: Color { self.tokens.primaryInk }
    var emerald: Color { self.tokens.accentText }
    var accentFill: Color { self.tokens.accent }
    var onAccentInk: Color { self.tokens.onAccentInk }
    var mint: Color { self.tokens.secondaryAccent }
    var paleMint: Color { self.tokens.paleAccent }
    var emptyDot: Color { self.tokens.emptyDot }
    var positivePillBg: Color { self.tokens.positivePillBg }
    var neutralPillBg: Color { self.tokens.neutralPillBg }
    
    
    func heat(_ level: Int) -> Color {
        
        switch level {
            case 4: self.tokens.heat4
            case 3: self.tokens.heat3
            case 2: self.tokens.heat2
            case 1: self.tokens.heat1
            default: self.emptyDot
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
        var modelPerformance: [ModelPerformanceSummary]
        var features: [FeatureUsageSummary]
        var latencyMs: Int
    }
    
    var today: DailyWritingStats
    var todayHourlyPulse: [Int]
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
    var recentManuscripts: [TouchedManuscriptItem]
    
    
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
            todayHourlyPulse: analytics.hourlyWritingPulse(for: today.dateKey),
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
                modelPerformance: analytics.modelPerformanceSummaries(forTodayOnly: true),
                features: analytics.todayFeatureDistribution(),
                latencyMs: analytics.averageLatencyMs(forTodayOnly: true)
            ),
            ai30: AISlice(
                totals: analytics.aiUsageTotals(forTodayOnly: false, days: 30),
                models: analytics.modelDistribution(days: 30),
                modelPerformance: analytics.modelPerformanceSummaries(forTodayOnly: false, days: 30),
                features: analytics.featureDistribution(days: 30),
                latencyMs: analytics.averageLatencyMs(forTodayOnly: false, days: 30)
            ),
            recentManuscripts: analytics.recentTouchedManuscripts(days: 7, limit: 6)
        )
    }
}


// MARK: - Dashboard

/// Architectural Bento writing dashboard with distinct achievement KPI cards,
/// candid colloquial bullet-point AI summary, and tactile Studio Manuscript Folio gallery.
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
    @State private var studioPalette = StudioPaletteManager.shared
    @State private var snapshot: DashboardSnapshot?
    @State private var expandedKPI: KPIKind?
    @State private var aiRange: AIRange = .thirtyDays
    @State private var selectedYear: Int = Calendar.current.component(.year, from: Date())
    @State private var selectedDateKey: String = AnalyticsManager.dateKey()
    @State private var forceRecentManuscripts = false
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
    
    
    private var palette: DashPalette {
        DashPalette(
            self.colorScheme,
            tokens: self.studioPalette.tokens(isDark: self.colorScheme == .dark)
        )
    }
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
        let isTodaySelected = (activeCell.dateKey == s.today.dateKey)
        
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
                HStack(alignment: .top, spacing: self.gap) {
                    VStack(alignment: .leading, spacing: self.gap) {
                        self.yearlyHeatmapCard(s, activeCell: activeCell)
                        
                        self.manuscriptFolioCard(s, activeCell: activeCell, isTodaySelected: isTodaySelected)
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    
                    self.candidSummaryPillar(story, activeCell: activeCell, snapshot: s, isSidePillar: true)
                        .frame(width: 332, alignment: .topLeading)
                }
                .fixedSize(horizontal: false, vertical: true)
            } else {
                self.yearlyHeatmapCard(s, activeCell: activeCell)
                
                self.manuscriptFolioCard(s, activeCell: activeCell, isTodaySelected: isTodaySelected)
                
                self.candidSummaryPillar(story, activeCell: activeCell, snapshot: s, isSidePillar: false)
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
                self.forceRecentManuscripts = false
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
    
    
    // MARK: Header
    
    private var header: some View {
        
        let profile = self.profileManager.activeProfile
        
        return ZStack(alignment: .top) {
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
            
            HStack(alignment: .center) {
                if let onDismiss = self.onDismiss {
                    BackPillButton(palette: self.palette, action: onDismiss)
                        .help(AppLanguage.text("返回编辑器 (Esc)", en: "Back to Editor (Esc)"))
                }
                
                Spacer()
                
                self.paletteQuickSwitcherPill
            }
        }
    }
    
    
    private var paletteQuickSwitcherPill: some View {
        let presets: [StudioPaletteID] = self.studioPalette.selectedID == .custom
            ? StudioPaletteID.allCases
            : [.ultraViolet, .signalCrimson, .matchaParchment, .pineCeladon]
        
        return HStack(spacing: 6) {
            ForEach(presets) { preset in
                let triad = self.studioPalette.triad(for: preset)
                let isSelected = (self.studioPalette.selectedID == preset)
                Button {
                    withAnimation(DashMotion.spring) {
                        self.studioPalette.selectPalette(preset)
                    }
                } label: {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(StudioPaletteManager.swiftUIColor(hex: triad.accentHex))
                            .frame(width: 9, height: 9)
                            .overlay(
                                Circle()
                                    .strokeBorder(Color.white.opacity(isSelected ? 0.95 : 0.25), lineWidth: isSelected ? 1.5 : 0.75)
                            )
                        
                        if isSelected {
                            Text(preset.displayName)
                                .font(.system(size: 10.5, weight: .semibold))
                                .foregroundStyle(self.palette.pine)
                                .lineLimit(1)
                        }
                    }
                    .padding(.horizontal, isSelected ? 7 : 3)
                    .frame(height: 22)
                    .background(
                        Capsule()
                            .fill(isSelected ? self.palette.positivePillBg : Color.clear)
                    )
                }
                .buttonStyle(PressStyle())
                .pointerStyle(.link)
                .help(preset.displayName)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
            Capsule()
                .fill(self.palette.card)
                .shadow(color: self.palette.cardShadow, radius: 8, y: 2)
        )
    }
    
    
    // MARK: 3 Distinct Top KPI Cards (Zero Duplicated Sparkbars or Arrow Circles)
    
    private func kpiRow(_ s: DashboardSnapshot) -> some View {
        
        let today = s.today
        let equiv = AnalyticsManager.tangibleWritingEquivalent(for: today.typedChars)
        let savedText = Self.formatSavedTime(chars: today.aiCompletedChars)
        let totalProduced = today.typedChars + today.aiCompletedChars
        let handShare = totalProduced > 0 ? Double(today.typedChars) / Double(totalProduced) : 0
        let totalTokens = today.inputTokens + today.outputTokens
        let inputShare = totalTokens > 0 ? Double(today.inputTokens) / Double(totalTokens) : 0
        
        return HStack(alignment: .top, spacing: self.gap) {
            // 1. 今日手写: Tangible Milestone Pill + 24h Circadian Skyline Curve
            DistinctKPICard(
                title: "今日手写",
                badgeText: equiv.badge,
                value: Self.int(today.typedChars),
                unit: "字",
                isExpanded: self.expandedKPI == .typed,
                compact: self.compact,
                padding: self.cardPadding,
                cornerRadius: self.cornerRadius,
                palette: self.palette,
                action: { self.toggle(.typed) }
            ) {
                CircadianMiniSparkline(hourly: s.todayHourlyPulse, palette: self.palette)
                    .frame(height: 22)
            }
            
            // 2. AI 帮写: Time Saved Pill + Dual-Tone Human vs AI Authorship Ratio Bar
            DistinctKPICard(
                title: "AI 帮写",
                badgeText: today.aiCompletionAccepts > 0 ? "省下 \(savedText) · \(today.aiCompletionAccepts) Tab" : "待唤醒续写",
                value: Self.int(today.aiCompletedChars),
                unit: "字",
                isExpanded: self.expandedKPI == .completion,
                compact: self.compact,
                padding: self.cardPadding,
                cornerRadius: self.cornerRadius,
                palette: self.palette,
                action: { self.toggle(.completion) }
            ) {
                VStack(alignment: .leading, spacing: 5) {
                    TwinRatioCapsuleBar(
                        leftRatio: handShare,
                        leftColor: self.palette.pine,
                        rightColor: self.palette.emerald,
                        emptyColor: self.palette.emptyDot
                    )
                    
                    HStack {
                        Text(totalProduced > 0 ? "手写 \(Int((handShare * 100).rounded()))%" : "手写主笔")
                        Spacer()
                        Text(totalProduced > 0 ? "AI \(max(0, 100 - Int((handShare * 100).rounded())))%" : "AI 辅助")
                    }
                    .font(.system(size: 10, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                }
            }
            
            // 3. AI 用量: Local Zero-Cost Hits Pill + Input / Output Token Balance Bar
            DistinctKPICard(
                title: "AI 用量",
                badgeText: today.localHits > 0 ? "本地省流 \(today.localHits) 次" : "\(today.aiRequests) 次调用",
                value: AnalyticsManager.formatCompactTokenCount(today.totalTokens),
                unit: "Tokens",
                isExpanded: self.expandedKPI == .consumption,
                compact: self.compact,
                padding: self.cardPadding,
                cornerRadius: self.cornerRadius,
                palette: self.palette,
                action: { self.toggle(.consumption) }
            ) {
                VStack(alignment: .leading, spacing: 5) {
                    TwinRatioCapsuleBar(
                        leftRatio: inputShare,
                        leftColor: self.palette.emerald,
                        rightColor: self.palette.mint,
                        emptyColor: self.palette.emptyDot
                    )
                    
                    HStack {
                        Text("入 \(AnalyticsManager.formatCompactTokenCount(today.inputTokens))")
                        Spacer()
                        Text("出 \(AnalyticsManager.formatCompactTokenCount(today.outputTokens))")
                    }
                    .font(.system(size: 10, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                }
            }
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
                    TypedDetailPanel(
                        today: s.today,
                        hourlyPulse: s.todayHourlyPulse,
                        analytics: self.analytics,
                        compact: self.compact,
                        palette: self.palette
                    ) {
                        withAnimation(DashMotion.standard) { self.expandedKPI = nil }
                    }
                case .completion:
                    CompletionDetailPanel(
                        days: s.days7,
                        series7: s.series7,
                        today: s.today,
                        compact: self.compact,
                        palette: self.palette
                    ) {
                        withAnimation(DashMotion.standard) { self.expandedKPI = nil }
                    }
                case .consumption:
                    ConsumptionDetailPanel(
                        aiHeatmap: s.aiHeatmap12,
                        slice: (self.aiRange == .today) ? s.aiToday : s.ai30,
                        savedSummary: self.analytics.estimatedTokensSavedByLocalHits(forTodayOnly: self.aiRange == .today, days: 30),
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
    
    
    // MARK: Full-Width Studio Manuscript Folio Grid (这几天动过的文档)
    
    private func manuscriptFolioCard(
        _ s: DashboardSnapshot,
        activeCell: HeatmapDayCell,
        isTodaySelected: Bool
    ) -> some View {
        
        let showRecent = isTodaySelected || self.forceRecentManuscripts
        let items: [TouchedManuscriptItem] = showRecent
            ? s.recentManuscripts
            : self.analytics.dayTouchedManuscripts(for: activeCell, limit: 6)
        let maxChars = max(1, items.map(\.charCount).max() ?? 1)
        let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]
        
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 8) {
                Text(showRecent ? "这几天动过的文档" : "这天动过的文档")
                    .font(.system(size: 13.5, weight: .semibold))
                
                if !items.isEmpty {
                    Text(showRecent ? "近 7 天 · \(items.count) 篇" : "\(items.count) 篇")
                        .font(.system(size: 10.5, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2.5)
                        .background(self.palette.neutralPillBg, in: Capsule())
                }
                
                Spacer()
                
                if !isTodaySelected {
                    Button {
                        withAnimation(DashMotion.spring) {
                            self.forceRecentManuscripts.toggle()
                        }
                    } label: {
                        Text(self.forceRecentManuscripts ? "看当日文档" : "看近 7 天文档")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(self.palette.emerald)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 3.5)
                            .background(self.palette.positivePillBg, in: Capsule())
                    }
                    .buttonStyle(PressStyle())
                    .pointerStyle(.link)
                }
            }
            
            if items.isEmpty {
                HStack(spacing: 10) {
                    ManuscriptFolioIcon(kind: .plainText, isCreatedToday: false, palette: self.palette)
                        .scaleEffect(0.75)
                    Text(showRecent ? "最近 7 天还没有保存过手稿，写两行试试？" : "这天没有留下文档改动记录")
                        .font(.system(size: 12.5))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity)
                .background(self.palette.inset, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(self.palette.hairline, lineWidth: 0.75)
                )
            } else {
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(items) { item in
                        ManuscriptFolioTile(
                            item: item,
                            maxChars: maxChars,
                            palette: self.palette
                        ) {
                            self.openManuscriptItem(item)
                        }
                    }
                }
            }
        }
        .modifier(DashCard(palette: self.palette, padding: self.cardPadding, cornerRadius: self.cornerRadius))
    }
    
    
    // MARK: Right Pillar — Candid Plain-Spoken Bullet Summary (今日总结)
    
    private func candidSummaryPillar(
        _ story: DailyHumanStory,
        activeCell: HeatmapDayCell,
        snapshot s: DashboardSnapshot,
        isSidePillar: Bool
    ) -> some View {
        
        let cells = s.orderedCells
        let index = cells.firstIndex(where: { $0.dateKey == story.dateKey })
        let canStepBack = (index ?? 0) > 0
        let canStepForward = index.map { $0 < cells.count - 1 } ?? false
        let isToday = (story.dateKey == s.today.dateKey)
        let bulletPoints = self.analytics.candidDailyTakePoints(
            for: activeCell,
            baselineDailyChars: s.typedBaseline7
        )
        
        return VStack(alignment: .leading, spacing: 14) {
            // Top bar: date + AI点评 refresh + day steppers
            HStack(alignment: .center, spacing: 6) {
                HStack(spacing: 7) {
                    Text(story.dateBadge)
                        .font(.system(size: self.compact ? 13.5 : 14.5, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    
                    if !isToday {
                        Button {
                            withAnimation(DashMotion.spring) {
                                self.selectedYear = Calendar.current.component(.year, from: Date())
                                self.selectedDateKey = s.today.dateKey
                                self.forceRecentManuscripts = false
                            }
                        } label: {
                            Text("回今天")
                                .font(.system(size: 10.5, weight: .medium))
                                .foregroundStyle(self.palette.pine)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(self.palette.inset, in: Capsule())
                        }
                        .buttonStyle(PressStyle())
                        .pointerStyle(.link)
                    }
                }
                
                Spacer(minLength: 4)
                
                if isToday {
                    Button {
                        Task {
                            await self.analytics.refreshDailyDigest(force: true)
                        }
                    } label: {
                        HStack(spacing: 4) {
                            if self.analytics.isSummarizingDigest {
                                ProgressView().controlSize(.mini)
                            } else {
                                Image(systemName: "sparkles")
                                    .font(.system(size: 10, weight: .semibold))
                            }
                            Text("AI 锐评")
                                .font(.system(size: 10.5, weight: .semibold))
                        }
                        .foregroundStyle(self.palette.emerald)
                        .padding(.horizontal, 8)
                        .frame(height: 24)
                        .background(self.palette.positivePillBg, in: Capsule())
                    }
                    .buttonStyle(PressStyle())
                    .pointerStyle(.link)
                    .disabled(self.analytics.isSummarizingDigest)
                    .help("让 AI 用人话再锐评一下今天")
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
            
            Rectangle()
                .fill(self.palette.hairline)
                .frame(height: 1)
            
            // Candid, crisp, numbered vernacular points (zero meaningless squares, zero borderLeft!)
            VStack(alignment: .leading, spacing: 14) {
                ForEach(Array(bulletPoints.enumerated()), id: \.offset) { idx, point in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(String(format: "%02d", idx + 1))
                            .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                            .foregroundStyle(self.palette.emerald)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(self.palette.positivePillBg, in: Capsule())
                        
                        Text(point)
                            .font(.system(size: self.compact ? 13 : 13.8, weight: .regular))
                            .foregroundStyle(.primary)
                            .lineSpacing(4.5)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            
            if isToday, let err = self.analytics.digestErrorMessage, !err.isEmpty {
                Text(err)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
            }
            
            if isSidePillar {
                Spacer(minLength: 4)
            }
        }
        .frame(maxHeight: isSidePillar ? .infinity : nil, alignment: .topLeading)
        .modifier(DashCard(palette: self.palette, padding: self.cardPadding, cornerRadius: self.cornerRadius))
        .id(story.dateKey)
        .transition(.opacity)
    }
    
    
    private func openManuscriptItem(_ item: TouchedManuscriptItem) {
        
        switch item.payload {
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
    
    
    // MARK: Formatting
    
    fileprivate static func int(_ value: Int) -> String {
        
        value.formatted(.number.grouping(.automatic))
    }
    
    
    fileprivate static func formatSavedTime(chars: Int) -> String {
        
        let seconds = Int((Double(chars) * 0.48).rounded())
        if seconds < 60 {
            return "\(max(1, seconds)) 秒"
        }
        let mins = seconds / 60
        let remSec = seconds % 60
        return remSec > 0 ? "\(mins) 分 \(remSec) 秒" : "\(mins) 分钟"
    }
    
    
    private static func todayTitle() -> String {
        
        let formatter = DateFormatter()
        let isEn = (AppLanguage.current == .english)
        formatter.locale = Locale(identifier: isEn ? "en_US" : "zh_CN")
        formatter.dateFormat = isEn ? "EEEE, MMM d" : "M 月 d 日 · EEEE"
        return formatter.string(from: Date())
    }
}


// MARK: - Top KPI Card Components

private struct DistinctKPICard<Accessory: View>: View {
    
    let title: String
    let badgeText: String
    let value: String
    let unit: String
    let isExpanded: Bool
    let compact: Bool
    let padding: CGFloat
    let cornerRadius: CGFloat
    let palette: DashPalette
    let action: () -> Void
    @ViewBuilder let accessory: () -> Accessory
    
    @State private var isHovered = false
    
    
    var body: some View {
        
        Button(action: self.action) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center, spacing: 6) {
                    Text(self.title)
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(.secondary)
                    
                    Spacer(minLength: 4)
                    
                    Text(self.badgeText)
                        .font(.system(size: 10.5, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(self.isExpanded ? self.palette.emerald : .secondary)
                        .lineLimit(1)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2.5)
                        .background(
                            self.isExpanded ? self.palette.positivePillBg : self.palette.inset,
                            in: Capsule()
                        )
                }
                
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
                    
                    Spacer(minLength: 4)
                }
                
                self.accessory()
            }
            .modifier(DashCard(
                palette: self.palette,
                padding: self.padding,
                cornerRadius: self.cornerRadius,
                isHighlighted: self.isExpanded,
                isHovered: self.isHovered
            ))
            .overlay(alignment: .bottom) {
                if self.isExpanded {
                    Capsule()
                        .fill(self.palette.emerald)
                        .frame(width: 44, height: 2.5)
                        .padding(.bottom, 5)
                }
            }
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


/// 24-hour smooth circadian horizon sparkline unique to the 今日手写 KPI card.
private struct CircadianMiniSparkline: View {
    
    let hourly: [Int]
    let palette: DashPalette
    
    
    var body: some View {
        Canvas { context, size in
            let bins = self.hourly.count == 24 ? self.hourly : Array(repeating: 0, count: 24)
            let peak = max(1, bins.max() ?? 1)
            let count = bins.count
            let stepX = size.width / CGFloat(max(1, count - 1))
            let bottomY = size.height - 2
            let maxAmp = max(6, size.height - 5)
            
            var linePath = Path()
            var fillPath = Path()
            var points: [CGPoint] = []
            for (idx, val) in bins.enumerated() {
                let norm = Double(val) / Double(peak)
                let x = CGFloat(idx) * stepX
                let y = bottomY - CGFloat(norm) * maxAmp
                points.append(CGPoint(x: x, y: y))
            }
            
            if let first = points.first, let last = points.last {
                linePath.move(to: first)
                fillPath.move(to: CGPoint(x: first.x, y: bottomY))
                fillPath.addLine(to: first)
                
                for i in 1..<points.count {
                    let prev = points[i - 1]
                    let curr = points[i]
                    let midX = (prev.x + curr.x) * 0.5
                    linePath.addCurve(to: curr, control1: CGPoint(x: midX, y: prev.y), control2: CGPoint(x: midX, y: curr.y))
                    fillPath.addCurve(to: curr, control1: CGPoint(x: midX, y: prev.y), control2: CGPoint(x: midX, y: curr.y))
                }
                fillPath.addLine(to: CGPoint(x: last.x, y: bottomY))
                fillPath.closeSubpath()
                
                context.fill(
                    fillPath,
                    with: .linearGradient(
                        Gradient(colors: [self.palette.emerald.opacity(0.26), self.palette.emerald.opacity(0.02)]),
                        startPoint: CGPoint(x: 0, y: 0),
                        endPoint: CGPoint(x: 0, y: bottomY)
                    )
                )
                context.stroke(
                    linePath,
                    with: .color(bins.allSatisfy({ $0 == 0 }) ? self.palette.emptyDot : self.palette.emerald),
                    style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round)
                )
                
                if let bestIdx = bins.enumerated().max(by: { $0.element < $1.element })?.offset,
                   bins[bestIdx] > 0,
                   points.indices.contains(bestIdx)
                {
                    let pt = points[bestIdx]
                    let dot = CGRect(x: pt.x - 2.2, y: pt.y - 2.2, width: 4.4, height: 4.4)
                    context.fill(Path(ellipseIn: dot), with: .color(self.palette.pine))
                }
            }
        }
    }
}


private struct TwinRatioCapsuleBar: View {
    
    let leftRatio: Double
    let leftColor: Color
    let rightColor: Color
    let emptyColor: Color
    
    
    var body: some View {
        GeometryReader { proxy in
            let w = max(12, proxy.size.width)
            if self.leftRatio <= 0 && self.leftColor != self.emptyColor {
                Capsule()
                    .fill(self.emptyColor)
                    .frame(width: w, height: 6)
            } else {
                let leftW = max(6, min(w - 6, w * CGFloat(self.leftRatio)))
                HStack(spacing: 2) {
                    Capsule()
                        .fill(self.leftColor)
                        .frame(width: leftW, height: 6)
                    Capsule()
                        .fill(self.rightColor)
                        .frame(maxWidth: .infinity)
                        .frame(height: 6)
                }
            }
        }
        .frame(height: 6)
    }
}


// MARK: - Reimagined High-Achievement Expanded KPI Panels

/// Panel 1 (今日手写): Tangible Achievement Milestone + Personal Best PB + 24-Hour Golden Flow Skyline.
private struct TypedDetailPanel: View {
    
    let today: DailyWritingStats
    let hourlyPulse: [Int]
    let analytics: AnalyticsManager
    let compact: Bool
    let palette: DashPalette
    let onClose: () -> Void
    
    @State private var hoveredHour: Int?
    
    
    var body: some View {
        
        let equiv = AnalyticsManager.tangibleWritingEquivalent(for: self.today.typedChars)
        let pb = self.analytics.personalRecordTypedChars()
        let pbChars = max(self.today.typedChars, pb?.chars ?? 0)
        let isNewPB = (self.today.typedChars > 0 && self.today.typedChars >= (pb?.chars ?? 0))
        let pbRatio = pbChars > 0 ? min(1.0, Double(self.today.typedChars) / Double(pbChars)) : 0
        let percentile = self.analytics.typedPercentile(for: self.today.typedChars)
        let streak = self.analytics.currentWritingStreak
        let peakWindow = self.analytics.peakFlowWindow(for: self.today.dateKey)
        
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 10) {
                Text("字迹成就馆")
                    .font(.system(size: 14, weight: .semibold))
                
                if let hr = self.hoveredHour, self.hourlyPulse.indices.contains(hr) {
                    Text(String(format: "%02d:00–%02d:59 · %d 字", hr, hr, self.hourlyPulse[hr]))
                        .font(.system(size: 12, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(self.palette.pine)
                } else if let peakWindow {
                    Text("\(peakWindow.chronotype) · 黄金时段 \(peakWindow.hourRange)")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(self.palette.emerald)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2.5)
                        .background(self.palette.positivePillBg, in: Capsule())
                }
                
                Spacer(minLength: 8)
                
                IconButton(systemImage: "xmark", palette: self.palette, isClose: true, action: self.onClose)
            }
            
            HStack(alignment: .top, spacing: self.compact ? 14 : 20) {
                // Left: Physical Achievement Equivalence & PB Tracker
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(equiv.badge)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.primary)
                        Text(equiv.detail)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    
                    // PB Progress Gauge
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(isNewPB ? "🎉 已刷新个人单日最高纪录" : "距个人单日巅峰")
                                .font(.system(size: 11.5, weight: .semibold))
                                .foregroundStyle(isNewPB ? self.palette.emerald : .primary)
                            Spacer()
                            if pbChars > 0 {
                                Text("\(AnalyticsDashboardView.int(self.today.typedChars)) / \(AnalyticsDashboardView.int(pbChars))")
                                    .font(.system(size: 11, weight: .medium))
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                            }
                        }
                        
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(self.palette.emptyDot)
                                Capsule()
                                    .fill(isNewPB ? self.palette.emerald : self.palette.pine)
                                    .frame(width: max(6, geo.size.width * CGFloat(pbRatio)))
                            }
                        }
                        .frame(height: 6)
                        
                        if self.today.typedChars > 0 {
                            Text("超过了过去 \(percentile)% 的动笔日")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(10)
                    .background(self.palette.inset, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                    
                    HStack(spacing: 8) {
                        AchievementChip(label: "连续执笔", value: "\(streak) 天", palette: self.palette)
                        AchievementChip(label: "累计字迹", value: AnalyticsManager.formatCompactTokenCount(self.analytics.lifetimeTypedChars), palette: self.palette)
                    }
                }
                .frame(width: self.compact ? 228 : 268)
                
                // Right: 24-Hour Golden Flow Skyline
                HourlyFlowSkylineChart(
                    hourly: self.hourlyPulse,
                    palette: self.palette,
                    hoveredHour: self.$hoveredHour
                )
                .frame(height: 156)
                .frame(maxWidth: .infinity)
            }
        }
    }
}


private struct HourlyFlowSkylineChart: View {
    
    let hourly: [Int]
    let palette: DashPalette
    @Binding var hoveredHour: Int?
    
    
    var body: some View {
        let bins = self.hourly.count == 24 ? self.hourly : Array(repeating: 0, count: 24)
        let peak = max(60, bins.max() ?? 60)
        let peakHour = bins.enumerated().max(by: { $0.element < $1.element })?.offset
        
        GeometryReader { proxy in
            let count = 24
            let gap: CGFloat = 3
            let labelBand: CGFloat = 18
            let barAreaH = max(40, proxy.size.height - labelBand)
            let barW = max(4, (proxy.size.width - gap * CGFloat(count - 1)) / CGFloat(count))
            let pitch = barW + gap
            
            Canvas { context, size in
                for hr in 0..<count {
                    let val = bins[hr]
                    let isHovered = (self.hoveredHour == hr)
                    let isPeak = (val > 0 && peakHour == hr)
                    let ratio = Double(val) / Double(peak)
                    let h = val > 0 ? max(8, barAreaH * CGFloat(ratio)) : 4
                    let x = CGFloat(hr) * pitch
                    let y = barAreaH - h
                    let rect = CGRect(x: x, y: y, width: barW, height: h)
                    
                    let fillColor: Color
                    if isHovered {
                        fillColor = self.palette.pine
                    } else if isPeak {
                        fillColor = self.palette.emerald
                    } else if val > 0 {
                        fillColor = self.palette.mint.opacity(0.45 + 0.50 * ratio)
                    } else {
                        fillColor = self.palette.emptyDot.opacity(0.65)
                    }
                    
                    context.fill(
                        Path(roundedRect: rect, cornerRadius: barW * 0.45, style: .continuous),
                        with: .color(fillColor)
                    )
                    
                    if hr % 6 == 0 || hr == 23 {
                        let labelText = context.resolve(
                            Text(String(format: "%02d", hr))
                                .font(.system(size: 9.5, weight: isHovered ? .semibold : .regular))
                                .foregroundStyle(isHovered ? self.palette.pine : .secondary)
                        )
                        context.draw(labelText, at: CGPoint(x: x + barW * 0.5, y: size.height - 2), anchor: .bottom)
                    }
                }
            }
            .onContinuousHover { phase in
                switch phase {
                    case .active(let pt):
                        let idx = Int((pt.x / max(1, pitch)).rounded(.down))
                        if (0..<24).contains(idx) {
                            self.hoveredHour = idx
                        }
                    case .ended:
                        self.hoveredHour = nil
                }
            }
        }
    }
}


/// Panel 2 (AI 帮写): Reclaimed Time + Best Single-Tab Trophy + Dual-Engine Local-vs-Cloud Velocity.
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
        let todayLocalChars = min(self.today.aiCompletedChars, self.today.localAcceptedChars)
        let todayCloudChars = max(0, self.today.aiCompletedChars - todayLocalChars)
        let savedToday = AnalyticsDashboardView.formatSavedTime(chars: self.today.aiCompletedChars)
        
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("默契副驾舱")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                IconButton(systemImage: "xmark", palette: self.palette, isClose: true, action: self.onClose)
            }
            
            HStack(alignment: .top, spacing: self.compact ? 14 : 22) {
                // Left: Time Reclaimed + Best Single Tab Trophy
                VStack(alignment: .leading, spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(self.today.aiCompletedChars > 0 ? "今天少敲了 \(savedToday) 机械重复" : "按下 Tab 即可让副驾帮你接半句")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.primary)
                        Text("今天接纳 \(self.today.aiCompletionAccepts) 次 · 7 天累计帮写 \(AnalyticsDashboardView.int(ai7)) 字")
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                    }
                    
                    HStack(spacing: 8) {
                        AchievementChip(
                            label: "单次一发最长",
                            value: "\(self.today.maxSingleAcceptChars) 字",
                            palette: self.palette
                        )
                        AchievementChip(
                            label: "7 日均值/次",
                            value: "\(accepts7 > 0 ? ai7 / accepts7 : 0) 字",
                            palette: self.palette
                        )
                    }
                    
                    // Dual-engine Local 0ms vs Cloud AI
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("0ms 本地习惯秒出")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(self.palette.emerald)
                            Spacer()
                            Text("\(todayLocalChars) 字 · \(local7) 次命中")
                                .font(.system(size: 11).monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        HStack {
                            Text("云端大模型续写")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(self.palette.pine)
                            Spacer()
                            Text("\(todayCloudChars) 字")
                                .font(.system(size: 11).monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(10)
                    .background(self.palette.inset, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                }
                .frame(width: self.compact ? 228 : 272)
                
                // Right: 7-day Human Lead vs AI Assist Stacked Columns
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("7 日主笔共创比例")
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("7 日手写 \(AnalyticsDashboardView.int(typed7)) 字")
                            .font(.system(size: 11).monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    
                    CoWritingStackedStrip(days: self.days, palette: self.palette)
                        .frame(height: 116)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
}


private struct CoWritingStackedStrip: View {
    
    let days: [DashboardSnapshot.ChartDay]
    let palette: DashPalette
    
    
    var body: some View {
        let maxTotal = max(120, self.days.map { $0.typed + $0.ai }.max() ?? 120)
        
        HStack(alignment: .bottom, spacing: 8) {
            ForEach(self.days) { day in
                let total = day.typed + day.ai
                let barH = total > 0 ? max(12, CGFloat(total) / CGFloat(maxTotal) * 86) : 5
                let aiH = total > 0 ? barH * CGFloat(day.ai) / CGFloat(total) : 0
                let handH = max(0, barH - aiH)
                let cal = Calendar.current
                
                VStack(spacing: 5) {
                    Spacer(minLength: 0)
                    VStack(spacing: 1.5) {
                        if aiH > 0 {
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(self.palette.emerald)
                                .frame(height: max(3, aiH))
                        }
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(total > 0 ? self.palette.pine : self.palette.emptyDot)
                            .frame(height: total > 0 ? max(4, handH) : 5)
                    }
                    .frame(maxWidth: 22)
                    
                    Text(day.isToday ? "今" : "\(cal.component(.day, from: day.date))")
                        .font(.system(size: 9.5, weight: day.isToday ? .semibold : .regular))
                        .foregroundStyle(day.isToday ? self.palette.pine : .secondary)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(self.palette.inset, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}


/// Panel 3 (AI 用量): Input->Output Alchemy + Local Zero-Token Shield + Bot Team & Model Speed Ranking.
private struct ConsumptionDetailPanel: View {
    
    let aiHeatmap: RollingHeatmapData
    let slice: DashboardSnapshot.AISlice
    let savedSummary: (localHits: Int, estimatedTokens: Int)
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
                Text("算力能量账本")
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
                    self.alchemyColumn(totals: totals, inputShare: inputShare, outputShare: outputShare)
                    self.rankingsRow
                }
            } else {
                HStack(alignment: .top, spacing: 16) {
                    self.alchemyColumn(totals: totals, inputShare: inputShare, outputShare: outputShare)
                        .frame(width: 310)
                    
                    self.rankingsRow
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }
    
    
    private func alchemyColumn(
        totals: AIUsageTotals,
        inputShare: Double,
        outputShare: Double
    ) -> some View {
        
        VStack(alignment: .leading, spacing: 10) {
            // Local zero-token shield highlight
            HStack(spacing: 8) {
                Image(systemName: "shield.lefthalf.filled")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(self.palette.emerald)
                
                VStack(alignment: .leading, spacing: 1) {
                    Text("本地省流护盾已拦截 \(self.savedSummary.localHits) 次")
                        .font(.system(size: 11.5, weight: .semibold))
                    Text("白嫖省下约 \(AnalyticsManager.formatCompactTokenCount(self.savedSummary.estimatedTokens)) Tokens")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(self.palette.positivePillBg, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            
            MiniAIHeatmap(heatmap: self.aiHeatmap, palette: self.palette, hovered: self.$hoveredDay)
            
            VStack(alignment: .leading, spacing: 6) {
                TwinRatioCapsuleBar(
                    leftRatio: totals.requests > 0 ? inputShare : 0,
                    leftColor: self.palette.emerald,
                    rightColor: self.palette.mint,
                    emptyColor: self.palette.emptyDot
                )
                
                HStack(spacing: 10) {
                    Text("输入 \(AnalyticsManager.formatCompactTokenCount(totals.inputTokens))")
                    Text("产出 \(AnalyticsManager.formatCompactTokenCount(totals.outputTokens))")
                    Spacer()
                    if self.slice.latencyMs > 0 {
                        Text("均速 \(self.slice.latencyMs)ms")
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
        }
    }
    
    
    private var rankingsRow: some View {
        
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Bot 出勤榜")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(.secondary)
                
                if self.slice.features.isEmpty {
                    Text("暂无调用记录")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(self.palette.inset, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                } else {
                    ForEach(self.slice.features.prefix(4)) { feat in
                        let matchedBot = AIBotID.allCases.first { $0.analyticsFeatureKey == feat.feature }
                        let botAccent = matchedBot.map { Color(hexString: $0.accentHex) } ?? self.palette.emerald
                        HStack(spacing: 7) {
                            Circle()
                                .fill(botAccent)
                                .frame(width: 7, height: 7)
                            Text(matchedBot?.displayName ?? feat.displayName)
                                .font(.system(size: 12, weight: .medium))
                                .lineLimit(1)
                            Spacer()
                            Text("\(feat.requests) 次")
                                .font(.system(size: 11.5, weight: .medium).monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 10)
                        .frame(height: 32)
                        .background(self.palette.inset, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            
            VStack(alignment: .leading, spacing: 6) {
                Text("模型实测极速榜")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(.secondary)
                
                if self.slice.modelPerformance.isEmpty {
                    Text("暂无模型记录")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(self.palette.inset, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                } else {
                    ForEach(self.slice.modelPerformance.prefix(4)) { item in
                        HStack(spacing: 6) {
                            Text(item.model)
                                .font(.system(size: 12, weight: .medium))
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            if item.averageLatencyMs > 0 {
                                Text("\(item.averageLatencyMs)ms")
                                    .font(.system(size: 10.5, weight: .semibold).monospacedDigit())
                                    .foregroundStyle(self.palette.emerald)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1.5)
                                    .background(self.palette.positivePillBg, in: Capsule())
                            }
                            Text(AnalyticsManager.formatCompactTokenCount(item.totalTokens))
                                .font(.system(size: 11, weight: .medium).monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 10)
                        .frame(height: 32)
                        .background(self.palette.inset, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }
    
    
    private static func shortDate(_ date: Date) -> String {
        
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M 月 d 日"
        return formatter.string(from: date)
    }
}


private struct AchievementChip: View {
    
    let label: String
    let value: String
    let palette: DashPalette
    
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(self.label)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(self.value)
                .font(.system(size: 13.5, weight: .semibold).monospacedDigit())
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(self.palette.inset, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
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


// MARK: - Studio Manuscript Folio Gallery Components

/// Bespoke Canvas-drawn folded-corner page emblem tailored by manuscript genre.
private struct ManuscriptFolioIcon: View {
    
    let kind: TouchedManuscriptItem.Kind
    let isCreatedToday: Bool
    let palette: DashPalette
    
    
    private var genreTint: Color {
        switch self.kind {
            case .markdown: self.palette.emerald
            case .code: Color(red: 0.25, green: 0.56, blue: 0.88)
            case .weeklyReport: Color(red: 0.86, green: 0.52, blue: 0.16)
            case .plainText: self.palette.pine.opacity(0.85)
        }
    }
    
    
    var body: some View {
        ZStack(alignment: .topTrailing) {
            Canvas { context, size in
                let w = size.width
                let h = size.height
                let fold: CGFloat = 8.5
                let r: CGFloat = 4.5
                
                // Page silhouette with folded top-right dog-ear
                var sheet = Path()
                sheet.move(to: CGPoint(x: r, y: 0))
                sheet.addLine(to: CGPoint(x: w - fold, y: 0))
                sheet.addLine(to: CGPoint(x: w, y: fold))
                sheet.addLine(to: CGPoint(x: w, y: h - r))
                sheet.addQuadCurve(to: CGPoint(x: w - r, y: h), control: CGPoint(x: w, y: h))
                sheet.addLine(to: CGPoint(x: r, y: h))
                sheet.addQuadCurve(to: CGPoint(x: 0, y: h - r), control: CGPoint(x: 0, y: h))
                sheet.addLine(to: CGPoint(x: 0, y: r))
                sheet.addQuadCurve(to: CGPoint(x: r, y: 0), control: CGPoint(x: 0, y: 0))
                sheet.closeSubpath()
                
                context.fill(sheet, with: .color(self.palette.card))
                context.stroke(sheet, with: .color(self.genreTint.opacity(0.42)), lineWidth: 1.0)
                
                // Top-right dog-ear triangle
                var ear = Path()
                ear.move(to: CGPoint(x: w - fold, y: 0))
                ear.addLine(to: CGPoint(x: w - fold, y: fold))
                ear.addLine(to: CGPoint(x: w, y: fold))
                ear.closeSubpath()
                context.fill(ear, with: .color(self.genreTint.opacity(0.22)))
                context.stroke(ear, with: .color(self.genreTint.opacity(0.45)), lineWidth: 0.8)
                
                // Genre-specific miniature graphic motif inside the sheet
                switch self.kind {
                    case .weeklyReport:
                        // Spiral binding notches at top + badge circle
                        for i in 0..<3 {
                            let cx = 7.0 + CGFloat(i) * 6.5
                            let notch = CGRect(x: cx, y: 4.5, width: 2.8, height: 4.5)
                            context.fill(Path(roundedRect: notch, cornerRadius: 1), with: .color(self.genreTint))
                        }
                        for row in 0..<3 {
                            let y = 16.0 + CGFloat(row) * 5.5
                            let lineRect = CGRect(x: 6, y: y, width: row == 2 ? w - 16 : w - 12, height: 2.0)
                            context.fill(Path(roundedRect: lineRect, cornerRadius: 1), with: .color(self.genreTint.opacity(row == 0 ? 0.8 : 0.35)))
                        }
                    case .code:
                        // Code braces `{ }` bar accent
                        let bar = CGRect(x: 5.5, y: 12, width: 2.5, height: 17)
                        context.fill(Path(roundedRect: bar, cornerRadius: 1.2), with: .color(self.genreTint))
                        for row in 0..<3 {
                            let y = 13.0 + CGFloat(row) * 6.0
                            let indent: CGFloat = row == 1 ? 13 : 10.5
                            let len: CGFloat = row == 1 ? (w - 18) : (w - 16)
                            context.fill(
                                Path(roundedRect: CGRect(x: indent, y: y, width: len, height: 2.2), cornerRadius: 1.1),
                                with: .color(self.genreTint.opacity(row == 1 ? 0.85 : 0.45))
                            )
                        }
                    case .markdown:
                        // Editorial heading bar + ruled lines
                        context.fill(
                            Path(roundedRect: CGRect(x: 6, y: 12, width: w - 16, height: 3.2), cornerRadius: 1.5),
                            with: .color(self.genreTint)
                        )
                        for row in 0..<3 {
                            let y = 19.0 + CGFloat(row) * 5.0
                            context.fill(
                                Path(roundedRect: CGRect(x: 6, y: y, width: row == 2 ? w - 18 : w - 12, height: 1.8), cornerRadius: 0.9),
                                with: .color(self.genreTint.opacity(0.38))
                            )
                        }
                    case .plainText:
                        // Fountain-pen clean ruled lines
                        for row in 0..<4 {
                            let y = 12.5 + CGFloat(row) * 5.2
                            context.fill(
                                Path(roundedRect: CGRect(x: 6, y: y, width: row == 3 ? w - 19 : w - 12, height: 1.8), cornerRadius: 0.9),
                                with: .color(self.genreTint.opacity(row == 0 ? 0.72 : 0.32))
                            )
                        }
                }
            }
            .frame(width: 34, height: 40)
            .shadow(color: self.palette.cardShadow, radius: 3, y: 1.5)
            
            if self.isCreatedToday {
                Circle()
                    .fill(self.palette.emerald)
                    .frame(width: 7, height: 7)
                    .overlay(Circle().strokeBorder(self.palette.card, lineWidth: 1.2))
                    .offset(x: 2, y: -2)
            }
        }
    }
}


private struct ManuscriptFolioTile: View {
    
    let item: TouchedManuscriptItem
    let maxChars: Int
    let palette: DashPalette
    let onOpen: () -> Void
    
    @State private var isHovered = false
    
    
    var body: some View {
        let ratio = max(0.08, min(1.0, Double(self.item.charCount) / Double(max(1, self.maxChars))))
        let charsLabel = self.item.charCount >= 1000
            ? String(format: "%.1fk 字", Double(self.item.charCount) / 1000.0)
            : "\(self.item.charCount) 字"
        
        Button(action: self.onOpen) {
            VStack(alignment: .leading, spacing: 9) {
                HStack(alignment: .top, spacing: 10) {
                    ManuscriptFolioIcon(
                        kind: self.item.kind,
                        isCreatedToday: self.item.isCreatedToday,
                        palette: self.palette
                    )
                    
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 4) {
                            Text(self.item.title)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            
                            Spacer(minLength: 2)
                            
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 9.5, weight: .semibold))
                                .foregroundStyle(self.isHovered ? self.palette.emerald : .secondary)
                                .opacity(self.isHovered ? 1.0 : 0.35)
                        }
                        
                        HStack(spacing: 5) {
                            Text(self.item.relativeTimeBadge)
                            Text("·")
                            Text(self.item.syntaxLabel)
                        }
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    }
                }
                
                Text(self.item.excerpt)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                
                HStack(spacing: 8) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(self.palette.emptyDot)
                            Capsule()
                                .fill(self.isHovered ? self.palette.emerald : self.palette.mint)
                                .frame(width: max(6, geo.size.width * CGFloat(ratio)))
                        }
                    }
                    .frame(height: 3.5)
                    
                    Text(charsLabel)
                        .font(.system(size: 10.5, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(self.isHovered ? self.palette.insetHover : self.palette.inset)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .strokeBorder(self.isHovered ? self.palette.hairlineStrong : self.palette.hairline, lineWidth: 0.9)
            )
            .scaleEffect(self.isHovered ? 1.012 : 1.0)
            .contentShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        }
        .buttonStyle(PressStyle())
        .pointerStyle(.link)
        .onHover { hovering in
            withAnimation(DashMotion.quick) { self.isHovered = hovering }
        }
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


// MARK: - Bento Card & Small UI Helpers

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
