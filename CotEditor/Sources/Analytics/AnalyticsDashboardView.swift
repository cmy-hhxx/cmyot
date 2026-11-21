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


// MARK: - Editorial Studio Palette & Tokens

private struct StudioPalette {
    
    let isDark: Bool
    
    init(colorScheme: ColorScheme) {
        self.isDark = (colorScheme == .dark)
    }
    
    var paper: Color {
        self.isDark
            ? Color(red: 0.075, green: 0.075, blue: 0.071)   // #131312
            : Color(red: 0.976, green: 0.969, blue: 0.953)   // #F9F7F3
    }
    
    var card: Color {
        self.isDark
            ? Color(red: 0.106, green: 0.106, blue: 0.098)   // #1B1B19
            : Color.white                                     // #FFFFFF
    }
    
    var subtle: Color {
        self.isDark
            ? Color(red: 0.133, green: 0.133, blue: 0.125)   // #222220
            : Color(red: 0.937, green: 0.925, blue: 0.902)   // #EFECE6
    }
    
    var hairline: Color {
        self.isDark
            ? Color(red: 0.173, green: 0.169, blue: 0.157)   // #2C2B28
            : Color(red: 0.898, green: 0.878, blue: 0.843)   // #E5E0D7
    }
    
    var ink: Color {
        self.isDark
            ? Color(red: 0.949, green: 0.937, blue: 0.914)   // #F2EFE9
            : Color(red: 0.102, green: 0.102, blue: 0.094)   // #1A1A18
    }
    
    var secondaryInk: Color {
        self.isDark
            ? Color(red: 0.647, green: 0.631, blue: 0.596)   // #A5A198
            : Color(red: 0.361, green: 0.353, blue: 0.329)   // #5C5A54
    }
    
    var tertiaryInk: Color {
        self.isDark
            ? Color(red: 0.451, green: 0.435, blue: 0.404)   // #736F67
            : Color(red: 0.541, green: 0.525, blue: 0.490)   // #8A867D
    }
    
    var cinnabar: Color {
        self.isDark
            ? Color(red: 0.878, green: 0.427, blue: 0.325)   // #E06D53
            : Color(red: 0.722, green: 0.231, blue: 0.157)   // #B83B28
    }
    
    var pineGreen: Color {
        self.isDark
            ? Color(red: 0.459, green: 0.722, blue: 0.557)   // #75B88E
            : Color(red: 0.184, green: 0.365, blue: 0.275)   // #2F5D46
    }
    
    var heatmapLevels: [Color] {
        if self.isDark {
            return [
                Color(red: 0.133, green: 0.133, blue: 0.122), // #22221F
                Color(red: 0.145, green: 0.220, blue: 0.173), // #25382C
                Color(red: 0.208, green: 0.361, blue: 0.271), // #355C45
                Color(red: 0.298, green: 0.522, blue: 0.388), // #4C8563
                Color(red: 0.459, green: 0.722, blue: 0.557), // #75B88E
            ]
        }
        return [
            Color(red: 0.925, green: 0.914, blue: 0.886),     // #ECE9E2
            Color(red: 0.788, green: 0.827, blue: 0.780),     // #C9D3C7
            Color(red: 0.537, green: 0.639, blue: 0.553),     // #89A38D
            Color(red: 0.278, green: 0.431, blue: 0.329),     // #476E54
            Color(red: 0.114, green: 0.251, blue: 0.173),     // #1D402C
        ]
    }
    
    func heatmapColor(for level: Int) -> Color {
        let clamped = min(max(0, level), self.heatmapLevels.count - 1)
        return self.heatmapLevels[clamped]
    }
}


private enum StudioLens: String, CaseIterable, Identifiable {
    
    case typed
    case completion
    case consumption
    
    var id: String { self.rawValue }
    
    var title: String {
        switch self {
            case .typed: "今日手写"
            case .completion: "Tab 帮写"
            case .consumption: "AI 用量"
        }
    }
    
    var symbolName: String {
        switch self {
            case .typed: "pencil.line"
            case .completion: "keyboard.badge.ellipsis"
            case .consumption: "cpu"
        }
    }
}


private enum CadenceMode: String, CaseIterable, Identifiable {
    
    case fourteenDays
    case todayHourly
    
    var id: String { self.rawValue }
    
    var label: String {
        switch self {
            case .fourteenDays: "近 14 天节奏"
            case .todayHourly: "今日 24 小时脉搏"
        }
    }
}


private enum ConsumptionScope: String, CaseIterable, Identifiable {
    
    case today
    case thirtyDays
    
    var id: String { self.rawValue }
    
    var label: String {
        switch self {
            case .today: "今日"
            case .thirtyDays: "近 30 天"
        }
    }
}


// MARK: - Main Studio Ledger View

/// Editorial Studio Ledger analytics dashboard rendered inside the editor workspace or settings pane.
struct AnalyticsDashboardView: View {
    
    var isEmbeddedInSettings: Bool = false
    var onDismiss: (() -> Void)? = nil
    var onOpenDocument: ((StoredDocumentRecord) -> Void)? = nil
    var onOpenWeeklyReport: ((StoredWeeklyReport) -> Void)? = nil
    
    @Environment(\.colorScheme) private var colorScheme
    @State private var analytics = AnalyticsManager.shared
    @State private var userManager = UserProfileManager.shared
    @State private var predictor = AINextTokenPredictor.shared
    
    @State private var selectedLens: StudioLens? = nil
    @State private var selectedYear: Int = Calendar.current.component(.year, from: Date())
    @State private var selectedDateKey: String = AnalyticsManager.dateKey(for: Date())
    @State private var cadenceMode: CadenceMode = .fourteenDays
    @State private var consumptionScope: ConsumptionScope = .today
    @State private var refreshSpin = false
    
    
    private var palette: StudioPalette {
        StudioPalette(colorScheme: self.colorScheme)
    }
    
    
    private var openDocHandler: (StoredDocumentRecord) -> Void {
        self.onOpenDocument ?? { AnalyticsDashboardWindowController.shared.openDocument($0) }
    }
    
    
    private var openReportHandler: (StoredWeeklyReport) -> Void {
        self.onOpenWeeklyReport ?? { AnalyticsDashboardWindowController.shared.openWeeklyReport($0) }
    }
    
    
    var body: some View {
        let p = self.palette
        let outerPad: CGFloat = self.isEmbeddedInSettings ? 14 : 20
        
        VStack(spacing: 0) {
            self.headerBar(palette: p)
                .padding(.horizontal, outerPad)
                .frame(height: 48)
            
            Divider().overlay(p.hairline)
            
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 14) {
                    self.unifiedLensStrip(palette: p)
                    
                    self.stageContent(palette: p)
                        .animation(.easeOut(duration: 0.18), value: self.selectedLens)
                }
                .padding(.horizontal, outerPad)
                .padding(.vertical, 14)
            }
        }
        .background(p.paper)
        .foregroundStyle(p.ink)
        .onAppear {
            self.analytics.flushPendingStats()
            self.analytics.reloadFromDatabase()
            let years = self.analytics.availableHeatmapYears()
            if !years.contains(self.selectedYear), let latest = years.first {
                self.selectedYear = latest
            }
        }
    }
    
    
    // MARK: Compact 48pt Header
    
    @ViewBuilder
    private func headerBar(palette p: StudioPalette) -> some View {
        let streak = self.analytics.currentWritingStreak
        let availableYears = self.analytics.availableHeatmapYears()
        
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                Text("创作案头")
                    .font(.system(size: 16, weight: .semibold, design: .serif))
                    .foregroundStyle(p.ink)
                
                Text("·")
                    .foregroundStyle(p.tertiaryInk)
                
                Text(self.userManager.activeProfile.displayName)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(p.secondaryInk)
                
                if streak > 0 {
                    Text("连续 \(streak) 天")
                        .font(.system(size: 11, weight: .medium).monospacedDigit())
                        .foregroundStyle(p.cinnabar)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(p.cinnabar.opacity(self.colorScheme == .dark ? 0.14 : 0.09))
                        )
                }
            }
            
            Spacer(minLength: 8)
            
            HStack(spacing: 8) {
                if self.selectedLens != nil {
                    Button {
                        withAnimation(.easeOut(duration: 0.18)) {
                            self.selectedLens = nil
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 10, weight: .semibold))
                            Text("返回年鉴")
                                .font(.system(size: 11.5, weight: .medium))
                        }
                        .foregroundStyle(p.cinnabar)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(p.cinnabar.opacity(self.colorScheme == .dark ? 0.14 : 0.08))
                        )
                    }
                    .buttonStyle(.plain)
                } else if availableYears.count > 1 {
                    Menu {
                        ForEach(availableYears, id: \.self) { year in
                            Button("\(String(year)) 年") {
                                self.selectedYear = year
                                let hm = self.analytics.yearlyHeatmap(year: year, trimFutureWeeks: false)
                                if let latest = hm.weeks.flatMap(\.self).last(where: { !$0.isOutOfYear && !$0.isFuture && $0.typedChars > 0 }) {
                                    self.selectedDateKey = latest.dateKey
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text("\(String(self.selectedYear)) 年")
                                .font(.system(size: 11.5, weight: .medium).monospacedDigit())
                            Image(systemName: "chevron.down")
                                .font(.system(size: 9, weight: .semibold))
                        }
                        .foregroundStyle(p.secondaryInk)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(p.subtle)
                        )
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                } else {
                    Text("\(String(self.selectedYear)) 年")
                        .font(.system(size: 11.5, weight: .medium).monospacedDigit())
                        .foregroundStyle(p.tertiaryInk)
                }
                
                Button {
                    self.analytics.flushPendingStats()
                    self.analytics.reloadFromDatabase()
                    withAnimation(.easeInOut(duration: 0.35)) {
                        self.refreshSpin.toggle()
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(p.secondaryInk)
                        .rotationEffect(.degrees(self.refreshSpin ? 360 : 0))
                        .frame(width: 26, height: 26)
                        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(p.subtle))
                }
                .buttonStyle(.plain)
                .help("刷新本地统计数据")
                
                if let onDismiss = self.onDismiss {
                    Button {
                        onDismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(p.secondaryInk)
                            .frame(width: 26, height: 26)
                            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(p.subtle))
                    }
                    .buttonStyle(.plain)
                    .help("关闭创作案头 (Esc)")
                }
            }
        }
    }
    
    
    // MARK: Unified Top Lens Strip (42% / 29% / 29%)
    
    @ViewBuilder
    private func unifiedLensStrip(palette p: StudioPalette) -> some View {
        let today = self.analytics.todayStats
        let todayAI = self.analytics.aiUsageTotals(forTodayOnly: true)
        let percentile = self.analytics.typedPercentile(for: today.typedChars)
        let pages = Double(today.typedChars) / 500.0
        
        let totalCompleted = today.aiCompletedChars
        let localRatio: Int = totalCompleted > 0
            ? Int((Double(min(today.localAcceptedChars, totalCompleted)) * 100.0 / Double(totalCompleted)).rounded())
            : (today.localHits > 0 ? 100 : 0)
        
        let typedSubtitle = today.typedChars > 0
            ? String(format: "约 %.1f 页纸书 · 超过 %d%% 创作日", pages, percentile)
            : "500 字折合 1 页纸书 · 准备起笔"
        
        let completionSubtitle = today.aiCompletionAccepts > 0
            ? "省敲 \(today.aiCompletionAccepts) 次 · 本地占 \(localRatio)%"
            : "尚未接纳续写 · 支持 Tab 一键采纳"
        
        let consumptionSubtitle = "\(todayAI.requests) 次调用 · 本地拦截 \(today.localHits) 次"
        
        GeometryReader { geo in
            let w = geo.size.width
            let w1 = w * 0.42
            let w2 = w * 0.29
            let w3 = max(0, w - w1 - w2 - 2)
            
            HStack(spacing: 0) {
                self.lensCell(
                    lens: .typed,
                    value: today.typedChars.formatted(),
                    unit: "字",
                    subtitle: typedSubtitle,
                    width: w1,
                    isHero: true,
                    palette: p
                )
                
                Rectangle().fill(p.hairline).frame(width: 1)
                
                self.lensCell(
                    lens: .completion,
                    value: today.aiCompletedChars.formatted(),
                    unit: "字",
                    subtitle: completionSubtitle,
                    width: w2,
                    isHero: false,
                    palette: p
                )
                
                Rectangle().fill(p.hairline).frame(width: 1)
                
                self.lensCell(
                    lens: .consumption,
                    value: AnalyticsManager.formatCompactTokenCount(todayAI.totalTokens),
                    unit: "Tokens",
                    subtitle: consumptionSubtitle,
                    width: w3,
                    isHero: false,
                    palette: p
                )
            }
        }
        .frame(height: 86)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(p.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(p.hairline, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
    
    
    @ViewBuilder
    private func lensCell(
        lens: StudioLens,
        value: String,
        unit: String,
        subtitle: String,
        width: CGFloat,
        isHero: Bool,
        palette p: StudioPalette
    ) -> some View {
        let isActive = (self.selectedLens == lens)
        
        Button {
            withAnimation(.easeOut(duration: 0.18)) {
                self.selectedLens = (self.selectedLens == lens) ? nil : lens
            }
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 5) {
                    Image(systemName: lens.symbolName)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(isActive ? p.cinnabar : p.secondaryInk)
                    Text(lens.title)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(isActive ? p.ink : p.secondaryInk)
                    Spacer(minLength: 0)
                    if isActive {
                        Circle()
                            .fill(p.cinnabar)
                            .frame(width: 5, height: 5)
                    }
                }
                
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(value)
                        .font(.system(size: isHero ? 26 : 22, weight: .semibold, design: .serif).monospacedDigit())
                        .foregroundStyle(p.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    Text(unit)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(p.tertiaryInk)
                }
                
                Text(subtitle)
                    .font(.system(size: 10.5))
                    .foregroundStyle(p.tertiaryInk)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(width: max(0, width), height: 86, alignment: .leading)
            .background(isActive ? p.cinnabar.opacity(self.colorScheme == .dark ? 0.08 : 0.04) : Color.clear)
            .overlay(alignment: .bottom) {
                if isActive {
                    Rectangle()
                        .fill(p.cinnabar)
                        .frame(height: 2.5)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
    
    
    // MARK: Single-Focus Stage
    
    @ViewBuilder
    private func stageContent(palette p: StudioPalette) -> some View {
        switch self.selectedLens {
            case nil:
                self.overviewStage(palette: p)
            case .typed:
                self.typedStage(palette: p)
            case .completion:
                self.completionStage(palette: p)
            case .consumption:
                self.consumptionStage(palette: p)
        }
    }
    
    
    // MARK: Stage 0 — 年鉴总览
    
    @ViewBuilder
    private func overviewStage(palette p: StudioPalette) -> some View {
        let heatmap = self.analytics.yearlyHeatmap(year: self.selectedYear, trimFutureWeeks: false)
        let longest = self.analytics.longestWritingStreak(year: self.selectedYear)
        let allCells = heatmap.weeks.flatMap(\.self).filter { !$0.isOutOfYear }
        let selectedCell = allCells.first(where: { $0.dateKey == self.selectedDateKey })
            ?? allCells.last(where: { !$0.isFuture && $0.typedChars > 0 })
            ?? allCells.last(where: { !$0.isFuture })
            ?? HeatmapDayCell(dateKey: self.selectedDateKey, date: Date(), typedChars: 0, aiCompletedChars: 0, filesCreated: 0, aiRequests: 0, level: 0, isFuture: false)
        let detail = self.analytics.dayDetail(for: selectedCell)
        let story = self.analytics.humanDayStory(for: selectedCell)
        
        VStack(alignment: .leading, spacing: 14) {
            // 1. Full-width 53-week Pine-Soot Ink Heatmap
            StudioCard(palette: p) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("\(String(self.selectedYear)) 创作年鉴")
                            .font(.system(size: 13.5, weight: .semibold, design: .serif))
                            .foregroundStyle(p.ink)
                        
                        Spacer(minLength: 8)
                        
                        Text("活跃 \(heatmap.activeDays) 天 · \(heatmap.totalTypedChars.formatted()) 字 · 最长连续 \(longest) 天")
                            .font(.system(size: 11).monospacedDigit())
                            .foregroundStyle(p.secondaryInk)
                    }
                    
                    PineSootHeatmapGrid(
                        heatmap: heatmap,
                        selectedDateKey: selectedCell.dateKey,
                        palette: p,
                        onSelectCell: { cell in
                            self.selectedDateKey = cell.dateKey
                        }
                    )
                    
                    HStack(spacing: 6) {
                        Text("点击任意方格回溯当日文稿与记录")
                            .font(.system(size: 10.5))
                            .foregroundStyle(p.tertiaryInk)
                        Spacer()
                        HStack(spacing: 3) {
                            Text("浅")
                                .font(.system(size: 9.5))
                                .foregroundStyle(p.tertiaryInk)
                            ForEach(0..<5, id: \.self) { level in
                                RoundedRectangle(cornerRadius: 2, style: .continuous)
                                    .fill(p.heatmapColor(for: level))
                                    .frame(width: 9, height: 9)
                            }
                            Text("深")
                                .font(.system(size: 9.5))
                                .foregroundStyle(p.tertiaryInk)
                        }
                    }
                }
            }
            
            // 2. 58 / 42 Asymmetric Document Directory & Daily Ledger
            HStack(alignment: .top, spacing: 14) {
                self.dayDocumentsDirectoryCard(story: story, detail: detail, palette: p)
                    .frame(maxWidth: .infinity)
                
                self.dayFactualLedgerCard(story: story, detail: detail, palette: p)
                    .frame(width: self.isEmbeddedInSettings ? 276 : 336)
            }
        }
    }
    
    
    @ViewBuilder
    private func dayDocumentsDirectoryCard(
        story: DailyHumanStory,
        detail: HeatmapDayDetail,
        palette p: StudioPalette
    ) -> some View {
        StudioCard(palette: p) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("\(story.dateBadge) · 落笔目录")
                        .font(.system(size: 13, weight: .semibold, design: .serif))
                        .foregroundStyle(p.ink)
                    Spacer()
                    let count = detail.documents.count + detail.weeklyReports.count
                    if count > 0 {
                        Text("\(count) 份存档")
                            .font(.system(size: 10.5).monospacedDigit())
                            .foregroundStyle(p.tertiaryInk)
                    }
                }
                
                if detail.documents.isEmpty && detail.weeklyReports.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("当日暂无本地存档记录")
                            .font(.system(size: 12))
                            .foregroundStyle(p.secondaryInk)
                        Text("你在编辑器中保存或编辑的文档会按日期沉淀在这里，方便随时回翻。")
                            .font(.system(size: 11))
                            .foregroundStyle(p.tertiaryInk)
                    }
                    .padding(.vertical, 18)
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    VStack(spacing: 6) {
                        ForEach(detail.documents) { doc in
                            self.documentDirectoryRow(doc: doc, palette: p)
                        }
                        ForEach(detail.weeklyReports) { report in
                            self.weeklyReportDirectoryRow(report: report, palette: p)
                        }
                    }
                }
            }
        }
    }
    
    
    @ViewBuilder
    private func documentDirectoryRow(doc: StoredDocumentRecord, palette p: StudioPalette) -> some View {
        let preview = AnalyticsManager.documentFirstLinePreview(doc.content)
        
        Button {
            self.openDocHandler(doc)
        } label: {
            HStack(alignment: .top, spacing: 9) {
                Image(systemName: "doc.text")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(p.cinnabar)
                    .frame(width: 18, height: 18)
                    .padding(.top, 1)
                
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(doc.title.isEmpty ? "未命名文稿" : doc.title)
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundStyle(p.ink)
                            .lineLimit(1)
                        
                        if !doc.syntax.isEmpty && doc.syntax != "Plain Text" {
                            Text(doc.syntax)
                                .font(.system(size: 9.5, weight: .medium))
                                .foregroundStyle(p.secondaryInk)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(RoundedRectangle(cornerRadius: 4).fill(p.subtle))
                        }
                    }
                    
                    if !preview.isEmpty {
                        Text(preview)
                            .font(.system(size: 11))
                            .foregroundStyle(p.tertiaryInk)
                            .lineLimit(1)
                    }
                }
                
                Spacer(minLength: 6)
                
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(doc.content.count.formatted()) 字")
                        .font(.system(size: 11).monospacedDigit())
                        .foregroundStyle(p.secondaryInk)
                    Text(Self.shortTimeString(doc.updatedAt))
                        .font(.system(size: 10).monospacedDigit())
                        .foregroundStyle(p.tertiaryInk)
                }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(p.subtle.opacity(0.65))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
    
    
    @ViewBuilder
    private func weeklyReportDirectoryRow(report: StoredWeeklyReport, palette p: StudioPalette) -> some View {
        Button {
            self.openReportHandler(report)
        } label: {
            HStack(spacing: 9) {
                Image(systemName: "calendar.badge.clock")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(p.pineGreen)
                    .frame(width: 18)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(report.title)
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(p.ink)
                        .lineLimit(1)
                    Text("周报归档 · \(report.periodLabel)")
                        .font(.system(size: 10.5))
                        .foregroundStyle(p.tertiaryInk)
                }
                
                Spacer()
                
                Text("\(report.content.count.formatted()) 字")
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(p.secondaryInk)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(p.subtle.opacity(0.65))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
    
    
    @ViewBuilder
    private func dayFactualLedgerCard(
        story: DailyHumanStory,
        detail: HeatmapDayDetail,
        palette p: StudioPalette
    ) -> some View {
        StudioCard(palette: p) {
            VStack(alignment: .leading, spacing: 10) {
                Text("当日笔录")
                    .font(.system(size: 13, weight: .semibold, design: .serif))
                    .foregroundStyle(p.ink)
                
                Text(story.headline)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(p.ink)
                    .fixedSize(horizontal: false, vertical: true)
                
                if !story.highlights.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(story.highlights, id: \.self) { point in
                            HStack(alignment: .top, spacing: 6) {
                                Text("—")
                                    .font(.system(size: 11))
                                    .foregroundStyle(p.cinnabar)
                                Text(point)
                                    .font(.system(size: 11.5))
                                    .foregroundStyle(p.secondaryInk)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
                
                Divider().overlay(p.hairline)
                
                VStack(spacing: 6) {
                    self.ledgerKeyValueRow(label: "手写字数", value: "\(story.handTypedChars.formatted()) 字", palette: p)
                    self.ledgerKeyValueRow(label: "Tab 补全", value: "\(story.aiChars.formatted()) 字", palette: p)
                    self.ledgerKeyValueRow(label: "新建 / 保存", value: "\(story.createdCount) 篇 / \(story.savedCount) 次", palette: p)
                    if detail.averageLatencyMs > 0 {
                        self.ledgerKeyValueRow(label: "AI 平均响应", value: "\(detail.averageLatencyMs) ms", palette: p)
                    }
                }
            }
        }
    }
    
    
    @ViewBuilder
    private func ledgerKeyValueRow(label: String, value: String, palette p: StudioPalette) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(p.tertiaryInk)
            Spacer()
            Text(value)
                .font(.system(size: 11.5, weight: .medium).monospacedDigit())
                .foregroundStyle(p.ink)
        }
    }
    
    
    // MARK: Stage 1 — .typed 手稿刻度 · 作品与心流档案
    
    @ViewBuilder
    private func typedStage(palette p: StudioPalette) -> some View {
        let series14 = self.analytics.dailySeries(days: 14)
        let prior14 = series14.dropLast().filter { $0.typedChars > 0 }
        let avg14 = prior14.isEmpty ? 0 : prior14.reduce(0) { $0 + $1.typedChars } / prior14.count
        let todayChars = self.analytics.todayStats.typedChars
        let record = self.analytics.personalRecordTypedChars()
        let hourly = self.analytics.hourlyWritingPulse(for: self.analytics.todayStats.dateKey)
        let weekdayPoints = self.analytics.weekdayActivityDistribution(days: 90)
        
        let todayKey = self.analytics.todayStats.dateKey
        let todayDocs = CotLocalDatabase.shared.documents
            .filter { doc in
                !doc.id.hasPrefix("weekly:") && (
                    AnalyticsManager.dateKey(for: doc.updatedAt) == todayKey ||
                    doc.createdAt.map { AnalyticsManager.dateKey(for: $0) == todayKey } == true
                )
            }
            .sorted { $0.updatedAt > $1.updatedAt }
            .prefix(6)
        
        VStack(alignment: .leading, spacing: 14) {
            // 1. Manuscript Scale Ruler
            StudioCard(palette: p) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("手稿字数标尺")
                            .font(.system(size: 13.5, weight: .semibold, design: .serif))
                        Spacer()
                        HStack(spacing: 12) {
                            Text("14 日均笔 \(avg14.formatted()) 字")
                                .font(.system(size: 11).monospacedDigit())
                                .foregroundStyle(p.secondaryInk)
                            if let record {
                                Text("历史单日峰值 \(record.chars.formatted()) 字 (\(record.dateKey.suffix(5)))")
                                    .font(.system(size: 11).monospacedDigit())
                                    .foregroundStyle(p.cinnabar)
                            }
                        }
                    }
                    
                    ManuscriptScaleRuler(
                        todayChars: todayChars,
                        averageChars: avg14,
                        recordChars: record?.chars ?? 0,
                        palette: p
                    )
                    .frame(height: 68)
                }
            }
            
            // 2. Cadence Chart (14-Day vs 24-Hour Pulse)
            StudioCard(palette: p) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text(self.cadenceMode == .fourteenDays ? "近 14 天产出节奏" : "今日 24 小时输入脉搏")
                            .font(.system(size: 13, weight: .semibold, design: .serif))
                        Spacer()
                        Picker("", selection: self.$cadenceMode) {
                            ForEach(CadenceMode.allCases) { mode in
                                Text(mode.label).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .frame(width: 240)
                    }
                    
                    if self.cadenceMode == .fourteenDays {
                        FourteenDayTypedChart(series: series14, averageChars: avg14, palette: p)
                            .frame(height: 150)
                    } else {
                        HourlyPulseChart(hourlyValues: hourly, palette: p)
                            .frame(height: 150)
                    }
                }
            }
            
            // 3. Weekday Rhythm + Today's Documents
            HStack(alignment: .top, spacing: 14) {
                StudioCard(palette: p) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("周内写作习惯（近 90 天均笔）")
                            .font(.system(size: 13, weight: .semibold, design: .serif))
                        
                        let peakWeekday = weekdayPoints.max(by: { $0.averageChars < $1.averageChars })?.averageChars ?? 1
                        let peakDenom = max(1, peakWeekday)
                        
                        VStack(spacing: 7) {
                            ForEach(weekdayPoints) { point in
                                HStack(spacing: 8) {
                                    Text(point.label)
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundStyle(p.secondaryInk)
                                        .frame(width: 28, alignment: .leading)
                                    
                                    GeometryReader { geo in
                                        let ratio = min(1.0, Double(point.averageChars) / Double(peakDenom))
                                        ZStack(alignment: .leading) {
                                            RoundedRectangle(cornerRadius: 3)
                                                .fill(p.subtle)
                                            RoundedRectangle(cornerRadius: 3)
                                                .fill(point.averageChars == peakWeekday && peakWeekday > 0 ? p.cinnabar : p.pineGreen.opacity(0.75))
                                                .frame(width: max(point.averageChars > 0 ? 4 : 0, geo.size.width * ratio))
                                        }
                                    }
                                    .frame(height: 8)
                                    
                                    Text("\(point.averageChars.formatted())")
                                        .font(.system(size: 10.5).monospacedDigit())
                                        .foregroundStyle(p.tertiaryInk)
                                        .frame(width: 46, alignment: .trailing)
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                
                StudioCard(palette: p) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("今日动笔篇目")
                                .font(.system(size: 13, weight: .semibold, design: .serif))
                            Spacer()
                            Text("\(todayDocs.count) 篇")
                                .font(.system(size: 10.5).monospacedDigit())
                                .foregroundStyle(p.tertiaryInk)
                        }
                        
                        if todayDocs.isEmpty {
                            Text("今日还没有保存到本地库的文稿。")
                                .font(.system(size: 11.5))
                                .foregroundStyle(p.tertiaryInk)
                                .padding(.vertical, 24)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            VStack(spacing: 6) {
                                ForEach(Array(todayDocs)) { doc in
                                    self.documentDirectoryRow(doc: doc, palette: p)
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
    
    
    // MARK: Stage 2 — .completion Tab 减负银行 · 双引擎直觉图谱
    
    @ViewBuilder
    private func completionStage(palette p: StudioPalette) -> some View {
        let today = self.analytics.todayStats
        let localChars = min(today.localAcceptedChars, today.aiCompletedChars)
        let cloudChars = max(0, today.aiCompletedChars - localChars)
        let localSharePct: Int = today.aiCompletedChars > 0
            ? Int((Double(localChars) * 100.0 / Double(today.aiCompletedChars)).rounded())
            : (today.localHits > 0 ? 100 : 0)
        let series14 = self.analytics.dailySeries(days: 14)
        let habitSnapshot = UserHabitPredictor.shared.habitSnapshot(limit: 6)
        
        VStack(alignment: .leading, spacing: 14) {
            // 1. Tactile Tab Keycap + 4 Concrete Telemetry Figures
            StudioCard(palette: p) {
                HStack(spacing: 16) {
                    VStack(spacing: 4) {
                        HStack(spacing: 5) {
                            Image(systemName: "arrow.right.to.line")
                                .font(.system(size: 12, weight: .semibold))
                            Text("Tab")
                                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        }
                        .foregroundStyle(p.ink)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(p.paper)
                                .shadow(color: .black.opacity(self.colorScheme == .dark ? 0.35 : 0.08), radius: 1, y: 1.5)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .strokeBorder(p.hairline, lineWidth: 1.2)
                        )
                        
                        Text("减负键")
                            .font(.system(size: 10))
                            .foregroundStyle(p.tertiaryInk)
                    }
                    
                    Divider().frame(height: 52).overlay(p.hairline)
                    
                    HStack(spacing: 0) {
                        self.telemetryColumn(
                            label: "少敲字符",
                            value: "\(today.aiCompletedChars.formatted())",
                            note: "本地 \(localChars) / 云端 \(cloudChars)",
                            palette: p
                        )
                        self.telemetryColumn(
                            label: "接纳次数",
                            value: "\(today.aiCompletionAccepts)",
                            note: "次即时落笔",
                            palette: p
                        )
                        self.telemetryColumn(
                            label: "单次最长",
                            value: "\(today.maxSingleAcceptChars)",
                            note: "字一整句补全",
                            palette: p
                        )
                        self.telemetryColumn(
                            label: "本地发动机",
                            value: "\(localSharePct)%",
                            note: "\(today.localHits) 次零消耗命中",
                            palette: p
                        )
                    }
                }
            }
            
            // 2. 14-Day Dual-Engine Mirrored / Stacked Relay Chart
            StudioCard(palette: p) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("14 天双引擎补全接力（本地直觉 vs 云端 FIM）")
                            .font(.system(size: 13, weight: .semibold, design: .serif))
                        Spacer()
                        HStack(spacing: 12) {
                            HStack(spacing: 4) {
                                RoundedRectangle(cornerRadius: 2).fill(p.pineGreen).frame(width: 8, height: 8)
                                Text("本地零耗时").font(.system(size: 10.5)).foregroundStyle(p.secondaryInk)
                            }
                            HStack(spacing: 4) {
                                RoundedRectangle(cornerRadius: 2).fill(p.cinnabar).frame(width: 8, height: 8)
                                Text("云端续写").font(.system(size: 10.5)).foregroundStyle(p.secondaryInk)
                            }
                        }
                    }
                    
                    DualEngineCompletionChart(series: series14, palette: p)
                        .frame(height: 150)
                }
            }
            
            // 3. Learned User Habit Chains
            StudioCard(palette: p) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("已养成的写作直觉图谱")
                            .font(.system(size: 13, weight: .semibold, design: .serif))
                        Spacer()
                        Text("衔接规则 \(habitSnapshot.transitionCount) 条 · 记忆词汇 \(habitSnapshot.vocabularyCount) 个")
                            .font(.system(size: 10.5).monospacedDigit())
                            .foregroundStyle(p.secondaryInk)
                    }
                    
                    if habitSnapshot.topChains.isEmpty {
                        Text("随着日常写作和 Tab 采纳，系统会在本地静默记住你的常用前文与接续习惯（全程不上云）。")
                            .font(.system(size: 11.5))
                            .foregroundStyle(p.tertiaryInk)
                            .padding(.vertical, 8)
                    } else {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 8)], spacing: 8) {
                            ForEach(habitSnapshot.topChains) { chain in
                                HStack(spacing: 6) {
                                    Text(chain.trigger)
                                        .font(.system(size: 11.5, weight: .medium))
                                        .foregroundStyle(p.secondaryInk)
                                        .lineLimit(1)
                                    Image(systemName: "arrow.right")
                                        .font(.system(size: 9.5, weight: .semibold))
                                        .foregroundStyle(p.cinnabar)
                                    Text(chain.candidate)
                                        .font(.system(size: 11.5, weight: .semibold))
                                        .foregroundStyle(p.ink)
                                        .lineLimit(1)
                                    Spacer(minLength: 4)
                                    Text("×\(chain.count)")
                                        .font(.system(size: 10).monospacedDigit())
                                        .foregroundStyle(p.pineGreen)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .fill(p.subtle.opacity(0.75))
                                )
                            }
                        }
                    }
                }
            }
        }
    }
    
    
    @ViewBuilder
    private func telemetryColumn(label: String, value: String, note: String, palette p: StudioPalette) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 10.5))
                .foregroundStyle(p.tertiaryInk)
            Text(value)
                .font(.system(size: 20, weight: .semibold, design: .serif).monospacedDigit())
                .foregroundStyle(p.ink)
            Text(note)
                .font(.system(size: 10))
                .foregroundStyle(p.secondaryInk)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    
    // MARK: Stage 3 — .consumption 精密算力小票 · 省流护盾与效能雷达
    
    @ViewBuilder
    private func consumptionStage(palette p: StudioPalette) -> some View {
        let isToday = (self.consumptionScope == .today)
        let saved = self.analytics.estimatedTokensSavedByLocalHits(forTodayOnly: isToday, days: 30)
        let routing = self.predictor.resolveModelRouting(baseConfig: AIConfiguration.current)
        let dailyCap = AINextTokenPredictor.dailyCap
        let sentToday = self.predictor.todayStats.aiRequests
        let features = isToday
            ? self.analytics.todayFeatureDistribution()
            : self.analytics.featureDistribution(days: 30)
        let models = self.analytics.modelPerformanceSummaries(forTodayOnly: isToday, days: 30)
        let events = self.analytics.recentAIEventsSlice(forTodayOnly: isToday, days: 30, limit: 8)
        
        VStack(alignment: .leading, spacing: 14) {
            // Scope Switcher Bar
            HStack {
                Text("算力明细与省流路由")
                    .font(.system(size: 13.5, weight: .semibold, design: .serif))
                Spacer()
                Picker("", selection: self.$consumptionScope) {
                    ForEach(ConsumptionScope.allCases) { scope in
                        Text(scope.label).tag(scope)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 150)
            }
            
            // 1. Zero-Waste Local Shield + Daily Cap
            StudioCard(palette: p) {
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Image(systemName: "shield.lefthalf.filled")
                                .font(.system(size: 12))
                                .foregroundStyle(p.pineGreen)
                            Text("本地零消耗护盾")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text("\(saved.localHits)")
                                .font(.system(size: 22, weight: .semibold, design: .serif).monospacedDigit())
                            Text("次拦截 · 约省下 \(AnalyticsManager.formatCompactTokenCount(saved.estimatedTokens)) Tokens")
                                .font(.system(size: 11).monospacedDigit())
                                .foregroundStyle(p.secondaryInk)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    
                    Divider().frame(height: 44).overlay(p.hairline)
                    
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text("续写当前路由")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(p.secondaryInk)
                            Spacer()
                            Text(routing.effectiveModel.isEmpty ? "未配置模型" : routing.effectiveModel)
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .foregroundStyle(routing.isAutoRouted ? p.pineGreen : p.ink)
                        }
                        
                        let capDenom = max(1, dailyCap)
                        let capRatio = dailyCap > 0 ? min(1.0, Double(sentToday) / Double(capDenom)) : 0
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 3).fill(p.subtle)
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(capRatio >= 0.85 ? p.cinnabar : p.pineGreen)
                                    .frame(width: geo.size.width * capRatio)
                            }
                        }
                        .frame(height: 6)
                        
                        Text(dailyCap > 0 ? "今日智能续写配额 \(sentToday) / \(dailyCap) 次" : "今日已发送 \(sentToday) 次（无上限）")
                            .font(.system(size: 10).monospacedDigit())
                            .foregroundStyle(p.tertiaryInk)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            
            // 2. Feature Breakdown + Model Performance Table
            HStack(alignment: .top, spacing: 14) {
                StudioCard(palette: p) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("各能力 Token 分布")
                            .font(.system(size: 12.5, weight: .semibold, design: .serif))
                        
                        if features.isEmpty {
                            Text("该时段暂无云端 AI 调用记录。")
                                .font(.system(size: 11.5))
                                .foregroundStyle(p.tertiaryInk)
                                .padding(.vertical, 14)
                        } else {
                            VStack(spacing: 7) {
                                ForEach(features.prefix(6)) { item in
                                    VStack(alignment: .leading, spacing: 3) {
                                        HStack {
                                            Text(item.displayName)
                                                .font(.system(size: 11.5, weight: .medium))
                                            Spacer()
                                            Text("\(item.requests) 次 · \(AnalyticsManager.formatCompactTokenCount(item.totalTokens))")
                                                .font(.system(size: 10.5).monospacedDigit())
                                                .foregroundStyle(p.secondaryInk)
                                        }
                                        GeometryReader { geo in
                                            ZStack(alignment: .leading) {
                                                RoundedRectangle(cornerRadius: 2).fill(p.subtle)
                                                RoundedRectangle(cornerRadius: 2)
                                                    .fill(p.cinnabar.opacity(0.85))
                                                    .frame(width: max(3, geo.size.width * min(1.0, item.share)))
                                            }
                                        }
                                        .frame(height: 5)
                                    }
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                
                StudioCard(palette: p) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("模型效能台账")
                            .font(.system(size: 12.5, weight: .semibold, design: .serif))
                        
                        if models.isEmpty {
                            Text("该时段暂无模型响应样本。")
                                .font(.system(size: 11.5))
                                .foregroundStyle(p.tertiaryInk)
                                .padding(.vertical, 14)
                        } else {
                            VStack(spacing: 6) {
                                ForEach(models.prefix(5)) { model in
                                    HStack(spacing: 6) {
                                        Text(model.model)
                                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                                            .lineLimit(1)
                                            .truncationMode(.middle)
                                        Spacer()
                                        Text("\(model.requests)x")
                                            .font(.system(size: 10.5).monospacedDigit())
                                            .foregroundStyle(p.secondaryInk)
                                        Text(model.averageLatencyMs > 0 ? "\(model.averageLatencyMs)ms" : "-")
                                            .font(.system(size: 10.5).monospacedDigit())
                                            .foregroundStyle(p.tertiaryInk)
                                            .frame(width: 48, alignment: .trailing)
                                        Text("\(Int((model.successRate * 100).rounded()))%")
                                            .font(.system(size: 10.5, weight: .medium).monospacedDigit())
                                            .foregroundStyle(model.successRate >= 0.9 ? p.pineGreen : p.cinnabar)
                                            .frame(width: 34, alignment: .trailing)
                                    }
                                    .padding(.vertical, 2)
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity)
            }
            
            // 3. Recent Compute Receipt Tape
            StudioCard(palette: p) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("最近算力小票")
                            .font(.system(size: 12.5, weight: .semibold, design: .serif))
                        Spacer()
                        Text("按时间倒序保留最近 \(events.count) 笔")
                            .font(.system(size: 10.5))
                            .foregroundStyle(p.tertiaryInk)
                    }
                    
                    if events.isEmpty {
                        Text("尚未产生近期调用流水。")
                            .font(.system(size: 11.5))
                            .foregroundStyle(p.tertiaryInk)
                            .padding(.vertical, 10)
                    } else {
                        VStack(spacing: 4) {
                            ForEach(events) { event in
                                HStack(spacing: 8) {
                                    Circle()
                                        .fill(event.success ? p.pineGreen : p.cinnabar)
                                        .frame(width: 6, height: 6)
                                    Text(Self.shortTimeString(event.timestamp))
                                        .font(.system(size: 10.5, design: .monospaced))
                                        .foregroundStyle(p.tertiaryInk)
                                    Text(AnalyticsManager.featureDisplayName(for: event.feature))
                                        .font(.system(size: 11, weight: .medium))
                                        .frame(width: 68, alignment: .leading)
                                        .lineLimit(1)
                                    Text(event.model)
                                        .font(.system(size: 10.5, design: .monospaced))
                                        .foregroundStyle(p.secondaryInk)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                    Spacer()
                                    Text("\(event.inputTokens)↑ / \(event.outputTokens)↓")
                                        .font(.system(size: 10.5, design: .monospaced))
                                        .foregroundStyle(p.secondaryInk)
                                    Text("\(event.latencyMs)ms")
                                        .font(.system(size: 10.5, design: .monospaced))
                                        .foregroundStyle(p.tertiaryInk)
                                        .frame(width: 48, alignment: .trailing)
                                }
                                .padding(.vertical, 3)
                            }
                        }
                    }
                }
            }
        }
    }
    
    
    private static func shortTimeString(_ date: Date) -> String {
        
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: date)
    }
}


// MARK: - Editorial Card Shell

private struct StudioCard<Content: View>: View {
    
    let palette: StudioPalette
    @ViewBuilder var content: () -> Content
    
    var body: some View {
        self.content()
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(self.palette.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(self.palette.hairline, lineWidth: 1)
            )
    }
}


// MARK: - Pine-Soot Ink 53-Week Heatmap

private struct PineSootHeatmapGrid: View {
    
    let heatmap: YearlyHeatmapData
    let selectedDateKey: String
    let palette: StudioPalette
    let onSelectCell: (HeatmapDayCell) -> Void
    
    @State private var hoveredCell: HeatmapDayCell?
    
    private let cellSize: CGFloat = 11
    private let cellGap: CGFloat = 3
    private let leftAxisWidth: CGFloat = 20
    private let topLabelHeight: CGFloat = 16
    
    
    var body: some View {
        let weekCount = max(1, self.heatmap.weeks.count)
        let gridWidth = self.leftAxisWidth + CGFloat(weekCount) * self.cellSize + CGFloat(max(0, weekCount - 1)) * self.cellGap
        let gridHeight = self.topLabelHeight + 7 * self.cellSize + 6 * self.cellGap
        
        VStack(alignment: .leading, spacing: 6) {
            ScrollView(.horizontal, showsIndicators: false) {
                ZStack(alignment: .topLeading) {
                    Canvas { context, _ in
                        // Month labels along top edge
                        for label in self.heatmap.monthLabels {
                            let x = self.leftAxisWidth + CGFloat(label.weekIndex) * (self.cellSize + self.cellGap)
                            let text = Text("\(label.month)月")
                                .font(.system(size: 9.5))
                                .foregroundStyle(self.palette.tertiaryInk)
                            context.draw(text, at: CGPoint(x: x, y: 0), anchor: .topLeading)
                        }
                        
                        // Weekday guides (Mon, Wed, Fri)
                        let dayMarkers: [(Int, String)] = [(0, "一"), (2, "三"), (4, "五")]
                        for (row, title) in dayMarkers {
                            let y = self.topLabelHeight + CGFloat(row) * (self.cellSize + self.cellGap) + self.cellSize * 0.5
                            let text = Text(title)
                                .font(.system(size: 9.5))
                                .foregroundStyle(self.palette.tertiaryInk)
                            context.draw(text, at: CGPoint(x: 0, y: y), anchor: .leading)
                        }
                        
                        // Cells
                        for (weekIdx, week) in self.heatmap.weeks.enumerated() {
                            for (dayIdx, cell) in week.enumerated() where !cell.isOutOfYear {
                                let rect = CGRect(
                                    x: self.leftAxisWidth + CGFloat(weekIdx) * (self.cellSize + self.cellGap),
                                    y: self.topLabelHeight + CGFloat(dayIdx) * (self.cellSize + self.cellGap),
                                    width: self.cellSize,
                                    height: self.cellSize
                                )
                                let path = Path(roundedRect: rect, cornerRadius: 2.2, style: .continuous)
                                let fillColor: Color = cell.isFuture
                                    ? self.palette.heatmapColor(for: 0).opacity(0.35)
                                    : self.palette.heatmapColor(for: cell.level)
                                context.fill(path, with: .color(fillColor))
                                
                                if cell.dateKey == self.selectedDateKey {
                                    context.stroke(path, with: .color(self.palette.cinnabar), lineWidth: 1.5)
                                } else if self.hoveredCell?.dateKey == cell.dateKey {
                                    context.stroke(path, with: .color(self.palette.ink.opacity(0.65)), lineWidth: 1.0)
                                }
                            }
                        }
                    }
                    .frame(width: gridWidth, height: gridHeight)
                    .contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                            case .active(let location):
                                self.hoveredCell = self.cell(at: location)
                            case .ended:
                                self.hoveredCell = nil
                        }
                    }
                    .onTapGesture { location in
                        if let tapped = self.cell(at: location), !tapped.isFuture {
                            self.onSelectCell(tapped)
                        }
                    }
                }
            }
            
            if let hovered = self.hoveredCell {
                HStack(spacing: 10) {
                    Text(hovered.dateKey)
                        .font(.system(size: 10.5, weight: .semibold).monospacedDigit())
                    Text("手写 \(hovered.typedChars.formatted()) 字")
                        .font(.system(size: 10.5).monospacedDigit())
                        .foregroundStyle(self.palette.secondaryInk)
                    if hovered.aiCompletedChars > 0 {
                        Text("补全 \(hovered.aiCompletedChars.formatted()) 字")
                            .font(.system(size: 10.5).monospacedDigit())
                            .foregroundStyle(self.palette.secondaryInk)
                    }
                    if hovered.filesCreated > 0 {
                        Text("新建 \(hovered.filesCreated) 篇")
                            .font(.system(size: 10.5).monospacedDigit())
                            .foregroundStyle(self.palette.secondaryInk)
                    }
                }
                .transition(.opacity)
            }
        }
    }
    
    
    private func cell(at point: CGPoint) -> HeatmapDayCell? {
        
        let relX = point.x - self.leftAxisWidth
        let relY = point.y - self.topLabelHeight
        guard relX >= 0, relY >= 0 else { return nil }
        let step = self.cellSize + self.cellGap
        let weekIdx = Int(relX / step)
        let dayIdx = Int(relY / step)
        guard self.heatmap.weeks.indices.contains(weekIdx),
              self.heatmap.weeks[weekIdx].indices.contains(dayIdx)
        else { return nil }
        let candidate = self.heatmap.weeks[weekIdx][dayIdx]
        return candidate.isOutOfYear ? nil : candidate
    }
}


// MARK: - Manuscript Scale Ruler (今日手写刻度)

private struct ManuscriptScaleRuler: View {
    
    let todayChars: Int
    let averageChars: Int
    let recordChars: Int
    let palette: StudioPalette
    
    var body: some View {
        Canvas { context, size in
            let leftPad: CGFloat = 10
            let rightPad: CGFloat = 10
            let trackW = max(60, size.width - leftPad - rightPad)
            let maxDomain = max(2000, max(self.todayChars, max(self.averageChars, self.recordChars)) + 400)
            let baselineY: CGFloat = 38
            
            // Progress fill bar for today's typed chars
            let todayRatio = min(1.0, CGFloat(self.todayChars) / CGFloat(maxDomain))
            let barRect = CGRect(x: leftPad, y: baselineY - 12, width: trackW * todayRatio, height: 10)
            context.fill(
                Path(roundedRect: barRect, cornerRadius: 2),
                with: .color(self.palette.cinnabar.opacity(0.20))
            )
            
            // Main baseline hairline
            var baseline = Path()
            baseline.move(to: CGPoint(x: leftPad, y: baselineY))
            baseline.addLine(to: CGPoint(x: leftPad + trackW, y: baselineY))
            context.stroke(baseline, with: .color(self.palette.hairline), lineWidth: 1.2)
            
            // Paperback page ticks (every 500 chars = 1 page)
            let stepChars = maxDomain > 8000 ? 1000 : 500
            var cursor = 0
            while cursor <= maxDomain {
                let x = leftPad + trackW * CGFloat(cursor) / CGFloat(maxDomain)
                let isMajor = (cursor % 1000 == 0)
                var tick = Path()
                tick.move(to: CGPoint(x: x, y: baselineY))
                tick.addLine(to: CGPoint(x: x, y: baselineY + (isMajor ? 8 : 4.5)))
                context.stroke(tick, with: .color(isMajor ? self.palette.secondaryInk : self.palette.tertiaryInk), lineWidth: 1)
                
                if isMajor && cursor > 0 && cursor < maxDomain - 250 {
                    let pageLabel = "\(cursor / 500)页"
                    let txt = Text(pageLabel).font(.system(size: 9)).foregroundStyle(self.palette.tertiaryInk)
                    context.draw(txt, at: CGPoint(x: x, y: baselineY + 11), anchor: .top)
                }
                cursor += stepChars
            }
            
            // 14-day average dashed marker
            if self.averageChars > 0 {
                let avgX = leftPad + trackW * min(1.0, CGFloat(self.averageChars) / CGFloat(maxDomain))
                var avgLine = Path()
                avgLine.move(to: CGPoint(x: avgX, y: 12))
                avgLine.addLine(to: CGPoint(x: avgX, y: baselineY))
                context.stroke(avgLine, with: .color(self.palette.pineGreen), style: StrokeStyle(lineWidth: 1.2, dash: [3, 2]))
                let label = Text("均值").font(.system(size: 9, weight: .medium)).foregroundStyle(self.palette.pineGreen)
                context.draw(label, at: CGPoint(x: avgX, y: 1), anchor: .top)
            }
            
            // Record notch
            if self.recordChars > 0 {
                let recX = leftPad + trackW * min(1.0, CGFloat(self.recordChars) / CGFloat(maxDomain))
                var recLine = Path()
                recLine.move(to: CGPoint(x: recX, y: 14))
                recLine.addLine(to: CGPoint(x: recX, y: baselineY))
                context.stroke(recLine, with: .color(self.palette.secondaryInk.opacity(0.65)), lineWidth: 1)
                let label = Text("峰值").font(.system(size: 9)).foregroundStyle(self.palette.secondaryInk)
                context.draw(label, at: CGPoint(x: recX, y: 2), anchor: .topTrailing)
            }
            
            // Today cinnabar needle
            let todayX = leftPad + trackW * todayRatio
            var needle = Path()
            needle.move(to: CGPoint(x: todayX, y: 18))
            needle.addLine(to: CGPoint(x: todayX, y: baselineY + 2))
            context.stroke(needle, with: .color(self.palette.cinnabar), lineWidth: 2)
            let dot = Path(ellipseIn: CGRect(x: todayX - 3.5, y: 15, width: 7, height: 7))
            context.fill(dot, with: .color(self.palette.cinnabar))
        }
    }
}


// MARK: - 14-Day Typed Bar Chart

private struct FourteenDayTypedChart: View {
    
    let series: [DailyWritingStats]
    let averageChars: Int
    let palette: StudioPalette
    
    @State private var hoveredIdx: Int?
    
    var body: some View {
        let peak = max(1, max(self.series.map(\.typedChars).max() ?? 1, self.averageChars))
        
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { geo in
                let count = max(1, self.series.count)
                let gap: CGFloat = 6
                let barW = max(8, (geo.size.width - CGFloat(count - 1) * gap) / CGFloat(count))
                let plotH = max(40, geo.size.height - 20)
                
                ZStack(alignment: .bottomLeading) {
                    // Average hairline
                    if self.averageChars > 0 {
                        let avgY = 20 + plotH * (1.0 - CGFloat(self.averageChars) / CGFloat(peak))
                        Path { path in
                            path.move(to: CGPoint(x: 0, y: avgY))
                            path.addLine(to: CGPoint(x: geo.size.width, y: avgY))
                        }
                        .stroke(self.palette.pineGreen.opacity(0.65), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    }
                    
                    HStack(alignment: .bottom, spacing: gap) {
                        ForEach(Array(self.series.enumerated()), id: \.offset) { idx, stat in
                            let hRatio = CGFloat(stat.typedChars) / CGFloat(peak)
                            let barH = stat.typedChars > 0 ? max(4, plotH * hRatio) : 2
                            let isToday = (idx == self.series.count - 1)
                            
                            VStack(spacing: 4) {
                                Spacer(minLength: 0)
                                RoundedRectangle(cornerRadius: 3, style: .continuous)
                                    .fill(
                                        stat.typedChars == 0
                                            ? self.palette.subtle
                                            : (isToday ? self.palette.cinnabar : self.palette.pineGreen.opacity(0.8))
                                    )
                                    .frame(width: barW, height: barH)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                                            .strokeBorder(self.hoveredIdx == idx ? self.palette.ink : Color.clear, lineWidth: 1)
                                    )
                                
                                Text(String(stat.dateKey.suffix(2)))
                                    .font(.system(size: 9).monospacedDigit())
                                    .foregroundStyle(isToday ? self.palette.cinnabar : self.palette.tertiaryInk)
                            }
                            .frame(width: barW, height: geo.size.height)
                            .onHover { inside in
                                self.hoveredIdx = inside ? idx : (self.hoveredIdx == idx ? nil : self.hoveredIdx)
                            }
                        }
                    }
                }
            }
            
            if let idx = self.hoveredIdx, self.series.indices.contains(idx) {
                let s = self.series[idx]
                Text("\(s.dateKey)：手写 \(s.typedChars.formatted()) 字（约 \(String(format: "%.1f", Double(s.typedChars) / 500.0)) 页纸书）")
                    .font(.system(size: 10.5).monospacedDigit())
                    .foregroundStyle(self.palette.secondaryInk)
            }
        }
    }
}


// MARK: - 24-Hour Pulse Chart

private struct HourlyPulseChart: View {
    
    let hourlyValues: [Int]
    let palette: StudioPalette
    
    @State private var hoveredHour: Int?
    
    var body: some View {
        let peak = max(1, self.hourlyValues.max() ?? 1)
        let currentHour = Calendar.current.component(.hour, from: Date())
        
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { geo in
                let gap: CGFloat = 3
                let barW = max(4, (geo.size.width - CGFloat(23) * gap) / 24.0)
                let plotH = max(40, geo.size.height - 20)
                
                HStack(alignment: .bottom, spacing: gap) {
                    ForEach(0..<24, id: \.self) { hr in
                        let val = self.hourlyValues.indices.contains(hr) ? self.hourlyValues[hr] : 0
                        let barH = val > 0 ? max(4, plotH * CGFloat(val) / CGFloat(peak)) : 2
                        
                        VStack(spacing: 4) {
                            Spacer(minLength: 0)
                            RoundedRectangle(cornerRadius: 2, style: .continuous)
                                .fill(
                                    val == 0
                                        ? self.palette.subtle
                                        : (hr == currentHour ? self.palette.cinnabar : self.palette.pineGreen.opacity(0.78))
                                )
                                .frame(width: barW, height: barH)
                            
                            Text(hr % 6 == 0 ? "\(hr)" : "")
                                .font(.system(size: 9).monospacedDigit())
                                .foregroundStyle(self.palette.tertiaryInk)
                                .frame(height: 12)
                        }
                        .frame(width: barW, height: geo.size.height)
                        .onHover { inside in
                            self.hoveredHour = inside ? hr : (self.hoveredHour == hr ? nil : self.hoveredHour)
                        }
                    }
                }
            }
            
            if let hr = self.hoveredHour, self.hourlyValues.indices.contains(hr) {
                Text(String(format: "%02d:00 – %02d:59：活跃 %d 字", hr, hr, self.hourlyValues[hr]))
                    .font(.system(size: 10.5).monospacedDigit())
                    .foregroundStyle(self.palette.secondaryInk)
            }
        }
    }
}


// MARK: - 14-Day Dual-Engine Relay Chart

private struct DualEngineCompletionChart: View {
    
    let series: [DailyWritingStats]
    let palette: StudioPalette
    
    @State private var hoveredIdx: Int?
    
    var body: some View {
        let peak = max(1, self.series.map { max($0.aiCompletedChars, $0.localAcceptedChars) }.max() ?? 1)
        
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { geo in
                let count = max(1, self.series.count)
                let gap: CGFloat = 6
                let barW = max(8, (geo.size.width - CGFloat(count - 1) * gap) / CGFloat(count))
                let plotH = max(40, geo.size.height - 20)
                
                HStack(alignment: .bottom, spacing: gap) {
                    ForEach(Array(self.series.enumerated()), id: \.offset) { idx, stat in
                        let local = min(stat.localAcceptedChars, stat.aiCompletedChars)
                        let cloud = max(0, stat.aiCompletedChars - local)
                        let localH = local > 0 ? max(3, plotH * CGFloat(local) / CGFloat(peak)) : 0
                        let cloudH = cloud > 0 ? max(3, plotH * CGFloat(cloud) / CGFloat(peak)) : 0
                        
                        VStack(spacing: 4) {
                            Spacer(minLength: 0)
                            if local + cloud == 0 {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(self.palette.subtle)
                                    .frame(width: barW, height: 2)
                            } else {
                                VStack(spacing: 1) {
                                    if cloudH > 0 {
                                        RoundedRectangle(cornerRadius: 2)
                                            .fill(self.palette.cinnabar)
                                            .frame(width: barW, height: cloudH)
                                    }
                                    if localH > 0 {
                                        RoundedRectangle(cornerRadius: 2)
                                            .fill(self.palette.pineGreen)
                                            .frame(width: barW, height: localH)
                                    }
                                }
                            }
                            
                            Text(String(stat.dateKey.suffix(2)))
                                .font(.system(size: 9).monospacedDigit())
                                .foregroundStyle(self.palette.tertiaryInk)
                        }
                        .frame(width: barW, height: geo.size.height)
                        .onHover { inside in
                            self.hoveredIdx = inside ? idx : (self.hoveredIdx == idx ? nil : self.hoveredIdx)
                        }
                    }
                }
            }
            
            if let idx = self.hoveredIdx, self.series.indices.contains(idx) {
                let s = self.series[idx]
                let local = min(s.localAcceptedChars, s.aiCompletedChars)
                let cloud = max(0, s.aiCompletedChars - local)
                Text("\(s.dateKey)：共补全 \(s.aiCompletedChars.formatted()) 字（本地 \(local) 字 + 云端 \(cloud) 字）")
                    .font(.system(size: 10.5).monospacedDigit())
                    .foregroundStyle(self.palette.secondaryInk)
            }
        }
    }
}
