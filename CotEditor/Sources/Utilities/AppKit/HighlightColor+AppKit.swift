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
    /// Semi-transparent so the text stays readable on top of it.
    var backgroundColor: NSColor {
        
        self.baseColor.withAlphaComponent(0.35)
    }
    
    
    /// The opaque color used for the context menu swatch.
    var swatchColor: NSColor {
        
        self.baseColor
    }
    
    
    private var baseColor: NSColor {
        
        let components = self.components
        
        return NSColor(name: nil) { appearance in
            // deepen the tone in dark mode, where a pale wash would vanish
            let factor: CGFloat = appearance.isDark ? 0.75 : 1
            return NSColor(srgbRed: components.red * factor,
                           green: components.green * factor,
                           blue: components.blue * factor,
                           alpha: 1)
        }
    }
    
    
    /// Saturation tuned per color so the five read as one family.
    private var components: (red: CGFloat, green: CGFloat, blue: CGFloat) {
        
        switch self {
            case .yellow: (0.98, 0.85, 0.25)
            case .green:  (0.45, 0.85, 0.45)
            case .blue:   (0.42, 0.70, 0.98)
            case .pink:   (0.98, 0.55, 0.78)
            case .orange: (0.99, 0.65, 0.30)
        }
    }
}
