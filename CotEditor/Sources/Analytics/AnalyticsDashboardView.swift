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
    static let flip = Animation.spring(response: 0.42, dampingFraction: 0.84)
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
        let yearly = analytics.yearlyHeatmap(year: resolvedYear, trimFutureWeeks: false)
        
        let aiTodayTotals = analytics.aiUsageTotals(forTodayOnly: true)
        let ai30Totals = analytics.aiUsageTotals(forTodayOnly: false, days: 30)
        let models = analytics.modelDistribution(days: 30)
        let features = analytics.featureDistribution(days: 30)
        
        return DashboardSnapshot(
            today: today,
            days14: days14,
            yearlyHeatmap: yearly,
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
    @State private var isAddingTodo = false
    @State private var newTodoText = ""
    @State private var hasAppeared = false
    @Namespace private var quadNamespace
    
    
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
    private var row2MinHeight: CGFloat { self.isEmbeddedInSettings ? 204 : 254 }
    
    
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
                            HStack {
                                Text("数据看板")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(self.palette.pine)
                                
                                Spacer()
                                
                                Button(action: onDismiss) {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(self.palette.pine.opacity(0.68))
                                        .frame(width: 24, height: 24)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.bottom, 2)
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
            if self.isAddingTodo {
                withAnimation(DashMotion.quick) {
                    self.isAddingTodo = false
                    self.newTodoText = ""
                }
                return .handled
            }
            if self.expandedQuad != nil {
                withAnimation(DashMotion.flip) {
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
            await self.newsService.refreshIfNeeded()
        }
        .onChange(of: self.analytics.revision) { _, _ in
            self.rebuildSnapshot()
        }
        .onChange(of: self.selectedYear) { _, _ in
            self.rebuildSnapshot()
        }
    }
    
    
    // MARK: Row 1 — Heatmap + Flippable 2x2 Quad
    
    private func row1Section(_ snapshot: DashboardSnapshot) -> some View {
        GeometryReader { proxy in
            let spacing: CGFloat = 14
            let usableW = max(320, proxy.size.width - spacing)
            let leftWidth = floor(usableW * 0.52)
            let rightWidth = max(160, usableW - leftWidth)
            
            HStack(alignment: .top, spacing: spacing) {
                DashboardHeatmapCard(
                    yearlyHeatmap: snapshot.yearlyHeatmap,
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
    
    
    @ViewBuilder
    private func flippableQuadSection(_ snapshot: DashboardSnapshot) -> some View {
        if let expanded = self.expandedQuad {
            DashboardExpandedQuadCard(
                metric: expanded,
                snapshot: snapshot,
                palette: self.palette,
                namespace: self.quadNamespace
            ) {
                withAnimation(DashMotion.flip) {
                    self.expandedQuad = nil
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .transition(.asymmetric(
                insertion: .opacity.combined(with: .scale(scale: 0.96)),
                removal: .opacity.combined(with: .scale(scale: 0.96))
            ))
        } else {
            let vGap: CGFloat = 12
            let hGap: CGFloat = 12
            let tileH = (self.row1Height - vGap) * 0.5
            
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
            .transition(.asymmetric(
                insertion: .opacity.combined(with: .scale(scale: 0.96)),
                removal: .opacity.combined(with: .scale(scale: 0.96))
            ))
        }
    }
    
    
    private func quadCard(metric: DashboardQuadMetric, snapshot: DashboardSnapshot) -> some View {
        DashboardCompactQuadCard(
            metric: metric,
            snapshot: snapshot,
            palette: self.palette,
            namespace: self.quadNamespace
        ) {
            withAnimation(DashMotion.flip) {
                self.expandedQuad = metric
            }
        }
    }
    
    
    // MARK: Row 2 — Equal 3-Column Layout (干了啥 / 要干啥 / NEWS)
    
    private func row2Section() -> some View {
        HStack(alignment: .top, spacing: 14) {
            self.doneTodayColumn()
                .frame(maxWidth: .infinity, minHeight: self.row2MinHeight, maxHeight: .infinity, alignment: .topLeading)
            
            self.todoColumn()
                .frame(maxWidth: .infinity, minHeight: self.row2MinHeight, maxHeight: .infinity, alignment: .topLeading)
            
            self.newsColumn()
                .frame(maxWidth: .infinity, minHeight: self.row2MinHeight, maxHeight: .infinity, alignment: .topLeading)
        }
        .fixedSize(horizontal: false, vertical: true)
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
    
    
    private func todoColumn() -> some View {
        let items = self.mergedTodoItems()
        let detected = self.analytics.detectedNoteTodos(limit: 3)
        
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text("要干啥")
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(self.palette.pine)
                
                Spacer()
                
                Button {
                    withAnimation(DashMotion.quick) {
                        self.isAddingTodo.toggle()
                    }
                } label: {
                    Image(systemName: self.isAddingTodo ? "minus" : "plus")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(self.palette.pine.opacity(0.68))
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            
            if self.isAddingTodo {
                HStack(spacing: 6) {
                    TextField("添加待办…", text: self.$newTodoText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(self.palette.inset)
                        )
                        .onSubmit {
                            self.commitNewTodo()
                        }
                    
                    Button("添加") {
                        self.commitNewTodo()
                    }
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(self.palette.emerald)
                    .buttonStyle(.plain)
                    .disabled(self.newTodoText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 7) {
                    if items.isEmpty && detected.isEmpty {
                        Text("暂无待办")
                            .font(.system(size: 12))
                            .foregroundStyle(self.palette.pine.opacity(0.45))
                            .padding(.top, 4)
                    } else {
                        ForEach(items) { item in
                            TodoChecklistRow(
                                item: item,
                                palette: self.palette,
                                onToggle: {
                                    withAnimation(DashMotion.quick) {
                                        self.analytics.toggleReminderCompleted(id: item.id)
                                    }
                                },
                                onDelete: {
                                    withAnimation(DashMotion.quick) {
                                        self.analytics.deleteReminder(id: item.id)
                                    }
                                }
                            )
                        }
                        
                        ForEach(detected) { candidate in
                            if !items.contains(where: { $0.title == candidate.text }) {
                                Button {
                                    withAnimation(DashMotion.quick) {
                                        _ = self.analytics.addPinnedTodo(title: candidate.text, deadline: nil)
                                    }
                                } label: {
                                    HStack(spacing: 7) {
                                        Image(systemName: "plus.circle")
                                            .font(.system(size: 11))
                                            .foregroundStyle(self.palette.accentFill.opacity(0.75))
                                        
                                        Text(candidate.text)
                                            .font(.system(size: 12))
                                            .foregroundStyle(self.palette.pine.opacity(0.72))
                                            .lineLimit(1)
                                            .truncationMode(.tail)
                                        
                                        Spacer()
                                    }
                                    .padding(.vertical, 2)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
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
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text("NEWS")
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(self.palette.pine)
                
                Spacer()
                
                Button {
                    Task {
                        await self.newsService.refreshIfNeeded(force: true)
                    }
                } label: {
                    Image(systemName: self.newsService.isLoading ? "hourglass" : "arrow.clockwise")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(self.palette.pine.opacity(0.60))
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(self.newsService.isLoading)
                
                Button {
                    NSWorkspace.shared.open(AIHotNewsService.portalURL)
                } label: {
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(self.palette.pine.opacity(0.60))
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 8) {
                    if self.newsService.items.isEmpty {
                        if self.newsService.isLoading {
                            HStack(spacing: 8) {
                                ProgressView()
                                    .controlSize(.small)
                                Text("正在同步行业动态…")
                                    .font(.system(size: 12))
                                    .foregroundStyle(self.palette.pine.opacity(0.60))
                            }
                            .padding(.top, 4)
                        } else {
                            Button {
                                NSWorkspace.shared.open(AIHotNewsService.portalURL)
                            } label: {
                                Text("点击访问 aihot.news/agent 获取最新动态")
                                    .font(.system(size: 12))
                                    .foregroundStyle(self.palette.emerald)
                                    .underline()
                            }
                            .buttonStyle(.plain)
                        }
                    } else {
                        ForEach(self.newsService.items) { item in
                            Button {
                                NSWorkspace.shared.open(item.url ?? AIHotNewsService.portalURL)
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.title)
                                        .font(.system(size: 12.5, weight: .medium))
                                        .foregroundStyle(self.palette.pine.opacity(0.92))
                                        .lineLimit(2)
                                        .multilineTextAlignment(.leading)
                                    
                                    if !item.conciseMetaLabel.isEmpty {
                                        Text(item.conciseMetaLabel)
                                            .font(.system(size: 11, weight: .regular))
                                            .foregroundStyle(self.palette.pine.opacity(0.52))
                                            .lineLimit(1)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 3)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(14)
        .dashboardCardSurface(palette: self.palette, cornerRadius: 16)
    }
    
    
    // MARK: Actions
    
    private func rebuildSnapshot() {
        self.snapshot = DashboardSnapshot.build(analytics: self.analytics, selectedYear: self.selectedYear)
    }
    
    
    private func commitNewTodo() {
        let trimmed = self.newTodoText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        _ = self.analytics.addPinnedTodo(title: trimmed, deadline: nil)
        self.newTodoText = ""
        self.isAddingTodo = false
    }
    
    
    private func mergedTodoItems() -> [UserReminder] {
        var seen = Set<String>()
        var merged: [UserReminder] = []
        let sources = self.analytics.overdueReminders
            + self.analytics.pinnedTodos
            + self.analytics.todayReminders
            + self.analytics.tomorrowReminders
        for item in sources where seen.insert(item.id).inserted {
            merged.append(item)
        }
        return ToolbarCapsuleTodoHelper.prioritizedTodos(merged)
    }
}


// MARK: - Heatmap Card (Year Switcher Only, Zero Legend, Zero Clipping)

private struct DashboardHeatmapCard: View {
    
    let yearlyHeatmap: YearlyHeatmapData
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
            HStack {
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
            }
            
            GeometryReader { geo in
                let layout = HeatmapGridLayout.compute(
                    size: geo.size,
                    weekCount: max(1, self.yearlyHeatmap.weeks.count)
                )
                
                ZStack(alignment: .topLeading) {
                    Canvas { context, _ in
                        for (colIndex, week) in self.yearlyHeatmap.weeks.enumerated() {
                            for (rowIndex, cell) in week.enumerated() {
                                guard rowIndex < 7, !cell.isOutOfYear else { continue }
                                let rect = layout.cellRect(col: colIndex, row: rowIndex)
                                let path = RoundedRectangle(cornerRadius: layout.cornerRadius, style: .continuous)
                                    .path(in: rect)
                                context.fill(path, with: .color(self.palette.heat(cell.level)))
                                
                                if self.hoveredCell?.id == cell.id {
                                    context.stroke(
                                        path,
                                        with: .color(self.palette.pine.opacity(0.65)),
                                        lineWidth: 1.0
                                    )
                                }
                            }
                        }
                    }
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
                        self.hoverTooltip(cell: cell, in: geo.size)
                    }
                }
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


private struct HeatmapGridLayout {
    
    let originX: CGFloat
    let originY: CGFloat
    let cellW: CGFloat
    let cellH: CGFloat
    let gapX: CGFloat
    let gapY: CGFloat
    let cornerRadius: CGFloat
    
    
    static func compute(size: CGSize, weekCount: Int) -> HeatmapGridLayout {
        let safeInset: CGFloat = 6
        let availW = max(120, size.width - safeInset * 2)
        let availH = max(84, size.height - safeInset * 2)
        let cols = max(1, weekCount)
        let rows = 7
        
        let gapX: CGFloat = cols > 45 ? max(1.8, min(3.0, availW * 0.0055)) : 3.0
        let cellW = max(2.0, (availW - CGFloat(cols - 1) * gapX) / CGFloat(cols))
        
        let gapY: CGFloat = max(3.0, min(7.0, availH * 0.025))
        let rawCellH = max(4.0, (availH - CGFloat(rows - 1) * gapY) / CGFloat(rows))
        let cellH = min(rawCellH, cellW * 2.6)
        
        let totalW = CGFloat(cols) * cellW + CGFloat(cols - 1) * gapX
        let totalH = CGFloat(rows) * cellH + CGFloat(rows - 1) * gapY
        let originX = max(safeInset, (size.width - totalW) * 0.5)
        let originY = max(safeInset, (size.height - totalH) * 0.5)
        let cornerRadius = max(1.5, min(4.0, min(cellW, cellH) * 0.28))
        
        return HeatmapGridLayout(
            originX: originX,
            originY: originY,
            cellW: cellW,
            cellH: cellH,
            gapX: gapX,
            gapY: gapY,
            cornerRadius: cornerRadius
        )
    }
    
    
    func cellRect(col: Int, row: Int) -> CGRect {
        let x = self.originX + CGFloat(col) * (self.cellW + self.gapX)
        let y = self.originY + CGFloat(row) * (self.cellH + self.gapY)
        return CGRect(x: x, y: y, width: self.cellW, height: self.cellH)
    }
    
    
    func hitTest(point: CGPoint, weeks: [[HeatmapDayCell]]) -> HeatmapDayCell? {
        let stepX = self.cellW + self.gapX
        let stepY = self.cellH + self.gapY
        let col = Int(floor((point.x - self.originX) / stepX))
        let row = Int(floor((point.y - self.originY) / stepY))
        guard col >= 0, col < weeks.count, row >= 0, row < weeks[col].count else { return nil }
        let cell = weeks[col][row]
        guard !cell.isOutOfYear else { return nil }
        return cell
    }
}


// MARK: - Compact & Expanded Flippable Quad Cards (Trend, Sankey, Rose, Sunburst)

private struct DashboardCompactQuadCard: View {
    
    let metric: DashboardQuadMetric
    let snapshot: DashboardSnapshot
    let palette: DashPalette
    let namespace: Namespace.ID
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
        .matchedGeometryEffect(id: self.metric.rawValue, in: self.namespace)
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
                SankeyFlowChartView(snapshot: self.snapshot, palette: self.palette, detailed: false)
            case .busyness:
                NightingaleRoseChartView(metrics: self.snapshot.busyness, palette: self.palette, detailed: false)
            case .mood:
                EmotionSunburstChartView(metrics: self.snapshot.mood, palette: self.palette, detailed: false)
        }
    }
}


private struct DashboardExpandedQuadCard: View {
    
    let metric: DashboardQuadMetric
    let snapshot: DashboardSnapshot
    let palette: DashPalette
    let namespace: Namespace.ID
    let onClose: () -> Void
    
    @State private var flipAngle: Double = 90
    
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 10) {
                Text(self.metric.title)
                    .font(.system(size: 14.5, weight: .semibold))
                    .foregroundStyle(self.palette.pine)
                
                Text(self.detailHeadline)
                    .font(.system(size: 14.5, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(self.palette.emerald)
                
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
        .matchedGeometryEffect(id: self.metric.rawValue, in: self.namespace)
        .rotation3DEffect(.degrees(self.flipAngle), axis: (x: 0, y: 1, z: 0), perspective: 0.55)
        .onAppear {
            self.flipAngle = 90
            withAnimation(DashMotion.flip) {
                self.flipAngle = 0
            }
        }
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
                SankeyFlowChartView(snapshot: self.snapshot, palette: self.palette, detailed: true)
            case .busyness:
                NightingaleRoseChartView(metrics: self.snapshot.busyness, palette: self.palette, detailed: true)
            case .mood:
                EmotionSunburstChartView(metrics: self.snapshot.mood, palette: self.palette, detailed: true)
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
                
                Canvas { context, _ in
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


// MARK: - Chart 2: 3-Column Sankey Flow Diagram (桑基图)

private struct SankeyFlowChartView: View {
    
    let snapshot: DashboardSnapshot
    let palette: DashPalette
    let detailed: Bool
    
    
    private struct SankeyNode {
        var label: String
        var weight: Double
        var color: Color
    }
    
    
    var body: some View {
        GeometryReader { _ in
            Canvas { context, size in
                let padX: CGFloat = self.detailed ? 74 : 6
                let padY: CGFloat = self.detailed ? 10 : 4
                let nodeW: CGFloat = self.detailed ? 10 : 7
                let innerW = max(40, size.width - padX * 2)
                let innerH = max(36, size.height - padY * 2)
                
                let col1X = padX
                let col2X = padX + innerW * 0.5 - nodeW * 0.5
                let col3X = padX + innerW - nodeW
                
                let col1Nodes = self.leftFeatureNodes()
                let col2Nodes = self.middleModelNodes()
                let col3Nodes = self.rightSinkNodes()
                
                let rects1 = Self.layoutColumn(nodes: col1Nodes, x: col1X, yStart: padY, height: innerH, width: nodeW, gap: 6)
                let rects2 = Self.layoutColumn(nodes: col2Nodes, x: col2X, yStart: padY, height: innerH, width: nodeW, gap: 6)
                let rects3 = Self.layoutColumn(nodes: col3Nodes, x: col3X, yStart: padY, height: innerH, width: nodeW, gap: 6)
                
                // Draw flows Col 1 -> Col 2
                Self.drawFlows(context: &context, sources: rects1, targets: rects2)
                // Draw flows Col 2 -> Col 3
                Self.drawFlows(context: &context, sources: rects2, targets: rects3)
                
                // Draw column nodes
                for (node, layout) in zip(col1Nodes, rects1) {
                    let rect = layout.rect
                    let p = RoundedRectangle(cornerRadius: 2.5, style: .continuous).path(in: rect)
                    context.fill(p, with: .color(node.color))
                    if self.detailed {
                        context.draw(
                            Text(node.label)
                                .font(.system(size: 10.5, weight: .medium))
                                .foregroundStyle(self.palette.pine.opacity(0.85)),
                            at: CGPoint(x: rect.minX - 6, y: rect.midY),
                            anchor: .trailing
                        )
                    }
                }
                
                for (node, layout) in zip(col2Nodes, rects2) {
                    let rect = layout.rect
                    let p = RoundedRectangle(cornerRadius: 2.5, style: .continuous).path(in: rect)
                    context.fill(p, with: .color(node.color))
                    if self.detailed {
                        context.draw(
                            Text(node.label)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(self.palette.pine.opacity(0.9)),
                            at: CGPoint(x: rect.midX, y: max(rect.minY - 7, 8)),
                            anchor: .center
                        )
                    }
                }
                
                for (node, layout) in zip(col3Nodes, rects3) {
                    let rect = layout.rect
                    let p = RoundedRectangle(cornerRadius: 2.5, style: .continuous).path(in: rect)
                    context.fill(p, with: .color(node.color))
                    if self.detailed {
                        context.draw(
                            Text(node.label)
                                .font(.system(size: 10.5, weight: .medium))
                                .foregroundStyle(self.palette.pine.opacity(0.85)),
                            at: CGPoint(x: rect.maxX + 6, y: rect.midY),
                            anchor: .leading
                        )
                    }
                }
            }
        }
    }
    
    
    private func leftFeatureNodes() -> [SankeyNode] {
        let feats = self.snapshot.aiFeatures.prefix(3)
        if !feats.isEmpty {
            let colors = [self.palette.accentFill, self.palette.mint, self.palette.paleMint]
            return feats.enumerated().map { idx, f in
                SankeyNode(
                    label: f.displayName.isEmpty ? f.feature : f.displayName,
                    weight: max(1, Double(f.totalTokens > 0 ? f.totalTokens : f.requests * 100)),
                    color: colors[idx % colors.count]
                )
            }
        }
        return [
            SankeyNode(label: "续写", weight: 46, color: self.palette.accentFill),
            SankeyNode(label: "对话", weight: 32, color: self.palette.mint),
            SankeyNode(label: "摘要", weight: 22, color: self.palette.paleMint),
        ]
    }
    
    
    private func middleModelNodes() -> [SankeyNode] {
        let mods = self.snapshot.aiModels.prefix(3)
        if !mods.isEmpty {
            let colors = [self.palette.emerald, self.palette.heat(3), self.palette.heat(2)]
            return mods.enumerated().map { idx, m in
                SankeyNode(
                    label: Self.shortModelName(m.model),
                    weight: max(1, Double(m.totalTokens > 0 ? m.totalTokens : m.requests * 100)),
                    color: colors[idx % colors.count]
                )
            }
        }
        return [
            SankeyNode(label: "主力模型", weight: 62, color: self.palette.emerald),
            SankeyNode(label: "轻量模型", weight: 38, color: self.palette.heat(2)),
        ]
    }
    
    
    private func rightSinkNodes() -> [SankeyNode] {
        let totals = self.snapshot.ai30Totals
        let input = max(1, totals.inputTokens)
        let output = max(1, totals.outputTokens)
        if totals.inputTokens + totals.outputTokens > 0 {
            return [
                SankeyNode(label: "输入", weight: Double(input), color: self.palette.mint),
                SankeyNode(label: "生成", weight: Double(output), color: self.palette.accentFill),
            ]
        }
        return [
            SankeyNode(label: "输入", weight: 58, color: self.palette.mint),
            SankeyNode(label: "生成", weight: 42, color: self.palette.accentFill),
        ]
    }
    
    
    private static func shortModelName(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.count <= 14 ? trimmed : String(trimmed.prefix(13)) + "…"
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
        var targetOffsets = targets.map { $0.rect.minY }
        
        for src in sources {
            var srcOffsetY = src.rect.minY
            for (tIdx, tgt) in targets.enumerated() {
                let share = tgt.weight / totalTarget
                let ribbonSrcH = src.rect.height * CGFloat(share)
                let ribbonTgtH = tgt.rect.height * CGFloat(src.weight / max(1.0, sources.reduce(0.0) { $0 + $1.weight }))
                
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
                            src.color.opacity(0.32),
                            tgt.color.opacity(0.26),
                        ]),
                        startPoint: CGPoint(x: startX, y: sTop),
                        endPoint: CGPoint(x: endX, y: tTop)
                    )
                )
            }
        }
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


// MARK: - Chart 4: 2-Ring Emotion Sunburst Chart (旭日图)

private struct EmotionSunburstChartView: View {
    
    let metrics: MoodMetrics
    let palette: DashPalette
    let detailed: Bool
    
    @State private var hoveredLabel: String?
    
    
    var body: some View {
        VStack(spacing: 6) {
            GeometryReader { geo in
                Canvas { context, size in
                    let center = CGPoint(x: size.width * 0.5, y: size.height * 0.5)
                    let outerLimit = max(18, min(size.width, size.height) * 0.5 - (self.detailed ? 18 : 4))
                    let rCore = max(10, outerLimit * 0.30)
                    let rMid = max(rCore + 4, outerLimit * 0.64)
                    let rOuter = max(rMid + 6, outerLimit)
                    
                    let totalWeight = max(1.0, self.metrics.segments.reduce(0.0) { $0 + $1.weight })
                    var cursorDeg = -90.0
                    
                    for segment in self.metrics.segments {
                        let spanDeg = (segment.weight / totalWeight) * 360.0
                        let segStart = cursorDeg + 1.2
                        let segEnd = cursorDeg + spanDeg - 1.2
                        let baseColor = self.palette.toneColor(for: segment.tone)
                        
                        if segEnd > segStart {
                            var innerSector = Path()
                            innerSector.addArc(center: center, radius: rCore, startAngle: .degrees(segStart), endAngle: .degrees(segEnd), clockwise: false)
                            innerSector.addArc(center: center, radius: rMid - 1.5, startAngle: .degrees(segEnd), endAngle: .degrees(segStart), clockwise: true)
                            innerSector.closeSubpath()
                            context.fill(innerSector, with: .color(baseColor.opacity(0.86)))
                            
                            if self.detailed && spanDeg > 28 {
                                let midRad = (segStart + segEnd) * 0.5 * .pi / 180.0
                                let labelR = (rCore + rMid) * 0.5
                                context.draw(
                                    Text(segment.label)
                                        .font(.system(size: 10.5, weight: .semibold))
                                        .foregroundStyle(Color.white),
                                    at: CGPoint(x: center.x + CGFloat(cos(midRad)) * labelR, y: center.y + CGFloat(sin(midRad)) * labelR),
                                    anchor: .center
                                )
                            }
                        }
                        
                        let childSum = max(1.0, segment.children.reduce(0.0) { $0 + $1.value })
                        var childCursor = cursorDeg
                        for (cIdx, child) in segment.children.enumerated() {
                            let childSpan = (child.value / childSum) * spanDeg
                            let cStart = childCursor + 0.9
                            let cEnd = childCursor + childSpan - 0.9
                            if cEnd > cStart {
                                var outerSector = Path()
                                outerSector.addArc(center: center, radius: rMid + 1.5, startAngle: .degrees(cStart), endAngle: .degrees(cEnd), clockwise: false)
                                outerSector.addArc(center: center, radius: rOuter, startAngle: .degrees(cEnd), endAngle: .degrees(cStart), clockwise: true)
                                outerSector.closeSubpath()
                                let alpha = cIdx.isMultiple(of: 2) ? 0.58 : 0.40
                                context.fill(outerSector, with: .color(baseColor.opacity(alpha)))
                                
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
                            Text("\(self.metrics.score)")
                                .font(.system(size: 16, weight: .bold, design: .rounded).monospacedDigit())
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
                            self.hoveredLabel = self.hitTestSector(loc, in: geo.size)
                        case .ended:
                            self.hoveredLabel = nil
                    }
                }
            }
            
            if self.detailed {
                Text(self.hoveredLabel ?? " ")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(self.palette.pine.opacity(0.75))
                    .frame(height: 16)
            }
        }
    }
    
    
    private func hitTestSector(_ point: CGPoint, in size: CGSize) -> String? {
        let center = CGPoint(x: size.width * 0.5, y: size.height * 0.5)
        let outerLimit = max(18, min(size.width, size.height) * 0.5 - (self.detailed ? 18 : 4))
        let rCore = max(10, outerLimit * 0.30)
        let rMid = max(rCore + 4, outerLimit * 0.64)
        let dist = hypot(point.x - center.x, point.y - center.y)
        guard dist >= rCore && dist <= outerLimit else { return nil }
        
        var deg = atan2(point.y - center.y, point.x - center.x) * 180.0 / .pi + 90.0
        if deg < 0 { deg += 360.0 }
        
        let total = max(1.0, self.metrics.segments.reduce(0.0) { $0 + $1.weight })
        var cursor = 0.0
        for seg in self.metrics.segments {
            let span = (seg.weight / total) * 360.0
            if deg <= cursor + span {
                if dist <= rMid {
                    let pct = Int(((seg.weight / total) * 100).rounded())
                    return "\(seg.label) · 占比 \(pct)%"
                }
                let childTotal = max(1.0, seg.children.reduce(0.0) { $0 + $1.value })
                var cCursor = cursor
                for child in seg.children {
                    let cSpan = (child.value / childTotal) * span
                    if deg <= cCursor + cSpan {
                        return "\(seg.label) → \(child.label)"
                    }
                    cCursor += cSpan
                }
                return seg.label
            }
            cursor += span
        }
        return nil
    }
}


// MARK: - Supporting Components

private struct TodoChecklistRow: View {
    
    let item: UserReminder
    let palette: DashPalette
    let onToggle: () -> Void
    let onDelete: () -> Void
    
    @State private var isHovered = false
    
    
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Button(action: self.onToggle) {
                Image(systemName: self.item.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 13))
                    .foregroundStyle(self.item.isCompleted ? self.palette.emerald : self.palette.pine.opacity(0.42))
                    .padding(.top, 1)
            }
            .buttonStyle(.plain)
            
            Text(self.item.title)
                .font(.system(size: 12.5))
                .strikethrough(self.item.isCompleted)
                .foregroundStyle(self.item.isCompleted ? self.palette.pine.opacity(0.45) : self.palette.pine.opacity(0.88))
                .lineLimit(2)
            
            Spacer()
            
            if self.isHovered {
                Button(action: self.onDelete) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(self.palette.pine.opacity(0.45))
                        .frame(width: 16, height: 16)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 2)
        .onHover { hovering in
            self.isHovered = hovering
        }
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
