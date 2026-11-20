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


/// Interactive Bento analytics dashboard powered by native Swift Charts and LeiBox-inspired micro-interactions.
struct AnalyticsDashboardView: View {
    
    private enum KPICardKind: String, CaseIterable, Identifiable {
        
        case typedChars
        case aiCompletion
        case aiConsumption
        
        var id: String { self.rawValue }
        
        var accentColor: Color {
            switch self {
                case .typedChars: Color(red: 0.23, green: 0.54, blue: 0.98)
                case .aiCompletion: Color(red: 0.46, green: 0.38, blue: 0.96)
                case .aiConsumption: Color(red: 0.95, green: 0.55, blue: 0.18)
            }
        }
    }
    
    private enum AIRange: String, CaseIterable, Identifiable {
        
        case today = "今日"
        case thirtyDays = "30 天"
        
        var id: String { self.rawValue }
    }
    
    let isEmbeddedInSettings: Bool
    var onDismiss: (() -> Void)?
    
    @Environment(\.colorScheme) private var colorScheme
    @Namespace private var rangeSwitchNamespace
    
    @State private var analytics = AnalyticsManager.shared
    @State private var profileManager = UserProfileManager.shared
    @State private var expandedKPI: KPICardKind? = nil
    @State private var hoveredKPI: KPICardKind? = nil
    @State private var hoveredCell: HeatmapDayCell? = nil
    @State private var selectedHeatmapCell: HeatmapDayCell? = nil
    @State private var selectedYear: Int = Calendar.current.component(.year, from: Date())
    @State private var aiRange: AIRange = .thirtyDays
    @State private var heatmapContentWidth: CGFloat
    @State private var hasAppeared = false
    
    
    init(isEmbeddedInSettings: Bool, onDismiss: (() -> Void)? = nil) {
        
        self.isEmbeddedInSettings = isEmbeddedInSettings
        self.onDismiss = onDismiss
        self._heatmapContentWidth = State(initialValue: isEmbeddedInSettings ? 676 : 920)
    }
    
    
    private var outerPadding: CGFloat {
        
        self.isEmbeddedInSettings ? 14 : 24
    }
    
    
    private var gridSpacing: CGFloat {
        
        self.isEmbeddedInSettings ? 12 : 16
    }
    
    
    private var cardPadding: CGFloat {
        
        self.isEmbeddedInSettings ? 13 : 16
    }
    
    
    var body: some View {
        ZStack {
            ScrollView {
                VStack(alignment: .leading, spacing: self.gridSpacing) {
                    self.topBar
                        .opacity(self.hasAppeared ? 1 : 0)
                        .offset(y: self.hasAppeared ? 0 : 6)
                        .animation(.spring(response: 0.42, dampingFraction: 0.86), value: self.hasAppeared)
                    
                    self.kpiSection
                        .opacity(self.hasAppeared ? 1 : 0)
                        .offset(y: self.hasAppeared ? 0 : 10)
                        .animation(.spring(response: 0.46, dampingFraction: 0.84).delay(0.04), value: self.hasAppeared)
                    
                    self.yearlyHeatmapCard
                        .opacity(self.hasAppeared ? 1 : 0)
                        .offset(y: self.hasAppeared ? 0 : 12)
                        .animation(.spring(response: 0.50, dampingFraction: 0.84).delay(0.08), value: self.hasAppeared)
                    
                    self.bottomBentoRow
                        .opacity(self.hasAppeared ? 1 : 0)
                        .offset(y: self.hasAppeared ? 0 : 14)
                        .animation(.spring(response: 0.54, dampingFraction: 0.84).delay(0.12), value: self.hasAppeared)
                }
                .padding(self.outerPadding)
                .frame(maxWidth: 1060, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .background(self.canvasBackground)
            .blur(radius: self.selectedHeatmapCell == nil ? 0 : 2.5)
            .animation(.easeOut(duration: 0.22), value: self.selectedHeatmapCell != nil)
            
            if let cell = self.selectedHeatmapCell {
                self.heatmapModalOverlay(for: cell)
                    .transition(.opacity)
                    .zIndex(50)
            }
        }
        .onAppear {
            self.analytics.flushPendingStats()
            self.analytics.reloadFromDatabase()
            let currentYear = Calendar.current.component(.year, from: Date())
            if !self.analytics.availableHeatmapYears().contains(self.selectedYear) {
                self.selectedYear = currentYear
            }
            if !self.hasAppeared {
                self.hasAppeared = true
            }
        }
        .onKeyPress(.escape) {
            if self.selectedHeatmapCell != nil {
                withAnimation(.spring(response: 0.30, dampingFraction: 0.84)) {
                    self.selectedHeatmapCell = nil
                }
                return .handled
            }
            if self.expandedKPI != nil {
                withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) {
                    self.expandedKPI = nil
                }
                return .handled
            }
            return .ignored
        }
    }
    
    
    // MARK: Band 0 — Top Bar
    
    private var topBar: some View {
        let profile = self.profileManager.activeProfile
        let streak = self.analytics.currentWritingStreak
        let yearly = self.analytics.yearlyHeatmap(year: self.selectedYear)
        
        return HStack(spacing: 10) {
            UserAvatarCircleView(profile: profile, size: 26)
                .shadow(color: Color(hexString: profile.avatarColorHex).opacity(0.28), radius: 6, y: 2)
            
            Text("数据看板")
                .font(.system(size: 15.5, weight: .semibold, design: .rounded))
                .lineLimit(1)
            
            Text(profile.displayName)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            
            LiveTelemetryPulseBadge()
            
            Spacer(minLength: 8)
            
            if !self.isEmbeddedInSettings {
                HStack(spacing: 5) {
                    Image(systemName: "text.word.spacing")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(Color(red: 0.23, green: 0.54, blue: 0.98))
                    Text("\(self.selectedYear) 累计 \(Self.formattedCompactChars(yearly.totalTypedChars))")
                        .font(.system(size: 11.5, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(self.cardBackground, in: Capsule())
                .overlay(Capsule().strokeBorder(self.cardBorder, lineWidth: 1))
            }
            
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
            .overlay(Capsule().strokeBorder(streak > 0 ? Color.orange.opacity(0.28) : self.cardBorder, lineWidth: 1))
            
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
    
    
    // MARK: Band 1 — 3-Column Expandable KPI Bento Row + Animated Sub-Card Drawer
    
    private var kpiSection: some View {
        let today = self.analytics.todayStats
        let series7 = self.analytics.dailySeries(days: 7)
        let avgTyped7 = max(0, series7.dropLast().reduce(0) { $0 + $1.typedChars } / max(1, series7.count - 1))
        let typedDeltaText = Self.deltaLabel(current: today.typedChars, baseline: avgTyped7)
        let completionRate = today.typedChars + today.aiCompletedChars > 0
            ? Int(round(Double(today.aiCompletedChars) * 100.0 / Double(today.typedChars + today.aiCompletedChars)))
            : 0
        
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: self.gridSpacing) {
                self.kpiCard(
                    kind: .typedChars,
                    title: "今日输入",
                    symbol: "character.cursor.ibeam",
                    value: Self.formattedInt(today.typedChars),
                    unit: "字",
                    badgeText: typedDeltaText,
                    sparkValues: series7.map { Double($0.typedChars) }
                )
                
                self.kpiCard(
                    kind: .aiCompletion,
                    title: "AI 补全",
                    symbol: "sparkles",
                    value: Self.formattedInt(today.aiCompletedChars),
                    unit: "字",
                    badgeText: completionRate > 0 ? "占比 \(completionRate)%" : "\(today.aiCompletionAccepts) 次采纳",
                    sparkValues: series7.map { Double($0.aiCompletedChars) }
                )
                
                self.kpiCard(
                    kind: .aiConsumption,
                    title: "AI 消耗",
                    symbol: "bolt.fill",
                    value: AnalyticsManager.formatCompactTokenCount(today.totalTokens),
                    unit: "Tokens",
                    badgeText: "\(today.aiRequests) 次调用",
                    sparkValues: series7.map { Double($0.totalTokens) }
                )
            }
            .fixedSize(horizontal: false, vertical: true)
            
            if let expanded = self.expandedKPI {
                self.expandedSubCardContainer(for: expanded)
                    .id(expanded.id)
                    .transition(
                        .asymmetric(
                            insertion: .opacity
                                .combined(with: .scale(scale: 0.975, anchor: .top))
                                .combined(with: .offset(y: -8)),
                            removal: .opacity
                                .combined(with: .scale(scale: 0.985, anchor: .top))
                        )
                    )
            }
        }
    }
    
    
    private func kpiCard(
        kind: KPICardKind,
        title: String,
        symbol: String,
        value: String,
        unit: String,
        badgeText: String,
        sparkValues: [Double]
    ) -> some View {
        let isExpanded = (self.expandedKPI == kind)
        let isHovered = (self.hoveredKPI == kind)
        let tint = kind.accentColor
        
        return Button {
            withAnimation(.spring(response: 0.40, dampingFraction: 0.78)) {
                self.expandedKPI = (self.expandedKPI == kind) ? nil : kind
            }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(tint.opacity(isExpanded || isHovered ? 0.18 : 0.11))
                            .frame(width: 22, height: 22)
                        Image(systemName: symbol)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(tint)
                    }
                    
                    Text(title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(isExpanded ? Color.primary : Color.secondary)
                        .lineLimit(1)
                    
                    Spacer(minLength: 4)
                    
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(isExpanded ? tint : Color.secondary.opacity(0.75))
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                        .animation(.spring(response: 0.34, dampingFraction: 0.76), value: isExpanded)
                }
                
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(value)
                        .font(.system(size: self.isEmbeddedInSettings ? 23 : 26, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                    
                    Text(unit)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    
                    Spacer(minLength: 2)
                }
                
                HStack(alignment: .bottom, spacing: 8) {
                    Text(badgeText)
                        .font(.system(size: 10.5, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(isExpanded ? tint : .secondary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2.5)
                        .background(tint.opacity(isExpanded ? 0.14 : 0.08), in: Capsule())
                        .lineLimit(1)
                    
                    Spacer(minLength: 2)
                    
                    MiniSparklineChart(values: sparkValues, tint: tint)
                        .frame(width: self.isEmbeddedInSettings ? 62 : 84, height: 24)
                }
            }
            .padding(self.cardPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(self.cardBackground)
                    .overlay(
                        LinearGradient(
                            colors: [
                                tint.opacity(isExpanded ? 0.09 : (isHovered ? 0.045 : 0.0)),
                                Color.clear,
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(
                        isExpanded ? tint.opacity(0.45) : (isHovered ? tint.opacity(0.24) : self.cardBorder),
                        lineWidth: isExpanded ? 1.25 : 1
                    )
            )
            .overlay {
                if isExpanded || isHovered {
                    BorderBeamOverlay(
                        cornerRadius: 14,
                        accent: tint,
                        speed: isExpanded ? 4.2 : 5.5,
                        opacity: isExpanded ? 0.72 : 0.42
                    )
                }
            }
            .shadow(
                color: isExpanded ? tint.opacity(self.colorScheme == .dark ? 0.16 : 0.10) : Color.black.opacity(self.colorScheme == .dark ? 0.12 : 0.03),
                radius: isExpanded ? 12 : 3,
                y: isExpanded ? 4 : 1
            )
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .pointerStyle(.link)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.18)) {
                if hovering {
                    self.hoveredKPI = kind
                } else if self.hoveredKPI == kind {
                    self.hoveredKPI = nil
                }
            }
        }
    }
    
    
    // MARK: Expanded KPI Detail Sub-Cards (Native Swift Charts, Zero Progress Bars)
    
    @ViewBuilder
    private func expandedSubCardContainer(for kind: KPICardKind) -> some View {
        let tint = kind.accentColor
        
        VStack(alignment: .leading, spacing: 14) {
            switch kind {
                case .typedChars:
                    self.typedCharsDetailSubCard(tint: tint)
                case .aiCompletion:
                    self.aiCompletionDetailSubCard(tint: tint)
                case .aiConsumption:
                    self.aiConsumptionDetailSubCard(tint: tint)
            }
        }
        .padding(self.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(self.cardBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(tint.opacity(0.32), lineWidth: 1)
        )
        .shadow(
            color: tint.opacity(self.colorScheme == .dark ? 0.12 : 0.06),
            radius: 14,
            y: 5
        )
    }
    
    
    private func typedCharsDetailSubCard(tint: Color) -> some View {
        let series14 = self.analytics.dailySeries(days: 14)
        let total14 = series14.reduce(0) { $0 + $1.typedChars }
        let activeCount14 = max(1, series14.filter { $0.typedChars > 0 }.count)
        let avg14 = total14 / activeCount14
        let peakDay = series14.max(by: { $0.typedChars < $1.typedChars })
        let today = self.analytics.todayStats
        let touchedDocs = self.analytics.todayTouchedDocuments()
        
        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Label("输入趋势与产出拆解", systemImage: "chart.bar.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(tint)
                Spacer()
                Text("近 14 天 · 累计 \(Self.formattedInt(total14)) 字 · 日均 \(Self.formattedInt(avg14)) 字")
                    .font(.system(size: 11.5, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                self.closeSubCardButton
            }
            
            HStack(alignment: .top, spacing: 14) {
                // Left: 14-day Swift Charts BarMark + average RuleMark
                VStack(alignment: .leading, spacing: 8) {
                    Text("近 14 天每日手打字数")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(.secondary)
                    
                    Chart {
                        ForEach(series14) { item in
                            BarMark(
                                x: .value("日期", Self.shortMonthDay(item.dateKey)),
                                y: .value("字数", item.typedChars)
                            )
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [
                                        item.dateKey == today.dateKey ? tint : tint.opacity(0.76),
                                        tint.opacity(0.32),
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .cornerRadius(4)
                        }
                        if avg14 > 0 {
                            RuleMark(y: .value("日均", avg14))
                                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                                .foregroundStyle(tint.opacity(0.55))
                                .annotation(position: .top, alignment: .trailing) {
                                    Text("均值 \(Self.formattedInt(avg14))")
                                        .font(.system(size: 9.5, weight: .medium))
                                        .monospacedDigit()
                                        .foregroundStyle(.secondary)
                                }
                        }
                    }
                    .chartXAxis {
                        AxisMarks(values: .automatic(desiredCount: 7)) { _ in
                            AxisValueLabel()
                                .font(.system(size: 9.5))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .chartYAxis {
                        AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { _ in
                            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 2]))
                                .foregroundStyle(Color.primary.opacity(0.08))
                            AxisValueLabel()
                                .font(.system(size: 9.5))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .frame(height: 148)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(self.subCardBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(self.subCardBorder, lineWidth: 0.5))
                
                // Right: Key Telemetry Tiles + Today's Touched Documents
                VStack(alignment: .leading, spacing: 10) {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                        self.metricTile(title: "新建文档", value: "\(today.filesCreated)", unit: "篇", tint: tint)
                        self.metricTile(title: "今日保存", value: "\(today.documentsSaved)", unit: "次", tint: tint)
                        self.metricTile(title: "14日峰值", value: Self.formattedInt(peakDay?.typedChars ?? 0), unit: "字", tint: tint)
                        self.metricTile(title: "活跃天数", value: "\(activeCount14)/14", unit: "天", tint: tint)
                    }
                    
                    if !touchedDocs.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("今日编辑文档")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)
                            StackedMetadataPills(items: touchedDocs.prefix(4).map(\.title), tint: tint)
                        }
                    }
                }
                .frame(width: self.isEmbeddedInSettings ? 228 : 290)
            }
        }
    }
    
    
    private func aiCompletionDetailSubCard(tint: Color) -> some View {
        let today = self.analytics.todayStats
        let series7 = self.analytics.dailySeries(days: 7)
        let totalAccepts7 = series7.reduce(0) { $0 + $1.aiCompletionAccepts }
        let totalLocal7 = series7.reduce(0) { $0 + $1.localHits }
        let totalAIChars7 = series7.reduce(0) { $0 + $1.aiCompletedChars }
        let totalTyped7 = series7.reduce(0) { $0 + $1.typedChars }
        let avgCharsPerAccept = totalAccepts7 > 0 ? totalAIChars7 / totalAccepts7 : 0
        let localHitShare = (totalAccepts7 + totalLocal7) > 0
            ? Int(round(Double(totalLocal7) * 100.0 / Double(totalAccepts7 + totalLocal7)))
            : 0
        
        let shareSlices: [(label: String, value: Int, color: Color)] = [
            ("手动输入", max(0, totalTyped7), Color(red: 0.23, green: 0.54, blue: 0.98)),
            ("AI 补全", max(0, totalAIChars7), tint),
        ].filter { $0.value > 0 }
        let aiRatioPct = (totalTyped7 + totalAIChars7) > 0
            ? Int(round(Double(totalAIChars7) * 100.0 / Double(totalTyped7 + totalAIChars7)))
            : 0
        
        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Label("AI 补全效率与协同占比", systemImage: "sparkles")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(tint)
                Spacer()
                Text("近 7 天采纳 \(totalAccepts7) 次 · 补全 \(Self.formattedInt(totalAIChars7)) 字 · 本地 0 成本命中 \(totalLocal7) 次")
                    .font(.system(size: 11.5, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                self.closeSubCardButton
            }
            
            HStack(alignment: .top, spacing: 12) {
                // Left: Donut chart (Manual vs AI Collaboration)
                VStack(alignment: .leading, spacing: 8) {
                    Text("近 7 天人机协同占比")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(.secondary)
                    
                    HStack(spacing: 14) {
                        ZStack {
                            if shareSlices.isEmpty {
                                Circle()
                                    .stroke(Color.primary.opacity(0.08), lineWidth: 16)
                                    .frame(width: 112, height: 112)
                            } else {
                                Chart(shareSlices, id: \.label) { slice in
                                    SectorMark(
                                        angle: .value("字数", slice.value),
                                        innerRadius: .ratio(0.64),
                                        angularInset: 2.0
                                    )
                                    .cornerRadius(4)
                                    .foregroundStyle(slice.color)
                                }
                                .chartLegend(.hidden)
                                .frame(width: 116, height: 116)
                            }
                            
                            VStack(spacing: 1) {
                                Text("\(aiRatioPct)%")
                                    .font(.system(size: 17, weight: .bold, design: .rounded))
                                    .monospacedDigit()
                                Text("AI 贡献")
                                    .font(.system(size: 9.5, weight: .medium))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        
                        VStack(alignment: .leading, spacing: 10) {
                            self.donutLegendRow(
                                color: tint,
                                title: "AI 补全",
                                detail: "\(Self.formattedInt(totalAIChars7)) 字"
                            )
                            self.donutLegendRow(
                                color: Color(red: 0.23, green: 0.54, blue: 0.98),
                                title: "手动输入",
                                detail: "\(Self.formattedInt(totalTyped7)) 字"
                            )
                            self.donutLegendRow(
                                color: .teal,
                                title: "本地命中率",
                                detail: "\(localHitShare)% (0 Token)"
                            )
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(self.subCardBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(self.subCardBorder, lineWidth: 0.5))
                
                // Right: 7-day completion trend Area/Line chart + compact metrics
                VStack(alignment: .leading, spacing: 10) {
                    Text("近 7 天补全字数走势")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(.secondary)
                    
                    Chart(series7) { item in
                        AreaMark(
                            x: .value("日期", Self.shortMonthDay(item.dateKey)),
                            y: .value("补全", item.aiCompletedChars)
                        )
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [tint.opacity(0.28), tint.opacity(0.02)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        
                        LineMark(
                            x: .value("日期", Self.shortMonthDay(item.dateKey)),
                            y: .value("补全", item.aiCompletedChars)
                        )
                        .interpolationMethod(.catmullRom)
                        .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                        .foregroundStyle(tint)
                        
                        PointMark(
                            x: .value("日期", Self.shortMonthDay(item.dateKey)),
                            y: .value("补全", item.aiCompletedChars)
                        )
                        .symbolSize(24)
                        .foregroundStyle(tint)
                    }
                    .chartXAxis {
                        AxisMarks { _ in
                            AxisValueLabel()
                                .font(.system(size: 9.5))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .chartYAxis(.hidden)
                    .frame(height: 82)
                    
                    HStack(spacing: 8) {
                        self.metricTile(title: "今日采纳", value: "\(today.aiCompletionAccepts)", unit: "次", tint: tint)
                        self.metricTile(title: "单次均长", value: "\(avgCharsPerAccept)", unit: "字", tint: tint)
                        self.metricTile(title: "今日省流", value: "\(today.localHits)", unit: "次", tint: .teal)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(self.subCardBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(self.subCardBorder, lineWidth: 0.5))
            }
        }
    }
    
    
    /// Replaces the removed standalone AI Usage card — uses native Swift Charts Donut & Grouped Bars (zero progress bars).
    private func aiConsumptionDetailSubCard(tint: Color) -> some View {
        let isToday = (self.aiRange == .today)
        let totals = self.analytics.aiUsageTotals(forTodayOnly: isToday, days: 30)
        let models = isToday ? self.analytics.todayModelDistribution() : self.analytics.modelDistribution(days: 30)
        let features = isToday ? self.analytics.todayFeatureDistribution() : self.analytics.featureDistribution(days: 30)
        let avgLatency = self.analytics.averageLatencyMs(forTodayOnly: isToday, days: 30)
        let series7 = self.analytics.dailySeries(days: 7)
        
        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Label("AI 消耗与分布透视", systemImage: "bolt.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(tint)
                
                Spacer(minLength: 6)
                
                Text("\(totals.requests) 次 · 入 \(AnalyticsManager.formatCompactTokenCount(totals.inputTokens)) · 出 \(AnalyticsManager.formatCompactTokenCount(totals.outputTokens))\(avgLatency > 0 ? " · \(avgLatency)ms" : "")")
                    .font(.system(size: 11.5, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                
                // LeiBox glass-tab-menu style sliding capsule switcher
                HStack(spacing: 2) {
                    ForEach(AIRange.allCases) { range in
                        let selected = (self.aiRange == range)
                        Button {
                            withAnimation(.spring(response: 0.30, dampingFraction: 0.80)) {
                                self.aiRange = range
                            }
                        } label: {
                            Text(range.rawValue)
                                .font(.system(size: 11, weight: selected ? .semibold : .regular))
                                .foregroundStyle(selected ? Color.primary : Color.secondary)
                                .padding(.horizontal, 9)
                                .padding(.vertical, 3)
                                .background {
                                    if selected {
                                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                                            .fill(self.cardBackground)
                                            .matchedGeometryEffect(id: "aiRangePill", in: self.rangeSwitchNamespace)
                                            .shadow(color: Color.black.opacity(0.08), radius: 2, y: 1)
                                    }
                                }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(2)
                .background(self.subCardBackground, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(self.subCardBorder, lineWidth: 0.5))
                
                self.closeSubCardButton
            }
            
            // Dual Swift Charts Donut Cards (Model & Feature Distribution — ZERO progress bars)
            HStack(alignment: .top, spacing: 12) {
                self.donutDistributionCard(
                    title: "模型分布",
                    centerPrimary: AnalyticsManager.formatCompactTokenCount(totals.totalTokens),
                    centerSecondary: "总 Tokens",
                    items: models.prefix(5).enumerated().map { idx, item in
                        DonutItem(
                            id: item.id,
                            label: item.model,
                            value: max(1, item.totalTokens),
                            shareText: "\(Int(round(item.share * 100)))%",
                            metricText: AnalyticsManager.formatCompactTokenCount(item.totalTokens),
                            color: Self.seriesColor(at: idx)
                        )
                    }
                )
                
                self.donutDistributionCard(
                    title: "功能分布",
                    centerPrimary: "\(totals.requests)",
                    centerSecondary: "总调用",
                    items: features.prefix(5).enumerated().map { idx, item in
                        DonutItem(
                            id: item.id,
                            label: item.displayName,
                            value: max(1, item.requests),
                            shareText: "\(Int(round(item.share * 100)))%",
                            metricText: "\(item.requests) 次",
                            color: Self.seriesColor(at: idx)
                        )
                    }
                )
            }
            .fixedSize(horizontal: false, vertical: true)
            
            // 7-day Input vs Output Token Stacked Bar Chart
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("近 7 天输入 / 输出 Token 对比")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                    HStack(spacing: 10) {
                        self.legendDot(color: Color(red: 0.95, green: 0.55, blue: 0.18), label: "输入 Tokens")
                        self.legendDot(color: Color(red: 0.46, green: 0.38, blue: 0.96), label: "输出 Tokens")
                    }
                }
                
                Chart {
                    ForEach(series7) { item in
                        BarMark(
                            x: .value("日期", Self.shortMonthDay(item.dateKey)),
                            y: .value("Tokens", item.inputTokens)
                        )
                        .foregroundStyle(Color(red: 0.95, green: 0.55, blue: 0.18).opacity(0.85))
                        .cornerRadius(3)
                        
                        BarMark(
                            x: .value("日期", Self.shortMonthDay(item.dateKey)),
                            y: .value("Tokens", item.outputTokens)
                        )
                        .foregroundStyle(Color(red: 0.46, green: 0.38, blue: 0.96).opacity(0.88))
                        .cornerRadius(3)
                    }
                }
                .chartXAxis {
                    AxisMarks { _ in
                        AxisValueLabel()
                            .font(.system(size: 9.5))
                            .foregroundStyle(.tertiary)
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { _ in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 2]))
                            .foregroundStyle(Color.primary.opacity(0.08))
                        AxisValueLabel()
                            .font(.system(size: 9.5))
                            .foregroundStyle(.tertiary)
                    }
                }
                .frame(height: 92)
            }
            .padding(12)
            .background(self.subCardBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(self.subCardBorder, lineWidth: 0.5))
        }
    }
    
    
    private struct DonutItem: Identifiable {
        let id: String
        let label: String
        let value: Int
        let shareText: String
        let metricText: String
        let color: Color
    }
    
    
    private func donutDistributionCard(
        title: String,
        centerPrimary: String,
        centerSecondary: String,
        items: [DonutItem]
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
            
            if items.isEmpty {
                Text("暂无数据")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, minHeight: 96, alignment: .center)
            } else {
                HStack(alignment: .center, spacing: 14) {
                    ZStack {
                        Chart(items) { item in
                            SectorMark(
                                angle: .value("占比", item.value),
                                innerRadius: .ratio(0.62),
                                angularInset: 2.0
                            )
                            .cornerRadius(4)
                            .foregroundStyle(item.color)
                        }
                        .chartLegend(.hidden)
                        .frame(width: self.isEmbeddedInSettings ? 96 : 112, height: self.isEmbeddedInSettings ? 96 : 112)
                        
                        VStack(spacing: 1) {
                            Text(centerPrimary)
                                .font(.system(size: self.isEmbeddedInSettings ? 13 : 15, weight: .bold, design: .rounded))
                                .monospacedDigit()
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                            Text(centerSecondary)
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: 64)
                    }
                    
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(items) { item in
                            HStack(spacing: 6) {
                                RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                                    .fill(item.color)
                                    .frame(width: 8, height: 8)
                                Text(item.label)
                                    .font(.system(size: 11.5, weight: .medium))
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Spacer(minLength: 4)
                                Text(item.shareText)
                                    .font(.system(size: 10.5, weight: .semibold))
                                    .monospacedDigit()
                                    .foregroundStyle(item.color)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1.5)
                                    .background(item.color.opacity(0.12), in: Capsule())
                                Text(item.metricText)
                                    .font(.system(size: 10.5))
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(self.subCardBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(self.subCardBorder, lineWidth: 0.5))
    }
    
    
    private var closeSubCardButton: some View {
        Button {
            withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) {
                self.expandedKPI = nil
            }
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 22, height: 22)
                .background(self.subCardBackground, in: Circle())
                .overlay(Circle().strokeBorder(self.subCardBorder, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .pointerStyle(.link)
        .help("收起详情")
    }
    
    
    private func metricTile(title: String, value: String, unit: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                Text(unit)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(self.cardBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(tint.opacity(0.14), lineWidth: 0.75)
        )
    }
    
    
    private func donutLegendRow(color: Color, title: String, detail: String) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                Text(detail)
                    .font(.system(size: 12, weight: .semibold))
                    .monospacedDigit()
            }
        }
    }
    
    
    private func legendDot(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
    }
    
    
    // MARK: Band 2 — Yearly Activity Heatmap (Interactive Click -> Center Modal)
    
    private var yearlyHeatmapCard: some View {
        let years = self.analytics.availableHeatmapYears()
        let minYear = years.first ?? self.selectedYear
        let maxYear = years.last ?? self.selectedYear
        let heatmap = self.analytics.yearlyHeatmap(year: self.selectedYear)
        let longestStreak = self.analytics.longestWritingStreak(year: self.selectedYear)
        let avgActiveDayChars = heatmap.activeDays > 0 ? (heatmap.totalTypedChars / heatmap.activeDays) : 0
        
        let weekdayColWidth: CGFloat = 14
        let weekdayGap: CGFloat = 8
        let weekCount = max(1, heatmap.weeks.count)
        let gridWidth = max(240, self.heatmapContentWidth - weekdayColWidth - weekdayGap)
        let cellGap: CGFloat = gridWidth >= 780 ? 3.0 : 2.0
        let cellSize = max(6.0, min(16.0, (gridWidth - CGFloat(weekCount - 1) * cellGap) / CGFloat(weekCount)))
        let pitch = cellSize + cellGap
        let cellRadius = max(1.8, min(3.2, cellSize * 0.24))
        
        return VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack(spacing: 10) {
                Text("年度热力图")
                    .font(.system(size: 13.5, weight: .semibold))
                    .lineLimit(1)
                
                Spacer(minLength: 8)
                
                if let hovered = self.hoveredCell, !hovered.isOutOfYear, !hovered.isFuture {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(self.heatmapLevelColor(level: hovered.level))
                            .frame(width: 7, height: 7)
                        Text("\(hovered.dateKey) · 输入 \(Self.formattedInt(hovered.typedChars)) 字 · 补全 \(Self.formattedInt(hovered.aiCompletedChars)) 字 · AI \(hovered.aiRequests) 次")
                            .font(.system(size: 11.5, weight: .medium))
                            .monospacedDigit()
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 3)
                    .background(self.subCardBackground, in: Capsule())
                    .overlay(Capsule().strokeBorder(self.subCardBorder, lineWidth: 0.5))
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
                } else {
                    Text("\(heatmap.activeDays) 活跃天 · 最长连续 \(longestStreak) 天 · 活跃日均 \(Self.formattedInt(avgActiveDayChars)) 字")
                        .font(.system(size: 11.5))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                
                HStack(spacing: 4) {
                    Button {
                        withAnimation(.easeOut(duration: 0.2)) {
                            self.hoveredCell = nil
                            self.selectedYear = max(minYear, self.selectedYear - 1)
                        }
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 10, weight: .semibold))
                            .frame(width: 18, height: 18)
                    }
                    .buttonStyle(.plain)
                    .disabled(self.selectedYear <= minYear)
                    .opacity(self.selectedYear <= minYear ? 0.35 : 1)
                    
                    Text(String(self.selectedYear))
                        .font(.system(size: 11.5, weight: .semibold))
                        .monospacedDigit()
                        .frame(minWidth: 34)
                    
                    Button {
                        withAnimation(.easeOut(duration: 0.2)) {
                            self.hoveredCell = nil
                            self.selectedYear = min(maxYear, self.selectedYear + 1)
                        }
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
                .background(self.subCardBackground, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(self.subCardBorder, lineWidth: 0.5)
                )
            }
            
            // Full calendar-year grid
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
                                        let isSelected = self.selectedHeatmapCell?.id == cell.id
                                        RoundedRectangle(cornerRadius: cellRadius, style: .continuous)
                                            .fill(self.heatmapColor(for: cell))
                                            .frame(width: cellSize, height: cellSize)
                                            .scaleEffect(isHovered || isSelected ? 1.24 : 1.0)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: cellRadius, style: .continuous)
                                                    .strokeBorder(
                                                        isSelected ? Color.accentColor : (isHovered ? Color.primary.opacity(0.65) : Color.clear),
                                                        lineWidth: isSelected ? 1.5 : 1
                                                    )
                                            )
                                            .zIndex(isHovered || isSelected ? 2 : 0)
                                            .animation(.spring(response: 0.22, dampingFraction: 0.72), value: isHovered)
                                            .onHover { hovering in
                                                if hovering && !cell.isFuture {
                                                    self.hoveredCell = cell
                                                } else if self.hoveredCell?.id == cell.id {
                                                    self.hoveredCell = nil
                                                }
                                            }
                                            .onTapGesture {
                                                guard !cell.isFuture else { return }
                                                withAnimation(.spring(response: 0.36, dampingFraction: 0.80)) {
                                                    self.selectedHeatmapCell = cell
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
            
            // Footer: clickable hint + intensity legend
            HStack {
                Text("点击任意日期方块查看当日详情")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.tertiary)
                Spacer()
                HStack(spacing: 4) {
                    Text("少")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                    ForEach(0..<5, id: \.self) { level in
                        RoundedRectangle(cornerRadius: 2.2, style: .continuous)
                            .fill(self.heatmapLevelColor(level: level))
                            .frame(width: 9.5, height: 9.5)
                    }
                    Text("多")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(self.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(self.cardBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(self.cardBorder, lineWidth: 1)
        )
    }
    
    
    // MARK: Band 3 — Dual-Column Bento Insights Row (Daily Digest + Writing Rhythm & Tasks)
    
    private var bottomBentoRow: some View {
        HStack(alignment: .top, spacing: self.gridSpacing) {
            self.dailySummaryCard
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            
            self.writingRhythmAndTasksCard
                .frame(width: self.isEmbeddedInSettings ? 276 : 368)
                .frame(maxHeight: .infinity, alignment: .topLeading)
        }
        .fixedSize(horizontal: false, vertical: true)
    }
    
    
    private var dailySummaryCard: some View {
        let digest = self.analytics.todayDigest
        let points = digest.map { AnalyticsManager.structuredSummaryPoints(from: $0.summary, maxPoints: 4) } ?? []
        let topics = digest?.topics ?? []
        let tomorrowFocus = digest?.tomorrowFocus.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text("今日总结")
                    .font(.system(size: 13.5, weight: .semibold))
                    .lineLimit(1)
                
                if !topics.isEmpty {
                    StackedMetadataPills(
                        items: Array(topics.prefix(self.isEmbeddedInSettings ? 2 : 4)),
                        tint: Color(red: 0.46, green: 0.38, blue: 0.96)
                    )
                }
                
                Spacer(minLength: 8)
                
                if let error = self.analytics.digestErrorMessage, !error.isEmpty {
                    Text(error)
                        .font(.system(size: 11))
                        .foregroundStyle(.orange)
                        .lineLimit(1)
                }
                
                if self.analytics.isSummarizingDigest {
                    MiniThinkingMatrixView(tint: Color(red: 0.46, green: 0.38, blue: 0.96))
                }
                
                Button {
                    Task {
                        await self.analytics.refreshDailyDigest(force: true)
                    }
                } label: {
                    Text(digest == nil ? "生成" : "刷新")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(Color.accentColor)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 3.5)
                        .background(Color.accentColor.opacity(0.11), in: Capsule())
                }
                .buttonStyle(.plain)
                .pointerStyle(.link)
                .disabled(self.analytics.isSummarizingDigest)
            }
            
            if digest != nil, !points.isEmpty || !tomorrowFocus.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    if !points.isEmpty {
                        self.summaryBulletList(points: points)
                    }
                    
                    if !tomorrowFocus.isEmpty {
                        self.tomorrowFocusBox(focus: tomorrowFocus)
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text("暂无今日总结")
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text("点击右上角「生成」即可提炼今日文档脉络与明日聚焦项。")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.tertiary)
                }
                .padding(.vertical, 8)
            }
        }
        .padding(self.cardPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(self.cardBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(self.cardBorder, lineWidth: 1)
        )
    }
    
    
    /// Right Bento Card: Weekly Writing Rhythm Swift Chart (`BarMark`) + Quick Reminders / Detected TODOs.
    private var writingRhythmAndTasksCard: some View {
        let rhythm = self.analytics.weekdayActivityDistribution(days: 90)
        let peakWeekday = rhythm.max(by: { $0.averageChars < $1.averageChars })
        let pendingReminders = Array((self.analytics.todayReminders + self.analytics.tomorrowReminders).prefix(3))
        let detectedTodos = pendingReminders.isEmpty ? self.analytics.detectedNoteTodos(limit: 2) : []
        
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Text("星期写作节奏")
                    .font(.system(size: 13.5, weight: .semibold))
                    .lineLimit(1)
                Spacer()
                if let peak = peakWeekday, peak.averageChars > 0 {
                    Text("高峰 \(peak.label)")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(Color(red: 0.20, green: 0.72, blue: 0.56))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2.5)
                        .background(Color(red: 0.20, green: 0.72, blue: 0.56).opacity(0.13), in: Capsule())
                }
            }
            
            Chart(rhythm) { point in
                let isPeak = (peakWeekday?.weekdayIndex == point.weekdayIndex && point.averageChars > 0)
                BarMark(
                    x: .value("星期", point.label),
                    y: .value("日均字数", point.averageChars)
                )
                .foregroundStyle(
                    isPeak
                        ? Color(red: 0.20, green: 0.72, blue: 0.56)
                        : Color(red: 0.23, green: 0.54, blue: 0.98).opacity(0.62)
                )
                .cornerRadius(4)
            }
            .chartXAxis {
                AxisMarks { _ in
                    AxisValueLabel()
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            .chartYAxis(.hidden)
            .frame(height: 88)
            
            if !pendingReminders.isEmpty {
                Divider().opacity(0.45)
                VStack(alignment: .leading, spacing: 6) {
                    Text("近期提醒")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                    
                    ForEach(pendingReminders) { reminder in
                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.76)) {
                                self.analytics.toggleReminderCompleted(id: reminder.id)
                            }
                        } label: {
                            HStack(spacing: 7) {
                                Image(systemName: reminder.isCompleted ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 12))
                                    .foregroundStyle(reminder.priority == .high ? .orange : .secondary)
                                Text(reminder.title)
                                    .font(.system(size: 11.5))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                Spacer(minLength: 4)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            } else if !detectedTodos.isEmpty {
                Divider().opacity(0.45)
                VStack(alignment: .leading, spacing: 6) {
                    Text("笔记待办发现")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                    
                    ForEach(detectedTodos) { todo in
                        HStack(spacing: 6) {
                            Circle()
                                .fill(Color.orange.opacity(0.8))
                                .frame(width: 5, height: 5)
                            Text(todo.text)
                                .font(.system(size: 11.5))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            Spacer(minLength: 4)
                            Button("加入提醒") {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.78)) {
                                    _ = self.analytics.addReminder(
                                        title: todo.text,
                                        dueDate: todo.suggestedForTomorrow ? AnalyticsManager.tomorrowDate() : Date()
                                    )
                                }
                            }
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Color.accentColor)
                            .buttonStyle(.plain)
                            .pointerStyle(.link)
                        }
                    }
                }
            }
        }
        .padding(self.cardPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(self.cardBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(self.cardBorder, lineWidth: 1)
        )
    }
    
    
    private func summaryBulletList(points: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(points.enumerated()), id: \.offset) { _, point in
                HStack(alignment: .top, spacing: 8) {
                    Circle()
                        .fill(Color.accentColor.opacity(0.85))
                        .frame(width: 5.5, height: 5.5)
                        .padding(.top, 5.5)
                    
                    Text(point)
                        .font(.system(size: 12.5))
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
    
    
    private func tomorrowFocusBox(focus: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
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
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(self.colorScheme == .dark ? 0.08 : 0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.orange.opacity(0.22), lineWidth: 0.75)
        )
    }
    
    
    // MARK: Center Modal Popup for Clicked Heatmap Day (LeiBox transfer-glow + share-invite style)
    
    private func heatmapModalOverlay(for cell: HeatmapDayCell) -> some View {
        let detail = self.analytics.dayDetail(for: cell)
        let prevCell = self.analytics.adjacentHeatmapCell(from: cell.dateKey, deltaDays: -1, in: self.selectedYear)
        let nextCell = self.analytics.adjacentHeatmapCell(from: cell.dateKey, deltaDays: 1, in: self.selectedYear)
        
        return ZStack {
            Color.black.opacity(self.colorScheme == .dark ? 0.56 : 0.28)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(.spring(response: 0.30, dampingFraction: 0.84)) {
                        self.selectedHeatmapCell = nil
                    }
                }
            
            HeatmapDayDetailModalCard(
                detail: detail,
                levelColor: self.heatmapLevelColor(level: detail.cell.level),
                cardBackground: self.colorScheme == .dark
                    ? Color(nsColor: .windowBackgroundColor).opacity(0.96)
                    : Color(nsColor: .controlBackgroundColor),
                subCardBackground: self.subCardBackground,
                cardBorder: self.cardBorder,
                subCardBorder: self.subCardBorder,
                canStepPrev: prevCell != nil,
                canStepNext: nextCell != nil,
                onStepPrev: {
                    if let prevCell {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.84)) {
                            self.selectedHeatmapCell = prevCell
                        }
                    }
                },
                onStepNext: {
                    if let nextCell {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.84)) {
                            self.selectedHeatmapCell = nextCell
                        }
                    }
                },
                onClose: {
                    withAnimation(.spring(response: 0.30, dampingFraction: 0.84)) {
                        self.selectedHeatmapCell = nil
                    }
                }
            )
            .frame(maxWidth: self.isEmbeddedInSettings ? 520 : 560)
            .padding(20)
            .transition(
                .asymmetric(
                    insertion: .scale(scale: 0.90).combined(with: .opacity),
                    removal: .scale(scale: 0.94).combined(with: .opacity)
                )
            )
        }
    }
    
    
    // MARK: Visual Tokens & Helpers
    
    private var canvasBackground: Color {
        
        Color(nsColor: .windowBackgroundColor)
    }
    
    
    private var cardBackground: Color {
        
        if self.colorScheme == .dark {
            Color.white.opacity(0.048)
        } else {
            Color(nsColor: .controlBackgroundColor)
        }
    }
    
    
    private var cardBorder: Color {
        
        if self.colorScheme == .dark {
            Color.white.opacity(0.095)
        } else {
            Color.black.opacity(0.075)
        }
    }
    
    
    private var subCardBackground: Color {
        
        if self.colorScheme == .dark {
            Color.black.opacity(0.24)
        } else {
            Color.primary.opacity(0.032)
        }
    }
    
    
    private var subCardBorder: Color {
        
        if self.colorScheme == .dark {
            Color.white.opacity(0.065)
        } else {
            Color.black.opacity(0.055)
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
                case 4: Color(red: 0.24, green: 0.84, blue: 0.45)
                case 3: Color(red: 0.17, green: 0.65, blue: 0.35)
                case 2: Color(red: 0.11, green: 0.45, blue: 0.25)
                case 1: Color(red: 0.08, green: 0.28, blue: 0.17)
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
        
        let palette: [Color] = [
            Color(red: 0.23, green: 0.54, blue: 0.98),
            Color(red: 0.46, green: 0.38, blue: 0.96),
            Color(red: 0.18, green: 0.72, blue: 0.60),
            Color(red: 0.95, green: 0.55, blue: 0.18),
            Color(red: 0.91, green: 0.36, blue: 0.62),
        ]
        return palette[index % palette.count]
    }
    
    
    private static func formattedInt(_ value: Int) -> String {
        
        value.formatted(.number.grouping(.automatic))
    }
    
    
    private static func formattedCompactChars(_ value: Int) -> String {
        
        if value >= 10_000 {
            return String(format: "%.1f 万字", Double(value) / 10_000.0)
        }
        return "\(Self.formattedInt(value)) 字"
    }
    
    
    private static func shortMonthDay(_ dateKey: String) -> String {
        
        let parts = dateKey.split(separator: "-")
        guard parts.count == 3 else { return dateKey }
        let m = Int(parts[1]) ?? 0
        let d = Int(parts[2]) ?? 0
        return "\(m)/\(d)"
    }
    
    
    private static func deltaLabel(current: Int, baseline: Int) -> String {
        
        guard baseline > 0 else {
            return current > 0 ? "今日已开启" : "待开始写作"
        }
        let pct = Int(round(Double(current - baseline) * 100.0 / Double(baseline)))
        if pct >= 0 {
            return "较均 +\(pct)%"
        } else {
            return "较均 \(pct)%"
        }
    }
}


// MARK: - LeiBox-Inspired Reusable Effects & Subviews

/// Compact Swift Charts Catmull-Rom Sparkline embedded inside KPI Bento cards.
private struct MiniSparklineChart: View {
    
    let values: [Double]
    let tint: Color
    
    var body: some View {
        let points = self.values.enumerated().map { (index: $0.offset, value: $0.element) }
        Chart(points, id: \.index) { pt in
            AreaMark(
                x: .value("Day", pt.index),
                y: .value("Val", pt.value)
            )
            .interpolationMethod(.catmullRom)
            .foregroundStyle(
                LinearGradient(
                    colors: [self.tint.opacity(0.28), self.tint.opacity(0.01)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            
            LineMark(
                x: .value("Day", pt.index),
                y: .value("Val", pt.value)
            )
            .interpolationMethod(.catmullRom)
            .lineStyle(StrokeStyle(lineWidth: 1.6, lineCap: .round))
            .foregroundStyle(self.tint)
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .allowsHitTesting(false)
    }
}


/// LeiBox `border-beam` inspired traveling luminous edge highlight along a rounded card border.
private struct BorderBeamOverlay: View {
    
    let cornerRadius: CGFloat
    let accent: Color
    var speed: Double = 4.5
    var opacity: Double = 0.65
    
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
            let angle = Angle.degrees((context.date.timeIntervalSinceReferenceDate * (360.0 / self.speed)).truncatingRemainder(dividingBy: 360.0))
            RoundedRectangle(cornerRadius: self.cornerRadius, style: .continuous)
                .strokeBorder(
                    AngularGradient(
                        gradient: Gradient(stops: [
                            .init(color: .clear, location: 0.0),
                            .init(color: .clear, location: 0.68),
                            .init(color: self.accent.opacity(self.opacity * 0.6), location: 0.82),
                            .init(color: self.accent.opacity(self.opacity), location: 0.92),
                            .init(color: Color.white.opacity(self.opacity * 0.9), location: 0.96),
                            .init(color: .clear, location: 1.0),
                        ]),
                        center: .center,
                        angle: angle
                    ),
                    lineWidth: 1.4
                )
        }
        .allowsHitTesting(false)
    }
}


/// Subtle live recording pill inspired by LeiBox `ai-generating` pulse dot.
private struct LiveTelemetryPulseBadge: View {
    
    @State private var pulse = false
    
    var body: some View {
        HStack(spacing: 5) {
            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.28))
                    .frame(width: 10, height: 10)
                    .scaleEffect(self.pulse ? 1.45 : 0.75)
                    .opacity(self.pulse ? 0.0 : 0.85)
                Circle()
                    .fill(Color.green)
                    .frame(width: 5.5, height: 5.5)
            }
            Text("实时记录")
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Color.green.opacity(0.08), in: Capsule())
        .onAppear {
            withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: false)) {
                self.pulse = true
            }
        }
    }
}


/// LeiBox `thinking-particles` inspired 3×3 staggered breathing dot matrix indicator.
private struct MiniThinkingMatrixView: View {
    
    let tint: Color
    
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24.0)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let grid = [0, 1, 2]
            VStack(spacing: 1.5) {
                ForEach(grid, id: \.self) { row in
                    HStack(spacing: 1.5) {
                        ForEach(grid, id: \.self) { col in
                            let idx = Double(row + col)
                            let wave = 0.5 + 0.5 * sin(t * 5.4 - idx * 0.65)
                            RoundedRectangle(cornerRadius: 0.8)
                                .fill(self.tint.opacity(0.22 + 0.78 * wave))
                                .frame(width: 3, height: 3)
                                .scaleEffect(0.75 + 0.30 * wave)
                        }
                    }
                }
            }
        }
        .frame(width: 14, height: 14)
    }
}


/// LeiBox `stacked-metadata` inspired pill strip that gently fans apart on hover.
private struct StackedMetadataPills: View {
    
    let items: [String]
    let tint: Color
    
    @State private var isHovered = false
    
    var body: some View {
        HStack(spacing: self.isHovered ? 6 : 3) {
            ForEach(Array(self.items.enumerated()), id: \.offset) { _, label in
                Text(label)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(self.isHovered ? self.tint : Color.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2.5)
                    .background(self.tint.opacity(self.isHovered ? 0.14 : 0.08), in: Capsule())
                    .overlay(Capsule().strokeBorder(self.tint.opacity(self.isHovered ? 0.30 : 0.14), lineWidth: 0.6))
                    .lineLimit(1)
            }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.76), value: self.isHovered)
        .onHover { self.isHovered = $0 }
    }
}


/// Center detail modal opened when clicking a heatmap day cell (inspired by LeiBox `transfer-glow` & `share-invite`).
private struct HeatmapDayDetailModalCard: View {
    
    let detail: HeatmapDayDetail
    let levelColor: Color
    let cardBackground: Color
    let subCardBackground: Color
    let cardBorder: Color
    let subCardBorder: Color
    let canStepPrev: Bool
    let canStepNext: Bool
    let onStepPrev: () -> Void
    let onStepNext: () -> Void
    let onClose: () -> Void
    
    @State private var isCloseHovered = false
    
    var body: some View {
        let cell = self.detail.cell
        
        VStack(alignment: .leading, spacing: 14) {
            // Header
            HStack(spacing: 10) {
                HStack(spacing: 7) {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(self.levelColor)
                        .frame(width: 12, height: 12)
                    
                    Text(Self.formattedFullDate(cell.date))
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                    
                    Text(Self.activityLevelTitle(for: cell.level))
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(cell.level > 0 ? self.levelColor : .secondary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(
                            (cell.level > 0 ? self.levelColor : Color.secondary).opacity(0.14),
                            in: Capsule()
                        )
                }
                
                Spacer(minLength: 8)
                
                HStack(spacing: 4) {
                    Button(action: self.onStepPrev) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 10, weight: .semibold))
                            .frame(width: 24, height: 24)
                            .background(self.subCardBackground, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .disabled(!self.canStepPrev)
                    .opacity(self.canStepPrev ? 1 : 0.35)
                    .help("上一天")
                    
                    Button(action: self.onStepNext) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                            .frame(width: 24, height: 24)
                            .background(self.subCardBackground, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .disabled(!self.canStepNext)
                    .opacity(self.canStepNext ? 1 : 0.35)
                    .help("下一天")
                }
                
                Button(action: self.onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(self.isCloseHovered ? Color.red : Color.secondary)
                        .rotationEffect(.degrees(self.isCloseHovered ? 90 : 0))
                        .frame(width: 26, height: 26)
                        .background(
                            self.isCloseHovered ? Color.red.opacity(0.14) : self.subCardBackground,
                            in: Circle()
                        )
                }
                .buttonStyle(.plain)
                .pointerStyle(.link)
                .onHover { hovering in
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.68)) {
                        self.isCloseHovered = hovering
                    }
                }
                .help("关闭 (Esc)")
            }
            
            // Core 6-Metric Grid (Tabular Numbers, Zero Progress Bars)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                self.modalStatTile(title: "手动输入", value: cell.typedChars.formatted(), unit: "字", tint: Color(red: 0.23, green: 0.54, blue: 0.98))
                self.modalStatTile(title: "AI 补全", value: cell.aiCompletedChars.formatted(), unit: "字", tint: Color(red: 0.46, green: 0.38, blue: 0.96))
                self.modalStatTile(title: "AI 调用", value: "\(cell.aiRequests)", unit: "次", tint: Color(red: 0.95, green: 0.55, blue: 0.18))
                self.modalStatTile(title: "Token 消耗", value: AnalyticsManager.formatCompactTokenCount(cell.totalTokens), unit: "入\(AnalyticsManager.formatCompactTokenCount(cell.inputTokens))/出\(AnalyticsManager.formatCompactTokenCount(cell.outputTokens))", tint: Color(red: 0.95, green: 0.55, blue: 0.18))
                self.modalStatTile(title: "文档动态", value: "\(cell.filesCreated) / \(cell.documentsSaved)", unit: "新建·保存", tint: .teal)
                self.modalStatTile(title: "采纳与省流", value: "\(cell.aiCompletionAccepts) / \(cell.localHits)", unit: "采纳·本地", tint: .green)
            }
            
            // Visual Breakdown when the day has writing or AI data
            if cell.typedChars + cell.aiCompletedChars > 0 || !self.detail.models.isEmpty {
                HStack(alignment: .top, spacing: 12) {
                    if cell.typedChars + cell.aiCompletedChars > 0 {
                        let mix: [(label: String, value: Int, color: Color)] = [
                            ("手打", cell.typedChars, Color(red: 0.23, green: 0.54, blue: 0.98)),
                            ("AI补全", cell.aiCompletedChars, Color(red: 0.46, green: 0.38, blue: 0.96)),
                        ].filter { $0.value > 0 }
                        
                        VStack(alignment: .leading, spacing: 6) {
                            Text("产出构成")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.secondary)
                            HStack(spacing: 12) {
                                Chart(mix, id: \.label) { item in
                                    SectorMark(
                                        angle: .value("字数", item.value),
                                        innerRadius: .ratio(0.60),
                                        angularInset: 2
                                    )
                                    .cornerRadius(3)
                                    .foregroundStyle(item.color)
                                }
                                .chartLegend(.hidden)
                                .frame(width: 68, height: 68)
                                
                                VStack(alignment: .leading, spacing: 5) {
                                    ForEach(mix, id: \.label) { item in
                                        HStack(spacing: 5) {
                                            Circle().fill(item.color).frame(width: 6, height: 6)
                                            Text("\(item.label) \(item.value.formatted()) 字")
                                                .font(.system(size: 11))
                                                .monospacedDigit()
                                        }
                                    }
                                }
                            }
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(self.subCardBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(self.subCardBorder, lineWidth: 0.5))
                    }
                    
                    if !self.detail.models.isEmpty || !self.detail.features.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("AI 使用明细")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.secondary)
                            
                            ForEach(self.detail.models.prefix(3)) { model in
                                HStack(spacing: 6) {
                                    Circle().fill(Color.orange).frame(width: 5, height: 5)
                                    Text(model.model)
                                        .font(.system(size: 11, weight: .medium))
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                    Spacer()
                                    Text("\(model.requests) 次 · \(AnalyticsManager.formatCompactTokenCount(model.totalTokens))")
                                        .font(.system(size: 10.5))
                                        .monospacedDigit()
                                        .foregroundStyle(.secondary)
                                }
                            }
                            if self.detail.averageLatencyMs > 0 {
                                Text("平均响应 \(self.detail.averageLatencyMs) ms")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(self.subCardBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(self.subCardBorder, lineWidth: 0.5))
                    }
                }
            }
            
            // Documents / Weekly Reports touched on that date
            if !self.detail.documents.isEmpty || !self.detail.weeklyReports.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("关联文档与周报")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                    
                    let titles = self.detail.documents.map(\.title) + self.detail.weeklyReports.map(\.title)
                    StackedMetadataPills(items: Array(titles.prefix(5)), tint: Color.accentColor)
                }
            }
            
            // Daily AI Digest if available for this date
            if let digest = self.detail.digest {
                let pts = AnalyticsManager.structuredSummaryPoints(from: digest.summary, maxPoints: 3)
                if !pts.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("当日总结")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                        ForEach(Array(pts.enumerated()), id: \.offset) { _, pt in
                            HStack(alignment: .top, spacing: 6) {
                                Circle().fill(Color.accentColor).frame(width: 4.5, height: 4.5).padding(.top, 5)
                                Text(pt)
                                    .font(.system(size: 11.5))
                                    .foregroundStyle(.primary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(self.subCardBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
        }
        .padding(18)
        .background(self.cardBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(self.cardBorder, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.24), radius: 28, y: 12)
    }
    
    
    private func modalStatTile(title: String, value: String, unit: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(unit)
                .font(.system(size: 9.5))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(self.subCardBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(tint.opacity(0.16), lineWidth: 0.75)
        )
    }
    
    
    private static func formattedFullDate(_ date: Date) -> String {
        
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy年M月d日 · EEEE"
        return formatter.string(from: date)
    }
    
    
    private static func activityLevelTitle(for level: Int) -> String {
        
        switch level {
            case 4: "高能爆发"
            case 3: "深度专注"
            case 2: "稳定产出"
            case 1: "轻度记录"
            default: "休息日"
        }
    }
}
