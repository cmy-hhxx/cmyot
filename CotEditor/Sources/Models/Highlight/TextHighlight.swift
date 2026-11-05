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
enum HighlightColor: String, CaseIterable, Codable, Sendable {
    
    case yellow
    case green
    case blue
    case pink
    case orange
    
    
    /// The display name, used in the context menu.
    var localizedName: String {
        
        switch self {
            case .yellow: "黄色"
            case .green: "绿色"
            case .blue: "蓝色"
            case .pink: "粉色"
            case .orange: "橙色"
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
