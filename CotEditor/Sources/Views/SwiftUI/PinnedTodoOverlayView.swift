//
//  PinnedTodoOverlayView.swift
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

/// Computed visual urgency and lightweight typography metrics for a pinned todo capsule.
nonisolated struct PinnedTodoUrgencyMetrics: Sendable, Equatable {
    
    var fontSize: CGFloat
    var progress: Double
    var isOverdue: Bool
    var isWindowBursting: Bool
    var remainingText: String?
    var urgencyLevel: Int   // 0 = timeless, 1 = calm, 2 = approaching, 3 = imminent, 4 = critical/overdue
}


/// Playful animated IP companion styles rendered inside pinned todo capsules.
nonisolated enum TodoMascotKind: String, CaseIterable, Identifiable, Codable, Sendable {
    
    case autoMix
    case claudeChibi
    case deepseekFish
    case usagiPixel
    
    var id: String { self.rawValue }
    
    
    var displayName: String {
        switch self {
            case .autoMix: AppLanguage.text("灵动混搭", en: "Auto Mix")
            case .claudeChibi: AppLanguage.text("Claude 小橘灵", en: "Claude Chibi")
            case .deepseekFish: AppLanguage.text("DeepSeek 像素大肥鱼", en: "Pixel Whale")
            case .usagiPixel: AppLanguage.text("像素乌萨奇", en: "Pixel Usagi")
        }
    }
    
    
    /// Resolves `.autoMix` deterministically per item ID so consecutive pills show diverse IP buddies.
    func resolvedKind(for seedID: String) -> TodoMascotKind {
        guard self == .autoMix else { return self }
        let concrete: [TodoMascotKind] = [.claudeChibi, .deepseekFish, .usagiPixel]
        let sum = seedID.unicodeScalars.reduce(0) { $0 &+ Int($1.value) }
        return concrete[abs(sum) % concrete.count]
    }
    
    
    @MainActor
    static var persisted: TodoMascotKind {
        let raw = CotLocalDatabase.shared.string(
            forKey: CotLocalDatabase.ConfigKey.pinnedTodoMascot,
            default: TodoMascotKind.autoMix.rawValue
        )
        return TodoMascotKind(rawValue: raw) ?? .autoMix
    }
    
    
    @MainActor
    func saveAsDefault() {
        CotLocalDatabase.shared.set(self.rawValue, forKey: CotLocalDatabase.ConfigKey.pinnedTodoMascot)
    }
}


/// Featherweight urgency model that gently shifts capsule accent and subtle emphasis
/// without ever hijacking or obstructing the editor canvas.
nonisolated enum PinnedTodoUrgency {
    
    static func metrics(
        createdAt: Date,
        deadline: Date?,
        now: Date,
        containerSize: CGSize
    ) -> PinnedTodoUrgencyMetrics {
        
        guard let deadline else {
            return PinnedTodoUrgencyMetrics(
                fontSize: 12.2,
                progress: 0,
                isOverdue: false,
                isWindowBursting: false,
                remainingText: nil,
                urgencyLevel: 0
            )
        }
        
        let remaining = deadline.timeIntervalSince(now)
        let totalSpan = max(60.0, deadline.timeIntervalSince(createdAt))
        let spanRatio = min(1.0, max(0.0, now.timeIntervalSince(createdAt) / totalSpan))
        
        let timePressure: Double
        if remaining <= 0 {
            timePressure = 1.0
        } else if remaining <= 60 {
            timePressure = 0.92 + (1.0 - remaining / 60.0) * 0.08
        } else if remaining <= 600 {
            timePressure = 0.72 + (1.0 - (remaining - 60.0) / 540.0) * 0.20
        } else if remaining <= 1800 {
            timePressure = 0.52 + (1.0 - (remaining - 600.0) / 1200.0) * 0.20
        } else if remaining <= 7200 {
            timePressure = 0.26 + (1.0 - (remaining - 1800.0) / 5400.0) * 0.26
        } else {
            timePressure = max(0.02, 0.26 * (7200.0 / remaining))
        }
        
        let effectiveProgress = min(1.0, max(spanRatio * 0.85, timePressure))
        let isOverdue = (remaining <= 0)
        
        let fontSize: CGFloat
        let urgencyLevel: Int
        
        if remaining <= 0 {
            let overdueRatio = min(1.0, (-remaining) / 300.0)
            fontSize = 13.4 + CGFloat(overdueRatio) * 0.4
            urgencyLevel = 4
        } else if remaining <= 45 || effectiveProgress >= 0.96 {
            let countdownRatio = min(1.0, max(0.0, 1.0 - remaining / 45.0))
            fontSize = 13.1 + CGFloat(countdownRatio) * 0.3
            urgencyLevel = 4
        } else if effectiveProgress >= 0.72 {
            let localT = (effectiveProgress - 0.72) / 0.24
            fontSize = 12.8 + CGFloat(localT) * 0.4
            urgencyLevel = 3
        } else if effectiveProgress >= 0.45 {
            let localT = (effectiveProgress - 0.45) / 0.27
            fontSize = 12.5 + CGFloat(localT) * 0.3
            urgencyLevel = 2
        } else {
            let localT = effectiveProgress / 0.45
            fontSize = 12.2 + CGFloat(localT) * 0.3
            urgencyLevel = 1
        }
        
        return PinnedTodoUrgencyMetrics(
            fontSize: fontSize,
            progress: effectiveProgress,
            isOverdue: isOverdue,
            isWindowBursting: false,
            remainingText: Self.formatRemaining(remaining),
            urgencyLevel: urgencyLevel
        )
    }
    
    
    static func compactBadgeText(_ remaining: TimeInterval) -> String {
        
        let isEn = (AppLanguage.current == .english)
        let overduePrefix = isEn ? "Overdue " : "超时 "
        let absSeconds = Int(abs(remaining).rounded(.down))
        if remaining < 0 {
            if absSeconds < 60 {
                return "\(overduePrefix)\(max(1, absSeconds))s"
            }
            let minutes = absSeconds / 60
            if minutes < 60 {
                return "\(overduePrefix)\(minutes)m"
            }
            let hours = minutes / 60
            if hours < 24 {
                return "\(overduePrefix)\(hours)h"
            }
            return "\(overduePrefix)\(hours / 24)d"
        }
        
        if absSeconds < 60 {
            return "\(max(1, absSeconds))s"
        }
        let minutes = absSeconds / 60
        if minutes < 60 {
            return "\(minutes)m"
        }
        let hours = minutes / 60
        let remMin = minutes % 60
        if hours < 24 {
            return remMin > 0 ? "\(hours)h \(remMin)m" : "\(hours)h"
        }
        return "\(hours / 24)d"
    }
    
    
    static func formatRemaining(_ remaining: TimeInterval) -> String {
        
        let absSeconds = Int(abs(remaining).rounded(.down))
        let prefix = remaining < 0 ? "已超时 " : "还剩 "
        
        if absSeconds < 60 {
            return "\(prefix)\(max(1, absSeconds)) 秒"
        }
        let minutes = absSeconds / 60
        let seconds = absSeconds % 60
        if minutes < 60 {
            return remaining < 0 || minutes >= 10
                ? "\(prefix)\(minutes) 分钟"
                : "\(prefix)\(minutes) 分 \(seconds) 秒"
        }
        let hours = minutes / 60
        let remMin = minutes % 60
        if hours < 24 {
            return remMin > 0 ? "\(prefix)\(hours) 小时 \(remMin) 分" : "\(prefix)\(hours) 小时"
        }
        let days = hours / 24
        let remHours = hours % 24
        return remHours > 0 ? "\(prefix)\(days) 天 \(remHours) 小时" : "\(prefix)\(days) 天"
    }
}


// MARK: - Animated IP Companions (Claude Chibi & DeepSeek Pixel Fat Fish & Pixel Usagi)

/// Reusable animated pixel/chibi mascot companion that breathes inside todo capsules.
struct PinnedTodoMascotAvatar: View {
    
    let kind: TodoMascotKind
    var isHovered: Bool = false
    var isUrgent: Bool = false
    var isCompleting: Bool = false
    var size: CGFloat = 22
    var phaseSeed: Double = 0
    
    @Environment(\.colorScheme) private var colorScheme
    
    
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24.0, paused: AnimationConstants.isReducedMotionEnabled)) { context in
            let t = context.date.timeIntervalSinceReferenceDate + self.phaseSeed
            let bob = self.isCompleting
                ? -4.5
                : (sin(t * (self.isUrgent ? 7.2 : 2.6)) * (self.isHovered ? 1.8 : 1.1))
            let tilt = self.isCompleting
                ? 14.0
                : (self.isHovered ? sin(t * 5.0) * 6.0 : (self.isUrgent ? sin(t * 14.0) * 4.5 : sin(t * 1.4) * 2.0))
            
            Canvas { ctx, canvasSize in
                switch self.kind {
                    case .claudeChibi, .autoMix:
                        Self.drawClaudeChibi(in: ctx, size: canvasSize, t: t, happy: self.isHovered || self.isCompleting, urgent: self.isUrgent)
                    case .deepseekFish:
                        Self.drawPixelDeepSeekFish(in: ctx, size: canvasSize, t: t, happy: self.isHovered || self.isCompleting, urgent: self.isUrgent, isDark: self.colorScheme == .dark)
                    case .usagiPixel:
                        Self.drawPixelUsagi(in: ctx, size: canvasSize, t: t, happy: self.isHovered || self.isCompleting, isDark: self.colorScheme == .dark)
                }
            }
            .frame(width: self.size, height: self.size)
            .offset(y: bob)
            .rotationEffect(.degrees(tilt))
            .scaleEffect(self.isCompleting ? 1.24 : (self.isHovered ? 1.10 : 1.0))
            .animation(.spring(response: 0.28, dampingFraction: 0.64), value: self.isCompleting)
            .animation(.spring(response: 0.25, dampingFraction: 0.72), value: self.isHovered)
        }
    }
    
    
    private static func drawClaudeChibi(in ctx: GraphicsContext, size: CGSize, t: Double, happy: Bool, urgent: Bool) {
        let w = size.width
        let h = size.height
        let cx = w * 0.5
        let cy = h * 0.53
        let r = min(w, h) * 0.40
        
        // 8 plump rounded starburst lobes creating Claude's warm sunburst silhouette
        let terracotta = urgent
            ? Color(red: 0.94, green: 0.36, blue: 0.28)
            : Color(red: 0.85, green: 0.47, blue: 0.34)
        let warmGlow = Color(red: 0.97, green: 0.67, blue: 0.52)
        
        let rays = 10
        let breatheAngle = sin(t * 1.2) * 0.08
        for i in 0..<rays {
            let theta = Double(i) * (.pi * 2.0 / Double(rays)) + breatheAngle
            let px = cx + cos(theta) * (r * 0.64)
            let py = cy + sin(theta) * (r * 0.64)
            let lobeR = r * (i % 2 == 0 ? 0.34 : 0.27)
            let rect = CGRect(x: px - lobeR, y: py - lobeR, width: lobeR * 2, height: lobeR * 2)
            ctx.fill(Path(ellipseIn: rect), with: .color(terracotta))
        }
        
        let coreRect = CGRect(x: cx - r * 0.72, y: cy - r * 0.70, width: r * 1.44, height: r * 1.40)
        ctx.fill(
            Path(ellipseIn: coreRect),
            with: .linearGradient(
                Gradient(colors: [warmGlow, terracotta]),
                startPoint: CGPoint(x: cx, y: cy - r),
                endPoint: CGPoint(x: cx, y: cy + r)
            )
        )
        
        // Kawaii cheeks
        let cheekColor = Color(red: 1.0, green: 0.72, blue: 0.70).opacity(0.85)
        ctx.fill(Path(ellipseIn: CGRect(x: cx - r * 0.48, y: cy + r * 0.08, width: r * 0.24, height: r * 0.14)), with: .color(cheekColor))
        ctx.fill(Path(ellipseIn: CGRect(x: cx + r * 0.24, y: cy + r * 0.08, width: r * 0.24, height: r * 0.14)), with: .color(cheekColor))
        
        // Eyes: natural blink cycle + "^ ^" happy crescent when hovered/completing
        let ink = Color(red: 0.16, green: 0.10, blue: 0.08)
        let cycle = t.truncatingRemainder(dividingBy: 3.4)
        let isBlinking = cycle > 3.22
        
        if happy {
            for side in [-1.0, 1.0] {
                var arc = Path()
                let ex = cx + side * r * 0.24
                let ey = cy - r * 0.02
                arc.move(to: CGPoint(x: ex - r * 0.11, y: ey + r * 0.04))
                arc.addQuadCurve(to: CGPoint(x: ex + r * 0.11, y: ey + r * 0.04), control: CGPoint(x: ex, y: ey - r * 0.14))
                ctx.stroke(arc, with: .color(ink), style: StrokeStyle(lineWidth: max(1.1, w * 0.065), lineCap: .round))
            }
        } else if isBlinking {
            for side in [-1.0, 1.0] {
                let ex = cx + side * r * 0.24
                let ey = cy - r * 0.01
                let rect = CGRect(x: ex - r * 0.10, y: ey, width: r * 0.20, height: max(1.0, h * 0.045))
                ctx.fill(Path(roundedRect: rect, cornerRadius: 1), with: .color(ink))
            }
        } else {
            for side in [-1.0, 1.0] {
                let ex = cx + side * r * 0.24
                let ey = cy - r * 0.05
                let eyeR = max(1.1, r * 0.11)
                ctx.fill(Path(ellipseIn: CGRect(x: ex - eyeR, y: ey - eyeR, width: eyeR * 2, height: eyeR * 2.2)), with: .color(ink))
                ctx.fill(Path(ellipseIn: CGRect(x: ex - eyeR * 0.35, y: ey - eyeR * 0.55, width: eyeR * 0.7, height: eyeR * 0.7)), with: .color(.white))
            }
        }
        
        // Tiny smile dot
        var mouth = Path()
        mouth.move(to: CGPoint(x: cx - r * 0.10, y: cy + r * 0.20))
        mouth.addQuadCurve(to: CGPoint(x: cx + r * 0.10, y: cy + r * 0.20), control: CGPoint(x: cx, y: cy + r * 0.31))
        ctx.stroke(mouth, with: .color(ink), style: StrokeStyle(lineWidth: max(1.0, w * 0.05), lineCap: .round))
    }
    
    
    private static func drawPixelDeepSeekFish(in ctx: GraphicsContext, size: CGSize, t: Double, happy: Bool, urgent: Bool, isDark: Bool) {
        // 12x12 crisp pixel art grid for DeepSeek 大肥鱼 (chubby cerulean pixel whale/fish)
        let wagFrame = Int(t * (urgent ? 8.0 : (happy ? 5.0 : 2.6))) % 2
        let bubbleStep = Int(t * 2.2) % 3
        
        let gridA: [String] = [
            "............",
            "....SS......",
            ".....S......",
            "..BBBBBB....",
            ".BHHHHHHB...",
            "BBHBBBBBBBT.",
            "BBBEBBBBBBTT",
            "BBBCWWWWBBT.",
            ".BWWWWWWWB..",
            "..BWWWWWB...",
            "...BBBBB....",
            "............",
        ]
        let gridB: [String] = [
            "............",
            ".....SS.....",
            "....S.......",
            "..BBBBBB....",
            ".BHHHHHHBT..",
            "BBHBBBBBBTT.",
            "BBBEBBBBBBT.",
            "BBBCWWWWBB..",
            ".BWWWWWWWB..",
            "..BWWWWWB...",
            "...BBBBB....",
            "............",
        ]
        
        var rows = (wagFrame == 0) ? gridA : gridB
        // Animate tiny pixel water spout droplet
        var row0 = Array(rows[0])
        row0[3 + (bubbleStep % 2)] = "S"
        rows[0] = String(row0)
        
        let px = size.width / 12.0
        let py = size.height / 12.0
        let blue = urgent ? Color(red: 0.38, green: 0.44, blue: 0.98) : Color(red: 0.22, green: 0.43, blue: 0.96)
        let highlight = Color(red: 0.46, green: 0.69, blue: 1.00)
        let belly = isDark ? Color(red: 0.92, green: 0.95, blue: 1.00) : Color(red: 0.96, green: 0.98, blue: 1.00)
        let tail = Color(red: 0.16, green: 0.34, blue: 0.86)
        let cheek = Color(red: 1.00, green: 0.60, blue: 0.72)
        let spout = Color(red: 0.48, green: 0.85, blue: 0.98)
        let eye = Color(red: 0.08, green: 0.10, blue: 0.18)
        
        for (r, line) in rows.enumerated() {
            for (c, ch) in line.enumerated() {
                let color: Color? = switch ch {
                    case "B": blue
                    case "H": highlight
                    case "W": belly
                    case "T": tail
                    case "C": cheek
                    case "E": eye
                    case "S": spout
                    default: nil
                }
                guard let color else { continue }
                let rect = CGRect(x: CGFloat(c) * px, y: CGFloat(r) * py, width: ceil(px), height: ceil(py))
                ctx.fill(Path(rect), with: .color(color))
            }
        }
    }
    
    
    private static func drawPixelUsagi(in ctx: GraphicsContext, size: CGSize, t: Double, happy: Bool, isDark: Bool) {
        // 12x12 pixel art bunny inspired by 乌萨奇
        let hopFrame = Int(t * (happy ? 5.0 : 2.2)) % 2
        let rows: [String] = [
            "...EE..EE...",
            "...EP..EP...",
            "...EP..EP...",
            "..YYYYYYYY..",
            ".YYYYYYYYYY.",
            ".YYEYYYYEYY.",
            ".YYCYYYYCYY.",
            ".YYYYYYYYYY.",
            "..YYYYYYYY..",
            hopFrame == 0 ? "..YY....YY.." : "...YY..YY...",
            "............",
            "............",
        ]
        let px = size.width / 12.0
        let py = size.height / 12.0
        let cream = Color(red: 1.00, green: 0.93, blue: 0.68)
        let outline = isDark ? Color(red: 0.85, green: 0.75, blue: 0.45) : Color(red: 0.35, green: 0.25, blue: 0.20)
        let pink = Color(red: 1.00, green: 0.64, blue: 0.74)
        let eye = Color(red: 0.20, green: 0.14, blue: 0.12)
        
        for (r, line) in rows.enumerated() {
            for (c, ch) in line.enumerated() {
                let color: Color? = switch ch {
                    case "Y": cream
                    case "P", "C": pink
                    case "E": (r < 3 ? outline : eye)
                    default: nil
                }
                guard let color else { continue }
                let rect = CGRect(x: CGFloat(c) * px, y: CGFloat(r) * py, width: ceil(px), height: ceil(py))
                ctx.fill(Path(rect), with: .color(color))
            }
        }
    }
}


// MARK: - Pass-Through Hit-Testing Infrastructure

@MainActor
final class PinnedTodoHitTestStore {
    
    var interactiveRects: [CGRect] = []
}


private struct PinnedTodoHitRectsPreferenceKey: PreferenceKey {
    
    static let defaultValue: [CGRect] = []
    
    static func reduce(value: inout [CGRect], nextValue: () -> [CGRect]) {
        value.append(contentsOf: nextValue())
    }
}


private struct ReportInteractiveRectModifier: ViewModifier {
    
    func body(content: Content) -> some View {
        content.background(
            GeometryReader { geo in
                Color.clear.preference(
                    key: PinnedTodoHitRectsPreferenceKey.self,
                    value: [geo.frame(in: .named("PinnedTodoOverlaySpace"))]
                )
            }
        )
    }
}


// MARK: - AppKit Transparent Overlay Container

/// Transparent AppKit container hovering above the split editor whose `hitTest(_:)` passes
/// all pointer events through to `EditorTextView` outside active capsule bounds.
@MainActor
final class PinnedTodoOverlayContainerView: NSView {
    
    private let hitTestStore = PinnedTodoHitTestStore()
    private let hostingView: NSHostingView<PinnedTodoOverlayView>
    
    override var isFlipped: Bool { true }
    
    
    override init(frame frameRect: NSRect) {
        
        let rootView = PinnedTodoOverlayView(hitTestStore: self.hitTestStore)
        self.hostingView = NSHostingView(rootView: rootView)
        
        super.init(frame: frameRect)
        
        self.wantsLayer = true
        self.layer?.backgroundColor = NSColor.clear.cgColor
        
        self.hostingView.translatesAutoresizingMaskIntoConstraints = false
        self.hostingView.wantsLayer = true
        self.hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        self.addSubview(self.hostingView)
        
        NSLayoutConstraint.activate([
            self.hostingView.leadingAnchor.constraint(equalTo: self.leadingAnchor),
            self.hostingView.trailingAnchor.constraint(equalTo: self.trailingAnchor),
            self.hostingView.topAnchor.constraint(equalTo: self.topAnchor),
            self.hostingView.bottomAnchor.constraint(equalTo: self.bottomAnchor),
        ])
    }
    
    
    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    
    override func hitTest(_ point: NSPoint) -> NSView? {
        
        guard !AnalyticsManager.shared.pinnedTodos.isEmpty else { return nil }
        let localPoint = self.convert(point, from: self.superview)
        guard self.bounds.contains(localPoint) else { return nil }
        let isInsideTodo = self.hitTestStore.interactiveRects.contains { rect in
            rect.insetBy(dx: -4, dy: -4).contains(localPoint)
        }
        guard isInsideTodo else { return nil }
        return super.hitTest(point)
    }
}


// MARK: - Plump Layered Dynamic-Island Capsule Overlay Rendering

struct PinnedTodoOverlayView: View {
    
    let hitTestStore: PinnedTodoHitTestStore
    
    @AppStorage("cot.pinnedTodo.dockBottomRight") private var dockBottomRight = false
    @AppStorage("cot.pinnedTodo.mascotKind") private var mascotKindRaw = TodoMascotKind.autoMix.rawValue
    @State private var analytics = AnalyticsManager.shared
    @State private var studioPalette = StudioPaletteManager.shared
    @State private var hoveredID: String?
    @State private var isCollapsed = false
    @State private var completingIDs: Set<String> = []
    @State private var checkHoveredID: String?
    @Environment(\.colorScheme) private var colorScheme
    
    private var selectedMascot: TodoMascotKind {
        TodoMascotKind(rawValue: self.mascotKindRaw) ?? .autoMix
    }
    
    
    var body: some View {
        let todos = self.analytics.pinnedTodos
        let anchorAlignment: Alignment = self.dockBottomRight ? .bottomTrailing : .topTrailing
        
        GeometryReader { geo in
            ZStack(alignment: anchorAlignment) {
                if todos.isEmpty {
                    Color.clear
                } else if todos.contains(where: \.hasDeadline) {
                    TimelineView(.periodic(from: .now, by: 1.0)) { context in
                        self.overlayContent(todos: todos, now: context.date, containerSize: geo.size)
                    }
                } else {
                    self.overlayContent(todos: todos, now: Date(), containerSize: geo.size)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: anchorAlignment)
        }
        .coordinateSpace(name: "PinnedTodoOverlaySpace")
        .onPreferenceChange(PinnedTodoHitRectsPreferenceKey.self) { rects in
            self.hitTestStore.interactiveRects = rects
        }
        .onChange(of: todos.isEmpty) { _, isEmpty in
            if isEmpty {
                self.hitTestStore.interactiveRects = []
                self.isCollapsed = false
                self.completingIDs.removeAll()
            }
        }
        .onAppear {
            self.mascotKindRaw = TodoMascotKind.persisted.rawValue
        }
    }
    
    
    @ViewBuilder
    private func overlayContent(todos: [UserReminder], now: Date, containerSize: CGSize) -> some View {
        let evaluated = todos.map { item -> (UserReminder, PinnedTodoUrgencyMetrics) in
            let metrics = PinnedTodoUrgency.metrics(
                createdAt: item.createdAt,
                deadline: item.hasDeadline ? item.dueDate : nil,
                now: now,
                containerSize: containerSize
            )
            return (item, metrics)
        }
        
        if self.isCollapsed {
            self.collapsedPeekCapsule(evaluated: evaluated, now: now)
                .padding(.vertical, 12)
                .padding(.trailing, 16)
        } else {
            VStack(alignment: .trailing, spacing: 8) {
                ForEach(Array(evaluated.prefix(4).enumerated()), id: \.element.0.id) { index, pair in
                    self.layeredCapsule(item: pair.0, metrics: pair.1, now: now, index: index)
                }
            }
            .padding(.vertical, 12)
            .padding(.trailing, 16)
        }
    }
    
    
    @ViewBuilder
    private func collapsedPeekCapsule(
        evaluated: [(UserReminder, PinnedTodoUrgencyMetrics)],
        now: Date
    ) -> some View {
        let nearest = evaluated.first
        let tokens = self.studioPalette.tokens(isDark: self.colorScheme == .dark)
        let accent = nearest.map { self.urgencyAccent(for: $0.1.urgencyLevel, tokens: tokens) } ?? tokens.accentText
        let mascot = nearest.map { self.selectedMascot.resolvedKind(for: $0.0.id) } ?? .deepseekFish
        
        Button {
            withAnimation(.spring(response: 0.30, dampingFraction: 0.78)) {
                self.isCollapsed = false
            }
        } label: {
            HStack(spacing: 7) {
                PinnedTodoMascotAvatar(kind: mascot, isHovered: true, size: 20)
                
                Text("\(evaluated.count)")
                    .font(.system(size: 12, weight: .bold).monospacedDigit())
                    .foregroundStyle(tokens.primaryInk)
                
                if let (firstItem, _) = nearest, firstItem.hasDeadline {
                    Text(PinnedTodoUrgency.compactBadgeText(firstItem.dueDate.timeIntervalSince(now)))
                        .font(.system(size: 10.5, weight: .semibold).monospacedDigit())
                        .foregroundStyle(accent)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(accent.opacity(self.colorScheme == .dark ? 0.20 : 0.12), in: Capsule())
                }
            }
            .padding(.leading, 8)
            .padding(.trailing, 10)
            .frame(height: 30)
            .background {
                self.capsulePlinthBackground(accent: accent)
            }
        }
        .buttonStyle(.plain)
        .pointerStyle(.link)
        .help(AppLanguage.text("展开 \(evaluated.count) 项置顶待办", en: "Expand \(evaluated.count) Pinned Todos"))
        .contextMenu {
            self.mascotMenuSection()
            Divider()
            Button(AppLanguage.text("展开置顶待办", en: "Expand Pinned Todos")) {
                withAnimation(.spring(response: 0.30, dampingFraction: 0.78)) {
                    self.isCollapsed = false
                }
            }
            Button(self.dockBottomRight ? AppLanguage.text("移至右上角", en: "Move to Top Right") : AppLanguage.text("移至右下角", en: "Move to Bottom Right")) {
                withAnimation(.spring(response: 0.30, dampingFraction: 0.84)) {
                    self.dockBottomRight.toggle()
                }
            }
        }
        .modifier(ReportInteractiveRectModifier())
    }
    
    
    @ViewBuilder
    private func layeredCapsule(
        item: UserReminder,
        metrics: PinnedTodoUrgencyMetrics,
        now: Date,
        index: Int
    ) -> some View {
        let isHovered = (self.hoveredID == item.id)
        let isCheckHovered = (self.checkHoveredID == item.id)
        let isCompleting = self.completingIDs.contains(item.id)
        let tokens = self.studioPalette.tokens(isDark: self.colorScheme == .dark)
        let accent = isCompleting ? tokens.accentText : self.urgencyAccent(for: metrics.urgencyLevel, tokens: tokens)
        let mascot = self.selectedMascot.resolvedKind(for: item.id)
        
        HStack(alignment: .center, spacing: 8) {
            // 1. Live IP Companion Well (tap to cycle companion)
            Button {
                self.cycleMascotPreference()
            } label: {
                ZStack {
                    Circle()
                        .fill(Color.primary.opacity(self.colorScheme == .dark ? 0.08 : 0.045))
                        .frame(width: 26, height: 26)
                    
                    PinnedTodoMascotAvatar(
                        kind: mascot,
                        isHovered: isHovered,
                        isUrgent: metrics.urgencyLevel >= 3,
                        isCompleting: isCompleting,
                        size: 20,
                        phaseSeed: Double(index) * 1.17
                    )
                }
            }
            .buttonStyle(.plain)
            .pointerStyle(.link)
            .help(AppLanguage.text("点击切换小伙伴：\(mascot.displayName)", en: "Click to switch companion: \(mascot.displayName)"))
            
            // 2. Concise 1-line title
            Text(item.title)
                .font(.system(size: metrics.fontSize, weight: .medium))
                .foregroundStyle(isCompleting ? .secondary : .primary)
                .strikethrough(isCompleting)
                .lineLimit(1)
                .truncationMode(.tail)
            
            // 3. Soft nested countdown pill (zero hard border)
            if item.hasDeadline {
                let remaining = item.dueDate.timeIntervalSince(now)
                Text(PinnedTodoUrgency.compactBadgeText(remaining))
                    .font(.system(size: 10.5, weight: .semibold).monospacedDigit())
                    .foregroundStyle(accent)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(accent.opacity(self.colorScheme == .dark ? 0.18 : 0.11), in: Capsule())
                    .fixedSize()
            }
            
            // 4. Progressive hover micro-actions
            if isHovered && !isCompleting {
                HStack(spacing: 4) {
                    Menu {
                        Button("+15 分钟") {
                            self.analytics.snoozeReminder(id: item.id, by: 15 * 60)
                        }
                        Button("+1 小时") {
                            self.analytics.snoozeReminder(id: item.id, by: 3600)
                        }
                        Button(AppLanguage.text("推迟到今晚 22:00", en: "Tonight 22:00")) {
                            self.snoozeUntilTonight(item)
                        }
                    } label: {
                        Image(systemName: "clock")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 22, height: 22)
                            .background(Color.primary.opacity(0.06), in: Circle())
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .help(AppLanguage.text("延后提醒", en: "Snooze"))
                    
                    Button {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.80)) {
                            self.isCollapsed = true
                        }
                    } label: {
                        Image(systemName: "minus")
                            .font(.system(size: 9.5, weight: .bold))
                            .foregroundStyle(.secondary)
                            .frame(width: 22, height: 22)
                            .background(Color.primary.opacity(0.06), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .pointerStyle(.link)
                    .help(AppLanguage.text("收起迷你胶囊", en: "Collapse"))
                    
                    Button {
                        self.analytics.unpinReminder(id: item.id)
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.secondary)
                            .frame(width: 22, height: 22)
                            .background(Color.primary.opacity(0.06), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .pointerStyle(.link)
                    .help(AppLanguage.text("取消置顶", en: "Unpin"))
                }
                .transition(.opacity.combined(with: .scale(scale: 0.88)))
            }
            
            // 5. Borderless tactile complete pill button
            Button {
                self.completeWithFeedback(item)
            } label: {
                ZStack {
                    Circle()
                        .fill(
                            isCompleting
                                ? Color(red: 0.20, green: 0.72, blue: 0.45)
                                : accent.opacity(isCheckHovered ? 0.24 : 0.12)
                        )
                        .frame(width: 22, height: 22)
                    
                    Image(systemName: isCompleting || isCheckHovered ? "checkmark" : "circle.fill")
                        .font(.system(size: isCompleting || isCheckHovered ? 10.5 : 5, weight: .bold))
                        .foregroundStyle(isCompleting ? .white : accent)
                }
                .scaleEffect(isCompleting ? 1.15 : (isCheckHovered ? 1.06 : 1.0))
            }
            .buttonStyle(.plain)
            .pointerStyle(.link)
            .onHover { hovering in
                withAnimation(.spring(response: 0.20, dampingFraction: 0.75)) {
                    self.checkHoveredID = hovering ? item.id : (self.checkHoveredID == item.id ? nil : self.checkHoveredID)
                }
            }
            .help(AppLanguage.text("打卡完成", en: "Complete"))
        }
        .padding(.leading, 6)
        .padding(.trailing, 7)
        .frame(height: 36)
        .frame(maxWidth: isHovered ? 380 : 284)
        .background {
            self.capsulePlinthBackground(accent: accent)
        }
        .scaleEffect(isCompleting ? 0.94 : (isHovered ? 1.018 : 1.0))
        .opacity(isCompleting ? 0.62 : 1.0)
        .help(metrics.remainingText.map { "\(item.title) · \($0)" } ?? item.title)
        .onHover { inside in
            withAnimation(.spring(response: 0.26, dampingFraction: 0.80)) {
                self.hoveredID = inside ? item.id : (self.hoveredID == item.id ? nil : self.hoveredID)
            }
        }
        .contextMenu {
            Button(AppLanguage.text("打卡完成", en: "Complete")) {
                self.completeWithFeedback(item)
            }
            self.mascotMenuSection()
            Divider()
            Button("+15 分钟") {
                self.analytics.snoozeReminder(id: item.id, by: 15 * 60)
            }
            Button("+1 小时") {
                self.analytics.snoozeReminder(id: item.id, by: 3600)
            }
            Divider()
            Button(self.dockBottomRight ? AppLanguage.text("移至右上角", en: "Move to Top Right") : AppLanguage.text("移至右下角", en: "Move to Bottom Right")) {
                withAnimation(.spring(response: 0.30, dampingFraction: 0.84)) {
                    self.dockBottomRight.toggle()
                }
            }
            Button(AppLanguage.text("收起迷你胶囊", en: "Collapse Capsule")) {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                    self.isCollapsed = true
                }
            }
            Button(AppLanguage.text("复制内容", en: "Copy Title")) {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(item.title, forType: .string)
            }
            Divider()
            Button(AppLanguage.text("取消置顶", en: "Unpin")) {
                self.analytics.unpinReminder(id: item.id)
            }
        }
        .modifier(ReportInteractiveRectModifier())
    }
    
    
    /// Borderless multi-layer glassmorphic pill surface with top-only inner sheen and airy elevation shadows.
    @ViewBuilder
    private func capsulePlinthBackground(accent: Color) -> some View {
        let isDark = (self.colorScheme == .dark)
        let fillBase = isDark
            ? Color(red: 0.09, green: 0.10, blue: 0.14).opacity(0.84)
            : Color.white.opacity(0.90)
        
        Capsule()
            .fill(.ultraThinMaterial)
            .overlay(
                Capsule()
                    .fill(fillBase)
            )
            .overlay(
                Capsule()
                    .fill(accent.opacity(isDark ? 0.07 : 0.035))
            )
            .overlay(
                // Soft inner crystalline highlight along top arc ONLY (zero hard outline!)
                Capsule()
                    .strokeBorder(
                        LinearGradient(
                            colors: isDark
                                ? [Color.white.opacity(0.18), Color.white.opacity(0.03), Color.clear]
                                : [Color.white.opacity(0.95), Color.black.opacity(0.04), Color.black.opacity(0.06)],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 0.65
                    )
            )
            .shadow(color: Color.black.opacity(isDark ? 0.42 : 0.10), radius: 14, x: 0, y: 6)
            .shadow(color: Color.black.opacity(isDark ? 0.22 : 0.05), radius: 3, x: 0, y: 1)
    }
    
    
    @ViewBuilder
    private func mascotMenuSection() -> some View {
        Menu(AppLanguage.text("伴侣形象", en: "Companion IP")) {
            ForEach(TodoMascotKind.allCases) { kind in
                Button {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) {
                        self.mascotKindRaw = kind.rawValue
                        kind.saveAsDefault()
                    }
                } label: {
                    HStack {
                        Text(kind.displayName)
                        if self.selectedMascot == kind {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        }
    }
    
    
    // MARK: Helpers
    
    private func urgencyAccent(for level: Int, tokens: StudioColorTokens) -> Color {
        switch level {
            case 4: Color(red: 0.88, green: 0.26, blue: 0.25)
            case 3: Color(red: 0.90, green: 0.42, blue: 0.18)
            case 2: Color(red: 0.90, green: 0.58, blue: 0.16)
            case 1: tokens.accentText
            default: tokens.accentText
        }
    }
    
    
    private func cycleMascotPreference() {
        let order = TodoMascotKind.allCases
        let currentIdx = order.firstIndex(of: self.selectedMascot) ?? 0
        let next = order[(currentIdx + 1) % order.count]
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        withAnimation(.spring(response: 0.28, dampingFraction: 0.75)) {
            self.mascotKindRaw = next.rawValue
            next.saveAsDefault()
        }
    }
    
    
    private func completeWithFeedback(_ item: UserReminder) {
        guard !self.completingIDs.contains(item.id) else { return }
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        withAnimation(.spring(response: 0.24, dampingFraction: 0.68)) {
            _ = self.completingIDs.insert(item.id)
        }
        let targetID = item.id
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.24) {
            withAnimation(.easeOut(duration: 0.18)) {
                self.analytics.toggleReminderCompleted(id: targetID)
                self.completingIDs.remove(targetID)
            }
        }
    }
    
    
    private func snoozeUntilTonight(_ item: UserReminder) {
        let now = Date()
        let tonight = Calendar.current.date(bySettingHour: 22, minute: 0, second: 0, of: now)
        let target = (tonight.flatMap { $0.timeIntervalSince(now) > 900 ? $0 : nil }) ?? now.addingTimeInterval(3 * 3600)
        self.analytics.snoozeReminder(id: item.id, by: target.timeIntervalSince(now))
    }
}
