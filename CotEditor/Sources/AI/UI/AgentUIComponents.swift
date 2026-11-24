//
//  AgentUIComponents.swift
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

// MARK: - Window & App Activity Render Gate + Shared Markdown Cache

@MainActor @Observable
final class AppActivityRenderGate {
    
    static let shared = AppActivityRenderGate()
    
    private(set) var isAppActive: Bool
    
    @ObservationIgnored private var activeObserver: NSObjectProtocol?
    @ObservationIgnored private var resignObserver: NSObjectProtocol?
    
    
    private init() {
        self.isAppActive = NSApp?.isActive ?? true
        self.activeObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.isAppActive = true }
        }
        self.resignObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.isAppActive = false }
        }
    }
    
    
    isolated deinit {
        if let activeObserver { NotificationCenter.default.removeObserver(activeObserver) }
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
    }
}


private final class WindowVisibilityProbeNSView: NSView {
    
    var onChange: (Bool) -> Void
    private var occlusionObserver: NSObjectProtocol?
    private var lastReported: Bool?
    
    
    init(onChange: @escaping (Bool) -> Void) {
        self.onChange = onChange
        super.init(frame: .zero)
    }
    
    
    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    
    isolated deinit {
        if let occlusionObserver { NotificationCenter.default.removeObserver(occlusionObserver) }
    }
    
    
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let occlusionObserver {
            NotificationCenter.default.removeObserver(occlusionObserver)
            self.occlusionObserver = nil
        }
        if let window = self.window {
            self.occlusionObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didChangeOcclusionStateNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.evaluateVisibility() }
            }
        }
        self.evaluateVisibility()
    }
    
    
    override func viewDidHide() {
        super.viewDidHide()
        self.evaluateVisibility()
    }
    
    
    override func viewDidUnhide() {
        super.viewDidUnhide()
        self.evaluateVisibility()
    }
    
    
    func evaluateVisibility() {
        let visible = !self.isHiddenOrHasHiddenAncestor
            && (self.window?.occlusionState.contains(.visible) ?? false)
        guard visible != self.lastReported else { return }
        self.lastReported = visible
        let callback = self.onChange
        DispatchQueue.main.async {
            callback(visible)
        }
    }
}


private struct WindowVisibilityProbeRepresentable: NSViewRepresentable {
    
    @Binding var isVisible: Bool
    
    
    func makeNSView(context: Context) -> WindowVisibilityProbeNSView {
        WindowVisibilityProbeNSView { next in
            if self.isVisible != next {
                self.isVisible = next
            }
        }
    }
    
    
    func updateNSView(_ nsView: WindowVisibilityProbeNSView, context: Context) {
        nsView.onChange = { next in
            if self.isVisible != next {
                self.isVisible = next
            }
        }
        nsView.evaluateVisibility()
    }
    
    
    static func dismantleNSView(_ nsView: WindowVisibilityProbeNSView, coordinator: ()) {
        nsView.onChange = { _ in }
    }
}


extension View {
    
    func observeWindowRenderActivity(_ isVisible: Binding<Bool>) -> some View {
        self.background(
            WindowVisibilityProbeRepresentable(isVisible: isVisible)
                .frame(width: 0, height: 0)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        )
    }
}


nonisolated struct GatedPeriodicTimelineSchedule: TimelineSchedule, Sendable, Equatable {
    
    let startDate: Date
    let interval: TimeInterval
    let isPaused: Bool
    
    
    init(from startDate: Date, by interval: TimeInterval, paused: Bool) {
        self.startDate = startDate
        self.interval = interval
        self.isPaused = paused
    }
    
    
    struct Entries: Sequence, IteratorProtocol, Sendable {
        var nextDate: Date
        let interval: TimeInterval
        let singleShot: Bool
        var emittedSingleShot = false
        
        mutating func next() -> Date? {
            if self.singleShot {
                guard !self.emittedSingleShot else { return nil }
                self.emittedSingleShot = true
                return self.nextDate
            }
            let current = self.nextDate
            self.nextDate = current.addingTimeInterval(Swift.max(0.05, self.interval))
            return current
        }
    }
    
    
    func entries(from startDate: Date, mode: TimelineScheduleMode) -> Entries {
        let base = self.startDate > startDate ? self.startDate : startDate
        return Entries(nextDate: base, interval: self.interval, singleShot: self.isPaused)
    }
}


nonisolated enum MarkdownRenderCache {
    
    private final class StorageBox: @unchecked Sendable {
        let lock = NSLock()
        var blocksCache: [String: [NewsMarkdownBlock]] = [:]
        var blocksOrder: [String] = []
        var inlineCache: [String: AttributedString] = [:]
        var inlineOrder: [String] = []
    }
    
    private static let box = StorageBox()
    private static let maxBlocksEntries = 96
    private static let maxInlineEntries = 512
    private static let inlineOptions = AttributedString.MarkdownParsingOptions(
        interpretedSyntax: .inlineOnlyPreservingWhitespace
    )
    
    
    static func blocks(for source: String) -> [NewsMarkdownBlock] {
        let cacheable = source.count <= 32_768
        if cacheable {
            self.box.lock.lock()
            if let hit = self.box.blocksCache[source] {
                self.box.lock.unlock()
                return hit
            }
            self.box.lock.unlock()
        }
        
        let parsed = NewsMarkdownParser.parse(source)
        if cacheable {
            self.box.lock.lock()
            self.box.blocksCache[source] = parsed
            self.box.blocksOrder.removeAll { $0 == source }
            self.box.blocksOrder.append(source)
            while self.box.blocksOrder.count > Self.maxBlocksEntries {
                let evicted = self.box.blocksOrder.removeFirst()
                self.box.blocksCache.removeValue(forKey: evicted)
            }
            self.box.lock.unlock()
        }
        return parsed
    }
    
    
    static func attributedInline(for raw: String) -> AttributedString? {
        guard raw.count <= 2_048 else {
            return try? AttributedString(markdown: raw, options: Self.inlineOptions)
        }
        self.box.lock.lock()
        if let hit = self.box.inlineCache[raw] {
            self.box.lock.unlock()
            return hit
        }
        self.box.lock.unlock()
        
        guard let parsed = try? AttributedString(markdown: raw, options: Self.inlineOptions) else {
            return nil
        }
        self.box.lock.lock()
        self.box.inlineCache[raw] = parsed
        self.box.inlineOrder.removeAll { $0 == raw }
        self.box.inlineOrder.append(raw)
        while self.box.inlineOrder.count > Self.maxInlineEntries {
            let evicted = self.box.inlineOrder.removeFirst()
            self.box.inlineCache.removeValue(forKey: evicted)
        }
        self.box.lock.unlock()
        return parsed
    }
}

// MARK: - Beautiful UI Design Tokens (beautifului.dev)

/// Unified semantic color tokens ported directly from Beautiful UI (`light` & `dark` surfaces).
struct BeautifulUITokens: Equatable, Sendable {
    
    let isDark: Bool
    let page: Color
    let canvas: Color
    let surface: Color
    let inset: Color
    let field: Color
    let hover: Color
    let hover2: Color
    let ink: Color
    let ink2: Color
    let ink3: Color
    let line: Color
    let lineStrong: Color
    let accent: Color
    let accentInk: Color
    let accentTint: Color
    let green: Color
    let orange: Color
    let red: Color
    
    
    static func resolve(isDark: Bool) -> BeautifulUITokens {
        if isDark {
            let accent = Color(hexString: "#519AFD")
            return BeautifulUITokens(
                isDark: true,
                page: Color(hexString: "#17181C"),
                canvas: Color(hexString: "#1B1C21"),
                surface: Color(hexString: "#212229"),
                inset: Color(hexString: "#1E1F25"),
                field: Color(hexString: "#272932"),
                hover: Color(hexString: "#262831"),
                hover2: Color(hexString: "#2D303B"),
                ink: Color(hexString: "#F3F4F6"),
                ink2: Color(hexString: "#A4A8B3"),
                ink3: Color(hexString: "#6C707C"),
                line: Color(hexString: "#2D3039"),
                lineStrong: Color(hexString: "#393D49"),
                accent: accent,
                accentInk: Color(hexString: "#8FC0FF"),
                accentTint: accent.opacity(0.16),
                green: Color(hexString: "#38BD77"),
                orange: Color(hexString: "#F59B3B"),
                red: Color(hexString: "#EE5A55")
            )
        } else {
            return BeautifulUITokens(
                isDark: false,
                page: Color(hexString: "#FAFAFB"),
                canvas: Color(hexString: "#F3F4F6"),
                surface: Color(hexString: "#FFFFFF"),
                inset: Color(hexString: "#F8F9FA"),
                field: Color(hexString: "#F2F2F4"),
                hover: Color(hexString: "#F5F6F8"),
                hover2: Color(hexString: "#EAECEF"),
                ink: Color(hexString: "#1E2025"),
                ink2: Color(hexString: "#636770"),
                ink3: Color(hexString: "#9CA0AA"),
                line: Color(hexString: "#EBEDF0"),
                lineStrong: Color(hexString: "#DFE2E7"),
                accent: Color(hexString: "#2F7CF6"),
                accentInk: Color(hexString: "#1D67DB"),
                accentTint: Color(hexString: "#EFF6FF"),
                green: Color(hexString: "#189E59"),
                orange: Color(hexString: "#EA7A1E"),
                red: Color(hexString: "#E23C39")
            )
        }
    }
}


// MARK: - Dissolve 状态粒子球 (leibox.pantoria.cn/docs/animations/thinking-orb)

nonisolated enum AgentOrbState: String, CaseIterable, Sendable {
    case idle
    case thinking
    case searching
    case listening
    case done
    case error
}

private nonisolated struct DissolveSeedTable {
    
    let spherePoints: [(x: Double, y: Double, z: Double)]
    let checkPoints: [(x: Double, y: Double, z: Double)]
    let randA: [Double]
    let randB: [Double]
    
    
    private static let lock = NSLock()
    private static var cache: [Int: DissolveSeedTable] = [:]
    
    
    static func table(dots: Int) -> DissolveSeedTable {
        let count = max(12, dots)
        self.lock.lock()
        defer { self.lock.unlock() }
        if let existing = self.cache[count] {
            return existing
        }
        
        let goldenAngle = Double.pi * (3.0 - sqrt(5.0))
        var sphere: [(Double, Double, Double)] = []
        sphere.reserveCapacity(count)
        var rA: [Double] = []
        rA.reserveCapacity(count)
        var rB: [Double] = []
        rB.reserveCapacity(count)
        
        @inline(__always)
        func hashUnit(_ i: Int, _ salt: Double) -> Double {
            let v = sin(Double(i + 1) * 12.9898 + salt * 78.233) * 43758.5453
            return v - floor(v)
        }
        
        for i in 0..<count {
            let a = hashUnit(i, 1.37)
            let b = hashUnit(i, 7.91)
            rA.append(a)
            rB.append(b)
            
            let y = 1.0 - ((Double(i) + 0.5) / Double(count)) * 2.0
            let radius = sqrt(max(0.0, 1.0 - y * y))
            let theta = Double(i) * goldenAngle
            sphere.append((cos(theta) * radius, y, sin(theta) * radius))
        }
        
        // Checkmark polyline segments from Dissolve ThinkingOrb: (-0.52,0.02) -> (-0.16,0.38) -> (0.56,-0.36)
        let p0 = (x: -0.52, y: 0.02)
        let p1 = (x: -0.16, y: 0.38)
        let p2 = (x: 0.56, y: -0.36)
        let len0 = hypot(p1.x - p0.x, p1.y - p0.y)
        let len1 = hypot(p2.x - p1.x, p2.y - p1.y)
        let totalLen = len0 + len1
        
        var check: [(Double, Double, Double)] = []
        check.reserveCapacity(count)
        for i in 0..<count {
            var pos = (Double(i) + 0.5) / Double(count) * totalLen
            let segStart: (x: Double, y: Double)
            let segEnd: (x: Double, y: Double)
            let segLen: Double
            if pos > len0 {
                pos -= len0
                segStart = p1
                segEnd = p2
                segLen = len1
            } else {
                segStart = p0
                segEnd = p1
                segLen = len0
            }
            let t = segLen > 0 ? (pos / segLen) : 0
            let nx = -(segEnd.y - segStart.y) / max(1e-6, segLen)
            let ny = (segEnd.x - segStart.x) / max(1e-6, segLen)
            let spread = (rA[i] - 0.5) * 0.11
            let cx = segStart.x + (segEnd.x - segStart.x) * t + nx * spread
            let cy = segStart.y + (segEnd.y - segStart.y) * t + ny * spread
            let cz = (rB[i] - 0.5) * 0.5
            check.append((cx, cy, cz))
        }
        
        let built = DissolveSeedTable(spherePoints: sphere, checkPoints: check, randA: rA, randB: rB)
        self.cache[count] = built
        return built
    }
}

/// 180-dot spherical Dissolve particle orb morphing cleanly between idle, thinking, searching, listening, done, and error.
struct DissolveThinkingOrbView: View, Equatable {
    
    var state: AgentOrbState = .idle
    var size: CGFloat = 52
    var dots: Int = 180
    var level: Double = 0.35
    var interactive: Bool = true
    var color: Color? = nil
    var paused: Bool = false
    
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var activityGate = AppActivityRenderGate.shared
    @State private var isWindowVisible = true
    @State private var isDoneSettled = false
    @State private var hoverPoint: CGPoint? = nil
    @State private var previousState: AgentOrbState = .idle
    @State private var transitionStart: TimeInterval = 0
    
    
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.state == rhs.state
            && lhs.size == rhs.size
            && lhs.dots == rhs.dots
            && lhs.level == rhs.level
            && lhs.interactive == rhs.interactive
            && lhs.color == rhs.color
            && lhs.paused == rhs.paused
    }
    
    
    var body: some View {
        let tokens = BeautifulUITokens.resolve(isDark: self.colorScheme == .dark)
        let settledDone = (self.state == .done && self.isDoneSettled && self.hoverPoint == nil)
        let isPausedNow = self.reduceMotion
            || self.paused
            || !self.activityGate.isAppActive
            || !self.isWindowVisible
            || settledDone
        let interval: TimeInterval = (self.state == .idle && self.hoverPoint == nil) ? (1.0 / 30.0) : (1.0 / 60.0)
        
        TimelineView(.animation(minimumInterval: interval, paused: isPausedNow)) { timeline in
            Canvas(rendersAsynchronously: true) { context, canvasSize in
                let effectiveNow: TimeInterval = if self.reduceMotion {
                    0.6
                } else if settledDone {
                    max(0.6, self.transitionStart + 10.0)
                } else {
                    timeline.date.timeIntervalSinceReferenceDate
                }
                self.drawOrb(
                    context: &context,
                    canvasSize: canvasSize,
                    now: effectiveNow,
                    tokens: tokens
                )
            }
        }
        .frame(width: self.size, height: self.size)
        .observeWindowRenderActivity(self.$isWindowVisible)
        .onAppear {
            if self.state == .done {
                self.isDoneSettled = true
            }
        }
        .onContinuousHover { phase in
            guard self.interactive else {
                if self.hoverPoint != nil { self.hoverPoint = nil }
                return
            }
            switch phase {
                case .active(let loc):
                    self.hoverPoint = loc
                case .ended:
                    self.hoverPoint = nil
            }
        }
        .onChange(of: self.state) { oldValue, newValue in
            self.previousState = oldValue
            self.transitionStart = Date().timeIntervalSinceReferenceDate
            self.isDoneSettled = false
            if newValue == .done {
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(700))
                    if self.state == .done {
                        self.isDoneSettled = true
                    }
                }
            }
        }
        .accessibilityLabel(Text("Assistant \(self.state.rawValue)"))
    }
    
    
    private func drawOrb(
        context: inout GraphicsContext,
        canvasSize: CGSize,
        now: TimeInterval,
        tokens: BeautifulUITokens
    ) {
        let count = max(12, self.dots)
        let table = DissolveSeedTable.table(dots: count)
        let width = min(canvasSize.width, canvasSize.height)
        let half = width * 0.5
        let orbRadius = width * 0.40
        let dotBaseR = max(1.15, width * 0.0115)
        
        let baseTint: Color = switch self.state {
            case .done: tokens.green
            case .error: tokens.red
            default: self.color ?? tokens.ink
        }
        
        let elapsedTrans = self.transitionStart > 0 ? max(0.0, now - self.transitionStart) : 10.0
        let ringSpeeds: [Double] = [2.1, -1.6, 1.2]
        let ringZAngles: [Double] = [0.0, 1.05, -1.05]
        let goldenAngle = Double.pi * (3.0 - sqrt(5.0))
        let twoPi = Double.pi * 2.0
        let repelRadius = width * 0.62
        
        @inline(__always)
        func samplePoint(for targetState: AgentOrbState, index i: Int, t: Double) -> (Double, Double, Double, Double) {
            var kx: Double
            var ky: Double
            var kz: Double
            var alpha = 1.0
            
            switch targetState {
                case .thinking:
                    let ring = i % 3
                    let perRing = max(1, count / 3)
                    let theta = (Double(i / 3) / Double(perRing)) * twoPi + t * ringSpeeds[ring]
                    let ax = cos(theta) * 0.95
                    let ay = sin(theta) * 0.95
                    let rx = -ay * sin(0.45)
                    let rz = ay * cos(0.45)
                    let cz = cos(ringZAngles[ring])
                    let sz = sin(ringZAngles[ring])
                    kx = ax * cz - rx * sz
                    ky = ax * sz + rx * cz
                    kz = rz
                    
                case .searching:
                    let radial = 0.95 * sqrt((Double(i) + 0.5) / Double(count))
                    let theta = Double(i) * goldenAngle
                    kx = cos(theta) * radial
                    ky = sin(theta) * radial
                    var sweep = (t * twoPi - theta).truncatingRemainder(dividingBy: twoPi)
                    if sweep < 0 { sweep += twoPi }
                    alpha = 0.3 + 0.7 * exp(-sweep * 1.4)
                    kz = alpha * 0.6 - 0.3
                    
                case .done:
                    let pt = table.checkPoints[i]
                    kx = pt.x
                    ky = pt.y
                    kz = pt.z
                    
                case .error:
                    let pt = table.spherePoints[i]
                    let burst = min(1.0, elapsedTrans / 0.55)
                    let fall = pow(burst, 1.6) * 0.55
                    kx = pt.x + (table.randA[i] - 0.5) * 0.45 * burst
                    ky = min(1.05, pt.y + fall - table.randB[i] * 0.25 * (1.0 - burst))
                    kz = pt.z * 0.5
                    alpha = max(0.35, 1.0 - burst * 0.35)
                    
                case .idle, .listening:
                    let pt = table.spherePoints[i]
                    let breath: Double
                    if targetState == .listening {
                        let lvl = max(0.0, min(1.0, self.level))
                        breath = (0.84 + lvl * 0.2) * (1.0 + 0.06 * lvl * sin(pt.y * 5.0 - t * 12.0))
                    } else {
                        breath = 0.98 + 0.02 * sin((t / 2.4) * twoPi)
                    }
                    kx = pt.x * breath
                    ky = pt.y * breath
                    kz = pt.z * breath
            }
            
            if targetState != .done && targetState != .searching && targetState != .thinking {
                let yaw = t * 0.40
                let cy = cos(yaw)
                let sy = sin(yaw)
                let rx = kx * cy + kz * sy
                let rz = -kx * sy + kz * cy
                let ct = cos(0.3)
                let st = sin(0.3)
                kx = rx
                kz = ky * st + rz * ct
                ky = ky * ct - rz * st
            }
            return (kx, ky, kz, alpha)
        }
        
        for i in 0..<count {
            let cur = samplePoint(for: self.state, index: i, t: now)
            var px = cur.0
            var py = cur.1
            var pz = cur.2
            var pa = cur.3
            
            if elapsedTrans < 0.72 && self.previousState != self.state {
                let prev = samplePoint(for: self.previousState, index: i, t: now)
                let stagger = Double(i) * 0.0014
                let raw = max(0.0, min(1.0, (elapsedTrans - stagger) / 0.52))
                let ease = raw * raw * (3.0 - 2.0 * raw)
                px = prev.0 + (cur.0 - prev.0) * ease
                py = prev.1 + (cur.1 - prev.1) * ease
                pz = prev.2 + (cur.2 - prev.2) * ease
                pa = prev.3 + (cur.3 - prev.3) * ease
            }
            
            var screenX = half + CGFloat(px) * orbRadius
            var screenY = half + CGFloat(py) * orbRadius
            
            if let pointer = self.hoverPoint, self.interactive {
                let dx = screenX - pointer.x
                let dy = screenY - pointer.y
                let dist = hypot(dx, dy)
                if dist < repelRadius && dist > 0.01 {
                    let push = (repelRadius - dist) * 0.55
                    screenX += (dx / dist) * push
                    screenY += (dy / dist) * push
                }
            }
            
            let depth = max(0.0, min(1.0, (pz + 1.0) * 0.5))
            let opacity = (0.38 + 0.62 * depth) * pa
            let dotR = dotBaseR * CGFloat(0.8 + 0.4 * depth)
            let rect = CGRect(x: screenX - dotR, y: screenY - dotR, width: dotR * 2, height: dotR * 2)
            
            context.opacity = opacity
            context.fill(Path(ellipseIn: rect), with: .color(baseTint))
        }
    }
}


// MARK: - 思考粒子 (leibox.pantoria.cn/docs/animations/thinking-orbs)

nonisolated enum ThinkingOrbsMode: String, CaseIterable, Identifiable, Sendable {
    case working
    case searching
    case solving
    case listening
    case connecting
    case weaving
    case composing
    case breathing
    case shaping
    
    var id: String { self.rawValue }
    
    var defaultAccentHex: String {
        switch self {
            case .working: "#5040A2"
            case .searching: "#1B7394"
            case .solving: "#9B6429"
            case .listening: "#327E60"
            case .connecting: "#216790"
            case .weaving: "#8C3D98"
            case .composing: "#A34175"
            case .breathing: "#5159A2"
            case .shaping: "#376D92"
        }
    }
}

/// Multi-mode 3D dot-particle orb ported directly from LeiBox `thinking-orbs`.
struct ThinkingOrbsParticleView: View, Equatable {
    
    var mode: ThinkingOrbsMode = .working
    var size: CGFloat = 24
    var color: Color? = nil
    var speed: Double = 1.0
    var paused: Bool = false
    
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var activityGate = AppActivityRenderGate.shared
    @State private var isWindowVisible = true
    
    
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.mode == rhs.mode
            && lhs.size == rhs.size
            && lhs.color == rhs.color
            && lhs.speed == rhs.speed
            && lhs.paused == rhs.paused
    }
    
    
    var body: some View {
        let isDark = (self.colorScheme == .dark)
        let isReduced = self.reduceMotion || self.paused || !self.activityGate.isAppActive || !self.isWindowVisible
        let tint = self.color ?? Color(hexString: self.mode.defaultAccentHex)
        let minInterval: TimeInterval = self.size <= 24 ? (1.0 / 30.0) : (1.0 / 60.0)
        
        TimelineView(.animation(minimumInterval: minInterval, paused: isReduced)) { timeline in
            Canvas(rendersAsynchronously: true) { context, canvasSize in
                self.renderParticles(
                    context: &context,
                    side: min(canvasSize.width, canvasSize.height),
                    time: (isReduced ? 0.6 : timeline.date.timeIntervalSinceReferenceDate) * self.speed * self.modeSpeedMultiplier,
                    isDark: isDark,
                    tint: tint
                )
            }
        }
        .frame(width: self.size, height: self.size)
        .observeWindowRenderActivity(self.$isWindowVisible)
        .accessibilityLabel(Text(self.mode.rawValue))
    }
    
    
    private var modeSpeedMultiplier: Double {
        switch self.mode {
            case .working: 2.0
            case .searching: 2.1
            case .solving: 1.85
            case .listening: 4.1
            case .connecting: 3.4
            case .weaving: 1.8
            case .composing: 2.4
            case .breathing: 3.2
            case .shaping: 2.3
        }
    }
    
    
    private struct ParticleDot {
        let x: Double
        let y: Double
        let z: Double
        let r: Double
        let white: Double
        let alpha: Double
    }
    
    private struct ParticleLine {
        let x1: Double
        let y1: Double
        let x2: Double
        let y2: Double
        let white: Double
        let alpha: Double
        let width: Double
    }
    
    
    @inline(__always)
    private static func hash2D(_ a: Double, _ b: Double) -> Double {
        let v = sin(a * 12.9898 + b * 78.233) * 43758.5453
        return v - floor(v)
    }
    
    
    @inline(__always)
    private static func fibPoint(_ i: Int, _ n: Int) -> (Double, Double, Double) {
        let ga = Double.pi * (3.0 - sqrt(5.0))
        let y = 1.0 - 2.0 * (Double(i) + 0.5) / Double(n)
        let rad = sqrt(max(0.0, 1.0 - y * y))
        let phi = Double(i) * ga
        return (rad * cos(phi), y, rad * sin(phi))
    }
    
    
    private func renderParticles(
        context: inout GraphicsContext,
        side: CGFloat,
        time t: Double,
        isDark: Bool,
        tint: Color
    ) {
        let s = Double(side)
        let half = s * 0.5
        let densityScale = self.size < 28 ? 0.45 : (self.size < 44 ? 0.68 : 1.0)
        let rScale = pow(max(12.0, s) / 300.0, 0.56) * (self.size < 28 ? 1.75 : (self.size < 44 ? 1.35 : 1.0))
        
        func rotateProject(yaw: Double, pitch: Double, scale: Double) -> (Double, Double, Double) -> (Double, Double, Double) {
            let sp = sin(pitch)
            let cp = cos(pitch)
            let sy = sin(yaw)
            let cy = cos(yaw)
            return { x, y, z in
                let rx = x * cy + z * sy
                let rz = -x * sy + z * cy
                let py = y * cp - rz * sp
                let pz = y * sp + rz * cp
                return (half + rx * scale, half - py * scale, pz)
            }
        }
        
        var dots: [ParticleDot] = []
        var lines: [ParticleLine] = []
        
        switch self.mode {
            case .working:
                let orbitN = max(4, Int((12.0 * densityScale).rounded()))
                let ringPts = max(12, Int((36.0 * densityScale).rounded()))
                let proj = rotateProject(yaw: t * 0.12, pitch: 0.30, scale: 1.0)
                let radius = half * 0.82
                for f in 0..<orbitN {
                    let h1 = Self.hash2D(Double(f), 1.7)
                    let h2 = Self.hash2D(Double(f), 5.2)
                    let h3 = Self.hash2D(Double(f), 8.9)
                    let planeR = radius * (0.45 + 0.52 * h1)
                    let phi = h1 * 2.0 * Double.pi
                    let theta = acos(2.0 * h2 - 1.0)
                    let nx = sin(theta) * cos(phi)
                    let ny = cos(theta)
                    let nz = sin(theta) * sin(phi)
                    var ux = -ny
                    var uy = nx
                    let uz = 0.0
                    let normLen = max(1e-6, sqrt(ux * ux + uy * uy))
                    ux /= normLen
                    uy /= normLen
                    let wx = ny * uz - nz * uy
                    let wy = nz * ux - nx * uz
                    let wz = nx * uy - ny * ux
                    let spinDir = (0.25 + 0.55 * h3) * (h3 > 0.5 ? 1.0 : -1.0)
                    
                    for step in 0..<ringPts {
                        let a = Double(step) / Double(ringPts) * 2.0 * Double.pi
                        let ca = cos(a)
                        let sa = sin(a)
                        let p = proj((ux * ca + wx * sa) * planeR, (uy * ca + wy * sa) * planeR, (uz * ca + wz * sa) * planeR)
                        let depth = (p.2 / planeR + 1.0) * 0.5
                        dots.append(ParticleDot(x: p.0, y: p.1, z: p.2, r: 0.78 * rScale, white: 0.65, alpha: 0.32 + 0.45 * depth))
                    }
                    for orbiter in 0..<2 {
                        let a = t * spinDir + Double(orbiter) * Double.pi + h2 * 6.0
                        let ca = cos(a)
                        let sa = sin(a)
                        let p = proj((ux * ca + wx * sa) * planeR, (uy * ca + wy * sa) * planeR, (uz * ca + wz * sa) * planeR)
                        let depth = (p.2 / planeR + 1.0) * 0.5
                        dots.append(ParticleDot(x: p.0, y: p.1, z: p.2, r: (1.25 + 1.5 * depth) * rScale, white: 0.25 - 0.18 * depth, alpha: 0.85 + 0.15 * depth))
                    }
                }
                
            case .searching:
                let latRings = max(6, Int((15.0 * densityScale).rounded()))
                let lonDen = max(10, Int((36.0 * densityScale).rounded()))
                let proj = rotateProject(yaw: t * 0.5, pitch: 0.4 + 0.06 * sin(t * 0.35), scale: half * 0.82)
                let beamAngle = t * 2.8
                for c in 0...latRings {
                    let lat = -Double.pi * 0.5 + Double(c) / Double(latRings) * Double.pi
                    let cl = cos(lat)
                    let sl = sin(lat)
                    let cols = max(1, Int((abs(cl) * Double(lonDen)).rounded()))
                    for col in 0..<cols {
                        let lon = Double(col) / Double(cols) * 2.0 * Double.pi
                        let p = proj(cl * cos(lon), sl, cl * sin(lon))
                        let depth = (p.2 + 1.0) * 0.5
                        let diff = atan2(sin((lon + t * 0.5) - beamAngle), cos((lon + t * 0.5) - beamAngle))
                        let glow = exp(-(diff * diff) / 0.18) * max(0.0, p.2)
                        dots.append(ParticleDot(x: p.0, y: p.1, z: p.2, r: (0.65 + 1.6 * depth + glow) * rScale, white: 0.58 - 0.48 * depth, alpha: 0.42 + 0.58 * min(1.0, glow)))
                    }
                }
                
            case .solving:
                let latRings = max(6, Int((14.0 * densityScale).rounded()))
                let lonDen = max(10, Int((34.0 * densityScale).rounded()))
                let proj = rotateProject(yaw: t * 0.55, pitch: 0.35 + 0.1 * sin(t * 0.9), scale: half * 0.82)
                let phase = (t * 0.8).truncatingRemainder(dividingBy: 3.0)
                let sliceAxis = Int(phase)
                let frac = phase - Double(sliceAxis)
                let ease = 1.0 - pow(1.0 - min(1.0, frac / 0.72), 3.0)
                let sliceAngle = ease * Double.pi * 0.5
                for c in 0...latRings {
                    let lat = -Double.pi * 0.5 + Double(c) / Double(latRings) * Double.pi
                    let cl = cos(lat)
                    let sl = sin(lat)
                    let cols = max(1, Int((abs(cl) * Double(lonDen)).rounded()))
                    for col in 0..<cols {
                        let lon = Double(col) / Double(cols) * 2.0 * Double.pi
                        var px = cl * cos(lon)
                        var py = sl
                        var pz = cl * sin(lon)
                        let axisVal = sliceAxis == 0 ? px : (sliceAxis == 1 ? py : pz)
                        var activeSlice = false
                        if axisVal > 0.15 {
                            activeSlice = true
                            let ca = cos(sliceAngle)
                            let sa = sin(sliceAngle)
                            if sliceAxis == 0 {
                                let ny = py * ca - pz * sa
                                pz = py * sa + pz * ca
                                py = ny
                            } else if sliceAxis == 1 {
                                let nx = px * ca + pz * sa
                                pz = -px * sa + pz * ca
                                px = nx
                            } else {
                                let nx = px * ca - py * sa
                                py = px * sa + py * ca
                                px = nx
                            }
                        }
                        let p = proj(px, py, pz)
                        let depth = (p.2 + 1.0) * 0.5
                        dots.append(ParticleDot(x: p.0, y: p.1, z: p.2, r: (0.65 + 1.65 * depth + (activeSlice ? 0.35 : 0.0)) * rScale, white: 0.58 - 0.48 * depth - (activeSlice ? 0.15 : 0.0), alpha: 0.85))
                    }
                }
                
            case .listening:
                let rings = max(6, Int((14.0 * densityScale).rounded()))
                let lonDen = max(10, Int((34.0 * densityScale).rounded()))
                let radius = half * 0.86
                let proj = rotateProject(yaw: t * 0.18, pitch: 0.38, scale: 1.0)
                for m in 0...rings {
                    let lat = -Double.pi * 0.5 + Double(m) / Double(rings) * Double.pi
                    let cl = cos(lat)
                    let sl = sin(lat)
                    let wave = 0.62 * sin(t * 2.1 - Double(m) * 0.52) + 0.38 * sin(t * 1.27 + Double(m) * 0.83)
                    let rad = radius * (0.88 + 0.105 * wave)
                    let cols = max(1, Int((abs(cl) * Double(lonDen)).rounded()))
                    for hCol in 0..<cols {
                        let lon = Double(hCol) / Double(cols) * 2.0 * Double.pi
                        let p = proj(cl * cos(lon) * rad, sl * rad, cl * sin(lon) * rad)
                        let depth = (p.2 / radius + 1.0) * 0.5
                        let boost = max(0.0, wave)
                        dots.append(ParticleDot(x: p.0, y: p.1, z: p.2, r: (0.6 + 1.6 * depth) * (1.0 + 0.4 * boost) * rScale, white: 0.62 - 0.52 * depth - 0.1 * boost, alpha: 0.90))
                    }
                }
                
            case .connecting:
                let nodeCount = max(10, Int((28.0 * densityScale).rounded()))
                let proj = rotateProject(yaw: t * 0.14, pitch: 0.32, scale: half * 0.80)
                var nodes: [(Double, Double, Double)] = []
                nodes.reserveCapacity(nodeCount)
                for nIdx in 0..<nodeCount {
                    let base = Self.fibPoint(nIdx, nodeCount)
                    let dx = base.0 + 0.25 * sin(t * 0.8 + Double(nIdx) * 1.3)
                    let dy = base.1 + 0.25 * cos(t * 0.7 + Double(nIdx) * 2.1)
                    let dz = base.2 + 0.25 * sin(t * 0.9 + Double(nIdx) * 0.7)
                    let norm = max(1e-6, sqrt(dx * dx + dy * dy + dz * dz))
                    nodes.append((dx / norm, dy / norm, dz / norm))
                }
                let threshold = 0.76
                for i in 0..<nodeCount {
                    let pi = proj(nodes[i].0, nodes[i].1, nodes[i].2)
                    let depth = (pi.2 + 1.0) * 0.5
                    dots.append(ParticleDot(x: pi.0, y: pi.1, z: pi.2, r: (1.2 + 1.5 * depth) * rScale, white: 0.52 - 0.42 * depth, alpha: 0.92))
                    for j in (i + 1)..<nodeCount {
                        let dist = sqrt(pow(nodes[i].0 - nodes[j].0, 2) + pow(nodes[i].1 - nodes[j].1, 2) + pow(nodes[i].2 - nodes[j].2, 2))
                        guard dist < threshold else { continue }
                        let pj = proj(nodes[j].0, nodes[j].1, nodes[j].2)
                        let avgDepth = ((pi.2 + pj.2) * 0.5 + 1.0) * 0.5
                        lines.append(ParticleLine(x1: pi.0, y1: pi.1, x2: pj.0, y2: pj.1, white: 0.42, alpha: (1.0 - dist / threshold) * (0.28 + 0.55 * avgDepth), width: max(0.55, 0.8 * rScale)))
                    }
                }
                
            case .weaving:
                let ghostN = max(24, Int((90.0 * densityScale).rounded()))
                let strandN = max(18, Int((46.0 * densityScale).rounded()))
                let radius = half * 0.76
                let proj = rotateProject(yaw: t * 0.40, pitch: 0.30, scale: 1.0)
                for f in 0..<ghostN {
                    let gp = Self.fibPoint(f, ghostN)
                    let p = proj(gp.0 * radius, gp.1 * radius, gp.2 * radius)
                    let depth = (p.2 / radius + 1.0) * 0.5
                    dots.append(ParticleDot(x: p.0, y: p.1, z: p.2, r: 0.78 * rScale, white: 0.76, alpha: 0.12 + 0.22 * depth))
                }
                for strand in 0..<3 {
                    let phaseOffset = Double(strand) / 3.0 * 2.0 * Double.pi
                    for l in 0..<strandN {
                        let u = (Double(l) / Double(strandN) + t * 0.045)
                        let frac = u - floor(u)
                        let yNorm = (frac * 2.0 - 1.0) * 0.96
                        let sBase = sqrt(max(0.0, 1.0 - yNorm * yNorm))
                        let fade = min(1.0, (1.0 - abs(yNorm)) / 0.1)
                        let angle = yNorm * Double.pi * 3.0 + phaseOffset
                        let wobble = 1.0 + 0.075 * sin(yNorm * Double.pi * 6.0 + phaseOffset * 2.0 + t * 0.8)
                        let rr = sBase * radius * wobble
                        let p = proj(cos(angle) * rr, yNorm * radius * wobble, sin(angle) * rr)
                        let depth = (p.2 / radius + 1.0) * 0.5
                        dots.append(ParticleDot(x: p.0, y: p.1, z: p.2, r: (1.1 + 1.6 * depth) * rScale, white: 0.52 - 0.42 * depth, alpha: fade * (0.45 + 0.55 * depth)))
                    }
                }
                
            case .composing, .breathing:
                let isFaceOn = (self.mode == .breathing)
                let lanes = isFaceOn ? 4 : 5
                let segs = max(24, Int((76.0 * densityScale).rounded()))
                let radius = half * (isFaceOn ? 0.68 : 0.78)
                let proj = rotateProject(yaw: 0.0, pitch: 0.30, scale: 1.0)
                let wobMul = isFaceOn ? 0.38 : 1.0
                for b in 0..<lanes {
                    let laneOff = (Double(b) - Double(lanes - 1) * 0.5) * 0.075
                    let edgeRatio = abs(Double(b) - Double(lanes - 1) * 0.5) / max(1.0, Double(lanes - 1) * 0.5)
                    for n in 0..<segs {
                        let ang = Double(n) / Double(segs) * 2.0 * Double.pi
                        let wob = (0.16 * sin(ang * 3.0 - t * 1.7 + Double(b) * 0.22) + 0.07 * sin(ang * 5.0 + t * 1.1)) * wobMul
                        let sx = isFaceOn ? cos(ang) * (1.0 + wob) : cos(ang)
                        let sy = isFaceOn ? sin(ang) * (1.0 + wob) : sin(ang) * 0.55 + wob
                        let sz = isFaceOn ? laneOff : laneOff + wob * 0.6
                        let len = max(1e-6, sqrt(sx * sx + sy * sy + sz * sz))
                        let p = proj(sx / len * radius, sy / len * radius, sz / len * radius)
                        let depth = (p.2 / radius + 1.0) * 0.5
                        dots.append(ParticleDot(x: p.0, y: p.1, z: p.2, r: (1.0 + 1.5 * depth) * (1.0 - 0.25 * edgeRatio) * rScale, white: 0.50 - 0.42 * depth + 0.18 * edgeRatio, alpha: 0.42 + 0.58 * depth))
                    }
                }
                
            case .shaping:
                let count = max(14, Int((32.0 * densityScale).rounded()))
                let cycle = t.truncatingRemainder(dividingBy: 6.9)
                let shapeIdx = Int(cycle / 2.3) % 3
                let nextIdx = (shapeIdx + 1) % 3
                let local = (cycle.truncatingRemainder(dividingBy: 2.3)) / 2.3
                let morph = local > 0.6 ? pow((local - 0.6) / 0.4, 2) * (3.0 - 2.0 * (local - 0.6) / 0.4) : 0.0
                
                func polyPoint(_ kind: Int, _ frac: Double) -> (Double, Double) {
                    if kind == 0 {
                        let a = -Double.pi * 0.5 + frac * 2.0 * Double.pi
                        return (cos(a) * 0.34, sin(a) * 0.34)
                    } else if kind == 1 {
                        let verts = [(0.0, -0.36), (0.34, 0.24), (-0.34, 0.24)]
                        let seg = min(2, Int(frac * 3.0))
                        let u = frac * 3.0 - Double(seg)
                        let a = verts[seg]
                        let b = verts[(seg + 1) % 3]
                        return (a.0 + (b.0 - a.0) * u, a.1 + (b.1 - a.1) * u)
                    } else {
                        let verts = [(-0.28, -0.28), (0.28, -0.28), (0.28, 0.28), (-0.28, 0.28)]
                        let seg = min(3, Int(frac * 4.0))
                        let u = frac * 4.0 - Double(seg)
                        let a = verts[seg]
                        let b = verts[(seg + 1) % 4]
                        return (a.0 + (b.0 - a.0) * u, a.1 + (b.1 - a.1) * u)
                    }
                }
                for i in 0..<count {
                    let frac = Double(i) / Double(count)
                    let p0 = polyPoint(shapeIdx, frac)
                    let p1 = polyPoint(nextIdx, frac)
                    let x = half + (p0.0 + (p1.0 - p0.0) * morph) * s
                    let y = half + (p0.1 + (p1.1 - p0.1) * morph) * s
                    dots.append(ParticleDot(x: x, y: y, z: 0.0, r: max(1.1, 0.032 * s), white: 0.15, alpha: 0.92))
                }
        }
        
        dots.sort { $0.z < $1.z }
        
        for line in lines where line.alpha >= 0.02 {
            var path = Path()
            path.move(to: CGPoint(x: line.x1, y: line.y1))
            path.addLine(to: CGPoint(x: line.x2, y: line.y2))
            context.opacity = line.alpha
            context.stroke(path, with: .color(tint), lineWidth: CGFloat(line.width))
        }
        
        for dot in dots where dot.alpha >= 0.02 {
            let rr = CGFloat(max(0.55, dot.r))
            let rect = CGRect(x: dot.x - Double(rr), y: dot.y - Double(rr), width: Double(rr) * 2.0, height: Double(rr) * 2.0)
            let w = min(1.0, max(0.0, dot.white))
            let brightnessBoost = isDark ? (1.0 - w) * 0.45 : w * 0.35
            context.opacity = dot.alpha * (1.0 - brightnessBoost * 0.45)
            context.fill(Path(ellipseIn: rect), with: .color(tint))
        }
    }
}


// MARK: - Beautiful UI Primitives (Pixel Loader, Thinking Trace, Tool Chips, Markdown, Prompt Bar, Unified Chat Surface)

nonisolated enum BeautifulUILoaderVariant: String, CaseIterable, Sendable {
    case drive
    case dots
    case orbit
}

/// 3x3 pixel-grid loader paired with label and tabular monospaced elapsed timer (`beautifului.dev` LoadingState).
struct BeautifulUIPixelLoader: View {
    
    var label: String = "Processing"
    var variant: BeautifulUILoaderVariant = .drive
    var showTimer: Bool = true
    var startedAt: Date = Date()
    
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var activityGate = AppActivityRenderGate.shared
    @State private var isWindowVisible = true
    
    private static let driveDelays: [Double] = [0.09, 0.18, 0.27, 0.0, 0.09, 0.18, 0.09, 0.18, 0.27]
    private static let orbitOrder: [Int: Double] = [0: 0.0, 1: 0.11, 2: 0.22, 5: 0.33, 8: 0.44, 7: 0.55, 6: 0.66, 3: 0.77]
    
    
    var body: some View {
        let tokens = BeautifulUITokens.resolve(isDark: self.colorScheme == .dark)
        let isPaused = self.reduceMotion || !self.activityGate.isAppActive || !self.isWindowVisible
        
        TimelineView(GatedPeriodicTimelineSchedule(from: self.startedAt, by: 0.08, paused: isPaused)) { context in
            let elapsed = max(0, context.date.timeIntervalSince(self.startedAt))
            let cycleDur: Double = self.variant == .orbit ? 0.95 : 0.65
            let cornerR: CGFloat = self.variant == .dots ? 2 : 1
            
            HStack(spacing: 8) {
                Canvas(rendersAsynchronously: true) { gfx, _ in
                    for idx in 0..<9 {
                        let opacity: Double = {
                            if self.reduceMotion { return 0.22 }
                            if self.variant == .orbit {
                                guard let delay = Self.orbitOrder[idx] else { return 0.07 }
                                let phase = ((elapsed - delay).truncatingRemainder(dividingBy: cycleDur) + cycleDur)
                                    .truncatingRemainder(dividingBy: cycleDur) / cycleDur
                                return 0.15 + 0.78 * max(0, sin(phase * .pi))
                            } else {
                                let delay = Self.driveDelays[idx]
                                let phase = ((elapsed - delay).truncatingRemainder(dividingBy: cycleDur) + cycleDur)
                                    .truncatingRemainder(dividingBy: cycleDur) / cycleDur
                                return 0.15 + 0.75 * max(0, sin(phase * .pi))
                            }
                        }()
                        let row = idx / 3
                        let col = idx % 3
                        let rect = CGRect(x: CGFloat(col) * 5.5, y: CGFloat(row) * 5.5, width: 4, height: 4)
                        gfx.fill(
                            Path(roundedRect: rect, cornerRadius: cornerR, style: .continuous),
                            with: .color(tokens.ink.opacity(opacity))
                        )
                    }
                }
                .frame(width: 15, height: 15)
                
                Text(self.label)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(tokens.ink2)
                
                if self.showTimer {
                    Text(Self.formatElapsed(elapsed))
                        .font(.system(size: 11.5, weight: .regular, design: .monospaced).monospacedDigit())
                        .foregroundStyle(tokens.ink3)
                }
            }
        }
        .observeWindowRenderActivity(self.$isWindowVisible)
    }
    
    
    private static func formatElapsed(_ seconds: TimeInterval) -> String {
        if seconds < 60 {
            return String(format: "%.1fs", seconds)
        }
        let mins = Int(seconds) / 60
        let rem = seconds - Double(mins * 60)
        return "\(mins)m \(String(format: "%.1fs", rem))"
    }
}


nonisolated struct BeautifulUIThinkingStep: Identifiable, Equatable, Sendable {
    let id: String
    let primary: String
    let secondary: String?
    let mono: Bool
    let isCompleted: Bool
    
    init(
        id: String = UUID().uuidString,
        primary: String,
        secondary: String? = nil,
        mono: Bool = false,
        isCompleted: Bool = false
    ) {
        self.id = id
        self.primary = primary
        self.secondary = secondary
        self.mono = mono
        self.isCompleted = isCompleted
    }
}

/// Expandable agent trace combining LeiBox `ThinkingOrbsParticleView` with Beautiful UI vertical guide lines.
struct BeautifulUIThinkingTrace: View {
    
    let isWorking: Bool
    let activeLabel: String
    let doneLabel: String
    var mode: ThinkingOrbsMode = .working
    var steps: [BeautifulUIThinkingStep] = []
    var initiallyExpanded: Bool = true
    
    @Environment(\.colorScheme) private var colorScheme
    @State private var isExpanded: Bool = true
    
    
    init(
        isWorking: Bool,
        activeLabel: String,
        doneLabel: String,
        mode: ThinkingOrbsMode = .working,
        steps: [BeautifulUIThinkingStep] = [],
        initiallyExpanded: Bool = true
    ) {
        self.isWorking = isWorking
        self.activeLabel = activeLabel
        self.doneLabel = doneLabel
        self.mode = mode
        self.steps = steps
        self.initiallyExpanded = initiallyExpanded
        self._isExpanded = State(initialValue: initiallyExpanded)
    }
    
    
    var body: some View {
        let tokens = BeautifulUITokens.resolve(isDark: self.colorScheme == .dark)
        
        VStack(alignment: .leading, spacing: 4) {
            Button {
                guard !self.steps.isEmpty else { return }
                withAnimation(.timingCurve(0.23, 1, 0.32, 1, duration: 0.24)) {
                    self.isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    ThinkingOrbsParticleView(
                        mode: self.mode,
                        size: 18,
                        color: self.isWorking ? tokens.ink2 : tokens.ink3,
                        paused: !self.isWorking
                    )
                    
                    Text(self.isWorking ? self.activeLabel : self.doneLabel)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(self.isWorking ? tokens.ink : tokens.ink2)
                    
                    if !self.steps.isEmpty {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9.5, weight: .semibold))
                            .foregroundStyle(tokens.ink3)
                            .rotationEffect(.degrees(self.isExpanded ? 180 : 0))
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            .buttonStyle(.plain)
            .pointerStyle(self.steps.isEmpty ? .default : .link)
            
            if !self.steps.isEmpty && self.isExpanded {
                HStack(alignment: .top, spacing: 10) {
                    Rectangle()
                        .fill(tokens.line)
                        .frame(width: 1)
                        .padding(.leading, 8)
                        .padding(.vertical, 4)
                    
                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(self.steps) { step in
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(step.isCompleted ? tokens.green : (self.isWorking ? tokens.accent : tokens.ink3))
                                    .frame(width: 5, height: 5)
                                
                                Text(step.primary)
                                    .font(step.mono ? .system(size: 11.5, design: .monospaced) : .system(size: 12))
                                    .foregroundStyle(tokens.ink2)
                                
                                if let secondary = step.secondary, !secondary.isEmpty {
                                    Text(secondary)
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundStyle(tokens.ink3)
                                }
                            }
                        }
                    }
                    .padding(.vertical, 3)
                }
                .padding(.leading, 6)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}


nonisolated struct AgentToolChipItem: Identifiable, Equatable, Hashable, Sendable {
    let id: String
    let label: String
    let detail: String?
    
    init(id: String = UUID().uuidString, label: String, detail: String? = nil) {
        self.id = id
        self.label = label
        self.detail = detail
    }
}

/// Compact pill chips displaying tool calls / executed actions (`beautifului.dev` ToolChips).
struct BeautifulUIToolChipsView: View {
    
    let items: [AgentToolChipItem]
    
    @Environment(\.colorScheme) private var colorScheme
    
    
    var body: some View {
        let tokens = BeautifulUITokens.resolve(isDark: self.colorScheme == .dark)
        
        if !self.items.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(self.items) { item in
                        HStack(spacing: 5) {
                            Circle()
                                .fill(tokens.green)
                                .frame(width: 5, height: 5)
                            
                            Text(item.label)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(tokens.ink)
                            
                            if let detail = item.detail, !detail.isEmpty {
                                Text(detail)
                                    .font(.system(size: 10.5, design: .monospaced))
                                    .foregroundStyle(tokens.ink3)
                            }
                        }
                        .padding(.horizontal, 9)
                        .frame(height: 22)
                        .background(tokens.field, in: Capsule())
                        .overlay(Capsule().strokeBorder(tokens.line, lineWidth: 0.75))
                    }
                }
            }
        }
    }
}


/// Shared Beautiful UI structured Markdown renderer backed by `NewsMarkdownParser`.
struct AgentMarkdownView: View {
    
    let markdown: String
    let isStreaming: Bool
    
    @Environment(\.colorScheme) private var colorScheme
    @State private var copiedCodeKey: String?
    
    
    var body: some View {
        let tokens = BeautifulUITokens.resolve(isDark: self.colorScheme == .dark)
        let blocks = MarkdownRenderCache.blocks(for: self.markdown)
        
        VStack(alignment: .leading, spacing: 9) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { idx, block in
                let key = "bui-\(idx)"
                AgentMarkdownBlockRow(
                    block: block,
                    tokens: tokens,
                    isCopied: self.copiedCodeKey == key,
                    onCopyCode: { code in
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(code, forType: .string)
                        self.copiedCodeKey = key
                        Task { @MainActor in
                            try? await Task.sleep(for: .seconds(1.5))
                            if self.copiedCodeKey == key { self.copiedCodeKey = nil }
                        }
                    }
                )
                .equatable()
            }
            
            if self.isStreaming {
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(tokens.accent)
                    .frame(width: 6, height: 13)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}


private struct AgentMarkdownBlockRow: View, Equatable {
    
    let block: NewsMarkdownBlock
    let tokens: BeautifulUITokens
    let isCopied: Bool
    let onCopyCode: (String) -> Void
    
    
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.block == rhs.block && lhs.tokens == rhs.tokens && lhs.isCopied == rhs.isCopied
    }
    
    
    var body: some View {
        let tokens = self.tokens
        switch self.block {
            case .heading(let level, let text):
                self.inlineText(text)
                    .font(.system(size: level == 1 ? 15.5 : (level == 2 ? 14 : 13.2), weight: .semibold))
                    .foregroundStyle(tokens.ink)
                    .padding(.top, level <= 2 ? 4 : 2)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
            case .paragraph(let text):
                self.inlineText(text)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(tokens.ink.opacity(0.94))
                    .lineSpacing(5)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
            case .bulletList(let items):
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                        HStack(alignment: .top, spacing: 8) {
                            Circle()
                                .fill(tokens.ink3)
                                .frame(width: 4, height: 4)
                                .padding(.top, 6.5)
                            
                            self.inlineText(item)
                                .font(.system(size: 13))
                                .foregroundStyle(tokens.ink.opacity(0.94))
                                .lineSpacing(4.5)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .padding(.leading, 2)
                
            case .orderedList(let items):
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                        HStack(alignment: .top, spacing: 6) {
                            Text("\(item.number).")
                                .font(.system(size: 12, weight: .semibold, design: .rounded).monospacedDigit())
                                .foregroundStyle(tokens.accentInk)
                                .frame(minWidth: 18, alignment: .trailing)
                                .padding(.top, 1)
                            
                            self.inlineText(item.text)
                                .font(.system(size: 13))
                                .foregroundStyle(tokens.ink.opacity(0.94))
                                .lineSpacing(4.5)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                
            case .blockquote(let text):
                HStack(alignment: .top, spacing: 10) {
                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                        .fill(tokens.lineStrong)
                        .frame(width: 2.5)
                    
                    self.inlineText(text)
                        .font(.system(size: 12.5))
                        .foregroundStyle(tokens.ink2)
                        .lineSpacing(4.5)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(tokens.inset, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                
            case .codeBlock(let language, let code):
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text(language.isEmpty ? "code" : language)
                            .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                            .foregroundStyle(tokens.ink3)
                        Spacer()
                        Button {
                            self.onCopyCode(code)
                        } label: {
                            Text(self.isCopied ? AppLanguage.text("已复制", en: "Copied") : AppLanguage.text("复制代码", en: "Copy"))
                                .font(.system(size: 10.5, weight: .medium))
                                .foregroundStyle(self.isCopied ? tokens.accentInk : tokens.ink2)
                        }
                        .buttonStyle(.plain)
                        .pointerStyle(.link)
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 27)
                    .background(tokens.field)
                    
                    ScrollView(.horizontal, showsIndicators: true) {
                        Text(code)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(tokens.ink)
                            .textSelection(.enabled)
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .background(tokens.inset, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(tokens.line, lineWidth: 0.75))
                
            case .table(let headers, let rows):
                let colCount = max(1, headers.count)
                ScrollView(.horizontal, showsIndicators: true) {
                    VStack(spacing: 0) {
                        HStack(spacing: 0) {
                            ForEach(0..<colCount, id: \.self) { col in
                                self.inlineText(headers[col])
                                    .font(.system(size: 11.5, weight: .semibold))
                                    .foregroundStyle(tokens.ink)
                                    .padding(.horizontal, 9)
                                    .padding(.vertical, 6)
                                    .frame(minWidth: 80, maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .background(tokens.field)
                        
                        ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                            Rectangle().fill(tokens.line).frame(height: 0.5)
                            HStack(spacing: 0) {
                                ForEach(0..<colCount, id: \.self) { col in
                                    self.inlineText(col < row.count ? row[col] : "")
                                        .font(.system(size: 11.8))
                                        .foregroundStyle(tokens.ink2)
                                        .padding(.horizontal, 9)
                                        .padding(.vertical, 6)
                                        .frame(minWidth: 80, maxWidth: .infinity, alignment: .leading)
                                }
                            }
                        }
                    }
                }
                .background(tokens.inset, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(tokens.line, lineWidth: 0.75))
                
            case .divider:
                Rectangle()
                    .fill(tokens.line)
                    .frame(height: 0.8)
                    .padding(.vertical, 2)
        }
    }
    
    
    private func inlineText(_ raw: String) -> Text {
        if let attr = MarkdownRenderCache.attributedInline(for: raw) {
            return Text(attr)
        }
        return Text(raw)
    }
}


// MARK: - Unified Chat Header, Message Row & Prompt Bar

nonisolated struct AgentChatMessageItem: Identifiable, Equatable, Sendable {
    let id: String
    let isUser: Bool
    let text: String
    let toolChips: [AgentToolChipItem]
    
    init(
        id: String,
        isUser: Bool,
        text: String,
        toolChips: [AgentToolChipItem] = []
    ) {
        self.id = id
        self.isUser = isUser
        self.text = text
        self.toolChips = toolChips
    }
}

nonisolated struct AgentModelOption: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let endpointID: UUID?
    let modelID: String
    
    init(
        id: String? = nil,
        title: String? = nil,
        endpointID: UUID? = nil,
        modelID: String
    ) {
        self.endpointID = endpointID
        self.modelID = modelID
        self.title = title ?? modelID
        self.id = id ?? "\(endpointID?.uuidString ?? "default")::\(modelID)"
    }
}

/// Equatable single-message row styled after `beautifului.dev` Chat component (completed rows never re-render while streaming).
struct BeautifulUIMessageRow: View, Equatable {
    
    let message: AgentChatMessageItem
    let isStreaming: Bool
    let isCopied: Bool
    let thinkingMode: ThinkingOrbsMode
    let tokens: BeautifulUITokens
    let onCopy: () -> Void
    
    
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.message == rhs.message
            && lhs.isStreaming == rhs.isStreaming
            && lhs.isCopied == rhs.isCopied
            && lhs.thinkingMode == rhs.thinkingMode
            && lhs.tokens == rhs.tokens
    }
    
    
    var body: some View {
        if self.message.isUser {
            HStack {
                Spacer(minLength: 48)
                Text(self.message.text)
                    .font(.system(size: 13))
                    .foregroundStyle(self.tokens.ink)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(self.tokens.field, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .textSelection(.enabled)
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                if self.isStreaming && self.message.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    BeautifulUIThinkingTrace(
                        isWorking: true,
                        activeLabel: AppLanguage.text("正在思考…", en: "Thinking…"),
                        doneLabel: AppLanguage.text("已完成", en: "Done"),
                        mode: self.thinkingMode
                    )
                } else {
                    AgentMarkdownView(markdown: self.message.text, isStreaming: self.isStreaming)
                    
                    if !self.message.toolChips.isEmpty {
                        BeautifulUIToolChipsView(items: self.message.toolChips)
                    }
                    
                    if !self.isStreaming && !self.message.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        HStack {
                            Spacer(minLength: 0)
                            Button(action: self.onCopy) {
                                Text(self.isCopied ? AppLanguage.text("已复制", en: "Copied") : AppLanguage.text("复制", en: "Copy"))
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(self.isCopied ? self.tokens.accentInk : self.tokens.ink3)
                                    .padding(.horizontal, 8)
                                    .frame(height: 22)
                                    .background(self.tokens.field, in: Capsule())
                            }
                            .buttonStyle(.plain)
                            .pointerStyle(.link)
                        }
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(self.tokens.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(self.tokens.line, lineWidth: 0.8))
        }
    }
}


/// Reusable PromptBar composer (`beautifului.dev` PromptBar) with isolated draft state and click-to-select model picker.
struct BeautifulUIPromptBar: View {
    
    let placeholder: String
    let isStreaming: Bool
    let availableModels: [AgentModelOption]
    let selectedModelTitle: String
    let tokens: BeautifulUITokens
    var onSelectModel: ((AgentModelOption) -> Void)? = nil
    var onOpenModelSettings: (() -> Void)? = nil
    let onSend: (String) -> Void
    
    @State private var draftText: String = ""
    @FocusState private var isFocused: Bool
    
    
    private var canSend: Bool {
        !self.isStreaming && !self.draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField(self.placeholder, text: self.$draftText, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(self.tokens.ink)
                .focused(self.$isFocused)
                .lineLimit(1...6)
                .onSubmit {
                    self.submit()
                }
            
            HStack(spacing: 8) {
                Menu {
                    if self.availableModels.isEmpty {
                        Button(AppLanguage.text("前往「API 网关」配置 OpenCode Go…", en: "Configure OpenCode Go…")) {
                            self.onOpenModelSettings?()
                        }
                    } else {
                        ForEach(self.availableModels) { option in
                            let selected = (option.title == self.selectedModelTitle || option.modelID == self.selectedModelTitle)
                            Button {
                                self.onSelectModel?(option)
                            } label: {
                                Text(selected ? "✓  \(option.title)" : option.title)
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(self.selectedModelTitle)
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(self.tokens.ink2)
                            .fixedSize(horizontal: true, vertical: false)
                        
                        Image(systemName: "chevron.down")
                            .font(.system(size: 8.5, weight: .semibold))
                            .foregroundStyle(self.tokens.ink3)
                    }
                    .padding(.horizontal, 8)
                    .frame(height: 26)
                    .background(self.tokens.surface, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(self.tokens.line, lineWidth: 0.75))
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .pointerStyle(.link)
                
                Spacer(minLength: 4)
                
                Button(action: self.submit) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(self.canSend ? self.tokens.ink : self.tokens.lineStrong)
                            .frame(width: 28, height: 28)
                        
                        if self.isStreaming {
                            ThinkingOrbsParticleView(mode: .working, size: 16, color: self.tokens.ink2)
                        } else {
                            Image(systemName: "arrow.up")
                                .font(.system(size: 12.5, weight: .bold))
                                .foregroundStyle(self.canSend ? self.tokens.surface : self.tokens.ink2)
                        }
                    }
                }
                .buttonStyle(.plain)
                .pointerStyle(.link)
                .disabled(!self.canSend)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(self.tokens.field, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(self.isFocused ? self.tokens.lineStrong : self.tokens.line, lineWidth: 1.0)
        )
    }
    
    
    private func submit() {
        let trimmed = self.draftText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !self.isStreaming else { return }
        self.draftText = ""
        self.onSend(trimmed)
    }
}


/// Unified minimalist Bot identity header bar shared across all Bot chat panes (no SVG/cartoon icon clutter).
struct AgentChatHeaderBar<TrailingActions: View>: View {
    
    let avatarImage: NSImage?
    let name: String
    let nickname: String
    let accent: Color
    let tokens: BeautifulUITokens
    @ViewBuilder var leadingControl: () -> AnyView
    @ViewBuilder var trailingActions: () -> TrailingActions
    
    
    init(
        avatarImage: NSImage?,
        name: String,
        nickname: String,
        accent: Color,
        tokens: BeautifulUITokens,
        @ViewBuilder trailingActions: @escaping () -> TrailingActions
    ) {
        self.avatarImage = avatarImage
        self.name = name
        self.nickname = nickname
        self.accent = accent
        self.tokens = tokens
        self.leadingControl = { AnyView(EmptyView()) }
        self.trailingActions = trailingActions
    }
    
    
    init<Leading: View>(
        avatarImage: NSImage?,
        name: String,
        nickname: String,
        accent: Color,
        tokens: BeautifulUITokens,
        @ViewBuilder leadingControl: @escaping () -> Leading,
        @ViewBuilder trailingActions: @escaping () -> TrailingActions
    ) {
        self.avatarImage = avatarImage
        self.name = name
        self.nickname = nickname
        self.accent = accent
        self.tokens = tokens
        self.leadingControl = { AnyView(leadingControl()) }
        self.trailingActions = trailingActions
    }
    
    
    var body: some View {
        HStack(spacing: 8) {
            self.leadingControl()
            
            ZStack {
                if let avatarImage = self.avatarImage {
                    Image(nsImage: avatarImage)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFill()
                } else {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(self.accent.opacity(0.14))
                    Text(String(self.name.prefix(1)))
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(self.accent)
                }
            }
            .frame(width: 24, height: 24)
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(self.tokens.lineStrong, lineWidth: 0.7)
            )
            
            Text(self.name)
                .font(.system(size: 13.5, weight: .semibold))
                .foregroundStyle(self.tokens.ink)
            
            if !self.nickname.isEmpty {
                Text("@\(self.nickname)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(self.tokens.ink2)
                    .padding(.horizontal, 7)
                    .frame(height: 20)
                    .background(self.tokens.field, in: Capsule())
            }
            
            Spacer(minLength: 4)
            
            self.trailingActions()
        }
        .padding(.horizontal, 12)
        .frame(height: 44)
        .background(self.tokens.surface)
    }
}


/// Unified chat surface used globally across Butler, Reading Companion, and Bot chats:
/// - Empty state: clean DissolveThinkingOrbView + "Hello" (zero fixed starter prompt chips)
/// - Message list: Equatable BeautifulUIMessageRow + throttled bottom scroll
/// - Footer: BeautifulUIPromptBar with selectable models
struct AgentChatTranscriptSurface: View {
    
    let messages: [AgentChatMessageItem]
    let isStreaming: Bool
    var streamingDraft: String? = nil
    let errorMessage: String?
    let placeholder: String
    let availableModels: [AgentModelOption]
    let selectedModelTitle: String
    let orbColor: Color?
    let tokens: BeautifulUITokens
    var onSelectModel: ((AgentModelOption) -> Void)? = nil
    var onOpenSettings: (() -> Void)? = nil
    let onSend: (String) -> Void
    
    @State private var copiedID: String?
    @State private var lastScrollAt: Date = .distantPast
    
    
    var body: some View {
        let displayMessages: [AgentChatMessageItem] = {
            var list = self.messages
            if self.isStreaming, let streamingDraft = self.streamingDraft {
                list.append(AgentChatMessageItem(
                    id: "__streaming_tail__",
                    isUser: false,
                    text: streamingDraft
                ))
            }
            return list
        }()
        
        return VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: true) {
                    if displayMessages.isEmpty {
                        VStack(spacing: 14) {
                            Spacer(minLength: 36)
                            
                            DissolveThinkingOrbView(
                                state: .idle,
                                size: 54,
                                interactive: true,
                                color: self.orbColor ?? self.tokens.ink
                            )
                            
                            Text("Hello")
                                .font(.system(size: 22, weight: .semibold))
                                .tracking(-0.4)
                                .foregroundStyle(self.tokens.ink)
                            
                            Spacer(minLength: 36)
                        }
                        .frame(maxWidth: .infinity, minHeight: 280)
                        .padding(.horizontal, 20)
                    } else {
                        LazyVStack(alignment: .leading, spacing: 12) {
                            ForEach(displayMessages) { msg in
                                let isTailStreaming = self.isStreaming && msg.id == displayMessages.last?.id
                                BeautifulUIMessageRow(
                                    message: msg,
                                    isStreaming: isTailStreaming,
                                    isCopied: self.copiedID == msg.id,
                                    thinkingMode: .working,
                                    tokens: self.tokens,
                                    onCopy: {
                                        let trimmed = msg.text.trimmingCharacters(in: .whitespacesAndNewlines)
                                        guard !trimmed.isEmpty else { return }
                                        NSPasteboard.general.clearContents()
                                        NSPasteboard.general.setString(trimmed, forType: .string)
                                        self.copiedID = msg.id
                                        Task { @MainActor in
                                            try? await Task.sleep(for: .seconds(1.5))
                                            if self.copiedID == msg.id { self.copiedID = nil }
                                        }
                                    }
                                )
                                .equatable()
                                .id(msg.id)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                        .frame(maxWidth: 740, alignment: .leading)
                        .frame(maxWidth: .infinity, alignment: .center)
                    }
                    
                    if let errorMessage = self.errorMessage, !errorMessage.isEmpty {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(self.tokens.orange)
                                .frame(width: 6, height: 6)
                            
                            Text(errorMessage)
                                .font(.system(size: 12))
                                .foregroundStyle(self.tokens.ink2)
                                .fixedSize(horizontal: false, vertical: true)
                            
                            Spacer(minLength: 4)
                            
                            if let onOpenSettings = self.onOpenSettings {
                                Button(AppLanguage.text("去配置", en: "Settings"), action: onOpenSettings)
                                    .font(.system(size: 11.5, weight: .semibold))
                                    .foregroundStyle(self.tokens.accentInk)
                                    .buttonStyle(.plain)
                                    .pointerStyle(.link)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background(self.tokens.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(self.tokens.orange.opacity(0.45), lineWidth: 0.8))
                        .padding(.horizontal, 16)
                        .padding(.bottom, 12)
                        .frame(maxWidth: 740)
                        .frame(maxWidth: .infinity, alignment: .center)
                    }
                }
                .onChange(of: displayMessages.last?.text ?? "") { _, _ in
                    guard let lastID = displayMessages.last?.id else { return }
                    let now = Date()
                    guard !self.isStreaming || now.timeIntervalSince(self.lastScrollAt) >= 0.085 else { return }
                    self.lastScrollAt = now
                    proxy.scrollTo(lastID, anchor: .bottom)
                }
                .onChange(of: displayMessages.count) { _, _ in
                    if let lastID = displayMessages.last?.id {
                        withAnimation(.easeOut(duration: 0.14)) {
                            proxy.scrollTo(lastID, anchor: .bottom)
                        }
                    }
                }
            }
            
            BeautifulUIPromptBar(
                placeholder: self.placeholder,
                isStreaming: self.isStreaming,
                availableModels: self.availableModels,
                selectedModelTitle: self.selectedModelTitle,
                tokens: self.tokens,
                onSelectModel: self.onSelectModel,
                onOpenModelSettings: self.onOpenSettings,
                onSend: self.onSend
            )
            .padding(.horizontal, 14)
            .padding(.top, 6)
            .padding(.bottom, 14)
            .frame(maxWidth: 740)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .background(self.tokens.page)
    }
}
