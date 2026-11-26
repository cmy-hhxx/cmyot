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

/// Visual Personal Knowledge Vault explorer for Settings: spatial storage ring & segmented bar,
/// clickable human-readable content cards (zero SQLite table/key jargon), AI token analytics,
/// and overflow-safe local file location controls.
struct LocalDatabaseSettingsView: View {
    
    let onExportDatabase: () -> Void
    let onImportDatabase: () -> Void
    var refreshRevision: Int = 0
    
    @Environment(\.colorScheme) private var colorScheme
    @State private var database = CotLocalDatabase.shared
    @State private var studioPalette = StudioPaletteManager.shared
    @State private var snapshot: DatabaseInspectionSnapshot?
    @State private var activeSection: DatabaseVaultSectionKind?
    @State private var sectionItems: [DatabaseVaultContentItem] = []
    @State private var highlightedCategory: DatabaseCategoryKind?
    @State private var tokenTab: TokenViewTab = .overview
    @State private var compactStatusText: String?
    @State private var didCopyPath = false
    
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
        VStack(alignment: .leading, spacing: 16) {
            if let section = self.activeSection {
                DatabaseVaultDetailView(
                    section: section,
                    items: self.sectionItems,
                    isDark: self.isDark,
                    onSwitchSection: { next in
                        self.openSection(next)
                    },
                    onBack: {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            self.activeSection = nil
                            self.sectionItems = []
                        }
                    }
                )
                .transition(.opacity.combined(with: .move(edge: .trailing)))
            } else if let snapshot = self.snapshot {
                DatabaseVaultHeroCard(
                    snapshot: snapshot,
                    highlightedCategory: self.$highlightedCategory,
                    isDark: self.isDark,
                    compactStatusText: self.compactStatusText,
                    didCopyPath: self.didCopyPath,
                    onCopyPath: { self.copyDatabasePath(snapshot.filePath) },
                    onRevealInFinder: { self.revealDatabaseInFinder() },
                    onExport: self.onExportDatabase,
                    onImport: self.onImportDatabase,
                    onCompact: { self.runCompact() }
                )
                
                DatabaseVaultContentsBento(
                    assets: snapshot.assets,
                    tokenSummary: snapshot.tokenSummary,
                    highlightedCategory: self.highlightedCategory,
                    isDark: self.isDark,
                    accent: self.accent,
                    onOpenSection: { kind in
                        self.openSection(kind)
                    }
                )
                
                DatabaseTokenAnalyticsCard(
                    summary: snapshot.tokenSummary,
                    selectedTab: self.$tokenTab,
                    isDark: self.isDark,
                    accent: self.accent
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task(id: self.refreshRevision) {
            self.reloadSnapshot()
        }
    }
    
    
    private func reloadSnapshot() {
        self.snapshot = self.database.inspectDatabaseSnapshot()
    }
    
    
    private func openSection(_ kind: DatabaseVaultSectionKind) {
        let items = self.database.inspectVaultItems(for: kind, limit: 40)
        withAnimation(.easeInOut(duration: 0.18)) {
            self.sectionItems = items
            self.activeSection = kind
        }
    }
    
    
    private func revealDatabaseInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([self.database.databaseURL])
    }
    
    
    private func copyDatabasePath(_ path: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(path, forType: .string)
        withAnimation(.easeOut(duration: 0.15)) {
            self.didCopyPath = true
        }
        Task {
            try? await Task.sleep(for: .seconds(1.8))
            await MainActor.run {
                withAnimation(.easeOut(duration: 0.2)) {
                    self.didCopyPath = false
                }
            }
        }
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
                isDark ? Color(red: 0.64, green: 0.50, blue: 0.95) : Color(red: 0.48, green: 0.36, blue: 0.84)
            case .memory:
                isDark ? Color(red: 0.30, green: 0.78, blue: 0.58) : Color(red: 0.16, green: 0.62, blue: 0.44)
            case .feedsAndBoards:
                isDark ? Color(red: 0.92, green: 0.66, blue: 0.34) : Color(red: 0.84, green: 0.54, blue: 0.16)
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
                HStack(alignment: .firstTextBaseline) {
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


// MARK: - 1. Spatial Vault Storage Hero Card

private struct DatabaseVaultHeroCard: View {
    
    let snapshot: DatabaseInspectionSnapshot
    @Binding var highlightedCategory: DatabaseCategoryKind?
    let isDark: Bool
    let compactStatusText: String?
    let didCopyPath: Bool
    let onCopyPath: () -> Void
    let onRevealInFinder: () -> Void
    let onExport: () -> Void
    let onImport: () -> Void
    let onCompact: () -> Void
    
    var body: some View {
        let totalEstimated = max(Int64(1), self.snapshot.categories.reduce(Int64(0)) { $0 + $1.bytes })
        let displayPath = CotLocalDatabase.abbreviatedDisplayPath(self.snapshot.filePath)
        
        DatabaseCardContainer(
            title: AppLanguage.text("本地数据金库", en: "Local Vault"),
            trailingTitle: "\(self.snapshot.totalRowCount.formatted()) \(AppLanguage.text("条数据", en: "items"))",
            isDark: self.isDark
        ) {
            VStack(alignment: .leading, spacing: 14) {
                // Top spatial split: radial storage ring + aligned category breakdown
                HStack(alignment: .center, spacing: 16) {
                    DatabaseStorageRingView(
                        categories: self.snapshot.categories,
                        totalBytes: self.snapshot.totalBytes,
                        highlightedCategory: self.highlightedCategory,
                        isDark: self.isDark
                    )
                    .frame(width: 92, height: 92)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(DatabaseFormatters.bytes(self.snapshot.totalBytes))
                                .font(.system(size: 22, weight: .bold, design: .rounded).monospacedDigit())
                                .foregroundStyle(.primary)
                            
                            Spacer(minLength: 4)
                            
                            if let compactStatusText = self.compactStatusText {
                                Text(compactStatusText)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(.secondary)
                                    .transition(.opacity)
                            }
                        }
                        
                        // Perfectly aligned category legend rows (zero truncation, zero orphan wrap)
                        VStack(spacing: 4.5) {
                            ForEach(self.snapshot.categories) { category in
                                let pct = Int((Double(category.bytes) / Double(totalEstimated) * 100).rounded())
                                let isActive = (self.highlightedCategory == category.kind)
                                HStack(spacing: 7) {
                                    Circle()
                                        .fill(DatabaseFormatters.categoryColor(category.kind, isDark: self.isDark))
                                        .frame(width: 7, height: 7)
                                    
                                    Text(category.kind.displayName)
                                        .font(.system(size: 11.5, weight: isActive ? .semibold : .regular))
                                        .foregroundStyle(isActive ? .primary : .secondary)
                                        .lineLimit(1)
                                    
                                    Spacer(minLength: 6)
                                    
                                    Text(DatabaseFormatters.bytes(category.bytes))
                                        .font(.system(size: 11, weight: .medium, design: .monospaced).monospacedDigit())
                                        .foregroundStyle(.primary.opacity(0.84))
                                        .frame(width: 60, alignment: .trailing)
                                    
                                    Text("\(pct)%")
                                        .font(.system(size: 10.5, design: .monospaced).monospacedDigit())
                                        .foregroundStyle(.secondary)
                                        .frame(width: 32, alignment: .trailing)
                                }
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(
                                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                                        .fill(isActive ? (self.isDark ? Color.white.opacity(0.06) : Color.black.opacity(0.035)) : Color.clear)
                                )
                                .onHover { hovering in
                                    self.highlightedCategory = hovering ? category.kind : (self.highlightedCategory == category.kind ? nil : self.highlightedCategory)
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                
                // Proportional segmented storage strip
                GeometryReader { geo in
                    let nonZero = self.snapshot.categories.filter { $0.bytes > 0 }
                    let spacing: CGFloat = nonZero.count > 1 ? 2.5 : 0
                    let usableWidth = max(0, geo.size.width - spacing * CGFloat(max(0, nonZero.count - 1)))
                    
                    HStack(spacing: spacing) {
                        if nonZero.isEmpty {
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(self.isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.06))
                        } else {
                            ForEach(nonZero) { category in
                                let fraction = CGFloat(category.bytes) / CGFloat(totalEstimated)
                                let dimmed = (self.highlightedCategory != nil && self.highlightedCategory != category.kind)
                                RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                                    .fill(DatabaseFormatters.categoryColor(category.kind, isDark: self.isDark).opacity(dimmed ? 0.30 : 0.92))
                                    .frame(width: max(8, usableWidth * fraction))
                                    .onHover { hovering in
                                        self.highlightedCategory = hovering ? category.kind : (self.highlightedCategory == category.kind ? nil : self.highlightedCategory)
                                    }
                            }
                        }
                    }
                }
                .frame(height: 8)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                
                // Overflow-safe file location strip
                HStack(spacing: 8) {
                    Image(systemName: "folder")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                    
                    Text(displayPath)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                        .help(self.snapshot.filePath)
                    
                    Button(action: self.onCopyPath) {
                        Image(systemName: self.didCopyPath ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(.secondary)
                            .frame(width: 22, height: 22)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .pointerStyle(.link)
                    .help(AppLanguage.text("复制路径", en: "Copy Path"))
                    
                    Button(AppLanguage.text("在访达中显示", en: "Reveal")) {
                        self.onRevealInFinder()
                    }
                    .controlSize(.small)
                    .fixedSize()
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(self.isDark ? Color.white.opacity(0.035) : Color.black.opacity(0.025))
                )
                
                Rectangle()
                    .fill(self.isDark ? Color.white.opacity(0.07) : Color.black.opacity(0.06))
                    .frame(height: 0.5)
                
                // Clean aligned action strip
                HStack(spacing: 8) {
                    Button(AppLanguage.text("导出迁移文件", en: "Export")) {
                        self.onExport()
                    }
                    .controlSize(.small)
                    
                    Button(AppLanguage.text("导入数据库", en: "Import")) {
                        self.onImport()
                    }
                    .controlSize(.small)
                    
                    Spacer()
                    
                    Button(AppLanguage.text("压缩整理", en: "Compact")) {
                        self.onCompact()
                    }
                    .controlSize(.small)
                }
            }
            .padding(14)
        }
    }
}


private struct DatabaseStorageRingView: View {
    
    let categories: [DatabaseStorageCategory]
    let totalBytes: Int64
    let highlightedCategory: DatabaseCategoryKind?
    let isDark: Bool
    
    var body: some View {
        let total = max(1.0, Double(self.categories.reduce(Int64(0)) { $0 + $1.bytes }))
        let nonZero = self.categories.filter { $0.bytes > 0 }
        
        ZStack {
            Canvas { context, size in
                let center = CGPoint(x: size.width * 0.5, y: size.height * 0.5)
                let radius = min(size.width, size.height) * 0.5 - 7
                let lineW: CGFloat = 10
                
                // Base track
                let trackRect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
                context.stroke(
                    Circle().path(in: trackRect),
                    with: .color(self.isDark ? Color.white.opacity(0.07) : Color.black.opacity(0.055)),
                    lineWidth: lineW
                )
                
                var startDeg = -90.0
                let gapDeg = nonZero.count > 1 ? 3.5 : 0.0
                for cat in nonZero {
                    let span = max(4.0, (Double(cat.bytes) / total) * 360.0)
                    let segStart = startDeg + gapDeg * 0.5
                    let segEnd = max(segStart + 2.0, startDeg + span - gapDeg * 0.5)
                    let isActive = (self.highlightedCategory == cat.kind)
                    let dimmed = (self.highlightedCategory != nil && !isActive)
                    
                    var arc = Path()
                    arc.addArc(
                        center: center,
                        radius: radius,
                        startAngle: .degrees(segStart),
                        endAngle: .degrees(segEnd),
                        clockwise: false
                    )
                    context.stroke(
                        arc,
                        with: .color(DatabaseFormatters.categoryColor(cat.kind, isDark: self.isDark).opacity(dimmed ? 0.28 : 0.94)),
                        style: StrokeStyle(lineWidth: isActive ? lineW + 2.0 : lineW, lineCap: .round)
                    )
                    startDeg += span
                }
            }
            
            VStack(spacing: 1) {
                Text(AppLanguage.text("占用", en: "Used"))
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(.secondary)
                Text(DatabaseFormatters.bytes(self.totalBytes))
                    .font(.system(size: 11.5, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .frame(width: 58)
        }
    }
}


// MARK: - 2. Imaginative Asymmetric Vault Contents Bento ("里面有什么")

private struct DatabaseVaultContentsBento: View {
    
    let assets: DatabaseAssetCounts
    let tokenSummary: DatabaseAITokenSummary
    let highlightedCategory: DatabaseCategoryKind?
    let isDark: Bool
    let accent: Color
    let onOpenSection: (DatabaseVaultSectionKind) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(AppLanguage.text("数据内容", en: "Vault Contents"))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
            
            // Row 1: Two visual hero content cards (Documents/Writing & Memories/Tasks)
            HStack(spacing: 10) {
                VaultDocumentsHeroTile(
                    assets: self.assets,
                    isHighlighted: self.highlightedCategory == .documents,
                    isDark: self.isDark,
                    onTap: { self.onOpenSection(.documents) }
                )
                
                VaultMemoryAndTasksHeroTile(
                    assets: self.assets,
                    isHighlighted: self.highlightedCategory == .memory,
                    isDark: self.isDark,
                    onOpenMemories: { self.onOpenSection(.memories) },
                    onOpenReminders: { self.onOpenSection(.reminders) }
                )
            }
            
            // Row 2: Three balanced interactive category cards
            HStack(spacing: 10) {
                VaultCompactFeatureTile(
                    icon: "bubble.left.and.bubble.right",
                    title: AppLanguage.text("AI 对话", en: "AI Chats"),
                    primaryValue: "\(self.assets.totalMessages)",
                    unit: AppLanguage.text("条", en: "msgs"),
                    meta: "\(self.assets.butlerSessions) \(AppLanguage.text("个会话", en: "sessions"))",
                    tint: DatabaseFormatters.categoryColor(.aiRecords, isDark: self.isDark),
                    isHighlighted: self.highlightedCategory == .aiRecords,
                    isDark: self.isDark,
                    onTap: { self.onOpenSection(.conversations) }
                )
                
                VaultCompactFeatureTile(
                    icon: "doc.text",
                    title: AppLanguage.text("周报归档", en: "Reports"),
                    primaryValue: "\(self.assets.weeklyReports)",
                    unit: AppLanguage.text("份", en: "saved"),
                    meta: "\(self.assets.writingDays) \(AppLanguage.text("活跃天", en: "days"))",
                    tint: DatabaseFormatters.categoryColor(.documents, isDark: self.isDark),
                    isHighlighted: self.highlightedCategory == .documents,
                    isDark: self.isDark,
                    onTap: { self.onOpenSection(.weeklyReports) }
                )
                
                VaultCompactFeatureTile(
                    icon: "bookmark",
                    title: AppLanguage.text("订阅关注", en: "Feeds"),
                    primaryValue: "\(self.assets.totalSubscriptions)",
                    unit: AppLanguage.text("项", en: "items"),
                    meta: "\(self.assets.watchlistStocks) \(AppLanguage.text("股", en: "stk")) · \(self.assets.podcasts) \(AppLanguage.text("播客", en: "pod"))",
                    tint: DatabaseFormatters.categoryColor(.feedsAndBoards, isDark: self.isDark),
                    isHighlighted: self.highlightedCategory == .feedsAndBoards,
                    isDark: self.isDark,
                    onTap: { self.onOpenSection(.subscriptions) }
                )
            }
        }
    }
}


private struct VaultDocumentsHeroTile: View {
    
    let assets: DatabaseAssetCounts
    let isHighlighted: Bool
    let isDark: Bool
    let onTap: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        let tint = DatabaseFormatters.categoryColor(.documents, isDark: self.isDark)
        let totalWritten = max(1, self.assets.totalTypedChars + self.assets.totalAICompletedChars)
        let typedFrac = CGFloat(self.assets.totalTypedChars) / CGFloat(totalWritten)
        let activeBorder = self.isHovered || self.isHighlighted
        let cardFill: Color = if self.isDark {
            Color.white.opacity(self.isHovered ? 0.075 : 0.055)
        } else {
            self.isHovered ? Color.black.opacity(0.015) : Color.white
        }
        let borderColor: Color = if activeBorder {
            self.isDark ? Color.white.opacity(0.18) : Color.black.opacity(0.14)
        } else {
            self.isDark ? Color.white.opacity(0.075) : Color.black.opacity(0.06)
        }
        let borderWidth: CGFloat = activeBorder ? 0.9 : 0.5
        
        Button(action: self.onTap) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center, spacing: 6) {
                    Image(systemName: "doc.richtext")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(tint)
                    Text(AppLanguage.text("创作文档", en: "Documents"))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary.opacity(self.isHovered ? 0.9 : 0.45))
                }
                
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(self.assets.activeDocuments)")
                        .font(.system(size: 24, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(.primary)
                    Text(AppLanguage.text("篇", en: "docs"))
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(DatabaseFormatters.compactCount(self.assets.totalDocumentChars)) \(AppLanguage.text("字", en: "ch"))")
                        .font(.system(size: 11.5, weight: .medium, design: .monospaced).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    GeometryReader { geo in
                        let w = max(24, geo.size.width)
                        let typedW = max(6, w * min(1, max(0.08, typedFrac)))
                        HStack(spacing: 2) {
                            RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                                .fill(tint.opacity(0.85))
                                .frame(width: typedW)
                            RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                                .fill(DatabaseFormatters.categoryColor(.memory, isDark: self.isDark).opacity(0.75))
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .frame(height: 5)
                    
                    HStack {
                        Text("\(AppLanguage.text("累计写作", en: "Typed")) \(DatabaseFormatters.compactCount(self.assets.totalTypedChars))")
                            .font(.system(size: 10.5).monospacedDigit())
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(self.assets.writingDays) \(AppLanguage.text("天", en: "d"))")
                            .font(.system(size: 10.5).monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(13)
            .frame(maxWidth: .infinity, minHeight: 114, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(cardFill))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(borderColor, lineWidth: borderWidth))
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .pointerStyle(.link)
        .onHover { self.isHovered = $0 }
    }
}


private struct VaultMemoryAndTasksHeroTile: View {
    
    let assets: DatabaseAssetCounts
    let isHighlighted: Bool
    let isDark: Bool
    let onOpenMemories: () -> Void
    let onOpenReminders: () -> Void
    
    @State private var isMemoryHovered = false
    @State private var isTaskHovered = false
    
    var body: some View {
        let memTint = DatabaseFormatters.categoryColor(.memory, isDark: self.isDark)
        let taskTint = DatabaseFormatters.categoryColor(.feedsAndBoards, isDark: self.isDark)
        let completedTasks = max(0, self.assets.remindersTotal - self.assets.remindersOpen)
        let taskProgress: Double = self.assets.remindersTotal > 0
            ? Double(completedTasks) / Double(self.assets.remindersTotal)
            : 1.0
        let activeBorder = self.isMemoryHovered || self.isTaskHovered || self.isHighlighted
        let cardFill: Color = self.isDark ? Color.white.opacity(0.055) : Color.white
        let borderColor: Color = if activeBorder {
            self.isDark ? Color.white.opacity(0.18) : Color.black.opacity(0.14)
        } else {
            self.isDark ? Color.white.opacity(0.075) : Color.black.opacity(0.06)
        }
        let borderWidth: CGFloat = activeBorder ? 0.9 : 0.5
        let hoverBg: Color = self.isDark ? Color.white.opacity(0.03) : Color.black.opacity(0.02)
        
        HStack(spacing: 0) {
            self.memoryPane(tint: memTint, hoverBg: hoverBg)
            
            Rectangle()
                .fill(self.isDark ? Color.white.opacity(0.07) : Color.black.opacity(0.06))
                .frame(width: 0.6)
                .padding(.vertical, 12)
            
            self.taskPane(tint: taskTint, completedTasks: completedTasks, taskProgress: taskProgress, hoverBg: hoverBg)
        }
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(cardFill))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(borderColor, lineWidth: borderWidth))
    }
    
    
    private func memoryPane(tint: Color, hoverBg: Color) -> some View {
        Button(action: self.onOpenMemories) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 5) {
                    Circle().fill(tint).frame(width: 6.5, height: 6.5)
                    Text(AppLanguage.text("长期记忆", en: "Memory"))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(.secondary.opacity(self.isMemoryHovered ? 0.9 : 0.4))
                }
                
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text("\(self.assets.kycMemories)")
                        .font(.system(size: 24, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(.primary)
                    Text(AppLanguage.text("条", en: ""))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                
                Spacer(minLength: 0)
                
                Text("\(self.assets.memoryJournals) \(AppLanguage.text("条演变日志", en: "logs"))")
                    .font(.system(size: 10.5).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(13)
            .frame(maxWidth: .infinity, minHeight: 114, alignment: .topLeading)
            .background(self.isMemoryHovered ? hoverBg : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointerStyle(.link)
        .onHover { self.isMemoryHovered = $0 }
    }
    
    
    private func taskPane(tint: Color, completedTasks: Int, taskProgress: Double, hoverBg: Color) -> some View {
        let trackColor: Color = self.isDark ? Color.white.opacity(0.09) : Color.black.opacity(0.07)
        return Button(action: self.onOpenReminders) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 5) {
                    Circle().fill(tint).frame(width: 6.5, height: 6.5)
                    Text(AppLanguage.text("待办", en: "Tasks"))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(.secondary.opacity(self.isTaskHovered ? 0.9 : 0.4))
                }
                
                HStack(alignment: .center, spacing: 10) {
                    HStack(alignment: .firstTextBaseline, spacing: 2.5) {
                        Text("\(self.assets.remindersOpen)")
                            .font(.system(size: 24, weight: .bold, design: .rounded).monospacedDigit())
                            .foregroundStyle(.primary)
                        Text(AppLanguage.text("项", en: ""))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    
                    Spacer(minLength: 0)
                    
                    ZStack {
                        Circle()
                            .stroke(trackColor, lineWidth: 3.5)
                        Circle()
                            .trim(from: 0, to: CGFloat(min(1, max(0.04, taskProgress))))
                            .stroke(tint, style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                    }
                    .frame(width: 24, height: 24)
                }
                
                Spacer(minLength: 0)
                
                Text("\(AppLanguage.text("已完成", en: "Done")) \(completedTasks)/\(self.assets.remindersTotal)")
                    .font(.system(size: 10.5).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(13)
            .frame(maxWidth: .infinity, minHeight: 114, alignment: .topLeading)
            .background(self.isTaskHovered ? hoverBg : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointerStyle(.link)
        .onHover { self.isTaskHovered = $0 }
    }
}


private struct VaultCompactFeatureTile: View {
    
    let icon: String
    let title: String
    let primaryValue: String
    let unit: String
    let meta: String
    let tint: Color
    let isHighlighted: Bool
    let isDark: Bool
    let onTap: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        let activeBorder = self.isHovered || self.isHighlighted
        let cardFill: Color = if self.isDark {
            Color.white.opacity(self.isHovered ? 0.075 : 0.055)
        } else {
            self.isHovered ? Color.black.opacity(0.015) : Color.white
        }
        let borderColor: Color = if activeBorder {
            self.isDark ? Color.white.opacity(0.18) : Color.black.opacity(0.14)
        } else {
            self.isDark ? Color.white.opacity(0.075) : Color.black.opacity(0.06)
        }
        let borderWidth: CGFloat = activeBorder ? 0.9 : 0.5
        
        Button(action: self.onTap) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 5) {
                    Image(systemName: self.icon)
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(self.tint)
                    Text(self.title)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer(minLength: 2)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(.secondary.opacity(self.isHovered ? 0.88 : 0.35))
                }
                
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(self.primaryValue)
                        .font(.system(size: 18, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(.primary)
                    Text(self.unit)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                
                Text(self.meta)
                    .font(.system(size: 10.5).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(cardFill))
            .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(borderColor, lineWidth: borderWidth))
            .contentShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        }
        .buttonStyle(.plain)
        .pointerStyle(.link)
        .onHover { self.isHovered = $0 }
    }
}


// MARK: - 3. Human-Readable Vault Content Browser

private struct DatabaseVaultDetailView: View {
    
    let section: DatabaseVaultSectionKind
    let items: [DatabaseVaultContentItem]
    let isDark: Bool
    let onSwitchSection: (DatabaseVaultSectionKind) -> Void
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
                
                Text(self.section.title)
                    .font(.system(size: 14, weight: .semibold))
                
                Spacer()
                
                Text("\(self.items.count) \(AppLanguage.text("项", en: "items"))")
                    .font(.system(size: 11.5).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            
            // Quick section switcher pills
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(DatabaseVaultSectionKind.allCases) { kind in
                        let selected = (kind == self.section)
                        Button {
                            self.onSwitchSection(kind)
                        } label: {
                            Text(kind.title)
                                .font(.system(size: 11.5, weight: selected ? .semibold : .regular))
                                .foregroundStyle(selected ? .primary : .secondary)
                                .padding(.horizontal, 10)
                                .frame(height: 25)
                                .background(
                                    Capsule(style: .continuous)
                                        .fill(selected
                                              ? (self.isDark ? Color.white.opacity(0.14) : Color.black.opacity(0.08))
                                              : (self.isDark ? Color.white.opacity(0.04) : Color.black.opacity(0.025)))
                                )
                        }
                        .buttonStyle(.plain)
                        .pointerStyle(.link)
                    }
                }
            }
            
            DatabaseCardContainer(title: nil, isDark: self.isDark) {
                if self.items.isEmpty {
                    HStack {
                        Text(AppLanguage.text("暂无记录", en: "No items yet"))
                            .font(.system(size: 12.5))
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(16)
                } else {
                    ForEach(Array(self.items.enumerated()), id: \.element.id) { idx, item in
                        if idx > 0 {
                            Rectangle()
                                .fill(self.isDark ? Color.white.opacity(0.06) : Color.black.opacity(0.05))
                                .frame(height: 0.5)
                                .padding(.leading, 14)
                        }
                        
                        HStack(alignment: .center, spacing: 10) {
                            Circle()
                                .fill(DatabaseFormatters.categoryColor(self.section.categoryKind, isDark: self.isDark))
                                .frame(width: 6, height: 6)
                            
                            Text(item.title)
                                .font(.system(size: 12.5, weight: .medium))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                            
                            if let badge = item.badge, !badge.isEmpty {
                                Text(badge)
                                    .font(.system(size: 10.5, weight: .medium))
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 7)
                                    .frame(height: 20)
                                    .background(
                                        Capsule(style: .continuous)
                                            .fill(self.isDark ? Color.white.opacity(0.07) : Color.black.opacity(0.045))
                                    )
                                    .fixedSize()
                            }
                            
                            if !item.metric.isEmpty {
                                Text(item.metric)
                                    .font(.system(size: 11, design: .monospaced).monospacedDigit())
                                    .foregroundStyle(.secondary)
                                    .fixedSize()
                            }
                            
                            if let detail = item.detail, !detail.isEmpty {
                                Text(detail)
                                    .font(.system(size: 10.5, design: .monospaced).monospacedDigit())
                                    .foregroundStyle(.secondary.opacity(0.8))
                                    .frame(width: 72, alignment: .trailing)
                            }
                        }
                        .padding(.horizontal, 14)
                        .frame(height: 36)
                    }
                }
            }
        }
    }
}


// MARK: - 4. AI Token Analytics Card

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
            
            if !self.summary.dailyTrend.isEmpty {
                self.dailyTrendStrip
            }
            
            HStack(alignment: .top, spacing: 16) {
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
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(self.accent.opacity(0.78))
                        .frame(maxWidth: .infinity)
                        .frame(height: h)
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
                        .fill(tint.opacity(0.78))
                        .frame(width: max(4, geo.size.width * min(1, max(0, ratio))))
                }
            }
            .frame(height: 4.5)
        }
    }
}
