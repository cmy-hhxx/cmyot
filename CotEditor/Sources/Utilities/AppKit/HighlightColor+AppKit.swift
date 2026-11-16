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

extension HighlightColor {
    
    /// The fill color drawn behind highlighted text.
    ///
    /// The two appearances need different colors, not the same color at a different alpha: on a
    /// light background a highlight is a saturated pastel that still reads on white, while on a
    /// dark background the same hue has to become a dim glow under light text. The dark fills
    /// are therefore translucent, so the editor theme still shows through them.
    var backgroundColor: NSColor {
        
        self.dynamicColor(light: self.lightFill, dark: self.darkFill)
    }
    
    
    /// The opaque color used for the context menu swatch.
    ///
    /// The light fill already reads on a light menu; the dark fill is too dim there, so the dark
    /// appearance gets the same hue at full saturation instead.
    var swatchColor: NSColor {
        
        self.dynamicColor(light: self.lightFill, dark: self.darkSwatch)
    }
    
    
    // MARK: Private Computed Properties
    
    private var lightFill: NSColor {
        
        switch self {
            case .yellow: NSColor(srgbRed: 1.00, green: 0.839, blue: 0.251, alpha: 1)
            case .green: NSColor(srgbRed: 0.627, green: 0.894, blue: 0.557, alpha: 1)
            case .blue: NSColor(srgbRed: 0.588, green: 0.796, blue: 0.988, alpha: 1)
            case .pink: NSColor(srgbRed: 1.00, green: 0.667, blue: 0.792, alpha: 1)
            case .orange: NSColor(srgbRed: 1.00, green: 0.729, blue: 0.463, alpha: 1)
        }
    }
    
    
    private var darkFill: NSColor {
        
        switch self {
            case .yellow: NSColor(srgbRed: 1.00, green: 0.78, blue: 0.10, alpha: 0.30)
            case .green: NSColor(srgbRed: 0.35, green: 0.85, blue: 0.40, alpha: 0.30)
            case .blue: NSColor(srgbRed: 0.30, green: 0.62, blue: 1.00, alpha: 0.32)
            case .pink: NSColor(srgbRed: 1.00, green: 0.45, blue: 0.70, alpha: 0.30)
            case .orange: NSColor(srgbRed: 1.00, green: 0.62, blue: 0.25, alpha: 0.32)
        }
    }
    
    
    private var darkSwatch: NSColor {
        
        switch self {
            case .yellow: NSColor(srgbRed: 0.91, green: 0.72, blue: 0.05, alpha: 1)
            case .green: NSColor(srgbRed: 0.30, green: 0.80, blue: 0.36, alpha: 1)
            case .blue: NSColor(srgbRed: 0.25, green: 0.56, blue: 1.00, alpha: 1)
            case .pink: NSColor(srgbRed: 0.94, green: 0.38, blue: 0.62, alpha: 1)
            case .orange: NSColor(srgbRed: 0.95, green: 0.58, blue: 0.20, alpha: 1)
        }
    }
    
    
    // MARK: Private Methods
    
    /// Builds one color that follows the appearance.
    ///
    /// - Parameters:
    ///   - light: The color to use in a light appearance.
    ///   - dark: The color to use in a dark appearance.
    /// - Returns: The appearance-dependent color.
    private func dynamicColor(light: NSColor, dark: NSColor) -> NSColor {
        
        NSColor(name: nil) { appearance in
            appearance.isDark ? dark : light
        }
    }
}
