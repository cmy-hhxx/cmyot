//
//  AnalyticsDashboardView.swift
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
import ImageIO
import SwiftUI
import UniformTypeIdentifiers
import Vision

// MARK: - Window / Settings Entry Points

/// Routes dashboard presentation requests into the active editor window (never opens a standalone window).
@MainActor final class AnalyticsDashboardWindowController {
    
    static let shared = AnalyticsDashboardWindowController()
    
    
    private init() {}
    
    
    func showWindow(_ sender: Any?) {
        
        self.showInWindow(preferredWindow: (sender as? NSWindow) ?? NSApp.mainWindow)
    }
    
    
    func showInWindow(preferredWindow: NSWindow? = nil) {
        
        AnalyticsManager.shared.flushPendingStats()
        AnalyticsManager.shared.reloadFromDatabase()
        
        if let activeWC = self.resolveDocumentWindowController(preferredWindow: preferredWindow),
           let contentVC = activeWC.workspaceContentViewController
        {
            contentVC.showInWindowCenter(.dashboard)
            activeWC.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        
        if let controller = NSDocumentController.shared as? DocumentController {
            _ = try? controller.openUntitledDocumentAndDisplay(true)
            if let activeWC = self.resolveDocumentWindowController(preferredWindow: nil),
               let contentVC = activeWC.workspaceContentViewController
            {
                contentVC.showInWindowCenter(.dashboard)
                activeWC.window?.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
            }
        }
    }
    
    
    func openDocument(_ record: StoredDocumentRecord, preferredWindow: NSWindow? = nil) {
        
        if let activeWC = self.resolveDocumentWindowController(preferredWindow: preferredWindow),
           let docVC = activeWC.workspaceContentViewController?.documentViewController
        {
            docVC.openStoredDocumentRecord(record)
            activeWC.workspaceContentViewController?.hideInWindowCenter()
            activeWC.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }
    
    
    private func resolveDocumentWindowController(preferredWindow: NSWindow?) -> DocumentWindowController? {
        
        if let wc = preferredWindow?.windowController as? DocumentWindowController {
            return wc
        }
        if let wc = NSApp.mainWindow?.windowController as? DocumentWindowController {
            return wc
        }
        return NSApp.orderedWindows
            .compactMap { $0.windowController as? DocumentWindowController }
            .first
    }
}


/// Settings pane wrapper matching the unified Settings pane proportions.
struct DashboardSettingsView: View {
    
    var body: some View {
        
        AnalyticsDashboardView(isEmbeddedInSettings: true)
            .frame(width: SettingsPaneLayout.width, height: SettingsPaneLayout.height)
    }
}


// MARK: - Sub-Layer Escape Coordination

private struct WorkspaceCenterEscRegisterKey: EnvironmentKey {
    static let defaultValue: (@MainActor ((() -> Bool)?) -> Void)? = nil
}

extension EnvironmentValues {
    var registerWorkspaceCenterEscPop: (@MainActor ((() -> Bool)?) -> Void)? {
        get { self[WorkspaceCenterEscRegisterKey.self] }
        set { self[WorkspaceCenterEscRegisterKey.self] = newValue }
    }
}


// MARK: - Mathematical Trend Curve Engine (Fritsch–Carlson C¹ Hermite Spline + Gaussian μ ± σ Band)

nonisolated enum MathematicalTrendCurveEngine {
    
    struct SamplePoint: Sendable, Equatable {
        let t: Double        // Normalized x in [0, 1]
        let value: Double    // Interpolated value >= 0
        let mu: Double       // Gaussian kernel regression mean
        let sigma: Double    // Local Gaussian-weighted std dev
        
        var upper: Double { self.mu + 0.65 * self.sigma }
        var lower: Double { max(0, self.mu - 0.65 * self.sigma) }
    }
    
    struct Result: Sendable {
        let rawValues: [Double]
        let samples: [SamplePoint]
        let maxScale: Double
        let peakIndex: Int?
        let peakValue: Double
        let averageValue: Double
    }
    
    
    /// Evaluates a C¹ monotone cubic Hermite spline (Fritsch–Carlson) alongside a Gaussian kernel
    /// regression curve μ(t) and local ±0.65σ volatility corridor over `values`.
    static func compute(values: [Double], samplesPerSegment: Int = 8, bandwidth: Double = 1.65) -> Result {
        let clean = values.map { max(0, $0.isFinite ? $0 : 0) }
        guard !clean.isEmpty else {
            return Result(rawValues: [], samples: [], maxScale: 100, peakIndex: nil, peakValue: 0, averageValue: 0)
        }
        
        let n = clean.count
        let average = clean.reduce(0, +) / Double(n)
        let peakPair = clean.enumerated().max(by: { $0.element < $1.element })
        let peakIdx = (peakPair?.element ?? 0) > 0 ? peakPair?.offset : nil
        let peakVal = peakPair?.element ?? 0
        
        if n == 1 {
            let v = clean[0]
            let s = SamplePoint(t: 0.5, value: v, mu: v, sigma: 0)
            return Result(
                rawValues: clean,
                samples: [s],
                maxScale: max(100, v * 1.15),
                peakIndex: peakIdx,
                peakValue: peakVal,
                averageValue: average
            )
        }
        
        // 1. Fritsch–Carlson monotone cubic Hermite tangents (unit step h = 1)
        var secants = [Double](repeating: 0, count: n - 1)
        for k in 0..<(n - 1) {
            secants[k] = clean[k + 1] - clean[k]
        }
        var tangents = [Double](repeating: 0, count: n)
        tangents[0] = secants[0]
        tangents[n - 1] = secants[n - 2]
        for k in 1..<(n - 1) {
            if secants[k - 1] * secants[k] > 0 {
                tangents[k] = 0.5 * (secants[k - 1] + secants[k])
            } else {
                tangents[k] = 0
            }
        }
        for k in 0..<(n - 1) {
            let dk = secants[k]
            if abs(dk) < 1e-9 {
                tangents[k] = 0
                tangents[k + 1] = 0
            } else {
                let alpha = tangents[k] / dk
                let beta = tangents[k + 1] / dk
                let sq = alpha * alpha + beta * beta
                if sq > 9.0 {
                    let tau = 3.0 / sqrt(sq)
                    tangents[k] = tau * alpha * dk
                    tangents[k + 1] = tau * beta * dk
                }
            }
        }
        
        // 2. Dense curve evaluation + Gaussian kernel regression μ(x) and local σ(x)
        let segSteps = max(2, samplesPerSegment)
        let totalSteps = (n - 1) * segSteps
        var samples: [SamplePoint] = []
        samples.reserveCapacity(totalSteps + 1)
        let twoB2 = max(0.2, 2.0 * bandwidth * bandwidth)
        
        var globalMax: Double = max(100, peakVal)
        for step in 0...totalSteps {
            let x = Double(step) / Double(segSteps)
            let k = min(n - 2, Int(floor(x)))
            let u = max(0, min(1, x - Double(k)))
            let u2 = u * u
            let u3 = u2 * u
            
            let h00 = 2 * u3 - 3 * u2 + 1
            let h10 = u3 - 2 * u2 + u
            let h01 = -2 * u3 + 3 * u2
            let h11 = u3 - u2
            
            let splineY = max(0, h00 * clean[k] + h10 * tangents[k] + h01 * clean[k + 1] + h11 * tangents[k + 1])
            
            var wSum = 0.0
            var wySum = 0.0
            for i in 0..<n {
                let d = x - Double(i)
                let w = exp(-(d * d) / twoB2)
                wSum += w
                wySum += w * clean[i]
            }
            let mu = wSum > 0 ? (wySum / wSum) : splineY
            
            var wVarSum = 0.0
            for i in 0..<n {
                let d = x - Double(i)
                let w = exp(-(d * d) / twoB2)
                let diff = clean[i] - mu
                wVarSum += w * diff * diff
            }
            let sigma = wSum > 0 ? sqrt(wVarSum / wSum) : 0
            
            let t = x / Double(n - 1)
            let point = SamplePoint(t: t, value: splineY, mu: mu, sigma: sigma)
            globalMax = max(globalMax, point.upper, point.value)
            samples.append(point)
        }
        
        return Result(
            rawValues: clean,
            samples: samples,
            maxScale: max(100, globalMax * 1.10),
            peakIndex: peakIdx,
            peakValue: peakVal,
            averageValue: average
        )
    }
}


// MARK: - Reference-Faithful Drill-Down Sunburst Layout Engine (from eval_data_server/sunburst.js)

nonisolated enum EvalSunburstLayoutEngine {
    
    static let innerRatioRange: ClosedRange<CGFloat> = (64.0 / 110.0)...(84.0 / 110.0)
    static let outerRatioRange: ClosedRange<CGFloat> = (89.0 / 110.0)...(101.0 / 110.0)
    static let maxKeptChildren = 7
    
    final class Node: Identifiable {
        let id: String
        let name: String
        let value: Double
        let outputValue: Double
        let requests: Int
        let isOther: Bool
        weak var parent: Node?
        var children: [Node]
        
        init(
            id: String,
            name: String,
            value: Double,
            outputValue: Double = 0,
            requests: Int = 0,
            isOther: Bool = false,
            children: [Node] = []
        ) {
            self.id = id
            self.name = name
            self.value = value
            self.outputValue = outputValue
            self.requests = requests
            self.isOther = isOther
            self.children = children
        }
    }
    
    enum Ring: Sendable {
        case inner
        case outer
    }
    
    struct ArcItem: Identifiable {
        enum ToneKind {
            case openActive
            case sibling
            case otherInner
            case outerIndexed(index: Int, count: Int)
            case otherOuter
            case outputMark
        }
        
        let key: String
        let node: Node
        let ring: Ring
        let isMark: Bool
        let a0: Double        // Radians clockwise from 12 o'clock (-π/2 in CG)
        let a1: Double
        let r0Ratio: CGFloat
        let r1Ratio: CGFloat
        let tone: ToneKind
        
        var id: String { self.key }
    }
    
    struct LedgerRow: Identifiable {
        let node: Node
        let ring: Ring
        let isOpenHeader: Bool
        let isSubRow: Bool
        let fraction: Double
        let tone: ArcItem.ToneKind
        
        var id: String { self.node.id }
    }
    
    
    /// Folds smallest children beyond `KEEP = 7` into one "其他" node and links parent pointers.
    static func prepareTree(_ raw: Node, parent: Node? = nil, fold: Bool = true) -> Node {
        var kids = raw.children.filter { $0.value > 0 }
        if fold, kids.count > Self.maxKeptChildren + 1 {
            let sorted = kids.sorted { $0.value > $1.value }
            let keepSet = Set(sorted.prefix(Self.maxKeptChildren).map(\.id))
            let kept = kids.filter { keepSet.contains($0.id) }
            let rest = kids.filter { !keepSet.contains($0.id) }
            let restVal = rest.reduce(0.0) { $0 + $1.value }
            let restOut = rest.reduce(0.0) { $0 + $1.outputValue }
            let restReq = rest.reduce(0) { $0 + $1.requests }
            let otherNode = Node(
                id: "\(raw.id)/~",
                name: "其他",
                value: restVal,
                outputValue: restOut,
                requests: restReq,
                isOther: true
            )
            kids = kept + [otherNode]
        }
        let preparedChildren = kids.map { Self.prepareTree($0, parent: nil, fold: fold) }
        let outSum = raw.outputValue > 0 ? raw.outputValue : preparedChildren.reduce(0.0) { $0 + $1.outputValue }
        let reqSum = raw.requests > 0 ? raw.requests : preparedChildren.reduce(0) { $0 + $1.requests }
        let copy = Node(
            id: raw.id,
            name: raw.name,
            value: max(raw.value, preparedChildren.reduce(0.0) { $0 + $1.value }),
            outputValue: outSum,
            requests: reqSum,
            isOther: raw.isOther,
            children: preparedChildren
        )
        copy.parent = parent
        for child in copy.children {
            child.parent = copy
        }
        return copy
    }
    
    
    static func indexByID(_ root: Node) -> [String: Node] {
        var map: [String: Node] = [:]
        func walk(_ node: Node) {
            map[node.id] = node
            for c in node.children { walk(c) }
        }
        walk(root)
        return map
    }
    
    
    static func biggestNonOtherChild(of node: Node) -> Node? {
        node.children
            .filter { !$0.isOther }
            .max(by: { $0.value < $1.value }) ?? node.children.first
    }
    
    
    /// Produces sunburst.js layout: inner ring holds `focus.children` across 0..2π;
    /// outer rail holds `open.children` constrained strictly inside `open`'s angular span.
    static func layout(focus: Node, open: Node?) -> (arcs: [ArcItem], rows: [LedgerRow]) {
        let tau = Double.pi * 2.0
        let kids = focus.children
        let total = max(1e-9, kids.reduce(0.0) { $0 + $1.value })
        
        var arcs: [ArcItem] = []
        var innerColorMap: [String: ArcItem.ToneKind] = [:]
        var outerColorMap: [String: ArcItem.ToneKind] = [:]
        
        func appendMark(for node: Node, a0: Double, a1: Double, outerRatio: CGFloat, keyPrefix: String) {
            guard node.outputValue > 0, node.value > 0 else { return }
            let frac = min(1.0, node.outputValue / node.value)
            let end = a0 + (a1 - a0) * frac
            guard end - a0 > 1e-4 else { return }
            arcs.append(ArcItem(
                key: "\(keyPrefix)#mark",
                node: node,
                ring: keyPrefix.hasPrefix("out:") ? .outer : .inner,
                isMark: true,
                a0: a0,
                a1: end,
                r0Ratio: outerRatio + (1.2 / 110.0),
                r1Ratio: outerRatio + (3.8 / 110.0),
                tone: .outputMark
            ))
        }
        
        var a = 0.0
        var openSpan: (Double, Double)?
        for child in kids {
            let a1 = a + (tau * child.value) / total
            let tone: ArcItem.ToneKind = if child.id == open?.id {
                .openActive
            } else if child.isOther {
                .otherInner
            } else {
                .sibling
            }
            innerColorMap[child.id] = tone
            arcs.append(ArcItem(
                key: "in:\(child.id)",
                node: child,
                ring: .inner,
                isMark: false,
                a0: a,
                a1: a1,
                r0Ratio: Self.innerRatioRange.lowerBound,
                r1Ratio: Self.innerRatioRange.upperBound,
                tone: tone
            ))
            appendMark(for: child, a0: a, a1: a1, outerRatio: Self.innerRatioRange.upperBound, keyPrefix: "in:\(child.id)")
            if child.id == open?.id {
                openSpan = (a, a1)
            }
            a = a1
        }
        
        if let open, !open.children.isEmpty, let span = openSpan {
            let subTotal = max(1e-9, open.children.reduce(0.0) { $0 + $1.value })
            var b = span.0
            let subCount = open.children.count
            for (idx, sub) in open.children.enumerated() {
                let b1 = b + ((span.1 - span.0) * sub.value) / subTotal
                let tone: ArcItem.ToneKind = sub.isOther ? .otherOuter : .outerIndexed(index: idx, count: subCount)
                outerColorMap[sub.id] = tone
                arcs.append(ArcItem(
                    key: "out:\(sub.id)",
                    node: sub,
                    ring: .outer,
                    isMark: false,
                    a0: b,
                    a1: b1,
                    r0Ratio: Self.outerRatioRange.lowerBound,
                    r1Ratio: Self.outerRatioRange.upperBound,
                    tone: tone
                ))
                appendMark(for: sub, a0: b, a1: b1, outerRatio: Self.outerRatioRange.upperBound, keyPrefix: "out:\(sub.id)")
                b = b1
            }
        }
        
        // Ledger rows: siblings ordered by volume (keeping 其他 last), expanding `open.children` inline under `open`
        let orderedKids = kids.sorted { lhs, rhs in
            if lhs.isOther != rhs.isOther { return !lhs.isOther }
            return lhs.value > rhs.value
        }
        var rows: [LedgerRow] = []
        for child in orderedKids {
            let isOpen = (child.id == open?.id)
            rows.append(LedgerRow(
                node: child,
                ring: .inner,
                isOpenHeader: isOpen,
                isSubRow: false,
                fraction: child.value / total,
                tone: innerColorMap[child.id] ?? .sibling
            ))
            if isOpen, !child.children.isEmpty {
                let subOrdered = child.children.sorted { lhs, rhs in
                    if lhs.isOther != rhs.isOther { return !lhs.isOther }
                    return lhs.value > rhs.value
                }
                for sub in subOrdered {
                    rows.append(LedgerRow(
                        node: sub,
                        ring: .outer,
                        isOpenHeader: false,
                        isSubRow: true,
                        fraction: sub.value / max(1e-9, child.value),
                        tone: outerColorMap[sub.id] ?? .otherOuter
                    ))
                }
            }
        }
        
        return (arcs, rows)
    }
    
    
    /// Non-jumpy radial two-ring sunburst layout: displays every visible child's inner wedge AND
    /// all sub-children's outer arcs simultaneously around 0..2π so hover/click never teleports outer rings.
    static func radialLayout(focus: Node) -> (arcs: [ArcItem], rows: [LedgerRow], hueMap: [String: Int]) {
        let tau = Double.pi * 2.0
        let kids = focus.children.sorted { lhs, rhs in
            if lhs.isOther != rhs.isOther { return !lhs.isOther }
            return lhs.value > rhs.value
        }
        let total = max(1e-9, kids.reduce(0.0) { $0 + $1.value })
        let innerLow: CGFloat = 55.0 / 110.0
        let innerHigh: CGFloat = 78.5 / 110.0
        let outerLow: CGFloat = 80.5 / 110.0
        let outerHigh: CGFloat = 102.0 / 110.0
        
        var arcs: [ArcItem] = []
        var rows: [LedgerRow] = []
        var hueMap: [String: Int] = [:]
        
        var a = 0.0
        for (idx, child) in kids.enumerated() {
            let a1 = a + (tau * child.value) / total
            let hueIndex = child.isOther ? -1 : idx
            hueMap[child.id] = hueIndex
            
            let tone: ArcItem.ToneKind = child.isOther ? .otherInner : .sibling
            arcs.append(ArcItem(
                key: "in:\(child.id)",
                node: child,
                ring: .inner,
                isMark: false,
                a0: a,
                a1: a1,
                r0Ratio: innerLow,
                r1Ratio: innerHigh,
                tone: tone
            ))
            
            rows.append(LedgerRow(
                node: child,
                ring: .inner,
                isOpenHeader: false,
                isSubRow: false,
                fraction: child.value / total,
                tone: tone
            ))
            
            if !child.children.isEmpty {
                let subKids = child.children.sorted { lhs, rhs in
                    if lhs.isOther != rhs.isOther { return !lhs.isOther }
                    return lhs.value > rhs.value
                }
                let subTotal = max(1e-9, subKids.reduce(0.0) { $0 + $1.value })
                var b = a
                for (subIdx, sub) in subKids.enumerated() {
                    let b1 = b + ((a1 - a) * sub.value) / subTotal
                    let subTone: ArcItem.ToneKind = sub.isOther
                        ? .otherOuter
                        : .outerIndexed(index: subIdx, count: subKids.count)
                    hueMap[sub.id] = hueIndex
                    arcs.append(ArcItem(
                        key: "out:\(sub.id)",
                        node: sub,
                        ring: .outer,
                        isMark: false,
                        a0: b,
                        a1: b1,
                        r0Ratio: outerLow,
                        r1Ratio: outerHigh,
                        tone: subTone
                    ))
                    b = b1
                }
            }
            
            a = a1
        }
        
        return (arcs, rows, hueMap)
    }
    
    
    /// Gapless polar hit-testing exposed cleanly on layout engine for both hover UI and unit tests.
    static func gaplessHitTest(
        _ point: CGPoint,
        center: CGPoint,
        radius: CGFloat,
        arcs: [ArcItem]
    ) -> ArcItem? {
        let dx = point.x - center.x
        let dy = point.y - center.y
        let dist = hypot(dx, dy)
        let normR = dist / max(1, radius)
        guard normR >= (53.0 / 110.0), normR <= (105.0 / 110.0) else { return nil }
        
        var angle = atan2(dy, dx) + Double.pi * 0.5
        if angle < 0 { angle += Double.pi * 2.0 }
        
        let seamMid: CGFloat = 79.5 / 110.0
        let targetRing: Ring = normR < seamMid ? .inner : .outer
        
        if let exact = arcs.first(where: { !$0.isMark && $0.ring == targetRing && angle >= $0.a0 && angle <= $0.a1 }) {
            return exact
        }
        return arcs.first(where: { !$0.isMark && $0.ring == .inner && angle >= $0.a0 && angle <= $0.a1 })
    }
    
    
    static func buildTree(
        events recentAIEvents: [AIUsageEvent],
        models aiModels: [ModelUsageSummary],
        features aiFeatures: [FeatureUsageSummary],
        ai30Totals: AIUsageTotals
    ) -> Node {
        let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? .distantPast
        return Self.buildTree(
            windowEvents: recentAIEvents.filter { $0.timestamp >= cutoff },
            models: aiModels,
            features: aiFeatures,
            ai30Totals: ai30Totals
        )
    }


    fileprivate static func buildTree(
        windowEvents events: [AIUsageEvent],
        models aiModels: [ModelUsageSummary],
        features aiFeatures: [FeatureUsageSummary],
        ai30Totals: AIUsageTotals
    ) -> Node {
        func featureDisplayName(_ key: String) -> String {
            switch key.lowercased() {
                case "completion", "inline", "continue": "续写"
                case "translate": "翻译"
                case "summarize": "摘要"
                case "explain": "解释"
                case "weeklyreport", "weekly_report": "周报"
                case "ocrpolish", "ocr": "识图"
                default: key.isEmpty ? "对话" : key
            }
        }
        
        func shortName(_ raw: String) -> String {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.count <= 14 ? trimmed : String(trimmed.prefix(13)) + "…"
        }
        
        var modelNodes: [Node] = []
        if !events.isEmpty {
            let groupedByModel = Dictionary(grouping: events, by: { $0.model.trimmingCharacters(in: .whitespacesAndNewlines) })
            modelNodes = groupedByModel.compactMap { rawModel, modelEvents in
                let name = rawModel.isEmpty ? "主力模型" : shortName(rawModel)
                let featGroups = Dictionary(grouping: modelEvents, by: { $0.feature })
                let featNodes: [Node] = featGroups.map { featureKey, featEvents in
                    let inTok = featEvents.reduce(0.0) { $0 + Double(max(0, $1.inputTokens)) }
                    let outTok = featEvents.reduce(0.0) { $0 + Double(max(0, $1.outputTokens)) }
                    let val = max(Double(featEvents.count * 120), inTok + outTok)
                    let fid = "model:\(name)/feat:\(featureKey)"
                    let ioNodes = [
                        Node(id: "\(fid)/in", name: "输入", value: max(1, inTok > 0 ? inTok : val * 0.62), outputValue: 0, requests: featEvents.count),
                        Node(id: "\(fid)/out", name: "生成", value: max(1, outTok > 0 ? outTok : val * 0.38), outputValue: outTok, requests: featEvents.count),
                    ]
                    return Node(
                        id: fid,
                        name: featureDisplayName(featureKey),
                        value: val,
                        outputValue: outTok,
                        requests: featEvents.count,
                        children: ioNodes
                    )
                }.sorted { $0.value > $1.value }
                
                let totalIn = modelEvents.reduce(0.0) { $0 + Double(max(0, $1.inputTokens)) }
                let totalOut = modelEvents.reduce(0.0) { $0 + Double(max(0, $1.outputTokens)) }
                let totalVal = max(Double(modelEvents.count * 150), totalIn + totalOut)
                return Node(
                    id: "model:\(name)",
                    name: name,
                    value: totalVal,
                    outputValue: totalOut,
                    requests: modelEvents.count,
                    children: featNodes
                )
            }.sorted { $0.value > $1.value }
        } else if !aiModels.isEmpty {
            let outShare: Double = ai30Totals.totalTokens > 0 ? Double(ai30Totals.outputTokens) / Double(ai30Totals.totalTokens) : 0.38
            modelNodes = aiModels.map { m in
                let name = shortName(m.model)
                let val = Double(m.totalTokens > 0 ? m.totalTokens : max(1, m.requests * 150))
                let featSum = max(1.0, aiFeatures.reduce(0.0) { $0 + Double($1.totalTokens > 0 ? $1.totalTokens : max(1, $1.requests * 120)) })
                let featNodes: [Node] = aiFeatures.map { f in
                    let fRatio = Double(f.totalTokens > 0 ? f.totalTokens : max(1, f.requests * 120)) / featSum
                    let fw = max(1, val * fRatio)
                    let fid = "model:\(name)/feat:\(f.feature)"
                    return Node(
                        id: fid,
                        name: f.displayName.isEmpty ? featureDisplayName(f.feature) : f.displayName,
                        value: fw,
                        outputValue: fw * outShare,
                        requests: f.requests,
                        children: [
                            Node(id: "\(fid)/in", name: "输入", value: max(1, fw * (1 - outShare))),
                            Node(id: "\(fid)/out", name: "生成", value: max(1, fw * outShare), outputValue: fw * outShare),
                        ]
                    )
                }
                return Node(
                    id: "model:\(name)",
                    name: name,
                    value: val,
                    outputValue: Double(m.outputTokens),
                    requests: m.requests,
                    children: featNodes
                )
            }
        } else {
            let defaults: [(String, Double)] = [("主力模型", 62), ("轻量模型", 38)]
            modelNodes = defaults.map { name, weight in
                let featNodes = [("续写", 0.44), ("翻译", 0.30), ("摘要", 0.26)].map { fName, frac in
                    let fw = weight * frac
                    return Node(
                        id: "model:\(name)/feat:\(fName)",
                        name: fName,
                        value: fw,
                        outputValue: fw * 0.38,
                        children: [
                            Node(id: "model:\(name)/feat:\(fName)/in", name: "输入", value: fw * 0.62),
                            Node(id: "model:\(name)/feat:\(fName)/out", name: "生成", value: fw * 0.38, outputValue: fw * 0.38),
                        ]
                    )
                }
                return Node(
                    id: "model:\(name)",
                    name: name,
                    value: weight,
                    outputValue: weight * 0.38,
                    children: featNodes
                )
            }
        }
        
        let rootSum = max(1.0, modelNodes.reduce(0.0) { $0 + $1.value })
        let rawRoot = Node(
            id: "root",
            name: "30日用量",
            value: rootSum,
            outputValue: Double(ai30Totals.outputTokens),
            requests: ai30Totals.requests,
            children: modelNodes
        )
        return Self.prepareTree(rawRoot, fold: true)
    }
}


// MARK: - Design Tokens & Snapshot

enum DashMotion {
    
    static var isReducedMotion: Bool { AnimationConstants.isReducedMotionEnabled }
    
    static func resolve(_ animation: Animation) -> Animation? {
        AnimationConstants.isReducedMotionEnabled ? nil : animation
    }
    
    static let quick = Animation.easeOut(duration: 0.12)
    static let standard = Animation.timingCurve(0.20, 0.90, 0.30, 1.0, duration: 0.20)
    static let travel = Animation.timingCurve(0.32, 0.0, 0.15, 1.0, duration: 0.20)
    static let sunburst = Animation.timingCurve(0.20, 0.90, 0.30, 1.0, duration: 0.22)
    static let springCard = Animation.snappy(duration: 0.22, extraBounce: 0)
    static let press = Animation.easeOut(duration: 0.09)
    static let chartReveal = Animation.timingCurve(0.18, 0.92, 0.28, 1.0, duration: 0.34)
    static let staggeredEntrance = Animation.easeOut(duration: 0.16)
    static let pageTransition: AnyTransition = .opacity
}


/// Apple HIG concentric corner-radius hierarchy (`outerRadius == innerRadius + inset`)
/// ensuring unified, lightweight curvature across the photo backdrop stage and bento cards.
nonisolated enum DashboardCornerMetrics {
    
    static func unifiedOuterRadius(compact: Bool) -> CGFloat {
        compact ? 20 : 24
    }
    
    static func unifiedInset(compact: Bool) -> CGFloat {
        compact ? 8 : 10
    }
    
    static func innerCardRadius(compact: Bool) -> CGFloat {
        Self.unifiedOuterRadius(compact: compact) - Self.unifiedInset(compact: compact)
    }
    
    static func row2CardRadius(compact: Bool) -> CGFloat {
        compact ? 16 : 18
    }
    
    static let nestedWellRadius: CGFloat = 8
    static let newsMiniCardRadius: CGFloat = 10
    static let newsCoverRadius: CGFloat = 6
}


private enum DashboardQuadMetric: String, CaseIterable, Identifiable {
    
    case typed
    case aiUsage
    case busyness
    case mood
    
    var id: String { self.rawValue }
    
    var title: String {
        switch self {
            case .typed: "今日码字"
            case .aiUsage: "AI用量"
            case .busyness: "忙碌指数"
            case .mood: "心境流向"
        }
    }
}


/// Cohesive neutral-graphite & cobalt-ink design system shared across the Dashboard and NEWS reader.
struct DashPalette: Sendable, Equatable {
    
    let tokens: StudioColorTokens
    let secondaryInk: Color
    let mutedInk: Color
    let statusPositive: Color
    
    init(_ scheme: ColorScheme) {
        let isDark = (scheme == .dark)
        self.tokens = Self.editorialTokens(isDark: isDark)
        if isDark {
            self.secondaryInk = Color(red: 0.604, green: 0.635, blue: 0.706) // #9AA2B4
            self.mutedInk = Color(red: 0.455, green: 0.490, blue: 0.565)     // #747D90
            self.statusPositive = Color(red: 0.298, green: 0.765, blue: 0.541) // #4CC38A
        } else {
            self.secondaryInk = Color(red: 0.306, green: 0.337, blue: 0.408) // #4E5668
            self.mutedInk = Color(red: 0.451, green: 0.486, blue: 0.561)     // #737C8F
            self.statusPositive = Color(red: 0.086, green: 0.639, blue: 0.290) // #16A34A
        }
    }
    
    static func editorialTokens(isDark: Bool) -> StudioColorTokens {
        if isDark {
            let canvas = Color(hexString: "#15161A")
            let card = Color(hexString: "#1C1E24")
            let inset = Color(hexString: "#22252D")
            let insetHover = Color(hexString: "#2A2E38")
            let primary = Color(red: 0.925, green: 0.937, blue: 0.961)      // #ECEFF5
            let accent = Color(hexString: "#519AFD")
            let accentText = Color(hexString: "#8FC0FF")
            let secondaryAcc = Color(red: 0.220, green: 0.365, blue: 0.765) // #385DC3
            let paleAcc = Color(red: 0.145, green: 0.216, blue: 0.396)      // #253765
            let empty = Color(red: 0.137, green: 0.153, blue: 0.188)        // #232730
            
            return StudioColorTokens(
                isDark: true,
                canvasTop: canvas,
                canvasBottom: canvas,
                mistAccent: accent.opacity(0.10),
                card: card,
                cardShadow: .clear,
                inset: inset,
                insetHover: insetHover,
                hairline: Color.white.opacity(0.075),
                hairlineStrong: Color.white.opacity(0.16),
                topSpecular: Color.white.opacity(0.06),
                architecturalDot: Color.white.opacity(0.05),
                primaryInk: primary,
                accent: accent,
                accentText: accentText,
                onAccentInk: .white,
                secondaryAccent: secondaryAcc,
                paleAccent: paleAcc,
                emptyDot: empty,
                positivePillBg: accent.opacity(0.16),
                neutralPillBg: Color.white.opacity(0.07),
                heat1: Color(red: 0.133, green: 0.192, blue: 0.325), // #223153
                heat2: Color(red: 0.173, green: 0.278, blue: 0.514), // #2C4783
                heat3: Color(red: 0.231, green: 0.388, blue: 0.745), // #3B63BE
                heat4: Color(red: 0.345, green: 0.522, blue: 1.000)  // #5885FF
            )
        } else {
            let canvas = Color(hexString: "#F4F5F7")
            let card = Color.white                                          // #FFFFFF
            let inset = Color(hexString: "#F1F3F6")
            let insetHover = Color(hexString: "#E8EBF0")
            let primary = Color(red: 0.082, green: 0.098, blue: 0.133)      // #151922
            let accent = Color(hexString: "#2F7CF6")
            let accentText = Color(hexString: "#1D67DB")
            let secondaryAcc = Color(red: 0.431, green: 0.576, blue: 0.961) // #6E93F5
            let paleAcc = Color(red: 0.871, green: 0.906, blue: 0.992)      // #DEE7FD
            let empty = Color(red: 0.922, green: 0.933, blue: 0.953)        // #EBEEF3
            
            return StudioColorTokens(
                isDark: false,
                canvasTop: canvas,
                canvasBottom: canvas,
                mistAccent: accent.opacity(0.08),
                card: card,
                cardShadow: Color(red: 0.06, green: 0.08, blue: 0.12).opacity(0.035),
                inset: inset,
                insetHover: insetHover,
                hairline: Color(red: 0.08, green: 0.10, blue: 0.14).opacity(0.08),
                hairlineStrong: Color(red: 0.08, green: 0.10, blue: 0.14).opacity(0.16),
                topSpecular: Color.white.opacity(0.80),
                architecturalDot: Color(red: 0.08, green: 0.10, blue: 0.14).opacity(0.05),
                primaryInk: primary,
                accent: accent,
                accentText: accentText,
                onAccentInk: .white,
                secondaryAccent: secondaryAcc,
                paleAccent: paleAcc,
                emptyDot: empty,
                positivePillBg: accent.opacity(0.09),
                neutralPillBg: Color(red: 0.08, green: 0.10, blue: 0.14).opacity(0.05),
                heat1: Color(red: 0.831, green: 0.878, blue: 0.988), // #D4E0FC
                heat2: Color(red: 0.608, green: 0.718, blue: 0.980), // #9BB7FA
                heat3: Color(red: 0.345, green: 0.518, blue: 0.957), // #5884F4
                heat4: Color(red: 0.137, green: 0.314, blue: 0.851)  // #2350D9
            )
        }
    }
    
    var canvasTop: Color { self.tokens.canvasTop }
    var canvasBottom: Color { self.tokens.canvasBottom }
    var card: Color { self.tokens.card }
    var cardShadow: Color { self.tokens.cardShadow }
    var inset: Color { self.tokens.inset }
    var insetHover: Color { self.tokens.insetHover }
    var hairline: Color { self.tokens.hairline }
    var hairlineStrong: Color { self.tokens.hairlineStrong }
    
    var pine: Color { self.tokens.primaryInk }
    var emerald: Color { self.tokens.accentText }
    var accentFill: Color { self.tokens.accent }
    var mint: Color { self.tokens.secondaryAccent }
    var paleMint: Color { self.tokens.paleAccent }
    var emptyDot: Color { self.tokens.emptyDot }
    
    
    func heat(_ level: Int) -> Color {
        switch level {
            case 4: self.tokens.heat4
            case 3: self.tokens.heat3
            case 2: self.tokens.heat2
            case 1: self.tokens.heat1
            default: self.emptyDot
        }
    }
    
    
    func toneColor(for tone: PersonalityTagTone) -> Color {
        switch tone {
            case .calm: self.tokens.accent
            case .sharp: self.tokens.secondaryAccent
            case .warm: self.tokens.isDark
                ? Color(red: 0.345, green: 0.620, blue: 0.745)
                : Color(red: 0.212, green: 0.478, blue: 0.612)
            case .playful: self.tokens.heat2
        }
    }
}


struct DashboardSnapshot {
    
    struct ChartDay: Identifiable, Sendable, Equatable {
        var id: String
        var date: Date
        var typed: Int
        var ai: Int
    }
    
    var snapshotVersion: Int
    var today: DailyWritingStats
    var days14: [ChartDay]
    var trendCurve14: MathematicalTrendCurveEngine.Result
    var aiTrendCurve14: MathematicalTrendCurveEngine.Result
    var yearlyHeatmap: YearlyHeatmapData
    var currentStreak: Int
    var availableYears: [Int]
    var aiTodayTotals: AIUsageTotals
    var ai30Totals: AIUsageTotals
    var aiModels: [ModelUsageSummary]
    var aiFeatures: [FeatureUsageSummary]
    var sunburstRoot: EvalSunburstLayoutEngine.Node
    var sunburstIndex: [String: EvalSunburstLayoutEngine.Node]
    var busyness: BusynessMetrics
    var mood: MoodMetrics
    var doneTodayPoints: [String]
    var actionPredictions: [DocumentActionPrediction]
    
    
    private static let dayKeyFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar.current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
    
    
    @MainActor static func build(analytics: AnalyticsManager, selectedYear: Int, version: Int = 1) -> DashboardSnapshot {
        let now = Date()
        let today = analytics.todayStats
        let series14 = analytics.dailySeries(days: 14, referenceDate: now)
        
        let days14: [ChartDay] = series14.map { item in
            ChartDay(
                id: item.dateKey,
                date: Self.dayKeyFormatter.date(from: item.dateKey) ?? Date(),
                typed: item.typedChars,
                ai: item.aiCompletedChars
            )
        }
        let trendCurve14 = MathematicalTrendCurveEngine.compute(
            values: days14.map { Double($0.typed + $0.ai) },
            samplesPerSegment: 8,
            bandwidth: 1.65
        )
        let aiTrendCurve14 = MathematicalTrendCurveEngine.compute(
            values: days14.map { Double($0.ai) },
            samplesPerSegment: 6,
            bandwidth: 1.5
        )
        
        let availableYears = analytics.availableHeatmapYears(referenceDate: now)
        let resolvedYear = availableYears.contains(selectedYear)
            ? selectedYear
            : (availableYears.last ?? Calendar.current.component(.year, from: now))
        let yearly = analytics.yearlyHeatmap(year: resolvedYear, referenceDate: now, trimFutureWeeks: true)
        
        let aiTodayTotals = analytics.aiUsageTotals(forTodayOnly: true, referenceDate: now)
        let breakdown = analytics.aiUsageBreakdown(days: 30, referenceDate: now)
        let sunburstRoot = EvalSunburstLayoutEngine.buildTree(
            windowEvents: breakdown.events,
            models: breakdown.models,
            features: breakdown.features,
            ai30Totals: breakdown.totals
        )
        let sunburstIndex = EvalSunburstLayoutEngine.indexByID(sunburstRoot)
        
        return DashboardSnapshot(
            snapshotVersion: version,
            today: today,
            days14: days14,
            trendCurve14: trendCurve14,
            aiTrendCurve14: aiTrendCurve14,
            yearlyHeatmap: yearly,
            currentStreak: analytics.writingStreak(referenceDate: now),
            availableYears: availableYears,
            aiTodayTotals: aiTodayTotals,
            ai30Totals: breakdown.totals,
            aiModels: breakdown.models,
            aiFeatures: breakdown.features,
            sunburstRoot: sunburstRoot,
            sunburstIndex: sunburstIndex,
            busyness: analytics.busynessMetrics,
            mood: analytics.moodMetrics,
            doneTodayPoints: analytics.doneTodayPoints,
            actionPredictions: analytics.actionPredictions
        )
    }
}


// MARK: - Responsive Single-Page Viewport Layout Solver

/// Pure deterministic single-page layout solver for `AnalyticsDashboardView`.
/// Fits Hero + Row 1 + Row 2 cleanly inside standard macOS windows without vertical scrolling,
/// preserving balanced editorial proportions and falling back to scrolling only on very short windows.
nonisolated struct DashboardViewportLayout: Equatable, Sendable {
    let outerPadH: CGFloat
    let outerPadV: CGFloat
    let vSpacing: CGFloat
    let hSpacing: CGFloat
    let unifiedInnerGap: CGFloat
    let unifiedBottomPad: CGFloat
    let heroHeight: CGFloat
    let row1Height: CGFloat
    let row2Height: CGFloat
    let leftColumnRatio: CGFloat
    let maxContentWidth: CGFloat
    let isTight: Bool
    let needsVerticalScroll: Bool
    
    var unifiedTopStageHeight: CGFloat {
        self.heroHeight + self.unifiedInnerGap + self.row1Height + self.unifiedBottomPad
    }
    
    var totalContentHeight: CGFloat {
        self.outerPadV * 2 + self.vSpacing + self.unifiedTopStageHeight + self.row2Height
    }
    
    static func resolve(
        viewportSize: CGSize,
        isEmbeddedInSettings: Bool,
        hasHeroPhoto: Bool
    ) -> DashboardViewportLayout {
        let vpH = max(480, viewportSize.height)
        let vpW = max(680, viewportSize.width)
        let isTight = isEmbeddedInSettings || vpH < 760
        
        let outerPadH: CGFloat = isEmbeddedInSettings ? 10 : (vpW >= 1280 ? 14 : 12)
        let outerPadV: CGFloat = isEmbeddedInSettings ? 6 : (vpH >= 840 ? 9 : 7)
        let vSpacing: CGFloat = isEmbeddedInSettings ? 8 : (vpH >= 840 ? 10 : 8)
        let hSpacing: CGFloat = isEmbeddedInSettings ? 8 : 10
        let unifiedInnerGap: CGFloat = isTight ? 6 : 8
        let unifiedBottomPad: CGFloat = DashboardCornerMetrics.unifiedInset(compact: isEmbeddedInSettings)
        
        let minHero: CGFloat = isEmbeddedInSettings ? (hasHeroPhoto ? 102 : 90) : (hasHeroPhoto ? 110 : 96)
        let maxHero: CGFloat = isEmbeddedInSettings ? (hasHeroPhoto ? 124 : 108) : (hasHeroPhoto ? 144 : 122)
        let minRow1: CGFloat = isEmbeddedInSettings ? 196 : 216
        let maxRow1: CGFloat = isEmbeddedInSettings ? 290 : 390
        let minRow2: CGFloat = isEmbeddedInSettings ? 168 : 186
        let maxRow2: CGFloat = isEmbeddedInSettings ? 214 : 238
        
        let chromeV = outerPadV * 2 + vSpacing + unifiedInnerGap + unifiedBottomPad
        let minTotal = chromeV + minHero + minRow1 + minRow2
        let needsScroll = vpH < minTotal
        let usableH = max(minHero + minRow1 + minRow2, vpH - chromeV)
        
        let heroWeight: CGFloat = hasHeroPhoto ? 0.175 : 0.145
        let heroH = min(maxHero, max(minHero, floor(usableH * heroWeight)))
        
        let remainingAfterHero = usableH - heroH
        // Keep Row 2 crisp and void-free while giving data-dense Row 1 (Heatmap + Curves + Quads) generous breathing room.
        let desiredRow2 = min(maxRow2, max(minRow2, floor(remainingAfterHero * 0.37)))
        let row1H = min(maxRow1, max(minRow1, floor(remainingAfterHero - desiredRow2)))
        let row2H = min(maxRow2, max(minRow2, floor(remainingAfterHero - row1H)))
        
        return DashboardViewportLayout(
            outerPadH: outerPadH,
            outerPadV: outerPadV,
            vSpacing: vSpacing,
            hSpacing: hSpacing,
            unifiedInnerGap: unifiedInnerGap,
            unifiedBottomPad: unifiedBottomPad,
            heroHeight: heroH,
            row1Height: row1H,
            row2Height: row2H,
            leftColumnRatio: isEmbeddedInSettings ? 0.51 : 0.545,
            maxContentWidth: isEmbeddedInSettings ? 1160 : 1440,
            isTight: isTight,
            needsVerticalScroll: needsScroll
        )
    }
}


// MARK: - Two-Row Bento Dashboard + Interactive NEWS Workspace

struct AnalyticsDashboardView: View {
    
    let isEmbeddedInSettings: Bool
    var onDismiss: (() -> Void)?
    var onOpenDocument: ((StoredDocumentRecord) -> Void)?
    var onOpenWeeklyReport: ((StoredWeeklyReport) -> Void)?
    
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.registerWorkspaceCenterEscPop) private var registerEscPop
    
    @State private var analytics = AnalyticsManager.shared
    @State private var profileManager = UserProfileManager.shared
    @State private var studioPalette = StudioPaletteManager.shared
    @State private var heroCoverStore = DashboardHeroCoverStore.shared
    
    @State private var snapshot: DashboardSnapshot?
    @State private var snapshotVersion: Int = 0
    @State private var selectedYear: Int = Calendar.current.component(.year, from: Date())
    @State private var expandedQuad: DashboardQuadMetric?
    @State private var isNewsWorkspaceOpen = false
    @State private var activeNewsID: String?
    @State private var hasAppeared = false
    @State private var pendingRebuildTask: Task<Void, Never>?
    
    
    init(
        isEmbeddedInSettings: Bool,
        onDismiss: (() -> Void)? = nil,
        onOpenDocument: ((StoredDocumentRecord) -> Void)? = nil,
        onOpenWeeklyReport: ((StoredWeeklyReport) -> Void)? = nil
    ) {
        self.isEmbeddedInSettings = isEmbeddedInSettings
        self.onDismiss = onDismiss
        self.onOpenDocument = onOpenDocument
        self.onOpenWeeklyReport = onOpenWeeklyReport
    }
    
    
    private var palette: DashPalette {
        _ = self.studioPalette.revision
        return DashPalette(self.colorScheme)
    }
    
    var body: some View {
        ZStack {
            self.palette.canvasTop
                .ignoresSafeArea()
            
            if self.isNewsWorkspaceOpen {
                DashboardNewsCenterView(
                    newsService: AIHotNewsService.shared,
                    tokens: self.palette.tokens,
                    initialSelectedID: self.activeNewsID,
                    onClose: {
                        self.isNewsWorkspaceOpen = false
                    }
                )
            } else {
                let hasHeroPhoto = (self.heroCoverStore.coverImage != nil)
                
                GeometryReader { viewportGeo in
                    let layout = DashboardViewportLayout.resolve(
                        viewportSize: viewportGeo.size,
                        isEmbeddedInSettings: self.isEmbeddedInSettings,
                        hasHeroPhoto: hasHeroPhoto
                    )
                    
                    let contentStack = Group {
                        if let snapshot = self.snapshot {
                            VStack(alignment: .leading, spacing: layout.vSpacing) {
                                DashboardAchievementHeroBar(
                                    profile: self.profileManager.activeProfile,
                                    avatarImage: self.profileManager.avatarImage(for: self.profileManager.activeProfile),
                                    snapshot: snapshot,
                                    heroHeight: layout.heroHeight,
                                    innerGap: layout.unifiedInnerGap,
                                    bottomPad: layout.unifiedBottomPad,
                                    compact: self.isEmbeddedInSettings,
                                    palette: self.palette,
                                    onBack: self.isEmbeddedInSettings ? nil : self.onDismiss
                                ) {
                                    self.row1Section(snapshot, layout: layout, overPhoto: hasHeroPhoto)
                                }
                                .frame(maxWidth: .infinity)
                                .frame(height: layout.unifiedTopStageHeight)
                                .animation(DashMotion.resolve(DashMotion.standard), value: hasHeroPhoto)
                                
                                self.row2Section(snapshot, layout: layout)
                            }
                            .opacity(self.hasAppeared ? 1 : 0)
                            .animation(DashMotion.resolve(DashMotion.staggeredEntrance), value: self.hasAppeared)
                            .padding(.horizontal, layout.outerPadH)
                            .padding(.vertical, layout.outerPadV)
                            .frame(maxWidth: layout.maxContentWidth, alignment: .leading)
                            .frame(maxWidth: .infinity, minHeight: viewportGeo.size.height, alignment: .top)
                        } else {
                            Color.clear.frame(maxWidth: .infinity, minHeight: viewportGeo.size.height)
                        }
                    }
                    
                    if layout.needsVerticalScroll {
                        ScrollView(.vertical, showsIndicators: true) {
                            contentStack
                        }
                        .transition(.opacity)
                    } else {
                        contentStack
                            .frame(width: viewportGeo.size.width, height: viewportGeo.size.height, alignment: .top)
                            .clipped()
                            .transition(.opacity)
                    }
                }
            }
        }
        .onKeyPress(.escape) {
            if self.handleEscapePop() {
                return .handled
            }
            if let onDismiss = self.onDismiss {
                onDismiss()
                return .handled
            }
            return .ignored
        }
        .onAppear {
            self.registerEscPop? {
                self.handleEscapePop()
            }
        }
        .onDisappear {
            self.pendingRebuildTask?.cancel()
            self.registerEscPop?(nil)
        }
        .task {
            self.rebuildSnapshot()
            withAnimation(DashMotion.standard) {
                self.hasAppeared = true
            }
            async let newsTask: Void = AIHotNewsService.shared.refreshIfNeeded()
            async let predTask: Void = self.analytics.refreshActionPredictions(force: false)
            async let doneTask: Void = self.analytics.refreshDoneTodayCommentary(force: false)
            _ = await (newsTask, predTask, doneTask)
        }
        .onChange(of: self.analytics.revision) { _, _ in
            self.scheduleCoalescedRebuild()
        }
        .onChange(of: self.analytics.actionPredictions) { _, _ in
            self.scheduleCoalescedRebuild()
        }
        .onChange(of: self.analytics.doneTodayCommentary) { _, _ in
            self.scheduleCoalescedRebuild()
        }
        .onChange(of: self.selectedYear) { _, _ in
            self.rebuildSnapshot()
        }
    }
    
    
    private func handleEscapePop() -> Bool {
        if self.isNewsWorkspaceOpen {
            withAnimation(DashMotion.standard) {
                self.isNewsWorkspaceOpen = false
            }
            return true
        }
        if self.expandedQuad != nil {
            withAnimation(DashMotion.standard) {
                self.expandedQuad = nil
            }
            return true
        }
        return false
    }
    
    
    // MARK: Row 1 — Unified Heatmap + Mathematical Wave Card & AI Usage / Busyness Rose / Mood Flow
    
    private func row1Section(
        _ snapshot: DashboardSnapshot,
        layout: DashboardViewportLayout,
        overPhoto: Bool
    ) -> some View {
        let height = layout.row1Height
        let spacing = layout.hSpacing
        return GeometryReader { proxy in
            let usableW = max(320, proxy.size.width - spacing)
            let leftWidth = floor(usableW * layout.leftColumnRatio)
            let rightWidth = max(160, usableW - leftWidth)
            
            HStack(alignment: .top, spacing: spacing) {
                DashboardHeatmapCard(
                    yearlyHeatmap: snapshot.yearlyHeatmap,
                    today: snapshot.today,
                    days14: snapshot.days14,
                    trendCurve14: snapshot.trendCurve14,
                    aiTrendCurve14: snapshot.aiTrendCurve14,
                    currentStreak: snapshot.currentStreak,
                    availableYears: snapshot.availableYears,
                    selectedYear: self.$selectedYear,
                    compact: layout.isTight,
                    cornerRadius: DashboardCornerMetrics.innerCardRadius(compact: self.isEmbeddedInSettings),
                    overPhoto: overPhoto,
                    palette: self.palette
                )
                .frame(width: leftWidth, height: height)
                
                self.flippableQuadSection(snapshot, height: height, gap: spacing, overPhoto: overPhoto)
                    .frame(width: rightWidth, height: height)
            }
        }
        .frame(height: height)
    }
    
    
    private func flippableQuadSection(
        _ snapshot: DashboardSnapshot,
        height: CGFloat,
        gap: CGFloat,
        overPhoto: Bool
    ) -> some View {
        let cardRadius = DashboardCornerMetrics.innerCardRadius(compact: self.isEmbeddedInSettings)
        return ZStack {
            if let expanded = self.expandedQuad {
                DashboardExpandedQuadCard(
                    metric: expanded,
                    snapshot: snapshot,
                    cornerRadius: cardRadius,
                    overPhoto: overPhoto,
                    palette: self.palette
                ) {
                    withAnimation(DashMotion.resolve(DashMotion.springCard)) {
                        self.expandedQuad = nil
                    }
                }
                .id("expanded-\(expanded.rawValue)")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .transition(.opacity)
            } else {
                let vGap: CGFloat = gap
                let hGap: CGFloat = gap
                let topH = max(84, floor((height - vGap) * 0.49))
                let botH = max(80, height - vGap - topH)
                
                VStack(spacing: vGap) {
                    DashboardAIUsageWideCard(
                        snapshot: snapshot,
                        cornerRadius: cardRadius,
                        overPhoto: overPhoto,
                        palette: self.palette
                    ) {
                        withAnimation(DashMotion.resolve(DashMotion.springCard)) {
                            self.expandedQuad = .aiUsage
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: topH, maxHeight: topH)
                    
                    HStack(spacing: hGap) {
                        self.quadCard(metric: .busyness, snapshot: snapshot, cornerRadius: cardRadius, overPhoto: overPhoto)
                            .frame(maxWidth: .infinity, minHeight: botH, maxHeight: botH)
                        self.quadCard(metric: .mood, snapshot: snapshot, cornerRadius: cardRadius, overPhoto: overPhoto)
                            .frame(maxWidth: .infinity, minHeight: botH, maxHeight: botH)
                    }
                }
                .id("compact-bento-grid")
                .transition(.opacity)
            }
        }
        .animation(DashMotion.resolve(DashMotion.springCard), value: self.expandedQuad)
    }
    
    
    private func quadCard(
        metric: DashboardQuadMetric,
        snapshot: DashboardSnapshot,
        cornerRadius: CGFloat,
        overPhoto: Bool
    ) -> some View {
        DashboardCompactQuadCard(
            metric: metric,
            snapshot: snapshot,
            cornerRadius: cornerRadius,
            overPhoto: overPhoto,
            palette: self.palette
        ) {
            withAnimation(DashMotion.resolve(DashMotion.springCard)) {
                self.expandedQuad = metric
            }
        }
    }
    
    
    // MARK: Row 2 — Balanced Editorial + NEWS Strip (30.5% 干了啥 / 30.5% 要干啥 / 39% NEWS)
    
    private func row2Section(_ snapshot: DashboardSnapshot, layout: DashboardViewportLayout) -> some View {
        let height = layout.row2Height
        let spacing = layout.hSpacing
        let row2Radius = DashboardCornerMetrics.row2CardRadius(compact: self.isEmbeddedInSettings)
        return GeometryReader { proxy in
            let usableW = max(360, proxy.size.width - spacing * 2)
            let useAsymmetric = (!self.isEmbeddedInSettings && usableW >= 720)
            let newsW = useAsymmetric ? floor(usableW * 0.39) : floor(usableW / 3.0)
            let editorialW = max(140, floor((usableW - newsW) * 0.5))
            let resolvedNewsW = max(160, usableW - editorialW * 2)
            
            HStack(alignment: .top, spacing: spacing) {
                self.doneTodayColumn(points: snapshot.doneTodayPoints, compact: layout.isTight, cornerRadius: row2Radius)
                    .frame(width: editorialW, height: height, alignment: .topLeading)
                
                self.predictedActionsColumn(predictions: snapshot.actionPredictions, compact: layout.isTight, cornerRadius: row2Radius)
                    .frame(width: editorialW, height: height, alignment: .topLeading)
                
                DashboardNewsColumnCard(
                    compact: self.isEmbeddedInSettings,
                    tightPadding: layout.isTight,
                    cornerRadius: row2Radius,
                    cardHeight: height,
                    palette: self.palette,
                    onOpenWorkspace: { selectedID in
                        self.openNewsWorkspace(selecting: selectedID)
                    }
                )
                .frame(width: resolvedNewsW, height: height, alignment: .topLeading)
            }
        }
        .frame(height: height)
    }
    
    
    private func doneTodayColumn(points: [String], compact: Bool, cornerRadius: CGFloat) -> some View {
        DoneTodayEditorialCard(
            points: points,
            compact: compact,
            cornerRadius: cornerRadius,
            palette: self.palette
        )
    }
    
    
    private func predictedActionsColumn(predictions: [DocumentActionPrediction], compact: Bool, cornerRadius: CGFloat) -> some View {
        NextActionsEditorialCard(
            predictions: predictions,
            compact: compact,
            cornerRadius: cornerRadius,
            palette: self.palette,
            onOpenDocument: self.onOpenDocument
        )
    }
    
    
    // MARK: Actions
    
    private func openNewsWorkspace(selecting id: String?) {
        self.activeNewsID = id
        withAnimation(DashMotion.standard) {
            self.isNewsWorkspaceOpen = true
        }
    }
    
    
    private func scheduleCoalescedRebuild() {
        self.pendingRebuildTask?.cancel()
        self.pendingRebuildTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else { return }
            self.rebuildSnapshot()
        }
    }
    
    
    private func rebuildSnapshot() {
        self.snapshotVersion &+= 1
        self.snapshot = DashboardSnapshot.build(
            analytics: self.analytics,
            selectedYear: self.selectedYear,
            version: self.snapshotVersion
        )
    }
}


/// Shared Swiss indexed-ledger row used by both "干了啥" and "要干啥" editorial cards.
private struct EditorialLedgerRow: View {
    
    let index: Int
    let text: String
    var subtitle: String? = nil
    let isEmphasized: Bool
    let isHovered: Bool
    let fontSize: CGFloat
    let fontWeight: Font.Weight
    let lineSpacing: CGFloat
    let horizontalInset: CGFloat
    let verticalPad: CGFloat
    let palette: DashPalette
    let onHoverChange: (Bool) -> Void
    
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 9) {
            Text(String(format: "%02d", self.index + 1))
                .font(.system(size: 10.5, weight: .semibold, design: .monospaced).monospacedDigit())
                .foregroundStyle(self.index == 0 ? self.palette.emerald : self.palette.mutedInk.opacity(0.75))
                .frame(width: 18, alignment: .leading)
            
            VStack(alignment: .leading, spacing: 2.5) {
                Text(self.text)
                    .font(.system(size: self.fontSize, weight: self.fontWeight))
                    .foregroundStyle(self.palette.pine.opacity(self.isEmphasized || self.isHovered ? 0.96 : 0.86))
                    .lineSpacing(self.lineSpacing)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                if let subtitle = self.subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 10.5, weight: .regular))
                        .foregroundStyle(self.palette.mutedInk.opacity(0.84))
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, self.horizontalInset)
        .padding(.vertical, self.verticalPad)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(self.isHovered ? self.palette.inset.opacity(0.72) : Color.clear)
        )
        .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .onHover { hovering in
            self.onHoverChange(hovering)
        }
    }
}


/// Clean Swiss-grid editorial "干了啥" card (tight, balanced rhythm with zero cavernous bottom void).
private struct DoneTodayEditorialCard: View {
    
    let points: [String]
    let compact: Bool
    var cornerRadius: CGFloat = 18
    let palette: DashPalette
    
    @State private var hoveredRow: Int?
    
    
    var body: some View {
        let outerH: CGFloat = self.compact ? 12 : 15
        let outerV: CGFloat = self.compact ? 10 : 12
        let scrollOuterH: CGFloat = self.compact ? 6 : 8
        let rowInsetH: CGFloat = outerH - scrollOuterH
        let rowPadV: CGFloat = self.compact ? 6.5 : (self.points.count <= 3 ? 9 : 7)
        
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 6) {
                Text("干了啥")
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(self.palette.pine)
                Spacer(minLength: 4)
                if !self.points.isEmpty {
                    Text("\(self.points.count) 条")
                        .font(.system(size: 11, weight: .medium).monospacedDigit())
                        .foregroundStyle(self.palette.mutedInk.opacity(0.78))
                }
            }
            .frame(height: 20)
            .padding(.horizontal, outerH)
            
            Rectangle()
                .fill(self.palette.hairline)
                .frame(height: 0.75)
                .padding(.horizontal, outerH)
                .padding(.top, 6)
                .padding(.bottom, 3)
            
            ScrollView(.vertical, showsIndicators: false) {
                if self.points.isEmpty {
                    Text(AppLanguage.text("今天还没开张", en: "Quiet desk so far"))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(self.palette.mutedInk)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, rowInsetH)
                        .padding(.vertical, 10)
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(self.points.enumerated()), id: \.offset) { offset, point in
                            if offset > 0 {
                                Rectangle()
                                    .fill(self.palette.hairline.opacity(0.75))
                                    .frame(height: 0.65)
                                    .padding(.leading, rowInsetH + 27)
                                    .padding(.trailing, rowInsetH)
                            }
                            EditorialLedgerRow(
                                index: offset,
                                text: point,
                                isEmphasized: offset == 0,
                                isHovered: self.hoveredRow == offset,
                                fontSize: 12.8,
                                fontWeight: .regular,
                                lineSpacing: 3.5,
                                horizontalInset: rowInsetH,
                                verticalPad: rowPadV,
                                palette: self.palette
                            ) { hovering in
                                if hovering {
                                    self.hoveredRow = offset
                                } else if self.hoveredRow == offset {
                                    self.hoveredRow = nil
                                }
                            }
                        }
                    }
                    .padding(.bottom, 2)
                }
            }
            .padding(.horizontal, scrollOuterH)
        }
        .padding(.vertical, outerV)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .dashboardCardSurface(palette: self.palette, cornerRadius: self.cornerRadius, showsShadow: false)
    }
}


/// Clean Swiss-grid editorial "要干啥" card aligned 1:1 with "干了啥" with clickable source-doc links.
private struct NextActionsEditorialCard: View {
    
    let predictions: [DocumentActionPrediction]
    let compact: Bool
    var cornerRadius: CGFloat = 18
    let palette: DashPalette
    var onOpenDocument: ((StoredDocumentRecord) -> Void)? = nil
    
    @State private var hoveredID: String?
    
    
    var body: some View {
        let outerH: CGFloat = self.compact ? 12 : 15
        let outerV: CGFloat = self.compact ? 10 : 12
        let scrollOuterH: CGFloat = self.compact ? 6 : 8
        let rowInsetH: CGFloat = outerH - scrollOuterH
        let rowPadV: CGFloat = self.compact ? 6.5 : (self.predictions.count <= 4 ? 8 : 6.5)
        
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 6) {
                Text("要干啥")
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(self.palette.pine)
                Spacer(minLength: 4)
                if !self.predictions.isEmpty {
                    Text("\(self.predictions.count) 项")
                        .font(.system(size: 11, weight: .medium).monospacedDigit())
                        .foregroundStyle(self.palette.mutedInk.opacity(0.78))
                }
            }
            .frame(height: 20)
            .padding(.horizontal, outerH)
            
            Rectangle()
                .fill(self.palette.hairline)
                .frame(height: 0.75)
                .padding(.horizontal, outerH)
                .padding(.top, 6)
                .padding(.bottom, 3)
            
            ScrollView(.vertical, showsIndicators: false) {
                if self.predictions.isEmpty {
                    Text(AppLanguage.text("暂无待推进事项", en: "All clear for now"))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(self.palette.mutedInk)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, rowInsetH)
                        .padding(.vertical, 10)
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(self.predictions.enumerated()), id: \.element.id) { idx, pred in
                            if idx > 0 {
                                Rectangle()
                                    .fill(self.palette.hairline.opacity(0.75))
                                    .frame(height: 0.65)
                                    .padding(.leading, rowInsetH + 27)
                                    .padding(.trailing, rowInsetH)
                            }
                            let sourceLabel = self.resolvedSubtitle(for: pred)
                            let linkedDoc = self.resolveDocument(for: pred)
                            let row = EditorialLedgerRow(
                                index: idx,
                                text: pred.action,
                                subtitle: sourceLabel,
                                isEmphasized: idx == 0,
                                isHovered: self.hoveredID == pred.id,
                                fontSize: 12.8,
                                fontWeight: .medium,
                                lineSpacing: 2.5,
                                horizontalInset: rowInsetH,
                                verticalPad: rowPadV,
                                palette: self.palette
                            ) { hovering in
                                if hovering {
                                    self.hoveredID = pred.id
                                } else if self.hoveredID == pred.id {
                                    self.hoveredID = nil
                                }
                            }
                            if let linkedDoc, let onOpenDocument = self.onOpenDocument {
                                Button {
                                    onOpenDocument(linkedDoc)
                                } label: {
                                    row
                                }
                                .buttonStyle(.plain)
                                .pointerStyle(.link)
                            } else {
                                row
                            }
                        }
                    }
                    .padding(.bottom, 2)
                }
            }
            .padding(.horizontal, scrollOuterH)
        }
        .padding(.vertical, outerV)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .dashboardCardSurface(palette: self.palette, cornerRadius: self.cornerRadius, showsShadow: false)
    }
    
    
    private func resolvedSubtitle(for pred: DocumentActionPrediction) -> String? {
        let title = pred.sourceDocumentTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty,
              !GeneratedDocumentName.isGeneratedName(title),
              !pred.action.localizedCaseInsensitiveContains(title)
        else { return nil }
        return title
    }
    
    
    private func resolveDocument(for pred: DocumentActionPrediction) -> StoredDocumentRecord? {
        guard let targetID = pred.sourceDocumentID, !targetID.isEmpty else { return nil }
        return CotLocalDatabase.shared.documents.first {
            $0.id == targetID || $0.filePath == targetID
        }
    }
}


/// Isolated NEWS column card with Douyin/Xiaohongshu-style fresh-batch refresh (zero pagination) and crisp mini cards.
private struct DashboardNewsColumnCard: View {
    
    let compact: Bool
    var tightPadding: Bool = false
    var cornerRadius: CGFloat = 18
    let cardHeight: CGFloat
    let palette: DashPalette
    let onOpenWorkspace: (String?) -> Void
    
    @State private var newsService = AIHotNewsService.shared
    
    
    var body: some View {
        let items = self.newsService.feedItems(for: self.newsService.selectedCategory)
        let outerH: CGFloat = (self.compact || self.tightPadding) ? 12 : 15
        let outerV: CGFloat = (self.compact || self.tightPadding) ? 10 : 12
        
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Button {
                    self.onOpenWorkspace(nil)
                } label: {
                    HStack(spacing: 5) {
                        Text("NEWS")
                            .font(.system(size: 13.5, weight: .semibold))
                            .foregroundStyle(self.palette.pine)
                        
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(self.palette.mutedInk)
                    }
                }
                .buttonStyle(.plain)
                .pointerStyle(.link)
                
                Spacer(minLength: 4)
                
                if !self.compact {
                    HStack(spacing: 2) {
                        ForEach(NewsFeedCategory.allCases) { cat in
                            let active = (self.newsService.selectedCategory == cat)
                            Button {
                                self.newsService.selectedCategory = cat
                                self.newsService.prefetchCovers(for: cat, limit: 8)
                                if self.newsService.feedItems(for: cat).isEmpty {
                                    Task {
                                        await self.newsService.refreshFeed(for: cat, visibleCount: 4, forceNetwork: true)
                                    }
                                }
                            } label: {
                                Text(cat == .xSocial ? "X" : cat.label)
                                    .font(.system(size: 11, weight: active ? .medium : .regular))
                                    .foregroundStyle(active ? self.palette.tokens.onAccentInk : self.palette.secondaryInk)
                                    .padding(.horizontal, 7)
                                    .frame(height: 20)
                                    .background(
                                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                                            .fill(active ? self.palette.accentFill : Color.clear)
                                    )
                                    .contentShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .pointerStyle(.link)
                        }
                    }
                    .padding(2)
                    .background(self.palette.inset, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
                
                DashboardRefreshIconButton(
                    isRefreshing: self.newsService.isLoading,
                    palette: self.palette
                ) {
                    let visibleSlots = self.compact ? 2 : 4
                    Task {
                        await self.newsService.refreshFeed(
                            for: self.newsService.selectedCategory,
                            visibleCount: visibleSlots,
                            forceNetwork: true
                        )
                    }
                }
            }
            .frame(height: 22)
            
            GeometryReader { geo in
                let colCount = (!self.compact && geo.size.width >= 200) ? 2 : 1
                let rowCount = geo.size.height >= 150 ? 2 : 1
                let slotCount = colCount * rowCount
                let gridGap: CGFloat = 8
                let slotH: CGFloat = max(72, floor((geo.size.height - CGFloat(max(0, rowCount - 1)) * gridGap) / CGFloat(rowCount)))
                let showFooterLine = (slotH >= 114)
                let textReservedH: CGFloat = showFooterLine ? 54 : 36
                let coverH: CGFloat = max(40, floor(slotH - textReservedH))
                let activeItems = Array(items.prefix(slotCount))
                
                if activeItems.isEmpty {
                    if self.newsService.isLoading {
                        VStack(spacing: gridGap) {
                            ForEach(0..<rowCount, id: \.self) { _ in
                                HStack(spacing: gridGap) {
                                    ForEach(0..<colCount, id: \.self) { _ in
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .fill(self.palette.inset)
                                            .frame(maxWidth: .infinity)
                                            .frame(height: slotH)
                                    }
                                }
                            }
                        }
                    } else {
                        Button {
                            Task {
                                await self.newsService.refreshFeed(
                                    for: self.newsService.selectedCategory,
                                    visibleCount: slotCount,
                                    forceNetwork: true
                                )
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 12, weight: .medium))
                                Text(AppLanguage.text("刷新获取最新内容", en: "Refresh News"))
                                    .font(.system(size: 12.5, weight: .medium))
                            }
                            .foregroundStyle(self.palette.secondaryInk)
                            .padding(.horizontal, 12)
                            .frame(height: 32)
                            .background(self.palette.inset, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                        .buttonStyle(DashboardCardButtonStyle(pressedScale: 0.99))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                } else {
                    VStack(alignment: .leading, spacing: gridGap) {
                        ForEach(0..<rowCount, id: \.self) { rowIdx in
                            HStack(alignment: .top, spacing: gridGap) {
                                ForEach(0..<colCount, id: \.self) { colIdx in
                                    let itemIdx = rowIdx * colCount + colIdx
                                    if itemIdx < activeItems.count {
                                        let item = activeItems[itemIdx]
                                        NewsMiniVisualCard(
                                            item: item,
                                            cover: self.newsService.cachedCoverImage(for: item),
                                            isRead: self.newsService.isRead(item),
                                            coverHeight: coverH,
                                            slotHeight: slotH,
                                            showPublisherLine: showFooterLine,
                                            palette: self.palette,
                                            onAppearLoadCover: {
                                                self.newsService.requestCoverLoad(for: item)
                                            }
                                        ) {
                                            self.onOpenWorkspace(item.id)
                                        }
                                    } else {
                                        Color.clear
                                            .frame(maxWidth: .infinity)
                                            .frame(height: slotH)
                                    }
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .id("dash-news-\(self.newsService.selectedCategory.rawValue)-\(self.newsService.feedRefreshToken)")
                    .transition(.opacity)
                    .animation(DashMotion.resolve(DashMotion.quick), value: self.newsService.feedRefreshToken)
                    .onAppear {
                        self.newsService.prefetchCovers(for: self.newsService.selectedCategory, limit: slotCount * 2)
                    }
                    .onChange(of: self.newsService.selectedCategory) { _, nextCat in
                        self.newsService.prefetchCovers(for: nextCat, limit: slotCount * 2)
                    }
                }
            }
            .clipped()
        }
        .padding(.horizontal, outerH)
        .padding(.vertical, outerV)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .dashboardCardSurface(palette: self.palette, cornerRadius: self.cornerRadius, showsShadow: false)
    }
}


private struct NewsMiniVisualCard: View {
    
    let item: AIHotNewsItem
    let cover: NSImage?
    let isRead: Bool
    let coverHeight: CGFloat
    let slotHeight: CGFloat
    var showPublisherLine: Bool = true
    let palette: DashPalette
    let onAppearLoadCover: () -> Void
    let onTap: () -> Void
    
    @State private var isHovered = false
    
    
    var body: some View {
        let publisher = self.item.displayPublisherLabel
        let category = self.item.resolvedCategory
        
        Button(action: self.onTap) {
            VStack(alignment: .leading, spacing: 5) {
                ZStack(alignment: .topLeading) {
                    if let cover = self.cover {
                        Color.clear
                            .frame(height: self.coverHeight)
                            .overlay {
                                Image(nsImage: cover)
                                    .resizable()
                                    .interpolation(.medium)
                                    .scaledToFill()
                            }
                            .clipped()
                    } else {
                        self.fallbackCover
                    }
                    
                    HStack(spacing: 4) {
                        Text(category == .xSocial ? "X" : category.badgeLabel)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(self.palette.pine)
                            .padding(.horizontal, 5.5)
                            .frame(height: 16)
                            .background(self.palette.card.opacity(0.86), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                        
                        Spacer(minLength: 0)
                        
                        if !self.isRead {
                            Circle()
                                .fill(self.palette.accentFill)
                                .frame(width: 5, height: 5)
                        }
                    }
                    .padding(5)
                }
                .frame(maxWidth: .infinity)
                .frame(height: self.coverHeight)
                .clipShape(RoundedRectangle(cornerRadius: DashboardCornerMetrics.newsCoverRadius, style: .continuous))
                
                Text(self.item.title)
                    .font(.system(size: self.showPublisherLine ? 11.8 : 11.0, weight: self.isRead ? .regular : .semibold))
                    .foregroundStyle(self.isRead ? self.palette.secondaryInk : self.palette.pine)
                    .lineLimit(2)
                    .lineSpacing(1.5)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .layoutPriority(1)
                
                if self.showPublisherLine {
                    Spacer(minLength: 0)
                    
                    HStack(spacing: 4) {
                        Text(publisher.isEmpty ? category.label : publisher)
                            .font(.system(size: 10, weight: .regular))
                            .foregroundStyle(self.palette.mutedInk)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        
                        Spacer(minLength: 2)
                        
                        if let published = self.item.publishedAt {
                            Text(Self.shortAge(from: published))
                                .font(.system(size: 9.5, design: .monospaced).monospacedDigit())
                                .foregroundStyle(self.palette.mutedInk.opacity(0.8))
                        }
                    }
                }
            }
            .padding(self.showPublisherLine ? 7 : 5)
            .frame(maxWidth: .infinity)
            .frame(height: self.slotHeight, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: DashboardCornerMetrics.newsMiniCardRadius, style: .continuous)
                    .fill(self.isHovered ? self.palette.insetHover : self.palette.inset)
            )
            .clipShape(RoundedRectangle(cornerRadius: DashboardCornerMetrics.newsMiniCardRadius, style: .continuous))
        }
        .buttonStyle(DashboardCardButtonStyle(pressedScale: 0.992))
        .pointerStyle(.link)
        .onAppear {
            self.onAppearLoadCover()
        }
        .onHover { hovering in
            if hovering != self.isHovered {
                self.isHovered = hovering
            }
        }
    }
    
    
    private var fallbackCover: some View {
        let tint: Color = switch self.item.resolvedCategory {
            case .finance: self.palette.statusPositive
            case .xSocial: Color(red: 0.212, green: 0.478, blue: 0.612)
            case .ai, .all: self.palette.accentFill
        }
        let teaser = self.item.summary?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return ZStack(alignment: .bottomLeading) {
            LinearGradient(
                colors: [tint.opacity(self.palette.tokens.isDark ? 0.26 : 0.16), tint.opacity(0.05)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            if !teaser.isEmpty && self.coverHeight >= 54 {
                Text(teaser)
                    .font(.system(size: 9.5, weight: .regular))
                    .foregroundStyle(self.palette.secondaryInk.opacity(0.86))
                    .lineLimit(2)
                    .lineSpacing(1.5)
                    .padding(.horizontal, 7)
                    .padding(.bottom, 6)
            }
        }
    }
    
    
    private static func shortAge(from date: Date) -> String {
        let sec = max(60, Int(Date().timeIntervalSince(date)))
        if sec < 3600 { return "\(sec / 60)m" }
        if sec < 86_400 { return "\(sec / 3600)h" }
        return "\(sec / 86_400)d"
    }
}


// MARK: - Top Achievement Hero Stage (Centered Collector PASS + Flanking Danmaku)

nonisolated enum DashboardHeroDanmakuScheduler {
    
    struct Item: Identifiable, Hashable, Sendable {
        let id: String
        let text: String
        let tone: PersonalityTagTone
    }
    
    struct Placement: Identifiable, Sendable {
        let id: String
        let text: String
        let tone: PersonalityTagTone
        let frame: CGRect
        let opacity: Double
    }
    
    enum Wing: Hashable, Sendable {
        case left
        case right
    }
    
    
    static func estimatedPillSize(for text: String) -> CGSize {
        var width: CGFloat = 38
        for ch in text {
            if ch.isASCII {
                width += (ch == " " ? 4.5 : 8.2)
            } else {
                width += 13.4
            }
        }
        return CGSize(width: min(196, max(64, width.rounded(.up))), height: 24)
    }
    
    
    static func placements(
        canvasSize: CGSize,
        cardRect: CGRect,
        reservedTopLeftRect: CGRect,
        reservedTopRightRect: CGRect = .zero,
        items: [Item],
        elapsed: TimeInterval
    ) -> [Placement] {
        guard canvasSize.width > 120, canvasSize.height > 60, !items.isEmpty else { return [] }
        
        let protectedCard = cardRect.insetBy(dx: -18, dy: -8)
        let protectedBack = reservedTopLeftRect.isEmpty ? .zero : reservedTopLeftRect.insetBy(dx: -12, dy: -8)
        let protectedToggle = reservedTopRightRect.isEmpty ? .zero : reservedTopRightRect.insetBy(dx: -12, dy: -8)
        
        let lanePitch: CGFloat = 38
        let topPad: CGFloat = 10
        let botPad: CGFloat = 10
        let usableH = max(lanePitch, canvasSize.height - topPad - botPad)
        let laneCount = max(2, min(3, Int(usableH / lanePitch)))
        let totalTracksH = CGFloat(laneCount) * lanePitch
        let startY = max(topPad, (canvasSize.height - totalTracksH) * 0.5) + lanePitch * 0.5
        
        var leftBuckets = Array(repeating: [Item](), count: laneCount)
        var rightBuckets = Array(repeating: [Item](), count: laneCount)
        
        for (idx, item) in items.enumerated() {
            let lane = (idx / 2) % laneCount
            if idx.isMultiple(of: 2) {
                leftBuckets[lane].append(item)
            } else {
                rightBuckets[lane].append(item)
            }
        }
        
        var results: [Placement] = []
        let fadeMargin: CGFloat = 28
        let maxWingWidth: CGFloat = 280
        let leftFracs: [CGFloat] = [0.16, 0.68, 0.39]
        let rightFracs: [CGFloat] = [0.54, 0.14, 0.81]
        let laneSpeeds: [CGFloat] = [15.5, 20.5, 17.5]
        
        func scheduleWing(
            _ wing: Wing,
            buckets: [[Item]],
            baseMinX: CGFloat,
            baseMaxX: CGFloat,
            flowRightward: Bool
        ) {
            for lane in 0..<laneCount {
                let laneItems = buckets[lane]
                guard !laneItems.isEmpty else { continue }
                
                let baseY = startY + CGFloat(lane) * lanePitch
                let laneTop = baseY - 14
                let laneBottom = baseY + 14
                
                var laneMinX = baseMinX
                var laneMaxX = baseMaxX
                
                if wing == .left, !protectedBack.isEmpty {
                    let intersectsBackY = laneBottom > protectedBack.minY && laneTop < protectedBack.maxY
                    if intersectsBackY {
                        laneMinX = max(laneMinX, protectedBack.maxX)
                    }
                }
                if wing == .right, !protectedToggle.isEmpty {
                    let intersectsToggleY = laneBottom > protectedToggle.minY && laneTop < protectedToggle.maxY
                    if intersectsToggleY {
                        laneMaxX = min(laneMaxX, protectedToggle.minX)
                    }
                }
                
                let spanW = laneMaxX - laneMinX
                guard spanW >= 92 else { continue }
                
                let validItems = laneItems.filter {
                    Self.estimatedPillSize(for: $0.text).width <= spanW - 10
                }
                guard !validItems.isEmpty else { continue }
                
                let maxW = validItems.map { Self.estimatedPillSize(for: $0.text).width }.max() ?? 110
                let slotStep = maxW + 34
                let cycleLen = max(spanW + maxW + 44, CGFloat(validItems.count) * slotStep)
                let speed = laneSpeeds[lane % laneSpeeds.count] + (wing == .right ? 1.0 : 0)
                let frac = (wing == .left ? leftFracs : rightFracs)[lane % 3]
                let phaseOffset = cycleLen * frac
                
                var placedInLane: [CGRect] = []
                for (idx, item) in validItems.enumerated() {
                    let size = Self.estimatedPillSize(for: item.text)
                    let rawTravel = CGFloat(elapsed) * speed + phaseOffset + CGFloat(idx) * slotStep
                    let travelDist = rawTravel.truncatingRemainder(dividingBy: cycleLen)
                    
                    let centerX: CGFloat = flowRightward
                        ? (laneMinX - maxW * 0.5) + travelDist
                        : (laneMaxX + maxW * 0.5) - travelDist
                    
                    let minX = centerX - size.width * 0.5
                    let maxX = centerX + size.width * 0.5
                    guard minX >= laneMinX, maxX <= laneMaxX else { continue }
                    
                    let floatY = CGFloat(sin(elapsed * 1.35 + Double(lane) * 2.1 + Double(idx) * 0.9)) * 1.5
                    let centerY = baseY + floatY
                    let rect = CGRect(x: minX, y: centerY - size.height * 0.5, width: size.width, height: size.height)
                    guard !rect.intersects(protectedCard) else { continue }
                    if !protectedBack.isEmpty, rect.intersects(protectedBack) { continue }
                    if !protectedToggle.isEmpty, rect.intersects(protectedToggle) { continue }
                    if placedInLane.contains(where: { $0.insetBy(dx: -8, dy: 0).intersects(rect) }) { continue }
                    
                    let edgeClearance = min(minX - laneMinX, laneMaxX - maxX)
                    let fade = min(1.0, max(0.0, Double(edgeClearance / fadeMargin)))
                    let opacity = 0.90 * fade * fade * (3.0 - 2.0 * fade)
                    guard opacity > 0.03 else { continue }
                    
                    placedInLane.append(rect)
                    results.append(Placement(
                        id: "\(wing == .left ? "L" : "R")-\(lane)-\(item.id)",
                        text: item.text,
                        tone: item.tone,
                        frame: rect,
                        opacity: opacity
                    ))
                }
            }
        }
        
        let leftMinX = max(8, protectedCard.minX - maxWingWidth)
        let rightMaxX = min(canvasSize.width - 8, protectedCard.maxX + maxWingWidth)
        scheduleWing(.left, buckets: leftBuckets, baseMinX: leftMinX, baseMaxX: protectedCard.minX, flowRightward: false)
        scheduleWing(.right, buckets: rightBuckets, baseMinX: protectedCard.maxX, baseMaxX: rightMaxX, flowRightward: true)
        
        return results
    }
}


/// Display mode for the user-uploaded dashboard hero cover photo.
nonisolated enum HeroCoverFitMode: String, CaseIterable, Sendable {
    case fill = "fill"
    case fit = "fit"
    
    var label: String {
        switch self {
            case .fill: AppLanguage.text("铺满裁切", en: "Fill Frame")
            case .fit: AppLanguage.text("完整适配", en: "Fit Whole Image")
        }
    }
}


/// Persists and caches the user-uploaded dashboard hero cover photo, EXIF-normalized orientation,
/// 2D focal alignment (`focalX`, `focalY`), and display fit mode (`fill` vs `fit`).
@MainActor @Observable
final class DashboardHeroCoverStore {
    
    static let shared = DashboardHeroCoverStore()
    
    private let database: CotLocalDatabase
    private(set) var coverImage: NSImage? {
        didSet { self.initialToneSample = nil }
    }
    @ObservationIgnored private var initialToneSample: (
        focalX: Double, focalY: Double, fitMode: HeroCoverFitMode, aspect: CGFloat, fallback: HeroRegionTone, result: HeroBackdropToneSnapshot
    )?
    
    var focalX: Double {
        didSet {
            let clamped = max(0.0, min(1.0, self.focalX))
            if abs(clamped - self.focalX) > 0.0001 {
                self.focalX = clamped
                return
            }
            guard abs(oldValue - clamped) > 0.0001 else { return }
            self.database.set(String(format: "%.2f", clamped), forKey: CotLocalDatabase.ConfigKey.dashboardHeroCoverFocalX)
        }
    }
    
    var focalY: Double {
        didSet {
            let clamped = max(0.0, min(1.0, self.focalY))
            if abs(clamped - self.focalY) > 0.0001 {
                self.focalY = clamped
                return
            }
            guard abs(oldValue - clamped) > 0.0001 else { return }
            self.database.set(String(format: "%.2f", clamped), forKey: CotLocalDatabase.ConfigKey.dashboardHeroCoverFocalY)
        }
    }
    
    var fitMode: HeroCoverFitMode {
        didSet {
            guard self.fitMode != oldValue else { return }
            self.database.set(self.fitMode.rawValue, forKey: CotLocalDatabase.ConfigKey.dashboardHeroCoverFitMode)
        }
    }
    
    
    init(database: CotLocalDatabase = .shared) {
        self.database = database
        let rawFocalX = Double(database.string(forKey: CotLocalDatabase.ConfigKey.dashboardHeroCoverFocalX))
        let rawFocalY = Double(database.string(forKey: CotLocalDatabase.ConfigKey.dashboardHeroCoverFocalY))
        let rawMode = database.string(forKey: CotLocalDatabase.ConfigKey.dashboardHeroCoverFitMode)
        self.focalX = max(0.0, min(1.0, rawFocalX ?? 0.50))
        self.focalY = max(0.0, min(1.0, rawFocalY ?? 0.42))
        self.fitMode = HeroCoverFitMode(rawValue: rawMode) ?? .fill
        self.reloadFromDatabase()
    }
    
    
    func reloadFromDatabase() {
        let b64 = self.database.string(forKey: CotLocalDatabase.ConfigKey.dashboardHeroCoverImageBase64)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !b64.isEmpty,
              let data = Data(base64Encoded: b64),
              let cg = Self.normalizedCGImage(from: data, maxDimension: 1920)
        else {
            if !b64.isEmpty,
               let data = Data(base64Encoded: b64),
               let fallback = NSImage(data: data)
            {
                self.coverImage = fallback
            } else {
                self.coverImage = nil
            }
            return
        }
        self.coverImage = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }
    
    
    fileprivate func initialTones(canvasAspect: CGFloat, fallbackRGB: (Double, Double, Double)) -> HeroBackdropToneSnapshot {
        let fallback = HeroRegionTone(red: fallbackRGB.0, green: fallbackRGB.1, blue: fallbackRGB.2)
        if let sample = self.initialToneSample,
           sample.focalX == self.focalX,
           sample.focalY == self.focalY,
           sample.fitMode == self.fitMode,
           sample.aspect == canvasAspect,
           sample.fallback == fallback
        {
            return sample.result
        }
        let result = HeroCoverToneSampler.sample(
            image: self.coverImage,
            focalX: self.focalX,
            focalY: self.focalY,
            fitMode: self.fitMode,
            canvasAspect: canvasAspect,
            fallbackRGB: fallbackRGB
        )
        self.initialToneSample = (self.focalX, self.focalY, self.fitMode, canvasAspect, fallback, result)
        return result
    }
    
    
    @discardableResult
    func setCoverImage(from url: URL) -> Bool {
        if let cg = Self.normalizedCGImage(fromURL: url, maxDimension: 2400) {
            let normalizedNSImage = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
            guard self.setCoverImage(normalizedNSImage) else { return false }
            if let smart = Self.detectSmartFocalPoint(for: cg) {
                self.focalX = smart.x
                self.focalY = smart.y
            } else {
                self.focalX = 0.50
                self.focalY = 0.42
            }
            return true
        }
        guard let image = NSImage(contentsOf: url) else { return false }
        return self.setCoverImage(image)
    }
    
    
    @discardableResult
    func setCoverImage(_ image: NSImage) -> Bool {
        guard let encodedData = Self.processedCoverJPEGData(from: image),
              let cg = Self.normalizedCGImage(from: encodedData, maxDimension: 1920)
        else { return false }
        
        self.database.set(encodedData.base64EncodedString(), forKey: CotLocalDatabase.ConfigKey.dashboardHeroCoverImageBase64)
        self.coverImage = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        return true
    }
    
    
    func applySmartAutoFocal() {
        guard let image = self.coverImage,
              let cg = Self.underlyingCGImage(from: image),
              let smart = Self.detectSmartFocalPoint(for: cg)
        else {
            self.focalX = 0.50
            self.focalY = 0.42
            return
        }
        self.focalX = smart.x
        self.focalY = smart.y
    }
    
    
    func clearCoverImage() {
        self.database.set("", forKey: CotLocalDatabase.ConfigKey.dashboardHeroCoverImageBase64)
        self.coverImage = nil
        self.focalX = 0.50
        self.focalY = 0.42
        self.fitMode = .fill
    }
    
    
    func presentImagePicker() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.prompt = AppLanguage.text("设为背景", en: "Use Image")
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor [weak self] in
                _ = UserMediaLibraryStore.shared.importURLs([url], preferredKind: .background)
                _ = self?.setCoverImage(from: url)
            }
        }
    }
    
    
    nonisolated static func underlyingCGImage(from image: NSImage) -> CGImage? {
        if let direct = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            return direct
        }
        var proposed = NSRect(origin: .zero, size: image.size)
        return image.cgImage(forProposedRect: &proposed, context: nil, hints: nil)
    }
    
    
    /// Uses Vision face detection first, then attention-based saliency, returning top-left normalized `(x, y)` focal coordinates.
    nonisolated static func detectSmartFocalPoint(for cgImage: CGImage) -> (x: Double, y: Double)? {
        guard cgImage.width >= 24, cgImage.height >= 24 else { return nil }
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        
        let faceRequest = VNDetectFaceRectanglesRequest()
        try? handler.perform([faceRequest])
        if let faces = faceRequest.results, !faces.isEmpty {
            let unionBox = faces.reduce(CGRect.null) { $0.union($1.boundingBox) }
            if !unionBox.isNull && !unionBox.isEmpty {
                let fx = max(0.06, min(0.94, Double(unionBox.midX)))
                // Bias slightly toward upper-third of face box so foreheads/heads stay unclipped
                let visionTargetY = unionBox.minY + unionBox.height * 0.62
                let fy = max(0.06, min(0.94, 1.0 - Double(visionTargetY)))
                return (fx, fy)
            }
        }
        
        let saliencyRequest = VNGenerateAttentionBasedSaliencyImageRequest()
        try? handler.perform([saliencyRequest])
        if let obs = saliencyRequest.results?.first,
           let salient = obs.salientObjects?.first
        {
            let box = salient.boundingBox
            let fx = max(0.06, min(0.94, Double(box.midX)))
            let fy = max(0.06, min(0.94, 1.0 - Double(box.midY)))
            return (fx, fy)
        }
        return nil
    }
    
    
    private nonisolated static func normalizedCGImage(fromURL url: URL, maxDimension: CGFloat) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return Self.normalizedCGImage(fromSource: source, maxDimension: maxDimension)
    }
    
    
    private nonisolated static func normalizedCGImage(from data: Data, maxDimension: CGFloat) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return Self.normalizedCGImage(fromSource: source, maxDimension: maxDimension)
    }
    
    
    private nonisolated static func normalizedCGImage(fromSource source: CGImageSource, maxDimension: CGFloat) -> CGImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxDimension,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        if let thumb = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) {
            return thumb
        }
        return CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
    }
    
    
    private static func processedCoverJPEGData(from image: NSImage, maxDimension: CGFloat = 1920) -> Data? {
        guard let cgImage = Self.underlyingCGImage(from: image) else {
            return nil
        }
        let srcW = CGFloat(cgImage.width)
        let srcH = CGFloat(cgImage.height)
        guard srcW > 0, srcH > 0 else { return nil }
        
        let scale = min(1.0, maxDimension / max(srcW, srcH))
        let dstW = max(1, Int((srcW * scale).rounded()))
        let dstH = max(1, Int((srcH * scale).rounded()))
        
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: dstW,
            pixelsHigh: dstH,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return nil }
        
        NSGraphicsContext.saveGraphicsState()
        if let ctx = NSGraphicsContext(bitmapImageRep: rep) {
            NSGraphicsContext.current = ctx
            ctx.imageInterpolation = .high
            NSImage(cgImage: cgImage, size: NSSize(width: dstW, height: dstH)).draw(
                in: NSRect(x: 0, y: 0, width: dstW, height: dstH),
                from: .zero,
                operation: .copy,
                fraction: 1.0
            )
        }
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .jpeg, properties: [.compressionFactor: 0.88])
    }
}


/// Sampled color & perceptual luminance of one region of the Dashboard hero backdrop.
nonisolated struct HeroRegionTone: Equatable, Sendable {
    
    let red: Double
    let green: Double
    let blue: Double
    /// WCAG 2.1 relative luminance (`0.0` pure black ... `1.0` pure white).
    let luminance: Double
    /// HSV-like chroma saturation (`0.0` neutral ... `1.0` vivid).
    let saturation: Double
    
    /// `true` when dark ink should sit atop airy luminous frosted glass;
    /// `false` when crisp luminous off-white ink should sit atop chromatic translucent frosted glass.
    var isLightBackground: Bool {
        self.luminance > 0.54
    }
    
    init(red: Double, green: Double, blue: Double) {
        let r = max(0, min(1, red))
        let g = max(0, min(1, green))
        let b = max(0, min(1, blue))
        self.red = r
        self.green = g
        self.blue = b
        self.luminance = Self.relativeLuminance(r: r, g: g, b: b)
        let hi = max(r, max(g, b))
        let lo = min(r, min(g, b))
        self.saturation = hi > 0.001 ? (hi - lo) / hi : 0
    }
    
    static func relativeLuminance(r: Double, g: Double, b: Double) -> Double {
        func linearize(_ c: Double) -> Double {
            c <= 0.04045 ? (c / 12.92) : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linearize(r) + 0.7152 * linearize(g) + 0.0722 * linearize(b)
    }
    
    static func interpolate(_ lhs: HeroRegionTone, _ rhs: HeroRegionTone, t: Double) -> HeroRegionTone {
        let u = max(0, min(1, t))
        return HeroRegionTone(
            red: lhs.red + (rhs.red - lhs.red) * u,
            green: lhs.green + (rhs.green - lhs.green) * u,
            blue: lhs.blue + (rhs.blue - lhs.blue) * u
        )
    }
}


/// Real-time regional backdrop color & luminance snapshot driving adaptive Back button, top controls, and floating danmaku.
nonisolated struct HeroBackdropToneSnapshot: Equatable, Sendable {
    
    let hasPhoto: Bool
    /// Sampled directly behind the top-left Back button.
    let topLeft: HeroRegionTone
    /// Sampled directly behind the top-right Danmaku toggle & Cover picker controls.
    let topRight: HeroRegionTone
    /// Horizontal samples across the panoramic mid-stage danmaku flight corridor (`x: 0...1`).
    let danmakuColumns: [HeroRegionTone]
    /// Sampled near the lower photo edge feeding the bottom dock harmonization.
    let bottomStrip: HeroRegionTone
    
    /// Returns a smoothly interpolated regional background tone at horizontal fraction `x` (`0...1`).
    func danmakuTone(atNormalizedX x: Double) -> HeroRegionTone {
        guard !self.danmakuColumns.isEmpty else { return self.topRight }
        if self.danmakuColumns.count == 1 { return self.danmakuColumns[0] }
        let clamped = max(0, min(1, x))
        let scaled = clamped * Double(self.danmakuColumns.count - 1)
        let idx0 = Int(floor(scaled))
        let idx1 = min(self.danmakuColumns.count - 1, idx0 + 1)
        let frac = scaled - Double(idx0)
        return HeroRegionTone.interpolate(self.danmakuColumns[idx0], self.danmakuColumns[idx1], t: frac)
    }
}


/// Chromatic, material-backed adaptive glass styling derived directly from a sampled `HeroRegionTone`.
///
/// Strictly avoids opaque black slabs and muddy dark shadows: blends the real background hue with
/// frosted translucent glass and contrast-verified foreground ink.
@MainActor
struct HeroAdaptiveGlassTokens {
    
    let fillTint: Color
    let ink: Color
    let secondaryInk: Color
    let border: Color
    let topSpecular: Color
    let inactiveTrack: Color
    let accentDot: Color
    let usesLightInk: Bool
    
    static func resolve(
        for tone: HeroRegionTone,
        hasPhoto: Bool,
        hovered: Bool = false,
        palette: DashPalette
    ) -> HeroAdaptiveGlassTokens {
        let isLightBg = tone.isLightBackground
        let midToneBoost = max(0, 1.0 - abs(tone.luminance - 0.50) * 4.0) // Extra frost near luminance ~0.50
        
        if isLightBg {
            // Bright / pastel / sunlit backdrop -> airy frosted light glass tinted softly with photo hue + crisp deep ink
            let tintR = min(1.0, 0.88 + tone.red * 0.12)
            let tintG = min(1.0, 0.88 + tone.green * 0.12)
            let tintB = min(1.0, 0.88 + tone.blue * 0.12)
            let baseOpacity = hasPhoto ? (0.56 + midToneBoost * 0.14) : 0.72
            let opacity = hovered ? min(0.88, baseOpacity + 0.14) : baseOpacity
            
            // Deep hue-harmonized ink (never washed out)
            let inkR = 0.08 + tone.red * 0.07
            let inkG = 0.09 + tone.green * 0.07
            let inkB = 0.11 + tone.blue * 0.08
            
            let borderOpacity = hovered ? 0.30 : 0.18
            return HeroAdaptiveGlassTokens(
                fillTint: Color(red: tintR, green: tintG, blue: tintB).opacity(opacity),
                ink: Color(red: inkR, green: inkG, blue: inkB).opacity(0.94),
                secondaryInk: Color(red: inkR, green: inkG, blue: inkB).opacity(0.68),
                border: Color(red: inkR, green: inkG, blue: inkB).opacity(borderOpacity),
                topSpecular: Color.white.opacity(hovered ? 0.85 : 0.68),
                inactiveTrack: Color(red: inkR, green: inkG, blue: inkB).opacity(0.20),
                accentDot: palette.accentFill,
                usesLightInk: false
            )
        } else {
            // Deep / twilight / rich colorful backdrop -> chromatic translucent frosted glass (NOT pure black) + crisp luminous ink
            let lift = 0.14 + tone.saturation * 0.10
            let tintR = min(0.52, tone.red * 0.56 + lift)
            let tintG = min(0.52, tone.green * 0.56 + lift)
            let tintB = min(0.56, tone.blue * 0.56 + lift + 0.02)
            let baseOpacity = hasPhoto ? (0.36 + midToneBoost * 0.14) : 0.44
            let opacity = hovered ? min(0.64, baseOpacity + 0.12) : baseOpacity
            
            let inkR = 0.94 + tone.red * 0.06
            let inkG = 0.95 + tone.green * 0.05
            let inkB = 0.97 + tone.blue * 0.03
            
            let dotR = min(1.0, 0.52 + tone.red * 0.35 + 0.12)
            let dotG = min(1.0, 0.68 + tone.green * 0.25 + 0.06)
            let dotB = min(1.0, 0.78 + tone.blue * 0.20)
            
            return HeroAdaptiveGlassTokens(
                fillTint: Color(red: tintR, green: tintG, blue: tintB).opacity(opacity),
                ink: Color(red: inkR, green: inkG, blue: inkB).opacity(0.96),
                secondaryInk: Color(red: inkR, green: inkG, blue: inkB).opacity(0.76),
                border: Color.white.opacity(hovered ? 0.40 : 0.24),
                topSpecular: Color.white.opacity(hovered ? 0.36 : 0.22),
                inactiveTrack: Color.white.opacity(0.28),
                accentDot: Color(red: dotR, green: dotG, blue: dotB),
                usesLightInk: true
            )
        }
    }
    
    static func danmakuAccentDot(
        for itemTone: PersonalityTagTone,
        background: HeroRegionTone,
        palette: DashPalette
    ) -> Color {
        if background.isLightBackground {
            switch itemTone {
                case .calm: return Color(red: 0.14, green: 0.48, blue: 0.78)
                case .sharp: return palette.accentFill
                case .warm: return Color(red: 0.84, green: 0.44, blue: 0.14)
                case .playful: return Color(red: 0.54, green: 0.32, blue: 0.78)
            }
        } else {
            switch itemTone {
                case .calm: return Color(red: 0.52, green: 0.84, blue: 1.0)
                case .sharp: return Color(red: 0.48, green: 0.94, blue: 0.74)
                case .warm: return Color(red: 1.0, green: 0.78, blue: 0.42)
                case .playful: return Color(red: 0.86, green: 0.68, blue: 1.0)
            }
        }
    }
}


/// Fast sub-millisecond sRGB sampler matching `HeroPhotoFadeBackdrop`'s exact fill/fit & 2D focal crop geometry.
enum HeroCoverToneSampler {
    
    static let danmakuColumnCount = 6
    
    static func sample(
        image: NSImage?,
        focalX: Double = 0.50,
        focalY: Double,
        fitMode: HeroCoverFitMode = .fill,
        canvasAspect: CGFloat,
        fallbackRGB: (Double, Double, Double)
    ) -> HeroBackdropToneSnapshot {
        let fallbackTone = HeroRegionTone(red: fallbackRGB.0, green: fallbackRGB.1, blue: fallbackRGB.2)
        guard let image,
              let cgImage = DashboardHeroCoverStore.underlyingCGImage(from: image),
              cgImage.width > 0,
              cgImage.height > 0
        else {
            return HeroBackdropToneSnapshot(
                hasPhoto: false,
                topLeft: fallbackTone,
                topRight: fallbackTone,
                danmakuColumns: Array(repeating: fallbackTone, count: Self.danmakuColumnCount),
                bottomStrip: fallbackTone
            )
        }
        
        let clampedAspect = max(0.4, min(10.0, canvasAspect))
        let imgW = CGFloat(cgImage.width)
        let imgH = CGFloat(cgImage.height)
        let imgAspect = imgW / max(1, imgH)
        let clampedFocalX = max(0.0, min(1.0, focalX))
        let clampedFocalY = max(0.0, min(1.0, focalY))
        
        // Match HeroPhotoFadeBackdrop's crop geometry (`CGImage.cropping(to:)` uses top-left pixel coordinates).
        let cropRect: CGRect
        if fitMode == .fit {
            cropRect = CGRect(x: 0, y: 0, width: imgW, height: imgH)
        } else if imgAspect <= clampedAspect {
            let visibleH = min(imgH, imgW / clampedAspect)
            let overflowY = max(0, imgH - visibleH)
            cropRect = CGRect(
                x: 0,
                y: overflowY * CGFloat(clampedFocalY),
                width: imgW,
                height: max(1, visibleH)
            ).integral
        } else {
            let visibleW = min(imgW, imgH * clampedAspect)
            let overflowX = max(0, imgW - visibleW)
            cropRect = CGRect(
                x: overflowX * CGFloat(clampedFocalX),
                y: 0,
                width: max(1, visibleW),
                height: imgH
            ).integral
        }
        
        let cropped = cgImage.cropping(to: cropRect) ?? cgImage
        let sampleW = 48
        let sampleH = 24
        var bytes = [UInt8](repeating: 0, count: sampleW * sampleH * 4)
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        
        guard let ctx = CGContext(
            data: &bytes,
            width: sampleW,
            height: sampleH,
            bitsPerComponent: 8,
            bytesPerRow: sampleW * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            return HeroBackdropToneSnapshot(
                hasPhoto: true,
                topLeft: fallbackTone,
                topRight: fallbackTone,
                danmakuColumns: Array(repeating: fallbackTone, count: Self.danmakuColumnCount),
                bottomStrip: fallbackTone
            )
        }
        ctx.interpolationQuality = .low
        ctx.draw(cropped, in: CGRect(x: 0, y: 0, width: sampleW, height: sampleH))
        
        func averageTone(xMin: Double, xMax: Double, yMin: Double, yMax: Double) -> HeroRegionTone {
            let ix0 = max(0, min(sampleW - 1, Int(floor(xMin * Double(sampleW)))))
            let ix1 = max(ix0 + 1, min(sampleW, Int(ceil(xMax * Double(sampleW)))))
            let iy0 = max(0, min(sampleH - 1, Int(floor(yMin * Double(sampleH)))))
            let iy1 = max(iy0 + 1, min(sampleH, Int(ceil(yMax * Double(sampleH)))))
            var sumR = 0.0
            var sumG = 0.0
            var sumB = 0.0
            var count = 0.0
            for py in iy0..<iy1 {
                for px in ix0..<ix1 {
                    let offset = (py * sampleW + px) * 4
                    let a = Double(bytes[offset + 3]) / 255.0
                    let r = a > 0.001 ? min(1.0, (Double(bytes[offset]) / 255.0) / a) : fallbackRGB.0
                    let g = a > 0.001 ? min(1.0, (Double(bytes[offset + 1]) / 255.0) / a) : fallbackRGB.1
                    let b = a > 0.001 ? min(1.0, (Double(bytes[offset + 2]) / 255.0) / a) : fallbackRGB.2
                    sumR += r
                    sumG += g
                    sumB += b
                    count += 1
                }
            }
            guard count > 0 else { return fallbackTone }
            return HeroRegionTone(red: sumR / count, green: sumG / count, blue: sumB / count)
        }
        
        let topLeft = averageTone(xMin: 0.00, xMax: 0.24, yMin: 0.00, yMax: 0.24)
        let topRight = averageTone(xMin: 0.62, xMax: 1.00, yMin: 0.00, yMax: 0.24)
        let bottomStrip = averageTone(xMin: 0.04, xMax: 0.96, yMin: 0.56, yMax: 0.84)
        
        var columns: [HeroRegionTone] = []
        columns.reserveCapacity(Self.danmakuColumnCount)
        let step = 1.0 / Double(Self.danmakuColumnCount)
        for idx in 0..<Self.danmakuColumnCount {
            let x0 = Double(idx) * step
            let x1 = min(1.0, x0 + step)
            columns.append(averageTone(xMin: x0, xMax: x1, yMin: 0.22, yMax: 0.64))
        }
        
        return HeroBackdropToneSnapshot(
            hasPhoto: true,
            topLeft: topLeft,
            topRight: topRight,
            danmakuColumns: columns,
            bottomStrip: bottomStrip
        )
    }
}


private struct DashboardAchievementHeroBar<EmbeddedRow1: View>: View {
    
    let profile: UserProfile
    let avatarImage: NSImage?
    let snapshot: DashboardSnapshot
    let heroHeight: CGFloat
    let innerGap: CGFloat
    let bottomPad: CGFloat
    let compact: Bool
    let palette: DashPalette
    let onBack: (() -> Void)?
    let embeddedRow1: () -> EmbeddedRow1
    
    @State private var coverStore = DashboardHeroCoverStore.shared
    @State private var serialCode: String
    @State private var hasProLicense: Bool
    @State private var isDanmakuEnabled: Bool
    @State private var activityGate = AppActivityRenderGate.shared
    @State private var isWindowVisible = true
    @State private var isBackHovered = false
    @State private var isToggleHovered = false
    @State private var isCoverButtonHovered = false
    @State private var isDropTargeted = false
    @State private var isAdjustingCover = false
    @State private var dragStartFocal: (x: Double, y: Double)? = nil
    @State private var hasAppeared = false
    @State private var startDate = Date()
    @State private var toneSnapshot: HeroBackdropToneSnapshot
    @State private var lastSampleAspectBucket: Int = 0
    @State private var isShowingHeroBgLibraryPicker = false
    
    
    init(
        profile: UserProfile,
        avatarImage: NSImage?,
        snapshot: DashboardSnapshot,
        heroHeight: CGFloat,
        innerGap: CGFloat,
        bottomPad: CGFloat,
        compact: Bool,
        palette: DashPalette,
        onBack: (() -> Void)?,
        @ViewBuilder embeddedRow1: @escaping () -> EmbeddedRow1
    ) {
        self.profile = profile
        self.avatarImage = avatarImage
        self.snapshot = snapshot
        self.heroHeight = heroHeight
        self.innerGap = innerGap
        self.bottomPad = bottomPad
        self.compact = compact
        self.palette = palette
        self.onBack = onBack
        self.embeddedRow1 = embeddedRow1
        
        let db = CotLocalDatabase.shared
        var serial = db.string(forKey: CotLocalDatabase.ConfigKey.cotPassSerialCode)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if serial.isEmpty {
            serial = CotPassLicense.generateSerialCode()
            db.set(serial, forKey: CotLocalDatabase.ConfigKey.cotPassSerialCode)
        }
        let key = db.string(forKey: CotLocalDatabase.ConfigKey.cotPassLicenseKey)
        let tier = CotPassLicense.validate(key) ?? .explorer
        let rawDanmaku = db.string(forKey: CotLocalDatabase.ConfigKey.dashboardDanmakuEnabled, default: "false")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        
        let fallbackRGB = Self.fallbackSurfaceRGB(for: palette)
        let initialAspect: CGFloat = compact ? 2.6 : 2.95
        let initialTones = DashboardHeroCoverStore.shared.initialTones(canvasAspect: initialAspect, fallbackRGB: fallbackRGB)
        
        _serialCode = State(initialValue: serial)
        _hasProLicense = State(initialValue: tier != .explorer)
        _isDanmakuEnabled = State(initialValue: rawDanmaku == "true" || rawDanmaku == "1")
        _toneSnapshot = State(initialValue: initialTones)
    }
    
    
    private static func fallbackSurfaceRGB(for palette: DashPalette) -> (Double, Double, Double) {
        if let srgb = NSColor(palette.card).usingColorSpace(.sRGB) {
            return (Double(srgb.redComponent), Double(srgb.greenComponent), Double(srgb.blueComponent))
        }
        return palette.tokens.isDark ? (0.14, 0.15, 0.17) : (0.96, 0.96, 0.97)
    }
    
    
    private var danmakuItems: [DashboardHeroDanmakuScheduler.Item] {
        var tags: [UserPersonalityTag] = []
        let todayTotal = self.snapshot.today.typedChars + self.snapshot.today.aiCompletedChars
        let typed14 = self.snapshot.days14.reduce(0) { $0 + $1.typed }
        let ai14 = self.snapshot.days14.reduce(0) { $0 + $1.ai }
        let sum14 = typed14 + ai14
        if sum14 > 0 {
            let handRatio = Double(typed14) / Double(sum14)
            tags.append(UserPersonalityTag(
                id: "style",
                label: handRatio >= 0.65 ? "手写心流派" : "AI 协创派",
                explanation: "",
                tone: .calm
            ))
        }
        tags.append(UserPersonalityTag(
            id: "pass-tier",
            label: self.hasProLicense ? "PRO 通行证" : "创作通行证",
            explanation: "",
            tone: .sharp
        ))
        let moodLabel = self.snapshot.mood.dominantLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        if !moodLabel.isEmpty {
            tags.append(UserPersonalityTag(id: "mood", label: moodLabel, explanation: "", tone: .playful))
        }
        if todayTotal > 0 {
            tags.append(UserPersonalityTag(id: "today", label: "今日 \(todayTotal.formatted()) 字", explanation: "", tone: .calm))
        }
        if self.snapshot.currentStreak > 0 {
            tags.append(UserPersonalityTag(id: "streak", label: "连更 \(self.snapshot.currentStreak) 天", explanation: "", tone: .sharp))
        }
        let avg14 = Int(self.snapshot.trendCurve14.averageValue.rounded())
        if avg14 > 0 {
            tags.append(UserPersonalityTag(id: "avg14", label: "日均 \(avg14.formatted()) 字", explanation: "", tone: .warm))
        }
        if sum14 >= 8000 {
            tags.append(UserPersonalityTag(id: "prolific", label: "高产创作者", explanation: "", tone: .warm))
        }
        if self.snapshot.yearlyHeatmap.activeDays >= 60 {
            tags.append(UserPersonalityTag(id: "steady", label: "长期主义者", explanation: "", tone: .playful))
        }
        
        let deduped = UserPersonalityAnalyzer.deduplicatedTags(tags, maxCount: 8)
        return deduped.map {
            DashboardHeroDanmakuScheduler.Item(id: $0.id, text: $0.label, tone: $0.tone)
        }
    }
    
    
    private func refreshAdaptiveTones(canvasSize: CGSize) {
        let aspect = canvasSize.height > 1 ? (canvasSize.width / canvasSize.height) : (self.compact ? 3.2 : 4.2)
        let sampled = HeroCoverToneSampler.sample(
            image: self.coverStore.coverImage,
            focalX: self.coverStore.focalX,
            focalY: self.coverStore.focalY,
            fitMode: self.coverStore.fitMode,
            canvasAspect: aspect,
            fallbackRGB: Self.fallbackSurfaceRGB(for: self.palette)
        )
        if sampled != self.toneSnapshot {
            withAnimation(.easeInOut(duration: 0.22)) {
                self.toneSnapshot = sampled
            }
        }
    }
    
    
    var body: some View {
        let streakDays = max(1, self.snapshot.currentStreak)
        let todayTotal = self.snapshot.today.typedChars + self.snapshot.today.aiCompletedChars
        let avg14 = Int(self.snapshot.trendCurve14.averageValue.rounded())
        let hasPhoto = (self.coverStore.coverImage != nil)
        let coverImageID = self.coverStore.coverImage.map(ObjectIdentifier.init)
        let moodLabel = self.snapshot.mood.dominantLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayMood = moodLabel.isEmpty ? AppLanguage.text("冷静", en: "Calm") : moodLabel
        let padH: CGFloat = DashboardCornerMetrics.unifiedInset(compact: self.compact)
        let outerRadius: CGFloat = DashboardCornerMetrics.unifiedOuterRadius(compact: self.compact)
        let topLeftTone = self.toneSnapshot.topLeft
        let topRightTone = self.toneSnapshot.topRight
        
        GeometryReader { heroGeo in
            let isShortHero = self.compact || self.heroHeight < 136
            let padTop: CGFloat = isShortHero ? 9 : 11
            let rowHeight: CGFloat = isShortHero ? 44 : 50
            let aspectBucket = Int(((heroGeo.size.width / max(1, heroGeo.size.height)) * 20).rounded())
            
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    // Top floating adaptive frosted glass controls (real-time synced to topLeft & topRight pixels)
                    HStack(alignment: .center, spacing: 8) {
                        if let onBack = self.onBack {
                            self.heroBackButton(tone: topLeftTone, hasPhoto: hasPhoto, action: onBack)
                        } else {
                            Color.clear
                                .frame(width: 1, height: 28)
                        }
                        
                        Spacer(minLength: 12)
                        
                        HStack(spacing: 8) {
                            if self.compact {
                                let badgeGlass = HeroAdaptiveGlassTokens.resolve(
                                    for: topRightTone,
                                    hasPhoto: hasPhoto,
                                    hovered: false,
                                    palette: self.palette
                                )
                                Text(displayMood)
                                    .font(.system(size: 11.5, weight: .semibold))
                                    .foregroundStyle(badgeGlass.ink)
                                    .padding(.horizontal, 10)
                                    .frame(height: 28)
                                    .background {
                                        self.adaptiveGlassCapsule(glass: badgeGlass)
                                    }
                            }
                            
                            self.danmakuToggleButton(tone: topRightTone, hasPhoto: hasPhoto)
                            self.coverImageControlPill(tone: topRightTone, hasPhoto: hasPhoto)
                        }
                    }
                    .padding(.horizontal, padH + 4)
                    .padding(.top, padTop)
                    .frame(height: 28 + padTop, alignment: .top)
                    
                    // Open panoramic showcase zone — unobstructed cover view + real-time background-adaptive floating danmaku
                    ZStack {
                        if self.isDanmakuEnabled && !self.isAdjustingCover {
                            GeometryReader { stageGeo in
                                let danmakuPaused = AnimationConstants.isReducedMotionEnabled
                                    || !self.activityGate.isAppActive
                                    || !self.isWindowVisible
                                TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: danmakuPaused)) { timeline in
                                    let elapsed = max(0, timeline.date.timeIntervalSince(self.startDate))
                                    self.adaptiveDanmakuStage(
                                        size: stageGeo.size,
                                        items: self.danmakuItems,
                                        elapsed: elapsed,
                                        hasPhoto: hasPhoto
                                    )
                                }
                            }
                            .clipped()
                            .transition(.opacity)
                        }
                        
                        if self.isAdjustingCover && hasPhoto {
                            let hudGlass = HeroAdaptiveGlassTokens.resolve(
                                for: topRightTone,
                                hasPhoto: true,
                                hovered: true,
                                palette: self.palette
                            )
                            HStack(spacing: 10) {
                                Image(systemName: "arrow.up.and.down.and.arrow.left.and.right")
                                    .font(.system(size: 11, weight: .semibold))
                                Text(AppLanguage.text("拖动画面调整构图", en: "Drag to adjust framing"))
                                    .font(.system(size: 11.5, weight: .medium))
                                
                                Button {
                                    withAnimation(DashMotion.resolve(DashMotion.quick)) {
                                        self.coverStore.applySmartAutoFocal()
                                    }
                                } label: {
                                    Text(AppLanguage.text("智能对焦", en: "Auto Focus"))
                                        .font(.system(size: 11, weight: .semibold))
                                        .padding(.horizontal, 8)
                                        .frame(height: 22)
                                        .background(self.palette.accentFill.opacity(0.22), in: Capsule())
                                }
                                .buttonStyle(.plain)
                                .pointerStyle(.link)
                                
                                Button {
                                    withAnimation(DashMotion.resolve(DashMotion.quick)) {
                                        self.isAdjustingCover = false
                                    }
                                } label: {
                                    Text(AppLanguage.text("完成", en: "Done"))
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(self.palette.tokens.onAccentInk)
                                        .padding(.horizontal, 10)
                                        .frame(height: 22)
                                        .background(self.palette.accentFill, in: Capsule())
                                }
                                .buttonStyle(.plain)
                                .pointerStyle(.link)
                            }
                            .foregroundStyle(hudGlass.ink)
                            .padding(.horizontal, 12)
                            .frame(height: 30)
                            .background {
                                self.adaptiveGlassCapsule(glass: hudGlass)
                            }
                            .transition(.opacity)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.vertical, 2)
                    
                    // Borderless identity + telemetry strip seamlessly fused with the vivid scenic backdrop
                    HStack(alignment: .center, spacing: 0) {
                        self.identityLockup(streakDays: streakDays, overPhoto: hasPhoto)
                            .frame(width: self.compact ? 182 : 216, alignment: .leading)
                        
                        Rectangle()
                            .fill(hasPhoto ? Color.white.opacity(0.28) : self.palette.hairlineStrong.opacity(0.65))
                            .frame(width: 0.75, height: self.compact ? 22 : 26)
                            .padding(.horizontal, self.compact ? 12 : 16)
                        
                        self.telemetryMatrixZone(
                            todayTotal: todayTotal,
                            streakDays: streakDays,
                            avg14: avg14,
                            displayMood: displayMood,
                            overPhoto: hasPhoto
                        )
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.horizontal, padH + 6)
                    .frame(height: rowHeight)
                }
                .frame(height: self.heroHeight, alignment: .topLeading)
                
                self.embeddedRow1()
                    .padding(.horizontal, padH)
                    .padding(.top, self.innerGap)
                    .padding(.bottom, self.bottomPad)
                    .allowsHitTesting(!self.isAdjustingCover)
            }
            .frame(width: heroGeo.size.width, height: heroGeo.size.height, alignment: .topLeading)
            .background {
                HeroPhotoFadeBackdrop(
                    coverImage: self.coverStore.coverImage,
                    focalX: self.coverStore.focalX,
                    focalY: self.coverStore.focalY,
                    fitMode: self.coverStore.fitMode,
                    bottomTone: self.toneSnapshot.bottomStrip,
                    palette: self.palette
                )
            }
            .clipShape(RoundedRectangle(cornerRadius: outerRadius, style: .continuous))
            .overlay {
                if self.isDropTargeted || self.isAdjustingCover {
                    RoundedRectangle(cornerRadius: outerRadius, style: .continuous)
                        .strokeBorder(
                            self.isDropTargeted ? self.palette.accentFill : self.palette.accentFill.opacity(0.55),
                            lineWidth: 1.5
                        )
                } else {
                    RoundedRectangle(cornerRadius: outerRadius, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(self.palette.tokens.isDark ? 0.10 : (hasPhoto ? 0.42 : 0.65)),
                                    Color.clear,
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 0.5
                        )
                }
            }
            .shadow(
                color: Color.black.opacity(self.palette.tokens.isDark ? 0.22 : 0.045),
                radius: 12,
                x: 0,
                y: 4
            )
            .simultaneousGesture(
                DragGesture(minimumDistance: 2)
                    .onChanged { value in
                        guard self.isAdjustingCover,
                              hasPhoto,
                              self.coverStore.fitMode == .fill,
                              let cover = self.coverStore.coverImage
                        else { return }
                        if self.dragStartFocal == nil {
                            self.dragStartFocal = (self.coverStore.focalX, self.coverStore.focalY)
                        }
                        guard let start = self.dragStartFocal else { return }
                        let targetW = max(1, heroGeo.size.width)
                        let targetH = max(1, heroGeo.size.height)
                        let imgAspect: CGFloat = {
                            if let cg = DashboardHeroCoverStore.underlyingCGImage(from: cover), cg.height > 0 {
                                return CGFloat(cg.width) / CGFloat(cg.height)
                            }
                            return cover.size.height > 0 ? (cover.size.width / cover.size.height) : 1.77
                        }()
                        let targetAspect = targetW / targetH
                        if imgAspect >= targetAspect {
                            let renderedW = targetH * imgAspect
                            let overflowX = max(1, renderedW - targetW)
                            self.coverStore.focalX = max(0, min(1, start.x - Double(value.translation.width / overflowX)))
                        } else {
                            let renderedH = targetW / max(0.2, imgAspect)
                            let overflowY = max(1, renderedH - targetH)
                            self.coverStore.focalY = max(0, min(1, start.y - Double(value.translation.height / overflowY)))
                        }
                    }
                    .onEnded { _ in
                        self.dragStartFocal = nil
                    }
            )
            .onDrop(of: [.fileURL], isTargeted: self.$isDropTargeted) { providers in
                self.handleImageDrop(providers: providers)
            }
            .observeWindowRenderActivity(self.$isWindowVisible)
            .onAppear {
                self.lastSampleAspectBucket = aspectBucket
                self.refreshAdaptiveTones(canvasSize: heroGeo.size)
                guard !self.hasAppeared else { return }
                withAnimation(DashMotion.resolve(DashMotion.chartReveal.delay(0.08))) {
                    self.hasAppeared = true
                }
            }
            .onChange(of: coverImageID) { _, _ in
                self.isAdjustingCover = false
                self.refreshAdaptiveTones(canvasSize: heroGeo.size)
            }
            .onChange(of: self.coverStore.focalX) { _, _ in
                self.refreshAdaptiveTones(canvasSize: heroGeo.size)
            }
            .onChange(of: self.coverStore.focalY) { _, _ in
                self.refreshAdaptiveTones(canvasSize: heroGeo.size)
            }
            .onChange(of: self.coverStore.fitMode) { _, _ in
                self.refreshAdaptiveTones(canvasSize: heroGeo.size)
            }
            .onChange(of: self.palette.tokens.isDark) { _, _ in
                self.refreshAdaptiveTones(canvasSize: heroGeo.size)
            }
            .onChange(of: aspectBucket) { _, newBucket in
                guard newBucket != self.lastSampleAspectBucket else { return }
                self.lastSampleAspectBucket = newBucket
                self.refreshAdaptiveTones(canvasSize: heroGeo.size)
            }
        }
    }
    
    
    private func handleImageDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }) else {
            return false
        }
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            let url: URL? = {
                if let data = item as? Data {
                    return URL(dataRepresentation: data, relativeTo: nil)
                }
                if let direct = item as? URL {
                    return direct
                }
                return nil
            }()
            guard let url else { return }
            Task { @MainActor in
                _ = self.coverStore.setCoverImage(from: url)
            }
        }
        return true
    }
    
    
    private func adaptiveGlassCapsule(glass: HeroAdaptiveGlassTokens) -> some View {
        Capsule()
            .fill(.ultraThinMaterial)
            .overlay(
                Capsule()
                    .fill(glass.fillTint)
            )
            .overlay(
                Capsule()
                    .strokeBorder(
                        LinearGradient(
                            colors: [glass.topSpecular, glass.border],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 0.85
                    )
            )
    }
    
    
    private func heroBackButton(tone: HeroRegionTone, hasPhoto: Bool, action: @escaping () -> Void) -> some View {
        let glass = HeroAdaptiveGlassTokens.resolve(
            for: tone,
            hasPhoto: hasPhoto,
            hovered: self.isBackHovered,
            palette: self.palette
        )
        return Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 10, weight: .semibold))
                Text(AppLanguage.text("返回", en: "Back"))
                    .font(.system(size: 11.5, weight: .medium))
            }
            .foregroundStyle(glass.ink)
            .padding(.horizontal, 11)
            .frame(height: 28)
            .background {
                self.adaptiveGlassCapsule(glass: glass)
            }
            .contentShape(Capsule())
        }
        .buttonStyle(DashboardCardButtonStyle(pressedScale: 0.99))
        .pointerStyle(.link)
        .onHover { hovering in
            if hovering != self.isBackHovered {
                self.isBackHovered = hovering
            }
        }
    }
    
    
    @ViewBuilder
    private func coverImageControlPill(tone: HeroRegionTone, hasPhoto: Bool) -> some View {
        let glass = HeroAdaptiveGlassTokens.resolve(
            for: tone,
            hasPhoto: hasPhoto,
            hovered: self.isCoverButtonHovered,
            palette: self.palette
        )
        let pillLabel = HStack(spacing: 5) {
            Image(systemName: hasPhoto ? "photo" : "photo.badge.plus")
                .font(.system(size: 10.5, weight: .semibold))
            Text(hasPhoto
                 ? AppLanguage.text("背景图", en: "Cover")
                 : AppLanguage.text("上传背景", en: "Add Cover"))
                .font(.system(size: 11, weight: .medium))
        }
        .foregroundStyle(glass.ink)
        .padding(.horizontal, 11)
        .frame(height: 28)
        .background {
            self.adaptiveGlassCapsule(glass: glass)
        }
        .contentShape(Capsule())
        
        Group {
            if hasPhoto {
                Menu {
                    Button {
                        self.isShowingHeroBgLibraryPicker = true
                    } label: {
                        Label(AppLanguage.text("从背景库选择…", en: "Choose from Library…"), systemImage: "photo.stack")
                    }
                    
                    Button {
                        self.coverStore.presentImagePicker()
                    } label: {
                        Label(AppLanguage.text("更换本地图片…", en: "Choose Local Image…"), systemImage: "photo.badge.plus")
                    }
                    
                    Divider()
                    
                    Button {
                        withAnimation(DashMotion.resolve(DashMotion.standard)) {
                            self.coverStore.fitMode = .fill
                        }
                    } label: {
                        HStack {
                            Text(AppLanguage.text("铺满裁切 (Fill)", en: "Fill Frame"))
                            if self.coverStore.fitMode == .fill { Image(systemName: "checkmark") }
                        }
                    }
                    
                    Button {
                        withAnimation(DashMotion.resolve(DashMotion.standard)) {
                            self.isAdjustingCover = false
                            self.coverStore.fitMode = .fit
                        }
                    } label: {
                        HStack {
                            Text(AppLanguage.text("完整适配 (不裁切)", en: "Fit Whole Image"))
                            if self.coverStore.fitMode == .fit { Image(systemName: "checkmark") }
                        }
                    }
                    
                    if self.coverStore.fitMode == .fill {
                        Divider()
                        
                        Button {
                            withAnimation(DashMotion.resolve(DashMotion.quick)) {
                                self.isAdjustingCover.toggle()
                            }
                        } label: {
                            Label(
                                self.isAdjustingCover
                                    ? AppLanguage.text("退出拖拽构图", en: "Finish Dragging")
                                    : AppLanguage.text("拖拽调整构图", en: "Drag to Reposition"),
                                systemImage: "arrow.up.and.down.and.arrow.left.and.right"
                            )
                        }
                        
                        Button {
                            withAnimation(DashMotion.resolve(DashMotion.quick)) {
                                self.coverStore.applySmartAutoFocal()
                            }
                        } label: {
                            Label(AppLanguage.text("智能识别对焦", en: "Smart Auto Focus"), systemImage: "viewfinder")
                        }
                        
                        Divider()
                        
                        Button {
                            withAnimation(DashMotion.resolve(DashMotion.quick)) {
                                self.coverStore.focalY = 0.08
                            }
                        } label: {
                            HStack {
                                Text(AppLanguage.text("画面顶部", en: "Focus Top Edge"))
                                if self.coverStore.focalY < 0.16 { Image(systemName: "checkmark") }
                            }
                        }
                        
                        Button {
                            withAnimation(DashMotion.resolve(DashMotion.quick)) {
                                self.coverStore.focalY = 0.25
                            }
                        } label: {
                            HStack {
                                Text(AppLanguage.text("画面偏上", en: "Focus Upper"))
                                if self.coverStore.focalY >= 0.16 && self.coverStore.focalY < 0.38 { Image(systemName: "checkmark") }
                            }
                        }
                        
                        Button {
                            withAnimation(DashMotion.resolve(DashMotion.quick)) {
                                self.coverStore.focalY = 0.50
                                self.coverStore.focalX = 0.50
                            }
                        } label: {
                            HStack {
                                Text(AppLanguage.text("画面居中", en: "Focus Center"))
                                if self.coverStore.focalY >= 0.38 && self.coverStore.focalY <= 0.64 { Image(systemName: "checkmark") }
                            }
                        }
                        
                        Button {
                            withAnimation(DashMotion.resolve(DashMotion.quick)) {
                                self.coverStore.focalY = 0.78
                            }
                        } label: {
                            HStack {
                                Text(AppLanguage.text("画面偏下", en: "Focus Lower"))
                                if self.coverStore.focalY > 0.64 && self.coverStore.focalY < 0.90 { Image(systemName: "checkmark") }
                            }
                        }
                        
                        Button {
                            withAnimation(DashMotion.resolve(DashMotion.quick)) {
                                self.coverStore.focalY = 0.96
                            }
                        } label: {
                            HStack {
                                Text(AppLanguage.text("画面底部", en: "Focus Bottom Edge"))
                                if self.coverStore.focalY >= 0.90 { Image(systemName: "checkmark") }
                            }
                        }
                    }
                    
                    Divider()
                    
                    Button(role: .destructive) {
                        withAnimation(DashMotion.resolve(DashMotion.standard)) {
                            self.isAdjustingCover = false
                            self.coverStore.clearCoverImage()
                        }
                    } label: {
                        Label(AppLanguage.text("移除背景图片", en: "Remove Cover"), systemImage: "trash")
                    }
                } label: {
                    pillLabel
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .pointerStyle(.link)
                .onHover { hovering in
                    guard hovering != self.isCoverButtonHovered else { return }
                    withAnimation(DashMotion.resolve(DashMotion.quick)) {
                        self.isCoverButtonHovered = hovering
                    }
                }
            } else {
                Menu {
                    Button {
                        self.isShowingHeroBgLibraryPicker = true
                    } label: {
                        Label(AppLanguage.text("从背景库选择…", en: "Choose from Library…"), systemImage: "photo.stack")
                    }
                    
                    Button {
                        self.coverStore.presentImagePicker()
                    } label: {
                        Label(AppLanguage.text("上传本地图片…", en: "Upload Image…"), systemImage: "photo.badge.plus")
                    }
                } label: {
                    pillLabel
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .pointerStyle(.link)
                .onHover { hovering in
                    guard hovering != self.isCoverButtonHovered else { return }
                    withAnimation(DashMotion.resolve(DashMotion.quick)) {
                        self.isCoverButtonHovered = hovering
                    }
                }
            }
        }
        .popover(isPresented: self.$isShowingHeroBgLibraryPicker, arrowEdge: .bottom) {
            BackgroundLibraryPickerPopover(
                title: AppLanguage.text("选择数据看板背景", en: "Choose Dashboard Cover"),
                onSelect: { asset in
                    _ = UserMediaLibraryStore.shared.applyBackgroundToDashboardHero(assetID: asset.id, heroStore: self.coverStore)
                    self.isShowingHeroBgLibraryPicker = false
                },
                onClear: hasPhoto ? {
                    self.coverStore.clearCoverImage()
                    self.isShowingHeroBgLibraryPicker = false
                } : nil
            )
        }
    }
    
    
    private func identityLockup(streakDays: Int, overPhoto: Bool) -> some View {
        let tierBadge = self.hasProLicense ? "PRO" : "PASS"
        let subLabel = "#\(String(self.serialCode.prefix(4)))"
        let primaryInk: Color = overPhoto ? .white : self.palette.pine
        let secondaryInk: Color = overPhoto ? Color.white.opacity(0.76) : self.palette.mutedInk
        let textShadow: Color = overPhoto ? Color.black.opacity(0.28) : .clear
        
        return HStack(alignment: .center, spacing: 11) {
            self.authorPortrait(size: self.compact ? 38 : 44)
            
            VStack(alignment: .leading, spacing: 3) {
                Text(self.profile.displayName)
                    .font(.system(size: self.compact ? 16 : 18.5, weight: .bold))
                    .foregroundStyle(primaryInk)
                    .shadow(color: textShadow, radius: 2.5, y: 1)
                    .lineLimit(1)
                    .minimumScaleFactor(0.80)
                
                HStack(spacing: 6) {
                    Text(tierBadge)
                        .font(.system(size: 9.5, weight: .bold, design: .rounded))
                        .foregroundStyle(overPhoto ? .white : self.palette.accentFill)
                        .padding(.horizontal, 6)
                        .frame(height: 16)
                        .background(
                            overPhoto ? Color.white.opacity(0.18) : self.palette.tokens.positivePillBg,
                            in: Capsule()
                        )
                        .overlay {
                            if overPhoto {
                                Capsule().strokeBorder(Color.white.opacity(0.32), lineWidth: 0.6)
                            }
                        }
                    
                    Text(subLabel)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(secondaryInk)
                        .shadow(color: textShadow, radius: 1.5, y: 0.5)
                        .lineLimit(1)
                }
            }
            
            Spacer(minLength: 0)
        }
    }
    
    
    private func telemetryMatrixZone(
        todayTotal: Int,
        streakDays: Int,
        avg14: Int,
        displayMood: String,
        overPhoto: Bool
    ) -> some View {
        let rhythmBars = Array(self.snapshot.busyness.slices.suffix(6))
        let primaryInk: Color = overPhoto ? .white : self.palette.pine
        let labelInk: Color = overPhoto ? Color.white.opacity(0.76) : self.palette.mutedInk
        let accentInk: Color = overPhoto ? Color(red: 0.62, green: 0.84, blue: 1.0) : self.palette.accentFill
        let inactiveBar: Color = overPhoto ? Color.white.opacity(0.28) : self.palette.accentFill.opacity(0.22)
        let textShadow: Color = overPhoto ? Color.black.opacity(0.26) : .clear
        
        return HStack(alignment: .center, spacing: 0) {
            self.headerStatBlock(
                label: AppLanguage.text("今日码字", en: "Today"),
                value: todayTotal.formatted(),
                unit: AppLanguage.text("字", en: "ch"),
                overPhoto: overPhoto
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            
            self.headerStatBlock(
                label: AppLanguage.text("连续", en: "Streak"),
                value: "\(streakDays)",
                unit: AppLanguage.text("天", en: "d"),
                overPhoto: overPhoto
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            
            self.headerStatBlock(
                label: AppLanguage.text("年度活跃", en: "Active"),
                value: "\(self.snapshot.yearlyHeatmap.activeDays)",
                unit: AppLanguage.text("天", en: "d"),
                overPhoto: overPhoto
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            
            if !self.compact && avg14 > 0 {
                self.headerStatBlock(
                    label: AppLanguage.text("14日均", en: "14d"),
                    value: avg14.formatted(),
                    unit: AppLanguage.text("字", en: "ch"),
                    overPhoto: overPhoto
                )
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            
            if !self.compact {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 5) {
                        Text(AppLanguage.text("心境", en: "Mood"))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(labelInk)
                        Text("\(self.snapshot.mood.score)")
                            .font(.system(size: 11, weight: .semibold, design: .rounded).monospacedDigit())
                            .foregroundStyle(accentInk)
                            .contentTransition(.numericText())
                    }
                    .shadow(color: textShadow, radius: 1.5, y: 0.5)
                    .lineLimit(1)
                    
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(displayMood)
                            .font(.system(size: 19.5, weight: .bold))
                            .foregroundStyle(primaryInk)
                            .shadow(color: textShadow, radius: 2.5, y: 1)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                        
                        HStack(alignment: .bottom, spacing: 3) {
                            ForEach(Array(rhythmBars.enumerated()), id: \.element.id) { _, slice in
                                let h = max(5, CGFloat(slice.intensity) * 18)
                                Capsule(style: .continuous)
                                    .fill(slice.intensity > 0.35 ? accentInk : inactiveBar)
                                    .frame(width: 3, height: h)
                            }
                        }
                        .frame(height: 18, alignment: .bottom)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
    
    
    private func danmakuToggleButton(tone: HeroRegionTone, hasPhoto: Bool) -> some View {
        let glass = HeroAdaptiveGlassTokens.resolve(
            for: tone,
            hasPhoto: hasPhoto,
            hovered: self.isToggleHovered,
            palette: self.palette
        )
        return Button {
            let next = !self.isDanmakuEnabled
            if next {
                self.startDate = Date()
            }
            withAnimation(DashMotion.resolve(DashMotion.quick)) {
                self.isDanmakuEnabled = next
            }
            CotLocalDatabase.shared.set(
                next ? "true" : "false",
                forKey: CotLocalDatabase.ConfigKey.dashboardDanmakuEnabled
            )
        } label: {
            HStack(spacing: 6) {
                Text(AppLanguage.text("弹幕", en: "Ticker"))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(glass.ink)
                
                ZStack(alignment: self.isDanmakuEnabled ? .trailing : .leading) {
                    Capsule()
                        .fill(self.isDanmakuEnabled ? self.palette.accentFill : glass.inactiveTrack)
                        .frame(width: 24, height: 14)
                    Circle()
                        .fill(Color.white)
                        .frame(width: 10, height: 10)
                        .padding(.horizontal, 2)
                }
            }
            .padding(.horizontal, 11)
            .frame(height: 28)
            .background {
                self.adaptiveGlassCapsule(glass: glass)
            }
            .contentShape(Capsule())
        }
        .buttonStyle(DashboardCardButtonStyle(pressedScale: 0.99))
        .pointerStyle(.link)
        .onHover { hovering in
            if hovering != self.isToggleHovered {
                self.isToggleHovered = hovering
            }
        }
    }
    
    
    private func authorPortrait(size: CGFloat) -> some View {
        ZStack {
            if let avatarImage = self.avatarImage {
                Image(nsImage: avatarImage)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipped()
            } else {
                UserAvatarCircleView(profile: self.profile, size: size, customImage: nil)
                    .frame(width: size, height: size)
                    .clipped()
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(
                    Color.white.opacity(self.palette.tokens.isDark ? 0.14 : 0.65),
                    lineWidth: 0.6
                )
        )
    }
    
    
    private func headerStatBlock(label: String, value: String, unit: String, overPhoto: Bool) -> some View {
        let primaryInk: Color = overPhoto ? .white : self.palette.pine
        let labelInk: Color = overPhoto ? Color.white.opacity(0.76) : self.palette.mutedInk
        let textShadow: Color = overPhoto ? Color.black.opacity(0.26) : .clear
        
        return VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(labelInk)
                .shadow(color: textShadow, radius: 1.5, y: 0.5)
                .lineLimit(1)
            
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.system(size: self.compact ? 17 : 19.5, weight: .semibold).monospacedDigit())
                    .foregroundStyle(primaryInk)
                    .shadow(color: textShadow, radius: 2.5, y: 1)
                    .contentTransition(.numericText())
                    .lineLimit(1)
                Text(unit)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(labelInk)
                    .shadow(color: textShadow, radius: 1.5, y: 0.5)
                    .lineLimit(1)
            }
        }
    }
    
    
    private func adaptiveDanmakuStage(
        size: CGSize,
        items: [DashboardHeroDanmakuScheduler.Item],
        elapsed: TimeInterval,
        hasPhoto: Bool
    ) -> some View {
        let laneCount = (!self.compact && size.height >= 104) ? 3 : 2
        let lanePitch: CGFloat = max(28, size.height / CGFloat(laneCount))
        let pillHeight: CGFloat = self.compact ? 24 : 26
        let maxW = items.map { DashboardHeroDanmakuScheduler.estimatedPillSize(for: $0.text).width }.max() ?? 116
        let step = maxW + 44
        let cycle = max(size.width + maxW + 64, CGFloat(max(1, items.count)) * step / CGFloat(laneCount))
        
        return ZStack(alignment: .topLeading) {
            ForEach(Array(items.enumerated()), id: \.element.id) { idx, item in
                let lane = idx % laneCount
                let pillSize = DashboardHeroDanmakuScheduler.estimatedPillSize(for: item.text)
                let speed: CGFloat = switch lane {
                    case 0: 21.0
                    case 1: 16.5
                    default: 24.5
                }
                let phaseOffset = CGFloat(lane) * (step * 0.42)
                let raw = CGFloat(elapsed) * speed + CGFloat(idx / laneCount) * step + phaseOffset
                let travel = raw.truncatingRemainder(dividingBy: cycle)
                let centerX = (size.width + maxW * 0.5) - travel
                let centerY = (CGFloat(lane) + 0.5) * lanePitch
                let edgeDist = min(centerX - pillSize.width * 0.5, size.width - (centerX + pillSize.width * 0.5))
                let fade = min(1.0, max(0.0, Double(edgeDist / 34.0)))
                if fade > 0.02 {
                    // Sample the exact horizontal column behind this pill right now so its glass & ink adapt continuously!
                    let normalizedX = Double(centerX / max(1, size.width))
                    let localBgTone = self.toneSnapshot.danmakuTone(atNormalizedX: normalizedX)
                    let pillGlass = HeroAdaptiveGlassTokens.resolve(
                        for: localBgTone,
                        hasPhoto: hasPhoto,
                        hovered: false,
                        palette: self.palette
                    )
                    let dotColor = HeroAdaptiveGlassTokens.danmakuAccentDot(
                        for: item.tone,
                        background: localBgTone,
                        palette: self.palette
                    )
                    HStack(spacing: 6) {
                        Circle()
                            .fill(dotColor)
                            .frame(width: 5, height: 5)
                        Text(item.text)
                            .font(.system(size: self.compact ? 11.5 : 12, weight: .medium))
                            .foregroundStyle(pillGlass.ink)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 11)
                    .frame(height: pillHeight)
                    .background {
                        self.adaptiveGlassCapsule(glass: pillGlass)
                    }
                    .position(x: centerX, y: centerY)
                    .opacity(fade)
                }
            }
        }
    }
}


/// Adaptive photographic hero backdrop supporting both clamped 2D `.fill` framing and uncropped `.fit` ambient presentation,
/// keeping upper showcase clarity while smoothly melting into the bottom telemetry strip.
private struct HeroPhotoFadeBackdrop: View {
    
    let coverImage: NSImage?
    let focalX: Double
    let focalY: Double
    let fitMode: HeroCoverFitMode
    let bottomTone: HeroRegionTone
    let palette: DashPalette
    
    var body: some View {
        let isDark = self.palette.tokens.isDark
        let cardColor = self.palette.card
        let ambientTint = Color(red: self.bottomTone.red, green: self.bottomTone.green, blue: self.bottomTone.blue)
        
        ZStack(alignment: .top) {
            cardColor
            
            if let coverImage = self.coverImage {
                GeometryReader { geo in
                    let targetW = max(1, geo.size.width)
                    let targetH = max(1, geo.size.height)
                    let imgAspect: CGFloat = {
                        if let cg = DashboardHeroCoverStore.underlyingCGImage(from: coverImage), cg.height > 0 {
                            return CGFloat(cg.width) / CGFloat(cg.height)
                        }
                        let sz = coverImage.size
                        return sz.height > 0 ? (sz.width / sz.height) : 1.77
                    }()
                    let safeAspect = max(0.2, min(8.0, imgAspect))
                    let targetAspect = targetW / targetH
                    
                    if self.fitMode == .fit {
                        // Fit Mode: harmonious blurred ambient fill + uncropped centered subject
                        ZStack(alignment: .center) {
                            Image(nsImage: coverImage)
                                .resizable()
                                .interpolation(.medium)
                                .aspectRatio(contentMode: .fill)
                                .frame(width: targetW, height: targetH)
                                .blur(radius: 26)
                                .scaleEffect(1.08)
                                .overlay(ambientTint.opacity(isDark ? 0.24 : 0.14))
                                .clipped()
                            
                            Image(nsImage: coverImage)
                                .resizable()
                                .interpolation(.high)
                                .aspectRatio(contentMode: .fit)
                                .frame(maxWidth: targetW * 0.94, maxHeight: max(60, targetH * 0.82))
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .padding(.bottom, targetH * 0.16)
                        }
                        .frame(width: targetW, height: targetH)
                        .clipped()
                    } else {
                        // Fill Mode: crisp scenic upper showcase melting into Apple-style progressive frosted blur
                        let renderedW = safeAspect >= targetAspect ? (targetH * safeAspect) : targetW
                        let renderedH = safeAspect >= targetAspect ? targetH : (targetW / safeAspect)
                        let overflowX = max(0, renderedW - targetW)
                        let overflowY = max(0, renderedH - targetH)
                        let xOffset = -overflowX * CGFloat(max(0.0, min(1.0, self.focalX)))
                        let yOffset = -overflowY * CGFloat(max(0.0, min(1.0, self.focalY)))
                        
                        ZStack(alignment: .topLeading) {
                            Image(nsImage: coverImage)
                                .resizable()
                                .interpolation(.high)
                                .frame(width: renderedW, height: renderedH)
                                .offset(x: xOffset, y: yOffset)
                                .frame(width: targetW, height: targetH, alignment: .topLeading)
                            
                            Image(nsImage: coverImage)
                                .resizable()
                                .interpolation(.medium)
                                .frame(width: renderedW, height: renderedH)
                                .offset(x: xOffset, y: yOffset)
                                .frame(width: targetW, height: targetH, alignment: .topLeading)
                                .blur(radius: 30, opaque: true)
                                .mask(
                                    LinearGradient(
                                        stops: [
                                            .init(color: .clear, location: 0.00),
                                            .init(color: .clear, location: 0.24),
                                            .init(color: .white.opacity(0.68), location: 0.42),
                                            .init(color: .white, location: 0.58),
                                            .init(color: .white, location: 1.00),
                                        ],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                        }
                        .clipped()
                    }
                }
                
                // Photo-harmonized atmospheric depth scrim (zero chalky milky-white veil):
                // keeps upper photo vivid, anchors crisp luminous white typography across the identity/KPI band,
                // and lets natural photo chroma breathe harmoniously behind Row 1 frosted-glass cards.
                let deepPhotoScrim = Color(
                    red: max(0.03, self.bottomTone.red * 0.22),
                    green: max(0.04, self.bottomTone.green * 0.24),
                    blue: max(0.06, self.bottomTone.blue * 0.30)
                )
                LinearGradient(
                    stops: [
                        .init(color: deepPhotoScrim.opacity(0.22), location: 0.00),
                        .init(color: deepPhotoScrim.opacity(0.06), location: 0.12),
                        .init(color: deepPhotoScrim.opacity(0.36), location: 0.28),
                        .init(color: deepPhotoScrim.opacity(isDark ? 0.42 : 0.26), location: 0.44),
                        .init(color: deepPhotoScrim.opacity(isDark ? 0.32 : 0.12), location: 1.00),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                
                // Subtle ambient chromatic wash echoing the cover photo across the lower frosted zone
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0.30),
                        .init(color: ambientTint.opacity(isDark ? 0.20 : 0.16), location: 0.72),
                        .init(color: cardColor.opacity(isDark ? 0.22 : 0.14), location: 1.00),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            } else {
                // Soft, airy daylight mist default wash (zero heavy dark colors)
                ZStack {
                    LinearGradient(
                        stops: [
                            .init(color: self.palette.accentFill.opacity(isDark ? 0.16 : 0.09), location: 0.00),
                            .init(color: self.palette.tokens.secondaryAccent.opacity(isDark ? 0.08 : 0.05), location: 0.42),
                            .init(color: cardColor.opacity(0.0), location: 0.78),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    
                    RadialGradient(
                        colors: [
                            self.palette.accentFill.opacity(isDark ? 0.14 : 0.08),
                            Color.clear,
                        ],
                        center: UnitPoint(x: 0.78, y: 0.12),
                        startRadius: 10,
                        endRadius: 380
                    )
                }
            }
        }
        .allowsHitTesting(false)
    }
}


// MARK: - Unified Writing Telemetry & Yearly Heatmap Card (今日码字 × 热力图 × 数学曲线双向联动)

private struct DashboardHeatmapCard: View {
    
    let yearlyHeatmap: YearlyHeatmapData
    let today: DailyWritingStats
    let days14: [DashboardSnapshot.ChartDay]
    let trendCurve14: MathematicalTrendCurveEngine.Result
    let aiTrendCurve14: MathematicalTrendCurveEngine.Result
    let currentStreak: Int
    let availableYears: [Int]
    @Binding var selectedYear: Int
    let compact: Bool
    var cornerRadius: CGFloat = 14
    var overPhoto: Bool = false
    let palette: DashPalette
    
    @State private var hoveredHit: HeatmapGridLayout.Hit?
    @State private var hoveredBarDayID: String?
    @State private var selectedEndWeek: Int?
    @State private var trendDragAnchorEndWeek: Int?
    @State private var heatmapDragAnchorEndWeek: Int?
    @State private var heatmapDragStartsInsideScope = false
    @State private var isDraggingTrend = false
    @State private var isDraggingHeatmap = false
    @State private var cachedWindowKey = ""
    @State private var cachedWindowSlice: HeatmapTrendWindowEngine.Slice?
    @State private var waveReveal: CGFloat = DashMotion.isReducedMotion ? 1.0 : 0.0
    @State private var isPrevYearHovered = false
    @State private var isNextYearHovered = false
    
    
    private var previousYear: Int? {
        self.availableYears.last { $0 < self.yearlyHeatmap.year }
    }
    
    private var nextYear: Int? {
        self.availableYears.first { $0 > self.yearlyHeatmap.year }
    }
    
    private var isDraggingWindow: Bool {
        self.isDraggingTrend || self.isDraggingHeatmap
    }
    
    private var activeLinkedDayID: String? {
        guard !self.isDraggingWindow else { return nil }
        return self.hoveredBarDayID ?? self.hoveredHit?.cell.id
    }
    
    private var windowCacheKey: String {
        "\(self.yearlyHeatmap.year)|\(self.yearlyHeatmap.weeks.count)|\(self.yearlyHeatmap.totalTypedChars)|\(self.yearlyHeatmap.activeDays)|\(self.selectedEndWeek ?? -1)"
    }
    
    private var activeWindowSlice: HeatmapTrendWindowEngine.Slice {
        if self.cachedWindowKey == self.windowCacheKey, let cached = self.cachedWindowSlice {
            return cached
        }
        return HeatmapTrendWindowEngine.slice(
            weeks: self.yearlyHeatmap.weeks,
            requestedEndWeek: self.selectedEndWeek
        )
    }
    
    private func activeReadout(windowDays: [DashboardSnapshot.ChartDay]) -> (label: String, total: Int, typed: Int, ai: Int) {
        if !self.isDraggingWindow,
           let barID = self.hoveredBarDayID,
           let day = windowDays.first(where: { $0.id == barID })
        {
            return (Self.shortDateFormatter.string(from: day.date), day.typed + day.ai, day.typed, day.ai)
        }
        if !self.isDraggingWindow, let cell = self.hoveredHit?.cell {
            return (Self.shortDateFormatter.string(from: cell.date), cell.typedChars + cell.aiCompletedChars, cell.typedChars, cell.aiCompletedChars)
        }
        let total = self.today.typedChars + self.today.aiCompletedChars
        return ("今日码字", total, self.today.typedChars, self.today.aiCompletedChars)
    }
    
    private func formattedWindowRange(_ slice: HeatmapTrendWindowEngine.Slice) -> String {
        guard let start = slice.startDate, let end = slice.endDate else { return "" }
        let s = Self.compactMonthDayFormatter.string(from: start)
        let e = Self.compactMonthDayFormatter.string(from: end)
        return s == e ? s : "\(s) – \(e)"
    }
    
    private func syncWindowCache() {
        let key = self.windowCacheKey
        guard self.cachedWindowKey != key else { return }
        self.cachedWindowSlice = HeatmapTrendWindowEngine.slice(
            weeks: self.yearlyHeatmap.weeks,
            requestedEndWeek: self.selectedEndWeek
        )
        self.cachedWindowKey = key
    }
    
    
    var body: some View {
        let slice = self.activeWindowSlice
        let readout = self.activeReadout(windowDays: slice.days)
        let isInspecting = (self.activeLinkedDayID != nil)
        let weekCount = max(1, self.yearlyHeatmap.weeks.count)
        let avgWindow = Int(slice.totalCurve.averageValue.rounded())
        
        VStack(alignment: .leading, spacing: self.compact ? 4 : 6) {
            self.topTelemetryBar(readout: readout, isInspecting: isInspecting)
            
            // Tightly coupled Upright 2-Week Heatmap Frame -> Window Bridge -> Draggable Telemetry Wave
            GeometryReader { bodyGeo in
                let gap: CGFloat = self.compact ? 5 : 6
                let bridgeH: CGFloat = 18
                let minWaveH: CGFloat = self.compact ? 50 : 66
                let rawHeatmapH = HeatmapGridLayout.intrinsicHeight(forWidth: bodyGeo.size.width, weekCount: weekCount)
                let maxHeatmapH = max(76, bodyGeo.size.height - bridgeH - gap * 2 - minWaveH)
                let targetHeatmapH = min(rawHeatmapH, maxHeatmapH)
                let layout = HeatmapGridLayout.compute(
                    size: CGSize(width: bodyGeo.size.width, height: targetHeatmapH),
                    weekCount: weekCount
                )
                let heatmapH = layout.canvasHeight
                
                VStack(alignment: .leading, spacing: gap) {
                    self.heatmapScrollLayer(
                        layout: layout,
                        heatmapH: heatmapH,
                        weekCount: weekCount,
                        range: slice.range
                    )
                    
                    self.windowBridgeBar(
                        slice: slice,
                        readout: readout,
                        isInspecting: isInspecting,
                        avgWindow: avgWindow,
                        height: bridgeH
                    )
                    
                    self.draggableTrendWaveWell(
                        slice: slice,
                        weekCount: weekCount
                    )
                }
            }
        }
        .padding(self.compact ? 11 : 13)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .dashboardCardSurface(palette: self.palette, cornerRadius: self.cornerRadius, overPhoto: self.overPhoto)
        .onAppear {
            self.syncWindowCache()
            guard self.waveReveal < 1.0 else { return }
            withAnimation(DashMotion.resolve(DashMotion.chartReveal.delay(0.10))) {
                self.waveReveal = 1.0
            }
        }
        .onChange(of: self.yearlyHeatmap.year) { _, _ in
            self.selectedEndWeek = nil
            self.hoveredHit = nil
            self.hoveredBarDayID = nil
            self.syncWindowCache()
        }
        .onChange(of: self.windowCacheKey) { _, _ in
            self.syncWindowCache()
        }
    }
    
    
    @ViewBuilder
    private func topTelemetryBar(
        readout: (label: String, total: Int, typed: Int, ai: Int),
        isInspecting: Bool
    ) -> some View {
        HStack(alignment: .center, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(isInspecting ? readout.label : AppLanguage.text("今日码字", en: "Typed Today"))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(isInspecting ? self.palette.emerald : self.palette.mutedInk)
                
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(readout.total.formatted())
                        .font(.system(size: self.compact ? 17 : 20, weight: .semibold).monospacedDigit())
                        .foregroundStyle(isInspecting ? self.palette.emerald : self.palette.pine)
                    Text("字")
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(self.palette.mutedInk)
                }
            }
            
            Spacer(minLength: 4)
            
            if !self.compact {
                HStack(spacing: 2.5) {
                    ForEach(0..<5, id: \.self) { level in
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(self.palette.heat(level))
                            .frame(width: 8, height: 8)
                    }
                }
                .padding(.trailing, 4)
            }
            
            HStack(spacing: 2) {
                Button {
                    if let prev = self.previousYear {
                        withAnimation(DashMotion.resolve(DashMotion.quick)) {
                            self.selectedYear = prev
                        }
                    }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(self.previousYear != nil ? (self.isPrevYearHovered ? self.palette.pine : self.palette.secondaryInk) : self.palette.pine.opacity(0.20))
                        .frame(width: 20, height: 20)
                        .background(
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(self.isPrevYearHovered && self.previousYear != nil ? self.palette.insetHover : Color.clear)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(self.previousYear == nil)
                .onHover { hovering in
                    withAnimation(DashMotion.resolve(DashMotion.quick)) {
                        self.isPrevYearHovered = hovering
                    }
                }
                
                Text("\(String(self.yearlyHeatmap.year))")
                    .font(.system(size: 11.5, weight: .medium, design: .monospaced).monospacedDigit())
                    .foregroundStyle(self.palette.pine)
                    .contentTransition(.numericText())
                
                Button {
                    if let next = self.nextYear {
                        withAnimation(DashMotion.resolve(DashMotion.quick)) {
                            self.selectedYear = next
                        }
                    }
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(self.nextYear != nil ? (self.isNextYearHovered ? self.palette.pine : self.palette.secondaryInk) : self.palette.pine.opacity(0.20))
                        .frame(width: 20, height: 20)
                        .background(
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(self.isNextYearHovered && self.nextYear != nil ? self.palette.insetHover : Color.clear)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(self.nextYear == nil)
                .onHover { hovering in
                    withAnimation(DashMotion.resolve(DashMotion.quick)) {
                        self.isNextYearHovered = hovering
                    }
                }
            }
            .padding(.horizontal, 4)
            .frame(height: 22)
            .background(self.palette.inset, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
    }
    
    
    @ViewBuilder
    private func heatmapScrollLayer(
        layout: HeatmapGridLayout,
        heatmapH: CGFloat,
        weekCount: Int,
        range: HeatmapTrendWindowEngine.WindowRange
    ) -> some View {
        ScrollViewReader { scrollProxy in
            ScrollView(.horizontal, showsIndicators: false) {
                ZStack(alignment: .topLeading) {
                    HStack(spacing: 0) {
                        Color.clear.frame(width: layout.gridOriginX, height: 1)
                        ForEach(0..<weekCount, id: \.self) { col in
                            Color.clear
                                .frame(width: layout.pitch, height: 1)
                                .id(col)
                        }
                    }
                    .allowsHitTesting(false)
                    
                    HeatmapStaticBaseCanvas(
                        yearlyHeatmap: self.yearlyHeatmap,
                        scopeStartWeek: range.startWeek,
                        scopeEndWeek: range.endWeek,
                        isDraggingScope: self.isDraggingWindow,
                        layout: layout,
                        heatmapHeight: heatmapH,
                        overPhoto: self.overPhoto,
                        palette: self.palette
                    )
                    .equatable()
                    
                    if let linkedID = self.activeLinkedDayID {
                        Canvas { context, _ in
                            for (colIndex, week) in self.yearlyHeatmap.weeks.enumerated() {
                                for (rowIndex, cell) in week.enumerated() {
                                    guard rowIndex < 7, !cell.isOutOfYear, !cell.isFuture, cell.id == linkedID else { continue }
                                    let rect = layout.cellRect(col: colIndex, row: rowIndex)
                                    let path = RoundedRectangle(cornerRadius: layout.cornerRadius, style: .continuous)
                                        .path(in: rect)
                                    context.fill(path, with: .color(self.palette.emerald))
                                    context.stroke(
                                        path,
                                        with: .color(self.palette.pine.opacity(0.85)),
                                        lineWidth: 1.35
                                    )
                                    return
                                }
                            }
                        }
                        .frame(width: layout.canvasWidth, height: heatmapH)
                        .allowsHitTesting(false)
                    }
                    
                    Color.clear
                        .contentShape(Rectangle())
                        .frame(width: layout.canvasWidth, height: heatmapH)
                        .onContinuousHover { phase in
                            guard !self.isDraggingWindow else { return }
                            switch phase {
                                case .active(let location):
                                    let hit = layout.hitTestCoord(point: location, weeks: self.yearlyHeatmap.weeks)
                                    if hit != self.hoveredHit {
                                        self.hoveredHit = hit
                                    }
                                case .ended:
                                    if self.hoveredHit != nil {
                                        self.hoveredHit = nil
                                    }
                            }
                        }
                        .onTapGesture(coordinateSpace: .local) { location in
                            let target = HeatmapTrendWindowEngine.endWeekForHeatmapTap(
                                locationX: location.x,
                                layout: layout,
                                weekCount: weekCount
                            )
                            self.selectedEndWeek = target
                        }
                        .gesture(
                            DragGesture(minimumDistance: 4, coordinateSpace: .local)
                                .onChanged { value in
                                    if self.heatmapDragAnchorEndWeek == nil {
                                        let scopeBox = layout.scopeRect(
                                            minCol: range.startWeek,
                                            maxCol: range.endWeek
                                        ).insetBy(dx: -8, dy: -6)
                                        self.heatmapDragStartsInsideScope = scopeBox.contains(value.startLocation)
                                        self.heatmapDragAnchorEndWeek = range.endWeek
                                        self.isDraggingHeatmap = true
                                        self.hoveredHit = nil
                                        self.hoveredBarDayID = nil
                                    }
                                    let nextEnd: Int
                                    if self.heatmapDragStartsInsideScope, let anchor = self.heatmapDragAnchorEndWeek {
                                        nextEnd = HeatmapTrendWindowEngine.endWeekForHeatmapDrag(
                                            anchorEndWeek: anchor,
                                            translationX: value.translation.width,
                                            pitch: layout.pitch,
                                            weekCount: weekCount
                                        )
                                    } else {
                                        nextEnd = HeatmapTrendWindowEngine.endWeekForHeatmapTap(
                                            locationX: value.location.x,
                                            layout: layout,
                                            weekCount: weekCount
                                        )
                                    }
                                    if nextEnd != self.selectedEndWeek {
                                        self.selectedEndWeek = nextEnd
                                    }
                                }
                                .onEnded { _ in
                                    self.heatmapDragAnchorEndWeek = nil
                                    self.heatmapDragStartsInsideScope = false
                                    self.isDraggingHeatmap = false
                                }
                        )
                    
                    if !self.isDraggingWindow, let hit = self.hoveredHit {
                        self.hoverTooltip(
                            hit: hit,
                            layout: layout,
                            in: CGSize(width: layout.canvasWidth, height: heatmapH)
                        )
                    }
                }
            }
            .defaultScrollAnchor(.trailing)
            .frame(height: heatmapH)
            .onChange(of: range.endWeek) { _, newEndWeek in
                guard !self.isDraggingHeatmap else { return }
                withAnimation(DashMotion.resolve(DashMotion.quick)) {
                    scrollProxy.scrollTo(newEndWeek, anchor: .center)
                }
            }
        }
    }
    
    
    @ViewBuilder
    private func windowBridgeBar(
        slice: HeatmapTrendWindowEngine.Slice,
        readout: (label: String, total: Int, typed: Int, ai: Int),
        isInspecting: Bool,
        avgWindow: Int,
        height: CGFloat
    ) -> some View {
        let rangeText = self.formattedWindowRange(slice)
        HStack(spacing: 6) {
            HStack(spacing: 5) {
                RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                    .fill(self.palette.accentFill.opacity(self.palette.tokens.isDark ? 0.16 : 0.10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                            .strokeBorder(self.palette.accentFill.opacity(self.palette.tokens.isDark ? 0.58 : 0.48), lineWidth: 1.0)
                    )
                    .frame(width: 9, height: 9)
                
                Text(
                    slice.range.isLatest
                        ? AppLanguage.text("两周趋势", en: "2W Trend")
                        : rangeText
                )
                .font(.system(size: 10.5, weight: .medium).monospacedDigit())
                .foregroundStyle(slice.range.isLatest ? self.palette.mutedInk : self.palette.pine)
                .fixedSize(horizontal: true, vertical: false)
                
                if slice.range.isLatest, !rangeText.isEmpty, !self.compact {
                    Text(rangeText)
                        .font(.system(size: 10, weight: .regular).monospacedDigit())
                        .foregroundStyle(self.palette.mutedInk.opacity(0.82))
                        .fixedSize(horizontal: true, vertical: false)
                }
            }
            
            HStack(spacing: 1) {
                Button {
                    let prev = HeatmapTrendWindowEngine.clampedRange(
                        weekCount: self.yearlyHeatmap.weeks.count,
                        requestedEndWeek: slice.range.endWeek - 1
                    ).endWeek
                    self.selectedEndWeek = prev
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(slice.range.canStepBackward ? self.palette.secondaryInk : self.palette.pine.opacity(0.18))
                        .frame(width: 16, height: 16)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!slice.range.canStepBackward)
                
                Button {
                    let next = HeatmapTrendWindowEngine.clampedRange(
                        weekCount: self.yearlyHeatmap.weeks.count,
                        requestedEndWeek: slice.range.endWeek + 1
                    ).endWeek
                    self.selectedEndWeek = (next >= slice.range.maxEndWeek) ? nil : next
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(slice.range.canStepForward ? self.palette.secondaryInk : self.palette.pine.opacity(0.18))
                        .frame(width: 16, height: 16)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!slice.range.canStepForward)
            }
            
            if !slice.range.isLatest {
                Button {
                    self.selectedEndWeek = nil
                } label: {
                    Text(AppLanguage.text("最新", en: "Latest"))
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(self.palette.secondaryInk)
                        .padding(.horizontal, 5.5)
                        .padding(.vertical, 1.5)
                        .background(
                            Capsule(style: .continuous)
                                .fill(self.palette.inset)
                        )
                }
                .buttonStyle(.plain)
            }
            
            Rectangle()
                .fill(self.palette.hairline)
                .frame(height: 0.7)
            
            if isInspecting {
                Text("手写 \(readout.typed.formatted()) · AI \(readout.ai.formatted())")
                    .font(.system(size: 10.5, weight: .medium, design: .monospaced).monospacedDigit())
                    .foregroundStyle(self.palette.emerald)
                    .fixedSize(horizontal: true, vertical: false)
            } else {
                HStack(spacing: 6) {
                    HStack(spacing: 3) {
                        Circle()
                            .fill(self.palette.accentFill)
                            .frame(width: 5, height: 5)
                        Text(AppLanguage.text("手写", en: "Typed"))
                    }
                    HStack(spacing: 3) {
                        Circle()
                            .fill(self.palette.emerald)
                            .frame(width: 5, height: 5)
                        Text("AI")
                    }
                    if avgWindow > 0 {
                        Text("· 日均 \(avgWindow.formatted()) 字")
                    }
                }
                .font(.system(size: 10, weight: .regular).monospacedDigit())
                .foregroundStyle(self.palette.mutedInk)
                .fixedSize(horizontal: true, vertical: false)
            }
        }
        .frame(height: height)
    }
    
    
    @ViewBuilder
    private func draggableTrendWaveWell(
        slice: HeatmapTrendWindowEngine.Slice,
        weekCount: Int
    ) -> some View {
        GeometryReader { waveGeo in
            let days = slice.days
            let count = days.count
            TelemetryWaveCanvas(
                days14: days,
                curve: slice.totalCurve,
                aiCurve: slice.aiCurve,
                activeLinkedDayID: self.activeLinkedDayID,
                compact: self.compact,
                palette: self.palette,
                reveal: self.waveReveal
            )
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                guard count > 0, !self.isDraggingWindow else { return }
                let padX: CGFloat = 6
                let plotW = max(10, waveGeo.size.width - padX * 2)
                switch phase {
                    case .active(let loc):
                        let norm = max(0, min(1, (loc.x - padX) / plotW))
                        let idx = min(count - 1, max(0, Int((norm * CGFloat(max(1, count - 1))).rounded())))
                        let nextID = days[idx].id
                        if nextID != self.hoveredBarDayID {
                            self.hoveredBarDayID = nextID
                        }
                    case .ended:
                        if self.hoveredBarDayID != nil {
                            self.hoveredBarDayID = nil
                        }
                }
            }
            .onTapGesture(count: 2) {
                if !slice.range.isLatest {
                    self.selectedEndWeek = nil
                }
            }
            .gesture(
                DragGesture(minimumDistance: 5, coordinateSpace: .local)
                    .onChanged { value in
                        if self.trendDragAnchorEndWeek == nil {
                            self.trendDragAnchorEndWeek = slice.range.endWeek
                            self.isDraggingTrend = true
                            self.hoveredBarDayID = nil
                            self.hoveredHit = nil
                        }
                        guard let anchor = self.trendDragAnchorEndWeek else { return }
                        let plotW = max(40, waveGeo.size.width - 12)
                        let nextEnd = HeatmapTrendWindowEngine.endWeekForTrendDrag(
                            anchorEndWeek: anchor,
                            translationX: value.translation.width,
                            plotWidth: plotW,
                            weekCount: weekCount
                        )
                        if nextEnd != self.selectedEndWeek {
                            self.selectedEndWeek = (nextEnd >= slice.range.maxEndWeek) ? nil : nextEnd
                        }
                    }
                    .onEnded { _ in
                        self.trendDragAnchorEndWeek = nil
                        self.isDraggingTrend = false
                    }
            )
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: DashboardCornerMetrics.nestedWellRadius, style: .continuous)
                .fill(self.palette.inset.opacity(self.palette.tokens.isDark ? (self.isDraggingTrend ? 0.52 : 0.38) : (self.overPhoto ? 0.44 : (self.isDraggingTrend ? 0.72 : 0.58))))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DashboardCornerMetrics.nestedWellRadius, style: .continuous)
                .strokeBorder(self.isDraggingTrend ? self.palette.hairlineStrong : Color.clear, lineWidth: 0.8)
        )
    }
    
    
    @ViewBuilder
    private func hoverTooltip(hit: HeatmapGridLayout.Hit, layout: HeatmapGridLayout, in size: CGSize) -> some View {
        let cellRect = layout.cellRect(col: hit.col, row: hit.row)
        let total = hit.cell.typedChars + hit.cell.aiCompletedChars
        let tipX = min(max(62, cellRect.midX), max(62, size.width - 62))
        let tipY = max(16, cellRect.minY - 14)
        
        Text("\(Self.shortDateFormatter.string(from: hit.cell.date)) · \(total.formatted()) 字")
            .font(.system(size: 11, weight: .medium, design: .rounded).monospacedDigit())
            .foregroundStyle(self.palette.pine)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(self.palette.card.opacity(0.96))
                    .shadow(color: self.palette.cardShadow, radius: 6, y: 2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(self.palette.hairlineStrong, lineWidth: 0.7)
            )
            .position(x: tipX, y: tipY)
            .allowsHitTesting(false)
    }
    
    
    private static let shortDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "M月d日"
        return f
    }()
    
    private static let compactMonthDayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "M/d"
        return f
    }()
}


/// Animatable dual-layer 14-day telemetry wave (bars grow smoothly from baseline + C¹ spline sweeps left-to-right).
private struct TelemetryWaveCanvas: View, Animatable {
    
    let days14: [DashboardSnapshot.ChartDay]
    let curve: MathematicalTrendCurveEngine.Result
    let aiCurve: MathematicalTrendCurveEngine.Result
    let activeLinkedDayID: String?
    let compact: Bool
    let palette: DashPalette
    var reveal: CGFloat
    
    var animatableData: CGFloat {
        get { self.reveal }
        set { self.reveal = newValue }
    }
    
    
    var body: some View {
        let count = self.days14.count
        let progress = max(0.0, min(1.0, self.reveal))
        
        Canvas { context, size in
            guard size.width > 16, size.height > 14, !self.curve.samples.isEmpty else { return }
            let padX: CGFloat = 6
            let padTop: CGFloat = 6
            let padBot: CGFloat = 4
            let plotW = max(10, size.width - padX * 2)
            let plotH = max(8, size.height - padTop - padBot)
            let maxV = max(1.0, self.curve.maxScale)
            
            func pt(t: Double, val: Double) -> CGPoint {
                let x = padX + CGFloat(t) * plotW
                let y = padTop + plotH * CGFloat(1.0 - min(1.0, max(0.0, val / maxV)))
                return CGPoint(x: x, y: y)
            }
            
            // 0. Base & Mean horizon reference hairlines
            let baseY = padTop + plotH
            var baseRef = Path()
            baseRef.move(to: CGPoint(x: padX, y: baseY))
            baseRef.addLine(to: CGPoint(x: size.width - padX, y: baseY))
            context.stroke(baseRef, with: .color(self.palette.hairline), lineWidth: 0.7)
            
            if self.curve.averageValue > 0 {
                let avgY = pt(t: 0, val: self.curve.averageValue).y
                var avgLine = Path()
                avgLine.move(to: CGPoint(x: padX, y: avgY))
                avgLine.addLine(to: CGPoint(x: size.width - padX, y: avgY))
                context.stroke(
                    avgLine,
                    with: .color(self.palette.secondaryInk.opacity(0.24 * Double(progress))),
                    style: StrokeStyle(lineWidth: 0.75, dash: [3, 3])
                )
            }
            
            // 1. Slim stacked daily impulse bars rising smoothly with wave reveal
            let denom = Double(max(1, count - 1))
            let barW: CGFloat = self.compact ? 4 : 5
            for (idx, day) in self.days14.enumerated() {
                let totalV = Double(day.typed + day.ai)
                guard totalV > 0 else { continue }
                let t = count > 1 ? Double(idx) / denom : 0.5
                let barProgress = max(0.0, min(1.0, (progress * 1.25) - CGFloat(t) * 0.25))
                guard barProgress > 0.01 else { continue }
                let cx = padX + CGFloat(t) * plotW
                let totalH = max(2, plotH * CGFloat(min(1.0, totalV / maxV)) * barProgress)
                let aiH = totalH * CGFloat(Double(day.ai) / totalV)
                let typedH = totalH - aiH
                let isLinked = (self.activeLinkedDayID == day.id)
                
                if typedH > 0.5 {
                    let rect = CGRect(x: cx - barW * 0.5, y: baseY - typedH, width: barW, height: typedH)
                    context.fill(
                        RoundedRectangle(cornerRadius: 1.5, style: .continuous).path(in: rect),
                        with: .color(self.palette.accentFill.opacity(isLinked ? 0.42 : 0.16))
                    )
                }
                if aiH > 0.5 {
                    let rect = CGRect(x: cx - barW * 0.5, y: baseY - totalH, width: barW, height: max(1, aiH))
                    context.fill(
                        RoundedRectangle(cornerRadius: 1.5, style: .continuous).path(in: rect),
                        with: .color(self.palette.emerald.opacity(isLinked ? 0.58 : 0.28))
                    )
                }
            }
            
            // Left-to-right progressive clip for splines & envelope
            let clipW = progress >= 0.999 ? size.width : (padX + plotW * progress + 4)
            context.drawLayer { layerCtx in
                layerCtx.clip(to: Path(CGRect(x: 0, y: 0, width: clipW, height: size.height)))
                
                // 2. Gaussian ±0.65σ confidence envelope corridor
                var bandPath = Path()
                for (idx, s) in self.curve.samples.enumerated() {
                    let p = pt(t: s.t, val: s.upper)
                    if idx == 0 { bandPath.move(to: p) } else { bandPath.addLine(to: p) }
                }
                for s in self.curve.samples.reversed() {
                    bandPath.addLine(to: pt(t: s.t, val: s.lower))
                }
                bandPath.closeSubpath()
                layerCtx.fill(bandPath, with: .color(self.palette.accentFill.opacity(0.09)))
                
                // 3. Secondary AI Co-Writing Spline
                if self.aiCurve.peakValue > 0, !self.aiCurve.samples.isEmpty {
                    var aiPath = Path()
                    for (idx, s) in self.aiCurve.samples.enumerated() {
                        let p = pt(t: s.t, val: s.value)
                        if idx == 0 { aiPath.move(to: p) } else { aiPath.addLine(to: p) }
                    }
                    layerCtx.stroke(
                        aiPath,
                        with: .color(self.palette.emerald.opacity(0.75)),
                        style: StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round)
                    )
                }
                
                // 4. Primary Total C¹ Hermite Spline & Area Fill
                var areaPath = Path()
                var linePath = Path()
                for (idx, s) in self.curve.samples.enumerated() {
                    let p = pt(t: s.t, val: s.value)
                    if idx == 0 {
                        areaPath.move(to: CGPoint(x: p.x, y: baseY))
                        areaPath.addLine(to: p)
                        linePath.move(to: p)
                    } else {
                        areaPath.addLine(to: p)
                        linePath.addLine(to: p)
                    }
                }
                if let last = self.curve.samples.last {
                    areaPath.addLine(to: CGPoint(x: pt(t: last.t, val: last.value).x, y: baseY))
                    areaPath.closeSubpath()
                }
                layerCtx.fill(
                    areaPath,
                    with: .linearGradient(
                        Gradient(colors: [self.palette.accentFill.opacity(0.14), self.palette.accentFill.opacity(0.01)]),
                        startPoint: CGPoint(x: size.width * 0.5, y: padTop),
                        endPoint: CGPoint(x: size.width * 0.5, y: baseY)
                    )
                )
                layerCtx.stroke(
                    linePath,
                    with: .color(self.palette.accentFill),
                    style: StrokeStyle(lineWidth: 1.75, lineCap: .round, lineJoin: .round)
                )
            }
            
            // 5. Knot dots + 2D Hover Crosshair
            for (idx, day) in self.days14.enumerated() {
                let t = count > 1 ? Double(idx) / denom : 0.5
                guard CGFloat(t) <= progress + 0.04 else { continue }
                let val = Double(day.typed + day.ai)
                let p = pt(t: t, val: val)
                let isLinked = (self.activeLinkedDayID == day.id)
                let isPeak = (self.curve.peakIndex == idx)
                let dotAlpha = min(1.0, max(0.0, Double((progress - CGFloat(t) + 0.08) / 0.14)))
                
                if isLinked {
                    var cross = Path()
                    cross.move(to: CGPoint(x: p.x, y: padTop))
                    cross.addLine(to: CGPoint(x: p.x, y: baseY))
                    cross.move(to: CGPoint(x: padX, y: p.y))
                    cross.addLine(to: CGPoint(x: size.width - padX, y: p.y))
                    context.stroke(cross, with: .color(self.palette.emerald.opacity(0.45)), style: StrokeStyle(lineWidth: 0.9, dash: [2, 2]))
                    
                    let halo = CGRect(x: p.x - 5.5, y: p.y - 5.5, width: 11, height: 11)
                    context.fill(Circle().path(in: halo), with: .color(self.palette.emerald.opacity(0.24)))
                    let dot = CGRect(x: p.x - 3.2, y: p.y - 3.2, width: 6.4, height: 6.4)
                    context.fill(Circle().path(in: dot), with: .color(self.palette.emerald))
                } else if isPeak {
                    let ring = CGRect(x: p.x - 3.0, y: p.y - 3.0, width: 6.0, height: 6.0)
                    context.fill(Circle().path(in: ring), with: .color(self.palette.card.opacity(dotAlpha)))
                    context.stroke(Circle().path(in: ring), with: .color(self.palette.emerald.opacity(dotAlpha)), lineWidth: 1.5)
                } else if val > 0 {
                    let dot = CGRect(x: p.x - 1.6, y: p.y - 1.6, width: 3.2, height: 3.2)
                    context.fill(Circle().path(in: dot), with: .color(self.palette.accentFill.opacity(0.80 * dotAlpha)))
                }
            }
        }
    }
}


/// Static 365-cell heatmap layer isolated from transient hover state (`Equatable` + async Canvas).
private struct HeatmapStaticBaseCanvas: View, Equatable {
    
    let yearlyHeatmap: YearlyHeatmapData
    let scopeStartWeek: Int
    let scopeEndWeek: Int
    let isDraggingScope: Bool
    let layout: HeatmapGridLayout
    let heatmapHeight: CGFloat
    var overPhoto: Bool = false
    let palette: DashPalette
    
    
    var body: some View {
        let isDark = self.palette.tokens.isDark
        let emptyCellFill: Color = if self.overPhoto {
            isDark
                ? Color.white.opacity(0.085)
                : self.palette.pine.opacity(0.065)
        } else {
            self.palette.emptyDot
        }
        let weekCount = self.yearlyHeatmap.weeks.count
        
        Canvas(rendersAsynchronously: true) { context, canvasSize in
            guard canvasSize.width.isFinite, canvasSize.height.isFinite,
                  canvasSize.width > 10, canvasSize.height > 10 else { return }
            
            var lastLabelRightX: CGFloat = -100
            for marker in self.yearlyHeatmap.monthLabels where marker.month == 1 || marker.month == 4 || marker.month == 7 || marker.month == 10 {
                let x = self.layout.gridOriginX + CGFloat(marker.weekIndex) * self.layout.pitch
                guard x >= lastLabelRightX + 26 else { continue }
                lastLabelRightX = x
                context.draw(
                    Text("\(marker.month)")
                        .font(.system(size: 9.5, weight: .medium, design: .rounded).monospacedDigit())
                        .foregroundStyle(self.palette.pine.opacity(0.46)),
                    at: CGPoint(x: x, y: HeatmapGridLayout.monthLabelBaselineY),
                    anchor: .leading
                )
            }
            
            // Upright, symmetrical 2-week rectangular lens strictly centered in the cell gutters
            let hasScope = weekCount > 0 && self.scopeStartWeek <= self.scopeEndWeek && self.scopeEndWeek < weekCount
            let scopeBox = hasScope
                ? self.layout.scopeRect(minCol: max(0, self.scopeStartWeek), maxCol: min(weekCount - 1, self.scopeEndWeek))
                : .zero
            let scopePath = hasScope
                ? RoundedRectangle(cornerRadius: self.layout.scopeCornerRadius, style: .continuous).path(in: scopeBox)
                : Path()
            
            if hasScope {
                let fillOpacity: Double = isDark
                    ? (self.isDraggingScope ? 0.19 : 0.12)
                    : (self.isDraggingScope ? 0.13 : 0.075)
                context.fill(scopePath, with: .color(self.palette.accentFill.opacity(fillOpacity)))
            }
            
            for (colIndex, week) in self.yearlyHeatmap.weeks.enumerated() {
                for (rowIndex, cell) in week.enumerated() {
                    guard rowIndex < 7, !cell.isOutOfYear else { continue }
                    let rect = self.layout.cellRect(col: colIndex, row: rowIndex)
                    let path = RoundedRectangle(cornerRadius: self.layout.cornerRadius, style: .continuous)
                        .path(in: rect)
                    if cell.isFuture {
                        // Subtle balanced placeholder slots for upcoming days in the current week
                        context.fill(path, with: .color(emptyCellFill.opacity(isDark ? 0.24 : 0.34)))
                        context.stroke(path, with: .color(self.palette.hairline.opacity(0.85)), lineWidth: 0.5)
                    } else {
                        let fill = (cell.level == 0) ? emptyCellFill : self.palette.heat(cell.level)
                        context.fill(path, with: .color(fill))
                    }
                }
            }
            
            // Unbroken rectangular border on top, strictly centered in the gutter with zero cell overlap
            if hasScope {
                let strokeOpacity: Double = isDark
                    ? (self.isDraggingScope ? 0.82 : 0.58)
                    : (self.isDraggingScope ? 0.72 : 0.48)
                let strokeW = self.layout.scopeStrokeWidth(isDragging: self.isDraggingScope)
                context.stroke(
                    scopePath,
                    with: .color(self.palette.accentFill.opacity(strokeOpacity)),
                    style: StrokeStyle(
                        lineWidth: strokeW,
                        lineCap: .round,
                        lineJoin: .round
                    )
                )
            }
        }
        .frame(width: self.layout.canvasWidth, height: self.heatmapHeight)
    }
}


/// Strict 1:1 square-cell layout for the yearly activity heatmap with guaranteed unclipped scope bleed margins.
struct HeatmapGridLayout: Equatable {
    
    static let sidePad: CGFloat = 6.0
    static let topAxis: CGFloat = 18.0
    static let bottomPad: CGFloat = 6.0
    static let monthLabelBaselineY: CGFloat = 6.5
    static let scopeStrokeWidth: CGFloat = 1.0
    
    let gridOriginX: CGFloat
    let gridOriginY: CGFloat
    let cellSide: CGFloat
    let gap: CGFloat
    let cornerRadius: CGFloat
    let canvasWidth: CGFloat
    let canvasHeight: CGFloat
    
    var pitch: CGFloat { self.cellSide + self.gap }
    
    /// Exact half-gutter outset so the 14-day contour runs dead-center between adjacent cells
    /// with zero overlap into neighboring columns or rows.
    var scopeOutset: CGFloat {
        self.gap * 0.5
    }
    
    /// Stroke width tuned to always stay strictly clear of both inner and outer cell edges inside the gutter.
    var scopeStrokeWidth: CGFloat {
        self.scopeStrokeWidth(isDragging: false)
    }
    
    func scopeStrokeWidth(isDragging: Bool) -> CGFloat {
        if isDragging {
            return self.gap <= 2.0 ? 1.25 : 1.35
        }
        return self.gap <= 2.0 ? 0.9 : 1.0
    }
    
    /// Concentric rounded corner radius matching `cellCornerRadius + scopeOutset`, capped cleanly for crisp geometry.
    var scopeCornerRadius: CGFloat {
        min(self.cornerRadius + self.scopeOutset, 5.0)
    }
    
    
    static func intrinsicHeight(forWidth width: CGFloat, weekCount: Int) -> CGFloat {
        let cols = max(1, weekCount)
        let rows = 7
        
        let availW = max(120, width - Self.sidePad * 2)
        let gap: CGFloat = cols > 40 ? 2.5 : 3.0
        let fitW = (availW - CGFloat(cols - 1) * gap) / CGFloat(cols)
        let cellSide = max(9.5, min(15.0, floor(fitW * 2) / 2))
        let gridH = CGFloat(rows) * cellSide + CGFloat(rows - 1) * gap
        return ceil(Self.topAxis + gridH + Self.bottomPad)
    }
    
    
    static func compute(size: CGSize, weekCount: Int) -> HeatmapGridLayout {
        let cols = max(1, weekCount)
        let rows = 7
        
        let availW = max(120, size.width - Self.sidePad * 2)
        let availH = max(48, size.height - Self.topAxis - Self.bottomPad)
        
        let standardGap: CGFloat = cols > 40 ? 2.5 : 3.0
        let fitHStandard = (availH - CGFloat(rows - 1) * standardGap) / CGFloat(rows)
        let gap: CGFloat = fitHStandard < 9.0 ? 2.0 : standardGap
        
        let fitW = (availW - CGFloat(cols - 1) * gap) / CGFloat(cols)
        let fitH = (availH - CGFloat(rows - 1) * gap) / CGFloat(rows)
        
        let maxSide: CGFloat = 15.0
        // Keep >= 9.5pt whenever vertical space permits (preserving crisp cells & horizontal scrolling on wide years),
        // and gracefully scale down to 6.5pt on short viewports so the 7 rows + scope frame NEVER clip vertically.
        let cellSide: CGFloat
        if fitH >= 9.5 {
            let idealSide = min(fitW, fitH)
            cellSide = max(9.5, min(maxSide, floor(idealSide * 2) / 2))
        } else {
            cellSide = max(6.0, min(maxSide, floor(fitH * 2) / 2))
        }
        
        let gridW = CGFloat(cols) * cellSide + CGFloat(cols - 1) * gap
        let gridH = CGFloat(rows) * cellSide + CGFloat(rows - 1) * gap
        
        let contentW = Self.sidePad * 2 + gridW
        let contentH = ceil(Self.topAxis + gridH + Self.bottomPad)
        let canvasWidth = max(size.width, contentW)
        let canvasHeight = contentH
        
        let gridOriginX = contentW < size.width
            ? Self.sidePad + floor((size.width - contentW) * 0.5)
            : Self.sidePad
        let gridOriginY = Self.topAxis
        let cornerRadius = max(1.8, min(3.5, cellSide * 0.25))
        
        return HeatmapGridLayout(
            gridOriginX: gridOriginX,
            gridOriginY: gridOriginY,
            cellSide: cellSide,
            gap: gap,
            cornerRadius: cornerRadius,
            canvasWidth: canvasWidth,
            canvasHeight: canvasHeight
        )
    }
    
    
    func cellRect(col: Int, row: Int) -> CGRect {
        let x = self.gridOriginX + CGFloat(col) * self.pitch
        let y = self.gridOriginY + CGFloat(row) * self.pitch
        return CGRect(x: x, y: y, width: self.cellSide, height: self.cellSide)
    }
    
    
    /// Exact gutter-centered upright highlight rectangle enclosing columns `minCol...maxCol` across all 7 weekday rows.
    func scopeRect(minCol: Int, maxCol: Int) -> CGRect {
        let first = self.cellRect(col: minCol, row: 0)
        let last = self.cellRect(col: maxCol, row: 6)
        let outset = self.scopeOutset
        return CGRect(
            x: first.minX - outset,
            y: first.minY - outset,
            width: (last.maxX - first.minX) + outset * 2,
            height: (last.maxY - first.minY) + outset * 2
        )
    }
    
    
    struct Hit: Equatable {
        let col: Int
        let row: Int
        let cell: HeatmapDayCell
    }
    
    
    func hitTest(point: CGPoint, weeks: [[HeatmapDayCell]]) -> HeatmapDayCell? {
        self.hitTestCoord(point: point, weeks: weeks)?.cell
    }
    
    
    func hitTestCoord(point: CGPoint, weeks: [[HeatmapDayCell]]) -> Hit? {
        let col = Int(floor((point.x - self.gridOriginX) / self.pitch))
        let row = Int(floor((point.y - self.gridOriginY) / self.pitch))
        guard col >= 0, col < weeks.count, row >= 0, row < weeks[col].count else { return nil }
        let cell = weeks[col][row]
        guard !cell.isOutOfYear, !cell.isFuture else { return nil }
        return Hit(col: col, row: row, cell: cell)
    }
}


/// Pure deterministic engine coupling the yearly heatmap's upright 2-week rectangular window
/// with the draggable bottom trend chart.
nonisolated enum HeatmapTrendWindowEngine {
    
    static let windowWeeks: Int = 2
    
    struct WindowRange: Equatable, Sendable {
        let startWeek: Int
        let endWeek: Int
        let maxEndWeek: Int
        let minEndWeek: Int
        
        var isLatest: Bool { self.endWeek >= self.maxEndWeek }
        var canStepBackward: Bool { self.endWeek > self.minEndWeek }
        var canStepForward: Bool { self.endWeek < self.maxEndWeek }
    }
    
    struct Slice: Sendable {
        let range: WindowRange
        let days: [DashboardSnapshot.ChartDay]
        let totalCurve: MathematicalTrendCurveEngine.Result
        let aiCurve: MathematicalTrendCurveEngine.Result
        let startDate: Date?
        let endDate: Date?
    }
    
    /// Clamps `requestedEndWeek` into the valid 2-week sliding window range for `weekCount` columns.
    static func clampedRange(weekCount: Int, requestedEndWeek: Int?) -> WindowRange {
        let count = max(1, weekCount)
        let maxEnd = count - 1
        let minEnd = min(maxEnd, Self.windowWeeks - 1)
        let rawEnd = requestedEndWeek ?? maxEnd
        let end = min(maxEnd, max(minEnd, rawEnd))
        let start = max(0, end - (Self.windowWeeks - 1))
        return WindowRange(
            startWeek: start,
            endWeek: end,
            maxEndWeek: maxEnd,
            minEndWeek: minEnd
        )
    }
    
    /// Maps a horizontal drag on the trend chart to a clamped `endWeek`.
    /// Dragging right pulls earlier history into view (decreases `endWeek`);
    /// dragging left advances forward toward today (increases `endWeek`).
    static func endWeekForTrendDrag(
        anchorEndWeek: Int,
        translationX: CGFloat,
        plotWidth: CGFloat,
        weekCount: Int
    ) -> Int {
        let stepWidth = max(24.0, min(44.0, plotWidth / 12.0))
        let deltaWeeks = Int(((-translationX) / stepWidth).rounded())
        return Self.clampedRange(weekCount: weekCount, requestedEndWeek: anchorEndWeek + deltaWeeks).endWeek
    }
    
    /// Maps a horizontal drag on the heatmap's upright window frame to a clamped `endWeek`.
    static func endWeekForHeatmapDrag(
        anchorEndWeek: Int,
        translationX: CGFloat,
        pitch: CGFloat,
        weekCount: Int
    ) -> Int {
        let safePitch = max(6.0, pitch)
        let deltaWeeks = Int((translationX / safePitch).rounded())
        return Self.clampedRange(weekCount: weekCount, requestedEndWeek: anchorEndWeek + deltaWeeks).endWeek
    }
    
    /// Maps a click/scrub x-coordinate on the heatmap canvas to a clamped `endWeek` framing that week.
    static func endWeekForHeatmapTap(
        locationX: CGFloat,
        layout: HeatmapGridLayout,
        weekCount: Int
    ) -> Int {
        let rawCol = Int(floor((locationX - layout.gridOriginX) / max(6.0, layout.pitch)))
        let clampedCol = min(max(0, weekCount - 1), max(0, rawCol))
        return Self.clampedRange(weekCount: weekCount, requestedEndWeek: clampedCol).endWeek
    }
    
    /// Extracts the active days inside columns `startWeek...endWeek` and computes total & AI Hermite curves.
    static func slice(
        weeks: [[HeatmapDayCell]],
        requestedEndWeek: Int?
    ) -> Slice {
        let range = Self.clampedRange(weekCount: weeks.count, requestedEndWeek: requestedEndWeek)
        var days: [DashboardSnapshot.ChartDay] = []
        days.reserveCapacity(Self.windowWeeks * 7)
        
        if !weeks.isEmpty, range.startWeek <= range.endWeek {
            for col in range.startWeek...min(range.endWeek, weeks.count - 1) {
                for (rowIdx, cell) in weeks[col].enumerated() where rowIdx < 7 && !cell.isOutOfYear && !cell.isFuture {
                    days.append(
                        DashboardSnapshot.ChartDay(
                            id: cell.id,
                            date: cell.date,
                            typed: cell.typedChars,
                            ai: cell.aiCompletedChars
                        )
                    )
                }
            }
        }
        
        let totalCurve = MathematicalTrendCurveEngine.compute(
            values: days.map { Double($0.typed + $0.ai) },
            samplesPerSegment: 8,
            bandwidth: 1.65
        )
        let aiCurve = MathematicalTrendCurveEngine.compute(
            values: days.map { Double($0.ai) },
            samplesPerSegment: 6,
            bandwidth: 1.5
        )
        return Slice(
            range: range,
            days: days,
            totalCurve: totalCurve,
            aiCurve: aiCurve,
            startDate: days.first?.date,
            endDate: days.last?.date
        )
    }
}


// MARK: - Full-Width AI Usage Card (Clean Sunburst + Single Cost & Input/Output Split)

private struct DashboardAIUsageWideCard: View {
    
    let snapshot: DashboardSnapshot
    var cornerRadius: CGFloat = 14
    var overPhoto: Bool = false
    let palette: DashPalette
    let onTap: () -> Void
    
    @State private var isHovered = false
    @State private var hasAppeared = DashMotion.isReducedMotion
    
    
    var body: some View {
        let totals = self.snapshot.ai30Totals
        let todayTotals = self.snapshot.aiTodayTotals
        let displayReqs = todayTotals.requests > 0 ? todayTotals.requests : totals.requests
        let costEstimate = AIModelPricingCatalog.estimateTotalCost(models: self.snapshot.aiModels, fallbackTotals: totals)
        
        let inTok = max(0, totals.inputTokens)
        let outTok = max(0, totals.outputTokens)
        let inFrac: Double = (inTok + outTok) > 0 ? Double(inTok) / Double(inTok + outTok) : 0.62
        let inPct = Int((inFrac * 100).rounded())
        let outPct = max(0, 100 - inPct)
        
        Button(action: self.onTap) {
            GeometryReader { cardGeo in
                let ringSide = min(88, max(68, floor(cardGeo.size.height - 20)))
                HStack(spacing: 14) {
                    ZStack {
                        AIUsageSunburstChartView(snapshot: self.snapshot, palette: self.palette, detailed: false)
                            .frame(width: ringSide, height: ringSide)
                        
                        VStack(spacing: 0.5) {
                            Text("\(displayReqs)")
                                .font(.system(size: ringSide < 78 ? 12 : 13.5, weight: .bold, design: .rounded).monospacedDigit())
                                .foregroundStyle(self.palette.pine)
                                .contentTransition(.numericText())
                            Text(AppLanguage.text("次", en: "req"))
                                .font(.system(size: 9.5, weight: .medium))
                                .foregroundStyle(self.palette.mutedInk)
                        }
                        .allowsHitTesting(false)
                    }
                    .frame(width: ringSide + 2, height: ringSide + 2)
                    
                    VStack(alignment: .leading, spacing: cardGeo.size.height < 118 ? 8 : 12) {
                        HStack(alignment: .top, spacing: 8) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(AppLanguage.text("AI 用量", en: "AI Usage"))
                                    .font(.system(size: 11.5, weight: .medium))
                                    .foregroundStyle(self.palette.mutedInk)
                                
                                HStack(alignment: .firstTextBaseline, spacing: 3) {
                                    Text(Self.compactTokens(totals.totalTokens))
                                        .font(.system(size: cardGeo.size.height < 118 ? 18 : 20, weight: .semibold).monospacedDigit())
                                        .foregroundStyle(self.palette.pine)
                                        .contentTransition(.numericText())
                                    Text("tok")
                                        .font(.system(size: 11, weight: .regular))
                                        .foregroundStyle(self.palette.mutedInk)
                                }
                            }
                            
                            Spacer(minLength: 4)
                            
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(costEstimate.formattedRMB)
                                    .font(.system(size: 13, weight: .semibold, design: .rounded).monospacedDigit())
                                    .foregroundStyle(self.palette.pine)
                                Text(costEstimate.formattedUSD)
                                    .font(.system(size: 10.5, weight: .regular, design: .monospaced).monospacedDigit())
                                    .foregroundStyle(self.palette.mutedInk)
                            }
                        }
                        
                        VStack(spacing: 5) {
                            GeometryReader { barGeo in
                                let w = max(40, barGeo.size.width)
                                let splitX = max(14, min(w - 14, w * CGFloat(inFrac)))
                                HStack(spacing: 2) {
                                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                                        .fill(self.palette.pine.opacity(self.palette.tokens.isDark ? 0.72 : 0.68))
                                        .frame(width: max(8, splitX - 1))
                                    
                                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                                        .fill(self.palette.pine.opacity(self.palette.tokens.isDark ? 0.22 : 0.16))
                                        .frame(maxWidth: .infinity)
                                }
                                .scaleEffect(x: self.hasAppeared ? 1.0 : 0.08, anchor: .leading)
                                .animation(DashMotion.resolve(DashMotion.chartReveal.delay(0.12)), value: self.hasAppeared)
                            }
                            .frame(height: 4)
                            
                            HStack {
                                Text("输入 \(Self.compactTokens(inTok)) · \(inPct)%")
                                    .font(.system(size: 10.5, weight: .medium).monospacedDigit())
                                    .foregroundStyle(self.palette.secondaryInk)
                                Spacer()
                                Text("生成 \(Self.compactTokens(outTok)) · \(outPct)%")
                                    .font(.system(size: 10.5, weight: .regular).monospacedDigit())
                                    .foregroundStyle(self.palette.mutedInk)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 13)
                .padding(.vertical, 9)
                .frame(width: cardGeo.size.width, height: cardGeo.size.height, alignment: .center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .dashboardCardSurface(palette: self.palette, cornerRadius: self.cornerRadius, isHighlighted: self.isHovered, overPhoto: self.overPhoto)
            .contentShape(RoundedRectangle(cornerRadius: self.cornerRadius, style: .continuous))
        }
        .buttonStyle(DashboardCardButtonStyle(pressedScale: 0.995))
        .pointerStyle(.link)
        .onHover { hovering in
            if hovering != self.isHovered {
                self.isHovered = hovering
            }
        }
        .onAppear {
            guard !self.hasAppeared else { return }
            withAnimation(DashMotion.resolve(DashMotion.chartReveal)) {
                self.hasAppeared = true
            }
        }
    }
    
    
    private static func compactTokens(_ value: Int) -> String {
        if value >= 1_000_000 { return String(format: "%.1fM", Double(value) / 1_000_000.0) }
        if value >= 1_000 { return String(format: "%.1fK", Double(value) / 1_000.0) }
        return value.formatted()
    }
}


// MARK: - Compact & Expanded Quad Cards

private struct DashboardCompactQuadCard: View {
    
    let metric: DashboardQuadMetric
    let snapshot: DashboardSnapshot
    var cornerRadius: CGFloat = 14
    var overPhoto: Bool = false
    let palette: DashPalette
    let onTap: () -> Void
    
    @State private var isHovered = false
    
    
    var body: some View {
        Button {
            self.onTap()
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(self.metric.title)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(self.palette.mutedInk)
                        .lineLimit(1)
                    
                    Spacer(minLength: 4)
                    
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text(self.heroValueText)
                            .font(.system(size: 16, weight: .semibold).monospacedDigit())
                            .foregroundStyle(self.palette.pine)
                            .contentTransition(.numericText())
                            .lineLimit(1)
                        
                        if !self.heroUnitText.isEmpty {
                            Text(self.heroUnitText)
                                .font(.system(size: 11, weight: .regular))
                                .foregroundStyle(self.palette.mutedInk)
                                .lineLimit(1)
                        }
                    }
                }
                
                self.miniVisualization
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(11)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .dashboardCardSurface(palette: self.palette, cornerRadius: self.cornerRadius, isHighlighted: self.isHovered, overPhoto: self.overPhoto)
            .contentShape(RoundedRectangle(cornerRadius: self.cornerRadius, style: .continuous))
        }
        .buttonStyle(DashboardCardButtonStyle(pressedScale: 0.995))
        .pointerStyle(.link)
        .onHover { hovering in
            if hovering != self.isHovered {
                self.isHovered = hovering
            }
        }
    }
    
    
    private var heroValueText: String {
        switch self.metric {
            case .typed:
                let total = self.snapshot.today.typedChars + self.snapshot.today.aiCompletedChars
                return total.formatted()
            case .aiUsage:
                let val = self.snapshot.aiTodayTotals.totalTokens > 0
                    ? self.snapshot.aiTodayTotals.totalTokens
                    : self.snapshot.ai30Totals.totalTokens
                return self.formatTokens(val)
            case .busyness:
                return "\(self.snapshot.busyness.score)"
            case .mood:
                return "\(self.snapshot.mood.score)"
        }
    }
    
    
    private var heroUnitText: String {
        switch self.metric {
            case .typed: "字"
            case .aiUsage: "tok"
            case .busyness: "%"
            case .mood: ""
        }
    }
    
    
    private var secondaryBadgeText: String? {
        nil
    }
    
    
    private func formatTokens(_ value: Int) -> String {
        if value >= 10_000 {
            return String(format: "%.1fK", Double(value) / 1000.0)
        }
        return value.formatted()
    }
    
    
    @ViewBuilder
    private var miniVisualization: some View {
        switch self.metric {
            case .typed:
                TrendAreaChartView(days: self.snapshot.days14, curve: self.snapshot.trendCurve14, palette: self.palette, detailed: false)
            case .aiUsage:
                AIUsageSunburstChartView(snapshot: self.snapshot, palette: self.palette, detailed: false)
            case .busyness:
                NightingaleRoseChartView(metrics: self.snapshot.busyness, palette: self.palette, detailed: false)
            case .mood:
                EmotionSankeyChartView(snapshot: self.snapshot, palette: self.palette, detailed: false)
        }
    }
}


private struct DashboardExpandedQuadCard: View {
    
    let metric: DashboardQuadMetric
    let snapshot: DashboardSnapshot
    var cornerRadius: CGFloat = 14
    var overPhoto: Bool = false
    let palette: DashPalette
    let onClose: () -> Void
    
    @State private var hoverDetail: String?
    @State private var isCloseHovered = false
    
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 10) {
                Text(self.metric.title)
                    .font(.system(size: 14.5, weight: .semibold))
                    .foregroundStyle(self.palette.pine)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                
                Spacer(minLength: 8)
                
                // Fixed-height readout slot in header: never shifts or resizes chart layout on hover
                Text(self.hoverDetail ?? " ")
                    .font(.system(size: 11.5, weight: .medium, design: .rounded).monospacedDigit())
                    .foregroundStyle(self.palette.secondaryInk)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .padding(.horizontal, 9)
                    .frame(height: 22)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(self.palette.inset)
                    )
                    .opacity(self.hoverDetail == nil ? 0 : 1)
                    .scaleEffect(self.hoverDetail == nil && !DashMotion.isReducedMotion ? 0.96 : 1.0)
                    .animation(DashMotion.resolve(DashMotion.quick), value: self.hoverDetail)
                    .allowsHitTesting(false)
                
                Button(action: self.onClose) {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(self.isCloseHovered ? self.palette.pine : self.palette.pine.opacity(0.68))
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(self.isCloseHovered ? self.palette.insetHover : self.palette.inset))
                        .contentShape(Circle())
                }
                .buttonStyle(DashboardCardButtonStyle(pressedScale: 0.99))
                .pointerStyle(.link)
                .onHover { hovering in
                    guard hovering != self.isCloseHovered else { return }
                    self.isCloseHovered = hovering
                }
            }
            .frame(height: 26)
            
            self.detailedVisualization
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .dashboardCardSurface(palette: self.palette, cornerRadius: self.cornerRadius, isHighlighted: false, overPhoto: self.overPhoto)
        .onChange(of: self.metric) { _, _ in
            self.hoverDetail = nil
        }
    }
    
    
    @ViewBuilder
    private var detailedVisualization: some View {
        switch self.metric {
            case .typed:
                TrendAreaChartView(
                    days: self.snapshot.days14,
                    curve: self.snapshot.trendCurve14,
                    palette: self.palette,
                    detailed: true,
                    onHoverDetail: { self.hoverDetail = $0 }
                )
            case .aiUsage:
                AIUsageSunburstChartView(
                    snapshot: self.snapshot,
                    palette: self.palette,
                    detailed: true,
                    onHoverDetail: { self.hoverDetail = $0 }
                )
            case .busyness:
                NightingaleRoseChartView(
                    metrics: self.snapshot.busyness,
                    palette: self.palette,
                    detailed: true,
                    onHoverDetail: { self.hoverDetail = $0 }
                )
            case .mood:
                EmotionSankeyChartView(
                    snapshot: self.snapshot,
                    palette: self.palette,
                    detailed: true,
                    onHoverDetail: { self.hoverDetail = $0 }
                )
        }
    }
}


// MARK: - Chart 1: Trend Area-Line Chart

private struct TrendAreaChartView: View {
    
    let days: [DashboardSnapshot.ChartDay]
    let curve: MathematicalTrendCurveEngine.Result
    let palette: DashPalette
    let detailed: Bool
    var onHoverDetail: ((String?) -> Void)? = nil
    
    @State private var hoveredIndex: Int?
    @State private var reveal: CGFloat = DashMotion.isReducedMotion ? 1.0 : 0.0
    
    
    var body: some View {
        let curve = self.curve
        
        GeometryReader { geo in
            Canvas { context, size in
                guard size.width.isFinite, size.height.isFinite,
                      size.width > 12, size.height > 12, !curve.samples.isEmpty else { return }
                let padTop: CGFloat = self.detailed ? 12 : 4
                let padBottom: CGFloat = self.detailed ? 20 : 4
                let padX: CGFloat = self.detailed ? 8 : 4
                let plotW = max(8, size.width - padX * 2)
                let plotH = max(8, size.height - padTop - padBottom)
                let maxY = max(1.0, curve.maxScale)
                
                func pointAt(t: Double, value: Double) -> CGPoint {
                    let x = padX + CGFloat(t) * plotW
                    let y = padTop + plotH * CGFloat(1.0 - min(1.0, max(0.0, value / maxY)))
                    return CGPoint(x: x, y: y)
                }
                
                if self.detailed {
                    for frac in [0.0, 0.5, 1.0] {
                        let y = padTop + plotH * CGFloat(frac)
                        var grid = Path()
                        grid.move(to: CGPoint(x: padX, y: y))
                        grid.addLine(to: CGPoint(x: size.width - padX, y: y))
                        context.stroke(grid, with: .color(self.palette.hairline), lineWidth: 0.7)
                    }
                }
                
                var area = Path()
                var line = Path()
                let baseY = padTop + plotH
                for (idx, s) in curve.samples.enumerated() {
                    let pt = pointAt(t: s.t, value: s.value)
                    if idx == 0 {
                        area.move(to: CGPoint(x: pt.x, y: baseY))
                        area.addLine(to: pt)
                        line.move(to: pt)
                    } else {
                        area.addLine(to: pt)
                        line.addLine(to: pt)
                    }
                }
                if let last = curve.samples.last {
                    area.addLine(to: CGPoint(x: pointAt(t: last.t, value: last.value).x, y: baseY))
                    area.closeSubpath()
                }
                
                context.fill(
                    area,
                    with: .linearGradient(
                        Gradient(colors: [self.palette.accentFill.opacity(0.28), self.palette.accentFill.opacity(0.02)]),
                        startPoint: CGPoint(x: size.width * 0.5, y: padTop),
                        endPoint: CGPoint(x: size.width * 0.5, y: baseY)
                    )
                )
                context.stroke(line, with: .color(self.palette.emerald), style: StrokeStyle(lineWidth: self.detailed ? 2.2 : 1.7, lineCap: .round, lineJoin: .round))
                
                if self.detailed {
                    let denom = Double(max(1, self.days.count - 1))
                    for (idx, d) in self.days.enumerated() {
                        let pt = pointAt(t: self.days.count > 1 ? Double(idx) / denom : 0.5, value: Double(d.typed + d.ai))
                        let isHover = (self.hoveredIndex == idx)
                        let r: CGFloat = isHover ? 4.5 : 2.6
                        context.fill(
                            Circle().path(in: CGRect(x: pt.x - r, y: pt.y - r, width: r * 2, height: r * 2)),
                            with: .color(isHover ? self.palette.pine : self.palette.emerald)
                        )
                        if idx == 0 || idx == self.days.count / 2 || idx == self.days.count - 1 {
                            context.draw(
                                Text(Self.dayFmt.string(from: d.date))
                                    .font(.system(size: 9.5, design: .rounded).monospacedDigit())
                                    .foregroundStyle(self.palette.pine.opacity(0.45)),
                                at: CGPoint(x: pt.x, y: size.height - 8),
                                anchor: .center
                            )
                        }
                    }
                }
            }
            .mask(alignment: .leading) {
                Rectangle()
                    .frame(width: max(1, geo.size.width * self.reveal))
            }
            .onAppear {
                guard self.reveal < 1.0 else { return }
                withAnimation(DashMotion.resolve(DashMotion.chartReveal)) {
                    self.reveal = 1.0
                }
            }
            .onContinuousHover { phase in
                guard self.detailed, !self.days.isEmpty else { return }
                switch phase {
                    case .active(let loc):
                        let padX: CGFloat = 8
                        let usable = max(1, geo.size.width - padX * 2)
                        let frac = max(0, min(1, (loc.x - padX) / usable))
                        let nextIdx = min(self.days.count - 1, Int((frac * CGFloat(self.days.count - 1)).rounded()))
                        if nextIdx != self.hoveredIndex {
                            self.hoveredIndex = nextIdx
                            let d = self.days[nextIdx]
                            self.onHoverDetail?("\(Self.dayFmt.string(from: d.date)) · \((d.typed + d.ai).formatted()) 字")
                        }
                    case .ended:
                        if self.hoveredIndex != nil {
                            self.hoveredIndex = nil
                            self.onHoverDetail?(nil)
                        }
                }
            }
        }
    }
    
    
    private static let dayFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "M/d"
        return f
    }()
}


// MARK: - Chart 2: High-Performance Drill-Down Sunburst Chart (Value-Type Render Arcs + GPU Backing + Zero-Churn Hover)

private struct SunburstRenderArc: Equatable, Identifiable {
    let key: String
    let nodeID: String
    let parentID: String?
    let ring: EvalSunburstLayoutEngine.Ring
    let a0: Double
    let a1: Double
    let r0Ratio: CGFloat
    let r1Ratio: CGFloat
    let hueIndex: Int
    let shadeStep: Int
    
    var id: String { self.key }
}


private struct SunburstDialCanvas: View, Equatable {
    
    let renderArcs: [SunburstRenderArc]
    let hoveredNodeID: String?
    let detailed: Bool
    let isDark: Bool
    let palette: DashPalette
    
    static func == (lhs: SunburstDialCanvas, rhs: SunburstDialCanvas) -> Bool {
        lhs.renderArcs == rhs.renderArcs
            && lhs.hoveredNodeID == rhs.hoveredNodeID
            && lhs.detailed == rhs.detailed
            && lhs.isDark == rhs.isDark
    }
    
    var body: some View {
        let hoveredParentID = self.hoveredNodeID.flatMap { hid in
            self.renderArcs.first(where: { $0.nodeID == hid })?.parentID
        }
        
        Canvas(opaque: false, colorMode: .nonLinear, rendersAsynchronously: true) { context, canvasSize in
            guard canvasSize.width.isFinite, canvasSize.height.isFinite,
                  canvasSize.width > 8, canvasSize.height > 8 else { return }
            let center = CGPoint(x: canvasSize.width * 0.5, y: canvasSize.height * 0.5)
            let radius = max(16, min(canvasSize.width, canvasSize.height) * 0.5 - (self.detailed ? 4 : 2))
            let hasHover = (self.hoveredNodeID != nil)
            
            for arc in self.renderArcs {
                guard arc.a1 - arc.a0 > 1e-4 else { continue }
                let sDeg = arc.a0 * 180.0 / .pi - 90.0
                let eDeg = arc.a1 * 180.0 / .pi - 90.0
                let r0 = radius * arc.r0Ratio
                let r1 = radius * arc.r1Ratio
                guard r1 - r0 > 0.2 else { continue }
                
                var path = Path()
                if arc.a1 - arc.a0 >= Double.pi * 1.9999 {
                    path.addArc(center: center, radius: r1, startAngle: .degrees(0), endAngle: .degrees(359.99), clockwise: false)
                    path.addArc(center: center, radius: r0, startAngle: .degrees(359.99), endAngle: .degrees(0), clockwise: true)
                    path.closeSubpath()
                } else {
                    path.addArc(center: center, radius: r1, startAngle: .degrees(sDeg), endAngle: .degrees(eDeg), clockwise: false)
                    path.addArc(center: center, radius: r0, startAngle: .degrees(eDeg), endAngle: .degrees(sDeg), clockwise: true)
                    path.closeSubpath()
                }
                
                let isDirectlyHovered = (self.hoveredNodeID == arc.nodeID)
                let isRelated = isDirectlyHovered
                    || (self.hoveredNodeID != nil && (arc.parentID == self.hoveredNodeID || arc.nodeID == hoveredParentID))
                let baseColor = AIUsageSunburstChartView.color(
                    hueIndex: arc.hueIndex,
                    shadeStep: arc.shadeStep,
                    isDark: self.isDark,
                    palette: self.palette
                )
                let opacityMod: Double = (!hasHover || isRelated) ? (isDirectlyHovered ? 1.0 : 0.94) : 0.72
                context.fill(path, with: .color(baseColor.opacity(opacityMod)))
                context.stroke(
                    path,
                    with: .color(self.palette.card),
                    style: StrokeStyle(lineWidth: self.detailed ? 1.5 : 1.0, lineJoin: .round)
                )
            }
        }
        .drawingGroup()
    }
}


private struct SunburstLedgerRowView: View, Equatable {
    
    let nodeID: String
    let name: String
    let compactValue: String
    let percentText: String
    let hueIndex: Int
    let isHovered: Bool
    let isDark: Bool
    let palette: DashPalette
    let onTap: () -> Void
    let onHoverChanged: (Bool) -> Void
    
    static func == (lhs: SunburstLedgerRowView, rhs: SunburstLedgerRowView) -> Bool {
        lhs.nodeID == rhs.nodeID
            && lhs.name == rhs.name
            && lhs.compactValue == rhs.compactValue
            && lhs.percentText == rhs.percentText
            && lhs.hueIndex == rhs.hueIndex
            && lhs.isHovered == rhs.isHovered
            && lhs.isDark == rhs.isDark
    }
    
    var body: some View {
        Button(action: self.onTap) {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                    .fill(AIUsageSunburstChartView.color(
                        hueIndex: self.hueIndex,
                        shadeStep: 0,
                        isDark: self.isDark,
                        palette: self.palette
                    ))
                    .frame(width: 9, height: 9)
                
                Text(self.name)
                    .font(.system(size: 12.5, weight: self.isHovered ? .semibold : .regular))
                    .foregroundStyle(self.palette.pine)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                Text(self.compactValue)
                    .font(.system(size: 12, weight: .medium, design: .rounded).monospacedDigit())
                    .foregroundStyle(self.palette.pine)
                    .frame(minWidth: 50, alignment: .trailing)
                
                Text(self.percentText)
                    .font(.system(size: 11.5, weight: .regular, design: .rounded).monospacedDigit())
                    .foregroundStyle(self.palette.secondaryInk)
                    .frame(width: 42, alignment: .trailing)
            }
            .padding(.horizontal, 9)
            .frame(minHeight: 28)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(self.isHovered ? self.palette.insetHover : Color.clear)
            )
            .animation(DashMotion.resolve(DashMotion.quick), value: self.isHovered)
            .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
        .pointerStyle(.link)
        .onHover(perform: self.onHoverChanged)
    }
}


private struct AIUsageSunburstChartView: View {
    
    let snapshot: DashboardSnapshot
    let palette: DashPalette
    let detailed: Bool
    var onHoverDetail: ((String?) -> Void)? = nil
    
    @State private var focusID: String = "root"
    @State private var hoveredNodeID: String?
    @State private var isCenterHovered = false
    @State private var dialReveal: CGFloat = DashMotion.isReducedMotion ? 1.0 : 0.0
    @State private var drillPulseScale: CGFloat = 1.0
    
    @State private var cachedFocus: EvalSunburstLayoutEngine.Node?
    @State private var cachedArcs: [EvalSunburstLayoutEngine.ArcItem] = []
    @State private var cachedRenderArcs: [SunburstRenderArc] = []
    @State private var cachedRows: [EvalSunburstLayoutEngine.LedgerRow] = []
    @State private var cachedHueMap: [String: Int] = [:]
    
    
    fileprivate static func multiHuePalette(isDark: Bool) -> [Color] {
        if isDark {
            return [
                Color(red: 0.357, green: 0.541, blue: 1.000), // Cobalt
                Color(red: 0.176, green: 0.769, blue: 0.596), // Emerald
                Color(red: 0.949, green: 0.639, blue: 0.263), // Amber
                Color(red: 0.600, green: 0.498, blue: 0.980), // Iris
                Color(red: 0.949, green: 0.439, blue: 0.533), // Rose Coral
                Color(red: 0.227, green: 0.706, blue: 0.831), // Cerulean
                Color(red: 0.545, green: 0.635, blue: 0.957), // Indigo Mist
            ]
        }
        return [
            Color(red: 0.231, green: 0.431, blue: 0.965), // Cobalt
            Color(red: 0.071, green: 0.647, blue: 0.478), // Emerald
            Color(red: 0.863, green: 0.525, blue: 0.149), // Amber
            Color(red: 0.471, green: 0.349, blue: 0.961), // Iris
            Color(red: 0.863, green: 0.302, blue: 0.408), // Rose Coral
            Color(red: 0.086, green: 0.573, blue: 0.698), // Cerulean
            Color(red: 0.329, green: 0.420, blue: 0.820), // Indigo
        ]
    }
    
    
    fileprivate static func color(hueIndex: Int, shadeStep: Int, isDark: Bool, palette: DashPalette) -> Color {
        guard hueIndex >= 0 else {
            return palette.pine.opacity(shadeStep > 0 ? 0.20 : 0.28)
        }
        let hues = Self.multiHuePalette(isDark: isDark)
        let base = hues[hueIndex % hues.count]
        guard shadeStep > 0 else { return base }
        let alpha = max(0.38, 0.82 - Double(shadeStep - 1) * 0.14)
        return base.opacity(alpha)
    }
    
    
    private func buildState(focusID: String) -> (
        focus: EvalSunburstLayoutEngine.Node,
        arcs: [EvalSunburstLayoutEngine.ArcItem],
        renderArcs: [SunburstRenderArc],
        rows: [EvalSunburstLayoutEngine.LedgerRow],
        hueMap: [String: Int]
    ) {
        let root = self.snapshot.sunburstRoot
        let map = self.snapshot.sunburstIndex
        var focus = map[focusID] ?? root
        if focus.children.isEmpty, let parent = focus.parent {
            focus = parent
        }
        let laid = EvalSunburstLayoutEngine.radialLayout(focus: focus)
        let renderArcs = laid.arcs.map { arc in
            let shade: Int = switch arc.tone {
                case .outerIndexed(let idx, _): idx + 1
                case .otherOuter: 4
                default: 0
            }
            return SunburstRenderArc(
                key: arc.key,
                nodeID: arc.node.id,
                parentID: arc.node.parent?.id,
                ring: arc.ring,
                a0: arc.a0,
                a1: arc.a1,
                r0Ratio: arc.r0Ratio,
                r1Ratio: arc.r1Ratio,
                hueIndex: laid.hueMap[arc.node.id] ?? -1,
                shadeStep: shade
            )
        }
        return (focus, laid.arcs, renderArcs, laid.rows, laid.hueMap)
    }
    
    
    private func syncLayout() {
        let state = self.buildState(focusID: self.focusID)
        self.cachedFocus = state.focus
        self.cachedArcs = state.arcs
        self.cachedRenderArcs = state.renderArcs
        self.cachedRows = state.rows
        self.cachedHueMap = state.hueMap
    }
    
    
    private func updateHover(_ nextID: String?) {
        guard nextID != self.hoveredNodeID else { return }
        withAnimation(.easeInOut(duration: 0.18)) {
            self.hoveredNodeID = nextID
        }
        guard let onHoverDetail = self.onHoverDetail else { return }
        if let nextID, let node = self.snapshot.sunburstIndex[nextID] {
            let parentVal = max(1.0, node.parent?.value ?? self.snapshot.sunburstRoot.value)
            let pct = Self.percentString(node.value / parentVal)
            onHoverDetail("\(node.name) · \(Self.compactTokens(Int(node.value.rounded()))) tok (\(pct))")
        } else {
            onHoverDetail(nil)
        }
    }
    
    
    var body: some View {
        let fallback = self.cachedFocus == nil ? self.buildState(focusID: self.focusID) : nil
        let focus = self.cachedFocus ?? fallback?.focus ?? self.snapshot.sunburstRoot
        let renderArcs = self.cachedFocus != nil ? self.cachedRenderArcs : (fallback?.renderArcs ?? [])
        let arcs = self.cachedFocus != nil ? self.cachedArcs : (fallback?.arcs ?? [])
        let rows = self.cachedFocus != nil ? self.cachedRows : (fallback?.rows ?? [])
        let hueMap = self.cachedFocus != nil ? self.cachedHueMap : (fallback?.hueMap ?? [:])
        
        Group {
            if !self.detailed {
                SunburstDialCanvas(
                    renderArcs: renderArcs,
                    hoveredNodeID: nil,
                    detailed: false,
                    isDark: self.palette.tokens.isDark,
                    palette: self.palette
                )
                .equatable()
                .scaleEffect(0.90 + 0.10 * self.dialReveal)
                .opacity(self.dialReveal)
                .allowsHitTesting(false)
            } else {
                GeometryReader { geo in
                    let dialSide = min(max(148, geo.size.height - 8), max(148, geo.size.width * 0.44))
                    HStack(alignment: .center, spacing: 18) {
                        self.sunburstDial(focus: focus, arcs: arcs, renderArcs: renderArcs)
                            .frame(width: dialSide, height: dialSide)
                            .scaleEffect((0.92 + 0.08 * self.dialReveal) * self.drillPulseScale)
                            .opacity(self.dialReveal)
                        
                        self.ledgerView(rows: rows, hueMap: hueMap)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .onAppear {
            if self.cachedFocus == nil {
                self.syncLayout()
            }
            if self.dialReveal < 1.0 {
                withAnimation(DashMotion.resolve(DashMotion.chartReveal)) {
                    self.dialReveal = 1.0
                }
            }
        }
        .onChange(of: self.snapshot.snapshotVersion) { _, _ in
            self.syncLayout()
        }
    }
    
    
    private func sunburstDial(
        focus: EvalSunburstLayoutEngine.Node,
        arcs: [EvalSunburstLayoutEngine.ArcItem],
        renderArcs: [SunburstRenderArc]
    ) -> some View {
        GeometryReader { geo in
            let size = geo.size
            let center = CGPoint(x: size.width * 0.5, y: size.height * 0.5)
            let radius = max(16, min(size.width, size.height) * 0.5 - 4)
            let holeRadius = radius * (53.0 / 110.0)
            let up = focus.parent
            
            ZStack {
                SunburstDialCanvas(
                    renderArcs: renderArcs,
                    hoveredNodeID: self.hoveredNodeID,
                    detailed: true,
                    isDark: self.palette.tokens.isDark,
                    palette: self.palette
                )
                .equatable()
                .allowsHitTesting(false)
                
                VStack(spacing: 2) {
                    if let up {
                        Text("‹ \(up.name)")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(self.palette.emerald)
                            .lineLimit(1)
                    }
                    Text(Self.compactTokens(Int(focus.value.rounded())))
                        .font(.system(size: 18, weight: .light, design: .rounded).monospacedDigit())
                        .foregroundStyle(self.palette.pine)
                        .contentTransition(.numericText())
                        .lineLimit(1)
                    if up != nil {
                        Text(focus.name)
                            .font(.system(size: 10.5, weight: .regular))
                            .foregroundStyle(self.palette.pine.opacity(0.60))
                            .lineLimit(1)
                    }
                }
                .padding(6)
                .frame(width: holeRadius * 2, height: holeRadius * 2)
                .background(
                    Circle()
                        .fill(self.isCenterHovered && up != nil ? self.palette.insetHover : self.palette.card)
                )
                .allowsHitTesting(false)
            }
            .contentShape(Circle())
            .pointerStyle(.link)
            .onContinuousHover { phase in
                switch phase {
                    case .active(let pt):
                        let dist = hypot(pt.x - center.x, pt.y - center.y)
                        if dist <= holeRadius {
                            let centerHit = (up != nil)
                            if centerHit != self.isCenterHovered {
                                self.isCenterHovered = centerHit
                            }
                            self.updateHover(nil)
                        } else {
                            if self.isCenterHovered { self.isCenterHovered = false }
                            let hitID = Self.gaplessHitTest(pt, center: center, radius: radius, arcs: arcs)?.node.id
                            self.updateHover(hitID)
                        }
                    case .ended:
                        if self.isCenterHovered { self.isCenterHovered = false }
                        self.updateHover(nil)
                }
            }
            .onTapGesture { pt in
                let dist = hypot(pt.x - center.x, pt.y - center.y)
                if dist <= holeRadius {
                    guard let up else { return }
                    self.focusID = up.id
                    self.isCenterHovered = false
                    self.updateHover(nil)
                    self.triggerDrillTransition()
                    return
                }
                if let hit = Self.gaplessHitTest(pt, center: center, radius: radius, arcs: arcs) {
                    self.handleSelect(node: hit.node)
                }
            }
        }
    }
    
    
    private func triggerDrillTransition() {
        if !DashMotion.isReducedMotion {
            self.drillPulseScale = 0.955
        }
        withAnimation(DashMotion.resolve(DashMotion.springCard)) {
            self.syncLayout()
            self.drillPulseScale = 1.0
        }
    }
    
    
    private func ledgerView(rows: [EvalSunburstLayoutEngine.LedgerRow], hueMap: [String: Int]) -> some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 2) {
                ForEach(rows) { row in
                    SunburstLedgerRowView(
                        nodeID: row.node.id,
                        name: row.node.name,
                        compactValue: Self.compactTokens(Int(row.node.value.rounded())),
                        percentText: Self.percentString(row.fraction),
                        hueIndex: hueMap[row.node.id] ?? -1,
                        isHovered: self.hoveredNodeID == row.node.id,
                        isDark: self.palette.tokens.isDark,
                        palette: self.palette,
                        onTap: {
                            self.handleSelect(node: row.node)
                        },
                        onHoverChanged: { inside in
                            let nextHover: String? = inside ? row.node.id : (self.hoveredNodeID == row.node.id ? nil : self.hoveredNodeID)
                            self.updateHover(nextHover)
                        }
                    )
                    .equatable()
                }
            }
            .padding(.vertical, 4)
        }
    }
    
    
    private func handleSelect(node: EvalSunburstLayoutEngine.Node) {
        if !node.children.isEmpty {
            self.focusID = node.id
            self.updateHover(nil)
            self.triggerDrillTransition()
        } else if let parent = node.parent, parent.id != self.focusID, !parent.children.isEmpty {
            self.focusID = parent.id
            self.updateHover(nil)
            self.triggerDrillTransition()
        }
    }
    
    
    /// Gapless polar hit-testing delegated to `EvalSunburstLayoutEngine`.
    static func gaplessHitTest(
        _ point: CGPoint,
        center: CGPoint,
        radius: CGFloat,
        arcs: [EvalSunburstLayoutEngine.ArcItem]
    ) -> EvalSunburstLayoutEngine.ArcItem? {
        EvalSunburstLayoutEngine.gaplessHitTest(point, center: center, radius: radius, arcs: arcs)
    }
    
    
    private static func percentString(_ frac: Double) -> String {
        let pct = frac * 100.0
        if pct > 0 && pct < 1.0 { return "<1%" }
        return "\(Int(pct.rounded()))%"
    }
    
    
    private static func compactTokens(_ value: Int) -> String {
        if value >= 1_000_000 { return String(format: "%.1fM", Double(value) / 1_000_000.0) }
        if value >= 1_000 { return String(format: "%.1fK", Double(value) / 1_000.0) }
        return value.formatted()
    }
}


// MARK: - Chart 3: Nightingale Rose Chart (Both Compact & Expanded Busyness)

private struct NightingaleRoseCanvas: View, Animatable {
    
    let metrics: BusynessMetrics
    let palette: DashPalette
    let detailed: Bool
    let hoveredSliceIndex: Int?
    var reveal: CGFloat
    
    var animatableData: CGFloat {
        get { self.reveal }
        set { self.reveal = newValue }
    }
    
    
    var body: some View {
        let progress = max(0.0, min(1.0, self.reveal))
        
        Canvas { context, size in
            guard size.width.isFinite, size.height.isFinite,
                  size.width > 8, size.height > 8 else { return }
            let center = CGPoint(x: size.width * 0.5, y: size.height * 0.5)
            let labelMargin: CGFloat = self.detailed ? 24 : 15
            let outerLimit = max(14, min(size.width, size.height) * 0.5 - labelMargin)
            let innerR = max(self.detailed ? 22 : 12, outerLimit * (self.detailed ? 0.28 : 0.34))
            let maxPetalSpan = max(6, outerLimit - innerR)
            
            for frac in (self.detailed ? [0.35, 0.70, 1.0] : [0.5, 1.0]) {
                let r = innerR + maxPetalSpan * CGFloat(frac)
                let ringRect = CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)
                context.stroke(
                    Circle().path(in: ringRect),
                    with: .color(self.palette.hairline),
                    lineWidth: self.detailed ? 0.7 : 0.55
                )
            }
            
            let slices = self.metrics.slices
            let totalSlices = max(1, slices.count)
            let stepAngle = 360.0 / Double(totalSlices)
            let hasHover = (self.hoveredSliceIndex != nil)
            
            for slice in slices {
                let padDeg = self.detailed ? 1.5 : 1.8
                let startDeg = -90.0 + Double(slice.index) * stepAngle + padDeg
                let endDeg = -90.0 + Double(slice.index + 1) * stepAngle - padDeg
                let stagger = CGFloat(slice.index) / CGFloat(totalSlices) * 0.28
                let localReveal = max(0.0, min(1.0, (progress - stagger) / max(0.01, 1.0 - stagger)))
                let easedReveal = 1.0 - pow(1.0 - Double(localReveal), 3.0)
                let radiusFactor = max(0.16, sqrt(max(0.02, slice.intensity))) * easedReveal
                let isHovered = (self.hoveredSliceIndex == slice.index)
                let hoverLift: CGFloat = (isHovered && self.detailed) ? 3.5 : 0.0
                let petalOuter = innerR + max(1.5, maxPetalSpan * CGFloat(radiusFactor) + hoverLift)
                
                var petal = Path()
                petal.addArc(
                    center: center,
                    radius: innerR,
                    startAngle: .degrees(startDeg),
                    endAngle: .degrees(endDeg),
                    clockwise: false
                )
                petal.addArc(
                    center: center,
                    radius: petalOuter,
                    startAngle: .degrees(endDeg),
                    endAngle: .degrees(startDeg),
                    clockwise: true
                )
                petal.closeSubpath()
                
                let color: Color = {
                    if slice.intensity >= 0.75 { return self.palette.emerald }
                    if slice.intensity >= 0.45 { return self.palette.accentFill }
                    if slice.intensity >= 0.22 { return self.palette.mint }
                    return self.palette.emptyDot
                }()
                let fillAlpha = isHovered ? 0.98 : (hasHover ? 0.55 : 0.84)
                context.fill(petal, with: .color(color.opacity(fillAlpha * max(0.25, easedReveal))))
                if isHovered {
                    context.stroke(petal, with: .color(self.palette.pine), lineWidth: 1.25)
                }
                
                if self.detailed, slice.index.isMultiple(of: 2) {
                    let midRad = (startDeg + endDeg) * 0.5 * .pi / 180.0
                    let labelR = outerLimit + 13
                    let lx = center.x + CGFloat(cos(midRad)) * labelR
                    let ly = center.y + CGFloat(sin(midRad)) * labelR
                    context.draw(
                        Text(slice.label)
                            .font(.system(size: 10, weight: isHovered ? .bold : .medium, design: .rounded).monospacedDigit())
                            .foregroundStyle(isHovered ? self.palette.pine : self.palette.secondaryInk),
                        at: CGPoint(x: lx, y: ly),
                        anchor: .center
                    )
                }
            }
            
            // Compact clock dial markers directly inside the rose chart (00 / 06 / 12 / 18)
            if !self.detailed {
                let markers: [(String, Double)] = [
                    ("夜", -90.0),
                    ("晨", 0.0),
                    ("午", 90.0),
                    ("晚", 180.0),
                ]
                let labelR = outerLimit + 9
                for (text, deg) in markers {
                    let rad = deg * .pi / 180.0
                    let lx = center.x + CGFloat(cos(rad)) * labelR
                    let ly = center.y + CGFloat(sin(rad)) * labelR
                    context.draw(
                        Text(text)
                            .font(.system(size: 9.5, weight: .medium))
                            .foregroundStyle(self.palette.secondaryInk),
                        at: CGPoint(x: lx, y: ly),
                        anchor: .center
                    )
                }
            }
            
            let coreRect = CGRect(x: center.x - innerR + 1, y: center.y - innerR + 1, width: (innerR - 1) * 2, height: (innerR - 1) * 2)
            context.fill(Circle().path(in: coreRect), with: .color(self.palette.card))
            
            // Peak hour label directly inside the rose core
            let peakShort = self.metrics.peakHourLabel.split(separator: ":").first.map { "\($0)h" } ?? "12h"
            if self.detailed {
                context.draw(
                    Text(self.metrics.peakHourLabel)
                        .font(.system(size: 11, weight: .semibold, design: .rounded).monospacedDigit())
                        .foregroundStyle(self.palette.pine),
                    at: CGPoint(x: center.x, y: center.y - 5),
                    anchor: .center
                )
                context.draw(
                    Text("峰值")
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(self.palette.mutedInk),
                    at: CGPoint(x: center.x, y: center.y + 8),
                    anchor: .center
                )
            } else {
                context.draw(
                    Text(peakShort)
                        .font(.system(size: 9, weight: .semibold, design: .rounded).monospacedDigit())
                        .foregroundStyle(self.palette.pine),
                    at: center,
                    anchor: .center
                )
            }
        }
    }
}


private struct NightingaleRoseChartView: View {
    
    let metrics: BusynessMetrics
    let palette: DashPalette
    let detailed: Bool
    var onHoverDetail: ((String?) -> Void)? = nil
    
    @State private var hoveredSliceIndex: Int?
    @State private var reveal: CGFloat = DashMotion.isReducedMotion ? 1.0 : 0.0
    
    
    var body: some View {
        GeometryReader { geo in
            NightingaleRoseCanvas(
                metrics: self.metrics,
                palette: self.palette,
                detailed: self.detailed,
                hoveredSliceIndex: self.hoveredSliceIndex,
                reveal: self.reveal
            )
            .onAppear {
                guard self.reveal < 1.0 else { return }
                withAnimation(DashMotion.resolve(DashMotion.chartReveal.delay(self.detailed ? 0.02 : 0.10))) {
                    self.reveal = 1.0
                }
            }
            .onContinuousHover { phase in
                guard self.detailed else { return }
                let nextIdx: Int? = switch phase {
                    case .active(let loc):
                        self.hitTestPetal(loc, in: geo.size)
                    case .ended:
                        nil
                }
                if nextIdx != self.hoveredSliceIndex {
                    withAnimation(DashMotion.resolve(DashMotion.quick)) {
                        self.hoveredSliceIndex = nextIdx
                    }
                    if let idx = nextIdx, idx < self.metrics.slices.count {
                        let slice = self.metrics.slices[idx]
                        self.onHoverDetail?("\(slice.label) · \(slice.rawChars.formatted()) 字 · \(slice.rawAIRequests) 次 AI")
                    } else {
                        self.onHoverDetail?(nil)
                    }
                }
            }
        }
    }
    
    
    private func hitTestPetal(_ point: CGPoint, in size: CGSize) -> Int? {
        let center = CGPoint(x: size.width * 0.5, y: size.height * 0.5)
        let dx = point.x - center.x
        let dy = point.y - center.y
        let dist = hypot(dx, dy)
        let outerLimit = max(14, min(size.width, size.height) * 0.5 - 24)
        let innerR = max(22, outerLimit * 0.28)
        guard dist >= innerR && dist <= outerLimit else { return nil }
        var angle = atan2(dy, dx) * 180.0 / .pi + 90.0
        if angle < 0 { angle += 360.0 }
        let idx = Int(floor(angle / (360.0 / Double(max(1, self.metrics.slices.count)))))
        return min(max(0, idx), max(0, self.metrics.slices.count - 1))
    }
}


// MARK: - Chart 4: 3-Column Sankey Flow Diagram (心境流向)

struct EmotionSankeyChartView: View {
    
    let snapshot: DashboardSnapshot
    let palette: DashPalette
    let detailed: Bool
    var onHoverDetail: ((String?) -> Void)? = nil
    
    @State private var hoveredHit: SankeyHit?
    @State private var reveal: CGFloat = DashMotion.isReducedMotion ? 1.0 : 0.0
    
    fileprivate struct SankeyNode {
        let label: String
        let shortLabel: String
        let weight: Double
        let color: Color
    }
    
    fileprivate struct SankeyHit: Equatable {
        let column: Int
        let index: Int
        let caption: String
    }
    
    
    var body: some View {
        let col1Nodes = self.leftTimeSlotNodes()
        let col2Nodes = self.middleMoodNodes()
        let col3Nodes = self.rightSubMoodNodes()
        
        GeometryReader { geo in
            EmotionSankeyCanvas(
                col1Nodes: col1Nodes,
                col2Nodes: col2Nodes,
                col3Nodes: col3Nodes,
                palette: self.palette,
                detailed: self.detailed,
                hoveredHit: self.hoveredHit,
                reveal: self.reveal
            )
            .onAppear {
                guard self.reveal < 1.0 else { return }
                withAnimation(DashMotion.resolve(DashMotion.chartReveal.delay(self.detailed ? 0.02 : 0.14))) {
                    self.reveal = 1.0
                }
            }
            .onContinuousHover { phase in
                guard self.detailed else { return }
                let nextHit: SankeyHit? = switch phase {
                    case .active(let loc):
                        self.hitTestColumn(
                            loc,
                            in: geo.size,
                            col1: col1Nodes,
                            col2: col2Nodes,
                            col3: col3Nodes
                        )
                    case .ended:
                        nil
                }
                if nextHit != self.hoveredHit {
                    withAnimation(DashMotion.resolve(DashMotion.quick)) {
                        self.hoveredHit = nextHit
                    }
                    self.onHoverDetail?(nextHit?.caption)
                }
            }
        }
    }
    
    
    struct TimeSlotDescriptor: Equatable {
        let label: String
        let shortLabel: String
        let weight: Double
        let toneSlot: Int
    }
    
    
    /// Builds real-time-aware mood-flow time slots up to `currentHour` (0...23) so future periods
    /// (such as "夜间" or "午后" in the morning) never appear before they happen.
    static func timeSlotDescriptors(
        slices: [BusynessHourSlice],
        currentHour: Int
    ) -> [TimeSlotDescriptor] {
        let hour = min(23, max(0, currentHour))
        
        func sliceWeight(hourRange: Range<Int>) -> Double {
            var sum = 0.0
            for slice in slices {
                let startH = slice.index * 2
                let endH = startH + 2
                if endH > hourRange.lowerBound && startH < hourRange.upperBound {
                    sum += max(0.05, slice.intensity)
                }
            }
            return max(1.0, sum * 100.0)
        }
        
        if hour < 6 {
            return [
                TimeSlotDescriptor(label: "凌晨", shortLabel: "凌", weight: sliceWeight(hourRange: 0..<6), toneSlot: 2),
            ]
        } else if hour < 9 {
            return [
                TimeSlotDescriptor(label: "清晨", shortLabel: "晨", weight: sliceWeight(hourRange: 6..<9), toneSlot: 0),
            ]
        } else if hour < 12 {
            return [
                TimeSlotDescriptor(label: "清晨", shortLabel: "晨", weight: sliceWeight(hourRange: 6..<9), toneSlot: 0),
                TimeSlotDescriptor(label: "上午", shortLabel: "上", weight: sliceWeight(hourRange: 9..<12), toneSlot: 1),
            ]
        } else if hour < 18 {
            return [
                TimeSlotDescriptor(label: "晨间", shortLabel: "晨", weight: sliceWeight(hourRange: 6..<12), toneSlot: 0),
                TimeSlotDescriptor(label: "午后", shortLabel: "午", weight: sliceWeight(hourRange: 12..<18), toneSlot: 1),
            ]
        } else {
            return [
                TimeSlotDescriptor(label: "晨间", shortLabel: "晨", weight: sliceWeight(hourRange: 6..<12), toneSlot: 0),
                TimeSlotDescriptor(label: "午后", shortLabel: "午", weight: sliceWeight(hourRange: 12..<18), toneSlot: 1),
                TimeSlotDescriptor(label: "夜间", shortLabel: "夜", weight: sliceWeight(hourRange: 18..<24), toneSlot: 2),
            ]
        }
    }
    
    
    private func leftTimeSlotNodes(now: Date = Date()) -> [SankeyNode] {
        let currentHour = Calendar.current.component(.hour, from: now)
        let descriptors = Self.timeSlotDescriptors(slices: self.snapshot.busyness.slices, currentHour: currentHour)
        return descriptors.map { d in
            let col: Color = switch d.toneSlot {
                case 0: self.palette.mint
                case 1: self.palette.accentFill
                default: self.palette.emerald
            }
            return SankeyNode(label: d.label, shortLabel: d.shortLabel, weight: d.weight, color: col)
        }
    }
    
    
    private func middleMoodNodes() -> [SankeyNode] {
        let segs = Array(self.snapshot.mood.segments.prefix(self.detailed ? 4 : 3))
        guard !segs.isEmpty else {
            return [
                SankeyNode(label: "沉稳", shortLabel: "沉稳", weight: 45, color: self.palette.accentFill),
                SankeyNode(label: "专注", shortLabel: "专注", weight: 35, color: self.palette.mint),
                SankeyNode(label: "松弛", shortLabel: "松弛", weight: 20, color: self.palette.paleMint),
            ]
        }
        return segs.map { seg in
            SankeyNode(
                label: seg.label,
                shortLabel: String(seg.label.prefix(2)),
                weight: max(1, seg.weight),
                color: self.palette.toneColor(for: seg.tone)
            )
        }
    }
    
    
    private func rightSubMoodNodes() -> [SankeyNode] {
        var collected: [SankeyNode] = []
        for seg in self.snapshot.mood.segments {
            let baseColor = self.palette.toneColor(for: seg.tone)
            for child in seg.children.prefix(2) {
                collected.append(SankeyNode(
                    label: child.label,
                    shortLabel: String(child.label.prefix(2)),
                    weight: max(1, child.value),
                    color: baseColor.opacity(0.82)
                ))
            }
        }
        if !collected.isEmpty {
            return Array(collected.sorted { $0.weight > $1.weight }.prefix(self.detailed ? 4 : 3))
        }
        return [
            SankeyNode(label: "心流", shortLabel: "心流", weight: 42, color: self.palette.accentFill),
            SankeyNode(label: "克制", shortLabel: "克制", weight: 33, color: self.palette.mint),
            SankeyNode(label: "愉悦", shortLabel: "愉悦", weight: 25, color: self.palette.heat(2)),
        ]
    }
    
    
    private func hitTestColumn(
        _ point: CGPoint,
        in size: CGSize,
        col1: [SankeyNode],
        col2: [SankeyNode],
        col3: [SankeyNode]
    ) -> SankeyHit? {
        let third = size.width / 3.0
        let nodes: [SankeyNode]
        let prefix: String
        let column: Int
        if point.x < third {
            nodes = col1
            prefix = "时段"
            column = 0
        } else if point.x < third * 2 {
            nodes = col2
            prefix = "心境"
            column = 1
        } else {
            nodes = col3
            prefix = "状态"
            column = 2
        }
        let topHeaderH: CGFloat = 22
        let padBottom: CGFloat = 8
        let innerH = max(30, size.height - topHeaderH - padBottom)
        let laid = Self.layoutColumn(nodes: nodes, x: 0, yStart: topHeaderH, height: innerH, width: 10, gap: 8)
        let total = max(1.0, nodes.reduce(0.0) { $0 + $1.weight })
        for (idx, pair) in zip(nodes, laid).enumerated() {
            let (node, layout) = pair
            if point.y >= layout.rect.minY - 3 && point.y <= layout.rect.maxY + 3 {
                let pct = Int(((node.weight / total) * 100).rounded())
                return SankeyHit(column: column, index: idx, caption: "\(prefix) · \(node.label) (\(pct)%)")
            }
        }
        return nil
    }
    
    
    fileprivate static func layoutColumn(
        nodes: [SankeyNode],
        x: CGFloat,
        yStart: CGFloat,
        height: CGFloat,
        width: CGFloat,
        gap: CGFloat
    ) -> [(rect: CGRect, color: Color, weight: Double)] {
        let totalGap = CGFloat(max(0, nodes.count - 1)) * gap
        let usableH = max(12, height - totalGap)
        let minNodeH: CGFloat = nodes.isEmpty ? 0 : min(6, usableH / CGFloat(nodes.count))
        let leftoverH = max(0, usableH - minNodeH * CGFloat(nodes.count))
        let sumW = max(1.0, nodes.reduce(0.0) { $0 + $1.weight })
        
        var cursorY = yStart
        var result: [(rect: CGRect, color: Color, weight: Double)] = []
        for node in nodes {
            let h = minNodeH + leftoverH * CGFloat(node.weight / sumW)
            let rect = CGRect(x: x, y: cursorY, width: width, height: h)
            result.append((rect, node.color, node.weight))
            cursorY += h + gap
        }
        return result
    }
    
    
    fileprivate static func drawFlows(
        context: inout GraphicsContext,
        sources: [(rect: CGRect, color: Color, weight: Double)],
        targets: [(rect: CGRect, color: Color, weight: Double)],
        highlightedSourceIndex: Int? = nil,
        highlightedTargetIndex: Int? = nil,
        hasAnyHover: Bool = false
    ) {
        let totalTarget = max(1.0, targets.reduce(0.0) { $0 + $1.weight })
        let totalSource = max(1.0, sources.reduce(0.0) { $0 + $1.weight })
        var targetOffsets = targets.map { $0.rect.minY }
        
        for (sIdx, src) in sources.enumerated() {
            var srcOffsetY = src.rect.minY
            for (tIdx, tgt) in targets.enumerated() {
                let share = tgt.weight / totalTarget
                let ribbonSrcH = src.rect.height * CGFloat(share)
                let ribbonTgtH = tgt.rect.height * CGFloat(src.weight / totalSource)
                
                let sTop = srcOffsetY
                let sBot = srcOffsetY + ribbonSrcH
                let tTop = targetOffsets[tIdx]
                let tBot = targetOffsets[tIdx] + ribbonTgtH
                
                srcOffsetY = sBot
                targetOffsets[tIdx] = tBot
                
                let startX = src.rect.maxX
                let endX = tgt.rect.minX
                let ctrlX1 = startX + (endX - startX) * 0.45
                let ctrlX2 = endX - (endX - startX) * 0.45
                
                var ribbon = Path()
                ribbon.move(to: CGPoint(x: startX, y: sTop))
                ribbon.addCurve(
                    to: CGPoint(x: endX, y: tTop),
                    control1: CGPoint(x: ctrlX1, y: sTop),
                    control2: CGPoint(x: ctrlX2, y: tTop)
                )
                ribbon.addLine(to: CGPoint(x: endX, y: tBot))
                ribbon.addCurve(
                    to: CGPoint(x: startX, y: sBot),
                    control1: CGPoint(x: ctrlX2, y: tBot),
                    control2: CGPoint(x: ctrlX1, y: sBot)
                )
                ribbon.closeSubpath()
                
                let isEmphasized = (highlightedSourceIndex == sIdx) || (highlightedTargetIndex == tIdx)
                let srcAlpha: Double = !hasAnyHover ? 0.36 : (isEmphasized ? 0.56 : 0.14)
                let tgtAlpha: Double = !hasAnyHover ? 0.28 : (isEmphasized ? 0.44 : 0.10)
                
                context.fill(
                    ribbon,
                    with: .linearGradient(
                        Gradient(colors: [
                            src.color.opacity(srcAlpha),
                            tgt.color.opacity(tgtAlpha),
                        ]),
                        startPoint: CGPoint(x: startX, y: sTop),
                        endPoint: CGPoint(x: endX, y: tTop)
                    )
                )
            }
        }
    }
}


private struct EmotionSankeyCanvas: View, Animatable {
    
    let col1Nodes: [EmotionSankeyChartView.SankeyNode]
    let col2Nodes: [EmotionSankeyChartView.SankeyNode]
    let col3Nodes: [EmotionSankeyChartView.SankeyNode]
    let palette: DashPalette
    let detailed: Bool
    let hoveredHit: EmotionSankeyChartView.SankeyHit?
    var reveal: CGFloat
    
    var animatableData: CGFloat {
        get { self.reveal }
        set { self.reveal = newValue }
    }
    
    
    var body: some View {
        let progress = max(0.0, min(1.0, self.reveal))
        let hasHover = (self.hoveredHit != nil)
        
        Canvas { context, size in
            guard size.width.isFinite, size.height.isFinite,
                  size.width > 8, size.height > 8 else { return }
            let leftMargin: CGFloat = self.detailed ? 72 : 20
            let rightMargin: CGFloat = self.detailed ? 82 : 30
            let topHeaderH: CGFloat = self.detailed ? 22 : 4
            let padBottom: CGFloat = self.detailed ? 8 : 4
            let nodeW: CGFloat = self.detailed ? 10 : 6
            let innerW = max(36, size.width - leftMargin - rightMargin)
            let innerH = max(30, size.height - topHeaderH - padBottom)
            
            let col1X = leftMargin
            let col2X = leftMargin + innerW * 0.5 - nodeW * 0.5
            let col3X = leftMargin + innerW - nodeW
            
            if self.detailed {
                let headerStyle = Font.system(size: 10.5, weight: .medium)
                let headerColor = self.palette.mutedInk
                context.draw(Text("时段").font(headerStyle).foregroundStyle(headerColor), at: CGPoint(x: col1X + nodeW * 0.5, y: 8), anchor: .center)
                context.draw(Text("状态").font(headerStyle).foregroundStyle(headerColor), at: CGPoint(x: col3X + nodeW * 0.5, y: 8), anchor: .center)
            }
            
            let gap: CGFloat = self.detailed ? 8 : 4
            let rects1 = EmotionSankeyChartView.layoutColumn(nodes: self.col1Nodes, x: col1X, yStart: topHeaderH, height: innerH, width: nodeW, gap: gap)
            let rects2 = EmotionSankeyChartView.layoutColumn(nodes: self.col2Nodes, x: col2X, yStart: topHeaderH, height: innerH, width: nodeW, gap: gap)
            let rects3 = EmotionSankeyChartView.layoutColumn(nodes: self.col3Nodes, x: col3X, yStart: topHeaderH, height: innerH, width: nodeW, gap: gap)
            
            let flowClipW = progress >= 0.999 ? size.width : (col1X + (col3X + nodeW - col1X) * progress)
            context.drawLayer { flowCtx in
                flowCtx.clip(to: Path(CGRect(x: 0, y: 0, width: flowClipW, height: size.height)))
                EmotionSankeyChartView.drawFlows(
                    context: &flowCtx,
                    sources: rects1,
                    targets: rects2,
                    highlightedSourceIndex: self.hoveredHit?.column == 0 ? self.hoveredHit?.index : nil,
                    highlightedTargetIndex: self.hoveredHit?.column == 1 ? self.hoveredHit?.index : nil,
                    hasAnyHover: hasHover
                )
                EmotionSankeyChartView.drawFlows(
                    context: &flowCtx,
                    sources: rects2,
                    targets: rects3,
                    highlightedSourceIndex: self.hoveredHit?.column == 1 ? self.hoveredHit?.index : nil,
                    highlightedTargetIndex: self.hoveredHit?.column == 2 ? self.hoveredHit?.index : nil,
                    hasAnyHover: hasHover
                )
            }
            
            let sum1 = max(1.0, self.col1Nodes.reduce(0.0) { $0 + $1.weight })
            let sum3 = max(1.0, self.col3Nodes.reduce(0.0) { $0 + $1.weight })
            
            let col1Alpha = min(1.0, max(0.0, Double(progress / 0.35)))
            let col2Alpha = min(1.0, max(0.0, Double((progress - 0.25) / 0.40)))
            let col3Alpha = min(1.0, max(0.0, Double((progress - 0.55) / 0.45)))
            
            for (idx, pair) in zip(self.col1Nodes, rects1).enumerated() {
                let (node, layout) = pair
                let isNodeHover = (self.hoveredHit?.column == 0 && self.hoveredHit?.index == idx)
                let dim = (hasHover && self.hoveredHit?.column == 0 && !isNodeHover) ? 0.45 : 1.0
                let nodePath = RoundedRectangle(cornerRadius: 2.5, style: .continuous).path(in: layout.rect)
                context.fill(nodePath, with: .color(node.color.opacity(col1Alpha * dim)))
                if isNodeHover {
                    context.stroke(nodePath, with: .color(self.palette.pine), lineWidth: 1.2)
                }
                if self.detailed {
                    let pct = Int(((node.weight / sum1) * 100).rounded())
                    context.draw(
                        Text("\(node.label) \(pct)%")
                            .font(.system(size: 10.5, weight: isNodeHover ? .bold : .medium).monospacedDigit())
                            .foregroundStyle(self.palette.pine.opacity((isNodeHover ? 1.0 : 0.86) * col1Alpha)),
                        at: CGPoint(x: layout.rect.minX - 6, y: layout.rect.midY),
                        anchor: .trailing
                    )
                } else if layout.rect.height >= 10 {
                    context.draw(
                        Text(node.shortLabel)
                            .font(.system(size: 9.5, weight: .medium))
                            .foregroundStyle(self.palette.secondaryInk.opacity(col1Alpha)),
                        at: CGPoint(x: layout.rect.minX - 4, y: layout.rect.midY),
                        anchor: .trailing
                    )
                }
            }
            
            for (idx, pair) in zip(self.col2Nodes, rects2).enumerated() {
                let (node, layout) = pair
                let isNodeHover = (self.hoveredHit?.column == 1 && self.hoveredHit?.index == idx)
                let dim = (hasHover && self.hoveredHit?.column == 1 && !isNodeHover) ? 0.45 : 1.0
                let nodePath = RoundedRectangle(cornerRadius: 2.5, style: .continuous).path(in: layout.rect)
                context.fill(nodePath, with: .color(node.color.opacity(col2Alpha * dim)))
                if isNodeHover {
                    context.stroke(nodePath, with: .color(self.palette.pine), lineWidth: 1.2)
                }
            }
            
            for (idx, pair) in zip(self.col3Nodes, rects3).enumerated() {
                let (node, layout) = pair
                let isNodeHover = (self.hoveredHit?.column == 2 && self.hoveredHit?.index == idx)
                let dim = (hasHover && self.hoveredHit?.column == 2 && !isNodeHover) ? 0.45 : 1.0
                let nodePath = RoundedRectangle(cornerRadius: 2.5, style: .continuous).path(in: layout.rect)
                context.fill(nodePath, with: .color(node.color.opacity(col3Alpha * dim)))
                if isNodeHover {
                    context.stroke(nodePath, with: .color(self.palette.pine), lineWidth: 1.2)
                }
                if self.detailed {
                    let pct = Int(((node.weight / sum3) * 100).rounded())
                    context.draw(
                        Text("\(node.label) \(pct)%")
                            .font(.system(size: 10.5, weight: isNodeHover ? .bold : .medium).monospacedDigit())
                            .foregroundStyle(self.palette.pine.opacity((isNodeHover ? 1.0 : 0.86) * col3Alpha)),
                        at: CGPoint(x: layout.rect.maxX + 6, y: layout.rect.midY),
                        anchor: .leading
                    )
                } else if layout.rect.height >= 10 {
                    context.draw(
                        Text(node.shortLabel)
                            .font(.system(size: 9.5, weight: .medium))
                            .foregroundStyle(self.palette.secondaryInk.opacity(col3Alpha)),
                        at: CGPoint(x: layout.rect.maxX + 4, y: layout.rect.midY),
                        anchor: .leading
                    )
                }
            }
        }
    }
}


// MARK: - Supporting Components (Card Surface, Press Style & Refresh Motion)

private struct DashboardCardButtonStyle: ButtonStyle {
    
    var pressedScale: CGFloat = 0.995
    
    func makeBody(configuration: Configuration) -> some View {
        let clampedScale = max(0.985, self.pressedScale)
        configuration.label
            .scaleEffect(configuration.isPressed && !DashMotion.isReducedMotion ? clampedScale : 1.0)
            .opacity(configuration.isPressed ? 0.92 : 1.0)
            .animation(DashMotion.resolve(DashMotion.press), value: configuration.isPressed)
    }
}


private struct DashboardRefreshIconButton: View {
    
    let isRefreshing: Bool
    let palette: DashPalette
    let action: () -> Void
    
    @State private var isHovered = false
    @State private var spinAngle: Double = 0
    
    
    var body: some View {
        Button(action: self.action) {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(
                    self.isRefreshing || self.isHovered
                        ? self.palette.accentFill
                        : self.palette.secondaryInk
                )
                .rotationEffect(.degrees(self.spinAngle))
                .frame(width: 24, height: 24)
                .background(
                    (self.isHovered && !self.isRefreshing ? self.palette.insetHover : self.palette.inset),
                    in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                )
                .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(DashboardCardButtonStyle(pressedScale: 0.92))
        .pointerStyle(.link)
        .disabled(self.isRefreshing)
        .onHover { hovering in
            guard hovering != self.isHovered else { return }
            withAnimation(DashMotion.resolve(DashMotion.quick)) {
                self.isHovered = hovering
            }
        }
        .onAppear {
            self.syncSpinState(self.isRefreshing)
        }
        .onChange(of: self.isRefreshing) { _, refreshing in
            self.syncSpinState(refreshing)
        }
    }
    
    
    private func syncSpinState(_ refreshing: Bool) {
        if refreshing {
            guard !DashMotion.isReducedMotion else { return }
            self.spinAngle = 0
            withAnimation(.linear(duration: 0.9).repeatForever(autoreverses: false)) {
                self.spinAngle = 360
            }
        } else {
            withAnimation(DashMotion.resolve(DashMotion.quick)) {
                self.spinAngle = 0
            }
        }
    }
}


private extension View {
    
    func dashboardCardSurface(
        palette: DashPalette,
        cornerRadius: CGFloat = 16,
        isHighlighted: Bool = false,
        showsShadow: Bool = true,
        overPhoto: Bool = false
    ) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        let isDark = palette.tokens.isDark
        let shadowColor = showsShadow && !overPhoto
            ? Color.black.opacity(isDark ? 0.18 : 0.032)
            : .clear
        return self
            .background(
                ZStack {
                    if overPhoto {
                        shape
                            .fill(.regularMaterial)
                            .shadow(
                                color: Color.black.opacity(isDark ? 0.22 : 0.07),
                                radius: 10,
                                x: 0,
                                y: 3
                            )
                        shape.fill(palette.card.opacity(isDark ? (isHighlighted ? 0.40 : 0.30) : (isHighlighted ? 0.52 : 0.42)))
                    } else {
                        shape
                            .fill(palette.card)
                            .shadow(
                                color: shadowColor,
                                radius: showsShadow ? 8 : 0,
                                x: 0,
                                y: showsShadow ? 2 : 0
                            )
                        if isHighlighted {
                            shape.fill(isDark ? Color.white.opacity(0.035) : Color.black.opacity(0.018))
                        }
                    }
                }
            )
            .overlay {
                if overPhoto {
                    // Authentic Apple frosted-glass luminous specular rim fusing cleanly with the photo backdrop
                    shape.strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(isDark ? (isHighlighted ? 0.26 : 0.16) : (isHighlighted ? 0.78 : 0.64)),
                                Color.white.opacity(isDark ? 0.04 : 0.16),
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 0.75
                    )
                } else {
                    shape.strokeBorder(
                        isDark
                            ? Color.white.opacity(isHighlighted ? 0.10 : 0.055)
                            : Color.black.opacity(isHighlighted ? 0.075 : 0.04),
                        lineWidth: 0.5
                    )
                }
            }
            .animation(DashMotion.resolve(DashMotion.quick), value: isHighlighted)
    }
}
