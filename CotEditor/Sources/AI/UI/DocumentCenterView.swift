//
//  DocumentCenterView.swift
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
import Combine
import Observation
import SwiftUI
import UniformTypeIdentifiers

/// High-speed reusable AppKit text previewer so switching between large documents/reports
/// happens in <1ms with zero SwiftUI `Text` layout teardown and 120fps scrolling.
struct CenterPreviewTextView: NSViewRepresentable {
    
    let text: String
    var monospace: Bool = false
    
    func makeNSView(context: Context) -> NSScrollView {
        
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .textBackgroundColor
        scrollView.borderType = .noBorder
        scrollView.scrollerStyle = .overlay
        
        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.isRichText = false
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.textContainerInset = NSSize(width: 24, height: 20)
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 4.5
        textView.defaultParagraphStyle = paragraphStyle
        textView.font = self.monospace
            ? .monospacedSystemFont(ofSize: 12.5, weight: .regular)
            : .systemFont(ofSize: 13)
        textView.textColor = .labelColor
        
        scrollView.documentView = textView
        return scrollView
    }
    
    
    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        
        guard let textView = scrollView.documentView as? NSTextView else { return }
        
        let targetFont: NSFont = self.monospace
            ? .monospacedSystemFont(ofSize: 12.5, weight: .regular)
            : .systemFont(ofSize: 13)
        if textView.font != targetFont {
            textView.font = targetFont
        }
        
        if textView.string != self.text {
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.lineSpacing = 4.5
            let attributed = NSAttributedString(string: self.text, attributes: [
                .font: targetFont,
                .foregroundColor: NSColor.labelColor,
                .paragraphStyle: paragraphStyle,
            ])
            textView.textStorage?.setAttributedString(attributed)
            scrollView.contentView.scroll(to: .zero)
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }
    }
}


// MARK: - Pure Radial Cluster Math Engine (Retained for Layout Tests)

nonisolated enum StarMapLayoutEngine {
    
    struct PositionedCluster: Identifiable {
        let id: String
        let worldPoint: CGPoint
        let angle: Double
    }
    
    struct PositionedLeaf: Identifiable {
        let id: String
        let clusterID: String
        let worldPoint: CGPoint
        let parentPoint: CGPoint
        let angle: Double
    }
    
    struct LayoutResult {
        let clusters: [PositionedCluster]
        let leaves: [PositionedLeaf]
        let bounds: CGRect
    }
    
    
    static func compute(
        clusterIDs: [String],
        leafCountsByCluster: [String: Int],
        collapsedClusterIDs: Set<String>,
        leafIDsByCluster: [String: [String]]
    ) -> LayoutResult {
        guard !clusterIDs.isEmpty else {
            return LayoutResult(clusters: [], leaves: [], bounds: CGRect(x: -180, y: -140, width: 360, height: 280))
        }
        
        var positionedClusters: [PositionedCluster] = []
        var positionedLeaves: [PositionedLeaf] = []
        var minX: CGFloat = -90
        var maxX: CGFloat = 90
        var minY: CGFloat = -70
        var maxY: CGFloat = 70
        
        func include(_ pt: CGPoint, padX: CGFloat = 88, padY: CGFloat = 34) {
            minX = min(minX, pt.x - padX)
            maxX = max(maxX, pt.x + padX)
            minY = min(minY, pt.y - padY)
            maxY = max(maxY, pt.y + padY)
        }
        
        if clusterIDs.count == 1, let onlyID = clusterIDs.first {
            let leaves = leafIDsByCluster[onlyID] ?? []
            let isCollapsed = collapsedClusterIDs.contains(onlyID)
            let clusterPt = CGPoint(x: 0, y: -115)
            positionedClusters.append(PositionedCluster(id: onlyID, worldPoint: clusterPt, angle: -.pi * 0.5))
            include(clusterPt)
            
            if !isCollapsed {
                let ringCapacities = [10, 18, 26, 36]
                let ringRadii: [CGFloat] = [195, 315, 435, 555]
                var cursor = 0
                for (ringIdx, cap) in ringCapacities.enumerated() where cursor < leaves.count {
                    let count = min(cap, leaves.count - cursor)
                    let radius = ringRadii[ringIdx]
                    let step = (2.0 * .pi) / Double(max(1, count))
                    let phaseOffset = -Double.pi * 0.5 + (ringIdx.isMultiple(of: 2) ? 0.0 : step * 0.5)
                    for i in 0..<count {
                        let leafID = leaves[cursor]
                        cursor += 1
                        let a = phaseOffset + Double(i) * step
                        let pt = CGPoint(
                            x: CGFloat(cos(a)) * radius * 1.18,
                            y: CGFloat(sin(a)) * radius * 0.88
                        )
                        positionedLeaves.append(PositionedLeaf(
                            id: leafID,
                            clusterID: onlyID,
                            worldPoint: pt,
                            parentPoint: .zero,
                            angle: a
                        ))
                        include(pt)
                    }
                }
            }
            return LayoutResult(
                clusters: positionedClusters,
                leaves: positionedLeaves,
                bounds: CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
            )
        }
        
        let weights: [Double] = clusterIDs.map { cid in
            let collapsed = collapsedClusterIDs.contains(cid)
            let visibleCount = collapsed ? 0 : (leafCountsByCluster[cid] ?? 0)
            return max(2.4, Double(min(visibleCount, 12)) + 1.8)
        }
        let totalWeight = max(1.0, weights.reduce(0, +))
        let clusterBaseR: CGFloat = min(225, max(152, 130 + CGFloat(clusterIDs.count) * 14))
        
        var cursorAngle = -Double.pi * 0.5
        for (idx, cid) in clusterIDs.enumerated() {
            let span = (weights[idx] / totalWeight) * (2.0 * .pi)
            let midAngle = cursorAngle + span * 0.5
            let clusterPt = CGPoint(
                x: CGFloat(cos(midAngle)) * clusterBaseR * 1.14,
                y: CGFloat(sin(midAngle)) * clusterBaseR * 0.86
            )
            positionedClusters.append(PositionedCluster(id: cid, worldPoint: clusterPt, angle: midAngle))
            include(clusterPt)
            
            let isCollapsed = collapsedClusterIDs.contains(cid)
            let leaves = isCollapsed ? [] : (leafIDsByCluster[cid] ?? [])
            if !leaves.isEmpty {
                let usableSpan = max(0.28, span * 0.84)
                let startA = midAngle - usableSpan * 0.5
                let innerMax = 7
                let outerLeaves = leaves.count > innerMax ? Array(leaves.dropFirst(innerMax)) : []
                let innerLeaves = Array(leaves.prefix(innerMax))
                
                for (lIdx, leafID) in innerLeaves.enumerated() {
                    let frac = innerLeaves.count == 1 ? 0.5 : Double(lIdx) / Double(innerLeaves.count - 1)
                    let a = startA + frac * usableSpan
                    let stagger: CGFloat = lIdx.isMultiple(of: 2) ? 0 : 28
                    let r = clusterBaseR + 136 + stagger
                    let pt = CGPoint(
                        x: CGFloat(cos(a)) * r * 1.18,
                        y: CGFloat(sin(a)) * r * 0.88
                    )
                    positionedLeaves.append(PositionedLeaf(
                        id: leafID,
                        clusterID: cid,
                        worldPoint: pt,
                        parentPoint: clusterPt,
                        angle: a
                    ))
                    include(pt)
                }
                
                if !outerLeaves.isEmpty {
                    for (oIdx, leafID) in outerLeaves.enumerated() {
                        let frac = outerLeaves.count == 1 ? 0.5 : Double(oIdx) / Double(outerLeaves.count - 1)
                        let a = startA + frac * usableSpan
                        let stagger: CGFloat = oIdx.isMultiple(of: 2) ? 0 : 26
                        let r = clusterBaseR + 252 + stagger
                        let pt = CGPoint(
                            x: CGFloat(cos(a)) * r * 1.18,
                            y: CGFloat(sin(a)) * r * 0.88
                        )
                        positionedLeaves.append(PositionedLeaf(
                            id: leafID,
                            clusterID: cid,
                            worldPoint: pt,
                            parentPoint: clusterPt,
                            angle: a
                        ))
                        include(pt)
                    }
                }
            }
            
            cursorAngle += span
        }
        
        return LayoutResult(
            clusters: positionedClusters,
            leaves: positionedLeaves,
            bounds: CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        )
    }
}


// MARK: - Document Center State

@MainActor @Observable final class DocumentCenterState {
    
    struct ManagedDocumentItem: Identifiable, Equatable {
        let id: String
        let dbRecordID: String?
        let title: String
        let filePath: String?
        let fileExists: Bool
        let syntax: String
        let content: String
        let previewText: String
        let updatedAt: Date
        let isOpenNow: Bool
        let isDirty: Bool
        let characterCount: Int
        let groupName: String
        let storedRecord: StoredDocumentRecord?
        var isTrashed: Bool = false
        
        static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.id == rhs.id
                && lhs.title == rhs.title
                && lhs.isOpenNow == rhs.isOpenNow
                && lhs.isDirty == rhs.isDirty
                && lhs.characterCount == rhs.characterCount
                && lhs.groupName == rhs.groupName
                && lhs.updatedAt == rhs.updatedAt
        }
    }
    
    struct DocumentGroupSection: Identifiable {
        let name: String
        let items: [ManagedDocumentItem]
        let isUngrouped: Bool
        var id: String { self.isUngrouped ? "__ungrouped__" : "group:\(self.name)" }
    }
    
    var items: [ManagedDocumentItem] = []
    var trashedItems: [ManagedDocumentItem] = []
    var displayedItems: [ManagedDocumentItem] = []
    var groupSections: [DocumentGroupSection] = []
    var collapsedGroups: Set<String> = []
    var selectedID: String?
    var showingTrash = false {
        didSet {
            if oldValue != self.showingTrash {
                self.selectedID = nil
                self.recomputeDisplayedItems()
            }
        }
    }
    var searchText: String = "" {
        didSet {
            if oldValue != self.searchText {
                self.recomputeDisplayedItems()
            }
        }
    }
    
    private var liveDocsByID: [String: Document] = [:]
    
    func liveDocument(for id: String) -> Document? {
        self.liveDocsByID[id]
    }
    
    
    func refresh() {
        
        let orderedOpenDocs = Self.collectOpenDocuments()
        var dbByCanonicalKey: [String: StoredDocumentRecord] = [:]
        for record in CotLocalDatabase.shared.documents {
            let key = Self.canonicalKey(filePath: record.filePath, rawID: record.id)
            if dbByCanonicalKey[key] == nil {
                dbByCanonicalKey[key] = record
            }
        }
        
        let trashedKeys = Set(
            CotLocalDatabase.shared.trashedDocuments.map {
                Self.canonicalKey(filePath: $0.filePath, rawID: $0.id)
            }
        )
        
        var liveByKey: [String: Document] = [:]
        var merged: [ManagedDocumentItem] = []
        var usedKeys = Set<String>()
        
        for doc in orderedOpenDocs {
            guard !doc.databaseDocumentID.hasPrefix("weekly:") else { continue }
            let filePath = doc.fileURL?.standardizedFileURL.path(percentEncoded: false)
            let content = doc.textStorage.string
            let dirty = doc.hasUncommittedChanges || doc.isDocumentEdited
            
            if filePath == nil, !doc.isExplicitlyNamed, content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !dirty {
                continue
            }
            
            let key = Self.canonicalKey(filePath: filePath, rawID: doc.databaseDocumentID)
            guard !trashedKeys.contains(key) else { continue }
            guard usedKeys.insert(key).inserted else { continue }
            
            liveByKey[key] = doc
            let dbMatch = dbByCanonicalKey[key]
            let modifiedDate = max(
                doc.lastManualSaveDate ?? .distantPast,
                doc.fileModificationDate ?? .distantPast,
                dbMatch?.updatedAt ?? Date()
            )
            let fallbackID = filePath ?? (doc.databaseDocumentID.hasPrefix("doc:") ? doc.databaseDocumentID : "doc:\(doc.databaseDocumentID)")
            let preview = Self.buildPreviewText(from: content)
            let groupName = dbMatch?.groupName ?? ""
            
            merged.append(ManagedDocumentItem(
                id: key,
                dbRecordID: dbMatch?.id ?? fallbackID,
                title: doc.displayName,
                filePath: filePath,
                fileExists: filePath != nil,
                syntax: doc.syntaxName,
                content: content,
                previewText: preview,
                updatedAt: modifiedDate,
                isOpenNow: true,
                isDirty: dirty,
                characterCount: content.count,
                groupName: groupName,
                storedRecord: dbMatch ?? StoredDocumentRecord(
                    id: fallbackID,
                    title: doc.displayName,
                    filePath: filePath,
                    syntax: doc.syntaxName,
                    content: content,
                    highlightsJSON: "[]",
                    updatedAt: modifiedDate,
                    groupName: groupName
                )
            ))
        }
        
        for record in CotLocalDatabase.shared.documents where !record.id.hasPrefix("weekly:") {
            let key = Self.canonicalKey(filePath: record.filePath, rawID: record.id)
            guard usedKeys.insert(key).inserted else { continue }
            
            let preview = Self.buildPreviewText(from: record.content)
            merged.append(ManagedDocumentItem(
                id: key,
                dbRecordID: record.id,
                title: record.title,
                filePath: record.filePath,
                fileExists: record.filePath != nil,
                syntax: record.syntax,
                content: record.content,
                previewText: preview,
                updatedAt: record.updatedAt,
                isOpenNow: false,
                isDirty: false,
                characterCount: record.content.count,
                groupName: record.groupName,
                storedRecord: record
            ))
        }
        
        self.liveDocsByID = liveByKey
        self.items = merged
        self.trashedItems = CotLocalDatabase.shared.trashedDocuments.map { record in
            ManagedDocumentItem(
                id: Self.canonicalKey(filePath: record.filePath, rawID: record.id),
                dbRecordID: record.id,
                title: record.title,
                filePath: record.filePath,
                fileExists: record.filePath != nil,
                syntax: record.syntax,
                content: record.content,
                previewText: Self.buildPreviewText(from: record.content),
                updatedAt: record.updatedAt,
                isOpenNow: false,
                isDirty: false,
                characterCount: record.content.count,
                groupName: record.groupName,
                storedRecord: record,
                isTrashed: true
            )
        }
        self.recomputeDisplayedItems()
    }
    
    
    private func matchesSearch(_ item: ManagedDocumentItem, query: String) -> Bool {
        query.isEmpty
            || item.title.localizedCaseInsensitiveContains(query)
            || item.groupName.localizedCaseInsensitiveContains(query)
            || (item.filePath?.localizedCaseInsensitiveContains(query) ?? false)
            || item.content.prefix(2_000).localizedCaseInsensitiveContains(query)
    }
    
    
    private func recomputeDisplayedItems() {
        
        let query = self.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if self.showingTrash {
            let sorted = self.trashedItems
                .filter { self.matchesSearch($0, query: query) }
                .sorted { $0.updatedAt > $1.updatedAt }
            self.displayedItems = sorted
            self.groupSections = []
            if let selectedID, sorted.contains(where: { $0.id == selectedID }) {
                return
            }
            self.selectedID = sorted.first?.id
            return
        }
        
        let filtered = self.items.filter { self.matchesSearch($0, query: query) }
        
        let sorted = filtered.sorted { lhs, rhs in
            if lhs.isOpenNow != rhs.isOpenNow {
                return lhs.isOpenNow && !rhs.isOpenNow
            }
            return lhs.updatedAt > rhs.updatedAt
        }
        self.displayedItems = sorted
        
        var groupedBuckets: [String: [ManagedDocumentItem]] = [:]
        var ungrouped: [ManagedDocumentItem] = []
        for item in sorted {
            if item.groupName.isEmpty {
                ungrouped.append(item)
            } else {
                groupedBuckets[item.groupName, default: []].append(item)
            }
        }
        
        var sections: [DocumentGroupSection] = []
        for groupName in CotLocalDatabase.shared.documentGroups {
            let bucket = groupedBuckets.removeValue(forKey: groupName) ?? []
            if query.isEmpty || !bucket.isEmpty {
                sections.append(DocumentGroupSection(name: groupName, items: bucket, isUngrouped: false))
            }
        }
        for leftoverName in groupedBuckets.keys.sorted() {
            sections.append(DocumentGroupSection(name: leftoverName, items: groupedBuckets[leftoverName] ?? [], isUngrouped: false))
        }
        if !ungrouped.isEmpty || sections.isEmpty {
            sections.append(DocumentGroupSection(name: "未分组", items: ungrouped, isUngrouped: true))
        }
        self.groupSections = sections
        
        if let selectedID, sorted.contains(where: { $0.id == selectedID }) {
            return
        }
        self.selectedID = sorted.first?.id
    }
    
    
    private static func buildPreviewText(from content: String) -> String {
        if content.isEmpty {
            return "（空文档）"
        }
        if content.count > 12_000 {
            return String(content.prefix(12_000)) + "\n\n……（仅预览前 12,000 字，点击「在编辑器打开」查看完整内容）"
        }
        return content
    }
    
    
    private static func collectOpenDocuments() -> [Document] {
        var orderedOpenDocs: [Document] = []
        var seenPointers = Set<ObjectIdentifier>()
        
        for window in NSApp.orderedWindows {
            guard let docVC = (window.windowController as? DocumentWindowController)?.documentViewController else { continue }
            for pane in docVC.editorViewControllers {
                for tab in pane.tabs {
                    let doc = tab.document
                    if seenPointers.insert(ObjectIdentifier(doc)).inserted {
                        orderedOpenDocs.append(doc)
                    }
                }
            }
        }
        for case let doc as Document in NSDocumentController.shared.documents where seenPointers.insert(ObjectIdentifier(doc)).inserted {
            orderedOpenDocs.append(doc)
        }
        return orderedOpenDocs
    }
    
    
    static func canonicalKey(filePath: String?, rawID: String) -> String {
        if let filePath, !filePath.isEmpty {
            return "file:\(URL(filePath: filePath).standardizedFileURL.path(percentEncoded: false))"
        }
        let clean = rawID.hasPrefix("doc:") ? String(rawID.dropFirst(4)) : rawID
        return "doc:\(clean)"
    }
}


// MARK: - Editorial 3-Pane Document Center (Craft / Apple Notes / Linear Inspired)

struct DocumentCenterView: View {
    
    private enum LibraryScope: Hashable {
        case all
        case openNow
        case ungrouped
        case group(String)
        case trash
    }
    
    private enum CollectionLayoutMode: String, CaseIterable, Identifiable {
        case list
        case gallery
        
        var id: String { self.rawValue }
        
        var icon: String {
            switch self {
                case .list: "list.bullet"
                case .gallery: "square.grid.2x2"
            }
        }
        
        var label: String {
            switch self {
                case .list: "列表"
                case .gallery: "画廊"
            }
        }
    }
    
    private enum SortOrder: String, CaseIterable, Identifiable {
        case updatedDesc
        case titleAsc
        case lengthDesc
        
        var id: String { self.rawValue }
        
        var label: String {
            switch self {
                case .updatedDesc: "最近更新"
                case .titleAsc: "标题排序"
                case .lengthDesc: "字数最多"
            }
        }
    }
    
    @Bindable var state: DocumentCenterState
    var onOpenDocument: ((Document?, StoredDocumentRecord?) -> Void)?
    var onOpenAllDocuments: (([DocumentCenterState.ManagedDocumentItem]) -> Void)?
    var onDeleteDocument: ((DocumentCenterState.ManagedDocumentItem) -> Void)?
    var onCreateNewDocument: (() -> Void)?
    var onDismiss: (() -> Void)?
    
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.registerWorkspaceCenterEscPop) private var registerEscPop
    @State private var db = CotLocalDatabase.shared
    @State private var studioPalette = StudioPaletteManager.shared
    
    @State private var scope: LibraryScope = .all
    @State private var layoutMode: CollectionLayoutMode = .list
    @State private var sortOrder: SortOrder = .updatedDesc
    @State private var isSidebarHidden = false
    
    @State private var isRenaming = false
    @State private var renameDraft = ""
    @FocusState private var isRenameFieldFocused: Bool
    
    @State private var isCreatingGroup = false
    @State private var newGroupDraft = ""
    @FocusState private var isNewGroupFocused: Bool
    @State private var pendingAssignAfterGroupCreate: DocumentCenterState.ManagedDocumentItem?
    
    @State private var renamingGroupName: String?
    @State private var groupRenameDraft = ""
    @FocusState private var isGroupRenameFocused: Bool
    
    @State private var copiedFlag = false
    @State private var toastMessage: String?
    @State private var toastTask: Task<Void, Never>?
    @State private var keyMonitor: Any?
    
    
    private var scopedItems: [DocumentCenterState.ManagedDocumentItem] {
        let base: [DocumentCenterState.ManagedDocumentItem] = switch self.scope {
            case .trash:
                self.state.displayedItems
            case .all:
                self.state.displayedItems
            case .openNow:
                self.state.displayedItems.filter(\.isOpenNow)
            case .ungrouped:
                self.state.displayedItems.filter { $0.groupName.isEmpty }
            case .group(let name):
                self.state.displayedItems.filter { $0.groupName == name }
        }
        
        switch self.sortOrder {
            case .updatedDesc:
                return base
            case .titleAsc:
                return base.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
            case .lengthDesc:
                return base.sorted { $0.characterCount > $1.characterCount }
        }
    }
    
    private var scopeTitle: String {
        switch self.scope {
            case .all: "全部文档"
            case .openNow: "正在编辑"
            case .ungrouped: "未分组"
            case .group(let name): name
            case .trash: "废纸篓"
        }
    }
    
    
    var body: some View {
        let tokens = self.studioPalette.tokens(isDark: self.colorScheme == .dark)
        let items = self.scopedItems
        let activeItem = self.selectedItem(in: items)
        
        ZStack(alignment: .bottom) {
            LinearGradient(
                colors: [tokens.canvasTop, tokens.canvasBottom],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            VStack(spacing: 0) {
                self.topToolbar(totalCount: items.count, tokens: tokens)
                
                Rectangle()
                    .fill(tokens.hairline)
                    .frame(height: 0.75)
                
                GeometryReader { geo in
                    let showSidebar = !self.isSidebarHidden && geo.size.width >= 780
                    let collectionW: CGFloat = self.layoutMode == .gallery
                        ? min(340, max(256, geo.size.width * 0.34))
                        : min(296, max(230, geo.size.width * 0.28))
                    
                    HStack(spacing: 0) {
                        if showSidebar {
                            self.sidebarPane(tokens: tokens)
                                .frame(width: 192)
                            
                            Rectangle()
                                .fill(tokens.hairline)
                                .frame(width: 0.75)
                        }
                        
                        self.collectionPane(items: items, activeItem: activeItem, tokens: tokens)
                            .frame(width: collectionW)
                        
                        Rectangle()
                            .fill(tokens.hairline)
                            .frame(width: 0.75)
                        
                        self.readerPane(activeItem: activeItem, tokens: tokens)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
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
            self.state.showingTrash = (self.scope == .trash)
            self.state.refresh()
            self.installKeyboardMonitor()
            self.registerEscPop? {
                self.handleEscapePop()
            }
        }
        .onDisappear {
            self.removeKeyboardMonitor()
            self.registerEscPop?(nil)
        }
        .onChange(of: self.scope) { _, newScope in
            let nextTrash = (newScope == .trash)
            if self.state.showingTrash != nextTrash {
                self.state.showingTrash = nextTrash
            }
            if let first = self.scopedItems.first, !self.scopedItems.contains(where: { $0.id == self.state.selectedID }) {
                self.state.selectedID = first.id
            }
        }
        .onChange(of: self.db.documentsRevision) { _, _ in
            self.state.refresh()
        }
        .onChange(of: self.db.documentGroups) { _, _ in
            self.state.refresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSDocument.DidChangeFileURLMessage.name)) { _ in
            self.state.refresh()
        }
    }
    
    
    private func handleEscapePop() -> Bool {
        if self.isRenaming {
            self.isRenaming = false
            return true
        }
        if self.isCreatingGroup || self.renamingGroupName != nil {
            self.isCreatingGroup = false
            self.renamingGroupName = nil
            self.pendingAssignAfterGroupCreate = nil
            return true
        }
        if self.scope == .trash {
            self.scope = .all
            return true
        }
        return false
    }
    
    
    // MARK: 1. Unified Top Toolbar
    
    private func topToolbar(totalCount: Int, tokens: StudioColorTokens) -> some View {
        HStack(spacing: 10) {
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
            
            Button {
                withAnimation(.timingCurve(0.2, 0, 0, 1, duration: 0.18)) {
                    self.isSidebarHidden.toggle()
                }
            } label: {
                Image(systemName: "sidebar.leading")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(tokens.primaryInk.opacity(0.72))
                    .frame(width: 28, height: 28)
                    .background(tokens.inset, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            }
            .buttonStyle(.plain)
            .help("显示或隐藏分组边栏")
            
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("文档中心")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(tokens.primaryInk)
                Text("\(totalCount)")
                    .font(.system(size: 11.5, weight: .medium, design: .rounded).monospacedDigit())
                    .foregroundStyle(tokens.primaryInk.opacity(0.45))
            }
            
            Spacer(minLength: 8)
            
            // Search input
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(tokens.primaryInk.opacity(0.45))
                TextField("搜索标题、分组或正文", text: self.$state.searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(tokens.primaryInk)
                    .frame(minWidth: 130, maxWidth: 210)
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
            
            // List / Gallery layout switcher
            HStack(spacing: 2) {
                ForEach(CollectionLayoutMode.allCases) { mode in
                    let active = (self.layoutMode == mode)
                    Button {
                        withAnimation(.timingCurve(0.2, 0, 0, 1, duration: 0.16)) {
                            self.layoutMode = mode
                        }
                    } label: {
                        Image(systemName: mode.icon)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(active ? tokens.onAccentInk : tokens.primaryInk.opacity(0.62))
                            .frame(width: 26, height: 24)
                            .background(active ? tokens.accent : Color.clear, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .help(mode.label)
                }
            }
            .padding(3)
            .background(tokens.card, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(tokens.hairline, lineWidth: 0.75)
            )
            
            Button {
                self.pendingAssignAfterGroupCreate = nil
                self.newGroupDraft = ""
                self.isSidebarHidden = false
                self.isCreatingGroup = true
            } label: {
                Label("新分组", systemImage: "folder.badge.plus")
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
            
            if let onCreateNewDocument = self.onCreateNewDocument {
                Button(action: onCreateNewDocument) {
                    Label("新建文档", systemImage: "plus")
                        .font(.system(size: 12, weight: .semibold))
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
    
    
    // MARK: 2. Left Spaces Sidebar
    
    private func sidebarPane(tokens: StudioColorTokens) -> some View {
        let openCount = self.state.items.filter(\.isOpenNow).count
        let ungroupedCount = self.state.items.filter { $0.groupName.isEmpty }.count
        
        return VStack(alignment: .leading, spacing: 0) {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 2) {
                    self.sidebarRow(
                        title: "全部文档",
                        icon: "doc.on.doc",
                        count: self.state.items.count,
                        targetScope: .all,
                        tokens: tokens
                    )
                    self.sidebarRow(
                        title: "正在编辑",
                        icon: "pencil.line",
                        count: openCount,
                        targetScope: .openNow,
                        tokens: tokens
                    )
                    self.sidebarRow(
                        title: "未分组",
                        icon: "tray",
                        count: ungroupedCount,
                        targetScope: .ungrouped,
                        tokens: tokens
                    )
                    
                    HStack {
                        Text("分组")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(tokens.primaryInk.opacity(0.45))
                        Spacer()
                        Button {
                            self.pendingAssignAfterGroupCreate = nil
                            self.newGroupDraft = ""
                            self.isCreatingGroup = true
                        } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 10.5, weight: .semibold))
                                .foregroundStyle(tokens.primaryInk.opacity(0.55))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 10)
                    .padding(.top, 16)
                    .padding(.bottom, 4)
                    
                    if self.isCreatingGroup {
                        HStack(spacing: 4) {
                            TextField("输入分组名称", text: self.$newGroupDraft)
                                .textFieldStyle(.plain)
                                .font(.system(size: 12))
                                .focused(self.$isNewGroupFocused)
                                .onSubmit { self.commitCreateGroup() }
                            Button {
                                self.commitCreateGroup()
                            } label: {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(tokens.accentText)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 8)
                        .frame(height: 30)
                        .background(tokens.card, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .strokeBorder(tokens.accent.opacity(0.45), lineWidth: 0.9)
                        )
                        .padding(.horizontal, 4)
                        .padding(.bottom, 4)
                        .onAppear { self.isNewGroupFocused = true }
                    }
                    
                    ForEach(self.db.documentGroups, id: \.self) { groupName in
                        let groupCount = self.state.items.filter { $0.groupName == groupName }.count
                        if self.renamingGroupName == groupName {
                            HStack(spacing: 4) {
                                TextField("分组名", text: self.$groupRenameDraft)
                                    .textFieldStyle(.plain)
                                    .font(.system(size: 12))
                                    .focused(self.$isGroupRenameFocused)
                                    .onSubmit { self.commitGroupRename(oldName: groupName) }
                            }
                            .padding(.horizontal, 8)
                            .frame(height: 30)
                            .background(tokens.card, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .strokeBorder(tokens.accent.opacity(0.45), lineWidth: 0.9)
                            )
                            .padding(.horizontal, 4)
                            .onAppear { self.isGroupRenameFocused = true }
                        } else {
                            self.sidebarRow(
                                title: groupName,
                                icon: "folder",
                                count: groupCount,
                                targetScope: .group(groupName),
                                tokens: tokens
                            )
                            .contextMenu {
                                Button("打开整组文档") {
                                    let groupItems = self.state.items.filter { $0.groupName == groupName }
                                    self.openAll(items: groupItems)
                                }
                                Button("重命名分组") {
                                    self.groupRenameDraft = groupName
                                    self.renamingGroupName = groupName
                                }
                                Divider()
                                Button("解散分组", role: .destructive) {
                                    self.db.deleteDocumentGroup(named: groupName)
                                    if self.scope == .group(groupName) {
                                        self.scope = .all
                                    }
                                    self.state.refresh()
                                    self.showToast("已解散分组「\(groupName)」")
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 10)
            }
            
            Rectangle()
                .fill(tokens.hairline)
                .frame(height: 0.75)
            
            self.sidebarRow(
                title: "废纸篓",
                icon: "trash",
                count: self.state.trashedItems.count,
                targetScope: .trash,
                tokens: tokens
            )
            .padding(8)
        }
        .background(tokens.inset.opacity(0.45))
    }
    
    
    private func sidebarRow(
        title: String,
        icon: String,
        count: Int,
        targetScope: LibraryScope,
        tokens: StudioColorTokens
    ) -> some View {
        let active = (self.scope == targetScope)
        return Button {
            withAnimation(.timingCurve(0.2, 0, 0, 1, duration: 0.14)) {
                self.scope = targetScope
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(active ? tokens.accentText : tokens.primaryInk.opacity(0.56))
                    .frame(width: 18, alignment: .center)
                
                Text(title)
                    .font(.system(size: 12.5, weight: active ? .semibold : .regular))
                    .foregroundStyle(active ? tokens.primaryInk : tokens.primaryInk.opacity(0.82))
                    .lineLimit(1)
                
                Spacer(minLength: 4)
                
                if count > 0 {
                    Text("\(count)")
                        .font(.system(size: 11, weight: .medium, design: .rounded).monospacedDigit())
                        .foregroundStyle(active ? tokens.accentText : tokens.primaryInk.opacity(0.42))
                }
            }
            .padding(.horizontal, 9)
            .frame(height: 32)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(active ? tokens.insetHover : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .pointerStyle(.link)
    }
    
    
    // MARK: 3. Middle Collection Pane
    
    private func collectionPane(
        items: [DocumentCenterState.ManagedDocumentItem],
        activeItem: DocumentCenterState.ManagedDocumentItem?,
        tokens: StudioColorTokens
    ) -> some View {
        VStack(spacing: 0) {
            // Subheader
            HStack(spacing: 8) {
                Text(self.scopeTitle)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(tokens.primaryInk.opacity(0.88))
                    .lineLimit(1)
                
                Spacer(minLength: 4)
                
                if case .group = self.scope, !items.isEmpty {
                    Button("全部打开") {
                        self.openAll(items: items)
                    }
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(tokens.accentText)
                    .buttonStyle(.plain)
                    .pointerStyle(.link)
                } else if self.scope == .trash, !self.state.trashedItems.isEmpty {
                    Button("清空废纸篓") {
                        self.confirmEmptyTrash()
                    }
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.red.opacity(0.85))
                    .buttonStyle(.plain)
                    .pointerStyle(.link)
                }
                
                Menu {
                    ForEach(SortOrder.allCases) { order in
                        Button {
                            self.sortOrder = order
                        } label: {
                            HStack {
                                Text(order.label)
                                if self.sortOrder == order {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "arrow.up.arrow.down")
                            .font(.system(size: 10))
                        Text(self.sortOrder.label)
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundStyle(tokens.primaryInk.opacity(0.58))
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
            .padding(.horizontal, 12)
            .frame(height: 38)
            
            Rectangle()
                .fill(tokens.hairline)
                .frame(height: 0.75)
            
            if items.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: self.scope == .trash ? "trash" : "doc.text")
                        .font(.system(size: 24, weight: .light))
                        .foregroundStyle(tokens.primaryInk.opacity(0.28))
                    Text(self.scope == .trash ? "废纸篓为空" : (self.state.searchText.isEmpty ? "暂无文档" : "没有匹配的文档"))
                        .font(.system(size: 12.5))
                        .foregroundStyle(tokens.primaryInk.opacity(0.50))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.vertical, showsIndicators: true) {
                    if self.layoutMode == .gallery {
                        LazyVGrid(
                            columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
                            spacing: 10
                        ) {
                            ForEach(items) { item in
                                self.galleryCard(item, isSelected: activeItem?.id == item.id, tokens: tokens)
                            }
                        }
                        .padding(12)
                    } else {
                        LazyVStack(spacing: 4) {
                            ForEach(items) { item in
                                self.listRow(item, isSelected: activeItem?.id == item.id, tokens: tokens)
                            }
                        }
                        .padding(8)
                    }
                }
            }
        }
    }
    
    
    private func listRow(
        _ item: DocumentCenterState.ManagedDocumentItem,
        isSelected: Bool,
        tokens: StudioColorTokens
    ) -> some View {
        let excerpt = Self.cleanExcerpt(item.content)
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Circle()
                    .fill(self.statusColor(for: item, tokens: tokens))
                    .frame(width: 6, height: 6)
                
                Text(item.title)
                    .font(.system(size: 12.5, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(tokens.primaryInk)
                    .lineLimit(1)
                
                Spacer(minLength: 4)
                
                Text(Self.shortDate(item.updatedAt))
                    .font(.system(size: 10.5).monospacedDigit())
                    .foregroundStyle(tokens.primaryInk.opacity(0.42))
            }
            
            if !excerpt.isEmpty {
                Text(excerpt)
                    .font(.system(size: 11.5))
                    .foregroundStyle(tokens.primaryInk.opacity(0.56))
                    .lineLimit(1)
            }
            
            HStack(spacing: 6) {
                if !item.groupName.isEmpty {
                    Text(item.groupName)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(tokens.accentText)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1.5)
                        .background(tokens.positivePillBg, in: Capsule())
                }
                if item.isOpenNow {
                    Text(item.isDirty ? "未保存" : "打开中")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(item.isDirty ? Color.orange : tokens.primaryInk.opacity(0.55))
                }
                Spacer()
                Text("\(item.characterCount.formatted()) 字")
                    .font(.system(size: 10.5, design: .rounded).monospacedDigit())
                    .foregroundStyle(tokens.primaryInk.opacity(0.40))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(isSelected ? tokens.insetHover : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(isSelected ? tokens.accent.opacity(0.48) : Color.clear, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            self.isRenaming = false
            self.state.selectedID = item.id
        }
        .simultaneousGesture(
            TapGesture(count: 2).onEnded {
                if !item.isTrashed {
                    self.open(item: item)
                }
            }
        )
        .contextMenu {
            self.itemContextMenu(item: item, list: self.scopedItems)
        }
    }
    
    
    private func galleryCard(
        _ item: DocumentCenterState.ManagedDocumentItem,
        isSelected: Bool,
        tokens: StudioColorTokens
    ) -> some View {
        let excerpt = Self.cleanExcerpt(item.content, limit: 120)
        return VStack(alignment: .leading, spacing: 6) {
            // Miniature paper sheet preview (Craft-style)
            VStack(alignment: .leading, spacing: 4) {
                Text(excerpt.isEmpty ? "（空白文档）" : excerpt)
                    .font(.system(size: 10))
                    .foregroundStyle(tokens.primaryInk.opacity(0.62))
                    .lineSpacing(2)
                    .lineLimit(5)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .padding(8)
            .frame(height: 82)
            .background(tokens.card, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(tokens.hairline, lineWidth: 0.6)
            )
            
            HStack(spacing: 4) {
                Circle()
                    .fill(self.statusColor(for: item, tokens: tokens))
                    .frame(width: 5.5, height: 5.5)
                Text(item.title)
                    .font(.system(size: 11.5, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(tokens.primaryInk)
                    .lineLimit(1)
            }
            
            HStack {
                Text(item.groupName.isEmpty ? item.syntax : item.groupName)
                    .font(.system(size: 10))
                    .foregroundStyle(tokens.primaryInk.opacity(0.48))
                    .lineLimit(1)
                Spacer()
                Text("\(item.characterCount.formatted()) 字")
                    .font(.system(size: 10, design: .rounded).monospacedDigit())
                    .foregroundStyle(tokens.primaryInk.opacity(0.42))
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(isSelected ? tokens.insetHover : tokens.inset.opacity(0.55))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(isSelected ? tokens.accent.opacity(0.55) : tokens.hairline, lineWidth: isSelected ? 1.2 : 0.7)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            self.isRenaming = false
            self.state.selectedID = item.id
        }
        .simultaneousGesture(
            TapGesture(count: 2).onEnded {
                if !item.isTrashed {
                    self.open(item: item)
                }
            }
        )
        .contextMenu {
            self.itemContextMenu(item: item, list: self.scopedItems)
        }
    }
    
    
    // MARK: 4. Right Editorial Reader & Inspector Pane
    
    @ViewBuilder
    private func readerPane(activeItem: DocumentCenterState.ManagedDocumentItem?, tokens: StudioColorTokens) -> some View {
        if let item = activeItem {
            VStack(spacing: 0) {
                // Header & Action Bar
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .center, spacing: 10) {
                        if self.isRenaming {
                            TextField("输入文档名称", text: self.$renameDraft)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 15, weight: .semibold))
                                .focused(self.$isRenameFieldFocused)
                                .onSubmit { self.commitRename(for: item) }
                            
                            Button("保存") {
                                self.commitRename(for: item)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                            
                            Button("取消") {
                                self.isRenaming = false
                            }
                            .controlSize(.small)
                        } else {
                            Text(item.title)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(tokens.primaryInk)
                                .lineLimit(1)
                            
                            if !item.isTrashed {
                                Button {
                                    self.renameDraft = item.title
                                    self.isRenaming = true
                                    self.isRenameFieldFocused = true
                                } label: {
                                    Image(systemName: "pencil")
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundStyle(tokens.primaryInk.opacity(0.50))
                                        .frame(width: 24, height: 24)
                                        .background(tokens.inset, in: Circle())
                                }
                                .buttonStyle(.plain)
                                .help("重命名")
                            }
                        }
                        
                        Spacer(minLength: 8)
                        
                        if !item.isTrashed {
                            Menu {
                                Button("未分组") { self.move(item: item, toGroup: "") }
                                if !self.db.documentGroups.isEmpty {
                                    Divider()
                                    ForEach(self.db.documentGroups, id: \.self) { g in
                                        Button {
                                            self.move(item: item, toGroup: g)
                                        } label: {
                                            HStack {
                                                Text(g)
                                                if item.groupName == g { Image(systemName: "checkmark") }
                                            }
                                        }
                                    }
                                }
                                Divider()
                                Button("新建分组并移入…") {
                                    self.pendingAssignAfterGroupCreate = item
                                    self.newGroupDraft = ""
                                    self.isSidebarHidden = false
                                    self.isCreatingGroup = true
                                }
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "folder")
                                        .font(.system(size: 10.5))
                                    Text(item.groupName.isEmpty ? "未分组" : item.groupName)
                                        .font(.system(size: 11.5, weight: .medium))
                                }
                                .foregroundStyle(tokens.primaryInk.opacity(0.78))
                                .padding(.horizontal, 9)
                                .frame(height: 26)
                                .background(tokens.inset, in: Capsule())
                            }
                            .menuStyle(.borderlessButton)
                            .fixedSize()
                        }
                    }
                    
                    // Metadata + Primary Actions Row
                    HStack(spacing: 8) {
                        Text(item.syntax)
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(tokens.primaryInk.opacity(0.65))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2.5)
                            .background(tokens.inset, in: Capsule())
                        
                        Text("\(item.characterCount.formatted()) 字")
                            .font(.system(size: 11, design: .rounded).monospacedDigit())
                            .foregroundStyle(tokens.primaryInk.opacity(0.55))
                        
                        if let path = item.filePath {
                            Button {
                                NSWorkspace.shared.activateFileViewerSelecting([URL(filePath: path)])
                            } label: {
                                Label(URL(filePath: path).lastPathComponent, systemImage: "folder")
                                    .font(.system(size: 11))
                                    .foregroundStyle(tokens.primaryInk.opacity(0.52))
                                    .lineLimit(1)
                            }
                            .buttonStyle(.plain)
                            .help(path)
                        }
                        
                        Spacer(minLength: 8)
                        
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(item.content, forType: .string)
                            self.copiedFlag = true
                            self.showToast("已复制全文")
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
                        
                        if item.isTrashed {
                            Button {
                                self.restore(item: item)
                            } label: {
                                Text("还原")
                                    .font(.system(size: 11.5, weight: .semibold))
                                    .foregroundStyle(tokens.onAccentInk)
                                    .padding(.horizontal, 11)
                                    .frame(height: 28)
                                    .background(tokens.accent, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .pointerStyle(.link)
                            
                            Button {
                                self.permanentlyDelete(item: item)
                            } label: {
                                Text("彻底删除")
                                    .font(.system(size: 11.5, weight: .medium))
                                    .foregroundStyle(Color.red)
                                    .padding(.horizontal, 10)
                                    .frame(height: 28)
                                    .background(Color.red.opacity(0.10), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .pointerStyle(.link)
                        } else {
                            Button {
                                self.delete(item: item, in: self.scopedItems)
                            } label: {
                                Image(systemName: "trash")
                                    .font(.system(size: 11.5, weight: .medium))
                                    .foregroundStyle(Color.red.opacity(0.80))
                                    .frame(width: 28, height: 28)
                                    .background(tokens.inset, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .pointerStyle(.link)
                            .help("移到废纸篓")
                            
                            Button {
                                self.open(item: item)
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
                
                CenterPreviewTextView(text: item.previewText, monospace: false)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else {
            VStack(spacing: 10) {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.system(size: 28, weight: .light))
                    .foregroundStyle(tokens.primaryInk.opacity(0.26))
                Text("选择左侧文档以预览或编辑")
                    .font(.system(size: 13))
                    .foregroundStyle(tokens.primaryInk.opacity(0.50))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
    
    
    @ViewBuilder
    private func itemContextMenu(
        item: DocumentCenterState.ManagedDocumentItem,
        list: [DocumentCenterState.ManagedDocumentItem]
    ) -> some View {
        if item.isTrashed {
            Button("还原到文档库") { self.restore(item: item) }
            Button("彻底删除", role: .destructive) { self.permanentlyDelete(item: item) }
        } else {
            Button("在编辑器打开") { self.open(item: item) }
            Button("重命名") {
                self.state.selectedID = item.id
                self.renameDraft = item.title
                self.isRenaming = true
                self.isRenameFieldFocused = true
            }
            Menu("移动至分组") {
                Button("未分组") { self.move(item: item, toGroup: "") }
                if !self.db.documentGroups.isEmpty {
                    Divider()
                    ForEach(self.db.documentGroups, id: \.self) { groupName in
                        Button(groupName) { self.move(item: item, toGroup: groupName) }
                    }
                }
                Divider()
                Button("新建分组并移入…") {
                    self.pendingAssignAfterGroupCreate = item
                    self.newGroupDraft = ""
                    self.isSidebarHidden = false
                    self.isCreatingGroup = true
                }
            }
            Divider()
            Button("移到废纸篓", role: .destructive) { self.delete(item: item, in: list) }
        }
    }
    
    
    // MARK: Helpers & Keyboard Navigation
    
    private func statusColor(for item: DocumentCenterState.ManagedDocumentItem, tokens: StudioColorTokens) -> Color {
        if item.isTrashed { return .red.opacity(0.75) }
        if item.isDirty { return Color(red: 0.94, green: 0.56, blue: 0.20) }
        if item.isOpenNow { return tokens.accent }
        return tokens.secondaryAccent.opacity(0.55)
    }
    
    
    private func selectedItem(in items: [DocumentCenterState.ManagedDocumentItem]) -> DocumentCenterState.ManagedDocumentItem? {
        if let selectedID = self.state.selectedID,
           let matched = items.first(where: { $0.id == selectedID })
        {
            return matched
        }
        return items.first
    }
    
    
    private static func cleanExcerpt(_ content: String, limit: Int = 72) -> String {
        let singleLine = content
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty && !$0.hasPrefix("⟦🖼") }) ?? ""
        if singleLine.count <= limit { return singleLine }
        return String(singleLine.prefix(limit - 1)) + "…"
    }
    
    
    private static let shortDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "M/d HH:mm"
        return f
    }()
    
    private static func shortDate(_ date: Date) -> String {
        Self.shortDateFormatter.string(from: date)
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
                    
                case 36: // Return -> Open selected document
                    if !self.isRenaming, let active = self.selectedItem(in: self.scopedItems), !active.isTrashed {
                        self.open(item: active)
                        return nil
                    }
                    return event
                    
                case 126: // Up
                    self.stepSelection(by: -1, in: self.scopedItems)
                    return nil
                    
                case 125: // Down
                    self.stepSelection(by: 1, in: self.scopedItems)
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
    
    
    private func stepSelection(by delta: Int, in list: [DocumentCenterState.ManagedDocumentItem]) {
        guard !list.isEmpty else { return }
        if let currentID = self.state.selectedID,
           let idx = list.firstIndex(where: { $0.id == currentID })
        {
            let next = (idx + delta + list.count) % list.count
            self.state.selectedID = list[next].id
        } else {
            self.state.selectedID = list.first?.id
        }
    }
    
    
    // MARK: Actions
    
    private func open(item: DocumentCenterState.ManagedDocumentItem) {
        let liveDoc = self.state.liveDocument(for: item.id)
        if let onOpenDocument = self.onOpenDocument {
            onOpenDocument(liveDoc, item.storedRecord)
        } else if let liveDoc {
            liveDoc.makeWindowControllers()
            liveDoc.showWindows()
        } else if let path = item.filePath, FileManager.default.fileExists(atPath: path) {
            NSDocumentController.shared.openDocument(withContentsOf: URL(filePath: path), display: true) { _, _, _ in }
        } else if let stored = item.storedRecord {
            AnalyticsDashboardWindowController.shared.openDocument(stored)
        }
    }
    
    
    private func openAll(items: [DocumentCenterState.ManagedDocumentItem]) {
        guard !items.isEmpty else { return }
        if let onOpenAllDocuments = self.onOpenAllDocuments {
            onOpenAllDocuments(items)
        } else {
            for item in items {
                self.open(item: item)
            }
        }
    }
    
    
    private func delete(item: DocumentCenterState.ManagedDocumentItem, in list: [DocumentCenterState.ManagedDocumentItem]) {
        if item.isTrashed {
            self.permanentlyDelete(item: item)
            return
        }
        if let idx = list.firstIndex(where: { $0.id == item.id }) {
            let nextItem = list.indices.contains(idx + 1) ? list[idx + 1] : (idx > 0 ? list[idx - 1] : nil)
            self.state.selectedID = nextItem?.id
        }
        if let onDeleteDocument = self.onDeleteDocument {
            onDeleteDocument(item)
        } else if let recordID = item.dbRecordID {
            self.db.trashDocument(id: recordID, filePath: item.filePath)
            self.state.refresh()
        }
        self.showToast("已移入废纸篓「\(item.title)」")
    }
    
    
    private func restore(item: DocumentCenterState.ManagedDocumentItem) {
        self.db.restoreDocument(id: item.dbRecordID ?? item.id, filePath: item.filePath)
        self.state.refresh()
        self.showToast("已恢复「\(item.title)」")
    }
    
    
    private func permanentlyDelete(item: DocumentCenterState.ManagedDocumentItem) {
        self.confirmDestructive(
            title: "彻底删除「\(item.title)」？",
            message: "这条文档快照会从本地数据库永久删除，无法恢复。磁盘上的原文件不会被删除。"
        ) {
            self.db.permanentlyDeleteDocument(id: item.dbRecordID ?? item.id, filePath: item.filePath)
            self.state.refresh()
            self.showToast("已彻底删除「\(item.title)」")
        }
    }
    
    
    private func confirmEmptyTrash() {
        self.confirmDestructive(
            title: "清空废纸篓？",
            message: "废纸篓中的 \(self.state.trashedItems.count) 份文档快照会被永久删除，无法恢复。磁盘上的原文件不会被删除。"
        ) {
            self.db.emptyDocumentTrash()
            self.state.refresh()
            self.showToast("废纸篓已清空")
        }
    }
    
    
    private func confirmDestructive(title: String, message: String, action: @escaping () -> Void) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "彻底删除")
        alert.addButton(withTitle: "取消")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        action()
    }
    
    
    private func commitCreateGroup() {
        guard let created = self.db.createDocumentGroup(named: self.newGroupDraft) else {
            self.isCreatingGroup = false
            return
        }
        self.isCreatingGroup = false
        self.newGroupDraft = ""
        if let pending = self.pendingAssignAfterGroupCreate {
            self.pendingAssignAfterGroupCreate = nil
            self.move(item: pending, toGroup: created)
        } else {
            self.scope = .group(created)
            self.state.refresh()
            self.showToast("已新建分组「\(created)」")
        }
    }
    
    
    private func commitGroupRename(oldName: String) {
        let trimmed = self.groupRenameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        self.renamingGroupName = nil
        guard !trimmed.isEmpty, trimmed != oldName else { return }
        if self.db.renameDocumentGroup(from: oldName, to: trimmed) {
            if self.scope == .group(oldName) {
                self.scope = .group(trimmed)
            }
            self.state.refresh()
            self.showToast("分组已重命名为「\(trimmed)」")
        } else {
            self.showToast("分组名称已存在或无效")
        }
    }
    
    
    private func move(item: DocumentCenterState.ManagedDocumentItem, toGroup groupName: String) {
        let recordID = item.dbRecordID ?? item.id
        self.db.assignDocumentGroup(
            id: recordID,
            filePath: item.filePath,
            groupName: groupName,
            fallbackTitle: item.title,
            fallbackSyntax: item.syntax,
            fallbackContent: item.content
        )
        self.state.refresh()
        self.showToast(groupName.isEmpty ? "已移至「未分组」" : "已移动到分组「\(groupName)」")
    }
    
    
    private func commitRename(for item: DocumentCenterState.ManagedDocumentItem) {
        let trimmed = self.renameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            self.isRenaming = false
            return
        }
        
        var targetSelectionID = item.id
        if let liveDoc = self.state.liveDocument(for: item.id) {
            do {
                let newName = try WorkspaceOrganizer.renameDocument(liveDoc, to: trimmed)
                targetSelectionID = DocumentCenterState.canonicalKey(
                    filePath: liveDoc.fileURL?.path(percentEncoded: false),
                    rawID: liveDoc.databaseDocumentID
                )
                self.showToast("已重命名为「\(newName)」")
            } catch {
                CotLogger.shared.error(category: .document, "Document Center live rename failed", error: error)
                self.showToast("重命名失败：\(error.localizedDescription)")
            }
        } else if let recordID = item.dbRecordID, item.filePath == nil {
            self.db.renameDocument(oldID: recordID, oldFilePath: nil, newID: recordID, newTitle: trimmed, newFilePath: nil)
            self.showToast("已重命名为「\(trimmed)」")
        } else if let filePath = item.filePath {
            let oldURL = URL(filePath: filePath)
            let desiredName = WorkspaceOrganizer.resolvedRenamedFilename(for: trimmed, preservingExtensionOf: oldURL)
            do {
                let newURL = try WorkspaceOrganizer.coordinatedMoveFile(from: oldURL, toDesiredFilename: desiredName)
                let newPath = newURL.path(percentEncoded: false)
                if let recordID = item.dbRecordID {
                    self.db.renameDocument(
                        oldID: recordID,
                        oldFilePath: filePath,
                        newID: newPath,
                        newTitle: newURL.lastPathComponent,
                        newFilePath: newPath
                    )
                }
                targetSelectionID = DocumentCenterState.canonicalKey(filePath: newPath, rawID: newPath)
                self.showToast("已重命名为「\(newURL.lastPathComponent)」")
            } catch {
                CotLogger.shared.error(category: .document, "Document Center file rename failed", error: error)
                self.showToast("重命名失败：\(error.localizedDescription)")
            }
        }
        self.isRenaming = false
        self.state.refresh()
        self.state.selectedID = targetSelectionID
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
}
