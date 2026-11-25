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
