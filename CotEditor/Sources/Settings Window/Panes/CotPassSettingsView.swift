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
            case .explorer: "Free"
            case .pro, .founder: "FULL"
        }
    }
    
    
    var summaryLabel: String {
        switch self {
            case .explorer: "Free"
            case .pro, .founder: "FULL"
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


// MARK: - Curated Pass Finishes (Fluted Glass Palettes)

nonisolated struct FlutedRGB: Sendable, Equatable {
    let r: Double
    let g: Double
    let b: Double
    
    var swiftUIColor: Color {
        Color(red: self.r, green: self.g, blue: self.b)
    }
}

/// 5-stop optical density ramp for the animated Fluted Glass fluid shader.
nonisolated struct FlutedGlassPalette: Sendable, Equatable {
    let base: FlutedRGB
    let light: FlutedRGB
    let mid: FlutedRGB
    let deep: FlutedRGB
    let midnight: FlutedRGB
    
    /// Exact LeiBox Blue Fluted Glass palette (`#F4F4F4 -> #A8CCE3 -> #1A7ABA -> #042247 -> #020616`).
    static let cobaltBlue = FlutedGlassPalette(
        base: FlutedRGB(r: 0.957, g: 0.957, b: 0.957),
        light: FlutedRGB(r: 0.660, g: 0.800, b: 0.890),
        mid: FlutedRGB(r: 0.100, g: 0.480, b: 0.730),
        deep: FlutedRGB(r: 0.015, g: 0.135, b: 0.280),
        midnight: FlutedRGB(r: 0.008, g: 0.025, b: 0.087)
    )
    
    static let pineEmerald = FlutedGlassPalette(
        base: FlutedRGB(r: 0.953, g: 0.965, b: 0.957),
        light: FlutedRGB(r: 0.624, g: 0.847, b: 0.769),
        mid: FlutedRGB(r: 0.122, g: 0.541, b: 0.404),
        deep: FlutedRGB(r: 0.031, g: 0.204, b: 0.153),
        midnight: FlutedRGB(r: 0.012, g: 0.067, b: 0.051)
    )
    
    static let amberGold = FlutedGlassPalette(
        base: FlutedRGB(r: 0.969, g: 0.957, b: 0.933),
        light: FlutedRGB(r: 0.945, g: 0.812, b: 0.627),
        mid: FlutedRGB(r: 0.820, g: 0.490, b: 0.141),
        deep: FlutedRGB(r: 0.290, g: 0.141, b: 0.031),
        midnight: FlutedRGB(r: 0.086, g: 0.039, b: 0.012)
    )
    
    static let nebulaViolet = FlutedGlassPalette(
        base: FlutedRGB(r: 0.957, g: 0.949, b: 0.973),
        light: FlutedRGB(r: 0.773, g: 0.714, b: 0.910),
        mid: FlutedRGB(r: 0.427, g: 0.306, b: 0.761),
        deep: FlutedRGB(r: 0.133, g: 0.071, b: 0.302),
        midnight: FlutedRGB(r: 0.043, g: 0.020, b: 0.102)
    )
    
    static let signalCrimson = FlutedGlassPalette(
        base: FlutedRGB(r: 0.969, g: 0.949, b: 0.953),
        light: FlutedRGB(r: 0.941, g: 0.706, b: 0.729),
        mid: FlutedRGB(r: 0.800, g: 0.200, b: 0.267),
        deep: FlutedRGB(r: 0.290, g: 0.051, b: 0.086),
        midnight: FlutedRGB(r: 0.086, g: 0.016, b: 0.027)
    )
    
    static let auroraTeal = FlutedGlassPalette(
        base: FlutedRGB(r: 0.949, g: 0.965, b: 0.969),
        light: FlutedRGB(r: 0.635, g: 0.843, b: 0.875),
        mid: FlutedRGB(r: 0.118, g: 0.533, b: 0.600),
        deep: FlutedRGB(r: 0.031, g: 0.200, b: 0.239),
        midnight: FlutedRGB(r: 0.012, g: 0.063, b: 0.078)
    )
}


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
    let flutedPalette: FlutedGlassPalette
    
    
    static let allThemes: [CotPassTheme] = [
        CotPassTheme(
            id: 0,
            title: "蔚蓝",
            subtitle: "COBALT",
            matrixColorHex: "#4AA8E8",
            accentColorHex: "#E8F3FB",
            backgroundTopHex: "#042247",
            backgroundBottomHex: "#020616",
            mascotName: "蔚蓝",
            bitmap: ["........", "........", "........", "........", "........", "........"],
            flutedPalette: .cobaltBlue
        ),
        CotPassTheme(
            id: 1,
            title: "松烟",
            subtitle: "PINE",
            matrixColorHex: "#44C997",
            accentColorHex: "#E8ECE9",
            backgroundTopHex: "#083427",
            backgroundBottomHex: "#03110D",
            mascotName: "松烟",
            bitmap: ["........", "........", "........", "........", "........", "........"],
            flutedPalette: .pineEmerald
        ),
        CotPassTheme(
            id: 2,
            title: "琥珀",
            subtitle: "AMBER",
            matrixColorHex: "#E5A93C",
            accentColorHex: "#FDE6B8",
            backgroundTopHex: "#4A2408",
            backgroundBottomHex: "#160A03",
            mascotName: "琥珀",
            bitmap: ["........", "........", "........", "........", "........", "........"],
            flutedPalette: .amberGold
        ),
        CotPassTheme(
            id: 3,
            title: "星紫",
            subtitle: "VIOLET",
            matrixColorHex: "#9A84EB",
            accentColorHex: "#EAE8F5",
            backgroundTopHex: "#22124D",
            backgroundBottomHex: "#0B051A",
            mascotName: "星紫",
            bitmap: ["........", "........", "........", "........", "........", "........"],
            flutedPalette: .nebulaViolet
        ),
        CotPassTheme(
            id: 4,
            title: "绯红",
            subtitle: "CRIMSON",
            matrixColorHex: "#E6525C",
            accentColorHex: "#F2EAEA",
            backgroundTopHex: "#4A0D16",
            backgroundBottomHex: "#160407",
            mascotName: "绯红",
            bitmap: ["........", "........", "........", "........", "........", "........"],
            flutedPalette: .signalCrimson
        ),
        CotPassTheme(
            id: 5,
            title: "青黛",
            subtitle: "TEAL",
            matrixColorHex: "#36B5C9",
            accentColorHex: "#E5F5F7",
            backgroundTopHex: "#08333D",
            backgroundBottomHex: "#031014",
            mascotName: "青黛",
            bitmap: ["........", "........", "........", "........", "........", "........"],
            flutedPalette: .auroraTeal
        ),
    ]
    
    
    var isLightSurface: Bool {
        false
    }
    
    
    var pairedStudioPalette: StudioPaletteID {
        switch self.id {
            case 0: .oceanCobalt
            case 1: .pineCeladon
            case 2: .amberEspresso
            case 3: .ultraViolet
            case 4: .signalCrimson
            case 5: .nordFrost
            default: .oceanCobalt
        }
    }
    
    
    static func resolve(index: Int) -> CotPassTheme {
        let safe = ((index % Self.allThemes.count) + Self.allThemes.count) % Self.allThemes.count
        return Self.allThemes[safe]
    }
    
    
    static func themeIndex(for studioPalette: StudioPaletteID) -> Int {
        switch studioPalette {
            case .oceanCobalt: 0
            case .pineCeladon, .matchaParchment: 1
            case .amberEspresso, .terracottaClay: 2
            case .ultraViolet: 3
            case .signalCrimson, .sakuraQuartz: 4
            case .nordFrost, .graphiteMono: 5
        }
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
    
    var contourField: [Float] { self.activeField }
    
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
    @State private var isCardHovered = false
    
    
    private var theme: CotPassTheme {
        CotPassTheme.resolve(index: self.styleIndex)
    }
    
    private var joinedText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy.MM.dd"
        return formatter.string(from: self.profileManager.activeProfile.createdAt)
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
                isHovered: self.isCardHovered
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
                        let ux = max(0, min(1, pt.x / 424.0))
                        let uy = max(0, min(1, pt.y / 256.0))
                        self.hoverPoint = UnitPoint(x: ux, y: uy)
                        let nx = (ux - 0.5) * 2.0
                        let ny = (uy - 0.5) * 2.0
                        self.tiltY = max(-6.0, min(6.0, nx * 5.6))
                        self.tiltX = max(-6.0, min(6.0, -ny * 4.6))
                    case .ended:
                        self.isCardHovered = false
                        self.tiltX = 0
                        self.tiltY = 0
                        self.hoverPoint = UnitPoint(x: 0.5, y: 0.5)
                }
            }
            
            // Minimal Fluted Glass Prism Colorway Swatches
            HStack(spacing: 10) {
                ForEach(CotPassTheme.allThemes) { option in
                    let isSelected = (option.id == self.theme.id)
                    let swatch = option.flutedPalette.mid.swiftUIColor
                    let deep = option.flutedPalette.deep.swiftUIColor
                    
                    Button {
                        withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.24)) {
                            self.styleIndex = option.id
                        }
                        CotLocalDatabase.shared.set("\(option.id)", forKey: CotLocalDatabase.ConfigKey.cotPassStyleIndex)
                    } label: {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [option.flutedPalette.light.swiftUIColor, swatch, deep],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: isSelected ? 16 : 14, height: isSelected ? 16 : 14)
                                .overlay(
                                    Circle()
                                        .strokeBorder(Color.white.opacity(isSelected ? 0.90 : 0.35), lineWidth: isSelected ? 1.5 : 0.75)
                                )
                            
                            if isSelected {
                                Text(option.title)
                                    .font(.system(size: 11.5, weight: .semibold))
                                    .foregroundStyle(.primary)
                                    .fixedSize(horizontal: true, vertical: false)
                            }
                        }
                        .padding(.horizontal, isSelected ? 10 : 6)
                        .frame(height: 28)
                        .background(
                            Capsule()
                                .fill(isSelected ? swatch.opacity(self.colorScheme == .dark ? 0.24 : 0.14) : Color.clear)
                        )
                        .overlay(
                            Capsule()
                                .strokeBorder(isSelected ? swatch.opacity(0.55) : Color.clear, lineWidth: 1)
                        )
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .pointerStyle(.link)
                    .help(option.title)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(self.colorScheme == .dark ? Color.white.opacity(0.055) : Color.black.opacity(0.035))
            )
            .overlay(
                Capsule()
                    .strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.75)
            )
            
            Spacer(minLength: 12)
        }
        .frame(maxWidth: .infinity)
        .onAppear {
            self.loadPassState()
        }
        .onChange(of: activeProfile.id) { _, _ in
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
        
        let licenseKey = db.string(forKey: CotLocalDatabase.ConfigKey.cotPassLicenseKey)
        self.accessTier = CotPassLicense.validate(licenseKey) ?? .explorer
    }
}


// MARK: - Blue Fluted Glass Backdrop (leibox.pantoria.cn/docs/animations/blue-fluted-glass)

/// Faithfully reproduces the LeiBox Blue Fluted Glass fragment shader in CPU-vectorized Swift:
/// - Seamless 28-second periodic organic cobalt/Prussian/ice-blue fluid field (`trunk`, `crown`, `base`, `hole`)
/// - Vertical fluted glass refraction (`ribCount = 44`) with quadratic vertical lens bend
/// - 5-tap vertical frosted diffusion & specular facet sheen on deep-blue ridges
nonisolated enum BlueFlutedGlassRenderer {
    
    static let periodSeconds: Double = 28.0
    static let defaultWidth: Int = 176
    static let defaultHeight: Int = 106
    static let defaultRibCount: Double = 44.0
    
    private static let colorSpace = CGColorSpaceCreateDeviceRGB()
    
    @inline(__always)
    private static func smoothstep(_ edge0: Double, _ edge1: Double, _ x: Double) -> Double {
        let t = max(0.0, min(1.0, (x - edge0) / (edge1 - edge0)))
        return t * t * (3.0 - 2.0 * t)
    }
    
    @inline(__always)
    private static func blob(
        px: Double, py: Double,
        cx: Double, cy: Double,
        invRx: Double, invRy: Double,
        cosA: Double, sinA: Double
    ) -> Double {
        let dx = px - cx
        let dy = py - cy
        let qx = (cosA * dx - sinA * dy) * invRx
        let qy = (sinA * dx + cosA * dy) * invRy
        return exp(-(qx * qx + qy * qy))
    }
    
    /// Renders one frame of the Fluted Glass field at `time` (seconds) using `palette` into an RGBA `CGImage`.
    static func renderFrame(
        time: Double,
        palette: FlutedGlassPalette = .cobaltBlue,
        width: Int = Self.defaultWidth,
        height: Int = Self.defaultHeight,
        ribCount: Double = Self.defaultRibCount
    ) -> CGImage? {
        guard width > 0, height > 0 else { return nil }
        
        let wrapped = time.truncatingRemainder(dividingBy: Self.periodSeconds)
        let phase = (wrapped < 0 ? wrapped + Self.periodSeconds : wrapped) * (2.0 * .pi / Self.periodSeconds)
        let s = sin(phase)
        let c = cos(phase)
        let s2 = sin(2.0 * phase)
        let twoPhase = 2.0 * phase
        
        // Precompute per-frame blob centers, inverse radii, and rotation trig
        let trunkCx = 0.52 + 0.15 * s - 0.07 * s2
        let trunkCy = 0.76
        let trunkInvRx = 1.0 / 0.235
        let trunkInvRy = 1.0 / 0.46
        let trunkRot = -0.12 - 0.52 * s
        let trunkCos = cos(trunkRot)
        let trunkSin = sin(trunkRot)
        
        let crownCx = 0.77 - 0.55 * s
        let crownCy = 0.20 - 0.10 * s2
        let crownInvRx = 1.0 / 0.235
        let crownInvRy = 1.0 / 0.23
        let crownRot = -0.50 + 0.45 * s
        let crownCos = cos(crownRot)
        let crownSin = sin(crownRot)
        
        let holeCx = 0.85 - 0.55 * s
        let holeCy = 0.59 - 0.13 * s
        let holeInvRx = 1.0 / (0.19 + 0.025 * c)
        let holeInvRy = 1.0 / 0.32
        let holeRot = 0.10 + 0.50 * s
        let holeCos = cos(holeRot)
        let holeSin = sin(holeRot)
        
        // Precompute per-column fluted rib geometry & edge sheen
        var colRib = [Double](repeating: 0, count: width)
        var colRefrX = [Double](repeating: 0, count: width)
        var colRefrDy = [Double](repeating: 0, count: width)
        var colSheenFactor = [Double](repeating: 0, count: width)
        var colBaseY = [Double](repeating: 0, count: width)
        
        let invW = 1.0 / Double(width)
        let invH = 1.0 / Double(height)
        
        for x in 0..<width {
            let u = (Double(x) + 0.5) * invW
            let scaled = u * ribCount
            let rib = (scaled - floor(scaled)) - 0.5
            let rx = u + rib * 0.018
            let dy = (rib * rib - 0.0833) * 0.034
            let edge = pow(abs(rib) * 2.0, 10.0)
            colRib[x] = rib
            colRefrX[x] = rx
            colRefrDy[x] = dy
            colSheenFactor[x] = rib * 0.65 + edge * 0.24
            colBaseY[x] = 1.045 - 0.17 * rx + 0.075 * sin(rx * 5.0 + twoPhase)
        }
        
        @inline(__always)
        func sampleDensity(rx: Double, py: Double, baseYHint: Double) -> Double {
            let px = rx + 0.025 * sin(py * 7.0 + twoPhase)
            let trunk = Self.blob(px: px, py: py, cx: trunkCx, cy: trunkCy, invRx: trunkInvRx, invRy: trunkInvRy, cosA: trunkCos, sinA: trunkSin)
            let crown = Self.blob(px: px, py: py, cx: crownCx, cy: crownCy, invRx: crownInvRx, invRy: crownInvRy, cosA: crownCos, sinA: crownSin)
            let baseY = 1.045 - 0.17 * px + 0.075 * sin(px * 5.0 + twoPhase)
            let bd = (py - baseY) / 0.092
            let base = exp(-(bd * bd))
            let hole = Self.blob(px: px, py: py, cx: holeCx, cy: holeCy, invRx: holeInvRx, invRy: holeInvRy, cosA: holeCos, sinA: holeSin)
            _ = baseYHint
            return (trunk + 0.56 * crown + 0.90 * base) * (1.0 - 0.78 * hole)
        }
        
        let p0 = palette.base
        let p1 = palette.light
        let p2 = palette.mid
        let p3 = palette.deep
        let p4 = palette.midnight
        
        let byteCount = width * height * 4
        var pixels = [UInt8](repeating: 255, count: byteCount)
        
        pixels.withUnsafeMutableBufferPointer { buf in
            guard let ptr = buf.baseAddress else { return }
            
            for y in 0..<height {
                // Top-to-bottom UV (0 = top, 1 = bottom, matching WebGL canvas orientation)
                let v = (Double(y) + 0.5) * invH
                let rowOffset = y * width * 4
                
                for x in 0..<width {
                    let rx = colRefrX[x]
                    let ry = v + colRefrDy[x]
                    let baseHint = colBaseY[x]
                    
                    // 5-tap vertical frost softening matching reference shader weights
                    let d0 = sampleDensity(rx: rx, py: ry, baseYHint: baseHint)
                    let d1 = sampleDensity(rx: rx, py: ry + 0.025, baseYHint: baseHint)
                    let d2 = sampleDensity(rx: rx, py: ry - 0.025, baseYHint: baseHint)
                    let d3 = sampleDensity(rx: rx, py: ry + 0.055, baseYHint: baseHint)
                    let d4 = sampleDensity(rx: rx, py: ry - 0.055, baseYHint: baseHint)
                    let density = d0 * 0.40 + (d1 + d2) * 0.24 + (d3 + d4) * 0.06
                    
                    // 5-stop sRGB palette ramp
                    var r = p0.r
                    var g = p0.g
                    var b = p0.b
                    
                    let k1 = Self.smoothstep(0.015, 0.20, density)
                    r += (p1.r - r) * k1
                    g += (p1.g - g) * k1
                    b += (p1.b - b) * k1
                    
                    let k2 = Self.smoothstep(0.16, 0.49, density)
                    r += (p2.r - r) * k2
                    g += (p2.g - g) * k2
                    b += (p2.b - b) * k2
                    
                    let k3 = Self.smoothstep(0.40, 0.73, density)
                    r += (p3.r - r) * k3
                    g += (p3.g - g) * k3
                    b += (p3.b - b) * k3
                    
                    let k4 = Self.smoothstep(0.62, 0.93, density)
                    r += (p4.r - r) * k4
                    g += (p4.g - g) * k4
                    b += (p4.b - b) * k4
                    
                    // Chroma-aware specular rib facet sheen across every fluted palette
                    let maxC = max(r, max(g, b))
                    let minC = min(r, min(g, b))
                    let luma = (r + g + b) / 3.0
                    let chromaMask = (1.0 - luma) * Self.smoothstep(0.025, 0.20, maxC - minC)
                    let sheen = colSheenFactor[x] * chromaMask
                    r = max(0.0, min(1.0, r + (0.018 + 0.014 * p1.r) * sheen))
                    g = max(0.0, min(1.0, g + (0.018 + 0.014 * p1.g) * sheen))
                    b = max(0.0, min(1.0, b + (0.018 + 0.014 * p1.b) * sheen))
                    
                    let offset = rowOffset + x * 4
                    ptr[offset]     = UInt8(r * 255.0 + 0.5)
                    ptr[offset + 1] = UInt8(g * 255.0 + 0.5)
                    ptr[offset + 2] = UInt8(b * 255.0 + 0.5)
                    ptr[offset + 3] = 255
                }
            }
        }
        
        let data = Data(pixels)
        guard let provider = CGDataProvider(data: data as CFData) else { return nil }
        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: Self.colorSpace,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        )
    }
}


// MARK: - Cached LeiBox Fluted Glass Prism View (Zero-Lag Seamless Loop)

@MainActor
final class LeiBoxFlutedPrismCache {
    
    static let shared = LeiBoxFlutedPrismCache()
    
    private struct CacheKey: Hashable {
        let themeID: Int
        let width: Int
        let height: Int
        let ribCountInt: Int
    }
    
    private var loops: [CacheKey: [CGImage]] = [:]
    private var posters: [CacheKey: CGImage] = [:]
    private var inFlight: Set<CacheKey> = []
    
    
    func posterFrame(for theme: CotPassTheme, width: Int, height: Int, ribCount: Double) -> CGImage? {
        let key = CacheKey(themeID: theme.id, width: width, height: height, ribCountInt: Int(ribCount.rounded()))
        if let existing = self.loops[key]?.first ?? self.posters[key] {
            return existing
        }
        let img = BlueFlutedGlassRenderer.renderFrame(
            time: 4.2,
            palette: theme.flutedPalette,
            width: width,
            height: height,
            ribCount: ribCount
        )
        if let img {
            self.posters[key] = img
        }
        return img
    }
    
    
    func cachedFrames(for theme: CotPassTheme, width: Int, height: Int, ribCount: Double) -> [CGImage]? {
        let key = CacheKey(themeID: theme.id, width: width, height: height, ribCountInt: Int(ribCount.rounded()))
        return self.loops[key]
    }
    
    
    func warmFrames(
        for theme: CotPassTheme,
        width: Int,
        height: Int,
        ribCount: Double,
        frameCount: Int = 36,
        onReady: @escaping @MainActor ([CGImage]) -> Void
    ) {
        let key = CacheKey(themeID: theme.id, width: width, height: height, ribCountInt: Int(ribCount.rounded()))
        if let existing = self.loops[key] {
            onReady(existing)
            return
        }
        guard !self.inFlight.contains(key) else { return }
        self.inFlight.insert(key)
        
        let palette = theme.flutedPalette
        let period = BlueFlutedGlassRenderer.periodSeconds
        Task.detached(priority: .utility) {
            var rendered: [CGImage] = []
            rendered.reserveCapacity(frameCount)
            for idx in 0..<frameCount {
                let t = (Double(idx) / Double(frameCount)) * period
                if let img = BlueFlutedGlassRenderer.renderFrame(
                    time: t,
                    palette: palette,
                    width: width,
                    height: height,
                    ribCount: ribCount
                ) {
                    rendered.append(img)
                }
            }
            await MainActor.run {
                self.inFlight.remove(key)
                if !rendered.isEmpty {
                    self.loops[key] = rendered
                    onReady(rendered)
                }
            }
        }
    }
}


/// Faithful LeiBox Fluted Glass Prism view (`leibox.pantoria.cn/docs/animations/blue-fluted-glass`)
/// supporting all 6 colorways with pre-baked O(1) GPU-friendly loop playback.
struct LeiBoxFlutedPrismView: View {
    
    let theme: CotPassTheme
    var renderWidth: Int = 180
    var renderHeight: Int = 108
    var ribCount: Double = 44.0
    var animate: Bool = true
    var specularPoint: UnitPoint = UnitPoint(x: 0.5, y: 0.5)
    var isHovered: Bool = false
    
    @State private var loopFrames: [CGImage] = []
    @State private var loadedThemeID: Int = -1
    
    
    var body: some View {
        let fallbackFrame = LeiBoxFlutedPrismCache.shared.posterFrame(
            for: self.theme,
            width: self.renderWidth,
            height: self.renderHeight,
            ribCount: self.ribCount
        )
        let shouldAnimate = self.animate && !AnimationConstants.isReducedMotionEnabled && !self.loopFrames.isEmpty
        
        ZStack {
            if shouldAnimate {
                TimelineView(.animation(minimumInterval: 1.0 / 20.0)) { context in
                    let frames = self.loopFrames
                    let period = BlueFlutedGlassRenderer.periodSeconds
                    let raw = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: period)
                    let norm = (raw < 0 ? raw + period : raw) / period
                    let idx = min(frames.count - 1, max(0, Int(norm * Double(frames.count))))
                    Image(decorative: frames[idx], scale: 1.0)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFill()
                }
            } else if let fallbackFrame {
                Image(decorative: fallbackFrame, scale: 1.0)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFill()
            } else {
                LinearGradient(
                    colors: [
                        self.theme.flutedPalette.mid.swiftUIColor,
                        self.theme.flutedPalette.deep.swiftUIColor,
                        self.theme.flutedPalette.midnight.swiftUIColor,
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
            
            // Subtle optical prism specular highlight tracking pointer
            RadialGradient(
                colors: [
                    Color.white.opacity(self.isHovered ? 0.28 : 0.08),
                    self.theme.flutedPalette.light.swiftUIColor.opacity(self.isHovered ? 0.14 : 0.0),
                    Color.clear,
                ],
                center: self.specularPoint,
                startRadius: 4,
                endRadius: 210
            )
            .blendMode(.screen)
            .allowsHitTesting(false)
        }
        .onAppear {
            self.loadLoopIfNeeded()
        }
        .onChange(of: self.theme.id) { _, _ in
            self.loadLoopIfNeeded()
        }
    }
    
    
    private func loadLoopIfNeeded() {
        let targetID = self.theme.id
        if let cached = LeiBoxFlutedPrismCache.shared.cachedFrames(
            for: self.theme,
            width: self.renderWidth,
            height: self.renderHeight,
            ribCount: self.ribCount
        ) {
            self.loopFrames = cached
            self.loadedThemeID = targetID
            return
        }
        self.loopFrames = []
        self.loadedThemeID = targetID
        LeiBoxFlutedPrismCache.shared.warmFrames(
            for: self.theme,
            width: self.renderWidth,
            height: self.renderHeight,
            ribCount: self.ribCount
        ) { frames in
            if self.theme.id == targetID {
                self.loopFrames = frames
            }
        }
    }
}


// MARK: - Swiss-Gallery × Instant-Film Collector Pass Engine (7 Visual Principles)

/// Synthesizes a museum-grade Collector Pass uniting all 7 visual principles with zero wireframe clutter:
/// 1. `shades of off-white`: Porcelain Chalk ticket stub + perforated Raw Cotton tear-off + Recessed Limestone passe-partout
/// 2. `digital impressionism`: broken-color painterly impasto tiles inside the framed gallery window
/// 3. `lomo imagery`: instant-film Polaroid portrait mount with analog corner vignette & warm amber sun-kiss flare
/// 4. `generative art`: harmonic curl-flow vector field orienting the painterly impasto mosaic
/// 5. `morphing objects`: soft-shaded volumetric metaball light sculptures breathing without harsh outlines
/// 6. `ASCII and pixels`: Swiss-grid quantized portrait plaque + binary pixel telemetry strip
/// 7. `sketch and scribble`: fine 45° lithograph graphite hatching, corner `+` crop marks & Polaroid-chin ink paraph
nonisolated enum CotPassArtEngine {
    
    enum ASCIIPixelCell: Equatable, Sendable {
        case empty
        case pixelBlock(Double)
        case ascii(Character, Double)
    }
    
    enum ImpastoRole: Sendable {
        case porcelainHighlight
        case pastelWash
        case mineralAccent
        case warmOchre
    }
    
    struct ImpastoTile: Sendable {
        let u: Double
        let v: Double
        let angle: Double
        let width: CGFloat
        let height: CGFloat
        let role: ImpastoRole
    }
    
    private final class StockCache: @unchecked Sendable {
        let cache = NSCache<NSString, CGImage>()
    }
    
    private static let stockCache = StockCache()
    private static let colorSpace = CGColorSpaceCreateDeviceRGB()
    private static let asciiRamp: [Character] = Array("·:+*#")
    
    
    static func deterministicSeed(from text: String) -> Int {
        var hash: UInt64 = 14695981039346656037
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 1099511628211
        }
        return Int(truncatingIfNeeded: hash & 0x7FFF_FFFF)
    }
    
    
    private static func seededUnit(seed: Int, index: Int) -> Double {
        var n = UInt64(bitPattern: Int64(seed &* 747796405 &+ index &* 2891336453 &+ 277803737))
        n = (n ^ (n >> 28)) &* 277803737
        n = n ^ (n >> 22)
        return Double(n & 0xFFFF) / 65535.0
    }
    
    
    static func perforationX(in size: CGSize) -> CGFloat {
        (size.width * 0.575).rounded()
    }
    
    
    static func artWindowRect(in size: CGSize) -> CGRect {
        let seamX = Self.perforationX(in: size)
        let ultra = size.height < 165
        let padX: CGFloat = ultra ? 9 : 13
        let padY: CGFloat = ultra ? 10 : 14
        return CGRect(
            x: seamX + padX,
            y: padY,
            width: max(32, size.width - seamX - padX * 2),
            height: max(32, size.height - padY * 2)
        )
    }
    
    
    /// Renders & caches the tactile archival multi-tone off-white card stock at 2x Retina scale.
    static func cachedStockImage(theme: CotPassTheme, serialCode: String, size: CGSize) -> CGImage? {
        let w = max(64, Int((size.width * 2.0).rounded()))
        let h = max(48, Int((size.height * 2.0).rounded()))
        let cacheKey = "v2|\(theme.id)|\(serialCode)|\(w)x\(h)" as NSString
        if let hit = Self.stockCache.cache.object(forKey: cacheKey) {
            return hit
        }
        
        guard let ctx = CGContext(
            data: nil,
            width: w,
            height: h,
            bitsPerComponent: 8,
            bytesPerRow: w * 4,
            space: Self.colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        
        let wf = CGFloat(w)
        let hf = CGFloat(h)
        let scale: CGFloat = 2.0
        let seamX = Self.perforationX(in: size) * scale
        let seed = Self.deterministicSeed(from: "\(theme.id):\(serialCode)")
        
        // 1A. Left Identity Stub — Porcelain Chalk (#FCFBF8 -> #F6F2EA)
        ctx.saveGState()
        ctx.clip(to: CGRect(x: 0, y: 0, width: seamX, height: hf))
        let leftStops = [
            CGColor(srgbRed: 0.988, green: 0.984, blue: 0.973, alpha: 1.0),
            CGColor(srgbRed: 0.965, green: 0.949, blue: 0.918, alpha: 1.0),
        ] as CFArray
        if let leftGrad = CGGradient(colorsSpace: Self.colorSpace, colors: leftStops, locations: [0.0, 1.0]) {
            ctx.drawLinearGradient(leftGrad, start: CGPoint(x: 0, y: hf), end: CGPoint(x: seamX, y: 0), options: [])
        }
        ctx.restoreGState()
        
        // 1B. Right Gallery Stub — Raw Warm Cotton (#F5F0E6 -> #EBE4D5)
        ctx.saveGState()
        ctx.clip(to: CGRect(x: seamX, y: 0, width: wf - seamX, height: hf))
        let rightStops = [
            CGColor(srgbRed: 0.961, green: 0.941, blue: 0.902, alpha: 1.0),
            CGColor(srgbRed: 0.922, green: 0.894, blue: 0.835, alpha: 1.0),
        ] as CFArray
        if let rightGrad = CGGradient(colorsSpace: Self.colorSpace, colors: rightStops, locations: [0.0, 1.0]) {
            ctx.drawLinearGradient(rightGrad, start: CGPoint(x: seamX, y: hf), end: CGPoint(x: wf, y: 0), options: [])
        }
        ctx.restoreGState()
        
        // 1C. Recessed Museum Passe-Partout Window (#FAF7F0 inner ground with #E2DACB bevel)
        let swiftArtRect = Self.artWindowRect(in: size)
        let cgArtRect = CGRect(
            x: swiftArtRect.minX * scale,
            y: hf - swiftArtRect.maxY * scale,
            width: swiftArtRect.width * scale,
            height: swiftArtRect.height * scale
        )
        let artCorner = (size.height < 165 ? 9.0 : 11.0) * scale
        let outerMatPath = CGPath(
            roundedRect: cgArtRect.insetBy(dx: -2, dy: -2),
            cornerWidth: artCorner + 2,
            cornerHeight: artCorner + 2,
            transform: nil
        )
        ctx.addPath(outerMatPath)
        ctx.setFillColor(CGColor(srgbRed: 0.890, green: 0.863, blue: 0.808, alpha: 0.85))
        ctx.fillPath()
        
        let innerMatPath = CGPath(roundedRect: cgArtRect, cornerWidth: artCorner, cornerHeight: artCorner, transform: nil)
        ctx.addPath(innerMatPath)
        ctx.setFillColor(CGColor(srgbRed: 0.982, green: 0.973, blue: 0.949, alpha: 1.0))
        ctx.fillPath()
        
        // 1D. Ticket Perforation Micro-Dots & Edge Notches along `seamX`
        let dotStep: CGFloat = 11.0
        var py: CGFloat = 14.0
        while py < hf - 12.0 {
            ctx.setFillColor(CGColor(srgbRed: 1.0, green: 0.996, blue: 0.985, alpha: 0.85))
            ctx.fillEllipse(in: CGRect(x: seamX - 1.1, y: py - 1.8, width: 2.2, height: 2.2))
            ctx.setFillColor(CGColor(srgbRed: 0.56, green: 0.52, blue: 0.46, alpha: 0.22))
            ctx.fillEllipse(in: CGRect(x: seamX - 1.1, y: py - 1.1, width: 2.2, height: 2.2))
            py += dotStep
        }
        let notchR: CGFloat = size.height < 165 ? 6.5 : 8.5
        ctx.setFillColor(CGColor(srgbRed: 0.84, green: 0.81, blue: 0.75, alpha: 0.65))
        ctx.fillEllipse(in: CGRect(x: seamX - notchR, y: -notchR, width: notchR * 2, height: notchR * 2))
        ctx.fillEllipse(in: CGRect(x: seamX - notchR, y: hf - notchR, width: notchR * 2, height: notchR * 2))
        
        // 1E. Ultra-fine Cotton Paper Tooth (subtle luminance grain, never muddy)
        for gIdx in 0..<180 {
            let gx = Self.seededUnit(seed: seed &+ 91, index: gIdx * 2) * Double(wf)
            let gy = Self.seededUnit(seed: seed &+ 91, index: gIdx * 2 + 1) * Double(hf)
            let bright = (gIdx % 2 == 0)
            ctx.setFillColor(
                bright
                    ? CGColor(srgbRed: 1.0, green: 0.995, blue: 0.98, alpha: 0.30)
                    : CGColor(srgbRed: 0.42, green: 0.39, blue: 0.34, alpha: 0.028)
            )
            ctx.fill(CGRect(x: gx, y: gy, width: 1.3, height: 1.3))
        }
        
        guard let image = ctx.makeImage() else { return nil }
        Self.stockCache.cache.setObject(image, forKey: cacheKey)
        return image
    }
    
    
    /// Smooth continuous harmonic perimeter for soft-filled morphing sculptural cores (never stroked as wireframes).
    static func morphingObjectPath(center: CGPoint, baseRadius: CGFloat, phase: Double) -> Path {
        let vertexCount = 64
        var path = Path()
        for i in 0...vertexCount {
            let theta = (Double(i % vertexCount) / Double(vertexCount)) * Double.pi * 2.0
            let mod = 1.0
                + 0.11 * cos(2.0 * theta + phase)
                + 0.065 * sin(3.0 * theta - 1.15 * phase)
            let r = baseRadius * CGFloat(mod)
            let pt = CGPoint(
                x: center.x + r * CGFloat(cos(theta)),
                y: center.y + r * CGFloat(sin(theta))
            )
            if i == 0 {
                path.move(to: pt)
            } else {
                path.addLine(to: pt)
            }
        }
        path.closeSubpath()
        return path
    }
    
    
    /// Evaluates normalized volumetric metaball light intensity in `[0, 1]` across the gallery art window.
    static func morphingSculptureDensity(u: Double, v: Double, phase: Double) -> Double {
        let c1x = 0.52 + 0.13 * cos(phase * 0.75)
        let c1y = 0.40 + 0.11 * sin(phase * 0.62)
        let c2x = 0.44 - 0.12 * sin(phase * 0.58 + 1.1)
        let c2y = 0.67 + 0.09 * cos(phase * 0.82 + 0.6)
        
        let d1Sq = (u - c1x) * (u - c1x) / 0.14 + (v - c1y) * (v - c1y) / 0.16
        let d2Sq = (u - c2x) * (u - c2x) / 0.12 + (v - c2y) * (v - c2y) / 0.13
        let field = exp(-d1Sq) + 0.78 * exp(-d2Sq)
        return min(1.0, max(0.0, field * 0.74))
    }
    
    
    /// Precomputes a harmonious mosaic of painterly impasto tiles oriented along a generative curl-flow field.
    static func computeImpastoTiles(seed: Int, in artRect: CGRect) -> [ImpastoTile] {
        guard artRect.width > 24, artRect.height > 24 else { return [] }
        let ultra = artRect.height < 140
        let cols = ultra ? 7 : 9
        let rows = ultra ? 8 : 11
        let freqU = 1.6 + Double(seed % 5) * 0.22
        let freqV = 1.8 + Double((seed >> 3) % 5) * 0.20
        let phase0 = Double((seed >> 7) % 360) * .pi / 180.0
        
        var tiles: [ImpastoTile] = []
        tiles.reserveCapacity(cols * rows)
        
        for r in 0..<rows {
            for c in 0..<cols {
                let idx = r * cols + c
                let jitterU = (Self.seededUnit(seed: seed, index: idx * 3 + 1) - 0.5) * 0.65 / Double(cols)
                let jitterV = (Self.seededUnit(seed: seed, index: idx * 3 + 2) - 0.5) * 0.65 / Double(rows)
                let u = min(0.94, max(0.06, (Double(c) + 0.5) / Double(cols) + jitterU))
                let v = min(0.94, max(0.06, (Double(r) + 0.5) / Double(rows) + jitterV))
                
                // Generative curl-harmonic tangent orientation
                let angle = 0.58 * sin(u * .pi * freqU + phase0) * cos(v * .pi * freqV)
                    - 0.34 * cos((u + v) * .pi * 1.25 - phase0 * 0.5)
                
                let cellW = artRect.width / CGFloat(cols)
                let cellH = artRect.height / CGFloat(rows)
                let scaleVar = CGFloat(0.85 + Self.seededUnit(seed: seed, index: idx * 5 + 3) * 0.45)
                let tileW = max(6, cellW * 1.18 * scaleVar)
                let tileH = max(3.5, cellH * 0.56 * scaleVar)
                
                let roll = Self.seededUnit(seed: seed, index: idx * 7 + 4)
                let role: ImpastoRole = if roll < 0.24 {
                    .porcelainHighlight
                } else if roll < 0.58 {
                    .pastelWash
                } else if roll < 0.84 {
                    .mineralAccent
                } else {
                    .warmOchre
                }
                
                tiles.append(ImpastoTile(u: u, v: v, angle: angle, width: tileW, height: tileH, role: role))
            }
        }
        return tiles
    }
    
    
    /// Quantizes `BrandLinePassEngine`'s avatar contour field onto a crisp Swiss ASCII + Micro-Pixel matrix.
    static func buildASCIIPixelMatrix(
        from contourField: [Float],
        cols: Int = 10,
        rows: Int = 6
    ) -> [[ASCIIPixelCell]] {
        let g = BrandLinePassEngine.gridSize
        guard contourField.count == g * g, cols > 0, rows > 0 else { return [] }
        
        var matrix: [[ASCIIPixelCell]] = []
        matrix.reserveCapacity(rows)
        
        for r in 0..<rows {
            var rowCells: [ASCIIPixelCell] = []
            rowCells.reserveCapacity(cols)
            let gy = Int(((0.16 + 0.68 * (Double(r) + 0.5) / Double(rows)) * Double(g - 1)).rounded())
            for c in 0..<cols {
                let gx = Int(((0.46 + 0.48 * (Double(c) + 0.5) / Double(cols)) * Double(g - 1)).rounded())
                let idx = min(g - 1, max(0, gy)) * g + min(g - 1, max(0, gx))
                let val = Double(contourField[idx])
                
                if val < 0.14 {
                    rowCells.append(.empty)
                } else if val > 0.62 || (val > 0.40 && (r + c).isMultiple(of: 2)) {
                    rowCells.append(.pixelBlock(min(1.0, val)))
                } else {
                    let rampIdx = min(Self.asciiRamp.count - 1, max(0, Int((val * Double(Self.asciiRamp.count)).rounded(.down))))
                    rowCells.append(.ascii(Self.asciiRamp[rampIdx], val))
                }
            }
            matrix.append(rowCells)
        }
        return matrix
    }
    
    
    /// Clean architect's 45° parallel pencil lithograph shading in the lower-left shadow corner of the art window.
    static func lithographHatchPath(in artRect: CGRect, seed: Int) -> Path {
        var path = Path()
        let count = 8
        let spacing: CGFloat = artRect.height < 140 ? 4.2 : 5.4
        let maxSpan = min(artRect.width, artRect.height) * 0.36
        let originX = artRect.minX + 5
        let originY = artRect.maxY - 5
        
        for idx in 0..<count {
            let d = CGFloat(idx) * spacing
            guard d < maxSpan else { break }
            let jitter = CGFloat(Self.seededUnit(seed: seed, index: idx + 61) - 0.5) * 1.2
            path.move(to: CGPoint(x: originX, y: originY - d + jitter))
            path.addLine(to: CGPoint(x: originX + d - jitter, y: originY))
        }
        return path
    }
    
    
    /// Minimalist single-stroke artist's ink paraph signed on the off-white Polaroid bottom chin.
    static func calligraphicParaphPath(in chinRect: CGRect, seed: Int) -> Path {
        var path = Path()
        let w = min(22, chinRect.width * 0.52)
        let h = max(3.0, chinRect.height * 0.48)
        let startX = chinRect.maxX - w - 3
        let midY = chinRect.midY + 0.5
        let tilt = CGFloat(Self.seededUnit(seed: seed, index: 88) - 0.5) * 1.4
        
        path.move(to: CGPoint(x: startX, y: midY + h * 0.35))
        path.addCurve(
            to: CGPoint(x: startX + w * 0.62, y: midY - h * 0.35 + tilt),
            control1: CGPoint(x: startX + w * 0.18, y: midY - h * 0.65),
            control2: CGPoint(x: startX + w * 0.42, y: midY + h * 0.55)
        )
        path.addQuadCurve(
            to: CGPoint(x: startX + w, y: midY + 0.4),
            control: CGPoint(x: startX + w * 0.82, y: midY - h * 0.45)
        )
        return path
    }
}


// MARK: - LeiBox Fluted Glass Prism Collector Pass Card (Zero Ellipsis)

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
    var cardSize: CGSize = CGSize(width: 424, height: 256)
    var statusLabelTitle: String = "STATUS"
    
    private var compact: Bool {
        self.cardSize.height < 210
    }
    
    private var ultraCompact: Bool {
        self.cardSize.height < 165
    }
    
    
    var body: some View {
        let corner: CGFloat = self.compact ? 14 : 18
        let padH: CGFloat = self.ultraCompact ? 16 : (self.compact ? 20 : 26)
        let padV: CGFloat = self.ultraCompact ? 12 : (self.compact ? 16 : 22)
        let avatarSide: CGFloat = self.ultraCompact ? 34 : (self.compact ? 42 : 52)
        
        ZStack(alignment: .topLeading) {
            // Layer 0: Authentic LeiBox Fluted Glass Prism fluid refraction
            LeiBoxFlutedPrismView(
                theme: self.theme,
                renderWidth: self.compact ? 160 : 216,
                renderHeight: self.compact ? 96 : 130,
                ribCount: 44.0,
                animate: true,
                specularPoint: self.specularPoint,
                isHovered: self.isHovered
            )
            .frame(width: self.cardSize.width, height: self.cardSize.height)
            .clipped()
            
            // Layer 1: Subtle vertical contrast scrim so crisp white typography stays legible across every colorway
            LinearGradient(
                colors: [
                    self.theme.flutedPalette.midnight.swiftUIColor.opacity(0.28),
                    self.theme.flutedPalette.deep.swiftUIColor.opacity(0.18),
                    self.theme.flutedPalette.midnight.swiftUIColor.opacity(0.58),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .allowsHitTesting(false)
            
            // Layer 2: Full-width spacious identity layout — zero truncation, zero ellipsis
            VStack(alignment: .leading, spacing: 0) {
                // Header: Brand mark & colorway badge
                HStack(alignment: .center, spacing: 10) {
                    Text("COTEDITOR PASS")
                        .font(.system(size: self.ultraCompact ? 9.5 : 11, weight: .bold, design: .monospaced))
                        .tracking(1.2)
                        .foregroundStyle(Color.white.opacity(0.92))
                        .fixedSize(horizontal: true, vertical: false)
                    
                    Spacer(minLength: 8)
                    
                    Text("\(self.theme.title) · \(self.theme.subtitle)")
                        .font(.system(size: self.ultraCompact ? 9 : 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(0.88))
                        .fixedSize(horizontal: true, vertical: false)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 3.5)
                        .background(Color.white.opacity(0.14), in: Capsule())
                        .overlay(
                            Capsule()
                                .strokeBorder(Color.white.opacity(0.24), lineWidth: 0.75)
                        )
                }
                
                Spacer(minLength: self.ultraCompact ? 8 : 16)
                
                // Center: Avatar + full Display Name + full Serial Code (never clipped with ...)
                HStack(alignment: .center, spacing: self.ultraCompact ? 12 : 16) {
                    ZStack {
                        if let avatarImage = self.avatarImage {
                            Image(nsImage: avatarImage)
                                .resizable()
                                .interpolation(.high)
                                .scaledToFill()
                                .frame(width: avatarSide, height: avatarSide)
                                .clipped()
                        } else {
                            UserAvatarCircleView(profile: self.profile, size: avatarSide, customImage: nil)
                                .frame(width: avatarSide, height: avatarSide)
                                .clipped()
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: self.ultraCompact ? 9 : 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: self.ultraCompact ? 9 : 12, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.55), lineWidth: 1.2)
                    )
                    .shadow(color: Color.black.opacity(0.28), radius: 8, y: 3)
                    
                    VStack(alignment: .leading, spacing: self.ultraCompact ? 3 : 5) {
                        Text(self.profile.displayName)
                            .font(.system(size: self.ultraCompact ? 15 : (self.compact ? 18 : 22), weight: .bold))
                            .foregroundStyle(Color.white)
                            .minimumScaleFactor(0.72)
                            .fixedSize(horizontal: false, vertical: true)
                        
                        Text("NO. \(self.serialCode)")
                            .font(.system(size: self.ultraCompact ? 9.5 : 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(Color.white.opacity(0.78))
                            .fixedSize(horizontal: true, vertical: false)
                    }
                    
                    Spacer(minLength: 0)
                }
                
                Spacer(minLength: self.ultraCompact ? 8 : 16)
                
                Rectangle()
                    .fill(Color.white.opacity(0.20))
                    .frame(height: 0.75)
                    .padding(.bottom, self.ultraCompact ? 8 : 12)
                
                // Footer: 3 clean full-width metadata cells (no ellipsis)
                HStack(alignment: .bottom, spacing: 12) {
                    self.prismFieldCell(
                        label: self.statusLabelTitle,
                        value: self.statusText,
                        showStatusDot: true
                    )
                    
                    Spacer(minLength: 8)
                    
                    self.prismFieldCell(
                        label: "JOINED",
                        value: self.joinedText,
                        showStatusDot: false
                    )
                    
                    Spacer(minLength: 8)
                    
                    self.prismFieldCell(
                        label: "ACCESS",
                        value: self.accessText,
                        showStatusDot: false
                    )
                }
            }
            .padding(.horizontal, padH)
            .padding(.vertical, padV)
            .frame(width: self.cardSize.width, height: self.cardSize.height, alignment: .topLeading)
        }
        .frame(width: self.cardSize.width, height: self.cardSize.height)
        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(self.isHovered ? 0.56 : 0.34),
                            Color.white.opacity(0.10),
                            self.theme.flutedPalette.light.swiftUIColor.opacity(0.32),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.0
                )
        )
        .shadow(
            color: self.theme.flutedPalette.deep.swiftUIColor.opacity(self.isHovered ? 0.36 : 0.22),
            radius: self.isHovered ? 22 : 14,
            y: self.isHovered ? 10 : 6
        )
    }
    
    
    private func prismFieldCell(
        label: String,
        value: String,
        showStatusDot: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: self.ultraCompact ? 2 : 3) {
            Text(label)
                .font(.system(size: self.ultraCompact ? 8 : 9.5, weight: .semibold, design: .monospaced))
                .tracking(0.6)
                .foregroundStyle(Color.white.opacity(0.66))
                .fixedSize(horizontal: true, vertical: false)
            
            HStack(spacing: 5) {
                if showStatusDot {
                    Circle()
                        .fill(self.theme.flutedPalette.light.swiftUIColor)
                        .frame(width: 5.5, height: 5.5)
                }
                Text(value)
                    .font(.system(size: self.ultraCompact ? 10.5 : (self.compact ? 12 : 13.5), weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.white)
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
    }
}
