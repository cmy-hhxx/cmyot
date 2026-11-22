//
//  WeeklyReportCenterView.swift
//
//  CotEditor
//  https://coteditor.com
//
//  Created by 1024jp on 2026-11-17.
//
//  ---------------------------------------------------------------------------
//
//  © 2026 1024jp
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
import Combine
import SwiftUI
import UniformTypeIdentifiers

/// Controls the dedicated 周报中心 (Weekly Report Center) window.
@MainActor final class WeeklyReportWindowController: NSWindowController {
    
    static let shared = WeeklyReportWindowController()
    
    enum InitialMode: Sendable {
        case history
        case generator
    }
    
    private let state = WeeklyReportCenterState()
    
    private init() {
        
        let rootView = WeeklyReportCenterView(state: self.state)
        let hostingController = NSHostingController(rootView: rootView)
        
        let window = NSWindow(contentViewController: hostingController)
        window.title = String(localized: "ai.weeklyCenter.windowTitle", defaultValue: "周报中心", table: "AI")
        window.setContentSize(NSSize(width: 980, height: 660))
        window.minSize = NSSize(width: 760, height: 500)
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.titlebarAppearsTransparent = false
        window.isReleasedWhenClosed = false
        window.center()
        
        super.init(window: window)
    }
    
    
    @available(*, unavailable)
    required init?(coder: NSCoder) {
        
        fatalError("init(coder:) has not been implemented")
    }
    
    
    /// Brings the Weekly Report Center forward inside the current document window when available
    /// (falling back to the standalone window only when no document window is open).
    func showWindow(mode: InitialMode = .history, selectingReportID: String? = nil) {
        
        if let activeWC = (NSApp.mainWindow?.windowController as? DocumentWindowController)
            ?? NSApp.orderedWindows.compactMap({ $0.windowController as? DocumentWindowController }).first,
           let contentVC = activeWC.workspaceContentViewController
        {
            contentVC.showInWindowCenter(.weeklyReports, weeklyMode: mode, selectingReportID: selectingReportID)
            activeWC.window?.makeKeyAndOrderFront(nil)
            return
        }
        
        CotLocalDatabase.shared.reloadWeeklyReports()
        self.state.isGeneratorActive = (mode == .generator)
        self.state.rebuildGroups()
        if let selectingReportID {
            self.state.selectedReportID = selectingReportID
        } else if self.state.selectedReportID == nil {
            self.state.selectedReportID = CotLocalDatabase.shared.weeklyReports.first?.id
        }
        if mode == .generator {
            self.state.refreshOpenSources()
        }
        
        self.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    
    /// Opens a stored historical weekly report cleanly in the active window's Markdown tab (or a standalone window if needed).
    func openReportInEditor(_ report: StoredWeeklyReport) {
        
        if let activeWC = (NSApp.mainWindow?.windowController as? DocumentWindowController)
            ?? NSApp.orderedWindows.compactMap({ $0.windowController as? DocumentWindowController }).first,
           let docVC = activeWC.documentViewController
        {
            activeWC.workspaceContentViewController?.hideInWindowCenter()
            docVC.openStoredWeeklyReport(report)
            activeWC.window?.makeKeyAndOrderFront(nil)
            return
        }
        
        guard let controller = NSDocumentController.shared as? DocumentController else { return }
        
        // Reuse if already open
        for case let existing as Document in controller.documents where existing.databaseDocumentID == "weekly:\(report.id)" {
            existing.makeWindowControllers()
            existing.showWindows()
            return
        }
        
        do {
            let document = try controller.openUntitledDocument(content: report.content, title: report.title, display: true)
            document.databaseDocumentID = "weekly:\(report.id)"
            document.setSyntax(name: SyntaxName.markdown)
            document.updateChangeCount(.changeCleared)
        } catch {
            NSApp.presentError(error)
        }
    }
}


@MainActor @Observable final class WeeklyReportCenterState {
    
    struct OpenSourceItem: Identifiable {
        let id: String
        let title: String
        let content: String
        var isSelected: Bool
    }
    
    struct YearMonthGroup: Identifiable {
        let month: String
        let reports: [StoredWeeklyReport]
        var id: String { self.month }
    }
    
    var selectedReportID: String?
    var searchText: String = "" {
        didSet {
            if oldValue != self.searchText {
                self.rebuildGroups()
            }
        }
    }
    var isGeneratorActive: Bool = false
    var collapsedMonths: Set<String> = []
    var groups: [YearMonthGroup] = []
    var flatReports: [StoredWeeklyReport] = []
    
    // Generator fields
    var authorName: String = CotLocalDatabase.shared.weeklyReportAuthor
    var customNotes: String = ""
    var fragmentsText: String = CotLocalDatabase.shared.string(forKey: CotLocalDatabase.ConfigKey.weeklyReportFragments)
    var openSources: [OpenSourceItem] = []
    var generatedOutput: String = ""
    var isGenerating: Bool = false
    var generationError: String?
    
    func rebuildGroups() {
        
        let allReports = CotLocalDatabase.shared.weeklyReports
        let query = self.searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let filtered = if query.isEmpty {
            allReports
        } else {
            allReports.filter { report in
                report.title.lowercased().contains(query)
                    || report.periodLabel.lowercased().contains(query)
                    || report.yearMonth.lowercased().contains(query)
                    || report.content.prefix(2_000).lowercased().contains(query)
            }
        }
        
        let dict = Dictionary(grouping: filtered, by: \.yearMonth)
        let builtGroups = dict.keys.sorted(by: >).map { month in
            let sorted = (dict[month] ?? []).sorted { lhs, rhs in
                if lhs.periodLabel != rhs.periodLabel {
                    return lhs.periodLabel > rhs.periodLabel
                }
                return lhs.updatedAt > rhs.updatedAt
            }
            return YearMonthGroup(month: month, reports: sorted)
        }
        self.groups = builtGroups
        self.flatReports = builtGroups.flatMap(\.reports)
        
        if let selectedReportID, self.flatReports.contains(where: { $0.id == selectedReportID }) {
            return
        }
        self.selectedReportID = self.flatReports.first?.id ?? allReports.first?.id
    }
    
    
    func refreshOpenSources() {
        
        self.authorName = CotLocalDatabase.shared.weeklyReportAuthor
        self.fragmentsText = CotLocalDatabase.shared.string(forKey: CotLocalDatabase.ConfigKey.weeklyReportFragments)
        
        var items: [OpenSourceItem] = []
        var seen = Set<ObjectIdentifier>()
        for window in NSApp.orderedWindows {
            guard let docVC = (window.windowController as? DocumentWindowController)?.documentViewController else { continue }
            for pane in docVC.editorViewControllers {
                for tab in pane.tabs {
                    let doc = tab.document
                    let objID = ObjectIdentifier(doc)
                    guard seen.insert(objID).inserted else { continue }
                    let text = doc.textStorage.string.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !text.isEmpty else { continue }
                    let isHistoricWeekly = doc.databaseDocumentID.hasPrefix("weekly:")
                    items.append(OpenSourceItem(
                        id: "\(objID.hashValue)",
                        title: doc.displayName,
                        content: doc.textStorage.string,
                        isSelected: !isHistoricWeekly
                    ))
                }
            }
        }
        self.openSources = items
    }
}


struct WeeklyReportCenterView: View {
    
    @Bindable var state: WeeklyReportCenterState
    var onOpenReport: ((StoredWeeklyReport) -> Void)?
    var onDismiss: (() -> Void)?
    
    @State private var db = CotLocalDatabase.shared
    @State private var selectedMonthFolder: String?
    @State private var isEditingSelected = false
    @State private var editingReportID: String?
    @State private var editingDraft = ""
    @State private var isRenamingSelected = false
    @State private var renameDraft = ""
    @State private var copiedFlag = false
    @State private var toastMessage: String?
    @State private var toastTask: Task<Void, Never>?
    
    var body: some View {
        
        let groups = self.state.groups
        let flatReports = self.state.flatReports
        let activeReport = self.selectedReport(in: flatReports)
        
        ZStack(alignment: .bottom) {
            HStack(spacing: 0) {
                self.sidebar(groups: groups, flatReports: flatReports, activeReport: activeReport)
                    .frame(width: 356)
                
                Rectangle()
                    .fill(Color.primary.opacity(0.07))
                    .frame(width: 1)
                
                Group {
                    if self.state.isGeneratorActive {
                        self.generatorView
                    } else if let selected = activeReport {
                        self.detailView(for: selected)
                    } else {
                        self.emptyDetailView
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            
            if let toastMessage {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.green)
                    Text(toastMessage)
                        .font(.system(size: 12, weight: .medium))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(.regularMaterial, in: Capsule())
                .overlay(Capsule().stroke(Color.primary.opacity(0.08), lineWidth: 1))
                .padding(.bottom, 16)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
        .onAppear {
            self.state.rebuildGroups()
            self.state.refreshOpenSources()
        }
        .onReceive(
            NotificationCenter.default.publisher(for: CotLocalDatabase.weeklyReportsDidChangeNotification)
                .receive(on: RunLoop.main)
        ) { _ in
            self.state.rebuildGroups()
        }
        .onChange(of: self.state.searchText) { _, _ in
            self.state.rebuildGroups()
        }
        .onChange(of: self.state.selectedReportID) { _, newID in
            if self.editingReportID != newID {
                self.isEditingSelected = false
                self.editingReportID = nil
            }
            self.isRenamingSelected = false
        }
        .onChange(of: self.state.isGeneratorActive) { _, isGen in
            if isGen {
                self.isEditingSelected = false
                self.editingReportID = nil
                self.isRenamingSelected = false
            }
        }
    }
    
    
    private func selectedReport(in orderedReports: [StoredWeeklyReport]) -> StoredWeeklyReport? {
        
        guard let id = self.state.selectedReportID else { return orderedReports.first }
        return orderedReports.first(where: { $0.id == id })
            ?? self.db.weeklyReports.first(where: { $0.id == id })
            ?? orderedReports.first
    }
    
    
    // MARK: Sidebar
    
    private func sidebar(
        groups: [WeeklyReportCenterState.YearMonthGroup],
        flatReports: [StoredWeeklyReport],
        activeReport: StoredWeeklyReport?
    ) -> some View {
        
        let trimmedQuery = self.state.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let activeMonth = self.selectedMonthFolder.flatMap { month in
            groups.contains(where: { $0.month == month }) ? month : nil
        }
        let visibleGroups = (activeMonth == nil || !trimmedQuery.isEmpty)
            ? groups
            : groups.filter { $0.month == activeMonth }
        
        return VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center, spacing: 8) {
                    Image(systemName: "calendar.badge.clock")
                        .font(.system(size: 14, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 20, height: 20)
                    
                    Text("周报中心")
                        .font(.system(size: 14, weight: .semibold))
                    
                    Text("\(self.db.weeklyReports.count)")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Color.primary.opacity(0.06), in: Capsule())
                    
                    Spacer()
                    
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
                            .frame(height: 28)
                            .background(Color.primary.opacity(0.06), in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .pointerStyle(.link)
                        .help("返回编辑器 (Esc)")
                    }
                }
                .frame(height: 28)
                
                HStack(spacing: 6) {
                    Button {
                        self.createWeeklyReport(weekOffset: 0)
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "doc.badge.plus")
                                .font(.system(size: 11.5, weight: .semibold))
                            Text("新建本周")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 11)
                        .frame(height: 30)
                        .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .pointerStyle(.link)
                    .help("按标准格式新建当周工作周报（已存在则直接定位编辑）")
                    
                    Menu {
                        let thisWeek = CotLocalDatabase.weekPeriodInfo(weekOffset: 0)
                        let lastWeek = CotLocalDatabase.weekPeriodInfo(weekOffset: -1)
                        let nextWeek = CotLocalDatabase.weekPeriodInfo(weekOffset: 1)
                        Button("本周（\(thisWeek.displayRange)）") {
                            self.createWeeklyReport(weekOffset: 0)
                        }
                        Button("上周（\(lastWeek.displayRange)）") {
                            self.createWeeklyReport(weekOffset: -1)
                        }
                        Button("下周（\(nextWeek.displayRange)）") {
                            self.createWeeklyReport(weekOffset: 1)
                        }
                    } label: {
                        HStack(alignment: .center, spacing: 4) {
                            Image(systemName: "calendar")
                                .font(.system(size: 11.5, weight: .medium))
                            Image(systemName: "chevron.down")
                                .font(.system(size: 7.5, weight: .bold))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 9)
                        .frame(height: 30)
                        .background(Color.primary.opacity(0.065), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .contentShape(Rectangle())
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .pointerStyle(.link)
                    .help("选择周期新建周报")
                    
                    Button {
                        self.state.isGeneratorActive = true
                        self.state.refreshOpenSources()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 11, weight: .semibold))
                            Text("AI 生成")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 10)
                        .frame(height: 30)
                        .background(
                            self.state.isGeneratorActive
                                ? Color.accentColor.opacity(0.18)
                                : Color.primary.opacity(0.065),
                            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .pointerStyle(.link)
                    .help("使用 AI 汇总本周工作并生成周报")
                    
                    Button {
                        self.runImportPanel()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "square.and.arrow.down")
                                .font(.system(size: 11, weight: .medium))
                            Text("导入")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 10)
                        .frame(height: 30)
                        .background(Color.primary.opacity(0.065), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .pointerStyle(.link)
                    .help("从 .zip 压缩包、文件夹或 .md 文件导入历史周报")
                    
                    Spacer(minLength: 0)
                }
                
                HStack(spacing: 7) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.tertiary)
                    
                    TextField("搜索周报周期或内容…", text: self.$state.searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                    
                    if !self.state.searchText.isEmpty {
                        Button {
                            self.state.searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(.tertiary)
                        }
                        .buttonStyle(.plain)
                        .pointerStyle(.link)
                    }
                }
                .padding(.horizontal, 11)
                .frame(height: 32)
                .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(Color.primary.opacity(0.07), lineWidth: 1))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            
            Rectangle()
                .fill(Color.primary.opacity(0.06))
                .frame(height: 1)
            
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if trimmedQuery.isEmpty && !groups.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 6) {
                                Text("月份文件夹")
                                    .font(.system(size: 11.5, weight: .semibold))
                                    .foregroundStyle(.secondary)
                                
                                Spacer()
                                
                                if activeMonth != nil {
                                    Button {
                                        withAnimation(.spring(response: 0.36, dampingFraction: 0.78)) {
                                            self.selectedMonthFolder = nil
                                        }
                                    } label: {
                                        Text("显示全部")
                                            .font(.system(size: 11, weight: .medium))
                                            .foregroundStyle(Color.accentColor)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 3)
                                            .background(Color.accentColor.opacity(0.10), in: Capsule())
                                    }
                                    .buttonStyle(.plain)
                                    .pointerStyle(.link)
                                }
                            }
                            
                            let columns = [
                                GridItem(.flexible(), spacing: 12),
                                GridItem(.flexible(), spacing: 12),
                            ]
                            LazyVGrid(columns: columns, spacing: 14) {
                                GlassFolderCardView(
                                    title: "全部周报",
                                    count: flatReports.count,
                                    theme: .aurora,
                                    sheets: self.folderSheets(for: flatReports),
                                    isSelected: activeMonth == nil,
                                    onSelect: {
                                        withAnimation(.spring(response: 0.36, dampingFraction: 0.78)) {
                                            self.selectedMonthFolder = nil
                                        }
                                    },
                                    onAdd: {
                                        self.createWeeklyReport(weekOffset: 0)
                                    }
                                )
                                
                                ForEach(Array(groups.enumerated()), id: \.element.id) { idx, group in
                                    GlassFolderCardView(
                                        title: Self.formatYearMonthTitle(group.month),
                                        count: group.reports.count,
                                        theme: GlassFolderTheme.rotatingTheme(forIndex: idx + 1),
                                        sheets: self.folderSheets(for: group.reports),
                                        isSelected: activeMonth == group.month,
                                        onSelect: {
                                            withAnimation(.spring(response: 0.36, dampingFraction: 0.78)) {
                                                self.selectedMonthFolder = (self.selectedMonthFolder == group.month) ? nil : group.month
                                            }
                                            self.state.isGeneratorActive = false
                                            if let currentID = self.state.selectedReportID,
                                               !group.reports.contains(where: { $0.id == currentID }),
                                               let first = group.reports.first
                                            {
                                                self.state.selectedReportID = first.id
                                            }
                                        },
                                        onAdd: {
                                            self.createWeeklyReport(weekOffset: 0)
                                        }
                                    )
                                }
                            }
                        }
                    }
                    
                    let currentWeekPeriod = CotLocalDatabase.weekPeriodInfo().periodLabel
                    if visibleGroups.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "calendar.badge.exclamationmark")
                                .font(.system(size: 24))
                                .foregroundStyle(.tertiary)
                            Text(trimmedQuery.isEmpty ? "暂无周报记录" : "未找到匹配的周报")
                                .font(.system(size: 12.5, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 36)
                    } else {
                        LazyVStack(alignment: .leading, spacing: 8) {
                            ForEach(visibleGroups) { group in
                                HStack(spacing: 6) {
                                    Text(Self.formatYearMonthTitle(group.month))
                                        .font(.system(size: 11.5, weight: .semibold))
                                        .foregroundStyle(.secondary)
                                    
                                    Spacer()
                                    
                                    Text("\(group.reports.count) 篇")
                                        .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                                        .foregroundStyle(.tertiary)
                                }
                                .padding(.horizontal, 4)
                                .padding(.top, 4)
                                
                                ForEach(group.reports) { report in
                                    WeeklyReportSidebarRow(
                                        report: report,
                                        isCurrentWeek: report.periodLabel == currentWeekPeriod,
                                        dateRangeLabel: Self.readablePeriodRange(report.periodLabel),
                                        isSelected: !self.state.isGeneratorActive && activeReport?.id == report.id,
                                        onSelect: {
                                            self.isEditingSelected = false
                                            self.editingReportID = nil
                                            self.isRenamingSelected = false
                                            self.state.isGeneratorActive = false
                                            self.state.selectedReportID = report.id
                                        },
                                        onOpen: {
                                            self.open(report: report)
                                        },
                                        onRename: {
                                            self.state.isGeneratorActive = false
                                            self.state.selectedReportID = report.id
                                            self.renameDraft = report.title
                                            self.isRenamingSelected = true
                                        },
                                        onDelete: {
                                            self.delete(report: report, in: flatReports)
                                        }
                                    )
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.45))
    }
    
    
    private func folderSheets(for reports: [StoredWeeklyReport]) -> [GlassFolderSheetItem] {
        
        reports.prefix(4).map { report in
            GlassFolderSheetItem(
                id: report.id,
                title: report.periodLabel,
                meta: report.title,
                accentHex: "#5B8DEF"
            )
        }
    }
    
    
    // MARK: Detail Viewer / Editor
    
    private func detailView(for report: StoredWeeklyReport) -> some View {
        
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 10) {
                if self.isRenamingSelected {
                    TextField("周报标题", text: self.$renameDraft)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 260)
                        .onSubmit {
                            self.commitReportRename(report)
                        }
                    Button("确定") {
                        self.commitReportRename(report)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .pointerStyle(.link)
                    Button("取消") {
                        self.isRenamingSelected = false
                    }
                    .controlSize(.small)
                    .pointerStyle(.link)
                } else {
                    Text(report.title)
                        .font(.system(size: 15.5, weight: .semibold))
                        .lineLimit(1)
                    
                    Button {
                        self.renameDraft = report.title
                        self.isRenamingSelected = true
                    } label: {
                        Image(systemName: "pencil")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                            .frame(width: 22, height: 22)
                            .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 5))
                    }
                    .buttonStyle(.plain)
                    .pointerStyle(.link)
                    .help("重命名周报")
                    
                    Text(report.periodLabel)
                        .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2.5)
                        .background(Color.primary.opacity(0.05), in: Capsule())
                }
                
                Spacer(minLength: 8)
                
                HStack(spacing: 8) {
                    if self.isEditingSelected {
                        Button("保存") {
                            self.db.saveWeeklyReport(
                                id: report.id,
                                periodLabel: report.periodLabel,
                                yearMonth: report.yearMonth,
                                title: report.title,
                                content: self.editingDraft,
                                sourcePath: report.sourcePath,
                                isEnhanced: false
                            )
                            self.state.rebuildGroups()
                            self.isEditingSelected = false
                            self.editingReportID = nil
                            self.showToast("已保存 \(report.periodLabel)")
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .pointerStyle(.link)
                        
                        Button("取消") {
                            self.isEditingSelected = false
                            self.editingReportID = nil
                        }
                        .controlSize(.small)
                        .pointerStyle(.link)
                    } else {
                        Button {
                            self.editingDraft = report.content
                            self.editingReportID = report.id
                            self.isEditingSelected = true
                        } label: {
                            Label("编辑", systemImage: "square.and.pencil")
                        }
                        .controlSize(.small)
                        .pointerStyle(.link)
                    }
                    
                    Button {
                        let pboard = NSPasteboard.general
                        pboard.clearContents()
                        pboard.setString(report.content, forType: .string)
                        self.copiedFlag = true
                        self.showToast("已拷贝「\(report.periodLabel)」")
                        Task {
                            try? await Task.sleep(for: .seconds(1.5))
                            self.copiedFlag = false
                        }
                    } label: {
                        Label(self.copiedFlag ? "已拷贝" : "拷贝", systemImage: self.copiedFlag ? "checkmark" : "doc.on.doc")
                    }
                    .controlSize(.small)
                    .pointerStyle(.link)
                    
                    Button {
                        self.open(report: report)
                    } label: {
                        Label("在编辑器打开", systemImage: "arrow.up.right.square")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .pointerStyle(.link)
                }
            }
            .padding(.horizontal, 24)
            .frame(height: 52)
            
            Rectangle()
                .fill(Color.primary.opacity(0.06))
                .frame(height: 1)
            
            if self.isEditingSelected {
                TextEditor(text: self.$editingDraft)
                    .font(.system(size: 13, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                    .background(Color(nsColor: .textBackgroundColor))
            } else {
                let preview = report.content.count > 12_000
                    ? String(report.content.prefix(12_000)) + "\n\n……（仅预览前 12,000 字，点击右上角「在编辑器打开」查看完整内容）"
                    : report.content
                CenterPreviewTextView(text: preview)
            }
        }
    }
    
    
    private var emptyDetailView: some View {
        
        VStack(spacing: 12) {
            Image(systemName: "calendar.badge.plus")
                .font(.system(size: 32, weight: .light))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.tertiary)
            Text("还没有历史周报")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
            Text("点击左上角「新建周报」按标准格式创建本周周报，或点「导入」批量导入历史周报。")
                .font(.caption)
                .foregroundStyle(.tertiary)
            HStack(spacing: 8) {
                Button {
                    self.createWeeklyReport(weekOffset: 0)
                } label: {
                    Label("新建本周周报", systemImage: "doc.badge.plus")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .pointerStyle(.link)
                
                Button("导入历史周报 (.zip / 文件夹)…") {
                    self.runImportPanel()
                }
                .controlSize(.small)
                .pointerStyle(.link)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor))
    }
    
    
    // MARK: Weekly Report Generator Workbench
    
    private var generatorView: some View {
        
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 10) {
                Text("写本周周报")
                    .font(.system(size: 15.5, weight: .semibold))
                
                Text("自动对齐最近 2 篇历史周报风格")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                
                Spacer(minLength: 8)
                
                Button("返回历史周报") {
                    self.state.isGeneratorActive = false
                }
                .controlSize(.small)
                .pointerStyle(.link)
            }
            .padding(.horizontal, 24)
            .frame(height: 52)
            
            Rectangle()
                .fill(Color.primary.opacity(0.06))
                .frame(height: 1)
            
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .center, spacing: 12) {
                        Text("署名")
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundStyle(.secondary)
                        TextField("陈明扬", text: self.$state.authorName)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 140)
                            .onChange(of: self.state.authorName) { _, newVal in
                                let trimmed = newVal.trimmingCharacters(in: .whitespacesAndNewlines)
                                if !trimmed.isEmpty {
                                    self.db.weeklyReportAuthor = trimmed
                                }
                            }
                        
                        Text("默认周期：\(AIService.currentWeekPeriodLabel())")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(.secondary)
                        
                        Spacer()
                        
                        let refs = self.db.styleReferenceWeeklyReports(limit: 2)
                        if !refs.isEmpty {
                            Text("已参考范例：\(refs.map(\.periodLabel).joined(separator: "、"))")
                                .font(.system(size: 11.5))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    
                    if !self.state.openSources.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("从当前打开的编辑器窗口采集素材（勾选纳入）")
                                    .font(.system(size: 12.5, weight: .semibold))
                                Spacer()
                                Button("刷新列表") {
                                    self.state.refreshOpenSources()
                                }
                                .controlSize(.mini)
                                .pointerStyle(.link)
                            }
                            
                            ForEach(self.$state.openSources) { $source in
                                Toggle(isOn: $source.isSelected) {
                                    Text("\(source.title)（\(source.content.count) 字）")
                                        .font(.system(size: 12))
                                }
                            }
                        }
                        .padding(12)
                        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.06), lineWidth: 1))
                    }
                    
                    VStack(alignment: .leading, spacing: 6) {
                        Text("本周补充记录 / 做完的事情 / 遇到的问题")
                            .font(.system(size: 12.5, weight: .semibold))
                        TextEditor(text: self.$state.customNotes)
                            .font(.system(size: 12.5))
                            .scrollContentBackground(.hidden)
                            .padding(8)
                            .frame(height: 112)
                            .background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.08), lineWidth: 1))
                    }
                    
                    if !self.state.fragmentsText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("已随手记入的周报素材片段（会一并合并）")
                                    .font(.system(size: 12, weight: .medium))
                                Spacer()
                                Button("清空素材缓存") {
                                    self.db.clearWeeklyReportFragments()
                                    self.state.fragmentsText = ""
                                }
                                .controlSize(.mini)
                                .pointerStyle(.link)
                            }
                            TextEditor(text: self.$state.fragmentsText)
                                .font(.system(size: 11.5))
                                .scrollContentBackground(.hidden)
                                .padding(8)
                                .frame(height: 76)
                                .background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 8))
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.08), lineWidth: 1))
                        }
                    }
                    
                    HStack(spacing: 10) {
                        Button {
                            self.runWeeklyReportGeneration()
                        } label: {
                            if self.state.isGenerating {
                                HStack(spacing: 6) {
                                    ProgressView().controlSize(.small)
                                    Text("正在生成…")
                                }
                            } else {
                                Label("AI 一键生成本周周报", systemImage: "sparkles")
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .pointerStyle(.link)
                        .disabled(self.state.isGenerating)
                        
                        if !self.state.generatedOutput.isEmpty {
                            Button("存入周报库并在编辑器打开") {
                                let saved = self.db.saveGeneratedWeeklyReport(content: self.state.generatedOutput)
                                self.state.rebuildGroups()
                                self.state.selectedReportID = saved.id
                                self.state.isGeneratorActive = false
                                self.open(report: saved)
                            }
                            .pointerStyle(.link)
                            
                            Button("只存周报库") {
                                let saved = self.db.saveGeneratedWeeklyReport(content: self.state.generatedOutput)
                                self.state.rebuildGroups()
                                self.showToast("已存周报：\(saved.periodLabel)")
                            }
                            .pointerStyle(.link)
                        }
                    }
                    
                    if let error = self.state.generationError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                    
                    if !self.state.generatedOutput.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("生成结果预览（可直接微调后存入周报库）")
                                .font(.system(size: 12.5, weight: .semibold))
                            TextEditor(text: self.$state.generatedOutput)
                                .font(.system(size: 13))
                                .scrollContentBackground(.hidden)
                                .padding(8)
                                .frame(minHeight: 240)
                                .background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 8))
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.accentColor.opacity(0.35), lineWidth: 1))
                        }
                    }
                }
                .padding(24)
            }
            .background(Color(nsColor: .textBackgroundColor))
        }
    }
    
    
    // MARK: Actions
    
    private func createWeeklyReport(weekOffset: Int) {
        
        let result = self.db.createWeeklyReport(weekOffset: weekOffset, includeSavedFragments: true)
        self.state.collapsedMonths.remove(result.report.yearMonth)
        self.state.searchText = ""
        if self.selectedMonthFolder != nil && self.selectedMonthFolder != result.report.yearMonth {
            self.selectedMonthFolder = result.report.yearMonth
        }
        self.state.rebuildGroups()
        self.state.isGeneratorActive = false
        self.editingReportID = result.report.id
        self.state.selectedReportID = result.report.id
        self.isRenamingSelected = false
        self.editingDraft = result.report.content
        self.isEditingSelected = true
        
        if result.alreadyExisted {
            self.showToast("本周报「\(result.report.periodLabel)」已存在，已定位到编辑视图")
        } else {
            self.showToast("已按格式新建周报「\(result.report.periodLabel)」")
        }
    }
    
    
    private func commitReportRename(_ report: StoredWeeklyReport) {
        
        let trimmed = self.renameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            self.isRenamingSelected = false
            return
        }
        self.db.renameWeeklyReport(id: report.id, newTitle: trimmed)
        self.state.rebuildGroups()
        self.isRenamingSelected = false
        self.showToast("已重命名为「\(trimmed)」")
    }
    
    
    private static func formatYearMonthTitle(_ yearMonth: String) -> String {
        
        guard yearMonth.count == 6,
              let year = Int(yearMonth.prefix(4)),
              let month = Int(yearMonth.suffix(2))
        else { return yearMonth }
        return "\(year)年\(month)月"
    }
    
    
    private static func readablePeriodRange(_ periodLabel: String) -> String? {
        
        let parts = periodLabel.split(separator: "-")
        guard parts.count == 2, parts[0].count == 8, parts[1].count == 4 else { return nil }
        let startM = parts[0].dropFirst(4).prefix(2)
        let startD = parts[0].suffix(2)
        let endM = parts[1].prefix(2)
        let endD = parts[1].suffix(2)
        return "\(startM)/\(startD) - \(endM)/\(endD)"
    }
    
    
    private func open(report: StoredWeeklyReport) {
        
        if let onOpenReport = self.onOpenReport {
            onOpenReport(report)
        } else {
            WeeklyReportWindowController.shared.openReportInEditor(report)
        }
    }
    
    
    private func delete(report: StoredWeeklyReport, in list: [StoredWeeklyReport]) {
        
        if let idx = list.firstIndex(where: { $0.id == report.id }) {
            let nextReport = list.indices.contains(idx + 1) ? list[idx + 1] : (idx > 0 ? list[idx - 1] : nil)
            self.state.selectedReportID = nextReport?.id
        }
        
        self.db.deleteWeeklyReport(id: report.id)
        self.state.rebuildGroups()
        self.isEditingSelected = false
        self.editingReportID = nil
        self.showToast("已移除 \(report.periodLabel)")
    }
    
    
    private func showToast(_ message: String) {
        
        self.toastTask?.cancel()
        withAnimation(.easeOut(duration: 0.15)) {
            self.toastMessage = message
        }
        self.toastTask = Task {
            try? await Task.sleep(for: .milliseconds(1600))
            guard !Task.isCancelled else { return }
            withAnimation(.easeIn(duration: 0.18)) {
                self.toastMessage = nil
            }
        }
    }
    
    
    private func runImportPanel() {
        
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.zip, .folder, UTType(filenameExtension: "md") ?? .plainText, .plainText]
        panel.message = "选择历史周报 .zip 压缩包、周报文件夹或 .md 文件，自动解析月份并存入本地数据库"
        
        let beginHandler: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK, !panel.urls.isEmpty else { return }
            Task { @MainActor in
                do {
                    let count = try self.db.importWeeklyReports(fromURLs: panel.urls)
                    self.state.rebuildGroups()
                    self.showToast("成功导入 \(count) 篇周报")
                } catch {
                    self.showToast("导入失败：\(error.localizedDescription)")
                }
            }
        }
        
        if let window = NSApp.mainWindow ?? NSApp.keyWindow ?? NSApp.orderedWindows.first(where: \.isVisible) {
            panel.beginSheetModal(for: window, completionHandler: beginHandler)
        } else {
            beginHandler(panel.runModal())
        }
    }
    
    
    private func runWeeklyReportGeneration() {
        
        guard AIService.shared.isConfigured else {
            self.state.generationError = "尚未配置 AI 模型与 API Key，请先打开「设置 → AI」完成配置。"
            (NSApp.delegate as? AppDelegate)?.showAIPreferences(nil)
            return
        }
        
        var materialParts: [String] = []
        for source in self.state.openSources where source.isSelected {
            let trimmed = source.content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            materialParts.append("【文档：\(source.title)】\n\(trimmed)")
        }
        
        let custom = self.state.customNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        if !custom.isEmpty {
            materialParts.append("【手动补充记录】\n\(custom)")
        }
        
        let frags = self.state.fragmentsText.trimmingCharacters(in: .whitespacesAndNewlines)
        let rawInput: String
        if !materialParts.isEmpty {
            rawInput = materialParts.joined(separator: "\n\n---\n\n")
        } else if !frags.isEmpty {
            rawInput = "【本周积累片段】\n\(frags)"
        } else {
            self.state.generationError = "请至少勾选一份文档、或在上方输入框填几条本周做过的事。"
            return
        }
        
        self.db.set(frags, forKey: CotLocalDatabase.ConfigKey.weeklyReportFragments)
        self.state.generationError = nil
        self.state.isGenerating = true
        self.state.generatedOutput = ""
        
        Task {
            do {
                let result = try await AIService.shared.run(.weeklyReport, on: rawInput) { partial in
                    self.state.generatedOutput = partial
                }
                self.state.generatedOutput = MarkdownTableFormatter.formatTables(in: result)
            } catch {
                self.state.generationError = error.localizedDescription
            }
            self.state.isGenerating = false
        }
    }
}


private struct WeeklyReportSidebarRow: View {
    
    let report: StoredWeeklyReport
    let isCurrentWeek: Bool
    let dateRangeLabel: String?
    let isSelected: Bool
    var onSelect: () -> Void
    var onOpen: () -> Void
    var onRename: () -> Void
    var onDelete: () -> Void
    
    @State private var isHovered = false
    @State private var isTrashHovered = false
    
    var body: some View {
        
        HStack(alignment: .center, spacing: 8) {
            Button {
                self.onSelect()
            } label: {
                HStack(alignment: .center, spacing: 9) {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(self.isSelected ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.055))
                        .frame(width: 28, height: 28)
                        .overlay(
                            Image(systemName: self.isSelected ? "doc.text.fill" : "doc.text")
                                .font(.system(size: 12.5, weight: .semibold))
                                .foregroundStyle(self.isSelected ? Color.accentColor : .secondary)
                        )
                    
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 5) {
                            Text(self.report.periodLabel)
                                .font(.system(size: 12, weight: self.isSelected ? .semibold : .medium, design: .monospaced))
                                .foregroundStyle(self.isSelected ? Color.primary : Color.primary.opacity(0.92))
                            
                            if self.isCurrentWeek {
                                Text("本周")
                                    .font(.system(size: 9.5, weight: .semibold))
                                    .foregroundStyle(Color.accentColor)
                                    .padding(.horizontal, 5.5)
                                    .padding(.vertical, 1.5)
                                    .background(Color.accentColor.opacity(0.14), in: Capsule())
                            }
                        }
                        
                        Text(self.dateRangeLabel.map { "\($0) · \(self.report.title)" } ?? self.report.title)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    
                    Spacer(minLength: 4)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .pointerStyle(.link)
            
            HStack(spacing: 5) {
                Button {
                    self.onOpen()
                } label: {
                    Text("打开")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                        .padding(.horizontal, 9)
                        .frame(height: 24)
                        .background(Color.accentColor.opacity(0.14), in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .pointerStyle(.link)
                .help("在编辑器标签页打开「\(self.report.periodLabel)」")
                
                Button {
                    self.onDelete()
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(self.isTrashHovered ? Color.red : Color.secondary)
                        .frame(width: 24, height: 24)
                        .background(
                            self.isTrashHovered ? Color.red.opacity(0.14) : Color.primary.opacity(0.04),
                            in: Circle()
                        )
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .pointerStyle(.link)
                .opacity((self.isHovered || self.isSelected) ? 1.0 : 0.45)
                .onHover { hovering in
                    self.isTrashHovered = hovering
                }
                .help("删除「\(self.report.periodLabel)」")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(minHeight: 46, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(
                    self.isSelected
                        ? Color.accentColor.opacity(0.11)
                        : (self.isHovered ? Color.primary.opacity(0.05) : Color.primary.opacity(0.02))
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(
                    self.isSelected
                        ? Color.accentColor.opacity(0.42)
                        : (self.isHovered ? Color.primary.opacity(0.10) : Color.primary.opacity(0.05)),
                    lineWidth: 1
                )
        )
        .onHover { hovering in
            self.isHovered = hovering
        }
        .contextMenu {
            Button("在编辑器打开") { self.onOpen() }
            Button("重命名") { self.onRename() }
            Divider()
            Button("删除", role: .destructive) { self.onDelete() }
        }
    }
}
