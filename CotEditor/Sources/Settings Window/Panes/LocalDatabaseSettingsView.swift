//
//  LocalDatabaseSettingsView.swift
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

/// Visual local SQLite vault explorer for Settings: storage footprint, portable migration controls,
/// AI token analytics, interactive table schema/content browser, and storage health metrics.
struct LocalDatabaseSettingsView: View {
    
    let onExportDatabase: () -> Void
    let onImportDatabase: () -> Void
    var refreshRevision: Int = 0
    
    @Environment(\.colorScheme) private var colorScheme
    @State private var database = CotLocalDatabase.shared
    @State private var studioPalette = StudioPaletteManager.shared
    @State private var snapshot: DatabaseInspectionSnapshot?
    @State private var selectedTable: DatabaseTableSummary?
    @State private var tablePreview: DatabaseTablePreview?
    @State private var tableFilterOnlyPopulated = false
    @State private var tokenTab: TokenViewTab = .overview
    @State private var compactStatusText: String?
    
    fileprivate enum TokenViewTab: String, CaseIterable, Identifiable {
        case overview
        case events
        var id: String { self.rawValue }
        var title: String {
            switch self {
                case .overview: AppLanguage.text("统计", en: "Summary")
                case .events: AppLanguage.text("明细", en: "History")
            }
        }
    }
    
    private var isDark: Bool { self.colorScheme == .dark }
    
    private var accent: Color {
        self.studioPalette.softPreviewColors(for: self.studioPalette.selectedID, isDark: self.isDark).swatch
    }
    
    
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let table = self.selectedTable {
                DatabaseTableDetailView(
                    table: table,
                    preview: self.tablePreview,
                    isDark: self.isDark,
                    accent: self.accent,
                    onBack: {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            self.selectedTable = nil
                            self.tablePreview = nil
                        }
                    }
                )
                .transition(.opacity.combined(with: .move(edge: .trailing)))
            } else if let snapshot = self.snapshot {
                DatabaseStorageOverviewCard(
                    snapshot: snapshot,
                    isDark: self.isDark,
                    accent: self.accent,
                    compactStatusText: self.compactStatusText,
                    onRevealInFinder: { self.revealDatabaseInFinder() },
                    onExport: self.onExportDatabase,
                    onImport: self.onImportDatabase,
                    onCompact: { self.runCompact() }
                )
                
                DatabaseAssetPulseCard(
                    assets: snapshot.assets,
                    isDark: self.isDark
                )
                
                DatabaseTokenAnalyticsCard(
                    summary: snapshot.tokenSummary,
                    selectedTab: self.$tokenTab,
                    isDark: self.isDark,
                    accent: self.accent
                )
                
                DatabaseTableExplorerCard(
                    tables: snapshot.tables,
                    onlyPopulated: self.$tableFilterOnlyPopulated,
                    isDark: self.isDark,
                    onSelectTable: { table in
                        let preview = self.database.inspectTablePreview(tableName: table.name, limit: 30)
                        withAnimation(.easeInOut(duration: 0.18)) {
                            self.tablePreview = preview
                            self.selectedTable = table
                        }
                    }
                )
                
                DatabaseTechnicalMetaCard(
                    snapshot: snapshot,
                    isDark: self.isDark,
                    onRevealInFinder: { self.revealDatabaseInFinder() },
                    onRefresh: { self.reloadSnapshot() }
                )
            }
        }
        .task(id: self.refreshRevision) {
            self.reloadSnapshot()
        }
    }
    
    
    private func reloadSnapshot() {
        self.snapshot = self.database.inspectDatabaseSnapshot()
    }
    
    
    private func revealDatabaseInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([self.database.databaseURL])
    }
    
    
    private func runCompact() {
        let reclaimed = self.database.compactDatabase()
        self.reloadSnapshot()
        let text = reclaimed > 0
            ? AppLanguage.text("已释放 \(DatabaseFormatters.bytes(reclaimed))", en: "Freed \(DatabaseFormatters.bytes(reclaimed))")
            : AppLanguage.text("已整理", en: "Compacted")
        withAnimation(.easeOut(duration: 0.16)) {
            self.compactStatusText = text
        }
        Task {
            try? await Task.sleep(for: .seconds(2.5))
            await MainActor.run {
                if self.compactStatusText == text {
                    withAnimation(.easeOut(duration: 0.2)) {
                        self.compactStatusText = nil
                    }
                }
            }
        }
    }
}


// MARK: - Formatting & Palette Helpers

private enum DatabaseFormatters {
    
    private static let byteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useBytes, .useKB, .useMB, .useGB]
        formatter.countStyle = .file
        formatter.includesUnit = true
        return formatter
    }()
    
    private static let eventTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd HH:mm"
        return formatter
    }()
    
    static func bytes(_ count: Int64) -> String {
        if count <= 0 { return "0 B" }
        return self.byteFormatter.string(fromByteCount: count)
    }
    
    static func compactCount(_ value: Int) -> String {
        if value >= 1_000_000 {
            return String(format: "%.2fM", Double(value) / 1_000_000.0)
        }
        if value >= 10_000 {
            return String(format: "%.1fK", Double(value) / 1_000.0)
        }
        if value >= 1_000 {
            return String(format: "%.2fK", Double(value) / 1_000.0)
        }
        return "\(value)"
    }
    
    static func eventTimestamp(_ date: Date) -> String {
        self.eventTimeFormatter.string(from: date)
    }
    
    static func categoryColor(_ kind: DatabaseCategoryKind, isDark: Bool) -> Color {
        switch kind {
            case .documents:
                isDark ? Color(red: 0.36, green: 0.64, blue: 0.96) : Color(red: 0.18, green: 0.49, blue: 0.92)
            case .aiRecords:
                isDark ? Color(red: 0.65, green: 0.52, blue: 0.96) : Color(red: 0.48, green: 0.36, blue: 0.84)
            case .memory:
                isDark ? Color(red: 0.32, green: 0.78, blue: 0.60) : Color(red: 0.18, green: 0.64, blue: 0.47)
            case .feedsAndBoards:
                isDark ? Color(red: 0.92, green: 0.66, blue: 0.34) : Color(red: 0.85, green: 0.54, blue: 0.16)
            case .systemConfig:
                isDark ? Color(red: 0.56, green: 0.58, blue: 0.64) : Color(red: 0.52, green: 0.54, blue: 0.60)
        }
    }
}


private struct DatabaseCardContainer<Content: View>: View {
    
    var title: String?
    var trailingTitle: String? = nil
    let isDark: Bool
    @ViewBuilder var content: () -> Content
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if self.title != nil || self.trailingTitle != nil {
                HStack {
                    if let title = self.title {
                        Text(title)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let trailingTitle = self.trailingTitle {
                        Text(trailingTitle)
                            .font(.system(size: 11.5).monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 4)
            }
            
            VStack(alignment: .leading, spacing: 0) {
                self.content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(self.isDark ? Color.white.opacity(0.055) : Color.white)
                    .shadow(
                        color: self.isDark ? Color.clear : Color.black.opacity(0.025),
                        radius: 2,
                        y: 0.5
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(self.isDark ? Color.white.opacity(0.075) : Color.black.opacity(0.06), lineWidth: 0.5)
            )
        }
    }
}


// MARK: - 1. Storage Bar & Portable Migration Card

private struct DatabaseStorageOverviewCard: View {
    
    let snapshot: DatabaseInspectionSnapshot
    let isDark: Bool
    let accent: Color
    let compactStatusText: String?
    let onRevealInFinder: () -> Void
    let onExport: () -> Void
    let onImport: () -> Void
    let onCompact: () -> Void
    
    var body: some View {
        let totalEstimated = max(1, self.snapshot.categories.reduce(Int64(0)) { $0 + $1.bytes })
        
        DatabaseCardContainer(
            title: AppLanguage.text("本地存储", en: "Local Storage"),
            trailingTitle: "\(self.snapshot.tables.count) \(AppLanguage.text("张表", en: "tables")) · \(self.snapshot.totalRowCount) \(AppLanguage.text("条记录", en: "rows"))",
            isDark: self.isDark
        ) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(DatabaseFormatters.bytes(self.snapshot.totalBytes))
                        .font(.system(size: 24, weight: .semibold).monospacedDigit())
                        .foregroundStyle(.primary)
                    
                    Text(self.snapshot.fileName)
                        .font(.system(size: 11.5, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 7)
                        .frame(height: 20)
                        .background(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(self.isDark ? Color.white.opacity(0.06) : Color.black.opacity(0.04))
                        )
                    
                    Spacer(minLength: 8)
                    
                    if let compactStatusText = self.compactStatusText {
                        Text(compactStatusText)
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(.secondary)
                            .transition(.opacity)
                    }
                }
                
                // Apple Storage-style segmented bar
                GeometryReader { geo in
                    let nonZero = self.snapshot.categories.filter { $0.bytes > 0 }
                    let spacing: CGFloat = nonZero.count > 1 ? 2 : 0
                    let usableWidth = max(0, geo.size.width - spacing * CGFloat(max(0, nonZero.count - 1)))
                    
                    HStack(spacing: spacing) {
                        if nonZero.isEmpty {
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(self.isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.06))
                        } else {
                            ForEach(nonZero) { category in
                                let fraction = CGFloat(category.bytes) / CGFloat(totalEstimated)
                                RoundedRectangle(cornerRadius: 3, style: .continuous)
                                    .fill(DatabaseFormatters.categoryColor(category.kind, isDark: self.isDark))
                                    .frame(width: max(6, usableWidth * fraction))
                            }
                        }
                    }
                }
                .frame(height: 10)
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                
                // Category legend row
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 110), spacing: 8)],
                    alignment: .leading,
                    spacing: 6
                ) {
                    ForEach(self.snapshot.categories) { category in
                        HStack(spacing: 5) {
                            Circle()
                                .fill(DatabaseFormatters.categoryColor(category.kind, isDark: self.isDark))
                                .frame(width: 7, height: 7)
                            Text(category.kind.displayName)
                                .font(.system(size: 11.5))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            Text(DatabaseFormatters.bytes(category.bytes))
                                .font(.system(size: 11, weight: .medium).monospacedDigit())
                                .foregroundStyle(.primary.opacity(0.82))
                                .lineLimit(1)
                        }
                    }
                }
                
                Rectangle()
                    .fill(self.isDark ? Color.white.opacity(0.07) : Color.black.opacity(0.06))
                    .frame(height: 0.5)
                
                // Migration & maintenance action strip
                HStack(spacing: 8) {
                    Button(AppLanguage.text("导出迁移文件", en: "Export")) {
                        self.onExport()
                    }
                    .controlSize(.small)
                    
                    Button(AppLanguage.text("导入数据库", en: "Import")) {
                        self.onImport()
                    }
                    .controlSize(.small)
                    
                    Button(AppLanguage.text("压缩空间", en: "Compact")) {
                        self.onCompact()
                    }
                    .controlSize(.small)
                    
                    Spacer()
                    
                    Button(AppLanguage.text("在访达中显示", en: "Reveal")) {
                        self.onRevealInFinder()
                    }
                    .controlSize(.small)
                }
            }
            .padding(14)
        }
    }
}


// MARK: - 2. Local Vault Inventory Grid

private struct DatabaseAssetPulseCard: View {
    
    let assets: DatabaseAssetCounts
    let isDark: Bool
    
    var body: some View {
        let items: [(label: String, value: String, detail: String)] = [
            (
                AppLanguage.text("文档", en: "Docs"),
                "\(self.assets.activeDocuments)",
                "\(DatabaseFormatters.compactCount(self.assets.totalDocumentChars)) \(AppLanguage.text("字", en: "ch"))"
            ),
            (
                AppLanguage.text("AI 对话", en: "Chats"),
                "\(self.assets.totalMessages)",
                "\(self.assets.butlerSessions) \(AppLanguage.text("会话", en: "sess"))"
            ),
            (
                AppLanguage.text("长期记忆", en: "Memory"),
                "\(self.assets.kycMemories)",
                "\(self.assets.memoryJournals) \(AppLanguage.text("日志", en: "logs"))"
            ),
            (
                AppLanguage.text("写作天数", en: "Writing"),
                "\(self.assets.writingDays)",
                "\(DatabaseFormatters.compactCount(self.assets.totalTypedChars)) \(AppLanguage.text("字", en: "ch"))"
            ),
            (
                AppLanguage.text("待办", en: "Tasks"),
                "\(self.assets.remindersOpen)",
                "/ \(self.assets.remindersTotal)"
            ),
            (
                AppLanguage.text("周报", en: "Reports"),
                "\(self.assets.weeklyReports)",
                AppLanguage.text("归档", en: "saved")
            ),
            (
                AppLanguage.text("订阅", en: "Feeds"),
                "\(self.assets.totalSubscriptions)",
                "\(self.assets.watchlistStocks) \(AppLanguage.text("股", en: "stk")) · \(self.assets.podcasts) \(AppLanguage.text("播客", en: "pod"))"
            ),
            (
                AppLanguage.text("配置项", en: "Configs"),
                "\(self.assets.configEntries)",
                "SQLite"
            ),
        ]
        
        DatabaseCardContainer(
            title: AppLanguage.text("数据资产概览", en: "Stored Assets"),
            isDark: self.isDark
        ) {
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4),
                spacing: 8
            ) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.label)
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                        Text(item.value)
                            .font(.system(size: 16, weight: .semibold).monospacedDigit())
                            .foregroundStyle(.primary)
                        Text(item.detail)
                            .font(.system(size: 10.5).monospacedDigit())
                            .foregroundStyle(.secondary.opacity(0.85))
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(self.isDark ? Color.white.opacity(0.035) : Color.black.opacity(0.022))
                    )
                }
            }
            .padding(12)
        }
    }
}


// MARK: - 3. AI Token Analytics Card

private struct DatabaseTokenAnalyticsCard: View {
    
    let summary: DatabaseAITokenSummary
    @Binding var selectedTab: LocalDatabaseSettingsView.TokenViewTab
    let isDark: Bool
    let accent: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(AppLanguage.text("AI 会话与 Token 记录", en: "AI Token Usage"))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if self.summary.totalRequests > 0 {
                    Picker("", selection: self.$selectedTab) {
                        ForEach(LocalDatabaseSettingsView.TokenViewTab.allCases) { tab in
                            Text(tab.title).tag(tab)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .controlSize(.small)
                    .frame(width: 112)
                }
            }
            .padding(.horizontal, 4)
            
            DatabaseCardContainer(title: nil, isDark: self.isDark) {
                if self.summary.totalRequests == 0 {
                    HStack {
                        Text(AppLanguage.text("暂无 AI Token 记录", en: "No AI token records"))
                            .font(.system(size: 12.5))
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(14)
                } else if self.selectedTab == .overview {
                    self.overviewBody
                } else {
                    self.eventsBody
                }
            }
        }
    }
    
    
    private var overviewBody: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Top 4 KPI metrics
            HStack(spacing: 8) {
                self.kpiTile(
                    label: AppLanguage.text("总 Tokens", en: "Total"),
                    value: DatabaseFormatters.compactCount(self.summary.totalTokens)
                )
                self.kpiTile(
                    label: AppLanguage.text("输入", en: "Input"),
                    value: DatabaseFormatters.compactCount(self.summary.totalInputTokens)
                )
                self.kpiTile(
                    label: AppLanguage.text("输出", en: "Output"),
                    value: DatabaseFormatters.compactCount(self.summary.totalOutputTokens)
                )
                self.kpiTile(
                    label: "\(self.summary.totalRequests) \(AppLanguage.text("次", en: "req"))",
                    value: "\(self.summary.averageLatencyMs) ms"
                )
            }
            
            // 14-day token sparkbar trend
            if !self.summary.dailyTrend.isEmpty {
                self.dailyTrendStrip
            }
            
            // Model & Feature breakdowns side-by-side
            HStack(alignment: .top, spacing: 14) {
                if !self.summary.byModel.isEmpty {
                    VStack(alignment: .leading, spacing: 7) {
                        Text(AppLanguage.text("按模型", en: "By Model"))
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(.secondary)
                        let maxVal = max(1, self.summary.byModel.first?.totalTokens ?? 1)
                        ForEach(self.summary.byModel.prefix(5)) { entry in
                            self.barRow(
                                label: entry.model,
                                valueText: DatabaseFormatters.compactCount(entry.totalTokens),
                                ratio: CGFloat(entry.totalTokens) / CGFloat(maxVal),
                                tint: self.accent
                            )
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                
                if !self.summary.byFeature.isEmpty {
                    VStack(alignment: .leading, spacing: 7) {
                        Text(AppLanguage.text("按场景", en: "By Feature"))
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(.secondary)
                        let maxVal = max(1, self.summary.byFeature.first?.totalTokens ?? 1)
                        ForEach(self.summary.byFeature.prefix(5)) { entry in
                            self.barRow(
                                label: entry.displayName,
                                valueText: "\(DatabaseFormatters.compactCount(entry.totalTokens)) · \(entry.requests)",
                                ratio: CGFloat(entry.totalTokens) / CGFloat(maxVal),
                                tint: DatabaseFormatters.categoryColor(.aiRecords, isDark: self.isDark)
                            )
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(14)
    }
    
    
    private var dailyTrendStrip: some View {
        let maxTokens = max(1, self.summary.dailyTrend.map(\.totalTokens).max() ?? 1)
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(AppLanguage.text("近期消耗趋势", en: "Recent Trend"))
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if let first = self.summary.dailyTrend.first, let last = self.summary.dailyTrend.last {
                    Text("\(first.shortLabel) – \(last.shortLabel)")
                        .font(.system(size: 10.5).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            
            HStack(alignment: .bottom, spacing: 4) {
                ForEach(self.summary.dailyTrend) { point in
                    let h = max(4, CGFloat(point.totalTokens) / CGFloat(maxTokens) * 44)
                    VStack(spacing: 3) {
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(self.accent.opacity(0.75))
                            .frame(maxWidth: .infinity)
                            .frame(height: h)
                    }
                    .help("\(point.dateKey): \(DatabaseFormatters.compactCount(point.totalTokens)) tokens (\(point.requests))")
                }
            }
            .frame(height: 48, alignment: .bottom)
            .padding(.horizontal, 6)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(self.isDark ? Color.white.opacity(0.03) : Color.black.opacity(0.02))
            )
        }
    }
    
    
    private var eventsBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text(AppLanguage.text("时间", en: "Time"))
                    .frame(width: 78, alignment: .leading)
                Text(AppLanguage.text("场景", en: "Feature"))
                    .frame(width: 66, alignment: .leading)
                Text(AppLanguage.text("模型", en: "Model"))
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("Tokens")
                    .frame(width: 78, alignment: .trailing)
                Text(AppLanguage.text("耗时", en: "Latency"))
                    .frame(width: 54, alignment: .trailing)
            }
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 14)
            .frame(height: 30)
            
            ForEach(self.summary.recentEvents.prefix(12)) { event in
                Rectangle()
                    .fill(self.isDark ? Color.white.opacity(0.06) : Color.black.opacity(0.05))
                    .frame(height: 0.5)
                    .padding(.leading, 14)
                
                HStack(spacing: 8) {
                    Text(DatabaseFormatters.eventTimestamp(event.timestamp))
                        .font(.system(size: 11, design: .monospaced).monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 78, alignment: .leading)
                    
                    Text(event.featureLabel)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .frame(width: 66, alignment: .leading)
                    
                    Text(event.model)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    
                    Text("\(DatabaseFormatters.compactCount(event.inputTokens))/\(DatabaseFormatters.compactCount(event.outputTokens))")
                        .font(.system(size: 11, design: .monospaced).monospacedDigit())
                        .foregroundStyle(.primary)
                        .frame(width: 78, alignment: .trailing)
                    
                    Text("\(event.latencyMs)ms")
                        .font(.system(size: 11, design: .monospaced).monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 54, alignment: .trailing)
                }
                .padding(.horizontal, 14)
                .frame(height: 30)
            }
        }
    }
    
    
    private func kpiTile(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 11).monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(value)
                .font(.system(size: 14.5, weight: .semibold).monospacedDigit())
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(self.isDark ? Color.white.opacity(0.035) : Color.black.opacity(0.022))
        )
    }
    
    
    private func barRow(label: String, valueText: String, ratio: CGFloat, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(label)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 4)
                Text(valueText)
                    .font(.system(size: 11, design: .monospaced).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                        .fill(self.isDark ? Color.white.opacity(0.07) : Color.black.opacity(0.055))
                    RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                        .fill(tint.opacity(0.75))
                        .frame(width: max(4, geo.size.width * min(1, max(0, ratio))))
                }
            }
            .frame(height: 4.5)
        }
    }
}


// MARK: - 4. Interactive SQLite Table Explorer Card

private struct DatabaseTableExplorerCard: View {
    
    let tables: [DatabaseTableSummary]
    @Binding var onlyPopulated: Bool
    let isDark: Bool
    let onSelectTable: (DatabaseTableSummary) -> Void
    
    private var visibleTables: [DatabaseTableSummary] {
        self.onlyPopulated ? self.tables.filter { $0.rowCount > 0 } : self.tables
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(AppLanguage.text("数据表清单", en: "SQLite Tables"))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    self.onlyPopulated.toggle()
                } label: {
                    Text(self.onlyPopulated
                         ? AppLanguage.text("仅看非空", en: "Non-Empty")
                         : AppLanguage.text("全部 \(self.tables.count) 表", en: "All \(self.tables.count)"))
                        .font(.system(size: 11, weight: .medium).monospacedDigit())
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .frame(height: 20)
                        .background(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(self.isDark ? Color.white.opacity(0.06) : Color.black.opacity(0.04))
                        )
                }
                .buttonStyle(.plain)
                .pointerStyle(.link)
            }
            .padding(.horizontal, 4)
            
            DatabaseCardContainer(title: nil, isDark: self.isDark) {
                ForEach(Array(self.visibleTables.enumerated()), id: \.element.id) { idx, table in
                    if idx > 0 {
                        Rectangle()
                            .fill(self.isDark ? Color.white.opacity(0.07) : Color.black.opacity(0.06))
                            .frame(height: 0.5)
                            .padding(.leading, 14)
                    }
                    DatabaseTableRowView(
                        table: table,
                        isDark: self.isDark,
                        onSelect: { self.onSelectTable(table) }
                    )
                }
            }
        }
    }
}


private struct DatabaseTableRowView: View {
    
    let table: DatabaseTableSummary
    let isDark: Bool
    let onSelect: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        Button(action: self.onSelect) {
            HStack(spacing: 10) {
                Circle()
                    .fill(DatabaseFormatters.categoryColor(self.table.category, isDark: self.isDark))
                    .frame(width: 7, height: 7)
                
                Text(self.table.displayName)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                
                Text(self.table.name)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                
                Spacer(minLength: 8)
                
                Text("\(self.table.columns.count) \(AppLanguage.text("列", en: "col"))")
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(.secondary.opacity(0.8))
                    .frame(width: 38, alignment: .trailing)
                
                Text("\(self.table.rowCount) \(AppLanguage.text("行", en: "rows"))")
                    .font(.system(size: 11.5, weight: self.table.rowCount > 0 ? .medium : .regular).monospacedDigit())
                    .foregroundStyle(self.table.rowCount > 0 ? .primary : .secondary)
                    .frame(width: 58, alignment: .trailing)
                
                Text(DatabaseFormatters.bytes(self.table.estimatedBytes))
                    .font(.system(size: 11, design: .monospaced).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 62, alignment: .trailing)
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary.opacity(0.6))
            }
            .padding(.horizontal, 14)
            .frame(height: 36)
            .background(
                self.isHovered
                    ? (self.isDark ? Color.white.opacity(0.04) : Color.black.opacity(0.025))
                    : Color.clear
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointerStyle(.link)
        .onHover { hovering in
            self.isHovered = hovering
        }
    }
}


// MARK: - 5. Inline Table Schema & Live Content Viewer

private struct DatabaseTableDetailView: View {
    
    let table: DatabaseTableSummary
    let preview: DatabaseTablePreview?
    let isDark: Bool
    let accent: Color
    let onBack: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Button(action: self.onBack) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 10.5, weight: .semibold))
                        Text(AppLanguage.text("返回", en: "Back"))
                            .font(.system(size: 12.5, weight: .medium))
                    }
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .frame(height: 26)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(self.isDark ? Color.white.opacity(0.06) : Color.black.opacity(0.045))
                    )
                }
                .buttonStyle(.plain)
                .pointerStyle(.link)
                
                Text(self.table.displayName)
                    .font(.system(size: 14, weight: .semibold))
                
                Text(self.table.name)
                    .font(.system(size: 11.5, design: .monospaced))
                    .foregroundStyle(.secondary)
                
                Spacer()
                
                Text("\(self.table.rowCount) \(AppLanguage.text("行", en: "rows")) · \(self.table.columns.count) \(AppLanguage.text("列", en: "cols")) · \(self.table.indexCount) \(AppLanguage.text("索引", en: "idx"))")
                    .font(.system(size: 11.5).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            
            // Column schema chips
            DatabaseCardContainer(title: AppLanguage.text("表结构", en: "Schema"), isDark: self.isDark) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(self.table.columns) { col in
                            HStack(spacing: 4) {
                                if col.isPrimaryKey {
                                    Text("PK")
                                        .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                                        .foregroundStyle(self.accent)
                                }
                                Text(col.name)
                                    .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                                    .foregroundStyle(.primary)
                                Text(col.dataType)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 8)
                            .frame(height: 24)
                            .background(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(self.isDark ? Color.white.opacity(0.05) : Color.black.opacity(0.032))
                            )
                        }
                    }
                    .padding(12)
                }
            }
            
            // Live row preview
            DatabaseCardContainer(
                title: AppLanguage.text("近期内容", en: "Recent Rows"),
                trailingTitle: self.preview.map { "\($0.rows.count) / \($0.totalRowCount)" },
                isDark: self.isDark
            ) {
                if let preview = self.preview, !preview.rows.isEmpty {
                    ScrollView(.horizontal, showsIndicators: true) {
                        VStack(alignment: .leading, spacing: 0) {
                            // Header row
                            HStack(spacing: 12) {
                                ForEach(preview.columns, id: \.self) { colName in
                                    Text(colName)
                                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                        .frame(width: 120, alignment: .leading)
                                }
                            }
                            .padding(.horizontal, 12)
                            .frame(height: 30)
                            .background(self.isDark ? Color.white.opacity(0.03) : Color.black.opacity(0.02))
                            
                            ForEach(Array(preview.rows.enumerated()), id: \.offset) { _, row in
                                Rectangle()
                                    .fill(self.isDark ? Color.white.opacity(0.06) : Color.black.opacity(0.05))
                                    .frame(height: 0.5)
                                HStack(spacing: 12) {
                                    ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                                        Text(cell)
                                            .font(.system(size: 11.5, design: .monospaced))
                                            .foregroundStyle(.primary.opacity(0.88))
                                            .lineLimit(1)
                                            .truncationMode(.tail)
                                            .frame(width: 120, alignment: .leading)
                                            .textSelection(.enabled)
                                    }
                                }
                                .padding(.horizontal, 12)
                                .frame(height: 30)
                            }
                        }
                    }
                } else {
                    HStack {
                        Text(AppLanguage.text("当前表为空", en: "Empty table"))
                            .font(.system(size: 12.5))
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(14)
                }
            }
        }
    }
}


// MARK: - 6. Storage Engine Metadata Card

private struct DatabaseTechnicalMetaCard: View {
    
    let snapshot: DatabaseInspectionSnapshot
    let isDark: Bool
    let onRevealInFinder: () -> Void
    let onRefresh: () -> Void
    
    var body: some View {
        DatabaseCardContainer(
            title: AppLanguage.text("引擎信息", en: "Engine"),
            isDark: self.isDark
        ) {
            self.metaRow(
                label: AppLanguage.text("文件位置", en: "Location"),
                value: self.snapshot.filePath,
                monospaced: true
            )
            self.divider
            self.metaRow(
                label: AppLanguage.text("SQLite 引擎", en: "SQLite"),
                value: "v\(self.snapshot.sqliteVersion) · \(self.snapshot.journalMode)",
                monospaced: true
            )
            self.divider
            self.metaRow(
                label: AppLanguage.text("主文件 / WAL", en: "Main / WAL"),
                value: "\(DatabaseFormatters.bytes(self.snapshot.mainFileBytes)) / \(DatabaseFormatters.bytes(self.snapshot.walBytes))",
                monospaced: true
            )
            self.divider
            self.metaRow(
                label: AppLanguage.text("页结构 / 可回收", en: "Pages / Free"),
                value: "\(self.snapshot.pageCount) × \(DatabaseFormatters.bytes(Int64(self.snapshot.pageSize))) · \(DatabaseFormatters.bytes(self.snapshot.reclaimableBytes))",
                monospaced: true
            )
        }
    }
    
    
    private var divider: some View {
        Rectangle()
            .fill(self.isDark ? Color.white.opacity(0.07) : Color.black.opacity(0.06))
            .frame(height: 0.5)
            .padding(.leading, 14)
    }
    
    
    private func metaRow(label: String, value: String, monospaced: Bool) -> some View {
        HStack(spacing: 12) {
            Text(label)
                .font(.system(size: 12.5))
                .foregroundStyle(.primary)
            Spacer(minLength: 12)
            Text(value)
                .font(monospaced ? .system(size: 11.5, design: .monospaced).monospacedDigit() : .system(size: 12.5))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
        }
        .padding(.horizontal, 14)
        .frame(height: 36)
    }
}
