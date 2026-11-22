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

// MARK: - License & Serial Model

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
        "LANDED"
    }
    
    
    var accessLabel: String {
        switch self {
            case .explorer: AppLanguage.text("免费", en: "FREE")
            case .pro, .founder: AppLanguage.text("付费", en: "PAID")
        }
    }
    
    
    var summaryLabel: String {
        switch self {
            case .explorer: "免费"
            case .pro, .founder: "付费"
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


// MARK: - Curated Pass Finishes

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
            title: "松烟",
            subtitle: "PINE",
            matrixColorHex: "#44C997",
            accentColorHex: "#E8ECE9",
            backgroundTopHex: "#0B1512",
            backgroundBottomHex: "#15231E",
            mascotName: "松烟",
            bitmap: ["........", "........", "........", "........", "........", "........"]
        ),
        CotPassTheme(
            id: 1,
            title: "琥珀",
            subtitle: "AMBER",
            matrixColorHex: "#E5A93C",
            accentColorHex: "#FDE6B8",
            backgroundTopHex: "#15100A",
            backgroundBottomHex: "#241B10",
            mascotName: "琥珀",
            bitmap: ["........", "........", "........", "........", "........", "........"]
        ),
        CotPassTheme(
            id: 2,
            title: "深紫",
            subtitle: "VIOLET",
            matrixColorHex: "#8772D6",
            accentColorHex: "#EAE8F5",
            backgroundTopHex: "#0E0E16",
            backgroundBottomHex: "#1B172E",
            mascotName: "深紫",
            bitmap: ["........", "........", "........", "........", "........", "........"]
        ),
        CotPassTheme(
            id: 3,
            title: "绯红",
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
            title: "抹茶",
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
            title: "宣白",
            subtitle: "PAPER",
            matrixColorHex: "#D14236",
            accentColorHex: "#1C1F1E",
            backgroundTopHex: "#F6F3EC",
            backgroundBottomHex: "#ECE5D7",
            mascotName: "宣白",
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


// MARK: - Avatar-Contour Scanline Luminance Field & Spring Physics Engine

/// Computes a vertical scanline reconstruction directly from the user's avatar silhouette & contour
/// (Sobel edge detection + contrast-normalized luminance inside a circular portrait mask),
/// with pointer spring repulsion (`k=155, d=12`) and reticle detection boxes locking onto contour features.
@MainActor
final class BrandLinePassEngine {
    
    struct DetectionBox: Equatable, Sendable {
        let normRect: CGRect
    }
    
    static let gridSize = 72
    static let lineColumns = 48
    static let lineSegments = 76
    
    private static let fallbackField: [Float] = BrandLinePassEngine.buildMonogramContourField(initials: "C")
    private static var contourCache: [String: (field: [Float], boxes: [CGRect])] = [:]
    
    private var activeField: [Float]
    private var activeCandidateBoxes: [CGRect]
    private var activeContourKey: String = ""
    
    private(set) var offsetX: [CGFloat]
    private(set) var velocityX: [CGFloat]
    private(set) var activeDetections: [DetectionBox] = []
    private var lastGridKey: Int = -1
    private var lastTick: CFTimeInterval = 0
    
    init() {
        let total = Self.lineColumns * (Self.lineSegments + 1)
        self.offsetX = Array(repeating: 0, count: total)
        self.velocityX = Array(repeating: 0, count: total)
        self.activeField = Self.fallbackField
        self.activeCandidateBoxes = Self.buildCandidateBoxes(from: Self.fallbackField)
    }
    
    
    /// Updates the scanline emblem field from the active user's avatar image (or monogram fallback).
    func syncAvatarContour(profile: UserProfile, avatarImage: NSImage?) {
        let key = "\(profile.id)|\(profile.avatarData?.count ?? 0)|\(profile.displayName)"
        guard key != self.activeContourKey else { return }
        self.activeContourKey = key
        
        if let cached = Self.contourCache[key] {
            self.activeField = cached.field
            self.activeCandidateBoxes = cached.boxes
            self.lastGridKey = -1
            return
        }
        
        let field: [Float]
        if let avatarImage {
            field = Self.buildAvatarContourField(from: avatarImage)
        } else {
            field = Self.buildMonogramContourField(initials: UserProfileManager.initials(for: profile.displayName))
        }
        let boxes = Self.buildCandidateBoxes(from: field)
        if Self.contourCache.count > 16 {
            Self.contourCache.removeAll()
        }
        Self.contourCache[key] = (field, boxes)
        self.activeField = field
        self.activeCandidateBoxes = boxes
        self.lastGridKey = -1
    }
    
    
    /// Samples the active avatar-contour field at normalized card coordinates `(normX, normY)`.
    func sampleLuminance(normX: Double, normY: Double) -> Double {
        Self.sampleField(self.activeField, normX: normX, normY: normY)
    }
    
    
    /// Static fallback sampler retained for unit test compatibility.
    static func luminance(normX: Double, normY: Double) -> Double {
        Self.sampleField(Self.fallbackField, normX: normX, normY: normY)
    }
    
    
    private static func sampleField(_ f: [Float], normX: Double, normY: Double) -> Double {
        let gx = max(0, min(Double(Self.gridSize - 1), normX * Double(Self.gridSize - 1)))
        let gy = max(0, min(Double(Self.gridSize - 1), normY * Double(Self.gridSize - 1)))
        let x0 = Int(gx.rounded(.down))
        let y0 = Int(gy.rounded(.down))
        let x1 = min(Self.gridSize - 1, x0 + 1)
        let y1 = min(Self.gridSize - 1, y0 + 1)
        let tx = gx - Double(x0)
        let ty = gy - Double(y0)
        
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
        
        let sorted = self.activeCandidateBoxes.sorted { a, b in
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
    
    
    /// Extracts a Sobel contour + tonal silhouette field from the user's avatar image,
    /// positioned cleanly on the right-hand side of the Pass card.
    static func buildAvatarContourField(from avatarImage: NSImage) -> [Float] {
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
        
        // Right-hand portrait region centered at (0.72, 0.48), circularly clipped for clean silhouette framing
        let radius = CGFloat(size) * 0.27
        let cx = CGFloat(size) * 0.72
        let cy = CGFloat(size) * 0.52
        let circleRect = NSRect(x: cx - radius, y: cy - radius, width: radius * 2, height: radius * 2)
        
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSGraphicsContext.current?.imageInterpolation = .high
        NSColor.clear.setFill()
        NSRect(x: 0, y: 0, width: size, height: size).fill()
        
        NSBezierPath(ovalIn: circleRect).addClip()
        let src = avatarImage.size
        let aspectScale = max(circleRect.width / max(1, src.width), circleRect.height / max(1, src.height))
        let drawW = src.width * aspectScale
        let drawH = src.height * aspectScale
        let drawRect = NSRect(
            x: circleRect.midX - drawW * 0.5,
            y: circleRect.midY - drawH * 0.5,
            width: drawW,
            height: drawH
        )
        avatarImage.draw(in: drawRect, from: .zero, operation: .sourceOver, fraction: 1.0)
        NSGraphicsContext.restoreGraphicsState()
        
        var lumaGrid = [Float](repeating: 0, count: size * size)
        var alphaGrid = [Float](repeating: 0, count: size * size)
        var minLuma: Float = 1
        var maxLuma: Float = 0
        
        for y in 0..<size {
            for x in 0..<size {
                let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) ?? .clear
                let a = Float(c.alphaComponent)
                let l = Float(0.2126 * c.redComponent + 0.7152 * c.greenComponent + 0.0722 * c.blueComponent)
                let row = size - 1 - y
                lumaGrid[row * size + x] = l
                alphaGrid[row * size + x] = a
                if a > 0.3 {
                    minLuma = min(minLuma, l)
                    maxLuma = max(maxLuma, l)
                }
            }
        }
        
        let lumaSpan = max(0.15, maxLuma - minLuma)
        
        // Sobel gradient magnitude on luma + alpha to extract crisp silhouette & internal facial/hair contours
        var edgeGrid = [Float](repeating: 0, count: size * size)
        var maxEdge: Float = 0.001
        
        for y in 1..<(size - 1) {
            for x in 1..<(size - 1) {
                func sample(_ sx: Int, _ sy: Int) -> Float {
                    let i = sy * size + sx
                    return lumaGrid[i] * alphaGrid[i]
                }
                let tl = sample(x - 1, y - 1), tc = sample(x, y - 1), tr = sample(x + 1, y - 1)
                let ml = sample(x - 1, y),                             mr = sample(x + 1, y)
                let bl = sample(x - 1, y + 1), bc = sample(x, y + 1), br = sample(x + 1, y + 1)
                
                let gx = -tl + tr - 2 * ml + 2 * mr - bl + br
                let gy = -tl - 2 * tc - tr + bl + 2 * bc + br
                let mag = hypot(gx, gy)
                edgeGrid[y * size + x] = mag
                if mag > maxEdge { maxEdge = mag }
            }
        }
        
        let centerNormX = Float(0.72)
        let centerNormY = Float(0.48)
        let normRadius = Float(0.28)
        
        var field = [Float](repeating: 0, count: size * size)
        for y in 0..<size {
            for x in 0..<size {
                let idx = y * size + x
                let a = alphaGrid[idx]
                guard a > 0.05 else { continue }
                
                let nx = Float(x) / Float(size - 1)
                let ny = Float(y) / Float(size - 1)
                let dist = hypot(nx - centerNormX, ny - centerNormY)
                let radialFade = max(0, min(1, 1.0 - max(0, (dist - normRadius * 0.78) / (normRadius * 0.28))))
                
                let normEdge = min(1.0, pow(edgeGrid[idx] / maxEdge, 0.72) * 1.25)
                let normTone = max(0, min(1, (lumaGrid[idx] - minLuma) / lumaSpan))
                // Emphasize silhouette & facial contours (68%) supported by soft volume (32%)
                let combined = (normEdge * 0.68 + normTone * 0.32) * a * radialFade
                field[idx] = min(1.0, max(0.0, combined))
            }
        }
        return field
    }
    
    
    /// Fallback contour field when the user has not uploaded a photo: renders their monogram silhouette cleanly.
    private static func buildMonogramContourField(initials: String) -> [Float] {
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
        
        let cx = CGFloat(size) * 0.72
        let cy = CGFloat(size) * 0.50
        let r = CGFloat(size) * 0.24
        
        NSColor.white.withAlphaComponent(0.55).setStroke()
        let ring = NSBezierPath(ovalIn: NSRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2))
        ring.lineWidth = 2.0
        ring.stroke()
        
        let text = initials.isEmpty ? "C" : initials
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: r * 1.15, weight: .bold),
            .foregroundColor: NSColor.white,
        ]
        let strSize = (text as NSString).size(withAttributes: attrs)
        (text as NSString).draw(
            at: NSPoint(x: cx - strSize.width * 0.5, y: cy - strSize.height * 0.5),
            withAttributes: attrs
        )
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
                    if mean > 0.18 {
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


// MARK: - Settings View

struct CotPassSettingsView: View {
    
    @Environment(\.colorScheme) private var colorScheme
    
    @State private var profileManager = UserProfileManager.shared
    @State private var styleIndex: Int = 0
    @State private var serialCode: String = ""
    @State private var accessTier: CotPassTier = .explorer
    
    @State private var tiltX: Double = 0
    @State private var tiltY: Double = 0
    @State private var hoverPoint = UnitPoint(x: 0.5, y: 0.5)
    @State private var hoverLocation: CGPoint?
    @State private var isCardHovered = false
    @State private var brandLineEngine = BrandLinePassEngine()
    
    
    private var theme: CotPassTheme {
        CotPassTheme.resolve(index: self.styleIndex)
    }
    
    private var joinedText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy.MM.dd"
        return formatter.string(from: self.profileManager.activeProfile.createdAt)
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
    
    
    var body: some View {
        let activeProfile = self.profileManager.activeProfile
        let avatarImage = self.profileManager.avatarImage(for: activeProfile)
        
        VStack(alignment: .center, spacing: 20) {
            Spacer(minLength: 12)
            
            CotPassCardView(
                theme: self.theme,
                profile: activeProfile,
                avatarImage: avatarImage,
                serialCode: self.serialCode,
                statusText: self.accessTier.statusLabel,
                joinedText: self.joinedText,
                accessText: self.accessTier.accessLabel,
                specularPoint: self.hoverPoint,
                pointerLocation: self.hoverLocation,
                isHovered: self.isCardHovered,
                brandLineEngine: self.brandLineEngine
            )
            .rotation3DEffect(.degrees(self.tiltX), axis: (x: 1, y: 0, z: 0), perspective: 0.55)
            .rotation3DEffect(.degrees(self.tiltY), axis: (x: 0, y: 1, z: 0), perspective: 0.55)
            .scaleEffect(self.isCardHovered ? 1.015 : 1.0)
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
                        self.tiltY = max(-6.0, min(6.0, nx * 5.6))
                        self.tiltX = max(-6.0, min(6.0, -ny * 4.6))
                    case .ended:
                        self.isCardHovered = false
                        self.hoverLocation = nil
                        self.tiltX = 0
                        self.tiltY = 0
                        self.hoverPoint = UnitPoint(x: 0.5, y: 0.5)
                }
            }
            
            // Minimal Finish Swatches
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
                            withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.24)) {
                                self.styleIndex = option.id
                            }
                            CotLocalDatabase.shared.set("\(option.id)", forKey: CotLocalDatabase.ConfigKey.cotPassStyleIndex)
                        }
                        .pointerStyle(.link)
                        .help(option.title)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(self.colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.035))
            )
            
            Spacer(minLength: 12)
        }
        .frame(maxWidth: .infinity)
        .onAppear {
            self.loadPassState()
            self.brandLineEngine.syncAvatarContour(profile: activeProfile, avatarImage: avatarImage)
        }
        .onChange(of: activeProfile.id) { _, _ in
            self.loadPassState()
            self.brandLineEngine.syncAvatarContour(
                profile: self.profileManager.activeProfile,
                avatarImage: self.profileManager.avatarImage(for: self.profileManager.activeProfile)
            )
        }
        .onChange(of: activeProfile.avatarData?.count) { _, _ in
            self.brandLineEngine.syncAvatarContour(
                profile: self.profileManager.activeProfile,
                avatarImage: self.profileManager.avatarImage(for: self.profileManager.activeProfile)
            )
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
        
        let licenseKey = db.string(forKey: CotLocalDatabase.ConfigKey.cotPassLicenseKey)
        self.accessTier = CotPassLicense.validate(licenseKey) ?? .explorer
    }
}


// MARK: - Horizontal Collector Pass Card (Avatar-Contour Scanline Canvas)

struct CotPassCardView: View {
    
    let theme: CotPassTheme
    let profile: UserProfile
    let avatarImage: NSImage?
    let serialCode: String
    let statusText: String
    let joinedText: String
    let accessText: String
    var specularPoint: UnitPoint = UnitPoint(x: 0.5, y: 0.5)
    var pointerLocation: CGPoint? = nil
    var isHovered: Bool = false
    var brandLineEngine: BrandLinePassEngine? = nil
    
    @State private var fallbackEngine = BrandLinePassEngine()
    
    
    var body: some View {
        let accent = Color(hexString: self.theme.matrixColorHex)
        let topBg = Color(hexString: self.theme.backgroundTopHex)
        let bottomBg = Color(hexString: self.theme.backgroundBottomHex)
        let primaryText: Color = self.theme.isLightSurface ? Color(red: 0.10, green: 0.11, blue: 0.10) : Color.white
        let mutedText: Color = self.theme.isLightSurface ? Color.black.opacity(0.48) : Color.white.opacity(0.46)
        let dividerStroke: Color = self.theme.isLightSurface ? Color.black.opacity(0.09) : Color.white.opacity(0.10)
        let engine = self.brandLineEngine ?? self.fallbackEngine
        
        ZStack {
            // Subtle tonal base
            LinearGradient(colors: [topBg, bottomBg], startPoint: .topLeading, endPoint: .bottomTrailing)
            
            // Avatar-contour vertical scanline reconstruction + spring pointer repulsion + reticle boxes
            TimelineView(.animation(minimumInterval: self.isHovered ? (1.0 / 60.0) : (1.0 / 12.0), paused: AnimationConstants.isReducedMotionEnabled)) { context in
                let t = context.date.timeIntervalSinceReferenceDate
                Canvas { graphics, canvasSize in
                    engine.syncAvatarContour(profile: self.profile, avatarImage: self.avatarImage)
                    engine.step(time: t, size: canvasSize, pointer: self.pointerLocation)
                    
                    let cols = BrandLinePassEngine.lineColumns
                    let rows = BrandLinePassEngine.lineSegments
                    let colStep = canvasSize.width / CGFloat(max(1, cols - 1))
                    let rowStep = canvasSize.height / CGFloat(rows)
                    let widths: [CGFloat] = [0.34, 0.88, 1.70, 2.65]
                    let alphas: [Double] = [0.02, 0.18, 0.38, 0.62]
                    let noiseYShift = t * 0.44
                    
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
                            
                            let luma = engine.sampleLuminance(normX: normX, normY: normY)
                            let n = BrandLinePassEngine.valueNoise(x: Double(c) * 0.24, y: Double(r) * 0.16 - noiseYShift)
                            let combined = luma + (n - 0.5) * 0.20
                            let tier: Int
                            if combined >= 0.66 { tier = 3 }
                            else if combined >= 0.40 { tier = 2 }
                            else if combined >= 0.18 { tier = 1 }
                            else { tier = 0 }
                            
                            var seg = Path()
                            seg.move(to: CGPoint(x: x0, y: y0))
                            seg.addLine(to: CGPoint(x: x1, y: y1))
                            let a = self.theme.isLightSurface ? alphas[tier] * 0.82 : alphas[tier]
                            graphics.stroke(seg, with: .color(accent.opacity(a)), style: StrokeStyle(lineWidth: widths[tier], lineCap: .round))
                        }
                    }
                    
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
            
            // Inner registration hairline
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(dividerStroke, lineWidth: 0.75)
                .padding(8)
                .allowsHitTesting(false)
            
            // Subtle specular sheen tracking cursor
            RadialGradient(
                colors: [
                    (self.theme.isLightSurface ? Color.white : accent).opacity(self.isHovered ? 0.18 : 0.05),
                    .clear,
                ],
                center: self.specularPoint,
                startRadius: 8,
                endRadius: 240
            )
            .allowsHitTesting(false)
            
            VStack(alignment: .leading, spacing: 0) {
                // Header strip
                HStack(alignment: .center) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(accent)
                            .frame(width: 6, height: 6)
                        Text("COTEDITOR PASS")
                            .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                            .foregroundStyle(accent)
                    }
                    
                    Spacer()
                    
                    Text("NO.\(self.serialCode)")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(mutedText)
                }
                
                Spacer(minLength: 16)
                
                // Clean Identity Block (Left-aligned, leaving right canvas clear for avatar contour)
                HStack(alignment: .center, spacing: 12) {
                    UserAvatarCircleView(profile: self.profile, size: 48, customImage: self.avatarImage)
                        .overlay(
                            Circle()
                                .strokeBorder(accent.opacity(0.65), lineWidth: 1.2)
                        )
                    
                    Text(self.profile.displayName)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(primaryText)
                        .lineLimit(1)
                }
                
                Spacer(minLength: 20)
                
                Rectangle()
                    .fill(dividerStroke)
                    .frame(height: 1)
                    .padding(.bottom, 14)
                
                // Clean 3-Column Structured Pass Metadata: STATUS / JOINED / ACCESS
                HStack(spacing: 0) {
                    self.passFieldCell(
                        label: "STATUS",
                        value: self.statusText,
                        showStatusDot: true,
                        accent: accent,
                        primary: primaryText,
                        muted: mutedText
                    )
                    
                    self.passFieldCell(
                        label: "JOINED",
                        value: self.joinedText,
                        showStatusDot: false,
                        accent: accent,
                        primary: primaryText,
                        muted: mutedText
                    )
                    
                    self.passFieldCell(
                        label: "ACCESS",
                        value: self.accessText,
                        showStatusDot: false,
                        accent: accent,
                        primary: primaryText,
                        muted: mutedText
                    )
                }
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 20)
        }
        .frame(width: 408, height: 246)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(accent.opacity(self.isHovered ? 0.52 : 0.28), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(self.theme.isLightSurface ? 0.10 : 0.28), radius: 16, y: 6)
    }
    
    
    private func passFieldCell(
        label: String,
        value: String,
        showStatusDot: Bool,
        accent: Color,
        primary: Color,
        muted: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(muted)
            
            HStack(spacing: 5) {
                if showStatusDot {
                    Circle()
                        .fill(accent)
                        .frame(width: 5.5, height: 5.5)
                }
                Text(value)
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(primary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
