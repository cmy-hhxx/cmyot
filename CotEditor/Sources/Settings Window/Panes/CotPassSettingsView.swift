//
//  CotPassSettingsView.swift
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

// MARK: - License & Serial Model (Preserved for Model Compatibility)

nonisolated enum CotPassTier: String, Codable, Sendable, Equatable {
    
    case explorer
    case pro
    case founder
    
    
    var badgeTitle: String {
        switch self {
            case .explorer: "EXPLORER"
            case .pro: "PRO"
            case .founder: "FOUNDER"
        }
    }
    
    
    var statusLabel: String {
        switch self {
            case .explorer: "ACTIVE"
            case .pro: "PRO"
            case .founder: "FOUNDER"
        }
    }
    
    
    var accessLabel: String {
        switch self {
            case .explorer: "LOCAL"
            case .pro: "PRO"
            case .founder: "LIFETIME"
        }
    }
    
    
    var summaryLabel: String {
        switch self {
            case .explorer: "基础通行"
            case .pro: "专业通行"
            case .founder: "创始通行"
        }
    }
}


nonisolated enum CotPassLicense {
    
    /// Validates a CotEditor license key (`COT-PRO-XXXX-XXXX` or `COT-FOUNDER-XXXX-XXXX`).
    static func validate(_ rawKey: String) -> CotPassTier? {
        
        let normalized = rawKey.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !normalized.isEmpty else { return nil }
        
        if normalized.range(of: #"^COT-FOUNDER-[A-Z0-9]{4}(-[A-Z0-9]{4})?$"#, options: .regularExpression) != nil {
            return .founder
        }
        if normalized.range(of: #"^COT-PRO-[A-Z0-9]{4}-[A-Z0-9]{4}$"#, options: .regularExpression) != nil {
            return .pro
        }
        return nil
    }
    
    
    /// Generates a deterministic-looking readable pass serial code (`XXXX-YYV1`).
    static func generateSerialCode() -> String {
        let alphabet = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
        let head = String((0..<4).map { _ in alphabet.randomElement()! })
        let tail = String((0..<2).map { _ in alphabet.randomElement()! })
        return "\(head)-\(tail)V1"
    }
}


// MARK: - Curated Pass Themes (All Titles ≤ 4 Chars)

nonisolated struct CotPassTheme: Identifiable, Sendable {
    
    let id: Int
    let title: String
    let subtitle: String
    let matrixColorHex: String
    let accentColorHex: String
    let backgroundTopHex: String
    let backgroundBottomHex: String
    let mascotName: String
    let bitmap: [String]
    
    
    static let allThemes: [CotPassTheme] = [
        CotPassTheme(
            id: 0,
            title: "松烟墨玉",
            subtitle: "PINE INK",
            matrixColorHex: "#44C997",
            accentColorHex: "#E8ECE9",
            backgroundTopHex: "#0B1512",
            backgroundBottomHex: "#15231E",
            mascotName: "松烟",
            bitmap: ["........", "........", "........", "........", "........", "........"]
        ),
        CotPassTheme(
            id: 1,
            title: "鎏金琥珀",
            subtitle: "AMBER GOLD",
            matrixColorHex: "#E5A93C",
            accentColorHex: "#FDE6B8",
            backgroundTopHex: "#15100A",
            backgroundBottomHex: "#241B10",
            mascotName: "鎏金",
            bitmap: ["........", "........", "........", "........", "........", "........"]
        ),
        CotPassTheme(
            id: 2,
            title: "电光深紫",
            subtitle: "ULTRA VIOLET",
            matrixColorHex: "#8772D6",
            accentColorHex: "#EAE8F5",
            backgroundTopHex: "#0E0E16",
            backgroundBottomHex: "#1B172E",
            mascotName: "深紫",
            bitmap: ["........", "........", "........", "........", "........", "........"]
        ),
        CotPassTheme(
            id: 3,
            title: "信号绯红",
            subtitle: "CRIMSON",
            matrixColorHex: "#E0444D",
            accentColorHex: "#F2EAEA",
            backgroundTopHex: "#111011",
            backgroundBottomHex: "#211215",
            mascotName: "绯红",
            bitmap: ["........", "........", "........", "........", "........", "........"]
        ),
        CotPassTheme(
            id: 4,
            title: "抹茶书卷",
            subtitle: "MATCHA",
            matrixColorHex: "#5D8718",
            accentColorHex: "#A4CE46",
            backgroundTopHex: "#EFE6CC",
            backgroundBottomHex: "#E7DBB8",
            mascotName: "抹茶",
            bitmap: ["........", "........", "........", "........", "........", "........"]
        ),
        CotPassTheme(
            id: 5,
            title: "宣白朱砂",
            subtitle: "VERMILION",
            matrixColorHex: "#D14236",
            accentColorHex: "#1C1F1E",
            backgroundTopHex: "#F6F3EC",
            backgroundBottomHex: "#ECE5D7",
            mascotName: "朱砂",
            bitmap: ["........", "........", "........", "........", "........", "........"]
        ),
    ]
    
    
    var isLightSurface: Bool {
        self.id == 4 || self.id == 5
    }
    
    
    static func resolve(index: Int) -> CotPassTheme {
        let safe = ((index % Self.allThemes.count) + Self.allThemes.count) % Self.allThemes.count
        return Self.allThemes[safe]
    }
}


// MARK: - Brand-Line-Cards Luminance Field & Spring Physics Engine

/// Implements the `brand-line-cards` vertical scanline reconstruction algorithm:
/// precomputes an emblem luminance grid, renders vertical strokes in 4 opacity/width tiers
/// modulated by downward-flowing smooth value noise, spring-repels nodes around the cursor
/// (`k=155, d=12`), and highlights candidate zones with dynamic reticle detection boxes.
@MainActor
final class BrandLinePassEngine {
    
    struct DetectionBox: Equatable, Sendable {
        let normRect: CGRect
    }
    
    static let gridSize = 72
    static let lineColumns = 48
    static let lineSegments = 76
    
    private static let sharedLuminanceField: [Float] = BrandLinePassEngine.buildEmblemLuminanceField()
    private static let candidateBoxes: [CGRect] = BrandLinePassEngine.buildCandidateBoxes(from: BrandLinePassEngine.sharedLuminanceField)
    
    private(set) var offsetX: [CGFloat]
    private(set) var velocityX: [CGFloat]
    private(set) var activeDetections: [DetectionBox] = []
    private var lastGridKey: Int = -1
    private var lastTick: CFTimeInterval = 0
    
    init() {
        let total = Self.lineColumns * (Self.lineSegments + 1)
        self.offsetX = Array(repeating: 0, count: total)
        self.velocityX = Array(repeating: 0, count: total)
    }
    
    
    static func luminance(normX: Double, normY: Double) -> Double {
        let gx = max(0, min(Double(Self.gridSize - 1), normX * Double(Self.gridSize - 1)))
        let gy = max(0, min(Double(Self.gridSize - 1), normY * Double(Self.gridSize - 1)))
        let x0 = Int(gx.rounded(.down))
        let y0 = Int(gy.rounded(.down))
        let x1 = min(Self.gridSize - 1, x0 + 1)
        let y1 = min(Self.gridSize - 1, y0 + 1)
        let tx = gx - Double(x0)
        let ty = gy - Double(y0)
        
        let f = Self.sharedLuminanceField
        let v00 = Double(f[y0 * Self.gridSize + x0])
        let v10 = Double(f[y0 * Self.gridSize + x1])
        let v01 = Double(f[y1 * Self.gridSize + x0])
        let v11 = Double(f[y1 * Self.gridSize + x1])
        
        let a = v00 * (1 - tx) + v10 * tx
        let b = v01 * (1 - tx) + v11 * tx
        return a * (1 - ty) + b * ty
    }
    
    
    static func valueNoise(x: Double, y: Double, seed: Int = 29) -> Double {
        func hash(_ ix: Int, _ iy: Int) -> Double {
            var n = ix &* 374761393 &+ iy &* 668265263 &+ seed &* 1442695041
            n = (n ^ (n >> 13)) &* 1274126177
            return Double((n ^ (n >> 16)) & 0xFFFF) / 65535.0
        }
        let ix = Int(floor(x))
        let iy = Int(floor(y))
        let fx = x - floor(x)
        let fy = y - floor(y)
        let ux = fx * fx * (3.0 - 2.0 * fx)
        let uy = fy * fy * (3.0 - 2.0 * fy)
        let a = hash(ix, iy)
        let b = hash(ix + 1, iy)
        let c = hash(ix, iy + 1)
        let d = hash(ix + 1, iy + 1)
        return (a * (1 - ux) + b * ux) * (1 - uy) + (c * (1 - ux) + d * ux) * uy
    }
    
    
    func step(time: CFTimeInterval, size: CGSize, pointer: CGPoint?) {
        let dtRaw = self.lastTick == 0 ? 0.016 : max(0.001, min(0.025, time - self.lastTick))
        self.lastTick = time
        
        let substeps = max(1, Int(ceil(dtRaw / 0.009)))
        let h = CGFloat(dtRaw / Double(substeps))
        let radius = size.width * 0.28
        let stiffness: CGFloat = 155.0
        let damping: CGFloat = 12.0
        
        let cols = Self.lineColumns
        let rows = Self.lineSegments
        let colStep = size.width / CGFloat(max(1, cols - 1))
        let rowStep = size.height / CGFloat(rows)
        
        for _ in 0..<substeps {
            for c in 0..<cols {
                let baseX = CGFloat(c) * colStep
                for r in 0...rows {
                    let idx = c * (rows + 1) + r
                    var xOff = self.offsetX[idx]
                    var vx = self.velocityX[idx]
                    
                    var repelAccel: CGFloat = 0
                    if let pointer, radius > 1 {
                        let px = baseX + xOff
                        let py = CGFloat(r) * rowStep
                        let dx = px - pointer.x
                        let dy = py - pointer.y
                        let dist = hypot(dx, dy)
                        if dist < radius {
                            let falloff = pow(1.0 - dist / radius, 2.0)
                            let dir: CGFloat = abs(dx) < 1.5 ? ((c % 2 == 0) ? 1.0 : -1.0) : (dx >= 0 ? 1.0 : -1.0)
                            repelAccel = dir * falloff * 1450.0
                        }
                    }
                    
                    let accel = repelAccel - stiffness * xOff - damping * vx
                    vx += accel * h
                    xOff += vx * h
                    self.offsetX[idx] = max(-22, min(22, xOff))
                    self.velocityX[idx] = vx
                }
            }
        }
        
        self.updateDetectionBoxesIfNeeded(size: size, pointer: pointer)
    }
    
    
    private func updateDetectionBoxesIfNeeded(size: CGSize, pointer: CGPoint?) {
        guard let pointer, size.width > 0, size.height > 0 else {
            if !self.activeDetections.isEmpty {
                self.activeDetections.removeAll()
                self.lastGridKey = -1
            }
            return
        }
        let nx = max(0, min(1, pointer.x / size.width))
        let ny = max(0, min(1, pointer.y / size.height))
        let cellKey = Int(ny * 7) * 16 + Int(nx * 10)
        guard cellKey != self.lastGridKey else { return }
        self.lastGridKey = cellKey
        
        let sorted = Self.candidateBoxes.sorted { a, b in
            let da = hypot(a.midX - nx, a.midY - ny)
            let db = hypot(b.midX - nx, b.midY - ny)
            return da < db
        }
        var picked: [CGRect] = []
        for rect in sorted where hypot(rect.midX - nx, rect.midY - ny) <= 0.34 {
            if !picked.contains(where: { $0.intersects(rect.insetBy(dx: -0.02, dy: -0.02)) }) {
                picked.append(rect)
                if picked.count >= 2 { break }
            }
        }
        if picked.isEmpty, let nearest = sorted.first {
            picked = [nearest]
        }
        self.activeDetections = picked.map { DetectionBox(normRect: $0) }
    }
    
    
    private static func buildEmblemLuminanceField() -> [Float] {
        let size = Self.gridSize
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: size,
            pixelsHigh: size,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            return Array(repeating: 0, count: size * size)
        }
        rep.size = NSSize(width: size, height: size)
        
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor.black.setFill()
        NSRect(x: 0, y: 0, width: size, height: size).fill()
        
        // Draw iconic nib + orbiting rings centered on right-hand side of the pass card
        let cx = CGFloat(size) * 0.72
        let cy = CGFloat(size) * 0.46
        
        NSColor.white.withAlphaComponent(0.60).setStroke()
        for idx in 0..<3 {
            let r = CGFloat(11 + idx * 8)
            let ring = NSBezierPath(ovalIn: NSRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2))
            ring.lineWidth = idx == 1 ? 2.4 : 1.4
            ring.stroke()
        }
        
        // Bold fountain pen nib / quill silhouette
        let nib = NSBezierPath()
        nib.move(to: NSPoint(x: cx, y: cy + 20))
        nib.line(to: NSPoint(x: cx - 14, y: cy - 3))
        nib.line(to: NSPoint(x: cx - 7, y: cy - 17))
        nib.line(to: NSPoint(x: cx + 7, y: cy - 17))
        nib.line(to: NSPoint(x: cx + 14, y: cy - 3))
        nib.close()
        NSColor.white.withAlphaComponent(0.95).setFill()
        nib.fill()
        
        // Nib slit cutout
        NSColor.black.setStroke()
        let slit = NSBezierPath()
        slit.lineWidth = 2.0
        slit.move(to: NSPoint(x: cx, y: cy + 16))
        slit.line(to: NSPoint(x: cx, y: cy - 1))
        slit.stroke()
        NSColor.black.setFill()
        NSBezierPath(ovalIn: NSRect(x: cx - 2.6, y: cy - 4.0, width: 5.2, height: 5.2)).fill()
        
        NSGraphicsContext.restoreGraphicsState()
        
        var field = [Float](repeating: 0, count: size * size)
        for y in 0..<size {
            for x in 0..<size {
                let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) ?? .black
                let luma = Float(0.2126 * c.redComponent + 0.7152 * c.greenComponent + 0.0722 * c.blueComponent)
                field[(size - 1 - y) * size + x] = min(1, max(0, luma))
            }
        }
        return field
    }
    
    
    private static func buildCandidateBoxes(from field: [Float]) -> [CGRect] {
        let g = Self.gridSize
        let winSizes: [(Int, Int)] = [(8, 7), (11, 9), (14, 12)]
        var boxes: [CGRect] = []
        for (ww, wh) in winSizes {
            var y = 6
            while y + wh < g - 8 {
                var x = 20
                while x + ww < g - 4 {
                    var sum: Float = 0
                    for dy in 0..<wh {
                        for dx in 0..<ww {
                            sum += field[(y + dy) * g + (x + dx)]
                        }
                    }
                    let mean = sum / Float(ww * wh)
                    if mean > 0.24 {
                        boxes.append(CGRect(
                            x: CGFloat(x) / CGFloat(g),
                            y: CGFloat(y) / CGFloat(g),
                            width: CGFloat(ww) / CGFloat(g),
                            height: CGFloat(wh) / CGFloat(g)
                        ))
                    }
                    x += 5
                }
                y += 5
            }
        }
        return boxes
    }
}


// MARK: - Settings View (Pure Showcase — Zero Buttons)

struct CotPassSettingsView: View {
    
    @Environment(\.colorScheme) private var colorScheme
    
    @State private var profileManager = UserProfileManager.shared
    @State private var analytics = AnalyticsManager.shared
    @State private var botStore = AIBotStore.shared
    @State private var styleIndex: Int = 0
    @State private var serialCode: String = ""
    
    @State private var tiltX: Double = 0
    @State private var tiltY: Double = 0
    @State private var hoverPoint = UnitPoint(x: 0.5, y: 0.5)
    @State private var hoverLocation: CGPoint?
    @State private var isCardHovered = false
    @State private var isStamping = false
    @State private var brandLineEngine = BrandLinePassEngine()
    
    
    private var theme: CotPassTheme {
        CotPassTheme.resolve(index: self.styleIndex)
    }
    
    private var joinedText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy.MM.dd"
        return formatter.string(from: self.profileManager.activeProfile.createdAt)
    }
    
    private var lifetimeTypedChars: Int {
        var total = self.analytics.todayStats.typedChars
        let todayKey = self.analytics.todayStats.dateKey
        for stat in self.analytics.recentDailyStats where stat.dateKey != todayKey {
            total += stat.typedChars
        }
        return total
    }
    
    private var conceptBadge: String {
        Self.conciseBadgeTitle(
            aiConceptTitle: self.analytics.personalityProfile?.conceptTitle,
            lifetimeTypedChars: self.lifetimeTypedChars
        )
    }
    
    static func conciseBadgeTitle(aiConceptTitle: String?, lifetimeTypedChars: Int) -> String {
        if let raw = aiConceptTitle?.trimmingCharacters(in: .whitespacesAndNewlines),
           !raw.isEmpty
        {
            if raw.count <= 4 {
                return raw
            }
            return String(raw.prefix(4))
        }
        if lifetimeTypedChars >= 50_000 { return "万字大神" }
        if lifetimeTypedChars >= 10_000 { return "笔耕狠人" }
        if lifetimeTypedChars >= 2_000 { return "稳产写手" }
        return "执笔新锐"
    }
    
    private var enabledBotCount: Int {
        AIBotID.allCases.filter { self.botStore.config(for: $0).isEnabled }.count
    }
    
    
    var body: some View {
        let daily14 = self.analytics.dailySeries(days: 14).map { Double($0.typedChars) }
        let streakDays = self.analytics.currentWritingStreak
        let docCount = CotLocalDatabase.shared.documents.count
        
        VStack(alignment: .center, spacing: 22) {
            Spacer(minLength: 8)
            
            // Flagship Pure-Emotional Collector Card + Brand-Line-Cards Reactive Scanlines
            CotPassCardView(
                theme: self.theme,
                profile: self.profileManager.activeProfile,
                avatarImage: self.profileManager.avatarImage(for: self.profileManager.activeProfile),
                serialCode: self.serialCode,
                joinedText: self.joinedText,
                conceptBadge: self.conceptBadge,
                waveformValues: daily14,
                lifetimeTypedChars: self.lifetimeTypedChars,
                streakDays: streakDays,
                docCount: docCount,
                enabledBotCount: self.enabledBotCount,
                specularPoint: self.hoverPoint,
                pointerLocation: self.hoverLocation,
                isHovered: self.isCardHovered,
                isStamping: self.isStamping,
                brandLineEngine: self.brandLineEngine,
                onTapChopSeal: {
                    NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
                    withAnimation(.spring(response: 0.20, dampingFraction: 0.50)) {
                        self.isStamping = true
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
                        withAnimation(.spring(response: 0.30, dampingFraction: 0.72)) {
                            self.isStamping = false
                        }
                    }
                }
            )
            .rotation3DEffect(.degrees(self.tiltX), axis: (x: 1, y: 0, z: 0), perspective: 0.55)
            .rotation3DEffect(.degrees(self.tiltY), axis: (x: 0, y: 1, z: 0), perspective: 0.55)
            .scaleEffect(self.isCardHovered ? 1.018 : 1.0)
            .animation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.22), value: self.tiltX)
            .animation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.22), value: self.tiltY)
            .animation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.18), value: self.isCardHovered)
            .onContinuousHover { phase in
                switch phase {
                    case .active(let pt):
                        self.isCardHovered = true
                        self.hoverLocation = pt
                        let ux = max(0, min(1, pt.x / 408.0))
                        let uy = max(0, min(1, pt.y / 246.0))
                        self.hoverPoint = UnitPoint(x: ux, y: uy)
                        let nx = (ux - 0.5) * 2.0
                        let ny = (uy - 0.5) * 2.0
                        self.tiltY = max(-6.0, min(6.0, nx * 5.8))
                        self.tiltX = max(-6.0, min(6.0, -ny * 4.8))
                    case .ended:
                        self.isCardHovered = false
                        self.hoverLocation = nil
                        self.tiltX = 0
                        self.tiltY = 0
                        self.hoverPoint = UnitPoint(x: 0.5, y: 0.5)
                }
            }
            
            // Minimal Jewel Finish Swatches (zero utility buttons)
            HStack(spacing: 12) {
                ForEach(CotPassTheme.allThemes) { option in
                    let isSelected = (option.id == self.theme.id)
                    let swatch = Color(hexString: option.matrixColorHex)
                    let base = Color(hexString: option.backgroundTopHex)
                    
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [swatch, base],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: isSelected ? 22 : 16, height: isSelected ? 22 : 16)
                        .overlay(
                            Circle()
                                .strokeBorder(swatch.opacity(isSelected ? 0.95 : 0.35), lineWidth: isSelected ? 2.0 : 0.8)
                        )
                        .padding(3)
                        .background(
                            Circle()
                                .strokeBorder(isSelected ? swatch.opacity(0.42) : Color.clear, lineWidth: 1.5)
                        )
                        .contentShape(Circle())
                        .onTapGesture {
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) {
                                self.styleIndex = option.id
                            }
                            CotLocalDatabase.shared.set("\(option.id)", forKey: CotLocalDatabase.ConfigKey.cotPassStyleIndex)
                        }
                        .pointerStyle(.link)
                        .help(option.mascotName)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(self.colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.035))
            )
            
            Spacer(minLength: 8)
        }
        .frame(maxWidth: .infinity)
        .onAppear {
            self.loadPassState()
        }
    }
    
    
    private func loadPassState() {
        let db = CotLocalDatabase.shared
        let rawIndex = Int(db.string(forKey: CotLocalDatabase.ConfigKey.cotPassStyleIndex, default: "0")) ?? 0
        self.styleIndex = ((rawIndex % CotPassTheme.allThemes.count) + CotPassTheme.allThemes.count) % CotPassTheme.allThemes.count
        
        let storedSerial = db.string(forKey: CotLocalDatabase.ConfigKey.cotPassSerialCode)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if storedSerial.isEmpty {
            let generated = CotPassLicense.generateSerialCode()
            db.set(generated, forKey: CotLocalDatabase.ConfigKey.cotPassSerialCode)
            self.serialCode = generated
        } else {
            self.serialCode = storedSerial
        }
    }
}


// MARK: - Horizontal Collector Pass Card (Brand-Line Reactive Canvas)

struct CotPassCardView: View {
    
    let theme: CotPassTheme
    let profile: UserProfile
    let avatarImage: NSImage?
    let serialCode: String
    let joinedText: String
    let conceptBadge: String
    let waveformValues: [Double]
    let lifetimeTypedChars: Int
    let streakDays: Int
    let docCount: Int
    let enabledBotCount: Int
    var specularPoint: UnitPoint = UnitPoint(x: 0.5, y: 0.5)
    var pointerLocation: CGPoint? = nil
    var isHovered: Bool = false
    var isStamping: Bool = false
    var brandLineEngine: BrandLinePassEngine? = nil
    var onTapChopSeal: (() -> Void)? = nil
    
    @State private var fallbackEngine = BrandLinePassEngine()
    
    
    var body: some View {
        let accent = Color(hexString: self.theme.matrixColorHex)
        let secondaryInk = Color(hexString: self.theme.accentColorHex)
        let topBg = Color(hexString: self.theme.backgroundTopHex)
        let bottomBg = Color(hexString: self.theme.backgroundBottomHex)
        let primaryText: Color = self.theme.isLightSurface ? Color(red: 0.10, green: 0.11, blue: 0.10) : Color.white
        let mutedText: Color = self.theme.isLightSurface ? Color.black.opacity(0.52) : Color.white.opacity(0.50)
        let dividerStroke: Color = self.theme.isLightSurface ? Color.black.opacity(0.09) : Color.white.opacity(0.11)
        let badgeInk: Color = (self.theme.id == 4) ? Color(red: 0.08, green: 0.08, blue: 0.08) : (self.theme.isLightSurface ? .white : .black.opacity(0.88))
        let badgeFill: Color = (self.theme.id == 4) ? Color(hexString: self.theme.accentColorHex) : accent
        let engine = self.brandLineEngine ?? self.fallbackEngine
        
        ZStack {
            // Material metallic/vellum gradient base
            LinearGradient(colors: [topBg, bottomBg], startPoint: .topLeading, endPoint: .bottomTrailing)
            
            // Brand-Line-Cards vertical scanline emblem + spring pointer repulsion + reticle boxes
            TimelineView(.animation(minimumInterval: self.isHovered ? (1.0 / 60.0) : (1.0 / 12.0), paused: AnimationConstants.isReducedMotionEnabled)) { context in
                let t = context.date.timeIntervalSinceReferenceDate
                Canvas { graphics, canvasSize in
                    engine.step(time: t, size: canvasSize, pointer: self.pointerLocation)
                    
                    let cols = BrandLinePassEngine.lineColumns
                    let rows = BrandLinePassEngine.lineSegments
                    let colStep = canvasSize.width / CGFloat(max(1, cols - 1))
                    let rowStep = canvasSize.height / CGFloat(rows)
                    let widths: [CGFloat] = [0.34, 0.85, 1.65, 2.55]
                    let alphas: [Double] = [0.02, 0.16, 0.34, 0.54]
                    let noiseYShift = t * 0.48
                    
                    for c in 0..<cols {
                        let baseX = CGFloat(c) * colStep
                        let normX = Double(c) / Double(max(1, cols - 1))
                        
                        for r in 0..<rows {
                            let idx0 = c * (rows + 1) + r
                            let idx1 = idx0 + 1
                            let x0 = baseX + engine.offsetX[idx0]
                            let x1 = baseX + engine.offsetX[idx1]
                            let y0 = CGFloat(r) * rowStep
                            let y1 = CGFloat(r + 1) * rowStep
                            let normY = (Double(r) + 0.5) / Double(rows)
                            
                            let luma = BrandLinePassEngine.luminance(normX: normX, normY: normY)
                            let n = BrandLinePassEngine.valueNoise(x: Double(c) * 0.24, y: Double(r) * 0.16 - noiseYShift)
                            let combined = luma + (n - 0.5) * 0.26
                            let tier: Int
                            if combined >= 0.72 { tier = 3 }
                            else if combined >= 0.45 { tier = 2 }
                            else if combined >= 0.22 { tier = 1 }
                            else { tier = 0 }
                            
                            var seg = Path()
                            seg.move(to: CGPoint(x: x0, y: y0))
                            seg.addLine(to: CGPoint(x: x1, y: y1))
                            let a = self.theme.isLightSurface ? alphas[tier] * 0.82 : alphas[tier]
                            graphics.stroke(seg, with: .color(accent.opacity(a)), style: StrokeStyle(lineWidth: widths[tier], lineCap: .round))
                        }
                    }
                    
                    // Subtle 14-day keystroke curve along lower-right horizon
                    Self.drawKeystrokeRibbon(in: &graphics, size: canvasSize, values: self.waveformValues, accent: accent)
                    
                    // Dynamic pointer detection boxes & leader hairlines when hovered
                    if let pointer = self.pointerLocation, !engine.activeDetections.isEmpty {
                        for box in engine.activeDetections {
                            let rect = CGRect(
                                x: box.normRect.minX * canvasSize.width,
                                y: box.normRect.minY * canvasSize.height,
                                width: box.normRect.width * canvasSize.width,
                                height: box.normRect.height * canvasSize.height
                            )
                            graphics.stroke(
                                Path(roundedRect: rect, cornerRadius: 2),
                                with: .color(accent.opacity(0.55)),
                                lineWidth: 0.85
                            )
                            var leader = Path()
                            leader.move(to: pointer)
                            leader.addLine(to: CGPoint(x: rect.midX, y: rect.midY))
                            graphics.stroke(
                                leader,
                                with: .color(accent.opacity(0.32)),
                                style: StrokeStyle(lineWidth: 0.75, dash: [3, 2])
                            )
                        }
                    }
                }
            }
            .allowsHitTesting(false)
            
            // Inner letterpress registration hairline
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(dividerStroke, lineWidth: 0.75)
                .padding(8)
                .allowsHitTesting(false)
            
            // Diagonal metallic foil gleam tracking cursor
            RadialGradient(
                colors: [
                    (self.theme.isLightSurface ? Color.white : accent).opacity(self.isHovered ? 0.24 : 0.08),
                    .clear,
                ],
                center: self.specularPoint,
                startRadius: 8,
                endRadius: 250
            )
            .allowsHitTesting(false)
            
            VStack(alignment: .leading, spacing: 0) {
                // Header Seal (All labels ≤ 4 chars)
                HStack(alignment: .center) {
                    HStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(accent)
                            .frame(width: 6, height: 6)
                        Text(AppLanguage.text("执笔铭牌", en: "PASS CARD"))
                            .font(.system(size: 11, weight: .bold))
                            .tracking(1.6)
                            .foregroundStyle(accent)
                    }
                    
                    Spacer()
                    
                    Text("NO.\(self.serialCode) · \(self.joinedText)")
                        .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(mutedText)
                }
                
                Spacer(minLength: 10)
                
                // Identity Row
                HStack(alignment: .center, spacing: 14) {
                    UserAvatarCircleView(profile: self.profile, size: 52, customImage: self.avatarImage)
                        .overlay(
                            Circle()
                                .strokeBorder(accent.opacity(0.82), lineWidth: 1.5)
                        )
                        .shadow(color: accent.opacity(0.30), radius: 9, y: 2)
                    
                    VStack(alignment: .leading, spacing: 5) {
                        Text(self.profile.displayName)
                            .font(.system(size: 19, weight: .bold))
                            .foregroundStyle(primaryText)
                            .lineLimit(1)
                        
                        HStack(spacing: 6) {
                            Text(self.conceptBadge)
                                .font(.system(size: 10.5, weight: .semibold))
                                .foregroundStyle(badgeInk)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2.5)
                                .background(badgeFill, in: Capsule())
                            
                            Text(self.theme.title)
                                .font(.system(size: 10.5, weight: .medium))
                                .foregroundStyle(secondaryInk.opacity(0.86))
                        }
                    }
                    
                    Spacer(minLength: 4)
                    
                    // Playful tactile chop seal ("墨")
                    ZStack {
                        RoundedRectangle(cornerRadius: 6.5, style: .continuous)
                            .fill(Color(red: 0.78, green: 0.21, blue: 0.18).opacity(0.94))
                            .frame(width: 32, height: 32)
                            .overlay(
                                RoundedRectangle(cornerRadius: 4.8, style: .continuous)
                                    .strokeBorder(Color(red: 0.99, green: 0.95, blue: 0.88).opacity(0.55), lineWidth: 0.8)
                                    .padding(2.5)
                            )
                        
                        Text("墨")
                            .font(.system(size: 15, weight: .black, design: .serif))
                            .foregroundStyle(Color(red: 0.99, green: 0.96, blue: 0.90))
                    }
                    .rotationEffect(.degrees(self.isStamping ? -10 : 3))
                    .scaleEffect(self.isStamping ? 0.82 : 1.0)
                    .shadow(color: Color(red: 0.78, green: 0.21, blue: 0.18).opacity(0.35), radius: 6, y: 2)
                    .onTapGesture {
                        self.onTapChopSeal?()
                    }
                    .pointerStyle(.link)
                }
                
                Spacer(minLength: 14)
                
                Rectangle()
                    .fill(dividerStroke)
                    .frame(height: 1)
                    .padding(.bottom, 12)
                
                // Bottom 4 Plain & Concrete Telemetry Counters (Every Label ≤ 4 Chinese Characters)
                HStack(spacing: 0) {
                    self.metricCell(
                        label: AppLanguage.text("累计码字", en: "Typed"),
                        value: Self.compactChars(self.lifetimeTypedChars),
                        primary: primaryText,
                        muted: mutedText
                    )
                    self.metricCell(
                        label: AppLanguage.text("连续打卡", en: "Streak"),
                        value: "\(self.streakDays) 天",
                        primary: primaryText,
                        muted: mutedText
                    )
                    self.metricCell(
                        label: AppLanguage.text("文档总数", en: "Docs"),
                        value: "\(self.docCount) 篇",
                        primary: primaryText,
                        muted: mutedText
                    )
                    self.metricCell(
                        label: AppLanguage.text("AI 搭档", en: "Agents"),
                        value: "\(self.enabledBotCount) 位",
                        primary: primaryText,
                        muted: mutedText
                    )
                }
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 20)
        }
        .frame(width: 408, height: 246)
        .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 17, style: .continuous)
                .strokeBorder(accent.opacity(self.isHovered ? 0.58 : 0.32), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(self.theme.isLightSurface ? 0.14 : 0.34), radius: 22, y: 10)
    }
    
    
    private func metricCell(label: String, value: String, primary: Color, muted: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(muted)
            Text(value)
                .font(.system(size: 13.5, weight: .semibold, design: .monospaced))
                .foregroundStyle(primary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    
    private static func compactChars(_ count: Int) -> String {
        if count >= 10_000 {
            return String(format: "%.1f万", Double(count) / 10_000.0)
        }
        return "\(count) 字"
    }
    
    
    private static func drawKeystrokeRibbon(in context: inout GraphicsContext, size: CGSize, values: [Double], accent: Color) {
        let samples = values.isEmpty ? Array(repeating: 0.0, count: 14) : values
        let peak = max(120.0, samples.max() ?? 120.0)
        let baselineY = size.height * 0.65
        let startX = size.width * 0.48
        let widthSpan = size.width - startX - 22
        let stepX = widthSpan / CGFloat(max(1, samples.count - 1))
        
        var points: [CGPoint] = []
        for (index, val) in samples.enumerated() {
            let norm = max(0.04, min(1.0, val / peak))
            points.append(CGPoint(x: startX + CGFloat(index) * stepX, y: baselineY - CGFloat(norm) * 28))
        }
        guard let first = points.first else { return }
        var wavePath = Path()
        wavePath.move(to: first)
        for idx in 1..<points.count {
            let prev = points[idx - 1]
            let curr = points[idx]
            let midX = (prev.x + curr.x) * 0.5
            wavePath.addCurve(to: curr, control1: CGPoint(x: midX, y: prev.y), control2: CGPoint(x: midX, y: curr.y))
        }
        context.stroke(wavePath, with: .color(accent.opacity(0.42)), style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round))
    }
}
