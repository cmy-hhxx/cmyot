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


/// Expressive multi-state behavior for the moe AI vendor companions.
nonisolated enum MascotMoodState: String, CaseIterable, Sendable, Equatable {
    
    case idle
    case working
    case slacking
    case urgent
    case celebrating
}


/// Playful anthropomorphized ("娘化") mainstream AI vendor companions + Usagi rendered inside todo capsules.
nonisolated enum TodoMascotKind: String, CaseIterable, Identifiable, Codable, Sendable {
    
    case autoMix
    case deepseekFish
    case claudeChibi
    case openAIMaid
    case geminiTwin
    case qwenGirl
    case kimiGirl
    case grokGirl
    case usagiPixel
    
    var id: String { self.rawValue }
    
    
    var displayName: String {
        switch self {
            case .autoMix: AppLanguage.text("AI 娘轮换", en: "Auto Mix")
            case .deepseekFish: AppLanguage.text("DeepSeek 大肥鱼女仆", en: "DeepSeek Whale Maid")
            case .claudeChibi: AppLanguage.text("Claude 暖橘文学娘", en: "Claude Literary Girl")
            case .openAIMaid: AppLanguage.text("ChatGPT 薄荷机娘", en: "ChatGPT Mint Girl")
            case .geminiTwin: AppLanguage.text("Gemini 星璇双子娘", en: "Gemini Star Girl")
            case .qwenGirl: AppLanguage.text("千问 紫棠古风娘", en: "Qwen Girl")
            case .kimiGirl: AppLanguage.text("Kimi 月华少女", en: "Kimi Moon Girl")
            case .grokGirl: AppLanguage.text("Grok 黑猫酷妹", en: "Grok Cat Girl")
            case .usagiPixel: AppLanguage.text("像素乌萨奇", en: "Pixel Usagi")
        }
    }
    
    
    /// Concrete moe vendor roster eligible for `.autoMix` assignment.
    static let concreteMoeRoster: [TodoMascotKind] = [
        .deepseekFish, .claudeChibi, .openAIMaid, .geminiTwin, .qwenGirl, .kimiGirl, .grokGirl,
    ]
    
    
    /// Resolves `.autoMix` deterministically per item ID so consecutive pills feature distinct AI girls.
    func resolvedKind(for seedID: String) -> TodoMascotKind {
        guard self == .autoMix else { return self }
        let concrete = Self.concreteMoeRoster
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


/// Featherweight urgency model that gently shifts capsule accent without obstructing the editor canvas.
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
            fontSize = 13.0 + CGFloat(overdueRatio) * 0.4
            urgencyLevel = 4
        } else if remaining <= 45 || effectiveProgress >= 0.96 {
            let countdownRatio = min(1.0, max(0.0, 1.0 - remaining / 45.0))
            fontSize = 12.8 + CGFloat(countdownRatio) * 0.3
            urgencyLevel = 4
        } else if effectiveProgress >= 0.72 {
            let localT = (effectiveProgress - 0.72) / 0.24
            fontSize = 12.6 + CGFloat(localT) * 0.3
            urgencyLevel = 3
        } else if effectiveProgress >= 0.45 {
            let localT = (effectiveProgress - 0.45) / 0.27
            fontSize = 12.4 + CGFloat(localT) * 0.2
            urgencyLevel = 2
        } else {
            let localT = effectiveProgress / 0.45
            fontSize = 12.2 + CGFloat(localT) * 0.2
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


// MARK: - Animated Moe AI Girl Companions (DeepSeek 大肥鱼女仆 & Mainstream AI Vendors)

/// Multi-state expressive moe AI companion rendered inside compact todo capsules.
struct PinnedTodoMascotAvatar: View {
    
    let kind: TodoMascotKind
    var isHovered: Bool = false
    var isUrgent: Bool = false
    var isCompleting: Bool = false
    var size: CGFloat = 24
    var phaseSeed: Double = 0
    
    @Environment(\.colorScheme) private var colorScheme
    @State private var analytics = AnalyticsManager.shared
    
    
    private struct MoeStyle {
        let hairTop: Color
        let hairBottom: Color
        let ornament: Color
        let collar: Color
        let cheek: Color
    }
    
    
    static func moodState(
        now: Date,
        phaseSeed: Double,
        isHovered: Bool,
        isUrgent: Bool,
        isCompleting: Bool,
        lastKeystrokeAt: Date
    ) -> MascotMoodState {
        if isCompleting || isHovered { return .celebrating }
        if isUrgent { return .urgent }
        if now.timeIntervalSince(lastKeystrokeAt) <= 2.4 { return .working }
        let slot = (now.timeIntervalSinceReferenceDate + phaseSeed).truncatingRemainder(dividingBy: 14.0)
        if slot >= 10.5 { return .slacking }
        return .idle
    }
    
    
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24.0, paused: AnimationConstants.isReducedMotionEnabled)) { context in
            let now = context.date
            let t = now.timeIntervalSinceReferenceDate + self.phaseSeed
            let mood = Self.moodState(
                now: now,
                phaseSeed: self.phaseSeed,
                isHovered: self.isHovered,
                isUrgent: self.isUrgent,
                isCompleting: self.isCompleting,
                lastKeystrokeAt: self.analytics.lastKeystrokeAt
            )
            
            let bob: Double = switch mood {
                case .celebrating: -3.2 + sin(t * 7.5) * 1.4
                case .urgent: sin(t * 9.0) * 1.6
                case .working: abs(sin(t * 6.5)) * -1.8
                case .slacking: sin(t * 1.4) * 0.9 + 0.6
                case .idle: sin(t * 2.4) * 1.0
            }
            let tilt: Double = switch mood {
                case .celebrating: sin(t * 5.2) * 7.0
                case .urgent: sin(t * 13.0) * 4.5
                case .working: sin(t * 6.0) * 3.0
                case .slacking: -5.0 + sin(t * 1.2) * 2.0
                case .idle: sin(t * 1.4) * 1.8
            }
            
            Canvas { ctx, canvasSize in
                if self.kind == .usagiPixel {
                    Self.drawPixelUsagi(in: ctx, size: canvasSize, t: t, happy: mood == .celebrating, isDark: self.colorScheme == .dark)
                } else {
                    Self.drawMoeAICompanion(
                        in: ctx,
                        size: canvasSize,
                        kind: self.kind,
                        mood: mood,
                        t: t,
                        isDark: self.colorScheme == .dark
                    )
                }
            }
            .frame(width: self.size, height: self.size)
            .offset(y: bob)
            .rotationEffect(.degrees(tilt))
            .scaleEffect(self.isCompleting ? 1.22 : (self.isHovered ? 1.09 : 1.0))
            .animation(.spring(response: 0.26, dampingFraction: 0.68), value: self.isCompleting)
            .animation(.spring(response: 0.24, dampingFraction: 0.72), value: self.isHovered)
        }
    }
    
    
    private static func style(for kind: TodoMascotKind) -> MoeStyle {
        switch kind {
            case .deepseekFish, .autoMix:
                MoeStyle(
                    hairTop: Color(red: 0.22, green: 0.45, blue: 0.98),
                    hairBottom: Color(red: 0.50, green: 0.76, blue: 1.00),
                    ornament: .white,
                    collar: Color(red: 0.14, green: 0.23, blue: 0.56),
                    cheek: Color(red: 1.00, green: 0.62, blue: 0.74)
                )
            case .claudeChibi:
                MoeStyle(
                    hairTop: Color(red: 0.85, green: 0.46, blue: 0.32),
                    hairBottom: Color(red: 0.95, green: 0.64, blue: 0.48),
                    ornament: Color(red: 1.00, green: 0.84, blue: 0.52),
                    collar: Color(red: 0.36, green: 0.22, blue: 0.18),
                    cheek: Color(red: 1.00, green: 0.65, blue: 0.62)
                )
            case .openAIMaid:
                MoeStyle(
                    hairTop: Color(red: 0.10, green: 0.66, blue: 0.51),
                    hairBottom: Color(red: 0.42, green: 0.88, blue: 0.74),
                    ornament: .white,
                    collar: Color(red: 0.08, green: 0.30, blue: 0.25),
                    cheek: Color(red: 1.00, green: 0.68, blue: 0.75)
                )
            case .geminiTwin:
                MoeStyle(
                    hairTop: Color(red: 0.36, green: 0.48, blue: 0.98),
                    hairBottom: Color(red: 0.66, green: 0.54, blue: 0.98),
                    ornament: Color(red: 0.86, green: 0.94, blue: 1.00),
                    collar: Color(red: 0.24, green: 0.28, blue: 0.64),
                    cheek: Color(red: 1.00, green: 0.66, blue: 0.78)
                )
            case .qwenGirl:
                MoeStyle(
                    hairTop: Color(red: 0.44, green: 0.30, blue: 0.92),
                    hairBottom: Color(red: 0.70, green: 0.56, blue: 0.98),
                    ornament: Color(red: 0.98, green: 0.82, blue: 0.44),
                    collar: Color(red: 0.28, green: 0.18, blue: 0.58),
                    cheek: Color(red: 1.00, green: 0.64, blue: 0.76)
                )
            case .kimiGirl:
                MoeStyle(
                    hairTop: Color(red: 0.19, green: 0.48, blue: 0.88),
                    hairBottom: Color(red: 0.76, green: 0.88, blue: 0.99),
                    ornament: Color(red: 1.00, green: 0.88, blue: 0.48),
                    collar: Color(red: 0.14, green: 0.22, blue: 0.42),
                    cheek: Color(red: 1.00, green: 0.68, blue: 0.78)
                )
            case .grokGirl:
                MoeStyle(
                    hairTop: Color(red: 0.16, green: 0.17, blue: 0.22),
                    hairBottom: Color(red: 0.34, green: 0.36, blue: 0.44),
                    ornament: Color(red: 0.92, green: 0.94, blue: 0.98),
                    collar: Color(red: 0.10, green: 0.10, blue: 0.13),
                    cheek: Color(red: 0.98, green: 0.56, blue: 0.66)
                )
            case .usagiPixel:
                MoeStyle(
                    hairTop: Color(red: 1.00, green: 0.93, blue: 0.68),
                    hairBottom: Color(red: 1.00, green: 0.86, blue: 0.52),
                    ornament: Color(red: 1.00, green: 0.64, blue: 0.74),
                    collar: Color(red: 0.35, green: 0.25, blue: 0.20),
                    cheek: Color(red: 1.00, green: 0.64, blue: 0.74)
                )
        }
    }
    
    
    private static func drawMoeAICompanion(
        in ctx: GraphicsContext,
        size: CGSize,
        kind: TodoMascotKind,
        mood: MascotMoodState,
        t: Double,
        isDark: Bool
    ) {
        let style = Self.style(for: kind)
        let w = size.width
        let h = size.height
        let cx = w * 0.50
        let headY = h * 0.46
        let r = min(w, h) * 0.34
        let hairGrad = Gradient(colors: [style.hairTop, style.hairBottom])
        
        // 1. Character-specific back silhouette (whale tail for 大肥鱼女仆, twin-buns for ChatGPT/Qwen, cat ears for Grok)
        switch kind {
            case .deepseekFish, .autoMix:
                // Wagging chubby whale tail behind left shoulder + bilateral ear-fins
                let wag = sin(t * (mood == .urgent ? 12.0 : 4.2)) * 2.2
                var tail = Path()
                tail.move(to: CGPoint(x: cx - r * 0.55, y: headY + r * 0.45))
                tail.addQuadCurve(
                    to: CGPoint(x: cx - r * 1.18, y: headY + r * 0.15 + wag),
                    control: CGPoint(x: cx - r * 0.98, y: headY + r * 0.65)
                )
                tail.addLine(to: CGPoint(x: cx - r * 1.02, y: headY + r * 0.52 + wag))
                tail.addQuadCurve(
                    to: CGPoint(x: cx - r * 0.45, y: headY + r * 0.75),
                    control: CGPoint(x: cx - r * 0.85, y: headY + r * 0.82)
                )
                tail.closeSubpath()
                ctx.fill(tail, with: .color(style.hairTop))
                
                // Whale ear-fins
                for side in [-1.0, 1.0] {
                    var fin = Path()
                    let baseX = cx + side * r * 0.86
                    fin.move(to: CGPoint(x: baseX, y: headY - r * 0.12))
                    fin.addQuadCurve(
                        to: CGPoint(x: baseX + side * r * 0.36, y: headY + r * 0.12),
                        control: CGPoint(x: baseX + side * r * 0.34, y: headY - r * 0.24)
                    )
                    fin.addQuadCurve(
                        to: CGPoint(x: baseX, y: headY + r * 0.22),
                        control: CGPoint(x: baseX + side * r * 0.18, y: headY + r * 0.24)
                    )
                    fin.closeSubpath()
                    ctx.fill(fin, with: .color(style.hairBottom))
                }
            case .openAIMaid, .qwenGirl:
                // Twin odango buns
                for side in [-1.0, 1.0] {
                    let bx = cx + side * r * 0.78
                    let by = headY - r * 0.68
                    let bunR = r * 0.32
                    ctx.fill(Path(ellipseIn: CGRect(x: bx - bunR, y: by - bunR, width: bunR * 2, height: bunR * 2)), with: .color(style.hairTop))
                    ctx.fill(Path(ellipseIn: CGRect(x: bx - bunR * 0.42, y: by - bunR * 0.42, width: bunR * 0.84, height: bunR * 0.84)), with: .color(style.ornament))
                }
            case .grokGirl:
                // Sharp cat-ear headset
                for side in [-1.0, 1.0] {
                    var ear = Path()
                    ear.move(to: CGPoint(x: cx + side * r * 0.28, y: headY - r * 0.75))
                    ear.addLine(to: CGPoint(x: cx + side * r * 0.78, y: headY - r * 1.18))
                    ear.addLine(to: CGPoint(x: cx + side * r * 0.90, y: headY - r * 0.42))
                    ear.closeSubpath()
                    ctx.fill(ear, with: .color(style.hairTop))
                }
            default:
                break
        }
        
        // 2. Back hair volume
        let backHair = CGRect(x: cx - r * 1.04, y: headY - r * 0.92, width: r * 2.08, height: r * 1.92)
        ctx.fill(
            Path(roundedRect: backHair, cornerRadius: r * 0.88),
            with: .linearGradient(hairGrad, startPoint: CGPoint(x: cx, y: backHair.minY), endPoint: CGPoint(x: cx, y: backHair.maxY))
        )
        
        // 3. Cute Maid / Signature Collar Outfit at bottom
        let bodyRect = CGRect(x: cx - r * 0.64, y: headY + r * 0.56, width: r * 1.28, height: r * 0.66)
        ctx.fill(Path(roundedRect: bodyRect, cornerRadius: r * 0.30), with: .color(style.collar))
        // White collar bib / lace
        var apron = Path()
        apron.move(to: CGPoint(x: cx - r * 0.38, y: headY + r * 0.58))
        apron.addLine(to: CGPoint(x: cx, y: headY + r * 0.95))
        apron.addLine(to: CGPoint(x: cx + r * 0.38, y: headY + r * 0.58))
        apron.closeSubpath()
        ctx.fill(apron, with: .color(.white.opacity(0.95)))
        // Tiny bow knot
        ctx.fill(
            Path(ellipseIn: CGRect(x: cx - r * 0.12, y: headY + r * 0.74, width: r * 0.24, height: r * 0.16)),
            with: .color(style.hairTop)
        )
        
        // 4. Plump Chibi Face (porcelain warm peach)
        let chubbyFactor: CGFloat = (kind == .deepseekFish || kind == .autoMix) ? 0.86 : 0.78
        let faceRect = CGRect(x: cx - r * chubbyFactor, y: headY - r * 0.62, width: r * chubbyFactor * 2, height: r * 1.32)
        ctx.fill(
            Path(ellipseIn: faceRect),
            with: .color(Color(red: 1.00, green: 0.93, blue: 0.88))
        )
        
        // 5. Bangs + Bouncy Ahoge (呆毛)
        var bangs = Path()
        bangs.move(to: CGPoint(x: cx - r * 0.90, y: headY - r * 0.22))
        bangs.addQuadCurve(to: CGPoint(x: cx - r * 0.24, y: headY - r * 0.68), control: CGPoint(x: cx - r * 0.64, y: headY - r * 0.84))
        bangs.addLine(to: CGPoint(x: cx - r * 0.08, y: headY - r * 0.24))
        bangs.addLine(to: CGPoint(x: cx + r * 0.08, y: headY - r * 0.58))
        bangs.addLine(to: CGPoint(x: cx + r * 0.24, y: headY - r * 0.26))
        bangs.addQuadCurve(to: CGPoint(x: cx + r * 0.90, y: headY - r * 0.22), control: CGPoint(x: cx + r * 0.64, y: headY - r * 0.84))
        bangs.addArc(center: CGPoint(x: cx, y: headY - r * 0.20), radius: r * 0.92, startAngle: .zero, endAngle: .degrees(180), clockwise: true)
        bangs.closeSubpath()
        ctx.fill(bangs, with: .color(style.hairTop))
        
        // Ahoge curl at crown
        let ahogeSway = sin(t * 3.8) * 1.4
        var ahoge = Path()
        ahoge.move(to: CGPoint(x: cx, y: headY - r * 0.90))
        ahoge.addQuadCurve(
            to: CGPoint(x: cx + r * 0.22 + ahogeSway, y: headY - r * 1.26),
            control: CGPoint(x: cx - r * 0.14, y: headY - r * 1.22)
        )
        ctx.stroke(ahoge, with: .color(style.hairTop), style: StrokeStyle(lineWidth: max(1.4, w * 0.075), lineCap: .round))
        
        // 6. Signature Headwear / Hairpins
        switch kind {
            case .deepseekFish, .autoMix:
                // White frilly maid headband
                var brim = Path()
                brim.move(to: CGPoint(x: cx - r * 0.70, y: headY - r * 0.72))
                brim.addQuadCurve(to: CGPoint(x: cx + r * 0.70, y: headY - r * 0.72), control: CGPoint(x: cx, y: headY - r * 1.04))
                ctx.stroke(brim, with: .color(.white), style: StrokeStyle(lineWidth: max(2.2, w * 0.11), lineCap: .round))
            case .geminiTwin:
                // Glowing 4-point star hairpin
                let sx = cx + r * 0.45
                let sy = headY - r * 0.62
                let sr = r * 0.22
                var star = Path()
                star.move(to: CGPoint(x: sx, y: sy - sr))
                star.addLine(to: CGPoint(x: sx + sr * 0.35, y: sy - sr * 0.35))
                star.addLine(to: CGPoint(x: sx + sr, y: sy))
                star.addLine(to: CGPoint(x: sx + sr * 0.35, y: sy + sr * 0.35))
                star.addLine(to: CGPoint(x: sx, y: sy + sr))
                star.addLine(to: CGPoint(x: sx - sr * 0.35, y: sy + sr * 0.35))
                star.addLine(to: CGPoint(x: sx - sr, y: sy))
                star.addLine(to: CGPoint(x: sx - sr * 0.35, y: sy - sr * 0.35))
                star.closeSubpath()
                ctx.fill(star, with: .color(style.ornament))
            case .kimiGirl:
                // Glowing crescent-moon clip
                let mx = cx - r * 0.44
                let my = headY - r * 0.62
                ctx.fill(Path(ellipseIn: CGRect(x: mx - r * 0.18, y: my - r * 0.18, width: r * 0.36, height: r * 0.36)), with: .color(style.ornament))
            default:
                // Warm accent hair clip
                ctx.fill(Path(roundedRect: CGRect(x: cx + r * 0.28, y: headY - r * 0.66, width: r * 0.34, height: r * 0.14), cornerRadius: 2), with: .color(style.ornament))
        }
        
        // 7. Rosy Kawaii Cheeks
        let cheekAlpha = (mood == .celebrating || mood == .urgent) ? 0.92 : 0.72
        let cheekSize = (mood == .urgent) ? CGSize(width: r * 0.34, height: r * 0.20) : CGSize(width: r * 0.28, height: r * 0.16)
        ctx.fill(Path(ellipseIn: CGRect(x: cx - r * 0.56, y: headY + r * 0.16, width: cheekSize.width, height: cheekSize.height)), with: .color(style.cheek.opacity(cheekAlpha)))
        ctx.fill(Path(ellipseIn: CGRect(x: cx + r * 0.56 - cheekSize.width, y: headY + r * 0.16, width: cheekSize.width, height: cheekSize.height)), with: .color(style.cheek.opacity(cheekAlpha)))
        
        // 8. Expressive Multi-State Eyes & Mouth
        let ink = Color(red: 0.16, green: 0.12, blue: 0.18)
        let blinkCycle = t.truncatingRemainder(dividingBy: 3.6)
        let isBlinking = (blinkCycle > 3.44)
        
        switch mood {
            case .celebrating:
                // ^ ^ Happy crescent eyes
                for side in [-1.0, 1.0] {
                    var arc = Path()
                    let ex = cx + side * r * 0.30
                    let ey = headY + r * 0.02
                    arc.move(to: CGPoint(x: ex - r * 0.13, y: ey + r * 0.04))
                    arc.addQuadCurve(to: CGPoint(x: ex + r * 0.13, y: ey + r * 0.04), control: CGPoint(x: ex, y: ey - r * 0.18))
                    ctx.stroke(arc, with: .color(ink), style: StrokeStyle(lineWidth: max(1.2, w * 0.065), lineCap: .round))
                }
            case .urgent:
                // > < Panicked flustered eyes
                var leftE = Path()
                leftE.move(to: CGPoint(x: cx - r * 0.42, y: headY - r * 0.08))
                leftE.addLine(to: CGPoint(x: cx - r * 0.20, y: headY + r * 0.04))
                leftE.addLine(to: CGPoint(x: cx - r * 0.42, y: headY + r * 0.14))
                var rightE = Path()
                rightE.move(to: CGPoint(x: cx + r * 0.42, y: headY - r * 0.08))
                rightE.addLine(to: CGPoint(x: cx + r * 0.20, y: headY + r * 0.04))
                rightE.addLine(to: CGPoint(x: cx + r * 0.42, y: headY + r * 0.14))
                ctx.stroke(leftE, with: .color(ink), style: StrokeStyle(lineWidth: max(1.2, w * 0.06), lineCap: .round, lineJoin: .round))
                ctx.stroke(rightE, with: .color(ink), style: StrokeStyle(lineWidth: max(1.2, w * 0.06), lineCap: .round, lineJoin: .round))
                // Sweat droplet
                let dropY = headY - r * 0.26 + CGFloat((t * 8.0).truncatingRemainder(dividingBy: 3.0))
                ctx.fill(Path(ellipseIn: CGRect(x: cx + r * 0.68, y: dropY, width: r * 0.16, height: r * 0.24)), with: .color(Color(red: 0.46, green: 0.84, blue: 1.0)))
            default:
                if isBlinking || mood == .slacking {
                    for side in [-1.0, 1.0] {
                        let ex = cx + side * r * 0.30
                        let ey = headY + r * 0.03
                        var line = Path()
                        line.move(to: CGPoint(x: ex - r * 0.12, y: ey))
                        line.addLine(to: CGPoint(x: ex + r * 0.12, y: ey))
                        ctx.stroke(line, with: .color(ink), style: StrokeStyle(lineWidth: max(1.2, w * 0.06), lineCap: .round))
                    }
                } else {
                    for side in [-1.0, 1.0] {
                        let ex = cx + side * r * 0.30
                        let ey = headY + r * 0.01
                        let er = max(1.3, r * 0.14)
                        ctx.fill(Path(ellipseIn: CGRect(x: ex - er, y: ey - er * 1.15, width: er * 2, height: er * 2.3)), with: .color(ink))
                        // Highlight sparkle
                        let gl = er * 0.55
                        ctx.fill(Path(ellipseIn: CGRect(x: ex - er * 0.42, y: ey - er * 0.65, width: gl, height: gl)), with: .color(.white))
                    }
                }
        }
        
        // Tiny cat/w-mouth or smile
        var mouth = Path()
        mouth.move(to: CGPoint(x: cx - r * 0.11, y: headY + r * 0.28))
        mouth.addQuadCurve(to: CGPoint(x: cx + r * 0.11, y: headY + r * 0.28), control: CGPoint(x: cx, y: headY + r * (mood == .celebrating ? 0.44 : 0.38)))
        ctx.stroke(mouth, with: .color(ink), style: StrokeStyle(lineWidth: max(1.0, w * 0.05), lineCap: .round))
        
        // 9. Mood-specific micro prop: Steaming white rice bowl / working sparkle
        if mood == .slacking {
            // Iconic DeepSeek 大肥鱼白米饭 bowl on corner!
            let bx = cx + r * 0.58
            let by = headY + r * 0.56
            ctx.fill(Path(ellipseIn: CGRect(x: bx - r * 0.28, y: by - r * 0.16, width: r * 0.56, height: r * 0.30)), with: .color(.white))
            var bowl = Path()
            bowl.addRoundedRect(in: CGRect(x: bx - r * 0.30, y: by - r * 0.02, width: r * 0.60, height: r * 0.32), cornerSize: CGSize(width: r * 0.18, height: r * 0.18))
            ctx.fill(bowl, with: .color(isDark ? Color(red: 0.84, green: 0.90, blue: 0.98) : style.hairTop))
        } else if mood == .working {
            // Rhythmic typing sparkle beside crown
            let sx = cx + r * 0.88
            let sy = headY - r * 0.72 + CGFloat(sin(t * 9.0) * 1.6)
            var spark = Path()
            let sr = r * 0.18
            spark.move(to: CGPoint(x: sx, y: sy - sr))
            spark.addLine(to: CGPoint(x: sx, y: sy + sr))
            spark.move(to: CGPoint(x: sx - sr, y: sy))
            spark.addLine(to: CGPoint(x: sx + sr, y: sy))
            ctx.stroke(spark, with: .color(Color(red: 1.0, green: 0.86, blue: 0.36)), style: StrokeStyle(lineWidth: 1.3, lineCap: .round))
        }
    }
    
    
    private static func drawPixelUsagi(in ctx: GraphicsContext, size: CGSize, t: Double, happy: Bool, isDark: Bool) {
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


// MARK: - Compact Content-Hugging Glass Capsules (Zero Wasted Space + Generous Button Hit Targets)

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
                .padding(.trailing, 14)
        } else {
            VStack(alignment: .trailing, spacing: 7) {
                ForEach(Array(evaluated.prefix(4).enumerated()), id: \.element.0.id) { index, pair in
                    self.layeredCapsule(item: pair.0, metrics: pair.1, now: now, index: index)
                }
            }
            .padding(.vertical, 12)
            .padding(.trailing, 14)
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
            HStack(spacing: 6) {
                PinnedTodoMascotAvatar(kind: mascot, isHovered: true, size: 22)
                
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
            .frame(height: 32)
            .background {
                self.capsulePlinthBackground(accent: accent)
            }
            .fixedSize()
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
        
        // Strictly content-hugging HStack: zero blank middle whitespace, generous 28×28 hit targets!
        HStack(alignment: .center, spacing: 5) {
            // 1. Live AI Girl Companion Well (30×30 tap target)
            Button {
                self.cycleMascotPreference()
            } label: {
                ZStack {
                    Circle()
                        .fill(accent.opacity(self.colorScheme == .dark ? 0.14 : 0.08))
                        .frame(width: 28, height: 28)
                    
                    PinnedTodoMascotAvatar(
                        kind: mascot,
                        isHovered: isHovered,
                        isUrgent: metrics.urgencyLevel >= 3,
                        isCompleting: isCompleting,
                        size: 22,
                        phaseSeed: Double(index) * 1.17
                    )
                }
                .frame(width: 30, height: 30)
                .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .pointerStyle(.link)
            .help(AppLanguage.text("点击切换伙伴：\(mascot.displayName)", en: "Switch Companion: \(mascot.displayName)"))
            
            // 2. Content-hugging title (capped width, zero blank gap)
            Text(item.title)
                .font(.system(size: metrics.fontSize, weight: .medium))
                .foregroundStyle(isCompleting ? .secondary : .primary)
                .lineLimit(1)
                .truncationMode(.tail)
                .strikethrough(isCompleting)
                .frame(maxWidth: 164, alignment: .leading)
                .fixedSize(horizontal: true, vertical: false)
                .padding(.trailing, item.hasDeadline ? 0 : 2)
            
            // 3. Soft countdown pill
            if item.hasDeadline {
                let remaining = item.dueDate.timeIntervalSince(now)
                Text(PinnedTodoUrgency.compactBadgeText(remaining))
                    .font(.system(size: 10.5, weight: .semibold).monospacedDigit())
                    .foregroundStyle(accent)
                    .padding(.horizontal, 6.5)
                    .padding(.vertical, 2.5)
                    .background(accent.opacity(self.colorScheme == .dark ? 0.18 : 0.11), in: Capsule())
                    .fixedSize()
            }
            
            // 4. Stable 28×28 quick actions menu (Snooze / Collapse / Unpin) — zero width jump on hover!
            if !isCompleting {
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
                    Divider()
                    Button(AppLanguage.text("收起迷你胶囊", en: "Collapse")) {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.80)) {
                            self.isCollapsed = true
                        }
                    }
                    Button(AppLanguage.text("取消置顶", en: "Unpin"), role: .destructive) {
                        self.analytics.unpinReminder(id: item.id)
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 24, height: 24)
                        .background(Color.primary.opacity(isHovered ? 0.08 : 0.04), in: Circle())
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help(AppLanguage.text("延后 / 取消置顶", en: "Snooze or Unpin"))
            }
            
            // 5. Large comfortable 28×28 Complete Hit Target
            Button {
                self.completeWithFeedback(item)
            } label: {
                ZStack {
                    Circle()
                        .fill(
                            isCompleting
                                ? Color(red: 0.20, green: 0.72, blue: 0.45)
                                : accent.opacity(isCheckHovered ? 0.28 : 0.15)
                        )
                        .frame(width: 24, height: 24)
                    
                    Image(systemName: isCompleting || isCheckHovered ? "checkmark" : "circle.fill")
                        .font(.system(size: isCompleting || isCheckHovered ? 11 : 5.5, weight: .bold))
                        .foregroundStyle(isCompleting ? .white : accent)
                }
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
                .scaleEffect(isCompleting ? 1.14 : (isCheckHovered ? 1.06 : 1.0))
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
        .padding(.leading, 5)
        .padding(.trailing, 5)
        .frame(height: 38)
        .fixedSize()
        .background {
            self.capsulePlinthBackground(accent: accent)
        }
        .scaleEffect(isCompleting ? 0.94 : (isHovered ? 1.015 : 1.0))
        .opacity(isCompleting ? 0.62 : 1.0)
        .help(metrics.remainingText.map { "\(item.title) · \($0)" } ?? item.title)
        .onHover { inside in
            withAnimation(.spring(response: 0.24, dampingFraction: 0.80)) {
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
            ? Color(red: 0.09, green: 0.10, blue: 0.14).opacity(0.86)
            : Color.white.opacity(0.92)
        
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
        Menu(AppLanguage.text("AI 娘伙伴", en: "AI Companion")) {
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
