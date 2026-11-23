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
import SwiftUI

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
    
    
    static func buildTree(
        events recentAIEvents: [AIUsageEvent],
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
        
        let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? .distantPast
        let events = recentAIEvents.filter { $0.timestamp >= cutoff }
        
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

private enum DashMotion {
    
    static let quick = Animation.timingCurve(0.2, 0, 0, 1, duration: 0.16)
    static let standard = Animation.timingCurve(0.2, 0, 0, 1, duration: 0.24)
    static let sunburst = Animation.timingCurve(0.16, 1, 0.3, 1, duration: 0.58)
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


/// Resolves live editorial palette tokens from `StudioPaletteManager`.
private struct DashPalette: Sendable {
    
    let tokens: StudioColorTokens
    
    @MainActor init(_ scheme: ColorScheme, tokens: StudioColorTokens? = nil) {
        self.tokens = tokens ?? StudioPaletteManager.shared.tokens(isDark: scheme == .dark)
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
            case .warm: Color(red: 0.88, green: 0.56, blue: 0.34)
            case .playful: self.tokens.heat2
        }
    }
}


struct DashboardSnapshot {
    
    struct ChartDay: Identifiable {
        var id: String
        var date: Date
        var typed: Int
        var ai: Int
    }
    
    var snapshotVersion: Int
    var today: DailyWritingStats
    var days14: [ChartDay]
    var trendCurve14: MathematicalTrendCurveEngine.Result
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
        let today = analytics.todayStats
        let series14 = analytics.dailySeries(days: 14)
        
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
        
        let availableYears = analytics.availableHeatmapYears()
        let resolvedYear = availableYears.contains(selectedYear)
            ? selectedYear
            : (availableYears.last ?? Calendar.current.component(.year, from: Date()))
        let yearly = analytics.yearlyHeatmap(year: resolvedYear, trimFutureWeeks: true)
        
        let aiTodayTotals = analytics.aiUsageTotals(forTodayOnly: true)
        let ai30Totals = analytics.aiUsageTotals(forTodayOnly: false, days: 30)
        let models = analytics.modelDistribution(days: 30)
        let features = analytics.featureDistribution(days: 30)
        let sunburstRoot = EvalSunburstLayoutEngine.buildTree(
            events: analytics.recentAIEvents,
            models: models,
            features: features,
            ai30Totals: ai30Totals
        )
        let sunburstIndex = EvalSunburstLayoutEngine.indexByID(sunburstRoot)
        
        return DashboardSnapshot(
            snapshotVersion: version,
            today: today,
            days14: days14,
            trendCurve14: trendCurve14,
            yearlyHeatmap: yearly,
            currentStreak: analytics.currentWritingStreak,
            availableYears: availableYears,
            aiTodayTotals: aiTodayTotals,
            ai30Totals: ai30Totals,
            aiModels: models,
            aiFeatures: features,
            sunburstRoot: sunburstRoot,
            sunburstIndex: sunburstIndex,
            busyness: analytics.busynessMetrics,
            mood: analytics.moodMetrics,
            doneTodayPoints: analytics.doneTodayPoints,
            actionPredictions: analytics.actionPredictions
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
    @State private var studioPalette = StudioPaletteManager.shared
    @State private var profileManager = UserProfileManager.shared
    
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
        DashPalette(
            self.colorScheme,
            tokens: self.studioPalette.tokens(isDark: self.colorScheme == .dark)
        )
    }
    
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [self.palette.canvasTop, self.palette.canvasBottom],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            if self.isNewsWorkspaceOpen {
                DashboardNewsCenterView(
                    newsService: AIHotNewsService.shared,
                    tokens: self.palette.tokens,
                    initialSelectedID: self.activeNewsID,
                    onClose: {
                        withAnimation(DashMotion.standard) {
                            self.isNewsWorkspaceOpen = false
                        }
                    }
                )
                .transition(.opacity.combined(with: .move(edge: .trailing)))
            } else {
                GeometryReader { viewportGeo in
                    let viewH = max(460, viewportGeo.size.height)
                    let pad: CGFloat = self.isEmbeddedInSettings ? 12 : 18
                    let vSpacing: CGFloat = self.isEmbeddedInSettings ? 10 : 12
                    let hSpacing: CGFloat = self.isEmbeddedInSettings ? 10 : 14
                    let heroH: CGFloat = self.isEmbeddedInSettings
                        ? 148
                        : min(206, max(168, (viewH - pad * 2 - vSpacing * 2) * 0.232))
                    let remainingH = max(430, viewH - pad * 2 - vSpacing * 2 - heroH)
                    let row1H: CGFloat = self.isEmbeddedInSettings
                        ? 236
                        : max(276, floor(remainingH * 0.485))
                    let row2H: CGFloat = self.isEmbeddedInSettings
                        ? 226
                        : max(296, remainingH - row1H)
                    
                    ScrollView(.vertical, showsIndicators: true) {
                        if let snapshot = self.snapshot {
                            VStack(alignment: .leading, spacing: vSpacing) {
                                DashboardAchievementHeroBar(
                                    profile: self.profileManager.activeProfile,
                                    avatarImage: self.profileManager.avatarImage(for: self.profileManager.activeProfile),
                                    snapshot: snapshot,
                                    compact: self.isEmbeddedInSettings,
                                    palette: self.palette,
                                    onBack: self.isEmbeddedInSettings ? nil : self.onDismiss
                                )
                                .frame(maxWidth: .infinity)
                                .frame(height: heroH)
                                
                                self.row1Section(snapshot, height: row1H, spacing: hSpacing)
                                self.row2Section(snapshot, height: row2H, spacing: hSpacing)
                            }
                            .padding(pad)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .opacity(self.hasAppeared ? 1 : 0)
                            .offset(y: self.hasAppeared ? 0 : 6)
                        } else {
                            Color.clear.frame(height: 460)
                        }
                    }
                    .transition(.opacity)
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
            _ = await (newsTask, predTask)
        }
        .onChange(of: self.analytics.revision) { _, _ in
            self.scheduleCoalescedRebuild()
        }
        .onChange(of: self.analytics.actionPredictions) { _, _ in
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
    
    private func row1Section(_ snapshot: DashboardSnapshot, height: CGFloat, spacing: CGFloat) -> some View {
        GeometryReader { proxy in
            let usableW = max(320, proxy.size.width - spacing)
            let leftRatio: CGFloat = self.isEmbeddedInSettings ? 0.50 : 0.555
            let leftWidth = floor(usableW * leftRatio)
            let rightWidth = max(160, usableW - leftWidth)
            
            HStack(alignment: .top, spacing: spacing) {
                DashboardHeatmapCard(
                    yearlyHeatmap: snapshot.yearlyHeatmap,
                    today: snapshot.today,
                    days14: snapshot.days14,
                    trendCurve14: snapshot.trendCurve14,
                    currentStreak: snapshot.currentStreak,
                    availableYears: snapshot.availableYears,
                    selectedYear: self.$selectedYear,
                    compact: self.isEmbeddedInSettings,
                    palette: self.palette
                )
                .frame(width: leftWidth, height: height)
                
                self.flippableQuadSection(snapshot, height: height)
                    .frame(width: rightWidth, height: height)
            }
        }
        .frame(height: height)
    }
    
    
    private func flippableQuadSection(_ snapshot: DashboardSnapshot, height: CGFloat) -> some View {
        ZStack {
            if let expanded = self.expandedQuad {
                DashboardExpandedQuadCard(
                    metric: expanded,
                    snapshot: snapshot,
                    palette: self.palette
                ) {
                    withAnimation(DashMotion.standard) {
                        self.expandedQuad = nil
                    }
                }
                .id("expanded-\(expanded.rawValue)")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .transition(.opacity.combined(with: .scale(scale: 0.97)))
            } else {
                let vGap: CGFloat = self.isEmbeddedInSettings ? 10 : 12
                let hGap: CGFloat = self.isEmbeddedInSettings ? 10 : 12
                let topH = max(86, floor((height - vGap) * 0.50))
                let botH = max(84, height - vGap - topH)
                
                VStack(spacing: vGap) {
                    DashboardAIUsageWideCard(
                        snapshot: snapshot,
                        palette: self.palette
                    ) {
                        withAnimation(DashMotion.standard) {
                            self.expandedQuad = .aiUsage
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: topH, maxHeight: topH)
                    
                    HStack(spacing: hGap) {
                        self.quadCard(metric: .busyness, snapshot: snapshot)
                            .frame(maxWidth: .infinity, minHeight: botH, maxHeight: botH)
                        self.quadCard(metric: .mood, snapshot: snapshot)
                            .frame(maxWidth: .infinity, minHeight: botH, maxHeight: botH)
                    }
                }
                .id("compact-bento-grid")
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }
        }
        .animation(DashMotion.standard, value: self.expandedQuad)
    }
    
    
    private func quadCard(metric: DashboardQuadMetric, snapshot: DashboardSnapshot) -> some View {
        DashboardCompactQuadCard(
            metric: metric,
            snapshot: snapshot,
            palette: self.palette
        ) {
            withAnimation(DashMotion.standard) {
                self.expandedQuad = metric
            }
        }
    }
    
    
    // MARK: Row 2 — Equal 3-Column Layout (干了啥 / 要干啥 / 交互 NEWS)
    
    private func row2Section(_ snapshot: DashboardSnapshot, height: CGFloat, spacing: CGFloat) -> some View {
        HStack(alignment: .top, spacing: spacing) {
            self.doneTodayColumn(points: snapshot.doneTodayPoints)
                .frame(maxWidth: .infinity, minHeight: height, maxHeight: height, alignment: .topLeading)
            
            self.predictedActionsColumn(predictions: snapshot.actionPredictions)
                .frame(maxWidth: .infinity, minHeight: height, maxHeight: height, alignment: .topLeading)
            
            DashboardNewsColumnCard(
                compact: self.isEmbeddedInSettings,
                cardHeight: height,
                palette: self.palette,
                onOpenWorkspace: { selectedID in
                    self.openNewsWorkspace(selecting: selectedID)
                }
            )
            .frame(maxWidth: .infinity, minHeight: height, maxHeight: height, alignment: .topLeading)
        }
    }
    
    
    private func doneTodayColumn(points: [String]) -> some View {
        let tint = self.palette.accentFill
        return VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(self.palette.emerald)
                
                Text("干了啥")
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(self.palette.pine)
                
                Spacer()
            }
            .frame(height: 22)
            
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 8) {
                    if points.isEmpty {
                        Image(systemName: "checkmark.seal")
                            .font(.system(size: 18, weight: .light))
                            .foregroundStyle(self.palette.pine.opacity(0.24))
                            .frame(maxWidth: .infinity)
                            .padding(.top, 12)
                    } else {
                        ForEach(Array(points.enumerated()), id: \.offset) { idx, point in
                            HStack(alignment: .top, spacing: 8) {
                                Capsule()
                                    .fill(idx == 0 ? self.palette.emerald : self.palette.accentFill.opacity(0.65))
                                    .frame(width: 3, height: 14)
                                    .padding(.top, 2.5)
                                
                                Text(point)
                                    .font(.system(size: 12.5, weight: .regular))
                                    .foregroundStyle(self.palette.pine.opacity(0.90))
                                    .lineSpacing(2)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(tint.opacity(self.palette.tokens.isDark ? 0.11 : 0.06))
                            )
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(self.isEmbeddedInSettings ? 12 : 16)
        .dashboardCardSurface(palette: self.palette, cornerRadius: 18, tintAccent: tint)
    }
    
    
    private func predictedActionsColumn(predictions: [DocumentActionPrediction]) -> some View {
        let todoAccent: Color = self.palette.tokens.isDark
            ? Color(red: 0.96, green: 0.68, blue: 0.32)
            : Color(red: 0.86, green: 0.48, blue: 0.14)
        
        return VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.forward.circle.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(todoAccent)
                
                Text("要干啥")
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(self.palette.pine)
                
                Spacer()
            }
            .frame(height: 22)
            
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 7) {
                    if predictions.isEmpty {
                        Image(systemName: "sparkles")
                            .font(.system(size: 18, weight: .light))
                            .foregroundStyle(todoAccent.opacity(0.35))
                            .frame(maxWidth: .infinity)
                            .padding(.top, 12)
                    } else {
                        ForEach(Array(predictions.enumerated()), id: \.element.id) { idx, pred in
                            HStack(alignment: .center, spacing: 8) {
                                Capsule()
                                    .fill(idx == 0 ? todoAccent : todoAccent.opacity(0.62))
                                    .frame(width: 3, height: 13)
                                
                                Text(pred.action)
                                    .font(.system(size: 12.5, weight: idx == 0 ? .medium : .regular))
                                    .foregroundStyle(self.palette.pine.opacity(0.92))
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding(.horizontal, 10)
                            .frame(height: 32)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(todoAccent.opacity(self.palette.tokens.isDark ? 0.12 : 0.065))
                            )
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(self.isEmbeddedInSettings ? 12 : 16)
        .dashboardCardSurface(palette: self.palette, cornerRadius: 18, tintAccent: todoAccent)
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


/// Isolated NEWS column card so background thumbnail & excerpt downloads never invalidate the parent dashboard tree.
private struct DashboardNewsColumnCard: View {
    
    let compact: Bool
    let cardHeight: CGFloat
    let palette: DashPalette
    let onOpenWorkspace: (String?) -> Void
    
    @State private var newsService = AIHotNewsService.shared
    
    
    var body: some View {
        let pageItems = self.newsService.currentPageItems
        
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Button {
                    self.onOpenWorkspace(pageItems.first?.id)
                } label: {
                    HStack(spacing: 4) {
                        Text("NEWS")
                            .font(.system(size: 13.5, weight: .semibold, design: .rounded))
                            .foregroundStyle(self.palette.pine)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(self.palette.pine.opacity(0.45))
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
                                withAnimation(DashMotion.quick) {
                                    self.newsService.selectedCategory = cat
                                }
                            } label: {
                                Text(cat == .xSocial ? "X" : cat.label)
                                    .font(.system(size: 10, weight: active ? .semibold : .medium))
                                    .foregroundStyle(active ? self.palette.tokens.onAccentInk : self.palette.pine.opacity(0.60))
                                    .padding(.horizontal, 6)
                                    .frame(height: 20)
                                    .background(active ? self.palette.accentFill : Color.clear, in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(2)
                    .background(self.palette.inset, in: Capsule())
                }
                
                Button {
                    Task {
                        await self.newsService.refreshIfNeeded(force: true)
                    }
                } label: {
                    Image(systemName: self.newsService.isLoading ? "hourglass" : "arrow.clockwise")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(self.palette.pine.opacity(0.68))
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(self.palette.inset.opacity(0.85)))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .disabled(self.newsService.isLoading)
            }
            .frame(height: 22)
            
            GeometryReader { geo in
                let useTwoColumns = geo.size.width >= 260
                let rowSpacing: CGFloat = 8
                let canFitThreeRows = useTwoColumns && (geo.size.height >= 262 || self.cardHeight >= 370)
                let targetRows: Int = useTwoColumns ? (canFitThreeRows ? 3 : 2) : 3
                let visibleItems = Array(pageItems.prefix(useTwoColumns ? targetRows * 2 : targetRows))
                let textAndPaddingPerCard: CGFloat = 48
                let adaptiveCoverH: CGFloat = useTwoColumns
                    ? min(104, max(46, floor((geo.size.height - rowSpacing * CGFloat(targetRows - 1)) / CGFloat(targetRows) - textAndPaddingPerCard)))
                    : 46
                let columns: [GridItem] = useTwoColumns
                    ? [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]
                    : [GridItem(.flexible(), spacing: 8)]
                
                ScrollView(.vertical, showsIndicators: false) {
                    if visibleItems.isEmpty {
                        if self.newsService.isLoading {
                            HStack(spacing: 8) {
                                ProgressView()
                                    .controlSize(.small)
                                Text("正在加载资讯")
                                    .font(.system(size: 12))
                                    .foregroundStyle(self.palette.pine.opacity(0.60))
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 6)
                        } else {
                            Button {
                                Task {
                                    await self.newsService.refreshIfNeeded(force: true)
                                }
                            } label: {
                                Label("重新加载", systemImage: "arrow.clockwise")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(self.palette.emerald)
                                    .padding(.horizontal, 10)
                                    .frame(height: 28)
                                    .background(self.palette.accentFill.opacity(0.12), in: Capsule())
                            }
                            .buttonStyle(.plain)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 6)
                        }
                    } else {
                        LazyVGrid(columns: columns, alignment: .leading, spacing: rowSpacing) {
                            ForEach(visibleItems) { item in
                                NewsFeedCoverCard(
                                    item: item,
                                    coverImage: self.newsService.coverImage(for: item),
                                    isBookmarked: self.newsService.isBookmarked(item),
                                    compactRow: !useTwoColumns,
                                    coverHeight: adaptiveCoverH,
                                    palette: self.palette,
                                    onTap: {
                                        self.onOpenWorkspace(item.id)
                                    },
                                    onToggleBookmark: {
                                        self.newsService.toggleBookmark(item)
                                    }
                                )
                            }
                        }
                        .id("news-mixed-page-\(self.newsService.currentPage)-\(self.newsService.selectedCategory.rawValue)")
                    }
                }
            }
            
            if !self.newsService.filteredItems.isEmpty {
                HStack(spacing: 8) {
                    Button {
                        withAnimation(DashMotion.quick) {
                            self.newsService.goToPreviousPage()
                        }
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 9.5, weight: .semibold))
                            Text("上一页")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundStyle(self.newsService.totalPages > 1 ? self.palette.pine.opacity(0.75) : self.palette.pine.opacity(0.28))
                        .padding(.horizontal, 8)
                        .frame(height: 24)
                        .background(self.palette.inset, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(self.newsService.totalPages <= 1)
                    
                    Spacer()
                    
                    Button {
                        self.onOpenWorkspace(pageItems.first?.id)
                    } label: {
                        Text("进入阅读器")
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(self.palette.emerald)
                    }
                    .buttonStyle(.plain)
                    .pointerStyle(.link)
                    
                    Spacer()
                    
                    Button {
                        if self.newsService.totalPages > 1 {
                            withAnimation(DashMotion.quick) {
                                self.newsService.goToNextPage()
                            }
                        } else {
                            Task {
                                await self.newsService.refreshIfNeeded(force: true)
                            }
                        }
                    } label: {
                        HStack(spacing: 3) {
                            Text(self.newsService.currentPage >= self.newsService.totalPages ? "换一批" : "下一页")
                                .font(.system(size: 11, weight: .medium))
                            Image(systemName: self.newsService.currentPage >= self.newsService.totalPages ? "arrow.clockwise" : "chevron.right")
                                .font(.system(size: 9.5, weight: .semibold))
                        }
                        .foregroundStyle(self.palette.emerald)
                        .padding(.horizontal, 8)
                        .frame(height: 24)
                        .background(self.palette.accentFill.opacity(0.12), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 2)
            }
        }
        .padding(self.compact ? 12 : 16)
        .dashboardCardSurface(palette: self.palette, cornerRadius: 18)
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
        var width: CGFloat = 28
        for ch in text {
            if ch.isASCII {
                width += (ch == " " ? 4.0 : 7.0)
            } else {
                width += 11.8
            }
        }
        return CGSize(width: min(176, max(58, width.rounded(.up))), height: 24)
    }
    
    
    static func placements(
        canvasSize: CGSize,
        cardRect: CGRect,
        reservedTopLeftRect: CGRect,
        items: [Item],
        elapsed: TimeInterval
    ) -> [Placement] {
        guard canvasSize.width > 120, canvasSize.height > 60, !items.isEmpty else { return [] }
        
        let protectedCard = cardRect.insetBy(dx: -18, dy: -10)
        let protectedBack = reservedTopLeftRect.isEmpty ? .zero : reservedTopLeftRect.insetBy(dx: -12, dy: -8)
        
        let lanePitch: CGFloat = 31
        let topPad: CGFloat = 8
        let botPad: CGFloat = 8
        let usableH = max(lanePitch, canvasSize.height - topPad - botPad)
        let laneCount = max(2, min(5, Int(usableH / lanePitch)))
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
        let fadeMargin: CGFloat = 26
        
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
                
                let centerY = startY + CGFloat(lane) * lanePitch
                let laneTop = centerY - 12
                let laneBottom = centerY + 12
                
                var laneMinX = baseMinX
                let laneMaxX = baseMaxX
                
                if wing == .left, !protectedBack.isEmpty {
                    let intersectsBackY = laneBottom > protectedBack.minY && laneTop < protectedBack.maxY
                    if intersectsBackY {
                        laneMinX = max(laneMinX, protectedBack.maxX)
                    }
                }
                
                let spanW = laneMaxX - laneMinX
                guard spanW >= 92 else { continue }
                
                let validItems = laneItems.filter {
                    Self.estimatedPillSize(for: $0.text).width <= spanW - 10
                }
                guard !validItems.isEmpty else { continue }
                
                let maxW = validItems.map { Self.estimatedPillSize(for: $0.text).width }.max() ?? 100
                let slotStep = maxW + 30
                let cycleLen = max(spanW + maxW + 36, CGFloat(validItems.count) * slotStep)
                let speed = 17.5 + CGFloat(lane % 3) * 4.0 + (wing == .right ? 1.5 : 0)
                let phaseModulo = Int(max(120, spanW * 0.72))
                let phaseOffset = CGFloat((lane * 97 + (wing == .left ? 110 : 75)) % phaseModulo)
                
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
                    
                    let rect = CGRect(x: minX, y: centerY - size.height * 0.5, width: size.width, height: size.height)
                    guard !rect.intersects(protectedCard) else { continue }
                    if !protectedBack.isEmpty, rect.intersects(protectedBack) { continue }
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
        
        scheduleWing(.left, buckets: leftBuckets, baseMinX: 6, baseMaxX: protectedCard.minX, flowRightward: false)
        scheduleWing(.right, buckets: rightBuckets, baseMinX: protectedCard.maxX, baseMaxX: canvasSize.width - 6, flowRightward: true)
        
        return results
    }
}


private struct DashboardAchievementHeroBar: View {
    
    let profile: UserProfile
    let avatarImage: NSImage?
    let snapshot: DashboardSnapshot
    let compact: Bool
    let palette: DashPalette
    let onBack: (() -> Void)?
    
    @State private var passStyleIndex: Int
    @State private var serialCode: String
    @State private var hasProLicense: Bool
    @State private var pointerLocation = CGPoint(x: 0.5, y: 0.5)
    @State private var isCardHovered = false
    @State private var isBackHovered = false
    @State private var brandLineEngine = BrandLinePassEngine()
    @State private var startDate = Date()
    
    private static let joinedFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy.MM"
        return f
    }()
    
    
    init(
        profile: UserProfile,
        avatarImage: NSImage?,
        snapshot: DashboardSnapshot,
        compact: Bool,
        palette: DashPalette,
        onBack: (() -> Void)?
    ) {
        self.profile = profile
        self.avatarImage = avatarImage
        self.snapshot = snapshot
        self.compact = compact
        self.palette = palette
        self.onBack = onBack
        
        let db = CotLocalDatabase.shared
        let storedStyle = Int(db.string(forKey: CotLocalDatabase.ConfigKey.cotPassStyleIndex, default: "0")) ?? 0
        var serial = db.string(forKey: CotLocalDatabase.ConfigKey.cotPassSerialCode)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if serial.isEmpty {
            serial = CotPassLicense.generateSerialCode()
            db.set(serial, forKey: CotLocalDatabase.ConfigKey.cotPassSerialCode)
        }
        let key = db.string(forKey: CotLocalDatabase.ConfigKey.cotPassLicenseKey)
        let tier = CotPassLicense.validate(key) ?? .explorer
        
        _passStyleIndex = State(initialValue: storedStyle)
        _serialCode = State(initialValue: serial)
        _hasProLicense = State(initialValue: tier != .explorer)
    }
    
    
    private var danmakuItems: [DashboardHeroDanmakuScheduler.Item] {
        var tags: [UserPersonalityTag] = []
        let todayTotal = self.snapshot.today.typedChars + self.snapshot.today.aiCompletedChars
        if todayTotal > 0 {
            tags.append(UserPersonalityTag(id: "today", label: "今日 \(todayTotal.formatted()) 字", explanation: "", tone: .calm))
        }
        if self.snapshot.currentStreak > 0 {
            tags.append(UserPersonalityTag(id: "streak", label: "连更 \(self.snapshot.currentStreak) 天", explanation: "", tone: .sharp))
        }
        if self.snapshot.yearlyHeatmap.activeDays > 0 {
            tags.append(UserPersonalityTag(id: "active", label: "年活跃 \(self.snapshot.yearlyHeatmap.activeDays) 天", explanation: "", tone: .warm))
        }
        let avg14 = Int(self.snapshot.trendCurve14.averageValue.rounded())
        if avg14 > 0 {
            tags.append(UserPersonalityTag(id: "avg14", label: "日均 \(avg14.formatted()) 字", explanation: "", tone: .playful))
        }
        let peak14 = self.snapshot.days14.map { $0.typed + $0.ai }.max() ?? 0
        if peak14 > 0 {
            tags.append(UserPersonalityTag(id: "peak", label: "峰值 \(peak14.formatted()) 字", explanation: "", tone: .calm))
        }
        let typed14 = self.snapshot.days14.reduce(0) { $0 + $1.typed }
        let ai14 = self.snapshot.days14.reduce(0) { $0 + $1.ai }
        let sum14 = typed14 + ai14
        if sum14 > 0 {
            let handRatio = Double(typed14) / Double(sum14)
            tags.append(UserPersonalityTag(
                id: "style",
                label: handRatio >= 0.65 ? "手写心流派" : "AI 协创家",
                explanation: "",
                tone: .sharp
            ))
        }
        tags.append(UserPersonalityTag(
            id: "pass-tier",
            label: self.hasProLicense ? "PRO 典藏通行" : "COLLECTOR PASS",
            explanation: "",
            tone: self.hasProLicense ? .warm : .calm
        ))
        let moodLabel = self.snapshot.mood.dominantLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        if !moodLabel.isEmpty {
            tags.append(UserPersonalityTag(id: "mood", label: moodLabel, explanation: "", tone: .playful))
        }
        if sum14 >= 8000 {
            tags.append(UserPersonalityTag(id: "prolific", label: "高产创作者", explanation: "", tone: .warm))
        }
        if self.snapshot.yearlyHeatmap.activeDays >= 60 {
            tags.append(UserPersonalityTag(id: "steady", label: "长期主义者", explanation: "", tone: .playful))
        }
        
        let deduped = UserPersonalityAnalyzer.deduplicatedTags(tags, maxCount: 10)
        return deduped.map {
            DashboardHeroDanmakuScheduler.Item(id: $0.id, text: $0.label, tone: $0.tone)
        }
    }
    
    
    var body: some View {
        let theme = CotPassTheme.resolve(index: self.passStyleIndex)
        let joinedText = Self.joinedFormatter.string(from: self.profile.createdAt)
        let statusText = self.hasProLicense ? "PRO" : "ACTIVE"
        let accessText = "\(max(1, self.snapshot.currentStreak))D"
        let items = self.danmakuItems
        
        GeometryReader { heroGeo in
            let nativeW: CGFloat = 408
            let nativeH: CGFloat = 246
            let cardScale = min(0.86, max(0.56, (heroGeo.size.height - 6) / nativeH))
            let cardW = nativeW * cardScale
            let cardH = nativeH * cardScale
            let cardRect = CGRect(
                x: (heroGeo.size.width - cardW) * 0.5,
                y: (heroGeo.size.height - cardH) * 0.5,
                width: cardW,
                height: cardH
            )
            let reservedBackRect: CGRect = self.onBack != nil
                ? CGRect(x: 0, y: 0, width: 110, height: 36)
                : .zero
            
            ZStack(alignment: .topLeading) {
                // Flanking achievement danmaku lanes around central PASS sanctuary
                TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
                    let elapsed = max(0, timeline.date.timeIntervalSince(self.startDate))
                    let placements = DashboardHeroDanmakuScheduler.placements(
                        canvasSize: heroGeo.size,
                        cardRect: cardRect,
                        reservedTopLeftRect: reservedBackRect,
                        items: items,
                        elapsed: elapsed
                    )
                    
                    ZStack(alignment: .topLeading) {
                        ForEach(placements) { placement in
                            let toneCol = self.palette.toneColor(for: placement.tone)
                            HStack(spacing: 5) {
                                Circle()
                                    .fill(toneCol)
                                    .frame(width: 5.5, height: 5.5)
                                Text(placement.text)
                                    .font(.system(size: self.compact ? 10.5 : 11.5, weight: .semibold, design: .rounded))
                                    .foregroundStyle(self.palette.pine.opacity(0.86))
                                    .lineLimit(1)
                            }
                            .padding(.horizontal, 10)
                            .frame(width: placement.frame.width, height: placement.frame.height)
                            .background(
                                Capsule()
                                    .fill(self.palette.card.opacity(0.84))
                                    .overlay(
                                        Capsule()
                                            .strokeBorder(toneCol.opacity(0.38), lineWidth: 0.9)
                                    )
                            )
                            .shadow(color: self.palette.cardShadow.opacity(0.55), radius: 5, y: 2)
                            .position(x: placement.frame.midX, y: placement.frame.midY)
                            .opacity(placement.opacity)
                        }
                    }
                    .frame(width: heroGeo.size.width, height: heroGeo.size.height, alignment: .topLeading)
                    .allowsHitTesting(false)
                }
                
                // Centered interactive Collector PASS Card with ambient gallery glow
                ZStack {
                    RadialGradient(
                        colors: [
                            self.palette.accentFill.opacity(self.palette.tokens.isDark ? 0.20 : 0.14),
                            self.palette.mint.opacity(0.06),
                            .clear
                        ],
                        center: .center,
                        startRadius: 20,
                        endRadius: cardW * 0.72
                    )
                    .frame(width: cardW * 1.35, height: heroGeo.size.height)
                    .allowsHitTesting(false)
                    
                    CotPassCardView(
                        theme: theme,
                        profile: self.profile,
                        avatarImage: self.avatarImage,
                        serialCode: self.serialCode,
                        statusText: statusText,
                        joinedText: joinedText,
                        accessText: accessText,
                        specularPoint: UnitPoint(x: self.pointerLocation.x, y: self.pointerLocation.y),
                        pointerLocation: self.pointerLocation,
                        isHovered: self.isCardHovered,
                        brandLineEngine: self.brandLineEngine,
                        cardSize: CGSize(width: nativeW, height: nativeH),
                        statusLabelTitle: "STATUS"
                    )
                    .scaleEffect(cardScale)
                    .frame(width: cardW, height: cardH)
                    .rotation3DEffect(
                        .degrees(self.isCardHovered ? 6.5 : 0),
                        axis: (
                            x: CGFloat(0.5 - self.pointerLocation.y),
                            y: CGFloat(self.pointerLocation.x - 0.5),
                            z: 0
                        ),
                        perspective: 0.55
                    )
                    .contentShape(RoundedRectangle(cornerRadius: 20 * cardScale, style: .continuous))
                    .onContinuousHover { phase in
                        switch phase {
                            case .active(let loc):
                                let nx = min(1, max(0, loc.x / max(1, cardW)))
                                let ny = min(1, max(0, loc.y / max(1, cardH)))
                                self.pointerLocation = CGPoint(x: nx, y: ny)
                                if !self.isCardHovered {
                                    self.isCardHovered = true
                                }
                            case .ended:
                                if self.isCardHovered {
                                    self.isCardHovered = false
                                }
                                self.pointerLocation = CGPoint(x: 0.5, y: 0.5)
                        }
                    }
                    .onTapGesture {
                        withAnimation(DashMotion.standard) {
                            let next = (self.passStyleIndex + 1) % CotPassTheme.allThemes.count
                            self.passStyleIndex = next
                            CotLocalDatabase.shared.set("\(next)", forKey: CotLocalDatabase.ConfigKey.cotPassStyleIndex)
                        }
                    }
                    .pointerStyle(.link)
                }
                .position(x: cardRect.midX, y: cardRect.midY)
                
                // Top-left Back to Editor action
                if let onBack = self.onBack {
                    Button(action: onBack) {
                        HStack(spacing: 5) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(self.isBackHovered ? self.palette.emerald : self.palette.pine.opacity(0.75))
                            
                            Text(AppLanguage.text("返回编辑", en: "Back to Editor"))
                                .font(.system(size: 12.5, weight: .medium))
                                .foregroundStyle(self.palette.pine.opacity(self.isBackHovered ? 0.96 : 0.82))
                        }
                        .padding(.horizontal, 10)
                        .frame(height: 30)
                        .background(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(self.isBackHovered ? self.palette.card : self.palette.card.opacity(0.86))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .strokeBorder(self.isBackHovered ? self.palette.accentFill.opacity(0.45) : self.palette.hairline, lineWidth: 0.75)
                        )
                    }
                    .buttonStyle(.plain)
                    .pointerStyle(.link)
                    .onHover { hovering in
                        if hovering != self.isBackHovered {
                            self.isBackHovered = hovering
                        }
                    }
                    .padding(.top, 2)
                }
            }
        }
    }
}


// MARK: - Unified Writing Telemetry & Yearly Heatmap Card (今日码字 × 热力图 × 数学曲线双向联动)

private struct DashboardHeatmapCard: View {
    
    let yearlyHeatmap: YearlyHeatmapData
    let today: DailyWritingStats
    let days14: [DashboardSnapshot.ChartDay]
    let trendCurve14: MathematicalTrendCurveEngine.Result
    let currentStreak: Int
    let availableYears: [Int]
    @Binding var selectedYear: Int
    let compact: Bool
    let palette: DashPalette
    
    @State private var hoveredHit: HeatmapGridLayout.Hit?
    @State private var hoveredBarDayID: String?
    
    
    private var previousYear: Int? {
        self.availableYears.last { $0 < self.yearlyHeatmap.year }
    }
    
    private var nextYear: Int? {
        self.availableYears.first { $0 > self.yearlyHeatmap.year }
    }
    
    private var activeLinkedDayID: String? {
        self.hoveredBarDayID ?? self.hoveredHit?.cell.id
    }
    
    private var activeReadout: (label: String, total: Int, typed: Int, ai: Int) {
        if let barID = self.hoveredBarDayID,
           let day = self.days14.first(where: { $0.id == barID })
        {
            return (Self.shortDateFormatter.string(from: day.date), day.typed + day.ai, day.typed, day.ai)
        }
        if let cell = self.hoveredHit?.cell {
            return (Self.shortDateFormatter.string(from: cell.date), cell.typedChars + cell.aiCompletedChars, cell.typedChars, cell.aiCompletedChars)
        }
        let total = self.today.typedChars + self.today.aiCompletedChars
        return ("今日码字", total, self.today.typedChars, self.today.aiCompletedChars)
    }
    
    
    var body: some View {
        let readout = self.activeReadout
        let isInspecting = (self.activeLinkedDayID != nil)
        let curve = self.trendCurve14
        
        VStack(alignment: .leading, spacing: self.compact ? 6 : 8) {
            // Top Live-Activity Telemetry Strip
            HStack(alignment: .center, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text(readout.total.formatted())
                            .font(.system(size: self.compact ? 17 : 19, weight: .bold, design: .rounded).monospacedDigit())
                            .foregroundStyle(isInspecting ? self.palette.emerald : self.palette.pine)
                            .contentTransition(.numericText())
                        Text("字")
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(self.palette.pine.opacity(0.48))
                    }
                    
                    if isInspecting {
                        Text(readout.label)
                            .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                            .foregroundStyle(self.palette.pine.opacity(0.72))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2.5)
                            .background(self.palette.inset.opacity(0.90), in: Capsule())
                    }
                }
                
                Spacer(minLength: 4)
                
                if self.currentStreak > 0 {
                    let milestone: Double = self.currentStreak < 7 ? 7 : (self.currentStreak < 30 ? 30 : 100)
                    let fillRatio = min(1.0, max(0.16, Double(self.currentStreak) / milestone))
                    HStack(spacing: 5) {
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(self.palette.inset)
                                .frame(width: 30, height: 4.5)
                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: [self.palette.mint, self.palette.accentFill, self.palette.emerald],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: max(6, 30 * CGFloat(fillRatio)), height: 4.5)
                        }
                        Text("\(self.currentStreak)d")
                            .font(.system(size: 10.5, weight: .semibold, design: .rounded).monospacedDigit())
                            .foregroundStyle(self.palette.emerald)
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2.5)
                    .background(self.palette.accentFill.opacity(0.10), in: Capsule())
                }
                
                HStack(spacing: 2) {
                    Button {
                        if let prev = self.previousYear {
                            self.selectedYear = prev
                        }
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 9.5, weight: .semibold))
                            .foregroundStyle(self.previousYear != nil ? self.palette.pine.opacity(0.75) : self.palette.pine.opacity(0.22))
                            .frame(width: 18, height: 18)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(self.previousYear == nil)
                    
                    Text("\(String(self.yearlyHeatmap.year))")
                        .font(.system(size: 11.5, weight: .semibold, design: .rounded).monospacedDigit())
                        .foregroundStyle(self.palette.pine.opacity(0.86))
                    
                    Button {
                        if let next = self.nextYear {
                            self.selectedYear = next
                        }
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9.5, weight: .semibold))
                            .foregroundStyle(self.nextYear != nil ? self.palette.pine.opacity(0.75) : self.palette.pine.opacity(0.22))
                            .frame(width: 18, height: 18)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(self.nextYear == nil)
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(self.palette.inset.opacity(0.85), in: Capsule())
            }
            
            // Middle: Crisp 1:1 Square Yearly Activity Heatmap
            GeometryReader { geo in
                let layout = HeatmapGridLayout.compute(
                    size: geo.size,
                    weekCount: max(1, self.yearlyHeatmap.weeks.count)
                )
                
                ScrollView(.horizontal, showsIndicators: false) {
                    ZStack(alignment: .topLeading) {
                        Canvas { context, canvasSize in
                            guard canvasSize.width.isFinite, canvasSize.height.isFinite,
                                  canvasSize.width > 10, canvasSize.height > 10 else { return }
                            
                            var lastLabelRightX: CGFloat = -100
                            for marker in self.yearlyHeatmap.monthLabels {
                                let x = layout.gridOriginX + CGFloat(marker.weekIndex) * layout.pitch
                                guard x >= lastLabelRightX + 20 else { continue }
                                lastLabelRightX = x
                                context.draw(
                                    Text("\(marker.month)月")
                                        .font(.system(size: 9, weight: .medium, design: .rounded))
                                        .foregroundStyle(self.palette.pine.opacity(0.45)),
                                    at: CGPoint(x: x, y: layout.gridOriginY - 9),
                                    anchor: .leading
                                )
                            }
                            
                            for (rowIndex, label) in [(0, "一"), (2, "三"), (4, "五")] {
                                let rect = layout.cellRect(col: 0, row: rowIndex)
                                context.draw(
                                    Text(label)
                                        .font(.system(size: 8.5, weight: .regular))
                                        .foregroundStyle(self.palette.pine.opacity(0.40)),
                                    at: CGPoint(x: layout.gridOriginX - 6, y: rect.midY),
                                    anchor: .trailing
                                )
                            }
                            
                            for (colIndex, week) in self.yearlyHeatmap.weeks.enumerated() {
                                for (rowIndex, cell) in week.enumerated() {
                                    guard rowIndex < 7, !cell.isOutOfYear, !cell.isFuture else { continue }
                                    let rect = layout.cellRect(col: colIndex, row: rowIndex)
                                    let path = RoundedRectangle(cornerRadius: layout.cornerRadius, style: .continuous)
                                        .path(in: rect)
                                    let isLinked = (self.activeLinkedDayID == cell.id)
                                    let fillCol = isLinked ? self.palette.emerald : self.palette.heat(cell.level)
                                    context.fill(path, with: .color(fillCol))
                                    
                                    if isLinked {
                                        context.stroke(
                                            path,
                                            with: .color(self.palette.pine.opacity(0.85)),
                                            lineWidth: 1.35
                                        )
                                    }
                                }
                            }
                        }
                        .frame(width: layout.canvasWidth, height: max(layout.canvasHeight, geo.size.height))
                        .onContinuousHover { phase in
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
                        
                        if let hit = self.hoveredHit {
                            self.hoverTooltip(
                                hit: hit,
                                layout: layout,
                                in: CGSize(width: layout.canvasWidth, height: max(layout.canvasHeight, geo.size.height))
                            )
                        }
                    }
                }
                .defaultScrollAnchor(.trailing)
            }
            
            // Bottom: Mathematical C¹ Monotone Hermite Spline + Gaussian Kernel Regression μ ± σ Envelope
            VStack(spacing: 3) {
                GeometryReader { waveGeo in
                    let count = self.days14.count
                    Canvas { context, size in
                        guard size.width > 16, size.height > 14, !curve.samples.isEmpty else { return }
                        let padX: CGFloat = 6
                        let padTop: CGFloat = 6
                        let padBot: CGFloat = 4
                        let plotW = max(10, size.width - padX * 2)
                        let plotH = max(8, size.height - padTop - padBot)
                        let maxV = max(1.0, curve.maxScale)
                        
                        func pt(t: Double, val: Double) -> CGPoint {
                            let x = padX + CGFloat(t) * plotW
                            let y = padTop + plotH * CGFloat(1.0 - min(1.0, max(0.0, val / maxV)))
                            return CGPoint(x: x, y: y)
                        }
                        
                        // Horizontal baseline & mid reference hairlines
                        for frac in [0.5, 1.0] as [CGFloat] {
                            let ry = padTop + plotH * frac
                            var ref = Path()
                            ref.move(to: CGPoint(x: padX, y: ry))
                            ref.addLine(to: CGPoint(x: size.width - padX, y: ry))
                            context.stroke(
                                ref,
                                with: .color(self.palette.hairline),
                                style: StrokeStyle(lineWidth: 0.6, dash: frac < 1 ? [2, 3] : [])
                            )
                        }
                        
                        // 1. Gaussian ±0.65σ confidence envelope corridor
                        var bandPath = Path()
                        for (idx, s) in curve.samples.enumerated() {
                            let p = pt(t: s.t, val: s.upper)
                            if idx == 0 { bandPath.move(to: p) } else { bandPath.addLine(to: p) }
                        }
                        for s in curve.samples.reversed() {
                            bandPath.addLine(to: pt(t: s.t, val: s.lower))
                        }
                        bandPath.closeSubpath()
                        context.fill(bandPath, with: .color(self.palette.accentFill.opacity(0.11)))
                        
                        // 2. Dashed Gaussian kernel regression trend line μ(t)
                        var muPath = Path()
                        for (idx, s) in curve.samples.enumerated() {
                            let p = pt(t: s.t, val: s.mu)
                            if idx == 0 { muPath.move(to: p) } else { muPath.addLine(to: p) }
                        }
                        context.stroke(
                            muPath,
                            with: .color(self.palette.mint.opacity(0.75)),
                            style: StrokeStyle(lineWidth: 1.0, lineCap: .round, dash: [3, 3])
                        )
                        
                        // 3. Monotone Hermite spline area fill & luminous stroke
                        var areaPath = Path()
                        var linePath = Path()
                        let baseY = padTop + plotH
                        for (idx, s) in curve.samples.enumerated() {
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
                        if let last = curve.samples.last {
                            areaPath.addLine(to: CGPoint(x: pt(t: last.t, val: last.value).x, y: baseY))
                            areaPath.closeSubpath()
                        }
                        context.fill(
                            areaPath,
                            with: .linearGradient(
                                Gradient(colors: [self.palette.accentFill.opacity(0.22), self.palette.accentFill.opacity(0.01)]),
                                startPoint: CGPoint(x: size.width * 0.5, y: padTop),
                                endPoint: CGPoint(x: size.width * 0.5, y: baseY)
                            )
                        )
                        context.stroke(
                            linePath,
                            with: .linearGradient(
                                Gradient(colors: [self.palette.mint, self.palette.accentFill, self.palette.emerald]),
                                startPoint: CGPoint(x: padX, y: baseY * 0.5),
                                endPoint: CGPoint(x: size.width - padX, y: baseY * 0.5)
                            ),
                            style: StrokeStyle(lineWidth: 1.9, lineCap: .round, lineJoin: .round)
                        )
                        
                        // 4. Data knot markers + cross-linked hover guide
                        let denom = Double(max(1, count - 1))
                        for (idx, day) in self.days14.enumerated() {
                            let t = count > 1 ? Double(idx) / denom : 0.5
                            let val = Double(day.typed + day.ai)
                            let p = pt(t: t, val: val)
                            let isLinked = (self.activeLinkedDayID == day.id)
                            let isPeak = (curve.peakIndex == idx)
                            
                            if isLinked {
                                var guide = Path()
                                guide.move(to: CGPoint(x: p.x, y: padTop))
                                guide.addLine(to: CGPoint(x: p.x, y: baseY))
                                context.stroke(guide, with: .color(self.palette.emerald.opacity(0.55)), lineWidth: 1.0)
                                
                                let halo = CGRect(x: p.x - 5.5, y: p.y - 5.5, width: 11, height: 11)
                                context.fill(Circle().path(in: halo), with: .color(self.palette.emerald.opacity(0.25)))
                                let dot = CGRect(x: p.x - 3.2, y: p.y - 3.2, width: 6.4, height: 6.4)
                                context.fill(Circle().path(in: dot), with: .color(self.palette.emerald))
                            } else if isPeak {
                                let ring = CGRect(x: p.x - 3.2, y: p.y - 3.2, width: 6.4, height: 6.4)
                                context.fill(Circle().path(in: ring), with: .color(self.palette.card))
                                context.stroke(Circle().path(in: ring), with: .color(self.palette.emerald), lineWidth: 1.6)
                            } else if val > 0 {
                                let dot = CGRect(x: p.x - 1.8, y: p.y - 1.8, width: 3.6, height: 3.6)
                                context.fill(Circle().path(in: dot), with: .color(self.palette.accentFill.opacity(0.80)))
                            }
                        }
                    }
                    .contentShape(Rectangle())
                    .onContinuousHover { phase in
                        guard count > 0 else { return }
                        let padX: CGFloat = 6
                        let plotW = max(10, waveGeo.size.width - padX * 2)
                        switch phase {
                            case .active(let loc):
                                let norm = max(0, min(1, (loc.x - padX) / plotW))
                                let idx = min(count - 1, max(0, Int((norm * CGFloat(max(1, count - 1))).rounded())))
                                let nextID = self.days14[idx].id
                                if nextID != self.hoveredBarDayID {
                                    self.hoveredBarDayID = nextID
                                }
                            case .ended:
                                if self.hoveredBarDayID != nil {
                                    self.hoveredBarDayID = nil
                                }
                        }
                    }
                }
                .frame(minHeight: self.compact ? 48 : 68, maxHeight: self.compact ? 58 : 88)
            }
            .padding(.top, 2)
        }
        .padding(self.compact ? 12 : 16)
        .dashboardCardSurface(palette: self.palette, cornerRadius: 18)
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
}


/// Strict 1:1 square-cell layout for the yearly activity heatmap with left weekday labels & top month markers.
struct HeatmapGridLayout {
    
    let gridOriginX: CGFloat
    let gridOriginY: CGFloat
    let cellSide: CGFloat
    let gap: CGFloat
    let cornerRadius: CGFloat
    let canvasWidth: CGFloat
    let canvasHeight: CGFloat
    
    var pitch: CGFloat { self.cellSide + self.gap }
    
    
    static func compute(size: CGSize, weekCount: Int) -> HeatmapGridLayout {
        let cols = max(1, weekCount)
        let rows = 7
        let leftAxis: CGFloat = 18
        let topAxis: CGFloat = 18
        let trailingPad: CGFloat = 4
        let bottomPad: CGFloat = 4
        
        let availW = max(120, size.width - leftAxis - trailingPad)
        let availH = max(72, size.height - topAxis - bottomPad)
        
        let gap: CGFloat = cols > 40 ? 2.5 : 3.0
        let fitW = (availW - CGFloat(cols - 1) * gap) / CGFloat(cols)
        let fitH = (availH - CGFloat(rows - 1) * gap) / CGFloat(rows)
        
        let minSide: CGFloat = 9.5
        let maxSide: CGFloat = 15.0
        let idealSide = min(fitW, fitH)
        let cellSide = max(minSide, min(maxSide, floor(idealSide * 2) / 2))
        
        let gridW = CGFloat(cols) * cellSide + CGFloat(cols - 1) * gap
        let gridH = CGFloat(rows) * cellSide + CGFloat(rows - 1) * gap
        
        let contentW = leftAxis + gridW + trailingPad
        let canvasWidth = max(size.width, contentW)
        let canvasHeight = max(size.height, topAxis + gridH + bottomPad)
        
        let gridOriginX = contentW < size.width
            ? leftAxis + floor((size.width - contentW) * 0.5)
            : leftAxis
        let gridOriginY = topAxis + max(0, floor((canvasHeight - topAxis - bottomPad - gridH) * 0.5))
        let cornerRadius = max(2.0, min(3.5, cellSide * 0.25))
        
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


// MARK: - Full-Width AI Usage Card (Mini Eval Sunburst + Input/Output Split + Top Models)

private struct DashboardAIUsageWideCard: View {
    
    let snapshot: DashboardSnapshot
    let palette: DashPalette
    let onTap: () -> Void
    
    @State private var isHovered = false
    
    
    var body: some View {
        let totals = self.snapshot.ai30Totals
        let todayTotals = self.snapshot.aiTodayTotals
        let displayTokens = todayTotals.totalTokens > 0 ? todayTotals.totalTokens : totals.totalTokens
        let displayReqs = todayTotals.requests > 0 ? todayTotals.requests : totals.requests
        
        let inTok = max(0, totals.inputTokens)
        let outTok = max(0, totals.outputTokens)
        let inFrac: Double = (inTok + outTok) > 0 ? Double(inTok) / Double(inTok + outTok) : 0.62
        let inPct = Int((inFrac * 100).rounded())
        let outPct = max(0, 100 - inPct)
        
        let topModels: [(name: String, share: Int, color: Color)] = {
            let colors: [Color] = [self.palette.accentFill, self.palette.emerald, self.palette.mint]
            let models = Array(self.snapshot.aiModels.prefix(3))
            if !models.isEmpty {
                let sum = max(1.0, models.reduce(0.0) { $0 + Double($1.totalTokens > 0 ? $1.totalTokens : max(1, $1.requests * 150)) })
                return models.enumerated().map { idx, m in
                    let w = Double(m.totalTokens > 0 ? m.totalTokens : max(1, m.requests * 150))
                    let short = m.model.count <= 12 ? m.model : String(m.model.prefix(11)) + "…"
                    return (short, Int(((w / sum) * 100).rounded()), colors[idx % colors.count])
                }
            }
            return [
                ("主力模型", 62, self.palette.accentFill),
                ("轻量模型", 38, self.palette.mint),
            ]
        }()
        
        Button(action: self.onTap) {
            HStack(spacing: 12) {
                ZStack {
                    AIUsageSunburstChartView(snapshot: self.snapshot, palette: self.palette, detailed: false)
                        .frame(width: 96, height: 96)
                    
                    Text(Self.compactTokens(displayTokens))
                        .font(.system(size: 11.5, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(self.palette.pine)
                        .allowsHitTesting(false)
                }
                .frame(width: 98, height: 98)
                
                VStack(alignment: .leading, spacing: 7) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        HStack(alignment: .firstTextBaseline, spacing: 3) {
                            Text(Self.compactTokens(totals.totalTokens))
                                .font(.system(size: 18, weight: .bold, design: .rounded).monospacedDigit())
                                .foregroundStyle(self.palette.pine)
                            Text("tokens")
                                .font(.system(size: 10, weight: .medium, design: .rounded))
                                .foregroundStyle(self.palette.pine.opacity(0.46))
                        }
                        
                        Text("\(displayReqs) req")
                            .font(.system(size: 10, weight: .semibold, design: .rounded).monospacedDigit())
                            .foregroundStyle(self.palette.emerald)
                            .padding(.horizontal, 6.5)
                            .padding(.vertical, 2)
                            .background(self.palette.accentFill.opacity(0.12), in: Capsule())
                        
                        Spacer(minLength: 4)
                    }
                    
                    VStack(spacing: 3.5) {
                        GeometryReader { barGeo in
                            let w = max(40, barGeo.size.width)
                            let splitX = max(14, min(w - 14, w * CGFloat(inFrac)))
                            ZStack(alignment: .leading) {
                                Capsule()
                                    .fill(self.palette.inset)
                                
                                HStack(spacing: 2) {
                                    Capsule()
                                        .fill(
                                            LinearGradient(
                                                colors: [self.palette.accentFill.opacity(0.75), self.palette.accentFill],
                                                startPoint: .leading,
                                                endPoint: .trailing
                                            )
                                        )
                                        .frame(width: max(8, splitX - 1))
                                    
                                    Capsule()
                                        .fill(
                                            LinearGradient(
                                                colors: [self.palette.mint, self.palette.emerald],
                                                startPoint: .leading,
                                                endPoint: .trailing
                                            )
                                        )
                                        .frame(maxWidth: .infinity)
                                }
                                
                                Circle()
                                    .fill(self.palette.card)
                                    .frame(width: 7, height: 7)
                                    .overlay(Circle().strokeBorder(self.palette.emerald, lineWidth: 1.4))
                                    .offset(x: splitX - 3.5)
                            }
                        }
                        .frame(height: 8.5)
                        
                        HStack {
                            Text("\(inPct)%")
                                .font(.system(size: 9.5, weight: .semibold, design: .rounded).monospacedDigit())
                                .foregroundStyle(self.palette.pine.opacity(0.62))
                            Spacer()
                            Text("\(outPct)%")
                                .font(.system(size: 9.5, weight: .semibold, design: .rounded).monospacedDigit())
                                .foregroundStyle(self.palette.emerald.opacity(0.86))
                        }
                    }
                    
                    HStack(alignment: .bottom, spacing: 8) {
                        HStack(spacing: 5) {
                            ForEach(Array(topModels.prefix(2).enumerated()), id: \.offset) { _, m in
                                HStack(spacing: 4) {
                                    Circle()
                                        .fill(m.color)
                                        .frame(width: 5, height: 5)
                                    Text(m.name)
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundStyle(self.palette.pine.opacity(0.78))
                                        .lineLimit(1)
                                    Text("\(m.share)%")
                                        .font(.system(size: 9.5, weight: .semibold, design: .rounded).monospacedDigit())
                                        .foregroundStyle(self.palette.pine.opacity(0.46))
                                }
                                .padding(.horizontal, 6.5)
                                .padding(.vertical, 3)
                                .background(self.palette.inset.opacity(0.85), in: Capsule())
                            }
                        }
                        
                        Spacer(minLength: 4)
                        
                        HStack(alignment: .bottom, spacing: 2.5) {
                            let aiMax = max(20.0, self.snapshot.days14.map { Double($0.ai) }.max() ?? 20.0)
                            ForEach(Array(self.snapshot.days14.suffix(10).enumerated()), id: \.offset) { idx, day in
                                let frac = CGFloat(Double(day.ai) / aiMax)
                                let h = max(4, frac * 16)
                                Capsule()
                                    .fill(day.ai > 0 ? (idx == 9 ? self.palette.emerald : self.palette.accentFill.opacity(0.45 + 0.45 * Double(frac))) : self.palette.emptyDot)
                                    .frame(width: 3, height: h)
                            }
                        }
                        .frame(height: 16, alignment: .bottom)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .dashboardCardSurface(palette: self.palette, cornerRadius: 18, isHighlighted: self.isHovered)
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            if hovering != self.isHovered {
                self.isHovered = hovering
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
    let palette: DashPalette
    let onTap: () -> Void
    
    @State private var isHovered = false
    
    
    var body: some View {
        Button {
            self.onTap()
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text(self.heroValueText)
                            .font(.system(size: 16, weight: .bold, design: .rounded).monospacedDigit())
                            .foregroundStyle(self.palette.pine)
                            .lineLimit(1)
                        
                        Text(self.heroUnitText)
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundStyle(self.palette.pine.opacity(0.46))
                            .lineLimit(1)
                    }
                    
                    Spacer(minLength: 4)
                    
                    if let badgeText = self.secondaryBadgeText {
                        Text(badgeText)
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundStyle(self.palette.pine.opacity(0.56))
                            .lineLimit(1)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(self.palette.inset.opacity(0.85), in: Capsule())
                    }
                }
                
                self.miniVisualization
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(11)
            .dashboardCardSurface(palette: self.palette, cornerRadius: 18, isHighlighted: self.isHovered)
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
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
    let palette: DashPalette
    let onClose: () -> Void
    
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 10) {
                Text(self.metric.title)
                    .font(.system(size: 14.5, weight: .semibold))
                    .foregroundStyle(self.palette.pine)
                
                Spacer()
                
                Button(action: self.onClose) {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(self.palette.pine.opacity(0.70))
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(self.palette.inset))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
            }
            
            self.detailedVisualization
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(16)
        .dashboardCardSurface(palette: self.palette, cornerRadius: 18, isHighlighted: true)
    }
    
    
    @ViewBuilder
    private var detailedVisualization: some View {
        switch self.metric {
            case .typed:
                TrendAreaChartView(days: self.snapshot.days14, curve: self.snapshot.trendCurve14, palette: self.palette, detailed: true)
            case .aiUsage:
                AIUsageSunburstChartView(snapshot: self.snapshot, palette: self.palette, detailed: true)
            case .busyness:
                NightingaleRoseChartView(metrics: self.snapshot.busyness, palette: self.palette, detailed: true)
            case .mood:
                EmotionSankeyChartView(snapshot: self.snapshot, palette: self.palette, detailed: true)
        }
    }
}


// MARK: - Chart 1: Trend Area-Line Chart

private struct TrendAreaChartView: View {
    
    let days: [DashboardSnapshot.ChartDay]
    let curve: MathematicalTrendCurveEngine.Result
    let palette: DashPalette
    let detailed: Bool
    
    @State private var hoveredIndex: Int?
    
    
    var body: some View {
        let curve = self.curve
        
        VStack(spacing: 6) {
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
                            }
                        case .ended:
                            if self.hoveredIndex != nil {
                                self.hoveredIndex = nil
                            }
                    }
                }
            }
            
            if self.detailed, let idx = self.hoveredIndex, idx < self.days.count {
                let d = self.days[idx]
                Text("\(Self.dayFmt.string(from: d.date)) · \((d.typed + d.ai).formatted()) 字")
                    .font(.system(size: 11, weight: .medium, design: .rounded).monospacedDigit())
                    .foregroundStyle(self.palette.pine.opacity(0.84))
                    .frame(height: 16)
            }
        }
    }
    
    
    private static let dayFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "M/d"
        return f
    }()
}


// MARK: - Chart 2: Reference-Faithful Eval Sunburst Chart (Precomputed Tree + Cached Layout + 120fps Morph)

private struct SunburstArcGeom: Sendable {
    let a0: Double
    let a1: Double
    let r0: CGFloat
    let r1: CGFloat
}


private struct AnimatableSunburstDialCanvas: View, Animatable {
    
    let arcs: [EvalSunburstLayoutEngine.ArcItem]
    let prevGeoms: [String: SunburstArcGeom]
    var morphProgress: CGFloat
    let hoveredNodeID: String?
    let detailed: Bool
    let palette: DashPalette
    
    var animatableData: CGFloat {
        get { self.morphProgress }
        set { self.morphProgress = newValue }
    }
    
    
    var body: some View {
        let t = Double(max(0, min(1, self.morphProgress)))
        let cgT = CGFloat(t)
        
        Canvas { context, canvasSize in
            guard canvasSize.width.isFinite, canvasSize.height.isFinite,
                  canvasSize.width > 8, canvasSize.height > 8 else { return }
            let center = CGPoint(x: canvasSize.width * 0.5, y: canvasSize.height * 0.5)
            let radius = max(16, min(canvasSize.width, canvasSize.height) * 0.5 - (self.detailed ? 4 : 2))
            
            for arc in self.arcs {
                let a0: Double
                let a1: Double
                let r0Ratio: CGFloat
                let r1Ratio: CGFloat
                
                if t < 0.999, let prev = self.prevGeoms[arc.key] {
                    a0 = prev.a0 + (arc.a0 - prev.a0) * t
                    a1 = prev.a1 + (arc.a1 - prev.a1) * t
                    r0Ratio = prev.r0 + (arc.r0Ratio - prev.r0) * cgT
                    r1Ratio = prev.r1 + (arc.r1Ratio - prev.r1) * cgT
                } else if t < 0.999 {
                    let mid = (arc.a0 + arc.a1) * 0.5
                    a0 = mid + (arc.a0 - mid) * t
                    a1 = mid + (arc.a1 - mid) * t
                    r0Ratio = arc.r0Ratio
                    r1Ratio = arc.r1Ratio
                } else {
                    a0 = arc.a0
                    a1 = arc.a1
                    r0Ratio = arc.r0Ratio
                    r1Ratio = arc.r1Ratio
                }
                
                guard a1 - a0 > 1e-4 else { continue }
                let sDeg = a0 * 180.0 / .pi - 90.0
                let eDeg = a1 * 180.0 / .pi - 90.0
                let r0 = radius * r0Ratio
                let r1 = radius * r1Ratio
                guard r1 - r0 > 0.2 else { continue }
                
                var path = Path()
                if a1 - a0 >= Double.pi * 1.9999 {
                    path.addArc(center: center, radius: r1, startAngle: .degrees(0), endAngle: .degrees(359.99), clockwise: false)
                    path.addArc(center: center, radius: r0, startAngle: .degrees(359.99), endAngle: .degrees(0), clockwise: true)
                    path.closeSubpath()
                } else {
                    path.addArc(center: center, radius: r1, startAngle: .degrees(sDeg), endAngle: .degrees(eDeg), clockwise: false)
                    path.addArc(center: center, radius: r0, startAngle: .degrees(eDeg), endAngle: .degrees(sDeg), clockwise: true)
                    path.closeSubpath()
                }
                
                let isHovered = (self.hoveredNodeID == arc.node.id)
                let baseColor = AIUsageSunburstChartView.color(for: arc.tone, palette: self.palette)
                let opacityMod: Double = (self.hoveredNodeID == nil || isHovered) ? 1.0 : 0.42
                context.fill(path, with: .color(baseColor.opacity(opacityMod)))
                context.stroke(
                    path,
                    with: .color(self.palette.card),
                    style: StrokeStyle(lineWidth: arc.isMark ? 0.75 : 1.5, lineJoin: .round)
                )
            }
        }
    }
}


private struct AIUsageSunburstChartView: View {
    
    let snapshot: DashboardSnapshot
    let palette: DashPalette
    let detailed: Bool
    
    @State private var focusID: String = "root"
    @State private var openID: String?
    @State private var hoveredNodeID: String?
    @State private var isCenterHovered = false
    
    @State private var cachedFocus: EvalSunburstLayoutEngine.Node?
    @State private var cachedOpen: EvalSunburstLayoutEngine.Node?
    @State private var cachedArcs: [EvalSunburstLayoutEngine.ArcItem] = []
    @State private var cachedRows: [EvalSunburstLayoutEngine.LedgerRow] = []
    @State private var prevGeoms: [String: SunburstArcGeom] = [:]
    @State private var morphProgress: CGFloat = 1.0
    
    
    private func resolveFocusAndOpen(focusID: String, openID: String?) -> (focus: EvalSunburstLayoutEngine.Node, open: EvalSunburstLayoutEngine.Node?) {
        let root = self.snapshot.sunburstRoot
        let map = self.snapshot.sunburstIndex
        var focus = map[focusID] ?? root
        var open: EvalSunburstLayoutEngine.Node?
        if let openID, let candidate = map[openID], candidate.parent?.id == focus.id {
            open = candidate
        } else {
            open = EvalSunburstLayoutEngine.biggestNonOtherChild(of: focus)
        }
        if focus.children.isEmpty, let parent = focus.parent {
            open = focus
            focus = parent
        }
        return (focus, open)
    }
    
    
    private func syncLayout(animated: Bool) {
        let resolved = self.resolveFocusAndOpen(focusID: self.focusID, openID: self.openID)
        let layout = EvalSunburstLayoutEngine.layout(focus: resolved.focus, open: resolved.open)
        
        if animated && !self.cachedArcs.isEmpty {
            self.prevGeoms = Dictionary(
                uniqueKeysWithValues: self.cachedArcs.map {
                    ($0.key, SunburstArcGeom(a0: $0.a0, a1: $0.a1, r0: $0.r0Ratio, r1: $0.r1Ratio))
                }
            )
            self.cachedFocus = resolved.focus
            self.cachedOpen = resolved.open
            self.cachedArcs = layout.arcs
            self.cachedRows = layout.rows
            self.morphProgress = 0
            withAnimation(.timingCurve(0.16, 1, 0.3, 1, duration: 0.24)) {
                self.morphProgress = 1.0
            }
        } else {
            self.prevGeoms = [:]
            self.cachedFocus = resolved.focus
            self.cachedOpen = resolved.open
            self.cachedArcs = layout.arcs
            self.cachedRows = layout.rows
            self.morphProgress = 1.0
        }
    }
    
    
    fileprivate static func color(for tone: EvalSunburstLayoutEngine.ArcItem.ToneKind, palette: DashPalette) -> Color {
        switch tone {
            case .openActive:
                return palette.accentFill
            case .sibling:
                return palette.pine.opacity(0.38)
            case .otherInner:
                return palette.pine.opacity(0.22)
            case .outerIndexed(let index, let count):
                let share = count > 1 ? 0.92 - (Double(index) * 0.56 / Double(count - 1)) : 0.92
                return palette.accentFill.opacity(share)
            case .otherOuter:
                return palette.pine.opacity(0.14)
            case .outputMark:
                return palette.emerald.opacity(0.88)
        }
    }
    
    
    var body: some View {
        let focus = self.cachedFocus ?? self.snapshot.sunburstRoot
        let arcs: [EvalSunburstLayoutEngine.ArcItem] = self.cachedFocus != nil
            ? self.cachedArcs
            : {
                let resolved = self.resolveFocusAndOpen(focusID: self.focusID, openID: self.openID)
                return EvalSunburstLayoutEngine.layout(focus: resolved.focus, open: resolved.open).arcs
            }()
        let rows: [EvalSunburstLayoutEngine.LedgerRow] = self.cachedFocus != nil
            ? self.cachedRows
            : {
                let resolved = self.resolveFocusAndOpen(focusID: self.focusID, openID: self.openID)
                return EvalSunburstLayoutEngine.layout(focus: resolved.focus, open: resolved.open).rows
            }()
        
        Group {
            if !self.detailed {
                self.sunburstDial(focus: focus, arcs: arcs)
            } else {
                GeometryReader { geo in
                    let dialSide = min(max(148, geo.size.height - 8), max(148, geo.size.width * 0.44))
                    HStack(alignment: .center, spacing: 18) {
                        self.sunburstDial(focus: focus, arcs: arcs)
                            .frame(width: dialSide, height: dialSide)
                        
                        self.ledgerView(rows: rows)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .onAppear {
            if self.cachedFocus == nil {
                self.syncLayout(animated: false)
            }
        }
        .onChange(of: self.snapshot.snapshotVersion) { _, _ in
            self.syncLayout(animated: false)
        }
    }
    
    
    private func sunburstDial(focus: EvalSunburstLayoutEngine.Node, arcs: [EvalSunburstLayoutEngine.ArcItem]) -> some View {
        GeometryReader { geo in
            let size = geo.size
            let center = CGPoint(x: size.width * 0.5, y: size.height * 0.5)
            let radius = max(16, min(size.width, size.height) * 0.5 - (self.detailed ? 4 : 2))
            let holeRadius = radius * (52.0 / 110.0)
            
            ZStack {
                let dialCanvas = AnimatableSunburstDialCanvas(
                    arcs: arcs,
                    prevGeoms: self.prevGeoms,
                    morphProgress: self.morphProgress,
                    hoveredNodeID: self.hoveredNodeID,
                    detailed: self.detailed,
                    palette: self.palette
                )
                
                if self.detailed {
                    dialCanvas
                        .contentShape(Circle())
                        .onContinuousHover { phase in
                            let nextID: String? = switch phase {
                                case .active(let pt):
                                    self.hitTest(pt, center: center, radius: radius, arcs: arcs)?.node.id
                                case .ended:
                                    nil
                            }
                            if nextID != self.hoveredNodeID {
                                self.hoveredNodeID = nextID
                            }
                        }
                        .onTapGesture { pt in
                            if let hit = self.hitTest(pt, center: center, radius: radius, arcs: arcs) {
                                self.handleSelect(node: hit.node, ring: hit.ring)
                            }
                        }
                } else {
                    dialCanvas
                }
                
                if self.detailed {
                    let up = focus.parent
                    Button {
                        guard let up else { return }
                        self.openID = focus.id
                        self.focusID = up.id
                        if self.hoveredNodeID != nil {
                            self.hoveredNodeID = nil
                        }
                        self.syncLayout(animated: true)
                    } label: {
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
                                .lineLimit(1)
                            Text(focus.name)
                                .font(.system(size: 10.5, weight: .regular))
                                .foregroundStyle(self.palette.pine.opacity(0.55))
                                .lineLimit(1)
                        }
                        .padding(6)
                        .frame(width: holeRadius * 2, height: holeRadius * 2)
                        .background(
                            Circle()
                                .fill(self.isCenterHovered && up != nil ? self.palette.insetHover : self.palette.card)
                        )
                        .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .disabled(up == nil)
                    .onHover { inside in
                        if inside != self.isCenterHovered {
                            self.isCenterHovered = inside
                        }
                    }
                }
            }
        }
    }
    
    
    private func ledgerView(rows: [EvalSunburstLayoutEngine.LedgerRow]) -> some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 2) {
                ForEach(rows) { row in
                    let isHovered = (self.hoveredNodeID == row.node.id)
                    let pctText = Self.percentString(row.fraction)
                    
                    Button {
                        self.handleSelect(node: row.node, ring: row.ring)
                    } label: {
                        HStack(spacing: 8) {
                            RoundedRectangle(cornerRadius: 2, style: .continuous)
                                .fill(Self.color(for: row.tone, palette: self.palette))
                                .frame(width: 8, height: 8)
                            
                            Text(row.node.name)
                                .font(.system(size: 12.5, weight: row.isOpenHeader ? .medium : .regular))
                                .foregroundStyle(row.isOpenHeader ? self.palette.pine : self.palette.pine.opacity(0.84))
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            
                            Text(Self.compactTokens(Int(row.node.value.rounded())))
                                .font(.system(size: 12, weight: .medium, design: .rounded).monospacedDigit())
                                .foregroundStyle(self.palette.pine)
                                .frame(minWidth: 50, alignment: .trailing)
                            
                            Text(pctText)
                                .font(.system(size: 11.5, weight: .regular, design: .rounded).monospacedDigit())
                                .foregroundStyle(self.palette.pine.opacity(0.46))
                                .frame(width: 42, alignment: .trailing)
                        }
                        .padding(.leading, row.isSubRow ? 20 : 8)
                        .padding(.trailing, 8)
                        .frame(minHeight: 26)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(isHovered ? self.palette.insetHover : Color.clear)
                        )
                    }
                    .buttonStyle(.plain)
                    .onHover { inside in
                        let nextHover: String? = inside ? row.node.id : (self.hoveredNodeID == row.node.id ? nil : self.hoveredNodeID)
                        if nextHover != self.hoveredNodeID {
                            self.hoveredNodeID = nextHover
                        }
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }
    
    
    private func handleSelect(node: EvalSunburstLayoutEngine.Node, ring: EvalSunburstLayoutEngine.Ring) {
        if ring == .inner {
            if node.id == self.openID, !node.children.isEmpty {
                self.focusID = node.id
                self.openID = EvalSunburstLayoutEngine.biggestNonOtherChild(of: node)?.id
            } else {
                self.openID = node.id
            }
        } else {
            if let parent = node.parent, !parent.children.isEmpty {
                self.focusID = parent.id
                self.openID = node.id
            }
        }
        if self.hoveredNodeID != nil {
            self.hoveredNodeID = nil
        }
        self.syncLayout(animated: true)
    }
    
    
    private func hitTest(
        _ point: CGPoint,
        center: CGPoint,
        radius: CGFloat,
        arcs: [EvalSunburstLayoutEngine.ArcItem]
    ) -> EvalSunburstLayoutEngine.ArcItem? {
        let dx = point.x - center.x
        let dy = point.y - center.y
        let dist = hypot(dx, dy)
        var angle = atan2(dy, dx) + Double.pi * 0.5
        if angle < 0 { angle += Double.pi * 2.0 }
        
        for arc in arcs where !arc.isMark {
            let r0 = radius * arc.r0Ratio
            let r1 = radius * arc.r1Ratio
            if dist >= r0 && dist <= r1 && angle >= arc.a0 && angle <= arc.a1 {
                return arc
            }
        }
        return nil
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

private struct NightingaleRoseChartView: View {
    
    let metrics: BusynessMetrics
    let palette: DashPalette
    let detailed: Bool
    
    @State private var hoveredSliceIndex: Int?
    
    
    var body: some View {
        VStack(spacing: 4) {
            GeometryReader { geo in
                Canvas { context, size in
                    guard size.width.isFinite, size.height.isFinite,
                          size.width > 8, size.height > 8 else { return }
                    let center = CGPoint(x: size.width * 0.5, y: size.height * 0.5)
                    let outerLimit = max(14, min(size.width, size.height) * 0.5 - (self.detailed ? 22 : 4))
                    let innerR = max(5, outerLimit * (self.detailed ? 0.22 : 0.20))
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
                    let stepAngle = 360.0 / Double(max(1, slices.count))
                    
                    for slice in slices {
                        let padDeg = self.detailed ? 1.5 : 1.8
                        let startDeg = -90.0 + Double(slice.index) * stepAngle + padDeg
                        let endDeg = -90.0 + Double(slice.index + 1) * stepAngle - padDeg
                        // Nightingale area scaling (r proportional to sqrt(intensity) keeps area honest)
                        let radiusFactor = max(0.16, sqrt(max(0.02, slice.intensity)))
                        let petalOuter = innerR + maxPetalSpan * CGFloat(radiusFactor)
                        
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
                        
                        let isHovered = (self.hoveredSliceIndex == slice.index)
                        let color: Color = {
                            if slice.intensity >= 0.75 { return self.palette.emerald }
                            if slice.intensity >= 0.45 { return self.palette.accentFill }
                            if slice.intensity >= 0.22 { return self.palette.mint }
                            return self.palette.emptyDot
                        }()
                        context.fill(petal, with: .color(color.opacity(isHovered ? 0.96 : 0.84)))
                        if isHovered {
                            context.stroke(petal, with: .color(self.palette.pine), lineWidth: 1.2)
                        }
                        
                        if self.detailed, slice.index.isMultiple(of: 2) {
                            let midRad = (startDeg + endDeg) * 0.5 * .pi / 180.0
                            let labelR = outerLimit + 12
                            let lx = center.x + CGFloat(cos(midRad)) * labelR
                            let ly = center.y + CGFloat(sin(midRad)) * labelR
                            context.draw(
                                Text(slice.label)
                                    .font(.system(size: 9.5, design: .rounded).monospacedDigit())
                                    .foregroundStyle(self.palette.pine.opacity(0.55)),
                                at: CGPoint(x: lx, y: ly),
                                anchor: .center
                            )
                        }
                    }
                    
                    let coreRect = CGRect(x: center.x - innerR + 1, y: center.y - innerR + 1, width: (innerR - 1) * 2, height: (innerR - 1) * 2)
                    context.fill(Circle().path(in: coreRect), with: .color(self.palette.card))
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
                        self.hoveredSliceIndex = nextIdx
                    }
                }
            }
            
            if self.detailed, let idx = self.hoveredSliceIndex, idx < self.metrics.slices.count {
                let slice = self.metrics.slices[idx]
                Text("\(slice.label) · \(slice.rawChars.formatted()) 字 · \(slice.rawAIRequests) 次 AI")
                    .font(.system(size: 11, weight: .medium, design: .rounded).monospacedDigit())
                    .foregroundStyle(self.palette.pine.opacity(0.84))
                    .frame(height: 16)
            }
        }
    }
    
    
    private func hitTestPetal(_ point: CGPoint, in size: CGSize) -> Int? {
        let center = CGPoint(x: size.width * 0.5, y: size.height * 0.5)
        let dx = point.x - center.x
        let dy = point.y - center.y
        let dist = hypot(dx, dy)
        let outerLimit = max(14, min(size.width, size.height) * 0.5 - (self.detailed ? 22 : 4))
        let innerR = max(5, outerLimit * 0.22)
        guard dist >= innerR && dist <= outerLimit else { return nil }
        var angle = atan2(dy, dx) * 180.0 / .pi + 90.0
        if angle < 0 { angle += 360.0 }
        let idx = Int(floor(angle / (360.0 / Double(max(1, self.metrics.slices.count)))))
        return min(max(0, idx), max(0, self.metrics.slices.count - 1))
    }
}


// MARK: - Chart 4: 3-Column Sankey Flow Diagram (心境流向)

private struct EmotionSankeyChartView: View {
    
    let snapshot: DashboardSnapshot
    let palette: DashPalette
    let detailed: Bool
    
    @State private var hoveredCaption: String?
    
    private struct SankeyNode {
        let label: String
        let weight: Double
        let color: Color
    }
    
    
    var body: some View {
        let col1Nodes = self.leftTimeSlotNodes()
        let col2Nodes = self.middleMoodNodes()
        let col3Nodes = self.rightSubMoodNodes()
        
        VStack(spacing: 4) {
            GeometryReader { geo in
                Canvas { context, size in
                    guard size.width.isFinite, size.height.isFinite,
                          size.width > 8, size.height > 8 else { return }
                    let padX: CGFloat = self.detailed ? 74 : 6
                    let topHeaderH: CGFloat = self.detailed ? 20 : 2
                    let padBottom: CGFloat = self.detailed ? 10 : 3
                    let nodeW: CGFloat = self.detailed ? 10 : 5.5
                    let innerW = max(36, size.width - padX * 2)
                    let innerH = max(30, size.height - topHeaderH - padBottom)
                    
                    let col1X = padX
                    let col2X = padX + innerW * 0.5 - nodeW * 0.5
                    let col3X = padX + innerW - nodeW
                    
                    if self.detailed {
                        let headerStyle = Font.system(size: 10, weight: .medium)
                        let headerColor = self.palette.pine.opacity(0.46)
                        context.draw(Text("写作时段").font(headerStyle).foregroundStyle(headerColor), at: CGPoint(x: col1X + nodeW * 0.5, y: 7), anchor: .center)
                        context.draw(Text("心境维度").font(headerStyle).foregroundStyle(headerColor), at: CGPoint(x: col2X + nodeW * 0.5, y: 7), anchor: .center)
                        context.draw(Text("状态细分").font(headerStyle).foregroundStyle(headerColor), at: CGPoint(x: col3X + nodeW * 0.5, y: 7), anchor: .center)
                    }
                    
                    let rects1 = Self.layoutColumn(nodes: col1Nodes, x: col1X, yStart: topHeaderH, height: innerH, width: nodeW, gap: self.detailed ? 7 : 4)
                    let rects2 = Self.layoutColumn(nodes: col2Nodes, x: col2X, yStart: topHeaderH, height: innerH, width: nodeW, gap: self.detailed ? 7 : 4)
                    let rects3 = Self.layoutColumn(nodes: col3Nodes, x: col3X, yStart: topHeaderH, height: innerH, width: nodeW, gap: self.detailed ? 7 : 4)
                    
                    Self.drawFlows(context: &context, sources: rects1, targets: rects2)
                    Self.drawFlows(context: &context, sources: rects2, targets: rects3)
                    
                    let sum1 = max(1.0, col1Nodes.reduce(0.0) { $0 + $1.weight })
                    let sum3 = max(1.0, col3Nodes.reduce(0.0) { $0 + $1.weight })
                    
                    for (node, layout) in zip(col1Nodes, rects1) {
                        context.fill(RoundedRectangle(cornerRadius: 2.5, style: .continuous).path(in: layout.rect), with: .color(node.color))
                        if self.detailed {
                            let pct = Int(((node.weight / sum1) * 100).rounded())
                            let text = "\(node.label) \(pct)%"
                            context.draw(
                                Text(text)
                                    .font(.system(size: 10.5, weight: .medium).monospacedDigit())
                                    .foregroundStyle(self.palette.pine.opacity(0.84)),
                                at: CGPoint(x: layout.rect.minX - 5, y: layout.rect.midY),
                                anchor: .trailing
                            )
                        }
                    }
                    
                    for (node, layout) in zip(col2Nodes, rects2) {
                        context.fill(RoundedRectangle(cornerRadius: 2.5, style: .continuous).path(in: layout.rect), with: .color(node.color))
                        if self.detailed {
                            context.draw(
                                Text(node.label)
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(self.palette.pine.opacity(0.92)),
                                at: CGPoint(x: layout.rect.midX, y: max(layout.rect.minY - 7, topHeaderH + 4)),
                                anchor: .center
                            )
                        }
                    }
                    
                    for (node, layout) in zip(col3Nodes, rects3) {
                        context.fill(RoundedRectangle(cornerRadius: 2.5, style: .continuous).path(in: layout.rect), with: .color(node.color))
                        if self.detailed {
                            let pct = Int(((node.weight / sum3) * 100).rounded())
                            let text = "\(node.label) \(pct)%"
                            context.draw(
                                Text(text)
                                    .font(.system(size: 10.5, weight: .medium).monospacedDigit())
                                    .foregroundStyle(self.palette.pine.opacity(0.84)),
                                at: CGPoint(x: layout.rect.maxX + 5, y: layout.rect.midY),
                                anchor: .leading
                            )
                        }
                    }
                }
                .onContinuousHover { phase in
                    guard self.detailed else { return }
                    let nextCaption: String? = switch phase {
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
                    if nextCaption != self.hoveredCaption {
                        self.hoveredCaption = nextCaption
                    }
                }
            }
            
            if self.detailed, let caption = self.hoveredCaption {
                Text(caption)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(self.palette.pine.opacity(0.84))
                    .frame(height: 16)
            }
        }
    }
    
    
    private func leftTimeSlotNodes() -> [SankeyNode] {
        let slices = self.snapshot.busyness.slices
        var morning: Double = 0
        var afternoon: Double = 0
        var night: Double = 0
        for slice in slices {
            let weight = max(0.05, slice.intensity)
            switch slice.index {
                case 3..<6: morning += weight
                case 6..<9: afternoon += weight
                default: night += weight
            }
        }
        return [
            SankeyNode(label: "晨间", weight: max(1, morning * 100), color: self.palette.mint),
            SankeyNode(label: "午后", weight: max(1, afternoon * 100), color: self.palette.accentFill),
            SankeyNode(label: "夜间", weight: max(1, night * 100), color: self.palette.emerald),
        ]
    }
    
    
    private func middleMoodNodes() -> [SankeyNode] {
        let segs = Array(self.snapshot.mood.segments.prefix(4))
        guard !segs.isEmpty else {
            return [
                SankeyNode(label: "沉稳", weight: 45, color: self.palette.accentFill),
                SankeyNode(label: "专注", weight: 35, color: self.palette.mint),
                SankeyNode(label: "松弛", weight: 20, color: self.palette.paleMint),
            ]
        }
        return segs.map { seg in
            SankeyNode(
                label: seg.label,
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
                    weight: max(1, child.value),
                    color: baseColor.opacity(0.82)
                ))
            }
        }
        if !collected.isEmpty {
            return Array(collected.sorted { $0.weight > $1.weight }.prefix(4))
        }
        return [
            SankeyNode(label: "心流", weight: 42, color: self.palette.accentFill),
            SankeyNode(label: "克制", weight: 33, color: self.palette.mint),
            SankeyNode(label: "愉悦", weight: 25, color: self.palette.heat(2)),
        ]
    }
    
    
    private func hitTestColumn(
        _ point: CGPoint,
        in size: CGSize,
        col1: [SankeyNode],
        col2: [SankeyNode],
        col3: [SankeyNode]
    ) -> String? {
        let third = size.width / 3.0
        let nodes: [SankeyNode]
        let prefix: String
        if point.x < third {
            nodes = col1
            prefix = "写作时段"
        } else if point.x < third * 2 {
            nodes = col2
            prefix = "心境维度"
        } else {
            nodes = col3
            prefix = "状态细分"
        }
        let padY: CGFloat = 14
        let innerH = max(34, size.height - padY * 2)
        let laid = Self.layoutColumn(nodes: nodes, x: 0, yStart: padY, height: innerH, width: 10, gap: 6)
        let total = max(1.0, nodes.reduce(0.0) { $0 + $1.weight })
        for (node, layout) in zip(nodes, laid) {
            if point.y >= layout.rect.minY - 3 && point.y <= layout.rect.maxY + 3 {
                let pct = Int(((node.weight / total) * 100).rounded())
                return "\(prefix) · \(node.label) (\(pct)%)"
            }
        }
        return nil
    }
    
    
    private static func layoutColumn(
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
    
    
    private static func drawFlows(
        context: inout GraphicsContext,
        sources: [(rect: CGRect, color: Color, weight: Double)],
        targets: [(rect: CGRect, color: Color, weight: Double)]
    ) {
        let totalTarget = max(1.0, targets.reduce(0.0) { $0 + $1.weight })
        let totalSource = max(1.0, sources.reduce(0.0) { $0 + $1.weight })
        var targetOffsets = targets.map { $0.rect.minY }
        
        for src in sources {
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
                
                context.fill(
                    ribbon,
                    with: .linearGradient(
                        Gradient(colors: [
                            src.color.opacity(0.36),
                            tgt.color.opacity(0.28),
                        ]),
                        startPoint: CGPoint(x: startX, y: sTop),
                        endPoint: CGPoint(x: endX, y: tTop)
                    )
                )
            }
        }
    }
}


// MARK: - Supporting Components (Clean Cover News Cards with Top-Right Heat Pill)

private struct NewsFeedCoverCard: View {
    
    let item: AIHotNewsItem
    let coverImage: NSImage?
    let isBookmarked: Bool
    let compactRow: Bool
    var coverHeight: CGFloat = 70
    let palette: DashPalette
    let onTap: () -> Void
    let onToggleBookmark: () -> Void
    
    @State private var isHovered = false
    
    
    var body: some View {
        Button(action: self.onTap) {
            if self.compactRow {
                HStack(alignment: .top, spacing: 8) {
                    self.thumbnailView
                        .frame(width: 64, height: 46)
                        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    
                    Text(self.item.title)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(self.palette.pine.opacity(0.92))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    
                    if let score = self.item.heatScore, score > 0 {
                        self.heatPill(score)
                    }
                }
                .padding(6)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(self.isHovered ? self.palette.inset : self.palette.inset.opacity(0.45))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(self.palette.hairline, lineWidth: 0.6)
                )
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ZStack(alignment: .topLeading) {
                        self.thumbnailView
                            .frame(maxWidth: .infinity)
                            .frame(height: self.coverHeight)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        
                        HStack(alignment: .top) {
                            if self.isHovered || self.isBookmarked {
                                Button(action: self.onToggleBookmark) {
                                    Image(systemName: self.isBookmarked ? "bookmark.fill" : "bookmark")
                                        .font(.system(size: 9.5, weight: .semibold))
                                        .foregroundStyle(self.isBookmarked ? self.palette.tokens.onAccentInk : self.palette.pine.opacity(0.80))
                                        .frame(width: 20, height: 20)
                                        .background(
                                            self.isBookmarked ? self.palette.accentFill : self.palette.card.opacity(0.88),
                                            in: Circle()
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                            
                            Spacer(minLength: 4)
                            
                            if let score = self.item.heatScore, score > 0 {
                                self.heatPill(score)
                            }
                        }
                        .padding(4)
                    }
                    
                    Text(self.item.title)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(self.palette.pine.opacity(0.92))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(6)
                .background(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(self.isHovered ? self.palette.inset : self.palette.inset.opacity(0.45))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .strokeBorder(self.isHovered ? self.palette.accentFill.opacity(0.35) : self.palette.hairline, lineWidth: 0.7)
                )
            }
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            if hovering != self.isHovered {
                self.isHovered = hovering
            }
        }
    }
    
    
    private func heatPill(_ score: Int) -> some View {
        Text("\(score)°")
            .font(.system(size: 9.5, weight: .semibold, design: .rounded).monospacedDigit())
            .foregroundStyle(self.palette.emerald)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(self.palette.card.opacity(0.90), in: Capsule())
            .overlay(Capsule().strokeBorder(self.palette.hairline, lineWidth: 0.5))
    }
    
    
    @ViewBuilder
    private var thumbnailView: some View {
        ZStack {
            if let coverImage = self.coverImage {
                GeometryReader { geo in
                    Image(nsImage: coverImage)
                        .resizable()
                        .interpolation(.medium)
                        .scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                }
            } else {
                let tint = self.domainTintColor
                LinearGradient(
                    colors: [tint.opacity(0.24), tint.opacity(0.08)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                let badge = self.item.resolvedCategory.badgeLabel
                Text(badge.isEmpty ? "AI" : badge)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(tint.opacity(0.82))
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(self.palette.hairline, lineWidth: 0.5)
        )
    }
    
    
    private var domainTintColor: Color {
        let hash = abs(self.item.title.unicodeScalars.reduce(0) { $0 &* 31 &+ Int($1.value) })
        let hues: [Color] = [
            self.palette.accentFill,
            self.palette.mint,
            Color(red: 0.86, green: 0.48, blue: 0.34),
            Color(red: 0.44, green: 0.56, blue: 0.88),
            Color(red: 0.68, green: 0.44, blue: 0.84),
        ]
        return hues[hash % hues.count]
    }
}


private extension View {
    
    func dashboardCardSurface(
        palette: DashPalette,
        cornerRadius: CGFloat = 16,
        isHighlighted: Bool = false,
        tintAccent: Color? = nil
    ) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        let strokeColor: Color = if let tintAccent {
            tintAccent.opacity(isHighlighted ? 0.45 : 0.24)
        } else {
            isHighlighted ? palette.accentFill.opacity(0.45) : palette.hairline
        }
        return self
            .background(
                ZStack {
                    shape.fill(palette.card)
                    if let tintAccent {
                        shape.fill(
                            LinearGradient(
                                colors: [tintAccent.opacity(palette.tokens.isDark ? 0.08 : 0.045), Color.clear],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    }
                }
                .shadow(color: palette.cardShadow, radius: 8, x: 0, y: 4)
            )
            .overlay(
                shape.strokeBorder(strokeColor, lineWidth: isHighlighted ? 1.1 : 0.8)
            )
    }
}
