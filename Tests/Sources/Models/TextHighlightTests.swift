//
//  TextHighlightTests.swift
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
import Testing
@testable import CotEditor

struct TextHighlightTests {
    
    private func mark(_ location: Int, _ length: Int) -> TextHighlight {
        
        TextHighlight(location: location, length: length, color: .yellow)
    }
    
    
    // MARK: Edits before the mark
    
    @Test func insertBeforeShiftsMark() {
        
        let marks = [self.mark(10, 5)]
        let result = marks.adjusting(forEditIn: NSRange(location: 2, length: 0), changeInLength: 3)
        
        #expect(result.count == 1)
        #expect(result[0].location == 13)
        #expect(result[0].length == 5)
        #expect(result[0].color == .yellow)
    }
    
    
    @Test func deleteBeforeShiftsMarkBack() {
        
        let marks = [self.mark(10, 5)]
        let result = marks.adjusting(forEditIn: NSRange(location: 2, length: 4), changeInLength: -4)
        
        #expect(result.count == 1)
        #expect(result[0].location == 6)
        #expect(result[0].length == 5)
    }
    
    
    // MARK: Edits after the mark
    
    @Test func editAfterLeavesMarkUntouched() {
        
        let marks = [self.mark(10, 5)]
        let result = marks.adjusting(forEditIn: NSRange(location: 20, length: 2), changeInLength: 2)
        
        #expect(result.count == 1)
        #expect(result[0].location == 10)
        #expect(result[0].length == 5)
    }
    
    
    // MARK: Edits inside the mark
    
    @Test func insertInsideGrowsMark() {
        
        let marks = [self.mark(10, 5)]
        let result = marks.adjusting(forEditIn: NSRange(location: 12, length: 0), changeInLength: 3)
        
        #expect(result.count == 1)
        #expect(result[0].location == 10)
        #expect(result[0].length == 8)
    }
    
    
    @Test func deleteInsideShrinksMark() {
        
        let marks = [self.mark(10, 10)]
        let result = marks.adjusting(forEditIn: NSRange(location: 12, length: 4), changeInLength: -4)
        
        #expect(result.count == 1)
        #expect(result[0].location == 10)
        #expect(result[0].length == 6)
    }
    
    
    @Test func deleteCoveringWholeMarkRemovesIt() {
        
        let marks = [self.mark(10, 5)]
        let result = marks.adjusting(forEditIn: NSRange(location: 8, length: 10), changeInLength: -10)
        
        #expect(result.isEmpty)
    }
    
    
    @Test func deleteExactlyMarkRemovesIt() {
        
        let marks = [self.mark(10, 5)]
        let result = marks.adjusting(forEditIn: NSRange(location: 10, length: 5), changeInLength: -5)
        
        #expect(result.isEmpty)
    }
    
    
    // MARK: Edits clipping an edge
    
    @Test func editOverlappingHeadClipsHead() {
        
        let marks = [self.mark(10, 6)]
        let result = marks.adjusting(forEditIn: NSRange(location: 8, length: 4), changeInLength: -4)
        
        #expect(result.count == 1)
        #expect(result[0].location == 8)
        #expect(result[0].length == 4)
    }
    
    
    @Test func editOverlappingTailClipsTail() {
        
        let marks = [self.mark(10, 6)]
        let result = marks.adjusting(forEditIn: NSRange(location: 14, length: 4), changeInLength: -4)
        
        #expect(result.count == 1)
        #expect(result[0].location == 10)
        #expect(result[0].length == 4)
    }
    
    
    // MARK: Multiple marks
    
    @Test func multipleMarksAdjustIndependently() {
        
        let marks = [self.mark(0, 3), self.mark(10, 3), self.mark(20, 3)]
        let result = marks.adjusting(forEditIn: NSRange(location: 5, length: 0), changeInLength: 5)
        
        #expect(result.map(\.location) == [0, 15, 25])
        #expect(result.map(\.length) == [3, 3, 3])
    }
    
    
    // MARK: Query
    
    @Test func overlappingFindsIntersectingMarks() {
        
        let marks = [self.mark(0, 5), self.mark(10, 5), self.mark(20, 5)]
        
        #expect(marks.overlapping(NSRange(location: 3, length: 2)).count == 1)
        #expect(marks.overlapping(NSRange(location: 3, length: 10)).count == 2)
        #expect(marks.overlapping(NSRange(location: 100, length: 2)).isEmpty)
    }
    
    
    // MARK: Codable round trip
    
    @Test func codableRoundTrip() throws {
        
        let store = TextHighlightStore(marks: [self.mark(1, 2), TextHighlight(location: 5, length: 3, color: .blue)],
                                       sourceLength: 42)
        let data = try JSONEncoder().encode(store)
        let decoded = try JSONDecoder().decode(TextHighlightStore.self, from: data)
        
        #expect(decoded == store)
        #expect(decoded.version == TextHighlightStore.currentVersion)
    }
}
