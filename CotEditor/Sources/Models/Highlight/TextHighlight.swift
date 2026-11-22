//
//  TextHighlight.swift
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

import Foundation

/// A color the user can paint a text range with.
enum HighlightColor: Hashable, Codable, Sendable {
    
    case ivory
    case rose
    case yellow
    case green
    case cyan
    case blue
    case purple
    case pink
    case orange
    case customHue(Double)
    
    
    /// The 8 preset palette colors in row-major `3×3` order (followed by the rainbow custom orb).
    static let palettePresets: [HighlightColor] = [
        .ivory, .rose, .yellow,
        .green, .cyan, .blue,
        .purple, .pink,
    ]
    
    /// Standard menu presets preserved for context menu actions.
    static let allCases: [HighlightColor] = [
        .ivory, .rose, .yellow,
        .green, .cyan, .blue,
        .purple, .pink, .orange,
    ]
    
    
    /// Normalizes a hue angle into `[0, 360)` rounded to 0.1 degrees for deterministic encoding/equality.
    static func normalizedHue(_ hue: Double) -> Double {
        let clamped = hue.isFinite ? hue : 0
        let wrapped = (clamped.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
        let quantized = (wrapped * 10).rounded() / 10
        return quantized >= 360 ? 0 : quantized
    }
    
    
    init?(rawValue: String) {
        switch rawValue {
            case "ivory": self = .ivory
            case "rose": self = .rose
            case "yellow": self = .yellow
            case "green": self = .green
            case "cyan": self = .cyan
            case "blue": self = .blue
            case "purple": self = .purple
            case "pink": self = .pink
            case "orange": self = .orange
            default:
                if rawValue.hasPrefix("hue:"),
                   let parsed = Double(rawValue.dropFirst(4)),
                   parsed.isFinite
                {
                    self = .customHue(Self.normalizedHue(parsed))
                } else {
                    return nil
                }
        }
    }
    
    
    var rawValue: String {
        switch self {
            case .ivory: "ivory"
            case .rose: "rose"
            case .yellow: "yellow"
            case .green: "green"
            case .cyan: "cyan"
            case .blue: "blue"
            case .purple: "purple"
            case .pink: "pink"
            case .orange: "orange"
            case .customHue(let hue):
                String(format: "hue:%.1f", Self.normalizedHue(hue))
        }
    }
    
    
    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        guard let decoded = HighlightColor(rawValue: raw) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unknown HighlightColor '\(raw)'")
        }
        self = decoded
    }
    
    
    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(self.rawValue)
    }
    
    
    /// Extracts the hue angle `[0, 360)` for custom hues or an approximate hue for preset colors.
    var hueDegrees: Double {
        switch self {
            case .ivory: 0
            case .rose: 343
            case .yellow: 49
            case .green: 118
            case .cyan: 178
            case .blue: 252
            case .purple: 270
            case .pink: 312
            case .orange: 27
            case .customHue(let hue): Self.normalizedHue(hue)
        }
    }
    
    
    /// The display name, used in context menus and palette accessibility labels.
    var localizedName: String {
        switch self {
            case .ivory: AppLanguage.text("月白", en: "Ivory")
            case .rose: AppLanguage.text("玫红", en: "Rose")
            case .yellow: AppLanguage.text("明黄", en: "Yellow")
            case .green: AppLanguage.text("翠绿", en: "Green")
            case .cyan: AppLanguage.text("冰青", en: "Cyan")
            case .blue: AppLanguage.text("星蓝", en: "Blue")
            case .purple: AppLanguage.text("暮紫", en: "Purple")
            case .pink: AppLanguage.text("樱粉", en: "Pink")
            case .orange: AppLanguage.text("暖橙", en: "Orange")
            case .customHue: AppLanguage.text("自定义色", en: "Custom Hue")
        }
    }
}


/// A highlighted range in a document, stored separately from the text itself.
///
/// The document file stays plain text; these marks live in a sidecar file so that
/// an ordinary text editor opening the same file sees no difference.
struct TextHighlight: Codable, Equatable, Sendable {
    
    var location: Int
    var length: Int
    var color: HighlightColor
    
    
    var range: NSRange {
        
        NSRange(location: self.location, length: self.length)
    }
    
    
    init(location: Int, length: Int, color: HighlightColor) {
        
        self.location = location
        self.length = length
        self.color = color
    }
    
    
    init(range: NSRange, color: HighlightColor) {
        
        self.init(location: range.location, length: range.length, color: color)
    }
}


/// The on-disk representation of a document's highlights.
struct TextHighlightStore: Codable, Equatable, Sendable {
    
    static let currentVersion = 1
    
    var version: Int = TextHighlightStore.currentVersion
    var marks: [TextHighlight] = []
    
    
    /// The content length the marks were recorded against.
    ///
    /// Used to detect that the text changed while the file was closed outside CotEditor;
    /// in that case offsets can no longer be trusted and the marks are dropped.
    var sourceLength: Int = 0
}


extension Array where Element == TextHighlight {
    
    /// Shifts marks in response to an edit, keeping them attached to their text.
    ///
    /// - Parameters:
    ///   - editedRange: The range that was replaced, in pre-edit coordinates.
    ///   - changeInLength: The length delta introduced by the edit.
    /// - Returns: The adjusted marks, with any that collapsed to nothing removed.
    func adjusting(forEditIn editedRange: NSRange, changeInLength delta: Int) -> [TextHighlight] {
        
        let editStart = editedRange.location
        let editEnd = editedRange.location + editedRange.length
        
        return self.compactMap { mark in
            let markStart = mark.location
            let markEnd = mark.location + mark.length
            
            var newStart = markStart
            var newEnd = markEnd
            
            if markEnd <= editStart {
                // entirely before the edit: untouched
                
            } else if markStart >= editEnd {
                // entirely after the edit: shift wholesale
                newStart += delta
                newEnd += delta
            } else if markStart >= editStart && markEnd <= editEnd {
                // the mark lies fully inside the replaced range: it is gone
                return nil
            } else if markStart <= editStart && markEnd >= editEnd {
                // the edit happened inside the mark: grow or shrink it
                newEnd += delta
            } else if markStart < editStart {
                // the edit overlaps the mark's tail: clip the tail
                newEnd = editStart
            } else {
                // the edit overlaps the mark's head: clip the head
                // (`editStart` keeps its position; the mark's end moves with the text)
                newStart = editStart
                newEnd += delta
            }
            
            let newLength = newEnd - newStart
            guard newStart >= 0, newLength > 0 else { return nil }
            
            return TextHighlight(location: newStart, length: newLength, color: mark.color)
        }
    }
    
    
    /// Marks that overlap the given range.
    func overlapping(_ range: NSRange) -> [TextHighlight] {
        
        self.filter { NSIntersectionRange($0.range, range).length > 0 }
    }
}
