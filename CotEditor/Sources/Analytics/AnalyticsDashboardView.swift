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


// MARK: - Design Tokens & Snapshot

private enum DashMotion {
    
    static let quick = Animation.timingCurve(0.2, 0, 0, 1, duration: 0.16)
    static let standard = Animation.timingCurve(0.2, 0, 0, 1, duration: 0.24)
}


private enum DashboardQuadMetric: String, CaseIterable, Identifiable {
    
    case typed
    case aiUsage
    case busyness
    case mood
    
    var id: String { self.rawValue }
    
    var title: String {
        switch self {
            case .typed: "今日码字"
            case .aiUsage: "AI用量"
            case .busyness: "忙碌指数"
            case .mood: "情绪指数"
        }
    }
}


/// Resolves live editorial palette tokens from `StudioPaletteManager`.
private struct DashPalette: Sendable {
    
    let tokens: StudioColorTokens
    
    @MainActor init(_ scheme: ColorScheme, tokens: StudioColorTokens? = nil) {
        self.tokens = tokens ?? StudioPaletteManager.shared.tokens(isDark: scheme == .dark)
    }
    
    var canvasTop: Color { self.tokens.canvasTop }
    var canvasBottom: Color { self.tokens.canvasBottom }
    var card: Color { self.tokens.card }
    var cardShadow: Color { self.tokens.cardShadow }
    var inset: Color { self.tokens.inset }
    var hairline: Color { self.tokens.hairline }
    var hairlineStrong: Color { self.tokens.hairlineStrong }
    
    var pine: Color { self.tokens.primaryInk }
    var emerald: Color { self.tokens.accentText }
    var accentFill: Color { self.tokens.accent }
    var mint: Color { self.tokens.secondaryAccent }
    var paleMint: Color { self.tokens.paleAccent }
    var emptyDot: Color { self.tokens.emptyDot }
    
    
    func heat(_ level: Int) -> Color {
        switch level {
            case 4: self.tokens.heat4
            case 3: self.tokens.heat3
            case 2: self.tokens.heat2
            case 1: self.tokens.heat1
            default: self.emptyDot
        }
    }
    
    
    func toneColor(for tone: PersonalityTagTone) -> Color {
        switch tone {
            case .calm: self.tokens.accent
            case .sharp: self.tokens.secondaryAccent
            case .warm: Color(red: 0.88, green: 0.56, blue: 0.34)
            case .playful: self.tokens.heat2
        }
    }
}


private struct DashboardSnapshot {
    
    struct ChartDay: Identifiable {
        var id: String
        var date: Date
        var typed: Int
        var ai: Int
    }
    
    var today: DailyWritingStats
    var days14: [ChartDay]
    var yearlyHeatmap: YearlyHeatmapData
    var currentStreak: Int
    var availableYears: [Int]
    var aiTodayTotals: AIUsageTotals
    var ai30Totals: AIUsageTotals
    var aiModels: [ModelUsageSummary]
    var aiFeatures: [FeatureUsageSummary]
    var busyness: BusynessMetrics
    var mood: MoodMetrics
    
    
    @MainActor static func build(analytics: AnalyticsManager, selectedYear: Int) -> DashboardSnapshot {
        let today = analytics.todayStats
        let series14 = analytics.dailySeries(days: 14)
        
        let formatter = DateFormatter()
        formatter.calendar = Calendar.current
        formatter.dateFormat = "yyyy-MM-dd"
        let days14: [ChartDay] = series14.map { item in
            ChartDay(
                id: item.dateKey,
                date: formatter.date(from: item.dateKey) ?? Date(),
                typed: item.typedChars,
                ai: item.aiCompletedChars
            )
        }
        
        let availableYears = analytics.availableHeatmapYears()
        let resolvedYear = availableYears.contains(selectedYear)
            ? selectedYear
            : (availableYears.last ?? Calendar.current.component(.year, from: Date()))
        let yearly = analytics.yearlyHeatmap(year: resolvedYear, trimFutureWeeks: true)
        
        let aiTodayTotals = analytics.aiUsageTotals(forTodayOnly: true)
        let ai30Totals = analytics.aiUsageTotals(forTodayOnly: false, days: 30)
        let models = analytics.modelDistribution(days: 30)
        let features = analytics.featureDistribution(days: 30)
        
        return DashboardSnapshot(
            today: today,
            days14: days14,
            yearlyHeatmap: yearly,
            currentStreak: analytics.currentWritingStreak,
            availableYears: availableYears,
            aiTodayTotals: aiTodayTotals,
            ai30Totals: ai30Totals,
            aiModels: models,
            aiFeatures: features,
            busyness: analytics.busynessMetrics,
            mood: analytics.moodMetrics
        )
    }
}


// MARK: - Two-Row Bento Dashboard

struct AnalyticsDashboardView: View {
    
    let isEmbeddedInSettings: Bool
    var onDismiss: (() -> Void)?
    var onOpenDocument: ((StoredDocumentRecord) -> Void)?
    var onOpenWeeklyReport: ((StoredWeeklyReport) -> Void)?
    
    @Environment(\.colorScheme) private var colorScheme
    
    @State private var analytics = AnalyticsManager.shared
    @State private var studioPalette = StudioPaletteManager.shared
    @State private var newsService = AIHotNewsService.shared
    
    @State private var snapshot: DashboardSnapshot?
    @State private var selectedYear: Int = Calendar.current.component(.year, from: Date())
    @State private var expandedQuad: DashboardQuadMetric?
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
    
    private var outerPadding: CGFloat { self.isEmbeddedInSettings ? 14 : 22 }
    private var row1Height: CGFloat { self.isEmbeddedInSettings ? 250 : 316 }
    private var row2Height: CGFloat { self.isEmbeddedInSettings ? 260 : 340 }
    
    
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [self.palette.canvasTop, self.palette.canvasBottom],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            ScrollView(.vertical, showsIndicators: true) {
                if let snapshot = self.snapshot {
                    VStack(alignment: .leading, spacing: 14) {
                        if !self.isEmbeddedInSettings, let onDismiss = self.onDismiss {
                            DashboardTopNavigationBar(
                                palette: self.palette,
                                onBack: onDismiss
                            )
                        }
                        
                        self.row1Section(snapshot)
                        self.row2Section()
                    }
                    .padding(self.outerPadding)
                    .frame(maxWidth: 1160, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .opacity(self.hasAppeared ? 1 : 0)
                    .offset(y: self.hasAppeared ? 0 : 6)
                } else {
                    Color.clear.frame(height: 460)
                }
            }
        }
        .onKeyPress(.escape) {
            if self.expandedQuad != nil {
                withAnimation(DashMotion.standard) {
                    self.expandedQuad = nil
                }
                return .handled
            }
            if let onDismiss = self.onDismiss {
                onDismiss()
                return .handled
            }
            return .ignored
        }
        .task {
            self.rebuildSnapshot()
            withAnimation(DashMotion.standard) {
                self.hasAppeared = true
            }
            async let newsTask: Void = self.newsService.refreshIfNeeded()
            async let predTask: Void = self.analytics.refreshActionPredictions(force: false)
            _ = await (newsTask, predTask)
        }
        .onChange(of: self.analytics.revision) { _, _ in
            self.rebuildSnapshot()
        }
        .onChange(of: self.selectedYear) { _, _ in
            self.rebuildSnapshot()
        }
    }
    
    
    // MARK: Row 1 — Unified Heatmap+Today Writing Card + Asymmetric Live-Activity Bento (Wide AI Usage + Busyness & Mood)
    
    private func row1Section(_ snapshot: DashboardSnapshot) -> some View {
        GeometryReader { proxy in
            let spacing: CGFloat = 14
            let usableW = max(320, proxy.size.width - spacing)
            let leftRatio: CGFloat = self.isEmbeddedInSettings ? 0.50 : 0.54
            let leftWidth = floor(usableW * leftRatio)
            let rightWidth = max(160, usableW - leftWidth)
            
            HStack(alignment: .top, spacing: spacing) {
                DashboardHeatmapCard(
                    yearlyHeatmap: snapshot.yearlyHeatmap,
                    today: snapshot.today,
                    days14: snapshot.days14,
                    currentStreak: snapshot.currentStreak,
                    availableYears: snapshot.availableYears,
                    selectedYear: self.$selectedYear,
                    palette: self.palette
                )
                .frame(width: leftWidth, height: self.row1Height)
                
                self.flippableQuadSection(snapshot)
                    .frame(width: rightWidth, height: self.row1Height)
            }
        }
        .frame(height: self.row1Height)
    }
    
    
    private func flippableQuadSection(_ snapshot: DashboardSnapshot) -> some View {
        ZStack {
            if let expanded = self.expandedQuad {
                DashboardExpandedQuadCard(
                    metric: expanded,
                    snapshot: snapshot,
                    palette: self.palette
                ) {
                    withAnimation(DashMotion.standard) {
                        self.expandedQuad = nil
                    }
                }
                .id("expanded-\(expanded.rawValue)")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .transition(.opacity.combined(with: .scale(scale: 0.97)))
            } else {
                let vGap: CGFloat = 12
                let hGap: CGFloat = 12
                let topH = max(92, floor((self.row1Height - vGap) * 0.52))
                let botH = max(84, self.row1Height - vGap - topH)
                
                VStack(spacing: vGap) {
                    // Full-width 1x2 AI Usage Live-Activity Studio Card (click to expand Drill-Down Sunburst)
                    DashboardAIUsageWideCard(
                        snapshot: snapshot,
                        palette: self.palette
                    ) {
                        withAnimation(DashMotion.standard) {
                            self.expandedQuad = .aiUsage
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: topH, maxHeight: topH)
                    
                    // Bottom 2-column row: Busyness (Segmented Tick Meter / Rose) + Mood (External-Labeled Sankey)
                    HStack(spacing: hGap) {
                        self.quadCard(metric: .busyness, snapshot: snapshot)
                            .frame(maxWidth: .infinity, minHeight: botH, maxHeight: botH)
                        self.quadCard(metric: .mood, snapshot: snapshot)
                            .frame(maxWidth: .infinity, minHeight: botH, maxHeight: botH)
                    }
                }
                .id("compact-bento-grid")
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }
        }
        .animation(DashMotion.standard, value: self.expandedQuad)
    }
    
    
    private func quadCard(metric: DashboardQuadMetric, snapshot: DashboardSnapshot) -> some View {
        DashboardCompactQuadCard(
            metric: metric,
            snapshot: snapshot,
            palette: self.palette
        ) {
            withAnimation(DashMotion.standard) {
                self.expandedQuad = metric
            }
        }
    }
    
    
    // MARK: Row 2 — Equal 3-Column Layout (干了啥 / AI 预测要干啥 / 小红书风分页 NEWS)
    
    private func row2Section() -> some View {
        HStack(alignment: .top, spacing: 14) {
            self.doneTodayColumn()
                .frame(maxWidth: .infinity, minHeight: self.row2Height, maxHeight: self.row2Height, alignment: .topLeading)
            
            self.predictedActionsColumn()
                .frame(maxWidth: .infinity, minHeight: self.row2Height, maxHeight: self.row2Height, alignment: .topLeading)
            
            self.newsColumn()
                .frame(maxWidth: .infinity, minHeight: self.row2Height, maxHeight: self.row2Height, alignment: .topLeading)
        }
    }
    
    
    private func doneTodayColumn() -> some View {
        let points = self.analytics.doneTodayPoints
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Circle()
                    .fill(self.palette.accentFill)
                    .frame(width: 6, height: 6)
                Text("干了啥")
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(self.palette.pine)
                Spacer()
                Text(String(format: "%02d", points.count))
                    .font(.system(size: 11, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(self.palette.pine.opacity(0.46))
                    .padding(.horizontal, 6.5)
                    .padding(.vertical, 2)
                    .background(self.palette.inset, in: Capsule())
            }
            .frame(height: 22)
            
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 10) {
                    if points.isEmpty {
                        Text("今天还没有写作记录")
                            .font(.system(size: 12.5))
                            .foregroundStyle(self.palette.pine.opacity(0.46))
                    } else {
                        ForEach(Array(points.enumerated()), id: \.offset) { idx, point in
                            HStack(alignment: .top, spacing: 9) {
                                Capsule()
                                    .fill(idx == 0 ? self.palette.accentFill : self.palette.mint.opacity(0.65))
                                    .frame(width: 3, height: 14)
                                    .padding(.top, 2.5)
                                
                                Text(point)
                                    .font(.system(size: 12.5, weight: .regular))
                                    .foregroundStyle(self.palette.pine.opacity(0.90))
                                    .lineSpacing(2)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                
                                Text(String(format: "%02d", idx + 1))
                                    .font(.system(size: 10, weight: .medium, design: .monospaced).monospacedDigit())
                                    .foregroundStyle(self.palette.pine.opacity(0.34))
                                    .padding(.top, 2)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(16)
        .dashboardCardSurface(palette: self.palette, cornerRadius: 18)
    }
    
    
    private func predictedActionsColumn() -> some View {
        let predictions = self.analytics.actionPredictions
        
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Circle()
                    .fill(self.palette.mint)
                    .frame(width: 6, height: 6)
                Text("要干啥")
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(self.palette.pine)
                Spacer()
                Text(String(format: "%02d", predictions.count))
                    .font(.system(size: 11, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(self.palette.pine.opacity(0.46))
                    .padding(.horizontal, 6.5)
                    .padding(.vertical, 2)
                    .background(self.palette.inset, in: Capsule())
            }
            .frame(height: 22)
            
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 10) {
                    if predictions.isEmpty {
                        Text("开始写作后会自动梳理接下来要做的事")
                            .font(.system(size: 12.5))
                            .foregroundStyle(self.palette.pine.opacity(0.46))
                    } else {
                        ForEach(Array(predictions.enumerated()), id: \.element.id) { idx, pred in
                            HStack(alignment: .top, spacing: 9) {
                                Capsule()
                                    .fill(idx == 0 ? self.palette.accentFill : self.palette.mint.opacity(0.65))
                                    .frame(width: 3, height: 14)
                                    .padding(.top, 2.5)
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(pred.action)
                                        .font(.system(size: 12.5, weight: .regular))
                                        .foregroundStyle(self.palette.pine.opacity(0.90))
                                        .lineSpacing(2)
                                        .fixedSize(horizontal: false, vertical: true)
                                    
                                    if !pred.reason.isEmpty {
                                        Text(pred.reason)
                                            .font(.system(size: 11))
                                            .foregroundStyle(self.palette.pine.opacity(0.48))
                                            .lineLimit(1)
                                            .truncationMode(.tail)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                
                                Text(String(format: "%02d", idx + 1))
                                    .font(.system(size: 10, weight: .medium, design: .monospaced).monospacedDigit())
                                    .foregroundStyle(self.palette.pine.opacity(0.34))
                                    .padding(.top, 2)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(16)
        .dashboardCardSurface(palette: self.palette, cornerRadius: 18)
    }
    
    
    private func newsColumn() -> some View {
        let pageItems = self.newsService.currentPageItems
        
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Circle()
                    .fill(self.palette.emerald)
                    .frame(width: 6, height: 6)
                Text("NEWS")
                    .font(.system(size: 13.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(self.palette.pine)
                
                Spacer(minLength: 4)
                
                if !self.newsService.items.isEmpty {
                    Text("\(self.newsService.items.count)")
                        .font(.system(size: 10.5, weight: .semibold, design: .rounded).monospacedDigit())
                        .foregroundStyle(self.palette.pine.opacity(0.46))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(self.palette.inset, in: Capsule())
                }
                
                Button {
                    Task {
                        await self.newsService.refreshIfNeeded(force: true)
                    }
                } label: {
                    Image(systemName: self.newsService.isLoading ? "hourglass" : "arrow.clockwise")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(self.palette.pine.opacity(0.68))
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(self.palette.inset.opacity(0.85)))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .disabled(self.newsService.isLoading)
                .help("刷新精选资讯")
            }
            .frame(height: 22)
            
            GeometryReader { geo in
                let useTwoColumns = geo.size.width >= 260
                let columns: [GridItem] = useTwoColumns
                    ? [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]
                    : [GridItem(.flexible(), spacing: 8)]
                
                ScrollView(.vertical, showsIndicators: false) {
                    if pageItems.isEmpty {
                        if self.newsService.isLoading {
                            HStack(spacing: 8) {
                                ProgressView()
                                    .controlSize(.small)
                                Text("正在拉取高信息量精选帖子…")
                                    .font(.system(size: 12))
                                    .foregroundStyle(self.palette.pine.opacity(0.60))
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 6)
                        } else {
                            Button {
                                Task {
                                    await self.newsService.refreshIfNeeded(force: true)
                                }
                            } label: {
                                Label("重新加载最新资讯", systemImage: "arrow.clockwise")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(self.palette.emerald)
                                    .padding(.horizontal, 10)
                                    .frame(height: 28)
                                    .background(self.palette.accentFill.opacity(0.12), in: Capsule())
                            }
                            .buttonStyle(.plain)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 6)
                        }
                    } else {
                        LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                            ForEach(pageItems) { item in
                                NewsFeedCoverCard(
                                    item: item,
                                    coverImage: self.newsService.coverImage(for: item),
                                    compactRow: !useTwoColumns,
                                    palette: self.palette
                                ) {
                                    if let url = item.url {
                                        NSWorkspace.shared.open(url)
                                    }
                                }
                            }
                        }
                        .id("news-mixed-page-\(self.newsService.currentPage)")
                        .transition(.opacity)
                    }
                }
            }
            
            // Xiaohongshu-style bottom pagination bar
            if !self.newsService.filteredItems.isEmpty {
                HStack(spacing: 8) {
                    Button {
                        withAnimation(DashMotion.quick) {
                            self.newsService.goToPreviousPage()
                        }
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 9.5, weight: .semibold))
                            Text("上一页")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundStyle(self.newsService.totalPages > 1 ? self.palette.pine.opacity(0.75) : self.palette.pine.opacity(0.28))
                        .padding(.horizontal, 8)
                        .frame(height: 24)
                        .background(self.palette.inset, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(self.newsService.totalPages <= 1)
                    
                    Spacer()
                    
                    Text("\(self.newsService.currentPage) / \(self.newsService.totalPages)")
                        .font(.system(size: 10.5, weight: .semibold, design: .rounded).monospacedDigit())
                        .foregroundStyle(self.palette.pine.opacity(0.55))
                    
                    Spacer()
                    
                    Button {
                        if self.newsService.totalPages > 1 {
                            withAnimation(DashMotion.quick) {
                                self.newsService.goToNextPage()
                            }
                        } else {
                            Task {
                                await self.newsService.refreshIfNeeded(force: true)
                            }
                        }
                    } label: {
                        HStack(spacing: 3) {
                            Text(self.newsService.currentPage >= self.newsService.totalPages ? "换一批" : "下一页")
                                .font(.system(size: 11, weight: .medium))
                            Image(systemName: self.newsService.currentPage >= self.newsService.totalPages ? "arrow.clockwise" : "chevron.right")
                                .font(.system(size: 9.5, weight: .semibold))
                        }
                        .foregroundStyle(self.palette.emerald)
                        .padding(.horizontal, 8)
                        .frame(height: 24)
                        .background(self.palette.accentFill.opacity(0.12), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 2)
            }
        }
        .padding(16)
        .dashboardCardSurface(palette: self.palette, cornerRadius: 18)
    }
    
    
    // MARK: Actions
    
    private func rebuildSnapshot() {
        self.snapshot = DashboardSnapshot.build(analytics: self.analytics, selectedYear: self.selectedYear)
    }
}


// MARK: - Top Navigation Bar (Title-Free · Ergonomic Top-Left Back Pill)

private struct DashboardTopNavigationBar: View {
    
    let palette: DashPalette
    let onBack: () -> Void
    
    @State private var isHovered = false
    
    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy年M月d日 · EEEE"
        f.locale = Locale(identifier: "zh_CN")
        return f
    }()
    
    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Button(action: self.onBack) {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(self.isHovered ? self.palette.emerald : self.palette.pine.opacity(0.75))
                    
                    Text(AppLanguage.text("返回编辑", en: "Back to Editor"))
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(self.palette.pine.opacity(self.isHovered ? 0.96 : 0.82))
                    
                    Text("ESC")
                        .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                        .foregroundStyle(self.palette.pine.opacity(0.42))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(self.palette.inset, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                }
                .padding(.horizontal, 10)
                .frame(height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(self.isHovered ? self.palette.card : self.palette.card.opacity(0.84))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(self.isHovered ? self.palette.accentFill.opacity(0.45) : self.palette.hairline, lineWidth: 0.75)
                )
            }
            .buttonStyle(.plain)
            .pointerStyle(.link)
            .onHover { hovering in
                withAnimation(DashMotion.quick) {
                    self.isHovered = hovering
                }
            }
            .help(AppLanguage.text("返回编辑器 (Esc)", en: "Back to Editor (Esc)"))
            
            Spacer()
            
            Text(Self.dateFormatter.string(from: Date()))
                .font(.system(size: 11.5, weight: .medium).monospacedDigit())
                .foregroundStyle(self.palette.pine.opacity(0.48))
        }
        .padding(.bottom, 2)
    }
}


// MARK: - Unified Writing Telemetry & Yearly Heatmap Card (今日码字 × 热力图双向联动)

private struct DashboardHeatmapCard: View {
    
    let yearlyHeatmap: YearlyHeatmapData
    let today: DailyWritingStats
    let days14: [DashboardSnapshot.ChartDay]
    let currentStreak: Int
    let availableYears: [Int]
    @Binding var selectedYear: Int
    let palette: DashPalette
    
    @State private var hoveredCell: HeatmapDayCell?
    @State private var hoveredBarDayID: String?
    @State private var hoverPoint: CGPoint = .zero
    
    
    private var previousYear: Int? {
        self.availableYears.last { $0 < self.yearlyHeatmap.year }
    }
    
    private var nextYear: Int? {
        self.availableYears.first { $0 > self.yearlyHeatmap.year }
    }
    
    /// Active cross-linked day ID when hovering either the yearly heatmap OR the 14-day pill spectrum.
    private var activeLinkedDayID: String? {
        self.hoveredBarDayID ?? self.hoveredCell?.id
    }
    
    private var activeReadout: (label: String, total: Int, typed: Int, ai: Int) {
        if let barID = self.hoveredBarDayID,
           let day = self.days14.first(where: { $0.id == barID })
        {
            return (Self.shortDateFormatter.string(from: day.date), day.typed + day.ai, day.typed, day.ai)
        }
        if let cell = self.hoveredCell {
            return (Self.shortDateFormatter.string(from: cell.date), cell.typedChars + cell.aiCompletedChars, cell.typedChars, cell.aiCompletedChars)
        }
        let total = self.today.typedChars + self.today.aiCompletedChars
        return ("今日码字", total, self.today.typedChars, self.today.aiCompletedChars)
    }
    
    
    var body: some View {
        let readout = self.activeReadout
        let isInspecting = (self.activeLinkedDayID != nil)
        
        VStack(alignment: .leading, spacing: 8) {
            // Top Live-Activity Telemetry Strip: Today's Writing Hero (linked with hovered day) + Year & Streak
            HStack(alignment: .center, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text(readout.total.formatted())
                            .font(.system(size: 19, weight: .bold, design: .rounded).monospacedDigit())
                            .foregroundStyle(isInspecting ? self.palette.emerald : self.palette.pine)
                            .contentTransition(.numericText())
                        Text("字")
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(self.palette.pine.opacity(0.48))
                    }
                    
                    HStack(spacing: 4) {
                        Circle()
                            .fill(isInspecting ? self.palette.emerald : self.palette.accentFill)
                            .frame(width: 5, height: 5)
                        Text(readout.label)
                            .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                            .foregroundStyle(self.palette.pine.opacity(0.72))
                        if readout.total > 0 {
                            Text("手写 \(readout.typed.formatted()) · AI \(readout.ai.formatted())")
                                .font(.system(size: 10, weight: .medium, design: .rounded).monospacedDigit())
                                .foregroundStyle(self.palette.pine.opacity(0.46))
                                .lineLimit(1)
                        }
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2.5)
                    .background(self.palette.inset.opacity(0.90), in: Capsule())
                }
                
                Spacer(minLength: 4)
                
                // Compact Streak Momentum Bar (Harajuku — Shibuya — Ebisu inspired)
                if self.currentStreak > 0 {
                    let milestone: Double = self.currentStreak < 7 ? 7 : (self.currentStreak < 30 ? 30 : 100)
                    let fillRatio = min(1.0, max(0.16, Double(self.currentStreak) / milestone))
                    HStack(spacing: 5) {
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(self.palette.inset)
                                .frame(width: 34, height: 4.5)
                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: [self.palette.mint, self.palette.accentFill, self.palette.emerald],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: max(6, 34 * CGFloat(fillRatio)), height: 4.5)
                        }
                        Text("\(self.currentStreak)d")
                            .font(.system(size: 10.5, weight: .semibold, design: .rounded).monospacedDigit())
                            .foregroundStyle(self.palette.emerald)
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2.5)
                    .background(self.palette.accentFill.opacity(0.10), in: Capsule())
                }
                
                // Year selector pill
                HStack(spacing: 2) {
                    Button {
                        if let prev = self.previousYear {
                            self.selectedYear = prev
                        }
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 9.5, weight: .semibold))
                            .foregroundStyle(self.previousYear != nil ? self.palette.pine.opacity(0.75) : self.palette.pine.opacity(0.22))
                            .frame(width: 18, height: 18)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(self.previousYear == nil)
                    
                    Text("\(String(self.yearlyHeatmap.year))")
                        .font(.system(size: 11.5, weight: .semibold, design: .rounded).monospacedDigit())
                        .foregroundStyle(self.palette.pine.opacity(0.86))
                    
                    Button {
                        if let next = self.nextYear {
                            self.selectedYear = next
                        }
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9.5, weight: .semibold))
                            .foregroundStyle(self.nextYear != nil ? self.palette.pine.opacity(0.75) : self.palette.pine.opacity(0.22))
                            .frame(width: 18, height: 18)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(self.nextYear == nil)
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(self.palette.inset.opacity(0.85), in: Capsule())
            }
            
            // Middle: Crisp 1:1 Square Yearly Activity Heatmap (cross-highlights with 14-day spectrum)
            GeometryReader { geo in
                let layout = HeatmapGridLayout.compute(
                    size: geo.size,
                    weekCount: max(1, self.yearlyHeatmap.weeks.count)
                )
                
                ScrollView(.horizontal, showsIndicators: false) {
                    ZStack(alignment: .topLeading) {
                        Canvas { context, canvasSize in
                            guard canvasSize.width.isFinite, canvasSize.height.isFinite,
                                  canvasSize.width > 10, canvasSize.height > 10 else { return }
                            
                            var lastLabelRightX: CGFloat = -100
                            for marker in self.yearlyHeatmap.monthLabels {
                                let x = layout.gridOriginX + CGFloat(marker.weekIndex) * layout.pitch
                                guard x >= lastLabelRightX + 20 else { continue }
                                lastLabelRightX = x
                                context.draw(
                                    Text("\(marker.month)月")
                                        .font(.system(size: 9, weight: .medium, design: .rounded))
                                        .foregroundStyle(self.palette.pine.opacity(0.45)),
                                    at: CGPoint(x: x, y: layout.gridOriginY - 9),
                                    anchor: .leading
                                )
                            }
                            
                            for (rowIndex, label) in [(0, "一"), (2, "三"), (4, "五")] {
                                let rect = layout.cellRect(col: 0, row: rowIndex)
                                context.draw(
                                    Text(label)
                                        .font(.system(size: 8.5, weight: .regular))
                                        .foregroundStyle(self.palette.pine.opacity(0.40)),
                                    at: CGPoint(x: layout.gridOriginX - 6, y: rect.midY),
                                    anchor: .trailing
                                )
                            }
                            
                            for (colIndex, week) in self.yearlyHeatmap.weeks.enumerated() {
                                for (rowIndex, cell) in week.enumerated() {
                                    guard rowIndex < 7, !cell.isOutOfYear, !cell.isFuture else { continue }
                                    let rect = layout.cellRect(col: colIndex, row: rowIndex)
                                    let path = RoundedRectangle(cornerRadius: layout.cornerRadius, style: .continuous)
                                        .path(in: rect)
                                    let isLinked = (self.activeLinkedDayID == cell.id)
                                    let fillCol = isLinked ? self.palette.emerald : self.palette.heat(cell.level)
                                    context.fill(path, with: .color(fillCol))
                                    
                                    if isLinked {
                                        context.stroke(
                                            path,
                                            with: .color(self.palette.pine.opacity(0.85)),
                                            lineWidth: 1.35
                                        )
                                    }
                                }
                            }
                        }
                        .frame(width: layout.canvasWidth, height: max(layout.canvasHeight, geo.size.height))
                        .onContinuousHover { phase in
                            switch phase {
                                case .active(let location):
                                    self.hoverPoint = location
                                    self.hoveredCell = layout.hitTest(point: location, weeks: self.yearlyHeatmap.weeks)
                                case .ended:
                                    self.hoveredCell = nil
                            }
                        }
                        
                        if let cell = self.hoveredCell {
                            self.hoverTooltip(
                                cell: cell,
                                in: CGSize(width: layout.canvasWidth, height: max(layout.canvasHeight, geo.size.height))
                            )
                        }
                    }
                }
                .defaultScrollAnchor(.trailing)
            }
            
            // Bottom: Linked Live-Activity 14-Day Writing Pill-Bar Spectrum (7.2 mmol/L & 25:23 inspired)
            VStack(spacing: 4) {
                GeometryReader { specGeo in
                    let days = self.days14
                    let count = max(1, days.count)
                    let maxVal = max(100.0, days.map { Double($0.typed + $0.ai) }.max() ?? 100.0)
                    let gap: CGFloat = 5
                    let barW = max(4, min(14, (specGeo.size.width - CGFloat(count - 1) * gap) / CGFloat(count)))
                    let totalBarsW = CGFloat(count) * barW + CGFloat(count - 1) * gap
                    let startX = max(0, (specGeo.size.width - totalBarsW) * 0.5)
                    let plotH = max(20, specGeo.size.height - 6)
                    
                    Canvas { context, size in
                        guard size.width > 12, size.height > 12 else { return }
                        for (idx, day) in days.enumerated() {
                            let val = Double(day.typed + day.ai)
                            let ratio = CGFloat(val / maxVal)
                            let h = max(4, ratio * plotH)
                            let x = startX + CGFloat(idx) * (barW + gap)
                            let y = size.height - h
                            let rect = CGRect(x: x, y: y, width: barW, height: h)
                            let pill = Capsule().path(in: rect)
                            
                            let isLinked = (self.activeLinkedDayID == day.id)
                            let isToday = (idx == count - 1)
                            let barColor: Color = if isLinked {
                                self.palette.emerald
                            } else if isToday {
                                self.palette.accentFill
                            } else if ratio >= 0.68 {
                                self.palette.accentFill.opacity(0.86)
                            } else if ratio >= 0.30 {
                                self.palette.mint.opacity(0.74)
                            } else {
                                self.palette.emptyDot
                            }
                            context.fill(pill, with: .color(barColor))
                            
                            // Precision peak dot cap (82 mmHg / 7.2 mmol/L inspired) on active/hovered bars
                            if isLinked || (ratio >= 0.72 && val > 0) {
                                let dotD = min(barW, 4.5)
                                let dotRect = CGRect(x: rect.midX - dotD * 0.5, y: max(0, y - dotD - 2), width: dotD, height: dotD)
                                context.fill(Circle().path(in: dotRect), with: .color(isLinked ? self.palette.pine : self.palette.emerald))
                            }
                        }
                    }
                    .contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                            case .active(let loc):
                                let rel = loc.x - startX
                                let pitch = barW + gap
                                let idx = Int(floor(rel / max(1, pitch)))
                                if idx >= 0 && idx < days.count {
                                    self.hoveredBarDayID = days[idx].id
                                } else {
                                    self.hoveredBarDayID = nil
                                }
                            case .ended:
                                self.hoveredBarDayID = nil
                        }
                    }
                }
                .frame(height: 46)
                
                HStack {
                    Text("近14日节奏")
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(self.palette.pine.opacity(0.42))
                    Spacer()
                    Text("活跃 \(self.yearlyHeatmap.activeDays) 天 · 7D")
                        .font(.system(size: 9.5, weight: .medium, design: .rounded).monospacedDigit())
                        .foregroundStyle(self.palette.pine.opacity(0.42))
                    Spacer()
                    Text("NOW")
                        .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                        .foregroundStyle(self.palette.emerald.opacity(0.85))
                }
            }
            .padding(.top, 2)
        }
        .padding(16)
        .dashboardCardSurface(palette: self.palette, cornerRadius: 18)
    }
    
    
    @ViewBuilder
    private func hoverTooltip(cell: HeatmapDayCell, in size: CGSize) -> some View {
        let total = cell.typedChars + cell.aiCompletedChars
        let tipX = min(max(62, self.hoverPoint.x), max(62, size.width - 62))
        let tipY = max(16, self.hoverPoint.y - 22)
        
        Text("\(Self.shortDateFormatter.string(from: cell.date)) · \(total.formatted()) 字")
            .font(.system(size: 11, weight: .medium, design: .rounded).monospacedDigit())
            .foregroundStyle(self.palette.pine)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(self.palette.card.opacity(0.96))
                    .shadow(color: self.palette.cardShadow, radius: 6, y: 2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(self.palette.hairlineStrong, lineWidth: 0.7)
            )
            .position(x: tipX, y: tipY)
            .allowsHitTesting(false)
    }
    
    
    private static let shortDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "M月d日"
        return f
    }()
}


/// Strict 1:1 square-cell layout for the yearly activity heatmap with left weekday labels & top month markers.
struct HeatmapGridLayout {
    
    let gridOriginX: CGFloat
    let gridOriginY: CGFloat
    let cellSide: CGFloat
    let gap: CGFloat
    let cornerRadius: CGFloat
    let canvasWidth: CGFloat
    let canvasHeight: CGFloat
    
    var pitch: CGFloat { self.cellSide + self.gap }
    
    
    static func compute(size: CGSize, weekCount: Int) -> HeatmapGridLayout {
        let cols = max(1, weekCount)
        let rows = 7
        let leftAxis: CGFloat = 18
        let topAxis: CGFloat = 18
        let trailingPad: CGFloat = 4
        let bottomPad: CGFloat = 4
        
        let availW = max(120, size.width - leftAxis - trailingPad)
        let availH = max(72, size.height - topAxis - bottomPad)
        
        let gap: CGFloat = cols > 40 ? 2.5 : 3.0
        let fitW = (availW - CGFloat(cols - 1) * gap) / CGFloat(cols)
        let fitH = (availH - CGFloat(rows - 1) * gap) / CGFloat(rows)
        
        // Strictly 1:1 square cells bounded cleanly in [9.5pt, 15.0pt]; wider 53-week years scroll smoothly instead of distorting aspect ratio!
        let minSide: CGFloat = 9.5
        let maxSide: CGFloat = 15.0
        let idealSide = min(fitW, fitH)
        let cellSide = max(minSide, min(maxSide, floor(idealSide * 2) / 2))
        
        let gridW = CGFloat(cols) * cellSide + CGFloat(cols - 1) * gap
        let gridH = CGFloat(rows) * cellSide + CGFloat(rows - 1) * gap
        
        let contentW = leftAxis + gridW + trailingPad
        let canvasWidth = max(size.width, contentW)
        let canvasHeight = max(size.height, topAxis + gridH + bottomPad)
        
        let gridOriginX = contentW < size.width
            ? leftAxis + floor((size.width - contentW) * 0.5)
            : leftAxis
        let gridOriginY = topAxis + max(0, floor((canvasHeight - topAxis - bottomPad - gridH) * 0.5))
        let cornerRadius = max(2.0, min(3.5, cellSide * 0.25))
        
        return HeatmapGridLayout(
            gridOriginX: gridOriginX,
            gridOriginY: gridOriginY,
            cellSide: cellSide,
            gap: gap,
            cornerRadius: cornerRadius,
            canvasWidth: canvasWidth,
            canvasHeight: canvasHeight
        )
    }
    
    
    func cellRect(col: Int, row: Int) -> CGRect {
        let x = self.gridOriginX + CGFloat(col) * self.pitch
        let y = self.gridOriginY + CGFloat(row) * self.pitch
        return CGRect(x: x, y: y, width: self.cellSide, height: self.cellSide)
    }
    
    
    func hitTest(point: CGPoint, weeks: [[HeatmapDayCell]]) -> HeatmapDayCell? {
        let col = Int(floor((point.x - self.gridOriginX) / self.pitch))
        let row = Int(floor((point.y - self.gridOriginY) / self.pitch))
        guard col >= 0, col < weeks.count, row >= 0, row < weeks[col].count else { return nil }
        let cell = weeks[col][row]
        guard !cell.isOutOfYear, !cell.isFuture else { return nil }
        return cell
    }
}


// MARK: - Full-Width 1x2 AI Usage Live-Activity Studio Card (AI 用量 · 横幅仪表台)

private struct DashboardAIUsageWideCard: View {
    
    let snapshot: DashboardSnapshot
    let palette: DashPalette
    let onTap: () -> Void
    
    @State private var isHovered = false
    
    
    var body: some View {
        let totals = self.snapshot.ai30Totals
        let todayTotals = self.snapshot.aiTodayTotals
        let displayTokens = todayTotals.totalTokens > 0 ? todayTotals.totalTokens : totals.totalTokens
        let displayReqs = todayTotals.requests > 0 ? todayTotals.requests : totals.requests
        let scopeTag = todayTotals.totalTokens > 0 ? "今日" : "30日"
        
        let inTok = max(0, totals.inputTokens)
        let outTok = max(0, totals.outputTokens)
        let inFrac: Double = (inTok + outTok) > 0 ? Double(inTok) / Double(inTok + outTok) : 0.62
        let inPct = Int((inFrac * 100).rounded())
        let outPct = max(0, 100 - inPct)
        
        let topModels: [(name: String, share: Int, color: Color)] = {
            let colors: [Color] = [self.palette.accentFill, self.palette.emerald, self.palette.mint]
            let models = Array(self.snapshot.aiModels.prefix(3))
            if !models.isEmpty {
                let sum = max(1.0, models.reduce(0.0) { $0 + Double($1.totalTokens > 0 ? $1.totalTokens : max(1, $1.requests * 150)) })
                return models.enumerated().map { idx, m in
                    let w = Double(m.totalTokens > 0 ? m.totalTokens : max(1, m.requests * 150))
                    let short = m.model.count <= 12 ? m.model : String(m.model.prefix(11)) + "…"
                    return (short, Int(((w / sum) * 100).rounded()), colors[idx % colors.count])
                }
            }
            return [
                ("主力模型", 62, self.palette.accentFill),
                ("轻量模型", 38, self.palette.mint),
            ]
        }()
        
        Button(action: self.onTap) {
            HStack(spacing: 14) {
                // Left Zone: Interactive Mini Sunburst Dial with Live Center Readout
                ZStack {
                    AIUsageSunburstChartView(snapshot: self.snapshot, palette: self.palette, detailed: false)
                        .frame(width: 102, height: 102)
                    
                    VStack(spacing: 0) {
                        Text(Self.compactTokens(displayTokens))
                            .font(.system(size: 12, weight: .bold, design: .rounded).monospacedDigit())
                            .foregroundStyle(self.palette.pine)
                        Text(scopeTag)
                            .font(.system(size: 8.5, weight: .medium))
                            .foregroundStyle(self.palette.pine.opacity(0.46))
                    }
                    .allowsHitTesting(false)
                }
                .frame(width: 104, height: 104)
                
                // Right Zone: Live-Activity Telemetry Stack (Input/Output Luminous Bar + Model Mix + 14D Pulse Ticks)
                VStack(alignment: .leading, spacing: 8) {
                    // Header row: Hero Token Readout + Request Count + Drill-Down Hint
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        HStack(alignment: .firstTextBaseline, spacing: 3) {
                            Text(Self.compactTokens(totals.totalTokens))
                                .font(.system(size: 18, weight: .bold, design: .rounded).monospacedDigit())
                                .foregroundStyle(self.palette.pine)
                            Text("tokens")
                                .font(.system(size: 10, weight: .medium, design: .rounded))
                                .foregroundStyle(self.palette.pine.opacity(0.46))
                        }
                        
                        Text("\(displayReqs) req")
                            .font(.system(size: 10, weight: .semibold, design: .rounded).monospacedDigit())
                            .foregroundStyle(self.palette.emerald)
                            .padding(.horizontal, 6.5)
                            .padding(.vertical, 2)
                            .background(self.palette.accentFill.opacity(0.12), in: Capsule())
                        
                        Spacer(minLength: 4)
                        
                        HStack(spacing: 3) {
                            Text("旭日下钻")
                                .font(.system(size: 10, weight: .medium))
                            Image(systemName: "arrow.up.left.and.arrow.down.right")
                                .font(.system(size: 8.5, weight: .semibold))
                        }
                        .foregroundStyle(self.isHovered ? self.palette.emerald : self.palette.pine.opacity(0.44))
                    }
                    
                    // Middle: Now / Sunset / Dusk inspired Input ↔ Output Luminous Split Capsule
                    VStack(spacing: 4) {
                        GeometryReader { barGeo in
                            let w = max(40, barGeo.size.width)
                            let splitX = max(14, min(w - 14, w * CGFloat(inFrac)))
                            ZStack(alignment: .leading) {
                                Capsule()
                                    .fill(self.palette.inset)
                                
                                HStack(spacing: 2) {
                                    Capsule()
                                        .fill(
                                            LinearGradient(
                                                colors: [self.palette.accentFill.opacity(0.75), self.palette.accentFill],
                                                startPoint: .leading,
                                                endPoint: .trailing
                                            )
                                        )
                                        .frame(width: max(8, splitX - 1))
                                    
                                    Capsule()
                                        .fill(
                                            LinearGradient(
                                                colors: [self.palette.mint, self.palette.emerald],
                                                startPoint: .leading,
                                                endPoint: .trailing
                                            )
                                        )
                                        .frame(maxWidth: .infinity)
                                }
                                
                                Circle()
                                    .fill(self.palette.card)
                                    .frame(width: 7, height: 7)
                                    .overlay(Circle().strokeBorder(self.palette.emerald, lineWidth: 1.4))
                                    .offset(x: splitX - 3.5)
                            }
                        }
                        .frame(height: 9)
                        
                        HStack {
                            Text("输入 \(inPct)%")
                                .font(.system(size: 9.5, weight: .semibold, design: .rounded).monospacedDigit())
                                .foregroundStyle(self.palette.pine.opacity(0.62))
                            Spacer()
                            Text("生成 \(outPct)%")
                                .font(.system(size: 9.5, weight: .semibold, design: .rounded).monospacedDigit())
                                .foregroundStyle(self.palette.emerald.opacity(0.86))
                        }
                    }
                    
                    // Bottom: Top Models Chips + Espresso-style 14D AI Activity Pulse Ticks
                    HStack(alignment: .bottom, spacing: 8) {
                        HStack(spacing: 5) {
                            ForEach(Array(topModels.prefix(2).enumerated()), id: \.offset) { _, m in
                                HStack(spacing: 4) {
                                    Circle()
                                        .fill(m.color)
                                        .frame(width: 5, height: 5)
                                    Text(m.name)
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundStyle(self.palette.pine.opacity(0.78))
                                        .lineLimit(1)
                                    Text("\(m.share)%")
                                        .font(.system(size: 9.5, weight: .semibold, design: .rounded).monospacedDigit())
                                        .foregroundStyle(self.palette.pine.opacity(0.46))
                                }
                                .padding(.horizontal, 6.5)
                                .padding(.vertical, 3)
                                .background(self.palette.inset.opacity(0.85), in: Capsule())
                            }
                        }
                        
                        Spacer(minLength: 4)
                        
                        // 14-day AI pulse mini-ticks (Espresso meter inspired)
                        HStack(alignment: .bottom, spacing: 2.5) {
                            let aiMax = max(20.0, self.snapshot.days14.map { Double($0.ai) }.max() ?? 20.0)
                            ForEach(Array(self.snapshot.days14.suffix(10).enumerated()), id: \.offset) { idx, day in
                                let frac = CGFloat(Double(day.ai) / aiMax)
                                let h = max(4, frac * 18)
                                Capsule()
                                    .fill(day.ai > 0 ? (idx == 9 ? self.palette.emerald : self.palette.accentFill.opacity(0.45 + 0.45 * Double(frac))) : self.palette.emptyDot)
                                    .frame(width: 3, height: h)
                            }
                        }
                        .frame(height: 18, alignment: .bottom)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .dashboardCardSurface(palette: self.palette, cornerRadius: 18, isHighlighted: self.isHovered)
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .scaleEffect(self.isHovered ? 1.01 : 1.0)
        .animation(DashMotion.quick, value: self.isHovered)
        .onHover { hovering in
            self.isHovered = hovering
        }
    }
    
    
    private static func compactTokens(_ value: Int) -> String {
        if value >= 1_000_000 { return String(format: "%.1fM", Double(value) / 1_000_000.0) }
        if value >= 1_000 { return String(format: "%.1fK", Double(value) / 1_000.0) }
        return value.formatted()
    }
}


// MARK: - Compact & Expanded Quad Cards (Live-Activity Micro-Instruments)

private struct DashboardCompactQuadCard: View {
    
    let metric: DashboardQuadMetric
    let snapshot: DashboardSnapshot
    let palette: DashPalette
    let onTap: () -> Void
    
    @State private var isHovered = false
    
    
    var body: some View {
        Button {
            self.onTap()
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                // Live-Activity telemetry header: hero tabular value + muted unit (left), crisp badge (right)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text(self.heroValueText)
                            .font(.system(size: 16, weight: .bold, design: .rounded).monospacedDigit())
                            .foregroundStyle(self.palette.pine)
                            .lineLimit(1)
                        
                        Text(self.heroUnitText)
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundStyle(self.palette.pine.opacity(0.46))
                            .lineLimit(1)
                    }
                    
                    Spacer(minLength: 4)
                    
                    HStack(spacing: 4) {
                        Circle()
                            .fill(self.indicatorTint)
                            .frame(width: 5, height: 5)
                        Text(self.secondaryBadgeText)
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundStyle(self.palette.pine.opacity(0.62))
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(self.palette.inset.opacity(0.85), in: Capsule())
                }
                
                self.miniVisualization
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(12)
            .dashboardCardSurface(palette: self.palette, cornerRadius: 18, isHighlighted: self.isHovered)
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .scaleEffect(self.isHovered ? 1.014 : 1.0)
        .animation(DashMotion.quick, value: self.isHovered)
        .onHover { hovering in
            self.isHovered = hovering
        }
    }
    
    
    private var heroValueText: String {
        switch self.metric {
            case .typed:
                let total = self.snapshot.today.typedChars + self.snapshot.today.aiCompletedChars
                return total.formatted()
            case .aiUsage:
                let val = self.snapshot.aiTodayTotals.totalTokens > 0
                    ? self.snapshot.aiTodayTotals.totalTokens
                    : self.snapshot.ai30Totals.totalTokens
                return self.formatTokens(val)
            case .busyness:
                return "\(self.snapshot.busyness.score)"
            case .mood:
                return "\(self.snapshot.mood.score)"
        }
    }
    
    
    private var heroUnitText: String {
        switch self.metric {
            case .typed: "字"
            case .aiUsage: "tok"
            case .busyness: "%"
            case .mood: self.snapshot.mood.dominantLabel
        }
    }
    
    
    private var secondaryBadgeText: String {
        switch self.metric {
            case .typed: "今日码字"
            case .aiUsage: "AI用量"
            case .busyness: "峰值 \(self.snapshot.busyness.peakHourLabel)"
            case .mood: "情绪指数"
        }
    }
    
    
    private var indicatorTint: Color {
        switch self.metric {
            case .typed: self.palette.accentFill
            case .aiUsage: self.palette.emerald
            case .busyness: Color(red: 0.90, green: 0.56, blue: 0.24)
            case .mood: self.palette.mint
        }
    }
    
    
    private func formatTokens(_ value: Int) -> String {
        if value >= 10_000 {
            return String(format: "%.1fK", Double(value) / 1000.0)
        }
        return value.formatted()
    }
    
    
    @ViewBuilder
    private var miniVisualization: some View {
        switch self.metric {
            case .typed:
                TrendAreaChartView(days: self.snapshot.days14, palette: self.palette, detailed: false)
            case .aiUsage:
                AIUsageSunburstChartView(snapshot: self.snapshot, palette: self.palette, detailed: false)
            case .busyness:
                NightingaleRoseChartView(metrics: self.snapshot.busyness, palette: self.palette, detailed: false)
            case .mood:
                EmotionSankeyChartView(snapshot: self.snapshot, palette: self.palette, detailed: false)
        }
    }
}


private struct DashboardExpandedQuadCard: View {
    
    let metric: DashboardQuadMetric
    let snapshot: DashboardSnapshot
    let palette: DashPalette
    let onClose: () -> Void
    
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 10) {
                Text(self.metric.title)
                    .font(.system(size: 14.5, weight: .semibold))
                    .foregroundStyle(self.palette.pine)
                
                Text(self.detailHeadline)
                    .font(.system(size: 13.5, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(self.palette.emerald)
                    .lineLimit(1)
                
                Spacer()
                
                Button(action: self.onClose) {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(self.palette.pine.opacity(0.70))
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(self.palette.inset))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
            }
            
            self.detailedVisualization
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(16)
        .dashboardCardSurface(palette: self.palette, cornerRadius: 18, isHighlighted: true)
    }
    
    
    private var detailHeadline: String {
        switch self.metric {
            case .typed:
                let hand = self.snapshot.today.typedChars
                let ai = self.snapshot.today.aiCompletedChars
                return "\((hand + ai).formatted()) 字 (手写 \(hand.formatted()) / AI \(ai.formatted()))"
            case .aiUsage:
                return "\(self.snapshot.ai30Totals.totalTokens.formatted()) tokens · \(self.snapshot.ai30Totals.requests) 次请求"
            case .busyness:
                return "\(self.snapshot.busyness.score)% · 峰值 \(self.snapshot.busyness.peakHourLabel) · 活跃 \(self.snapshot.busyness.activeHours)h"
            case .mood:
                return "\(self.snapshot.mood.score) · 主导 \(self.snapshot.mood.dominantLabel)"
        }
    }
    
    
    @ViewBuilder
    private var detailedVisualization: some View {
        switch self.metric {
            case .typed:
                TrendAreaChartView(days: self.snapshot.days14, palette: self.palette, detailed: true)
            case .aiUsage:
                AIUsageSunburstChartView(snapshot: self.snapshot, palette: self.palette, detailed: true)
            case .busyness:
                NightingaleRoseChartView(metrics: self.snapshot.busyness, palette: self.palette, detailed: true)
            case .mood:
                EmotionSankeyChartView(snapshot: self.snapshot, palette: self.palette, detailed: true)
        }
    }
}


// MARK: - Chart 1: Trend Area-Line Chart (趋势图)

private struct TrendAreaChartView: View {
    
    let days: [DashboardSnapshot.ChartDay]
    let palette: DashPalette
    let detailed: Bool
    
    @State private var hoverIndex: Int?
    
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { geo in
                let padL: CGFloat = self.detailed ? 36 : 4
                let padR: CGFloat = self.detailed ? 10 : 4
                let padT: CGFloat = self.detailed ? 12 : 6
                let padB: CGFloat = self.detailed ? 22 : 4
                let plotW = max(40, geo.size.width - padL - padR)
                let plotH = max(30, geo.size.height - padT - padB)
                let totals = self.days.map { Double($0.typed + $0.ai) }
                let maxVal = max(100.0, totals.max() ?? 100.0)
                let count = max(2, self.days.count)
                
                let points: [CGPoint] = totals.enumerated().map { idx, val in
                    let x = padL + (CGFloat(idx) / CGFloat(count - 1)) * plotW
                    let y = padT + (1.0 - CGFloat(val / maxVal)) * plotH
                    return CGPoint(x: x, y: y)
                }
                let typedPoints: [CGPoint] = self.days.enumerated().map { idx, item in
                    let x = padL + (CGFloat(idx) / CGFloat(count - 1)) * plotW
                    let y = padT + (1.0 - CGFloat(Double(item.typed) / maxVal)) * plotH
                    return CGPoint(x: x, y: y)
                }
                
                Canvas { context, canvasSize in
                    guard canvasSize.width.isFinite, canvasSize.height.isFinite,
                          canvasSize.width > 8, canvasSize.height > 8 else { return }
                    if self.detailed {
                        for frac in [0.0, 0.5, 1.0] {
                            let y = padT + CGFloat(frac) * plotH
                            var grid = Path()
                            grid.move(to: CGPoint(x: padL, y: y))
                            grid.addLine(to: CGPoint(x: padL + plotW, y: y))
                            context.stroke(grid, with: .color(self.palette.hairline), lineWidth: 0.7)
                            
                            let valText = Int((maxVal * (1.0 - frac)).rounded()).formatted()
                            context.draw(
                                Text(valText)
                                    .font(.system(size: 9.5, design: .rounded).monospacedDigit())
                                    .foregroundStyle(self.palette.pine.opacity(0.45)),
                                at: CGPoint(x: padL - 6, y: y),
                                anchor: .trailing
                            )
                        }
                    }
                    
                    guard points.count >= 2, let firstPt = points.first, let lastPt = points.last else { return }
                    let linePath = Self.smoothPath(points: points)
                    var areaPath = linePath
                    areaPath.addLine(to: CGPoint(x: lastPt.x, y: padT + plotH))
                    areaPath.addLine(to: CGPoint(x: firstPt.x, y: padT + plotH))
                    areaPath.closeSubpath()
                    
                    context.fill(
                        areaPath,
                        with: .linearGradient(
                            Gradient(colors: [
                                self.palette.accentFill.opacity(0.32),
                                self.palette.accentFill.opacity(0.02),
                            ]),
                            startPoint: CGPoint(x: padL, y: padT),
                            endPoint: CGPoint(x: padL, y: padT + plotH)
                        )
                    )
                    
                    if self.detailed {
                        let typedCurve = Self.smoothPath(points: typedPoints)
                        context.stroke(
                            typedCurve,
                            with: .color(self.palette.mint.opacity(0.75)),
                            style: StrokeStyle(lineWidth: 1.4, lineCap: .round, dash: [4, 3])
                        )
                    }
                    
                    context.stroke(
                        linePath,
                        with: .color(self.palette.emerald),
                        style: StrokeStyle(lineWidth: self.detailed ? 2.2 : 1.8, lineCap: .round, lineJoin: .round)
                    )
                    
                    if let last = points.last {
                        let dotRect = CGRect(x: last.x - 3.5, y: last.y - 3.5, width: 7, height: 7)
                        context.fill(Circle().path(in: dotRect), with: .color(self.palette.emerald))
                    }
                    
                    if self.detailed, let hover = self.hoverIndex, hover >= 0, hover < points.count {
                        let pt = points[hover]
                        var guide = Path()
                        guide.move(to: CGPoint(x: pt.x, y: padT))
                        guide.addLine(to: CGPoint(x: pt.x, y: padT + plotH))
                        context.stroke(guide, with: .color(self.palette.pine.opacity(0.28)), lineWidth: 0.9)
                        
                        let dotRect = CGRect(x: pt.x - 4.5, y: pt.y - 4.5, width: 9, height: 9)
                        context.fill(Circle().path(in: dotRect), with: .color(self.palette.card))
                        context.stroke(Circle().path(in: dotRect), with: .color(self.palette.emerald), lineWidth: 2)
                    }
                    
                    if self.detailed {
                        let step = max(1, self.days.count / 5)
                        for idx in stride(from: 0, to: self.days.count, by: step) {
                            let pt = points[idx]
                            let label = Self.dayFmt.string(from: self.days[idx].date)
                            context.draw(
                                Text(label)
                                    .font(.system(size: 9.5, design: .rounded))
                                    .foregroundStyle(self.palette.pine.opacity(0.48)),
                                at: CGPoint(x: pt.x, y: padT + plotH + 12),
                                anchor: .center
                            )
                        }
                    }
                }
                .onContinuousHover { phase in
                    guard self.detailed else { return }
                    switch phase {
                        case .active(let loc):
                            let ratio = (loc.x - padL) / max(1, plotW)
                            let idx = Int((ratio * CGFloat(count - 1)).rounded())
                            self.hoverIndex = min(max(0, idx), count - 1)
                        case .ended:
                            self.hoverIndex = nil
                    }
                }
            }
            
            if self.detailed {
                let caption: String = if let idx = self.hoverIndex, idx < self.days.count {
                    {
                        let d = self.days[idx]
                        return "\(Self.dayFmt.string(from: d.date)) · 总计 \((d.typed + d.ai).formatted()) 字 (手写 \(d.typed.formatted()) / AI \(d.ai.formatted()))"
                    }()
                } else {
                    " "
                }
                Text(caption)
                    .font(.system(size: 11, weight: .medium, design: .rounded).monospacedDigit())
                    .foregroundStyle(self.palette.pine.opacity(0.75))
                    .frame(height: 16)
            }
        }
    }
    
    
    private static func smoothPath(points: [CGPoint]) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: first)
        for idx in 1..<points.count {
            let prev = points[idx - 1]
            let curr = points[idx]
            let midX = (prev.x + curr.x) * 0.5
            path.addCurve(
                to: curr,
                control1: CGPoint(x: midX, y: prev.y),
                control2: CGPoint(x: midX, y: curr.y)
            )
        }
        return path
    }
    
    
    private static let dayFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "M/d"
        return f
    }()
}


// MARK: - Chart 2: AI Usage Interactive Drill-Down Sunburst Chart (AI 用量 · 可下钻旭日图)

private struct AIUsageSunburstChartView: View {
    
    let snapshot: DashboardSnapshot
    let palette: DashPalette
    let detailed: Bool
    
    @State private var drillPath: [String] = []
    @State private var hoveredNodeID: String?
    @State private var hoveredCaption: String?
    
    private struct SunburstNode: Identifiable {
        let id: String
        let label: String
        let weight: Double
        let detailText: String
        let color: Color
        let children: [SunburstNode]
    }
    
    private struct HitArc {
        let node: SunburstNode
        let pathToNode: [String]
        let innerR: CGFloat
        let outerR: CGFloat
        let startDeg: Double
        let endDeg: Double
        let caption: String
    }
    
    
    private func buildRootNode() -> SunburstNode {
        let modelColors: [Color] = [
            self.palette.accentFill,
            self.palette.emerald,
            self.palette.mint,
            self.palette.heat(2),
            self.palette.paleMint,
        ]
        
        let totals = self.snapshot.ai30Totals
        let totalIn = max(0, totals.inputTokens)
        let totalOut = max(0, totals.outputTokens)
        let inRatio: Double = (totalIn + totalOut) > 0
            ? Double(totalIn) / Double(totalIn + totalOut)
            : 0.62
        let outRatio: Double = 1.0 - inRatio
        
        func tokenSplitLeaves(parentID: String, parentWeight: Double, baseColor: Color) -> [SunburstNode] {
            let inW = max(1.0, parentWeight * inRatio)
            let outW = max(1.0, parentWeight * outRatio)
            let inPct = Int((inRatio * 100).rounded())
            let outPct = max(0, 100 - inPct)
            return [
                SunburstNode(
                    id: "\(parentID)-in",
                    label: "输入",
                    weight: inW,
                    detailText: "输入 Token · \(Self.compactTokens(Int(inW.rounded()))) (\(inPct)%)",
                    color: baseColor.opacity(0.86),
                    children: []
                ),
                SunburstNode(
                    id: "\(parentID)-out",
                    label: "生成",
                    weight: outW,
                    detailText: "生成 Token · \(Self.compactTokens(Int(outW.rounded()))) (\(outPct)%)",
                    color: baseColor.opacity(0.54),
                    children: []
                ),
            ]
        }
        
        func featureNodes(parentID: String, parentWeight: Double, baseColor: Color) -> [SunburstNode] {
            let feats = Array(self.snapshot.aiFeatures.prefix(4))
            if !feats.isEmpty {
                let rawSum = max(1.0, feats.reduce(0.0) { $0 + Double($1.totalTokens > 0 ? $1.totalTokens : max(1, $1.requests * 120)) })
                return feats.enumerated().map { idx, f in
                    let name = f.displayName.isEmpty ? f.feature : f.displayName
                    let rawW = Double(f.totalTokens > 0 ? f.totalTokens : max(1, f.requests * 120))
                    let scaledW = max(1.0, parentWeight * (rawW / rawSum))
                    let fid = "\(parentID)-feat-\(idx)"
                    let tint = baseColor.opacity(idx.isMultiple(of: 2) ? 0.78 : 0.60)
                    return SunburstNode(
                        id: fid,
                        label: name,
                        weight: scaledW,
                        detailText: "\(name) · \(f.requests) 次 · \(Self.compactTokens(Int(scaledW.rounded())))",
                        color: tint,
                        children: tokenSplitLeaves(parentID: fid, parentWeight: scaledW, baseColor: baseColor)
                    )
                }
            }
            
            let defaults: [(String, Double)] = [("续写", 0.44), ("翻译", 0.30), ("摘要", 0.26)]
            return defaults.enumerated().map { idx, item in
                let w = max(1.0, parentWeight * item.1)
                let fid = "\(parentID)-def-\(idx)"
                return SunburstNode(
                    id: fid,
                    label: item.0,
                    weight: w,
                    detailText: "\(item.0) · 占比 \(Int((item.1 * 100).rounded()))%",
                    color: baseColor.opacity(idx.isMultiple(of: 2) ? 0.76 : 0.56),
                    children: tokenSplitLeaves(parentID: fid, parentWeight: w, baseColor: baseColor)
                )
            }
        }
        
        let models = Array(self.snapshot.aiModels.prefix(5))
        let modelNodes: [SunburstNode]
        if !models.isEmpty {
            modelNodes = models.enumerated().map { idx, m in
                let shortName = Self.shortName(m.model)
                let w = Double(m.totalTokens > 0 ? m.totalTokens : max(1, m.requests * 150))
                let color = modelColors[idx % modelColors.count]
                let mid = "model-\(idx)-\(shortName)"
                return SunburstNode(
                    id: mid,
                    label: shortName,
                    weight: w,
                    detailText: "\(shortName) · \(m.requests) 次 · \(Self.compactTokens(m.totalTokens)) tokens",
                    color: color,
                    children: featureNodes(parentID: mid, parentWeight: w, baseColor: color)
                )
            }
        } else {
            let fallbackModels: [(String, Double, Color)] = [
                ("主力模型", 62, self.palette.accentFill),
                ("轻量模型", 38, self.palette.mint),
            ]
            modelNodes = fallbackModels.enumerated().map { idx, item in
                let mid = "fallback-\(idx)"
                return SunburstNode(
                    id: mid,
                    label: item.0,
                    weight: item.1,
                    detailText: "\(item.0) · 占比 \(Int(item.1))%",
                    color: item.2,
                    children: featureNodes(parentID: mid, parentWeight: item.1, baseColor: item.2)
                )
            }
        }
        
        let totalWeight = max(1.0, modelNodes.reduce(0.0) { $0 + $1.weight })
        let rootSummary = totals.totalTokens > 0
            ? Self.compactTokens(totals.totalTokens)
            : "\(totals.requests)次"
        return SunburstNode(
            id: "root",
            label: "总用量",
            weight: totalWeight,
            detailText: rootSummary,
            color: self.palette.accentFill,
            children: modelNodes
        )
    }
    
    
    private func resolveActiveScope(from root: SunburstNode) -> (node: SunburstNode, trail: [(path: [String], title: String)]) {
        var current = root
        var trail: [(path: [String], title: String)] = [([], root.label)]
        var accumulated: [String] = []
        for id in self.drillPath {
            guard let next = current.children.first(where: { $0.id == id }) else { break }
            accumulated.append(id)
            current = next
            trail.append((accumulated, next.label))
        }
        return (current, trail)
    }
    
    
    private func layoutArcs(for scope: SunburstNode, in size: CGSize) -> (arcs: [HitArc], center: CGPoint, rCore: CGFloat) {
        let center = CGPoint(x: size.width * 0.5, y: size.height * 0.5)
        let outerLimit = max(18, min(size.width, size.height) * 0.5 - (self.detailed ? 10 : 4))
        let hasGrandchildren = scope.children.contains { !$0.children.isEmpty }
        let rCore = max(14, outerLimit * (self.detailed ? 0.34 : 0.32))
        let rMid = hasGrandchildren
            ? max(rCore + 6, outerLimit * 0.67)
            : outerLimit
        let rOuter = max(rMid + 6, outerLimit)
        
        let totalWeight = max(1.0, scope.children.reduce(0.0) { $0 + $1.weight })
        var cursorDeg = 0.0
        var arcs: [HitArc] = []
        
        for child in scope.children {
            let spanDeg = (child.weight / totalWeight) * 360.0
            let pct = Int(((child.weight / totalWeight) * 100).rounded())
            let drillHint = child.children.isEmpty ? "" : " · 点击下钻"
            arcs.append(HitArc(
                node: child,
                pathToNode: [child.id],
                innerR: rCore,
                outerR: hasGrandchildren ? (rMid - 1.5) : rOuter,
                startDeg: cursorDeg,
                endDeg: cursorDeg + spanDeg,
                caption: "\(child.detailText) (\(pct)%)\(drillHint)"
            ))
            
            if hasGrandchildren && !child.children.isEmpty {
                let grandSum = max(1.0, child.children.reduce(0.0) { $0 + $1.weight })
                var grandCursor = cursorDeg
                for grand in child.children {
                    let gSpan = (grand.weight / grandSum) * spanDeg
                    let gPct = Int(((grand.weight / grandSum) * 100).rounded())
                    let gHint = grand.children.isEmpty ? "" : " · 点击下钻"
                    arcs.append(HitArc(
                        node: grand,
                        pathToNode: [child.id, grand.id],
                        innerR: rMid + 1.5,
                        outerR: rOuter,
                        startDeg: grandCursor,
                        endDeg: grandCursor + gSpan,
                        caption: "\(child.label) → \(grand.detailText) (\(gPct)%)\(gHint)"
                    ))
                    grandCursor += gSpan
                }
            }
            cursorDeg += spanDeg
        }
        return (arcs, center, rCore)
    }
    
    
    var body: some View {
        let root = self.buildRootNode()
        let resolved = self.resolveActiveScope(from: root)
        let activeNode = resolved.node
        let trail = resolved.trail
        let isDrilled = !self.drillPath.isEmpty
        
        VStack(spacing: 4) {
            if self.detailed {
                // Interactive drill-down breadcrumb trail
                HStack(spacing: 4) {
                    ForEach(Array(trail.enumerated()), id: \.offset) { idx, crumb in
                        if idx > 0 {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 8.5, weight: .semibold))
                                .foregroundStyle(self.palette.pine.opacity(0.32))
                        }
                        let isCurrent = (idx == trail.count - 1)
                        Button {
                            withAnimation(DashMotion.standard) {
                                self.drillPath = crumb.path
                                self.hoveredNodeID = nil
                                self.hoveredCaption = nil
                            }
                        } label: {
                            Text(crumb.title)
                                .font(.system(size: 10.5, weight: isCurrent ? .semibold : .medium))
                                .foregroundStyle(isCurrent ? self.palette.emerald : self.palette.pine.opacity(0.62))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(
                                    Capsule()
                                        .fill(isCurrent ? self.palette.accentFill.opacity(0.14) : Color.clear)
                                )
                        }
                        .buttonStyle(.plain)
                        .disabled(isCurrent)
                    }
                    Spacer(minLength: 4)
                    if isDrilled {
                        Button {
                            withAnimation(DashMotion.standard) {
                                self.drillPath.removeLast()
                                self.hoveredNodeID = nil
                                self.hoveredCaption = nil
                            }
                        } label: {
                            HStack(spacing: 2) {
                                Image(systemName: "arrow.uturn.left")
                                    .font(.system(size: 9, weight: .semibold))
                                Text("返回上级")
                                    .font(.system(size: 10, weight: .medium))
                            }
                            .foregroundStyle(self.palette.pine.opacity(0.65))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(height: 18)
            }
            
            GeometryReader { geo in
                let layout = self.layoutArcs(for: activeNode, in: geo.size)
                
                Canvas { context, size in
                    guard size.width.isFinite, size.height.isFinite,
                          size.width > 8, size.height > 8 else { return }
                    let center = layout.center
                    let rCore = layout.rCore
                    
                    for arc in layout.arcs {
                        let span = arc.endDeg - arc.startDeg
                        let pad = min(1.0, span * 0.14)
                        let sDeg = arc.startDeg - 90.0 + pad
                        let eDeg = arc.endDeg - 90.0 - pad
                        guard eDeg > sDeg else { continue }
                        
                        var sector = Path()
                        sector.addArc(center: center, radius: arc.innerR, startAngle: .degrees(sDeg), endAngle: .degrees(eDeg), clockwise: false)
                        sector.addArc(center: center, radius: arc.outerR, startAngle: .degrees(eDeg), endAngle: .degrees(sDeg), clockwise: true)
                        sector.closeSubpath()
                        
                        let isHovered = (self.hoveredNodeID == arc.node.id)
                        let isInner = (arc.pathToNode.count == 1)
                        let baseAlpha: Double = isInner ? 0.90 : 0.68
                        let alpha = isHovered ? 1.0 : (self.hoveredNodeID == nil ? baseAlpha : baseAlpha * 0.72)
                        context.fill(sector, with: .color(arc.node.color.opacity(alpha)))
                        
                        if isHovered {
                            context.stroke(sector, with: .color(self.palette.card.opacity(0.95)), lineWidth: 1.6)
                        }
                        
                        if self.detailed && span > (isInner ? 28 : 22) {
                            let midRad = (sDeg + eDeg) * 0.5 * .pi / 180.0
                            let labelR = (arc.innerR + arc.outerR) * 0.5
                            context.draw(
                                Text(arc.node.label)
                                    .font(.system(size: isInner ? 10 : 9.5, weight: isInner ? .semibold : .medium))
                                    .foregroundStyle(isInner ? self.palette.tokens.onAccentInk : self.palette.pine.opacity(0.92)),
                                at: CGPoint(x: center.x + CGFloat(cos(midRad)) * labelR, y: center.y + CGFloat(sin(midRad)) * labelR),
                                anchor: .center
                            )
                        }
                    }
                    
                    let coreRect = CGRect(x: center.x - rCore + 2, y: center.y - rCore + 2, width: (rCore - 2) * 2, height: (rCore - 2) * 2)
                    context.fill(Circle().path(in: coreRect), with: .color(self.palette.card))
                    if isDrilled && self.detailed {
                        context.stroke(Circle().path(in: coreRect), with: .color(self.palette.hairlineStrong), lineWidth: 0.9)
                    }
                    if self.detailed {
                        let primaryCenter = isDrilled
                            ? activeNode.label
                            : activeNode.detailText
                        context.draw(
                            Text(primaryCenter)
                                .font(.system(size: isDrilled ? 11.5 : 13, weight: .bold, design: .rounded).monospacedDigit())
                                .foregroundStyle(self.palette.pine),
                            at: CGPoint(x: center.x, y: isDrilled ? center.y - 6 : center.y),
                            anchor: .center
                        )
                        if isDrilled {
                            context.draw(
                                Text("‹ 返回")
                                    .font(.system(size: 9.5, weight: .medium))
                                    .foregroundStyle(self.palette.emerald),
                                at: CGPoint(x: center.x, y: center.y + 9),
                                anchor: .center
                            )
                        }
                    }
                }
                .contentShape(Rectangle())
                .onContinuousHover { phase in
                    guard self.detailed else { return }
                    switch phase {
                        case .active(let loc):
                            if let hit = self.hitTestArc(loc, layout: layout) {
                                self.hoveredNodeID = hit.node.id
                                self.hoveredCaption = hit.caption
                            } else {
                                self.hoveredNodeID = nil
                                let dist = hypot(loc.x - layout.center.x, loc.y - layout.center.y)
                                if isDrilled && dist < layout.rCore {
                                    self.hoveredCaption = "点击中心返回上一级"
                                } else {
                                    self.hoveredCaption = nil
                                }
                            }
                        case .ended:
                            self.hoveredNodeID = nil
                            self.hoveredCaption = nil
                    }
                }
                .onTapGesture { loc in
                    guard self.detailed else { return }
                    let dist = hypot(loc.x - layout.center.x, loc.y - layout.center.y)
                    if dist < layout.rCore {
                        if !self.drillPath.isEmpty {
                            withAnimation(DashMotion.standard) {
                                self.drillPath.removeLast()
                                self.hoveredNodeID = nil
                                self.hoveredCaption = nil
                            }
                        }
                        return
                    }
                    if let hit = self.hitTestArc(loc, layout: layout), !hit.node.children.isEmpty {
                        withAnimation(DashMotion.standard) {
                            self.drillPath.append(contentsOf: hit.pathToNode)
                            self.hoveredNodeID = nil
                            self.hoveredCaption = nil
                        }
                    }
                }
            }
            
            if self.detailed {
                Text(self.hoveredCaption ?? (isDrilled ? "点击扇区继续下钻 · 点击中心或路径返回" : "点击任意模型或功能扇区下钻查看明细"))
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundStyle(self.palette.pine.opacity(self.hoveredCaption == nil ? 0.50 : 0.84))
                    .lineLimit(1)
                    .frame(height: 16)
            }
        }
    }
    
    
    private func hitTestArc(
        _ point: CGPoint,
        layout: (arcs: [HitArc], center: CGPoint, rCore: CGFloat)
    ) -> HitArc? {
        let dist = hypot(point.x - layout.center.x, point.y - layout.center.y)
        guard dist >= layout.rCore else { return nil }
        var deg = atan2(point.y - layout.center.y, point.x - layout.center.x) * 180.0 / .pi + 90.0
        if deg < 0 { deg += 360.0 }
        for arc in layout.arcs {
            if dist >= arc.innerR && dist <= arc.outerR && deg >= arc.startDeg && deg <= arc.endDeg {
                return arc
            }
        }
        return nil
    }
    
    
    private static func shortName(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.count <= 10 ? trimmed : String(trimmed.prefix(9)) + "…"
    }
    
    
    private static func compactTokens(_ value: Int) -> String {
        if value >= 1_000_000 { return String(format: "%.1fM", Double(value) / 1_000_000.0) }
        if value >= 1_000 { return String(format: "%.1fK", Double(value) / 1_000.0) }
        return value.formatted()
    }
}


// MARK: - Chart 3: Busyness Live-Activity Segmented Meter (Compact) & Nightingale Rose (Expanded)

private struct NightingaleRoseChartView: View {
    
    let metrics: BusynessMetrics
    let palette: DashPalette
    let detailed: Bool
    
    @State private var hoveredSliceIndex: Int?
    
    
    var body: some View {
        if !self.detailed {
            self.compactLiveActivityMeter
        } else {
            self.expandedRoseChart
        }
    }
    
    
    /// Compact Live-Activity instrument: Espresso 12-slot segmented tick meter + ISS Flyover circadian peak arc.
    private var compactLiveActivityMeter: some View {
        let slices = self.metrics.slices
        let peakIdx = slices.max(by: { $0.intensity < $1.intensity })?.index ?? 6
        let peakFrac = Double(peakIdx) / Double(max(1, slices.count - 1))
        
        return VStack(spacing: 6) {
            // ISS Flyover–inspired circadian peak horizon arc
            GeometryReader { geo in
                Canvas { context, size in
                    guard size.width > 16, size.height > 12 else { return }
                    let padX: CGFloat = 10
                    let startPt = CGPoint(x: padX, y: size.height - 2)
                    let endPt = CGPoint(x: size.width - padX, y: size.height - 2)
                    let ctrlPt = CGPoint(x: size.width * 0.5, y: -size.height * 0.45)
                    
                    var arcPath = Path()
                    arcPath.move(to: startPt)
                    arcPath.addQuadCurve(to: endPt, control: ctrlPt)
                    context.stroke(arcPath, with: .color(self.palette.hairlineStrong), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    
                    // Glowing quadratic point along the orbital arc for peak hour
                    let t = CGFloat(peakFrac)
                    let oneMinus = 1.0 - t
                    let px = oneMinus * oneMinus * startPt.x + 2 * oneMinus * t * ctrlPt.x + t * t * endPt.x
                    let py = oneMinus * oneMinus * startPt.y + 2 * oneMinus * t * ctrlPt.y + t * t * endPt.y
                    
                    // Subtle scan beam cone beneath orbital dot
                    var cone = Path()
                    cone.move(to: CGPoint(x: px, y: py))
                    cone.addLine(to: CGPoint(x: px - 12, y: size.height))
                    cone.addLine(to: CGPoint(x: px + 12, y: size.height))
                    cone.closeSubpath()
                    context.fill(
                        cone,
                        with: .linearGradient(
                            Gradient(colors: [self.palette.accentFill.opacity(0.28), .clear]),
                            startPoint: CGPoint(x: px, y: py),
                            endPoint: CGPoint(x: px, y: size.height)
                        )
                    )
                    
                    let glowRect = CGRect(x: px - 5.5, y: py - 5.5, width: 11, height: 11)
                    context.fill(Circle().path(in: glowRect), with: .color(self.palette.accentFill.opacity(0.28)))
                    let dotRect = CGRect(x: px - 3.2, y: py - 3.2, width: 6.4, height: 6.4)
                    context.fill(Circle().path(in: dotRect), with: .color(self.palette.emerald))
                }
            }
            .frame(height: 22)
            
            // Espresso 12-slot vertical segmented intensity ticks
            HStack(alignment: .bottom, spacing: 3.5) {
                ForEach(slices, id: \.index) { slice in
                    let active = slice.intensity > 0.08
                    let tickColor: Color = if slice.index == peakIdx && active {
                        self.palette.emerald
                    } else if slice.intensity >= 0.55 {
                        self.palette.accentFill
                    } else if slice.intensity >= 0.25 {
                        self.palette.mint.opacity(0.85)
                    } else {
                        self.palette.emptyDot
                    }
                    RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                        .fill(tickColor)
                        .frame(maxWidth: .infinity)
                        .frame(height: active ? max(10, 26 * CGFloat(slice.intensity)) : 10)
                }
            }
            .frame(height: 26, alignment: .bottom)
            
            HStack {
                Text("00")
                Spacer()
                Text("06")
                Spacer()
                Text("12")
                Spacer()
                Text("18")
                Spacer()
                Text("24")
            }
            .font(.system(size: 8.5, weight: .medium, design: .monospaced).monospacedDigit())
            .foregroundStyle(self.palette.pine.opacity(0.40))
        }
        .padding(.top, 2)
    }
    
    
    private var expandedRoseChart: some View {
        VStack(spacing: 6) {
            GeometryReader { geo in
                Canvas { context, size in
                    guard size.width.isFinite, size.height.isFinite,
                          size.width > 8, size.height > 8 else { return }
                    let center = CGPoint(x: size.width * 0.5, y: size.height * 0.5)
                    let outerLimit = max(16, min(size.width, size.height) * 0.5 - 22)
                    let innerR = max(8, outerLimit * 0.22)
                    let maxPetalSpan = max(8, outerLimit - innerR)
                    
                    for frac in [0.35, 0.70, 1.0] {
                        let r = innerR + maxPetalSpan * CGFloat(frac)
                        let ringRect = CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)
                        context.stroke(
                            Circle().path(in: ringRect),
                            with: .color(self.palette.hairline),
                            lineWidth: 0.7
                        )
                    }
                    
                    let slices = self.metrics.slices
                    let stepAngle = 360.0 / Double(max(1, slices.count))
                    
                    for slice in slices {
                        let startDeg = -90.0 + Double(slice.index) * stepAngle + 1.5
                        let endDeg = -90.0 + Double(slice.index + 1) * stepAngle - 1.5
                        let petalOuter = innerR + maxPetalSpan * CGFloat(slice.intensity)
                        
                        var petal = Path()
                        petal.addArc(
                            center: center,
                            radius: innerR,
                            startAngle: .degrees(startDeg),
                            endAngle: .degrees(endDeg),
                            clockwise: false
                        )
                        petal.addArc(
                            center: center,
                            radius: petalOuter,
                            startAngle: .degrees(endDeg),
                            endAngle: .degrees(startDeg),
                            clockwise: true
                        )
                        petal.closeSubpath()
                        
                        let isHovered = (self.hoveredSliceIndex == slice.index)
                        let color: Color = {
                            if slice.intensity >= 0.75 { return self.palette.emerald }
                            if slice.intensity >= 0.45 { return self.palette.accentFill }
                            if slice.intensity >= 0.22 { return self.palette.mint }
                            return self.palette.emptyDot
                        }()
                        context.fill(petal, with: .color(color.opacity(isHovered ? 0.96 : 0.82)))
                        if isHovered {
                            context.stroke(petal, with: .color(self.palette.pine), lineWidth: 1.2)
                        }
                        
                        if slice.index.isMultiple(of: 2) {
                            let midRad = (startDeg + endDeg) * 0.5 * .pi / 180.0
                            let labelR = outerLimit + 12
                            let lx = center.x + CGFloat(cos(midRad)) * labelR
                            let ly = center.y + CGFloat(sin(midRad)) * labelR
                            context.draw(
                                Text(slice.label)
                                    .font(.system(size: 9.5, design: .rounded).monospacedDigit())
                                    .foregroundStyle(self.palette.pine.opacity(0.55)),
                                at: CGPoint(x: lx, y: ly),
                                anchor: .center
                            )
                        }
                    }
                    
                    let coreRect = CGRect(x: center.x - innerR + 1, y: center.y - innerR + 1, width: (innerR - 1) * 2, height: (innerR - 1) * 2)
                    context.fill(Circle().path(in: coreRect), with: .color(self.palette.card))
                }
                .onContinuousHover { phase in
                    switch phase {
                        case .active(let loc):
                            self.hoveredSliceIndex = self.hitTestPetal(loc, in: geo.size)
                        case .ended:
                            self.hoveredSliceIndex = nil
                    }
                }
            }
            
            let caption: String = if let idx = self.hoveredSliceIndex, idx < self.metrics.slices.count {
                {
                    let slice = self.metrics.slices[idx]
                    return "\(slice.label) · \(slice.rawChars.formatted()) 字 · \(slice.rawAIRequests) 次 AI"
                }()
            } else {
                "24 小时写作与 AI 活跃分布 · 悬停查看各时段明细"
            }
            Text(caption)
                .font(.system(size: 11, weight: .medium, design: .rounded).monospacedDigit())
                .foregroundStyle(self.palette.pine.opacity(self.hoveredSliceIndex == nil ? 0.50 : 0.84))
                .frame(height: 16)
        }
    }
    
    
    private func hitTestPetal(_ point: CGPoint, in size: CGSize) -> Int? {
        let center = CGPoint(x: size.width * 0.5, y: size.height * 0.5)
        let dx = point.x - center.x
        let dy = point.y - center.y
        let dist = hypot(dx, dy)
        let outerLimit = max(16, min(size.width, size.height) * 0.5 - (self.detailed ? 22 : 4))
        let innerR = max(8, outerLimit * 0.22)
        guard dist >= innerR && dist <= outerLimit else { return nil }
        var angle = atan2(dy, dx) * 180.0 / .pi + 90.0
        if angle < 0 { angle += 360.0 }
        let idx = Int(floor(angle / (360.0 / Double(max(1, self.metrics.slices.count)))))
        return min(max(0, idx), max(0, self.metrics.slices.count - 1))
    }
}


// MARK: - Chart 4: 3-Column Emotion Sankey Flow Diagram (情绪指数 · 桑基图)

private struct EmotionSankeyChartView: View {
    
    let snapshot: DashboardSnapshot
    let palette: DashPalette
    let detailed: Bool
    
    @State private var hoveredCaption: String?
    
    private struct SankeyNode {
        let label: String
        let weight: Double
        let color: Color
    }
    
    
    var body: some View {
        let col1Nodes = self.leftTimeSlotNodes()
        let col2Nodes = self.middleMoodNodes()
        let col3Nodes = self.rightSubMoodNodes()
        
        VStack(spacing: 6) {
            GeometryReader { geo in
                Canvas { context, size in
                    guard size.width.isFinite, size.height.isFinite,
                          size.width > 8, size.height > 8 else { return }
                    let padX: CGFloat = self.detailed ? 74 : 30
                    let topHeaderH: CGFloat = self.detailed ? 20 : 2
                    let padBottom: CGFloat = self.detailed ? 10 : 3
                    let nodeW: CGFloat = self.detailed ? 10 : 5.5
                    let innerW = max(36, size.width - padX * 2)
                    let innerH = max(30, size.height - topHeaderH - padBottom)
                    
                    let col1X = padX
                    let col2X = padX + innerW * 0.5 - nodeW * 0.5
                    let col3X = padX + innerW - nodeW
                    
                    // Column headers above the Sankey diagram in detailed view
                    if self.detailed {
                        let headerStyle = Font.system(size: 10, weight: .medium)
                        let headerColor = self.palette.pine.opacity(0.46)
                        context.draw(Text("写作时段").font(headerStyle).foregroundStyle(headerColor), at: CGPoint(x: col1X + nodeW * 0.5, y: 7), anchor: .center)
                        context.draw(Text("情绪维度").font(headerStyle).foregroundStyle(headerColor), at: CGPoint(x: col2X + nodeW * 0.5, y: 7), anchor: .center)
                        context.draw(Text("心境状态").font(headerStyle).foregroundStyle(headerColor), at: CGPoint(x: col3X + nodeW * 0.5, y: 7), anchor: .center)
                    }
                    
                    let rects1 = Self.layoutColumn(nodes: col1Nodes, x: col1X, yStart: topHeaderH, height: innerH, width: nodeW, gap: self.detailed ? 7 : 4)
                    let rects2 = Self.layoutColumn(nodes: col2Nodes, x: col2X, yStart: topHeaderH, height: innerH, width: nodeW, gap: self.detailed ? 7 : 4)
                    let rects3 = Self.layoutColumn(nodes: col3Nodes, x: col3X, yStart: topHeaderH, height: innerH, width: nodeW, gap: self.detailed ? 7 : 4)
                    
                    Self.drawFlows(context: &context, sources: rects1, targets: rects2)
                    Self.drawFlows(context: &context, sources: rects2, targets: rects3)
                    
                    let sum1 = max(1.0, col1Nodes.reduce(0.0) { $0 + $1.weight })
                    let sum3 = max(1.0, col3Nodes.reduce(0.0) { $0 + $1.weight })
                    
                    // Left column nodes + external labels (visible in both compact & expanded views)
                    for (node, layout) in zip(col1Nodes, rects1) {
                        context.fill(RoundedRectangle(cornerRadius: 2.5, style: .continuous).path(in: layout.rect), with: .color(node.color))
                        let pct = Int(((node.weight / sum1) * 100).rounded())
                        let text = self.detailed ? "\(node.label) \(pct)%" : node.label
                        context.draw(
                            Text(text)
                                .font(.system(size: self.detailed ? 10.5 : 8.5, weight: .medium).monospacedDigit())
                                .foregroundStyle(self.palette.pine.opacity(self.detailed ? 0.84 : 0.62)),
                            at: CGPoint(x: layout.rect.minX - 5, y: layout.rect.midY),
                            anchor: .trailing
                        )
                    }
                    
                    // Middle column nodes + labels
                    for (node, layout) in zip(col2Nodes, rects2) {
                        context.fill(RoundedRectangle(cornerRadius: 2.5, style: .continuous).path(in: layout.rect), with: .color(node.color))
                        if self.detailed {
                            context.draw(
                                Text(node.label)
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(self.palette.pine.opacity(0.92)),
                                at: CGPoint(x: layout.rect.midX, y: max(layout.rect.minY - 7, topHeaderH + 4)),
                                anchor: .center
                            )
                        }
                    }
                    
                    // Right column nodes + external labels (visible in both compact & expanded views)
                    for (node, layout) in zip(col3Nodes, rects3) {
                        context.fill(RoundedRectangle(cornerRadius: 2.5, style: .continuous).path(in: layout.rect), with: .color(node.color))
                        let pct = Int(((node.weight / sum3) * 100).rounded())
                        let text = self.detailed ? "\(node.label) \(pct)%" : node.label
                        context.draw(
                            Text(text)
                                .font(.system(size: self.detailed ? 10.5 : 8.5, weight: .medium).monospacedDigit())
                                .foregroundStyle(self.palette.pine.opacity(self.detailed ? 0.84 : 0.62)),
                            at: CGPoint(x: layout.rect.maxX + 5, y: layout.rect.midY),
                            anchor: .leading
                        )
                    }
                }
                .onContinuousHover { phase in
                    guard self.detailed else { return }
                    switch phase {
                        case .active(let loc):
                            self.hoveredCaption = self.hitTestColumn(
                                loc,
                                in: geo.size,
                                col1: col1Nodes,
                                col2: col2Nodes,
                                col3: col3Nodes
                            )
                        case .ended:
                            self.hoveredCaption = nil
                    }
                }
            }
            
            if self.detailed {
                Text(self.hoveredCaption ?? "时段流向 → 主导情绪 → 心境细分")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(self.palette.pine.opacity(self.hoveredCaption == nil ? 0.48 : 0.80))
                    .frame(height: 16)
            }
        }
    }
    
    
    private func leftTimeSlotNodes() -> [SankeyNode] {
        let slices = self.snapshot.busyness.slices
        var morning: Double = 0
        var afternoon: Double = 0
        var night: Double = 0
        for slice in slices {
            let weight = max(0.05, slice.intensity)
            switch slice.index {
                case 3..<6: morning += weight     // 06:00 - 12:00
                case 6..<9: afternoon += weight   // 12:00 - 18:00
                default: night += weight          // 18:00 - 06:00
            }
        }
        return [
            SankeyNode(label: "晨间", weight: max(1, morning * 100), color: self.palette.mint),
            SankeyNode(label: "午后", weight: max(1, afternoon * 100), color: self.palette.accentFill),
            SankeyNode(label: "夜间", weight: max(1, night * 100), color: self.palette.emerald),
        ]
    }
    
    
    private func middleMoodNodes() -> [SankeyNode] {
        let segs = Array(self.snapshot.mood.segments.prefix(4))
        guard !segs.isEmpty else {
            return [
                SankeyNode(label: "沉稳", weight: 45, color: self.palette.accentFill),
                SankeyNode(label: "专注", weight: 35, color: self.palette.mint),
                SankeyNode(label: "松弛", weight: 20, color: self.palette.paleMint),
            ]
        }
        return segs.map { seg in
            SankeyNode(
                label: seg.label,
                weight: max(1, seg.weight),
                color: self.palette.toneColor(for: seg.tone)
            )
        }
    }
    
    
    private func rightSubMoodNodes() -> [SankeyNode] {
        var collected: [SankeyNode] = []
        for seg in self.snapshot.mood.segments {
            let baseColor = self.palette.toneColor(for: seg.tone)
            for child in seg.children.prefix(2) {
                collected.append(SankeyNode(
                    label: child.label,
                    weight: max(1, child.value),
                    color: baseColor.opacity(0.82)
                ))
            }
        }
        if !collected.isEmpty {
            return Array(collected.sorted { $0.weight > $1.weight }.prefix(4))
        }
        return [
            SankeyNode(label: "心流", weight: 42, color: self.palette.accentFill),
            SankeyNode(label: "克制", weight: 33, color: self.palette.mint),
            SankeyNode(label: "愉悦", weight: 25, color: self.palette.heat(2)),
        ]
    }
    
    
    private func hitTestColumn(
        _ point: CGPoint,
        in size: CGSize,
        col1: [SankeyNode],
        col2: [SankeyNode],
        col3: [SankeyNode]
    ) -> String? {
        let third = size.width / 3.0
        let nodes: [SankeyNode]
        let prefix: String
        if point.x < third {
            nodes = col1
            prefix = "写作时段"
        } else if point.x < third * 2 {
            nodes = col2
            prefix = "情绪维度"
        } else {
            nodes = col3
            prefix = "细分状态"
        }
        let padY: CGFloat = 14
        let innerH = max(34, size.height - padY * 2)
        let laid = Self.layoutColumn(nodes: nodes, x: 0, yStart: padY, height: innerH, width: 10, gap: 6)
        let total = max(1.0, nodes.reduce(0.0) { $0 + $1.weight })
        for (node, layout) in zip(nodes, laid) {
            if point.y >= layout.rect.minY - 3 && point.y <= layout.rect.maxY + 3 {
                let pct = Int(((node.weight / total) * 100).rounded())
                return "\(prefix) · \(node.label)（占比 \(pct)%）"
            }
        }
        return nil
    }
    
    
    private static func layoutColumn(
        nodes: [SankeyNode],
        x: CGFloat,
        yStart: CGFloat,
        height: CGFloat,
        width: CGFloat,
        gap: CGFloat
    ) -> [(rect: CGRect, color: Color, weight: Double)] {
        let totalGap = CGFloat(max(0, nodes.count - 1)) * gap
        let usableH = max(12, height - totalGap)
        let minNodeH: CGFloat = nodes.isEmpty ? 0 : min(6, usableH / CGFloat(nodes.count))
        let leftoverH = max(0, usableH - minNodeH * CGFloat(nodes.count))
        let sumW = max(1.0, nodes.reduce(0.0) { $0 + $1.weight })
        
        var cursorY = yStart
        var result: [(rect: CGRect, color: Color, weight: Double)] = []
        for node in nodes {
            let h = minNodeH + leftoverH * CGFloat(node.weight / sumW)
            let rect = CGRect(x: x, y: cursorY, width: width, height: h)
            result.append((rect, node.color, node.weight))
            cursorY += h + gap
        }
        return result
    }
    
    
    private static func drawFlows(
        context: inout GraphicsContext,
        sources: [(rect: CGRect, color: Color, weight: Double)],
        targets: [(rect: CGRect, color: Color, weight: Double)]
    ) {
        let totalTarget = max(1.0, targets.reduce(0.0) { $0 + $1.weight })
        let totalSource = max(1.0, sources.reduce(0.0) { $0 + $1.weight })
        var targetOffsets = targets.map { $0.rect.minY }
        
        for src in sources {
            var srcOffsetY = src.rect.minY
            for (tIdx, tgt) in targets.enumerated() {
                let share = tgt.weight / totalTarget
                let ribbonSrcH = src.rect.height * CGFloat(share)
                let ribbonTgtH = tgt.rect.height * CGFloat(src.weight / totalSource)
                
                let sTop = srcOffsetY
                let sBot = srcOffsetY + ribbonSrcH
                let tTop = targetOffsets[tIdx]
                let tBot = targetOffsets[tIdx] + ribbonTgtH
                
                srcOffsetY = sBot
                targetOffsets[tIdx] = tBot
                
                let startX = src.rect.maxX
                let endX = tgt.rect.minX
                let ctrlX1 = startX + (endX - startX) * 0.45
                let ctrlX2 = endX - (endX - startX) * 0.45
                
                var ribbon = Path()
                ribbon.move(to: CGPoint(x: startX, y: sTop))
                ribbon.addCurve(
                    to: CGPoint(x: endX, y: tTop),
                    control1: CGPoint(x: ctrlX1, y: sTop),
                    control2: CGPoint(x: ctrlX2, y: tTop)
                )
                ribbon.addLine(to: CGPoint(x: endX, y: tBot))
                ribbon.addCurve(
                    to: CGPoint(x: startX, y: sBot),
                    control1: CGPoint(x: ctrlX2, y: tBot),
                    control2: CGPoint(x: ctrlX1, y: sBot)
                )
                ribbon.closeSubpath()
                
                context.fill(
                    ribbon,
                    with: .linearGradient(
                        Gradient(colors: [
                            src.color.opacity(0.36),
                            tgt.color.opacity(0.28),
                        ]),
                        startPoint: CGPoint(x: startX, y: sTop),
                        endPoint: CGPoint(x: endX, y: tTop)
                    )
                )
            }
        }
    }
}


// MARK: - Supporting Components (Xiaohongshu-Style News Cards)


private struct NewsFeedCoverCard: View {
    
    let item: AIHotNewsItem
    let coverImage: NSImage?
    let compactRow: Bool
    let palette: DashPalette
    let onTap: () -> Void
    
    @State private var isHovered = false
    
    
    var body: some View {
        Button(action: self.onTap) {
            if self.compactRow {
                HStack(alignment: .top, spacing: 8) {
                    self.thumbnailView
                        .frame(width: 64, height: 46)
                        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    
                    VStack(alignment: .leading, spacing: 3) {
                        Text(self.item.title)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(self.palette.pine.opacity(0.92))
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        
                        if !self.item.conciseMetaLabel.isEmpty {
                            Text(self.item.conciseMetaLabel)
                                .font(.system(size: 10, weight: .regular))
                                .foregroundStyle(self.palette.pine.opacity(0.50))
                                .lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(6)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(self.isHovered ? self.palette.inset : self.palette.inset.opacity(0.45))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(self.palette.hairline, lineWidth: 0.6)
                )
            } else {
                // Xiaohongshu-style miniature cover card
                VStack(alignment: .leading, spacing: 5) {
                    self.thumbnailView
                        .frame(maxWidth: .infinity)
                        .frame(height: 68)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    
                    Text(self.item.title)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(self.palette.pine.opacity(0.92))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    
                    HStack(spacing: 4) {
                        Text(AIHotNewsService.sanitizedDisplaySource(self.item.source))
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(self.palette.pine.opacity(0.54))
                            .lineLimit(1)
                        
                        Spacer(minLength: 2)
                        
                        if let score = self.item.heatScore, score > 0 {
                            Text("\(score)°")
                                .font(.system(size: 10, weight: .semibold, design: .rounded).monospacedDigit())
                                .foregroundStyle(self.palette.emerald)
                        }
                    }
                }
                .padding(6)
                .background(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(self.isHovered ? self.palette.inset : self.palette.inset.opacity(0.45))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .strokeBorder(self.isHovered ? self.palette.accentFill.opacity(0.35) : self.palette.hairline, lineWidth: 0.7)
                )
                .scaleEffect(self.isHovered ? 1.015 : 1.0)
            }
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(DashMotion.quick) {
                self.isHovered = hovering
            }
        }
    }
    
    
    @ViewBuilder
    private var thumbnailView: some View {
        ZStack {
            if let coverImage = self.coverImage {
                GeometryReader { geo in
                    Image(nsImage: coverImage)
                        .resizable()
                        .interpolation(.medium)
                        .scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                }
            } else {
                let tint = self.domainTintColor
                LinearGradient(
                    colors: [tint.opacity(0.24), tint.opacity(0.08)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                VStack(spacing: 2) {
                    Text(String(self.item.source.prefix(2)).uppercased())
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(tint.opacity(0.85))
                    Text(self.item.source)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(self.palette.pine.opacity(0.48))
                        .lineLimit(1)
                        .padding(.horizontal, 6)
                }
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(self.palette.hairline, lineWidth: 0.5)
        )
    }
    
    
    private var domainTintColor: Color {
        let hash = abs(self.item.source.unicodeScalars.reduce(0) { $0 &* 31 &+ Int($1.value) })
        let hues: [Color] = [
            self.palette.accentFill,
            self.palette.mint,
            Color(red: 0.86, green: 0.48, blue: 0.34),
            Color(red: 0.44, green: 0.56, blue: 0.88),
            Color(red: 0.68, green: 0.44, blue: 0.84),
        ]
        return hues[hash % hues.count]
    }
}


private extension View {
    
    func dashboardCardSurface(
        palette: DashPalette,
        cornerRadius: CGFloat = 16,
        isHighlighted: Bool = false
    ) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return self
            .background(
                shape.fill(palette.card)
                    .shadow(color: palette.cardShadow, radius: isHighlighted ? 14 : 8, x: 0, y: 4)
            )
            .overlay(
                shape.strokeBorder(
                    isHighlighted ? palette.accentFill.opacity(0.45) : palette.hairline,
                    lineWidth: isHighlighted ? 1.1 : 0.8
                )
            )
    }
}
