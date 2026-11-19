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


/// Swiss-grid analytics dashboard designed around high data-ink ratio and zero decorative clutter.
struct AnalyticsDashboardView: View {
    
    private enum AIRange: String, CaseIterable, Identifiable {
        
        case today = "今日"
        case thirtyDays = "30 天"
        
        var id: String { self.rawValue }
    }
    
    let isEmbeddedInSettings: Bool
    var onDismiss: (() -> Void)?
    
    @Environment(\.colorScheme) private var colorScheme
    
    @State private var analytics = AnalyticsManager.shared
    @State private var profileManager = UserProfileManager.shared
    @State private var hoveredCell: HeatmapDayCell?
    @State private var selectedYear: Int = Calendar.current.component(.year, from: Date())
    @State private var aiRange: AIRange = .thirtyDays
    @State private var heatmapContentWidth: CGFloat
    
    
    init(isEmbeddedInSettings: Bool, onDismiss: (() -> Void)? = nil) {
        
        self.isEmbeddedInSettings = isEmbeddedInSettings
        self.onDismiss = onDismiss
        self._heatmapContentWidth = State(initialValue: isEmbeddedInSettings ? 676 : 900)
    }
    
    
    private var outerPadding: CGFloat {
        
        self.isEmbeddedInSettings ? 16 : 24
    }
    
    
    private var gridSpacing: CGFloat {
        
        self.isEmbeddedInSettings ? 12 : 16
    }
    
    
    private var cardPadding: CGFloat {
        
        self.isEmbeddedInSettings ? 14 : 16
    }
    
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: self.gridSpacing) {
                self.topBar
                self.kpiRow
                self.yearlyHeatmapCard
                self.aiUsageCard
                self.dailySummaryCard
            }
            .padding(self.outerPadding)
            .frame(maxWidth: 1020, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            self.analytics.flushPendingStats()
            self.analytics.reloadFromDatabase()
            let currentYear = Calendar.current.component(.year, from: Date())
            if !self.analytics.availableHeatmapYears().contains(self.selectedYear) {
                self.selectedYear = currentYear
            }
        }
    }
    
    
    // MARK: Band 0 — Top Bar
    
    private var topBar: some View {
        let profile = self.profileManager.activeProfile
        let streak = self.analytics.currentWritingStreak
        
        return HStack(spacing: 10) {
            UserAvatarCircleView(profile: profile, size: 24)
            
            Text("数据看板")
                .font(.system(size: 15, weight: .semibold))
                .lineLimit(1)
            
            Text(profile.displayName)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            
            Spacer(minLength: 8)
            
            HStack(spacing: 5) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(streak > 0 ? Color.orange : Color.secondary)
                Text("连续 \(streak) 天")
                    .font(.system(size: 12, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(streak > 0 ? Color.primary : Color.secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(self.cardBackground, in: Capsule())
            .overlay(Capsule().strokeBorder(self.cardBorder, lineWidth: 1))
            
            if let onDismiss = self.onDismiss {
                Button {
                    onDismiss()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 10, weight: .semibold))
                        Text("返回")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(self.cardBackground, in: Capsule())
                    .overlay(Capsule().strokeBorder(self.cardBorder, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .pointerStyle(.link)
                .help("返回编辑器 (Esc)")
            }
        }
    }
    
    
    // MARK: Band 1 — 3-Column KPI Row (4 + 4 + 4)
    
    private var kpiRow: some View {
        let today = self.analytics.todayStats
        
        return HStack(alignment: .top, spacing: self.gridSpacing) {
            self.kpiCard(
                title: "今日输入",
                symbol: "character.cursor.ibeam",
                tint: .blue,
                value: Self.formattedInt(today.typedChars),
                unit: "字"
            )
            
            self.kpiCard(
                title: "AI 补全",
                symbol: "sparkles",
                tint: .indigo,
                value: Self.formattedInt(today.aiCompletedChars),
                unit: "字"
            )
            
            self.kpiCard(
                title: "AI 消耗",
                symbol: "bolt.fill",
                tint: .orange,
                value: AnalyticsManager.formatCompactTokenCount(today.totalTokens),
                unit: "Tokens"
            )
        }
        .fixedSize(horizontal: false, vertical: true)
    }
    
    
    private func kpiCard(
        title: String,
        symbol: String,
        tint: Color,
        value: String,
        unit: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                
                Spacer(minLength: 4)
                
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(tint)
            }
            
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(value)
                    .font(.system(size: self.isEmbeddedInSettings ? 24 : 26, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                
                Text(unit)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(self.cardPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(self.cardBackground, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(self.cardBorder, lineWidth: 1)
        )
    }
    
    
    // MARK: Band 2 — Yearly Activity Heatmap (12 Columns)
    
    private var yearlyHeatmapCard: some View {
        let years = self.analytics.availableHeatmapYears()
        let minYear = years.first ?? self.selectedYear
        let maxYear = years.last ?? self.selectedYear
        let heatmap = self.analytics.yearlyHeatmap(year: self.selectedYear)
        
        let weekdayColWidth: CGFloat = 14
        let weekdayGap: CGFloat = 8
        let weekCount = max(1, heatmap.weeks.count)
        let gridWidth = max(240, self.heatmapContentWidth - weekdayColWidth - weekdayGap)
        let cellGap: CGFloat = gridWidth >= 780 ? 3.0 : 2.0
        let cellSize = max(6.0, min(16.0, (gridWidth - CGFloat(weekCount - 1) * cellGap) / CGFloat(weekCount)))
        let pitch = cellSize + cellGap
        let cellRadius = max(1.5, min(3.0, cellSize * 0.22))
        
        return VStack(alignment: .leading, spacing: 12) {
            // Single-level header
            HStack(spacing: 10) {
                Text("年度热力图")
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                
                Spacer(minLength: 8)
                
                if let hovered = self.hoveredCell, !hovered.isOutOfYear, !hovered.isFuture {
                    Text("\(hovered.dateKey) · 输入 \(Self.formattedInt(hovered.typedChars)) 字 · 补全 \(Self.formattedInt(hovered.aiCompletedChars)) 字 · AI \(hovered.aiRequests) 次")
                        .font(.system(size: 11.5))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else {
                    Text("\(heatmap.activeDays) 活跃天")
                        .font(.system(size: 11.5))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                
                HStack(spacing: 4) {
                    Button {
                        self.hoveredCell = nil
                        self.selectedYear = max(minYear, self.selectedYear - 1)
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 10, weight: .semibold))
                            .frame(width: 18, height: 18)
                    }
                    .buttonStyle(.plain)
                    .disabled(self.selectedYear <= minYear)
                    .opacity(self.selectedYear <= minYear ? 0.35 : 1)
                    
                    Text(String(self.selectedYear))
                        .font(.system(size: 11.5, weight: .medium))
                        .monospacedDigit()
                        .frame(minWidth: 34)
                    
                    Button {
                        self.hoveredCell = nil
                        self.selectedYear = min(maxYear, self.selectedYear + 1)
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                            .frame(width: 18, height: 18)
                    }
                    .buttonStyle(.plain)
                    .disabled(self.selectedYear >= maxYear)
                    .opacity(self.selectedYear >= maxYear ? 0.35 : 1)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(self.subCardBackground, in: RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(self.subCardBorder, lineWidth: 0.5)
                )
            }
            
            // Full calendar-year grid (flush, zero horizontal scroll)
            VStack(alignment: .leading, spacing: 4) {
                // Month axis
                HStack(spacing: weekdayGap) {
                    Color.clear
                        .frame(width: weekdayColWidth, height: 13)
                    
                    ZStack(alignment: .topLeading) {
                        ForEach(heatmap.monthLabels) { label in
                            Text("\(label.month)月")
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                                .fixedSize()
                                .offset(x: CGFloat(label.weekIndex) * pitch)
                        }
                    }
                    .frame(width: gridWidth, height: 13, alignment: .topLeading)
                }
                
                // Weekday axis + 52–54 x 7 cells
                HStack(alignment: .top, spacing: weekdayGap) {
                    VStack(alignment: .trailing, spacing: cellGap) {
                        ForEach(0..<7, id: \.self) { row in
                            if let label = Self.weekdayAxisLabel(for: row) {
                                Text(label)
                                    .font(.system(size: 9.5))
                                    .foregroundStyle(.tertiary)
                                    .frame(width: weekdayColWidth, height: cellSize, alignment: .trailing)
                            } else {
                                Color.clear
                                    .frame(width: weekdayColWidth, height: cellSize)
                            }
                        }
                    }
                    
                    HStack(spacing: cellGap) {
                        ForEach(Array(heatmap.weeks.enumerated()), id: \.offset) { _, weekCells in
                            VStack(spacing: cellGap) {
                                ForEach(weekCells) { cell in
                                    if cell.isOutOfYear {
                                        Color.clear
                                            .frame(width: cellSize, height: cellSize)
                                    } else {
                                        let isHovered = self.hoveredCell?.id == cell.id && !cell.isFuture
                                        RoundedRectangle(cornerRadius: cellRadius)
                                            .fill(self.heatmapColor(for: cell))
                                            .frame(width: cellSize, height: cellSize)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: cellRadius)
                                                    .strokeBorder(
                                                        isHovered ? Color.primary.opacity(0.6) : Color.clear,
                                                        lineWidth: 1
                                                    )
                                            )
                                            .onHover { hovering in
                                                if hovering && !cell.isFuture {
                                                    self.hoveredCell = cell
                                                } else if self.hoveredCell?.id == cell.id {
                                                    self.hoveredCell = nil
                                                }
                                            }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.width
            } action: { newWidth in
                if newWidth > 100 && abs(newWidth - self.heatmapContentWidth) > 0.5 {
                    self.heatmapContentWidth = newWidth
                }
            }
            
            // Minimal intensity legend
            HStack {
                Spacer()
                HStack(spacing: 4) {
                    Text("少")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                    ForEach(0..<5, id: \.self) { level in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(self.heatmapLevelColor(level: level))
                            .frame(width: 9, height: 9)
                    }
                    Text("多")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(self.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(self.cardBackground, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(self.cardBorder, lineWidth: 1)
        )
    }
    
    
    // MARK: Band 3 — AI Usage Card with Model & Feature Sub-Cards (6 + 6)
    
    private var aiUsageCard: some View {
        let isToday = (self.aiRange == .today)
        let totals = self.analytics.aiUsageTotals(forTodayOnly: isToday, days: 30)
        let models = isToday ? self.analytics.todayModelDistribution() : self.analytics.modelDistribution(days: 30)
        let features = isToday ? self.analytics.todayFeatureDistribution() : self.analytics.featureDistribution(days: 30)
        
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Text("AI 使用情况")
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                
                Spacer(minLength: 8)
                
                Text("\(totals.requests) 次 · 入 \(AnalyticsManager.formatCompactTokenCount(totals.inputTokens)) · 出 \(AnalyticsManager.formatCompactTokenCount(totals.outputTokens))")
                    .font(.system(size: 11.5))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                
                HStack(spacing: 2) {
                    ForEach(AIRange.allCases) { range in
                        let selected = self.aiRange == range
                        Button {
                            self.aiRange = range
                        } label: {
                            Text(range.rawValue)
                                .font(.system(size: 11, weight: selected ? .semibold : .regular))
                                .foregroundStyle(selected ? Color.primary : Color.secondary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(
                                    selected ? self.cardBackground : Color.clear,
                                    in: RoundedRectangle(cornerRadius: 5)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(2)
                .background(self.subCardBackground, in: RoundedRectangle(cornerRadius: 7))
                .overlay(
                    RoundedRectangle(cornerRadius: 7)
                        .strokeBorder(self.subCardBorder, lineWidth: 0.5)
                )
            }
            
            HStack(alignment: .top, spacing: 12) {
                self.distributionSubCard(title: "模型分布") {
                    if models.isEmpty {
                        self.emptySubCardLabel
                    } else {
                        VStack(spacing: 8) {
                            ForEach(Array(models.prefix(5).enumerated()), id: \.element.id) { index, item in
                                self.distributionBarRow(
                                    label: item.model,
                                    metric: "\(Int(round(item.share * 100)))% · \(AnalyticsManager.formatCompactTokenCount(item.totalTokens))",
                                    share: item.share,
                                    color: Self.seriesColor(at: index),
                                    truncation: .middle
                                )
                            }
                        }
                    }
                }
                
                self.distributionSubCard(title: "功能分布") {
                    if features.isEmpty {
                        self.emptySubCardLabel
                    } else {
                        VStack(spacing: 8) {
                            ForEach(Array(features.prefix(5).enumerated()), id: \.element.id) { index, item in
                                self.distributionBarRow(
                                    label: item.displayName,
                                    metric: "\(Int(round(item.share * 100)))% · \(item.requests) 次",
                                    share: item.share,
                                    color: Self.seriesColor(at: index),
                                    truncation: .tail
                                )
                            }
                        }
                    }
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(self.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(self.cardBackground, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(self.cardBorder, lineWidth: 1)
        )
    }
    
    
    private func distributionSubCard<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            
            content()
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(self.subCardBackground, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(self.subCardBorder, lineWidth: 0.5)
        )
    }
    
    
    private func distributionBarRow(
        label: String,
        metric: String,
        share: Double,
        color: Color,
        truncation: Text.TruncationMode
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Circle()
                    .fill(color)
                    .frame(width: 6, height: 6)
                
                Text(label)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(truncation)
                
                Spacer(minLength: 6)
                
                Text(metric)
                    .font(.system(size: 11))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.primary.opacity(0.07))
                    Capsule()
                        .fill(color.opacity(0.85))
                        .frame(width: max(4, proxy.size.width * CGFloat(max(0, min(1, share)))))
                }
            }
            .frame(height: 4)
        }
    }
    
    
    private var emptySubCardLabel: some View {
        Text("暂无数据")
            .font(.system(size: 12))
            .foregroundStyle(.tertiary)
            .padding(.vertical, 6)
    }
    
    
    // MARK: Band 4 — Structured Today Summary (12 Columns)
    
    private var dailySummaryCard: some View {
        let digest = self.analytics.todayDigest
        let points = digest.map { AnalyticsManager.structuredSummaryPoints(from: $0.summary, maxPoints: 4) } ?? []
        let topics = digest?.topics ?? []
        let tomorrowFocus = digest?.tomorrowFocus.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text("今日总结")
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                
                if !topics.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(topics.prefix(self.isEmbeddedInSettings ? 2 : 4), id: \.self) { topic in
                            Text(topic)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(self.subCardBackground, in: Capsule())
                                .overlay(Capsule().strokeBorder(self.subCardBorder, lineWidth: 0.5))
                                .lineLimit(1)
                        }
                    }
                }
                
                Spacer(minLength: 8)
                
                if let error = self.analytics.digestErrorMessage, !error.isEmpty {
                    Text(error)
                        .font(.system(size: 11))
                        .foregroundStyle(.orange)
                        .lineLimit(1)
                }
                
                if self.analytics.isSummarizingDigest {
                    ProgressView()
                        .controlSize(.small)
                }
                
                Button(digest == nil ? "生成" : "刷新") {
                    Task {
                        await self.analytics.refreshDailyDigest(force: true)
                    }
                }
                .controlSize(.small)
                .disabled(self.analytics.isSummarizingDigest)
            }
            
            if digest != nil, !points.isEmpty || !tomorrowFocus.isEmpty {
                if !tomorrowFocus.isEmpty {
                    HStack(alignment: .top, spacing: 12) {
                        self.summaryBulletList(points: points)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        
                        self.tomorrowFocusBox(focus: tomorrowFocus)
                            .frame(width: self.isEmbeddedInSettings ? 210 : 260)
                            .frame(maxHeight: .infinity, alignment: .topLeading)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                } else {
                    self.summaryBulletList(points: points)
                }
            } else {
                Text("暂无今日总结")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
                    .padding(.vertical, 4)
            }
        }
        .padding(self.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(self.cardBackground, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(self.cardBorder, lineWidth: 1)
        )
    }
    
    
    private func summaryBulletList(points: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(points.enumerated()), id: \.offset) { _, point in
                HStack(alignment: .top, spacing: 8) {
                    Circle()
                        .fill(Color.accentColor.opacity(0.85))
                        .frame(width: 5, height: 5)
                        .padding(.top, 6)
                    
                    Text(point)
                        .font(.system(size: 12.5))
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
    
    
    private func tomorrowFocusBox(focus: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: "arrow.forward.circle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
                Text("明日优先")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(.orange)
                    .lineLimit(1)
            }
            
            Text(focus)
                .font(.system(size: 12.5))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(self.subCardBackground, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(self.subCardBorder, lineWidth: 0.5)
        )
    }
    
    
    // MARK: Visual Tokens & Helpers
    
    private var cardBackground: Color {
        
        if self.colorScheme == .dark {
            Color.white.opacity(0.045)
        } else {
            Color(nsColor: .controlBackgroundColor)
        }
    }
    
    
    private var cardBorder: Color {
        
        if self.colorScheme == .dark {
            Color.white.opacity(0.09)
        } else {
            Color.black.opacity(0.08)
        }
    }
    
    
    private var subCardBackground: Color {
        
        if self.colorScheme == .dark {
            Color.black.opacity(0.22)
        } else {
            Color.primary.opacity(0.03)
        }
    }
    
    
    private var subCardBorder: Color {
        
        if self.colorScheme == .dark {
            Color.white.opacity(0.06)
        } else {
            Color.black.opacity(0.06)
        }
    }
    
    
    private func heatmapColor(for cell: HeatmapDayCell) -> Color {
        
        if cell.isFuture {
            return (self.colorScheme == .dark) ? Color.white.opacity(0.025) : Color.black.opacity(0.025)
        }
        return self.heatmapLevelColor(level: cell.level)
    }
    
    
    private func heatmapLevelColor(level: Int) -> Color {
        
        if self.colorScheme == .dark {
            switch level {
                case 4: Color(red: 0.24, green: 0.82, blue: 0.44)
                case 3: Color(red: 0.17, green: 0.63, blue: 0.34)
                case 2: Color(red: 0.11, green: 0.44, blue: 0.24)
                case 1: Color(red: 0.08, green: 0.27, blue: 0.16)
                default: Color.white.opacity(0.06)
            }
        } else {
            switch level {
                case 4: Color(red: 0.13, green: 0.50, blue: 0.24)
                case 3: Color(red: 0.24, green: 0.68, blue: 0.36)
                case 2: Color(red: 0.49, green: 0.82, blue: 0.56)
                case 1: Color(red: 0.78, green: 0.93, blue: 0.81)
                default: Color.black.opacity(0.055)
            }
        }
    }
    
    
    private static func weekdayAxisLabel(for row: Int) -> String? {
        
        switch row {
            case 0: "一"
            case 2: "三"
            case 4: "五"
            default: nil
        }
    }
    
    
    private static func seriesColor(at index: Int) -> Color {
        
        let palette: [Color] = [.blue, .indigo, .teal, .orange, .pink]
        return palette[index % palette.count]
    }
    
    
    private static func formattedInt(_ value: Int) -> String {
        
        value.formatted(.number.grouping(.automatic))
    }
}
