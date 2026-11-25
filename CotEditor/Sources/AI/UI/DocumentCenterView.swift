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
        textView.textContainerInset = NSSize(width: 28, height: 22)
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
        let clusters: [PositionedCluster]
        let leaves: [PositionedLeaf]
        let bounds: CGRect
        let leafPositionsByID: [String: PositionedLeaf]
        let leafColumns: [LeafColumnKey: [PositionedLeaf]]
        
        init(
            hubPoint: CGPoint = .zero,
            usesTimelineSpine: Bool = false,
            clusters: [PositionedCluster],
            leaves: [PositionedLeaf],
            bounds: CGRect
        ) {
            self.hubPoint = hubPoint
            self.usesTimelineSpine = usesTimelineSpine
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
    
    struct Plan: Codable, Sendable, Equatable {
        let assignments: [Assignment]
    }
    
    
    /// Checks whether a document title is generic / placeholder and safe for Agent title cleanup.
    static func isGenericUntitled(_ title: String, hasFilePath: Bool) -> Bool {
        if hasFilePath { return false }
        let clean = title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if clean.isEmpty || clean.count == 1 { return true }
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
            let title: String? = item.suggestedTitle.flatMap { raw in
                let trimmed = raw
                    .replacingOccurrences(of: "/", with: "-")
                    .replacingOccurrences(of: ":", with: "-")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : String(trimmed.prefix(36))
            }
            sanitized.append(Assignment(id: item.id, group: group, suggestedTitle: title))
        }
        return sanitized.isEmpty ? nil : Plan(assignments: sanitized)
    }
    
    
    /// Fast deterministic local classifier used when AI is unconfigured or returns invalid JSON.
    static func buildLocalFallbackPlan(items: [InputItem], existingGroups: [String]) -> Plan {
        let codeSyntaxes: Set<String> = [
            "swift", "python", "javascript", "typescript", "json", "yaml", "toml",
            "html", "css", "sql", "shell script", "bash", "c", "c++", "rust", "go", "java", "ruby",
        ]
        
        var assignments: [Assignment] = []
        assignments.reserveCapacity(items.count)
        
        for item in items {
            let titleLower = item.title.lowercased()
            let syntaxLower = item.syntax.lowercased()
            let sampleLower = (item.title + "\n" + item.excerpt).lowercased()
            
            let resolvedGroup: String
            if !item.currentGroup.isEmpty && existingGroups.contains(item.currentGroup) {
                resolvedGroup = item.currentGroup
            } else if sampleLower.contains("会议") || sampleLower.contains("纪要") || sampleLower.contains("meeting") || sampleLower.contains("sync") {
                resolvedGroup = "会议纪要"
            } else if sampleLower.contains("方案") || sampleLower.contains("需求") || sampleLower.contains("prd") || sampleLower.contains("设计") || sampleLower.contains("规划") || sampleLower.contains("架构") {
                resolvedGroup = "项目方案"
            } else if sampleLower.contains("周报") || sampleLower.contains("日报") || sampleLower.contains("复盘") || sampleLower.contains("总结") || sampleLower.contains("todo") || sampleLower.contains("清单") {
                resolvedGroup = "工作清单"
            } else if syntaxLower == "json" || syntaxLower == "yaml" || syntaxLower == "toml" || syntaxLower == "xml" || syntaxLower == "csv" || titleLower.hasSuffix(".env") {
                resolvedGroup = "配置数据"
            } else if codeSyntaxes.contains(syntaxLower) || sampleLower.contains("func ") || sampleLower.contains("import ") || sampleLower.contains("class ") {
                resolvedGroup = "代码开发"
            } else if sampleLower.contains("api") || sampleLower.contains("bug") || sampleLower.contains("debug") || sampleLower.contains("文档") || sampleLower.contains("教程") || sampleLower.contains("笔记") {
                resolvedGroup = "技术笔记"
            } else {
                resolvedGroup = "日常记录"
            }
            
            let suggestedTitle: String? = item.isUntitled ? Self.deriveTitleFromExcerpt(item.excerpt) : nil
            assignments.append(Assignment(id: item.id, group: resolvedGroup, suggestedTitle: suggestedTitle))
        }
        return Plan(assignments: assignments)
    }
    
    
    private static func deriveTitleFromExcerpt(_ excerpt: String) -> String? {
        for rawLine in excerpt.components(separatedBy: .newlines) {
            let trimmed = rawLine
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "#*-•> "))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.count >= 2 else { continue }
            let clean = trimmed
                .replacingOccurrences(of: "/", with: "-")
                .replacingOccurrences(of: ":", with: "-")
            return String(clean.prefix(24))
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
        
        let validIDs = Set(items.map(\.id))
        if AIService.shared.isConfigured {
            let cappedItems = Array(items.prefix(80))
            let manifestLines = cappedItems.enumerated().map { idx, item -> String in
                let compactExcerpt = item.excerpt
                    .replacingOccurrences(of: "\n", with: " ")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .prefix(180)
                return """
                [\(idx + 1)] id="\(item.id)" | title="\(item.title)" | syntax="\(item.syntax)" | group="\(item.currentGroup)" | untitled=\(item.isUntitled ? "true" : "false") | snippet="\(compactExcerpt)"
                """
            }.joined(separator: "\n")
            
            let existingLine = existingGroups.isEmpty ? "无" : existingGroups.joined(separator: "、")
            let systemPrompt = """
            你是文档中心智能整理 Agent。请将用户的全部文档归类到清晰、精炼的分组中（2-6字中文分组名，总数控制在 3-7 个，优先复用合理的已有分组），并为未命名或含糊草稿标题提炼准确标题。
            规则：
            1. 仅返回严格合法的 JSON，不要输出任何额外解释或 Markdown 之外的文字。
            2. JSON 格式：{"assignments":[{"id":"原id","group":"分组名","suggestedTitle":"仅当untitled=true且能从正文提炼4-18字清晰标题时填写，否则为null"}]}
            3. 每个输入文档的 id 都必须出现在 assignments 中。
            """
            let userPrompt = """
            已有分组：\(existingLine)
            待整理文档（共 \(cappedItems.count) 篇）：
            \(manifestLines)
            """
            
            do {
                let raw = try await AIService.shared.chat(
                    [.system(systemPrompt), .user(userPrompt)],
                    analyticsFeature: analyticsFeature
                )
                if let parsed = Self.parsePlan(from: raw, validIDs: validIDs) {
                    return (parsed, true)
                }
            } catch {
                CotLogger.shared.error(category: .ai, "Document Center Agent organize fallback", error: error)
            }
        }
        
        return (Self.buildLocalFallbackPlan(items: items, existingGroups: existingGroups), false)
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
    var isAgentOrganizing: Bool = false
    var agentOrganizeSummary: String?
    var lastOrganizeUndoSnapshot: [OrganizeUndoEntry] = []
    var lastOrganizeCreatedGroups: [String] = []
    
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
    private var eventMonitor: Any?
    
    
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        self.teardownMonitor()
        guard self.window != nil else { return }
        self.eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel, .magnify]) { [weak self] event in
            guard let self,
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
    
    
    func makeNSView(context: Context) -> StarMapTrackpadEventMonitorNSView {
        let v = StarMapTrackpadEventMonitorNSView()
        v.onPan = self.onPan
        v.onZoom = self.onZoom
        return v
    }
    
    
    func updateNSView(_ nsView: StarMapTrackpadEventMonitorNSView, context: Context) {
        nsView.onPan = self.onPan
        nsView.onZoom = self.onZoom
    }
}


/// Reusable, GPU-accelerated, zero-overlap Structured Tree Star-Map canvas shared by Document Center & Weekly Report Center.
struct ConstellationStarMapView<ClusterMenu: View, LeafMenu: View>: View {
    
    let hubTitle: String
    let hubSubtitle: String
    let clusters: [StarMapClusterNode]
    let relations: [StarMapRelationEdge]
    let selectedLeafID: String?
    let focusedClusterID: String?
    let searchQuery: String
    let panRequestToken: Int
    let onSelectLeaf: (String) -> Void
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
        focusedClusterID: String?,
        searchQuery: String,
        panRequestToken: Int = 0,
        onSelectLeaf: @escaping (String) -> Void,
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
        self.focusedClusterID = focusedClusterID
        self.searchQuery = searchQuery
        self.panRequestToken = panRequestToken
        self.onSelectLeaf = onSelectLeaf
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
    @State private var hasAutoFitted = false
    @State private var cachedClustersSnapshot: [StarMapClusterNode] = []
    @State private var cachedLayout = StarMapLayoutEngine.LayoutResult(
        clusters: [],
        leaves: [],
        bounds: CGRect(x: -180, y: -140, width: 360, height: 280)
    )
    
    
    private static func computeLayout(for clusters: [StarMapClusterNode]) -> StarMapLayoutEngine.LayoutResult {
        let clusterIDs = clusters.map(\.id)
        let usesTimeline = clusters.contains(where: { $0.timelineLabel != nil })
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
        return StarMapLayoutEngine.compute(
            clusterIDs: clusterIDs,
            leafCountsByCluster: counts,
            collapsedClusterIDs: collapsed,
            leafIDsByCluster: leafIDsByCluster,
            usesTimelineSpine: usesTimeline
        )
    }
    
    
    private static func hasSameLayoutInputs(_ previous: [StarMapClusterNode], _ current: [StarMapClusterNode]) -> Bool {
        previous.contains(where: { $0.timelineLabel != nil }) == current.contains(where: { $0.timelineLabel != nil })
            && previous.elementsEqual(current) { previous, current in
                previous.id == current.id && previous.isCollapsed == current.isCollapsed
                    && (current.isCollapsed || previous.leaves.prefix(40).elementsEqual(current.leaves.prefix(40)) { $0.id == $1.id })
            }
    }
    
    
    var body: some View {
        let isDark = (self.colorScheme == .dark)
        let tokens = DashPalette.editorialTokens(isDark: isDark)
        let layout = (self.cachedClustersSnapshot == self.clusters || Self.hasSameLayoutInputs(self.cachedClustersSnapshot, self.clusters))
            ? self.cachedLayout
            : Self.computeLayout(for: self.clusters)
        let worldPad: CGFloat = 160
        let worldW = max(840, layout.bounds.width + worldPad * 2)
        let worldH = max(620, layout.bounds.height + worldPad * 2)
        
        GeometryReader { geo in
            let viewportCenter = CGPoint(x: geo.size.width * 0.5, y: geo.size.height * 0.5 + 8)
            
            ZStack {
                // 1. Static GPU-cached architectural backdrop
                StarMapStaticBackdropView(
                    canvasColor: tokens.canvasTop,
                    dotColor: tokens.architecturalDot,
                    accentColor: tokens.accent,
                    isDark: isDark
                )
                .ignoresSafeArea()
                .allowsHitTesting(false)
                
                // 2. Two-finger trackpad scroll & pinch zoom catcher
                StarMapTrackpadPanZoomRepresentable(
                    onPan: { dx, dy in
                        self.panOffset.width += dx
                        self.panOffset.height += dy
                    },
                    onZoom: { factor in
                        let next = min(1.80, max(0.38, self.zoomScale * factor))
                        if abs(next - self.zoomScale) > 0.001 {
                            self.zoomScale = next
                        }
                    }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                
                // 3. Viewport-sized crisp vector tree & focused relation connectors (1/10th VRAM of world Canvas!)
                StarMapViewportConnectorsCanvas(
                    clusters: self.clusters,
                    relations: self.relations,
                    layout: layout,
                    selectedLeafID: self.selectedLeafID,
                    focusedClusterID: self.focusedClusterID,
                    viewportCenter: viewportCenter,
                    panOffset: self.panOffset,
                    zoomScale: self.zoomScale,
                    tokens: tokens
                )
                .allowsHitTesting(false)
                
                // 4. Pure Equatable Node Cards Stage (zero Canvas inside, zero hover state churn!)
                StarMapWorldStageView(
                    hubTitle: self.hubTitle,
                    hubSubtitle: self.hubSubtitle,
                    clusters: self.clusters,
                    relations: self.relations,
                    layout: layout,
                    selectedLeafID: self.selectedLeafID,
                    focusedClusterID: self.focusedClusterID,
                    isDark: isDark,
                    tokens: tokens,
                    worldW: worldW,
                    worldH: worldH,
                    onSelectLeaf: self.onSelectLeaf,
                    onDoubleClickLeaf: self.onDoubleClickLeaf,
                    onToggleCluster: self.onToggleCluster,
                    clusterContextMenu: self.clusterContextMenu,
                    leafContextMenu: self.leafContextMenu
                )
                .equatable()
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
                                withAnimation(.snappy(duration: 0.18, extraBounce: 0)) {
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
                            .help("重置视角以适配全部节点")
                            
                            Button {
                                withAnimation(.snappy(duration: 0.18, extraBounce: 0)) {
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
                        }
                        if let base = self.pinchBaseZoom {
                            self.zoomScale = min(1.80, max(0.38, base * value))
                        }
                    }
                    .onEnded { _ in
                        self.pinchBaseZoom = nil
                    }
            )
            .onAppear {
                self.cachedLayout = layout
                self.cachedClustersSnapshot = self.clusters
                if !self.hasAutoFitted && geo.size.width > 100 {
                    self.hasAutoFitted = true
                    self.fitViewport(bounds: layout.bounds, size: geo.size, animated: false)
                }
            }
            .onChange(of: self.clusters) { _, nextClusters in
                self.cachedLayout = layout
                self.cachedClustersSnapshot = nextClusters
            }
            .onChange(of: geo.size) { _, newSize in
                if !self.hasAutoFitted && newSize.width > 100 {
                    self.hasAutoFitted = true
                    self.fitViewport(bounds: layout.bounds, size: newSize, animated: false)
                }
            }
            .onChange(of: self.searchQuery) { _, _ in
                self.fitViewport(bounds: layout.bounds, size: geo.size, animated: true)
            }
            .onChange(of: self.panRequestToken) { _, _ in
                guard let selectedLeafID = self.selectedLeafID, geo.size.width > 100 else { return }
                if let lPos = layout.leaves.first(where: { $0.id == selectedLeafID }) {
                    let targetZoom: CGFloat = max(self.zoomScale, 0.84)
                    withAnimation(.snappy(duration: 0.24, extraBounce: 0)) {
                        self.zoomScale = targetZoom
                        self.panOffset = CGSize(
                            width: -lPos.worldPoint.x * targetZoom * 0.72,
                            height: -lPos.worldPoint.y * targetZoom * 0.72
                        )
                    }
                }
            }
            .onChange(of: self.focusedClusterID) { _, nextCID in
                guard geo.size.width > 100 else { return }
                if let nextCID, let cPos = layout.clusters.first(where: { $0.id == nextCID }) {
                    let targetZoom: CGFloat = max(self.zoomScale, 0.88)
                    withAnimation(.snappy(duration: 0.24, extraBounce: 0)) {
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
            withAnimation(.snappy(duration: 0.24, extraBounce: 0)) {
                self.zoomScale = targetZoom
                self.panOffset = targetPan
            }
        } else {
            self.zoomScale = targetZoom
            self.panOffset = targetPan
        }
    }
}


/// Crisp viewport-sized Canvas drawing clean edge-docked horizontal S-trunks, vertical spine buses,
/// and at most 2 focused relation arcs (zero crossing over cards, zero background dashed spiderwebs).
private struct StarMapViewportConnectorsCanvas: View {
    
    let clusters: [StarMapClusterNode]
    let relations: [StarMapRelationEdge]
    let layout: StarMapLayoutEngine.LayoutResult
    let selectedLeafID: String?
    let focusedClusterID: String?
    let viewportCenter: CGPoint
    let panOffset: CGSize
    let zoomScale: CGFloat
    let tokens: StudioColorTokens
    
    
    @inline(__always)
    private func toScreen(_ worldPt: CGPoint) -> CGPoint {
        CGPoint(
            x: self.viewportCenter.x + self.panOffset.width + worldPt.x * self.zoomScale,
            y: self.viewportCenter.y + self.panOffset.height + worldPt.y * self.zoomScale
        )
    }
    
    
    var body: some View {
        let clusterAccentByID: [String: Color] = Dictionary(uniqueKeysWithValues: self.clusters.map { ($0.id, $0.accent) })
        let leafPosByID = self.layout.leafPositionsByID
        let selectedClusterID: String? = self.focusedClusterID
            ?? self.selectedLeafID.flatMap { leafPosByID[$0]?.clusterID }
        
        Canvas(opaque: false, rendersAsynchronously: true) { context, canvasSize in
            let viewportBounds = CGRect(origin: .zero, size: canvasSize).insetBy(dx: -160, dy: -160)
            
            // 1. Hub -> Cluster connectors (Vertical Chronological Timeline Spine when timeline is active, or horizontal S-curves otherwise)
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
                // Subtle downward timeline arrow cap
                spinePath.move(to: CGPoint(x: spineEnd.x - 3.5, y: spineEnd.y - 4))
                spinePath.addLine(to: spineEnd)
                spinePath.addLine(to: CGPoint(x: spineEnd.x + 3.5, y: spineEnd.y - 4))
                context.stroke(
                    spinePath,
                    with: .color(self.tokens.primaryInk.opacity(0.20)),
                    style: StrokeStyle(lineWidth: 1.35, lineCap: .round, lineJoin: .round)
                )
                
                for cPos in self.layout.clusters {
                    let side: CGFloat = cPos.worldPoint.x >= 0 ? 1.0 : -1.0
                    let p0 = self.toScreen(CGPoint(x: side * milestoneHalfW, y: cPos.worldPoint.y))
                    let p1 = self.toScreen(CGPoint(x: cPos.worldPoint.x - side * clusterHalfW, y: cPos.worldPoint.y))
                    guard viewportBounds.contains(p0) || viewportBounds.contains(p1) else { continue }
                    
                    let accent = clusterAccentByID[cPos.id] ?? self.tokens.accent
                    let isActive = (selectedClusterID == nil || selectedClusterID == cPos.id)
                    
                    var branch = Path()
                    branch.move(to: p0)
                    branch.addLine(to: p1)
                    context.stroke(
                        branch,
                        with: .color(accent.opacity(isActive ? 0.56 : 0.20)),
                        style: StrokeStyle(lineWidth: (selectedClusterID == cPos.id) ? 1.75 : 1.2, lineCap: .round)
                    )
                }
            } else {
                for cPos in self.layout.clusters {
                    let side: CGFloat = cPos.worldPoint.x >= 0 ? 1.0 : -1.0
                    let p0 = self.toScreen(CGPoint(x: self.layout.hubPoint.x + side * hubHalfW, y: self.layout.hubPoint.y))
                    let p1 = self.toScreen(CGPoint(x: cPos.worldPoint.x - side * clusterHalfW, y: cPos.worldPoint.y))
                    guard viewportBounds.contains(p0) || viewportBounds.contains(p1) else { continue }
                    
                    let accent = clusterAccentByID[cPos.id] ?? self.tokens.accent
                    let isActive = (selectedClusterID == nil || selectedClusterID == cPos.id)
                    let midX = (p0.x + p1.x) * 0.5
                    
                    var trunk = Path()
                    trunk.move(to: p0)
                    trunk.addCurve(
                        to: p1,
                        control1: CGPoint(x: midX, y: p0.y),
                        control2: CGPoint(x: midX, y: p1.y)
                    )
                    context.stroke(
                        trunk,
                        with: .color(accent.opacity(isActive ? 0.52 : 0.20)),
                        style: StrokeStyle(lineWidth: (selectedClusterID == cPos.id) ? 1.7 : 1.2, lineCap: .round)
                    )
                }
            }
            
            // 2. Cluster -> Leaf clean orthogonal bus spines (zero diagonal lines slicing through cards!)
            for (key, colLeaves) in self.layout.leafColumns {
                let first = colLeaves[0]
                let colWorldX = first.worldPoint.x
                let side: CGFloat = colWorldX >= 0 ? 1.0 : -1.0
                let parentWorld = first.parentPoint
                let isSubcolumnContinuation = abs(parentWorld.x) > 350
                let parentOuterWorldX = parentWorld.x + side * (isSubcolumnContinuation ? leafHalfW : clusterHalfW)
                let leafInnerWorldX = colWorldX - side * leafHalfW
                let spineWorldX = (parentOuterWorldX + leafInnerWorldX) * 0.5
                
                let accent = clusterAccentByID[key.clusterID] ?? self.tokens.accent
                let isClusterActive = (selectedClusterID == nil || selectedClusterID == key.clusterID)
                let baseColor = accent.opacity(isClusterActive ? 0.36 : 0.14)
                
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
                    x: min(parentOutScreen.x, leafInScreenX) - 20,
                    y: minY - 20,
                    width: abs(leafInScreenX - parentOutScreen.x) + 40,
                    height: (maxY - minY) + 40
                )
                guard viewportBounds.intersects(colBounds) else { continue }
                
                var bus = Path()
                // Stem from parent outer border to vertical spine
                bus.move(to: parentOutScreen)
                bus.addLine(to: CGPoint(x: spineScreenX, y: parentOutScreen.y))
                // Vertical bus spine
                if maxY - minY > 0.5 {
                    bus.move(to: CGPoint(x: spineScreenX, y: minY))
                    bus.addLine(to: CGPoint(x: spineScreenX, y: maxY))
                }
                // Crisp horizontal ticks into each leaf card's inner edge
                for l in colLeaves {
                    let sy = self.toScreen(l.worldPoint).y
                    bus.move(to: CGPoint(x: spineScreenX, y: sy))
                    bus.addLine(to: CGPoint(x: leafInScreenX, y: sy))
                }
                context.stroke(
                    bus,
                    with: .color(baseColor),
                    style: StrokeStyle(lineWidth: 1.15, lineCap: .round, lineJoin: .round)
                )
                
                // Highlight selected leaf's exact branch path
                if let selID = self.selectedLeafID,
                   let selLeaf = colLeaves.first(where: { $0.id == selID })
                {
                    let selY = self.toScreen(selLeaf.worldPoint).y
                    var highlight = Path()
                    highlight.move(to: parentOutScreen)
                    highlight.addLine(to: CGPoint(x: spineScreenX, y: parentOutScreen.y))
                    highlight.addLine(to: CGPoint(x: spineScreenX, y: selY))
                    highlight.addLine(to: CGPoint(x: leafInScreenX, y: selY))
                    context.stroke(
                        highlight,
                        with: .color(accent.opacity(0.90)),
                        style: StrokeStyle(lineWidth: 1.85, lineCap: .round, lineJoin: .round)
                    )
                }
            }
            
            // 3. Focused Cross-Node Semantic Arcs (ONLY for selected leaf, max 2 clean curves — zero idle clutter!)
            if let selID = self.selectedLeafID {
                let incident = self.relations
                    .filter { $0.sourceID == selID || $0.targetID == selID }
                    .prefix(2)
                for edge in incident {
                    guard let a = leafPosByID[edge.sourceID],
                          let b = leafPosByID[edge.targetID]
                    else { continue }
                    let p0 = self.toScreen(a.worldPoint)
                    let p1 = self.toScreen(b.worldPoint)
                    let dx = p1.x - p0.x
                    let dy = p1.y - p0.y
                    let mid = CGPoint(x: (p0.x + p1.x) * 0.5, y: (p0.y + p1.y) * 0.5)
                    let ctrl = CGPoint(x: mid.x - dy * 0.12, y: mid.y + dx * 0.12 - 24)
                    var arc = Path()
                    arc.move(to: p0)
                    arc.addQuadCurve(to: p1, control: ctrl)
                    context.stroke(
                        arc,
                        with: .color(self.tokens.accent.opacity(0.65)),
                        style: StrokeStyle(lineWidth: 1.4, lineCap: .round, dash: [5, 4])
                    )
                }
            }
        }
    }
}


private struct StarMapWorldStageView<ClusterMenu: View, LeafMenu: View>: View, Equatable {
    
    let hubTitle: String
    let hubSubtitle: String
    let clusters: [StarMapClusterNode]
    let relations: [StarMapRelationEdge]
    let layout: StarMapLayoutEngine.LayoutResult
    let selectedLeafID: String?
    let focusedClusterID: String?
    let isDark: Bool
    let tokens: StudioColorTokens
    let worldW: CGFloat
    let worldH: CGFloat
    let onSelectLeaf: (String) -> Void
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
            && lhs.focusedClusterID == rhs.focusedClusterID
            && lhs.isDark == rhs.isDark
            && lhs.worldW == rhs.worldW
            && lhs.worldH == rhs.worldH
    }
    
    
    var body: some View {
        let tokens = self.tokens
        let originX = self.worldW * 0.5
        let originY = self.worldH * 0.5
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
        let relatedIDs: Set<String> = {
            guard let selID = self.selectedLeafID else { return [] }
            var ids = Set<String>()
            for edge in self.relations.filter({ $0.sourceID == selID || $0.targetID == selID }).prefix(2) {
                ids.insert(edge.sourceID == selID ? edge.targetID : edge.sourceID)
            }
            return ids
        }()
        
        ZStack {
            // 1. Center / Timeline Crown Hub Node
            VStack(spacing: 3) {
                HStack(spacing: 4) {
                    if self.layout.usesTimelineSpine {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(tokens.accent)
                    }
                    Text(self.hubTitle)
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(tokens.primaryInk)
                        .lineLimit(1)
                }
                Text(self.layout.usesTimelineSpine ? "时间轴 · \(self.hubSubtitle)" : self.hubSubtitle)
                    .font(.system(size: 10.5, weight: .medium, design: .rounded).monospacedDigit())
                    .foregroundStyle(tokens.primaryInk.opacity(0.55))
                    .lineLimit(1)
            }
            .frame(width: StarMapLayoutEngine.hubFootprint.width - 12, height: StarMapLayoutEngine.hubFootprint.height - 14)
            .background(tokens.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(tokens.accent.opacity(0.55), lineWidth: 1.2)
            )
            .position(x: originX + self.layout.hubPoint.x, y: originY + self.layout.hubPoint.y)
            
            // 1b. Chronological Timeline Milestones along X = 0 Spine
            if self.layout.usesTimelineSpine {
                ForEach(self.layout.clusters) { cPos in
                    if let cluster = clusterMap[cPos.id], let timeLabel = cluster.timelineLabel {
                        StarMapTimelineMilestoneView(
                            label: timeLabel,
                            accent: cluster.accent,
                            isFocused: self.focusedClusterID == cluster.id,
                            isDark: self.isDark,
                            tokens: tokens,
                            onTap: { self.onToggleCluster(cluster.id) }
                        )
                        .equatable()
                        .position(x: originX, y: originY + cPos.worldPoint.y)
                    }
                }
            }
            
            // 2. Tier-1 Cluster Nodes (Groups / Months)
            ForEach(self.layout.clusters) { cPos in
                if let cluster = clusterMap[cPos.id] {
                    StarMapClusterPillView(
                        cluster: cluster,
                        isFocused: self.focusedClusterID == cluster.id,
                        isDark: self.isDark,
                        tokens: tokens,
                        onToggle: { self.onToggleCluster(cluster.id) }
                    )
                    .equatable()
                    .position(x: originX + cPos.worldPoint.x, y: originY + cPos.worldPoint.y)
                    .contextMenu {
                        self.clusterContextMenu(cluster)
                    }
                }
            }
            
            // 3. Tier-2 Structured Leaf Cards
            ForEach(self.layout.leaves) { lPos in
                if let leaf = leafMap[lPos.id] {
                    let isSelected = (self.selectedLeafID == leaf.id)
                    let isRelated = relatedIDs.contains(leaf.id)
                    let dimmed = (self.focusedClusterID != nil && self.focusedClusterID != leaf.clusterID && !isSelected && !isRelated)
                    
                    StarMapLeafCardView(
                        leaf: leaf,
                        tokens: tokens,
                        isSelected: isSelected,
                        isRelated: isRelated,
                        dimmed: dimmed,
                        isDark: self.isDark
                    )
                    .equatable()
                    .position(x: originX + lPos.worldPoint.x, y: originY + lPos.worldPoint.y)
                    .pointerStyle(.link)
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
    }
}


private struct StarMapTimelineMilestoneView: View, Equatable {
    
    let label: String
    let accent: Color
    let isFocused: Bool
    let isDark: Bool
    let tokens: StudioColorTokens
    let onTap: () -> Void
    
    @State private var isHovered = false
    
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.label == rhs.label
            && lhs.accent == rhs.accent
            && lhs.isFocused == rhs.isFocused
            && lhs.isDark == rhs.isDark
    }
    
    var body: some View {
        Button(action: self.onTap) {
            HStack(spacing: 4.5) {
                Circle()
                    .fill(self.accent)
                    .frame(width: 5.5, height: 5.5)
                
                Text(self.label)
                    .font(.system(size: 9.5, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(self.isFocused ? self.accent : self.tokens.primaryInk.opacity(0.76))
                    .lineLimit(1)
            }
            .padding(.horizontal, 7)
            .frame(width: StarMapLayoutEngine.milestoneFootprint.width - 6, height: StarMapLayoutEngine.milestoneFootprint.height - 2)
            .background(self.tokens.card, in: Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(
                        (self.isFocused || self.isHovered) ? self.accent.opacity(0.75) : self.tokens.hairlineStrong,
                        lineWidth: (self.isFocused || self.isHovered) ? 1.2 : 0.75
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
    let tokens: StudioColorTokens
    let onToggle: () -> Void
    
    @State private var isHovered = false
    
    
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.cluster == rhs.cluster
            && lhs.isFocused == rhs.isFocused
            && lhs.isDark == rhs.isDark
    }
    
    
    var body: some View {
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
                    .font(.system(size: 10, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(self.cluster.accent)
                    .padding(.horizontal, 6)
                    .frame(height: 18)
                    .background(self.cluster.accent.opacity(self.isDark ? 0.18 : 0.11), in: Capsule())
                
                Image(systemName: self.cluster.isCollapsed ? "chevron.right" : "chevron.down")
                    .font(.system(size: 8.5, weight: .bold))
                    .foregroundStyle(self.tokens.primaryInk.opacity(0.45))
            }
            .padding(.horizontal, 10)
            .frame(width: StarMapLayoutEngine.clusterFootprint.width - 8, height: StarMapLayoutEngine.clusterFootprint.height - 8)
            .background(self.tokens.card, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(
                        (self.isFocused || self.isHovered) ? self.cluster.accent.opacity(0.78) : self.tokens.hairlineStrong,
                        lineWidth: (self.isFocused || self.isHovered) ? 1.3 : 0.85
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
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
    let isRelated: Bool
    let dimmed: Bool
    let isDark: Bool
    
    @State private var isHovered = false
    
    
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.leaf == rhs.leaf
            && lhs.isSelected == rhs.isSelected
            && lhs.isRelated == rhs.isRelated
            && lhs.dimmed == rhs.dimmed
            && lhs.isDark == rhs.isDark
    }
    
    
    var body: some View {
        VStack(alignment: .leading, spacing: 3.5) {
            HStack(spacing: 6) {
                Circle()
                    .fill(self.isRelated ? self.tokens.accent : self.leaf.dotColor)
                    .frame(width: self.isSelected ? 7 : 6, height: self.isSelected ? 7 : 6)
                
                Text(self.leaf.title)
                    .font(.system(size: 12, weight: self.isSelected ? .semibold : .medium))
                    .foregroundStyle(self.tokens.primaryInk.opacity(self.isSelected ? 1.0 : 0.90))
                    .lineLimit(1)
                
                Spacer(minLength: 0)
            }
            
            HStack(spacing: 5) {
                if let badge = self.leaf.statusBadge, !badge.isEmpty {
                    Text(badge)
                        .font(.system(size: 9, weight: .semibold))
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
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(width: StarMapLayoutEngine.leafFootprint.width - 8, height: StarMapLayoutEngine.leafFootprint.height - 6, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(self.tokens.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(
                    self.isSelected
                        ? self.leaf.dotColor.opacity(0.95)
                        : (self.isRelated
                           ? self.tokens.accent.opacity(0.68)
                           : (self.isHovered ? self.leaf.dotColor.opacity(0.55) : self.tokens.hairline)),
                    lineWidth: self.isSelected ? 1.6 : (self.isRelated ? 1.2 : 0.85)
                )
        )
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .opacity(self.dimmed ? 0.45 : 1.0)
        .onHover { hovering in
            if hovering != self.isHovered {
                self.isHovered = hovering
            }
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
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(self.title)
                            .font(.system(size: 14.5, weight: .semibold))
                            .foregroundStyle(tokens.primaryInk)
                            .fixedSize(horizontal: false, vertical: true)
                        if !self.subtitle.isEmpty {
                            Text(self.subtitle)
                                .font(.system(size: 11, weight: .regular, design: .rounded).monospacedDigit())
                                .foregroundStyle(tokens.primaryInk.opacity(0.52))
                                .fixedSize(horizontal: false, vertical: true)
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
                .padding(.vertical, 10)
                .frame(minHeight: 54)
                
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


// MARK: - Floating Search Results & Snippets HUD (Shared by Document Center & Weekly Report Center)

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
                    .font(.system(size: 12, weight: .semibold))
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
                    Text("无匹配关键词，可尝试减少关键词或切换分组")
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


// MARK: - Native Apple 3-Column Document Center

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
    @FocusState private var isSearchFocused: Bool
    
    @State private var isRenaming = false
    @State private var renameDraft = ""
    @FocusState private var isRenameFieldFocused: Bool
    @State private var isCreatingGroup = false
    @State private var newGroupDraft = ""
    @FocusState private var isNewGroupFieldFocused: Bool
    @State private var pendingAssignAfterGroupCreate: DocumentCenterState.ManagedDocumentItem?
    @State private var renamingGroupName: String?
    @State private var groupRenameDraft = ""
    @FocusState private var isGroupRenameFocused: Bool
    @State private var copiedFlag = false
    @State private var searchDraft = ""
    @State private var searchDebounceTask: Task<Void, Never>?
    @State private var toastMessage: String?
    @State private var toastTask: Task<Void, Never>?
    @State private var organizeTask: Task<Void, Never>?
    @State private var keyMonitor: Any?
    
    private var chromeBackground: Color { Color(nsColor: .windowBackgroundColor) }
    private var contentBackground: Color { Color(nsColor: .textBackgroundColor) }
    private var controlBackground: Color { Color(nsColor: .controlBackgroundColor) }
    private var separatorColor: Color { Color(nsColor: .separatorColor).opacity(0.65) }
    
    
    var body: some View {
        let displayedItems = self.state.displayedItems
        let activeItem = self.selectedItem(in: displayedItems)
        let searchTerms = StarMapSearchEngine.parseTerms(self.state.searchText)
        let hasQuery = !self.state.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                self.topBar(displayedItems: displayedItems, hasQuery: hasQuery)
                
                Rectangle()
                    .fill(self.separatorColor)
                    .frame(height: 1)
                
                HStack(spacing: 0) {
                    self.leftSidebar()
                    
                    Rectangle()
                        .fill(self.separatorColor)
                        .frame(width: 1)
                    
                    self.middleListColumn(
                        displayedItems: displayedItems,
                        activeItem: activeItem,
                        hasQuery: hasQuery
                    )
                    
                    Rectangle()
                        .fill(self.separatorColor)
                        .frame(width: 1)
                    
                    self.rightReaderPane(
                        activeItem: activeItem,
                        displayedItems: displayedItems,
                        searchTerms: searchTerms
                    )
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(self.contentBackground)
            
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
            self.state.refresh()
            self.searchDraft = self.state.searchText
            self.installKeyboardMonitor()
            self.registerEscPop? { self.handleEscapePop() }
        }
        .onDisappear {
            self.removeKeyboardMonitor()
            self.searchDebounceTask?.cancel()
            self.organizeTask?.cancel()
            self.registerEscPop?(nil)
        }
        .onChange(of: self.db.documents.count) { _, _ in
            self.state.refresh()
        }
        .onChange(of: self.db.trashedDocuments.count) { _, _ in
            self.state.refresh()
        }
        .onReceive(
            NotificationCenter.default.publisher(for: ScheduledAIDocumentOrganizer.didCompleteOrganizeNotification)
                .receive(on: RunLoop.main)
        ) { _ in
            self.state.refresh()
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
    }
    
    
    // MARK: Top Bar
    
    private func topBar(
        displayedItems: [DocumentCenterState.ManagedDocumentItem],
        hasQuery: Bool
    ) -> some View {
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
            
            Text("文档中心")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.primary)
            
            Spacer(minLength: 8)
            
            // Native Search Field
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
                            guard await self.state.applySearch(query), let firstHit = self.state.searchHits.first else { return }
                            self.selectDocument(firstHit.id)
                        }
                    }
                
                if hasQuery {
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
            .frame(minWidth: 210, maxWidth: 260, minHeight: 28, maxHeight: 28)
            .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(
                        self.isSearchFocused ? Color.accentColor.opacity(0.55) : self.separatorColor.opacity(0.6),
                        lineWidth: self.isSearchFocused ? 1.0 : 0.65
                    )
            )
            
            if self.state.sidebarFilter == .trash && !displayedItems.isEmpty {
                Button("清空废纸篓") {
                    self.confirmEmptyTrash()
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.red)
                .padding(.horizontal, 10)
                .frame(height: 28)
                .background(Color.red.opacity(0.10), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .buttonStyle(.plain)
                .pointerStyle(.link)
            }
            
            if self.state.isAgentOrganizing {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.mini)
                    Text("整理中")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.primary)
                    Button("取消") {
                        self.cancelAgentOrganize()
                    }
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.secondary)
                    .buttonStyle(.plain)
                    .pointerStyle(.link)
                }
                .padding(.horizontal, 10)
                .frame(height: 28)
                .background(Color.primary.opacity(0.065), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            } else {
                if let summary = self.state.agentOrganizeSummary {
                    HStack(spacing: 6) {
                        Text(summary)
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(Color.accentColor)
                        if !self.state.lastOrganizeUndoSnapshot.isEmpty {
                            Button("撤销") {
                                self.undoAgentOrganize()
                            }
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 6)
                            .frame(height: 20)
                            .background(self.contentBackground, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                            .buttonStyle(.plain)
                            .pointerStyle(.link)
                        }
                        Button {
                            self.state.agentOrganizeSummary = nil
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 9.5, weight: .semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .buttonStyle(.plain)
                        .pointerStyle(.link)
                    }
                    .padding(.horizontal, 9)
                    .frame(height: 28)
                    .background(Color.accentColor.opacity(0.11), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
                
                Button {
                    self.runAgentAutoOrganize()
                } label: {
                    Text("智能整理")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 11)
                        .frame(height: 28)
                        .background(Color.primary.opacity(0.065), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                        .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
                .buttonStyle(.plain)
                .pointerStyle(.link)
                .disabled(self.state.items.isEmpty)
                .opacity(self.state.items.isEmpty ? 0.45 : 1)
            }
            
            if let onCreateNewDocument = self.onCreateNewDocument {
                Button(action: onCreateNewDocument) {
                    Text("新建")
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
        }
        .padding(.horizontal, 14)
        .frame(height: 44)
        .background(self.chromeBackground)
    }
    
    
    // MARK: Column 1 - Left Library & Groups Sidebar
    
    private func leftSidebar() -> some View {
        let groupNames: [String] = {
            var ordered = self.db.documentGroups
            for key in self.state.groupCounts.keys.sorted() where !ordered.contains(key) {
                ordered.append(key)
            }
            return ordered
        }()
        
        return ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 2) {
                    self.sidebarSectionHeader("文库")
                    
                    self.sidebarRow(
                        title: "全部文档",
                        count: self.state.items.count,
                        isSelected: self.state.sidebarFilter == .all
                    ) {
                        self.state.sidebarFilter = .all
                    }
                    
                    self.sidebarRow(
                        title: "打开中",
                        count: self.state.openCount,
                        isSelected: self.state.sidebarFilter == .openNow
                    ) {
                        self.state.sidebarFilter = .openNow
                    }
                    
                    if self.state.ungroupedCount > 0 || self.state.sidebarFilter == .ungrouped {
                        self.sidebarRow(
                            title: "未分组",
                            count: self.state.ungroupedCount,
                            isSelected: self.state.sidebarFilter == .ungrouped
                        ) {
                            self.state.sidebarFilter = .ungrouped
                        }
                    }
                    
                    if !self.state.trashedItems.isEmpty || self.state.sidebarFilter == .trash {
                        self.sidebarRow(
                            title: "废纸篓",
                            count: self.state.trashedItems.count,
                            isSelected: self.state.sidebarFilter == .trash
                        ) {
                            self.state.sidebarFilter = .trash
                        }
                    }
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        self.sidebarSectionHeader("分组")
                        Spacer(minLength: 4)
                        Button("新建") {
                            self.newGroupDraft = ""
                            self.pendingAssignAfterGroupCreate = nil
                            self.isCreatingGroup = true
                            DispatchQueue.main.async { self.isNewGroupFieldFocused = true }
                        }
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.accentColor)
                        .buttonStyle(.plain)
                        .pointerStyle(.link)
                        .padding(.horizontal, 6)
                        .padding(.bottom, 4)
                    }
                    
                    if self.isCreatingGroup {
                        TextField("分组名称", text: self.$newGroupDraft)
                            .textFieldStyle(.plain)
                            .font(.system(size: 12))
                            .focused(self.$isNewGroupFieldFocused)
                            .padding(.horizontal, 8)
                            .frame(height: 26)
                            .background(self.contentBackground, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Color.accentColor.opacity(0.5), lineWidth: 0.85))
                            .padding(.bottom, 4)
                            .onSubmit { self.commitCreateGroup() }
                            .onExitCommand {
                                self.isCreatingGroup = false
                                self.pendingAssignAfterGroupCreate = nil
                            }
                    }
                    
                    if groupNames.isEmpty && !self.isCreatingGroup {
                        Text("暂无分组")
                            .font(.system(size: 11.5))
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                    } else {
                        LazyVStack(spacing: 2) {
                            ForEach(groupNames, id: \.self) { groupName in
                                if self.renamingGroupName == groupName {
                                    TextField("新分组名", text: self.$groupRenameDraft)
                                        .textFieldStyle(.plain)
                                        .font(.system(size: 12))
                                        .focused(self.$isGroupRenameFocused)
                                        .padding(.horizontal, 8)
                                        .frame(height: 26)
                                        .background(self.contentBackground, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                                        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Color.accentColor.opacity(0.5), lineWidth: 0.85))
                                        .onSubmit { self.commitGroupRename(oldName: groupName) }
                                        .onExitCommand { self.renamingGroupName = nil }
                                } else {
                                    let isActive = (self.state.sidebarFilter == .group(groupName))
                                    self.sidebarRow(
                                        title: groupName,
                                        count: self.state.groupCounts[groupName] ?? 0,
                                        isSelected: isActive
                                    ) {
                                        self.state.sidebarFilter = isActive ? .all : .group(groupName)
                                    }
                                    .contextMenu {
                                        self.groupContextMenu(groupName: groupName)
                                    }
                                }
                            }
                        }
                    }
                }
                
                if self.state.sidebarFilter != .trash {
                    VStack(alignment: .leading, spacing: 2) {
                        self.sidebarSectionHeader("时间")
                        
                        ForEach(DocumentCenterState.TimeHorizon.allCases, id: \.self) { horizon in
                            self.sidebarRow(
                                title: horizon.rawValue,
                                count: nil,
                                isSelected: self.state.timeHorizon == horizon
                            ) {
                                self.state.timeHorizon = horizon
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 12)
        }
        .frame(width: 192)
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
        count: Int?,
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
                
                if let count {
                    Text("\(count)")
                        .font(.system(size: 11, weight: .medium, design: .rounded).monospacedDigit())
                        .foregroundStyle(isSelected ? Color.accentColor.opacity(0.85) : .secondary)
                }
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
    
    
    // MARK: Column 2 - Middle Document List
    
    private func middleListColumn(
        displayedItems: [DocumentCenterState.ManagedDocumentItem],
        activeItem: DocumentCenterState.ManagedDocumentItem?,
        hasQuery: Bool
    ) -> some View {
        let headerTitle: String = if hasQuery {
            "搜索结果"
        } else {
            switch self.state.sidebarFilter {
                case .all: "全部文档"
                case .openNow: "打开中"
                case .group(let name): name
                case .ungrouped: "未分组"
                case .trash: "废纸篓"
            }
        }
        
        return VStack(spacing: 0) {
            HStack {
                Text(headerTitle)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 6)
                Text("\(displayedItems.count) 篇")
                    .font(.system(size: 11, weight: .medium, design: .rounded).monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .frame(height: 36)
            
            Rectangle()
                .fill(self.separatorColor)
                .frame(height: 1)
            
            if displayedItems.isEmpty {
                self.emptyListState(hasQuery: hasQuery)
            } else {
                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: true) {
                        LazyVStack(spacing: 2) {
                            ForEach(displayedItems) { item in
                                self.documentListRow(
                                    item: item,
                                    isSelected: activeItem?.id == item.id,
                                    allItems: displayedItems,
                                    hasQuery: hasQuery
                                )
                                .id(item.id)
                            }
                        }
                        .padding(8)
                    }
                    .onChange(of: self.state.selectedID) { _, nextID in
                        guard let nextID else { return }
                        withAnimation(.easeOut(duration: 0.12)) {
                            proxy.scrollTo(nextID, anchor: .center)
                        }
                    }
                }
            }
        }
        .frame(width: 300)
        .frame(maxHeight: .infinity)
        .background(self.contentBackground)
    }
    
    
    private func documentListRow(
        item: DocumentCenterState.ManagedDocumentItem,
        isSelected: Bool,
        allItems: [DocumentCenterState.ManagedDocumentItem],
        hasQuery: Bool
    ) -> some View {
        let eval = self.state.searchMatchesByID[item.id]
        let excerpt: String = if hasQuery, let snippet = eval?.snippet, !snippet.isEmpty {
            snippet
        } else {
            DocumentCenterState.cleanExcerpt(from: item.content)
        }
        let groupLabel = item.groupName.isEmpty ? "未分组" : item.groupName
        let metaLine = "\(groupLabel) · \(item.compactCharCount) · \(item.relativeTimeText)"
        
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(item.title)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                
                Spacer(minLength: 4)
                
                if item.isDirty {
                    Text("未保存")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 5)
                        .frame(height: 16)
                        .background(Color.orange.opacity(0.13), in: Capsule())
                } else if item.isOpenNow {
                    Text("打开中")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Color.accentColor)
                        .padding(.horizontal, 5)
                        .frame(height: 16)
                        .background(Color.accentColor.opacity(0.11), in: Capsule())
                }
            }
            
            HStack(spacing: 6) {
                Text(metaLine)
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
            self.selectDocument(item.id)
        }
        .simultaneousGesture(
            TapGesture(count: 2).onEnded {
                self.selectDocument(item.id)
                if !item.isTrashed {
                    self.open(item: item)
                }
            }
        )
        .contextMenu {
            self.itemContextMenu(item: item, allItems: allItems)
        }
    }
    
    
    private func emptyListState(hasQuery: Bool) -> some View {
        VStack(spacing: 10) {
            Text(hasQuery ? "未找到匹配文档" : (self.state.sidebarFilter == .trash ? "废纸篓为空" : "暂无文档"))
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
            
            if hasQuery {
                Button("清除搜索") {
                    self.searchDebounceTask?.cancel()
                    self.searchDraft = ""
                    self.state.searchText = ""
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.accentColor)
                .buttonStyle(.plain)
                .pointerStyle(.link)
            } else if self.state.sidebarFilter != .trash, let onCreateNewDocument = self.onCreateNewDocument {
                Button("新建文档", action: onCreateNewDocument)
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
    
    
    // MARK: Column 3 - Right Live Document Reader
    
    private func rightReaderPane(
        activeItem: DocumentCenterState.ManagedDocumentItem?,
        displayedItems: [DocumentCenterState.ManagedDocumentItem],
        searchTerms: [String]
    ) -> some View {
        Group {
            if let activeItem {
                let related = activeItem.isTrashed ? [] : self.state.relatedNodes(for: activeItem.id, in: self.state.items)
                
                VStack(spacing: 0) {
                    self.detailHeader(item: activeItem, displayedItems: displayedItems)
                    
                    Rectangle()
                        .fill(self.separatorColor)
                        .frame(height: 1)
                    
                    if !related.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                Text("相关")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(.secondary)
                                
                                ForEach(related.prefix(5), id: \.item.id) { entry in
                                    Button {
                                        self.selectDocument(entry.item.id)
                                    } label: {
                                        Text("\(entry.item.title) · \(entry.reason)")
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
                    
                    CenterPreviewTextView(
                        text: activeItem.previewText,
                        highlightTerms: searchTerms
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                Text("选择一篇文档以预览")
                    .font(.system(size: 13.5))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(self.contentBackground)
    }
    
    
    private func detailHeader(
        item: DocumentCenterState.ManagedDocumentItem,
        displayedItems: [DocumentCenterState.ManagedDocumentItem]
    ) -> some View {
        let groupLabel = item.groupName.isEmpty ? "未分组" : item.groupName
        let metaLine = "\(groupLabel) · \(item.syntax) · \(item.compactCharCount) · \(item.relativeTimeText)"
        
        return HStack(spacing: 12) {
            if self.isRenaming {
                TextField("文档标题", text: self.$renameDraft)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14, weight: .semibold))
                    .focused(self.$isRenameFieldFocused)
                    .padding(.horizontal, 8)
                    .frame(maxWidth: 300, minHeight: 28, maxHeight: 28)
                    .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .onSubmit { self.commitRename(for: item) }
                    .onExitCommand { self.isRenaming = false }
                
                Button("保存") { self.commitRename(for: item) }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                
                Button("取消") { self.isRenaming = false }
                    .controlSize(.small)
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    
                    Text(metaLine)
                        .font(.system(size: 11, weight: .regular, design: .rounded).monospacedDigit())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            
            Spacer(minLength: 10)
            
            if item.isTrashed {
                Button {
                    self.restore(item: item)
                } label: {
                    Text("恢复")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .frame(height: 27)
                        .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
                .buttonStyle(.plain)
                .pointerStyle(.link)
                
                Button {
                    self.permanentlyDelete(item: item)
                } label: {
                    Text("彻底删除")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.red)
                        .padding(.horizontal, 10)
                        .frame(height: 27)
                        .background(Color.red.opacity(0.10), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
                .buttonStyle(.plain)
                .pointerStyle(.link)
            } else {
                Button {
                    self.open(item: item)
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
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(item.content, forType: .string)
                    self.copiedFlag = true
                    self.showToast("已复制")
                    Task {
                        try? await Task.sleep(for: .seconds(1.4))
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
                    Menu("移动到分组") {
                        Button("未分组") { self.move(item: item, toGroup: "") }
                        if !self.db.documentGroups.isEmpty {
                            Divider()
                            ForEach(self.db.documentGroups, id: \.self) { group in
                                Button(group) { self.move(item: item, toGroup: group) }
                            }
                        }
                        Divider()
                        Button("新建分组") {
                            self.pendingAssignAfterGroupCreate = item
                            self.newGroupDraft = ""
                            self.isCreatingGroup = true
                            DispatchQueue.main.async { self.isNewGroupFieldFocused = true }
                        }
                    }
                    Divider()
                    Button("重命名") {
                        self.renameDraft = item.title
                        self.isRenaming = true
                        DispatchQueue.main.async { self.isRenameFieldFocused = true }
                    }
                    Button("移入废纸篓", role: .destructive) {
                        self.delete(item: item, in: displayedItems)
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
    
    
    private func selectDocument(_ id: String) {
        self.unfocusSearchField()
        self.isRenaming = false
        self.state.selectedID = id
    }
    
    
    // MARK: Context Menus
    
    @ViewBuilder
    private func groupContextMenu(groupName: String) -> some View {
        Button("打开全部分组文档") {
            let groupItems = self.state.items.filter { $0.groupName == groupName }
            self.openAll(items: groupItems)
        }
        Button("重命名分组") {
            self.groupRenameDraft = groupName
            self.renamingGroupName = groupName
            DispatchQueue.main.async { self.isGroupRenameFocused = true }
        }
        Divider()
        Button("解散分组", role: .destructive) {
            self.db.deleteDocumentGroup(named: groupName)
            if self.state.sidebarFilter == .group(groupName) {
                self.state.sidebarFilter = .all
            }
            self.state.refresh()
            self.showToast("已解散「\(groupName)」")
        }
    }
    
    
    @ViewBuilder
    private func itemContextMenu(
        item: DocumentCenterState.ManagedDocumentItem,
        allItems: [DocumentCenterState.ManagedDocumentItem]
    ) -> some View {
        if item.isTrashed {
            Button("恢复") { self.restore(item: item) }
            Divider()
            Button("彻底删除", role: .destructive) { self.permanentlyDelete(item: item) }
        } else {
            Button("在编辑器打开") { self.open(item: item) }
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
                Button("新建分组") {
                    self.pendingAssignAfterGroupCreate = item
                    self.newGroupDraft = ""
                    self.isCreatingGroup = true
                    DispatchQueue.main.async { self.isNewGroupFieldFocused = true }
                }
            }
            Divider()
            Button("移入废纸篓", role: .destructive) {
                self.delete(item: item, in: allItems)
            }
        }
    }
    
    
    // MARK: Agent One-Click Auto-Organize
    
    private func runAgentAutoOrganize() {
        let snapshotItems = self.state.items
        guard !snapshotItems.isEmpty, !self.state.isAgentOrganizing else { return }
        
        self.organizeTask?.cancel()
        self.state.isAgentOrganizing = true
        self.state.agentOrganizeSummary = nil
        
        let existingGroups = self.db.documentGroups
        let inputs: [DocumentCenterAgentOrganizer.InputItem] = snapshotItems.map { item in
            DocumentCenterAgentOrganizer.InputItem(
                id: item.id,
                title: item.title,
                syntax: item.syntax,
                currentGroup: item.groupName,
                excerpt: String(item.content.prefix(320)),
                isUntitled: DocumentCenterAgentOrganizer.isGenericUntitled(item.title, hasFilePath: item.filePath != nil)
            )
        }
        let itemsByID = Dictionary(uniqueKeysWithValues: snapshotItems.map { ($0.id, $0) })
        
        self.organizeTask = Task {
            let (plan, usedAI) = await DocumentCenterAgentOrganizer.generatePlan(
                items: inputs,
                existingGroups: existingGroups
            )
            guard !Task.isCancelled else {
                self.state.isAgentOrganizing = false
                return
            }
            
            var undoEntries: [DocumentCenterState.OrganizeUndoEntry] = []
            var existingGroupSet = Set(self.db.documentGroups)
            var createdGroups: [String] = []
            var touchedGroups = Set<String>()
            var changedCount = 0
            
            self.db.withTransaction {
                for assignment in plan.assignments {
                    guard let item = itemsByID[assignment.id] else { continue }
                    let targetGroup = assignment.group
                    let wantsRename: String? = {
                        guard let suggested = assignment.suggestedTitle,
                              !suggested.isEmpty,
                              suggested != item.title,
                              DocumentCenterAgentOrganizer.isGenericUntitled(item.title, hasFilePath: item.filePath != nil)
                        else { return nil }
                        return suggested
                    }()
                    
                    let groupChanged = (targetGroup != item.groupName)
                    guard groupChanged || wantsRename != nil else { continue }
                    
                    let recordID = item.dbRecordID ?? item.id
                    undoEntries.append(DocumentCenterState.OrganizeUndoEntry(
                        itemID: item.id,
                        dbRecordID: recordID,
                        filePath: item.filePath,
                        previousGroup: item.groupName,
                        previousTitle: item.title,
                        titleWasChanged: wantsRename != nil,
                        syntax: item.syntax,
                        content: item.content
                    ))
                    
                    if groupChanged {
                        if !targetGroup.isEmpty, existingGroupSet.insert(targetGroup).inserted {
                            createdGroups.append(targetGroup)
                        }
                        self.db.assignDocumentGroup(
                            id: recordID,
                            filePath: item.filePath,
                            groupName: targetGroup,
                            fallbackTitle: wantsRename ?? item.title,
                            fallbackSyntax: item.syntax,
                            fallbackContent: item.content,
                            reloadAfter: false
                        )
                        if !targetGroup.isEmpty {
                            touchedGroups.insert(targetGroup)
                        }
                    }
                    
                    if let newTitle = wantsRename {
                        if let liveDoc = self.state.liveDocument(for: item.id) {
                            _ = try? WorkspaceOrganizer.renameDocument(liveDoc, to: newTitle, reloadAfter: false)
                        } else if item.filePath == nil {
                            self.db.renameDocument(
                                oldID: recordID,
                                oldFilePath: nil,
                                newID: recordID,
                                newTitle: newTitle,
                                newFilePath: nil,
                                reloadAfter: false
                            )
                        }
                    }
                    changedCount += 1
                }
            }
            if changedCount > 0 {
                self.db.reloadDocuments()
            }
            
            self.state.lastOrganizeUndoSnapshot = undoEntries
            self.state.lastOrganizeCreatedGroups = createdGroups
            self.state.isAgentOrganizing = false
            self.state.refresh()
            
            if changedCount > 0 {
                let prefix = usedAI ? "Agent 已整理" : "已整理"
                self.state.agentOrganizeSummary = "\(prefix) \(changedCount) 篇 · \(max(1, touchedGroups.count)) 分组"
            } else {
                self.showToast("当前文档已整理完成")
            }
        }
    }
    
    
    private func cancelAgentOrganize() {
        self.organizeTask?.cancel()
        self.organizeTask = nil
        self.state.isAgentOrganizing = false
    }
    
    
    private func undoAgentOrganize() {
        let entries = self.state.lastOrganizeUndoSnapshot
        let createdGroups = self.state.lastOrganizeCreatedGroups
        guard !entries.isEmpty else { return }
        
        self.db.withTransaction {
            for entry in entries {
                self.db.assignDocumentGroup(
                    id: entry.dbRecordID,
                    filePath: entry.filePath,
                    groupName: entry.previousGroup,
                    fallbackTitle: entry.previousTitle,
                    fallbackSyntax: entry.syntax,
                    fallbackContent: entry.content,
                    reloadAfter: false
                )
                if entry.titleWasChanged {
                    if let liveDoc = self.state.liveDocument(for: entry.itemID) {
                        _ = try? WorkspaceOrganizer.renameDocument(liveDoc, to: entry.previousTitle, reloadAfter: false)
                    } else if entry.filePath == nil {
                        self.db.renameDocument(
                            oldID: entry.dbRecordID,
                            oldFilePath: nil,
                            newID: entry.dbRecordID,
                            newTitle: entry.previousTitle,
                            newFilePath: nil,
                            reloadAfter: false
                        )
                    }
                }
            }
            
            for group in createdGroups {
                let remaining = self.db.documents.contains { $0.groupName == group }
                if !remaining {
                    self.db.deleteDocumentGroup(named: group)
                }
            }
        }
        self.db.reloadDocuments()
        
        self.state.lastOrganizeUndoSnapshot = []
        self.state.lastOrganizeCreatedGroups = []
        self.state.agentOrganizeSummary = nil
        self.state.sidebarFilter = .all
        self.state.refresh()
        self.showToast("已撤销整理")
    }
    
    
    // MARK: Selection, QuickLook & Keyboard Navigation
    
    private func selectedItem(in items: [DocumentCenterState.ManagedDocumentItem]) -> DocumentCenterState.ManagedDocumentItem? {
        if let id = self.state.selectedID, let match = items.first(where: { $0.id == id }) {
            return match
        }
        return items.first
    }
    
    
    private func keyboardNavigationItems(displayedItems: [DocumentCenterState.ManagedDocumentItem]) -> [DocumentCenterState.ManagedDocumentItem] {
        let hasQuery = !self.state.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if hasQuery && !self.state.searchHits.isEmpty {
            let map = Dictionary(uniqueKeysWithValues: displayedItems.map { ($0.id, $0) })
            return self.state.searchHits.compactMap { map[$0.id] }
        }
        return displayedItems
    }
    
    
    private func unfocusSearchField() {
        self.isSearchFocused = false
        if let tv = NSApp.keyWindow?.firstResponder as? NSTextView, tv.isEditable {
            NSApp.keyWindow?.makeFirstResponder(nil)
        }
    }
    
    
    private func handleEscapePop() -> Bool {
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
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if flags == .command && event.charactersIgnoringModifiers?.lowercased() == "f" {
                self.isSearchFocused = true
                return nil
            }
            
            if let tv = (event.window ?? NSApp.keyWindow)?.firstResponder as? NSTextView, tv.isEditable {
                if event.keyCode == 125 && self.isSearchFocused {  // Down arrow exits search into list
                    self.unfocusSearchField()
                    return nil
                }
                return event
            }
            
            let navList = self.keyboardNavigationItems(displayedItems: self.state.displayedItems)
            guard !navList.isEmpty else { return event }
            
            switch event.keyCode {
                case 126:  // Up
                    self.stepSelection(by: -1, in: navList)
                    return nil
                case 125:  // Down
                    self.stepSelection(by: 1, in: navList)
                    return nil
                case 36:  // Return -> open
                    if let active = self.selectedItem(in: navList), !active.isTrashed {
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
        self.showToast("已移入废纸篓")
    }
    
    
    private func restore(item: DocumentCenterState.ManagedDocumentItem) {
        self.db.restoreDocument(id: item.dbRecordID ?? item.id, filePath: item.filePath)
        self.state.refresh()
        self.showToast("已恢复")
    }
    
    
    private func permanentlyDelete(item: DocumentCenterState.ManagedDocumentItem) {
        self.confirmDestructive(title: "彻底删除「\(item.title)」？") {
            self.db.permanentlyDeleteDocument(id: item.dbRecordID ?? item.id, filePath: item.filePath)
            self.state.refresh()
            self.showToast("已彻底删除")
        }
    }
    
    
    private func confirmEmptyTrash() {
        self.confirmDestructive(title: "清空废纸篓（\(self.state.trashedItems.count) 篇）？") {
            self.db.emptyDocumentTrash()
            self.state.refresh()
            self.showToast("已清空废纸篓")
        }
    }
    
    
    private func confirmDestructive(title: String, action: @escaping () -> Void) {
        let alert = NSAlert()
        alert.messageText = title
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
            self.state.sidebarFilter = .group(created)
            self.state.refresh()
            self.showToast("已新建分组「\(created)」")
        }
    }
    
    
    private func commitGroupRename(oldName: String) {
        let trimmed = self.groupRenameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        self.renamingGroupName = nil
        guard !trimmed.isEmpty, trimmed != oldName else { return }
        if self.db.renameDocumentGroup(from: oldName, to: trimmed) {
            if self.state.sidebarFilter == .group(oldName) {
                self.state.sidebarFilter = .group(trimmed)
            }
            self.state.refresh()
            self.showToast("已重命名为「\(trimmed)」")
        } else {
            self.showToast("分组名称无效")
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
        self.showToast(groupName.isEmpty ? "已移至未分组" : "已移至「\(groupName)」")
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
                self.showToast("重命名失败")
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
                self.showToast("重命名失败")
            }
        }
        self.isRenaming = false
        self.state.refresh()
        self.state.selectedID = targetSelectionID
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
        
        // Stage 1 & 2: Rename Titles + Organize Star-Map Groups & Semantic Relations
        var renamedCount = 0
        var regroupedCount = 0
        var usedAI = false
        
        if !candidates.isEmpty && (self.renameUntitledEnabled || self.organizeStarMapEnabled) {
            let inputs = candidates.map { item in
                DocumentCenterAgentOrganizer.InputItem(
                    id: item.canonicalID,
                    title: item.title,
                    syntax: item.syntax,
                    currentGroup: item.currentGroup,
                    excerpt: String(item.content.prefix(360)),
                    isUntitled: DocumentCenterAgentOrganizer.isGenericUntitled(item.title, hasFilePath: item.filePath != nil)
                )
            }
            let byID = Dictionary(uniqueKeysWithValues: candidates.map { ($0.canonicalID, $0) })
            let planOutcome: (plan: DocumentCenterAgentOrganizer.Plan, usedAI: Bool)
            if allowRemoteAI {
                planOutcome = await DocumentCenterAgentOrganizer.generatePlan(
                    items: inputs,
                    existingGroups: self.database.documentGroups,
                    analyticsFeature: "scheduledNightlyOrganize"
                )
            } else {
                planOutcome = (
                    DocumentCenterAgentOrganizer.buildLocalFallbackPlan(
                        items: inputs,
                        existingGroups: self.database.documentGroups
                    ),
                    false
                )
            }
            usedAI = planOutcome.usedAI
            
            let allowRename = self.renameUntitledEnabled
            let allowRegroup = self.organizeStarMapEnabled
            self.database.withTransaction {
                for assignment in planOutcome.plan.assignments {
                    guard let item = byID[assignment.id] else { continue }
                    let targetGroup = assignment.group
                    let wantsRename: String? = {
                        guard allowRename,
                              let suggested = assignment.suggestedTitle,
                              !suggested.isEmpty,
                              suggested != item.title,
                              DocumentCenterAgentOrganizer.isGenericUntitled(item.title, hasFilePath: item.filePath != nil)
                        else { return nil }
                        return suggested
                    }()
                    
                    let groupChanged = allowRegroup && (targetGroup != item.currentGroup)
                    guard groupChanged || wantsRename != nil else { continue }
                    
                    if groupChanged {
                        self.database.assignDocumentGroup(
                            id: item.dbRecordID,
                            filePath: item.filePath,
                            groupName: targetGroup,
                            fallbackTitle: wantsRename ?? item.title,
                            fallbackSyntax: item.syntax,
                            fallbackContent: item.content,
                            reloadAfter: false
                        )
                        regroupedCount += 1
                    }
                    
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
                }
            }
            
            if renamedCount > 0 || regroupedCount > 0 {
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


// MARK: - Dedicated Scheduled Tasks Settings Pane (Zero Clutter · Intuitive UX)

struct ScheduledAIOrganizeSettingsCard: View {
    
    var isEmbeddedInGroupCard: Bool = false
    
    @Environment(\.colorScheme) private var colorScheme
    @State private var organizer = ScheduledAIDocumentOrganizer.shared
    @State private var studioPalette = StudioPaletteManager.shared
    @State private var justCompleted = false
    
    private static let timePresets: [(hour: Int, minute: Int, label: String)] = [
        (3, 0, "03:00"),
        (9, 0, "09:00"),
        (18, 30, "18:30"),
        (23, 0, "23:00"),
    ]
    
    private static let minuteSteps: [Int] = [0, 5, 10, 15, 20, 25, 30, 35, 40, 45, 50, 55]
    
    private var isDark: Bool { self.colorScheme == .dark }
    
    private var accent: Color {
        self.studioPalette.tokens(isDark: self.isDark).accent
    }
    
    private var cardSurface: Color {
        self.isDark ? Color.white.opacity(0.055) : Color.white
    }
    
    private var cardBorder: Color {
        self.isDark ? Color.white.opacity(0.09) : Color.black.opacity(0.07)
    }
    
    private var dividerColor: Color {
        self.isDark ? Color.white.opacity(0.07) : Color.black.opacity(0.06)
    }
    
    private var chipSurface: Color {
        self.isDark ? Color.white.opacity(0.07) : Color.black.opacity(0.045)
    }
    
    var body: some View {
        @Bindable var bindableOrganizer = self.organizer
        let isActive = self.organizer.isEnabled && self.organizer.hasAnyStepEnabled
        
        VStack(alignment: .leading, spacing: 18) {
            // Card 1: Master Schedule + Frequency + Preset & Custom Time Picker
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(self.accent.opacity(self.isDark ? 0.22 : 0.12))
                        Image(systemName: "clock.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(self.accent)
                    }
                    .frame(width: 26, height: 26)
                    
                    Text(AppLanguage.text("自动整理文档", en: "Auto-Organize Documents"))
                        .font(.system(size: 13.5, weight: .semibold))
                    
                    Spacer(minLength: 8)
                    
                    self.scheduleStatusPill(isActive: isActive)
                    
                    Toggle("", isOn: $bindableOrganizer.isEnabled)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }
                .padding(.horizontal, 14)
                .frame(minHeight: 46)
                
                if self.organizer.isEnabled {
                    self.rowDivider
                    
                    // Frequency segmented selector
                    HStack(spacing: 12) {
                        Text(AppLanguage.text("执行频率", en: "Frequency"))
                            .font(.system(size: 13))
                        
                        Spacer()
                        
                        Picker("", selection: $bindableOrganizer.frequency) {
                            ForEach(ScheduledAIDocumentOrganizer.ScheduleFrequency.allCases) { freq in
                                Text(freq.title).tag(freq)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .frame(width: 188)
                    }
                    .padding(.horizontal, 14)
                    .frame(minHeight: 44)
                    
                    self.rowDivider
                    
                    // Intuitive time presets + clean HH:mm dropdown selector
                    HStack(spacing: 8) {
                        Text(AppLanguage.text("执行时间", en: "Run Time"))
                            .font(.system(size: 13))
                        
                        Spacer(minLength: 8)
                        
                        HStack(spacing: 5) {
                            ForEach(Self.timePresets, id: \.label) { preset in
                                let selected = (self.organizer.scheduledHour == preset.hour && self.organizer.scheduledMinute == preset.minute)
                                Button {
                                    withAnimation(.easeOut(duration: 0.14)) {
                                        self.organizer.updateScheduledTime(hour: preset.hour, minute: preset.minute)
                                    }
                                } label: {
                                    Text(preset.label)
                                        .font(.system(size: 11.5, weight: selected ? .semibold : .medium, design: .monospaced).monospacedDigit())
                                        .foregroundStyle(selected ? Color.white : Color.primary.opacity(0.78))
                                        .padding(.horizontal, 8)
                                        .frame(height: 24)
                                        .background(
                                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                                .fill(selected ? self.accent : self.chipSurface)
                                        )
                                        .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                                }
                                .buttonStyle(.plain)
                                .pointerStyle(.link)
                            }
                        }
                        
                        Rectangle()
                            .fill(self.dividerColor)
                            .frame(width: 1, height: 14)
                            .padding(.horizontal, 2)
                        
                        self.customTimeMenu
                    }
                    .padding(.horizontal, 14)
                    .frame(minHeight: 46)
                }
            }
            .background(self.cardSurface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(self.cardBorder, lineWidth: 1))
            
            // Card 2: Explicit Toggleable Task Steps (Replaces all explanatory subtitles)
            VStack(alignment: .leading, spacing: 6) {
                Text(AppLanguage.text("执行内容", en: "Actions"))
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 4)
                
                VStack(alignment: .leading, spacing: 0) {
                    self.stepToggleRow(
                        symbol: "pencil.line",
                        title: AppLanguage.text("未命名文档自动起标题", en: "Name Untitled Documents"),
                        isOn: $bindableOrganizer.renameUntitledEnabled
                    )
                    
                    self.rowDivider
                    
                    self.stepToggleRow(
                        symbol: "point.3.connected.trianglepath.dotted",
                        title: AppLanguage.text("文档分组与星图连线", en: "Group Documents & Star Map"),
                        isOn: $bindableOrganizer.organizeStarMapEnabled
                    )
                    
                    self.rowDivider
                    
                    self.stepToggleRow(
                        symbol: "chart.bar.doc.horizontal",
                        title: AppLanguage.text("更新今日「干了啥」与「要干啥」", en: "Refresh Daily Summary & Next Actions"),
                        isOn: $bindableOrganizer.refreshDashboardEnabled
                    )
                    
                    self.rowDivider
                    
                    self.stepToggleRow(
                        symbol: "moon.zzz",
                        title: AppLanguage.text("休眠错过后唤醒补跑", en: "Catch Up After Sleep"),
                        isOn: $bindableOrganizer.catchUpOnWakeEnabled
                    )
                }
                .background(self.cardSurface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(self.cardBorder, lineWidth: 1))
            }
            .opacity(self.organizer.isEnabled ? 1.0 : 0.52)
            .disabled(!self.organizer.isEnabled)
            
            // Card 3: Run Now & Latest Result Status
            HStack(spacing: 12) {
                HStack(spacing: 7) {
                    Circle()
                        .fill(self.organizer.lastSummary.isEmpty ? Color.secondary.opacity(0.4) : Color.green.opacity(0.85))
                        .frame(width: 7, height: 7)
                    
                    Text(
                        self.organizer.lastSummary.isEmpty
                            ? AppLanguage.text("尚未执行过", en: "Not run yet")
                            : self.organizer.lastSummary
                    )
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(self.organizer.lastSummary.isEmpty ? .secondary : .primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                }
                
                Spacer(minLength: 8)
                
                if self.organizer.isRunning {
                    HStack(spacing: 6) {
                        ProgressView()
                            .controlSize(.small)
                        Text(AppLanguage.text("整理中…", en: "Running…"))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 28)
                    .background(self.chipSurface, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                } else {
                    Button {
                        Task {
                            _ = await self.organizer.runOrganizePipeline()
                            withAnimation(.easeOut(duration: 0.16)) {
                                self.justCompleted = true
                            }
                            try? await Task.sleep(for: .seconds(2.2))
                            withAnimation(.easeOut(duration: 0.2)) {
                                self.justCompleted = false
                            }
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: self.justCompleted ? "checkmark" : "play.fill")
                                .font(.system(size: 10.5, weight: .semibold))
                            Text(self.justCompleted
                                 ? AppLanguage.text("已完成", en: "Done")
                                 : AppLanguage.text("立即执行", en: "Run Now"))
                                .font(.system(size: 12.5, weight: .semibold))
                        }
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 12)
                        .frame(height: 28)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(self.justCompleted ? Color.green : self.accent)
                        )
                        .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(!self.organizer.hasAnyStepEnabled)
                    .opacity(self.organizer.hasAnyStepEnabled ? 1.0 : 0.45)
                    .pointerStyle(self.organizer.hasAnyStepEnabled ? .link : .default)
                }
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 48)
            .background(self.cardSurface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(self.cardBorder, lineWidth: 1))
        }
        .animation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.20), value: self.organizer.isEnabled)
    }
    
    
    private var rowDivider: some View {
        Rectangle()
            .fill(self.dividerColor)
            .frame(height: 0.75)
            .padding(.horizontal, 14)
    }
    
    
    private func scheduleStatusPill(isActive: Bool) -> some View {
        HStack(spacing: 5) {
            if self.organizer.isRunning {
                ProgressView()
                    .controlSize(.mini)
                Text(AppLanguage.text("整理中", en: "Running"))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(self.accent)
            } else {
                Circle()
                    .fill(isActive ? Color.green : Color.secondary.opacity(0.45))
                    .frame(width: 6, height: 6)
                Text(self.organizer.nextScheduledLabel())
                    .font(.system(size: 11, weight: .medium, design: .monospaced).monospacedDigit())
                    .foregroundStyle(isActive ? Color.primary.opacity(0.75) : Color.secondary)
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 22)
        .background(self.chipSurface, in: Capsule())
    }
    
    
    private var customTimeMenu: some View {
        HStack(spacing: 4) {
            Menu {
                ForEach(0..<24, id: \.self) { hour in
                    Button {
                        self.organizer.updateScheduledTime(hour: hour, minute: self.organizer.scheduledMinute)
                    } label: {
                        HStack {
                            Text(String(format: "%02d:00", hour))
                            if hour == self.organizer.scheduledHour {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                Text(AppLanguage.text(String(format: "%02d 时", self.organizer.scheduledHour), en: String(format: "%02dh", self.organizer.scheduledHour)))
                    .font(.system(size: 11.5, weight: .semibold, design: .monospaced).monospacedDigit())
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 8)
                    .frame(height: 24)
                    .background(self.chipSurface, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(self.cardBorder, lineWidth: 0.8)
                    )
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .pointerStyle(.link)
            
            Menu {
                ForEach(Self.minuteSteps, id: \.self) { minute in
                    Button {
                        self.organizer.updateScheduledTime(hour: self.organizer.scheduledHour, minute: minute)
                    } label: {
                        HStack {
                            Text(String(format: ":%02d", minute))
                            if minute == self.organizer.scheduledMinute {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                Text(AppLanguage.text(String(format: "%02d 分", self.organizer.scheduledMinute), en: String(format: "%02dm", self.organizer.scheduledMinute)))
                    .font(.system(size: 11.5, weight: .semibold, design: .monospaced).monospacedDigit())
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 8)
                    .frame(height: 24)
                    .background(self.chipSurface, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(self.cardBorder, lineWidth: 0.8)
                    )
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .pointerStyle(.link)
        }
    }
    
    
    private func stepToggleRow(symbol: String, title: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(isOn.wrappedValue ? self.accent : Color.secondary)
                .frame(width: 18, alignment: .center)
            
            Text(title)
                .font(.system(size: 13, weight: .regular))
            
            Spacer()
            
            Toggle("", isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 42)
    }
}
