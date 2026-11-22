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
    @State private var pinnedPredictionIDs: Set<String> = []
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
    
    
    // MARK: Row 1 — Heatmap + Expandable 2x2 Quad
    
    private func row1Section(_ snapshot: DashboardSnapshot) -> some View {
        GeometryReader { proxy in
            let spacing: CGFloat = 14
            let usableW = max(320, proxy.size.width - spacing)
            let leftRatio: CGFloat = self.isEmbeddedInSettings ? 0.50 : 0.56
            let leftWidth = floor(usableW * leftRatio)
            let rightWidth = max(160, usableW - leftWidth)
            
            HStack(alignment: .top, spacing: spacing) {
                DashboardHeatmapCard(
                    yearlyHeatmap: snapshot.yearlyHeatmap,
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
                let tileH = max(80, (self.row1Height - vGap) * 0.5)
                
                VStack(spacing: vGap) {
                    HStack(spacing: hGap) {
                        self.quadCard(metric: .typed, snapshot: snapshot)
                            .frame(maxWidth: .infinity, minHeight: tileH, maxHeight: tileH)
                        self.quadCard(metric: .aiUsage, snapshot: snapshot)
                            .frame(maxWidth: .infinity, minHeight: tileH, maxHeight: tileH)
                    }
                    HStack(spacing: hGap) {
                        self.quadCard(metric: .busyness, snapshot: snapshot)
                            .frame(maxWidth: .infinity, minHeight: tileH, maxHeight: tileH)
                        self.quadCard(metric: .mood, snapshot: snapshot)
                            .frame(maxWidth: .infinity, minHeight: tileH, maxHeight: tileH)
                    }
                }
                .id("compact-quad-grid")
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
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("干了啥")
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(self.palette.pine)
                
                Spacer()
                
                Button {
                    Task {
                        await self.analytics.refreshDailyDigest(force: true)
                    }
                } label: {
                    Image(systemName: self.analytics.isSummarizingDigest ? "hourglass" : "arrow.clockwise")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(self.palette.pine.opacity(0.60))
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(self.analytics.isSummarizingDigest)
            }
            
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 9) {
                    ForEach(Array(points.enumerated()), id: \.offset) { idx, point in
                        HStack(alignment: .top, spacing: 8) {
                            Circle()
                                .fill(idx == 0 ? self.palette.accentFill : self.palette.mint.opacity(0.75))
                                .frame(width: 5, height: 5)
                                .padding(.top, 5)
                            
                            Text(point)
                                .font(.system(size: 12.5, weight: .regular))
                                .foregroundStyle(self.palette.pine.opacity(0.88))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(14)
        .dashboardCardSurface(palette: self.palette, cornerRadius: 16)
    }
    
    
    private func predictedActionsColumn() -> some View {
        let predictions = self.analytics.actionPredictions
        
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text("要干啥")
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(self.palette.pine)
                
                Text(self.analytics.actionPredictionsFromAI ? "AI 预测" : "文档推演")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(self.palette.emerald)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(self.palette.accentFill.opacity(0.12), in: Capsule())
                
                Spacer()
                
                Button {
                    Task {
                        await self.analytics.refreshActionPredictions(force: true)
                    }
                } label: {
                    Image(systemName: self.analytics.isPredictingActions ? "hourglass" : "arrow.clockwise")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(self.palette.pine.opacity(0.60))
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(self.analytics.isPredictingActions)
                .help("基于近期文档重新预测下一步行动")
            }
            
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 8) {
                    if predictions.isEmpty {
                        if self.analytics.isPredictingActions {
                            HStack(spacing: 8) {
                                ProgressView()
                                    .controlSize(.small)
                                Text("AI 正在阅读近期文档并推演下一步…")
                                    .font(.system(size: 12))
                                    .foregroundStyle(self.palette.pine.opacity(0.60))
                            }
                            .padding(.top, 4)
                        } else {
                            Text("开始写作后，AI 会结合文档内容自动预测下一步行动")
                                .font(.system(size: 12))
                                .foregroundStyle(self.palette.pine.opacity(0.48))
                                .padding(.top, 4)
                        }
                    } else {
                        ForEach(predictions) { pred in
                            let isPinned = self.pinnedPredictionIDs.contains(pred.id)
                            let sourceDoc = self.analytics.storedDocument(
                                id: pred.sourceDocumentID,
                                title: pred.sourceDocumentTitle
                            )
                            PredictedActionRow(
                                prediction: pred,
                                palette: self.palette,
                                isPinned: isPinned,
                                canOpenDocument: sourceDoc != nil,
                                onOpenDocument: {
                                    guard let doc = sourceDoc else { return }
                                    if let handler = self.onOpenDocument {
                                        handler(doc)
                                    } else {
                                        AnalyticsDashboardWindowController.shared.openDocument(doc)
                                    }
                                },
                                onPinToCapsule: {
                                    guard !isPinned else { return }
                                    _ = self.analytics.addPinnedTodo(title: pred.action, deadline: nil)
                                    withAnimation(DashMotion.quick) {
                                        _ = self.pinnedPredictionIDs.insert(pred.id)
                                    }
                                }
                            )
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(14)
        .dashboardCardSurface(palette: self.palette, cornerRadius: 16)
    }
    
    
    private func newsColumn() -> some View {
        let pageItems = self.newsService.currentPageItems
        
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text("NEWS")
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(self.palette.pine)
                
                Spacer(minLength: 4)
                
                HStack(spacing: 3) {
                    ForEach(NewsFeedCategory.allCases) { category in
                        let isSelected = (self.newsService.selectedCategory == category)
                        Button {
                            withAnimation(DashMotion.quick) {
                                self.newsService.selectedCategory = category
                            }
                        } label: {
                            Text(category.label)
                                .font(.system(size: 10, weight: isSelected ? .semibold : .medium))
                                .foregroundStyle(isSelected ? self.palette.tokens.onAccentInk : self.palette.pine.opacity(0.58))
                                .padding(.horizontal, 6)
                                .frame(height: 20)
                                .background(
                                    Capsule().fill(isSelected ? self.palette.accentFill : self.palette.inset)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                
                Button {
                    Task {
                        await self.newsService.refreshIfNeeded(force: true)
                    }
                } label: {
                    Image(systemName: self.newsService.isLoading ? "hourglass" : "arrow.clockwise")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(self.palette.pine.opacity(0.65))
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(self.palette.inset.opacity(0.7)))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .disabled(self.newsService.isLoading)
                .help("刷新金融、X 与 AI 资讯")
            }
            
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
                                Text("正在同步金融、X 与 AI 资讯…")
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
                        .id("news-\(self.newsService.selectedCategory.rawValue)-page-\(self.newsService.currentPage)")
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
                    
                    Text("第 \(self.newsService.currentPage) / \(self.newsService.totalPages) 页")
                        .font(.system(size: 10.5, weight: .medium, design: .rounded).monospacedDigit())
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
        .padding(14)
        .dashboardCardSurface(palette: self.palette, cornerRadius: 16)
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


// MARK: - Heatmap Card (Crisp 1:1 Square Cells + Month & Weekday Axis)

private struct DashboardHeatmapCard: View {
    
    let yearlyHeatmap: YearlyHeatmapData
    let currentStreak: Int
    let availableYears: [Int]
    @Binding var selectedYear: Int
    let palette: DashPalette
    
    @State private var hoveredCell: HeatmapDayCell?
    @State private var hoverPoint: CGPoint = .zero
    
    
    private var previousYear: Int? {
        self.availableYears.last { $0 < self.yearlyHeatmap.year }
    }
    
    private var nextYear: Int? {
        self.availableYears.first { $0 > self.yearlyHeatmap.year }
    }
    
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                HStack(spacing: 4) {
                    Button {
                        if let prev = self.previousYear {
                            self.selectedYear = prev
                        }
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(self.previousYear != nil ? self.palette.pine.opacity(0.75) : self.palette.pine.opacity(0.24))
                            .frame(width: 22, height: 22)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(self.previousYear == nil)
                    
                    Text("\(String(self.yearlyHeatmap.year))")
                        .font(.system(size: 13.5, weight: .semibold, design: .rounded).monospacedDigit())
                        .foregroundStyle(self.palette.pine)
                    
                    Button {
                        if let next = self.nextYear {
                            self.selectedYear = next
                        }
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(self.nextYear != nil ? self.palette.pine.opacity(0.75) : self.palette.pine.opacity(0.24))
                            .frame(width: 22, height: 22)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(self.nextYear == nil)
                }
                
                Spacer()
                
                HStack(spacing: 10) {
                    Text("活跃 \(self.yearlyHeatmap.activeDays) 天")
                        .font(.system(size: 11, weight: .medium, design: .rounded).monospacedDigit())
                        .foregroundStyle(self.palette.pine.opacity(0.58))
                    if self.currentStreak > 0 {
                        Text("连写 \(self.currentStreak) 天")
                            .font(.system(size: 11, weight: .semibold, design: .rounded).monospacedDigit())
                            .foregroundStyle(self.palette.emerald)
                    }
                }
            }
            
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
                            
                            // Top month axis labels
                            var lastLabelRightX: CGFloat = -100
                            for marker in self.yearlyHeatmap.monthLabels {
                                let x = layout.gridOriginX + CGFloat(marker.weekIndex) * layout.pitch
                                guard x >= lastLabelRightX + 20 else { continue }
                                lastLabelRightX = x
                                context.draw(
                                    Text("\(marker.month)月")
                                        .font(.system(size: 9.5, weight: .medium, design: .rounded))
                                        .foregroundStyle(self.palette.pine.opacity(0.46)),
                                    at: CGPoint(x: x, y: layout.gridOriginY - 10),
                                    anchor: .leading
                                )
                            }
                            
                            // Subtle left weekday axis (Mon / Wed / Fri)
                            for (rowIndex, label) in [(0, "一"), (2, "三"), (4, "五")] {
                                let rect = layout.cellRect(col: 0, row: rowIndex)
                                context.draw(
                                    Text(label)
                                        .font(.system(size: 9, weight: .regular))
                                        .foregroundStyle(self.palette.pine.opacity(0.42)),
                                    at: CGPoint(x: layout.gridOriginX - 6, y: rect.midY),
                                    anchor: .trailing
                                )
                            }
                            
                            // Strictly 1:1 square heatmap cells
                            for (colIndex, week) in self.yearlyHeatmap.weeks.enumerated() {
                                for (rowIndex, cell) in week.enumerated() {
                                    guard rowIndex < 7, !cell.isOutOfYear, !cell.isFuture else { continue }
                                    let rect = layout.cellRect(col: colIndex, row: rowIndex)
                                    let path = RoundedRectangle(cornerRadius: layout.cornerRadius, style: .continuous)
                                        .path(in: rect)
                                    context.fill(path, with: .color(self.palette.heat(cell.level)))
                                    
                                    if self.hoveredCell?.id == cell.id {
                                        context.stroke(
                                            path,
                                            with: .color(self.palette.pine.opacity(0.70)),
                                            lineWidth: 1.0
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
        }
        .padding(14)
        .dashboardCardSurface(palette: self.palette, cornerRadius: 16)
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


// MARK: - Compact & Expanded Quad Cards (Trend, Sankey, Rose, Sunburst)

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
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(self.metric.title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(self.palette.pine.opacity(0.72))
                    
                    Spacer()
                    
                    Text(self.primaryMetricText)
                        .font(.system(size: 15, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(self.palette.pine)
                }
                
                self.miniVisualization
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(11)
            .dashboardCardSurface(palette: self.palette, cornerRadius: 15, isHighlighted: self.isHovered)
            .contentShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
        }
        .buttonStyle(.plain)
        .scaleEffect(self.isHovered ? 1.012 : 1.0)
        .animation(DashMotion.quick, value: self.isHovered)
        .onHover { hovering in
            self.isHovered = hovering
        }
    }
    
    
    private var primaryMetricText: String {
        switch self.metric {
            case .typed:
                let total = self.snapshot.today.typedChars + self.snapshot.today.aiCompletedChars
                return "\(total.formatted()) 字"
            case .aiUsage:
                return self.formatTokens(self.snapshot.aiTodayTotals.totalTokens > 0
                    ? self.snapshot.aiTodayTotals.totalTokens
                    : self.snapshot.ai30Totals.totalTokens)
            case .busyness:
                return "\(self.snapshot.busyness.score)%"
            case .mood:
                return "\(self.snapshot.mood.score) · \(self.snapshot.mood.dominantLabel)"
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
        .padding(14)
        .dashboardCardSurface(palette: self.palette, cornerRadius: 16, isHighlighted: true)
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


// MARK: - Chart 2: AI Usage 2-Ring Sunburst Chart (AI 用量 · 旭日图)

private struct AIUsageSunburstChartView: View {
    
    let snapshot: DashboardSnapshot
    let palette: DashPalette
    let detailed: Bool
    
    @State private var hoveredLabel: String?
    
    private struct RingSlice {
        let label: String
        let weight: Double
        let detailText: String
        let color: Color
        let children: [ChildSlice]
    }
    
    private struct ChildSlice {
        let label: String
        let weight: Double
        let detailText: String
    }
    
    
    private func buildHierarchy() -> [RingSlice] {
        let modelColors: [Color] = [
            self.palette.accentFill,
            self.palette.emerald,
            self.palette.mint,
            self.palette.heat(2),
            self.palette.paleMint,
        ]
        
        let featureChildren: [ChildSlice] = {
            let feats = Array(self.snapshot.aiFeatures.prefix(4))
            if !feats.isEmpty {
                return feats.map { f in
                    let name = f.displayName.isEmpty ? f.feature : f.displayName
                    let tokens = max(1, f.totalTokens)
                    return ChildSlice(
                        label: name,
                        weight: Double(f.totalTokens > 0 ? f.totalTokens : max(1, f.requests * 120)),
                        detailText: "\(name) · \(f.requests) 次 · \(Self.compactTokens(tokens))"
                    )
                }
            }
            let totals = self.snapshot.ai30Totals
            if totals.inputTokens + totals.outputTokens > 0 {
                return [
                    ChildSlice(label: "输入", weight: Double(max(1, totals.inputTokens)), detailText: "输入 · \(Self.compactTokens(totals.inputTokens))"),
                    ChildSlice(label: "生成", weight: Double(max(1, totals.outputTokens)), detailText: "生成 · \(Self.compactTokens(totals.outputTokens))"),
                ]
            }
            return [
                ChildSlice(label: "续写", weight: 44, detailText: "续写 · 44%"),
                ChildSlice(label: "翻译", weight: 30, detailText: "翻译 · 30%"),
                ChildSlice(label: "摘要", weight: 26, detailText: "摘要 · 26%"),
            ]
        }()
        
        let models = Array(self.snapshot.aiModels.prefix(4))
        if !models.isEmpty {
            return models.enumerated().map { idx, m in
                let shortName = Self.shortName(m.model)
                let w = Double(m.totalTokens > 0 ? m.totalTokens : max(1, m.requests * 150))
                let sliceChildren: [ChildSlice] = if models.count == 1 {
                    featureChildren
                } else {
                    // Distribute top features proportionally inside each model arc
                    Array(featureChildren.prefix(3))
                }
                return RingSlice(
                    label: shortName,
                    weight: w,
                    detailText: "\(shortName) · \(m.requests) 次 · \(Self.compactTokens(m.totalTokens)) tokens",
                    color: modelColors[idx % modelColors.count],
                    children: sliceChildren
                )
            }
        }
        
        return [
            RingSlice(
                label: "主力模型",
                weight: 62,
                detailText: "主力模型 · 占比 62%",
                color: self.palette.accentFill,
                children: [
                    ChildSlice(label: "续写", weight: 38, detailText: "主力模型 → 续写"),
                    ChildSlice(label: "摘要", weight: 24, detailText: "主力模型 → 摘要"),
                ]
            ),
            RingSlice(
                label: "轻量模型",
                weight: 38,
                detailText: "轻量模型 · 占比 38%",
                color: self.palette.mint,
                children: [
                    ChildSlice(label: "翻译", weight: 22, detailText: "轻量模型 → 翻译"),
                    ChildSlice(label: "解释", weight: 16, detailText: "轻量模型 → 解释"),
                ]
            ),
        ]
    }
    
    
    var body: some View {
        let rings = self.buildHierarchy()
        let totalWeight = max(1.0, rings.reduce(0.0) { $0 + $1.weight })
        let centerTokens = self.snapshot.ai30Totals.totalTokens > 0
            ? Self.compactTokens(self.snapshot.ai30Totals.totalTokens)
            : "\(self.snapshot.ai30Totals.requests)次"
        
        VStack(spacing: 6) {
            GeometryReader { geo in
                Canvas { context, size in
                    guard size.width.isFinite, size.height.isFinite,
                          size.width > 8, size.height > 8 else { return }
                    let center = CGPoint(x: size.width * 0.5, y: size.height * 0.5)
                    let outerLimit = max(18, min(size.width, size.height) * 0.5 - (self.detailed ? 16 : 4))
                    let rCore = max(10, outerLimit * 0.32)
                    let rMid = max(rCore + 4, outerLimit * 0.66)
                    let rOuter = max(rMid + 6, outerLimit)
                    
                    var cursorDeg = -90.0
                    for slice in rings {
                        let spanDeg = (slice.weight / totalWeight) * 360.0
                        let segStart = cursorDeg + 1.2
                        let segEnd = cursorDeg + spanDeg - 1.2
                        
                        if segEnd > segStart {
                            var innerSector = Path()
                            innerSector.addArc(center: center, radius: rCore, startAngle: .degrees(segStart), endAngle: .degrees(segEnd), clockwise: false)
                            innerSector.addArc(center: center, radius: rMid - 1.5, startAngle: .degrees(segEnd), endAngle: .degrees(segStart), clockwise: true)
                            innerSector.closeSubpath()
                            context.fill(innerSector, with: .color(slice.color.opacity(0.88)))
                            
                            if self.detailed && spanDeg > 30 {
                                let midRad = (segStart + segEnd) * 0.5 * .pi / 180.0
                                let labelR = (rCore + rMid) * 0.5
                                context.draw(
                                    Text(slice.label)
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundStyle(self.palette.tokens.onAccentInk),
                                    at: CGPoint(x: center.x + CGFloat(cos(midRad)) * labelR, y: center.y + CGFloat(sin(midRad)) * labelR),
                                    anchor: .center
                                )
                            }
                        }
                        
                        let childSum = max(1.0, slice.children.reduce(0.0) { $0 + $1.weight })
                        var childCursor = cursorDeg
                        for (cIdx, child) in slice.children.enumerated() {
                            let childSpan = (child.weight / childSum) * spanDeg
                            let cStart = childCursor + 0.9
                            let cEnd = childCursor + childSpan - 0.9
                            if cEnd > cStart {
                                var outerSector = Path()
                                outerSector.addArc(center: center, radius: rMid + 1.5, startAngle: .degrees(cStart), endAngle: .degrees(cEnd), clockwise: false)
                                outerSector.addArc(center: center, radius: rOuter, startAngle: .degrees(cEnd), endAngle: .degrees(cStart), clockwise: true)
                                outerSector.closeSubpath()
                                let alpha = cIdx.isMultiple(of: 2) ? 0.58 : 0.38
                                context.fill(outerSector, with: .color(slice.color.opacity(alpha)))
                                
                                if self.detailed && childSpan > 24 {
                                    let midRad = (cStart + cEnd) * 0.5 * .pi / 180.0
                                    let labelR = (rMid + rOuter) * 0.52
                                    context.draw(
                                        Text(child.label)
                                            .font(.system(size: 9.5, weight: .medium))
                                            .foregroundStyle(self.palette.pine.opacity(0.90)),
                                        at: CGPoint(x: center.x + CGFloat(cos(midRad)) * labelR, y: center.y + CGFloat(sin(midRad)) * labelR),
                                        anchor: .center
                                    )
                                }
                            }
                            childCursor += childSpan
                        }
                        cursorDeg += spanDeg
                    }
                    
                    let coreRect = CGRect(x: center.x - rCore + 2, y: center.y - rCore + 2, width: (rCore - 2) * 2, height: (rCore - 2) * 2)
                    context.fill(Circle().path(in: coreRect), with: .color(self.palette.card))
                    if self.detailed {
                        context.draw(
                            Text(centerTokens)
                                .font(.system(size: 13, weight: .bold, design: .rounded).monospacedDigit())
                                .foregroundStyle(self.palette.pine),
                            at: center,
                            anchor: .center
                        )
                    }
                }
                .onContinuousHover { phase in
                    guard self.detailed else { return }
                    switch phase {
                        case .active(let loc):
                            self.hoveredLabel = self.hitTestSector(loc, in: geo.size, rings: rings, totalWeight: totalWeight)
                        case .ended:
                            self.hoveredLabel = nil
                    }
                }
            }
            
            if self.detailed {
                Text(self.hoveredLabel ?? "内环：模型占比 · 外环：功能与 Token 分布")
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundStyle(self.palette.pine.opacity(self.hoveredLabel == nil ? 0.48 : 0.80))
                    .frame(height: 16)
            }
        }
    }
    
    
    private func hitTestSector(_ point: CGPoint, in size: CGSize, rings: [RingSlice], totalWeight: Double) -> String? {
        let center = CGPoint(x: size.width * 0.5, y: size.height * 0.5)
        let outerLimit = max(18, min(size.width, size.height) * 0.5 - (self.detailed ? 16 : 4))
        let rCore = max(10, outerLimit * 0.32)
        let rMid = max(rCore + 4, outerLimit * 0.66)
        let dist = hypot(point.x - center.x, point.y - center.y)
        guard dist >= rCore && dist <= outerLimit else { return nil }
        
        var deg = atan2(point.y - center.y, point.x - center.x) * 180.0 / .pi + 90.0
        if deg < 0 { deg += 360.0 }
        
        var cursor = 0.0
        for slice in rings {
            let span = (slice.weight / totalWeight) * 360.0
            if deg <= cursor + span {
                if dist <= rMid {
                    return slice.detailText
                }
                let childTotal = max(1.0, slice.children.reduce(0.0) { $0 + $1.weight })
                var cCursor = cursor
                for child in slice.children {
                    let cSpan = (child.weight / childTotal) * span
                    if deg <= cCursor + cSpan {
                        return "\(slice.label) → \(child.detailText)"
                    }
                    cCursor += cSpan
                }
                return slice.detailText
            }
            cursor += span
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


// MARK: - Chart 3: Nightingale Rose Chart (玫瑰图)

private struct NightingaleRoseChartView: View {
    
    let metrics: BusynessMetrics
    let palette: DashPalette
    let detailed: Bool
    
    @State private var hoveredSliceIndex: Int?
    
    
    var body: some View {
        VStack(spacing: 6) {
            GeometryReader { geo in
                Canvas { context, size in
                    guard size.width.isFinite, size.height.isFinite,
                          size.width > 8, size.height > 8 else { return }
                    let center = CGPoint(x: size.width * 0.5, y: size.height * 0.5)
                    let outerLimit = max(16, min(size.width, size.height) * 0.5 - (self.detailed ? 22 : 4))
                    let innerR = max(8, outerLimit * 0.22)
                    let maxPetalSpan = max(8, outerLimit - innerR)
                    
                    if self.detailed {
                        for frac in [0.35, 0.70, 1.0] {
                            let r = innerR + maxPetalSpan * CGFloat(frac)
                            let ringRect = CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)
                            context.stroke(
                                Circle().path(in: ringRect),
                                with: .color(self.palette.hairline),
                                lineWidth: 0.7
                            )
                        }
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
                        
                        if self.detailed && slice.index.isMultiple(of: 2) {
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
                    guard self.detailed else { return }
                    switch phase {
                        case .active(let loc):
                            self.hoveredSliceIndex = self.hitTestPetal(loc, in: geo.size)
                        case .ended:
                            self.hoveredSliceIndex = nil
                    }
                }
            }
            
            if self.detailed {
                let caption: String = if let idx = self.hoveredSliceIndex, idx < self.metrics.slices.count {
                    {
                        let slice = self.metrics.slices[idx]
                        return "\(slice.label) · \(slice.rawChars.formatted()) 字 · \(slice.rawAIRequests) 次 AI"
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
                    let padX: CGFloat = self.detailed ? 64 : 6
                    let padY: CGFloat = self.detailed ? 14 : 4
                    let nodeW: CGFloat = self.detailed ? 10 : 6.5
                    let innerW = max(40, size.width - padX * 2)
                    let innerH = max(34, size.height - padY * 2)
                    
                    let col1X = padX
                    let col2X = padX + innerW * 0.5 - nodeW * 0.5
                    let col3X = padX + innerW - nodeW
                    
                    let rects1 = Self.layoutColumn(nodes: col1Nodes, x: col1X, yStart: padY, height: innerH, width: nodeW, gap: 6)
                    let rects2 = Self.layoutColumn(nodes: col2Nodes, x: col2X, yStart: padY, height: innerH, width: nodeW, gap: 6)
                    let rects3 = Self.layoutColumn(nodes: col3Nodes, x: col3X, yStart: padY, height: innerH, width: nodeW, gap: 6)
                    
                    Self.drawFlows(context: &context, sources: rects1, targets: rects2)
                    Self.drawFlows(context: &context, sources: rects2, targets: rects3)
                    
                    for (node, layout) in zip(col1Nodes, rects1) {
                        context.fill(RoundedRectangle(cornerRadius: 2.5, style: .continuous).path(in: layout.rect), with: .color(node.color))
                        if self.detailed {
                            context.draw(
                                Text(node.label)
                                    .font(.system(size: 10.5, weight: .medium))
                                    .foregroundStyle(self.palette.pine.opacity(0.84)),
                                at: CGPoint(x: layout.rect.minX - 6, y: layout.rect.midY),
                                anchor: .trailing
                            )
                        }
                    }
                    
                    for (node, layout) in zip(col2Nodes, rects2) {
                        context.fill(RoundedRectangle(cornerRadius: 2.5, style: .continuous).path(in: layout.rect), with: .color(node.color))
                        if self.detailed {
                            context.draw(
                                Text(node.label)
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(self.palette.pine.opacity(0.92)),
                                at: CGPoint(x: layout.rect.midX, y: max(layout.rect.minY - 7, 8)),
                                anchor: .center
                            )
                        }
                    }
                    
                    for (node, layout) in zip(col3Nodes, rects3) {
                        context.fill(RoundedRectangle(cornerRadius: 2.5, style: .continuous).path(in: layout.rect), with: .color(node.color))
                        if self.detailed {
                            context.draw(
                                Text(node.label)
                                    .font(.system(size: 10.5, weight: .medium))
                                    .foregroundStyle(self.palette.pine.opacity(0.84)),
                                at: CGPoint(x: layout.rect.maxX + 6, y: layout.rect.midY),
                                anchor: .leading
                            )
                        }
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


// MARK: - Supporting Components (AI Predicted Actions & Xiaohongshu-Style News Cards)

private struct PredictedActionRow: View {
    
    let prediction: DocumentActionPrediction
    let palette: DashPalette
    let isPinned: Bool
    let canOpenDocument: Bool
    let onOpenDocument: () -> Void
    let onPinToCapsule: () -> Void
    
    @State private var isHovered = false
    
    
    private var urgencyColor: Color {
        switch self.prediction.urgency {
            case "高": self.palette.emerald
            case "中": self.palette.mint
            default: self.palette.pine.opacity(0.35)
        }
    }
    
    
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                .fill(self.urgencyColor)
                .frame(width: 2.5, height: 28)
                .padding(.top, 2)
            
            VStack(alignment: .leading, spacing: 3) {
                Text(self.prediction.action)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(self.palette.pine.opacity(0.92))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                
                HStack(spacing: 5) {
                    if !self.prediction.sourceDocumentTitle.isEmpty {
                        Text("《\(self.prediction.sourceDocumentTitle)》")
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(self.palette.emerald.opacity(0.88))
                            .lineLimit(1)
                    }
                    
                    Text(self.prediction.reason)
                        .font(.system(size: 10.5))
                        .foregroundStyle(self.palette.pine.opacity(0.54))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture {
                if self.canOpenDocument {
                    self.onOpenDocument()
                }
            }
            
            Button(action: self.onPinToCapsule) {
                Image(systemName: self.isPinned ? "checkmark.circle.fill" : "pin")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(self.isPinned ? self.palette.emerald : self.palette.pine.opacity(self.isHovered ? 0.65 : 0.30))
                    .frame(width: 22, height: 22)
                    .background(
                        Circle().fill(self.isHovered || self.isPinned ? self.palette.inset : Color.clear)
                    )
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help(self.isPinned ? "已加入顶部待办" : "固定到顶部待办")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(self.isHovered ? self.palette.inset : Color.clear)
        )
        .onHover { hovering in
            withAnimation(DashMotion.quick) {
                self.isHovered = hovering
            }
        }
    }
}


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
                        let catBadge = self.item.resolvedCategory.badgeLabel
                        if !catBadge.isEmpty {
                            Text(catBadge)
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(self.palette.emerald)
                                .padding(.horizontal, 4.5)
                                .padding(.vertical, 1)
                                .background(self.palette.accentFill.opacity(0.12), in: Capsule())
                        }
                        
                        Text(AIHotNewsService.sanitizedDisplaySource(self.item.source))
                            .font(.system(size: 10))
                            .foregroundStyle(self.palette.pine.opacity(0.52))
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
