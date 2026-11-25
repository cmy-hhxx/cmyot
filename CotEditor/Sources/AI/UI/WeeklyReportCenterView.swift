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
        let characterCount: Int
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
    
    enum TimeHorizon: String, CaseIterable, Equatable {
        case all = "全部时间"
        case recent3Months = "近3个月"
        case thisYear = "今年"
        case earlier = "往年归档"
        
        func matches(yearMonth: String, now: Date = Date()) -> Bool {
            guard yearMonth.count == 6,
                  let year = Int(yearMonth.prefix(4)),
                  let month = Int(yearMonth.suffix(2))
            else { return true }
            let cal = Calendar.current
            let curYear = cal.component(.year, from: now)
            let curMonth = cal.component(.month, from: now)
            let monthsDelta = (curYear - year) * 12 + (curMonth - month)
            switch self {
                case .all:
                    return true
                case .recent3Months:
                    return monthsDelta <= 2
                case .thisYear:
                    return year == curYear
                case .earlier:
                    return year < curYear
            }
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
    var timeHorizon: TimeHorizon = .all {
        didSet {
            if oldValue != self.timeHorizon {
                self.recomputeDisplayedRows()
            }
        }
    }
    private var appliedSearchText = ""
    var searchText: String {
        get { self.appliedSearchText }
        set {
            if newValue != self.appliedSearchText {
                self.appliedSearchText = newValue
                self.rebuildGroups()
            }
        }
    }
    var isGeneratorActive: Bool = false
    var collapsedMonths: Set<String> = []
    var collapsedClusterIDs: Set<String> = []
    var defaultCollapseAll: Bool = true
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
    @ObservationIgnored private var cachedReports: [StoredWeeklyReport] = []
    @ObservationIgnored private var cachedCurrentWeek: String?
    @ObservationIgnored private var rowsInDatabaseOrder: [ReportRowItem] = []
    @ObservationIgnored private var rowsByMonth: [(month: String, title: String, rows: [ReportRowItem])] = []
    @ObservationIgnored private var initializedClusterIDs: Set<String> = []
    
    func registerClustersForDefaultCollapse(_ ids: [String]) {
        for cid in ids where self.initializedClusterIDs.insert(cid).inserted {
            if self.defaultCollapseAll {
                self.collapsedClusterIDs.insert(cid)
            }
        }
    }
    
    func expandAllClusters(_ ids: [String]) {
        for cid in ids {
            self.initializedClusterIDs.insert(cid)
            self.collapsedClusterIDs.remove(cid)
        }
    }
    
    func collapseAllClusters(_ ids: [String]) {
        for cid in ids {
            self.initializedClusterIDs.insert(cid)
            self.collapsedClusterIDs.insert(cid)
        }
    }
    
    func rebuildGroups() {
        self.rebuildGroups(evaluations: nil)
    }


    func applySearch(_ query: String) async -> Bool {
        guard !Task.isCancelled else { return false }
        let previousQuery = self.searchText
        guard query != previousQuery else { return true }
        let terms = StarMapSearchEngine.parseTerms(query)
        if terms.isEmpty {
            self.searchText = query
            return true
        }

        while !Task.isCancelled && self.searchText == previousQuery {
            let reports = CotLocalDatabase.shared.weeklyReports
            let documents = reports.map(Self.searchDocument(for:))
            let evaluations = await StarMapSearchEngine.evaluateCorpus(documents, terms: terms)
            guard let evaluations, !Task.isCancelled, self.searchText == previousQuery else { return false }
            guard reports == CotLocalDatabase.shared.weeklyReports else { continue }
            self.appliedSearchText = query
            self.rebuildGroups(evaluations: evaluations)
            return true
        }
        return false
    }


    private static func searchDocument(for report: StoredWeeklyReport) -> StarMapSearchEngine.SearchDocument {
        let metadata = [report.periodLabel, Self.readablePeriodRange(report.periodLabel)]
            .compactMap { $0 }
            .joined(separator: " ")
        return StarMapSearchEngine.SearchDocument(
            title: report.title,
            category: Self.formatYearMonthTitle(report.yearMonth),
            metadata: metadata,
            content: report.content
        )
    }


    private func rebuildGroups(evaluations: [StarMapSearchEngine.MatchEvaluation]?) {
        let allReports = CotLocalDatabase.shared.weeklyReports
        let currentWeek = AIService.currentWeekPeriodLabel()
        let reportsChanged = allReports != self.cachedReports

        if reportsChanged {
            let corpusDocs = allReports.prefix(StarMapRelationEngine.corpusLimit).map { report in
                StarMapRelationEngine.CorpusDocument(
                    id: report.id,
                    title: "\(report.periodLabel) \(report.title)",
                    group: Self.formatYearMonthTitle(report.yearMonth),
                    folderPath: report.yearMonth,
                    content: report.content,
                    sortTimestamp: report.updatedAt.timeIntervalSince1970
                )
            }
            self.relations = StarMapRelationEngine.buildRelations(for: corpusDocs, maxEdgesPerNode: 3)
            self.cachedReports = allReports
        }
        if reportsChanged || currentWeek != self.cachedCurrentWeek {
            self.prepareRows(from: allReports, currentWeek: currentWeek)
            self.cachedCurrentWeek = currentWeek
        }
        
        // Full-text multi-keyword search with 1-hop relation neighbor retention.
        let terms = StarMapSearchEngine.parseTerms(self.searchText)
        let visibleIDs: Set<String>?
        if terms.isEmpty {
            self.searchMatchesByID = [:]
            self.searchHits = []
            visibleIDs = nil
        } else {
            var matchesByID: [String: StarMapSearchEngine.MatchEvaluation] = [:]
            var scoredHits: [(hit: StarMapSearchHit, updatedAt: TimeInterval)] = []
            
            for (index, row) in self.rowsInDatabaseOrder.enumerated() {
                let report = row.report
                let evaluation = evaluations?[index] ?? Self.searchDocument(for: report).evaluate(terms: terms)
                guard evaluation.isMatch else { continue }
                matchesByID[report.id] = evaluation
                let metaLine = (row.rangeDesc.map { "\($0) · " } ?? "\(row.periodLabel) · ") + row.compactCharCount
                scoredHits.append((
                    hit: StarMapSearchHit(
                        id: report.id,
                        title: report.title,
                        categoryLabel: Self.formatYearMonthTitle(row.yearMonth),
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
            var matchingAndRelatedIDs = directIDs
            for edge in self.relations {
                if directIDs.contains(edge.sourceID) {
                    matchingAndRelatedIDs.insert(edge.targetID)
                } else if directIDs.contains(edge.targetID) {
                    matchingAndRelatedIDs.insert(edge.sourceID)
                }
            }
            visibleIDs = matchingAndRelatedIDs
        }
        
        var builtGroups: [YearMonthGroup] = []
        var visibleRows: [ReportRowItem] = []
        for month in self.rowsByMonth {
            let rows = if let visibleIDs {
                month.rows.filter { visibleIDs.contains($0.id) }
            } else {
                month.rows
            }
            guard !rows.isEmpty else { continue }
            builtGroups.append(YearMonthGroup(month: month.month, displayTitle: month.title, reports: rows.map(\.report)))
            visibleRows.append(contentsOf: rows)
        }
        self.groups = builtGroups
        self.registerClustersForDefaultCollapse(builtGroups.map(\.month))
        self.flatReports = builtGroups.flatMap(\.reports)
        self.allRowItems = visibleRows

        if let selectedMonth = self.selectedMonth, !builtGroups.contains(where: { $0.month == selectedMonth }) {
            self.selectedMonth = nil
        } else {
            self.recomputeDisplayedRows()
        }
    }


    private func prepareRows(from reports: [StoredWeeklyReport], currentWeek: String) {
        self.rowsInDatabaseOrder = reports.map { report in
            let characterCount = report.content.count
            return ReportRowItem(
                id: report.id,
                title: report.title,
                periodLabel: report.periodLabel,
                yearMonth: report.yearMonth,
                rangeDesc: Self.readablePeriodRange(report.periodLabel),
                characterCount: characterCount,
                compactCharCount: DocumentCenterState.compactChars(characterCount),
                isCurrentWeek: report.periodLabel == currentWeek,
                report: report
            )
        }
        let grouped = Dictionary(grouping: self.rowsInDatabaseOrder, by: \.yearMonth)
        self.rowsByMonth = grouped.keys.sorted(by: >).map { month in
            let sorted = grouped[month, default: []].sorted { lhs, rhs in
                if lhs.periodLabel != rhs.periodLabel {
                    return lhs.periodLabel > rhs.periodLabel
                }
                return lhs.report.updatedAt > rhs.report.updatedAt
            }
            return (month, Self.formatYearMonthTitle(month), sorted)
        }
    }
    
    
    private func recomputeDisplayedRows() {
        let now = Date()
        let monthFiltered: [ReportRowItem]
        if let month = self.selectedMonth {
            monthFiltered = self.allRowItems.filter { $0.yearMonth == month }
        } else {
            monthFiltered = self.allRowItems
        }
        let visible: [ReportRowItem] = (self.timeHorizon == .all || self.selectedMonth != nil)
            ? monthFiltered
            : monthFiltered.filter { self.timeHorizon.matches(yearMonth: $0.yearMonth, now: now) }
        self.displayedRows = visible
        
        if !self.searchHits.isEmpty {
            if let selectedReportID,
               self.searchMatchesByID[selectedReportID] != nil,
               visible.contains(where: { $0.id == selectedReportID }) {
                return
            }
            let visibleIDs = Set(visible.map(\.id))
            if let topHit = self.searchHits.first(where: { visibleIDs.contains($0.id) }) {
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
        self.registerClustersForDefaultCollapse(self.groups.map(\.month))
        
        var clusters: [StarMapClusterNode] = []
        for (idx, group) in self.groups.enumerated() {
            guard let monthRows = groupedByMonth[group.month], !monthRows.isEmpty else { continue }
            let accent = Color(hexString: paletteHexes[idx % paletteHexes.count])
            let latestTimestamp = monthRows.lazy.map(\.report.updatedAt.timeIntervalSince1970).max() ?? 0
            let timelineBadge = Self.formatTimelineBadge(group.month)
            let leaves: [StarMapLeafNode] = monthRows.prefix(40).map { row in
                let eval = self.searchMatchesByID[row.id]
                let badge = eval.map { "命中 \($0.totalHits) 处" } ?? (row.isCurrentWeek ? "本周" : nil)
                let baseMeta = row.rangeDesc ?? row.periodLabel
                let metaLine = "\(baseMeta) · \(row.compactCharCount)"
                let weight = min(1.0, max(0.35, Double(max(120, row.characterCount)) / 4000.0))
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
                    leaves: leaves,
                    timelineLabel: timelineBadge,
                    sortTimestamp: latestTimestamp
                )
            )
        }
        return clusters
    }
    
    
    static func formatTimelineBadge(_ yearMonth: String) -> String {
        guard yearMonth.count == 6,
              let year = Int(yearMonth.prefix(4)),
              let month = Int(yearMonth.suffix(2))
        else { return yearMonth }
        return String(format: "%04d · %02d月", year, month)
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


// MARK: - Native Apple 3-Column Weekly Report Center

struct WeeklyReportCenterView: View {
    
    @Bindable var state: WeeklyReportCenterState
    var onOpenReport: ((StoredWeeklyReport) -> Void)?
    var onDismiss: (() -> Void)?
    
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.registerWorkspaceCenterEscPop) private var registerEscPop
    @State private var db = CotLocalDatabase.shared
    @FocusState private var isSearchFocused: Bool
    @State private var isEditing = false
    @State private var editingReportID: String?
    @State private var editingDraft = ""
    @State private var isRenamingSelected = false
    @State private var renameDraft = ""
    @FocusState private var isRenameFieldFocused: Bool
    @State private var copiedFlag = false
    @State private var searchDraft = ""
    @State private var searchDebounceTask: Task<Void, Never>?
    @State private var toastMessage: String?
    @State private var toastTask: Task<Void, Never>?
    @State private var keyMonitor: Any?
    
    private var chromeBackground: Color { Color(nsColor: .windowBackgroundColor) }
    private var contentBackground: Color { Color(nsColor: .textBackgroundColor) }
    private var controlBackground: Color { Color(nsColor: .controlBackgroundColor) }
    private var separatorColor: Color { Color(nsColor: .separatorColor).opacity(0.65) }
    
    
    var body: some View {
        let rows = self.state.displayedRows
        let activeRow = self.selectedRow(in: rows)
        let searchTerms = StarMapSearchEngine.parseTerms(self.state.searchText)
        let isSearching = !searchTerms.isEmpty
        
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                self.topBar(searchTerms: searchTerms)
                
                Rectangle()
                    .fill(self.separatorColor)
                    .frame(height: 1)
                
                HStack(spacing: 0) {
                    self.leftSidebar()
                    
                    Rectangle()
                        .fill(self.separatorColor)
                        .frame(width: 1)
                    
                    self.middleListColumn(
                        rows: rows,
                        activeRow: activeRow,
                        isSearching: isSearching
                    )
                    
                    Rectangle()
                        .fill(self.separatorColor)
                        .frame(width: 1)
                    
                    self.rightReaderPane(
                        activeRow: activeRow,
                        allRows: rows,
                        searchTerms: searchTerms
                    )
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(self.contentBackground)
            
            if self.state.isGeneratorActive {
                self.generatorOverlay()
            }
            
            if let toastMessage {
                Text(toastMessage)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(self.controlBackground, in: Capsule())
                    .overlay(Capsule().strokeBorder(self.separatorColor, lineWidth: 0.8))
                    .shadow(color: .black.opacity(self.colorScheme == .dark ? 0.35 : 0.10), radius: 8, y: 3)
                    .padding(.bottom, 18)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .onAppear {
            self.state.rebuildGroups()
            self.searchDraft = self.state.searchText
            if self.state.isGeneratorActive {
                self.state.refreshOpenSources()
            }
            self.installKeyboardMonitor()
            self.registerEscPop? { self.handleEscapePop() }
        }
        .onDisappear {
            self.removeKeyboardMonitor()
            self.searchDebounceTask?.cancel()
            self.registerEscPop?(nil)
        }
        .onChange(of: self.state.isGeneratorActive) { _, isActive in
            if isActive {
                self.state.refreshOpenSources()
            }
        }
        .onChange(of: self.searchDraft) { _, newValue in
            self.searchDebounceTask?.cancel()
            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                if !self.state.searchText.isEmpty {
                    self.state.searchText = ""
                }
                return
            }
            self.searchDebounceTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(110))
                _ = await self.state.applySearch(newValue)
            }
        }
        .onChange(of: self.state.searchText) { _, newValue in
            if self.searchDraft != newValue {
                self.searchDraft = newValue
            }
        }
        .onReceive(
            NotificationCenter.default.publisher(for: CotLocalDatabase.weeklyReportsDidChangeNotification)
                .receive(on: RunLoop.main)
        ) { _ in
            self.state.rebuildGroups()
        }
    }
    
    
    // MARK: Top Bar
    
    private func topBar(searchTerms: [String]) -> some View {
        HStack(spacing: 10) {
            if let onDismiss = self.onDismiss {
                Button(action: onDismiss) {
                    HStack(spacing: 3) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 11, weight: .semibold))
                        Text("返回")
                            .font(.system(size: 12.5, weight: .medium))
                    }
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .frame(height: 26)
                    .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .buttonStyle(.plain)
                .pointerStyle(.link)
            }
            
            Text("周报中心")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.primary)
            
            Spacer(minLength: 8)
            
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(self.isSearchFocused ? Color.accentColor : .secondary)
                
                TextField("搜索", text: self.$searchDraft)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12.5))
                    .focused(self.$isSearchFocused)
                    .onSubmit {
                        self.searchDebounceTask?.cancel()
                        let query = self.searchDraft
                        self.unfocusSearchField()
                        self.searchDebounceTask = Task {
                            guard await self.state.applySearch(query), let first = self.state.searchHits.first else { return }
                            self.selectReport(first.id)
                        }
                    }
                
                if !searchTerms.isEmpty {
                    Text("\(self.state.searchHits.count)")
                        .font(.system(size: 10.5, weight: .semibold, design: .rounded).monospacedDigit())
                        .foregroundStyle(Color.accentColor)
                        .padding(.horizontal, 5)
                        .frame(height: 17)
                        .background(Color.accentColor.opacity(0.12), in: Capsule())
                }
                
                if !self.searchDraft.isEmpty {
                    Button {
                        self.searchDebounceTask?.cancel()
                        self.searchDraft = ""
                        self.state.searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11.5))
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 9)
            .frame(minWidth: 200, maxWidth: 240, minHeight: 28, maxHeight: 28)
            .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(
                        self.isSearchFocused ? Color.accentColor.opacity(0.55) : self.separatorColor.opacity(0.6),
                        lineWidth: self.isSearchFocused ? 1.0 : 0.65
                    )
            )
            
            Menu {
                Button("本周周报") {
                    self.createWeeklyReport(weekOffset: 0)
                }
                Button("上周周报") {
                    self.createWeeklyReport(weekOffset: -1)
                }
                Divider()
                Button("导入文件…") {
                    self.runImportPanel()
                }
            } label: {
                Text("新建")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 11)
                    .frame(height: 28)
                    .background(Color.primary.opacity(0.065), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
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
                Text("生成周报")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .frame(height: 28)
                    .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            }
            .buttonStyle(.plain)
            .pointerStyle(.link)
        }
        .padding(.horizontal, 14)
        .frame(height: 44)
        .background(self.chromeBackground)
    }
    
    
    // MARK: Column 1 - Left Time & Archive Sidebar
    
    private func leftSidebar() -> some View {
        let now = Date()
        let horizons = WeeklyReportCenterState.TimeHorizon.allCases.filter { $0 != .all }
        
        return ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 2) {
                    self.sidebarSectionHeader("时间")
                    
                    self.sidebarRow(
                        title: "全部周报",
                        count: self.state.allRowItems.count,
                        isSelected: self.state.selectedMonth == nil && self.state.timeHorizon == .all
                    ) {
                        self.state.selectedMonth = nil
                        self.state.timeHorizon = .all
                    }
                    
                    ForEach(horizons, id: \.self) { horizon in
                        let matchCount = self.state.allRowItems.count {
                            horizon.matches(yearMonth: $0.yearMonth, now: now)
                        }
                        self.sidebarRow(
                            title: horizon.rawValue,
                            count: matchCount,
                            isSelected: self.state.selectedMonth == nil && self.state.timeHorizon == horizon
                        ) {
                            self.state.selectedMonth = nil
                            self.state.timeHorizon = horizon
                        }
                    }
                }
                
                if !self.state.groups.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        self.sidebarSectionHeader("月份")
                        
                        LazyVStack(spacing: 2) {
                            ForEach(self.state.groups) { group in
                                let isActive = (self.state.selectedMonth == group.month)
                                self.sidebarRow(
                                    title: group.displayTitle,
                                    count: group.reports.count,
                                    isSelected: isActive
                                ) {
                                    self.state.selectedMonth = isActive ? nil : group.month
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 12)
        }
        .frame(width: 188)
        .frame(maxHeight: .infinity)
        .background(self.chromeBackground)
    }
    
    
    private func sidebarSectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.bottom, 4)
    }
    
    
    private func sidebarRow(
        title: String,
        count: Int,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 12.5, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Color.accentColor : .primary)
                    .lineLimit(1)
                
                Spacer(minLength: 4)
                
                Text("\(count)")
                    .font(.system(size: 11, weight: .medium, design: .rounded).monospacedDigit())
                    .foregroundStyle(isSelected ? Color.accentColor.opacity(0.85) : .secondary)
            }
            .padding(.horizontal, 8)
            .frame(height: 27)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.14) : Color.clear)
            )
            .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
        .pointerStyle(.link)
    }
    
    
    // MARK: Column 2 - Middle Report List
    
    private func middleListColumn(
        rows: [WeeklyReportCenterState.ReportRowItem],
        activeRow: WeeklyReportCenterState.ReportRowItem?,
        isSearching: Bool
    ) -> some View {
        let headerTitle: String = if isSearching {
            "搜索结果"
        } else if let month = self.state.selectedMonth {
            WeeklyReportCenterState.formatYearMonthTitle(month)
        } else if self.state.timeHorizon != .all {
            self.state.timeHorizon.rawValue
        } else {
            "全部周报"
        }
        
        return VStack(spacing: 0) {
            HStack {
                Text(headerTitle)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 6)
                Text("\(rows.count) 篇")
                    .font(.system(size: 11, weight: .medium, design: .rounded).monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .frame(height: 36)
            
            Rectangle()
                .fill(self.separatorColor)
                .frame(height: 1)
            
            if rows.isEmpty {
                self.emptyListState(isSearching: isSearching)
            } else {
                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: true) {
                        LazyVStack(spacing: 2) {
                            ForEach(rows) { row in
                                self.reportListRow(
                                    row: row,
                                    isSelected: activeRow?.id == row.id,
                                    allRows: rows,
                                    isSearching: isSearching
                                )
                                .id(row.id)
                            }
                        }
                        .padding(8)
                    }
                    .onChange(of: self.state.selectedReportID) { _, nextID in
                        guard let nextID else { return }
                        withAnimation(.easeOut(duration: 0.12)) {
                            proxy.scrollTo(nextID, anchor: .center)
                        }
                    }
                }
            }
        }
        .frame(width: 280)
        .frame(maxHeight: .infinity)
        .background(self.contentBackground)
    }
    
    
    private func reportListRow(
        row: WeeklyReportCenterState.ReportRowItem,
        isSelected: Bool,
        allRows: [WeeklyReportCenterState.ReportRowItem],
        isSearching: Bool
    ) -> some View {
        let eval = self.state.searchMatchesByID[row.id]
        let excerpt: String = if isSearching, let snippet = eval?.snippet, !snippet.isEmpty {
            snippet
        } else {
            DocumentCenterState.cleanExcerpt(from: row.report.content)
        }
        let dateMeta = "\(row.rangeDesc ?? row.periodLabel) · \(row.compactCharCount)"
        
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(row.title)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                
                Spacer(minLength: 4)
                
                if row.isCurrentWeek {
                    Text("本周")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                        .padding(.horizontal, 5)
                        .frame(height: 16)
                        .background(Color.accentColor.opacity(0.12), in: Capsule())
                }
            }
            
            HStack(spacing: 6) {
                Text(dateMeta)
                    .font(.system(size: 11, weight: .regular, design: .rounded).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                
                Spacer(minLength: 4)
                
                if let eval {
                    Text("命中 \(eval.totalHits) 处")
                        .font(.system(size: 10.5, weight: .medium, design: .rounded).monospacedDigit())
                        .foregroundStyle(Color.accentColor)
                }
            }
            
            if !excerpt.isEmpty {
                Text(excerpt)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.13) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(isSelected ? Color.accentColor.opacity(0.28) : Color.clear, lineWidth: 0.75)
        )
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .pointerStyle(.link)
        .onTapGesture {
            self.selectReport(row.id)
        }
        .simultaneousGesture(
            TapGesture(count: 2).onEnded {
                self.selectReport(row.id)
                self.open(report: row.report)
            }
        )
        .contextMenu {
            Button("在编辑器打开") {
                self.open(report: row.report)
            }
            Button("编辑") {
                self.beginEditing(report: row.report)
            }
            Button("重命名") {
                self.selectReport(row.id)
                self.renameDraft = row.title
                self.isRenamingSelected = true
                DispatchQueue.main.async { self.isRenameFieldFocused = true }
            }
            Divider()
            Button("删除", role: .destructive) {
                self.delete(report: row.report, in: allRows)
            }
        }
    }
    
    
    private func emptyListState(isSearching: Bool) -> some View {
        VStack(spacing: 10) {
            Text(isSearching ? "未找到匹配周报" : "暂无周报")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
            
            if isSearching {
                Button("清除搜索") {
                    self.searchDebounceTask?.cancel()
                    self.searchDraft = ""
                    self.state.searchText = ""
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.accentColor)
                .buttonStyle(.plain)
                .pointerStyle(.link)
            } else {
                Button("新建本周周报") {
                    self.createWeeklyReport(weekOffset: 0)
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .frame(height: 28)
                .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .buttonStyle(.plain)
                .pointerStyle(.link)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    
    // MARK: Column 3 - Right Live Reader & Inline Editor
    
    private func rightReaderPane(
        activeRow: WeeklyReportCenterState.ReportRowItem?,
        allRows: [WeeklyReportCenterState.ReportRowItem],
        searchTerms: [String]
    ) -> some View {
        Group {
            if let activeRow {
                let report = activeRow.report
                let editingThisReport = self.isEditing && self.editingReportID == report.id
                let related = editingThisReport ? [] : self.state.relatedRows(for: report.id, in: self.state.allRowItems)
                
                VStack(spacing: 0) {
                    self.detailHeader(
                        row: activeRow,
                        report: report,
                        allRows: allRows,
                        editingThisReport: editingThisReport
                    )
                    
                    Rectangle()
                        .fill(self.separatorColor)
                        .frame(height: 1)
                    
                    if !related.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                Text("相关")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(.secondary)
                                
                                ForEach(related, id: \.row.id) { rel in
                                    Button {
                                        if let month = self.state.selectedMonth, month != rel.row.yearMonth {
                                            self.state.selectedMonth = nil
                                        }
                                        self.selectReport(rel.row.id)
                                    } label: {
                                        Text("\(rel.row.title) · \(rel.reason)")
                                            .font(.system(size: 11, weight: .medium))
                                            .foregroundStyle(.primary.opacity(0.85))
                                            .padding(.horizontal, 9)
                                            .frame(height: 22)
                                            .background(Color.primary.opacity(0.055), in: Capsule())
                                    }
                                    .buttonStyle(.plain)
                                    .pointerStyle(.link)
                                }
                            }
                            .padding(.horizontal, 20)
                        }
                        .frame(height: 32)
                        .background(self.chromeBackground.opacity(0.5))
                        
                        Rectangle()
                            .fill(self.separatorColor)
                            .frame(height: 1)
                    }
                    
                    if editingThisReport {
                        TextEditor(text: self.$editingDraft)
                            .font(.system(size: 13.5))
                            .scrollContentBackground(.hidden)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 18)
                            .background(self.contentBackground)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        CenterPreviewTextView(
                            text: report.content,
                            highlightTerms: searchTerms
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            } else {
                Text("选择一篇周报以阅读")
                    .font(.system(size: 13.5))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(self.contentBackground)
    }
    
    
    private func detailHeader(
        row: WeeklyReportCenterState.ReportRowItem,
        report: StoredWeeklyReport,
        allRows: [WeeklyReportCenterState.ReportRowItem],
        editingThisReport: Bool
    ) -> some View {
        let meta = "\(WeeklyReportCenterState.formatYearMonthTitle(report.yearMonth)) · \(row.rangeDesc ?? row.periodLabel) · \(row.compactCharCount)"
        
        return HStack(spacing: 12) {
            if self.isRenamingSelected {
                TextField("周报标题", text: self.$renameDraft)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14, weight: .semibold))
                    .focused(self.$isRenameFieldFocused)
                    .padding(.horizontal, 8)
                    .frame(maxWidth: 300, minHeight: 28, maxHeight: 28)
                    .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .onSubmit { self.commitReportRename(report) }
                    .onExitCommand { self.isRenamingSelected = false }
                
                Button("保存") { self.commitReportRename(report) }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                
                Button("取消") { self.isRenamingSelected = false }
                    .controlSize(.small)
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Text(report.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    
                    Text(meta)
                        .font(.system(size: 11, weight: .regular, design: .rounded).monospacedDigit())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            
            Spacer(minLength: 10)
            
            if editingThisReport {
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
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .frame(height: 27)
                        .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
                .buttonStyle(.plain)
                .pointerStyle(.link)
                
                Button {
                    self.isEditing = false
                } label: {
                    Text("取消")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 10)
                        .frame(height: 27)
                        .background(Color.primary.opacity(0.065), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
                .buttonStyle(.plain)
                .pointerStyle(.link)
            } else {
                Button {
                    self.open(report: report)
                } label: {
                    Text("打开")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .frame(height: 27)
                        .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
                .buttonStyle(.plain)
                .pointerStyle(.link)
                
                Button {
                    self.beginEditing(report: report)
                } label: {
                    Text("编辑")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 10)
                        .frame(height: 27)
                        .background(Color.primary.opacity(0.065), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
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
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 10)
                        .frame(height: 27)
                        .background(Color.primary.opacity(0.065), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
                .buttonStyle(.plain)
                .pointerStyle(.link)
                
                Menu {
                    Button("重命名") {
                        self.renameDraft = report.title
                        self.isRenamingSelected = true
                        DispatchQueue.main.async { self.isRenameFieldFocused = true }
                    }
                    Divider()
                    Button("删除", role: .destructive) {
                        self.delete(report: report, in: allRows)
                    }
                } label: {
                    Text("···")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 27)
                        .background(Color.primary.opacity(0.065), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .pointerStyle(.link)
            }
        }
        .padding(.horizontal, 20)
        .frame(height: 48)
    }
    
    
    // MARK: Selection & Navigation Helpers
    
    private func selectReport(_ id: String) {
        self.unfocusSearchField()
        self.isRenamingSelected = false
        if self.editingReportID != id {
            self.isEditing = false
        }
        self.state.selectedReportID = id
    }
    
    
    private func beginEditing(report: StoredWeeklyReport) {
        self.state.selectedReportID = report.id
        self.editingReportID = report.id
        self.editingDraft = report.content
        self.isEditing = true
        self.isRenamingSelected = false
    }
    
    
    private func selectedRow(in rows: [WeeklyReportCenterState.ReportRowItem]) -> WeeklyReportCenterState.ReportRowItem? {
        if let id = self.state.selectedReportID, let match = rows.first(where: { $0.id == id }) {
            return match
        }
        return rows.first
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
        if self.isRenamingSelected {
            self.isRenamingSelected = false
            return true
        }
        if !self.state.searchText.isEmpty {
            self.searchDraft = ""
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
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if flags == .command && event.charactersIgnoringModifiers?.lowercased() == "f" {
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
                case 126:  // Up
                    self.stepSelection(by: -1, in: navList)
                    return nil
                case 125:  // Down
                    self.stepSelection(by: 1, in: navList)
                    return nil
                case 36:  // Return -> open
                    if let active = self.selectedRow(in: navList) {
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
        let currentID = self.state.selectedReportID
        let curIdx = list.firstIndex(where: { $0.id == currentID }) ?? 0
        let nextIdx = (curIdx + delta + list.count) % list.count
        let target = list[nextIdx].id
        self.state.selectedReportID = target
    }
    
    
    // MARK: Focused AI Weekly Report Generator Modal
    
    private func generatorOverlay() -> some View {
        ZStack {
            Color.black.opacity(self.colorScheme == .dark ? 0.50 : 0.24)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(.easeOut(duration: 0.14)) { self.state.isGeneratorActive = false }
                }
            
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Text("生成周报 · \(AIService.currentWeekPeriodLabel())")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.primary)
                    Spacer()
                    Button("关闭") {
                        withAnimation(.easeOut(duration: 0.14)) { self.state.isGeneratorActive = false }
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .buttonStyle(.plain)
                    .pointerStyle(.link)
                }
                .padding(.horizontal, 18)
                .frame(height: 46)
                
                Rectangle().fill(self.separatorColor).frame(height: 1)
                
                HStack(spacing: 0) {
                    ScrollView(.vertical, showsIndicators: true) {
                        VStack(alignment: .leading, spacing: 14) {
                            if !self.state.openSources.isEmpty {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("素材文档")
                                        .font(.system(size: 11.5, weight: .semibold))
                                        .foregroundStyle(.secondary)
                                    
                                    ForEach(self.$state.openSources) { $source in
                                        Toggle(isOn: $source.isSelected) {
                                            Text(source.title)
                                                .font(.system(size: 12.5))
                                                .foregroundStyle(.primary)
                                                .lineLimit(1)
                                        }
                                        .toggleStyle(.checkbox)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 5)
                                        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                                    }
                                }
                            }
                            
                            VStack(alignment: .leading, spacing: 6) {
                                Text("补充要点")
                                    .font(.system(size: 11.5, weight: .semibold))
                                    .foregroundStyle(.secondary)
                                TextEditor(text: self.$state.customNotes)
                                    .font(.system(size: 12.5))
                                    .scrollContentBackground(.hidden)
                                    .padding(8)
                                    .frame(height: 116)
                                    .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            }
                            
                            if !self.state.fragmentsText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("已积累片段")
                                        .font(.system(size: 11.5, weight: .semibold))
                                        .foregroundStyle(.secondary)
                                    TextEditor(text: self.$state.fragmentsText)
                                        .font(.system(size: 12))
                                        .scrollContentBackground(.hidden)
                                        .padding(8)
                                        .frame(height: 84)
                                        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
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
                                    }
                                    Text(self.state.isGenerating ? "生成中…" : "生成")
                                        .font(.system(size: 12.5, weight: .semibold))
                                }
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity, minHeight: 32)
                                .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                                .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .pointerStyle(.link)
                            .disabled(self.state.isGenerating)
                        }
                        .padding(16)
                    }
                    .frame(width: 272)
                    
                    Rectangle().fill(self.separatorColor).frame(width: 1)
                    
                    VStack(spacing: 0) {
                        if self.state.generatedOutput.isEmpty {
                            Text(self.state.isGenerating ? "正在生成…" : "选择素材后点击生成")
                                .font(.system(size: 12.5))
                                .foregroundStyle(.tertiary)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else {
                            CenterPreviewTextView(text: self.state.generatedOutput)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                            
                            Rectangle().fill(self.separatorColor).frame(height: 1)
                            
                            HStack(spacing: 8) {
                                Spacer()
                                Button {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(self.state.generatedOutput, forType: .string)
                                    self.showToast("已复制")
                                } label: {
                                    Text("复制")
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundStyle(.primary)
                                        .padding(.horizontal, 12)
                                        .frame(height: 28)
                                        .background(Color.primary.opacity(0.065), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
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
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 14)
                                        .frame(height: 28)
                                        .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
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
            .background(self.chromeBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(self.separatorColor, lineWidth: 1))
            .shadow(color: .black.opacity(self.colorScheme == .dark ? 0.5 : 0.18), radius: 24, y: 10)
            .padding(24)
        }
        .transition(.opacity)
    }
    
    
    // MARK: Actions
    
    private func createWeeklyReport(weekOffset: Int) {
        let result = self.db.createWeeklyReport(weekOffset: weekOffset, includeSavedFragments: true)
        self.state.selectedMonth = nil
        self.state.timeHorizon = .all
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
