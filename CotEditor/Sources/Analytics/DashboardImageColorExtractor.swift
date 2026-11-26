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

/// Extracted average, dominant, accent, and optional distinct secondary tones from the user's Dashboard background image.
nonisolated struct DashboardImageTone: Equatable, Sendable {
    let average: HeroRegionTone
    let dominant: HeroRegionTone
    let accent: HeroRegionTone
    let secondary: HeroRegionTone?
    
    init(
        average: HeroRegionTone,
        dominant: HeroRegionTone,
        accent: HeroRegionTone,
        secondary: HeroRegionTone? = nil
    ) {
        self.average = average
        self.dominant = dominant
        self.accent = accent
        self.secondary = secondary
    }
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
    
    
    /// Adjusts an extracted image dominant tone in HSV space so it achieves crisp contrast against `cardRGB`
    /// without degenerating into muddy olive or flat gray.
    static func harmonizedAccentRGB(
        from dominant: HeroRegionTone,
        against cardRGB: (Double, Double, Double),
        isDark: Bool
    ) -> (Double, Double, Double)? {
        guard dominant.saturation >= 0.14 else { return nil }
        let cardTone = HeroRegionTone(red: cardRGB.0, green: cardRGB.1, blue: cardRGB.2)
        var (h, s, v) = Self.rgbToHSV((dominant.red, dominant.green, dominant.blue))
        s = s < 0.22 ? min(0.55, s * 1.15) : min(0.84, max(s, isDark ? 0.50 : 0.56))
        v = isDark ? max(0.68, min(0.92, v)) : min(0.66, max(0.36, v))
        
        for _ in 0..<12 {
            let candidate = Self.hsvToRGB((h, s, v))
            let current = HeroRegionTone(red: candidate.0, green: candidate.1, blue: candidate.2)
            if Self.contrastRatio(current, cardTone) >= 3.6 {
                return candidate
            }
            if isDark {
                v = min(0.96, v + 0.04)
                s = max(0.38, s - 0.02)
            } else {
                v = max(0.24, v - 0.045)
                s = min(0.88, s + 0.015)
            }
        }
        return Self.hsvToRGB((h, s, v))
    }
    
    
    /// Derives a 4-color perceptually distinct harmonic series from `accentRGB`, preferring an extracted
    /// secondary hue when present and separating remaining channels cleanly across hues.
    static func harmonicSeriesRGB(
        from accentRGB: (Double, Double, Double),
        secondary: HeroRegionTone? = nil,
        against cardRGB: (Double, Double, Double)? = nil,
        isDark: Bool
    ) -> [(Double, Double, Double)] {
        let (h0, rawS, rawV) = Self.rgbToHSV(accentRGB)
        let baseSat = min(0.82, max(0.54, rawS))
        let baseVal = isDark ? min(0.90, max(0.68, rawV)) : min(0.66, max(0.42, rawV))
        let primary = Self.hsvToRGB((h0, baseSat, baseVal))
        
        let resolvedCard = cardRGB ?? (isDark ? (0.11, 0.12, 0.14) : (0.985, 0.988, 0.992))
        var color1: (Double, Double, Double)?
        var hue1Offset = 44.0 / 360.0
        
        if let secondary,
           let secHarmonized = Self.harmonizedAccentRGB(from: secondary, against: resolvedCard, isDark: isDark)
        {
            let (hSec, sSec, vSec) = Self.rgbToHSV(secHarmonized)
            let diff = abs(hSec - h0)
            let circularDiff = min(diff, 1.0 - diff)
            if circularDiff >= 36.0 / 360.0 {
                color1 = Self.hsvToRGB((
                    hSec,
                    min(0.82, max(0.48, sSec)),
                    isDark ? min(0.90, max(0.66, vSec)) : min(0.68, max(0.42, vSec))
                ))
                hue1Offset = circularDiff
            }
        }
        
        func shifted(_ deg: Double, sat: Double, valOffset: Double) -> (Double, Double, Double) {
            var nh = (h0 + deg / 360.0).truncatingRemainder(dividingBy: 1.0)
            if nh < 0 { nh += 1.0 }
            let ns = min(0.84, max(0.42, sat))
            let nv = min(0.92, max(0.36, baseVal + valOffset))
            return Self.hsvToRGB((nh, ns, nv))
        }
        
        let resolvedColor1 = color1 ?? shifted(44.0, sat: max(0.50, baseSat - 0.04), valOffset: isDark ? 0.03 : 0.04)
        let angle2 = abs(hue1Offset - (48.0 / 360.0)) < 0.06 ? 142.0 : -48.0
        let resolvedColor2 = shifted(angle2, sat: max(0.48, baseSat - 0.06), valOffset: isDark ? -0.02 : 0.02)
        let resolvedColor3 = shifted(155.0, sat: min(0.66, max(0.44, baseSat - 0.10)), valOffset: isDark ? 0.04 : 0.05)
        
        return [primary, resolvedColor1, resolvedColor2, resolvedColor3]
    }
    
    
    /// Derives a 4-color multi-hue harmonic series from `accentRGB`.
    static func analogousSeriesRGB(
        from accentRGB: (Double, Double, Double),
        isDark: Bool
    ) -> [(Double, Double, Double)] {
        Self.harmonicSeriesRGB(from: accentRGB, secondary: nil, against: nil, isDark: isDark)
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
        let side = 64
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
        
        var primaryHist = Self.makeHistogram(binCount: 36)
        var shadowHist = Self.makeHistogram(binCount: 36)
        
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
            
            let (hue, sat, val) = Self.rgbToHSV((r, g, b))
            guard sat >= 0.16, val >= 0.12, !(val > 0.97 && sat < 0.22) else { continue }
            let bin = min(35, max(0, Int(floor(hue * 36.0))))
            
            if val >= 0.26 {
                let lumCurve = pow(min(1.0, max(0.0, (val - 0.18) / 0.62)), 1.35)
                let popWeight = (sat * sat) * (0.06 + 0.94 * lumCurve)
                primaryHist.record(bin: bin, r: r, g: g, b: b, weight: popWeight)
            } else {
                let popWeight = sat * (0.35 + 0.65 * val)
                shadowHist.record(bin: bin, r: r, g: g, b: b, weight: popWeight)
            }
        }
        
        guard validCount > 0 else { return nil }
        let average = HeroRegionTone(
            red: sumR / validCount,
            green: sumG / validCount,
            blue: sumB / validCount
        )
        
        let activeHist = primaryHist.totalChromatic >= max(12, Int(validCount * 0.02)) ? primaryHist : shadowHist
        let picked = Self.selectPrimaryAndSecondaryBins(from: activeHist)
        let dominant = picked.primary ?? average
        return DashboardImageTone(
            average: average,
            dominant: dominant,
            accent: dominant,
            secondary: picked.secondary
        )
    }
    
    
    private struct HueHistogram {
        let binCount: Int
        var binPop: [Double]
        var binPixels: [Int]
        var binR: [Double]
        var binG: [Double]
        var binB: [Double]
        var totalChromatic: Int = 0
        
        mutating func record(bin: Int, r: Double, g: Double, b: Double, weight: Double) {
            self.binPop[bin] += weight
            self.binPixels[bin] += 1
            self.binR[bin] += r * weight
            self.binG[bin] += g * weight
            self.binB[bin] += b * weight
            self.totalChromatic += 1
        }
    }
    
    
    private static func makeHistogram(binCount: Int) -> HueHistogram {
        HueHistogram(
            binCount: binCount,
            binPop: [Double](repeating: 0, count: binCount),
            binPixels: [Int](repeating: 0, count: binCount),
            binR: [Double](repeating: 0, count: binCount),
            binG: [Double](repeating: 0, count: binCount),
            binB: [Double](repeating: 0, count: binCount)
        )
    }
    
    
    private static func selectPrimaryAndSecondaryBins(
        from hist: HueHistogram
    ) -> (primary: HeroRegionTone?, secondary: HeroRegionTone?) {
        func score(at bin: Int) -> Double {
            guard hist.binPixels[bin] > 0, hist.binPop[bin] > 0 else { return 0 }
            return hist.binPop[bin] * pow(Double(hist.binPixels[bin]), 0.30)
        }
        
        func tone(at bin: Int) -> HeroRegionTone? {
            let pop = hist.binPop[bin]
            guard pop > 0 else { return nil }
            return HeroRegionTone(red: hist.binR[bin] / pop, green: hist.binG[bin] / pop, blue: hist.binB[bin] / pop)
        }
        
        var bestBin = -1
        var bestScore = 0.0
        for b in 0..<hist.binCount {
            let s = score(at: b)
            if s > bestScore {
                bestScore = s
                bestBin = b
            }
        }
        guard bestBin >= 0, let primary = tone(at: bestBin) else {
            return (nil, nil)
        }
        
        let minSecondaryPixels = max(6, Int(Double(hist.totalChromatic) * 0.015))
        var secondBin = -1
        var secondScore = 0.0
        for b in 0..<hist.binCount where hist.binPixels[b] >= minSecondaryPixels {
            let rawDist = abs(b - bestBin)
            let circularDist = min(rawDist, hist.binCount - rawDist)
            guard circularDist >= 5 else { continue }
            let s = score(at: b)
            if s > secondScore {
                secondScore = s
                secondBin = b
            }
        }
        let secondary = secondBin >= 0 ? tone(at: secondBin) : nil
        return (primary, secondary)
    }
}
