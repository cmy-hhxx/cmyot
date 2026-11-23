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


// MARK: - Linear Pulse & Craft Digest Weekly Report Center

struct WeeklyReportCenterView: View {
    
    @Bindable var state: WeeklyReportCenterState
    var onOpenReport: ((StoredWeeklyReport) -> Void)?
    var onDismiss: (() -> Void)?
    
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.registerWorkspaceCenterEscPop) private var registerEscPop
    @State private var db = CotLocalDatabase.shared
    @State private var studioPalette = StudioPaletteManager.shared
    
    @State private var isEditingInline = false
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
        let tokens = self.studioPalette.tokens(isDark: self.colorScheme == .dark)
        let activeReport = self.selectedReport(in: self.state.flatReports)
        
        ZStack(alignment: .bottom) {
            LinearGradient(
                colors: [tokens.canvasTop, tokens.canvasBottom],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            VStack(spacing: 0) {
                self.topToolbar(tokens: tokens)
                
                Rectangle()
                    .fill(tokens.hairline)
                    .frame(height: 0.75)
                
                if self.state.isGeneratorActive {
                    self.generatorWorkbench(tokens: tokens)
                        .transition(.opacity)
                } else {
                    GeometryReader { geo in
                        let timelineW: CGFloat = min(292, max(232, geo.size.width * 0.30))
                        HStack(spacing: 0) {
                            self.timelinePane(activeReport: activeReport, tokens: tokens)
                                .frame(width: timelineW)
                            
                            Rectangle()
                                .fill(tokens.hairline)
                                .frame(width: 0.75)
                            
                            self.digestReaderPane(activeReport: activeReport, tokens: tokens)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }
                    .transition(.opacity)
                }
            }
            
            if let toastMessage = self.toastMessage {
                Text(toastMessage)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(tokens.primaryInk)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(tokens.card, in: Capsule())
                    .overlay(Capsule().strokeBorder(tokens.hairlineStrong, lineWidth: 0.75))
                    .shadow(color: tokens.cardShadow, radius: 10, y: 3)
                    .padding(.bottom, 16)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .onAppear {
            if self.db.weeklyReports.isEmpty {
                self.db.reloadWeeklyReports()
            }
            self.state.rebuildGroups()
            if self.state.isGeneratorActive {
                self.state.refreshOpenSources()
            }
            self.installKeyboardMonitor()
            self.registerEscPop? {
                self.handleEscapePop()
            }
        }
        .onDisappear {
            self.removeKeyboardMonitor()
            self.registerEscPop?(nil)
        }
        .onReceive(NotificationCenter.default.publisher(for: CotLocalDatabase.weeklyReportsDidChangeNotification)) { _ in
            self.state.rebuildGroups()
        }
    }
    
    
    private func handleEscapePop() -> Bool {
        if self.isEditingInline {
            self.isEditingInline = false
            self.editingReportID = nil
            return true
        }
        if self.isRenamingSelected {
            self.isRenamingSelected = false
            return true
        }
        if self.state.isGeneratorActive {
            withAnimation(.timingCurve(0.2, 0, 0, 1, duration: 0.18)) {
                self.state.isGeneratorActive = false
            }
            return true
        }
        return false
    }
    
    
    // MARK: 1. Unified Top Toolbar
    
    private func topToolbar(tokens: StudioColorTokens) -> some View {
        let thisWeek = CotLocalDatabase.weekPeriodInfo(weekOffset: 0)
        let lastWeek = CotLocalDatabase.weekPeriodInfo(weekOffset: -1)
        let nextWeek = CotLocalDatabase.weekPeriodInfo(weekOffset: 1)
        
        return HStack(spacing: 10) {
            if let onDismiss = self.onDismiss {
                Button(action: onDismiss) {
                    HStack(spacing: 5) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 11, weight: .semibold))
                        Text("返回编辑")
                            .font(.system(size: 12.5, weight: .medium))
                    }
                    .foregroundStyle(tokens.primaryInk.opacity(0.84))
                    .padding(.horizontal, 10)
                    .frame(height: 30)
                    .background(tokens.card, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(tokens.hairline, lineWidth: 0.75)
                    )
                }
                .buttonStyle(.plain)
                .pointerStyle(.link)
            }
            
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("周报中心")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(tokens.primaryInk)
                Text("\(self.state.flatReports.count)")
                    .font(.system(size: 11.5, weight: .medium, design: .rounded).monospacedDigit())
                    .foregroundStyle(tokens.primaryInk.opacity(0.45))
            }
            
            // Segmented Archive / Generator Switcher
            HStack(spacing: 2) {
                self.modeTabButton(title: "归档时间线", isSelected: !self.state.isGeneratorActive, tokens: tokens) {
                    withAnimation(.timingCurve(0.2, 0, 0, 1, duration: 0.18)) {
                        self.state.isGeneratorActive = false
                    }
                }
                self.modeTabButton(title: "AI 生成台", isSelected: self.state.isGeneratorActive, tokens: tokens) {
                    self.isEditingInline = false
                    self.state.refreshOpenSources()
                    withAnimation(.timingCurve(0.2, 0, 0, 1, duration: 0.18)) {
                        self.state.isGeneratorActive = true
                    }
                }
            }
            .padding(3)
            .background(tokens.card, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(tokens.hairline, lineWidth: 0.75)
            )
            
            Spacer(minLength: 8)
            
            if !self.state.isGeneratorActive {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(tokens.primaryInk.opacity(0.45))
                    TextField("搜索周期、标题或正文", text: self.$state.searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                        .foregroundStyle(tokens.primaryInk)
                        .frame(minWidth: 120, maxWidth: 185)
                    if !self.state.searchText.isEmpty {
                        Button {
                            self.state.searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(tokens.primaryInk.opacity(0.42))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 9)
                .frame(height: 30)
                .background(tokens.card, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(tokens.hairline, lineWidth: 0.75)
                )
            }
            
            Menu {
                Button("本周周报（\(thisWeek.displayRange)）") {
                    self.createWeeklyReport(weekOffset: 0)
                }
                Button("补写上周（\(lastWeek.displayRange)）") {
                    self.createWeeklyReport(weekOffset: -1)
                }
                Button("预建下周（\(nextWeek.displayRange)）") {
                    self.createWeeklyReport(weekOffset: 1)
                }
            } label: {
                Label("新建周报", systemImage: "plus")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(tokens.primaryInk.opacity(0.86))
                    .padding(.horizontal, 10)
                    .frame(height: 30)
                    .background(tokens.card, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(tokens.hairline, lineWidth: 0.75)
                    )
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            
            Button {
                self.runImportPanel()
            } label: {
                Label("导入", systemImage: "square.and.arrow.down")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(tokens.primaryInk.opacity(0.84))
                    .padding(.horizontal, 9)
                    .frame(height: 30)
                    .background(tokens.card, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(tokens.hairline, lineWidth: 0.75)
                    )
            }
            .buttonStyle(.plain)
            .pointerStyle(.link)
            
            if !self.state.isGeneratorActive {
                Button {
                    self.isEditingInline = false
                    self.state.refreshOpenSources()
                    withAnimation(.timingCurve(0.2, 0, 0, 1, duration: 0.18)) {
                        self.state.isGeneratorActive = true
                    }
                } label: {
                    Label("AI 生成", systemImage: "sparkles")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(tokens.onAccentInk)
                        .padding(.horizontal, 11)
                        .frame(height: 30)
                        .background(tokens.accent, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
                .pointerStyle(.link)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 48)
    }
    
    
    private func modeTabButton(
        title: String,
        isSelected: Bool,
        tokens: StudioColorTokens,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11.5, weight: isSelected ? .semibold : .medium))
                .foregroundStyle(isSelected ? tokens.onAccentInk : tokens.primaryInk.opacity(0.70))
                .padding(.horizontal, 10)
                .frame(height: 24)
                .background(isSelected ? tokens.accent : Color.clear, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
        .pointerStyle(.link)
    }
    
    
    // MARK: 2. Archive Mode — Linear Pulse Timeline + Editorial Digest Reader
    
    private func timelinePane(activeReport: StoredWeeklyReport?, tokens: StudioColorTokens) -> some View {
        let currentPeriod = AIService.currentWeekPeriodLabel()
        return Group {
            if self.state.groups.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "calendar.badge.clock")
                        .font(.system(size: 24, weight: .light))
                        .foregroundStyle(tokens.primaryInk.opacity(0.28))
                    Text(self.state.searchText.isEmpty ? "暂无周报归档" : "没有匹配的周报")
                        .font(.system(size: 12.5))
                        .foregroundStyle(tokens.primaryInk.opacity(0.50))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.vertical, showsIndicators: true) {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        ForEach(self.state.groups) { group in
                            let isCollapsed = self.state.collapsedMonths.contains(group.id)
                            VStack(alignment: .leading, spacing: 6) {
                                Button {
                                    withAnimation(.timingCurve(0.2, 0, 0, 1, duration: 0.16)) {
                                        if isCollapsed {
                                            self.state.collapsedMonths.remove(group.id)
                                        } else {
                                            self.state.collapsedMonths.insert(group.id)
                                        }
                                    }
                                } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                                            .font(.system(size: 9.5, weight: .semibold))
                                            .foregroundStyle(tokens.primaryInk.opacity(0.45))
                                            .frame(width: 12)
                                        Text(Self.formatYearMonthTitle(group.month))
                                            .font(.system(size: 11.5, weight: .semibold))
                                            .foregroundStyle(tokens.primaryInk.opacity(0.64))
                                        Spacer()
                                        Text("\(group.reports.count)")
                                            .font(.system(size: 10.5, weight: .medium, design: .rounded).monospacedDigit())
                                            .foregroundStyle(tokens.primaryInk.opacity(0.42))
                                    }
                                    .padding(.horizontal, 6)
                                }
                                .buttonStyle(.plain)
                                .pointerStyle(.link)
                                
                                if !isCollapsed {
                                    VStack(spacing: 4) {
                                        ForEach(group.reports) { report in
                                            self.timelineRow(
                                                report: report,
                                                isCurrentWeek: report.periodLabel == currentPeriod,
                                                isSelected: activeReport?.id == report.id,
                                                tokens: tokens
                                            )
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .padding(10)
                }
            }
        }
        .background(tokens.inset.opacity(0.40))
    }
    
    
    private func timelineRow(
        report: StoredWeeklyReport,
        isCurrentWeek: Bool,
        isSelected: Bool,
        tokens: StudioColorTokens
    ) -> some View {
        let range = Self.readablePeriodRange(report.periodLabel)
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Circle()
                    .fill(isCurrentWeek ? tokens.accent : tokens.secondaryAccent.opacity(0.65))
                    .frame(width: 6, height: 6)
                
                Text(range ?? report.periodLabel)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced).monospacedDigit())
                    .foregroundStyle(isCurrentWeek ? tokens.accentText : tokens.primaryInk.opacity(0.68))
                
                if isCurrentWeek {
                    Text("本周")
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(tokens.onAccentInk)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(tokens.accent, in: Capsule())
                }
                
                Spacer(minLength: 4)
                
                Text("\(report.content.count.formatted()) 字")
                    .font(.system(size: 10, design: .rounded).monospacedDigit())
                    .foregroundStyle(tokens.primaryInk.opacity(0.42))
            }
            
            Text(report.title)
                .font(.system(size: 12.5, weight: isSelected ? .semibold : .medium))
                .foregroundStyle(tokens.primaryInk)
                .lineLimit(1)
            
            let preview = Self.cleanExcerpt(report.content)
            if !preview.isEmpty {
                Text(preview)
                    .font(.system(size: 11))
                    .foregroundStyle(tokens.primaryInk.opacity(0.50))
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(isSelected ? tokens.card : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(isSelected ? tokens.accent.opacity(0.52) : Color.clear, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            if self.editingReportID != report.id {
                self.isEditingInline = false
                self.editingReportID = nil
            }
            self.isRenamingSelected = false
            self.state.selectedReportID = report.id
        }
        .simultaneousGesture(
            TapGesture(count: 2).onEnded {
                self.open(report: report)
            }
        )
        .contextMenu {
            Button("在编辑器打开") { self.open(report: report) }
            Button("快速编辑") {
                self.state.selectedReportID = report.id
                self.editingReportID = report.id
                self.editingDraft = report.content
                self.isEditingInline = true
            }
            Button("重命名") {
                self.state.selectedReportID = report.id
                self.renameDraft = report.title
                self.isRenamingSelected = true
                self.isRenameFieldFocused = true
            }
            Divider()
            Button("删除", role: .destructive) {
                self.delete(report: report, in: self.state.flatReports)
            }
        }
    }
    
    
    @ViewBuilder
    private func digestReaderPane(activeReport: StoredWeeklyReport?, tokens: StudioColorTokens) -> some View {
        if let report = activeReport {
            let isCurrentWeek = (report.periodLabel == AIService.currentWeekPeriodLabel())
            let isEditingThis = self.isEditingInline && self.editingReportID == report.id
            let range = Self.readablePeriodRange(report.periodLabel)
            
            VStack(spacing: 0) {
                // Digest Header
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .center, spacing: 8) {
                        if self.isRenamingSelected {
                            TextField("输入周报标题", text: self.$renameDraft)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 15, weight: .semibold))
                                .focused(self.$isRenameFieldFocused)
                                .onSubmit { self.commitReportRename(report) }
                            
                            Button("保存") {
                                self.commitReportRename(report)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                            
                            Button("取消") {
                                self.isRenamingSelected = false
                            }
                            .controlSize(.small)
                        } else {
                            Text(report.title)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(tokens.primaryInk)
                                .lineLimit(1)
                            
                            Button {
                                self.renameDraft = report.title
                                self.isRenamingSelected = true
                                self.isRenameFieldFocused = true
                            } label: {
                                Image(systemName: "pencil")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(tokens.primaryInk.opacity(0.48))
                                    .frame(width: 24, height: 24)
                                    .background(tokens.inset, in: Circle())
                            }
                            .buttonStyle(.plain)
                            .help("重命名")
                        }
                        
                        Spacer(minLength: 8)
                        
                        Text(report.periodLabel)
                            .font(.system(size: 11, weight: .semibold, design: .monospaced).monospacedDigit())
                            .foregroundStyle(tokens.accentText)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(tokens.positivePillBg, in: Capsule())
                        
                        if isCurrentWeek {
                            Text("本周")
                                .font(.system(size: 10.5, weight: .semibold))
                                .foregroundStyle(tokens.onAccentInk)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(tokens.accent, in: Capsule())
                        }
                    }
                    
                    HStack(spacing: 10) {
                        if let range {
                            Label(range, systemImage: "calendar")
                                .font(.system(size: 11.5).monospacedDigit())
                                .foregroundStyle(tokens.primaryInk.opacity(0.60))
                        }
                        
                        Text("\(report.content.count.formatted()) 字")
                            .font(.system(size: 11.5, design: .rounded).monospacedDigit())
                            .foregroundStyle(tokens.primaryInk.opacity(0.55))
                        
                        if report.isEnhanced {
                            Text("AI 润色")
                                .font(.system(size: 10.5, weight: .medium))
                                .foregroundStyle(tokens.accentText)
                        }
                        
                        Spacer(minLength: 8)
                        
                        if isEditingThis {
                            Button("取消") {
                                self.isEditingInline = false
                                self.editingReportID = nil
                            }
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(tokens.primaryInk.opacity(0.75))
                            .padding(.horizontal, 10)
                            .frame(height: 28)
                            .background(tokens.inset, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                            .buttonStyle(.plain)
                            
                            Button("保存修改") {
                                self.db.saveWeeklyReport(
                                    id: report.id,
                                    periodLabel: report.periodLabel,
                                    yearMonth: report.yearMonth,
                                    title: report.title,
                                    content: self.editingDraft,
                                    sourcePath: report.sourcePath
                                )
                                self.state.rebuildGroups()
                                self.isEditingInline = false
                                self.editingReportID = nil
                                self.showToast("周报已保存")
                            }
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(tokens.onAccentInk)
                            .padding(.horizontal, 11)
                            .frame(height: 28)
                            .background(tokens.accent, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                            .buttonStyle(.plain)
                        } else {
                            Button {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(report.content, forType: .string)
                                self.copiedFlag = true
                                self.showToast("已复制周报")
                                DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
                                    self.copiedFlag = false
                                }
                            } label: {
                                Label(self.copiedFlag ? "已复制" : "复制全文", systemImage: self.copiedFlag ? "checkmark" : "doc.on.doc")
                                    .font(.system(size: 11.5, weight: .medium))
                                    .foregroundStyle(tokens.primaryInk.opacity(0.82))
                                    .padding(.horizontal, 10)
                                    .frame(height: 28)
                                    .background(tokens.inset, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .pointerStyle(.link)
                            
                            Button {
                                self.editingReportID = report.id
                                self.editingDraft = report.content
                                self.isEditingInline = true
                            } label: {
                                Label("快速编辑", systemImage: "square.and.pencil")
                                    .font(.system(size: 11.5, weight: .medium))
                                    .foregroundStyle(tokens.primaryInk.opacity(0.82))
                                    .padding(.horizontal, 10)
                                    .frame(height: 28)
                                    .background(tokens.inset, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .pointerStyle(.link)
                            
                            Button {
                                self.delete(report: report, in: self.state.flatReports)
                            } label: {
                                Image(systemName: "trash")
                                    .font(.system(size: 11.5, weight: .medium))
                                    .foregroundStyle(Color.red.opacity(0.80))
                                    .frame(width: 28, height: 28)
                                    .background(tokens.inset, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .pointerStyle(.link)
                            .help("删除周报")
                            
                            Button {
                                self.open(report: report)
                            } label: {
                                Text("在编辑器打开")
                                    .font(.system(size: 11.5, weight: .semibold))
                                    .foregroundStyle(tokens.onAccentInk)
                                    .padding(.horizontal, 12)
                                    .frame(height: 28)
                                    .background(tokens.accent, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .pointerStyle(.link)
                        }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .background(tokens.card.opacity(0.65))
                
                Rectangle()
                    .fill(tokens.hairline)
                    .frame(height: 0.75)
                
                if isEditingThis {
                    TextEditor(text: self.$editingDraft)
                        .font(.system(size: 13.5))
                        .scrollContentBackground(.hidden)
                        .padding(16)
                        .background(Color(nsColor: .textBackgroundColor))
                } else {
                    CenterPreviewTextView(text: report.content, monospace: false)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        } else {
            VStack(spacing: 10) {
                Image(systemName: "doc.richtext")
                    .font(.system(size: 28, weight: .light))
                    .foregroundStyle(tokens.primaryInk.opacity(0.26))
                Text("选择左侧周报以阅读，或点击上方「AI 生成」")
                    .font(.system(size: 13))
                    .foregroundStyle(tokens.primaryInk.opacity(0.50))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
    
    
    // MARK: 3. Clean Two-Column AI Generator Studio
    
    private func generatorWorkbench(tokens: StudioColorTokens) -> some View {
        GeometryReader { geo in
            let isTwoColumns = geo.size.width >= 760
            if isTwoColumns {
                HStack(spacing: 0) {
                    self.generatorInputsColumn(tokens: tokens)
                        .frame(width: min(370, max(290, geo.size.width * 0.40)))
                    
                    Rectangle()
                        .fill(tokens.hairline)
                        .frame(width: 0.75)
                    
                    self.generatorOutputColumn(tokens: tokens)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                ScrollView {
                    VStack(spacing: 12) {
                        self.generatorInputsColumn(tokens: tokens)
                        self.generatorOutputColumn(tokens: tokens)
                            .frame(minHeight: 280)
                    }
                }
            }
        }
    }
    
    
    private func generatorInputsColumn(tokens: StudioColorTokens) -> some View {
        let refs = self.db.styleReferenceWeeklyReports(limit: 2)
        return VStack(spacing: 0) {
            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 12) {
                    // Author & Period Card
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("署名与周期")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(tokens.primaryInk)
                            Spacer()
                            Text(AIService.currentWeekPeriodLabel())
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .foregroundStyle(tokens.accentText)
                        }
                        
                        TextField("署名", text: self.$state.authorName)
                            .textFieldStyle(.roundedBorder)
                            .onChange(of: self.state.authorName) { _, newVal in
                                let trimmed = newVal.trimmingCharacters(in: .whitespacesAndNewlines)
                                if !trimmed.isEmpty {
                                    self.db.weeklyReportAuthor = trimmed
                                }
                            }
                        
                        if !refs.isEmpty {
                            Text("自动对齐历史风格：\(refs.map(\.periodLabel).joined(separator: "、"))")
                                .font(.system(size: 11))
                                .foregroundStyle(tokens.primaryInk.opacity(0.54))
                        }
                    }
                    .padding(12)
                    .background(tokens.card, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(tokens.hairline, lineWidth: 0.7))
                    
                    // Open Editor Tabs Material Selector
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("打开的文档素材")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(tokens.primaryInk)
                            Spacer()
                            Button("刷新") {
                                self.state.refreshOpenSources()
                            }
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(tokens.accentText)
                            .buttonStyle(.plain)
                            .pointerStyle(.link)
                        }
                        
                        if self.state.openSources.isEmpty {
                            Text("当前没有已打开的编辑器文档")
                                .font(.system(size: 11.5))
                                .foregroundStyle(tokens.primaryInk.opacity(0.46))
                        } else {
                            ForEach(self.$state.openSources) { $source in
                                Toggle(isOn: $source.isSelected) {
                                    HStack {
                                        Text(source.title)
                                            .font(.system(size: 12))
                                            .lineLimit(1)
                                        Spacer()
                                        Text("\(source.content.count) 字")
                                            .font(.system(size: 10.5, design: .rounded).monospacedDigit())
                                            .foregroundStyle(tokens.primaryInk.opacity(0.45))
                                    }
                                }
                            }
                        }
                    }
                    .padding(12)
                    .background(tokens.card, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(tokens.hairline, lineWidth: 0.7))
                    
                    // Custom Notes
                    VStack(alignment: .leading, spacing: 6) {
                        Text("本周补充记录与卡点")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(tokens.primaryInk)
                        TextEditor(text: self.$state.customNotes)
                            .font(.system(size: 12.5))
                            .scrollContentBackground(.hidden)
                            .padding(8)
                            .frame(minHeight: 88, maxHeight: 140)
                            .background(tokens.inset, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .padding(12)
                    .background(tokens.card, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(tokens.hairline, lineWidth: 0.7))
                    
                    // Accumulated Fragments
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("日常积累素材片段")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(tokens.primaryInk)
                            Spacer()
                            if !self.state.fragmentsText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                Button("清空缓存") {
                                    self.db.clearWeeklyReportFragments()
                                    self.state.fragmentsText = ""
                                }
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(tokens.primaryInk.opacity(0.58))
                                .buttonStyle(.plain)
                            }
                        }
                        TextEditor(text: self.$state.fragmentsText)
                            .font(.system(size: 12))
                            .scrollContentBackground(.hidden)
                            .padding(8)
                            .frame(minHeight: 68, maxHeight: 110)
                            .background(tokens.inset, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .padding(12)
                    .background(tokens.card, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(tokens.hairline, lineWidth: 0.7))
                    
                    if let error = self.state.generationError {
                        Text(error)
                            .font(.system(size: 11.5))
                            .foregroundStyle(Color.red)
                            .padding(.horizontal, 4)
                    }
                }
                .padding(14)
            }
            
            Rectangle()
                .fill(tokens.hairline)
                .frame(height: 0.75)
            
            Button {
                self.runWeeklyReportGeneration()
            } label: {
                HStack(spacing: 6) {
                    if self.state.isGenerating {
                        ProgressView().controlSize(.small)
                        Text("正在生成本周周报…")
                    } else {
                        Image(systemName: "sparkles")
                        Text("生成本周周报")
                    }
                }
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(tokens.onAccentInk)
                .frame(maxWidth: .infinity)
                .frame(height: 34)
                .background(tokens.accent, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            }
            .buttonStyle(.plain)
            .pointerStyle(.link)
            .disabled(self.state.isGenerating)
            .padding(12)
        }
        .background(tokens.inset.opacity(0.38))
    }
    
    
    private func generatorOutputColumn(tokens: StudioColorTokens) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("生成预览（可直接微调）")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(tokens.primaryInk.opacity(0.84))
                
                Spacer()
                
                if !self.state.generatedOutput.isEmpty {
                    Button {
                        let saved = self.db.saveGeneratedWeeklyReport(content: self.state.generatedOutput)
                        self.state.rebuildGroups()
                        self.state.selectedReportID = saved.id
                        self.state.isGeneratorActive = false
                        self.showToast("已存入周报库：\(saved.periodLabel)")
                    } label: {
                        Text("仅存入周报库")
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(tokens.primaryInk.opacity(0.84))
                            .padding(.horizontal, 10)
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
                    } label: {
                        Text("存入并在编辑器打开")
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(tokens.onAccentInk)
                            .padding(.horizontal, 11)
                            .frame(height: 28)
                            .background(tokens.accent, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .pointerStyle(.link)
                }
            }
            .padding(.horizontal, 16)
            .frame(height: 44)
            .background(tokens.card.opacity(0.65))
            
            Rectangle()
                .fill(tokens.hairline)
                .frame(height: 0.75)
            
            if self.state.generatedOutput.isEmpty && !self.state.isGenerating {
                VStack(spacing: 10) {
                    Image(systemName: "text.alignleft")
                        .font(.system(size: 28, weight: .light))
                        .foregroundStyle(tokens.primaryInk.opacity(0.24))
                    Text("勾选左侧文档或填写工作记录，点击「生成本周周报」")
                        .font(.system(size: 13))
                        .foregroundStyle(tokens.primaryInk.opacity(0.48))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                TextEditor(text: self.$state.generatedOutput)
                    .font(.system(size: 13.5))
                    .scrollContentBackground(.hidden)
                    .padding(16)
                    .background(Color(nsColor: .textBackgroundColor))
            }
        }
    }
    
    
    // MARK: Helpers & Keyboard Navigation
    
    private func selectedReport(in flatReports: [StoredWeeklyReport]) -> StoredWeeklyReport? {
        if let id = self.state.selectedReportID,
           let match = flatReports.first(where: { $0.id == id })
        {
            return match
        }
        return flatReports.first
    }
    
    
    private static func cleanExcerpt(_ content: String, limit: Int = 64) -> String {
        let line = content
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty && !$0.hasPrefix("#") && !$0.hasPrefix("---") }) ?? ""
        if line.count <= limit { return line }
        return String(line.prefix(limit - 1)) + "…"
    }
    
    
    private func installKeyboardMonitor() {
        self.removeKeyboardMonitor()
        self.keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if NSApp.keyWindow?.firstResponder is NSTextView {
                return event
            }
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            guard flags.isDisjoint(with: [.command, .control, .option]) else { return event }
            
            switch event.keyCode {
                case 53: // Esc
                    if self.handleEscapePop() {
                        return nil
                    }
                    if let onDismiss = self.onDismiss {
                        onDismiss()
                        return nil
                    }
                    return event
                    
                case 36: // Return -> Open selected report in editor
                    if !self.state.isGeneratorActive, !self.isRenamingSelected, !self.isEditingInline,
                       let active = self.selectedReport(in: self.state.flatReports)
                    {
                        self.open(report: active)
                        return nil
                    }
                    return event
                    
                case 126:
                    guard !self.state.isGeneratorActive, !self.isEditingInline else { return event }
                    self.stepSelection(by: -1, in: self.state.flatReports)
                    return nil
                    
                case 125:
                    guard !self.state.isGeneratorActive, !self.isEditingInline else { return event }
                    self.stepSelection(by: 1, in: self.state.flatReports)
                    return nil
                    
                default:
                    return event
            }
        }
    }
    
    
    private func removeKeyboardMonitor() {
        if let monitor = self.keyMonitor {
            NSEvent.removeMonitor(monitor)
            self.keyMonitor = nil
        }
    }
    
    
    private func stepSelection(by delta: Int, in list: [StoredWeeklyReport]) {
        guard !list.isEmpty else { return }
        if let currentID = self.state.selectedReportID,
           let idx = list.firstIndex(where: { $0.id == currentID })
        {
            let next = (idx + delta + list.count) % list.count
            self.state.selectedReportID = list[next].id
        } else {
            self.state.selectedReportID = list.first?.id
        }
    }
    
    
    // MARK: Actions
    
    private func createWeeklyReport(weekOffset: Int) {
        let result = self.db.createWeeklyReport(weekOffset: weekOffset, includeSavedFragments: true)
        self.state.collapsedMonths.remove(result.report.yearMonth)
        self.state.searchText = ""
        self.state.rebuildGroups()
        self.state.isGeneratorActive = false
        self.state.selectedReportID = result.report.id
        self.editingReportID = result.report.id
        self.editingDraft = result.report.content
        self.isEditingInline = true
        
        if result.alreadyExisted {
            self.showToast("本周报「\(result.report.periodLabel)」已存在，已定位到预览编辑")
        } else {
            self.showToast("已新建周报「\(result.report.periodLabel)」")
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
        return "\(startM)/\(startD)-\(endM)/\(endD)"
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
        self.isEditingInline = false
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
            self.state.generationError = "请至少勾选一份文档、或在输入框填几条本周做过的事。"
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
