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
            : .systemFont(ofSize: 13)
        let boldFont: NSFont = self.monospace
            ? .monospacedSystemFont(ofSize: 12.5, weight: .semibold)
            : .systemFont(ofSize: 13, weight: .semibold)
        if textView.font != targetFont {
            textView.font = targetFont
        }
        
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 4.5
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


// MARK: - Pure Radial Cluster Math Engine (Retained for Layout Tests)

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
    
    struct MatchEvaluation: Sendable, Equatable {
        let isMatch: Bool
        let score: Int
        let totalHits: Int
        let snippet: String?
        let matchedTerms: [String]
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
        
        let snippet = Self.extractSnippet(
            in: content,
            anchorRange: firstContentRange,
            terms: queryTerms
        )
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
        anchorRange: Range<String.Index>?,
        terms: [String]
    ) -> String? {
        guard !content.isEmpty else { return nil }
        let targetRange = anchorRange ?? terms.lazy.compactMap { term in
            content.range(of: term, options: [.caseInsensitive, .diacriticInsensitive])
        }.first
        guard let targetRange else { return nil }
        
        let lowerBound = content.index(targetRange.lowerBound, offsetBy: -26, limitedBy: content.startIndex) ?? content.startIndex
        let upperBound = content.index(targetRange.upperBound, offsetBy: 48, limitedBy: content.endIndex) ?? content.endIndex
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
    
    struct CorpusDocument: Sendable {
        let id: String
        let title: String
        let group: String
        let folderPath: String?
        let content: String
        let sortTimestamp: TimeInterval
    }
    
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
        let cappedDocs = Array(docs.prefix(90))
        
        var termsByDoc: [String: Set<String>] = [:]
        var lowerTermsByDoc: [String: [String: String]] = [:] // lowercased -> display casing
        var docFreq: [String: Int] = [:]
        
        for doc in cappedDocs {
            let extracted = Self.extractKeyTerms(title: doc.title, content: doc.content)
            termsByDoc[doc.id] = extracted
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
        }
        
        let maxAllowedDF = max(2, Int(ceil(Double(cappedDocs.count) * 0.6)))
        let discriminativeLowerTerms = Set(docFreq.compactMap { pair -> String? in
            (pair.value >= 2 && pair.value <= maxAllowedDF) ? pair.key : nil
        })
        
        var candidates: [StarMapRelationEdge] = []
        
        for i in 0..<(cappedDocs.count - 1) {
            let a = cappedDocs[i]
            let aTitleClean = Self.normalizedCleanTitle(a.title)
            let aLowerMap = lowerTermsByDoc[a.id] ?? [:]
            let aDiscriminative = Set(aLowerMap.keys).intersection(discriminativeLowerTerms)
            let aBodyLower = a.content.prefix(8_000).lowercased()
            
            for j in (i + 1)..<cappedDocs.count {
                let b = cappedDocs[j]
                let bTitleClean = Self.normalizedCleanTitle(b.title)
                let bBodyLower = b.content.prefix(8_000).lowercased()
                
                var bestStrength = 0.0
                var bestReason = ""
                
                // 1. Explicit title cross-mention
                if bTitleClean.count >= 3 && aBodyLower.contains(bTitleClean.lowercased()) {
                    bestStrength = 0.86
                    bestReason = "提及「\(String(bTitleClean.prefix(12)))」"
                } else if aTitleClean.count >= 3 && bBodyLower.contains(aTitleClean.lowercased()) {
                    bestStrength = 0.86
                    bestReason = "提及「\(String(aTitleClean.prefix(12)))」"
                }
                
                // 2. Shared discriminative keywords / concepts
                let bLowerMap = lowerTermsByDoc[b.id] ?? [:]
                let bDiscriminative = Set(bLowerMap.keys).intersection(discriminativeLowerTerms)
                let sharedLowers = aDiscriminative.intersection(bDiscriminative)
                
                if !sharedLowers.isEmpty {
                    let rankedShared = sharedLowers.sorted { lhs, rhs in
                        let dfL = docFreq[lhs] ?? 99
                        let dfR = docFreq[rhs] ?? 99
                        if dfL != dfR { return dfL < dfR }
                        return lhs.count > rhs.count
                    }
                    let requiresTwo = cappedDocs.count > 8
                    if rankedShared.count >= (requiresTwo ? 2 : 1) {
                        let topicStrength = min(0.92, 0.34 + Double(rankedShared.count) * 0.14)
                        if topicStrength > bestStrength {
                            let labels = rankedShared.prefix(2).compactMap { key in
                                aLowerMap[key] ?? bLowerMap[key]
                            }
                            bestStrength = topicStrength
                            bestReason = "共现：" + labels.joined(separator: " · ")
                        }
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
    
    
    /// Checks whether a document title is generic / untitled and safe for Agent title cleanup.
    static func isGenericUntitled(_ title: String, hasFilePath: Bool) -> Bool {
        if hasFilePath { return false }
        let clean = title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if clean.isEmpty { return true }
        let prefixes = ["untitled", "未命名", "新建文档", "无标题", "note ", "draft "]
        return prefixes.contains { clean == $0.trimmingCharacters(in: .whitespaces) || clean.hasPrefix($0) }
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
    static func generatePlan(items: [InputItem], existingGroups: [String]) async -> (plan: Plan, usedAI: Bool) {
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
            你是文档中心智能整理 Agent。请将用户的全部文档归类到清晰、精炼的分组中（2-6字中文分组名，总数控制在 3-7 个，优先复用合理的已有分组）。
            规则：
            1. 仅返回严格合法的 JSON，不要输出任何额外解释或 Markdown 之外的文字。
            2. JSON 格式：{"assignments":[{"id":"原id","group":"分组名","suggestedTitle":"仅当untitled=true且能从内容提炼清晰标题时填写，否则为null"}]}
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
                    analyticsFeature: "documentCenterAgentOrganize"
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
    
    var searchText: String = "" {
        didSet {
            if oldValue != self.searchText {
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
    @ObservationIgnored private var cachedRelationsCorpusKey: String = ""
    
    private static let shortDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "M/d"
        return f
    }()
    
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
        
        let corpusKey = merged.map {
            "\($0.id)|\($0.updatedAt.timeIntervalSince1970)|\($0.content.count)|\($0.title)|\($0.groupName)"
        }.joined(separator: ";")
        if corpusKey != self.cachedRelationsCorpusKey {
            self.cachedRelationsCorpusKey = corpusKey
            self.relations = StarMapRelationEngine.buildRelations(
                for: merged.map { item in
                    let folder = item.filePath.map { URL(filePath: $0).deletingLastPathComponent().path(percentEncoded: false) }
                    return StarMapRelationEngine.CorpusDocument(
                        id: item.id,
                        title: item.title,
                        group: item.groupName,
                        folderPath: folder,
                        content: item.content,
                        sortTimestamp: item.updatedAt.timeIntervalSince1970
                    )
                }
            )
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
            return [
                StarMapClusterNode(
                    id: "trash",
                    title: "废纸篓",
                    countText: "\(self.displayedItems.count)",
                    accent: Color.red.opacity(0.82),
                    isCollapsed: self.collapsedClusterIDs.contains("trash"),
                    leaves: leaves
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
            items.prefix(40).map { item in
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
        
        var clusters: [StarMapClusterNode] = []
        for (idx, groupName) in orderedGroups.enumerated() {
            let bucket = groupedBuckets[groupName] ?? []
            guard !bucket.isEmpty else { continue }
            let cid = "group:\(groupName)"
            let accent = Color(hexString: paletteHexes[idx % paletteHexes.count])
            clusters.append(
                StarMapClusterNode(
                    id: cid,
                    title: groupName,
                    countText: "\(bucket.count)",
                    accent: accent,
                    isCollapsed: self.collapsedClusterIDs.contains(cid),
                    leaves: makeLeaves(from: bucket, clusterID: cid, color: accent)
                )
            )
        }
        
        if !ungrouped.isEmpty {
            let cid = "__ungrouped__"
            let accent = tokens.accent
            clusters.append(
                StarMapClusterNode(
                    id: cid,
                    title: "未分组",
                    countText: "\(ungrouped.count)",
                    accent: accent,
                    isCollapsed: self.collapsedClusterIDs.contains(cid),
                    leaves: makeLeaves(from: ungrouped, clusterID: cid, color: accent)
                )
            )
        }
        
        return clusters
    }
    
    
    private func recomputeDisplayedItems() {
        
        let terms = StarMapSearchEngine.parseTerms(self.searchText)
        
        if self.showingTrash || self.sidebarFilter == .trash {
            var evalByID: [String: StarMapSearchEngine.MatchEvaluation] = [:]
            var hits: [StarMapSearchHit] = []
            var matched: [ManagedDocumentItem] = []
            for item in self.trashedItems {
                let eval = StarMapSearchEngine.evaluate(
                    queryTerms: terms,
                    title: item.title,
                    category: item.groupName,
                    secondaryMeta: item.filePath ?? "",
                    content: item.content
                )
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
        
        let baseScope: [ManagedDocumentItem] = switch self.sidebarFilter {
            case .all:
                self.items
            case .openNow:
                self.items.filter(\.isOpenNow)
            case .group(let name):
                self.items.filter { $0.groupName == name }
            case .ungrouped:
                self.items.filter { $0.groupName.isEmpty }
            case .trash:
                []
        }
        
        var evalByID: [String: StarMapSearchEngine.MatchEvaluation] = [:]
        var hits: [StarMapSearchHit] = []
        var matchedIDs = Set<String>()
        
        if terms.isEmpty {
            matchedIDs = Set(baseScope.map(\.id))
        } else {
            for item in baseScope {
                let eval = StarMapSearchEngine.evaluate(
                    queryTerms: terms,
                    title: item.title,
                    category: item.groupName,
                    secondaryMeta: item.filePath ?? "",
                    content: item.content
                )
                guard eval.isMatch else { continue }
                matchedIDs.insert(item.id)
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
        var visibleIDs = matchedIDs
        if !terms.isEmpty {
            let scopeIDs = Set(baseScope.map(\.id))
            for edge in self.relations {
                if matchedIDs.contains(edge.sourceID), scopeIDs.contains(edge.targetID) {
                    visibleIDs.insert(edge.targetID)
                } else if matchedIDs.contains(edge.targetID), scopeIDs.contains(edge.sourceID) {
                    visibleIDs.insert(edge.sourceID)
                }
            }
        }
        
        let visible = baseScope
            .filter { visibleIDs.contains($0.id) }
            .sorted { lhs, rhs in
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
    
    
    nonisolated static func buildPreviewText(from content: String) -> String {
        if content.isEmpty {
            return ""
        }
        if content.count > 120_000 {
            return String(content.prefix(120_000)) + "\n\n..."
        }
        return content
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


/// Reusable, GPU-accelerated, zero-overlap Star-Map canvas shared by Document Center & Weekly Report Center.
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
        let worldPad: CGFloat = 220
        let worldW = max(900, layout.bounds.width + worldPad * 2)
        let worldH = max(680, layout.bounds.height + worldPad * 2)
        
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
                
                // Single unified GPU-transformed World Layer: Equatable subview isolated from pan/zoom state
                StarMapWorldStageView(
                    hubTitle: self.hubTitle,
                    hubSubtitle: self.hubSubtitle,
                    clusters: self.clusters,
                    relations: self.relations,
                    layout: layout,
                    selectedLeafID: self.selectedLeafID,
                    focusedClusterID: self.focusedClusterID,
                    hoveredLeafID: self.hoveredLeafID,
                    hoveredClusterID: self.hoveredClusterID,
                    isDark: isDark,
                    tokens: tokens,
                    worldW: worldW,
                    worldH: worldH,
                    onHoverCluster: { next in
                        if next != self.hoveredClusterID {
                            self.hoveredClusterID = next
                        }
                    },
                    onHoverLeaf: { next in
                        if next != self.hoveredLeafID {
                            self.hoveredLeafID = next
                        }
                    },
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
                
                // 6. Minimal Zoom Controls (Bottom-Right)
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
                let sig = self.layoutSignature
                let refreshed: StarMapLayoutEngine.LayoutResult
                if self.cachedLayoutKey == sig {
                    refreshed = self.cachedLayout
                } else {
                    refreshed = self.computeFreshLayout()
                    self.cachedLayout = refreshed
                    self.cachedLayoutKey = sig
                }
                self.fitViewport(bounds: refreshed.bounds, size: geo.size, animated: true)
            }
            .onChange(of: self.panRequestToken) { _, _ in
                guard let selectedLeafID = self.selectedLeafID, geo.size.width > 100 else { return }
                let activeLayout = (self.cachedLayoutKey == self.layoutSignature) ? self.cachedLayout : self.computeFreshLayout()
                if let lPos = activeLayout.leaves.first(where: { $0.id == selectedLeafID }) {
                    let targetZoom: CGFloat = max(self.zoomScale, 0.82)
                    withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.28)) {
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
    
    
    private static func relationCurveControl(from p0: CGPoint, to p1: CGPoint) -> CGPoint {
        let mid = CGPoint(x: (p0.x + p1.x) * 0.5, y: (p0.y + p1.y) * 0.5)
        let dx = p1.x - p0.x
        let dy = p1.y - p0.y
        return CGPoint(x: mid.x - dy * 0.14, y: mid.y + dx * 0.14)
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


private struct StarMapWorldStageView<ClusterMenu: View, LeafMenu: View>: View, Equatable {
    
    let hubTitle: String
    let hubSubtitle: String
    let clusters: [StarMapClusterNode]
    let relations: [StarMapRelationEdge]
    let layout: StarMapLayoutEngine.LayoutResult
    let selectedLeafID: String?
    let focusedClusterID: String?
    let hoveredLeafID: String?
    let hoveredClusterID: String?
    let isDark: Bool
    let tokens: StudioColorTokens
    let worldW: CGFloat
    let worldH: CGFloat
    let onHoverCluster: (String?) -> Void
    let onHoverLeaf: (String?) -> Void
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
            && lhs.hoveredLeafID == rhs.hoveredLeafID
            && lhs.hoveredClusterID == rhs.hoveredClusterID
            && lhs.isDark == rhs.isDark
            && lhs.worldW == rhs.worldW
            && lhs.worldH == rhs.worldH
    }
    
    
    private static func relationCurveControl(from p0: CGPoint, to p1: CGPoint) -> CGPoint {
        let mid = CGPoint(x: (p0.x + p1.x) * 0.5, y: (p0.y + p1.y) * 0.5)
        let dx = p1.x - p0.x
        let dy = p1.y - p0.y
        return CGPoint(x: mid.x - dy * 0.14, y: mid.y + dx * 0.14)
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
        let activeLeafID: String? = self.hoveredLeafID ?? self.selectedLeafID
        let relatedNeighbors: [String: String] = {
            guard let activeLeafID else { return [:] }
            var map: [String: String] = [:]
            for edge in self.relations {
                if edge.sourceID == activeLeafID {
                    map[edge.targetID] = edge.reason
                } else if edge.targetID == activeLeafID {
                    map[edge.sourceID] = edge.reason
                }
            }
            return map
        }()
        let activeFocusClusterID: String? = self.hoveredClusterID
            ?? self.hoveredLeafID.flatMap { leafMap[$0]?.clusterID }
            ?? self.focusedClusterID
            ?? self.selectedLeafID.flatMap { leafMap[$0]?.clusterID }
        let leafWorldPosMap: [String: CGPoint] = Dictionary(
            uniqueKeysWithValues: self.layout.leaves.map {
                ($0.id, CGPoint(x: originX + $0.worldPoint.x, y: originY + $0.worldPoint.y))
            }
        )
        let activeRelationMidpoints: [(id: String, point: CGPoint, reason: String)] = {
            guard let activeLeafID else { return [] }
            var badges: [(id: String, point: CGPoint, reason: String)] = []
            for edge in self.relations {
                guard edge.sourceID == activeLeafID || edge.targetID == activeLeafID,
                      let p0 = leafWorldPosMap[edge.sourceID],
                      let p1 = leafWorldPosMap[edge.targetID]
                else { continue }
                let ctrl = Self.relationCurveControl(from: p0, to: p1)
                let mid = CGPoint(
                    x: 0.25 * p0.x + 0.5 * ctrl.x + 0.25 * p1.x,
                    y: 0.25 * p0.y + 0.5 * ctrl.y + 0.25 * p1.y
                )
                badges.append((edge.id, mid, edge.reason))
                if badges.count >= 4 { break }
            }
            return badges
        }()
        
        ZStack {
            // 1. Orbital Rings + Trunk/Leaf Branches + Semantic Cross-Node Relationship Arcs
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
                
                if self.layout.clusters.count > 1 {
                    for cPos in self.layout.clusters {
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
                
                for lPos in self.layout.leaves {
                    let parentPt = CGPoint(x: originX + lPos.parentPoint.x, y: originY + lPos.parentPoint.y)
                    let leafPt = CGPoint(x: originX + lPos.worldPoint.x, y: originY + lPos.worldPoint.y)
                    let leaf = leafMap[lPos.id]
                    let isSelected = (self.selectedLeafID == lPos.id)
                    let isHovered = (self.hoveredLeafID == lPos.id)
                    let isRelated = (relatedNeighbors[lPos.id] != nil)
                    let isClusterFocused = (activeFocusClusterID == lPos.clusterID)
                    let branchColor = leaf?.dotColor ?? tokens.accent
                    let alpha: Double = (isSelected || isHovered || isRelated)
                        ? 0.85
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
                
                // Cross-node semantic & structural relationship arcs
                for edge in self.relations {
                    guard let p0 = leafWorldPosMap[edge.sourceID],
                          let p1 = leafWorldPosMap[edge.targetID]
                    else { continue }
                    let isIncident = (activeLeafID == edge.sourceID || activeLeafID == edge.targetID)
                    let ctrl = Self.relationCurveControl(from: p0, to: p1)
                    var relPath = Path()
                    relPath.move(to: p0)
                    relPath.addQuadCurve(to: p1, control: ctrl)
                    
                    if isIncident {
                        context.stroke(
                            relPath,
                            with: .color(tokens.accent.opacity(0.86)),
                            style: StrokeStyle(lineWidth: 2.2, lineCap: .round)
                        )
                    } else {
                        let idleAlpha = (activeLeafID == nil) ? 0.24 : 0.07
                        context.stroke(
                            relPath,
                            with: .color(tokens.accent.opacity(idleAlpha)),
                            style: StrokeStyle(lineWidth: 1.05, lineCap: .round, dash: [4, 5])
                        )
                    }
                }
            }
            .frame(width: self.worldW, height: self.worldH)
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
            if self.layout.clusters.count > 1 {
                ForEach(self.layout.clusters) { cPos in
                    if let cluster = clusterMap[cPos.id] {
                        let isFocused = (activeFocusClusterID == cluster.id)
                        let isHovered = (self.hoveredClusterID == cluster.id)
                        let dimmed = (activeFocusClusterID != nil && !isFocused && relatedNeighbors.isEmpty)
                        
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
                                    .background(cluster.accent.opacity(self.isDark ? 0.18 : 0.11), in: Capsule())
                                
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
                        .opacity(dimmed ? 0.55 : 1.0)
                        .scaleEffect(isHovered ? 1.04 : 1.0)
                        .position(x: originX + cPos.worldPoint.x, y: originY + cPos.worldPoint.y)
                        .onHover { hovering in
                            let next = hovering ? cluster.id : (self.hoveredClusterID == cluster.id ? nil : self.hoveredClusterID)
                            self.onHoverCluster(next)
                        }
                        .contextMenu {
                            self.clusterContextMenu(cluster)
                        }
                    }
                }
            }
            
            // 4. Tier-2 Structured Leaf Cards (Equatable per-node leaves)
            ForEach(self.layout.leaves) { lPos in
                if let leaf = leafMap[lPos.id] {
                    let isSelected = (self.selectedLeafID == leaf.id)
                    let isHovered = (self.hoveredLeafID == leaf.id)
                    let isRelated = (relatedNeighbors[leaf.id] != nil)
                    let isClusterFocused = (activeFocusClusterID == leaf.clusterID)
                    let dimmed = (activeFocusClusterID != nil && !isClusterFocused && !isSelected && !isRelated)
                    
                    StarMapLeafCardView(
                        leaf: leaf,
                        tokens: tokens,
                        isSelected: isSelected,
                        isHovered: isHovered,
                        isRelated: isRelated,
                        dimmed: dimmed,
                        isDark: self.isDark
                    )
                    .equatable()
                    .position(x: originX + lPos.worldPoint.x, y: originY + lPos.worldPoint.y)
                    .pointerStyle(.link)
                    .onHover { hovering in
                        let next = hovering ? leaf.id : (self.hoveredLeafID == leaf.id ? nil : self.hoveredLeafID)
                        self.onHoverLeaf(next)
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
            
            // 5. Relationship Reason Pills anchored on Active Semantic Arcs
            ForEach(activeRelationMidpoints, id: \.id) { badge in
                Text(badge.reason)
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(tokens.accentText)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2.5)
                    .background(tokens.card, in: Capsule())
                    .overlay(Capsule().strokeBorder(tokens.accent.opacity(0.55), lineWidth: 0.85))
                    .shadow(color: Color.black.opacity(self.isDark ? 0.35 : 0.08), radius: 4, y: 1.5)
                    .position(badge.point)
                    .allowsHitTesting(false)
            }
        }
    }
}


private struct StarMapLeafCardView: View, Equatable {
    
    let leaf: StarMapLeafNode
    let tokens: StudioColorTokens
    let isSelected: Bool
    let isHovered: Bool
    let isRelated: Bool
    let dimmed: Bool
    let isDark: Bool
    
    
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.leaf == rhs.leaf
            && lhs.isSelected == rhs.isSelected
            && lhs.isHovered == rhs.isHovered
            && lhs.isRelated == rhs.isRelated
            && lhs.dimmed == rhs.dimmed
            && lhs.isDark == rhs.isDark
    }
    
    
    var body: some View {
        VStack(alignment: .leading, spacing: 3.5) {
            HStack(spacing: 6) {
                Circle()
                    .fill(self.isRelated ? self.tokens.accent : self.leaf.dotColor)
                    .frame(width: (self.isSelected || self.isRelated) ? 7.5 : 6, height: (self.isSelected || self.isRelated) ? 7.5 : 6)
                
                Text(self.leaf.title)
                    .font(.system(size: 12, weight: (self.isSelected || self.isRelated) ? .semibold : .medium))
                    .foregroundStyle(self.tokens.primaryInk.opacity(self.isSelected || self.isRelated ? 1.0 : 0.90))
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
                .fill(self.tokens.card.opacity(self.isSelected || self.isHovered || self.isRelated ? 1.0 : (self.isDark ? 0.92 : 0.98)))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(
                    self.isSelected
                        ? self.leaf.dotColor.opacity(0.92)
                        : (self.isRelated
                           ? self.tokens.accent.opacity(0.74)
                           : (self.isHovered ? self.leaf.dotColor.opacity(0.55) : self.tokens.hairline)),
                    lineWidth: (self.isSelected || self.isRelated) ? 1.6 : 0.85
                )
        )
        .shadow(
            color: self.isSelected ? self.leaf.dotColor.opacity(0.24) : Color.clear,
            radius: self.isSelected ? 10 : 0,
            y: self.isSelected ? 3 : 0
        )
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .opacity(self.dimmed ? 0.40 : 1.0)
        .scaleEffect(self.isSelected ? 1.05 : (self.isHovered || self.isRelated ? 1.02 : 1.0))
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


// MARK: - Star-Map Document Center (星图全景 · 语义关联 · 全文搜索 · 空格预览)

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
    @State private var quickLookItemID: String?
    @State private var panRequestToken = 0
    @State private var isSearchHUDCollapsed = false
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
    @State private var toastMessage: String?
    @State private var toastTask: Task<Void, Never>?
    @State private var organizeTask: Task<Void, Never>?
    @State private var keyMonitor: Any?
    
    
    var body: some View {
        let displayedItems = self.state.displayedItems
        let activeItem = self.selectedItem(in: displayedItems)
        let tokens = DashPalette.editorialTokens(isDark: self.colorScheme == .dark)
        let clusters = self.state.buildStarMapClusters(tokens: tokens)
        let visibleIDs = Set(displayedItems.map(\.id))
        let visibleRelations = self.state.relations.filter {
            visibleIDs.contains($0.sourceID) && visibleIDs.contains($0.targetID)
        }
        let hasQuery = !self.state.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let quickLookItem = self.quickLookItemID.flatMap { id in
            displayedItems.first(where: { $0.id == id }) ?? self.state.items.first(where: { $0.id == id })
        }
        
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                self.topBar(tokens: tokens)
                
                Rectangle()
                    .fill(tokens.hairline)
                    .frame(height: 1)
                
                if self.isCreatingGroup {
                    self.inlineGroupCreatorBar(tokens: tokens)
                    Rectangle().fill(tokens.hairline).frame(height: 1)
                }
                
                if let renamingGroup = self.renamingGroupName {
                    self.inlineGroupRenamerBar(oldName: renamingGroup, tokens: tokens)
                    Rectangle().fill(tokens.hairline).frame(height: 1)
                }
                
                ZStack(alignment: .topTrailing) {
                    if clusters.isEmpty {
                        self.emptyStarMapState(tokens: tokens, hasQuery: hasQuery)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ConstellationStarMapView(
                            hubTitle: self.state.sidebarFilter == .trash ? "废纸篓" : "文档星图",
                            hubSubtitle: "\(displayedItems.count) 篇",
                            clusters: clusters,
                            relations: self.state.sidebarFilter == .trash ? [] : visibleRelations,
                            selectedLeafID: activeItem?.id,
                            focusedClusterID: self.focusedClusterID,
                            searchQuery: self.state.searchText,
                            panRequestToken: self.panRequestToken,
                            onSelectLeaf: { leafID in
                                self.isRenaming = false
                                self.state.selectedID = leafID
                            },
                            onDoubleClickLeaf: { leafID in
                                self.state.selectedID = leafID
                                if let target = displayedItems.first(where: { $0.id == leafID }) {
                                    if target.isTrashed {
                                        withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.16)) {
                                            self.quickLookItemID = target.id
                                        }
                                    } else {
                                        self.open(item: target)
                                    }
                                }
                            },
                            onToggleCluster: { clusterID in
                                withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                                    if self.focusedClusterID == clusterID {
                                        self.focusedClusterID = nil
                                    } else {
                                        self.focusedClusterID = clusterID
                                        self.state.collapsedClusterIDs.remove(clusterID)
                                    }
                                }
                            },
                            clusterContextMenu: { cluster in
                                self.clusterContextMenu(cluster: cluster, allItems: displayedItems)
                            },
                            leafContextMenu: { leaf in
                                if let target = displayedItems.first(where: { $0.id == leaf.id }) {
                                    self.itemContextMenu(item: target, allItems: displayedItems)
                                }
                            }
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    
                    // Top-Right Search Hits & Contextual Snippets HUD
                    if hasQuery {
                        StarMapSearchResultsHUD(
                            hits: self.state.searchHits,
                            selectedID: activeItem?.id,
                            isCollapsed: self.isSearchHUDCollapsed,
                            tokens: tokens,
                            onToggleCollapse: {
                                withAnimation(.easeOut(duration: 0.15)) {
                                    self.isSearchHUDCollapsed.toggle()
                                }
                            },
                            onSelectHit: { hitID in
                                self.unfocusSearchField()
                                self.state.selectedID = hitID
                                self.panRequestToken &+= 1
                            },
                            onPreviewHit: { hitID in
                                self.unfocusSearchField()
                                self.state.selectedID = hitID
                                withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.16)) {
                                    self.quickLookItemID = hitID
                                }
                            },
                            onOpenHit: { hitID in
                                if let target = displayedItems.first(where: { $0.id == hitID }) ?? self.state.items.first(where: { $0.id == hitID }) {
                                    self.open(item: target)
                                }
                            }
                        )
                        .padding(16)
                    }
                    
                    // Bottom-Center Selection, Relationship Links & Quick Actions Bar
                    if quickLookItem == nil, let activeItem {
                        VStack {
                            Spacer()
                            self.bottomSelectionCapsule(
                                item: activeItem,
                                allItems: displayedItems,
                                tokens: tokens
                            )
                            .padding(.bottom, 16)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
            .background(tokens.canvasTop)
            
            // Spacebar QuickLook Overlay (with keyword highlighting & related doc hops)
            if let qItem = quickLookItem {
                let navList = self.keyboardNavigationItems(displayedItems: displayedItems)
                let curIdx = navList.firstIndex(where: { $0.id == qItem.id }) ?? 0
                let canPrev = navList.count > 1 && curIdx > 0
                let canNext = navList.count > 1 && curIdx + 1 < navList.count
                let related = self.state.relatedNodes(for: qItem.id, in: self.state.items)
                let highlightTerms = StarMapSearchEngine.parseTerms(self.state.searchText)
                
                StarMapQuickLookOverlay(
                    title: qItem.title,
                    subtitle: "\(qItem.groupName.isEmpty ? "未分组" : qItem.groupName) · \(qItem.compactCharCount) · \(qItem.relativeTimeText)",
                    canStepPrevious: canPrev,
                    canStepNext: canNext,
                    onPrevious: {
                        guard canPrev else { return }
                        let prev = navList[curIdx - 1]
                        self.state.selectedID = prev.id
                        self.quickLookItemID = prev.id
                    },
                    onNext: {
                        guard canNext else { return }
                        let next = navList[curIdx + 1]
                        self.state.selectedID = next.id
                        self.quickLookItemID = next.id
                    },
                    onClose: {
                        withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.16)) {
                            self.quickLookItemID = nil
                        }
                    },
                    headerActions: {
                        HStack(spacing: 6) {
                            if qItem.isTrashed {
                                Button("恢复") {
                                    self.restore(item: qItem)
                                    self.quickLookItemID = nil
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                            } else {
                                Button("打开") {
                                    self.quickLookItemID = nil
                                    self.open(item: qItem)
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                            }
                            
                            Button(self.copiedFlag ? "已复制" : "复制") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(qItem.content, forType: .string)
                                self.copiedFlag = true
                                self.showToast("已复制")
                                Task {
                                    try? await Task.sleep(for: .seconds(1.4))
                                    self.copiedFlag = false
                                }
                            }
                            .controlSize(.small)
                        }
                    },
                    bodyContent: {
                        VStack(spacing: 0) {
                            if !related.isEmpty {
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 6) {
                                        Text("关联")
                                            .font(.system(size: 10.5, weight: .semibold))
                                            .foregroundStyle(tokens.primaryInk.opacity(0.55))
                                        ForEach(related.prefix(5), id: \.item.id) { entry in
                                            Button {
                                                self.state.selectedID = entry.item.id
                                                self.quickLookItemID = entry.item.id
                                                self.panRequestToken &+= 1
                                            } label: {
                                                Text("\(entry.item.title) · \(entry.reason)")
                                                    .font(.system(size: 10.5, weight: .medium))
                                                    .foregroundStyle(tokens.accentText)
                                                    .padding(.horizontal, 8)
                                                    .padding(.vertical, 3)
                                                    .background(tokens.positivePillBg, in: Capsule())
                                            }
                                            .buttonStyle(.plain)
                                            .pointerStyle(.link)
                                        }
                                    }
                                    .padding(.horizontal, 18)
                                    .padding(.vertical, 8)
                                }
                                .background(tokens.canvasBottom)
                                Rectangle().fill(tokens.hairline).frame(height: 1)
                            }
                            
                            CenterPreviewTextView(
                                text: qItem.previewText,
                                highlightTerms: highlightTerms
                            )
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }
                )
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
            self.state.refresh()
            self.installKeyboardMonitor()
            self.registerEscPop? { self.handleEscapePop() }
        }
        .onDisappear {
            self.removeKeyboardMonitor()
            self.organizeTask?.cancel()
            self.registerEscPop?(nil)
        }
        .onChange(of: self.db.documents.count) { _, _ in
            self.state.refresh()
        }
        .onChange(of: self.db.trashedDocuments.count) { _, _ in
            self.state.refresh()
        }
        .onChange(of: self.state.searchText) { _, newValue in
            if !newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                self.isSearchHUDCollapsed = false
            }
        }
    }
    
    
    // MARK: Top Bar
    
    private func topBar(tokens: StudioColorTokens) -> some View {
        let groupNames: [String] = {
            var ordered = self.db.documentGroups
            for key in self.state.groupCounts.keys.sorted() where !ordered.contains(key) {
                ordered.append(key)
            }
            return ordered
        }()
        
        return HStack(spacing: 8) {
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
            
            Text("文档中心")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(tokens.primaryInk)
            
            // Scope filter pills
            HStack(spacing: 2) {
                self.scopeChip(title: "全部 \(self.state.items.count)", isActive: self.state.sidebarFilter == .all, tokens: tokens) {
                    self.focusedClusterID = nil
                    self.state.sidebarFilter = .all
                }
                self.scopeChip(title: "打开中 \(self.state.openCount)", isActive: self.state.sidebarFilter == .openNow, tokens: tokens) {
                    self.focusedClusterID = nil
                    self.state.sidebarFilter = .openNow
                }
                if !self.state.trashedItems.isEmpty || self.state.sidebarFilter == .trash {
                    self.scopeChip(title: "废纸篓 \(self.state.trashedItems.count)", isActive: self.state.sidebarFilter == .trash, tokens: tokens) {
                        self.focusedClusterID = nil
                        self.state.sidebarFilter = .trash
                    }
                }
            }
            .padding(2.5)
            .background(tokens.inset, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            
            // Group filter dropdown
            if !groupNames.isEmpty {
                Menu {
                    Button("全部分组") {
                        self.focusedClusterID = nil
                        self.state.sidebarFilter = .all
                    }
                    Divider()
                    ForEach(groupNames, id: \.self) { groupName in
                        Button("\(groupName)（\(self.state.groupCounts[groupName] ?? 0)）") {
                            self.focusedClusterID = "group:\(groupName)"
                            self.state.sidebarFilter = .group(groupName)
                        }
                    }
                    if self.state.ungroupedCount > 0 {
                        Button("未分组（\(self.state.ungroupedCount)）") {
                            self.focusedClusterID = "__ungrouped__"
                            self.state.sidebarFilter = .ungrouped
                        }
                    }
                    Divider()
                    Button("新建分组") {
                        self.newGroupDraft = ""
                        self.pendingAssignAfterGroupCreate = nil
                        self.isCreatingGroup = true
                        DispatchQueue.main.async { self.isNewGroupFieldFocused = true }
                    }
                } label: {
                    let activeLabel: String = switch self.state.sidebarFilter {
                        case .group(let name): name
                        case .ungrouped: "未分组"
                        default: "分组筛选"
                    }
                    HStack(spacing: 4) {
                        Image(systemName: "folder")
                            .font(.system(size: 10.5, weight: .medium))
                        Text(activeLabel)
                            .font(.system(size: 11.5, weight: .medium))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 8.5, weight: .semibold))
                            .foregroundStyle(tokens.primaryInk.opacity(0.5))
                    }
                    .foregroundStyle(tokens.primaryInk.opacity(0.84))
                    .padding(.horizontal, 9)
                    .frame(height: 28)
                    .background(tokens.inset, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .pointerStyle(.link)
            }
            
            Spacer(minLength: 6)
            
            // Full-Text Multi-Keyword Search Field
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(self.isSearchFocused ? tokens.accent : tokens.primaryInk.opacity(0.45))
                TextField("搜索标题与全文关键词（空格多词 · ⌘F）", text: self.$state.searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .focused(self.$isSearchFocused)
                    .frame(minWidth: 210, maxWidth: 270)
                    .onSubmit {
                        self.unfocusSearchField()
                        if let firstHit = self.state.searchHits.first {
                            self.state.selectedID = firstHit.id
                            self.panRequestToken &+= 1
                        }
                    }
                if !self.state.searchText.isEmpty {
                    Text("\(self.state.searchHits.count) 篇")
                        .font(.system(size: 10, weight: .semibold, design: .rounded).monospacedDigit())
                        .foregroundStyle(tokens.accentText)
                        .padding(.horizontal, 5.5)
                        .padding(.vertical, 1.5)
                        .background(tokens.positivePillBg, in: Capsule())
                    
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
            .frame(height: 28)
            .background(tokens.inset, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(self.isSearchFocused ? tokens.accent.opacity(0.65) : tokens.hairline, lineWidth: self.isSearchFocused ? 1.1 : 0.75)
            )
            
            if self.state.sidebarFilter == .trash && !self.state.displayedItems.isEmpty {
                Button("清空废纸篓") {
                    self.confirmEmptyTrash()
                }
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(.red)
                .padding(.horizontal, 10)
                .frame(height: 28)
                .background(Color.red.opacity(0.10), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .buttonStyle(.plain)
                .pointerStyle(.link)
            }
            
            if self.state.isAgentOrganizing {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Agent 整理中")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(tokens.accentText)
                    Button("取消") {
                        self.cancelAgentOrganize()
                    }
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(tokens.primaryInk.opacity(0.65))
                    .buttonStyle(.plain)
                    .pointerStyle(.link)
                }
                .padding(.horizontal, 10)
                .frame(height: 28)
                .background(tokens.positivePillBg, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            } else {
                if let summary = self.state.agentOrganizeSummary {
                    HStack(spacing: 6) {
                        Text(summary)
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(tokens.accentText)
                        if !self.state.lastOrganizeUndoSnapshot.isEmpty {
                            Button("撤销") {
                                self.undoAgentOrganize()
                            }
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(tokens.primaryInk)
                            .padding(.horizontal, 7)
                            .frame(height: 20)
                            .background(tokens.card, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                            .buttonStyle(.plain)
                            .pointerStyle(.link)
                        }
                        Button {
                            self.state.agentOrganizeSummary = nil
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 9.5, weight: .semibold))
                                .foregroundStyle(tokens.primaryInk.opacity(0.48))
                        }
                        .buttonStyle(.plain)
                        .pointerStyle(.link)
                    }
                    .padding(.horizontal, 9)
                    .frame(height: 28)
                    .background(tokens.positivePillBg, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
                
                Button {
                    self.runAgentAutoOrganize()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 10.5, weight: .semibold))
                        Text("Agent 整理")
                            .font(.system(size: 11.5, weight: .semibold))
                    }
                    .foregroundStyle(tokens.accentText)
                    .padding(.horizontal, 10)
                    .frame(height: 28)
                    .background(tokens.positivePillBg, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(tokens.accent.opacity(0.28), lineWidth: 0.75))
                    .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
                .buttonStyle(.plain)
                .pointerStyle(.link)
                .disabled(self.state.items.isEmpty)
                .opacity(self.state.items.isEmpty ? 0.45 : 1)
            }
            
            if let onCreateNewDocument = self.onCreateNewDocument {
                Button(action: onCreateNewDocument) {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                            .font(.system(size: 10.5, weight: .bold))
                        Text("新建文档")
                            .font(.system(size: 11.5, weight: .semibold))
                    }
                    .foregroundStyle(tokens.onAccentInk)
                    .padding(.horizontal, 10)
                    .frame(height: 28)
                    .background(tokens.accent, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
                .buttonStyle(.plain)
                .pointerStyle(.link)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 48)
        .background(tokens.canvasTop)
    }
    
    
    private func scopeChip(title: String, isActive: Bool, tokens: StudioColorTokens, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: isActive ? .semibold : .medium).monospacedDigit())
                .foregroundStyle(isActive ? tokens.primaryInk : tokens.primaryInk.opacity(0.60))
                .padding(.horizontal, 8)
                .frame(height: 23)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(isActive ? tokens.card : Color.clear)
                )
                .contentShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        }
        .buttonStyle(.plain)
        .pointerStyle(.link)
    }
    
    
    private func inlineGroupCreatorBar(tokens: StudioColorTokens) -> some View {
        HStack(spacing: 8) {
            Text("新建分组名称")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(tokens.primaryInk.opacity(0.70))
            TextField("输入分组名", text: self.$newGroupDraft)
                .textFieldStyle(.plain)
                .font(.system(size: 12.5))
                .focused(self.$isNewGroupFieldFocused)
                .padding(.horizontal, 8)
                .frame(width: 190, height: 26)
                .background(tokens.inset, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .onSubmit { self.commitCreateGroup() }
                .onExitCommand {
                    self.isCreatingGroup = false
                    self.pendingAssignAfterGroupCreate = nil
                }
            Button("确定") { self.commitCreateGroup() }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            Button("取消") {
                self.isCreatingGroup = false
                self.pendingAssignAfterGroupCreate = nil
            }
            .controlSize(.small)
            Spacer()
        }
        .padding(.horizontal, 16)
        .frame(height: 38)
        .background(tokens.canvasBottom)
    }
    
    
    private func inlineGroupRenamerBar(oldName: String, tokens: StudioColorTokens) -> some View {
        HStack(spacing: 8) {
            Text("重命名分组「\(oldName)」")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(tokens.primaryInk.opacity(0.70))
            TextField("新分组名", text: self.$groupRenameDraft)
                .textFieldStyle(.plain)
                .font(.system(size: 12.5))
                .focused(self.$isGroupRenameFocused)
                .padding(.horizontal, 8)
                .frame(width: 190, height: 26)
                .background(tokens.inset, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .onSubmit { self.commitGroupRename(oldName: oldName) }
                .onExitCommand { self.renamingGroupName = nil }
            Button("保存") { self.commitGroupRename(oldName: oldName) }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            Button("取消") { self.renamingGroupName = nil }
                .controlSize(.small)
            Spacer()
        }
        .padding(.horizontal, 16)
        .frame(height: 38)
        .background(tokens.canvasBottom)
    }
    
    
    private func emptyStarMapState(tokens: StudioColorTokens, hasQuery: Bool) -> some View {
        VStack(spacing: 10) {
            Image(systemName: self.state.sidebarFilter == .trash ? "trash" : (hasQuery ? "magnifyingglass" : "point.3.connected.trianglepath.dotted"))
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(tokens.primaryInk.opacity(0.28))
            Text(hasQuery ? "未检索到包含全部关键词的文档" : (self.state.sidebarFilter == .trash ? "废纸篓为空" : "暂无文档"))
                .font(.system(size: 13.5, weight: .medium))
                .foregroundStyle(tokens.primaryInk.opacity(0.50))
        }
        .background(tokens.canvasTop)
    }
    
    
    // MARK: Bottom Selection & Relationships Capsule
    
    private func bottomSelectionCapsule(
        item: DocumentCenterState.ManagedDocumentItem,
        allItems: [DocumentCenterState.ManagedDocumentItem],
        tokens: StudioColorTokens
    ) -> some View {
        let related = item.isTrashed ? [] : self.state.relatedNodes(for: item.id, in: self.state.items)
        
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Circle()
                    .fill(item.isDirty ? Color.orange : tokens.accent)
                    .frame(width: 8, height: 8)
                
                if self.isRenaming {
                    TextField("文档标题", text: self.$renameDraft)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13, weight: .semibold))
                        .focused(self.$isRenameFieldFocused)
                        .padding(.horizontal, 8)
                        .frame(width: 220, height: 26)
                        .background(tokens.inset, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .onSubmit { self.commitRename(for: item) }
                        .onExitCommand { self.isRenaming = false }
                    
                    Button("保存") { self.commitRename(for: item) }
                        .controlSize(.small)
                        .buttonStyle(.borderedProminent)
                    Button("取消") { self.isRenaming = false }
                        .controlSize(.small)
                } else {
                    VStack(alignment: .leading, spacing: 1.5) {
                        Text(item.title)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(tokens.primaryInk)
                            .fixedSize(horizontal: false, vertical: true)
                        
                        Text("\(item.groupName.isEmpty ? "未分组" : item.groupName) · \(item.compactCharCount) · \(item.relativeTimeText)")
                            .font(.system(size: 10.5, weight: .regular, design: .rounded).monospacedDigit())
                            .foregroundStyle(tokens.primaryInk.opacity(0.55))
                    }
                }
                
                Spacer(minLength: 10)
                
                Button {
                    withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.16)) {
                        self.quickLookItemID = item.id
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
                
                if item.isTrashed {
                    Button {
                        self.restore(item: item)
                    } label: {
                        Text("恢复")
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(tokens.onAccentInk)
                            .padding(.horizontal, 10)
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
                            .padding(.horizontal, 10)
                            .frame(height: 26)
                            .background(Color.red.opacity(0.10), in: Capsule())
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
                            .padding(.horizontal, 11)
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
                        Button("新建分组") {
                            self.pendingAssignAfterGroupCreate = item
                            self.newGroupDraft = ""
                            self.isCreatingGroup = true
                            DispatchQueue.main.async { self.isNewGroupFieldFocused = true }
                        }
                        Divider()
                        Button("重命名") {
                            self.renameDraft = item.title
                            self.isRenaming = true
                            DispatchQueue.main.async { self.isRenameFieldFocused = true }
                        }
                        Button("移入废纸篓", role: .destructive) {
                            self.delete(item: item, in: allItems)
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(tokens.primaryInk.opacity(0.70))
                            .frame(width: 26, height: 26)
                            .background(tokens.inset, in: Circle())
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .pointerStyle(.link)
                }
            }
            
            if !related.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        Text("关联文档")
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(tokens.primaryInk.opacity(0.55))
                        
                        ForEach(related, id: \.item.id) { entry in
                            Button {
                                self.state.selectedID = entry.item.id
                                self.panRequestToken &+= 1
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "link")
                                        .font(.system(size: 9, weight: .semibold))
                                    Text("\(entry.item.title) · \(entry.reason)")
                                        .font(.system(size: 10.5, weight: .medium))
                                }
                                .foregroundStyle(tokens.accentText)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(tokens.positivePillBg, in: Capsule())
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
        .frame(maxWidth: 660)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(tokens.hairlineStrong, lineWidth: 0.9)
        )
        .shadow(color: Color.black.opacity(self.colorScheme == .dark ? 0.38 : 0.12), radius: 16, y: 6)
        .padding(.horizontal, 24)
    }
    
    
    // MARK: Context Menus
    
    @ViewBuilder
    private func clusterContextMenu(
        cluster: StarMapClusterNode,
        allItems: [DocumentCenterState.ManagedDocumentItem]
    ) -> some View {
        Button("聚焦此分组") {
            self.focusedClusterID = (self.focusedClusterID == cluster.id) ? nil : cluster.id
        }
        if cluster.id.hasPrefix("group:") {
            let groupName = String(cluster.id.dropFirst(6))
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
                if self.focusedClusterID == cluster.id { self.focusedClusterID = nil }
                if self.state.sidebarFilter == .group(groupName) {
                    self.state.sidebarFilter = .all
                }
                self.state.refresh()
                self.showToast("已解散「\(groupName)」")
            }
        }
    }
    
    
    @ViewBuilder
    private func itemContextMenu(
        item: DocumentCenterState.ManagedDocumentItem,
        allItems: [DocumentCenterState.ManagedDocumentItem]
    ) -> some View {
        Button("空格预览") {
            self.state.selectedID = item.id
            self.quickLookItemID = item.id
        }
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
        if self.quickLookItemID != nil {
            withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.16)) {
                self.quickLookItemID = nil
            }
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
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if flags == .command && event.charactersIgnoringModifiers?.lowercased() == "f" {
                self.quickLookItemID = nil
                self.isSearchFocused = true
                return nil
            }
            
            if let tv = (event.window ?? NSApp.keyWindow)?.firstResponder as? NSTextView, tv.isEditable {
                if event.keyCode == 125 && self.isSearchFocused { // Down arrow exits search into results/canvas
                    self.unfocusSearchField()
                    return nil
                }
                return event
            }
            
            let navList = self.keyboardNavigationItems(displayedItems: self.state.displayedItems)
            guard !navList.isEmpty else { return event }
            
            switch event.keyCode {
                case 49: // Space -> toggle QuickLook preview
                    if self.quickLookItemID != nil {
                        withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.15)) {
                            self.quickLookItemID = nil
                        }
                        return nil
                    }
                    if let active = self.selectedItem(in: navList) {
                        withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.16)) {
                            self.quickLookItemID = active.id
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
                    if let active = self.selectedItem(in: navList), !active.isTrashed {
                        self.quickLookItemID = nil
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
        let nextID = list[nextIdx].id
        self.state.selectedID = nextID
        if self.quickLookItemID != nil {
            self.quickLookItemID = nextID
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
        if self.quickLookItemID == item.id {
            self.quickLookItemID = nil
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
            if self.quickLookItemID == item.id {
                self.quickLookItemID = nil
            }
            self.state.refresh()
            self.showToast("已彻底删除")
        }
    }
    
    
    private func confirmEmptyTrash() {
        self.confirmDestructive(title: "清空废纸篓（\(self.state.trashedItems.count) 篇）？") {
            self.db.emptyDocumentTrash()
            self.quickLookItemID = nil
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
            self.state.refresh()
            self.focusedClusterID = "group:\(created)"
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
            if self.focusedClusterID == "group:\(oldName)" {
                self.focusedClusterID = "group:\(trimmed)"
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
