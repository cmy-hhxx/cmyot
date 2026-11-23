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


/// Cohesive neutral-graphite & cobalt-ink design system shared across the Dashboard and NEWS reader.
struct DashPalette: Sendable {
    
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
            let canvas = Color(red: 0.071, green: 0.078, blue: 0.094)       // #121418
            let card = Color(red: 0.098, green: 0.110, blue: 0.133)         // #191C22
            let inset = Color(red: 0.129, green: 0.145, blue: 0.176)        // #21252D
            let insetHover = Color(red: 0.165, green: 0.184, blue: 0.227)   // #2A2F3A
            let primary = Color(red: 0.925, green: 0.937, blue: 0.961)      // #ECEFF5
            let accent = Color(red: 0.294, green: 0.482, blue: 1.000)       // #4B7BFF
            let accentText = Color(red: 0.490, green: 0.635, blue: 1.000)   // #7DA2FF
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
                hairlineStrong: Color.white.opacity(0.15),
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
            let canvas = Color(red: 0.957, green: 0.961, blue: 0.973)       // #F4F5F8
            let card = Color.white                                          // #FFFFFF
            let inset = Color(red: 0.957, green: 0.965, blue: 0.976)        // #F4F6F9
            let insetHover = Color(red: 0.918, green: 0.929, blue: 0.953)   // #EAEDF3
            let primary = Color(red: 0.082, green: 0.098, blue: 0.133)      // #151922
            let accent = Color(red: 0.169, green: 0.361, blue: 0.902)       // #2B5CE6
            let accentText = Color(red: 0.118, green: 0.278, blue: 0.780)   // #1E47C7
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
                hairlineStrong: Color(red: 0.08, green: 0.10, blue: 0.14).opacity(0.15),
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
    @State private var profileManager = UserProfileManager.shared
    @State private var studioPalette = StudioPaletteManager.shared
    
    @State private var snapshot: DashboardSnapshot?
    @State private var snapshotVersion: Int = 0
    @State private var selectedYear: Int = Calendar.current.component(.year, from: Date())
    @State private var expandedQuad: DashboardQuadMetric?
    @State private var isNewsWorkspaceOpen = false
    @State private var activeNewsID: String?
    @State private var hasAppeared = false
    @State private var pendingRebuildTask: Task<Void, Never>?
    @State private var copiedCardKey: String?
    
    
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
                        withAnimation(DashMotion.standard) {
                            self.isNewsWorkspaceOpen = false
                        }
                    }
                )
                .transition(.opacity.combined(with: .move(edge: .trailing)))
            } else {
                let outerPad: CGFloat = self.isEmbeddedInSettings ? 12 : 24
                let vSpacing: CGFloat = self.isEmbeddedInSettings ? 12 : 16
                let hSpacing: CGFloat = self.isEmbeddedInSettings ? 12 : 16
                let heroH: CGFloat = self.isEmbeddedInSettings ? 116 : 140
                let row1H: CGFloat = self.isEmbeddedInSettings ? 228 : 304
                let row2H: CGFloat = self.isEmbeddedInSettings ? 220 : 308
                
                GeometryReader { viewportGeo in
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
                            .padding(outerPad)
                            .frame(maxWidth: 1200, alignment: .leading)
                            .frame(maxWidth: .infinity, minHeight: viewportGeo.size.height, alignment: .center)
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
    
    private func row1Section(_ snapshot: DashboardSnapshot, height: CGFloat, spacing: CGFloat) -> some View {
        GeometryReader { proxy in
            let usableW = max(320, proxy.size.width - spacing)
            let leftRatio: CGFloat = self.isEmbeddedInSettings ? 0.50 : 0.54
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
                let vGap: CGFloat = self.isEmbeddedInSettings ? 12 : 16
                let hGap: CGFloat = self.isEmbeddedInSettings ? 12 : 16
                let topH = max(88, floor((height - vGap) * 0.50))
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
    
    
    // MARK: Row 2 — Equal 3-Column Layout (干了啥 / 要干啥 / NEWS)
    
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
        DoneTodayEditorialCard(
            points: points,
            isRefreshing: self.analytics.isRefreshingDoneToday,
            compact: self.isEmbeddedInSettings,
            palette: self.palette,
            copiedKey: self.copiedCardKey,
            onCopy: { text, key in
                self.copyDashboardText(text, key: key)
            },
            onRefresh: {
                Task { await self.analytics.refreshDoneTodayCommentary(force: true) }
            }
        )
    }
    
    
    private func predictedActionsColumn(predictions: [DocumentActionPrediction]) -> some View {
        NextActionsEditorialCard(
            predictions: predictions,
            isRefreshing: self.analytics.isPredictingActions,
            compact: self.isEmbeddedInSettings,
            palette: self.palette,
            copiedKey: self.copiedCardKey,
            resolveDocument: { pred in
                self.analytics.storedDocument(id: pred.sourceDocumentID, title: pred.sourceDocumentTitle)
            },
            onOpenDocument: { doc in
                if let onOpenDocument = self.onOpenDocument {
                    onOpenDocument(doc)
                } else {
                    AnalyticsDashboardWindowController.shared.openDocument(doc)
                }
            },
            onCopy: { text, key in
                self.copyDashboardText(text, key: key)
            },
            onRefresh: {
                Task { await self.analytics.refreshActionPredictions(force: true) }
            }
        )
    }
    
    
    private func copyDashboardText(_ text: String, key: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(trimmed, forType: .string)
        self.copiedCardKey = key
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))
            if self.copiedCardKey == key {
                self.copiedCardKey = nil
            }
        }
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


/// Editorial "干了啥" card: featured headline lead quote + connected timeline feed + zero-clutter hover feedback.
private struct DoneTodayEditorialCard: View {
    
    let points: [String]
    let isRefreshing: Bool
    let compact: Bool
    let palette: DashPalette
    let copiedKey: String?
    let onCopy: (String, String) -> Void
    let onRefresh: () -> Void
    
    @State private var isCardHovered = false
    @State private var hoveredIndex: Int?
    
    
    var body: some View {
        let isDark = self.palette.tokens.isDark
        
        VStack(alignment: .leading, spacing: 12) {
            // Clean editorial header with whisper-quiet hover refresh pill (zero resting icon clutter)
            HStack(spacing: 8) {
                Circle()
                    .fill(self.palette.emerald)
                    .frame(width: 7, height: 7)
                
                Text("干了啥")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(self.palette.pine)
                
                Spacer(minLength: 4)
                
                if self.isRefreshing {
                    Text(AppLanguage.text("点评中…", en: "Updating…"))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(self.palette.mutedInk)
                } else if self.isCardHovered {
                    Button(action: self.onRefresh) {
                        Text(AppLanguage.text("换一批", en: "Refresh"))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(self.palette.secondaryInk)
                            .padding(.horizontal, 8)
                            .frame(height: 22)
                            .background(self.palette.inset, in: Capsule())
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .pointerStyle(.link)
                    .transition(.opacity)
                }
            }
            .frame(height: 24)
            
            ScrollView(.vertical, showsIndicators: false) {
                if self.points.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(AppLanguage.text("今天还没开张", en: "Quiet desk so far"))
                            .font(.system(size: 13.5, weight: .semibold))
                            .foregroundStyle(self.palette.pine.opacity(0.75))
                        Text(AppLanguage.text("敲几行字，看看今天的犀利点评会怎么夸（或损）你。", en: "Start writing to see today's commentary."))
                            .font(.system(size: 12))
                            .foregroundStyle(self.palette.mutedInk)
                            .lineSpacing(3)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(self.palette.inset, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        // Lead Headline Pull-Quote (#0)
                        if let lead = self.points.first {
                            let leadKey = "done-0"
                            let isHover = (self.hoveredIndex == 0)
                            let isCopied = (self.copiedKey == leadKey)
                            
                            ZStack(alignment: .bottomTrailing) {
                                HStack(alignment: .top, spacing: 11) {
                                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                                        .fill(
                                            LinearGradient(
                                                colors: [self.palette.accentFill, self.palette.emerald],
                                                startPoint: .top,
                                                endPoint: .bottom
                                            )
                                        )
                                        .frame(width: 3)
                                    
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(AppLanguage.text("今日主评", en: "HIGHLIGHT"))
                                            .font(.system(size: 9.5, weight: .bold, design: .rounded))
                                            .tracking(0.6)
                                            .foregroundStyle(self.palette.accentFill)
                                        
                                        Text(lead)
                                            .font(.system(size: 13, weight: .semibold))
                                            .foregroundStyle(self.palette.pine)
                                            .lineSpacing(3.5)
                                            .textSelection(.enabled)
                                            .fixedSize(horizontal: false, vertical: true)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                }
                                .padding(.horizontal, 13)
                                .padding(.vertical, 12)
                                
                                if isHover || isCopied {
                                    self.floatingCopyPill(isCopied: isCopied) {
                                        self.onCopy(lead, leadKey)
                                    }
                                    .padding(8)
                                    .transition(.opacity.combined(with: .scale(scale: 0.92)))
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(
                                        LinearGradient(
                                            colors: [
                                                self.palette.accentFill.opacity(isDark ? 0.16 : 0.085),
                                                self.palette.inset.opacity(isDark ? 0.65 : 0.72),
                                            ],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .strokeBorder(
                                        self.palette.accentFill.opacity(isHover ? 0.48 : 0.24),
                                        lineWidth: isHover ? 1.0 : 0.75
                                    )
                            )
                            .scaleEffect(isHover ? 1.008 : 1.0)
                            .animation(.spring(response: 0.24, dampingFraction: 0.80), value: isHover)
                            .onHover { inside in
                                if inside { self.hoveredIndex = 0 }
                                else if self.hoveredIndex == 0 { self.hoveredIndex = nil }
                            }
                            .contextMenu {
                                self.doneContextMenu(point: lead, key: leadKey)
                            }
                        }
                        
                        // Connected Editorial Timeline Feed (#1...)
                        let rest = Array(self.points.dropFirst())
                        if !rest.isEmpty {
                            VStack(alignment: .leading, spacing: 2) {
                                ForEach(Array(rest.enumerated()), id: \.offset) { offset, point in
                                    let realIdx = offset + 1
                                    let itemKey = "done-\(realIdx)"
                                    let isHover = (self.hoveredIndex == realIdx)
                                    let isCopied = (self.copiedKey == itemKey)
                                    let isLast = (offset == rest.count - 1)
                                    let dotColor = (offset == 0) ? self.palette.emerald : self.palette.mint
                                    
                                    HStack(alignment: .top, spacing: 10) {
                                        // Minimal vertical timeline rail
                                        VStack(spacing: 0) {
                                            Circle()
                                                .fill(isHover ? self.palette.accentFill : dotColor)
                                                .frame(width: isHover ? 7 : 5.5, height: isHover ? 7 : 5.5)
                                                .padding(.top, 11)
                                            
                                            if !isLast {
                                                Rectangle()
                                                    .fill(self.palette.hairlineStrong)
                                                    .frame(width: 1)
                                                    .frame(maxHeight: .infinity)
                                                    .padding(.top, 4)
                                            }
                                        }
                                        .frame(width: 10)
                                        
                                        ZStack(alignment: .bottomTrailing) {
                                            Text(point)
                                                .font(.system(size: 12.5, weight: isHover ? .medium : .regular))
                                                .foregroundStyle(isHover ? self.palette.pine : self.palette.secondaryInk)
                                                .lineSpacing(3)
                                                .textSelection(.enabled)
                                                .fixedSize(horizontal: false, vertical: true)
                                                .padding(.horizontal, 10)
                                                .padding(.vertical, 8)
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                            
                                            if isHover || isCopied {
                                                self.floatingCopyPill(isCopied: isCopied) {
                                                    self.onCopy(point, itemKey)
                                                }
                                                .padding(6)
                                                .transition(.opacity.combined(with: .scale(scale: 0.92)))
                                            }
                                        }
                                        .background(
                                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                                .fill(isHover ? self.palette.insetHover : Color.clear)
                                        )
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                                .strokeBorder(isHover ? self.palette.hairlineStrong : Color.clear, lineWidth: 0.7)
                                        )
                                    }
                                    .animation(.spring(response: 0.22, dampingFraction: 0.82), value: isHover)
                                    .onHover { inside in
                                        if inside { self.hoveredIndex = realIdx }
                                        else if self.hoveredIndex == realIdx { self.hoveredIndex = nil }
                                    }
                                    .contextMenu {
                                        self.doneContextMenu(point: point, key: itemKey)
                                    }
                                }
                            }
                            .padding(.leading, 4)
                        }
                    }
                    .padding(.vertical, 1)
                }
            }
        }
        .padding(self.compact ? 12 : 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .dashboardCardSurface(palette: self.palette, cornerRadius: 16, isHighlighted: self.isCardHovered)
        .animation(.easeOut(duration: 0.16), value: self.isCardHovered)
        .onHover { inside in
            if inside != self.isCardHovered {
                self.isCardHovered = inside
            }
        }
    }
    
    
    private func floatingCopyPill(isCopied: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(isCopied ? AppLanguage.text("✓ 已复制", en: "✓ Copied") : AppLanguage.text("复制", en: "Copy"))
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(isCopied ? self.palette.tokens.onAccentInk : self.palette.secondaryInk)
                .padding(.horizontal, 8)
                .frame(height: 20)
                .background(
                    Capsule()
                        .fill(isCopied ? self.palette.emerald : self.palette.card.opacity(0.95))
                        .shadow(color: self.palette.cardShadow, radius: 4, y: 1)
                )
                .overlay(
                    Capsule()
                        .strokeBorder(isCopied ? Color.clear : self.palette.hairlineStrong, lineWidth: 0.6)
                )
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .pointerStyle(.link)
    }
    
    
    @ViewBuilder
    private func doneContextMenu(point: String, key: String) -> some View {
        Button(AppLanguage.text("复制这条点评", en: "Copy")) {
            self.onCopy(point, key)
        }
        Button(AppLanguage.text("复制全部点评", en: "Copy All")) {
            self.onCopy(self.points.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n"), "done-all")
        }
        Divider()
        Button(AppLanguage.text("换一批犀利点评", en: "Refresh"), action: self.onRefresh)
    }
}


/// Tactile interactive "要干啥" card: check-to-complete rings, priority accent stripe, clickable source doc tags,
/// and whisper-quiet hover copy feedback (zero resting icon clutter).
private struct NextActionsEditorialCard: View {
    
    let predictions: [DocumentActionPrediction]
    let isRefreshing: Bool
    let compact: Bool
    let palette: DashPalette
    let copiedKey: String?
    let resolveDocument: (DocumentActionPrediction) -> StoredDocumentRecord?
    let onOpenDocument: (StoredDocumentRecord) -> Void
    let onCopy: (String, String) -> Void
    let onRefresh: () -> Void
    
    @State private var isCardHovered = false
    @State private var hoveredID: String?
    @State private var completedIDs: Set<String> = []
    
    
    var body: some View {
        let isDark = self.palette.tokens.isDark
        let doneCount = self.predictions.filter { self.completedIDs.contains($0.id) }.count
        
        VStack(alignment: .leading, spacing: 12) {
            // Header with subtle progress badge & hover-only refresh text pill
            HStack(spacing: 8) {
                Circle()
                    .fill(self.palette.accentFill)
                    .frame(width: 7, height: 7)
                
                Text("要干啥")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(self.palette.pine)
                
                if doneCount > 0 {
                    Text("\(doneCount)/\(self.predictions.count)")
                        .font(.system(size: 10.5, weight: .semibold, design: .rounded).monospacedDigit())
                        .foregroundStyle(self.palette.emerald)
                        .padding(.horizontal, 6.5)
                        .frame(height: 18)
                        .background(self.palette.tokens.positivePillBg, in: Capsule())
                        .transition(.scale.combined(with: .opacity))
                }
                
                Spacer(minLength: 4)
                
                if self.isRefreshing {
                    Text(AppLanguage.text("推演中…", en: "Predicting…"))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(self.palette.mutedInk)
                } else if self.isCardHovered {
                    Button(action: self.onRefresh) {
                        Text(AppLanguage.text("重新预测", en: "Refresh"))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(self.palette.secondaryInk)
                            .padding(.horizontal, 8)
                            .frame(height: 22)
                            .background(self.palette.inset, in: Capsule())
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .pointerStyle(.link)
                    .transition(.opacity)
                }
            }
            .frame(height: 24)
            
            ScrollView(.vertical, showsIndicators: false) {
                if self.predictions.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(AppLanguage.text("暂无火烧眉毛的事", en: "All clear for now"))
                            .font(.system(size: 13.5, weight: .semibold))
                            .foregroundStyle(self.palette.pine.opacity(0.75))
                        Text(AppLanguage.text("继续写文档或记录待办，AI 会自动帮你盯紧最值得收口的下一步。", en: "AI will predict your highest-leverage next move from your notes."))
                            .font(.system(size: 12))
                            .foregroundStyle(self.palette.mutedInk)
                            .lineSpacing(3)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(self.palette.inset, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                } else {
                    VStack(alignment: .leading, spacing: 9) {
                        ForEach(Array(self.predictions.enumerated()), id: \.element.id) { idx, pred in
                            let linkedDoc = self.resolveDocument(pred)
                            let isDone = self.completedIDs.contains(pred.id)
                            let isHover = (self.hoveredID == pred.id)
                            let itemKey = "action-\(pred.id)"
                            let isCopied = (self.copiedKey == itemKey)
                            let isHigh = (pred.urgency == "高" || idx == 0)
                            let tone: Color = isDone
                                ? self.palette.emerald
                                : (isHigh ? self.palette.accentFill : (pred.urgency == "中" ? self.palette.emerald : self.palette.secondaryInk))
                            let badgeText: String = pred.urgency == "高" ? "优先" : (pred.urgency == "中" ? "推进" : "顺手")
                            
                            ZStack(alignment: .bottomTrailing) {
                                HStack(alignment: .top, spacing: 10) {
                                    // Tactile spring check-off ring
                                    Button {
                                        withAnimation(.spring(response: 0.28, dampingFraction: 0.68)) {
                                            if isDone {
                                                self.completedIDs.remove(pred.id)
                                            } else {
                                                self.completedIDs.insert(pred.id)
                                            }
                                        }
                                    } label: {
                                        ZStack {
                                            Circle()
                                                .fill(isDone ? self.palette.emerald : tone.opacity(isHover ? 0.14 : 0.06))
                                                .frame(width: 18, height: 18)
                                            Circle()
                                                .strokeBorder(isDone ? self.palette.emerald : tone.opacity(isHover ? 0.90 : 0.55), lineWidth: 1.4)
                                                .frame(width: 18, height: 18)
                                            if isDone {
                                                Image(systemName: "checkmark")
                                                    .font(.system(size: 9.5, weight: .bold))
                                                    .foregroundStyle(Color.white)
                                                    .transition(.scale.combined(with: .opacity))
                                            }
                                        }
                                        .contentShape(Circle().inset(by: -4))
                                    }
                                    .buttonStyle(.plain)
                                    .pointerStyle(.link)
                                    .padding(.top, 1.5)
                                    
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(pred.action)
                                            .font(.system(size: 12.8, weight: (idx == 0 && !isDone) ? .semibold : .medium))
                                            .foregroundStyle(isDone ? self.palette.mutedInk : (idx == 0 ? self.palette.pine : self.palette.secondaryInk))
                                            .strikethrough(isDone, color: self.palette.mutedInk.opacity(0.65))
                                            .lineSpacing(3)
                                            .textSelection(.enabled)
                                            .fixedSize(horizontal: false, vertical: true)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                        
                                        if !pred.reason.isEmpty && !isDone {
                                            Text(pred.reason)
                                                .font(.system(size: 11.2, weight: .regular))
                                                .foregroundStyle(self.palette.mutedInk)
                                                .lineSpacing(2)
                                                .textSelection(.enabled)
                                                .lineLimit(2)
                                        }
                                        
                                        HStack(spacing: 6) {
                                            Text(isDone ? AppLanguage.text("已搞定", en: "Done") : badgeText)
                                                .font(.system(size: 9.5, weight: .semibold))
                                                .foregroundStyle(isDone ? self.palette.emerald : tone)
                                                .padding(.horizontal, 6)
                                                .frame(height: 17)
                                                .background(
                                                    (isDone ? self.palette.emerald : tone).opacity(isDark ? 0.16 : 0.10),
                                                    in: Capsule()
                                                )
                                            
                                            if let linkedDoc {
                                                Button {
                                                    self.onOpenDocument(linkedDoc)
                                                } label: {
                                                    Text(linkedDoc.title)
                                                        .font(.system(size: 10.5, weight: .medium))
                                                        .foregroundStyle(isHover ? self.palette.accentFill : self.palette.mutedInk)
                                                        .lineLimit(1)
                                                        .truncationMode(.middle)
                                                        .padding(.horizontal, 6)
                                                        .frame(height: 17)
                                                        .background(self.palette.card.opacity(0.82), in: Capsule())
                                                        .contentShape(Capsule())
                                                }
                                                .buttonStyle(.plain)
                                                .pointerStyle(.link)
                                            }
                                            
                                            Spacer(minLength: 0)
                                        }
                                    }
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 11)
                                
                                if isHover || isCopied {
                                    Button {
                                        let payload = pred.reason.isEmpty ? pred.action : "\(pred.action)（\(pred.reason)）"
                                        self.onCopy(payload, itemKey)
                                    } label: {
                                        Text(isCopied ? AppLanguage.text("✓ 已复制", en: "✓ Copied") : AppLanguage.text("复制", en: "Copy"))
                                            .font(.system(size: 10, weight: .semibold))
                                            .foregroundStyle(isCopied ? self.palette.tokens.onAccentInk : self.palette.secondaryInk)
                                            .padding(.horizontal, 8)
                                            .frame(height: 20)
                                            .background(
                                                Capsule()
                                                    .fill(isCopied ? self.palette.emerald : self.palette.card.opacity(0.95))
                                                    .shadow(color: self.palette.cardShadow, radius: 4, y: 1)
                                            )
                                            .overlay(
                                                Capsule()
                                                    .strokeBorder(isCopied ? Color.clear : self.palette.hairlineStrong, lineWidth: 0.6)
                                            )
                                            .contentShape(Capsule())
                                    }
                                    .buttonStyle(.plain)
                                    .pointerStyle(.link)
                                    .padding(8)
                                    .transition(.opacity.combined(with: .scale(scale: 0.92)))
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(
                                        isDone
                                            ? self.palette.inset.opacity(0.55)
                                            : (isHigh
                                               ? tone.opacity(isDark ? (isHover ? 0.16 : 0.11) : (isHover ? 0.095 : 0.055))
                                               : (isHover ? self.palette.insetHover : self.palette.inset))
                                    )
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .strokeBorder(
                                        isHover
                                            ? tone.opacity(0.45)
                                            : (isHigh && !isDone ? tone.opacity(0.24) : self.palette.hairline),
                                        lineWidth: isHover ? 1.0 : 0.75
                                    )
                            )
                            .opacity(isDone ? 0.72 : 1.0)
                            .scaleEffect(isHover ? 1.008 : 1.0)
                            .animation(.spring(response: 0.24, dampingFraction: 0.80), value: isHover)
                            .animation(.spring(response: 0.28, dampingFraction: 0.76), value: isDone)
                            .onHover { inside in
                                if inside { self.hoveredID = pred.id }
                                else if self.hoveredID == pred.id { self.hoveredID = nil }
                            }
                            .contextMenu {
                                Button(AppLanguage.text("复制这条建议", en: "Copy")) {
                                    let payload = pred.reason.isEmpty ? pred.action : "\(pred.action)（\(pred.reason)）"
                                    self.onCopy(payload, itemKey)
                                }
                                Button(AppLanguage.text("复制全部行动预测", en: "Copy All")) {
                                    let text = self.predictions.enumerated().map { idx, p in
                                        let suffix = p.reason.isEmpty ? "" : "（\(p.reason)）"
                                        return "\(idx + 1). [\(p.urgency)] \(p.action)\(suffix)"
                                    }.joined(separator: "\n")
                                    self.onCopy(text, "action-all")
                                }
                                if let linkedDoc {
                                    Divider()
                                    Button(AppLanguage.text("打开关联文档：\(linkedDoc.title)", en: "Open Document")) {
                                        self.onOpenDocument(linkedDoc)
                                    }
                                }
                                Divider()
                                Button(AppLanguage.text("重新预测下一步", en: "Refresh"), action: self.onRefresh)
                            }
                        }
                    }
                    .padding(.vertical, 1)
                }
            }
        }
        .padding(self.compact ? 12 : 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .dashboardCardSurface(palette: self.palette, cornerRadius: 16, isHighlighted: self.isCardHovered)
        .animation(.easeOut(duration: 0.16), value: self.isCardHovered)
        .onHover { inside in
            if inside != self.isCardHovered {
                self.isCardHovered = inside
            }
        }
    }
}


/// Isolated NEWS column card rendering a Xiaohongshu-style 2-column visual card grid.
private struct DashboardNewsColumnCard: View {
    
    let compact: Bool
    let cardHeight: CGFloat
    let palette: DashPalette
    let onOpenWorkspace: (String?) -> Void
    
    @State private var newsService = AIHotNewsService.shared
    
    
    var body: some View {
        let items = self.newsService.filteredItems
        
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Button {
                    self.onOpenWorkspace(nil)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "newspaper")
                            .font(.system(size: 13.5, weight: .medium))
                            .foregroundStyle(self.palette.secondaryInk)
                            .frame(width: 16, alignment: .center)
                        
                        Text("NEWS")
                            .font(.system(size: 14, weight: .semibold))
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
                                withAnimation(DashMotion.quick) {
                                    self.newsService.selectedCategory = cat
                                }
                            } label: {
                                Text(cat == .xSocial ? "X" : cat.label)
                                    .font(.system(size: 11, weight: active ? .medium : .regular))
                                    .foregroundStyle(active ? self.palette.tokens.onAccentInk : self.palette.secondaryInk)
                                    .padding(.horizontal, 7)
                                    .frame(height: 20)
                                    .background(
                                        active ? self.palette.accentFill : Color.clear,
                                        in: RoundedRectangle(cornerRadius: 5, style: .continuous)
                                    )
                            }
                            .buttonStyle(.plain)
                            .pointerStyle(.link)
                        }
                    }
                    .padding(2)
                    .background(self.palette.inset, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
                
                Button {
                    Task {
                        await self.newsService.refreshIfNeeded(force: true)
                    }
                } label: {
                    Image(systemName: self.newsService.isLoading ? "hourglass" : "arrow.clockwise")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(self.palette.secondaryInk)
                        .frame(width: 24, height: 24)
                        .background(self.palette.inset, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .buttonStyle(.plain)
                .pointerStyle(.link)
                .disabled(self.newsService.isLoading)
            }
            .frame(height: 24)
            
            GeometryReader { geo in
                let useTwoColumns = !self.compact && geo.size.width >= 220
                let columns: [GridItem] = useTwoColumns
                    ? [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]
                    : [GridItem(.flexible(), spacing: 8)]
                let visibleItems = Array(items.prefix(useTwoColumns ? 6 : 4))
                let coverH: CGFloat = useTwoColumns ? 62 : 52
                
                ScrollView(.vertical, showsIndicators: false) {
                    if visibleItems.isEmpty {
                        if self.newsService.isLoading {
                            LazyVGrid(columns: columns, spacing: 8) {
                                ForEach(0..<(useTwoColumns ? 4 : 2), id: \.self) { _ in
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(self.palette.inset)
                                        .frame(height: coverH + 46)
                                }
                            }
                        } else {
                            Button {
                                Task {
                                    await self.newsService.refreshIfNeeded(force: true)
                                }
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "arrow.clockwise")
                                        .font(.system(size: 12, weight: .medium))
                                    Text(AppLanguage.text("刷新资讯", en: "Refresh News"))
                                        .font(.system(size: 12.5, weight: .medium))
                                }
                                .foregroundStyle(self.palette.secondaryInk)
                                .padding(.horizontal, 12)
                                .frame(height: 32)
                                .background(self.palette.inset, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .frame(maxWidth: .infinity, minHeight: 120)
                        }
                    } else {
                        LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                            ForEach(visibleItems) { item in
                                NewsMiniVisualCard(
                                    item: item,
                                    cover: self.newsService.coverImage(for: item),
                                    isRead: self.newsService.isRead(item),
                                    coverHeight: coverH,
                                    palette: self.palette
                                ) {
                                    self.onOpenWorkspace(item.id)
                                }
                            }
                        }
                        .padding(.bottom, 2)
                    }
                }
            }
        }
        .padding(self.compact ? 12 : 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .dashboardCardSurface(palette: self.palette, cornerRadius: 16)
    }
}


private struct NewsMiniVisualCard: View {
    
    let item: AIHotNewsItem
    let cover: NSImage?
    let isRead: Bool
    let coverHeight: CGFloat
    let palette: DashPalette
    let onTap: () -> Void
    
    @State private var isHovered = false
    
    
    var body: some View {
        let publisher = self.item.displayPublisherLabel
        
        Button(action: self.onTap) {
            VStack(alignment: .leading, spacing: 6) {
                ZStack(alignment: .topLeading) {
                    if let cover = self.cover {
                        GeometryReader { geo in
                            Image(nsImage: cover)
                                .resizable()
                                .interpolation(.high)
                                .scaledToFill()
                                .frame(width: geo.size.width, height: geo.size.height)
                                .clipped()
                        }
                    } else {
                        self.fallbackCover
                    }
                    
                    if !self.isRead {
                        Circle()
                            .fill(self.palette.accentFill)
                            .frame(width: 6, height: 6)
                            .padding(6)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: self.coverHeight)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                
                Text(self.item.title)
                    .font(.system(size: 11.5, weight: self.isRead ? .regular : .medium))
                    .foregroundStyle(self.isRead ? self.palette.secondaryInk : self.palette.pine)
                    .lineLimit(2)
                    .lineSpacing(1.5)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, minHeight: 28, alignment: .topLeading)
                
                Text(publisher.isEmpty ? self.item.resolvedCategory.label : publisher)
                    .font(.system(size: 10, weight: .regular))
                    .foregroundStyle(self.palette.mutedInk)
                    .lineLimit(1)
            }
            .padding(6)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(self.isHovered ? self.palette.insetHover : self.palette.inset)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(self.isHovered ? self.palette.accentFill.opacity(0.35) : self.palette.hairline, lineWidth: 0.7)
            )
        }
        .buttonStyle(.plain)
        .pointerStyle(.link)
        .onHover { hovering in
            if hovering != self.isHovered {
                self.isHovered = hovering
            }
        }
    }
    
    
    private var fallbackCover: some View {
        let seed = abs(self.item.id.hashValue)
        let tint: Color = switch seed % 4 {
            case 0: self.palette.accentFill
            case 1: self.palette.mint
            case 2: self.palette.statusPositive
            default: self.palette.emerald
        }
        return ZStack(alignment: .bottomLeading) {
            LinearGradient(
                colors: [tint.opacity(self.palette.tokens.isDark ? 0.34 : 0.22), tint.opacity(0.06)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Text(self.item.resolvedCategory.label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(self.palette.pine.opacity(0.72))
                .padding(.horizontal, 7)
                .padding(.vertical, 5)
        }
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
    @State private var isDanmakuEnabled: Bool
    @State private var isArtHovered = false
    @State private var isArtPressed = false
    @State private var hoverNorm = CGPoint(x: 0.5, y: 0.5)
    @State private var tapPulseCount: Int = 0
    @State private var isBackHovered = false
    @State private var isToggleHovered = false
    @State private var brandLineEngine = BrandLinePassEngine()
    @State private var asciiMatrix: [[CotPassArtEngine.ASCIIPixelCell]] = []
    @State private var impastoTiles: [CotPassArtEngine.ImpastoTile] = []
    @State private var cachedArtSize: CGSize = .zero
    @State private var cachedArtSeed: Int = -1
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
        let syncedStyle = CotPassTheme.themeIndex(for: StudioPaletteManager.shared.selectedID)
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
        
        _passStyleIndex = State(initialValue: syncedStyle)
        _serialCode = State(initialValue: serial)
        _hasProLicense = State(initialValue: tier != .explorer)
        _isDanmakuEnabled = State(initialValue: rawDanmaku == "true" || rawDanmaku == "1")
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
    
    
    var body: some View {
        let streakDays = max(1, self.snapshot.currentStreak)
        let todayTotal = self.snapshot.today.typedChars + self.snapshot.today.aiCompletedChars
        let avg14 = Int(self.snapshot.trendCurve14.averageValue.rounded())
        let cardSeed = CotPassArtEngine.deterministicSeed(from: "\(self.passStyleIndex):\(self.serialCode)")
        let items = self.danmakuItems
        
        HStack(spacing: 0) {
            self.identityZone
            
            Rectangle()
                .fill(self.palette.hairline)
                .frame(width: 1)
                .padding(.vertical, self.compact ? 10 : 14)
            
            self.overviewZone(
                todayTotal: todayTotal,
                streakDays: streakDays,
                avg14: avg14,
                items: items
            )
            
            self.perforatedSeam
            
            self.integratedPassGalleryStub(seed: cardSeed)
                .padding(self.compact ? 8 : 10)
                .frame(width: self.compact ? 172 : 216)
                .frame(maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .dashboardCardSurface(palette: self.palette, cornerRadius: 16)
    }
    
    
    private var perforatedSeam: some View {
        Canvas { ctx, size in
            var line = Path()
            line.move(to: CGPoint(x: size.width * 0.5, y: 10))
            line.addLine(to: CGPoint(x: size.width * 0.5, y: size.height - 10))
            ctx.stroke(
                line,
                with: .color(self.palette.hairlineStrong),
                style: StrokeStyle(lineWidth: 1, dash: [3, 4])
            )
        }
        .frame(width: 1)
    }
    
    
    private var identityZone: some View {
        let ambient = AvatarColorExtractor.extractPalette(for: self.profile, image: self.avatarImage)
        let blurredCover = AvatarColorExtractor.blurredAmbientArtwork(for: self.profile, image: self.avatarImage)
        let accentColor = ambient.accent
        let isDark = self.palette.tokens.isDark
        
        return ZStack(alignment: .topLeading) {
            // Main immersed Avatar + Display Name centerpiece
            HStack(alignment: .center, spacing: 14) {
                self.authorPortrait(size: self.compact ? 44 : 52, accent: accentColor)
                
                VStack(alignment: .leading, spacing: 3) {
                    Text(self.profile.displayName)
                        .font(.system(size: self.compact ? 17 : 20, weight: .bold))
                        .foregroundStyle(self.palette.pine)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                    
                    HStack(spacing: 5) {
                        Circle()
                            .fill(accentColor)
                            .frame(width: 5.5, height: 5.5)
                        Text(self.snapshot.mood.dominantLabel)
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(self.palette.secondaryInk)
                            .lineLimit(1)
                    }
                }
                
                Spacer(minLength: 0)
            }
            .padding(.horizontal, self.compact ? 16 : 20)
            .padding(.top, self.onBack != nil ? (self.compact ? 12 : 14) : 0)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            
            // Ultra-light unobtrusive "返回" ghost trigger tucked cleanly at top-left
            if let onBack = self.onBack {
                Button(action: onBack) {
                    HStack(spacing: 2.5) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 9.5, weight: .semibold))
                        Text(AppLanguage.text("返回", en: "Back"))
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundStyle(self.isBackHovered ? self.palette.pine : self.palette.secondaryInk.opacity(0.72))
                    .padding(.horizontal, 7)
                    .frame(height: 20)
                    .background(
                        Capsule()
                            .fill(self.isBackHovered ? self.palette.card.opacity(0.82) : Color.clear)
                    )
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .pointerStyle(.link)
                .onHover { hovering in
                    if hovering != self.isBackHovered {
                        self.isBackHovered = hovering
                    }
                }
                .padding(.leading, 10)
                .padding(.top, 7)
            }
        }
        .frame(minWidth: self.compact ? 216 : 268, maxWidth: self.compact ? 252 : 308, maxHeight: .infinity, alignment: .leading)
        // Strictly non-layout-affecting ambient avatar backdrop
        .background {
            Color.clear
                .overlay {
                    ZStack {
                        if let blurredCover {
                            Image(nsImage: blurredCover)
                                .resizable()
                                .scaledToFill()
                                .opacity(isDark ? 0.28 : 0.20)
                                .blur(radius: 22)
                        }
                        LinearGradient(
                            colors: [
                                accentColor.opacity(isDark ? 0.34 : 0.20),
                                accentColor.opacity(isDark ? 0.10 : 0.05),
                                Color.clear,
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    }
                }
                .clipped()
                .allowsHitTesting(false)
        }
        .clipped()
    }
    
    
    private func overviewZone(
        todayTotal: Int,
        streakDays: Int,
        avg14: Int,
        items: [DashboardHeroDanmakuScheduler.Item]
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center) {
                Text(AppLanguage.text("创作概览", en: "Overview"))
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(self.palette.mutedInk)
                
                Spacer(minLength: 6)
                
                self.danmakuToggleButton
            }
            
            Spacer(minLength: 6)
            
            if self.isDanmakuEnabled {
                GeometryReader { stageGeo in
                    TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
                        let elapsed = max(0, timeline.date.timeIntervalSince(self.startDate))
                        self.inlineDanmakuTrack(size: stageGeo.size, items: items, elapsed: elapsed)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
            } else {
                HStack(alignment: .lastTextBaseline, spacing: self.compact ? 14 : 24) {
                    self.headerStatBlock(
                        label: AppLanguage.text("今日码字", en: "Today"),
                        value: todayTotal.formatted(),
                        unit: AppLanguage.text("字", en: "ch"),
                        emphasize: true
                    )
                    
                    self.headerStatBlock(
                        label: AppLanguage.text("连续", en: "Streak"),
                        value: "\(streakDays)",
                        unit: AppLanguage.text("天", en: "d"),
                        emphasize: false
                    )
                    
                    self.headerStatBlock(
                        label: AppLanguage.text("年度活跃", en: "Active"),
                        value: "\(self.snapshot.yearlyHeatmap.activeDays)",
                        unit: AppLanguage.text("天", en: "d"),
                        emphasize: false
                    )
                    
                    if !self.compact && avg14 > 0 {
                        self.headerStatBlock(
                            label: AppLanguage.text("14日均", en: "14d"),
                            value: avg14.formatted(),
                            unit: AppLanguage.text("字", en: "ch"),
                            emphasize: false
                        )
                    }
                    
                    Spacer(minLength: 0)
                }
                
                Spacer(minLength: 2)
            }
        }
        .padding(.horizontal, self.compact ? 12 : 16)
        .padding(.vertical, self.compact ? 10 : 13)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
    
    
    private var danmakuToggleButton: some View {
        Button {
            let next = !self.isDanmakuEnabled
            if next {
                self.startDate = Date()
            }
            withAnimation(DashMotion.quick) {
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
                    .foregroundStyle(self.isDanmakuEnabled ? self.palette.pine : self.palette.mutedInk)
                
                ZStack(alignment: self.isDanmakuEnabled ? .trailing : .leading) {
                    Capsule()
                        .fill(self.isDanmakuEnabled ? self.palette.accentFill : self.palette.insetHover)
                        .frame(width: 24, height: 14)
                    Circle()
                        .fill(Color.white)
                        .frame(width: 10, height: 10)
                        .padding(.horizontal, 2)
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 24)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(self.isToggleHovered ? self.palette.insetHover : self.palette.inset)
            )
            .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
        .pointerStyle(.link)
        .onHover { hovering in
            if hovering != self.isToggleHovered {
                self.isToggleHovered = hovering
            }
        }
    }
    
    
    private func authorPortrait(size: CGFloat, accent: Color) -> some View {
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
        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [Color.white.opacity(0.65), accent.opacity(0.55)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.4
                )
        )
        .shadow(color: accent.opacity(0.28), radius: 10, y: 4)
    }
    
    
    private func microPixelBadge(seed: Int) -> some View {
        HStack(spacing: 1.5) {
            ForEach(0..<5, id: \.self) { col in
                VStack(spacing: 1.5) {
                    ForEach(0..<2, id: \.self) { row in
                        let on = ((seed >> (col + row * 3)) & 1) == 1
                        Rectangle()
                            .fill(on ? self.palette.accentFill : self.palette.pine.opacity(0.18))
                            .frame(width: 2.5, height: 2.5)
                    }
                }
            }
        }
    }
    
    
    private func headerStatBlock(label: String, value: String, unit: String, emphasize: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(self.palette.mutedInk)
                .lineLimit(1)
            
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.system(size: self.compact ? 16 : 19, weight: .semibold).monospacedDigit())
                    .foregroundStyle(emphasize ? self.palette.emerald : self.palette.pine)
                    .lineLimit(1)
                Text(unit)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(self.palette.mutedInk)
                    .lineLimit(1)
            }
        }
    }
    
    
    private func inlineDanmakuTrack(
        size: CGSize,
        items: [DashboardHeroDanmakuScheduler.Item],
        elapsed: TimeInterval
    ) -> some View {
        let laneCount = 2
        let lanePitch: CGFloat = max(28, size.height / CGFloat(laneCount))
        let maxW = items.map { DashboardHeroDanmakuScheduler.estimatedPillSize(for: $0.text).width }.max() ?? 110
        let step = maxW + 24
        let cycle = max(size.width + maxW + 40, CGFloat(max(1, items.count)) * step * 0.5)
        
        return ZStack(alignment: .topLeading) {
            ForEach(Array(items.enumerated()), id: \.element.id) { idx, item in
                let lane = idx % laneCount
                let pillSize = DashboardHeroDanmakuScheduler.estimatedPillSize(for: item.text)
                let speed: CGFloat = lane == 0 ? 18.0 : 14.5
                let raw = CGFloat(elapsed) * speed + CGFloat(idx / laneCount) * step + (lane == 1 ? step * 0.5 : 0)
                let travel = raw.truncatingRemainder(dividingBy: cycle)
                let centerX = (size.width + maxW * 0.5) - travel
                let centerY = (CGFloat(lane) + 0.5) * lanePitch
                let edgeDist = min(centerX - pillSize.width * 0.5, size.width - (centerX + pillSize.width * 0.5))
                let fade = min(1.0, max(0.0, Double(edgeDist / 24.0)))
                if fade > 0.02 {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(self.palette.toneColor(for: item.tone))
                            .frame(width: 4.5, height: 4.5)
                        Text(item.text)
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(self.palette.pine)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 9)
                    .frame(height: 24)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(self.palette.inset)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .strokeBorder(self.palette.hairline, lineWidth: 0.75)
                            )
                    )
                    .position(x: centerX, y: centerY)
                    .opacity(fade)
                }
            }
        }
    }
    
    
    private func integratedPassGalleryStub(seed: Int) -> some View {
        let activeTheme = CotPassTheme.resolve(index: self.passStyleIndex)
        let tiltX = self.isArtHovered ? Double((self.hoverNorm.y - 0.5) * -7.5) : 0
        let tiltY = self.isArtHovered ? Double((self.hoverNorm.x - 0.5) * 9.5) : 0
        
        return GeometryReader { geo in
            let rect = CGRect(origin: .zero, size: geo.size)
            ZStack {
                // Authentic LeiBox Fluted Glass Prism (leibox.pantoria.cn/docs/animations/blue-fluted-glass)
                LeiBoxFlutedPrismView(
                    theme: activeTheme,
                    renderWidth: 164,
                    renderHeight: 96,
                    ribCount: 38.0,
                    animate: true,
                    specularPoint: UnitPoint(x: self.hoverNorm.x, y: self.hoverNorm.y),
                    isHovered: self.isArtHovered
                )
                .frame(width: rect.width, height: rect.height)
                .clipped()
                .allowsHitTesting(false)
                
                // Bottom minimal colorway switcher readout & dots
                VStack {
                    Spacer()
                    HStack(alignment: .center, spacing: 6) {
                        Text(activeTheme.title)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color.white.opacity(0.92))
                            .fixedSize(horizontal: true, vertical: false)
                        
                        Spacer(minLength: 4)
                        
                        HStack(spacing: 3.5) {
                            ForEach(CotPassTheme.allThemes) { theme in
                                let isActive = (theme.id == activeTheme.id)
                                Capsule()
                                    .fill(isActive ? Color.white : Color.white.opacity(0.38))
                                    .frame(width: isActive ? 11 : 4, height: 4)
                            }
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(
                        LinearGradient(
                            colors: [Color.clear, Color.black.opacity(0.42)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                }
                .allowsHitTesting(false)
            }
            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(
                        Color.white.opacity(self.isArtHovered ? 0.48 : 0.22),
                        lineWidth: self.isArtHovered ? 1.1 : 0.8
                    )
            )
            .scaleEffect(self.isArtPressed ? 0.965 : (self.isArtHovered ? 1.018 : 1.0))
            .rotation3DEffect(.degrees(tiltX), axis: (x: 1, y: 0, z: 0), perspective: 0.6)
            .rotation3DEffect(.degrees(tiltY), axis: (x: 0, y: 1, z: 0), perspective: 0.6)
            .animation(.spring(response: 0.24, dampingFraction: 0.76), value: self.isArtHovered)
            .animation(.spring(response: 0.18, dampingFraction: 0.68), value: self.isArtPressed)
            .animation(.easeOut(duration: 0.22), value: self.passStyleIndex)
            .contentShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            .onContinuousHover { phase in
                switch phase {
                    case .active(let loc):
                        if !self.isArtHovered { self.isArtHovered = true }
                        let nx = max(0, min(1, loc.x / max(1, rect.width)))
                        let ny = max(0, min(1, loc.y / max(1, rect.height)))
                        if abs(nx - self.hoverNorm.x) > 0.02 || abs(ny - self.hoverNorm.y) > 0.02 {
                            self.hoverNorm = CGPoint(x: nx, y: ny)
                        }
                    case .ended:
                        if self.isArtHovered { self.isArtHovered = false }
                        self.hoverNorm = CGPoint(x: 0.5, y: 0.5)
                }
            }
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        if !self.isArtPressed { self.isArtPressed = true }
                    }
                    .onEnded { value in
                        self.isArtPressed = false
                        if rect.insetBy(dx: -8, dy: -8).contains(value.location) {
                            let next = (self.passStyleIndex + 1) % CotPassTheme.allThemes.count
                            let nextTheme = CotPassTheme.resolve(index: next)
                            self.passStyleIndex = next
                            self.tapPulseCount &+= 1
                            CotLocalDatabase.shared.set("\(next)", forKey: CotLocalDatabase.ConfigKey.cotPassStyleIndex)
                            StudioPaletteManager.shared.selectPalette(nextTheme.pairedStudioPalette, syncEditorTheme: true)
                        }
                    }
            )
            .pointerStyle(.link)
            .help(AppLanguage.text("点击切换棱镜与全局配色", en: "Click to switch prism & global palette"))
        }
    }
    
    
    private func syncStubCaches(seed: Int) {
        self.brandLineEngine.syncAvatarContour(profile: self.profile, avatarImage: self.avatarImage)
        self.asciiMatrix = CotPassArtEngine.buildASCIIPixelMatrix(
            from: self.brandLineEngine.contourField,
            cols: self.compact ? 8 : 9,
            rows: self.compact ? 5 : 6
        )
        if self.cachedArtSeed != seed, self.cachedArtSize.width > 20 {
            self.cachedArtSeed = seed
            self.impastoTiles = CotPassArtEngine.computeImpastoTiles(
                seed: seed,
                in: CGRect(origin: .zero, size: self.cachedArtSize)
            )
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
            // Top Live-Activity Telemetry Strip (enriched with week sum, peak day & hand/AI breakdown)
            let week7Total = self.days14.suffix(7).reduce(0) { $0 + $1.typed + $1.ai }
            let peakDayChars = self.yearlyHeatmap.weeks.flatMap { $0 }.map { $0.typedChars + $0.aiCompletedChars }.max() ?? 0
            
            HStack(alignment: .center, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(isInspecting ? readout.label : AppLanguage.text("今日码字", en: "Typed Today"))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(isInspecting ? self.palette.emerald : self.palette.mutedInk)
                    
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text(readout.total.formatted())
                            .font(.system(size: self.compact ? 17 : 20, weight: .semibold).monospacedDigit())
                            .foregroundStyle(isInspecting ? self.palette.emerald : self.palette.pine)
                            .contentTransition(.numericText())
                        Text("字")
                            .font(.system(size: 11, weight: .regular))
                            .foregroundStyle(self.palette.mutedInk)
                    }
                }
                
                if !self.compact {
                    HStack(spacing: 6) {
                        if readout.total > 0 {
                            let handPct = Int((Double(readout.typed) / Double(max(1, readout.total)) * 100.0).rounded())
                            Text("手写 \(handPct)%")
                                .font(.system(size: 10.5, weight: .medium, design: .rounded).monospacedDigit())
                                .foregroundStyle(self.palette.emerald)
                                .padding(.horizontal, 7)
                                .frame(height: 20)
                                .background(self.palette.tokens.positivePillBg, in: Capsule())
                        }
                        
                        Text("近7日 \(week7Total.formatted())")
                            .font(.system(size: 10.5, weight: .medium, design: .rounded).monospacedDigit())
                            .foregroundStyle(self.palette.secondaryInk)
                            .padding(.horizontal, 7)
                            .frame(height: 20)
                            .background(self.palette.inset, in: Capsule())
                        
                        if peakDayChars > 0 {
                            Text("峰值 \(peakDayChars.formatted())")
                                .font(.system(size: 10.5, weight: .medium, design: .rounded).monospacedDigit())
                                .foregroundStyle(self.palette.mutedInk)
                                .padding(.horizontal, 7)
                                .frame(height: 20)
                                .background(self.palette.inset, in: Capsule())
                        }
                    }
                }
                
                Spacer(minLength: 4)
                
                // Compact Intensity Scale Legend
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
                            self.selectedYear = prev
                        }
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 9.5, weight: .semibold))
                            .foregroundStyle(self.previousYear != nil ? self.palette.secondaryInk : self.palette.pine.opacity(0.20))
                            .frame(width: 20, height: 20)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(self.previousYear == nil)
                    
                    Text("\(String(self.yearlyHeatmap.year))")
                        .font(.system(size: 11.5, weight: .medium, design: .monospaced).monospacedDigit())
                        .foregroundStyle(self.palette.pine)
                    
                    Button {
                        if let next = self.nextYear {
                            self.selectedYear = next
                        }
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9.5, weight: .semibold))
                            .foregroundStyle(self.nextYear != nil ? self.palette.secondaryInk : self.palette.pine.opacity(0.20))
                            .frame(width: 20, height: 20)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(self.nextYear == nil)
                }
                .padding(.horizontal, 4)
                .frame(height: 22)
                .background(self.palette.inset, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
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
                                Gradient(colors: [self.palette.accentFill.opacity(0.14), self.palette.accentFill.opacity(0.01)]),
                                startPoint: CGPoint(x: size.width * 0.5, y: padTop),
                                endPoint: CGPoint(x: size.width * 0.5, y: baseY)
                            )
                        )
                        context.stroke(
                            linePath,
                            with: .color(self.palette.accentFill),
                            style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round)
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
                .frame(height: self.compact ? 44 : 60)
            }
            .padding(.top, 2)
        }
        .padding(self.compact ? 12 : 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .dashboardCardSurface(palette: self.palette, cornerRadius: 16)
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
        let costEstimate = AIModelPricingCatalog.estimateTotalCost(models: self.snapshot.aiModels, fallbackTotals: totals)
        
        let inTok = max(0, totals.inputTokens)
        let outTok = max(0, totals.outputTokens)
        let inFrac: Double = (inTok + outTok) > 0 ? Double(inTok) / Double(inTok + outTok) : 0.62
        let inPct = Int((inFrac * 100).rounded())
        let outPct = max(0, 100 - inPct)
        
        let topModels: [(name: String, share: Int, rmb: String, color: Color)] = {
            let colors: [Color] = [self.palette.accentFill, self.palette.emerald, self.palette.mint]
            let models = Array(self.snapshot.aiModels.prefix(3))
            if !models.isEmpty {
                let sum = max(1.0, models.reduce(0.0) { $0 + Double($1.totalTokens > 0 ? $1.totalTokens : max(1, $1.requests * 150)) })
                return models.enumerated().map { idx, m in
                    let w = Double(m.totalTokens > 0 ? m.totalTokens : max(1, m.requests * 150))
                    let short = m.model.count <= 13 ? m.model : String(m.model.prefix(12)) + "…"
                    let modelCost = AIModelPricingCatalog.estimateCost(model: m.model, inputTokens: m.inputTokens, outputTokens: m.outputTokens)
                    return (short, Int(((w / sum) * 100).rounded()), modelCost.formattedRMB, colors[idx % colors.count])
                }
            }
            return [
                ("主力模型", 62, "¥0.00", self.palette.accentFill),
                ("轻量模型", 38, "¥0.00", self.palette.mint),
            ]
        }()
        
        Button(action: self.onTap) {
            HStack(spacing: 12) {
                ZStack {
                    AIUsageSunburstChartView(snapshot: self.snapshot, palette: self.palette, detailed: false)
                        .frame(width: 96, height: 96)
                    
                    VStack(spacing: 0.5) {
                        Text(costEstimate.formattedRMB)
                            .font(.system(size: 11.5, weight: .bold, design: .rounded).monospacedDigit())
                            .foregroundStyle(self.palette.pine)
                        Text(Self.compactTokens(displayTokens))
                            .font(.system(size: 8.5, weight: .medium, design: .monospaced).monospacedDigit())
                            .foregroundStyle(self.palette.mutedInk)
                    }
                    .allowsHitTesting(false)
                }
                .frame(width: 98, height: 98)
                
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .center, spacing: 8) {
                        Text(AppLanguage.text("AI 用量", en: "AI Usage"))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(self.palette.mutedInk)
                        
                        HStack(alignment: .firstTextBaseline, spacing: 3) {
                            Text(Self.compactTokens(totals.totalTokens))
                                .font(.system(size: 17, weight: .semibold).monospacedDigit())
                                .foregroundStyle(self.palette.pine)
                            Text("tok")
                                .font(.system(size: 10.5, weight: .regular))
                                .foregroundStyle(self.palette.mutedInk)
                        }
                        
                        // Real official API cost estimate (RMB + USD)
                        HStack(spacing: 4) {
                            Text(costEstimate.formattedRMB)
                                .font(.system(size: 11.5, weight: .bold, design: .rounded).monospacedDigit())
                                .foregroundStyle(self.palette.emerald)
                            Text("(\(costEstimate.formattedUSD))")
                                .font(.system(size: 10, weight: .medium, design: .monospaced).monospacedDigit())
                                .foregroundStyle(self.palette.secondaryInk)
                        }
                        .padding(.horizontal, 7)
                        .frame(height: 21)
                        .background(self.palette.tokens.positivePillBg, in: Capsule())
                        
                        Spacer(minLength: 4)
                        
                        Text("\(displayReqs) 次")
                            .font(.system(size: 10.5, weight: .medium, design: .monospaced).monospacedDigit())
                            .foregroundStyle(self.palette.mutedInk)
                    }
                    
                    VStack(spacing: 4) {
                        GeometryReader { barGeo in
                            let w = max(40, barGeo.size.width)
                            let splitX = max(14, min(w - 14, w * CGFloat(inFrac)))
                            HStack(spacing: 2) {
                                RoundedRectangle(cornerRadius: 3, style: .continuous)
                                    .fill(self.palette.accentFill)
                                    .frame(width: max(8, splitX - 1))
                                
                                RoundedRectangle(cornerRadius: 3, style: .continuous)
                                    .fill(self.palette.mint.opacity(0.65))
                                    .frame(maxWidth: .infinity)
                            }
                        }
                        .frame(height: 6)
                        
                        HStack {
                            Text("输入 \(Self.compactTokens(inTok)) · \(inPct)%")
                                .font(.system(size: 10.5, weight: .regular).monospacedDigit())
                                .foregroundStyle(self.palette.secondaryInk)
                            Spacer()
                            Text("生成 \(Self.compactTokens(outTok)) · \(outPct)%")
                                .font(.system(size: 10.5, weight: .regular).monospacedDigit())
                                .foregroundStyle(self.palette.mutedInk)
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
                                        .font(.system(size: 10.5, weight: .medium))
                                        .foregroundStyle(self.palette.secondaryInk)
                                        .lineLimit(1)
                                    Text("\(m.rmb)")
                                        .font(.system(size: 10, weight: .semibold, design: .monospaced).monospacedDigit())
                                        .foregroundStyle(self.palette.pine)
                                }
                                .padding(.horizontal, 7)
                                .frame(height: 22)
                                .background(self.palette.inset, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                            }
                        }
                        
                        Spacer(minLength: 4)
                        
                        HStack(alignment: .bottom, spacing: 3) {
                            let aiMax = max(20.0, self.snapshot.days14.map { Double($0.ai) }.max() ?? 20.0)
                            ForEach(Array(self.snapshot.days14.suffix(10).enumerated()), id: \.offset) { idx, day in
                                let frac = CGFloat(Double(day.ai) / aiMax)
                                let h = max(4, frac * 16)
                                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                                    .fill(day.ai > 0 ? (idx == 9 ? self.palette.accentFill : self.palette.accentFill.opacity(0.45)) : self.palette.emptyDot)
                                    .frame(width: 3, height: h)
                            }
                        }
                        .frame(height: 16, alignment: .bottom)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .dashboardCardSurface(palette: self.palette, cornerRadius: 16, isHighlighted: self.isHovered)
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .pointerStyle(.link)
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
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .dashboardCardSurface(palette: self.palette, cornerRadius: 16, isHighlighted: self.isHovered)
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
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
    let palette: DashPalette
    let onClose: () -> Void
    
    @State private var hoverDetail: String?
    
    
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
                    .allowsHitTesting(false)
                
                Button(action: self.onClose) {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(self.palette.pine.opacity(0.70))
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(self.palette.inset))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .pointerStyle(.link)
            }
            .frame(height: 26)
            
            self.detailedVisualization
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .dashboardCardSurface(palette: self.palette, cornerRadius: 16, isHighlighted: true)
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
    let isMark: Bool
    let a0: Double
    let a1: Double
    let r0Ratio: CGFloat
    let r1Ratio: CGFloat
    let toneKey: Int
    
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
                
                let isHovered = (self.hoveredNodeID == arc.nodeID)
                let baseColor = AIUsageSunburstChartView.color(forToneKey: arc.toneKey, palette: self.palette)
                let opacityMod: Double = (!hasHover || isHovered) ? 1.0 : 0.36
                context.fill(path, with: .color(baseColor.opacity(opacityMod)))
                context.stroke(
                    path,
                    with: .color(self.palette.card),
                    style: StrokeStyle(lineWidth: arc.isMark ? 0.75 : 1.4, lineJoin: .round)
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
    let isOpenHeader: Bool
    let isSubRow: Bool
    let isHovered: Bool
    let toneKey: Int
    let isDark: Bool
    let palette: DashPalette
    let onTap: () -> Void
    let onHoverChanged: (Bool) -> Void
    
    static func == (lhs: SunburstLedgerRowView, rhs: SunburstLedgerRowView) -> Bool {
        lhs.nodeID == rhs.nodeID
            && lhs.name == rhs.name
            && lhs.compactValue == rhs.compactValue
            && lhs.percentText == rhs.percentText
            && lhs.isOpenHeader == rhs.isOpenHeader
            && lhs.isSubRow == rhs.isSubRow
            && lhs.isHovered == rhs.isHovered
            && lhs.toneKey == rhs.toneKey
            && lhs.isDark == rhs.isDark
    }
    
    var body: some View {
        Button(action: self.onTap) {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(AIUsageSunburstChartView.color(forToneKey: self.toneKey, palette: self.palette))
                    .frame(width: 8, height: 8)
                
                Text(self.name)
                    .font(.system(size: 12.5, weight: self.isOpenHeader ? .medium : .regular))
                    .foregroundStyle(self.isOpenHeader ? self.palette.pine : self.palette.pine.opacity(0.84))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                Text(self.compactValue)
                    .font(.system(size: 12, weight: .medium, design: .rounded).monospacedDigit())
                    .foregroundStyle(self.palette.pine)
                    .frame(minWidth: 50, alignment: .trailing)
                
                Text(self.percentText)
                    .font(.system(size: 11.5, weight: .regular, design: .rounded).monospacedDigit())
                    .foregroundStyle(self.palette.pine.opacity(0.46))
                    .frame(width: 42, alignment: .trailing)
            }
            .padding(.leading, self.isSubRow ? 20 : 8)
            .padding(.trailing, 8)
            .frame(minHeight: 26)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(self.isHovered ? self.palette.insetHover : Color.clear)
            )
            .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
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
    @State private var openID: String?
    @State private var hoveredNodeID: String?
    @State private var isCenterHovered = false
    
    @State private var cachedFocus: EvalSunburstLayoutEngine.Node?
    @State private var cachedArcs: [EvalSunburstLayoutEngine.ArcItem] = []
    @State private var cachedRenderArcs: [SunburstRenderArc] = []
    @State private var cachedRows: [EvalSunburstLayoutEngine.LedgerRow] = []
    @State private var dialScalePulse: CGFloat = 1.0
    
    
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
        let renderArcs = layout.arcs.map { arc in
            SunburstRenderArc(
                key: arc.key,
                nodeID: arc.node.id,
                isMark: arc.isMark,
                a0: arc.a0,
                a1: arc.a1,
                r0Ratio: arc.r0Ratio,
                r1Ratio: arc.r1Ratio,
                toneKey: Self.toneKey(for: arc.tone)
            )
        }
        
        self.cachedFocus = resolved.focus
        self.cachedArcs = layout.arcs
        self.cachedRenderArcs = renderArcs
        self.cachedRows = layout.rows
        
        if animated {
            // Fast GPU-composited spring pulse — zero per-frame Path re-tessellation on main thread
            self.dialScalePulse = 0.96
            withAnimation(.spring(response: 0.22, dampingFraction: 0.80)) {
                self.dialScalePulse = 1.0
            }
        }
    }
    
    
    fileprivate static func toneKey(for tone: EvalSunburstLayoutEngine.ArcItem.ToneKind) -> Int {
        switch tone {
            case .openActive: 0
            case .sibling: 1
            case .otherInner: 2
            case .otherOuter: 3
            case .outputMark: 4
            case .outerIndexed(let index, let count):
                100 + min(20, max(1, count)) * 32 + min(31, max(0, index))
        }
    }
    
    
    fileprivate static func color(forToneKey key: Int, palette: DashPalette) -> Color {
        switch key {
            case 0: return palette.accentFill
            case 1: return palette.pine.opacity(0.38)
            case 2: return palette.pine.opacity(0.22)
            case 3: return palette.pine.opacity(0.14)
            case 4: return palette.emerald.opacity(0.88)
            default:
                let encoded = max(0, key - 100)
                let count = max(1, encoded / 32)
                let index = encoded % 32
                let share = count > 1 ? 0.92 - (Double(index) * 0.56 / Double(count - 1)) : 0.92
                return palette.accentFill.opacity(share)
        }
    }
    
    
    private func updateHover(_ nextID: String?) {
        guard nextID != self.hoveredNodeID else { return }
        self.hoveredNodeID = nextID
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
        let focus = self.cachedFocus ?? self.snapshot.sunburstRoot
        let renderArcs: [SunburstRenderArc] = self.cachedFocus != nil
            ? self.cachedRenderArcs
            : {
                let resolved = self.resolveFocusAndOpen(focusID: self.focusID, openID: self.openID)
                return EvalSunburstLayoutEngine.layout(focus: resolved.focus, open: resolved.open).arcs.map { arc in
                    SunburstRenderArc(
                        key: arc.key,
                        nodeID: arc.node.id,
                        isMark: arc.isMark,
                        a0: arc.a0,
                        a1: arc.a1,
                        r0Ratio: arc.r0Ratio,
                        r1Ratio: arc.r1Ratio,
                        toneKey: Self.toneKey(for: arc.tone)
                    )
                }
            }()
        let arcs = self.cachedFocus != nil ? self.cachedArcs : []
        let rows = self.cachedFocus != nil ? self.cachedRows : []
        
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
                .allowsHitTesting(false)
            } else {
                GeometryReader { geo in
                    let dialSide = min(max(148, geo.size.height - 8), max(148, geo.size.width * 0.44))
                    HStack(alignment: .center, spacing: 18) {
                        self.sunburstDial(focus: focus, arcs: arcs, renderArcs: renderArcs)
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
    
    
    private func sunburstDial(
        focus: EvalSunburstLayoutEngine.Node,
        arcs: [EvalSunburstLayoutEngine.ArcItem],
        renderArcs: [SunburstRenderArc]
    ) -> some View {
        GeometryReader { geo in
            let size = geo.size
            let center = CGPoint(x: size.width * 0.5, y: size.height * 0.5)
            let radius = max(16, min(size.width, size.height) * 0.5 - 4)
            let holeRadius = radius * (52.0 / 110.0)
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
                .scaleEffect(self.dialScalePulse)
                .allowsHitTesting(false)
                
                // Center readout (non-interactive overlay — single unified hit-test below avoids hover fighting)
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
                    if up != nil {
                        Text(focus.name)
                            .font(.system(size: 10.5, weight: .regular))
                            .foregroundStyle(self.palette.pine.opacity(0.55))
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
                            let hitID = self.hitTest(pt, center: center, radius: radius, arcs: arcs)?.node.id
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
                    self.openID = focus.id
                    self.focusID = up.id
                    self.isCenterHovered = false
                    self.updateHover(nil)
                    self.syncLayout(animated: true)
                    return
                }
                if let hit = self.hitTest(pt, center: center, radius: radius, arcs: arcs) {
                    self.handleSelect(node: hit.node, ring: hit.ring)
                }
            }
        }
    }
    
    
    private func ledgerView(rows: [EvalSunburstLayoutEngine.LedgerRow]) -> some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 2) {
                ForEach(rows) { row in
                    SunburstLedgerRowView(
                        nodeID: row.node.id,
                        name: row.node.name,
                        compactValue: Self.compactTokens(Int(row.node.value.rounded())),
                        percentText: Self.percentString(row.fraction),
                        isOpenHeader: row.isOpenHeader,
                        isSubRow: row.isSubRow,
                        isHovered: self.hoveredNodeID == row.node.id,
                        toneKey: Self.toneKey(for: row.tone),
                        isDark: self.palette.tokens.isDark,
                        palette: self.palette,
                        onTap: {
                            self.handleSelect(node: row.node, ring: row.ring)
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
        self.updateHover(nil)
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
    var onHoverDetail: ((String?) -> Void)? = nil
    
    @State private var hoveredSliceIndex: Int?
    
    
    var body: some View {
        GeometryReader { geo in
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
                let stepAngle = 360.0 / Double(max(1, slices.count))
                
                for slice in slices {
                    let padDeg = self.detailed ? 1.5 : 1.8
                    let startDeg = -90.0 + Double(slice.index) * stepAngle + padDeg
                    let endDeg = -90.0 + Double(slice.index + 1) * stepAngle - padDeg
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
                        let labelR = outerLimit + 13
                        let lx = center.x + CGFloat(cos(midRad)) * labelR
                        let ly = center.y + CGFloat(sin(midRad)) * labelR
                        context.draw(
                            Text(slice.label)
                                .font(.system(size: 10, weight: .medium, design: .rounded).monospacedDigit())
                                .foregroundStyle(self.palette.secondaryInk),
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
    
    @State private var hoveredCaption: String?
    
    private struct SankeyNode {
        let label: String
        let shortLabel: String
        let weight: Double
        let color: Color
    }
    
    
    var body: some View {
        let col1Nodes = self.leftTimeSlotNodes()
        let col2Nodes = self.middleMoodNodes()
        let col3Nodes = self.rightSubMoodNodes()
        
        GeometryReader { geo in
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
                    context.draw(Text("心境").font(headerStyle).foregroundStyle(headerColor), at: CGPoint(x: col2X + nodeW * 0.5, y: 8), anchor: .center)
                    context.draw(Text("状态").font(headerStyle).foregroundStyle(headerColor), at: CGPoint(x: col3X + nodeW * 0.5, y: 8), anchor: .center)
                }
                
                let gap: CGFloat = self.detailed ? 8 : 4
                let rects1 = Self.layoutColumn(nodes: col1Nodes, x: col1X, yStart: topHeaderH, height: innerH, width: nodeW, gap: gap)
                let rects2 = Self.layoutColumn(nodes: col2Nodes, x: col2X, yStart: topHeaderH, height: innerH, width: nodeW, gap: gap)
                let rects3 = Self.layoutColumn(nodes: col3Nodes, x: col3X, yStart: topHeaderH, height: innerH, width: nodeW, gap: gap)
                
                Self.drawFlows(context: &context, sources: rects1, targets: rects2)
                Self.drawFlows(context: &context, sources: rects2, targets: rects3)
                
                let sum1 = max(1.0, col1Nodes.reduce(0.0) { $0 + $1.weight })
                let sum3 = max(1.0, col3Nodes.reduce(0.0) { $0 + $1.weight })
                
                for (node, layout) in zip(col1Nodes, rects1) {
                    context.fill(RoundedRectangle(cornerRadius: 2.5, style: .continuous).path(in: layout.rect), with: .color(node.color))
                    if self.detailed {
                        let pct = Int(((node.weight / sum1) * 100).rounded())
                        context.draw(
                            Text("\(node.label) \(pct)%")
                                .font(.system(size: 10.5, weight: .medium).monospacedDigit())
                                .foregroundStyle(self.palette.pine.opacity(0.86)),
                            at: CGPoint(x: layout.rect.minX - 6, y: layout.rect.midY),
                            anchor: .trailing
                        )
                    } else if layout.rect.height >= 10 {
                        context.draw(
                            Text(node.shortLabel)
                                .font(.system(size: 9.5, weight: .medium))
                                .foregroundStyle(self.palette.secondaryInk),
                            at: CGPoint(x: layout.rect.minX - 4, y: layout.rect.midY),
                            anchor: .trailing
                        )
                    }
                }
                
                for (node, layout) in zip(col2Nodes, rects2) {
                    context.fill(RoundedRectangle(cornerRadius: 2.5, style: .continuous).path(in: layout.rect), with: .color(node.color))
                    if self.detailed {
                        let pillW: CGFloat = 34
                        let pillH: CGFloat = 15
                        let pillRect = CGRect(
                            x: layout.rect.midX - pillW * 0.5,
                            y: layout.rect.midY - pillH * 0.5,
                            width: pillW,
                            height: pillH
                        )
                        context.fill(RoundedRectangle(cornerRadius: 4, style: .continuous).path(in: pillRect), with: .color(self.palette.card.opacity(0.92)))
                        context.draw(
                            Text(node.label)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(self.palette.pine),
                            at: CGPoint(x: layout.rect.midX, y: layout.rect.midY),
                            anchor: .center
                        )
                    } else if layout.rect.height >= 12 {
                        let pillW: CGFloat = 26
                        let pillH: CGFloat = 13
                        let pillRect = CGRect(
                            x: layout.rect.midX - pillW * 0.5,
                            y: layout.rect.midY - pillH * 0.5,
                            width: pillW,
                            height: pillH
                        )
                        context.fill(RoundedRectangle(cornerRadius: 3.5, style: .continuous).path(in: pillRect), with: .color(self.palette.card.opacity(0.88)))
                        context.draw(
                            Text(node.shortLabel)
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(self.palette.pine),
                            at: CGPoint(x: layout.rect.midX, y: layout.rect.midY),
                            anchor: .center
                        )
                    }
                }
                
                for (node, layout) in zip(col3Nodes, rects3) {
                    context.fill(RoundedRectangle(cornerRadius: 2.5, style: .continuous).path(in: layout.rect), with: .color(node.color))
                    if self.detailed {
                        let pct = Int(((node.weight / sum3) * 100).rounded())
                        context.draw(
                            Text("\(node.label) \(pct)%")
                                .font(.system(size: 10.5, weight: .medium).monospacedDigit())
                                .foregroundStyle(self.palette.pine.opacity(0.86)),
                            at: CGPoint(x: layout.rect.maxX + 6, y: layout.rect.midY),
                            anchor: .leading
                        )
                    } else if layout.rect.height >= 10 {
                        context.draw(
                            Text(node.shortLabel)
                                .font(.system(size: 9.5, weight: .medium))
                                .foregroundStyle(self.palette.secondaryInk),
                            at: CGPoint(x: layout.rect.maxX + 4, y: layout.rect.midY),
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
                    self.onHoverDetail?(nextCaption)
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
    ) -> String? {
        let third = size.width / 3.0
        let nodes: [SankeyNode]
        let prefix: String
        if point.x < third {
            nodes = col1
            prefix = "时段"
        } else if point.x < third * 2 {
            nodes = col2
            prefix = "心境"
        } else {
            nodes = col3
            prefix = "状态"
        }
        let topHeaderH: CGFloat = 22
        let padBottom: CGFloat = 8
        let innerH = max(30, size.height - topHeaderH - padBottom)
        let laid = Self.layoutColumn(nodes: nodes, x: 0, yStart: topHeaderH, height: innerH, width: 10, gap: 8)
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


// MARK: - Supporting Components (Card Surface)

private extension View {
    
    func dashboardCardSurface(
        palette: DashPalette,
        cornerRadius: CGFloat = 16,
        isHighlighted: Bool = false
    ) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        let strokeColor = isHighlighted ? palette.accentFill.opacity(0.45) : palette.hairline
        return self
            .background(
                shape
                    .fill(palette.card)
                    .shadow(color: palette.cardShadow, radius: 6, x: 0, y: 2)
            )
            .overlay(
                shape.strokeBorder(strokeColor, lineWidth: isHighlighted ? 1.0 : 0.8)
            )
    }
}
