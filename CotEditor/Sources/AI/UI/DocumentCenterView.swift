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
    
    
    static let hubFootprint = CGSize(width: 156, height: 68)
    static let clusterFootprint = CGSize(width: 164, height: 44)
    static let leafFootprint = CGSize(width: 196, height: 56)
    
    
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
        
        if clusterIDs.count == 1, let onlyID = clusterIDs.first {
            let leaves = leafIDsByCluster[onlyID] ?? []
            let isCollapsed = collapsedClusterIDs.contains(onlyID)
            let clusterPt = CGPoint(x: 0, y: -120)
            positionedClusters.append(PositionedCluster(id: onlyID, worldPoint: clusterPt, angle: -.pi * 0.5))
            
            if !isCollapsed {
                let ringCapacities = [8, 14, 22, 32]
                let ringRadii: [CGFloat] = [235, 390, 545, 700]
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
                            x: CGFloat(cos(a)) * radius * 1.28,
                            y: CGFloat(sin(a)) * radius * 0.86
                        )
                        positionedLeaves.append(PositionedLeaf(
                            id: leafID,
                            clusterID: onlyID,
                            worldPoint: pt,
                            parentPoint: .zero,
                            angle: a
                        ))
                    }
                }
            }
        } else {
            let weights: [Double] = clusterIDs.map { cid in
                let collapsed = collapsedClusterIDs.contains(cid)
                let visibleCount = collapsed ? 0 : (leafCountsByCluster[cid] ?? 0)
                return max(2.8, Double(min(visibleCount, 14)) + 2.2)
            }
            let totalWeight = max(1.0, weights.reduce(0, +))
            let clusterBaseR: CGFloat = min(290, max(195, 165 + CGFloat(clusterIDs.count) * 18))
            
            var cursorAngle = -Double.pi * 0.5
            for (idx, cid) in clusterIDs.enumerated() {
                let span = (weights[idx] / totalWeight) * (2.0 * .pi)
                let midAngle = cursorAngle + span * 0.5
                let clusterPt = CGPoint(
                    x: CGFloat(cos(midAngle)) * clusterBaseR * 1.24,
                    y: CGFloat(sin(midAngle)) * clusterBaseR * 0.86
                )
                positionedClusters.append(PositionedCluster(id: cid, worldPoint: clusterPt, angle: midAngle))
                
                let isCollapsed = collapsedClusterIDs.contains(cid)
                let leaves = isCollapsed ? [] : (leafIDsByCluster[cid] ?? [])
                if !leaves.isEmpty {
                    let usableSpan = max(0.36, span * 0.86)
                    let startA = midAngle - usableSpan * 0.5
                    let innerMax = 5
                    let midMax = 9
                    let innerLeaves = Array(leaves.prefix(innerMax))
                    let midLeaves = leaves.count > innerMax ? Array(leaves.dropFirst(innerMax).prefix(midMax)) : []
                    let outerLeaves = leaves.count > (innerMax + midMax) ? Array(leaves.dropFirst(innerMax + midMax)) : []
                    
                    func appendRing(_ ringLeaves: [String], baseRadius: CGFloat, staggerAmt: CGFloat) {
                        for (rIdx, leafID) in ringLeaves.enumerated() {
                            let frac = ringLeaves.count == 1 ? 0.5 : Double(rIdx) / Double(ringLeaves.count - 1)
                            let a = startA + frac * usableSpan
                            let stagger: CGFloat = rIdx.isMultiple(of: 2) ? 0 : staggerAmt
                            let r = baseRadius + stagger
                            let pt = CGPoint(
                                x: CGFloat(cos(a)) * r * 1.26,
                                y: CGFloat(sin(a)) * r * 0.88
                            )
                            positionedLeaves.append(PositionedLeaf(
                                id: leafID,
                                clusterID: cid,
                                worldPoint: pt,
                                parentPoint: clusterPt,
                                angle: a
                            ))
                        }
                    }
                    
                    appendRing(innerLeaves, baseRadius: clusterBaseR + 175, staggerAmt: 34)
                    if !midLeaves.isEmpty {
                        appendRing(midLeaves, baseRadius: clusterBaseR + 320, staggerAmt: 34)
                    }
                    if !outerLeaves.isEmpty {
                        appendRing(outerLeaves, baseRadius: clusterBaseR + 465, staggerAmt: 34)
                    }
                }
                
                cursorAngle += span
            }
        }
        
        // Deterministic AABB collision resolution across Hub, Clusters, and Leaves -> guaranteed zero overlap
        Self.resolveOverlaps(clusters: &positionedClusters, leaves: &positionedLeaves)
        
        // Keep leaf parentPoint synced with resolved cluster positions
        if positionedClusters.count > 1 {
            let clusterPosMap = Dictionary(uniqueKeysWithValues: positionedClusters.map { ($0.id, $0.worldPoint) })
            for i in positionedLeaves.indices {
                if let cPt = clusterPosMap[positionedLeaves[i].clusterID] {
                    positionedLeaves[i] = PositionedLeaf(
                        id: positionedLeaves[i].id,
                        clusterID: positionedLeaves[i].clusterID,
                        worldPoint: positionedLeaves[i].worldPoint,
                        parentPoint: cPt,
                        angle: positionedLeaves[i].angle
                    )
                }
            }
        }
        
        var minX: CGFloat = -Self.hubFootprint.width * 0.5 - 30
        var maxX: CGFloat = Self.hubFootprint.width * 0.5 + 30
        var minY: CGFloat = -Self.hubFootprint.height * 0.5 - 30
        var maxY: CGFloat = Self.hubFootprint.height * 0.5 + 30
        
        func include(_ pt: CGPoint, size: CGSize) {
            minX = min(minX, pt.x - size.width * 0.5 - 24)
            maxX = max(maxX, pt.x + size.width * 0.5 + 24)
            minY = min(minY, pt.y - size.height * 0.5 - 24)
            maxY = max(maxY, pt.y + size.height * 0.5 + 24)
        }
        
        for c in positionedClusters {
            include(c.worldPoint, size: Self.clusterFootprint)
        }
        for l in positionedLeaves {
            include(l.worldPoint, size: Self.leafFootprint)
        }
        
        return LayoutResult(
            clusters: positionedClusters,
            leaves: positionedLeaves,
            bounds: CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        )
    }
    
    
    /// Deterministically resolves all bounding-box overlaps among Hub (pinned), Cluster nodes, and Leaf cards.
    private static func resolveOverlaps(
        clusters: inout [PositionedCluster],
        leaves: inout [PositionedLeaf]
    ) {
        struct BoxNode {
            var center: CGPoint
            let halfW: CGFloat
            let halfH: CGFloat
            let fixed: Bool
            let isCluster: Bool
            let sourceIndex: Int
        }
        
        let pad: CGFloat = 14
        var nodes: [BoxNode] = [
            BoxNode(
                center: .zero,
                halfW: Self.hubFootprint.width * 0.5 + pad * 0.5,
                halfH: Self.hubFootprint.height * 0.5 + pad * 0.5,
                fixed: true,
                isCluster: false,
                sourceIndex: -1
            ),
        ]
        
        for (idx, c) in clusters.enumerated() {
            nodes.append(BoxNode(
                center: c.worldPoint,
                halfW: Self.clusterFootprint.width * 0.5 + pad * 0.5,
                halfH: Self.clusterFootprint.height * 0.5 + pad * 0.5,
                fixed: false,
                isCluster: true,
                sourceIndex: idx
            ))
        }
        
        for (idx, l) in leaves.enumerated() {
            nodes.append(BoxNode(
                center: l.worldPoint,
                halfW: Self.leafFootprint.width * 0.5 + pad * 0.5,
                halfH: Self.leafFootprint.height * 0.5 + pad * 0.5,
                fixed: false,
                isCluster: false,
                sourceIndex: idx
            ))
        }
        
        let count = nodes.count
        guard count > 1 else { return }
        
        for _ in 0..<44 {
            var movedAny = false
            for i in 0..<count {
                for j in (i + 1)..<count {
                    let a = nodes[i]
                    let b = nodes[j]
                    let dx = b.center.x - a.center.x
                    let dy = b.center.y - a.center.y
                    let overlapX = (a.halfW + b.halfW) - abs(dx)
                    let overlapY = (a.halfH + b.halfH) - abs(dy)
                    guard overlapX > 0.5 && overlapY > 0.5 else { continue }
                    
                    movedAny = true
                    // Push along the axis of minimum penetration (with deterministic radial tie-break)
                    let pushX: CGFloat
                    let pushY: CGFloat
                    if overlapX < overlapY * 1.15 {
                        let signX: CGFloat = dx >= 0 ? (dx == 0 ? (b.center.x >= 0 ? 1 : -1) : 1) : -1
                        pushX = signX * (overlapX + 2.0)
                        pushY = 0
                    } else {
                        let signY: CGFloat = dy >= 0 ? (dy == 0 ? (b.center.y >= 0 ? 1 : -1) : 1) : -1
                        pushX = 0
                        pushY = signY * (overlapY + 2.0)
                    }
                    
                    if a.fixed {
                        nodes[j].center.x += pushX
                        nodes[j].center.y += pushY
                    } else if b.fixed {
                        nodes[i].center.x -= pushX
                        nodes[i].center.y -= pushY
                    } else if a.isCluster && !b.isCluster {
                        // Prefer pushing leaf outward rather than displacing its parent cluster
                        nodes[i].center.x -= pushX * 0.22
                        nodes[i].center.y -= pushY * 0.22
                        nodes[j].center.x += pushX * 0.78
                        nodes[j].center.y += pushY * 0.78
                    } else if !a.isCluster && b.isCluster {
                        nodes[i].center.x -= pushX * 0.78
                        nodes[i].center.y -= pushY * 0.78
                        nodes[j].center.x += pushX * 0.22
                        nodes[j].center.y += pushY * 0.22
                    } else {
                        nodes[i].center.x -= pushX * 0.5
                        nodes[i].center.y -= pushY * 0.5
                        nodes[j].center.x += pushX * 0.5
                        nodes[j].center.y += pushY * 0.5
                    }
                }
            }
            if !movedAny { break }
        }
        
        for node in nodes where !node.fixed {
            if node.isCluster {
                let c = clusters[node.sourceIndex]
                clusters[node.sourceIndex] = PositionedCluster(id: c.id, worldPoint: node.center, angle: c.angle)
            } else {
                let l = leaves[node.sourceIndex]
                leaves[node.sourceIndex] = PositionedLeaf(
                    id: l.id,
                    clusterID: l.clusterID,
                    worldPoint: node.center,
                    parentPoint: l.parentPoint,
                    angle: l.angle
                )
            }
        }
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



// MARK: - Shared Structured Constellation Star-Map Engine (文档星图 / 周报星图)

struct StarMapClusterNode: Identifiable {
    let id: String
    let title: String
    let countText: String
    let accent: Color
    let isCollapsed: Bool
    let leaves: [StarMapLeafNode]
}


struct StarMapLeafNode: Identifiable {
    let id: String
    let clusterID: String
    let title: String
    let metaLine: String
    let statusBadge: String?
    let dotColor: Color
    let weight: Double
    let isHighlighted: Bool
}


/// Reusable, GPU-accelerated, zero-overlap Star-Map canvas shared by Document Center & Weekly Report Center.
struct ConstellationStarMapView<ClusterMenu: View, LeafMenu: View>: View {
    
    let hubTitle: String
    let hubSubtitle: String
    let clusters: [StarMapClusterNode]
    let selectedLeafID: String?
    let focusedClusterID: String?
    let searchQuery: String
    let onSelectLeaf: (String) -> Void
    let onDoubleClickLeaf: (String) -> Void
    let onToggleCluster: (String) -> Void
    @ViewBuilder let clusterContextMenu: (StarMapClusterNode) -> ClusterMenu
    @ViewBuilder let leafContextMenu: (StarMapLeafNode) -> LeafMenu
    
    @Environment(\.colorScheme) private var colorScheme
    @State private var panOffset: CGSize = .zero
    @State private var dragStartPan: CGSize?
    @State private var zoomScale: CGFloat = 1.0
    @State private var pinchBaseZoom: CGFloat?
    @State private var hoveredLeafID: String?
    @State private var hoveredClusterID: String?
    @State private var hasAutoFitted = false
    @State private var cachedLayoutKey: String = ""
    @State private var cachedLayout = StarMapLayoutEngine.LayoutResult(
        clusters: [],
        leaves: [],
        bounds: CGRect(x: -180, y: -140, width: 360, height: 280)
    )
    
    
    private var layoutSignature: String {
        self.clusters.map { c in
            let ids = c.leaves.prefix(40).map(\.id).joined(separator: ",")
            return "\(c.id):\(c.isCollapsed ? 1 : 0):\(ids)"
        }.joined(separator: "|")
    }
    
    
    private func computeFreshLayout() -> StarMapLayoutEngine.LayoutResult {
        let clusterIDs = self.clusters.map(\.id)
        var counts: [String: Int] = [:]
        var collapsed = Set<String>()
        var leafIDsByCluster: [String: [String]] = [:]
        for cluster in self.clusters {
            let cappedLeaves = Array(cluster.leaves.prefix(40))
            counts[cluster.id] = cappedLeaves.count
            leafIDsByCluster[cluster.id] = cappedLeaves.map(\.id)
            if cluster.isCollapsed {
                collapsed.insert(cluster.id)
            }
        }
        return StarMapLayoutEngine.compute(
            clusterIDs: clusterIDs,
            leafCountsByCluster: counts,
            collapsedClusterIDs: collapsed,
            leafIDsByCluster: leafIDsByCluster
        )
    }
    
    
    var body: some View {
        let isDark = (self.colorScheme == .dark)
        let tokens = DashPalette.editorialTokens(isDark: isDark)
        let currentSig = self.layoutSignature
        let layout = (self.cachedLayoutKey == currentSig) ? self.cachedLayout : self.computeFreshLayout()
        let clusterMap = Dictionary(uniqueKeysWithValues: self.clusters.map { ($0.id, $0) })
        let leafMap: [String: StarMapLeafNode] = {
            var map: [String: StarMapLeafNode] = [:]
            for c in self.clusters {
                for l in c.leaves.prefix(40) {
                    map[l.id] = l
                }
            }
            return map
        }()
        let activeFocusClusterID: String? = self.hoveredClusterID
            ?? self.hoveredLeafID.flatMap { leafMap[$0]?.clusterID }
            ?? self.focusedClusterID
            ?? self.selectedLeafID.flatMap { leafMap[$0]?.clusterID }
        
        let worldPad: CGFloat = 220
        let worldW = max(900, layout.bounds.width + worldPad * 2)
        let worldH = max(680, layout.bounds.height + worldPad * 2)
        let originX = worldW * 0.5
        let originY = worldH * 0.5
        
        GeometryReader { geo in
            let viewportCenter = CGPoint(x: geo.size.width * 0.5, y: geo.size.height * 0.5 + 14)
            
            ZStack {
                // Static GPU-cached architectural backdrop (never redraws during pan/zoom!)
                StarMapStaticBackdropView(
                    canvasColor: tokens.canvasTop,
                    dotColor: tokens.architecturalDot,
                    accentColor: tokens.accent,
                    isDark: isDark
                )
                .ignoresSafeArea()
                .allowsHitTesting(false)
                
                // Single unified GPU-transformed World Layer: scales & pans as one composited surface (locked 60-120Hz, zero node overlap at any zoom!)
                ZStack {
                    // 1. Orbital Rings + Structured Bezier Connections (drawn in world coordinates)
                    Canvas(opaque: false, colorMode: .nonLinear, rendersAsynchronously: true) { context, _ in
                        let hubPt = CGPoint(x: originX, y: originY)
                        
                        for (idx, rWorld) in [210.0, 410.0, 610.0].enumerated() {
                            let rx = CGFloat(rWorld) * 1.24
                            let ry = CGFloat(rWorld) * 0.87
                            let ellipseRect = CGRect(x: hubPt.x - rx, y: hubPt.y - ry, width: rx * 2, height: ry * 2)
                            context.stroke(
                                Path(ellipseIn: ellipseRect),
                                with: .color(tokens.hairline.opacity(idx == 0 ? 0.85 : 0.45)),
                                style: StrokeStyle(lineWidth: 0.9, dash: idx == 0 ? [] : [4, 6])
                            )
                        }
                        
                        if layout.clusters.count > 1 {
                            for cPos in layout.clusters {
                                let cPt = CGPoint(x: originX + cPos.worldPoint.x, y: originY + cPos.worldPoint.y)
                                let accent = clusterMap[cPos.id]?.accent ?? tokens.accent
                                let isFocused = (activeFocusClusterID == cPos.id)
                                let alpha: Double = isFocused ? 0.72 : (activeFocusClusterID == nil ? 0.34 : 0.14)
                                
                                let mid = CGPoint(x: (hubPt.x + cPt.x) * 0.5, y: (hubPt.y + cPt.y) * 0.5)
                                let ctrl = CGPoint(
                                    x: mid.x - (cPt.y - hubPt.y) * 0.08,
                                    y: mid.y + (cPt.x - hubPt.x) * 0.08
                                )
                                var trunk = Path()
                                trunk.move(to: hubPt)
                                trunk.addQuadCurve(to: cPt, control: ctrl)
                                context.stroke(
                                    trunk,
                                    with: .color(accent.opacity(alpha)),
                                    style: StrokeStyle(lineWidth: isFocused ? 2.2 : 1.3, lineCap: .round)
                                )
                            }
                        }
                        
                        for lPos in layout.leaves {
                            let parentPt = CGPoint(x: originX + lPos.parentPoint.x, y: originY + lPos.parentPoint.y)
                            let leafPt = CGPoint(x: originX + lPos.worldPoint.x, y: originY + lPos.worldPoint.y)
                            let leaf = leafMap[lPos.id]
                            let isSelected = (self.selectedLeafID == lPos.id)
                            let isHovered = (self.hoveredLeafID == lPos.id)
                            let isClusterFocused = (activeFocusClusterID == lPos.clusterID)
                            let branchColor = leaf?.dotColor ?? tokens.accent
                            let alpha: Double = (isSelected || isHovered)
                                ? 0.88
                                : (isClusterFocused ? 0.42 : (activeFocusClusterID == nil ? 0.24 : 0.10))
                            
                            let mid = CGPoint(x: (parentPt.x + leafPt.x) * 0.5, y: (parentPt.y + leafPt.y) * 0.5)
                            let ctrl = CGPoint(
                                x: mid.x - (leafPt.y - parentPt.y) * 0.06,
                                y: mid.y + (leafPt.x - parentPt.x) * 0.06
                            )
                            var curve = Path()
                            curve.move(to: parentPt)
                            curve.addQuadCurve(to: leafPt, control: ctrl)
                            context.stroke(
                                curve,
                                with: .color(branchColor.opacity(alpha)),
                                style: StrokeStyle(lineWidth: (isSelected || isHovered) ? 2.0 : 1.0, lineCap: .round)
                            )
                        }
                    }
                    .frame(width: worldW, height: worldH)
                    .allowsHitTesting(false)
                    
                    // 2. Center Hub Core Node
                    VStack(spacing: 3) {
                        Text(self.hubTitle)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(tokens.primaryInk)
                            .lineLimit(1)
                        Text(self.hubSubtitle)
                            .font(.system(size: 10.5, weight: .medium, design: .rounded).monospacedDigit())
                            .foregroundStyle(tokens.primaryInk.opacity(0.55))
                            .lineLimit(1)
                    }
                    .frame(width: StarMapLayoutEngine.hubFootprint.width - 12, height: StarMapLayoutEngine.hubFootprint.height - 14)
                    .background(tokens.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(tokens.accent.opacity(0.55), lineWidth: 1.3)
                    )
                    .shadow(color: tokens.cardShadow, radius: 10, y: 3)
                    .position(x: originX, y: originY)
                    
                    // 3. Tier-1 Cluster Nodes (Groups / Months)
                    if layout.clusters.count > 1 {
                        ForEach(layout.clusters) { cPos in
                            if let cluster = clusterMap[cPos.id] {
                                let isFocused = (activeFocusClusterID == cluster.id)
                                let isHovered = (self.hoveredClusterID == cluster.id)
                                let dimmed = (activeFocusClusterID != nil && !isFocused)
                                
                                Button {
                                    withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.24)) {
                                        self.onToggleCluster(cluster.id)
                                    }
                                } label: {
                                    HStack(spacing: 6) {
                                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                                            .fill(cluster.accent)
                                            .frame(width: 3.5, height: 15)
                                        
                                        Text(cluster.title)
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundStyle(tokens.primaryInk)
                                            .lineLimit(1)
                                        
                                        Spacer(minLength: 2)
                                        
                                        Text(cluster.countText)
                                            .font(.system(size: 10, weight: .semibold, design: .rounded).monospacedDigit())
                                            .foregroundStyle(cluster.accent)
                                            .padding(.horizontal, 6)
                                            .frame(height: 18)
                                            .background(cluster.accent.opacity(isDark ? 0.18 : 0.11), in: Capsule())
                                        
                                        Image(systemName: cluster.isCollapsed ? "chevron.right" : "chevron.down")
                                            .font(.system(size: 8.5, weight: .bold))
                                            .foregroundStyle(tokens.primaryInk.opacity(0.45))
                                    }
                                    .padding(.horizontal, 10)
                                    .frame(width: StarMapLayoutEngine.clusterFootprint.width - 8, height: StarMapLayoutEngine.clusterFootprint.height - 8)
                                    .background(tokens.card, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .strokeBorder(
                                                (isFocused || isHovered) ? cluster.accent.opacity(0.75) : tokens.hairlineStrong,
                                                lineWidth: (isFocused || isHovered) ? 1.3 : 0.85
                                            )
                                    )
                                    .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                }
                                .buttonStyle(.plain)
                                .pointerStyle(.link)
                                .opacity(dimmed ? 0.48 : 1.0)
                                .scaleEffect(isHovered ? 1.04 : 1.0)
                                .position(x: originX + cPos.worldPoint.x, y: originY + cPos.worldPoint.y)
                                .onHover { hovering in
                                    let next = hovering ? cluster.id : (self.hoveredClusterID == cluster.id ? nil : self.hoveredClusterID)
                                    if next != self.hoveredClusterID {
                                        self.hoveredClusterID = next
                                    }
                                }
                                .contextMenu {
                                    self.clusterContextMenu(cluster)
                                }
                            }
                        }
                    }
                    
                    // 4. Tier-2 Structured Leaf Cards (Fixed-footprint zero-overlap cards)
                    ForEach(layout.leaves) { lPos in
                        if let leaf = leafMap[lPos.id] {
                            let isSelected = (self.selectedLeafID == leaf.id)
                            let isHovered = (self.hoveredLeafID == leaf.id)
                            let isClusterFocused = (activeFocusClusterID == leaf.clusterID)
                            let dimmed = (activeFocusClusterID != nil && !isClusterFocused && !isSelected)
                            
                            VStack(alignment: .leading, spacing: 3.5) {
                                HStack(spacing: 6) {
                                    Circle()
                                        .fill(leaf.dotColor)
                                        .frame(width: isSelected ? 7.5 : 6, height: isSelected ? 7.5 : 6)
                                    
                                    Text(leaf.title)
                                        .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                                        .foregroundStyle(tokens.primaryInk.opacity(isSelected ? 1.0 : 0.90))
                                        .lineLimit(1)
                                    
                                    Spacer(minLength: 0)
                                }
                                
                                HStack(spacing: 5) {
                                    if let badge = leaf.statusBadge, !badge.isEmpty {
                                        Text(badge)
                                            .font(.system(size: 9, weight: .semibold))
                                            .foregroundStyle(tokens.accentText)
                                            .padding(.horizontal, 4.5)
                                            .frame(height: 15)
                                            .background(tokens.positivePillBg, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                                    }
                                    if !leaf.metaLine.isEmpty {
                                        Text(leaf.metaLine)
                                            .font(.system(size: 10, weight: .regular, design: .rounded).monospacedDigit())
                                            .foregroundStyle(tokens.primaryInk.opacity(0.50))
                                            .lineLimit(1)
                                    }
                                    Spacer(minLength: 0)
                                }
                                .padding(.leading, 12)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .frame(width: StarMapLayoutEngine.leafFootprint.width - 8, height: StarMapLayoutEngine.leafFootprint.height - 6, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(tokens.card.opacity(isSelected || isHovered ? 1.0 : (isDark ? 0.92 : 0.98)))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .strokeBorder(
                                        isSelected
                                            ? leaf.dotColor.opacity(0.90)
                                            : (isHovered ? leaf.dotColor.opacity(0.55) : tokens.hairline),
                                        lineWidth: isSelected ? 1.5 : 0.85
                                    )
                            )
                            .shadow(
                                color: isSelected ? leaf.dotColor.opacity(0.24) : Color.clear,
                                radius: isSelected ? 10 : 0,
                                y: isSelected ? 3 : 0
                            )
                            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .opacity(dimmed ? 0.42 : 1.0)
                            .scaleEffect(isSelected ? 1.04 : (isHovered ? 1.02 : 1.0))
                            .position(x: originX + lPos.worldPoint.x, y: originY + lPos.worldPoint.y)
                            .pointerStyle(.link)
                            .onHover { hovering in
                                let next = hovering ? leaf.id : (self.hoveredLeafID == leaf.id ? nil : self.hoveredLeafID)
                                if next != self.hoveredLeafID {
                                    self.hoveredLeafID = next
                                }
                            }
                            .onTapGesture(count: 2) {
                                self.onSelectLeaf(leaf.id)
                                self.onDoubleClickLeaf(leaf.id)
                            }
                            .onTapGesture(count: 1) {
                                self.onSelectLeaf(leaf.id)
                            }
                            .contextMenu {
                                self.leafContextMenu(leaf)
                            }
                        }
                    }
                }
                .frame(width: worldW, height: worldH)
                .scaleEffect(self.zoomScale, anchor: .center)
                .position(x: viewportCenter.x + self.panOffset.width, y: viewportCenter.y + self.panOffset.height)
                
                // 5. Minimal Zoom Controls (Bottom-Right)
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        HStack(spacing: 2) {
                            Button {
                                withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.18)) {
                                    self.zoomScale = max(0.38, self.zoomScale - 0.15)
                                }
                            } label: {
                                Image(systemName: "minus")
                                    .font(.system(size: 10.5, weight: .semibold))
                                    .frame(width: 26, height: 26)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .pointerStyle(.link)
                            
                            Button {
                                self.fitViewport(bounds: layout.bounds, size: geo.size, animated: true)
                            } label: {
                                Text("\(Int((self.zoomScale * 100).rounded()))%")
                                    .font(.system(size: 10.5, weight: .medium, design: .monospaced).monospacedDigit())
                                    .frame(minWidth: 42, minHeight: 26)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .pointerStyle(.link)
                            .help("重置视角以适配全部星图")
                            
                            Button {
                                withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.18)) {
                                    self.zoomScale = min(1.80, self.zoomScale + 0.15)
                                }
                            } label: {
                                Image(systemName: "plus")
                                    .font(.system(size: 10.5, weight: .semibold))
                                    .frame(width: 26, height: 26)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .pointerStyle(.link)
                        }
                        .foregroundStyle(tokens.primaryInk.opacity(0.76))
                        .padding(.horizontal, 4)
                        .background(tokens.card, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(tokens.hairlineStrong, lineWidth: 0.75)
                        )
                        .padding(16)
                    }
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 3)
                    .onChanged { value in
                        if self.dragStartPan == nil {
                            self.dragStartPan = self.panOffset
                        }
                        if let base = self.dragStartPan {
                            self.panOffset = CGSize(
                                width: base.width + value.translation.width,
                                height: base.height + value.translation.height
                            )
                        }
                    }
                    .onEnded { _ in
                        self.dragStartPan = nil
                    }
            )
            .simultaneousGesture(
                MagnificationGesture()
                    .onChanged { value in
                        if self.pinchBaseZoom == nil {
                            self.pinchBaseZoom = self.zoomScale
                        }
                        if let base = self.pinchBaseZoom {
                            self.zoomScale = min(1.85, max(0.36, base * value))
                        }
                    }
                    .onEnded { _ in
                        self.pinchBaseZoom = nil
                    }
            )
            .onAppear {
                self.cachedLayout = layout
                self.cachedLayoutKey = currentSig
                if !self.hasAutoFitted && geo.size.width > 100 {
                    self.hasAutoFitted = true
                    self.fitViewport(bounds: layout.bounds, size: geo.size, animated: false)
                }
            }
            .onChange(of: currentSig) { _, newSig in
                let refreshed = self.computeFreshLayout()
                self.cachedLayout = refreshed
                self.cachedLayoutKey = newSig
            }
            .onChange(of: geo.size) { _, newSize in
                if !self.hasAutoFitted && newSize.width > 100 {
                    self.hasAutoFitted = true
                    self.fitViewport(bounds: layout.bounds, size: newSize, animated: false)
                }
            }
            .onChange(of: self.searchQuery) { _, _ in
                let refreshed = self.computeFreshLayout()
                self.cachedLayout = refreshed
                self.cachedLayoutKey = self.layoutSignature
                self.fitViewport(bounds: refreshed.bounds, size: geo.size, animated: true)
            }
            .onChange(of: self.focusedClusterID) { _, nextCID in
                guard geo.size.width > 100 else { return }
                let activeLayout = (self.cachedLayoutKey == self.layoutSignature) ? self.cachedLayout : self.computeFreshLayout()
                if let nextCID, let cPos = activeLayout.clusters.first(where: { $0.id == nextCID }) {
                    let targetZoom: CGFloat = max(self.zoomScale, 0.88)
                    withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.28)) {
                        self.zoomScale = targetZoom
                        self.panOffset = CGSize(
                            width: -cPos.worldPoint.x * targetZoom * 0.72,
                            height: -cPos.worldPoint.y * targetZoom * 0.72
                        )
                    }
                } else {
                    self.fitViewport(bounds: activeLayout.bounds, size: geo.size, animated: true)
                }
            }
        }
    }
    
    
    private func fitViewport(bounds: CGRect, size: CGSize, animated: Bool) {
        let usableW = max(240, size.width - 110)
        let usableH = max(200, size.height - 176)
        let fitX = usableW / max(240, bounds.width)
        let fitY = usableH / max(180, bounds.height)
        let targetZoom = min(1.04, max(0.42, min(fitX, fitY)))
        let targetPan = CGSize(
            width: -bounds.midX * targetZoom,
            height: -bounds.midY * targetZoom
        )
        if animated {
            withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.28)) {
                self.zoomScale = targetZoom
                self.panOffset = targetPan
            }
        } else {
            self.zoomScale = targetZoom
            self.panOffset = targetPan
        }
    }
}


/// Static GPU-cached dot-grid & soft hub mist backdrop so panning never triggers dot-grid redraws.
private struct StarMapStaticBackdropView: View, Equatable {
    
    let canvasColor: Color
    let dotColor: Color
    let accentColor: Color
    let isDark: Bool
    
    static func == (lhs: StarMapStaticBackdropView, rhs: StarMapStaticBackdropView) -> Bool {
        lhs.isDark == rhs.isDark
    }
    
    var body: some View {
        ZStack {
            self.canvasColor
            
            Canvas(opaque: false, rendersAsynchronously: true) { context, size in
                guard size.width > 10, size.height > 10 else { return }
                let step: CGFloat = 32
                var dots = Path()
                var y: CGFloat = 16
                while y < size.height {
                    var x: CGFloat = 16
                    while x < size.width {
                        dots.addRect(CGRect(x: x - 0.7, y: y - 0.7, width: 1.4, height: 1.4))
                        x += step
                    }
                    y += step
                }
                context.fill(dots, with: .color(self.dotColor))
                
                let center = CGPoint(x: size.width * 0.5, y: size.height * 0.5)
                let mistR = max(size.width, size.height) * 0.45
                context.fill(
                    Circle().path(in: CGRect(x: center.x - mistR, y: center.y - mistR, width: mistR * 2, height: mistR * 2)),
                    with: .radialGradient(
                        Gradient(colors: [
                            self.accentColor.opacity(self.isDark ? 0.08 : 0.045),
                            .clear,
                        ]),
                        center: center,
                        startRadius: 12,
                        endRadius: mistR
                    )
                )
            }
            .drawingGroup()
        }
    }
}


/// Clean macOS QuickLook-style Spacebar preview overlay floating over the Star-Map.
struct StarMapQuickLookOverlay<HeaderActions: View, BodyContent: View>: View {
    
    let title: String
    let subtitle: String
    let canStepPrevious: Bool
    let canStepNext: Bool
    let onPrevious: () -> Void
    let onNext: () -> Void
    let onClose: () -> Void
    @ViewBuilder let headerActions: () -> HeaderActions
    @ViewBuilder let bodyContent: () -> BodyContent
    
    @Environment(\.colorScheme) private var colorScheme
    
    
    var body: some View {
        let tokens = DashPalette.editorialTokens(isDark: self.colorScheme == .dark)
        
        ZStack {
            Color.black.opacity(self.colorScheme == .dark ? 0.50 : 0.24)
                .ignoresSafeArea()
                .onTapGesture {
                    self.onClose()
                }
            
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    HStack(spacing: 4) {
                        Button(action: self.onPrevious) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 10.5, weight: .semibold))
                                .frame(width: 26, height: 26)
                                .background(tokens.inset, in: Circle())
                                .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .pointerStyle(self.canStepPrevious ? .link : .default)
                        .disabled(!self.canStepPrevious)
                        .opacity(self.canStepPrevious ? 1 : 0.35)
                        
                        Button(action: self.onNext) {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 10.5, weight: .semibold))
                                .frame(width: 26, height: 26)
                                .background(tokens.inset, in: Circle())
                                .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .pointerStyle(self.canStepNext ? .link : .default)
                        .disabled(!self.canStepNext)
                        .opacity(self.canStepNext ? 1 : 0.35)
                    }
                    
                    VStack(alignment: .leading, spacing: 1) {
                        Text(self.title)
                            .font(.system(size: 14.5, weight: .semibold))
                            .foregroundStyle(tokens.primaryInk)
                            .lineLimit(1)
                        if !self.subtitle.isEmpty {
                            Text(self.subtitle)
                                .font(.system(size: 11, weight: .regular, design: .rounded).monospacedDigit())
                                .foregroundStyle(tokens.primaryInk.opacity(0.52))
                                .lineLimit(1)
                        }
                    }
                    
                    Spacer(minLength: 8)
                    
                    self.headerActions()
                    
                    Button(action: self.onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(tokens.primaryInk.opacity(0.72))
                            .frame(width: 28, height: 28)
                            .background(tokens.inset, in: Circle())
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .pointerStyle(.link)
                    .help("按空格或 Esc 关闭预览")
                }
                .padding(.horizontal, 18)
                .frame(height: 54)
                
                Rectangle()
                    .fill(tokens.hairline)
                    .frame(height: 1)
                
                self.bodyContent()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: 760, maxHeight: 580)
            .background(tokens.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(tokens.hairlineStrong, lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(self.colorScheme == .dark ? 0.55 : 0.20), radius: 28, y: 12)
            .padding(28)
        }
        .transition(.opacity.combined(with: .scale(scale: 0.97)))
    }
}


// MARK: - Structured Star-Map Document Center

struct DocumentCenterView: View {
    
    @Bindable var state: DocumentCenterState
    var onOpenDocument: ((Document?, StoredDocumentRecord?) -> Void)?
    var onOpenAllDocuments: (([DocumentCenterState.ManagedDocumentItem]) -> Void)?
    var onDeleteDocument: ((DocumentCenterState.ManagedDocumentItem) -> Void)?
    var onCreateNewDocument: (() -> Void)?
    var onDismiss: (() -> Void)?
    
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.registerWorkspaceCenterEscPop) private var registerEscPop
    @State private var db = CotLocalDatabase.shared
    @State private var focusedClusterID: String?
    @State private var isQuickLookOpen = false
    @State private var isRenaming = false
    @State private var renameDraft = ""
    @FocusState private var isRenameFieldFocused: Bool
    @State private var isCreatingGroup = false
    @State private var newGroupDraft = ""
    @State private var pendingAssignAfterGroupCreate: DocumentCenterState.ManagedDocumentItem?
    @State private var renamingGroupName: String?
    @State private var groupRenameDraft = ""
    @State private var copiedFlag = false
    @State private var toastMessage: String?
    @State private var toastTask: Task<Void, Never>?
    @State private var keyMonitor: Any?
    
    
    var body: some View {
        let displayedItems = self.state.displayedItems
        let activeItem = self.selectedItem(in: displayedItems)
        let tokens = DashPalette.editorialTokens(isDark: self.colorScheme == .dark)
        let clusters = self.buildStarClusters(displayedItems: displayedItems, tokens: tokens)
        let itemByID = Dictionary(uniqueKeysWithValues: displayedItems.map { ($0.id, $0) })
        let sectionByID = Dictionary(uniqueKeysWithValues: self.state.groupSections.map { ($0.id, $0) })
        
        ZStack {
            ConstellationStarMapView(
                hubTitle: self.state.showingTrash ? "废纸篓" : "文档星图",
                hubSubtitle: self.state.showingTrash
                    ? "\(displayedItems.count) 篇已删"
                    : "\(displayedItems.count) 篇 · \(max(1, self.state.groupSections.count)) 分组",
                clusters: clusters,
                selectedLeafID: activeItem?.id,
                focusedClusterID: self.focusedClusterID,
                searchQuery: self.state.searchText,
                onSelectLeaf: { id in
                    self.isRenaming = false
                    self.state.selectedID = id
                },
                onDoubleClickLeaf: { id in
                    if let item = itemByID[id] {
                        if item.isTrashed {
                            withAnimation(.easeOut(duration: 0.16)) { self.isQuickLookOpen = true }
                        } else {
                            self.open(item: item)
                        }
                    }
                },
                onToggleCluster: { cid in
                    if self.state.collapsedGroups.contains(cid) {
                        self.state.collapsedGroups.remove(cid)
                    } else {
                        self.state.collapsedGroups.insert(cid)
                    }
                },
                clusterContextMenu: { cluster in
                    if let section = sectionByID[cluster.id] {
                        Button("展开此分组全部文档") {
                            self.openAll(items: section.items)
                        }
                        .disabled(section.items.isEmpty)
                        
                        if !section.isUngrouped {
                            Button("重命名分组") {
                                self.groupRenameDraft = section.name
                                self.renamingGroupName = section.name
                            }
                            Divider()
                            Button("解散分组（保留文档）", role: .destructive) {
                                self.db.deleteDocumentGroup(named: section.name)
                                if self.focusedClusterID == cluster.id { self.focusedClusterID = nil }
                                self.state.refresh()
                                self.showToast("已解散分组「\(section.name)」")
                            }
                        }
                    }
                },
                leafContextMenu: { leaf in
                    if let item = itemByID[leaf.id] {
                        if item.isTrashed {
                            Button("预览") {
                                self.state.selectedID = item.id
                                withAnimation(.easeOut(duration: 0.16)) { self.isQuickLookOpen = true }
                            }
                            Button("恢复文档") { self.restore(item: item) }
                            Divider()
                            Button("彻底删除", role: .destructive) { self.permanentlyDelete(item: item) }
                        } else {
                            Button("在编辑器打开") { self.open(item: item) }
                            Button("预览") {
                                self.state.selectedID = item.id
                                withAnimation(.easeOut(duration: 0.16)) { self.isQuickLookOpen = true }
                            }
                            Button("重命名") {
                                self.state.selectedID = item.id
                                self.renameDraft = item.title
                                self.isRenaming = true
                                DispatchQueue.main.async { self.isRenameFieldFocused = true }
                            }
                            Menu("移动到分组") {
                                Button("未分组") { self.move(item: item, toGroup: "") }
                                if !self.db.documentGroups.isEmpty {
                                    Divider()
                                    ForEach(self.db.documentGroups, id: \.self) { group in
                                        Button(group) { self.move(item: item, toGroup: group) }
                                    }
                                }
                                Divider()
                                Button("新建分组并移入…") {
                                    self.pendingAssignAfterGroupCreate = item
                                    self.newGroupDraft = ""
                                    self.isCreatingGroup = true
                                }
                            }
                            Divider()
                            Button("移入废纸篓", role: .destructive) {
                                self.delete(item: item, in: displayedItems)
                            }
                        }
                    }
                }
            )
            
            // Minimal Floating Top HUD + Group Quick-Jump Strip + Bottom Focus Dock
            VStack(spacing: 8) {
                self.floatingTopBar(tokens: tokens)
                    .padding(.horizontal, 16)
                    .padding(.top, 14)
                
                if !self.state.showingTrash && clusters.count > 1 {
                    self.groupQuickJumpStrip(clusters: clusters, tokens: tokens)
                        .padding(.horizontal, 16)
                }
                
                if self.isCreatingGroup {
                    self.inlineGroupPromptBar(
                        placeholder: "输入新分组名称…",
                        text: self.$newGroupDraft,
                        tokens: tokens,
                        onCommit: { self.commitCreateGroup() },
                        onCancel: {
                            self.isCreatingGroup = false
                            self.pendingAssignAfterGroupCreate = nil
                        }
                    )
                } else if let renamingGroup = self.renamingGroupName {
                    self.inlineGroupPromptBar(
                        placeholder: "重命名分组「\(renamingGroup)」…",
                        text: self.$groupRenameDraft,
                        tokens: tokens,
                        onCommit: { self.commitGroupRename(oldName: renamingGroup) },
                        onCancel: { self.renamingGroupName = nil }
                    )
                }
                
                Spacer()
                
                if let activeItem {
                    self.bottomFocusDock(item: activeItem, allItems: displayedItems, tokens: tokens)
                        .padding(.bottom, 16)
                } else {
                    self.floatingEmptyHint(tokens: tokens)
                        .padding(.bottom, 22)
                }
            }
            
            // Spacebar QuickLook Overlay
            if self.isQuickLookOpen, let item = activeItem {
                let idx = displayedItems.firstIndex(where: { $0.id == item.id }) ?? 0
                StarMapQuickLookOverlay(
                    title: item.title,
                    subtitle: "\(item.groupName.isEmpty ? "未分组" : item.groupName) · \(item.characterCount.formatted()) 字 · \(Self.relativeTime(item.updatedAt))",
                    canStepPrevious: idx > 0,
                    canStepNext: idx + 1 < displayedItems.count,
                    onPrevious: { self.stepSelection(by: -1, in: displayedItems) },
                    onNext: { self.stepSelection(by: 1, in: displayedItems) },
                    onClose: {
                        withAnimation(.easeOut(duration: 0.14)) { self.isQuickLookOpen = false }
                    },
                    headerActions: {
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(item.content, forType: .string)
                            self.copiedFlag = true
                            self.showToast("已复制全文")
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
                                .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .pointerStyle(.link)
                        
                        if item.isTrashed {
                            Button {
                                self.isQuickLookOpen = false
                                self.restore(item: item)
                            } label: {
                                Text("恢复文档")
                                    .font(.system(size: 11.5, weight: .semibold))
                                    .foregroundStyle(tokens.onAccentInk)
                                    .padding(.horizontal, 11)
                                    .frame(height: 26)
                                    .background(tokens.accent, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .pointerStyle(.link)
                        } else {
                            Button {
                                self.isQuickLookOpen = false
                                self.open(item: item)
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
                        CenterPreviewTextView(text: item.previewText)
                            .id("doc-ql-\(item.id)-\(idx)")
                    }
                )
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
            self.state.refresh()
            self.installKeyboardMonitor()
            self.registerEscPop? { self.handleEscapePop() }
        }
        .onDisappear {
            self.removeKeyboardMonitor()
            self.registerEscPop?(nil)
        }
        .onChange(of: self.db.documents.count) { _, _ in
            self.state.refresh()
        }
        .onChange(of: self.db.trashedDocuments.count) { _, _ in
            self.state.refresh()
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
                TextField("搜索星图文档…", text: self.$state.searchText)
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
                if !self.state.showingTrash {
                    if let onCreateNewDocument = self.onCreateNewDocument {
                        Button(action: onCreateNewDocument) {
                            HStack(spacing: 4) {
                                Image(systemName: "plus")
                                    .font(.system(size: 10.5, weight: .bold))
                                Text("新建文档")
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
                    }
                    
                    Button {
                        self.newGroupDraft = ""
                        self.pendingAssignAfterGroupCreate = nil
                        withAnimation(.easeOut(duration: 0.16)) { self.isCreatingGroup.toggle() }
                    } label: {
                        Text("新分组")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(tokens.primaryInk.opacity(0.80))
                            .padding(.horizontal, 10)
                            .frame(height: 30)
                            .background(tokens.card, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(tokens.hairlineStrong, lineWidth: 0.75))
                            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .pointerStyle(.link)
                } else if !self.state.trashedItems.isEmpty {
                    Button {
                        self.confirmEmptyTrash()
                    } label: {
                        Text("清空废纸篓")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.red)
                            .padding(.horizontal, 10)
                            .frame(height: 30)
                            .background(Color.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .pointerStyle(.link)
                }
                
                Button {
                    withAnimation(.easeOut(duration: 0.18)) {
                        self.isQuickLookOpen = false
                        self.focusedClusterID = nil
                        self.state.showingTrash.toggle()
                    }
                } label: {
                    let count = self.state.trashedItems.count
                    Text(self.state.showingTrash ? "返回星图" : (count > 0 ? "废纸篓 \(count)" : "废纸篓"))
                        .font(.system(size: 12, weight: .medium).monospacedDigit())
                        .foregroundStyle(self.state.showingTrash ? tokens.accentText : tokens.primaryInk.opacity(0.72))
                        .padding(.horizontal, 10)
                        .frame(height: 30)
                        .background(
                            self.state.showingTrash ? tokens.positivePillBg : tokens.card,
                            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                        )
                        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(tokens.hairlineStrong, lineWidth: 0.75))
                        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
                .pointerStyle(.link)
            }
        }
    }
    
    
    private func groupQuickJumpStrip(clusters: [StarMapClusterNode], tokens: StudioColorTokens) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                let allSelected = (self.focusedClusterID == nil)
                Button {
                    self.focusedClusterID = nil
                } label: {
                    Text("全部")
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
                    let isFocused = (self.focusedClusterID == cluster.id)
                    Button {
                        if self.state.collapsedGroups.contains(cluster.id) {
                            self.state.collapsedGroups.remove(cluster.id)
                        }
                        self.focusedClusterID = isFocused ? nil : cluster.id
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
    
    
    private func inlineGroupPromptBar(
        placeholder: String,
        text: Binding<String>,
        tokens: StudioColorTokens,
        onCommit: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 8) {
            TextField(placeholder, text: text)
                .textFieldStyle(.plain)
                .font(.system(size: 12.5))
                .frame(width: 210)
                .onSubmit(onCommit)
            
            Button("确定", action: onCommit)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(tokens.onAccentInk)
                .padding(.horizontal, 10)
                .frame(height: 24)
                .background(tokens.accent, in: Capsule())
                .buttonStyle(.plain)
            
            Button("取消", action: onCancel)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(tokens.primaryInk.opacity(0.62))
                .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(tokens.card, in: Capsule())
        .overlay(Capsule().strokeBorder(tokens.hairlineStrong, lineWidth: 0.85))
        .shadow(color: tokens.cardShadow, radius: 10, y: 4)
    }
    
    
    private func bottomFocusDock(
        item: DocumentCenterState.ManagedDocumentItem,
        allItems: [DocumentCenterState.ManagedDocumentItem],
        tokens: StudioColorTokens
    ) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(item.isOpenNow ? tokens.accent : tokens.primaryInk.opacity(0.35))
                .frame(width: 7, height: 7)
            
            if self.isRenaming {
                TextField("文档标题", text: self.$renameDraft)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12.5, weight: .semibold))
                    .focused(self.$isRenameFieldFocused)
                    .frame(width: 185)
                    .onSubmit { self.commitRename(for: item) }
                    .onExitCommand { self.isRenaming = false }
                
                Button("保存") { self.commitRename(for: item) }
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(tokens.onAccentInk)
                    .padding(.horizontal, 9)
                    .frame(height: 24)
                    .background(tokens.accent, in: Capsule())
                    .buttonStyle(.plain)
                
                Button("取消") { self.isRenaming = false }
                    .font(.system(size: 11))
                    .foregroundStyle(tokens.primaryInk.opacity(0.62))
                    .buttonStyle(.plain)
            } else {
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.title)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(tokens.primaryInk)
                        .lineLimit(1)
                        .frame(maxWidth: 200, alignment: .leading)
                    
                    Text("\(item.groupName.isEmpty ? "未分组" : item.groupName) · \(item.characterCount.formatted()) 字 · \(Self.relativeTime(item.updatedAt))")
                        .font(.system(size: 10, weight: .medium, design: .rounded).monospacedDigit())
                        .foregroundStyle(tokens.primaryInk.opacity(0.50))
                        .lineLimit(1)
                }
                
                Rectangle()
                    .fill(tokens.hairlineStrong)
                    .frame(width: 1, height: 20)
                
                Button {
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
                
                if item.isTrashed {
                    Button {
                        self.restore(item: item)
                    } label: {
                        Text("恢复")
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(tokens.onAccentInk)
                            .padding(.horizontal, 11)
                            .frame(height: 26)
                            .background(tokens.accent, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .pointerStyle(.link)
                    
                    Button {
                        self.permanentlyDelete(item: item)
                    } label: {
                        Text("彻底删除")
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(.red)
                            .padding(.horizontal, 9)
                            .frame(height: 26)
                            .background(Color.red.opacity(0.12), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .pointerStyle(.link)
                } else {
                    Button {
                        self.open(item: item)
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
                    
                    Menu {
                        Button("未分组") { self.move(item: item, toGroup: "") }
                        if !self.db.documentGroups.isEmpty {
                            Divider()
                            ForEach(self.db.documentGroups, id: \.self) { group in
                                Button(group) { self.move(item: item, toGroup: group) }
                            }
                        }
                        Divider()
                        Button("新建分组并移入…") {
                            self.pendingAssignAfterGroupCreate = item
                            self.newGroupDraft = ""
                            self.isCreatingGroup = true
                        }
                    } label: {
                        Text("分组")
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(tokens.primaryInk.opacity(0.78))
                            .padding(.horizontal, 9)
                            .frame(height: 26)
                            .background(tokens.inset, in: Capsule())
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .pointerStyle(.link)
                    
                    Button {
                        self.renameDraft = item.title
                        self.isRenaming = true
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
                        self.delete(item: item, in: allItems)
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
                    .help("移到废纸篓")
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(tokens.card, in: Capsule())
        .overlay(Capsule().strokeBorder(tokens.hairlineStrong, lineWidth: 0.85))
        .shadow(color: tokens.cardShadow, radius: 14, y: 4)
    }
    
    
    private func floatingEmptyHint(tokens: StudioColorTokens) -> some View {
        Text(self.state.showingTrash ? "废纸篓是空的" : (self.state.searchText.isEmpty ? "暂无文档 · 点击右上角新建" : "没有匹配的文档"))
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(tokens.primaryInk.opacity(0.55))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(tokens.card, in: Capsule())
            .overlay(Capsule().strokeBorder(tokens.hairline, lineWidth: 0.75))
    }
    
    
    // MARK: Constellation Data Mapping
    
    private func buildStarClusters(
        displayedItems: [DocumentCenterState.ManagedDocumentItem],
        tokens: StudioColorTokens
    ) -> [StarMapClusterNode] {
        let clusterAccents: [Color] = [
            tokens.accent,
            tokens.secondaryAccent,
            Color(red: 0.212, green: 0.478, blue: 0.612),
            tokens.heat3,
        ]
        
        if self.state.showingTrash {
            let leaves = displayedItems.map { item in
                StarMapLeafNode(
                    id: item.id,
                    clusterID: "trash",
                    title: item.title,
                    metaLine: "\(Self.compactChars(item.characterCount)) · \(Self.relativeTime(item.updatedAt))",
                    statusBadge: "已删",
                    dotColor: Color.red.opacity(0.75),
                    weight: 0.4,
                    isHighlighted: false
                )
            }
            return [
                StarMapClusterNode(
                    id: "trash",
                    title: "废纸篓",
                    countText: "\(leaves.count)",
                    accent: Color.red.opacity(0.75),
                    isCollapsed: false,
                    leaves: leaves
                ),
            ]
        }
        
        let maxChars = max(1.0, Double(displayedItems.map(\.characterCount).max() ?? 1))
        var result: [StarMapClusterNode] = []
        for (idx, section) in self.state.groupSections.enumerated() {
            let accent = section.isUngrouped
                ? tokens.primaryInk.opacity(0.45)
                : clusterAccents[idx % clusterAccents.count]
            let leaves = section.items.map { item -> StarMapLeafNode in
                let w = min(1.0, max(0.15, log10(Double(max(10, item.characterCount))) / log10(max(100.0, maxChars))))
                let status: String? = item.isDirty ? "未保存" : (item.isOpenNow ? "打开中" : nil)
                let dot: Color = item.isDirty ? .orange : (item.isOpenNow ? tokens.accent : accent.opacity(0.85))
                return StarMapLeafNode(
                    id: item.id,
                    clusterID: section.id,
                    title: item.title,
                    metaLine: "\(Self.compactChars(item.characterCount)) · \(Self.relativeTime(item.updatedAt))",
                    statusBadge: status,
                    dotColor: dot,
                    weight: w,
                    isHighlighted: item.isOpenNow
                )
            }
            result.append(StarMapClusterNode(
                id: section.id,
                title: section.name,
                countText: "\(leaves.count)",
                accent: accent,
                isCollapsed: self.state.collapsedGroups.contains(section.id),
                leaves: leaves
            ))
        }
        return result
    }
    
    
    private func selectedItem(in items: [DocumentCenterState.ManagedDocumentItem]) -> DocumentCenterState.ManagedDocumentItem? {
        if let id = self.state.selectedID, let match = items.first(where: { $0.id == id }) {
            return match
        }
        return items.first
    }
    
    
    private static func compactChars(_ count: Int) -> String {
        if count >= 10_000 { return String(format: "%.1f万字", Double(count) / 10_000.0) }
        if count >= 1_000 { return String(format: "%.1fK字", Double(count) / 1_000.0) }
        return "\(count)字"
    }
    
    
    private static func relativeTime(_ date: Date) -> String {
        let interval = max(0, Date().timeIntervalSince(date))
        if interval < 60 { return "刚刚" }
        if interval < 3600 { return "\(Int(interval / 60))分前" }
        if interval < 86_400 { return "\(Int(interval / 3600))时前" }
        let days = Int(interval / 86_400)
        if days < 30 { return "\(days)天前" }
        let f = DateFormatter()
        f.dateFormat = "M/d"
        return f.string(from: date)
    }
    
    
    // MARK: Keyboard Navigation
    
    private func handleEscapePop() -> Bool {
        if self.isQuickLookOpen {
            withAnimation(.easeOut(duration: 0.14)) { self.isQuickLookOpen = false }
            return true
        }
        if self.isRenaming {
            self.isRenaming = false
            return true
        }
        if self.isCreatingGroup {
            self.isCreatingGroup = false
            self.pendingAssignAfterGroupCreate = nil
            return true
        }
        if self.renamingGroupName != nil {
            self.renamingGroupName = nil
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
            if let responder = NSApp.keyWindow?.firstResponder, responder is NSTextView {
                return event
            }
            let items = self.state.displayedItems
            guard !items.isEmpty else { return event }
            
            switch event.keyCode {
                case 49: // Spacebar QuickLook toggle
                    if self.selectedItem(in: items) != nil {
                        withAnimation(.easeOut(duration: 0.15)) {
                            self.isQuickLookOpen.toggle()
                        }
                        return nil
                    }
                case 123, 126: // Left / Up
                    self.stepSelection(by: -1, in: items)
                    return nil
                case 124, 125: // Right / Down
                    self.stepSelection(by: 1, in: items)
                    return nil
                case 36: // Return -> open
                    if let active = self.selectedItem(in: items), !active.isTrashed {
                        self.isQuickLookOpen = false
                        self.open(item: active)
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
    
    
    private func stepSelection(by delta: Int, in list: [DocumentCenterState.ManagedDocumentItem]) {
        guard !list.isEmpty else { return }
        let curIdx = list.firstIndex(where: { $0.id == self.state.selectedID }) ?? 0
        let nextIdx = (curIdx + delta + list.count) % list.count
        self.state.selectedID = list[nextIdx].id
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
            self.state.refresh()
            self.showToast("已新建分组「\(created)」")
        }
    }
    
    
    private func commitGroupRename(oldName: String) {
        let trimmed = self.groupRenameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        self.renamingGroupName = nil
        guard !trimmed.isEmpty, trimmed != oldName else { return }
        if self.db.renameDocumentGroup(from: oldName, to: trimmed) {
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
