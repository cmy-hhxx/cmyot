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


// MARK: - Shared Constellation Mind-Map Engine (思维导图 / 星图)

/// Data model for one radial cluster branch (e.g. a document group or weekly-report month).
struct StarMapClusterNode: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let accent: Color
    let isCollapsed: Bool
    let leaves: [StarMapLeafNode]
}

/// Data model for one document/report leaf star on the constellation map.
struct StarMapLeafNode: Identifiable {
    let id: String
    let clusterID: String
    let title: String
    let subtitle: String
    let dotColor: Color
    let weight: Double          // 0...1 relative node brightness/size
    let isHighlighted: Bool     // e.g. currently open in editor or current week
}

/// Pure deterministic radial mind-map / constellation layout engine (O(N), zero simulation jitter).
nonisolated enum StarMapLayoutEngine {
    
    static let ambientStars: [(x: Double, y: Double, r: CGFloat, alpha: Double)] = {
        (0..<68).map { i in
            let fi = Double(i)
            let x = (sin(fi * 12.9898 + 1.3) * 43758.5453).truncatingRemainder(dividingBy: 1.0)
            let y = (sin(fi * 78.233 + 2.7) * 24634.6345).truncatingRemainder(dividingBy: 1.0)
            let r: CGFloat = i.isMultiple(of: 7) ? 1.8 : (i.isMultiple(of: 3) ? 1.2 : 0.85)
            let alpha = i.isMultiple(of: 7) ? 0.42 : 0.20
            return (abs(x), abs(y), r, alpha)
        }
    }()
    
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
        
        // Single cluster: place leaves directly in balanced concentric star rings around core hub
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
        
        // Multi-cluster constellation: allocate angular sectors weighted by visible leaf count
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


/// Reusable 120fps Interactive Constellation Mind-Map Canvas shared by Document Center & Weekly Report Center.
struct ConstellationStarMapView<ClusterMenu: View, LeafMenu: View>: View {
    
    let hubTitle: String
    let hubSubtitle: String
    let clusters: [StarMapClusterNode]
    let selectedLeafID: String?
    let searchQuery: String
    let onSelectLeaf: (String) -> Void
    let onDoubleClickLeaf: (String) -> Void
    let onToggleCluster: (String) -> Void
    @ViewBuilder let clusterContextMenu: (StarMapClusterNode) -> ClusterMenu
    @ViewBuilder let leafContextMenu: (StarMapLeafNode) -> LeafMenu
    
    @Environment(\.colorScheme) private var colorScheme
    @State private var studioPalette = StudioPaletteManager.shared
    @State private var panOffset: CGSize = .zero
    @State private var dragStartPan: CGSize?
    @State private var zoomScale: CGFloat = 1.0
    @State private var pinchBaseZoom: CGFloat?
    @State private var hoveredLeafID: String?
    @State private var hoveredClusterID: String?
    @State private var hasAutoFitted = false
    
    
    private var computedLayout: StarMapLayoutEngine.LayoutResult {
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
        let tokens = self.studioPalette.tokens(isDark: isDark)
        let layout = self.computedLayout
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
            ?? self.selectedLeafID.flatMap { leafMap[$0]?.clusterID }
        
        GeometryReader { geo in
            let viewportCenter = CGPoint(x: geo.size.width * 0.5, y: geo.size.height * 0.5 + 12)
            let toScreen: (CGPoint) -> CGPoint = { world in
                CGPoint(
                    x: viewportCenter.x + self.panOffset.width + world.x * self.zoomScale,
                    y: viewportCenter.y + self.panOffset.height + world.y * self.zoomScale
                )
            }
            
            ZStack {
                // 1. Deep Studio Celestial Backdrop + Precomputed Starfield + Orbital Grid + Curved Bezier Branches
                Canvas { context, size in
                    guard size.width > 10, size.height > 10 else { return }
                    
                    // Subtle ambient radial nebula anchored at hub
                    let hubScreen = toScreen(.zero)
                    let nebulaR = max(size.width, size.height) * 0.58
                    let nebulaRect = CGRect(x: hubScreen.x - nebulaR, y: hubScreen.y - nebulaR, width: nebulaR * 2, height: nebulaR * 2)
                    context.fill(
                        Circle().path(in: nebulaRect),
                        with: .radialGradient(
                            Gradient(colors: [
                                tokens.accent.opacity(isDark ? 0.14 : 0.08),
                                tokens.secondaryAccent.opacity(isDark ? 0.05 : 0.03),
                                .clear,
                            ]),
                            center: hubScreen,
                            startRadius: 8,
                            endRadius: nebulaR
                        )
                    )
                    
                    // Static micro-star dust (0 allocations, 120fps)
                    for star in StarMapLayoutEngine.ambientStars {
                        let sx = CGFloat(star.x) * size.width
                        let sy = CGFloat(star.y) * size.height
                        let rect = CGRect(x: sx - star.r, y: sy - star.r, width: star.r * 2, height: star.r * 2)
                        let col = isDark
                            ? Color.white.opacity(star.alpha)
                            : tokens.primaryInk.opacity(star.alpha * 0.42)
                        context.fill(Circle().path(in: rect), with: .color(col))
                    }
                    
                    // Delicate concentric orbital guide rings centered on core hub
                    for r in [165.0, 295.0, 420.0] {
                        let rx = CGFloat(r) * self.zoomScale * 1.15
                        let ry = CGFloat(r) * self.zoomScale * 0.87
                        let ringRect = CGRect(x: hubScreen.x - rx, y: hubScreen.y - ry, width: rx * 2, height: ry * 2)
                        context.stroke(
                            Ellipse().path(in: ringRect),
                            with: .color(tokens.primaryInk.opacity(isDark ? 0.055 : 0.045)),
                            style: StrokeStyle(lineWidth: 0.75, dash: [3, 5])
                        )
                    }
                    
                    // Constellation branches: Hub -> Cluster
                    for cPos in layout.clusters {
                        let cluster = clusterMap[cPos.id]
                        let endPt = toScreen(cPos.worldPoint)
                        let isFocused = (activeFocusClusterID == cPos.id)
                        let branchAccent = cluster?.accent ?? tokens.accent
                        let lineAlpha: Double = isFocused ? (isDark ? 0.72 : 0.62) : (activeFocusClusterID == nil ? 0.30 : 0.14)
                        
                        let dx = endPt.x - hubScreen.x
                        let dy = endPt.y - hubScreen.y
                        let ctrl = CGPoint(x: hubScreen.x + dx * 0.5 - dy * 0.08, y: hubScreen.y + dy * 0.5 + dx * 0.08)
                        var curve = Path()
                        curve.move(to: hubScreen)
                        curve.addQuadCurve(to: endPt, control: ctrl)
                        context.stroke(
                            curve,
                            with: .color(branchAccent.opacity(lineAlpha)),
                            style: StrokeStyle(lineWidth: isFocused ? 1.8 : 1.0, lineCap: .round)
                        )
                    }
                    
                    // Constellation filaments: Cluster -> Leaf Star
                    for lPos in layout.leaves {
                        let parentPt = toScreen(lPos.parentPoint)
                        let leafPt = toScreen(lPos.worldPoint)
                        let isSelected = (self.selectedLeafID == lPos.id)
                        let isHovered = (self.hoveredLeafID == lPos.id)
                        let isClusterFocused = (activeFocusClusterID == lPos.clusterID)
                        let leafAccent = leafMap[lPos.id]?.dotColor ?? tokens.accent
                        
                        let alpha: Double = if isSelected || isHovered {
                            0.88
                        } else if isClusterFocused {
                            0.38
                        } else {
                            activeFocusClusterID == nil ? 0.22 : 0.10
                        }
                        
                        let midX = (parentPt.x + leafPt.x) * 0.5
                        let midY = (parentPt.y + leafPt.y) * 0.5
                        let dx = leafPt.x - parentPt.x
                        let dy = leafPt.y - parentPt.y
                        let ctrl = CGPoint(x: midX - dy * 0.10, y: midY + dx * 0.10)
                        var curve = Path()
                        curve.move(to: parentPt)
                        curve.addQuadCurve(to: leafPt, control: ctrl)
                        context.stroke(
                            curve,
                            with: .color(leafAccent.opacity(alpha)),
                            style: StrokeStyle(lineWidth: (isSelected || isHovered) ? 1.7 : 0.85, lineCap: .round)
                        )
                        
                        if isSelected || isHovered {
                            let haloR: CGFloat = isSelected ? 16 : 12
                            let haloRect = CGRect(x: leafPt.x - haloR, y: leafPt.y - haloR, width: haloR * 2, height: haloR * 2)
                            context.fill(
                                Circle().path(in: haloRect),
                                with: .radialGradient(
                                    Gradient(colors: [leafAccent.opacity(0.32), .clear]),
                                    center: leafPt,
                                    startRadius: 2,
                                    endRadius: haloR
                                )
                            )
                        }
                    }
                }
                .allowsHitTesting(false)
                
                // 2. Center Core Hub Node
                let hubScreen = toScreen(.zero)
                VStack(spacing: 2) {
                    Text(self.hubTitle)
                        .font(.system(size: 13.5, weight: .bold, design: .rounded))
                        .foregroundStyle(tokens.primaryInk)
                    Text(self.hubSubtitle)
                        .font(.system(size: 10, weight: .medium, design: .rounded).monospacedDigit())
                        .foregroundStyle(tokens.primaryInk.opacity(0.56))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(
                    Capsule()
                        .fill(tokens.card.opacity(isDark ? 0.94 : 0.96))
                        .shadow(color: tokens.accent.opacity(isDark ? 0.25 : 0.14), radius: 14, y: 2)
                )
                .overlay(
                    Capsule()
                        .strokeBorder(tokens.accent.opacity(0.55), lineWidth: 1.2)
                )
                .position(hubScreen)
                
                // 3. Interactive Cluster Star Nodes (Groups / Months)
                if layout.clusters.count > 1 {
                    ForEach(layout.clusters) { cPos in
                        if let cluster = clusterMap[cPos.id] {
                            let isFocused = (activeFocusClusterID == cluster.id)
                            let isHovered = (self.hoveredClusterID == cluster.id)
                            let dimmed = (activeFocusClusterID != nil && !isFocused)
                            
                            Button {
                                withAnimation(.spring(response: 0.30, dampingFraction: 0.82)) {
                                    self.onToggleCluster(cluster.id)
                                }
                            } label: {
                                HStack(spacing: 6) {
                                    Circle()
                                        .fill(cluster.accent)
                                        .frame(width: 7.5, height: 7.5)
                                        .shadow(color: cluster.accent.opacity(0.65), radius: 4)
                                    
                                    Text(cluster.title)
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(tokens.primaryInk)
                                        .lineLimit(1)
                                    
                                    Text(cluster.subtitle)
                                        .font(.system(size: 10, weight: .semibold, design: .rounded).monospacedDigit())
                                        .foregroundStyle(cluster.accent)
                                        .padding(.horizontal, 5.5)
                                        .padding(.vertical, 1.5)
                                        .background(cluster.accent.opacity(isDark ? 0.18 : 0.12), in: Capsule())
                                    
                                    if cluster.isCollapsed {
                                        Image(systemName: "plus")
                                            .font(.system(size: 8.5, weight: .bold))
                                            .foregroundStyle(tokens.primaryInk.opacity(0.45))
                                    }
                                }
                                .padding(.horizontal, 10)
                                .frame(height: 28)
                                .background(
                                    Capsule()
                                        .fill(tokens.card.opacity(isDark ? 0.90 : 0.95))
                                        .shadow(color: tokens.cardShadow, radius: isHovered ? 10 : 5, y: 2)
                                )
                                .overlay(
                                    Capsule()
                                        .strokeBorder(
                                            (isFocused || isHovered) ? cluster.accent.opacity(0.65) : tokens.hairlineStrong,
                                            lineWidth: (isFocused || isHovered) ? 1.15 : 0.75
                                        )
                                )
                            }
                            .buttonStyle(.plain)
                            .pointerStyle(.link)
                            .opacity(dimmed ? 0.56 : 1.0)
                            .scaleEffect(isHovered ? 1.05 : 1.0)
                            .animation(.easeOut(duration: 0.14), value: isHovered)
                            .position(toScreen(cPos.worldPoint))
                            .onHover { hovering in
                                self.hoveredClusterID = hovering ? cluster.id : (self.hoveredClusterID == cluster.id ? nil : self.hoveredClusterID)
                            }
                            .contextMenu {
                                self.clusterContextMenu(cluster)
                            }
                        }
                    }
                }
                
                // 4. Interactive Leaf Star Nodes (Documents / Weekly Reports — zero duplicated icons!)
                ForEach(layout.leaves) { lPos in
                    if let leaf = leafMap[lPos.id] {
                        let isSelected = (self.selectedLeafID == leaf.id)
                        let isHovered = (self.hoveredLeafID == leaf.id)
                        let isClusterFocused = (activeFocusClusterID == leaf.clusterID)
                        let dimmed = (activeFocusClusterID != nil && !isClusterFocused && !isSelected)
                        let dotSize: CGFloat = (isSelected || isHovered) ? 8.5 : (5.5 + CGFloat(leaf.weight) * 2.5)
                        
                        HStack(spacing: 6) {
                            Circle()
                                .fill(leaf.dotColor)
                                .frame(width: dotSize, height: dotSize)
                                .shadow(color: leaf.dotColor.opacity(isSelected || leaf.isHighlighted ? 0.75 : 0.30), radius: isSelected ? 5 : 2)
                            
                            VStack(alignment: .leading, spacing: 1) {
                                Text(leaf.title)
                                    .font(.system(size: isSelected ? 12 : 11.5, weight: isSelected ? .semibold : .medium))
                                    .foregroundStyle(tokens.primaryInk.opacity(isSelected ? 1.0 : 0.88))
                                    .lineLimit(1)
                                    .frame(maxWidth: 136, alignment: .leading)
                                
                                if !leaf.subtitle.isEmpty && (isSelected || isHovered || self.zoomScale >= 0.90) {
                                    Text(leaf.subtitle)
                                        .font(.system(size: 9.5, weight: .medium, design: .rounded).monospacedDigit())
                                        .foregroundStyle(tokens.primaryInk.opacity(0.46))
                                        .lineLimit(1)
                                }
                            }
                        }
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(
                                    isSelected
                                        ? tokens.card
                                        : tokens.card.opacity(isHovered ? 0.94 : (isDark ? 0.78 : 0.88))
                                )
                                .shadow(
                                    color: isSelected ? leaf.dotColor.opacity(0.28) : tokens.cardShadow.opacity(0.6),
                                    radius: isSelected ? 12 : 4,
                                    y: 2
                                )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(
                                    isSelected
                                        ? leaf.dotColor.opacity(0.85)
                                        : (isHovered ? tokens.hairlineStrong : tokens.hairline),
                                    lineWidth: isSelected ? 1.35 : 0.75
                                )
                        )
                        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .opacity(dimmed ? 0.45 : 1.0)
                        .scaleEffect(isSelected ? 1.05 : (isHovered ? 1.03 : 1.0))
                        .animation(.easeOut(duration: 0.14), value: isSelected)
                        .animation(.easeOut(duration: 0.12), value: isHovered)
                        .pointerStyle(.link)
                        .onTapGesture(count: 2) {
                            self.onSelectLeaf(leaf.id)
                            self.onDoubleClickLeaf(leaf.id)
                        }
                        .onTapGesture(count: 1) {
                            self.onSelectLeaf(leaf.id)
                        }
                        .onHover { hovering in
                            self.hoveredLeafID = hovering ? leaf.id : (self.hoveredLeafID == leaf.id ? nil : self.hoveredLeafID)
                        }
                        .contextMenu {
                            self.leafContextMenu(leaf)
                        }
                        .position(toScreen(lPos.worldPoint))
                    }
                }
                
                // 5. Compact Bottom-Right Zoom & Reset Instrument Pill
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        HStack(spacing: 4) {
                            Button {
                                withAnimation(.easeOut(duration: 0.18)) {
                                    self.zoomScale = max(0.45, self.zoomScale - 0.15)
                                }
                            } label: {
                                Image(systemName: "minus")
                                    .font(.system(size: 10, weight: .semibold))
                                    .frame(width: 24, height: 24)
                            }
                            .buttonStyle(.plain)
                            .pointerStyle(.link)
                            
                            Text("\(Int((self.zoomScale * 100).rounded()))%")
                                .font(.system(size: 10.5, weight: .semibold, design: .rounded).monospacedDigit())
                                .foregroundStyle(tokens.primaryInk.opacity(0.68))
                                .frame(minWidth: 36)
                            
                            Button {
                                withAnimation(.easeOut(duration: 0.18)) {
                                    self.zoomScale = min(2.2, self.zoomScale + 0.15)
                                }
                            } label: {
                                Image(systemName: "plus")
                                    .font(.system(size: 10, weight: .semibold))
                                    .frame(width: 24, height: 24)
                            }
                            .buttonStyle(.plain)
                            .pointerStyle(.link)
                            
                            Rectangle()
                                .fill(tokens.hairlineStrong)
                                .frame(width: 1, height: 12)
                            
                            Button {
                                self.autoFit(layoutBounds: layout.bounds, viewport: geo.size, animated: true)
                            } label: {
                                Image(systemName: "scope")
                                    .font(.system(size: 11, weight: .medium))
                                    .frame(width: 24, height: 24)
                            }
                            .buttonStyle(.plain)
                            .pointerStyle(.link)
                            .help("自适应居中星图")
                        }
                        .foregroundStyle(tokens.primaryInk.opacity(0.76))
                        .padding(.horizontal, 8)
                        .frame(height: 30)
                        .background(tokens.card.opacity(0.92), in: Capsule())
                        .overlay(Capsule().strokeBorder(tokens.hairlineStrong, lineWidth: 0.75))
                        .shadow(color: tokens.cardShadow, radius: 8, y: 2)
                    }
                    .padding(16)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                LinearGradient(
                    colors: [tokens.canvasTop, tokens.canvasBottom],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 4)
                    .onChanged { value in
                        if self.dragStartPan == nil {
                            self.dragStartPan = self.panOffset
                        }
                        let base = self.dragStartPan ?? .zero
                        self.panOffset = CGSize(
                            width: base.width + value.translation.width,
                            height: base.height + value.translation.height
                        )
                    }
                    .onEnded { _ in
                        self.dragStartPan = nil
                    }
            )
            .simultaneousGesture(
                MagnifyGesture()
                    .onChanged { value in
                        if self.pinchBaseZoom == nil {
                            self.pinchBaseZoom = self.zoomScale
                        }
                        let base = self.pinchBaseZoom ?? 1.0
                        self.zoomScale = max(0.45, min(2.2, base * value.magnification))
                    }
                    .onEnded { _ in
                        self.pinchBaseZoom = nil
                    }
            )
            .onAppear {
                if !self.hasAutoFitted {
                    self.hasAutoFitted = true
                    self.autoFit(layoutBounds: layout.bounds, viewport: geo.size, animated: false)
                }
            }
            .onChange(of: self.clusters.count) { _, _ in
                self.autoFit(layoutBounds: self.computedLayout.bounds, viewport: geo.size, animated: true)
            }
        }
    }
    
    
    private func autoFit(layoutBounds: CGRect, viewport: CGSize, animated: Bool) {
        guard viewport.width > 120, viewport.height > 120,
              layoutBounds.width > 10, layoutBounds.height > 10 else { return }
        let usableW = max(180, viewport.width - 96)
        let usableH = max(160, viewport.height - 156)
        let fit = min(usableW / layoutBounds.width, usableH / layoutBounds.height)
        let clamped = max(0.55, min(1.06, fit))
        let apply = {
            self.zoomScale = clamped
            self.panOffset = .zero
        }
        if animated {
            withAnimation(.spring(response: 0.34, dampingFraction: 0.84)) { apply() }
        } else {
            apply()
        }
    }
}


/// Shared macOS QuickLook-style Spacebar Preview Sheet floating cleanly over the Star-Map.
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
    @State private var studioPalette = StudioPaletteManager.shared
    
    
    var body: some View {
        let tokens = self.studioPalette.tokens(isDark: self.colorScheme == .dark)
        
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
                                .frame(width: 24, height: 24)
                                .background(tokens.inset, in: Circle())
                        }
                        .buttonStyle(.plain)
                        .disabled(!self.canStepPrevious)
                        .opacity(self.canStepPrevious ? 1 : 0.35)
                        
                        Button(action: self.onNext) {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 10.5, weight: .semibold))
                                .frame(width: 24, height: 24)
                                .background(tokens.inset, in: Circle())
                        }
                        .buttonStyle(.plain)
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
                                .font(.system(size: 10.5, weight: .medium, design: .rounded).monospacedDigit())
                                .foregroundStyle(tokens.primaryInk.opacity(0.52))
                                .lineLimit(1)
                        }
                    }
                    
                    Spacer(minLength: 8)
                    
                    self.headerActions()
                    
                    Button(action: self.onClose) {
                        HStack(spacing: 3) {
                            Text("SPACE")
                                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                                .foregroundStyle(tokens.primaryInk.opacity(0.45))
                            Image(systemName: "xmark")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(tokens.primaryInk.opacity(0.72))
                        }
                        .padding(.horizontal, 8)
                        .frame(height: 26)
                        .background(tokens.inset, in: Capsule())
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
            .background(tokens.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(tokens.hairlineStrong, lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(self.colorScheme == .dark ? 0.55 : 0.22), radius: 32, y: 12)
            .padding(28)
        }
        .transition(.opacity.combined(with: .scale(scale: 0.96)))
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


// MARK: - Immersive Star-Map Document Center

struct DocumentCenterView: View {
    
    @Bindable var state: DocumentCenterState
    var onOpenDocument: ((Document?, StoredDocumentRecord?) -> Void)?
    var onOpenAllDocuments: (([DocumentCenterState.ManagedDocumentItem]) -> Void)?
    var onDeleteDocument: ((DocumentCenterState.ManagedDocumentItem) -> Void)?
    var onCreateNewDocument: (() -> Void)?
    var onDismiss: (() -> Void)?
    
    @Environment(\.colorScheme) private var colorScheme
    @State private var db = CotLocalDatabase.shared
    @State private var studioPalette = StudioPaletteManager.shared
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
        let tokens = self.studioPalette.tokens(isDark: self.colorScheme == .dark)
        let clusters = self.buildStarClusters(displayedItems: displayedItems, tokens: tokens)
        let itemByID = Dictionary(uniqueKeysWithValues: displayedItems.map { ($0.id, $0) })
        let sectionByID = Dictionary(uniqueKeysWithValues: self.state.groupSections.map { ($0.id, $0) })
        
        ZStack {
            // Full-window Immersive Constellation Star-Map
            ConstellationStarMapView(
                hubTitle: self.state.showingTrash ? "废纸篓" : "文档星图",
                hubSubtitle: self.state.showingTrash
                    ? "\(displayedItems.count) 篇已删"
                    : "\(displayedItems.count) 篇 · \(max(1, self.state.groupSections.count)) 分组",
                clusters: clusters,
                selectedLeafID: activeItem?.id,
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
                                self.state.refresh()
                                self.showToast("已解散分组「\(section.name)」")
                            }
                        }
                    }
                },
                leafContextMenu: { leaf in
                    if let item = itemByID[leaf.id] {
                        if item.isTrashed {
                            Button("空格预览") {
                                self.state.selectedID = item.id
                                withAnimation(.easeOut(duration: 0.16)) { self.isQuickLookOpen = true }
                            }
                            Button("恢复文档") { self.restore(item: item) }
                            Divider()
                            Button("彻底删除", role: .destructive) { self.permanentlyDelete(item: item) }
                        } else {
                            Button("在编辑器打开") { self.open(item: item) }
                            Button("空格预览") {
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
                                ForEach(self.db.documentGroups, id: \.self) { groupName in
                                    Button {
                                        self.move(item: item, toGroup: groupName)
                                    } label: {
                                        if item.groupName == groupName {
                                            Label(groupName, systemImage: "checkmark")
                                        } else {
                                            Text(groupName)
                                        }
                                    }
                                }
                                if !self.db.documentGroups.isEmpty { Divider() }
                                Button("未分组") { self.move(item: item, toGroup: "") }
                                Divider()
                                Button("新建分组并移入…") {
                                    self.pendingAssignAfterGroupCreate = item
                                    self.newGroupDraft = ""
                                    self.isCreatingGroup = true
                                }
                            }
                            Divider()
                            Button("移到废纸篓", role: .destructive) {
                                self.delete(item: item, in: displayedItems)
                            }
                        }
                    }
                }
            )
            
            // Minimal Floating Top HUD + Bottom Selected-Star Action Dock
            VStack(spacing: 0) {
                self.floatingTopBar(tokens: tokens, displayedItems: displayedItems)
                    .padding(.horizontal, 16)
                    .padding(.top, 14)
                
                if self.isCreatingGroup {
                    self.inlineGroupPromptBar(
                        placeholder: "输入新分组名称，回车创建",
                        text: self.$newGroupDraft,
                        tokens: tokens,
                        onCommit: { self.commitCreateGroup() },
                        onCancel: {
                            self.isCreatingGroup = false
                            self.pendingAssignAfterGroupCreate = nil
                        }
                    )
                    .padding(.top, 8)
                } else if let renamingGroupName = self.renamingGroupName {
                    self.inlineGroupPromptBar(
                        placeholder: "重命名分组「\(renamingGroupName)」",
                        text: self.$groupRenameDraft,
                        tokens: tokens,
                        onCommit: { self.commitGroupRename(oldName: renamingGroupName) },
                        onCancel: { self.renamingGroupName = nil }
                    )
                    .padding(.top, 8)
                }
                
                Spacer()
                
                if let activeItem {
                    self.bottomFocusDock(item: activeItem, allItems: displayedItems, tokens: tokens)
                        .padding(.bottom, 16)
                } else if displayedItems.isEmpty {
                    self.floatingEmptyHint(tokens: tokens)
                        .padding(.bottom, 22)
                }
            }
            
            // Spacebar QuickLook Preview Overlay
            if self.isQuickLookOpen, let item = activeItem {
                let idx = displayedItems.firstIndex(where: { $0.id == item.id }) ?? 0
                StarMapQuickLookOverlay(
                    title: item.title,
                    subtitle: "\(item.characterCount.formatted()) 字" + (item.groupName.isEmpty ? "" : " · \(item.groupName)"),
                    canStepPrevious: displayedItems.count > 1,
                    canStepNext: displayedItems.count > 1,
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
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { self.copiedFlag = false }
                        } label: {
                            Text(self.copiedFlag ? "已复制" : "复制")
                                .font(.system(size: 11.5, weight: .medium))
                                .foregroundStyle(tokens.primaryInk.opacity(0.78))
                                .padding(.horizontal, 10)
                                .frame(height: 26)
                                .background(tokens.inset, in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .pointerStyle(.link)
                        
                        if item.isTrashed {
                            Button {
                                self.restore(item: item)
                                self.isQuickLookOpen = false
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
                                    .background(tokens.accent, in: Capsule())
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
            
            // Toast
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
        }
        .onDisappear {
            self.removeKeyboardMonitor()
        }
        .onChange(of: self.db.documents.count) { _, _ in
            self.state.refresh()
        }
        .onChange(of: self.db.trashedDocuments.count) { _, _ in
            self.state.refresh()
        }
    }
    
    
    // MARK: Floating HUDs
    
    private func floatingTopBar(
        tokens: StudioColorTokens,
        displayedItems: [DocumentCenterState.ManagedDocumentItem]
    ) -> some View {
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
                    .padding(.horizontal, 10)
                    .frame(height: 30)
                    .background(tokens.card.opacity(0.92), in: Capsule())
                    .overlay(Capsule().strokeBorder(tokens.hairlineStrong, lineWidth: 0.75))
                }
                .buttonStyle(.plain)
                .pointerStyle(.link)
            }
            
            // Compact search pill
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(tokens.primaryInk.opacity(0.45))
                TextField("搜索星图文档…", text: self.$state.searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .frame(width: 170)
                if !self.state.searchText.isEmpty {
                    Button {
                        self.state.searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(tokens.primaryInk.opacity(0.40))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(tokens.card.opacity(0.92), in: Capsule())
            .overlay(Capsule().strokeBorder(tokens.hairlineStrong, lineWidth: 0.75))
            
            Spacer(minLength: 8)
            
            // Minimal single-row actions (zero duplicate icons)
            HStack(spacing: 6) {
                if !self.state.showingTrash {
                    if let onCreateNewDocument = self.onCreateNewDocument {
                        Button(action: onCreateNewDocument) {
                            Text("新建文档")
                                .font(.system(size: 11.5, weight: .semibold))
                                .foregroundStyle(tokens.onAccentInk)
                                .padding(.horizontal, 11)
                                .frame(height: 28)
                                .background(tokens.accent, in: Capsule())
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
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(tokens.primaryInk.opacity(0.78))
                            .padding(.horizontal, 10)
                            .frame(height: 28)
                            .background(tokens.card.opacity(0.92), in: Capsule())
                            .overlay(Capsule().strokeBorder(tokens.hairlineStrong, lineWidth: 0.75))
                    }
                    .buttonStyle(.plain)
                    .pointerStyle(.link)
                } else if !self.state.trashedItems.isEmpty {
                    Button {
                        self.confirmEmptyTrash()
                    } label: {
                        Text("清空废纸篓")
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(.red)
                            .padding(.horizontal, 10)
                            .frame(height: 28)
                            .background(Color.red.opacity(0.12), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .pointerStyle(.link)
                }
                
                Button {
                    withAnimation(.easeOut(duration: 0.18)) {
                        self.isQuickLookOpen = false
                        self.state.showingTrash.toggle()
                    }
                } label: {
                    let count = self.state.trashedItems.count
                    Text(self.state.showingTrash ? "返回文档" : (count > 0 ? "废纸篓 \(count)" : "废纸篓"))
                        .font(.system(size: 11.5, weight: .medium).monospacedDigit())
                        .foregroundStyle(self.state.showingTrash ? tokens.accentText : tokens.primaryInk.opacity(0.68))
                        .padding(.horizontal, 10)
                        .frame(height: 28)
                        .background(
                            self.state.showingTrash ? tokens.positivePillBg : tokens.card.opacity(0.92),
                            in: Capsule()
                        )
                        .overlay(Capsule().strokeBorder(tokens.hairlineStrong, lineWidth: 0.75))
                }
                .buttonStyle(.plain)
                .pointerStyle(.link)
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
                .foregroundStyle(tokens.primaryInk.opacity(0.65))
                .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(tokens.card, in: Capsule())
        .overlay(Capsule().strokeBorder(tokens.accent.opacity(0.45), lineWidth: 1))
        .shadow(color: tokens.cardShadow, radius: 10, y: 3)
    }
    
    
    private func bottomFocusDock(
        item: DocumentCenterState.ManagedDocumentItem,
        allItems: [DocumentCenterState.ManagedDocumentItem],
        tokens: StudioColorTokens
    ) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(self.statusColor(for: item, tokens: tokens))
                .frame(width: 7, height: 7)
            
            if self.isRenaming && !item.isTrashed {
                TextField("文档标题", text: self.$renameDraft)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12.5, weight: .semibold))
                    .focused(self.$isRenameFieldFocused)
                    .frame(width: 170)
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
                        .frame(maxWidth: 180, alignment: .leading)
                    Text("\(item.characterCount.formatted()) 字" + (item.groupName.isEmpty ? "" : " · \(item.groupName)"))
                        .font(.system(size: 10, weight: .medium, design: .rounded).monospacedDigit())
                        .foregroundStyle(tokens.primaryInk.opacity(0.50))
                }
                
                Rectangle()
                    .fill(tokens.hairlineStrong)
                    .frame(width: 1, height: 20)
                
                Button {
                    withAnimation(.easeOut(duration: 0.16)) { self.isQuickLookOpen = true }
                } label: {
                    HStack(spacing: 4) {
                        Text("预览")
                            .font(.system(size: 11.5, weight: .medium))
                        Text("SPACE")
                            .font(.system(size: 8.5, weight: .semibold, design: .monospaced))
                            .foregroundStyle(tokens.primaryInk.opacity(0.45))
                    }
                    .foregroundStyle(tokens.primaryInk.opacity(0.86))
                    .padding(.horizontal, 9)
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
                            .padding(.horizontal, 11)
                            .frame(height: 26)
                            .background(tokens.accent, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .pointerStyle(.link)
                    
                    Button {
                        self.renameDraft = item.title
                        self.isRenaming = true
                        DispatchQueue.main.async { self.isRenameFieldFocused = true }
                    } label: {
                        Text("重命名")
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(tokens.primaryInk.opacity(0.76))
                            .padding(.horizontal, 8)
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
                    }
                    .buttonStyle(.plain)
                    .pointerStyle(.link)
                    .help("移到废纸篓")
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(tokens.card.opacity(0.95), in: Capsule())
        .overlay(Capsule().strokeBorder(tokens.hairlineStrong, lineWidth: 0.85))
        .shadow(color: tokens.cardShadow, radius: 14, y: 4)
    }
    
    
    private func floatingEmptyHint(tokens: StudioColorTokens) -> some View {
        Text(self.state.showingTrash ? "废纸篓是空的" : (self.state.searchText.isEmpty ? "暂无文档 · 点击右上角新建" : "没有匹配的文档"))
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(tokens.primaryInk.opacity(0.55))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(tokens.card.opacity(0.90), in: Capsule())
            .overlay(Capsule().strokeBorder(tokens.hairline, lineWidth: 0.75))
    }
    
    
    // MARK: Constellation Data Mapping
    
    private func buildStarClusters(
        displayedItems: [DocumentCenterState.ManagedDocumentItem],
        tokens: StudioColorTokens
    ) -> [StarMapClusterNode] {
        let clusterPalette: [Color] = [
            tokens.accent,
            tokens.secondaryAccent,
            Color(red: 0.45, green: 0.62, blue: 0.94),
            Color(red: 0.88, green: 0.56, blue: 0.34),
            Color(red: 0.74, green: 0.48, blue: 0.88),
        ]
        
        if self.state.showingTrash {
            let maxChars = max(1.0, Double(displayedItems.map(\.characterCount).max() ?? 1))
            let leaves = displayedItems.map { item in
                StarMapLeafNode(
                    id: item.id,
                    clusterID: "__trash__",
                    title: item.title,
                    subtitle: "\(item.characterCount.formatted()) 字",
                    dotColor: Color.red.opacity(0.78),
                    weight: min(1.0, Double(item.characterCount) / maxChars),
                    isHighlighted: false
                )
            }
            return leaves.isEmpty ? [] : [
                StarMapClusterNode(
                    id: "__trash__",
                    title: "废纸篓",
                    subtitle: "\(leaves.count)",
                    accent: Color.red.opacity(0.78),
                    isCollapsed: false,
                    leaves: leaves
                ),
            ]
        }
        
        let maxChars = max(1.0, Double(displayedItems.map(\.characterCount).max() ?? 1))
        return self.state.groupSections.enumerated().map { idx, section in
            let accent = section.isUngrouped ? tokens.secondaryAccent : clusterPalette[idx % clusterPalette.count]
            let leaves = section.items.map { item in
                StarMapLeafNode(
                    id: item.id,
                    clusterID: section.id,
                    title: item.title,
                    subtitle: "\(item.characterCount.formatted()) 字",
                    dotColor: self.statusColor(for: item, tokens: tokens),
                    weight: min(1.0, Double(item.characterCount) / maxChars),
                    isHighlighted: item.isOpenNow
                )
            }
            return StarMapClusterNode(
                id: section.id,
                title: section.name,
                subtitle: "\(section.items.count)",
                accent: accent,
                isCollapsed: self.state.collapsedGroups.contains(section.id),
                leaves: leaves
            )
        }
    }
    
    
    private func statusColor(for item: DocumentCenterState.ManagedDocumentItem, tokens: StudioColorTokens) -> Color {
        if item.isTrashed { return .red.opacity(0.75) }
        if item.isDirty { return Color(red: 0.94, green: 0.56, blue: 0.20) }
        if item.isOpenNow { return tokens.accent }
        return tokens.secondaryAccent
    }
    
    
    private func selectedItem(in displayedItems: [DocumentCenterState.ManagedDocumentItem]) -> DocumentCenterState.ManagedDocumentItem? {
        if let selectedID = self.state.selectedID,
           let matched = displayedItems.first(where: { $0.id == selectedID })
        {
            return matched
        }
        return displayedItems.first
    }
    
    
    // MARK: Keyboard Navigation (Space QuickLook, Arrows, Return Open, Esc Close)
    
    private func installKeyboardMonitor() {
        self.removeKeyboardMonitor()
        self.keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // Never hijack keystrokes while typing in search/rename text fields
            if NSApp.keyWindow?.firstResponder is NSTextView {
                return event
            }
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            guard flags.isDisjoint(with: [.command, .control, .option]) else { return event }
            
            switch event.keyCode {
                case 49: // Space -> QuickLook Preview toggle
                    let items = self.state.displayedItems
                    guard self.selectedItem(in: items) != nil else { return event }
                    withAnimation(.easeOut(duration: 0.16)) {
                        self.isQuickLookOpen.toggle()
                    }
                    return nil
                    
                case 53: // Esc
                    if self.isQuickLookOpen {
                        withAnimation(.easeOut(duration: 0.14)) { self.isQuickLookOpen = false }
                        return nil
                    }
                    if self.isRenaming {
                        self.isRenaming = false
                        return nil
                    }
                    if self.isCreatingGroup || self.renamingGroupName != nil {
                        self.isCreatingGroup = false
                        self.renamingGroupName = nil
                        return nil
                    }
                    if let onDismiss = self.onDismiss {
                        onDismiss()
                        return nil
                    }
                    return event
                    
                case 36: // Return -> Open selected document
                    if !self.isRenaming, let active = self.selectedItem(in: self.state.displayedItems), !active.isTrashed {
                        self.isQuickLookOpen = false
                        self.open(item: active)
                        return nil
                    }
                    return event
                    
                case 123, 126: // Left / Up -> Previous star
                    self.stepSelection(by: -1, in: self.state.displayedItems)
                    return nil
                    
                case 124, 125: // Right / Down -> Next star
                    self.stepSelection(by: 1, in: self.state.displayedItems)
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
