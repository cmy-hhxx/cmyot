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
    var collapsedClusterIDs: Set<String> = []
    var groups: [YearMonthGroup] = []
    var flatReports: [StoredWeeklyReport] = []
    var displayedRows: [ReportRowItem] = []
    var relations: [StarMapRelationEdge] = []
    var searchHits: [StarMapSearchHit] = []
    var searchMatchesByID: [String: StarMapSearchEngine.MatchEvaluation] = [:]
    
    // Generator fields
    var authorName: String = CotLocalDatabase.shared.weeklyReportAuthor
    var customNotes: String = ""
    var fragmentsText: String = CotLocalDatabase.shared.string(forKey: CotLocalDatabase.ConfigKey.weeklyReportFragments)
    var openSources: [OpenSourceItem] = []
    var generatedOutput: String = ""
    var isGenerating: Bool = false
    var generationError: String?
    
    private(set) var allRowItems: [ReportRowItem] = []
    @ObservationIgnored private var cachedRelationsCorpusKey: String = ""
    
    func rebuildGroups() {
        let allReports = CotLocalDatabase.shared.weeklyReports
        let currentWeek = AIService.currentWeekPeriodLabel()
        
        // 1. Discover cross-report topic, title-mention, and consecutive-week relationships across full corpus.
        let corpusKey = allReports.map {
            "\($0.id)|\($0.updatedAt.timeIntervalSince1970)|\($0.content.count)|\($0.title)|\($0.periodLabel)"
        }.joined(separator: ";")
        
        let builtRelations: [StarMapRelationEdge]
        if corpusKey == self.cachedRelationsCorpusKey {
            builtRelations = self.relations
        } else {
            let corpusDocs = allReports.map { report in
                StarMapRelationEngine.CorpusDocument(
                    id: report.id,
                    title: "\(report.periodLabel) \(report.title)",
                    group: Self.formatYearMonthTitle(report.yearMonth),
                    folderPath: report.yearMonth,
                    content: report.content,
                    sortTimestamp: report.updatedAt.timeIntervalSince1970
                )
            }
            var computed = StarMapRelationEngine.buildRelations(for: corpusDocs, maxEdgesPerNode: 3)
            
            var existingPairs = Set<String>()
            var incidentDegree: [String: Int] = [:]
            for edge in computed {
                let key = edge.sourceID < edge.targetID
                    ? "\(edge.sourceID)|\(edge.targetID)"
                    : "\(edge.targetID)|\(edge.sourceID)"
                existingPairs.insert(key)
                incidentDegree[edge.sourceID, default: 0] += 1
                incidentDegree[edge.targetID, default: 0] += 1
            }
            
            let chronoReports = allReports.sorted { lhs, rhs in
                if lhs.periodLabel != rhs.periodLabel {
                    return lhs.periodLabel < rhs.periodLabel
                }
                return lhs.updatedAt < rhs.updatedAt
            }
            if chronoReports.count >= 2 {
                for idx in 0..<(chronoReports.count - 1) {
                    let a = chronoReports[idx].id
                    let b = chronoReports[idx + 1].id
                    let key = a < b ? "\(a)|\(b)" : "\(b)|\(a)"
                    guard !existingPairs.contains(key) else { continue }
                    guard incidentDegree[a, default: 0] < 3 || incidentDegree[b, default: 0] < 3 else { continue }
                    existingPairs.insert(key)
                    incidentDegree[a, default: 0] += 1
                    incidentDegree[b, default: 0] += 1
                    computed.append(
                        StarMapRelationEdge(
                            sourceID: a,
                            targetID: b,
                            strength: 0.44,
                            reason: "相邻周次"
                        )
                    )
                }
            }
            self.cachedRelationsCorpusKey = corpusKey
            self.relations = computed
            builtRelations = computed
        }
        
        // 2. Full-text multi-keyword search with 1-hop relation neighbor retention.
        let terms = StarMapSearchEngine.parseTerms(self.searchText)
        let filtered: [StoredWeeklyReport]
        if terms.isEmpty {
            self.searchMatchesByID = [:]
            self.searchHits = []
            filtered = allReports
        } else {
            var matchesByID: [String: StarMapSearchEngine.MatchEvaluation] = [:]
            var scoredHits: [(hit: StarMapSearchHit, updatedAt: TimeInterval)] = []
            
            for report in allReports {
                let monthTitle = Self.formatYearMonthTitle(report.yearMonth)
                let meta = [report.periodLabel, Self.readablePeriodRange(report.periodLabel)]
                    .compactMap { $0 }
                    .joined(separator: " ")
                let evaluation = StarMapSearchEngine.evaluate(
                    queryTerms: terms,
                    title: report.title,
                    category: monthTitle,
                    secondaryMeta: meta,
                    content: report.content
                )
                guard evaluation.isMatch else { continue }
                matchesByID[report.id] = evaluation
                let rangeDesc = Self.readablePeriodRange(report.periodLabel)
                let metaLine = (rangeDesc.map { "\($0) · " } ?? "\(report.periodLabel) · ")
                    + DocumentCenterState.compactChars(report.content.count)
                scoredHits.append((
                    hit: StarMapSearchHit(
                        id: report.id,
                        title: report.title,
                        categoryLabel: monthTitle,
                        metaLabel: metaLine,
                        totalHits: evaluation.totalHits,
                        score: evaluation.score,
                        snippet: evaluation.snippet
                    ),
                    updatedAt: report.updatedAt.timeIntervalSince1970
                ))
            }
            
            scoredHits.sort { lhs, rhs in
                if lhs.hit.score != rhs.hit.score {
                    return lhs.hit.score > rhs.hit.score
                }
                if lhs.hit.totalHits != rhs.hit.totalHits {
                    return lhs.hit.totalHits > rhs.hit.totalHits
                }
                return lhs.updatedAt > rhs.updatedAt
            }
            self.searchMatchesByID = matchesByID
            self.searchHits = scoredHits.map(\.hit)
            
            let directIDs = Set(matchesByID.keys)
            var visibleIDs = directIDs
            for edge in builtRelations {
                if directIDs.contains(edge.sourceID) {
                    visibleIDs.insert(edge.targetID)
                } else if directIDs.contains(edge.targetID) {
                    visibleIDs.insert(edge.sourceID)
                }
            }
            filtered = allReports.filter { visibleIDs.contains($0.id) }
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
        
        if !self.searchHits.isEmpty {
            if let selectedReportID,
               self.searchMatchesByID[selectedReportID] != nil,
               visible.contains(where: { $0.id == selectedReportID }) {
                return
            }
            if let topHit = self.searchHits.first(where: { hit in visible.contains(where: { $0.id == hit.id }) }) {
                self.selectedReportID = topHit.id
                return
            }
        }
        
        if let selectedReportID, visible.contains(where: { $0.id == selectedReportID }) {
            return
        }
        self.selectedReportID = visible.first?.id ?? self.allRowItems.first?.id
    }
    
    
    func relatedRows(for reportID: String, in pool: [ReportRowItem]) -> [(row: ReportRowItem, reason: String)] {
        let byID = Dictionary(uniqueKeysWithValues: pool.map { ($0.id, $0) })
        var collected: [(row: ReportRowItem, reason: String, strength: Double)] = []
        var seen: Set<String> = [reportID]
        for edge in self.relations {
            let neighborID: String?
            if edge.sourceID == reportID {
                neighborID = edge.targetID
            } else if edge.targetID == reportID {
                neighborID = edge.sourceID
            } else {
                neighborID = nil
            }
            guard let nid = neighborID, !seen.contains(nid), let neighbor = byID[nid] else { continue }
            seen.insert(nid)
            collected.append((neighbor, edge.reason, edge.strength))
        }
        return collected
            .sorted { $0.strength > $1.strength }
            .prefix(4)
            .map { ($0.row, $0.reason) }
    }
    
    
    func buildStarMapClusters(tokens: StudioColorTokens) -> [StarMapClusterNode] {
        let paletteHexes = ["#2563EB", "#7C3AED", "#0D9488", "#D97706", "#059669", "#4F46E5", "#E11D48"]
        let isSearching = !StarMapSearchEngine.parseTerms(self.searchText).isEmpty
        let groupedByMonth = Dictionary(grouping: self.displayedRows, by: \.yearMonth)
        
        var clusters: [StarMapClusterNode] = []
        for (idx, group) in self.groups.enumerated() {
            guard let monthRows = groupedByMonth[group.month], !monthRows.isEmpty else { continue }
            let accent = Color(hexString: paletteHexes[idx % paletteHexes.count])
            let leaves: [StarMapLeafNode] = monthRows.prefix(40).map { row in
                let eval = self.searchMatchesByID[row.id]
                let badge = eval.map { "命中 \($0.totalHits) 处" } ?? (row.isCurrentWeek ? "本周" : nil)
                let baseMeta = row.rangeDesc ?? row.periodLabel
                let metaLine = "\(baseMeta) · \(row.compactCharCount)"
                let weight = min(1.0, max(0.35, Double(max(120, row.report.content.count)) / 4000.0))
                return StarMapLeafNode(
                    id: row.id,
                    clusterID: group.month,
                    title: row.title,
                    metaLine: metaLine,
                    statusBadge: badge,
                    dotColor: eval != nil ? accent : (row.isCurrentWeek ? tokens.accent : accent.opacity(0.86)),
                    weight: weight,
                    isHighlighted: eval != nil
                )
            }
            clusters.append(
                StarMapClusterNode(
                    id: group.month,
                    title: group.displayTitle,
                    countText: "\(monthRows.count) 篇",
                    accent: accent,
                    isCollapsed: !isSearching && self.collapsedClusterIDs.contains(group.month),
                    leaves: leaves
                )
            )
        }
        return clusters
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


// MARK: - Full-Canvas Star-Map Weekly Report Center

struct WeeklyReportCenterView: View {
    
    @Bindable var state: WeeklyReportCenterState
    var onOpenReport: ((StoredWeeklyReport) -> Void)?
    var onDismiss: (() -> Void)?
    
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.registerWorkspaceCenterEscPop) private var registerEscPop
    @State private var db = CotLocalDatabase.shared
    @State private var quickLookReportID: String?
    @State private var focusedClusterID: String?
    @State private var panRequestToken: Int = 0
    @State private var isSearchHUDCollapsed: Bool = false
    @FocusState private var isSearchFocused: Bool
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
        let navList = self.keyboardNavigationItems(rows: rows)
        let activeRow = self.selectedRow(in: rows)
        let tokens = DashPalette.editorialTokens(isDark: self.colorScheme == .dark)
        let searchTerms = StarMapSearchEngine.parseTerms(self.state.searchText)
        let isSearching = !searchTerms.isEmpty
        let clusters = self.state.buildStarMapClusters(tokens: tokens)
        let visibleIDs = Set(rows.map(\.id))
        let visibleRelations = self.state.relations.filter {
            visibleIDs.contains($0.sourceID) && visibleIDs.contains($0.targetID)
        }
        
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                self.topBar(tokens: tokens)
                
                Rectangle()
                    .fill(tokens.hairline)
                    .frame(height: 1)
                
                ZStack {
                    if clusters.isEmpty {
                        self.emptyStarMapState(tokens: tokens)
                    } else {
                        ConstellationStarMapView(
                            hubTitle: self.state.selectedMonth.map(WeeklyReportCenterState.formatYearMonthTitle) ?? "周报星图",
                            hubSubtitle: isSearching ? "命中 \(self.state.searchHits.count) 篇" : "\(rows.count) 篇周报",
                            clusters: clusters,
                            relations: visibleRelations,
                            selectedLeafID: activeRow?.id,
                            focusedClusterID: self.focusedClusterID,
                            searchQuery: self.state.searchText,
                            panRequestToken: self.panRequestToken,
                            onSelectLeaf: { leafID in
                                self.unfocusSearchField()
                                self.isRenamingSelected = false
                                if self.editingReportID != leafID {
                                    self.isEditing = false
                                }
                                self.state.selectedReportID = leafID
                            },
                            onDoubleClickLeaf: { leafID in
                                self.unfocusSearchField()
                                if let match = rows.first(where: { $0.id == leafID }) {
                                    self.open(report: match.report)
                                }
                            },
                            onToggleCluster: { clusterID in
                                withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.22)) {
                                    if self.state.collapsedClusterIDs.contains(clusterID) {
                                        self.state.collapsedClusterIDs.remove(clusterID)
                                    } else {
                                        self.state.collapsedClusterIDs.insert(clusterID)
                                    }
                                    self.focusedClusterID = self.focusedClusterID == clusterID ? nil : clusterID
                                }
                            },
                            clusterContextMenu: { cluster in
                                Button(self.focusedClusterID == cluster.id ? "取消月度聚焦" : "聚焦此月星团") {
                                    withAnimation(.easeOut(duration: 0.16)) {
                                        self.focusedClusterID = self.focusedClusterID == cluster.id ? nil : cluster.id
                                    }
                                }
                                Button(self.state.selectedMonth == cluster.id ? "显示全部月份" : "仅查看「\(cluster.title)」") {
                                    self.state.selectedMonth = self.state.selectedMonth == cluster.id ? nil : cluster.id
                                }
                                Button(cluster.isCollapsed ? "展开此月" : "折叠此月") {
                                    if self.state.collapsedClusterIDs.contains(cluster.id) {
                                        self.state.collapsedClusterIDs.remove(cluster.id)
                                    } else {
                                        self.state.collapsedClusterIDs.insert(cluster.id)
                                    }
                                }
                            },
                            leafContextMenu: { leaf in
                                if let target = rows.first(where: { $0.id == leaf.id }) {
                                    Button("空格预览") {
                                        self.state.selectedReportID = target.id
                                        withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.16)) {
                                            self.quickLookReportID = target.id
                                        }
                                    }
                                    Button("在编辑器打开") {
                                        self.open(report: target.report)
                                    }
                                    Button("编辑") {
                                        self.state.selectedReportID = target.id
                                        self.editingReportID = target.id
                                        self.editingDraft = target.report.content
                                        self.isEditing = true
                                        withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.16)) {
                                            self.quickLookReportID = target.id
                                        }
                                    }
                                    Button("重命名") {
                                        self.state.selectedReportID = target.id
                                        self.renameDraft = target.title
                                        self.isRenamingSelected = true
                                        DispatchQueue.main.async { self.isRenameFieldFocused = true }
                                    }
                                    Divider()
                                    Button("删除", role: .destructive) {
                                        self.delete(report: target.report, in: rows)
                                    }
                                }
                            }
                        )
                    }
                    
                    if isSearching && !self.state.searchHits.isEmpty {
                        StarMapSearchResultsHUD(
                            hits: self.state.searchHits,
                            selectedID: activeRow?.id,
                            isCollapsed: self.isSearchHUDCollapsed,
                            tokens: tokens,
                            onToggleCollapse: {
                                withAnimation(.easeOut(duration: 0.15)) {
                                    self.isSearchHUDCollapsed.toggle()
                                }
                            },
                            onSelectHit: { hitID in
                                self.unfocusSearchField()
                                self.state.selectedReportID = hitID
                                self.panRequestToken &+= 1
                            },
                            onPreviewHit: { hitID in
                                self.unfocusSearchField()
                                self.state.selectedReportID = hitID
                                withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.16)) {
                                    self.quickLookReportID = hitID
                                }
                            },
                            onOpenHit: { hitID in
                                self.unfocusSearchField()
                                if let match = self.quickLookRow(id: hitID, rows: rows) {
                                    self.open(report: match.report)
                                }
                            }
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                        .padding(.top, 14)
                        .padding(.trailing, 16)
                    }
                    
                    if let activeRow, self.quickLookReportID == nil {
                        self.bottomSelectionCapsule(row: activeRow, allRows: rows, tokens: tokens)
                            .padding(.horizontal, 20)
                            .padding(.bottom, 16)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(tokens.canvasTop)
            
            if let qID = self.quickLookReportID, let qRow = self.quickLookRow(id: qID, rows: rows) {
                let qReport = qRow.report
                let curIdx = navList.firstIndex(where: { $0.id == qID })
                let canPrev = (curIdx ?? 0) > 0
                let canNext = curIdx.map { $0 + 1 < navList.count } ?? false
                let related = self.state.relatedRows(for: qReport.id, in: self.state.allRowItems)
                let qEval = self.state.searchMatchesByID[qReport.id]
                let editingThisReport = self.isEditing && self.editingReportID == qReport.id
                
                StarMapQuickLookOverlay(
                    title: qReport.title,
                    subtitle: "\(WeeklyReportCenterState.formatYearMonthTitle(qReport.yearMonth)) · \(qRow.periodLabel)"
                        + (qRow.rangeDesc.map { " (\($0))" } ?? "")
                        + " · \(qRow.compactCharCount)",
                    canStepPrevious: canPrev,
                    canStepNext: canNext,
                    onPrevious: {
                        guard canPrev, let curIdx else { return }
                        let prev = navList[curIdx - 1]
                        self.isEditing = false
                        self.state.selectedReportID = prev.id
                        self.quickLookReportID = prev.id
                    },
                    onNext: {
                        guard canNext, let curIdx else { return }
                        let next = navList[curIdx + 1]
                        self.isEditing = false
                        self.state.selectedReportID = next.id
                        self.quickLookReportID = next.id
                    },
                    onClose: {
                        self.isEditing = false
                        withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.16)) {
                            self.quickLookReportID = nil
                        }
                    },
                    headerActions: {
                        if editingThisReport {
                            Button {
                                self.db.saveWeeklyReport(
                                    id: qReport.id,
                                    periodLabel: qReport.periodLabel,
                                    yearMonth: qReport.yearMonth,
                                    title: qReport.title,
                                    content: self.editingDraft,
                                    sourcePath: qReport.sourcePath,
                                    isEnhanced: qReport.isEnhanced,
                                    createdAt: qReport.createdAt,
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
                                    .frame(height: 27)
                                    .background(tokens.accent, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .pointerStyle(.link)
                            
                            Button {
                                self.isEditing = false
                            } label: {
                                Text("取消")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(tokens.primaryInk.opacity(0.84))
                                    .padding(.horizontal, 10)
                                    .frame(height: 27)
                                    .background(tokens.inset, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .pointerStyle(.link)
                        } else {
                            if let qEval {
                                Text("命中 \(qEval.totalHits) 处")
                                    .font(.system(size: 10.5, weight: .semibold, design: .rounded).monospacedDigit())
                                    .foregroundStyle(tokens.accentText)
                                    .padding(.horizontal, 8)
                                    .frame(height: 22)
                                    .background(tokens.accent.opacity(0.14), in: Capsule())
                            }
                            
                            Button {
                                self.quickLookReportID = nil
                                self.open(report: qReport)
                            } label: {
                                Text("打开")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(tokens.onAccentInk)
                                    .padding(.horizontal, 12)
                                    .frame(height: 27)
                                    .background(tokens.accent, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .pointerStyle(.link)
                            
                            Button {
                                self.editingReportID = qReport.id
                                self.editingDraft = qReport.content
                                self.isEditing = true
                            } label: {
                                Text("编辑")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(tokens.primaryInk.opacity(0.84))
                                    .padding(.horizontal, 10)
                                    .frame(height: 27)
                                    .background(tokens.inset, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .pointerStyle(.link)
                            
                            Button {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(qReport.content, forType: .string)
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
                                    .frame(height: 27)
                                    .background(tokens.inset, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .pointerStyle(.link)
                            
                            Button {
                                self.delete(report: qReport, in: rows)
                            } label: {
                                Image(systemName: "trash")
                                    .font(.system(size: 11.5, weight: .medium))
                                    .foregroundStyle(tokens.primaryInk.opacity(0.65))
                                    .frame(width: 27, height: 27)
                                    .background(tokens.inset, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .pointerStyle(.link)
                        }
                    },
                    bodyContent: {
                        VStack(spacing: 0) {
                            if !related.isEmpty && !editingThisReport {
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 6) {
                                        Label("关联周报", systemImage: "point.topleft.down.curvedto.point.bottomright.up")
                                            .font(.system(size: 11, weight: .semibold))
                                            .foregroundStyle(tokens.primaryInk.opacity(0.60))
                                        
                                        ForEach(related, id: \.row.id) { rel in
                                            Button {
                                                self.state.selectedReportID = rel.row.id
                                                self.quickLookReportID = rel.row.id
                                                self.panRequestToken &+= 1
                                            } label: {
                                                Text("\(rel.row.title) · \(rel.reason)")
                                                    .font(.system(size: 11, weight: .medium))
                                                    .foregroundStyle(tokens.primaryInk.opacity(0.86))
                                                    .padding(.horizontal, 9)
                                                    .frame(height: 24)
                                                    .background(tokens.inset, in: Capsule())
                                                    .overlay(Capsule().strokeBorder(tokens.hairline, lineWidth: 0.7))
                                            }
                                            .buttonStyle(.plain)
                                            .pointerStyle(.link)
                                        }
                                    }
                                    .padding(.horizontal, 18)
                                    .padding(.vertical, 9)
                                }
                                .background(tokens.canvasBottom.opacity(0.75))
                                
                                Rectangle()
                                    .fill(tokens.hairline)
                                    .frame(height: 1)
                            }
                            
                            if editingThisReport {
                                TextEditor(text: self.$editingDraft)
                                    .font(.system(size: 13))
                                    .scrollContentBackground(.hidden)
                                    .padding(18)
                                    .background(Color(nsColor: .textBackgroundColor))
                            } else {
                                CenterPreviewTextView(
                                    text: qReport.content,
                                    highlightTerms: searchTerms
                                )
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                            }
                        }
                    }
                )
            }
            
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
        let searchTerms = StarMapSearchEngine.parseTerms(self.state.searchText)
        let currentMonthTitle = self.state.selectedMonth
            .map(WeeklyReportCenterState.formatYearMonthTitle) ?? "全部月份"
        
        return HStack(spacing: 10) {
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
            
            Menu {
                Button("全部月份（\(self.state.flatReports.count)）") {
                    self.state.selectedMonth = nil
                    self.focusedClusterID = nil
                }
                if !self.state.groups.isEmpty {
                    Divider()
                    ForEach(self.state.groups) { group in
                        Button("\(group.displayTitle)（\(group.reports.count)）") {
                            self.state.selectedMonth = group.month
                            self.focusedClusterID = group.month
                        }
                    }
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "calendar")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(self.state.selectedMonth == nil ? tokens.primaryInk.opacity(0.60) : tokens.accentText)
                    Text(currentMonthTitle)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(self.state.selectedMonth == nil ? tokens.primaryInk.opacity(0.84) : tokens.accentText)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(tokens.primaryInk.opacity(0.42))
                }
                .padding(.horizontal, 10)
                .frame(height: 28)
                .background(
                    self.state.selectedMonth == nil ? tokens.inset : tokens.accent.opacity(0.12),
                    in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                )
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .pointerStyle(.link)
            
            Spacer(minLength: 6)
            
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(searchTerms.isEmpty ? tokens.primaryInk.opacity(0.45) : tokens.accent)
                
                TextField("搜索周报全文、项目词、日期（空格多词 · ⌘F）", text: self.$state.searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12.5))
                    .focused(self.$isSearchFocused)
                    .onSubmit {
                        if let first = self.state.searchHits.first {
                            self.state.selectedReportID = first.id
                            self.panRequestToken &+= 1
                        }
                        self.unfocusSearchField()
                    }
                
                if !searchTerms.isEmpty {
                    Text("\(self.state.searchHits.count) 篇")
                        .font(.system(size: 10.5, weight: .semibold, design: .rounded).monospacedDigit())
                        .foregroundStyle(tokens.accentText)
                        .padding(.horizontal, 6)
                        .frame(height: 18)
                        .background(tokens.accent.opacity(0.13), in: Capsule())
                }
                
                if !self.state.searchText.isEmpty {
                    Button {
                        self.state.searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11.5))
                            .foregroundStyle(tokens.primaryInk.opacity(0.42))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .frame(minWidth: 230, maxWidth: 320, minHeight: 28, maxHeight: 28)
            .background(tokens.inset, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(searchTerms.isEmpty ? tokens.hairline : tokens.accent.opacity(0.45), lineWidth: 0.85)
            )
            
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
    
    
    // MARK: Empty State & Bottom Selection Capsule
    
    private func emptyStarMapState(tokens: StudioColorTokens) -> some View {
        VStack(spacing: 12) {
            Image(systemName: self.state.searchText.isEmpty ? "sparkles" : "magnifyingglass")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(tokens.primaryInk.opacity(0.28))
            
            Text(self.state.searchText.isEmpty ? "暂无周报节点" : "未找到匹配的周报内容")
                .font(.system(size: 13.5, weight: .medium))
                .foregroundStyle(tokens.primaryInk.opacity(0.62))
            
            if self.state.searchText.isEmpty {
                Button("新建本周周报") {
                    self.createWeeklyReport(weekOffset: 0)
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tokens.onAccentInk)
                .padding(.horizontal, 14)
                .frame(height: 30)
                .background(tokens.accent, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .buttonStyle(.plain)
                .pointerStyle(.link)
            } else {
                Button("清除搜索条件") {
                    self.state.searchText = ""
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(tokens.accentText)
                .padding(.horizontal, 12)
                .frame(height: 28)
                .background(tokens.accent.opacity(0.12), in: Capsule())
                .buttonStyle(.plain)
                .pointerStyle(.link)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(tokens.canvasBottom)
    }
    
    
    private func bottomSelectionCapsule(
        row: WeeklyReportCenterState.ReportRowItem,
        allRows: [WeeklyReportCenterState.ReportRowItem],
        tokens: StudioColorTokens
    ) -> some View {
        let report = row.report
        let related = self.state.relatedRows(for: report.id, in: self.state.allRowItems)
        
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Circle()
                    .fill(row.isCurrentWeek ? tokens.accent : tokens.primaryInk.opacity(0.35))
                    .frame(width: 8, height: 8)
                
                if self.isRenamingSelected {
                    TextField("周报标题", text: self.$renameDraft)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13, weight: .semibold))
                        .focused(self.$isRenameFieldFocused)
                        .padding(.horizontal, 8)
                        .frame(width: 220, height: 26)
                        .background(tokens.inset, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .onSubmit { self.commitReportRename(report) }
                        .onExitCommand { self.isRenamingSelected = false }
                    
                    Button("保存") { self.commitReportRename(report) }
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(tokens.onAccentInk)
                        .padding(.horizontal, 10)
                        .frame(height: 24)
                        .background(tokens.accent, in: Capsule())
                        .buttonStyle(.plain)
                    
                    Button("取消") { self.isRenamingSelected = false }
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(tokens.primaryInk.opacity(0.68))
                        .buttonStyle(.plain)
                } else {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(report.title)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(tokens.primaryInk)
                                .fixedSize(horizontal: false, vertical: true)
                            
                            if row.isCurrentWeek {
                                Text("本周")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(tokens.accentText)
                                    .padding(.horizontal, 6)
                                    .frame(height: 16)
                                    .background(tokens.positivePillBg, in: Capsule())
                            }
                        }
                        
                        let meta = "\(WeeklyReportCenterState.formatYearMonthTitle(report.yearMonth)) · \(row.periodLabel)"
                            + (row.rangeDesc.map { " (\($0))" } ?? "")
                            + " · \(row.compactCharCount)"
                        Text(meta)
                            .font(.system(size: 10.5, weight: .regular, design: .rounded).monospacedDigit())
                            .foregroundStyle(tokens.primaryInk.opacity(0.56))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                
                Spacer(minLength: 10)
                
                Button {
                    withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.16)) {
                        self.quickLookReportID = report.id
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "eye")
                            .font(.system(size: 10.5, weight: .medium))
                        Text("空格预览")
                            .font(.system(size: 11.5, weight: .medium))
                    }
                    .foregroundStyle(tokens.primaryInk)
                    .padding(.horizontal, 10)
                    .frame(height: 26)
                    .background(tokens.inset, in: Capsule())
                }
                .buttonStyle(.plain)
                .pointerStyle(.link)
                
                Button {
                    self.editingReportID = report.id
                    self.editingDraft = report.content
                    self.isEditing = true
                    withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.16)) {
                        self.quickLookReportID = report.id
                    }
                } label: {
                    Text("编辑")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(tokens.primaryInk.opacity(0.84))
                        .padding(.horizontal, 10)
                        .frame(height: 26)
                        .background(tokens.inset, in: Capsule())
                }
                .buttonStyle(.plain)
                .pointerStyle(.link)
                
                Button {
                    self.open(report: report)
                } label: {
                    Text("打开")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(tokens.onAccentInk)
                        .padding(.horizontal, 11)
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
                        .foregroundStyle(tokens.primaryInk.opacity(0.84))
                        .padding(.horizontal, 9)
                        .frame(height: 26)
                        .background(tokens.inset, in: Capsule())
                }
                .buttonStyle(.plain)
                .pointerStyle(.link)
                
                Button {
                    self.delete(report: report, in: allRows)
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(tokens.primaryInk.opacity(0.62))
                        .frame(width: 26, height: 26)
                        .background(tokens.inset, in: Circle())
                }
                .buttonStyle(.plain)
                .pointerStyle(.link)
            }
            
            if !related.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        Text("关联周报")
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(tokens.primaryInk.opacity(0.50))
                        
                        ForEach(related, id: \.row.id) { rel in
                            Button {
                                if let month = self.state.selectedMonth, month != rel.row.yearMonth {
                                    self.state.selectedMonth = nil
                                }
                                self.state.selectedReportID = rel.row.id
                                self.panRequestToken &+= 1
                            } label: {
                                Text("\(rel.row.title) · \(rel.reason)")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(tokens.primaryInk.opacity(0.84))
                                    .padding(.horizontal, 8)
                                    .frame(height: 22)
                                    .background(tokens.inset, in: Capsule())
                                    .overlay(Capsule().strokeBorder(tokens.hairline, lineWidth: 0.7))
                            }
                            .buttonStyle(.plain)
                            .pointerStyle(.link)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: 760)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(tokens.hairlineStrong, lineWidth: 0.8)
        )
        .shadow(color: .black.opacity(tokens.isDark ? 0.28 : 0.10), radius: 14, y: 6)
    }
    
    
    // MARK: Selection & Navigation Helpers
    
    private func selectedRow(in rows: [WeeklyReportCenterState.ReportRowItem]) -> WeeklyReportCenterState.ReportRowItem? {
        if let id = self.state.selectedReportID, let match = rows.first(where: { $0.id == id }) {
            return match
        }
        return rows.first
    }
    
    
    private func quickLookRow(id: String, rows: [WeeklyReportCenterState.ReportRowItem]) -> WeeklyReportCenterState.ReportRowItem? {
        rows.first(where: { $0.id == id }) ?? self.state.allRowItems.first(where: { $0.id == id })
    }
    
    
    private func keyboardNavigationItems(rows: [WeeklyReportCenterState.ReportRowItem]) -> [WeeklyReportCenterState.ReportRowItem] {
        if !StarMapSearchEngine.parseTerms(self.state.searchText).isEmpty && !self.state.searchHits.isEmpty {
            let byID = Dictionary(uniqueKeysWithValues: rows.map { ($0.id, $0) })
            let hitRows = self.state.searchHits.compactMap { byID[$0.id] }
            if !hitRows.isEmpty {
                return hitRows
            }
        }
        return rows
    }
    
    
    // MARK: Keyboard Navigation
    
    private func unfocusSearchField() {
        self.isSearchFocused = false
        if let tv = NSApp.keyWindow?.firstResponder as? NSTextView, tv.isEditable {
            NSApp.keyWindow?.makeFirstResponder(nil)
        }
    }
    
    
    private func handleEscapePop() -> Bool {
        if self.state.isGeneratorActive {
            withAnimation(.easeOut(duration: 0.14)) { self.state.isGeneratorActive = false }
            return true
        }
        if self.isEditing {
            self.isEditing = false
            return true
        }
        if self.quickLookReportID != nil {
            withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.16)) {
                self.quickLookReportID = nil
            }
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
        if self.focusedClusterID != nil {
            self.focusedClusterID = nil
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
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if flags == .command && event.charactersIgnoringModifiers?.lowercased() == "f" {
                self.quickLookReportID = nil
                self.isSearchFocused = true
                return nil
            }
            if let tv = (event.window ?? NSApp.keyWindow)?.firstResponder as? NSTextView, tv.isEditable {
                if event.keyCode == 125 && self.isSearchFocused {
                    self.unfocusSearchField()
                    return nil
                }
                return event
            }
            let rows = self.state.displayedRows
            let navList = self.keyboardNavigationItems(rows: rows)
            guard !navList.isEmpty else { return event }
            
            switch event.keyCode {
                case 49: // Space -> QuickLook preview
                    if self.quickLookReportID != nil {
                        withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.15)) {
                            self.quickLookReportID = nil
                        }
                        return nil
                    }
                    if let active = self.selectedRow(in: navList) {
                        withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.16)) {
                            self.quickLookReportID = active.id
                        }
                        return nil
                    }
                case 123, 126: // Left / Up
                    self.stepSelection(by: -1, in: navList)
                    return nil
                case 124, 125: // Right / Down
                    self.stepSelection(by: 1, in: navList)
                    return nil
                case 36: // Return -> open
                    if let active = self.selectedRow(in: navList) {
                        self.quickLookReportID = nil
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
        let currentID = self.quickLookReportID ?? self.state.selectedReportID
        let curIdx = list.firstIndex(where: { $0.id == currentID }) ?? 0
        let nextIdx = (curIdx + delta + list.count) % list.count
        let target = list[nextIdx].id
        self.state.selectedReportID = target
        if self.quickLookReportID != nil {
            self.quickLookReportID = target
        }
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
        self.quickLookReportID = result.report.id
        self.panRequestToken &+= 1
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
        if self.quickLookReportID == report.id {
            self.quickLookReportID = self.state.selectedReportID
        }
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
            let db = self.db
            let urls = panel.urls
            let knownDates = db.weeklyReportsKnownUpdatedAtBySourcePath()
            Task { @MainActor in
                do {
                    let payloads = try await Task.detached(priority: .userInitiated) {
                        try CotLocalDatabase.prepareWeeklyReportPayloads(
                            fromURLs: urls,
                            knownUpdatedAtBySourcePath: knownDates
                        )
                    }.value
                    let count = db.applyPreparedWeeklyReports(payloads)
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
