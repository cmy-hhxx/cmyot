//
//  GlassFolderCardView.swift
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

enum GlassFolderTheme: String, CaseIterable, Codable, Sendable {
    
    case aurora
    case ember
    case dusk
    case glacier
    case verdant
    
    
    var prefersLightLabel: Bool {
        switch self {
            case .ember, .dusk: true
            case .aurora, .glacier, .verdant: false
        }
    }
    
    
    static func rotatingTheme(forIndex index: Int) -> GlassFolderTheme {
        let palette: [GlassFolderTheme] = [.aurora, .glacier, .dusk, .verdant, .ember]
        return palette[abs(index) % palette.count]
    }
}


struct GlassFolderSheetItem: Identifiable, Equatable, Sendable {
    
    let id: String
    let title: String
    let meta: String
    let accentHex: String
}


/// Generates cached procedural domain-warped fBm backplate artwork inspired by `glass-folder`.
nonisolated final class GlassFolderTextureGenerator: @unchecked Sendable {
    
    static let shared = GlassFolderTextureGenerator()
    
    private let lock = NSLock()
    private var cache: [GlassFolderTheme: NSImage] = [:]
    
    
    static func textureImage(for theme: GlassFolderTheme) -> NSImage {
        self.shared.cachedImage(for: theme)
    }
    
    
    private func cachedImage(for theme: GlassFolderTheme) -> NSImage {
        if let hit = self.lock.withLock({ self.cache[theme] }) {
            return hit
        }
        let generated = Self.renderTexture(for: theme, width: 170, height: 136)
        self.lock.withLock {
            self.cache[theme] = generated
        }
        return generated
    }
    
    
    // MARK: Domain-Warped fBm Synthesis
    
    private struct RGB {
        var r: Double
        var g: Double
        var b: Double
    }
    
    private struct TextureSpec {
        let palette: [RGB]
        let scale: Double
        let warp: Double
        let angle: Double
        let gloss: Double
        let veins: Double
        let streak: Bool
        let seed: UInt64
    }
    
    
    private static func spec(for theme: GlassFolderTheme) -> TextureSpec {
        func hex(_ h: UInt32) -> RGB {
            RGB(
                r: Double((h >> 16) & 0xFF) / 255.0,
                g: Double((h >> 8) & 0xFF) / 255.0,
                b: Double(h & 0xFF) / 255.0
            )
        }
        switch theme {
            case .aurora:
                return TextureSpec(
                    palette: [hex(0xF4EFE9), hex(0xE9C2B8), hex(0xC2433F), hex(0x2A1E2A), hex(0x22395E), hex(0x6F97C2), hex(0xE5EDF4)],
                    scale: 0.72, warp: 1.4, angle: -0.62, gloss: 0.18, veins: 0.25, streak: true, seed: 101
                )
            case .ember:
                return TextureSpec(
                    palette: [hex(0x07090C), hex(0x16252C), hex(0x3D5F68), hex(0x1A1416), hex(0xA3201A), hex(0xEF4A2B), hex(0xFF8A5C)],
                    scale: 0.62, warp: 3.2, angle: -0.50, gloss: 0.55, veins: 0.60, streak: false, seed: 202
                )
            case .dusk:
                return TextureSpec(
                    palette: [hex(0x120C18), hex(0x3E2850), hex(0x8F6C9C), hex(0x2B1A24), hex(0xB3502F), hex(0xEAB08A), hex(0xFBE7D2)],
                    scale: 0.68, warp: 3.6, angle: 0.80, gloss: 0.36, veins: 0.40, streak: false, seed: 303
                )
            case .glacier:
                return TextureSpec(
                    palette: [hex(0xF6F9FC), hex(0xDCE7F2), hex(0xAFC6DE), hex(0x6C8FB3), hex(0x3E638B), hex(0xB5CEE4), hex(0xEEF4FA)],
                    scale: 0.75, warp: 1.6, angle: -0.45, gloss: 0.24, veins: 0.20, streak: true, seed: 404
                )
            case .verdant:
                return TextureSpec(
                    palette: [hex(0xEFF2E7), hex(0xD3DFC1), hex(0x98B57C), hex(0x4F7043), hex(0x324B2C), hex(0xC2A55F), hex(0xF4EDCE)],
                    scale: 0.66, warp: 2.5, angle: 0.42, gloss: 0.30, veins: 0.35, streak: false, seed: 505
                )
        }
    }
    
    
    private static func mulberry32(_ seed: UInt64) -> () -> Double {
        var s = UInt32(truncatingIfNeeded: seed)
        return {
            s &+= 0x6D2B79F5
            var z = s
            z = (z ^ (z >> 15)) &* (z | 1)
            z ^= z &+ ((z ^ (z >> 7)) &* (z | 61))
            return Double(z ^ (z >> 14)) / Double(UInt32.max)
        }
    }
    
    
    private static func makePermutationTable(seed: UInt64) -> [Int] {
        let rand = mulberry32(seed)
        var p = Array(0..<256)
        for i in stride(from: 255, through: 1, by: -1) {
            let j = Int(floor(rand() * Double(i + 1)))
            p.swapAt(i, j)
        }
        return p + p
    }
    
    
    private static func gradNoise(_ x: Double, _ y: Double, perm: [Int]) -> Double {
        let xi = Int(floor(x)) & 255
        let yi = Int(floor(y)) & 255
        let xf = x - floor(x)
        let yf = y - floor(y)
        let u = xf * xf * (3 - 2 * xf)
        let v = yf * yf * (3 - 2 * yf)
        
        func grad(_ hash: Int, _ dx: Double, _ dy: Double) -> Double {
            switch hash & 3 {
                case 0: dx + dy
                case 1: -dx + dy
                case 2: dx - dy
                default: -dx - dy
            }
        }
        
        let aa = perm[perm[xi] + yi]
        let ab = perm[perm[xi] + yi + 1]
        let ba = perm[perm[xi + 1] + yi]
        let bb = perm[perm[xi + 1] + yi + 1]
        
        let x1 = grad(aa, xf, yf) + u * (grad(ba, xf - 1, yf) - grad(aa, xf, yf))
        let x2 = grad(ab, xf, yf - 1) + u * (grad(bb, xf - 1, yf - 1) - grad(ab, xf, yf - 1))
        return 0.5 + 0.5 * (x1 + v * (x2 - x1))
    }
    
    
    private static func fbm(_ xIn: Double, _ yIn: Double, perm: [Int]) -> Double {
        var x = xIn
        var y = yIn
        var value = 0.0
        var amp = 0.5
        let c = cos(0.55)
        let s = sin(0.55)
        for _ in 0..<4 {
            value += amp * gradNoise(x, y, perm: perm)
            let nx = c * x - s * y
            let ny = s * x + c * y
            x = nx * 2.02 + 13.1
            y = ny * 2.02 + 7.7
            amp *= 0.5
        }
        return value
    }
    
    
    private static func renderTexture(for theme: GlassFolderTheme, width: Int, height: Int) -> NSImage {
        let sp = Self.spec(for: theme)
        let perm = Self.makePermutationTable(seed: sp.seed)
        let cosA = cos(sp.angle)
        let sinA = sin(sp.angle)
        
        let hw = width / 2 + 2
        let hh = height / 2 + 2
        var field = Array(repeating: 0.0, count: hw * hh)
        var qMag = Array(repeating: 0.0, count: hw * hh)
        
        for py in 0..<hh {
            for px in 0..<hw {
                var u = (Double(px) / Double(max(1, hw - 2)) - 0.5) * 2.2 * sp.scale
                var v = (Double(py) / Double(max(1, hh - 2)) - 0.5) * 2.2 * sp.scale
                let rx = u * cosA - v * sinA
                let ry = u * sinA + v * cosA
                u = sp.streak ? rx * 0.14 : rx
                v = sp.streak ? ry * 2.20 : ry
                
                let qx = fbm(u, v, perm: perm)
                let qy = fbm(u + 5.2, v + 1.3, perm: perm)
                let rxp = fbm(u + sp.warp * qx + 1.7, v + sp.warp * qy + 9.2, perm: perm)
                let ryp = fbm(u + sp.warp * qx + 8.3, v + sp.warp * qy + 2.8, perm: perm)
                let f = fbm(u + sp.warp * rxp, v + sp.warp * ryp, perm: perm)
                let idx = py * hw + px
                field[idx] = f
                qMag[idx] = hypot(qx, qy)
            }
        }
        
        let sorted = field.sorted()
        let lo = sorted[max(0, Int(Double(sorted.count) * 0.02))]
        let hi = sorted[min(sorted.count - 1, Int(Double(sorted.count) * 0.98))]
        let span = max(0.001, hi - lo)
        
        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        let stops = sp.palette
        
        for y in 0..<height {
            let fy = Double(y) * 0.5 + 0.5
            let iy = min(hh - 2, max(1, Int(floor(fy))))
            for x in 0..<width {
                let fx = Double(x) * 0.5 + 0.5
                let ix = min(hw - 2, max(1, Int(floor(fx))))
                let f = max(0.0, min(1.0, (field[iy * hw + ix] - lo) / span))
                let q = qMag[iy * hw + ix]
                
                let scaled = f * Double(stops.count - 1)
                let seg = min(stops.count - 2, max(0, Int(floor(scaled))))
                let t = scaled - Double(seg)
                let c0 = stops[seg]
                let c1 = stops[seg + 1]
                var r = c0.r + (c1.r - c0.r) * t
                var g = c0.g + (c1.g - c0.g) * t
                var b = c0.b + (c1.b - c0.b) * t
                
                let gx = field[iy * hw + min(hw - 1, ix + 1)] - field[iy * hw + max(0, ix - 1)]
                let gy = field[min(hh - 1, iy + 1) * hw + ix] - field[max(0, iy - 1) * hw + ix]
                let nz = 0.25
                let normLen = max(0.001, sqrt(gx * gx + gy * gy + nz * nz))
                let nd = max(0.0, (-gx * -0.55 - gy * -0.65 + nz * 0.52) / normLen)
                let specBoost = pow(nd, 12.0) * sp.gloss * 0.65
                let veinDarken = sp.veins * max(0.0, 1.0 - abs(q - 0.58) * 9.0) * 0.28
                let ripple = sin(f * 32.0 + q * 18.0) * 0.025
                
                r = max(0, min(1, r * (1.0 - veinDarken) + specBoost + ripple))
                g = max(0, min(1, g * (1.0 - veinDarken) + specBoost + ripple))
                b = max(0, min(1, b * (1.0 - veinDarken) + specBoost + ripple))
                
                let outIdx = (y * width + x) * 4
                pixels[outIdx] = UInt8((r * 255.0).rounded())
                pixels[outIdx + 1] = UInt8((g * 255.0).rounded())
                pixels[outIdx + 2] = UInt8((b * 255.0).rounded())
                pixels[outIdx + 3] = 255
            }
        }
        
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        if let provider = CGDataProvider(data: Data(pixels) as CFData),
           let cgImage = CGImage(
               width: width,
               height: height,
               bitsPerComponent: 8,
               bitsPerPixel: 32,
               bytesPerRow: width * 4,
               space: colorSpace,
               bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
               provider: provider,
               decode: nil,
               shouldInterpolate: true,
               intent: .defaultIntent
           )
        {
            return NSImage(cgImage: cgImage, size: NSSize(width: width, height: height))
        }
        return NSImage(size: NSSize(width: width, height: height))
    }
}


// MARK: - Folder Geometries (Scaled from 340×272 Spec)

private struct GlassFolderBackShape: Shape {
    
    func path(in rect: CGRect) -> Path {
        let sx = rect.width / 340.0
        let sy = rect.height / 272.0
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * sx, y: rect.minY + y * sy)
        }
        
        var p = Path()
        p.move(to: pt(0, 56))
        p.addQuadCurve(to: pt(22, 34), control: pt(0, 34))
        p.addLine(to: pt(146, 34))
        p.addCurve(to: pt(198, 0), control1: pt(170, 34), control2: pt(172, 0))
        p.addLine(to: pt(318, 0))
        p.addQuadCurve(to: pt(340, 22), control: pt(340, 0))
        p.addLine(to: pt(340, 250))
        p.addQuadCurve(to: pt(318, 272), control: pt(340, 272))
        p.addLine(to: pt(22, 272))
        p.addQuadCurve(to: pt(0, 250), control: pt(0, 272))
        p.closeSubpath()
        return p
    }
}


private struct GlassFolderFrontShape: Shape {
    
    func path(in rect: CGRect) -> Path {
        let sx = rect.width / 340.0
        let sy = rect.height / 198.0
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * sx, y: rect.minY + y * sy)
        }
        
        var p = Path()
        p.move(to: pt(0, 22))
        p.addQuadCurve(to: pt(22, 0), control: pt(0, 0))
        p.addLine(to: pt(118, 0))
        p.addCurve(to: pt(172, 32), control1: pt(144, 0), control2: pt(146, 32))
        p.addLine(to: pt(318, 32))
        p.addQuadCurve(to: pt(340, 54), control: pt(340, 32))
        p.addLine(to: pt(340, 176))
        p.addQuadCurve(to: pt(318, 198), control: pt(340, 198))
        p.addLine(to: pt(22, 198))
        p.addQuadCurve(to: pt(0, 176), control: pt(0, 198))
        p.closeSubpath()
        return p
    }
}


private struct GlassFolderBlurBackdrop: NSViewRepresentable {
    
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .popover
        view.blendingMode = .withinWindow
        view.state = .active
        return view
    }
    
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}


/// Tactile layered translucent folder card inspired by `glass-folder`.
struct GlassFolderCardView: View {
    
    let title: String
    let count: Int
    let theme: GlassFolderTheme
    let sheets: [GlassFolderSheetItem]
    let isSelected: Bool
    var onSelect: () -> Void
    var onAdd: (() -> Void)? = nil
    var onRename: (() -> Void)? = nil
    var onOpenAll: (() -> Void)? = nil
    var onDeleteGroup: (() -> Void)? = nil
    
    @State private var isHovered = false
    @State private var plusSpinDegrees: Double = 0
    @Environment(\.colorScheme) private var colorScheme
    
    
    private var liftFactor: Double {
        if self.isSelected { return 1.0 }
        if self.isHovered { return 0.56 }
        return 0.0
    }
    
    private var hingeDegrees: Double {
        if self.isSelected { return -20 }
        if self.isHovered { return -10 }
        return 0
    }
    
    
    var body: some View {
        let cardWidth: CGFloat = 152
        let folderHeight: CGFloat = cardWidth * (272.0 / 340.0)   // ~121.6
        let frontHeight: CGFloat = cardWidth * (198.0 / 340.0)    // ~88.5
        let headroom: CGFloat = 20
        
        ZStack(alignment: .bottom) {
            // 1. Backplate + Procedural Domain-Warped fBm Texture
            Button(action: self.onSelect) {
                ZStack(alignment: .topLeading) {
                    Image(nsImage: GlassFolderTextureGenerator.textureImage(for: self.theme))
                        .resizable()
                        .interpolation(.high)
                        .scaledToFill()
                        .frame(width: cardWidth, height: folderHeight)
                        .clipShape(GlassFolderBackShape())
                        .overlay(
                            GlassFolderBackShape()
                                .stroke(
                                    Color.white.opacity(self.isSelected ? 0.55 : 0.25),
                                    lineWidth: self.isSelected ? 1.5 : 0.8
                                )
                        )
                        .shadow(
                            color: Color.black.opacity(self.colorScheme == .dark ? 0.34 : 0.14),
                            radius: self.isHovered || self.isSelected ? 12 : 6,
                            y: self.isHovered || self.isSelected ? 6 : 3
                        )
                }
            }
            .buttonStyle(.plain)
            .pointerStyle(.link)
            .zIndex(1)
            
            // 2. Stacked Translucent Paper Sheets (up to 4 latest items inside this folder)
            let shownSheets = Array(self.sheets.prefix(4).reversed())
            ZStack(alignment: .bottom) {
                ForEach(Array(shownSheets.enumerated()), id: \.element.id) { idx, sheet in
                    let reverseIdx = shownSheets.count - 1 - idx
                    let baseOffset = CGFloat(reverseIdx) * 4.5
                    let openSpread = CGFloat(reverseIdx) * (self.isSelected ? 10.5 : (self.isHovered ? 6.5 : 1.0))
                    let fanAngle = Double(reverseIdx - shownSheets.count / 2) * (self.isSelected ? 3.2 : (self.isHovered ? 1.4 : 0.3))
                    let rise = -8.0 - baseOffset - openSpread - (self.isSelected ? 14 : (self.isHovered ? 6 : 0))
                    
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color(nsColor: .textBackgroundColor))
                        .overlay(
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 4) {
                                    Circle()
                                        .fill(Color(hexString: sheet.accentHex))
                                        .frame(width: 5, height: 5)
                                    Text(sheet.title)
                                        .font(.system(size: 9.5, weight: .semibold))
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)
                                }
                                Text(sheet.meta)
                                    .font(.system(size: 8, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 8)
                            .padding(.top, 5)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.75)
                        )
                        .shadow(color: Color.black.opacity(0.08), radius: 3, y: 1.5)
                        .frame(width: cardWidth * 0.80, height: frontHeight * 0.74)
                        .rotationEffect(.degrees(fanAngle), anchor: .bottom)
                        .offset(y: rise)
                }
            }
            .allowsHitTesting(false)
            .zIndex(5)
            
            // 3. Frosted 3D-Hinged Glass Front Pocket + Labels + Action Affordances
            Button(action: self.onSelect) {
                ZStack(alignment: .bottomLeading) {
                    GlassFolderFrontShape()
                        .fill(.clear)
                        .background(
                            GlassFolderBlurBackdrop()
                                .clipShape(GlassFolderFrontShape())
                                .opacity(0.86)
                        )
                        .overlay(
                            GlassFolderFrontShape()
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            Color.white.opacity(self.colorScheme == .dark ? 0.16 : 0.48),
                                            Color.white.opacity(self.colorScheme == .dark ? 0.04 : 0.14),
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                        )
                        .overlay(
                            GlassFolderFrontShape()
                                .stroke(
                                    LinearGradient(
                                        colors: [
                                            Color.white.opacity(self.isSelected ? 0.88 : 0.56),
                                            Color.white.opacity(0.14),
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: self.isSelected ? 1.5 : 1.0
                                )
                        )
                        .shadow(color: Color.black.opacity(0.14), radius: 6, y: -2)
                    
                    // Label + Monospace item count anchored inside front glass pocket
                    VStack(alignment: .leading, spacing: 2) {
                        Text(self.title)
                            .font(.system(size: 13.5, weight: .semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        
                        Text("\(self.count) 篇")
                            .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 10)
                }
                .frame(width: cardWidth, height: frontHeight)
                .contentShape(GlassFolderFrontShape())
            }
            .buttonStyle(.plain)
            .pointerStyle(.link)
            .rotation3DEffect(
                .degrees(self.hingeDegrees),
                axis: (x: 1, y: 0, z: 0),
                anchor: .bottom,
                perspective: 0.45
            )
            .zIndex(10)
            
            // 4. Floating Easy-Click Action Buttons (+ Create / ... Menu)
            HStack(spacing: 4) {
                Spacer(minLength: 0)
                
                if let onAdd = self.onAdd {
                    Button {
                        withAnimation(.spring(response: 0.45, dampingFraction: 0.65)) {
                            self.plusSpinDegrees += 90
                        }
                        onAdd()
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 10.5, weight: .bold))
                            .foregroundStyle(.primary)
                            .rotationEffect(.degrees(self.plusSpinDegrees))
                            .frame(width: 24, height: 24)
                            .background(.ultraThinMaterial, in: Circle())
                            .overlay(Circle().strokeBorder(Color.white.opacity(0.35), lineWidth: 0.75))
                    }
                    .buttonStyle(.plain)
                    .pointerStyle(.link)
                    .help(AppLanguage.text("在此新建", en: "Create inside folder"))
                }
                
                if self.onRename != nil || self.onOpenAll != nil || self.onDeleteGroup != nil {
                    Menu {
                        if let onOpenAll = self.onOpenAll, self.count > 0 {
                            Button(AppLanguage.text("全部在编辑器打开", en: "Open All in Editor")) {
                                onOpenAll()
                            }
                        }
                        if let onRename = self.onRename {
                            Button(AppLanguage.text("重命名分组", en: "Rename Group")) {
                                onRename()
                            }
                        }
                        if let onDeleteGroup = self.onDeleteGroup {
                            Divider()
                            Button(AppLanguage.text("解散分组", en: "Ungroup"), role: .destructive) {
                                onDeleteGroup()
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.primary)
                            .frame(width: 24, height: 24)
                            .background(.ultraThinMaterial, in: Circle())
                            .overlay(Circle().strokeBorder(Color.white.opacity(0.35), lineWidth: 0.75))
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .pointerStyle(.link)
                }
            }
            .padding(.horizontal, 8)
            .padding(.bottom, frontHeight - 28)
            .zIndex(14)
        }
        .frame(width: cardWidth, height: folderHeight + headroom, alignment: .bottom)
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(
                    self.isSelected ? Color.accentColor.opacity(0.75) : Color.clear,
                    lineWidth: 2
                )
                .frame(width: cardWidth + 4, height: folderHeight + 4)
                .offset(y: headroom * 0.5)
                .allowsHitTesting(false)
        )
        .animation(.spring(response: 0.40, dampingFraction: 0.76), value: self.isHovered)
        .animation(.spring(response: 0.40, dampingFraction: 0.76), value: self.isSelected)
        .onHover { hovering in
            self.isHovered = hovering
        }
    }
}
