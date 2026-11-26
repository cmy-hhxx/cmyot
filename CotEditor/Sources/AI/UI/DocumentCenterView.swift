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
/// happens in <1ms with zero SwiftUI `Text` layout teardown, supporting live keyword highlighting.
struct CenterPreviewTextView: NSViewRepresentable {
    
    let text: String
    var monospace: Bool = false
    var highlightTerms: [String] = []
    
    final class Coordinator {
        var lastText: String?
        var lastMonospace: Bool?
        var lastHighlightKey: String?
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    func makeNSView(context: Context) -> NSScrollView {
        
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = false
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
        textView.textContainerInset = NSSize(width: 30, height: 22)
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 5.5
        textView.defaultParagraphStyle = paragraphStyle
        textView.font = self.monospace
            ? .monospacedSystemFont(ofSize: 12.5, weight: .regular)
            : .systemFont(ofSize: 13.5)
        textView.textColor = .labelColor
        
        scrollView.documentView = textView
        return scrollView
    }
    
    
    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        
        guard let textView = scrollView.documentView as? NSTextView else { return }
        let coordinator = context.coordinator
        let highlightKey = self.highlightTerms.joined(separator: "\u{1F}")
        
        guard coordinator.lastText != self.text
            || coordinator.lastMonospace != self.monospace
            || coordinator.lastHighlightKey != highlightKey
        else {
            return
        }
        coordinator.lastText = self.text
        coordinator.lastMonospace = self.monospace
        coordinator.lastHighlightKey = highlightKey
        
        let targetFont: NSFont = self.monospace
            ? .monospacedSystemFont(ofSize: 12.5, weight: .regular)
            : .systemFont(ofSize: 13.5)
        let boldFont: NSFont = self.monospace
            ? .monospacedSystemFont(ofSize: 12.5, weight: .semibold)
            : .systemFont(ofSize: 13.5, weight: .semibold)
        if textView.font != targetFont {
            textView.font = targetFont
        }
        
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 5.5
        let attributed = NSMutableAttributedString(string: self.text, attributes: [
            .font: targetFont,
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraphStyle,
        ])
        
        let nsText = self.text as NSString
        let fullLength = nsText.length
        var firstMatchRange: NSRange?
        var remainingHighlights = 400
        let cleanTerms = self.highlightTerms
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        
        if !cleanTerms.isEmpty, fullLength > 0 {
            let matchBg = NSColor.systemYellow.withAlphaComponent(0.36)
            for term in cleanTerms {
                var searchLocation = 0
                while searchLocation < fullLength && remainingHighlights > 0 {
                    let searchRange = NSRange(location: searchLocation, length: fullLength - searchLocation)
                    let found = nsText.range(
                        of: term,
                        options: [.caseInsensitive, .diacriticInsensitive],
                        range: searchRange
                    )
                    guard found.location != NSNotFound, found.length > 0 else { break }
                    attributed.addAttributes([
                        .backgroundColor: matchBg,
                        .font: boldFont,
                    ], range: found)
                    if let currentFirst = firstMatchRange {
                        if found.location < currentFirst.location {
                            firstMatchRange = found
                        }
                    } else {
                        firstMatchRange = found
                    }
                    remainingHighlights -= 1
                    searchLocation = found.location + found.length
                }
            }
        }
        
        textView.textStorage?.setAttributedString(attributed)
        if let firstMatchRange, let container = textView.textContainer {
            textView.layoutManager?.ensureLayout(for: container)
            textView.scrollRangeToVisible(firstMatchRange)
            textView.showFindIndicator(for: firstMatchRange)
        } else {
            scrollView.contentView.scroll(to: .zero)
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }
    }
}


// MARK: - Structured Bidirectional Tree Layout Engine (整齐左右分栏 · 零交叉 · O(N) 确定性布局)

nonisolated enum StarMapLayoutStyle: Equatable, Sendable {
    case timeline
    case orbital
}


nonisolated enum StarMapLayoutEngine {
    
    struct PositionedCluster: Identifiable, Equatable {
        let id: String
        let worldPoint: CGPoint
        let angle: Double
    }
    
    struct PositionedLeaf: Identifiable, Equatable {
        let id: String
        let clusterID: String
        let worldPoint: CGPoint
        let parentPoint: CGPoint
        let angle: Double
    }
    
    struct LayoutResult: Equatable {
        struct LeafColumnKey: Hashable {
            let clusterID: String
            let quantizedX: Int
        }

        let hubPoint: CGPoint
        let usesTimelineSpine: Bool
        let usesOrbitalLayout: Bool
        let clusters: [PositionedCluster]
        let leaves: [PositionedLeaf]
        let bounds: CGRect
        let leafPositionsByID: [String: PositionedLeaf]
        let leafColumns: [LeafColumnKey: [PositionedLeaf]]
        
        init(
            hubPoint: CGPoint = .zero,
            usesTimelineSpine: Bool = false,
            usesOrbitalLayout: Bool = false,
            clusters: [PositionedCluster],
            leaves: [PositionedLeaf],
            bounds: CGRect
        ) {
            self.hubPoint = hubPoint
            self.usesTimelineSpine = usesTimelineSpine
            self.usesOrbitalLayout = usesOrbitalLayout
            self.clusters = clusters
            self.leaves = leaves
            self.bounds = bounds
            self.leafPositionsByID = Dictionary(leaves.lazy.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            self.leafColumns = Dictionary(grouping: leaves) { leaf in
                LeafColumnKey(clusterID: leaf.clusterID, quantizedX: Int(leaf.worldPoint.x.rounded()))
            }
        }
    }
    
    
    static let hubFootprint = CGSize(width: 156, height: 68)
    static let milestoneFootprint = CGSize(width: 104, height: 24)
    static let clusterFootprint = CGSize(width: 164, height: 44)
    static let leafFootprint = CGSize(width: 196, height: 56)
    
    private static let rowsPerSubcolumn = 8
    private static let rowStep: CGFloat = 66 // 56pt card + 10pt gap
    private static let clusterVerticalGap: CGFloat = 32
    private static let timelineMilestoneStep: CGFloat = 48
    private static let clusterCenterX: CGFloat = 236 // Hub half(78) + corridor(76) + Cluster half(82)
    private static let firstLeafColumnX: CGFloat = 468 // Cluster outer(318) + spine corridor(52) + Leaf half(98)
    private static let subcolumnStrideX: CGFloat = 232 // 196pt card + 36pt spine corridor
    
    
    static func compute(
        clusterIDs: [String],
        leafCountsByCluster: [String: Int],
        collapsedClusterIDs: Set<String>,
        leafIDsByCluster: [String: [String]],
        usesTimelineSpine: Bool = false
    ) -> LayoutResult {
        guard !clusterIDs.isEmpty else {
            return LayoutResult(
                hubPoint: .zero,
                usesTimelineSpine: usesTimelineSpine,
                clusters: [],
                leaves: [],
                bounds: CGRect(x: -180, y: -140, width: 360, height: 280)
            )
        }
        
        struct ClusterSpec {
            let index: Int
            let id: String
            let leaves: [String]
            let blockHeight: CGFloat
        }
        
        let specs: [ClusterSpec] = clusterIDs.enumerated().map { idx, cid in
            let isCollapsed = collapsedClusterIDs.contains(cid)
            let rawLeaves = isCollapsed ? [] : (leafIDsByCluster[cid] ?? [])
            let visibleRows = min(Self.rowsPerSubcolumn, rawLeaves.count)
            let leavesHeight = visibleRows > 0
                ? CGFloat(visibleRows) * Self.rowStep - (Self.rowStep - Self.leafFootprint.height)
                : 0
            let blockH = max(Self.clusterFootprint.height, leavesHeight)
            return ClusterSpec(index: idx, id: cid, leaves: rawLeaves, blockHeight: blockH)
        }
        
        func buildClusterLeaves(for spec: ClusterSpec, side: CGFloat, blockMidY: CGFloat, clusterPt: CGPoint) -> [PositionedLeaf] {
            guard !spec.leaves.isEmpty else { return [] }
            var clusterLeaves: [PositionedLeaf] = []
            let subcolCount = Int(ceil(Double(spec.leaves.count) / Double(Self.rowsPerSubcolumn)))
            for colIdx in 0..<subcolCount {
                let start = colIdx * Self.rowsPerSubcolumn
                let end = min(spec.leaves.count, start + Self.rowsPerSubcolumn)
                let slice = spec.leaves[start..<end]
                let colX = side * (Self.firstLeafColumnX + CGFloat(colIdx) * Self.subcolumnStrideX)
                let parentAnchor: CGPoint = colIdx == 0
                    ? clusterPt
                    : CGPoint(x: side * (Self.firstLeafColumnX + CGFloat(colIdx - 1) * Self.subcolumnStrideX), y: blockMidY)
                let startY = blockMidY - CGFloat(slice.count - 1) * Self.rowStep * 0.5
                for (rowOffset, leafID) in slice.enumerated() {
                    let pt = CGPoint(x: colX, y: startY + CGFloat(rowOffset) * Self.rowStep)
                    clusterLeaves.append(PositionedLeaf(
                        id: leafID,
                        clusterID: spec.id,
                        worldPoint: pt,
                        parentPoint: parentAnchor,
                        angle: atan2(Double(pt.y), Double(pt.x))
                    ))
                }
            }
            return clusterLeaves
        }
        
        if usesTimelineSpine {
            // Chronological Top-to-Bottom Timeline Spine down X = 0, alternating Left (-1) / Right (+1)
            let rawHubY: CGFloat = 0
            let firstZoneTop: CGFloat = Self.hubFootprint.height * 0.5 + 36
            var leftBottomY: CGFloat = firstZoneTop
            var rightBottomY: CGFloat = firstZoneTop
            var prevMilestoneY: CGFloat?
            
            var rawClusters: [PositionedCluster] = []
            var rawLeaves: [PositionedLeaf] = []
            rawClusters.reserveCapacity(specs.count)
            
            for (idx, spec) in specs.enumerated() {
                let side: CGFloat = (idx % 2 == 0) ? -1.0 : 1.0
                let sideAvailTop = (side < 0) ? leftBottomY : rightBottomY
                let minCenterForSide = sideAvailTop + spec.blockHeight * 0.5
                let minCenterForSpine = prevMilestoneY.map { $0 + Self.timelineMilestoneStep }
                    ?? (firstZoneTop + Self.clusterFootprint.height * 0.5)
                let blockMidY = max(minCenterForSide, minCenterForSpine)
                let cPt = CGPoint(x: side * Self.clusterCenterX, y: blockMidY)
                
                rawClusters.append(PositionedCluster(
                    id: spec.id,
                    worldPoint: cPt,
                    angle: atan2(Double(cPt.y), Double(cPt.x))
                ))
                rawLeaves.append(contentsOf: buildClusterLeaves(for: spec, side: side, blockMidY: blockMidY, clusterPt: cPt))
                
                prevMilestoneY = blockMidY
                let nextBottom = blockMidY + spec.blockHeight * 0.5 + Self.clusterVerticalGap
                if side < 0 {
                    leftBottomY = nextBottom
                } else {
                    rightBottomY = nextBottom
                }
            }
            
            let rawTopY = rawHubY - Self.hubFootprint.height * 0.5
            let rawBottomY = max(leftBottomY, rightBottomY) - Self.clusterVerticalGap
            let shiftY = -(rawTopY + rawBottomY) * 0.5
            
            let hubPoint = CGPoint(x: 0, y: rawHubY + shiftY)
            let shiftedClusters = rawClusters.map { c in
                let pt = CGPoint(x: c.worldPoint.x, y: c.worldPoint.y + shiftY)
                return PositionedCluster(id: c.id, worldPoint: pt, angle: atan2(Double(pt.y), Double(pt.x)))
            }
            let shiftedLeaves = rawLeaves.map { l in
                let pt = CGPoint(x: l.worldPoint.x, y: l.worldPoint.y + shiftY)
                let parentPt = CGPoint(x: l.parentPoint.x, y: l.parentPoint.y + shiftY)
                return PositionedLeaf(id: l.id, clusterID: l.clusterID, worldPoint: pt, parentPoint: parentPt, angle: atan2(Double(pt.y), Double(pt.x)))
            }
            
            var minX: CGFloat = -Self.hubFootprint.width * 0.5 - 30
            var maxX: CGFloat = Self.hubFootprint.width * 0.5 + 30
            var minY: CGFloat = hubPoint.y - Self.hubFootprint.height * 0.5 - 28
            var maxY: CGFloat = hubPoint.y + Self.hubFootprint.height * 0.5 + 28
            
            func includeTimeline(_ pt: CGPoint, size: CGSize) {
                minX = min(minX, pt.x - size.width * 0.5 - 28)
                maxX = max(maxX, pt.x + size.width * 0.5 + 28)
                minY = min(minY, pt.y - size.height * 0.5 - 28)
                maxY = max(maxY, pt.y + size.height * 0.5 + 28)
            }
            for c in shiftedClusters {
                includeTimeline(c.worldPoint, size: Self.clusterFootprint)
                includeTimeline(CGPoint(x: 0, y: c.worldPoint.y), size: Self.milestoneFootprint)
            }
            for l in shiftedLeaves {
                includeTimeline(l.worldPoint, size: Self.leafFootprint)
            }
            return LayoutResult(
                hubPoint: hubPoint,
                usesTimelineSpine: true,
                clusters: shiftedClusters,
                leaves: shiftedLeaves,
                bounds: CGRect(x: minX, y: minY, width: max(380, maxX - minX), height: max(260, maxY - minY))
            )
        }
        
        // Balance clusters cleanly across Right (+1) and Left (-1) columns
        var rightSpecs: [ClusterSpec] = []
        var leftSpecs: [ClusterSpec] = []
        var rightHeight: CGFloat = 0
        var leftHeight: CGFloat = 0
        
        for spec in specs {
            if rightSpecs.isEmpty || (specs.count > 1 && rightHeight <= leftHeight) {
                rightHeight += (rightSpecs.isEmpty ? 0 : Self.clusterVerticalGap) + spec.blockHeight
                rightSpecs.append(spec)
            } else {
                leftHeight += (leftSpecs.isEmpty ? 0 : Self.clusterVerticalGap) + spec.blockHeight
                leftSpecs.append(spec)
            }
        }
        
        var positionedClustersByIndex: [Int: PositionedCluster] = [:]
        var positionedLeavesByCluster: [Int: [PositionedLeaf]] = [:]
        
        func placeSide(_ sideSpecs: [ClusterSpec], side: CGFloat, totalHeight: CGFloat) {
            var cursorY = -totalHeight * 0.5
            for spec in sideSpecs {
                let blockMidY = cursorY + spec.blockHeight * 0.5
                let cPt = CGPoint(x: side * Self.clusterCenterX, y: blockMidY)
                let cAngle = atan2(Double(cPt.y), Double(cPt.x))
                positionedClustersByIndex[spec.index] = PositionedCluster(
                    id: spec.id,
                    worldPoint: cPt,
                    angle: cAngle
                )
                positionedLeavesByCluster[spec.index] = buildClusterLeaves(for: spec, side: side, blockMidY: blockMidY, clusterPt: cPt)
                cursorY += spec.blockHeight + Self.clusterVerticalGap
            }
        }
        
        placeSide(rightSpecs, side: 1.0, totalHeight: rightHeight)
        if !leftSpecs.isEmpty {
            placeSide(leftSpecs, side: -1.0, totalHeight: leftHeight)
        }
        
        let orderedClusters = (0..<specs.count).compactMap { positionedClustersByIndex[$0] }
        let orderedLeaves = (0..<specs.count).flatMap { positionedLeavesByCluster[$0] ?? [] }
        
        var minX: CGFloat = -Self.hubFootprint.width * 0.5 - 30
        var maxX: CGFloat = Self.hubFootprint.width * 0.5 + 30
        var minY: CGFloat = -150
        var maxY: CGFloat = 150
        
        func include(_ pt: CGPoint, size: CGSize) {
            minX = min(minX, pt.x - size.width * 0.5 - 28)
            maxX = max(maxX, pt.x + size.width * 0.5 + 28)
            minY = min(minY, pt.y - size.height * 0.5 - 28)
            maxY = max(maxY, pt.y + size.height * 0.5 + 28)
        }
        
        for c in orderedClusters {
            include(c.worldPoint, size: Self.clusterFootprint)
        }
        for l in orderedLeaves {
            include(l.worldPoint, size: Self.leafFootprint)
        }
        
        return LayoutResult(
            hubPoint: .zero,
            usesTimelineSpine: false,
            clusters: orderedClusters,
            leaves: orderedLeaves,
            bounds: CGRect(x: minX, y: minY, width: max(380, maxX - minX), height: max(300, maxY - minY))
        )
    }
    
    
    /// Pure deterministic non-overlapping orbital universe layout for Document Center.
    static func computeOrbital(
        clusterIDs: [String],
        collapsedClusterIDs: Set<String>,
        leafIDsByCluster: [String: [String]]
    ) -> LayoutResult {
        guard !clusterIDs.isEmpty else {
            return LayoutResult(
                hubPoint: .zero,
                usesTimelineSpine: false,
                usesOrbitalLayout: true,
                clusters: [],
                leaves: [],
                bounds: CGRect(x: -180, y: -140, width: 360, height: 280)
            )
        }
        
        let hubClearanceBox = CGRect(
            x: -Self.hubFootprint.width * 0.5 - 16,
            y: -Self.hubFootprint.height * 0.5 - 16,
            width: Self.hubFootprint.width + 32,
            height: Self.hubFootprint.height + 32
        )
        
        var placedBoxes: [CGRect] = [hubClearanceBox]
        var orderedClusters: [PositionedCluster] = []
        var orderedLeaves: [PositionedLeaf] = []
        orderedClusters.reserveCapacity(clusterIDs.count)
        
        let goldenAngle = 2.39996322972865332
        let baseClusterGapX: CGFloat = Self.clusterFootprint.width * 0.5 + 48 + Self.leafFootprint.width * 0.5
        
        for (idx, cid) in clusterIDs.enumerated() {
            let ringIndex = Self.orbitalRingIndex(forClusterIndex: idx)
            let ringStart = Self.orbitalRingFirstIndex(ringIndex)
            let ringCapacity = Self.orbitalRingCapacity(ringIndex)
            let countInRing = min(ringCapacity, clusterIDs.count - ringStart)
            let posInRing = idx - ringStart
            let baseAngle = (Double(posInRing) / Double(max(1, countInRing))) * (.pi * 2.0) + goldenAngle * Double(ringIndex)
            let dirX = CGFloat(cos(baseAngle))
            let dirY = CGFloat(sin(baseAngle))
            let side: CGFloat = dirX >= 0 ? 1.0 : -1.0
            
            let leafIDs = collapsedClusterIDs.contains(cid) ? [] : (leafIDsByCluster[cid] ?? [])
            var radius: CGFloat = 250 + CGFloat(ringIndex) * 320
            var candidateClusterPt = CGPoint(x: dirX * radius, y: dirY * radius)
            var candidateLeaves: [PositionedLeaf] = []
            var candidateBox = CGRect.zero
            
            for _ in 0..<260 {
                candidateClusterPt = CGPoint(x: dirX * radius, y: dirY * radius)
                (candidateLeaves, candidateBox) = Self.orbitalClusterBlock(
                    clusterID: cid,
                    clusterPt: candidateClusterPt,
                    side: side,
                    baseOffsetX: baseClusterGapX,
                    leafIDs: leafIDs
                )
                let padded = candidateBox.insetBy(dx: -10, dy: -10)
                if !placedBoxes.contains(where: { $0.intersects(padded) }) {
                    break
                }
                radius += 58
            }
            
            placedBoxes.append(candidateBox)
            orderedClusters.append(PositionedCluster(
                id: cid,
                worldPoint: candidateClusterPt,
                angle: atan2(Double(candidateClusterPt.y), Double(candidateClusterPt.x))
            ))
            orderedLeaves.append(contentsOf: candidateLeaves)
        }
        
        let unionBounds = placedBoxes.reduce(CGRect.null) { $0.union($1) }.insetBy(dx: -24, dy: -24)
        return LayoutResult(
            hubPoint: .zero,
            usesTimelineSpine: false,
            usesOrbitalLayout: true,
            clusters: orderedClusters,
            leaves: orderedLeaves,
            bounds: CGRect(
                x: unionBounds.minX,
                y: unionBounds.minY,
                width: max(380, unionBounds.width),
                height: max(300, unionBounds.height)
            )
        )
    }
    
    
    private static func orbitalRingIndex(forClusterIndex index: Int) -> Int {
        var ring = 0
        var remaining = index
        while true {
            let cap = Self.orbitalRingCapacity(ring)
            if remaining < cap { return ring }
            remaining -= cap
            ring += 1
        }
    }
    
    
    private static func orbitalRingFirstIndex(_ ring: Int) -> Int {
        guard ring > 0 else { return 0 }
        var total = 0
        for r in 0..<ring {
            total += Self.orbitalRingCapacity(r)
        }
        return total
    }
    
    
    private static func orbitalRingCapacity(_ ring: Int) -> Int {
        6 + ring * 6
    }
    
    
    private static func orbitalClusterBlock(
        clusterID: String,
        clusterPt: CGPoint,
        side: CGFloat,
        baseOffsetX: CGFloat,
        leafIDs: [String]
    ) -> (leaves: [PositionedLeaf], bounds: CGRect) {
        var box = CGRect(
            x: clusterPt.x - Self.clusterFootprint.width * 0.5,
            y: clusterPt.y - Self.clusterFootprint.height * 0.5,
            width: Self.clusterFootprint.width,
            height: Self.clusterFootprint.height
        )
        guard !leafIDs.isEmpty else { return ([], box) }
        
        var leaves: [PositionedLeaf] = []
        leaves.reserveCapacity(leafIDs.count)
        let subcolCount = Int(ceil(Double(leafIDs.count) / Double(Self.rowsPerSubcolumn)))
        for colIdx in 0..<subcolCount {
            let start = colIdx * Self.rowsPerSubcolumn
            let end = min(leafIDs.count, start + Self.rowsPerSubcolumn)
            let slice = leafIDs[start..<end]
            let colX = clusterPt.x + side * (baseOffsetX + CGFloat(colIdx) * Self.subcolumnStrideX)
            let startY = clusterPt.y - CGFloat(slice.count - 1) * Self.rowStep * 0.5
            for (rowOffset, leafID) in slice.enumerated() {
                let pt = CGPoint(x: colX, y: startY + CGFloat(rowOffset) * Self.rowStep)
                leaves.append(PositionedLeaf(
                    id: leafID,
                    clusterID: clusterID,
                    worldPoint: pt,
                    parentPoint: clusterPt,
                    angle: atan2(Double(pt.y), Double(pt.x))
                ))
                let leafRect = CGRect(
                    x: pt.x - Self.leafFootprint.width * 0.5,
                    y: pt.y - Self.leafFootprint.height * 0.5,
                    width: Self.leafFootprint.width,
                    height: Self.leafFootprint.height
                )
                box = box.union(leafRect)
            }
        }
        return (leaves, box)
    }
}


// MARK: - Full-Text Multi-Keyword Search Engine

nonisolated struct StarMapSearchHit: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let categoryLabel: String
    let metaLabel: String
    let totalHits: Int
    let score: Int
    let snippet: String?
}


nonisolated enum StarMapSearchEngine {

    struct SearchDocument: Sendable {
        let title: String
        let category: String
        let metadata: String
        let content: String

        func evaluate(terms: [String]) -> MatchEvaluation {
            StarMapSearchEngine.evaluate(queryTerms: terms, title: self.title, category: self.category,
                                         secondaryMeta: self.metadata, content: self.content)
        }
    }
    
    struct MatchEvaluation: Sendable, Equatable {
        let isMatch: Bool
        let score: Int
        let totalHits: Int
        let snippet: String?
        let matchedTerms: [String]
    }


    @concurrent static func evaluateCorpus(_ documents: [SearchDocument], terms: [String]) async -> [MatchEvaluation]? {
        var evaluations: [MatchEvaluation] = []
        evaluations.reserveCapacity(documents.count)
        for document in documents {
            guard !Task.isCancelled else { return nil }
            evaluations.append(document.evaluate(terms: terms))
        }
        return evaluations
    }
    
    
    static func parseTerms(_ rawQuery: String) -> [String] {
        var seen = Set<String>()
        var terms: [String] = []
        for piece in rawQuery.components(separatedBy: .whitespacesAndNewlines) {
            let clean = piece.trimmingCharacters(in: .whitespacesAndNewlines)
            let folded = clean.lowercased()
            guard !clean.isEmpty, seen.insert(folded).inserted else { continue }
            terms.append(clean)
        }
        return terms
    }
    
    
    static func evaluate(
        queryTerms: [String],
        title: String,
        category: String,
        secondaryMeta: String,
        content: String
    ) -> MatchEvaluation {
        guard !queryTerms.isEmpty else {
            return MatchEvaluation(isMatch: true, score: 0, totalHits: 0, snippet: nil, matchedTerms: [])
        }
        
        var score = 0
        var totalHits = 0
        var matched: [String] = []
        var firstContentRange: Range<String.Index>?
        
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        
        for term in queryTerms {
            let titleCount = Self.countOccurrences(of: term, in: title, cap: 8)
            let categoryCount = Self.countOccurrences(of: term, in: category, cap: 4)
            let metaCount = Self.countOccurrences(of: term, in: secondaryMeta, cap: 4)
            let contentResult = Self.countAndFirstRange(of: term, in: content, cap: 50)
            
            let termHits = titleCount + categoryCount + metaCount + contentResult.count
            guard termHits > 0 else {
                return MatchEvaluation(isMatch: false, score: 0, totalHits: 0, snippet: nil, matchedTerms: [])
            }
            
            matched.append(term)
            totalHits += termHits
            
            if trimmedTitle.compare(term, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame {
                score += 180
            } else if titleCount > 0 {
                score += 110 + min(3, titleCount) * 20
            }
            if categoryCount > 0 {
                score += 45
            }
            if metaCount > 0 {
                score += 25
            }
            score += min(40, contentResult.count) * 12
            
            if let foundRange = contentResult.firstRange {
                if let existing = firstContentRange {
                    if foundRange.lowerBound < existing.lowerBound {
                        firstContentRange = foundRange
                    }
                } else {
                    firstContentRange = foundRange
                }
            }
        }
        
        let snippet = firstContentRange.flatMap { Self.extractSnippet(in: content, anchorRange: $0) }
        return MatchEvaluation(
            isMatch: true,
            score: score,
            totalHits: totalHits,
            snippet: snippet,
            matchedTerms: matched
        )
    }
    
    
    private static func countOccurrences(of term: String, in text: String, cap: Int) -> Int {
        guard !text.isEmpty else { return 0 }
        var count = 0
        var start = text.startIndex
        while start < text.endIndex && count < cap {
            guard let range = text.range(
                of: term,
                options: [.caseInsensitive, .diacriticInsensitive],
                range: start..<text.endIndex
            ) else { break }
            count += 1
            start = range.upperBound
        }
        return count
    }
    
    
    private static func countAndFirstRange(
        of term: String,
        in text: String,
        cap: Int
    ) -> (count: Int, firstRange: Range<String.Index>?) {
        guard !text.isEmpty else { return (0, nil) }
        var count = 0
        var first: Range<String.Index>?
        var start = text.startIndex
        while start < text.endIndex && count < cap {
            guard let range = text.range(
                of: term,
                options: [.caseInsensitive, .diacriticInsensitive],
                range: start..<text.endIndex
            ) else { break }
            if first == nil {
                first = range
            }
            count += 1
            start = range.upperBound
        }
        return (count, first)
    }
    
    
    private static func extractSnippet(
        in content: String,
        anchorRange: Range<String.Index>
    ) -> String? {
        let lowerBound = content.index(anchorRange.lowerBound, offsetBy: -26, limitedBy: content.startIndex) ?? content.startIndex
        let upperBound = content.index(anchorRange.upperBound, offsetBy: 48, limitedBy: content.endIndex) ?? content.endIndex
        let rawSlice = String(content[lowerBound..<upperBound])
        let collapsed = rawSlice
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !collapsed.isEmpty else { return nil }
        let prefix = lowerBound > content.startIndex ? "..." : ""
        let suffix = upperBound < content.endIndex ? "..." : ""
        return "\(prefix)\(collapsed)\(suffix)"
    }
}


// MARK: - Cross-Node Semantic & Structural Relationship Engine

nonisolated struct StarMapRelationEdge: Identifiable, Equatable, Sendable {
    let sourceID: String
    let targetID: String
    let strength: Double
    let reason: String
    
    var id: String {
        self.sourceID < self.targetID
            ? "\(self.sourceID)<->\(self.targetID)"
            : "\(self.targetID)<->\(self.sourceID)"
    }
}


nonisolated enum StarMapRelationEngine {
    
    struct CorpusDocument: Equatable, Sendable {
        let id: String
        let title: String
        let group: String
        let folderPath: String?
        let content: String
        let sortTimestamp: TimeInterval
    }

    static let corpusLimit = 64
    
    private static let asciiStopWords: Set<String> = [
        "the", "and", "for", "with", "this", "that", "from", "have", "has", "was", "were",
        "are", "but", "not", "you", "your", "our", "will", "can", "into", "about", "more",
        "http", "https", "www", "com", "org", "var", "let", "func", "return", "import",
        "struct", "class", "enum", "true", "false", "null", "nil", "none", "markdown",
    ]
    
    private static let cjkStopWords: Set<String> = [
        "未命名", "文档", "周报", "本周", "上周", "工作", "总结", "完成", "进行", "问题",
        "需要", "可以", "一个", "我们", "目前", "相关", "内容", "记录", "使用", "通过",
        "支持", "已经", "如果", "没有", "以及", "主要", "部分", "方面", "情况",
    ]
    
    private nonisolated(unsafe) static let asciiTermRegex = try? NSRegularExpression(pattern: #"[A-Za-z][A-Za-z0-9_\-\.]{2,24}"#)
    private nonisolated(unsafe) static let cjkTermRegex = try? NSRegularExpression(pattern: #"[\p{Han}]{2,12}"#)
    private nonisolated(unsafe) static let structTermRegex = try? NSRegularExpression(
        pattern: #"(?:^#{1,4}\s+([^\n]+)|\[\[([^\]\n]+)\]\]|「([^」\n]+)」|【([^】\n]+)】|`([^`\n]{2,28})`|\*\*([^\*\n]{2,28})\*\*)"#,
        options: [.anchorsMatchLines]
    )
    
    private final class TermCacheBox: @unchecked Sendable {
        let lock = NSLock()
        var termsByKey: [String: Set<String>] = [:]
        var keyOrder: [String] = []
    }
    private static let termCache = TermCacheBox()
    private static let maxCachedTermEntries = 512
    
    
    private static func termCacheKey(title: String, sampledBody: Substring) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in title.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        hash ^= 0xFF
        for byte in sampledBody.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return "\(title.count):\(sampledBody.count):\(hash)"
    }
    
    
    static func extractKeyTerms(title: String, content: String) -> Set<String> {
        let sampledBody = content.prefix(6_000)
        let key = Self.termCacheKey(title: title, sampledBody: sampledBody)
        Self.termCache.lock.lock()
        if let cached = Self.termCache.termsByKey[key] {
            Self.termCache.lock.unlock()
            return cached
        }
        Self.termCache.lock.unlock()
        
        var terms = Set<String>()
        
        func harvestASCIIAndCJK(from text: String, addBigrams: Bool) {
            // ASCII identifiers / words (>= 3 chars)
            if let asciiRegex = Self.asciiTermRegex {
                let ns = text as NSString
                for m in asciiRegex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
                    let token = ns.substring(with: m.range).trimmingCharacters(in: CharacterSet(charactersIn: ".-_"))
                    let lower = token.lowercased()
                    guard token.count >= 3, !Self.asciiStopWords.contains(lower) else { continue }
                    terms.insert(token.count <= 14 ? token : lower)
                }
            }
            
            // CJK phrase spans (2...6 Han characters or frequent bigrams)
            if let cjkRegex = Self.cjkTermRegex {
                let ns = text as NSString
                var cjkCounts: [String: Int] = [:]
                for m in cjkRegex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
                    let span = ns.substring(with: m.range)
                    if span.count <= 5 && !Self.cjkStopWords.contains(span) {
                        terms.insert(span)
                    }
                    if addBigrams && span.count >= 4 {
                        let chars = Array(span)
                        for idx in 0...(chars.count - 2) {
                            let bg = String(chars[idx...(idx + 1)])
                            if !Self.cjkStopWords.contains(bg) {
                                cjkCounts[bg, default: 0] += 1
                            }
                        }
                    }
                }
                if addBigrams {
                    for (bg, count) in cjkCounts where count >= 2 {
                        terms.insert(bg)
                    }
                }
            }
        }
        
        let cleanTitle = Self.normalizedCleanTitle(title)
        if !cleanTitle.isEmpty {
            harvestASCIIAndCJK(from: cleanTitle, addBigrams: true)
        }
        
        // Extract structural cues from Markdown headings, [[wiki links]], quotes, bold & code spans
        let sampledString = String(sampledBody)
        if let structRegex = Self.structTermRegex {
            let ns = sampledString as NSString
            for m in structRegex.matches(in: sampledString, range: NSRange(location: 0, length: ns.length)) {
                for g in 1..<m.numberOfRanges {
                    let r = m.range(at: g)
                    if r.location != NSNotFound && r.length > 0 {
                        let captured = ns.substring(with: r).trimmingCharacters(in: .whitespacesAndNewlines)
                        harvestASCIIAndCJK(from: captured, addBigrams: true)
                    }
                }
            }
        }
        
        harvestASCIIAndCJK(from: String(sampledString.prefix(3_000)), addBigrams: true)
        
        Self.termCache.lock.lock()
        Self.termCache.termsByKey[key] = terms
        Self.termCache.keyOrder.removeAll { $0 == key }
        Self.termCache.keyOrder.append(key)
        while Self.termCache.keyOrder.count > Self.maxCachedTermEntries {
            let evicted = Self.termCache.keyOrder.removeFirst()
            Self.termCache.termsByKey.removeValue(forKey: evicted)
        }
        Self.termCache.lock.unlock()
        return terms
    }
    
    
    static func buildRelations(
        for docs: [CorpusDocument],
        maxEdgesPerNode: Int = 3
    ) -> [StarMapRelationEdge] {
        guard docs.count >= 2 else { return [] }
        let cappedDocs = Array(docs.prefix(Self.corpusLimit))
        
        var lowerTermsByDoc: [String: [String: String]] = [:] // lowercased -> display casing
        var docFreq: [String: Int] = [:]
        var cleanTitles: [String] = []
        var cleanTitleLowers: [String] = []
        var bodyLowers: [String] = []
        cleanTitles.reserveCapacity(cappedDocs.count)
        cleanTitleLowers.reserveCapacity(cappedDocs.count)
        bodyLowers.reserveCapacity(cappedDocs.count)
        
        for doc in cappedDocs {
            let extracted = Self.extractKeyTerms(title: doc.title, content: doc.content)
            var lowerMap: [String: String] = [:]
            for t in extracted {
                let lower = t.lowercased()
                if lowerMap[lower] == nil {
                    lowerMap[lower] = t
                }
            }
            lowerTermsByDoc[doc.id] = lowerMap
            for lower in lowerMap.keys {
                docFreq[lower, default: 0] += 1
            }
            let cTitle = Self.normalizedCleanTitle(doc.title)
            cleanTitles.append(cTitle)
            cleanTitleLowers.append(cTitle.lowercased())
            bodyLowers.append(doc.content.prefix(2_400).lowercased())
        }
        
        let maxAllowedDF = max(2, Int(ceil(Double(cappedDocs.count) * 0.6)))
        let discriminativeTerms = docFreq.compactMap { (2...maxAllowedDF).contains($0.value) ? $0.key : nil }
        let discriminativeByIndex: [Set<String>] = cappedDocs.map { doc in
            let map = lowerTermsByDoc[doc.id] ?? [:]
            return Set(map.keys).intersection(discriminativeTerms)
        }
        
        var candidates: [StarMapRelationEdge] = []
        let minimumSharedTerms = cappedDocs.count > 8 ? 2 : 1
        
        for i in 0..<(cappedDocs.count - 1) {
            let a = cappedDocs[i]
            let aTitleClean = cleanTitles[i]
            let aTitleLower = cleanTitleLowers[i]
            let aLowerMap = lowerTermsByDoc[a.id] ?? [:]
            let aDiscriminative = discriminativeByIndex[i]
            let aBodyLower = bodyLowers[i]
            
            for j in (i + 1)..<cappedDocs.count {
                let b = cappedDocs[j]
                let bTitleClean = cleanTitles[j]
                let bTitleLower = cleanTitleLowers[j]
                let bBodyLower = bodyLowers[j]
                
                var bestStrength = 0.0
                var bestReason = ""
                
                // 1. Explicit title cross-mention
                if bTitleClean.count >= 3 && aBodyLower.contains(bTitleLower) {
                    bestStrength = 0.86
                    bestReason = "提及「\(String(bTitleClean.prefix(12)))」"
                } else if aTitleClean.count >= 3 && bBodyLower.contains(aTitleLower) {
                    bestStrength = 0.86
                    bestReason = "提及「\(String(aTitleClean.prefix(12)))」"
                }
                
                // 2. Shared discriminative keywords / concepts
                let bLowerMap = lowerTermsByDoc[b.id] ?? [:]
                let bDiscriminative = discriminativeByIndex[j]
                let sharedLowers = aDiscriminative.intersection(bDiscriminative)
                
                if sharedLowers.count >= minimumSharedTerms {
                    let topicStrength = min(0.92, 0.34 + Double(sharedLowers.count) * 0.14)
                    if topicStrength > bestStrength {
                        let rankedShared = sharedLowers.sorted { lhs, rhs in
                            let dfL = docFreq[lhs] ?? 99
                            let dfR = docFreq[rhs] ?? 99
                            if dfL != dfR { return dfL < dfR }
                            return lhs.count > rhs.count
                        }
                        let labels = rankedShared.prefix(2).compactMap { key in
                            aLowerMap[key] ?? bLowerMap[key]
                        }
                        bestStrength = topicStrength
                        bestReason = "共现：" + labels.joined(separator: " · ")
                    }
                }
                
                // 3. Same local folder path
                if let folderA = a.folderPath, let folderB = b.folderPath,
                   !folderA.isEmpty, folderA == folderB
                {
                    let folderName = URL(filePath: folderA).lastPathComponent
                    if bestStrength < 0.48 {
                        bestStrength = max(bestStrength + 0.20, 0.48)
                        if bestReason.isEmpty {
                            bestReason = folderName.isEmpty ? "同目录" : "同目录 · \(folderName)"
                        }
                    } else {
                        bestStrength = min(0.95, bestStrength + 0.08)
                    }
                }
                
                if bestStrength >= 0.42, !bestReason.isEmpty {
                    candidates.append(StarMapRelationEdge(
                        sourceID: a.id,
                        targetID: b.id,
                        strength: bestStrength,
                        reason: bestReason
                    ))
                }
            }
        }
        
        let sorted = candidates.sorted { lhs, rhs in
            if lhs.strength != rhs.strength { return lhs.strength > rhs.strength }
            return lhs.id < rhs.id
        }
        
        var degreeByNode: [String: Int] = [:]
        var accepted: [StarMapRelationEdge] = []
        var seenPairs = Set<String>()
        
        for edge in sorted {
            guard seenPairs.insert(edge.id).inserted else { continue }
            let degA = degreeByNode[edge.sourceID, default: 0]
            let degB = degreeByNode[edge.targetID, default: 0]
            guard degA < maxEdgesPerNode && degB < maxEdgesPerNode else { continue }
            accepted.append(edge)
            degreeByNode[edge.sourceID] = degA + 1
            degreeByNode[edge.targetID] = degB + 1
            if accepted.count >= 48 { break }
        }
        
        return accepted
    }
    
    
    private static func normalizedCleanTitle(_ title: String) -> String {
        var clean = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if let dotIdx = clean.lastIndex(of: "."), clean.distance(from: dotIdx, to: clean.endIndex) <= 6 {
            clean = String(clean[..<dotIdx])
        }
        guard !DocumentCenterAgentOrganizer.isGenericUntitled(clean, hasFilePath: false) else { return "" }
        return clean
    }
}


// MARK: - Agent Auto-Organize Engine (文档中心一键整理)

nonisolated enum DocumentCenterAgentOrganizer {
    
    struct InputItem: Sendable {
        let id: String
        let title: String
        let syntax: String
        let currentGroup: String
        let excerpt: String
        let isUntitled: Bool
    }
    
    struct Assignment: Codable, Sendable, Equatable {
        let id: String
        let group: String
        let suggestedTitle: String?
    }
    
    struct SemanticDeleteProposal: Codable, Sendable, Equatable {
        let id: String
        let reason: String?
    }
    
    struct SemanticMergeProposal: Codable, Sendable, Equatable {
        let primaryId: String
        let mergeIds: [String]
        let mergedTitle: String?
        let group: String?
        let reason: String?
    }
    
    struct Plan: Codable, Sendable, Equatable {
        let assignments: [Assignment]
        let merges: [SemanticMergeProposal]
        let deletes: [SemanticDeleteProposal]
        
        enum CodingKeys: String, CodingKey {
            case assignments
            case merges
            case deletes
        }
        
        init(
            assignments: [Assignment],
            merges: [SemanticMergeProposal] = [],
            deletes: [SemanticDeleteProposal] = []
        ) {
            self.assignments = assignments
            self.merges = merges
            self.deletes = deletes
        }
        
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.assignments = try container.decodeIfPresent([Assignment].self, forKey: .assignments) ?? []
            self.merges = try container.decodeIfPresent([SemanticMergeProposal].self, forKey: .merges) ?? []
            self.deletes = try container.decodeIfPresent([SemanticDeleteProposal].self, forKey: .deletes) ?? []
        }
    }
    
    
    static let bloatedGroupThreshold = 8
    
    static func isMonolithicGroup(count: Int, totalItems: Int) -> Bool {
        if count >= Self.bloatedGroupThreshold {
            return true
        }
        return totalItems >= 4 && Double(count) / Double(max(1, totalItems)) >= 0.70
    }
    
    static let catchAllGroupNames: Set<String> = [
        "未分组", "日常记录", "日常随记", "杂记", "随笔", "默认", "其他", "临时", "综合",
    ]
    
    static let coreTopicPalette: [String] = [
        "评测与数据", "工程与开发", "方案与会议", "周报与待办", "日常随记",
    ]
    
    /// Checks whether a document title is generic / placeholder (including `GeneratedDocumentName`
    /// whimsical names like `"啃瓜的小浣熊"`) and safe for Agent title cleanup.
    static func isGenericUntitled(_ title: String, hasFilePath: Bool) -> Bool {
        if hasFilePath { return false }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let clean = trimmed.lowercased()
        if clean.isEmpty || clean.count == 1 { return true }
        if GeneratedDocumentName.isGeneratedName(trimmed) {
            return true
        }
        let prefixes = [
            "untitled", "未命名", "新建文档", "无标题", "note ", "draft ",
            "草稿", "临时", "新建", "随便写", "备忘", "test", "tmp", "temp",
        ]
        if prefixes.contains(where: { clean == $0.trimmingCharacters(in: .whitespaces) || clean.hasPrefix($0) }) {
            return true
        }
        // Pure digits / timestamps like "111", "222", "20261124", "11-24"
        let strippedPunct = clean.replacingOccurrences(of: #"[\d\-_/\.\s:]+"#, with: "", options: .regularExpression)
        if strippedPunct.isEmpty {
            return true
        }
        return false
    }
    
    
    /// Returns true when a scratch document's title is untitled/whimsical OR a vague generic label
    /// (such as `"笔记1"`, `"方案"`, `"想法"`, `"文档2"`) that AI can safely upgrade to reflect its actual content.
    static func isWeakScratchTitle(_ title: String, hasFilePath: Bool) -> Bool {
        if hasFilePath { return false }
        if Self.isGenericUntitled(title, hasFilePath: false) { return true }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        var stem = trimmed
        let trailingChars = CharacterSet.decimalDigits
            .union(.whitespaces)
            .union(CharacterSet(charactersIn: "_-·#()（）vV"))
        while let last = stem.unicodeScalars.last, trailingChars.contains(last) {
            stem.unicodeScalars.removeLast()
        }
        let vagueLabels: Set<String> = [
            "笔记", "文档", "记录", "方案", "想法", "随手记", "随笔", "杂记", "问题", "总结",
            "整理", "资料", "清单", "待办", "新的", "内容", "测试文档", "草稿箱",
            "note", "notes", "doc", "docs", "memo", "scratch", "idea", "ideas", "todo", "plan", "draft",
        ]
        if vagueLabels.contains(stem.lowercased()) {
            return true
        }
        if trimmed.count <= 2, trimmed.unicodeScalars.allSatisfy(\.isASCII) {
            return true
        }
        return false
    }
    
    
    /// Parses the Agent JSON response (tolerating markdown code fences and surrounding prose).
    static func parsePlan(from rawResponse: String, validIDs: Set<String>) -> Plan? {
        var cleaned = rawResponse.trimmingCharacters(in: .whitespacesAndNewlines)
        if let start = cleaned.firstIndex(of: "{"), let end = cleaned.lastIndex(of: "}") {
            cleaned = String(cleaned[start...end])
        }
        guard let data = cleaned.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(Plan.self, from: data)
        else { return nil }
        
        var seen = Set<String>()
        var sanitized: [Assignment] = []
        for item in decoded.assignments {
            guard validIDs.contains(item.id), seen.insert(item.id).inserted else { continue }
            let rawGroup = item.group.trimmingCharacters(in: .whitespacesAndNewlines)
            let group = (rawGroup == "未分组" || rawGroup.isEmpty) ? "" : String(rawGroup.prefix(14))
            let title = Self.sanitizeSuggestedTitle(item.suggestedTitle)
            sanitized.append(Assignment(id: item.id, group: group, suggestedTitle: title))
        }
        
        var sanitizedMerges: [SemanticMergeProposal] = []
        for proposal in decoded.merges {
            guard validIDs.contains(proposal.primaryId) else { continue }
            var uniqueMergeIDs: [String] = []
            var mergeSeen = Set<String>([proposal.primaryId])
            for mid in proposal.mergeIds where validIDs.contains(mid) && mergeSeen.insert(mid).inserted {
                uniqueMergeIDs.append(mid)
            }
            guard !uniqueMergeIDs.isEmpty else { continue }
            let cleanGroup: String? = proposal.group.flatMap { raw in
                let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                return (trimmed.isEmpty || trimmed == "未分组") ? nil : String(trimmed.prefix(14))
            }
            sanitizedMerges.append(SemanticMergeProposal(
                primaryId: proposal.primaryId,
                mergeIds: uniqueMergeIDs,
                mergedTitle: Self.sanitizeSuggestedTitle(proposal.mergedTitle),
                group: cleanGroup,
                reason: proposal.reason?.trimmingCharacters(in: .whitespacesAndNewlines)
            ))
        }
        
        var seenDeletes = Set<String>()
        var sanitizedDeletes: [SemanticDeleteProposal] = []
        for item in decoded.deletes {
            guard validIDs.contains(item.id), seenDeletes.insert(item.id).inserted else { continue }
            let reason = item.reason?.trimmingCharacters(in: .whitespacesAndNewlines)
            sanitizedDeletes.append(SemanticDeleteProposal(
                id: item.id,
                reason: (reason?.isEmpty == false) ? String(reason!.prefix(24)) : nil
            ))
        }
        
        return (sanitized.isEmpty && sanitizedMerges.isEmpty && sanitizedDeletes.isEmpty)
            ? nil
            : Plan(assignments: sanitized, merges: sanitizedMerges, deletes: sanitizedDeletes)
    }
    
    
    static func sanitizeSuggestedTitle(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "`", with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: " \t\n\r\"'“”《》【】#*-•>"))
        guard trimmed.count >= 2,
              !Self.isGenericUntitled(trimmed, hasFilePath: false)
        else { return nil }
        return String(trimmed.prefix(36))
    }
    
    
    /// Fast deterministic local classifier used when AI is unconfigured, offline, or returns partial JSON.
    /// Automatically splits bloated (`>= 8` docs) or catch-all groups by content semantics instead of freezing them.
    static func buildLocalFallbackPlan(
        items: [InputItem],
        existingGroups: [String],
        allowPreserveExisting: Bool = true
    ) -> Plan {
        var groupCounts: [String: Int] = [:]
        for item in items where !item.currentGroup.isEmpty {
            groupCounts[item.currentGroup, default: 0] += 1
        }
        let existingSet = Set(existingGroups)
        
        var assignments: [Assignment] = []
        assignments.reserveCapacity(items.count)
        
        for item in items {
            let resolvedGroup = Self.classifyTopicGroup(
                for: item,
                existingSet: existingSet,
                groupCounts: groupCounts,
                totalItems: items.count,
                allowPreserveExisting: allowPreserveExisting
            )
            let suggestedTitle: String? = item.isUntitled ? Self.deriveTitleFromExcerpt(item.excerpt) : nil
            assignments.append(Assignment(id: item.id, group: resolvedGroup, suggestedTitle: suggestedTitle))
        }
        return Plan(assignments: assignments)
    }
    
    
    private static func classifyTopicGroup(
        for item: InputItem,
        existingSet: Set<String>,
        groupCounts: [String: Int],
        totalItems: Int,
        allowPreserveExisting: Bool
    ) -> String {
        if allowPreserveExisting,
           !item.currentGroup.isEmpty,
           existingSet.contains(item.currentGroup),
           !Self.catchAllGroupNames.contains(item.currentGroup),
           !Self.isMonolithicGroup(count: groupCounts[item.currentGroup, default: 0], totalItems: totalItems)
        {
            return item.currentGroup
        }
        
        let codeSyntaxes: Set<String> = [
            "swift", "python", "javascript", "typescript", "json", "yaml", "toml",
            "html", "css", "sql", "shell script", "bash", "c", "c++", "rust", "go", "java", "ruby",
        ]
        let titleLower = item.title.lowercased()
        let syntaxLower = item.syntax.lowercased()
        let effectiveTitle = item.isUntitled ? "" : item.title
        
        // 1. Prioritize direct title affinity against existing healthy user groups (e.g. "cot优化roadmap" -> "cot优化").
        if !effectiveTitle.isEmpty {
            let sig = OrganizeTopicSignature.extract(title: effectiveTitle, content: item.excerpt, isUntitled: false)
            if !sig.titleProjectStems.isEmpty {
                let bestExisting = existingSet
                    .filter { !Self.catchAllGroupNames.contains($0) && !Self.isMonolithicGroup(count: groupCounts[$0, default: 0], totalItems: totalItems) }
                    .max { lhs, rhs in
                        OrganizeTopicSignature.titleAffinityScore(for: sig, groupName: lhs)
                            < OrganizeTopicSignature.titleAffinityScore(for: sig, groupName: rhs)
                    }
                if let bestExisting,
                   OrganizeTopicSignature.titleAffinityScore(for: sig, groupName: bestExisting) >= 12
                {
                    return bestExisting
                }
            }
        }
        
        // 2. Check explicit title signals before falling back to body excerpts so body examples never hijack the group.
        func matchCategory(in text: String) -> String? {
            if text.contains("会议") || text.contains("纪要") || text.contains("例会") || text.contains("周会") || text.contains("meeting") || text.contains("sync") {
                return "会议纪要"
            }
            if text.contains("方案") || text.contains("需求") || text.contains("prd") || text.contains("设计") || text.contains("规划") || text.contains("架构") || text.contains("roadmap") || text.contains("路线图") {
                return "项目方案"
            }
            if text.contains("评测") || text.contains("重评") || text.contains("归因") || text.contains("badcase") || text.contains("goldencase") || text.contains("评级") || text.contains("压测") || text.contains("基准") || text.contains("看板") || text.contains("eval") || text.contains("benchmark") {
                return "评测分析"
            }
            if text.contains("数据梳理") || text.contains("聚类") || text.contains("统计") || text.contains("指标") || text.contains("大盘") || text.contains("口径") || text.contains("报表") || text.contains("trace") || text.contains("dataset") {
                return "数据分析"
            }
            if text.contains("周报") || text.contains("日报") || text.contains("复盘") || text.contains("总结") || text.contains("todo") || text.contains("清单") || text.contains("排期") || text.contains("待办") {
                return "工作清单"
            }
            return nil
        }
        
        if !effectiveTitle.isEmpty, let titleMatch = matchCategory(in: effectiveTitle.lowercased()) {
            return titleMatch
        }
        
        let sampleLower = (effectiveTitle + "\n" + item.excerpt).lowercased()
        if let bodyMatch = matchCategory(in: sampleLower) {
            return bodyMatch
        }
        if syntaxLower == "json" || syntaxLower == "yaml" || syntaxLower == "toml" || syntaxLower == "xml" || syntaxLower == "csv" || titleLower.hasSuffix(".env") {
            return "配置数据"
        }
        if codeSyntaxes.contains(syntaxLower) || sampleLower.contains("func ") || sampleLower.contains("import ") || sampleLower.contains("class ") || sampleLower.contains("def ") || sampleLower.contains("部署") || sampleLower.contains("worker") || sampleLower.contains("脚本") || sampleLower.contains("docker") {
            return "代码开发"
        }
        if sampleLower.contains("api") || sampleLower.contains("bug") || sampleLower.contains("debug") || sampleLower.contains("排查") || sampleLower.contains("文档") || sampleLower.contains("教程") || sampleLower.contains("笔记") || sampleLower.contains("优化") {
            return "技术笔记"
        }
        return "日常记录"
    }
    
    
    /// Derives a crisp, human-readable title from document content, stripping Markdown chrome,
    /// code fences, URLs, and table divider lines.
    static func deriveTitleFromExcerpt(_ excerpt: String) -> String? {
        for rawLine in excerpt.components(separatedBy: .newlines) {
            var line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }
            if line.hasPrefix("```") || line.hasPrefix("~~~") { continue }
            
            // Skip horizontal rules & markdown table separator rows (e.g. "|---|---|")
            let ruleSet = CharacterSet(charactersIn: "-*_=|: ")
            if line.count >= 3, line.unicodeScalars.allSatisfy({ ruleSet.contains($0) }) {
                continue
            }
            
            // Turn a markdown table header row into a concise readable title
            if line.hasPrefix("|") && line.contains("|") {
                let cells = line
                    .split(separator: "|", omittingEmptySubsequences: true)
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                if cells.count >= 2 {
                    let preview = cells.prefix(3).joined(separator: "·")
                    let tableTitle = String("\(preview) 数据表".prefix(22))
                    if !Self.isGenericUntitled(tableTitle, hasFilePath: false) {
                        return tableTitle
                    }
                }
                continue
            }
            
            // Skip bare URL lines
            let lower = line.lowercased()
            if lower.hasPrefix("http://") || lower.hasPrefix("https://") { continue }
            
            // Strip leading markdown heading / quote / bullet / numbered list prefixes
            while let first = line.first, first == "#" || first == ">" {
                line.removeFirst()
                line = line.trimmingCharacters(in: .whitespaces)
            }
            for prefix in ["- [ ] ", "- [x] ", "- [X] ", "- ", "* ", "+ ", "• "] {
                if line.hasPrefix(prefix) {
                    line.removeFirst(prefix.count)
                    line = line.trimmingCharacters(in: .whitespaces)
                    break
                }
            }
            if let dotIdx = line.firstIndex(where: { !$0.isNumber }),
               dotIdx > line.startIndex,
               line[dotIdx] == "." || line[dotIdx] == ")" || line[dotIdx] == "、"
            {
                let after = line.index(after: dotIdx)
                if after < line.endIndex {
                    line = String(line[after...]).trimmingCharacters(in: .whitespaces)
                }
            }
            
            // Strip inline markdown wrappers and filesystem-unsafe separators
            line = line
                .replacingOccurrences(of: "**", with: "")
                .replacingOccurrences(of: "__", with: "")
                .replacingOccurrences(of: "`", with: "")
                .replacingOccurrences(of: "~~", with: "")
                .replacingOccurrences(of: "/", with: "-")
                .replacingOccurrences(of: ":", with: " ")
                .replacingOccurrences(of: "：", with: " ")
                .components(separatedBy: .whitespacesAndNewlines)
                .filter { !$0.isEmpty }
                .joined(separator: " ")
                .trimmingCharacters(in: CharacterSet(charactersIn: " \t\"'“”()（）[]【】—–-，,。.;；、"))
            
            guard line.count >= 2 else { continue }
            
            // Prefer cutting at a natural clause boundary when the first line is a full paragraph
            var candidate = line
            if candidate.count > 22 {
                let stopChars: Set<Character> = ["。", "；", ";", "，", ",", "？", "?", "！", "!"]
                if let breakIdx = candidate.firstIndex(where: { stopChars.contains($0) }),
                   candidate.distance(from: candidate.startIndex, to: breakIdx) >= 6,
                   candidate.distance(from: candidate.startIndex, to: breakIdx) <= 22
                {
                    candidate = String(candidate[..<breakIdx])
                } else {
                    candidate = String(candidate.prefix(20))
                }
                candidate = candidate.trimmingCharacters(in: CharacterSet(charactersIn: " \t—–-，,。.;；、"))
            }
            
            guard candidate.count >= 2, !Self.isGenericUntitled(candidate, hasFilePath: false) else { continue }
            return candidate
        }
        return nil
    }
    
    
    @MainActor
    static func generatePlan(
        items: [InputItem],
        existingGroups: [String],
        analyticsFeature: String = "documentCenterAgentOrganize"
    ) async -> (plan: Plan, usedAI: Bool) {
        guard !items.isEmpty else {
            return (Plan(assignments: []), false)
        }
        
        let funnelInputs = items.map { item in
            OrganizeFunnelInput(
                id: item.id,
                dbRecordID: item.id,
                title: item.title,
                filePath: item.isUntitled ? nil : item.id,
                syntax: item.syntax,
                currentGroup: item.currentGroup,
                content: item.excerpt,
                updatedAt: Date(),
                isOpenNow: false,
                isUntitled: item.isUntitled
            )
        }
        
        let fullPlan = await DocumentOrganizeFunnel.runFullPipeline(
            items: funnelInputs,
            existingGroups: existingGroups,
            allowRemoteAI: true,
            analyticsFeature: analyticsFeature
        )
        
        let assignedByID = Dictionary(uniqueKeysWithValues: fullPlan.assignments.map { ($0.id, $0) })
        let fallbackMap = Dictionary(
            uniqueKeysWithValues: Self.buildLocalFallbackPlan(items: items, existingGroups: existingGroups).assignments.map { ($0.id, $0) }
        )
        let completeAssignments = items.compactMap { assignedByID[$0.id] ?? fallbackMap[$0.id] }
        return (Plan(assignments: completeAssignments), fullPlan.usedAI)
    }
}


// MARK: - Document Center State

@MainActor @Observable final class DocumentCenterState {
    
    enum SidebarFilter: Hashable {
        case all
        case openNow
        case group(String)
        case ungrouped
        case trash
    }
    
    enum TimeHorizon: String, CaseIterable, Equatable {
        case all = "全部时间"
        case today = "今天"
        case last7Days = "近7天"
        case last30Days = "近30天"
        case older = "更早"
        
        func matches(_ date: Date, now: Date = Date()) -> Bool {
            let cal = Calendar.current
            switch self {
                case .all:
                    return true
                case .today:
                    return cal.isDate(date, inSameDayAs: now)
                case .last7Days:
                    let cutoff = cal.date(byAdding: .day, value: -7, to: now) ?? now.addingTimeInterval(-7 * 86_400)
                    return date >= cutoff
                case .last30Days:
                    let cutoff = cal.date(byAdding: .day, value: -30, to: now) ?? now.addingTimeInterval(-30 * 86_400)
                    return date >= cutoff
                case .older:
                    let cutoff = cal.date(byAdding: .day, value: -30, to: now) ?? now.addingTimeInterval(-30 * 86_400)
                    return date < cutoff
            }
        }
    }
    
    struct OrganizeUndoEntry {
        enum Kind {
            case modified
            case deleted
            case mergedPrimary
        }
        
        let kind: Kind
        let itemID: String
        let dbRecordID: String
        let filePath: String?
        let previousGroup: String
        let previousTitle: String
        let titleWasChanged: Bool
        let syntax: String
        let content: String
    }
    
    struct ManagedDocumentItem: Identifiable, Equatable {
        let id: String
        let dbRecordID: String?
        let title: String
        let filePath: String?
        let fileExists: Bool
        let syntax: String
        let content: String
        let updatedAt: Date
        let isOpenNow: Bool
        let isDirty: Bool
        let characterCount: Int
        let compactCharCount: String
        let relativeTimeText: String
        let groupName: String
        let storedRecord: StoredDocumentRecord?
        var isTrashed: Bool = false
        
        var previewText: String {
            DocumentCenterState.buildPreviewText(from: self.content)
        }

        fileprivate var searchDocument: StarMapSearchEngine.SearchDocument {
            StarMapSearchEngine.SearchDocument(title: self.title, category: self.groupName,
                                               metadata: self.filePath ?? "", content: self.content)
        }
        
        static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.id == rhs.id
                && lhs.title == rhs.title
                && lhs.isOpenNow == rhs.isOpenNow
                && lhs.isDirty == rhs.isDirty
                && lhs.characterCount == rhs.characterCount
                && lhs.groupName == rhs.groupName
                && lhs.updatedAt == rhs.updatedAt
                && lhs.isTrashed == rhs.isTrashed
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
    var collapsedClusterIDs: Set<String> = []
    var defaultCollapseAll: Bool = true
    var timeHorizon: TimeHorizon = .all {
        didSet {
            if oldValue != self.timeHorizon {
                self.recomputeDisplayedItems()
            }
        }
    }
    var relations: [StarMapRelationEdge] = []
    var searchHits: [StarMapSearchHit] = []
    var searchMatchesByID: [String: StarMapSearchEngine.MatchEvaluation] = [:]
    var openCount: Int = 0
    var ungroupedCount: Int = 0
    var groupCounts: [String: Int] = [:]
    var selectedID: String?
    
    var sidebarFilter: SidebarFilter = .all {
        didSet {
            if oldValue != self.sidebarFilter {
                let isTrash = (self.sidebarFilter == .trash)
                if self.showingTrash != isTrash {
                    self.showingTrash = isTrash
                }
                self.recomputeDisplayedItems()
            }
        }
    }
    
    var showingTrash = false {
        didSet {
            if oldValue != self.showingTrash {
                if self.showingTrash && self.sidebarFilter != .trash {
                    self.sidebarFilter = .trash
                } else if !self.showingTrash && self.sidebarFilter == .trash {
                    self.sidebarFilter = .all
                }
                self.selectedID = nil
                self.recomputeDisplayedItems()
            }
        }
    }
    
    private var appliedSearchText = ""
    var searchText: String {
        get { self.appliedSearchText }
        set {
            if newValue != self.appliedSearchText {
                self.appliedSearchText = newValue
                self.recomputeDisplayedItems()
            }
        }
    }
    
    // Agent Auto-Organize state
    struct OrganizeLogEntry: Identifiable, Sendable, Equatable {
        enum Kind: Sendable, Equatable {
            case deleted
            case merged
            case renamed
            case groupSummary
        }
        let id = UUID()
        let kind: Kind
        let title: String
        let detail: String?
    }
    
    var isAgentOrganizing: Bool = false
    var agentOrganizeProgressText: String = "一键整理中"
    var agentOrganizeSummary: String?
    var lastOrganizeMergeLogs: [String] = []
    var lastOrganizeLogEntries: [OrganizeLogEntry] = []
    var lastOrganizeUndoSnapshot: [OrganizeUndoEntry] = []
    var lastOrganizeCreatedGroups: [String] = []
    var lastOrganizeRemovedGroups: [String] = []
    
    private var liveDocsByID: [String: Document] = [:]
    @ObservationIgnored private var cachedRelationsCorpus: [StarMapRelationEngine.CorpusDocument] = []
    @ObservationIgnored private var initializedClusterIDs: Set<String> = []
    @ObservationIgnored private var displayRevision = 0
    
    private static let shortDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "M/d"
        return f
    }()
    
    private static let timelineHourMinuteFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()
    
    private static let timelineMonthDayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "M月d日"
        return f
    }()
    
    private static let timelineYearMonthDayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy/M/d"
        return f
    }()
    
    static func timelineMilestoneText(for date: Date, now: Date = Date()) -> String {
        let cal = Calendar.current
        if cal.isDate(date, inSameDayAs: now) {
            return "今天 \(Self.timelineHourMinuteFormatter.string(from: date))"
        }
        if let yesterday = cal.date(byAdding: .day, value: -1, to: now),
           cal.isDate(date, inSameDayAs: yesterday)
        {
            return "昨天 \(Self.timelineHourMinuteFormatter.string(from: date))"
        }
        if cal.component(.year, from: date) == cal.component(.year, from: now) {
            return Self.timelineMonthDayFormatter.string(from: date)
        }
        return Self.timelineYearMonthDayFormatter.string(from: date)
    }
    
    func registerClustersForDefaultCollapse(_ ids: [String]) {
        for cid in ids where self.initializedClusterIDs.insert(cid).inserted {
            if self.defaultCollapseAll {
                self.collapsedClusterIDs.insert(cid)
            }
        }
    }
    
    func setClusterExpanded(_ cid: String, expanded: Bool) {
        self.initializedClusterIDs.insert(cid)
        if expanded {
            self.collapsedClusterIDs.remove(cid)
        } else {
            self.collapsedClusterIDs.insert(cid)
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
    
    /// Sets a crisp post-organize expansion state: expands all clusters when every group fits
    /// cleanly into a single vertical column (`<= 24` docs total and `<= 8` per group), or
    /// presents a clean collapsed cluster overview when the corpus is larger.
    func applyCleanPostOrganizeClusterState() {
        var countsByCluster: [String: Int] = [:]
        for item in self.displayedItems {
            let cid = item.groupName.isEmpty ? "__ungrouped__" : "group:\(item.groupName)"
            countsByCluster[cid, default: 0] += 1
        }
        let clusterIDs = Array(countsByCluster.keys)
        guard !clusterIDs.isEmpty else { return }
        
        let maxClusterSize = countsByCluster.values.max() ?? 0
        if self.displayedItems.count <= 24 && maxClusterSize <= 8 {
            self.expandAllClusters(clusterIDs)
        } else {
            self.collapseAllClusters(clusterIDs)
        }
    }
    
    func liveDocument(for id: String) -> Document? {
        self.liveDocsByID[id]
    }
    
    
    func refresh() {
        
        let now = Date()
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
        var openTotal = 0
        var ungroupedTotal = 0
        var countsByGroup: [String: Int] = [:]
        
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
            openTotal += 1
            let dbMatch = dbByCanonicalKey[key]
            let modifiedDate = max(
                doc.lastManualSaveDate ?? .distantPast,
                doc.fileModificationDate ?? .distantPast,
                dbMatch?.updatedAt ?? now
            )
            let fallbackID = filePath ?? (doc.databaseDocumentID.hasPrefix("doc:") ? doc.databaseDocumentID : "doc:\(doc.databaseDocumentID)")
            let groupName = dbMatch?.groupName ?? ""
            if groupName.isEmpty {
                ungroupedTotal += 1
            } else {
                countsByGroup[groupName, default: 0] += 1
            }
            let charCount = content.count
            
            merged.append(ManagedDocumentItem(
                id: key,
                dbRecordID: dbMatch?.id ?? fallbackID,
                title: doc.displayName,
                filePath: filePath,
                fileExists: filePath != nil,
                syntax: doc.syntaxName,
                content: content,
                updatedAt: modifiedDate,
                isOpenNow: true,
                isDirty: dirty,
                characterCount: charCount,
                compactCharCount: Self.compactChars(charCount),
                relativeTimeText: Self.relativeTime(modifiedDate, now: now),
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
            
            if record.groupName.isEmpty {
                ungroupedTotal += 1
            } else {
                countsByGroup[record.groupName, default: 0] += 1
            }
            let charCount = record.content.count
            merged.append(ManagedDocumentItem(
                id: key,
                dbRecordID: record.id,
                title: record.title,
                filePath: record.filePath,
                fileExists: record.filePath != nil,
                syntax: record.syntax,
                content: record.content,
                updatedAt: record.updatedAt,
                isOpenNow: false,
                isDirty: false,
                characterCount: charCount,
                compactCharCount: Self.compactChars(charCount),
                relativeTimeText: Self.relativeTime(record.updatedAt, now: now),
                groupName: record.groupName,
                storedRecord: record
            ))
        }
        
        self.liveDocsByID = liveByKey
        self.items = merged
        self.openCount = openTotal
        self.ungroupedCount = ungroupedTotal
        self.groupCounts = countsByGroup
        self.trashedItems = CotLocalDatabase.shared.trashedDocuments.map { record in
            let charCount = record.content.count
            return ManagedDocumentItem(
                id: Self.canonicalKey(filePath: record.filePath, rawID: record.id),
                dbRecordID: record.id,
                title: record.title,
                filePath: record.filePath,
                fileExists: record.filePath != nil,
                syntax: record.syntax,
                content: record.content,
                updatedAt: record.updatedAt,
                isOpenNow: false,
                isDirty: false,
                characterCount: charCount,
                compactCharCount: Self.compactChars(charCount),
                relativeTimeText: Self.relativeTime(record.updatedAt, now: now),
                groupName: record.groupName,
                storedRecord: record,
                isTrashed: true
            )
        }
        
        let corpus = merged.prefix(StarMapRelationEngine.corpusLimit).map { item in
            StarMapRelationEngine.CorpusDocument(
                id: item.id,
                title: item.title,
                group: item.groupName,
                folderPath: item.filePath.map { URL(filePath: $0).deletingLastPathComponent().path(percentEncoded: false) },
                content: item.content,
                sortTimestamp: item.updatedAt.timeIntervalSince1970
            )
        }
        if corpus != self.cachedRelationsCorpus {
            self.relations = StarMapRelationEngine.buildRelations(for: corpus)
            self.cachedRelationsCorpus = corpus
        }
        self.recomputeDisplayedItems()
    }
    
    
    func relatedNodes(for itemID: String, in pool: [ManagedDocumentItem]) -> [(item: ManagedDocumentItem, reason: String)] {
        let lookup = Dictionary(uniqueKeysWithValues: pool.map { ($0.id, $0) })
        var results: [(item: ManagedDocumentItem, reason: String)] = []
        var seen = Set<String>()
        for edge in self.relations {
            let neighborID: String
            if edge.sourceID == itemID {
                neighborID = edge.targetID
            } else if edge.targetID == itemID {
                neighborID = edge.sourceID
            } else {
                continue
            }
            guard seen.insert(neighborID).inserted, let target = lookup[neighborID] else { continue }
            results.append((target, edge.reason))
        }
        return results
    }
    
    
    func buildStarMapClusters(tokens: StudioColorTokens) -> [StarMapClusterNode] {
        let paletteHexes = ["#2563EB", "#7C3AED", "#0D9488", "#D97706", "#059669", "#4F46E5", "#E11D48"]
        let isSearching = !StarMapSearchEngine.parseTerms(self.searchText).isEmpty
        let now = Date()
        
        if self.showingTrash || self.sidebarFilter == .trash {
            let leaves = self.displayedItems.prefix(40).map { item in
                let eval = self.searchMatchesByID[item.id]
                let badge = eval.map { "命中 \($0.totalHits) 处" }
                return StarMapLeafNode(
                    id: item.id,
                    clusterID: "trash",
                    title: item.title,
                    metaLine: "\(item.compactCharCount) · \(item.relativeTimeText)",
                    statusBadge: badge,
                    dotColor: Color.red.opacity(0.82),
                    weight: 0.65,
                    isHighlighted: eval != nil
                )
            }
            guard !leaves.isEmpty else { return [] }
            self.registerClustersForDefaultCollapse(["trash"])
            let latestTrashDate = self.displayedItems.map(\.updatedAt).max() ?? now
            return [
                StarMapClusterNode(
                    id: "trash",
                    title: "废纸篓",
                    countText: "\(self.displayedItems.count)",
                    accent: Color.red.opacity(0.82),
                    isCollapsed: !isSearching && self.collapsedClusterIDs.contains("trash"),
                    leaves: leaves,
                    timelineLabel: Self.timelineMilestoneText(for: latestTrashDate, now: now),
                    sortTimestamp: latestTrashDate.timeIntervalSince1970
                ),
            ]
        }
        
        var groupedBuckets: [String: [ManagedDocumentItem]] = [:]
        var ungrouped: [ManagedDocumentItem] = []
        for item in self.displayedItems {
            if item.groupName.isEmpty {
                ungrouped.append(item)
            } else {
                groupedBuckets[item.groupName, default: []].append(item)
            }
        }
        
        var orderedGroups: [String] = []
        for g in CotLocalDatabase.shared.documentGroups where groupedBuckets[g] != nil {
            orderedGroups.append(g)
        }
        for leftover in groupedBuckets.keys.sorted() where !orderedGroups.contains(leftover) {
            orderedGroups.append(leftover)
        }
        
        func makeLeaves(from items: [ManagedDocumentItem], clusterID: String, color: Color) -> [StarMapLeafNode] {
            let orderedItems = isSearching
                ? items
                : items.sorted { $0.updatedAt > $1.updatedAt }
            return orderedItems.prefix(40).map { item in
                let hitEval = self.searchMatchesByID[item.id]
                let badge: String? = if let hitEval {
                    "命中 \(hitEval.totalHits) 处"
                } else if item.isDirty {
                    "未保存"
                } else if item.isOpenNow {
                    "打开中"
                } else {
                    nil
                }
                return StarMapLeafNode(
                    id: item.id,
                    clusterID: clusterID,
                    title: item.title,
                    metaLine: "\(item.compactCharCount) · \(item.relativeTimeText)",
                    statusBadge: badge,
                    dotColor: color,
                    weight: hitEval != nil ? 1.0 : (item.isOpenNow ? 0.88 : 0.64),
                    isHighlighted: hitEval != nil || item.isOpenNow
                )
            }
        }
        
        struct CandidateCluster {
            let id: String
            let title: String
            let accent: Color
            let bucket: [ManagedDocumentItem]
            let latestDate: Date
        }
        
        var candidates: [CandidateCluster] = []
        for (idx, groupName) in orderedGroups.enumerated() {
            let bucket = groupedBuckets[groupName] ?? []
            guard !bucket.isEmpty else { continue }
            let cid = "group:\(groupName)"
            let accent = Color(hexString: paletteHexes[idx % paletteHexes.count])
            let latest = bucket.map(\.updatedAt).max() ?? .distantPast
            candidates.append(CandidateCluster(id: cid, title: groupName, accent: accent, bucket: bucket, latestDate: latest))
        }
        if !ungrouped.isEmpty {
            let cid = "__ungrouped__"
            let latest = ungrouped.map(\.updatedAt).max() ?? .distantPast
            candidates.append(CandidateCluster(id: cid, title: "未分组", accent: tokens.accent, bucket: ungrouped, latestDate: latest))
        }
        
        // Sort clusters newest-active first along the top-to-bottom Timeline Spine
        candidates.sort { lhs, rhs in
            if lhs.latestDate != rhs.latestDate {
                return lhs.latestDate > rhs.latestDate
            }
            return lhs.id < rhs.id
        }
        
        self.registerClustersForDefaultCollapse(candidates.map(\.id))
        
        return candidates.map { cand in
            StarMapClusterNode(
                id: cand.id,
                title: cand.title,
                countText: "\(cand.bucket.count)",
                accent: cand.accent,
                isCollapsed: !isSearching && self.collapsedClusterIDs.contains(cand.id),
                leaves: makeLeaves(from: cand.bucket, clusterID: cand.id, color: cand.accent),
                timelineLabel: Self.timelineMilestoneText(for: cand.latestDate, now: now),
                sortTimestamp: cand.latestDate.timeIntervalSince1970
            )
        }
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
            let revision = self.displayRevision
            let scope = (self.showingTrash || self.sidebarFilter == .trash) ? self.trashedItems : self.scopedDocuments()
            let evaluations = await StarMapSearchEngine.evaluateCorpus(scope.map(\.searchDocument), terms: terms)
            guard let evaluations, !Task.isCancelled, self.searchText == previousQuery else { return false }
            guard revision == self.displayRevision else { continue }
            self.appliedSearchText = query
            self.recomputeDisplayedItems(search: (scope, evaluations))
            return true
        }
        return false
    }


    private func recomputeDisplayedItems(
        search: (scope: [ManagedDocumentItem], evaluations: [StarMapSearchEngine.MatchEvaluation])? = nil
    ) {
        self.displayRevision &+= 1
        
        let terms = StarMapSearchEngine.parseTerms(self.searchText)
        
        if self.showingTrash || self.sidebarFilter == .trash {
            var evalByID: [String: StarMapSearchEngine.MatchEvaluation] = [:]
            var hits: [StarMapSearchHit] = []
            var matched: [ManagedDocumentItem] = []
            for (index, item) in (search?.scope ?? self.trashedItems).enumerated() {
                let eval = search?.evaluations[index] ?? item.searchDocument.evaluate(terms: terms)
                guard eval.isMatch else { continue }
                matched.append(item)
                if !terms.isEmpty {
                    evalByID[item.id] = eval
                    hits.append(StarMapSearchHit(
                        id: item.id,
                        title: item.title,
                        categoryLabel: "废纸篓",
                        metaLabel: "\(item.compactCharCount) · \(item.relativeTimeText)",
                        totalHits: eval.totalHits,
                        score: eval.score,
                        snippet: eval.snippet
                    ))
                }
            }
            let sorted = matched.sorted { lhs, rhs in
                let scoreL = evalByID[lhs.id]?.score ?? 0
                let scoreR = evalByID[rhs.id]?.score ?? 0
                if scoreL != scoreR { return scoreL > scoreR }
                return lhs.updatedAt > rhs.updatedAt
            }
            self.searchMatchesByID = evalByID
            self.searchHits = hits.sorted { $0.score > $1.score }
            self.displayedItems = sorted
            self.groupSections = []
            if let selectedID, sorted.contains(where: { $0.id == selectedID }) {
                return
            }
            self.selectedID = sorted.first?.id
            return
        }
        
        let baseScope = search?.scope ?? self.scopedDocuments()
        
        var evalByID: [String: StarMapSearchEngine.MatchEvaluation] = [:]
        var hits: [StarMapSearchHit] = []
        
        if !terms.isEmpty {
            for (index, item) in baseScope.enumerated() {
                let eval = search?.evaluations[index] ?? item.searchDocument.evaluate(terms: terms)
                guard eval.isMatch else { continue }
                evalByID[item.id] = eval
                hits.append(StarMapSearchHit(
                    id: item.id,
                    title: item.title,
                    categoryLabel: item.groupName.isEmpty ? "未分组" : item.groupName,
                    metaLabel: "\(item.compactCharCount) · \(item.relativeTimeText)",
                    totalHits: eval.totalHits,
                    score: eval.score,
                    snippet: eval.snippet
                ))
            }
        }
        
        let sortedHits = hits.sorted { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            return lhs.totalHits > rhs.totalHits
        }
        self.searchMatchesByID = evalByID
        self.searchHits = sortedHits
        
        // Keep matched items plus 1-hop related neighbors when searching so relationships stay legible
        let matchedIDs = Set(evalByID.keys)
        var visibleIDs = matchedIDs
        if !terms.isEmpty {
            for edge in self.relations {
                if matchedIDs.contains(edge.sourceID) {
                    visibleIDs.insert(edge.targetID)
                } else if matchedIDs.contains(edge.targetID) {
                    visibleIDs.insert(edge.sourceID)
                }
            }
        }
        
        let filtered = terms.isEmpty ? baseScope : baseScope.filter { visibleIDs.contains($0.id) }
        let visible = filtered.sorted { lhs, rhs in
            let hitL = evalByID[lhs.id]?.score ?? -1
            let hitR = evalByID[rhs.id]?.score ?? -1
            if hitL != hitR { return hitL > hitR }
            if lhs.isOpenNow != rhs.isOpenNow {
                return lhs.isOpenNow && !rhs.isOpenNow
            }
            return lhs.updatedAt > rhs.updatedAt
        }
        self.displayedItems = visible
        
        // Maintain groupSections compatibility
        var groupedBuckets: [String: [ManagedDocumentItem]] = [:]
        var ungrouped: [ManagedDocumentItem] = []
        for item in visible {
            if item.groupName.isEmpty {
                ungrouped.append(item)
            } else {
                groupedBuckets[item.groupName, default: []].append(item)
            }
        }
        var sections: [DocumentGroupSection] = []
        for groupName in CotLocalDatabase.shared.documentGroups {
            let bucket = groupedBuckets.removeValue(forKey: groupName) ?? []
            if terms.isEmpty || !bucket.isEmpty {
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
        self.registerClustersForDefaultCollapse(sections.map(\.id))
        
        if let topHitID = sortedHits.first?.id, terms.isEmpty == false {
            if let selectedID, evalByID[selectedID] != nil {
                return
            }
            self.selectedID = topHitID
            return
        }
        
        if let selectedID, visible.contains(where: { $0.id == selectedID }) {
            return
        }
        self.selectedID = visible.first?.id
    }
    
    
    private func scopedDocuments() -> [ManagedDocumentItem] {
        let scope: [ManagedDocumentItem] = switch self.sidebarFilter {
            case .all: self.items
            case .openNow: self.items.filter(\.isOpenNow)
            case .group(let name): self.items.filter { $0.groupName == name }
            case .ungrouped: self.items.filter { $0.groupName.isEmpty }
            case .trash: []
        }
        guard self.timeHorizon != .all else { return scope }
        let now = Date()
        return scope.filter { self.timeHorizon.matches($0.updatedAt, now: now) }
    }
    
    
    nonisolated static func buildPreviewText(from content: String) -> String {
        if content.isEmpty {
            return ""
        }
        if content.count > 120_000 {
            return String(content.prefix(120_000)) + "\n\n..."
        }
        return content
    }
    
    
    nonisolated static func cleanExcerpt(from content: String, maxLength: Int = 96) -> String {
        guard maxLength > 0, !content.isEmpty else { return "" }
        
        var collected: [String] = []
        for rawLine in content.components(separatedBy: .newlines) {
            var line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }
            if line.hasPrefix("```") || line.hasPrefix("~~~") { continue }
            
            let ruleChars = CharacterSet(charactersIn: "-*_=")
            if line.count >= 3 && line.unicodeScalars.allSatisfy({ ruleChars.contains($0) || $0 == " " }) {
                continue
            }
            
            while let first = line.first, first == "#" || first == ">" {
                line.removeFirst()
                line = line.trimmingCharacters(in: .whitespaces)
            }
            
            for prefix in ["- [ ] ", "- [x] ", "- [X] ", "- ", "* ", "+ "] {
                if line.hasPrefix(prefix) {
                    line.removeFirst(prefix.count)
                    line = line.trimmingCharacters(in: .whitespaces)
                    break
                }
            }
            
            if let dotIdx = line.firstIndex(where: { !$0.isNumber }),
               dotIdx > line.startIndex,
               line[dotIdx] == "." || line[dotIdx] == ")"
            {
                let after = line.index(after: dotIdx)
                if after < line.endIndex && line[after] == " " {
                    line = String(line[line.index(after: after)...]).trimmingCharacters(in: .whitespaces)
                }
            }
            
            let collapsed = line
                .components(separatedBy: .whitespacesAndNewlines)
                .filter { !$0.isEmpty }
                .joined(separator: " ")
            guard !collapsed.isEmpty else { continue }
            
            collected.append(collapsed)
            if collected.count >= 2 || collected.joined(separator: " ").count >= maxLength {
                break
            }
        }
        
        let joined = collected.joined(separator: " ")
        guard joined.count > maxLength else { return joined }
        let cutoff = joined.index(joined.startIndex, offsetBy: max(1, maxLength - 1))
        return String(joined[..<cutoff]).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
    }
    
    
    nonisolated static func compactChars(_ count: Int) -> String {
        if count >= 10_000 { return String(format: "%.1f万字", Double(count) / 10_000.0) }
        if count >= 1_000 { return String(format: "%.1fK字", Double(count) / 1_000.0) }
        return "\(count)字"
    }
    
    
    static func relativeTime(_ date: Date, now: Date = Date()) -> String {
        let interval = max(0, now.timeIntervalSince(date))
        if interval < 60 { return "刚刚" }
        if interval < 3600 { return "\(Int(interval / 60))分前" }
        if interval < 86_400 { return "\(Int(interval / 3600))时前" }
        let days = Int(interval / 86_400)
        if days < 30 { return "\(days)天前" }
        return Self.shortDateFormatter.string(from: date)
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

struct StarMapClusterNode: Identifiable, Equatable {
    let id: String
    let title: String
    let countText: String
    let accent: Color
    let isCollapsed: Bool
    let leaves: [StarMapLeafNode]
    let timelineLabel: String?
    let sortTimestamp: TimeInterval
    
    init(
        id: String,
        title: String,
        countText: String,
        accent: Color,
        isCollapsed: Bool,
        leaves: [StarMapLeafNode],
        timelineLabel: String? = nil,
        sortTimestamp: TimeInterval = 0
    ) {
        self.id = id
        self.title = title
        self.countText = countText
        self.accent = accent
        self.isCollapsed = isCollapsed
        self.leaves = leaves
        self.timelineLabel = timelineLabel
        self.sortTimestamp = sortTimestamp
    }
}


struct StarMapLeafNode: Identifiable, Equatable {
    let id: String
    let clusterID: String
    let title: String
    let metaLine: String
    let statusBadge: String?
    let dotColor: Color
    let weight: Double
    let isHighlighted: Bool
}


/// Lightweight AppKit trackpad pan & pinch/⌘-scroll zoom bridge that never blocks inner ScrollViews (QuickLook / Search HUD).
private final class StarMapTrackpadEventMonitorNSView: NSView {
    
    var onPan: ((CGFloat, CGFloat) -> Void)?
    var onZoom: ((CGFloat) -> Void)?
    var isBlockedByOverlay: Bool = false
    private var eventMonitor: Any?
    
    
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        self.teardownMonitor()
        guard self.window != nil else { return }
        self.eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel, .magnify]) { [weak self] event in
            guard let self,
                  !self.isBlockedByOverlay,
                  let window = self.window,
                  event.window === window,
                  !self.isHiddenOrHasHiddenAncestor
            else { return event }
            
            let localPt = self.convert(event.locationInWindow, from: nil)
            guard self.bounds.contains(localPt) else { return event }
            
            // Let inner scroll views (QuickLook text preview or Search Hits list) handle their own scrolling
            if let hitView = window.contentView?.hitTest(event.locationInWindow),
               hitView.enclosingScrollView != nil
            {
                return event
            }
            
            if event.type == .magnify {
                self.onZoom?(1.0 + event.magnification)
                return nil
            } else if event.type == .scrollWheel {
                if event.modifierFlags.contains(.command) {
                    let delta = event.scrollingDeltaY * (event.hasPreciseScrollingDeltas ? 0.004 : 0.02)
                    self.onZoom?(1.0 + delta)
                } else {
                    let mul: CGFloat = event.hasPreciseScrollingDeltas ? 1.0 : 12.0
                    self.onPan?(event.scrollingDeltaX * mul, event.scrollingDeltaY * mul)
                }
                return nil
            }
            return event
        }
    }
    
    
    private func teardownMonitor() {
        if let monitor = self.eventMonitor {
            NSEvent.removeMonitor(monitor)
            self.eventMonitor = nil
        }
    }
    
    
    deinit {
        if let monitor = self.eventMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }
}


private struct StarMapTrackpadPanZoomRepresentable: NSViewRepresentable {
    
    let onPan: (CGFloat, CGFloat) -> Void
    let onZoom: (CGFloat) -> Void
    let isBlockedByOverlay: Bool
    
    
    func makeNSView(context: Context) -> StarMapTrackpadEventMonitorNSView {
        let v = StarMapTrackpadEventMonitorNSView()
        v.onPan = self.onPan
        v.onZoom = self.onZoom
        v.isBlockedByOverlay = self.isBlockedByOverlay
        return v
    }
    
    
    func updateNSView(_ nsView: StarMapTrackpadEventMonitorNSView, context: Context) {
        nsView.onPan = self.onPan
        nsView.onZoom = self.onZoom
        nsView.isBlockedByOverlay = self.isBlockedByOverlay
    }
}


/// Pure deterministic lossless vector zoom metrics for Star-Map nodes & viewport projection.
/// Scaling layout geometry and typography natively instead of applying a layer `.scaleEffect`
/// ensures CoreText & CoreGraphics re-rasterize razor-sharp vectors at every zoom level (38%–240%).
nonisolated struct StarMapZoomMetrics: Equatable, Sendable {
    
    static let minZoom: CGFloat = 0.38
    static let maxZoom: CGFloat = 2.40
    
    let zoom: CGFloat
    
    init(zoom: CGFloat) {
        self.zoom = min(Self.maxZoom, max(Self.minZoom, zoom))
    }
    
    @inline(__always)
    func scaled(_ base: CGFloat) -> CGFloat {
        base * self.zoom
    }
    
    @inline(__always)
    func fontSize(_ base: CGFloat) -> CGFloat {
        self.zoom >= 0.6 ? max(11.0, base) : max(10.5, base)
    }
    
    @inline(__always)
    func strokeWidth(_ base: CGFloat) -> CGFloat {
        max(0.7, base * min(1.5, max(0.85, self.zoom)))
    }
    
    @inline(__always)
    static func screenPoint(
        world: CGPoint,
        viewportCenter: CGPoint,
        panOffset: CGSize,
        zoom: CGFloat
    ) -> CGPoint {
        CGPoint(
            x: viewportCenter.x + panOffset.width + world.x * zoom,
            y: viewportCenter.y + panOffset.height + world.y * zoom
        )
    }
    
    /// Scales `panOffset` proportionally with zoom ratio so the world point at viewport center stays anchored.
    static func zoomAnchoredPan(oldPan: CGSize, oldZoom: CGFloat, newZoom: CGFloat) -> CGSize {
        guard oldZoom > 0.001 else { return oldPan }
        let ratio = newZoom / oldZoom
        return CGSize(width: oldPan.width * ratio, height: oldPan.height * ratio)
    }
}


/// Reusable, lossless vector-zoom, zero-overlap Structured Tree Star-Map canvas shared by Document Center & Weekly Report Center.
struct ConstellationStarMapView<ClusterMenu: View, LeafMenu: View>: View {
    
    let hubTitle: String
    let hubSubtitle: String
    let clusters: [StarMapClusterNode]
    let relations: [StarMapRelationEdge]
    let selectedLeafID: String?
    let multiSelectedLeafIDs: Set<String>
    let focusedClusterID: String?
    let searchQuery: String
    let panRequestToken: Int
    let fitRequestToken: Int
    let isOverlayBlockingInteraction: Bool
    let layoutStyle: StarMapLayoutStyle
    let onSelectedLeafFrameChange: ((CGRect?) -> Void)?
    let onSelectLeaf: (String) -> Void
    let onCommandSelectLeaf: ((String) -> Void)?
    let onDoubleClickLeaf: (String) -> Void
    let onToggleCluster: (String) -> Void
    @ViewBuilder let clusterContextMenu: (StarMapClusterNode) -> ClusterMenu
    @ViewBuilder let leafContextMenu: (StarMapLeafNode) -> LeafMenu
    
    init(
        hubTitle: String,
        hubSubtitle: String,
        clusters: [StarMapClusterNode],
        relations: [StarMapRelationEdge] = [],
        selectedLeafID: String?,
        multiSelectedLeafIDs: Set<String> = [],
        focusedClusterID: String?,
        searchQuery: String,
        panRequestToken: Int = 0,
        fitRequestToken: Int = 0,
        isOverlayBlockingInteraction: Bool = false,
        layoutStyle: StarMapLayoutStyle = .timeline,
        onSelectedLeafFrameChange: ((CGRect?) -> Void)? = nil,
        onSelectLeaf: @escaping (String) -> Void,
        onCommandSelectLeaf: ((String) -> Void)? = nil,
        onDoubleClickLeaf: @escaping (String) -> Void,
        onToggleCluster: @escaping (String) -> Void,
        @ViewBuilder clusterContextMenu: @escaping (StarMapClusterNode) -> ClusterMenu,
        @ViewBuilder leafContextMenu: @escaping (StarMapLeafNode) -> LeafMenu
    ) {
        self.hubTitle = hubTitle
        self.hubSubtitle = hubSubtitle
        self.clusters = clusters
        self.relations = relations
        self.selectedLeafID = selectedLeafID
        self.multiSelectedLeafIDs = multiSelectedLeafIDs
        self.focusedClusterID = focusedClusterID
        self.searchQuery = searchQuery
        self.panRequestToken = panRequestToken
        self.fitRequestToken = fitRequestToken
        self.isOverlayBlockingInteraction = isOverlayBlockingInteraction
        self.layoutStyle = layoutStyle
        self.onSelectedLeafFrameChange = onSelectedLeafFrameChange
        self.onSelectLeaf = onSelectLeaf
        self.onCommandSelectLeaf = onCommandSelectLeaf
        self.onDoubleClickLeaf = onDoubleClickLeaf
        self.onToggleCluster = onToggleCluster
        self.clusterContextMenu = clusterContextMenu
        self.leafContextMenu = leafContextMenu
    }
    
    @Environment(\.colorScheme) private var colorScheme
    @State private var panOffset: CGSize = .zero
    @State private var dragStartPan: CGSize?
    @State private var zoomScale: CGFloat = 1.0
    @State private var pinchBaseZoom: CGFloat?
    @State private var pinchBasePan: CGSize?
    @State private var hasAutoFitted = false
    @State private var cachedClustersSnapshot: [StarMapClusterNode] = []
    @State private var cachedLayoutStyle: StarMapLayoutStyle = .timeline
    @State private var cachedLayout = StarMapLayoutEngine.LayoutResult(
        clusters: [],
        leaves: [],
        bounds: CGRect(x: -180, y: -140, width: 360, height: 280)
    )
    @State private var cachedClusterMap: [String: StarMapClusterNode] = [:]
    @State private var cachedLeafMap: [String: StarMapLeafNode] = [:]
    
    private static var cameraSpring: Animation {
        .spring(response: 0.38, dampingFraction: 0.9)
    }
    
    
    private static func computeLayout(
        for clusters: [StarMapClusterNode],
        layoutStyle: StarMapLayoutStyle
    ) -> StarMapLayoutEngine.LayoutResult {
        let clusterIDs = clusters.map(\.id)
        var counts: [String: Int] = [:]
        var collapsed = Set<String>()
        var leafIDsByCluster: [String: [String]] = [:]
        for cluster in clusters {
            if cluster.isCollapsed {
                collapsed.insert(cluster.id)
            } else {
                let leafIDs = cluster.leaves.prefix(40).map(\.id)
                counts[cluster.id] = leafIDs.count
                leafIDsByCluster[cluster.id] = leafIDs
            }
        }
        switch layoutStyle {
            case .orbital:
                return StarMapLayoutEngine.computeOrbital(
                    clusterIDs: clusterIDs,
                    collapsedClusterIDs: collapsed,
                    leafIDsByCluster: leafIDsByCluster
                )
            case .timeline:
                let usesTimeline = clusters.contains(where: { $0.timelineLabel != nil })
                return StarMapLayoutEngine.compute(
                    clusterIDs: clusterIDs,
                    leafCountsByCluster: counts,
                    collapsedClusterIDs: collapsed,
                    leafIDsByCluster: leafIDsByCluster,
                    usesTimelineSpine: usesTimeline
                )
        }
    }
    
    
    private static func buildNodeMaps(for clusters: [StarMapClusterNode]) -> (
        clusterMap: [String: StarMapClusterNode],
        leafMap: [String: StarMapLeafNode]
    ) {
        var cMap: [String: StarMapClusterNode] = [:]
        cMap.reserveCapacity(clusters.count)
        var lMap: [String: StarMapLeafNode] = [:]
        for c in clusters {
            cMap[c.id] = c
            for l in c.leaves.prefix(40) {
                lMap[l.id] = l
            }
        }
        return (cMap, lMap)
    }
    
    
    private static func hasSameLayoutInputs(
        _ previous: [StarMapClusterNode],
        _ current: [StarMapClusterNode],
        previousStyle: StarMapLayoutStyle,
        currentStyle: StarMapLayoutStyle
    ) -> Bool {
        previousStyle == currentStyle
            && previous.contains(where: { $0.timelineLabel != nil }) == current.contains(where: { $0.timelineLabel != nil })
            && previous.elementsEqual(current) { previous, current in
                previous.id == current.id && previous.isCollapsed == current.isCollapsed
                    && (current.isCollapsed || previous.leaves.prefix(40).elementsEqual(current.leaves.prefix(40)) { $0.id == $1.id })
            }
    }
    
    
    var body: some View {
        let isDark = (self.colorScheme == .dark)
        let tokens = DashPalette.editorialTokens(isDark: isDark)
        let reuseCached = (self.cachedClustersSnapshot == self.clusters
            || Self.hasSameLayoutInputs(self.cachedClustersSnapshot, self.clusters, previousStyle: self.cachedLayoutStyle, currentStyle: self.layoutStyle))
        let layout = reuseCached ? self.cachedLayout : Self.computeLayout(for: self.clusters, layoutStyle: self.layoutStyle)
        let maps: (clusterMap: [String: StarMapClusterNode], leafMap: [String: StarMapLeafNode]) = (self.cachedClustersSnapshot == self.clusters && !self.cachedClusterMap.isEmpty)
            ? (self.cachedClusterMap, self.cachedLeafMap)
            : Self.buildNodeMaps(for: self.clusters)
        
        GeometryReader { geo in
            let viewportCenter = CGPoint(x: geo.size.width * 0.5, y: geo.size.height * 0.5 + 8)
            let clusterGlows: [StarMapClusterGlow] = layout.clusters.compactMap { cPos in
                guard let cluster = maps.clusterMap[cPos.id] else { return nil }
                return StarMapClusterGlow(id: cPos.id, worldPoint: cPos.worldPoint, color: cluster.accent)
            }
            
            ZStack {
                StarMapStarfieldBackdrop(
                    canvasColor: tokens.canvasTop,
                    accentColor: tokens.accent,
                    isDark: isDark,
                    viewportCenter: viewportCenter,
                    panOffset: self.panOffset,
                    zoomScale: self.zoomScale,
                    clusterGlows: clusterGlows
                )
                .ignoresSafeArea()
                .allowsHitTesting(false)
                
                StarMapTrackpadPanZoomRepresentable(
                    onPan: { dx, dy in
                        self.panOffset.width += dx
                        self.panOffset.height += dy
                    },
                    onZoom: { factor in
                        self.applyZoom(to: self.zoomScale * factor, animated: false)
                    },
                    isBlockedByOverlay: self.isOverlayBlockingInteraction
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                
                StarMapViewportConnectorsCanvas(
                    clusters: self.clusters,
                    relations: self.relations,
                    layout: layout,
                    clusterMap: maps.clusterMap,
                    leafMap: maps.leafMap,
                    selectedLeafID: self.selectedLeafID,
                    focusedClusterID: self.focusedClusterID,
                    viewportCenter: viewportCenter,
                    panOffset: self.panOffset,
                    zoomScale: self.zoomScale,
                    tokens: tokens
                )
                .allowsHitTesting(false)
                
                StarMapWorldStageView(
                    hubTitle: self.hubTitle,
                    hubSubtitle: self.hubSubtitle,
                    clusters: self.clusters,
                    relations: self.relations,
                    layout: layout,
                    clusterMap: maps.clusterMap,
                    leafMap: maps.leafMap,
                    selectedLeafID: self.selectedLeafID,
                    multiSelectedLeafIDs: self.multiSelectedLeafIDs,
                    focusedClusterID: self.focusedClusterID,
                    isDark: isDark,
                    tokens: tokens,
                    viewportSize: geo.size,
                    viewportCenter: viewportCenter,
                    panOffset: self.panOffset,
                    zoomScale: self.zoomScale,
                    onSelectLeaf: self.onSelectLeaf,
                    onCommandSelectLeaf: self.onCommandSelectLeaf,
                    onDoubleClickLeaf: self.onDoubleClickLeaf,
                    onToggleCluster: self.onToggleCluster,
                    clusterContextMenu: self.clusterContextMenu,
                    leafContextMenu: self.leafContextMenu
                )
                .equatable()
                .frame(width: geo.size.width, height: geo.size.height)
                
                self.zoomHUD(layout: layout, size: geo.size, tokens: tokens)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 4)
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
                            self.pinchBasePan = self.panOffset
                        }
                        if let base = self.pinchBaseZoom, let basePan = self.pinchBasePan {
                            let next = min(StarMapZoomMetrics.maxZoom, max(StarMapZoomMetrics.minZoom, base * value))
                            self.panOffset = StarMapZoomMetrics.zoomAnchoredPan(oldPan: basePan, oldZoom: base, newZoom: next)
                            self.zoomScale = next
                        }
                    }
                    .onEnded { _ in
                        self.pinchBaseZoom = nil
                        self.pinchBasePan = nil
                    }
            )
            .onAppear {
                self.cachedLayout = layout
                self.cachedLayoutStyle = self.layoutStyle
                self.cachedClustersSnapshot = self.clusters
                self.cachedClusterMap = maps.clusterMap
                self.cachedLeafMap = maps.leafMap
                if !self.hasAutoFitted && geo.size.width > 100 {
                    self.hasAutoFitted = true
                    self.fitViewport(bounds: layout.bounds, size: geo.size, animated: false)
                }
                self.reportSelectedLeafFrame(layout: layout, viewportCenter: viewportCenter)
            }
            .onChange(of: self.clusters) { _, nextClusters in
                let nextMaps = Self.buildNodeMaps(for: nextClusters)
                self.cachedLayout = Self.computeLayout(for: nextClusters, layoutStyle: self.layoutStyle)
                self.cachedLayoutStyle = self.layoutStyle
                self.cachedClustersSnapshot = nextClusters
                self.cachedClusterMap = nextMaps.clusterMap
                self.cachedLeafMap = nextMaps.leafMap
                self.reportSelectedLeafFrame(layout: self.cachedLayout, viewportCenter: viewportCenter)
            }
            .onChange(of: self.layoutStyle) { _, nextStyle in
                let freshLayout = Self.computeLayout(for: self.clusters, layoutStyle: nextStyle)
                self.cachedLayout = freshLayout
                self.cachedLayoutStyle = nextStyle
                if geo.size.width > 100 {
                    self.fitViewport(bounds: freshLayout.bounds, size: geo.size, animated: true)
                }
                self.reportSelectedLeafFrame(layout: freshLayout, viewportCenter: viewportCenter)
            }
            .onChange(of: self.selectedLeafID) { _, _ in
                self.reportSelectedLeafFrame(layout: layout, viewportCenter: viewportCenter)
            }
            .onChange(of: self.panOffset) { _, _ in
                self.reportSelectedLeafFrame(layout: layout, viewportCenter: viewportCenter)
            }
            .onChange(of: self.zoomScale) { _, _ in
                self.reportSelectedLeafFrame(layout: layout, viewportCenter: viewportCenter)
            }
            .onChange(of: geo.size) { _, newSize in
                if !self.hasAutoFitted && newSize.width > 100 {
                    self.hasAutoFitted = true
                    self.fitViewport(bounds: layout.bounds, size: newSize, animated: false)
                }
                let nextCenter = CGPoint(x: newSize.width * 0.5, y: newSize.height * 0.5 + 8)
                self.reportSelectedLeafFrame(layout: layout, viewportCenter: nextCenter)
            }
            .onChange(of: self.searchQuery) { _, _ in
                self.fitViewport(bounds: layout.bounds, size: geo.size, animated: true)
            }
            .onChange(of: self.panRequestToken) { _, _ in
                guard let selectedLeafID = self.selectedLeafID, geo.size.width > 100 else { return }
                if let lPos = layout.leaves.first(where: { $0.id == selectedLeafID }) {
                    let targetZoom: CGFloat = max(self.zoomScale, 1.0)
                    withAnimation(Self.cameraSpring) {
                        self.zoomScale = targetZoom
                        self.panOffset = CGSize(
                            width: -lPos.worldPoint.x * targetZoom * 0.72,
                            height: -lPos.worldPoint.y * targetZoom * 0.72
                        )
                    }
                }
            }
            .onChange(of: self.fitRequestToken) { _, _ in
                guard geo.size.width > 100 else { return }
                let freshLayout = Self.computeLayout(for: self.clusters, layoutStyle: self.layoutStyle)
                let freshMaps = Self.buildNodeMaps(for: self.clusters)
                self.cachedLayout = freshLayout
                self.cachedLayoutStyle = self.layoutStyle
                self.cachedClustersSnapshot = self.clusters
                self.cachedClusterMap = freshMaps.clusterMap
                self.cachedLeafMap = freshMaps.leafMap
                self.fitViewport(bounds: freshLayout.bounds, size: geo.size, animated: true)
            }
            .onChange(of: self.focusedClusterID) { _, nextCID in
                guard geo.size.width > 100 else { return }
                if let nextCID, let cPos = layout.clusters.first(where: { $0.id == nextCID }) {
                    let targetZoom: CGFloat = max(self.zoomScale, 0.92)
                    withAnimation(Self.cameraSpring) {
                        self.zoomScale = targetZoom
                        self.panOffset = CGSize(
                            width: -cPos.worldPoint.x * targetZoom * 0.72,
                            height: -cPos.worldPoint.y * targetZoom * 0.72
                        )
                    }
                } else {
                    self.fitViewport(bounds: layout.bounds, size: geo.size, animated: true)
                }
            }
        }
    }
    
    
    private func zoomHUD(
        layout: StarMapLayoutEngine.LayoutResult,
        size: CGSize,
        tokens: StudioColorTokens
    ) -> some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                HStack(spacing: 2) {
                    Button {
                        self.applyZoom(to: self.zoomScale - 0.15, animated: true)
                    } label: {
                        Image(systemName: "minus")
                            .font(.system(size: 10.5, weight: .semibold))
                            .frame(width: 26, height: 26)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .pointerStyle(.link)
                    
                    Button {
                        self.fitViewport(bounds: layout.bounds, size: size, animated: true)
                    } label: {
                        Text("\(Int((self.zoomScale * 100).rounded()))%")
                            .font(.system(size: 10.5, weight: .medium, design: .monospaced).monospacedDigit())
                            .frame(minWidth: 42, minHeight: 26)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .pointerStyle(.link)
                    
                    Button {
                        self.applyZoom(to: self.zoomScale + 0.15, animated: true)
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 10.5, weight: .semibold))
                            .frame(width: 26, height: 26)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .pointerStyle(.link)
                    
                    Rectangle()
                        .fill(tokens.hairline)
                        .frame(width: 1, height: 14)
                        .padding(.horizontal, 2)
                    
                    Button {
                        self.fitViewport(bounds: layout.bounds, size: size, animated: true)
                    } label: {
                        Image(systemName: "scope")
                            .font(.system(size: 11, weight: .medium))
                            .frame(width: 26, height: 26)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .pointerStyle(.link)
                    .help("回到全景")
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
    
    
    private func reportSelectedLeafFrame(layout: StarMapLayoutEngine.LayoutResult, viewportCenter: CGPoint) {
        guard let onSelectedLeafFrameChange = self.onSelectedLeafFrameChange else { return }
        guard let selID = self.selectedLeafID, let lPos = layout.leafPositionsByID[selID] else {
            onSelectedLeafFrameChange(nil)
            return
        }
        let metrics = StarMapZoomMetrics(zoom: self.zoomScale)
        let center = StarMapZoomMetrics.screenPoint(
            world: lPos.worldPoint,
            viewportCenter: viewportCenter,
            panOffset: self.panOffset,
            zoom: self.zoomScale
        )
        let w = metrics.scaled(StarMapLayoutEngine.leafFootprint.width - 8)
        let h = metrics.scaled(StarMapLayoutEngine.leafFootprint.height - 6)
        onSelectedLeafFrameChange(CGRect(x: center.x - w * 0.5, y: center.y - h * 0.5, width: w, height: h))
    }
    
    
    private func applyZoom(to rawNext: CGFloat, animated: Bool) {
        let next = min(StarMapZoomMetrics.maxZoom, max(StarMapZoomMetrics.minZoom, rawNext))
        guard abs(next - self.zoomScale) > 0.001 else { return }
        let nextPan = StarMapZoomMetrics.zoomAnchoredPan(
            oldPan: self.panOffset,
            oldZoom: self.zoomScale,
            newZoom: next
        )
        if animated {
            withAnimation(Self.cameraSpring) {
                self.zoomScale = next
                self.panOffset = nextPan
            }
        } else {
            self.zoomScale = next
            self.panOffset = nextPan
        }
    }
    
    
    private func fitViewport(bounds: CGRect, size: CGSize, animated: Bool) {
        let usableW = max(240, size.width - 96)
        let usableH = max(200, size.height - 156)
        let fitX = usableW / max(240, bounds.width)
        let fitY = usableH / max(180, bounds.height)
        let targetZoom = min(1.02, max(0.42, min(fitX, fitY)))
        let targetPan = CGSize(
            width: -bounds.midX * targetZoom,
            height: -bounds.midY * targetZoom
        )
        if animated {
            withAnimation(Self.cameraSpring) {
                self.zoomScale = targetZoom
                self.panOffset = targetPan
            }
        } else {
            self.zoomScale = targetZoom
            self.panOffset = targetPan
        }
    }
}


private struct StarMapClusterGlow: Identifiable, Equatable {
    let id: String
    let worldPoint: CGPoint
    let color: Color
}


/// Viewport-sized Animatable Canvas drawing orbital curves, timeline spine buses, far-zoom leaf dots, and focused relation arcs.
private struct StarMapViewportConnectorsCanvas: View, Animatable {
    
    let clusters: [StarMapClusterNode]
    let relations: [StarMapRelationEdge]
    let layout: StarMapLayoutEngine.LayoutResult
    let clusterMap: [String: StarMapClusterNode]
    let leafMap: [String: StarMapLeafNode]
    let selectedLeafID: String?
    let focusedClusterID: String?
    let viewportCenter: CGPoint
    var panOffset: CGSize
    var zoomScale: CGFloat
    let tokens: StudioColorTokens
    
    var animatableData: AnimatablePair<CGFloat, AnimatablePair<CGFloat, CGFloat>> {
        get { AnimatablePair(self.zoomScale, AnimatablePair(self.panOffset.width, self.panOffset.height)) }
        set {
            self.zoomScale = newValue.first
            self.panOffset = CGSize(width: newValue.second.first, height: newValue.second.second)
        }
    }
    
    @inline(__always)
    private func toScreen(_ worldPt: CGPoint) -> CGPoint {
        CGPoint(
            x: self.viewportCenter.x + self.panOffset.width + worldPt.x * self.zoomScale,
            y: self.viewportCenter.y + self.panOffset.height + worldPt.y * self.zoomScale
        )
    }
    
    
    var body: some View {
        let leafPosByID = self.layout.leafPositionsByID
        let selectedClusterID: String? = self.focusedClusterID
            ?? self.selectedLeafID.flatMap { leafPosByID[$0]?.clusterID }
        
        Canvas(opaque: false, rendersAsynchronously: true) { context, canvasSize in
            let z = self.zoomScale
            let metrics = StarMapZoomMetrics(zoom: z)
            let viewportBounds = CGRect(origin: .zero, size: canvasSize).insetBy(dx: -180 * z, dy: -180 * z)
            
            if self.layout.usesOrbitalLayout {
                self.drawOrbitalConnectors(
                    context: &context,
                    viewportBounds: viewportBounds,
                    selectedClusterID: selectedClusterID,
                    metrics: metrics
                )
            } else {
                self.drawTreeConnectors(
                    context: &context,
                    viewportBounds: viewportBounds,
                    selectedClusterID: selectedClusterID,
                    metrics: metrics
                )
            }
            
            if z < 0.60 {
                self.drawFarZoomLeafDots(context: &context, viewportBounds: viewportBounds)
            }
            
            self.drawSelectedRelationArcs(
                context: &context,
                leafPosByID: leafPosByID,
                metrics: metrics
            )
        }
    }
    
    
    private func drawOrbitalConnectors(
        context: inout GraphicsContext,
        viewportBounds: CGRect,
        selectedClusterID: String?,
        metrics: StarMapZoomMetrics
    ) {
        let hubScreen = self.toScreen(self.layout.hubPoint)
        for cPos in self.layout.clusters {
            let cScreen = self.toScreen(cPos.worldPoint)
            guard viewportBounds.contains(hubScreen) || viewportBounds.contains(cScreen) else { continue }
            let accent = self.clusterMap[cPos.id]?.accent ?? self.tokens.accent
            let isActive = (selectedClusterID == nil || selectedClusterID == cPos.id)
            let dx = cScreen.x - hubScreen.x
            let dy = cScreen.y - hubScreen.y
            let control = CGPoint(
                x: (hubScreen.x + cScreen.x) * 0.5 - dy * 0.18,
                y: (hubScreen.y + cScreen.y) * 0.5 + dx * 0.18
            )
            var path = Path()
            path.move(to: hubScreen)
            path.addQuadCurve(to: cScreen, control: control)
            context.stroke(
                path,
                with: .color(accent.opacity(isActive ? 0.36 : 0.14)),
                style: StrokeStyle(lineWidth: metrics.strokeWidth(0.9), lineCap: .round)
            )
        }
        
        for lPos in self.layout.leaves {
            let p0 = self.toScreen(lPos.parentPoint)
            let p1 = self.toScreen(lPos.worldPoint)
            guard viewportBounds.contains(p0) || viewportBounds.contains(p1) else { continue }
            let accent = self.clusterMap[lPos.clusterID]?.accent ?? self.tokens.accent
            let isSelected = (self.selectedLeafID == lPos.id)
            let isClusterActive = (selectedClusterID == nil || selectedClusterID == lPos.clusterID)
            let dx = p1.x - p0.x
            let dy = p1.y - p0.y
            let control = CGPoint(
                x: (p0.x + p1.x) * 0.5 - dy * 0.14,
                y: (p0.y + p1.y) * 0.5 + dx * 0.14
            )
            var curve = Path()
            curve.move(to: p0)
            curve.addQuadCurve(to: p1, control: control)
            context.stroke(
                curve,
                with: .color(accent.opacity(isSelected ? 0.85 : (isClusterActive ? 0.22 : 0.10))),
                style: StrokeStyle(lineWidth: isSelected ? 1.5 : 0.75, lineCap: .round)
            )
        }
    }
    
    
    private func drawTreeConnectors(
        context: inout GraphicsContext,
        viewportBounds: CGRect,
        selectedClusterID: String?,
        metrics: StarMapZoomMetrics
    ) {
        let z = self.zoomScale
        let hubHalfW: CGFloat = (StarMapLayoutEngine.hubFootprint.width - 12) * 0.5
        let hubHalfH: CGFloat = (StarMapLayoutEngine.hubFootprint.height - 14) * 0.5
        let milestoneHalfW: CGFloat = (StarMapLayoutEngine.milestoneFootprint.width - 6) * 0.5
        let clusterHalfW: CGFloat = (StarMapLayoutEngine.clusterFootprint.width - 8) * 0.5
        let leafHalfW: CGFloat = (StarMapLayoutEngine.leafFootprint.width - 8) * 0.5
        
        if self.layout.usesTimelineSpine, let lastCluster = self.layout.clusters.last {
            let spineStart = self.toScreen(CGPoint(x: 0, y: self.layout.hubPoint.y + hubHalfH))
            let spineEnd = self.toScreen(CGPoint(x: 0, y: lastCluster.worldPoint.y + 22))
            var spinePath = Path()
            spinePath.move(to: spineStart)
            spinePath.addLine(to: spineEnd)
            spinePath.move(to: CGPoint(x: spineEnd.x - 3.5 * z, y: spineEnd.y - 4 * z))
            spinePath.addLine(to: spineEnd)
            spinePath.addLine(to: CGPoint(x: spineEnd.x + 3.5 * z, y: spineEnd.y - 4 * z))
            context.stroke(
                spinePath,
                with: .color(self.tokens.primaryInk.opacity(0.20)),
                style: StrokeStyle(lineWidth: metrics.strokeWidth(1.35), lineCap: .round, lineJoin: .round)
            )
            for cPos in self.layout.clusters {
                let side: CGFloat = cPos.worldPoint.x >= 0 ? 1.0 : -1.0
                let p0 = self.toScreen(CGPoint(x: side * milestoneHalfW, y: cPos.worldPoint.y))
                let p1 = self.toScreen(CGPoint(x: cPos.worldPoint.x - side * clusterHalfW, y: cPos.worldPoint.y))
                guard viewportBounds.contains(p0) || viewportBounds.contains(p1) else { continue }
                let accent = self.clusterMap[cPos.id]?.accent ?? self.tokens.accent
                let isActive = (selectedClusterID == nil || selectedClusterID == cPos.id)
                var branch = Path()
                branch.move(to: p0)
                branch.addLine(to: p1)
                context.stroke(
                    branch,
                    with: .color(accent.opacity(isActive ? 0.56 : 0.20)),
                    style: StrokeStyle(lineWidth: metrics.strokeWidth((selectedClusterID == cPos.id) ? 1.75 : 1.2), lineCap: .round)
                )
            }
        } else {
            for cPos in self.layout.clusters {
                let side: CGFloat = cPos.worldPoint.x >= 0 ? 1.0 : -1.0
                let p0 = self.toScreen(CGPoint(x: self.layout.hubPoint.x + side * hubHalfW, y: self.layout.hubPoint.y))
                let p1 = self.toScreen(CGPoint(x: cPos.worldPoint.x - side * clusterHalfW, y: cPos.worldPoint.y))
                guard viewportBounds.contains(p0) || viewportBounds.contains(p1) else { continue }
                let accent = self.clusterMap[cPos.id]?.accent ?? self.tokens.accent
                let isActive = (selectedClusterID == nil || selectedClusterID == cPos.id)
                let midX = (p0.x + p1.x) * 0.5
                var trunk = Path()
                trunk.move(to: p0)
                trunk.addCurve(to: p1, control1: CGPoint(x: midX, y: p0.y), control2: CGPoint(x: midX, y: p1.y))
                context.stroke(
                    trunk,
                    with: .color(accent.opacity(isActive ? 0.52 : 0.20)),
                    style: StrokeStyle(lineWidth: metrics.strokeWidth((selectedClusterID == cPos.id) ? 1.7 : 1.2), lineCap: .round)
                )
            }
        }
        
        for (key, colLeaves) in self.layout.leafColumns {
            let first = colLeaves[0]
            let colWorldX = first.worldPoint.x
            let side: CGFloat = colWorldX >= 0 ? 1.0 : -1.0
            let parentWorld = first.parentPoint
            let isSubcolumnContinuation = abs(parentWorld.x) > 350
            let parentOuterWorldX = parentWorld.x + side * (isSubcolumnContinuation ? leafHalfW : clusterHalfW)
            let leafInnerWorldX = colWorldX - side * leafHalfW
            let spineWorldX = (parentOuterWorldX + leafInnerWorldX) * 0.5
            let accent = self.clusterMap[key.clusterID]?.accent ?? self.tokens.accent
            let isClusterActive = (selectedClusterID == nil || selectedClusterID == key.clusterID)
            let parentOutScreen = self.toScreen(CGPoint(x: parentOuterWorldX, y: parentWorld.y))
            let spineScreenX = self.toScreen(CGPoint(x: spineWorldX, y: parentWorld.y)).x
            let leafInScreenX = self.toScreen(CGPoint(x: leafInnerWorldX, y: parentWorld.y)).x
            var minY = parentOutScreen.y
            var maxY = parentOutScreen.y
            for l in colLeaves {
                let sy = self.toScreen(l.worldPoint).y
                minY = min(minY, sy)
                maxY = max(maxY, sy)
            }
            let colBounds = CGRect(
                x: min(parentOutScreen.x, leafInScreenX) - 20 * z,
                y: minY - 20 * z,
                width: abs(leafInScreenX - parentOutScreen.x) + 40 * z,
                height: (maxY - minY) + 40 * z
            )
            guard viewportBounds.intersects(colBounds) else { continue }
            var bus = Path()
            bus.move(to: parentOutScreen)
            bus.addLine(to: CGPoint(x: spineScreenX, y: parentOutScreen.y))
            if maxY - minY > 0.5 {
                bus.move(to: CGPoint(x: spineScreenX, y: minY))
                bus.addLine(to: CGPoint(x: spineScreenX, y: maxY))
            }
            for l in colLeaves {
                let sy = self.toScreen(l.worldPoint).y
                bus.move(to: CGPoint(x: spineScreenX, y: sy))
                bus.addLine(to: CGPoint(x: leafInScreenX, y: sy))
            }
            context.stroke(
                bus,
                with: .color(accent.opacity(isClusterActive ? 0.36 : 0.14)),
                style: StrokeStyle(lineWidth: metrics.strokeWidth(1.15), lineCap: .round, lineJoin: .round)
            )
            if let selID = self.selectedLeafID, let selLeaf = colLeaves.first(where: { $0.id == selID }) {
                let selY = self.toScreen(selLeaf.worldPoint).y
                var highlight = Path()
                highlight.move(to: parentOutScreen)
                highlight.addLine(to: CGPoint(x: spineScreenX, y: parentOutScreen.y))
                highlight.addLine(to: CGPoint(x: spineScreenX, y: selY))
                highlight.addLine(to: CGPoint(x: leafInScreenX, y: selY))
                context.stroke(
                    highlight,
                    with: .color(accent.opacity(0.90)),
                    style: StrokeStyle(lineWidth: metrics.strokeWidth(1.85), lineCap: .round, lineJoin: .round)
                )
            }
        }
    }
    
    
    private func drawFarZoomLeafDots(context: inout GraphicsContext, viewportBounds: CGRect) {
        for lPos in self.layout.leaves {
            let pt = self.toScreen(lPos.worldPoint)
            guard viewportBounds.contains(pt) else { continue }
            let dotColor = self.leafMap[lPos.id]?.dotColor ?? self.tokens.accent
            let haloRect = CGRect(x: pt.x - 3.5, y: pt.y - 3.5, width: 7, height: 7)
            context.fill(Circle().path(in: haloRect), with: .color(dotColor.opacity(0.25)))
            let dotRect = CGRect(x: pt.x - 1.5, y: pt.y - 1.5, width: 3, height: 3)
            context.fill(Circle().path(in: dotRect), with: .color(dotColor.opacity(0.92)))
        }
    }
    
    
    private func drawSelectedRelationArcs(
        context: inout GraphicsContext,
        leafPosByID: [String: StarMapLayoutEngine.PositionedLeaf],
        metrics: StarMapZoomMetrics
    ) {
        guard let selID = self.selectedLeafID else { return }
        let z = self.zoomScale
        let leafHalfW: CGFloat = (StarMapLayoutEngine.leafFootprint.width - 8) * 0.5
        let incident = self.relations.filter { $0.sourceID == selID || $0.targetID == selID }.prefix(2)
        for edge in incident {
            guard let a = leafPosByID[edge.sourceID], let b = leafPosByID[edge.targetID] else { continue }
            let sideA: CGFloat = a.worldPoint.x >= 0 ? 1.0 : -1.0
            let sideB: CGFloat = b.worldPoint.x >= 0 ? 1.0 : -1.0
            var arc = Path()
            if sideA == sideB {
                let p0 = self.toScreen(CGPoint(x: a.worldPoint.x + sideA * leafHalfW, y: a.worldPoint.y))
                let p1 = self.toScreen(CGPoint(x: b.worldPoint.x + sideB * leafHalfW, y: b.worldPoint.y))
                let outerWorldX = sideA > 0
                    ? max(a.worldPoint.x, b.worldPoint.x) + leafHalfW
                    : min(a.worldPoint.x, b.worldPoint.x) - leafHalfW
                let bowOut = min(76, max(30, abs(b.worldPoint.y - a.worldPoint.y) * 0.22))
                let cX = self.toScreen(CGPoint(x: outerWorldX + sideA * bowOut, y: 0)).x
                arc.move(to: p0)
                arc.addCurve(to: p1, control1: CGPoint(x: cX, y: p0.y), control2: CGPoint(x: cX, y: p1.y))
            } else {
                let p0 = self.toScreen(CGPoint(x: a.worldPoint.x - sideA * leafHalfW, y: a.worldPoint.y))
                let p1 = self.toScreen(CGPoint(x: b.worldPoint.x - sideB * leafHalfW, y: b.worldPoint.y))
                let midX = (p0.x + p1.x) * 0.5
                arc.move(to: p0)
                arc.addCurve(to: p1, control1: CGPoint(x: midX, y: p0.y), control2: CGPoint(x: midX, y: p1.y))
            }
            context.stroke(
                arc,
                with: .color(self.tokens.accent.opacity(0.42)),
                style: StrokeStyle(lineWidth: metrics.strokeWidth(1.15), lineCap: .round, dash: [4 * z, 4 * z])
            )
        }
    }
}


private struct StarMapWorldStageView<ClusterMenu: View, LeafMenu: View>: View, Equatable {
    
    let hubTitle: String
    let hubSubtitle: String
    let clusters: [StarMapClusterNode]
    let relations: [StarMapRelationEdge]
    let layout: StarMapLayoutEngine.LayoutResult
    let clusterMap: [String: StarMapClusterNode]
    let leafMap: [String: StarMapLeafNode]
    let selectedLeafID: String?
    let multiSelectedLeafIDs: Set<String>
    let focusedClusterID: String?
    let isDark: Bool
    let tokens: StudioColorTokens
    let viewportSize: CGSize
    let viewportCenter: CGPoint
    let panOffset: CGSize
    let zoomScale: CGFloat
    let onSelectLeaf: (String) -> Void
    let onCommandSelectLeaf: ((String) -> Void)?
    let onDoubleClickLeaf: (String) -> Void
    let onToggleCluster: (String) -> Void
    @ViewBuilder let clusterContextMenu: (StarMapClusterNode) -> ClusterMenu
    @ViewBuilder let leafContextMenu: (StarMapLeafNode) -> LeafMenu
    
    
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.hubTitle == rhs.hubTitle
            && lhs.hubSubtitle == rhs.hubSubtitle
            && lhs.clusters == rhs.clusters
            && lhs.relations == rhs.relations
            && lhs.layout == rhs.layout
            && lhs.selectedLeafID == rhs.selectedLeafID
            && lhs.multiSelectedLeafIDs == rhs.multiSelectedLeafIDs
            && lhs.focusedClusterID == rhs.focusedClusterID
            && lhs.isDark == rhs.isDark
            && lhs.viewportSize == rhs.viewportSize
            && lhs.viewportCenter == rhs.viewportCenter
            && lhs.panOffset == rhs.panOffset
            && abs(lhs.zoomScale - rhs.zoomScale) < 0.0005
    }
    
    
    private func screenPosition(_ worldPt: CGPoint) -> CGPoint {
        StarMapZoomMetrics.screenPoint(
            world: worldPt,
            viewportCenter: self.viewportCenter,
            panOffset: self.panOffset,
            zoom: self.zoomScale
        )
    }
    
    
    var body: some View {
        let tokens = self.tokens
        let metrics = StarMapZoomMetrics(zoom: self.zoomScale)
        let cullRect = CGRect(origin: .zero, size: self.viewportSize)
            .insetBy(dx: -metrics.scaled(260), dy: -metrics.scaled(160))
        let relatedIDs: Set<String> = {
            guard let selID = self.selectedLeafID else { return [] }
            var ids = Set<String>()
            for edge in self.relations.filter({ $0.sourceID == selID || $0.targetID == selID }).prefix(2) {
                ids.insert(edge.sourceID == selID ? edge.targetID : edge.sourceID)
            }
            return ids
        }()
        let hubScreen = self.screenPosition(self.layout.hubPoint)
        let isFarZoom = self.zoomScale < 0.60
        let isCompactMidZoom = self.zoomScale >= 0.60 && self.zoomScale < 1.00
        
        ZStack {
            if cullRect.contains(hubScreen) {
                let hubCorner = metrics.scaled(12)
                VStack(spacing: 3) {
                    Text(self.hubTitle)
                        .font(.system(size: isFarZoom ? 12.5 : 13.5, weight: .semibold))
                        .foregroundStyle(tokens.primaryInk)
                        .lineLimit(1)
                    Text(self.hubSubtitle)
                        .font(.system(size: 10.5, weight: .medium, design: .rounded).monospacedDigit())
                        .foregroundStyle(tokens.primaryInk.opacity(0.55))
                        .lineLimit(1)
                }
                .frame(
                    width: max(124, metrics.scaled(StarMapLayoutEngine.hubFootprint.width - 12)),
                    height: max(46, metrics.scaled(StarMapLayoutEngine.hubFootprint.height - 14))
                )
                .background(tokens.card, in: RoundedRectangle(cornerRadius: max(10, hubCorner), style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: max(10, hubCorner), style: .continuous)
                        .strokeBorder(tokens.accent.opacity(0.55), lineWidth: metrics.strokeWidth(1.2))
                )
                .position(x: hubScreen.x, y: hubScreen.y)
            }
            
            if self.layout.usesTimelineSpine {
                ForEach(self.layout.clusters) { cPos in
                    let pt = self.screenPosition(CGPoint(x: 0, y: cPos.worldPoint.y))
                    if cullRect.contains(pt),
                       let cluster = self.clusterMap[cPos.id],
                       let timeLabel = cluster.timelineLabel
                    {
                        StarMapTimelineMilestoneView(
                            label: timeLabel,
                            accent: cluster.accent,
                            isFocused: self.focusedClusterID == cluster.id,
                            isDark: self.isDark,
                            zoomScale: self.zoomScale,
                            tokens: tokens,
                            onTap: { self.onToggleCluster(cluster.id) }
                        )
                        .equatable()
                        .position(x: pt.x, y: pt.y)
                    }
                }
            }
            
            ForEach(self.layout.clusters) { cPos in
                let pt = self.screenPosition(cPos.worldPoint)
                if cullRect.contains(pt), let cluster = self.clusterMap[cPos.id] {
                    StarMapClusterPillView(
                        cluster: cluster,
                        isFocused: self.focusedClusterID == cluster.id,
                        isDark: self.isDark,
                        zoomScale: self.zoomScale,
                        tokens: tokens,
                        onToggle: { self.onToggleCluster(cluster.id) }
                    )
                    .equatable()
                    .position(x: pt.x, y: pt.y)
                    .contextMenu {
                        self.clusterContextMenu(cluster)
                    }
                }
            }
            
            if !isFarZoom {
                ForEach(self.layout.leaves) { lPos in
                    let pt = self.screenPosition(lPos.worldPoint)
                    if cullRect.contains(pt), let leaf = self.leafMap[lPos.id] {
                        let isMultiSelected = self.multiSelectedLeafIDs.contains(leaf.id)
                        let isSelected = (self.selectedLeafID == leaf.id) || isMultiSelected
                        let isRelated = relatedIDs.contains(leaf.id)
                        let dimmed = (self.focusedClusterID != nil && self.focusedClusterID != leaf.clusterID && !isSelected && !isRelated)
                        
                        StarMapLeafCardView(
                            leaf: leaf,
                            tokens: tokens,
                            isSelected: isSelected,
                            isMultiSelected: isMultiSelected,
                            isRelated: isRelated,
                            dimmed: dimmed,
                            isDark: self.isDark,
                            isCompactLOD: isCompactMidZoom,
                            zoomScale: self.zoomScale
                        )
                        .equatable()
                        .position(x: pt.x, y: pt.y)
                        .pointerStyle(.link)
                        .onTapGesture(count: 2) {
                            self.onSelectLeaf(leaf.id)
                            self.onDoubleClickLeaf(leaf.id)
                        }
                        .onTapGesture(count: 1) {
                            if let onCommandSelect = self.onCommandSelectLeaf,
                               NSEvent.modifierFlags.contains(.command)
                            {
                                onCommandSelect(leaf.id)
                            } else {
                                self.onSelectLeaf(leaf.id)
                            }
                        }
                        .contextMenu {
                            self.leafContextMenu(leaf)
                        }
                    }
                }
            }
        }
        .clipped()
    }
}


private struct StarMapTimelineMilestoneView: View, Equatable {
    
    let label: String
    let accent: Color
    let isFocused: Bool
    let isDark: Bool
    let zoomScale: CGFloat
    let tokens: StudioColorTokens
    let onTap: () -> Void
    
    @State private var isHovered = false
    
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.label == rhs.label
            && lhs.accent == rhs.accent
            && lhs.isFocused == rhs.isFocused
            && lhs.isDark == rhs.isDark
            && abs(lhs.zoomScale - rhs.zoomScale) < 0.0005
    }
    
    var body: some View {
        let m = StarMapZoomMetrics(zoom: self.zoomScale)
        let strokeColor: Color = self.isFocused
            ? self.accent.opacity(0.75)
            : self.tokens.hairlineStrong
        Button(action: self.onTap) {
            HStack(spacing: m.scaled(4.5)) {
                Circle()
                    .fill(self.accent)
                    .frame(width: 5.5, height: 5.5)
                
                Text(self.label)
                    .font(.system(size: 10.5, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(self.isFocused ? self.accent : self.tokens.primaryInk.opacity(0.76))
                    .lineLimit(1)
            }
            .padding(.horizontal, 8)
            .frame(
                width: max(92, m.scaled(StarMapLayoutEngine.milestoneFootprint.width - 6)),
                height: max(22, m.scaled(StarMapLayoutEngine.milestoneFootprint.height - 2))
            )
            .background(self.isHovered ? self.tokens.insetHover : self.tokens.card, in: Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(
                        strokeColor,
                        lineWidth: m.strokeWidth((self.isFocused || self.isHovered) ? 1.2 : 0.75)
                    )
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .pointerStyle(.link)
        .onHover { hovering in
            if hovering != self.isHovered {
                self.isHovered = hovering
            }
        }
    }
}


private struct StarMapClusterPillView: View, Equatable {
    
    let cluster: StarMapClusterNode
    let isFocused: Bool
    let isDark: Bool
    let zoomScale: CGFloat
    let tokens: StudioColorTokens
    let onToggle: () -> Void
    
    @State private var isHovered = false
    
    
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.cluster == rhs.cluster
            && lhs.isFocused == rhs.isFocused
            && lhs.isDark == rhs.isDark
            && abs(lhs.zoomScale - rhs.zoomScale) < 0.0005
    }
    
    
    var body: some View {
        let m = StarMapZoomMetrics(zoom: self.zoomScale)
        let isFarZoom = self.zoomScale < 0.60
        let corner: CGFloat = isFarZoom ? 10 : max(10, m.scaled(10))
        let strokeColor: Color = self.isFocused
            ? self.cluster.accent.opacity(0.78)
            : self.tokens.hairlineStrong
        Button(action: self.onToggle) {
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(self.cluster.accent)
                    .frame(width: 3.5, height: 15)
                
                Text(self.cluster.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(self.tokens.primaryInk)
                    .lineLimit(1)
                
                Spacer(minLength: 2)
                
                Text(self.cluster.countText)
                    .font(.system(size: 10.5, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(self.cluster.accent)
                    .padding(.horizontal, 6)
                    .frame(height: 18)
                    .background(self.cluster.accent.opacity(self.isDark ? 0.18 : 0.11), in: Capsule())
                
                if !isFarZoom {
                    Image(systemName: self.cluster.isCollapsed ? "chevron.right" : "chevron.down")
                        .font(.system(size: 9.5, weight: .bold))
                        .foregroundStyle(self.tokens.primaryInk.opacity(0.45))
                }
            }
            .padding(.horizontal, 10)
            .frame(
                width: max(136, m.scaled(StarMapLayoutEngine.clusterFootprint.width - 8)),
                height: max(32, m.scaled(StarMapLayoutEngine.clusterFootprint.height - 8))
            )
            .background(self.isHovered ? self.tokens.insetHover : self.tokens.card, in: RoundedRectangle(cornerRadius: corner, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .strokeBorder(
                        strokeColor,
                        lineWidth: m.strokeWidth((self.isFocused || self.isHovered) ? 1.3 : 0.85)
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
        }
        .buttonStyle(.plain)
        .pointerStyle(.link)
        .onHover { hovering in
            if hovering != self.isHovered {
                self.isHovered = hovering
            }
        }
    }
}


private struct StarMapLeafCardView: View, Equatable {
    
    let leaf: StarMapLeafNode
    let tokens: StudioColorTokens
    let isSelected: Bool
    let isMultiSelected: Bool
    let isRelated: Bool
    let dimmed: Bool
    let isDark: Bool
    let isCompactLOD: Bool
    let zoomScale: CGFloat
    
    @State private var isHovered = false
    
    
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.leaf == rhs.leaf
            && lhs.isSelected == rhs.isSelected
            && lhs.isMultiSelected == rhs.isMultiSelected
            && lhs.isRelated == rhs.isRelated
            && lhs.dimmed == rhs.dimmed
            && lhs.isDark == rhs.isDark
            && lhs.isCompactLOD == rhs.isCompactLOD
            && abs(lhs.zoomScale - rhs.zoomScale) < 0.0005
    }
    
    
    var body: some View {
        let m = StarMapZoomMetrics(zoom: self.zoomScale)
        let corner: CGFloat = self.isCompactLOD ? 8 : 10
        let strokeColor: Color = {
            if self.isSelected {
                return self.leaf.dotColor.opacity(0.95)
            }
            if self.isRelated {
                return self.tokens.accent.opacity(0.68)
            }
            return self.isHovered ? self.tokens.hairlineStrong : self.tokens.hairline
        }()
        let cardWidth = self.isCompactLOD
            ? min(176, max(126, m.scaled(StarMapLayoutEngine.leafFootprint.width - 8)))
            : max(188, m.scaled(StarMapLayoutEngine.leafFootprint.width - 8))
        let cardHeight = self.isCompactLOD
            ? 32
            : max(50, m.scaled(StarMapLayoutEngine.leafFootprint.height - 6))
        
        VStack(alignment: .leading, spacing: 3.5) {
            HStack(spacing: 6) {
                if self.isMultiSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(self.tokens.accent)
                } else {
                    Circle()
                        .fill(self.isRelated ? self.tokens.accent : self.leaf.dotColor)
                        .frame(width: self.isSelected ? 7 : 6, height: self.isSelected ? 7 : 6)
                }
                
                Text(self.leaf.title)
                    .font(.system(size: self.isCompactLOD ? 11.5 : 12, weight: self.isSelected ? .semibold : .medium))
                    .foregroundStyle(self.tokens.primaryInk.opacity(self.isSelected ? 1.0 : 0.90))
                    .lineLimit(1)
                
                Spacer(minLength: 0)
            }
            
            if !self.isCompactLOD {
                HStack(spacing: 5) {
                    if let badge = self.leaf.statusBadge, !badge.isEmpty {
                        Text(badge)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(self.tokens.accentText)
                            .padding(.horizontal, 4.5)
                            .frame(height: 15)
                            .background(self.tokens.positivePillBg, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                    }
                    if !self.leaf.metaLine.isEmpty {
                        Text(self.leaf.metaLine)
                            .font(.system(size: 10, weight: .regular, design: .rounded).monospacedDigit())
                            .foregroundStyle(self.tokens.primaryInk.opacity(0.50))
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.leading, 12)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, self.isCompactLOD ? 5 : 6)
        .frame(width: cardWidth, height: cardHeight, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .fill(self.isHovered ? self.tokens.insetHover : self.tokens.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .strokeBorder(
                    strokeColor,
                    lineWidth: m.strokeWidth(self.isSelected ? 1.6 : (self.isRelated ? 1.2 : 0.85))
                )
        )
        .contentShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
        .opacity(self.dimmed ? 0.45 : 1.0)
        .onHover { hovering in
            if hovering != self.isHovered {
                self.isHovered = hovering
            }
        }
    }
}


/// Animatable parallax starfield & nebula backdrop for the explorable star-map universe.
private struct StarMapStarfieldBackdrop: View, Animatable {
    
    struct SeedStar: Sendable {
        let x: CGFloat
        let y: CGFloat
        let radius: CGFloat
        let layer: Int
        let alpha: CGFloat
    }
    
    private static let seededStars: [SeedStar] = {
        var state: UInt64 = 0x5A17_9E37_79B9_7F4A
        func nextUnit() -> CGFloat {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            let v = Double((state >> 32) & 0xFFFF_FFFF) / Double(UInt32.max)
            return CGFloat(v)
        }
        return (0..<220).map { i in
            let layer = i % 3
            let radius: CGFloat = layer == 0 ? 0.85 : (layer == 1 ? 1.15 : 1.55)
            let alpha: CGFloat = 0.28 + nextUnit() * 0.72
            return SeedStar(x: nextUnit(), y: nextUnit(), radius: radius, layer: layer, alpha: alpha)
        }
    }()
    
    let canvasColor: Color
    let accentColor: Color
    let isDark: Bool
    let viewportCenter: CGPoint
    var panOffset: CGSize
    var zoomScale: CGFloat
    let clusterGlows: [StarMapClusterGlow]
    
    var animatableData: AnimatablePair<CGFloat, AnimatablePair<CGFloat, CGFloat>> {
        get { AnimatablePair(self.zoomScale, AnimatablePair(self.panOffset.width, self.panOffset.height)) }
        set {
            self.zoomScale = newValue.first
            self.panOffset = CGSize(width: newValue.second.first, height: newValue.second.second)
        }
    }
    
    var body: some View {
        ZStack {
            self.canvasColor
            
            Canvas(opaque: false, rendersAsynchronously: true) { context, size in
                guard size.width > 10, size.height > 10 else { return }
                let tile: CGFloat = 1024
                let parallaxFactors: [CGFloat] = [0.12, 0.30, 0.55]
                let maxStarOpacity: CGFloat = self.isDark ? 0.55 : 0.22
                let starBaseColor = self.isDark ? Color.white : self.accentColor
                
                for star in Self.seededStars {
                    let factor = parallaxFactors[star.layer]
                    let rawX = (star.x * tile + self.panOffset.width * factor).truncatingRemainder(dividingBy: tile)
                    let rawY = (star.y * tile + self.panOffset.height * factor).truncatingRemainder(dividingBy: tile)
                    let baseX = rawX < 0 ? rawX + tile : rawX
                    let baseY = rawY < 0 ? rawY + tile : rawY
                    let color = starBaseColor.opacity(star.alpha * maxStarOpacity)
                    
                    var y = baseY
                    while y < size.height {
                        var x = baseX
                        while x < size.width {
                            let rect = CGRect(x: x - star.radius, y: y - star.radius, width: star.radius * 2, height: star.radius * 2)
                            context.fill(Circle().path(in: rect), with: .color(color))
                            x += tile
                        }
                        y += tile
                    }
                }
                
                let nebulaOpacity: CGFloat = self.isDark ? 0.16 : 0.10
                let nebulaR = max(120, 190 * min(1.35, max(0.7, self.zoomScale)))
                for glow in self.clusterGlows {
                    let center = CGPoint(
                        x: self.viewportCenter.x + self.panOffset.width + glow.worldPoint.x * self.zoomScale,
                        y: self.viewportCenter.y + self.panOffset.height + glow.worldPoint.y * self.zoomScale
                    )
                    guard center.x > -nebulaR, center.x < size.width + nebulaR,
                          center.y > -nebulaR, center.y < size.height + nebulaR
                    else { continue }
                    let circleRect = CGRect(x: center.x - nebulaR, y: center.y - nebulaR, width: nebulaR * 2, height: nebulaR * 2)
                    context.fill(
                        Circle().path(in: circleRect),
                        with: .radialGradient(
                            Gradient(colors: [glow.color.opacity(nebulaOpacity), .clear]),
                            center: center,
                            startRadius: 8,
                            endRadius: nebulaR
                        )
                    )
                }
            }
            .drawingGroup()
        }
    }
}


// `StarMapQuickLookOverlay`, `StarMapQuickLookController`, and `StarMapQuickLookGeometry`
// live in `StarMapQuickLookOverlay.swift`.


// MARK: - Floating Search Results & Snippets HUD (Shared by Document Center & Weekly Report Center)

struct StarMapSearchField: View {
    
    let placeholder: String
    @Binding var text: String
    let hitCount: Int
    let showCount: Bool
    var isFocused: FocusState<Bool>.Binding
    let tokens: StudioColorTokens
    let onSubmit: () -> Void
    let onClear: () -> Void
    
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(self.isFocused.wrappedValue ? self.tokens.primaryInk : self.tokens.primaryInk.opacity(0.45))
            TextField(self.placeholder, text: self.$text)
                .textFieldStyle(.plain)
                .font(.system(size: 12.5))
                .focused(self.isFocused)
                .frame(minWidth: 180, maxWidth: 240)
                .onSubmit(self.onSubmit)
            if self.showCount {
                Text("\(self.hitCount) 篇")
                    .font(.system(size: 10.5, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(self.tokens.accentText)
                    .padding(.horizontal, 6)
                    .frame(height: 18)
                    .background(self.tokens.positivePillBg, in: Capsule())
            }
            if !self.text.isEmpty {
                Button(action: self.onClear) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11.5))
                        .foregroundStyle(self.tokens.primaryInk.opacity(0.42))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 28)
        .background(self.tokens.inset, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(self.isFocused.wrappedValue ? self.tokens.hairlineStrong : self.tokens.hairline, lineWidth: 0.85)
        )
    }
}


struct StarMapSearchResultsHUD: View {
    
    let hits: [StarMapSearchHit]
    let selectedID: String?
    let isCollapsed: Bool
    let tokens: StudioColorTokens
    let onToggleCollapse: () -> Void
    let onSelectHit: (String) -> Void
    let onPreviewHit: (String) -> Void
    let onOpenHit: (String) -> Void
    
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(self.tokens.accent)
                
                Text("全文匹配 · \(self.hits.count) 篇")
                    .font(.system(size: 12, weight: .semibold).monospacedDigit())
                    .foregroundStyle(self.tokens.primaryInk)
                
                Spacer(minLength: 4)
                
                Button(action: self.onToggleCollapse) {
                    Image(systemName: self.isCollapsed ? "chevron.down" : "chevron.up")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(self.tokens.primaryInk.opacity(0.60))
                        .frame(width: 24, height: 24)
                        .background(self.tokens.inset, in: Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .pointerStyle(.link)
            }
            .padding(.horizontal, 12)
            .frame(height: 36)
            
            if !self.isCollapsed {
                Rectangle()
                    .fill(self.tokens.hairline)
                    .frame(height: 1)
                
                if self.hits.isEmpty {
                    Text("无匹配")
                        .font(.system(size: 11.5))
                        .foregroundStyle(self.tokens.primaryInk.opacity(0.55))
                        .padding(14)
                } else {
                    ScrollView(.vertical, showsIndicators: true) {
                        LazyVStack(spacing: 6) {
                            ForEach(self.hits) { hit in
                                let isSelected = (self.selectedID == hit.id)
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack(spacing: 6) {
                                        Circle()
                                            .fill(isSelected ? self.tokens.accent : self.tokens.primaryInk.opacity(0.32))
                                            .frame(width: 6, height: 6)
                                        
                                        Text(hit.title)
                                            .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                                            .foregroundStyle(self.tokens.primaryInk)
                                            .fixedSize(horizontal: false, vertical: true)
                                        
                                        Spacer(minLength: 4)
                                        
                                        Text("命中 \(hit.totalHits) 处")
                                            .font(.system(size: 9.5, weight: .semibold, design: .rounded).monospacedDigit())
                                            .foregroundStyle(self.tokens.accentText)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(self.tokens.positivePillBg, in: Capsule())
                                        
                                        Button {
                                            self.onPreviewHit(hit.id)
                                        } label: {
                                            Image(systemName: "eye")
                                                .font(.system(size: 10.5, weight: .medium))
                                                .foregroundStyle(self.tokens.primaryInk.opacity(0.70))
                                                .frame(width: 22, height: 22)
                                                .background(self.tokens.inset, in: Circle())
                                        }
                                        .buttonStyle(.plain)
                                        .pointerStyle(.link)
                                        .help("空格预览")
                                    }
                                    
                                    if let snippet = hit.snippet, !snippet.isEmpty {
                                        Text(snippet)
                                            .font(.system(size: 11))
                                            .foregroundStyle(self.tokens.primaryInk.opacity(0.68))
                                            .lineLimit(2)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                    
                                    Text("\(hit.categoryLabel) · \(hit.metaLabel)")
                                        .font(.system(size: 10, design: .rounded).monospacedDigit())
                                        .foregroundStyle(self.tokens.primaryInk.opacity(0.45))
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(isSelected ? self.tokens.accent.opacity(self.tokens.isDark ? 0.18 : 0.10) : self.tokens.inset)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .strokeBorder(isSelected ? self.tokens.accent.opacity(0.55) : Color.clear, lineWidth: 0.9)
                                )
                                .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                .onTapGesture(count: 2) {
                                    self.onOpenHit(hit.id)
                                }
                                .onTapGesture(count: 1) {
                                    self.onSelectHit(hit.id)
                                }
                            }
                        }
                        .padding(8)
                    }
                    .frame(maxHeight: 272)
                }
            }
        }
        .frame(width: 332)
        .background(self.tokens.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(self.tokens.hairlineStrong, lineWidth: 1)
        )
        .shadow(color: self.tokens.cardShadow, radius: 14, y: 6)
    }
}


// MARK: - Scheduled Nightly AI Document Organizer (凌晨 3 点自动重命名 · 星图整理 · 总结干了啥 · 预测要干啥)

@MainActor @Observable final class ScheduledAIDocumentOrganizer {
    
    enum ScheduleFrequency: String, CaseIterable, Identifiable, Sendable {
        case daily
        case weekdays
        case weekends
        
        var id: String { self.rawValue }
        
        var title: String {
            switch self {
                case .daily: AppLanguage.text("每天", en: "Daily")
                case .weekdays: AppLanguage.text("工作日", en: "Weekdays")
                case .weekends: AppLanguage.text("周末", en: "Weekends")
            }
        }
        
        func matches(_ date: Date, calendar: Calendar = .current) -> Bool {
            let weekday = calendar.component(.weekday, from: date) // 1 = Sun ... 7 = Sat
            switch self {
                case .daily: return true
                case .weekdays: return (2...6).contains(weekday)
                case .weekends: return weekday == 1 || weekday == 7
            }
        }
    }
    
    struct OrganizeReport: Sendable, Equatable {
        let renamedCount: Int
        let regroupedCount: Int
        let groupCount: Int
        let relationCount: Int
        let doneTodayCount: Int
        let predictionCount: Int
        let usedAI: Bool
        let summaryText: String
    }
    
    static let shared = ScheduledAIDocumentOrganizer()
    static let didCompleteOrganizeNotification = Notification.Name("ScheduledAIDocumentOrganizerDidComplete")
    
    private let database: CotLocalDatabase
    private let analytics: AnalyticsManager
    private var schedulerTask: Task<Void, Never>?
    private var wakeObserver: NSObjectProtocol?
    
    private var suppressAutoSlotStamp = false
    
    var isEnabled: Bool {
        didSet {
            guard oldValue != self.isEnabled else { return }
            self.database.set(self.isEnabled ? "1" : "0", forKey: CotLocalDatabase.ConfigKey.aiScheduledOrganizeEnabled)
            if self.isEnabled && !self.suppressAutoSlotStamp {
                self.markPassedSlotAsHandledIfNeeded(now: Date())
            }
        }
    }
    
    var frequency: ScheduleFrequency {
        didSet {
            guard oldValue != self.frequency else { return }
            self.database.set(self.frequency.rawValue, forKey: CotLocalDatabase.ConfigKey.aiScheduledOrganizeFrequency)
            if self.isEnabled && !self.suppressAutoSlotStamp {
                self.markPassedSlotAsHandledIfNeeded(now: Date())
            }
        }
    }
    
    var renameUntitledEnabled: Bool {
        didSet {
            guard oldValue != self.renameUntitledEnabled else { return }
            self.database.set(self.renameUntitledEnabled ? "1" : "0", forKey: CotLocalDatabase.ConfigKey.aiScheduledOrganizeRenameUntitled)
        }
    }
    
    var organizeStarMapEnabled: Bool {
        didSet {
            guard oldValue != self.organizeStarMapEnabled else { return }
            self.database.set(self.organizeStarMapEnabled ? "1" : "0", forKey: CotLocalDatabase.ConfigKey.aiScheduledOrganizeStarMap)
        }
    }
    
    var refreshDashboardEnabled: Bool {
        didSet {
            guard oldValue != self.refreshDashboardEnabled else { return }
            self.database.set(self.refreshDashboardEnabled ? "1" : "0", forKey: CotLocalDatabase.ConfigKey.aiScheduledOrganizeRefreshDashboard)
        }
    }
    
    var catchUpOnWakeEnabled: Bool {
        didSet {
            guard oldValue != self.catchUpOnWakeEnabled else { return }
            self.database.set(self.catchUpOnWakeEnabled ? "1" : "0", forKey: CotLocalDatabase.ConfigKey.aiScheduledOrganizeCatchUpOnWake)
        }
    }
    
    var hasAnyStepEnabled: Bool {
        self.renameUntitledEnabled || self.organizeStarMapEnabled || self.refreshDashboardEnabled
    }
    
    func setEnabled(_ enabled: Bool, now: Date = Date()) {
        self.suppressAutoSlotStamp = true
        self.isEnabled = enabled
        self.suppressAutoSlotStamp = false
        if enabled {
            self.markPassedSlotAsHandledIfNeeded(now: now)
        }
    }
    
    private(set) var scheduledHour: Int
    private(set) var scheduledMinute: Int
    private(set) var lastCycleKey: String
    private(set) var lastSummary: String
    private(set) var isRunning: Bool = false
    
    private static var isRunningUnitTests: Bool {
        let env = ProcessInfo.processInfo.environment
        return NSClassFromString("XCTestCase") != nil
            || env["XCTestConfigurationFilePath"] != nil
            || env["XCTestBundlePath"] != nil
    }
    
    private static let summaryStampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "M/d HH:mm"
        return f
    }()
    
    init(database: CotLocalDatabase = .shared, analytics: AnalyticsManager = .shared) {
        self.database = database
        self.analytics = analytics
        
        let rawEnabled = database.string(forKey: CotLocalDatabase.ConfigKey.aiScheduledOrganizeEnabled)
        // Default ON at 03:00 AM unless user explicitly toggled it off ("0")
        self.isEnabled = (rawEnabled != "0")
        
        let rawFreq = database.string(forKey: CotLocalDatabase.ConfigKey.aiScheduledOrganizeFrequency)
        self.frequency = ScheduleFrequency(rawValue: rawFreq) ?? .daily
        
        self.renameUntitledEnabled = database.string(forKey: CotLocalDatabase.ConfigKey.aiScheduledOrganizeRenameUntitled) != "0"
        self.organizeStarMapEnabled = database.string(forKey: CotLocalDatabase.ConfigKey.aiScheduledOrganizeStarMap) != "0"
        self.refreshDashboardEnabled = database.string(forKey: CotLocalDatabase.ConfigKey.aiScheduledOrganizeRefreshDashboard) != "0"
        self.catchUpOnWakeEnabled = database.string(forKey: CotLocalDatabase.ConfigKey.aiScheduledOrganizeCatchUpOnWake) != "0"
        
        let rawHour = Int(database.string(forKey: CotLocalDatabase.ConfigKey.aiScheduledOrganizeHour))
        let rawMinute = Int(database.string(forKey: CotLocalDatabase.ConfigKey.aiScheduledOrganizeMinute))
        self.scheduledHour = min(23, max(0, rawHour ?? 3))
        self.scheduledMinute = min(59, max(0, rawMinute ?? 0))
        self.lastCycleKey = database.string(forKey: CotLocalDatabase.ConfigKey.aiScheduledOrganizeLastCycleKey)
        self.lastSummary = database.string(forKey: CotLocalDatabase.ConfigKey.aiScheduledOrganizeLastSummary)
        
        if rawEnabled.isEmpty {
            database.set("1", forKey: CotLocalDatabase.ConfigKey.aiScheduledOrganizeEnabled)
            database.set("\(self.scheduledHour)", forKey: CotLocalDatabase.ConfigKey.aiScheduledOrganizeHour)
            database.set("\(self.scheduledMinute)", forKey: CotLocalDatabase.ConfigKey.aiScheduledOrganizeMinute)
            // Avoid an immediate midday run on very first install; wait cleanly for the next 03:00 slot.
            self.markPassedSlotAsHandledIfNeeded(now: Date())
        }
    }
    
    var formattedScheduledTime: String {
        String(format: "%02d:%02d", self.scheduledHour, self.scheduledMinute)
    }
    
    func nextScheduledLabel(now: Date = Date(), calendar: Calendar = .current) -> String {
        guard self.isEnabled, self.hasAnyStepEnabled else {
            return AppLanguage.text("已暂停", en: "Paused")
        }
        let timeText = self.formattedScheduledTime
        let chineseWeekdays = ["周日", "周一", "周二", "周三", "周四", "周五", "周六"]
        let englishWeekdays = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        
        for dayOffset in 0...7 {
            guard let candidateDay = calendar.date(byAdding: .day, value: dayOffset, to: now),
                  self.frequency.matches(candidateDay, calendar: calendar),
                  let slot = calendar.date(
                      bySettingHour: self.scheduledHour,
                      minute: self.scheduledMinute,
                      second: 0,
                      of: candidateDay
                  )
            else { continue }
            
            let key = Self.cycleKey(for: slot, hour: self.scheduledHour, minute: self.scheduledMinute, calendar: calendar)
            if slot > now && key != self.lastCycleKey {
                if dayOffset == 0 {
                    return AppLanguage.text("下次 今日 \(timeText)", en: "Next Today \(timeText)")
                } else if dayOffset == 1 {
                    return AppLanguage.text("下次 明日 \(timeText)", en: "Next Tomorrow \(timeText)")
                } else {
                    let wdIdx = max(0, min(6, calendar.component(.weekday, from: slot) - 1))
                    return AppLanguage.text("下次 \(chineseWeekdays[wdIdx]) \(timeText)", en: "Next \(englishWeekdays[wdIdx]) \(timeText)")
                }
            }
        }
        return AppLanguage.text("下次 \(timeText)", en: "Next \(timeText)")
    }
    
    var scheduledDateBindingValue: Date {
        get {
            Calendar.current.date(bySettingHour: self.scheduledHour, minute: self.scheduledMinute, second: 0, of: Date()) ?? Date()
        }
        set {
            let comps = Calendar.current.dateComponents([.hour, .minute], from: newValue)
            self.updateScheduledTime(hour: comps.hour ?? 3, minute: comps.minute ?? 0)
        }
    }
    
    func updateScheduledTime(hour: Int, minute: Int, now: Date = Date()) {
        let clampedH = min(23, max(0, hour))
        let clampedM = min(59, max(0, minute))
        guard clampedH != self.scheduledHour || clampedM != self.scheduledMinute else { return }
        self.scheduledHour = clampedH
        self.scheduledMinute = clampedM
        self.database.set("\(clampedH)", forKey: CotLocalDatabase.ConfigKey.aiScheduledOrganizeHour)
        self.database.set("\(clampedM)", forKey: CotLocalDatabase.ConfigKey.aiScheduledOrganizeMinute)
        self.markPassedSlotAsHandledIfNeeded(now: now)
    }
    
    /// Marks an already-passed slot earlier today (>90s ago) as handled when the user edits schedule settings interactively,
    /// so the job runs at the next upcoming scheduled time instead of firing mid-configuration.
    private func markPassedSlotAsHandledIfNeeded(now: Date, calendar: Calendar = .current) {
        guard let todayTarget = calendar.date(bySettingHour: self.scheduledHour, minute: self.scheduledMinute, second: 0, of: now) else { return }
        if now.timeIntervalSince(todayTarget) > 90 {
            let key = Self.cycleKey(for: todayTarget, hour: self.scheduledHour, minute: self.scheduledMinute, calendar: calendar)
            self.lastCycleKey = key
            self.database.set(key, forKey: CotLocalDatabase.ConfigKey.aiScheduledOrganizeLastCycleKey)
        }
    }
    
    static func cycleKey(for slotDate: Date, hour: Int, minute: Int, calendar: Calendar = .current) -> String {
        let comps = calendar.dateComponents([.year, .month, .day], from: slotDate)
        return String(format: "%04d-%02d-%02d@%02d:%02d", comps.year ?? 0, comps.month ?? 0, comps.day ?? 0, hour, minute)
    }
    
    /// Returns the cycle key if the scheduled time is currently due (or within a 12-hour sleep-wake catch-up window)
    /// and has not yet been executed for that cycle.
    func dueCycleKey(now: Date = Date(), calendar: Calendar = .current) -> String? {
        guard self.isEnabled, self.hasAnyStepEnabled else { return nil }
        guard let todayTarget = calendar.date(bySettingHour: self.scheduledHour, minute: self.scheduledMinute, second: 0, of: now) else {
            return nil
        }
        let latestTarget: Date
        if now >= todayTarget {
            latestTarget = todayTarget
        } else if let yesterdayTarget = calendar.date(byAdding: .day, value: -1, to: todayTarget) {
            latestTarget = yesterdayTarget
        } else {
            return nil
        }
        
        guard self.frequency.matches(latestTarget, calendar: calendar) else { return nil }
        
        let maxLag: TimeInterval = self.catchUpOnWakeEnabled ? (12 * 3600) : 120
        let lag = now.timeIntervalSince(latestTarget)
        guard lag >= 0, lag <= maxLag else { return nil }
        
        let key = Self.cycleKey(for: latestTarget, hour: self.scheduledHour, minute: self.scheduledMinute, calendar: calendar)
        guard key != self.lastCycleKey else { return nil }
        return key
    }
    
    func startScheduler() {
        guard !Self.isRunningUnitTests, self.schedulerTask == nil else { return }
        
        self.wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(8))
                await self?.evaluateScheduleAndRunIfNeeded()
            }
        }
        
        self.schedulerTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(20))
            while !Task.isCancelled {
                await self?.evaluateScheduleAndRunIfNeeded()
                try? await Task.sleep(for: .seconds(30))
            }
        }
    }
    
    func stopScheduler() {
        self.schedulerTask?.cancel()
        self.schedulerTask = nil
        if let wakeObserver = self.wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
            self.wakeObserver = nil
        }
    }
    
    func evaluateScheduleAndRunIfNeeded(now: Date = Date()) async {
        guard !self.isRunning, let cycleKey = self.dueCycleKey(now: now) else { return }
        _ = await self.runOrganizePipeline(markCycleKey: cycleKey, referenceDate: now)
    }
    
    /// Executes all 4 stages:
    /// 1) Rename generic/draft titles, 2) Organize Star-Map groups & relation edges,
    /// 3) Synthesize "干了啥", 4) Predict "要干啥".
    @discardableResult
    func runOrganizePipeline(
        markCycleKey: String? = nil,
        referenceDate: Date = Date(),
        allowRemoteAI: Bool = true
    ) async -> OrganizeReport {
        if self.isRunning {
            return OrganizeReport(
                renamedCount: 0,
                regroupedCount: 0,
                groupCount: self.database.documentGroups.count,
                relationCount: 0,
                doneTodayCount: self.analytics.doneTodayPoints.count,
                predictionCount: self.analytics.actionPredictions.count,
                usedAI: false,
                summaryText: self.lastSummary
            )
        }
        
        self.isRunning = true
        defer { self.isRunning = false }
        
        struct CandidateDoc {
            let canonicalID: String
            let dbRecordID: String
            let title: String
            let filePath: String?
            let syntax: String
            let content: String
            let currentGroup: String
            let updatedAt: Date
            let liveDoc: Document?
        }
        
        var candidates: [CandidateDoc] = []
        var seenCanonical = Set<String>()
        let trashedKeys = Set(
            self.database.trashedDocuments.map {
                DocumentCenterState.canonicalKey(filePath: $0.filePath, rawID: $0.id)
            }
        )
        
        if self.database === CotLocalDatabase.shared {
            var dbLookup: [String: StoredDocumentRecord] = [:]
            for rec in self.database.documents {
                let k = DocumentCenterState.canonicalKey(filePath: rec.filePath, rawID: rec.id)
                if dbLookup[k] == nil { dbLookup[k] = rec }
            }
            for case let doc as Document in NSDocumentController.shared.documents where !doc.databaseDocumentID.hasPrefix("weekly:") {
                let filePath = doc.fileURL?.standardizedFileURL.path(percentEncoded: false)
                let content = doc.textStorage.string
                if filePath == nil, content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    continue
                }
                let canonical = DocumentCenterState.canonicalKey(filePath: filePath, rawID: doc.databaseDocumentID)
                guard !trashedKeys.contains(canonical), seenCanonical.insert(canonical).inserted else { continue }
                let existing = dbLookup[canonical]
                let fallbackID = filePath ?? (doc.databaseDocumentID.hasPrefix("doc:") ? doc.databaseDocumentID : "doc:\(doc.databaseDocumentID)")
                candidates.append(CandidateDoc(
                    canonicalID: canonical,
                    dbRecordID: existing?.id ?? fallbackID,
                    title: doc.displayName,
                    filePath: filePath,
                    syntax: doc.syntaxName,
                    content: content,
                    currentGroup: existing?.groupName ?? "",
                    updatedAt: existing?.updatedAt ?? referenceDate,
                    liveDoc: doc
                ))
            }
        }
        
        for rec in self.database.documents where !rec.id.hasPrefix("weekly:") {
            let canonical = DocumentCenterState.canonicalKey(filePath: rec.filePath, rawID: rec.id)
            guard !trashedKeys.contains(canonical), seenCanonical.insert(canonical).inserted else { continue }
            candidates.append(CandidateDoc(
                canonicalID: canonical,
                dbRecordID: rec.id,
                title: rec.title,
                filePath: rec.filePath,
                syntax: rec.syntax,
                content: rec.content,
                currentGroup: rec.groupName,
                updatedAt: rec.updatedAt,
                liveDoc: nil
            ))
        }
        
        // Stage 1 & 2: Data Funnel (Junk/Garbled Cleanup + Duplicate Merge) + Sharded Star-Map Organization
        var renamedCount = 0
        var regroupedCount = 0
        var deletedJunkCount = 0
        var mergedDupCount = 0
        var usedAI = false
        
        if !candidates.isEmpty && (self.renameUntitledEnabled || self.organizeStarMapEnabled) {
            let funnelInputs = candidates.map { item in
                OrganizeFunnelInput(
                    id: item.canonicalID,
                    dbRecordID: item.dbRecordID,
                    title: item.title,
                    filePath: item.filePath,
                    syntax: item.syntax,
                    currentGroup: item.currentGroup,
                    content: item.content,
                    updatedAt: item.updatedAt,
                    isOpenNow: item.liveDoc != nil,
                    isUntitled: DocumentCenterAgentOrganizer.isGenericUntitled(item.title, hasFilePath: item.filePath != nil)
                )
            }
            let byID = Dictionary(uniqueKeysWithValues: candidates.map { ($0.canonicalID, $0) })
            let fullPlan = await DocumentOrganizeFunnel.runFullPipeline(
                items: funnelInputs,
                existingGroups: self.database.documentGroups,
                allowRemoteAI: allowRemoteAI,
                analyticsFeature: "scheduledNightlyOrganize"
            )
            usedAI = fullPlan.usedAI
            
            let allowRename = self.renameUntitledEnabled
            let allowRegroup = self.organizeStarMapEnabled
            let mergedByPrimaryID = Dictionary(uniqueKeysWithValues: fullPlan.funnel.mergeClusters.map { ($0.primary.id, $0) })
            
            self.database.withTransaction {
                if allowRegroup {
                    for junk in fullPlan.funnel.junkToDelete {
                        guard let item = byID[junk.item.id] else { continue }
                        self.database.permanentlyDeleteDocument(id: item.dbRecordID, filePath: item.filePath)
                        deletedJunkCount += 1
                    }
                    
                    for cluster in fullPlan.funnel.mergeClusters {
                        guard let primaryItem = byID[cluster.primary.id] else { continue }
                        if let liveDoc = primaryItem.liveDoc {
                            if cluster.mergedContent != liveDoc.textStorage.string {
                                liveDoc.textStorage.replaceCharacters(
                                    in: NSRange(location: 0, length: liveDoc.textStorage.length),
                                    with: cluster.mergedContent
                                )
                                if liveDoc.fileURL == nil { liveDoc.updateChangeCount(.changeCleared) }
                            }
                            if cluster.bestTitle != primaryItem.title, liveDoc.fileURL == nil {
                                liveDoc.displayName = cluster.bestTitle
                                liveDoc.isExplicitlyNamed = true
                            }
                        }
                        if cluster.bestTitle != primaryItem.title {
                            renamedCount += 1
                        }
                        self.database.saveDocument(
                            id: primaryItem.dbRecordID,
                            title: cluster.bestTitle,
                            filePath: primaryItem.filePath,
                            syntax: primaryItem.syntax,
                            content: cluster.mergedContent,
                            groupName: cluster.bestGroup
                        )
                        for dup in cluster.duplicates {
                            guard let dupItem = byID[dup.id] else { continue }
                            self.database.permanentlyDeleteDocument(id: dupItem.dbRecordID, filePath: dupItem.filePath)
                            mergedDupCount += 1
                        }
                    }
                }
                
                for assignment in fullPlan.assignments {
                    guard let item = byID[assignment.id] else { continue }
                    let mergedCluster = mergedByPrimaryID[assignment.id]
                    let effectiveTitle = mergedCluster?.bestTitle ?? item.title
                    let effectiveGroup = mergedCluster?.bestGroup ?? item.currentGroup
                    let effectiveContent = mergedCluster?.mergedContent ?? item.content
                    
                    let targetGroup = assignment.group
                    let wantsRename: String? = {
                        guard allowRename,
                              let suggested = assignment.suggestedTitle,
                              !suggested.isEmpty,
                              suggested != effectiveTitle,
                              item.filePath == nil,
                              (fullPlan.usedAI || DocumentCenterAgentOrganizer.isWeakScratchTitle(effectiveTitle, hasFilePath: false))
                        else { return nil }
                        return suggested
                    }()
                    
                    let groupChanged = allowRegroup && (targetGroup != effectiveGroup)
                    guard groupChanged || wantsRename != nil else { continue }
                    
                    if let newTitle = wantsRename {
                        if let liveDoc = item.liveDoc {
                            _ = try? WorkspaceOrganizer.renameDocument(liveDoc, to: newTitle, reloadAfter: false)
                        } else if item.filePath == nil {
                            self.database.renameDocument(
                                oldID: item.dbRecordID,
                                oldFilePath: nil,
                                newID: item.dbRecordID,
                                newTitle: newTitle,
                                newFilePath: nil,
                                reloadAfter: false
                            )
                        }
                        renamedCount += 1
                    }
                    
                    if groupChanged {
                        self.database.assignDocumentGroup(
                            id: item.dbRecordID,
                            filePath: item.filePath,
                            groupName: targetGroup,
                            fallbackTitle: wantsRename ?? effectiveTitle,
                            fallbackSyntax: item.syntax,
                            fallbackContent: effectiveContent,
                            reloadAfter: false
                        )
                        regroupedCount += 1
                    }
                }
            }
            
            if renamedCount > 0 || regroupedCount > 0 || deletedJunkCount > 0 || mergedDupCount > 0 {
                self.database.reloadDocuments()
            }
        }
        
        // Refresh semantic relation graph cache for clean Star-Map connections
        let updatedDocs = self.database.documents.filter { !$0.id.hasPrefix("weekly:") }
        let relationCount: Int = if self.organizeStarMapEnabled {
            StarMapRelationEngine.buildRelations(
                for: updatedDocs.map { rec in
                    let folder = rec.filePath.map { URL(filePath: $0).deletingLastPathComponent().path(percentEncoded: false) }
                    return StarMapRelationEngine.CorpusDocument(
                        id: DocumentCenterState.canonicalKey(filePath: rec.filePath, rawID: rec.id),
                        title: rec.title,
                        group: rec.groupName,
                        folderPath: folder,
                        content: rec.content,
                        sortTimestamp: rec.updatedAt.timeIntervalSince1970
                    )
                }
            ).count
        } else {
            0
        }
        
        // Stage 3: Synthesize "干了啥" (Daily Digest + Lively Commentary) & Stage 4: Predict "要干啥"
        if self.refreshDashboardEnabled {
            if allowRemoteAI {
                await self.analytics.refreshDailyDigest(force: true)
                await self.analytics.refreshDoneTodayCommentary(force: true)
                await self.analytics.refreshActionPredictions(force: true)
            } else {
                self.analytics.loadDoneTodayCommentaryFromDatabase()
                self.analytics.loadActionPredictionsFromDatabase()
            }
        }
        
        let activeGroups = Set(updatedDocs.map(\.groupName).filter { !$0.isEmpty })
        let stamp = Self.summaryStampFormatter.string(from: referenceDate)
        var summaryParts: [String] = ["\(stamp) 已完成"]
        if renamedCount > 0 {
            summaryParts.append("重命名 \(renamedCount) 篇")
        }
        if self.organizeStarMapEnabled {
            summaryParts.append("星图 \(max(1, activeGroups.count)) 组")
        }
        if self.refreshDashboardEnabled {
            summaryParts.append("已更新看板")
        }
        let summary = summaryParts.joined(separator: " · ")
        
        if let cycleKey = markCycleKey {
            self.lastCycleKey = cycleKey
            self.database.set(cycleKey, forKey: CotLocalDatabase.ConfigKey.aiScheduledOrganizeLastCycleKey)
        }
        self.lastSummary = summary
        self.database.set(summary, forKey: CotLocalDatabase.ConfigKey.aiScheduledOrganizeLastSummary)
        
        NotificationCenter.default.post(name: Self.didCompleteOrganizeNotification, object: self)
        
        return OrganizeReport(
            renamedCount: renamedCount,
            regroupedCount: regroupedCount,
            groupCount: activeGroups.count,
            relationCount: relationCount,
            doneTodayCount: self.analytics.doneTodayPoints.count,
            predictionCount: self.analytics.actionPredictions.count,
            usedAI: usedAI || self.analytics.doneTodayFromAI || self.analytics.actionPredictionsFromAI,
            summaryText: summary
        )
    }
}


// MARK: - Dedicated Scheduled Tasks Settings Pane (Less is More · Zero Clutter)

struct ScheduledAIOrganizeSettingsCard: View {
    
    var isEmbeddedInGroupCard: Bool = false
    
    @Environment(\.colorScheme) private var colorScheme
    @State private var organizer = ScheduledAIDocumentOrganizer.shared
    @State private var justCompleted = false
    
    private static let scheduleHours: [Int] = [0, 3, 6, 9, 12, 15, 18, 21, 23]
    
    private var isDark: Bool { self.colorScheme == .dark }
    
    private var cardSurface: Color {
        self.isDark ? Color.white.opacity(0.055) : Color.white
    }
    
    private var cardBorder: Color {
        self.isDark ? Color.white.opacity(0.075) : Color.black.opacity(0.06)
    }
    
    private var dividerColor: Color {
        self.isDark ? Color.white.opacity(0.07) : Color.black.opacity(0.06)
    }
    
    private var masterEnabledBinding: Binding<Bool> {
        Binding(
            get: { self.organizer.isEnabled },
            set: { enabled in
                self.organizer.isEnabled = enabled
                if enabled {
                    self.ensureDefaultStepsEnabled()
                }
            }
        )
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Row 1: Single effortless master switch
            HStack(spacing: 12) {
                Text(AppLanguage.text("自动整理文档", en: "Auto-Organize Documents"))
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(.primary)
                
                Spacer(minLength: 12)
                
                Toggle("", isOn: self.masterEnabledBinding)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 44)
            
            if self.organizer.isEnabled {
                self.rowDivider
                
                // Row 2: Single quiet schedule time menu (no preset strip or multi-menu clutter)
                HStack(spacing: 12) {
                    Text(AppLanguage.text("整理时间", en: "Schedule"))
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(.primary)
                    
                    Spacer(minLength: 12)
                    
                    Menu {
                        ForEach(Self.scheduleHours, id: \.self) { hour in
                            Button {
                                self.organizer.frequency = .daily
                                self.organizer.updateScheduledTime(hour: hour, minute: 0)
                            } label: {
                                Text(String(format: "%02d:00", hour))
                            }
                        }
                    } label: {
                        Text(AppLanguage.text(
                            "每日 \(self.organizer.formattedScheduledTime)",
                            en: "Daily \(self.organizer.formattedScheduledTime)"
                        ))
                        .font(.system(size: 12.5, weight: .regular).monospacedDigit())
                        .foregroundStyle(.secondary)
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .pointerStyle(.link)
                }
                .padding(.horizontal, 14)
                .frame(minHeight: 44)
            }
            
            self.rowDivider
            
            // Row 3: Quiet last-run status + native Run Now button (zero decorative icons)
            HStack(spacing: 12) {
                Text(
                    self.organizer.lastSummary.isEmpty
                        ? AppLanguage.text("尚未整理", en: "Not run yet")
                        : self.organizer.lastSummary
                )
                .font(.system(size: 12.5, weight: .regular))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
                
                Spacer(minLength: 12)
                
                if self.organizer.isRunning {
                    HStack(spacing: 6) {
                        ProgressView()
                            .controlSize(.small)
                        Text(AppLanguage.text("整理中…", en: "Running…"))
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Button(
                        self.justCompleted
                            ? AppLanguage.text("已完成", en: "Done")
                            : AppLanguage.text("立即整理", en: "Run Now")
                    ) {
                        self.ensureDefaultStepsEnabled()
                        Task {
                            _ = await self.organizer.runOrganizePipeline()
                            withAnimation(.easeOut(duration: 0.16)) {
                                self.justCompleted = true
                            }
                            try? await Task.sleep(for: .seconds(2.0))
                            withAnimation(.easeOut(duration: 0.2)) {
                                self.justCompleted = false
                            }
                        }
                    }
                    .controlSize(.small)
                }
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 44)
        }
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(self.cardSurface)
                .shadow(
                    color: self.isDark ? Color.clear : Color.black.opacity(0.025),
                    radius: 2,
                    y: 0.5
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(self.cardBorder, lineWidth: 0.5)
        )
        .animation(.easeInOut(duration: 0.18), value: self.organizer.isEnabled)
    }
    
    
    private var rowDivider: some View {
        Rectangle()
            .fill(self.dividerColor)
            .frame(height: 0.5)
            .padding(.leading, 14)
    }
    
    
    private func ensureDefaultStepsEnabled() {
        if !self.organizer.hasAnyStepEnabled {
            self.organizer.renameUntitledEnabled = true
            self.organizer.organizeStarMapEnabled = true
            self.organizer.refreshDashboardEnabled = true
        }
        self.organizer.catchUpOnWakeEnabled = true
    }
}
