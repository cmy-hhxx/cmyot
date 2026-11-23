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
        let displayTitle: String
        let reports: [StoredWeeklyReport]
        var id: String { self.month }
    }
    
    struct ReportRowItem: Identifiable, Equatable {
        let id: String
        let title: String
        let periodLabel: String
        let yearMonth: String
        let rangeDesc: String?
        let compactCharCount: String
        let isCurrentWeek: Bool
        let report: StoredWeeklyReport
        
        static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.id == rhs.id
                && lhs.title == rhs.title
                && lhs.periodLabel == rhs.periodLabel
                && lhs.compactCharCount == rhs.compactCharCount
                && lhs.isCurrentWeek == rhs.isCurrentWeek
        }
    }
    
    var selectedReportID: String?
    var selectedMonth: String? = nil {
        didSet {
            if oldValue != self.selectedMonth {
                self.recomputeDisplayedRows()
            }
        }
    }
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
    var displayedRows: [ReportRowItem] = []
    
    // Generator fields
    var authorName: String = CotLocalDatabase.shared.weeklyReportAuthor
    var customNotes: String = ""
    var fragmentsText: String = CotLocalDatabase.shared.string(forKey: CotLocalDatabase.ConfigKey.weeklyReportFragments)
    var openSources: [OpenSourceItem] = []
    var generatedOutput: String = ""
    var isGenerating: Bool = false
    var generationError: String?
    
    private var allRowItems: [ReportRowItem] = []
    
    func rebuildGroups() {
        
        let allReports = CotLocalDatabase.shared.weeklyReports
        let currentWeek = AIService.currentWeekPeriodLabel()
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
            return YearMonthGroup(
                month: month,
                displayTitle: Self.formatYearMonthTitle(month),
                reports: sorted
            )
        }
        self.groups = builtGroups
        let flat = builtGroups.flatMap(\.reports)
        self.flatReports = flat
        self.allRowItems = flat.map { report in
            ReportRowItem(
                id: report.id,
                title: report.title,
                periodLabel: report.periodLabel,
                yearMonth: report.yearMonth,
                rangeDesc: Self.readablePeriodRange(report.periodLabel),
                compactCharCount: DocumentCenterState.compactChars(report.content.count),
                isCurrentWeek: report.periodLabel == currentWeek,
                report: report
            )
        }
        
        if let selectedMonth = self.selectedMonth, !builtGroups.contains(where: { $0.month == selectedMonth }) {
            self.selectedMonth = nil
        }
        self.recomputeDisplayedRows()
    }
    
    
    private func recomputeDisplayedRows() {
        let visible: [ReportRowItem]
        if let month = self.selectedMonth {
            visible = self.allRowItems.filter { $0.yearMonth == month }
        } else {
            visible = self.allRowItems
        }
        self.displayedRows = visible
        
        if let selectedReportID, visible.contains(where: { $0.id == selectedReportID }) {
            return
        }
        self.selectedReportID = visible.first?.id ?? self.allRowItems.first?.id
    }
    
    
    static func formatYearMonthTitle(_ yearMonth: String) -> String {
        guard yearMonth.count == 6,
              let year = Int(yearMonth.prefix(4)),
              let month = Int(yearMonth.suffix(2))
        else { return yearMonth }
        return "\(year)年\(month)月"
    }
    
    
    static func readablePeriodRange(_ periodLabel: String) -> String? {
        let parts = periodLabel.split(separator: "-")
        guard parts.count == 2, parts[0].count == 8, parts[1].count == 4 else { return nil }
        let startM = parts[0].dropFirst(4).prefix(2)
        let startD = parts[0].suffix(2)
        let endM = parts[1].prefix(2)
        let endD = parts[1].suffix(2)
        return "\(startM)/\(startD)-\(endM)/\(endD)"
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


// MARK: - Structured 3-Column Weekly Report Center

private struct WeeklyReportRowView: View, Equatable {
    
    let row: WeeklyReportCenterState.ReportRowItem
    let isSelected: Bool
    let tokens: StudioColorTokens
    
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.row == rhs.row
            && lhs.isSelected == rhs.isSelected
            && lhs.tokens == rhs.tokens
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 7) {
                Circle()
                    .fill(self.row.isCurrentWeek ? self.tokens.accent : self.tokens.primaryInk.opacity(0.24))
                    .frame(width: 6, height: 6)
                
                Text(self.row.periodLabel)
                    .font(.system(size: 13, weight: self.isSelected ? .semibold : .medium, design: .rounded).monospacedDigit())
                    .foregroundStyle(self.tokens.primaryInk.opacity(self.isSelected ? 1.0 : 0.90))
                    .lineLimit(1)
                
                if self.row.isCurrentWeek {
                    Text("本周")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(self.tokens.accentText)
                        .padding(.horizontal, 5.5)
                        .frame(height: 16)
                        .background(self.tokens.positivePillBg, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                }
                
                Spacer(minLength: 0)
            }
            
            HStack(spacing: 5) {
                let meta = (self.row.rangeDesc.map { "\($0) · " } ?? "") + self.row.compactCharCount
                Text(meta)
                    .font(.system(size: 11, weight: .regular, design: .rounded).monospacedDigit())
                    .foregroundStyle(self.tokens.primaryInk.opacity(0.46))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.leading, 13)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(self.isSelected ? self.tokens.accent.opacity(self.tokens.isDark ? 0.20 : 0.12) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(self.isSelected ? self.tokens.accent.opacity(0.35) : Color.clear, lineWidth: 0.75)
        )
        .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}


struct WeeklyReportCenterView: View {
    
    @Bindable var state: WeeklyReportCenterState
    var onOpenReport: ((StoredWeeklyReport) -> Void)?
    var onDismiss: (() -> Void)?
    
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.registerWorkspaceCenterEscPop) private var registerEscPop
    @State private var db = CotLocalDatabase.shared
    @State private var isEditing = false
    @State private var editingReportID: String?
    @State private var editingDraft = ""
    @State private var isRenamingSelected = false
    @State private var renameDraft = ""
    @FocusState private var isRenameFieldFocused: Bool
    @State private var copiedFlag = false
    @State private var toastMessage: String?
    @State private var toastTask: Task<Void, Never>?
    @State private var keyMonitor: Any?
    
    
    var body: some View {
        let rows = self.state.displayedRows
        let activeRow = self.selectedRow(in: rows)
        let tokens = DashPalette.editorialTokens(isDark: self.colorScheme == .dark)
        
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                self.topBar(tokens: tokens)
                
                Rectangle()
                    .fill(tokens.hairline)
                    .frame(height: 1)
                
                HStack(spacing: 0) {
                    self.monthSidebar(tokens: tokens)
                        .frame(width: 176)
                    
                    Rectangle()
                        .fill(tokens.hairline)
                        .frame(width: 1)
                    
                    self.listColumn(rows: rows, activeID: activeRow?.id, tokens: tokens)
                        .frame(width: 264)
                    
                    Rectangle()
                        .fill(tokens.hairline)
                        .frame(width: 1)
                    
                    self.detailColumn(row: activeRow, allRows: rows, tokens: tokens)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .background(tokens.canvasTop)
            
            if self.state.isGeneratorActive {
                self.generatorOverlay(tokens: tokens)
            }
            
            if let toastMessage {
                HStack(spacing: 6) {
                    Circle()
                        .fill(tokens.accent)
                        .frame(width: 6, height: 6)
                    Text(toastMessage)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(tokens.primaryInk)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(tokens.card, in: Capsule())
                .overlay(Capsule().strokeBorder(tokens.hairlineStrong, lineWidth: 0.8))
                .padding(.bottom, 18)
                .allowsHitTesting(false)
                .transition(.opacity)
            }
        }
        .onAppear {
            self.state.rebuildGroups()
            self.state.refreshOpenSources()
            self.installKeyboardMonitor()
            self.registerEscPop? { self.handleEscapePop() }
        }
        .onDisappear {
            self.removeKeyboardMonitor()
            self.registerEscPop?(nil)
        }
        .onReceive(
            NotificationCenter.default.publisher(for: CotLocalDatabase.weeklyReportsDidChangeNotification)
                .receive(on: RunLoop.main)
        ) { _ in
            self.state.rebuildGroups()
        }
    }
    
    
    // MARK: Top Bar
    
    private func topBar(tokens: StudioColorTokens) -> some View {
        HStack(spacing: 10) {
            if let onDismiss = self.onDismiss {
                Button(action: onDismiss) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 10.5, weight: .semibold))
                        Text("返回")
                            .font(.system(size: 12.5, weight: .medium))
                    }
                    .foregroundStyle(tokens.primaryInk.opacity(0.84))
                    .padding(.horizontal, 10)
                    .frame(height: 28)
                    .background(tokens.inset, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
                .buttonStyle(.plain)
                .pointerStyle(.link)
            }
            
            Text("周报中心")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(tokens.primaryInk)
            
            Spacer(minLength: 8)
            
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(tokens.primaryInk.opacity(0.42))
                TextField("搜索周报", text: self.$state.searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12.5))
                    .frame(width: 190)
                if !self.state.searchText.isEmpty {
                    Button {
                        self.state.searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(tokens.primaryInk.opacity(0.40))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 9)
            .frame(height: 28)
            .background(tokens.inset, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(tokens.hairline, lineWidth: 0.75))
            
            Button {
                self.runImportPanel()
            } label: {
                Text("导入")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(tokens.primaryInk.opacity(0.84))
                    .padding(.horizontal, 10)
                    .frame(height: 28)
                    .background(tokens.inset, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            }
            .buttonStyle(.plain)
            .pointerStyle(.link)
            
            Menu {
                Button("本周（\(AIService.currentWeekPeriodLabel())）") {
                    self.createWeeklyReport(weekOffset: 0)
                }
                Button("上周") {
                    self.createWeeklyReport(weekOffset: -1)
                }
            } label: {
                Text("新建周报")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(tokens.primaryInk.opacity(0.84))
                    .padding(.horizontal, 10)
                    .frame(height: 28)
                    .background(tokens.inset, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .pointerStyle(.link)
            
            Button {
                self.state.refreshOpenSources()
                withAnimation(.easeOut(duration: 0.16)) {
                    self.state.isGeneratorActive = true
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 11, weight: .semibold))
                    Text("AI 生成周报")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(tokens.onAccentInk)
                .padding(.horizontal, 11)
                .frame(height: 28)
                .background(tokens.accent, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            }
            .buttonStyle(.plain)
            .pointerStyle(.link)
        }
        .padding(.horizontal, 14)
        .frame(height: 46)
        .background(tokens.canvasTop)
    }
    
    
    // MARK: Column 1 - Structured Month Sidebar
    
    private func monthSidebar(tokens: StudioColorTokens) -> some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 2) {
                self.monthSidebarRow(
                    title: "全部周报",
                    icon: "calendar",
                    count: self.state.flatReports.count,
                    isSelected: self.state.selectedMonth == nil,
                    tokens: tokens
                ) {
                    self.state.selectedMonth = nil
                }
                
                if !self.state.groups.isEmpty {
                    Rectangle()
                        .fill(tokens.hairline)
                        .frame(height: 1)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 6)
                    
                    ForEach(self.state.groups) { group in
                        self.monthSidebarRow(
                            title: group.displayTitle,
                            icon: "folder",
                            count: group.reports.count,
                            isSelected: self.state.selectedMonth == group.month,
                            tokens: tokens
                        ) {
                            self.state.selectedMonth = group.month
                        }
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 10)
        }
        .background(tokens.canvasBottom)
    }
    
    
    private func monthSidebarRow(
        title: String,
        icon: String,
        count: Int,
        isSelected: Bool,
        tokens: StudioColorTokens,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: icon)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(isSelected ? tokens.accentText : tokens.primaryInk.opacity(0.50))
                    .frame(width: 15)
                
                Text(title)
                    .font(.system(size: 12.5, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? tokens.primaryInk : tokens.primaryInk.opacity(0.82))
                    .lineLimit(1)
                
                Spacer(minLength: 4)
                
                Text("\(count)")
                    .font(.system(size: 11, weight: .medium, design: .rounded).monospacedDigit())
                    .foregroundStyle(isSelected ? tokens.accentText : tokens.primaryInk.opacity(0.42))
            }
            .padding(.horizontal, 8)
            .frame(height: 30)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isSelected ? tokens.accent.opacity(tokens.isDark ? 0.20 : 0.12) : Color.clear)
            )
            .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
        .pointerStyle(.link)
    }
    
    
    // MARK: Column 2 - Fast Lazy Report List
    
    private func listColumn(
        rows: [WeeklyReportCenterState.ReportRowItem],
        activeID: String?,
        tokens: StudioColorTokens
    ) -> some View {
        Group {
            if rows.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "calendar.badge.clock")
                        .font(.system(size: 22, weight: .light))
                        .foregroundStyle(tokens.primaryInk.opacity(0.24))
                    Text(self.state.searchText.isEmpty ? "暂无周报" : "无匹配结果")
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(tokens.primaryInk.opacity(0.45))
                    if self.state.searchText.isEmpty {
                        Button("新建本周周报") {
                            self.createWeeklyReport(weekOffset: 0)
                        }
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(tokens.onAccentInk)
                        .padding(.horizontal, 12)
                        .frame(height: 28)
                        .background(tokens.accent, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                        .buttonStyle(.plain)
                        .pointerStyle(.link)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.vertical, showsIndicators: true) {
                    LazyVStack(spacing: 2) {
                        ForEach(rows) { row in
                            WeeklyReportRowView(
                                row: row,
                                isSelected: activeID == row.id,
                                tokens: tokens
                            )
                            .equatable()
                            .onTapGesture(count: 2) {
                                self.state.selectedReportID = row.id
                                self.open(report: row.report)
                            }
                            .onTapGesture(count: 1) {
                                if self.editingReportID != row.id {
                                    self.isEditing = false
                                }
                                self.isRenamingSelected = false
                                self.state.selectedReportID = row.id
                            }
                            .contextMenu {
                                Button("在编辑器打开") { self.open(report: row.report) }
                                Button("编辑") {
                                    self.state.selectedReportID = row.id
                                    self.editingReportID = row.id
                                    self.editingDraft = row.report.content
                                    self.isEditing = true
                                }
                                Button("重命名") {
                                    self.state.selectedReportID = row.id
                                    self.renameDraft = row.title
                                    self.isRenamingSelected = true
                                    DispatchQueue.main.async { self.isRenameFieldFocused = true }
                                }
                                Divider()
                                Button("删除", role: .destructive) {
                                    self.delete(report: row.report, in: rows)
                                }
                            }
                        }
                    }
                    .padding(6)
                }
            }
        }
        .background(tokens.canvasTop)
    }
    
    
    // MARK: Column 3 - Reading & Inline Editing Pane
    
    @ViewBuilder
    private func detailColumn(
        row: WeeklyReportCenterState.ReportRowItem?,
        allRows: [WeeklyReportCenterState.ReportRowItem],
        tokens: StudioColorTokens
    ) -> some View {
        if let row {
            let report = row.report
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    if self.isRenamingSelected {
                        TextField("周报标题", text: self.$renameDraft)
                            .textFieldStyle(.plain)
                            .font(.system(size: 14, weight: .semibold))
                            .focused(self.$isRenameFieldFocused)
                            .padding(.horizontal, 8)
                            .frame(height: 28)
                            .background(tokens.inset, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                            .frame(maxWidth: 280)
                            .onSubmit { self.commitReportRename(report) }
                            .onExitCommand { self.isRenamingSelected = false }
                        
                        Button("保存") { self.commitReportRename(report) }
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(tokens.onAccentInk)
                            .padding(.horizontal, 10)
                            .frame(height: 26)
                            .background(tokens.accent, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                            .buttonStyle(.plain)
                            .pointerStyle(.link)
                        
                        Button("取消") { self.isRenamingSelected = false }
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(tokens.primaryInk.opacity(0.65))
                            .buttonStyle(.plain)
                            .pointerStyle(.link)
                    } else {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(report.title)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(tokens.primaryInk)
                                    .lineLimit(1)
                                if row.isCurrentWeek {
                                    Text("本周")
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundStyle(tokens.accentText)
                                        .padding(.horizontal, 6)
                                        .frame(height: 17)
                                        .background(tokens.positivePillBg, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                                }
                            }
                            let meta = "\(row.periodLabel)" + (row.rangeDesc.map { " · \($0)" } ?? "") + " · \(row.compactCharCount)"
                            Text(meta)
                                .font(.system(size: 11, weight: .regular, design: .rounded).monospacedDigit())
                                .foregroundStyle(tokens.primaryInk.opacity(0.46))
                                .lineLimit(1)
                        }
                    }
                    
                    Spacer(minLength: 8)
                    
                    if self.isEditing && self.editingReportID == report.id {
                        Button {
                            self.db.saveWeeklyReport(
                                id: report.id,
                                periodLabel: report.periodLabel,
                                yearMonth: report.yearMonth,
                                title: report.title,
                                content: self.editingDraft,
                                sourcePath: report.sourcePath,
                                isEnhanced: report.isEnhanced,
                                createdAt: report.createdAt,
                                reloadAfter: true
                            )
                            self.state.rebuildGroups()
                            self.isEditing = false
                            self.showToast("已保存")
                        } label: {
                            Text("保存")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(tokens.onAccentInk)
                                .padding(.horizontal, 12)
                                .frame(height: 28)
                                .background(tokens.accent, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .pointerStyle(.link)
                        
                        Button {
                            self.isEditing = false
                        } label: {
                            Text("取消")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(tokens.primaryInk.opacity(0.80))
                                .padding(.horizontal, 10)
                                .frame(height: 28)
                                .background(tokens.inset, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .pointerStyle(.link)
                    } else {
                        Button {
                            self.open(report: report)
                        } label: {
                            Text("打开")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(tokens.onAccentInk)
                                .padding(.horizontal, 12)
                                .frame(height: 28)
                                .background(tokens.accent, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .pointerStyle(.link)
                        
                        Button {
                            self.editingReportID = report.id
                            self.editingDraft = report.content
                            self.isEditing = true
                        } label: {
                            Text("编辑")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(tokens.primaryInk.opacity(0.84))
                                .padding(.horizontal, 10)
                                .frame(height: 28)
                                .background(tokens.inset, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .pointerStyle(.link)
                        
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(report.content, forType: .string)
                            self.copiedFlag = true
                            self.showToast("已复制")
                            Task {
                                try? await Task.sleep(for: .seconds(1.5))
                                self.copiedFlag = false
                            }
                        } label: {
                            Text(self.copiedFlag ? "已复制" : "复制")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(tokens.primaryInk.opacity(0.84))
                                .padding(.horizontal, 10)
                                .frame(height: 28)
                                .background(tokens.inset, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .pointerStyle(.link)
                        
                        Button {
                            self.renameDraft = report.title
                            self.isRenamingSelected = true
                            DispatchQueue.main.async { self.isRenameFieldFocused = true }
                        } label: {
                            Text("重命名")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(tokens.primaryInk.opacity(0.84))
                                .padding(.horizontal, 10)
                                .frame(height: 28)
                                .background(tokens.inset, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .pointerStyle(.link)
                        
                        Button {
                            self.delete(report: report, in: allRows)
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 11.5, weight: .medium))
                                .foregroundStyle(tokens.primaryInk.opacity(0.62))
                                .frame(width: 28, height: 28)
                                .background(tokens.inset, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                                .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .pointerStyle(.link)
                    }
                }
                .padding(.horizontal, 18)
                .frame(height: 52)
                .background(tokens.canvasTop)
                
                Rectangle()
                    .fill(tokens.hairline)
                    .frame(height: 1)
                
                if self.isEditing && self.editingReportID == report.id {
                    TextEditor(text: self.$editingDraft)
                        .font(.system(size: 13))
                        .scrollContentBackground(.hidden)
                        .padding(18)
                        .background(Color(nsColor: .textBackgroundColor))
                } else {
                    CenterPreviewTextView(text: report.content)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .background(Color(nsColor: .textBackgroundColor))
        } else {
            VStack(spacing: 8) {
                Image(systemName: "doc.text")
                    .font(.system(size: 26, weight: .light))
                    .foregroundStyle(tokens.primaryInk.opacity(0.20))
                Text("未选择周报")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(tokens.primaryInk.opacity(0.42))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .textBackgroundColor))
        }
    }
    
    
    private func selectedRow(in rows: [WeeklyReportCenterState.ReportRowItem]) -> WeeklyReportCenterState.ReportRowItem? {
        if let id = self.state.selectedReportID, let match = rows.first(where: { $0.id == id }) {
            return match
        }
        return rows.first
    }
    
    
    // MARK: Keyboard Navigation
    
    private func handleEscapePop() -> Bool {
        if self.state.isGeneratorActive {
            withAnimation(.easeOut(duration: 0.14)) { self.state.isGeneratorActive = false }
            return true
        }
        if self.isEditing {
            self.isEditing = false
            return true
        }
        if self.isRenamingSelected {
            self.isRenamingSelected = false
            return true
        }
        if !self.state.searchText.isEmpty {
            self.state.searchText = ""
            return true
        }
        return false
    }
    
    
    private func installKeyboardMonitor() {
        self.removeKeyboardMonitor()
        self.keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [self] event in
            if self.state.isGeneratorActive || self.isEditing {
                return event
            }
            if let responder = NSApp.keyWindow?.firstResponder, responder is NSTextView {
                return event
            }
            let rows = self.state.displayedRows
            guard !rows.isEmpty else { return event }
            
            switch event.keyCode {
                case 126: // Up
                    self.stepSelection(by: -1, in: rows)
                    return nil
                case 125: // Down
                    self.stepSelection(by: 1, in: rows)
                    return nil
                case 36: // Return -> open
                    if let active = self.selectedRow(in: rows) {
                        self.open(report: active.report)
                        return nil
                    }
                default:
                    break
            }
            return event
        }
    }
    
    
    private func removeKeyboardMonitor() {
        if let monitor = self.keyMonitor {
            NSEvent.removeMonitor(monitor)
            self.keyMonitor = nil
        }
    }
    
    
    private func stepSelection(by delta: Int, in list: [WeeklyReportCenterState.ReportRowItem]) {
        guard !list.isEmpty else { return }
        let curIdx = list.firstIndex(where: { $0.id == self.state.selectedReportID }) ?? 0
        let nextIdx = (curIdx + delta + list.count) % list.count
        self.state.selectedReportID = list[nextIdx].id
    }
    
    
    // MARK: Focused AI Weekly Report Generator Modal
    
    private func generatorOverlay(tokens: StudioColorTokens) -> some View {
        ZStack {
            Color.black.opacity(self.colorScheme == .dark ? 0.50 : 0.24)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(.easeOut(duration: 0.14)) { self.state.isGeneratorActive = false }
                }
            
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(tokens.accent)
                    Text("AI 生成周报 · \(AIService.currentWeekPeriodLabel())")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(tokens.primaryInk)
                    Spacer()
                    Button {
                        withAnimation(.easeOut(duration: 0.14)) { self.state.isGeneratorActive = false }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(tokens.primaryInk.opacity(0.72))
                            .frame(width: 28, height: 28)
                            .background(tokens.inset, in: Circle())
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .pointerStyle(.link)
                }
                .padding(.horizontal, 18)
                .frame(height: 48)
                
                Rectangle().fill(tokens.hairline).frame(height: 1)
                
                HStack(spacing: 0) {
                    ScrollView(.vertical, showsIndicators: true) {
                        VStack(alignment: .leading, spacing: 14) {
                            if !self.state.openSources.isEmpty {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("素材文档")
                                        .font(.system(size: 11.5, weight: .semibold))
                                        .foregroundStyle(tokens.primaryInk.opacity(0.62))
                                    
                                    ForEach(self.$state.openSources) { $source in
                                        Button {
                                            source.isSelected.toggle()
                                        } label: {
                                            HStack(spacing: 8) {
                                                Image(systemName: source.isSelected ? "checkmark.circle.fill" : "circle")
                                                    .font(.system(size: 13))
                                                    .foregroundStyle(source.isSelected ? tokens.accent : tokens.primaryInk.opacity(0.32))
                                                Text(source.title)
                                                    .font(.system(size: 12))
                                                    .foregroundStyle(tokens.primaryInk)
                                                    .lineLimit(1)
                                                Spacer()
                                            }
                                            .padding(.horizontal, 10)
                                            .frame(height: 30)
                                            .background(tokens.inset, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                                            .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                                        }
                                        .buttonStyle(.plain)
                                        .pointerStyle(.link)
                                    }
                                }
                            }
                            
                            VStack(alignment: .leading, spacing: 6) {
                                Text("补充要点")
                                    .font(.system(size: 11.5, weight: .semibold))
                                    .foregroundStyle(tokens.primaryInk.opacity(0.62))
                                TextEditor(text: self.$state.customNotes)
                                    .font(.system(size: 12.5))
                                    .scrollContentBackground(.hidden)
                                    .padding(8)
                                    .frame(height: 116)
                                    .background(tokens.inset, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            }
                            
                            if !self.state.fragmentsText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("已积累片段")
                                        .font(.system(size: 11.5, weight: .semibold))
                                        .foregroundStyle(tokens.primaryInk.opacity(0.62))
                                    TextEditor(text: self.$state.fragmentsText)
                                        .font(.system(size: 12))
                                        .scrollContentBackground(.hidden)
                                        .padding(8)
                                        .frame(height: 84)
                                        .background(tokens.inset, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                                }
                            }
                            
                            if let err = self.state.generationError {
                                Text(err)
                                    .font(.system(size: 11.5))
                                    .foregroundStyle(.red)
                            }
                            
                            Button {
                                self.runWeeklyReportGeneration()
                            } label: {
                                HStack(spacing: 6) {
                                    if self.state.isGenerating {
                                        ProgressView().controlSize(.small)
                                    } else {
                                        Image(systemName: "sparkles")
                                            .font(.system(size: 12, weight: .semibold))
                                    }
                                    Text(self.state.isGenerating ? "生成中" : "一键生成")
                                        .font(.system(size: 12.5, weight: .semibold))
                                }
                                .foregroundStyle(tokens.onAccentInk)
                                .frame(maxWidth: .infinity, minHeight: 34)
                                .background(tokens.accent, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                                .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .pointerStyle(.link)
                            .disabled(self.state.isGenerating)
                        }
                        .padding(16)
                    }
                    .frame(width: 272)
                    
                    Rectangle().fill(tokens.hairline).frame(width: 1)
                    
                    VStack(spacing: 0) {
                        if self.state.generatedOutput.isEmpty {
                            VStack(spacing: 8) {
                                Image(systemName: "sparkles")
                                    .font(.system(size: 22, weight: .light))
                                    .foregroundStyle(tokens.primaryInk.opacity(0.24))
                                Text("等待生成")
                                    .font(.system(size: 12.5, weight: .medium))
                                    .foregroundStyle(tokens.primaryInk.opacity(0.45))
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else {
                            CenterPreviewTextView(text: self.state.generatedOutput)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                            
                            Rectangle().fill(tokens.hairline).frame(height: 1)
                            
                            HStack(spacing: 8) {
                                Spacer()
                                Button {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(self.state.generatedOutput, forType: .string)
                                    self.showToast("已复制")
                                } label: {
                                    Text("复制")
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundStyle(tokens.primaryInk.opacity(0.84))
                                        .padding(.horizontal, 12)
                                        .frame(height: 28)
                                        .background(tokens.inset, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                                }
                                .buttonStyle(.plain)
                                .pointerStyle(.link)
                                
                                Button {
                                    let saved = self.db.saveGeneratedWeeklyReport(content: self.state.generatedOutput)
                                    self.state.rebuildGroups()
                                    self.state.selectedReportID = saved.id
                                    self.state.isGeneratorActive = false
                                    self.open(report: saved)
                                    self.showToast("已保存")
                                } label: {
                                    Text("保存并打开")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(tokens.onAccentInk)
                                        .padding(.horizontal, 14)
                                        .frame(height: 28)
                                        .background(tokens.accent, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                                }
                                .buttonStyle(.plain)
                                .pointerStyle(.link)
                            }
                            .padding(.horizontal, 14)
                            .frame(height: 46)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(maxWidth: 820, maxHeight: 560)
            .background(tokens.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(tokens.hairlineStrong, lineWidth: 1))
            .padding(24)
        }
        .transition(.opacity)
    }
    
    
    // MARK: Actions
    
    private func createWeeklyReport(weekOffset: Int) {
        let result = self.db.createWeeklyReport(weekOffset: weekOffset, includeSavedFragments: true)
        self.state.selectedMonth = nil
        self.state.searchText = ""
        self.state.rebuildGroups()
        self.state.isGeneratorActive = false
        self.state.selectedReportID = result.report.id
        self.editingReportID = result.report.id
        self.editingDraft = result.report.content
        self.isEditing = true
        self.showToast(result.alreadyExisted ? "已定位「\(result.report.periodLabel)」" : "已新建「\(result.report.periodLabel)」")
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
        self.showToast("已重命名")
    }
    
    
    private func open(report: StoredWeeklyReport) {
        if let onOpenReport = self.onOpenReport {
            onOpenReport(report)
        } else {
            WeeklyReportWindowController.shared.openReportInEditor(report)
        }
    }
    
    
    private func delete(report: StoredWeeklyReport, in list: [WeeklyReportCenterState.ReportRowItem]) {
        if let idx = list.firstIndex(where: { $0.id == report.id }) {
            let nextReport = list.indices.contains(idx + 1) ? list[idx + 1] : (idx > 0 ? list[idx - 1] : nil)
            self.state.selectedReportID = nextReport?.id
        }
        self.db.deleteWeeklyReport(id: report.id)
        self.state.rebuildGroups()
        self.isEditing = false
        self.editingReportID = nil
        self.showToast("已删除")
    }
    
    
    private func showToast(_ message: String) {
        self.toastTask?.cancel()
        withAnimation(.easeOut(duration: 0.14)) {
            self.toastMessage = message
        }
        self.toastTask = Task {
            try? await Task.sleep(for: .milliseconds(1600))
            guard !Task.isCancelled else { return }
            withAnimation(.easeIn(duration: 0.16)) {
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
        
        let beginHandler: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK, !panel.urls.isEmpty else { return }
            Task { @MainActor in
                do {
                    let count = try self.db.importWeeklyReports(fromURLs: panel.urls)
                    self.state.rebuildGroups()
                    self.showToast("已导入 \(count) 篇")
                } catch {
                    self.showToast("导入失败")
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
            self.state.generationError = "请先配置 API"
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
            self.state.generationError = "请选择素材或输入要点"
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
