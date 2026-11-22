//
//  HighlightColor+AppKit.swift
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

extension NSAttributedString.Key {
    
    /// Translucent background tint painted behind Notes-style highlighted passages.
    static let notesHighlightFillColor = NSAttributedString.Key("local.cmy.CotEditor.NotesHighlightFillColor")
    
    /// Foreground ink tint applied to Notes-style highlighted passages without disturbing syntax tokens.
    static let notesHighlightTextColor = NSAttributedString.Key("local.cmy.CotEditor.NotesHighlightTextColor")
}


extension HighlightColor {
    
    /// Dynamic foreground text tint matching the Notes Text Color palette (`#eeeeef`, `#f38aa7`, `#e6cf67`, `#77f172`, `#80e9e6`, `#9c86f3`, `#b17ee6`, `#e68dd4`, plus `hsl(h, 76%, 72%)` on dark themes).
    var noteTextColor: NSColor {
        
        self.dynamicColor(light: self.lightTextTint, dark: self.darkTextTint)
    }
    
    
    /// Translucent multiline selection wash drawn behind highlighted characters.
    var backgroundColor: NSColor {
        
        self.dynamicColor(light: self.lightFill, dark: self.darkFill)
    }
    
    
    /// Saturated swatch color used in menus and `2×7pt` recent-passage indicators.
    var swatchColor: NSColor {
        
        self.dynamicColor(light: self.lightSwatch, dark: self.darkTextTint)
    }
    
    
    /// Center-deep, rim-bright radial gradient pair for the `17×17pt` frosted palette orbs.
    var orbGradientColors: (inner: NSColor, outer: NSColor) {
        
        let rim = self.darkTextTint
        let core: NSColor = switch self {
            case .ivory:
                NSColor(srgbRed: 0.72, green: 0.73, blue: 0.76, alpha: 1)
            case .customHue(let hue):
                Self.colorFromHSL(hueDegrees: hue, saturation: 0.80, lightness: 0.56)
            default:
                rim.blended(withFraction: 0.28, of: .black) ?? rim
        }
        return (core, rim)
    }
    
    
    /// Converts HSL (`hueDegrees: 0...360`, `saturation: 0...1`, `lightness: 0...1`) into sRGB `NSColor`.
    static func colorFromHSL(hueDegrees: Double, saturation: Double, lightness: Double, alpha: Double = 1.0) -> NSColor {
        
        let h = Self.normalizedHue(hueDegrees) / 360.0
        let s = max(0, min(1, saturation))
        let l = max(0, min(1, lightness))
        
        guard s > 0 else {
            return NSColor(srgbRed: l, green: l, blue: l, alpha: alpha)
        }
        
        let q = l < 0.5 ? l * (1 + s) : l + s - l * s
        let p = 2 * l - q
        
        func hueToRGB(_ tInput: Double) -> Double {
            var t = tInput
            if t < 0 { t += 1 }
            if t > 1 { t -= 1 }
            if t < 1.0 / 6.0 { return p + (q - p) * 6.0 * t }
            if t < 1.0 / 2.0 { return q }
            if t < 2.0 / 3.0 { return p + (q - p) * (2.0 / 3.0 - t) * 6.0 }
            return p
        }
        
        return NSColor(
            srgbRed: hueToRGB(h + 1.0 / 3.0),
            green: hueToRGB(h),
            blue: hueToRGB(h - 1.0 / 3.0),
            alpha: alpha
        )
    }
    
    
    // MARK: Private Color Tables
    
    private var darkTextTint: NSColor {
        
        switch self {
            case .ivory: NSColor(srgbRed: 0.933, green: 0.933, blue: 0.937, alpha: 1)     // #eeeeef
            case .rose: NSColor(srgbRed: 0.953, green: 0.541, blue: 0.655, alpha: 1)      // #f38aa7
            case .yellow: NSColor(srgbRed: 0.902, green: 0.812, blue: 0.404, alpha: 1)    // #e6cf67
            case .green: NSColor(srgbRed: 0.467, green: 0.945, blue: 0.447, alpha: 1)     // #77f172
            case .cyan: NSColor(srgbRed: 0.502, green: 0.914, blue: 0.902, alpha: 1)      // #80e9e6
            case .blue: NSColor(srgbRed: 0.612, green: 0.525, blue: 0.953, alpha: 1)      // #9c86f3
            case .purple: NSColor(srgbRed: 0.694, green: 0.494, blue: 0.902, alpha: 1)    // #b17ee6
            case .pink: NSColor(srgbRed: 0.902, green: 0.553, blue: 0.831, alpha: 1)      // #e68dd4
            case .orange: NSColor(srgbRed: 0.961, green: 0.631, blue: 0.353, alpha: 1)    // #f5a15a
            case .customHue(let hue): Self.colorFromHSL(hueDegrees: hue, saturation: 0.76, lightness: 0.72)
        }
    }
    
    
    private var lightTextTint: NSColor {
        
        switch self {
            case .ivory: NSColor(srgbRed: 0.133, green: 0.137, blue: 0.153, alpha: 1)
            case .rose: NSColor(srgbRed: 0.745, green: 0.176, blue: 0.357, alpha: 1)
            case .yellow: NSColor(srgbRed: 0.541, green: 0.380, blue: 0.000, alpha: 1)
            case .green: NSColor(srgbRed: 0.106, green: 0.498, blue: 0.165, alpha: 1)
            case .cyan: NSColor(srgbRed: 0.047, green: 0.455, blue: 0.478, alpha: 1)
            case .blue: NSColor(srgbRed: 0.290, green: 0.231, blue: 0.780, alpha: 1)
            case .purple: NSColor(srgbRed: 0.435, green: 0.196, blue: 0.722, alpha: 1)
            case .pink: NSColor(srgbRed: 0.651, green: 0.169, blue: 0.557, alpha: 1)
            case .orange: NSColor(srgbRed: 0.706, green: 0.298, blue: 0.047, alpha: 1)
            case .customHue(let hue): Self.colorFromHSL(hueDegrees: hue, saturation: 0.74, lightness: 0.38)
        }
    }
    
    
    private var lightFill: NSColor {
        
        switch self {
            case .ivory: NSColor(srgbRed: 0.52, green: 0.53, blue: 0.56, alpha: 0.16)
            case .customHue(let hue): Self.colorFromHSL(hueDegrees: hue, saturation: 0.78, lightness: 0.62, alpha: 0.28)
            default: self.darkTextTint.withAlphaComponent(0.32)
        }
    }
    
    
    private var darkFill: NSColor {
        
        switch self {
            case .ivory: self.darkTextTint.withAlphaComponent(0.20)
            case .customHue(let hue): Self.colorFromHSL(hueDegrees: hue, saturation: 0.76, lightness: 0.72, alpha: 0.32)
            default: self.darkTextTint.withAlphaComponent(0.32)
        }
    }
    
    
    private var lightSwatch: NSColor {
        
        switch self {
            case .ivory: NSColor(srgbRed: 0.76, green: 0.77, blue: 0.80, alpha: 1)
            case .customHue(let hue): Self.colorFromHSL(hueDegrees: hue, saturation: 0.76, lightness: 0.52)
            default: self.lightTextTint.blended(withFraction: 0.25, of: self.darkTextTint) ?? self.lightTextTint
        }
    }
    
    
    // MARK: Private Methods
    
    private func dynamicColor(light: NSColor, dark: NSColor) -> NSColor {
        
        NSColor(name: nil) { appearance in
            appearance.isDark ? dark : light
        }
    }
}
