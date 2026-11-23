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




// MARK: - Structured Star-Map Weekly Report Center

struct WeeklyReportCenterView: View {
    
    @Bindable var state: WeeklyReportCenterState
    var onOpenReport: ((StoredWeeklyReport) -> Void)?
    var onDismiss: (() -> Void)?
    
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.registerWorkspaceCenterEscPop) private var registerEscPop
    @State private var db = CotLocalDatabase.shared
    @State private var focusedMonthID: String?
    @State private var isQuickLookOpen = false
    @State private var isEditingQuickLook = false
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
        let groups = self.state.groups
        let flatReports = self.state.flatReports
        let activeReport = self.selectedReport(in: flatReports)
        let tokens = DashPalette.editorialTokens(isDark: self.colorScheme == .dark)
        let currentWeek = AIService.currentWeekPeriodLabel()
        let clusters = self.buildStarClusters(groups: groups, currentWeek: currentWeek, tokens: tokens)
        let reportByID = Dictionary(uniqueKeysWithValues: flatReports.map { ($0.id, $0) })
        
        ZStack {
            ConstellationStarMapView(
                hubTitle: "周报星图",
                hubSubtitle: "\(flatReports.count) 篇 · \(groups.count) 个月",
                clusters: clusters,
                selectedLeafID: activeReport?.id,
                focusedClusterID: self.focusedMonthID,
                searchQuery: self.state.searchText,
                onSelectLeaf: { id in
                    self.isRenamingSelected = false
                    self.state.selectedReportID = id
                },
                onDoubleClickLeaf: { id in
                    if let report = reportByID[id] {
                        self.open(report: report)
                    }
                },
                onToggleCluster: { monthID in
                    if self.state.collapsedMonths.contains(monthID) {
                        self.state.collapsedMonths.remove(monthID)
                    } else {
                        self.state.collapsedMonths.insert(monthID)
                    }
                },
                clusterContextMenu: { cluster in
                    Button(cluster.isCollapsed ? "展开此月份" : "收起此月份") {
                        if self.state.collapsedMonths.contains(cluster.id) {
                            self.state.collapsedMonths.remove(cluster.id)
                        } else {
                            self.state.collapsedMonths.insert(cluster.id)
                        }
                    }
                },
                leafContextMenu: { leaf in
                    if let report = reportByID[leaf.id] {
                        Button("在编辑器打开") { self.open(report: report) }
                        Button("预览") {
                            self.state.selectedReportID = report.id
                            self.isEditingQuickLook = false
                            withAnimation(.easeOut(duration: 0.16)) { self.isQuickLookOpen = true }
                        }
                        Button("重命名") {
                            self.state.selectedReportID = report.id
                            self.renameDraft = report.title
                            self.isRenamingSelected = true
                            DispatchQueue.main.async { self.isRenameFieldFocused = true }
                        }
                        Divider()
                        Button("删除", role: .destructive) {
                            self.delete(report: report, in: flatReports)
                        }
                    }
                }
            )
            
            // Minimal Floating Top Bar + Month Quick-Jump Strip + Bottom Focus Dock
            VStack(spacing: 8) {
                self.floatingTopBar(tokens: tokens)
                    .padding(.horizontal, 16)
                    .padding(.top, 14)
                
                if clusters.count > 1 && !self.state.isGeneratorActive {
                    self.monthQuickJumpStrip(clusters: clusters, tokens: tokens)
                        .padding(.horizontal, 16)
                }
                
                Spacer()
                
                if let activeReport, !self.state.isGeneratorActive {
                    self.bottomFocusDock(report: activeReport, flatReports: flatReports, currentWeek: currentWeek, tokens: tokens)
                        .padding(.bottom, 16)
                } else if flatReports.isEmpty && !self.state.isGeneratorActive {
                    self.floatingEmptyHint(tokens: tokens)
                        .padding(.bottom, 22)
                }
            }
            
            // Spacebar QuickLook Preview & Quick-Edit Overlay
            if self.isQuickLookOpen, let report = activeReport {
                self.quickLookOverlay(report: report, flatReports: flatReports, tokens: tokens)
            }
            
            // Focused AI Weekly Report Generator Sheet
            if self.state.isGeneratorActive {
                self.generatorOverlay(tokens: tokens)
            }
            
            if let toastMessage {
                VStack {
                    Spacer()
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
                    .shadow(color: tokens.cardShadow, radius: 10, y: 4)
                    .padding(.bottom, 74)
                }
                .allowsHitTesting(false)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
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
    
    
    // MARK: Floating HUDs
    
    private func floatingTopBar(tokens: StudioColorTokens) -> some View {
        HStack(spacing: 10) {
            if let onDismiss = self.onDismiss {
                Button(action: onDismiss) {
                    HStack(spacing: 5) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 10.5, weight: .semibold))
                        Text("返回编辑")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundStyle(tokens.primaryInk.opacity(0.84))
                    .padding(.horizontal, 11)
                    .frame(height: 32)
                    .background(tokens.card, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(tokens.hairlineStrong, lineWidth: 0.75))
                    .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
                .pointerStyle(.link)
            }
            
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(tokens.primaryInk.opacity(0.45))
                TextField("搜索周期、月份或内容…", text: self.$state.searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12.5))
                    .frame(width: 175)
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
            .padding(.horizontal, 10)
            .frame(height: 32)
            .background(tokens.card, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(tokens.hairlineStrong, lineWidth: 0.75))
            
            Spacer(minLength: 8)
            
            HStack(spacing: 6) {
                Button {
                    self.state.refreshOpenSources()
                    self.isQuickLookOpen = false
                    withAnimation(.easeOut(duration: 0.18)) {
                        self.state.isGeneratorActive = true
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 10.5, weight: .semibold))
                        Text("AI 生成周报")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(tokens.onAccentInk)
                    .padding(.horizontal, 12)
                    .frame(height: 30)
                    .background(tokens.accent, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
                .pointerStyle(.link)
                
                Menu {
                    Button("新建本周周报（\(AIService.currentWeekPeriodLabel())）") {
                        self.createWeeklyReport(weekOffset: 0)
                    }
                    Button("补建上周周报") {
                        self.createWeeklyReport(weekOffset: -1)
                    }
                } label: {
                    Text("新建周报")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(tokens.primaryInk.opacity(0.82))
                        .padding(.horizontal, 10)
                        .frame(height: 30)
                        .background(tokens.card, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(tokens.hairlineStrong, lineWidth: 0.75))
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .pointerStyle(.link)
                
                Button {
                    self.runImportPanel()
                } label: {
                    Text("导入")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(tokens.primaryInk.opacity(0.76))
                        .padding(.horizontal, 10)
                        .frame(height: 30)
                        .background(tokens.card, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(tokens.hairlineStrong, lineWidth: 0.75))
                        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
                .pointerStyle(.link)
            }
        }
    }
    
    
    private func monthQuickJumpStrip(clusters: [StarMapClusterNode], tokens: StudioColorTokens) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                let allSelected = (self.focusedMonthID == nil)
                Button {
                    self.focusedMonthID = nil
                } label: {
                    Text("全部月份")
                        .font(.system(size: 11.5, weight: allSelected ? .semibold : .medium))
                        .foregroundStyle(allSelected ? tokens.onAccentInk : tokens.primaryInk.opacity(0.76))
                        .padding(.horizontal, 10)
                        .frame(height: 25)
                        .background(allSelected ? tokens.accent : tokens.card.opacity(0.92), in: Capsule())
                        .overlay(Capsule().strokeBorder(allSelected ? Color.clear : tokens.hairline, lineWidth: 0.75))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .pointerStyle(.link)
                
                ForEach(clusters) { cluster in
                    let isFocused = (self.focusedMonthID == cluster.id)
                    Button {
                        if self.state.collapsedMonths.contains(cluster.id) {
                            self.state.collapsedMonths.remove(cluster.id)
                        }
                        self.focusedMonthID = isFocused ? nil : cluster.id
                    } label: {
                        HStack(spacing: 5) {
                            Circle()
                                .fill(isFocused ? tokens.onAccentInk : cluster.accent)
                                .frame(width: 5.5, height: 5.5)
                            Text(cluster.title)
                                .font(.system(size: 11.5, weight: isFocused ? .semibold : .medium))
                            Text(cluster.countText)
                                .font(.system(size: 10, weight: .medium, design: .rounded).monospacedDigit())
                                .opacity(0.75)
                        }
                        .foregroundStyle(isFocused ? tokens.onAccentInk : tokens.primaryInk.opacity(0.80))
                        .padding(.horizontal, 10)
                        .frame(height: 25)
                        .background(isFocused ? tokens.accent : tokens.card.opacity(0.92), in: Capsule())
                        .overlay(Capsule().strokeBorder(isFocused ? Color.clear : tokens.hairline, lineWidth: 0.75))
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .pointerStyle(.link)
                }
            }
        }
    }
    
    
    private func bottomFocusDock(
        report: StoredWeeklyReport,
        flatReports: [StoredWeeklyReport],
        currentWeek: String,
        tokens: StudioColorTokens
    ) -> some View {
        let isCurrent = (report.periodLabel == currentWeek)
        let rangeDesc = Self.readablePeriodRange(report.periodLabel)
        
        return HStack(spacing: 10) {
            Circle()
                .fill(isCurrent ? tokens.accent : tokens.secondaryAccent)
                .frame(width: 7, height: 7)
            
            if self.isRenamingSelected {
                TextField("周报标题", text: self.$renameDraft)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12.5, weight: .semibold))
                    .focused(self.$isRenameFieldFocused)
                    .frame(width: 185)
                    .onSubmit { self.commitReportRename(report) }
                    .onExitCommand { self.isRenamingSelected = false }
                
                Button("保存") { self.commitReportRename(report) }
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(tokens.onAccentInk)
                    .padding(.horizontal, 9)
                    .frame(height: 24)
                    .background(tokens.accent, in: Capsule())
                    .buttonStyle(.plain)
                
                Button("取消") { self.isRenamingSelected = false }
                    .font(.system(size: 11))
                    .foregroundStyle(tokens.primaryInk.opacity(0.62))
                    .buttonStyle(.plain)
            } else {
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 5) {
                        Text(report.periodLabel)
                            .font(.system(size: 12.5, weight: .semibold, design: .rounded).monospacedDigit())
                            .foregroundStyle(tokens.primaryInk)
                            .lineLimit(1)
                        if isCurrent {
                            Text("本周")
                                .font(.system(size: 9.5, weight: .semibold))
                                .foregroundStyle(tokens.accentText)
                                .padding(.horizontal, 5.5)
                                .padding(.vertical, 1)
                                .background(tokens.positivePillBg, in: Capsule())
                        }
                    }
                    Text((rangeDesc.map { "\($0) · " } ?? "") + "\(report.content.count.formatted()) 字")
                        .font(.system(size: 10, weight: .medium, design: .rounded).monospacedDigit())
                        .foregroundStyle(tokens.primaryInk.opacity(0.50))
                        .lineLimit(1)
                }
                
                Rectangle()
                    .fill(tokens.hairlineStrong)
                    .frame(width: 1, height: 20)
                
                Button {
                    self.isEditingQuickLook = false
                    withAnimation(.easeOut(duration: 0.16)) { self.isQuickLookOpen = true }
                } label: {
                    Text("预览")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(tokens.primaryInk.opacity(0.86))
                        .padding(.horizontal, 10)
                        .frame(height: 26)
                        .background(tokens.inset, in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .pointerStyle(.link)
                
                Button {
                    self.open(report: report)
                } label: {
                    Text("打开")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(tokens.onAccentInk)
                        .padding(.horizontal, 12)
                        .frame(height: 26)
                        .background(tokens.accent, in: Capsule())
                }
                .buttonStyle(.plain)
                .pointerStyle(.link)
                
                Button {
                    self.renameDraft = report.title
                    self.isRenamingSelected = true
                    DispatchQueue.main.async { self.isRenameFieldFocused = true }
                } label: {
                    Text("重命名")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(tokens.primaryInk.opacity(0.78))
                        .padding(.horizontal, 9)
                        .frame(height: 26)
                        .background(tokens.inset, in: Capsule())
                }
                .buttonStyle(.plain)
                .pointerStyle(.link)
                
                Button {
                    self.delete(report: report, in: flatReports)
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(tokens.primaryInk.opacity(0.62))
                        .frame(width: 26, height: 26)
                        .background(tokens.inset, in: Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .pointerStyle(.link)
                .help("删除此周报")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(tokens.card, in: Capsule())
        .overlay(Capsule().strokeBorder(tokens.hairlineStrong, lineWidth: 0.85))
        .shadow(color: tokens.cardShadow, radius: 14, y: 4)
    }
    
    
    private func floatingEmptyHint(tokens: StudioColorTokens) -> some View {
        HStack(spacing: 10) {
            Text(self.state.searchText.isEmpty ? "还没有历史周报" : "没有匹配的周报")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(tokens.primaryInk.opacity(0.62))
            if self.state.searchText.isEmpty {
                Button("新建本周周报") {
                    self.createWeeklyReport(weekOffset: 0)
                }
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(tokens.onAccentInk)
                .padding(.horizontal, 11)
                .frame(height: 26)
                .background(tokens.accent, in: Capsule())
                .buttonStyle(.plain)
                .pointerStyle(.link)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(tokens.card, in: Capsule())
        .overlay(Capsule().strokeBorder(tokens.hairlineStrong, lineWidth: 0.75))
    }
    
    
    // MARK: Constellation Data Mapping
    
    private func buildStarClusters(
        groups: [WeeklyReportCenterState.YearMonthGroup],
        currentWeek: String,
        tokens: StudioColorTokens
    ) -> [StarMapClusterNode] {
        let monthAccents: [Color] = [
            tokens.accent,
            tokens.secondaryAccent,
            Color(red: 0.212, green: 0.478, blue: 0.612),
            tokens.heat3,
        ]
        
        let maxChars = max(1.0, Double(self.state.flatReports.map { $0.content.count }.max() ?? 1))
        return groups.enumerated().map { idx, group in
            let accent = monthAccents[idx % monthAccents.count]
            let leaves = group.reports.map { report -> StarMapLeafNode in
                let isCurrent = (report.periodLabel == currentWeek)
                let rangeDesc = Self.readablePeriodRange(report.periodLabel)
                let w = min(1.0, max(0.2, Double(report.content.count) / maxChars))
                let meta = (rangeDesc.map { "\($0) · " } ?? "") + "\(report.content.count)字"
                return StarMapLeafNode(
                    id: report.id,
                    clusterID: group.month,
                    title: report.periodLabel,
                    metaLine: meta,
                    statusBadge: isCurrent ? "本周" : nil,
                    dotColor: isCurrent ? tokens.accent : accent.opacity(0.85),
                    weight: w,
                    isHighlighted: isCurrent
                )
            }
            return StarMapClusterNode(
                id: group.month,
                title: Self.formatYearMonthTitle(group.month),
                countText: "\(leaves.count)",
                accent: accent,
                isCollapsed: self.state.collapsedMonths.contains(group.month),
                leaves: leaves
            )
        }
    }
    
    
    private func selectedReport(in flatReports: [StoredWeeklyReport]) -> StoredWeeklyReport? {
        if let id = self.state.selectedReportID, let match = flatReports.first(where: { $0.id == id }) {
            return match
        }
        return flatReports.first
    }
    
    
    // MARK: Keyboard Navigation
    
    private func handleEscapePop() -> Bool {
        if self.state.isGeneratorActive {
            withAnimation(.easeOut(duration: 0.16)) { self.state.isGeneratorActive = false }
            return true
        }
        if self.isQuickLookOpen {
            self.isEditingQuickLook = false
            withAnimation(.easeOut(duration: 0.14)) { self.isQuickLookOpen = false }
            return true
        }
        if self.isRenamingSelected {
            self.isRenamingSelected = false
            return true
        }
        if self.focusedMonthID != nil {
            self.focusedMonthID = nil
            return true
        }
        return false
    }
    
    
    private func installKeyboardMonitor() {
        self.removeKeyboardMonitor()
        self.keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [self] event in
            if self.state.isGeneratorActive || self.isEditingQuickLook {
                return event
            }
            if let responder = NSApp.keyWindow?.firstResponder, responder is NSTextView {
                return event
            }
            let list = self.state.flatReports
            guard !list.isEmpty else { return event }
            
            switch event.keyCode {
                case 49: // Spacebar QuickLook
                    if self.selectedReport(in: list) != nil {
                        self.isEditingQuickLook = false
                        withAnimation(.easeOut(duration: 0.15)) {
                            self.isQuickLookOpen.toggle()
                        }
                        return nil
                    }
                case 123, 126:
                    self.stepSelection(by: -1, in: list)
                    return nil
                case 124, 125:
                    self.stepSelection(by: 1, in: list)
                    return nil
                case 36:
                    if let active = self.selectedReport(in: list) {
                        self.isQuickLookOpen = false
                        self.open(report: active)
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
    
    
    private func stepSelection(by delta: Int, in list: [StoredWeeklyReport]) {
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
                    withAnimation(.easeOut(duration: 0.16)) { self.state.isGeneratorActive = false }
                }
            
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(tokens.accent)
                    Text("AI 生成本周周报 · \(AIService.currentWeekPeriodLabel())")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(tokens.primaryInk)
                    Spacer()
                    Button {
                        withAnimation(.easeOut(duration: 0.16)) { self.state.isGeneratorActive = false }
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
                .frame(height: 50)
                
                Rectangle().fill(tokens.hairline).frame(height: 1)
                
                HStack(spacing: 0) {
                    // Left compact inputs
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
                                            .background(tokens.inset, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                                            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
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
                                    .background(tokens.inset, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
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
                                        .background(tokens.inset, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
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
                                    Text(self.state.isGenerating ? "正在生成…" : "一键生成周报")
                                        .font(.system(size: 12.5, weight: .semibold))
                                }
                                .foregroundStyle(tokens.onAccentInk)
                                .frame(maxWidth: .infinity, minHeight: 34)
                                .background(tokens.accent, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                                .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .pointerStyle(.link)
                            .disabled(self.state.isGenerating)
                        }
                        .padding(16)
                    }
                    .frame(width: 280)
                    
                    Rectangle().fill(tokens.hairline).frame(width: 1)
                    
                    // Right live output
                    VStack(spacing: 0) {
                        if self.state.generatedOutput.isEmpty {
                            VStack(spacing: 8) {
                                Image(systemName: "doc.text.magnifyingglass")
                                    .font(.system(size: 24, weight: .light))
                                    .foregroundStyle(tokens.primaryInk.opacity(0.28))
                                Text("点击左侧「一键生成周报」即可开始")
                                    .font(.system(size: 12.5))
                                    .foregroundStyle(tokens.primaryInk.opacity(0.48))
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
                                    self.showToast("已复制周报内容")
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
                                    self.showToast("已保存并打开周报")
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
            .background(tokens.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(tokens.hairlineStrong, lineWidth: 1))
            .shadow(color: Color.black.opacity(self.colorScheme == .dark ? 0.55 : 0.20), radius: 28, y: 12)
            .padding(24)
        }
        .transition(.opacity.combined(with: .scale(scale: 0.97)))
    }
    
    
    @ViewBuilder
    private func quickLookOverlay(
        report: StoredWeeklyReport,
        flatReports: [StoredWeeklyReport],
        tokens: StudioColorTokens
    ) -> some View {
        let idx = flatReports.firstIndex(where: { $0.id == report.id }) ?? 0
        let rangeDesc = Self.readablePeriodRange(report.periodLabel)
        let subtitle = "\(report.periodLabel)" + (rangeDesc.map { " · \($0)" } ?? "") + " · \(report.content.count.formatted()) 字"
        
        StarMapQuickLookOverlay(
            title: report.title,
            subtitle: subtitle,
            canStepPrevious: idx > 0,
            canStepNext: idx + 1 < flatReports.count,
            onPrevious: {
                self.isEditingQuickLook = false
                self.stepSelection(by: -1, in: flatReports)
            },
            onNext: {
                self.isEditingQuickLook = false
                self.stepSelection(by: 1, in: flatReports)
            },
            onClose: {
                self.isEditingQuickLook = false
                withAnimation(.easeOut(duration: 0.14)) { self.isQuickLookOpen = false }
            },
            headerActions: {
                if self.isEditingQuickLook {
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
                        self.isEditingQuickLook = false
                        self.showToast("已保存周报修改")
                    } label: {
                        Text("保存")
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(tokens.onAccentInk)
                            .padding(.horizontal, 11)
                            .frame(height: 26)
                            .background(tokens.accent, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .pointerStyle(.link)
                    
                    Button {
                        self.isEditingQuickLook = false
                    } label: {
                        Text("取消")
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(tokens.primaryInk.opacity(0.76))
                            .padding(.horizontal, 9)
                            .frame(height: 26)
                            .background(tokens.inset, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .pointerStyle(.link)
                } else {
                    Button {
                        self.editingReportID = report.id
                        self.editingDraft = report.content
                        self.isEditingQuickLook = true
                    } label: {
                        Text("编辑")
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(tokens.primaryInk.opacity(0.84))
                            .padding(.horizontal, 10)
                            .frame(height: 26)
                            .background(tokens.inset, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .pointerStyle(.link)
                    
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(report.content, forType: .string)
                        self.copiedFlag = true
                        self.showToast("已复制周报")
                        Task {
                            try? await Task.sleep(for: .seconds(1.5))
                            self.copiedFlag = false
                        }
                    } label: {
                        Text(self.copiedFlag ? "已复制" : "复制")
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(tokens.primaryInk.opacity(0.84))
                            .padding(.horizontal, 10)
                            .frame(height: 26)
                            .background(tokens.inset, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .pointerStyle(.link)
                    
                    Button {
                        self.isQuickLookOpen = false
                        self.open(report: report)
                    } label: {
                        Text("在编辑器打开")
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(tokens.onAccentInk)
                            .padding(.horizontal, 11)
                            .frame(height: 26)
                            .background(tokens.accent, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .pointerStyle(.link)
                }
            },
            bodyContent: {
                if self.isEditingQuickLook {
                    TextEditor(text: self.$editingDraft)
                        .font(.system(size: 13))
                        .scrollContentBackground(.hidden)
                        .padding(16)
                        .background(Color(nsColor: .textBackgroundColor))
                } else {
                    CenterPreviewTextView(text: report.content)
                        .id("weekly-ql-\(report.id)")
                }
            }
        )
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
        self.isEditingQuickLook = true
        self.isQuickLookOpen = true
        
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
        self.isEditingQuickLook = false
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
            self.state.generationError = "尚未配置 AI 模型与 API Key，请先打开「设置 → API 网关」完成配置。"
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
