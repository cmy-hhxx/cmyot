//
//  DashboardImageColorExtractor.swift
//
//  CotEditor
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

import CoreGraphics
import Foundation

/// Extracted average, dominant, and accent tones from the user's Dashboard background image.
nonisolated struct DashboardImageTone: Equatable, Sendable {
    let average: HeroRegionTone
    let dominant: HeroRegionTone
    let accent: HeroRegionTone
}


/// Pure off-main color extraction and mixing utilities for adapting the Dashboard palette to user media.
nonisolated enum DashboardImageColorExtractor {
    
    static func mixRGB(
        _ lhs: (Double, Double, Double),
        _ rhs: (Double, Double, Double),
        t: Double
    ) -> (Double, Double, Double) {
        let u = max(0.0, min(1.0, t))
        return (
            lhs.0 + (rhs.0 - lhs.0) * u,
            lhs.1 + (rhs.1 - lhs.1) * u,
            lhs.2 + (rhs.2 - lhs.2) * u
        )
    }
    
    
    static func mixTone(_ lhs: HeroRegionTone, _ rhs: HeroRegionTone, t: Double) -> HeroRegionTone {
        HeroRegionTone.interpolate(lhs, rhs, t: t)
    }
    
    
    static func contrastRatio(_ lhs: HeroRegionTone, _ rhs: HeroRegionTone) -> Double {
        let l1 = max(lhs.luminance, rhs.luminance)
        let l2 = min(lhs.luminance, rhs.luminance)
        return (l1 + 0.05) / (l2 + 0.05)
    }
    
    
    /// Adjusts an extracted image dominant tone so it achieves readable contrast against `cardRGB`
    /// while preserving the image's signature hue.
    static func harmonizedAccentRGB(
        from dominant: HeroRegionTone,
        against cardRGB: (Double, Double, Double),
        isDark: Bool
    ) -> (Double, Double, Double)? {
        guard dominant.saturation >= 0.14 else { return nil }
        let cardTone = HeroRegionTone(red: cardRGB.0, green: cardRGB.1, blue: cardRGB.2)
        var candidate = (dominant.red, dominant.green, dominant.blue)
        let targetTone: (Double, Double, Double) = isDark ? (0.94, 0.96, 1.0) : (0.04, 0.07, 0.12)
        for _ in 0..<8 {
            let current = HeroRegionTone(red: candidate.0, green: candidate.1, blue: candidate.2)
            if Self.contrastRatio(current, cardTone) >= 3.4 {
                return candidate
            }
            candidate = Self.mixRGB(candidate, targetTone, t: 0.22)
        }
        return candidate
    }
    
    
    /// Derives a 4-color analogous harmonic series from `accentRGB` (hue shifts 0°, -22°, +26°, -44°)
    /// so multi-series charts (Sankey, radial rose) match the user's uploaded backdrop instead of clashing.
    static func analogousSeriesRGB(
        from accentRGB: (Double, Double, Double),
        isDark: Bool
    ) -> [(Double, Double, Double)] {
        let (h, s, v) = Self.rgbToHSV(accentRGB)
        let baseSat = min(0.84, max(0.38, s))
        let baseVal = isDark ? min(0.92, max(0.64, v)) : min(0.76, max(0.42, v))
        let specs: [(dh: Double, ds: Double, dv: Double)] = [
            (0.0, 0.0, 0.0),
            (-22.0 / 360.0, -0.06, isDark ? 0.05 : 0.06),
            (26.0 / 360.0, -0.10, isDark ? -0.04 : -0.04),
            (-44.0 / 360.0, -0.16, isDark ? 0.08 : 0.10),
        ]
        return specs.map { spec in
            var nh = (h + spec.dh).truncatingRemainder(dividingBy: 1.0)
            if nh < 0 { nh += 1.0 }
            let ns = min(0.90, max(0.24, baseSat + spec.ds))
            let nv = min(0.94, max(0.32, baseVal + spec.dv))
            return Self.hsvToRGB((nh, ns, nv))
        }
    }
    
    
    private static func rgbToHSV(_ rgb: (Double, Double, Double)) -> (Double, Double, Double) {
        let r = max(0, min(1, rgb.0))
        let g = max(0, min(1, rgb.1))
        let b = max(0, min(1, rgb.2))
        let maxC = max(r, max(g, b))
        let minC = min(r, min(g, b))
        let delta = maxC - minC
        let s = maxC > 0.0001 ? delta / maxC : 0.0
        var h = 0.0
        if delta > 0.0001 {
            if maxC == r {
                h = ((g - b) / delta).truncatingRemainder(dividingBy: 6.0)
            } else if maxC == g {
                h = (b - r) / delta + 2.0
            } else {
                h = (r - g) / delta + 4.0
            }
            if h < 0 { h += 6.0 }
            h /= 6.0
        }
        return (h, s, maxC)
    }
    
    
    private static func hsvToRGB(_ hsv: (Double, Double, Double)) -> (Double, Double, Double) {
        let h = hsv.0 * 6.0
        let s = hsv.1
        let v = hsv.2
        let sector = Int(floor(h)) % 6
        let f = h - floor(h)
        let p = v * (1.0 - s)
        let q = v * (1.0 - f * s)
        let t = v * (1.0 - (1.0 - f) * s)
        switch sector {
            case 0: return (v, t, p)
            case 1: return (q, v, p)
            case 2: return (p, v, t)
            case 3: return (p, q, v)
            case 4: return (t, p, v)
            default: return (v, p, q)
        }
    }
    
    
    static func extract(from cgImage: CGImage) -> DashboardImageTone? {
        let side = 48
        let totalPixels = side * side
        var bytes = [UInt8](repeating: 0, count: totalPixels * 4)
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(
                data: &bytes,
                width: side,
                height: side,
                bitsPerComponent: 8,
                bytesPerRow: side * 4,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
              )
        else { return nil }
        
        ctx.interpolationQuality = .medium
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: side, height: side))
        
        var sumR = 0.0
        var sumG = 0.0
        var sumB = 0.0
        var validCount = 0.0
        
        let binCount = 24
        var binWeight = [Double](repeating: 0, count: binCount)
        var binR = [Double](repeating: 0, count: binCount)
        var binG = [Double](repeating: 0, count: binCount)
        var binB = [Double](repeating: 0, count: binCount)
        
        for i in 0..<totalPixels {
            let offset = i * 4
            let a = Double(bytes[offset + 3]) / 255.0
            guard a > 0.05 else { continue }
            let r = min(1.0, (Double(bytes[offset]) / 255.0) / a)
            let g = min(1.0, (Double(bytes[offset + 1]) / 255.0) / a)
            let b = min(1.0, (Double(bytes[offset + 2]) / 255.0) / a)
            
            sumR += r
            sumG += g
            sumB += b
            validCount += 1.0
            
            let maxC = max(r, max(g, b))
            let minC = min(r, min(g, b))
            let delta = maxC - minC
            let sat = maxC > 0.001 ? delta / maxC : 0.0
            let val = maxC
            guard sat >= 0.14, val >= 0.12, val <= 0.96, delta > 0.0001 else { continue }
            
            var hue = 0.0
            if maxC == r {
                hue = ((g - b) / delta).truncatingRemainder(dividingBy: 6.0)
            } else if maxC == g {
                hue = (b - r) / delta + 2.0
            } else {
                hue = (r - g) / delta + 4.0
            }
            if hue < 0 { hue += 6.0 }
            let normalizedHue = hue / 6.0
            let bin = min(binCount - 1, max(0, Int(floor(normalizedHue * Double(binCount)))))
            let weight = sat * (0.35 + 0.65 * val)
            binWeight[bin] += weight
            binR[bin] += r * weight
            binG[bin] += g * weight
            binB[bin] += b * weight
        }
        
        guard validCount > 0 else { return nil }
        let average = HeroRegionTone(
            red: sumR / validCount,
            green: sumG / validCount,
            blue: sumB / validCount
        )
        
        var bestBin = -1
        var bestWeight = 0.0
        for b in 0..<binCount where binWeight[b] > bestWeight {
            bestWeight = binWeight[b]
            bestBin = b
        }
        
        let dominant: HeroRegionTone
        if bestBin >= 0, bestWeight > 0 {
            dominant = HeroRegionTone(
                red: binR[bestBin] / bestWeight,
                green: binG[bestBin] / bestWeight,
                blue: binB[bestBin] / bestWeight
            )
        } else {
            dominant = average
        }
        
        let accent = Self.mixTone(dominant, average, t: 0.15)
        return DashboardImageTone(average: average, dominant: dominant, accent: accent)
    }
}
