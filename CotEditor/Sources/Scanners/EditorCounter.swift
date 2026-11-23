//
//  EditorCounter.swift
//
//  CotEditor
//  https://coteditor.com
//
//  Created by 1024jp on 2014-12-18.
//
//  ---------------------------------------------------------------------------
//
//  © 2014-2026 1024jp
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
import LineEnding
import StringUtils

@MainActor final class EditorCounter {
    
    @MainActor @Observable final class Result {
        
        var characters = Count()
        var lines = Count()
        var words = Count()
        
        /// Cursor location from the beginning of the content.
        var location: Int?
        
        /// Current line.
        var line: Int?
        
        /// Cursor location from the beginning of the line.
        var column: Int?
    }
    
    
    struct Count: Equatable {
        
        var entire: Int?
        var selected = 0
    }
    
    
    struct Types: OptionSet {
        
        var rawValue: Int
        
        static let characters = Self(rawValue: 1 << 0)
        static let lines      = Self(rawValue: 1 << 1)
        static let words      = Self(rawValue: 1 << 2)
        static let location   = Self(rawValue: 1 << 3)
        static let line       = Self(rawValue: 1 << 4)
        static let column     = Self(rawValue: 1 << 5)
        
        static let all: Self = [.characters, .lines, .words, .location, .line, .column]
        static let count: Self = [.characters, .lines, .words]
    }
    
    
    @MainActor protocol Source: AnyObject {
        
        var string: String { get }
        var selectedRanges: [NSValue] { get }
    }
    
    
    // MARK: Public Properties
    
    let result: Result = .init()
    
    var source: () -> (any Source)? = { nil }
    var lineRangeCalculator: (any LineRangeCalculating)?
    
    var updatesAll = false  { didSet { self.updateTypes() } }
    var statusBarRequirements: Types = []  { didSet { self.updateTypes() } }
    
    
    // MARK: Private Properties
    
    private var types: Types = []
    
    private var contentTask: Task<Void, any Error>?
    private var selectionTask: Task<Void, any Error>?
    
    
    // MARK: Public Methods
    
    /// Cancels all remaining tasks.
    func cancel() {
        
        self.contentTask?.cancel()
        self.contentTask = nil
        self.selectionTask?.cancel()
        self.selectionTask = nil
    }
    
    
    /// Updates content counts.
    func invalidateContent() {
        
        self.contentTask?.cancel()
        
        guard !self.types.isDisjoint(with: .count) else { return }
        
        self.contentTask = Task {
            try await Task.sleep(for: .milliseconds(85), tolerance: .milliseconds(20))  // debounce
            
            guard let source = self.source() else { return }
            
            let string = source.string.immutable
            let types = self.types
            let hasLineCalc = (self.lineRangeCalculator != nil)
            
            let computed = await Task.detached(priority: .utility) { () -> (chars: Int?, lines: Int?, words: Int?) in
                let chars = types.contains(.characters) ? string.count : nil
                let lines = (types.contains(.lines) && !hasLineCalc) ? string.numberOfLines : nil
                let words = types.contains(.words) ? string.numberOfWords : nil
                return (chars, lines, words)
            }.value
            
            try Task.checkCancellation()
            
            if let chars = computed.chars {
                self.result.characters.entire = chars
            }
            if types.contains(.lines) {
                self.result.lines.entire = self.lineRangeCalculator?.numberOfLines ?? computed.lines
            }
            if let words = computed.words {
                self.result.words.entire = words
            }
        }
    }
    
    
    /// Updates content and selection counts immediately (e.g. when a tab or window becomes active).
    func refreshNow() {
        
        guard !self.types.isEmpty, let source = self.source() else { return }
        
        let string = source.string.immutable
        let selectedNSRanges = source.selectedRanges.map(\.rangeValue)
        let utf16Length = (string as NSString).length
        
        if utf16Length <= 100_000 {
            if self.types.contains(.characters) {
                self.result.characters.entire = string.count
            }
            if self.types.contains(.lines) {
                self.result.lines.entire = self.lineRangeCalculator?.numberOfLines ?? string.numberOfLines
            }
            if self.types.contains(.words) {
                self.result.words.entire = string.numberOfWords
            }
            
            let safeSelectedRanges = selectedNSRanges.compactMap { Range($0, in: string) }
            let selectedStrings = safeSelectedRanges.map { string[$0] }
            let location = safeSelectedRanges.first?.lowerBound ?? string.startIndex
            
            if self.types.contains(.characters) {
                self.result.characters.selected = selectedStrings.map(\.count).reduce(0, +)
            }
            if self.types.contains(.lines) {
                self.result.lines.selected = string.numberOfLines(in: safeSelectedRanges)
            }
            if self.types.contains(.words) {
                self.result.words.selected = selectedStrings.map(\.numberOfWords).reduce(0, +)
            }
            if self.types.contains(.location) {
                self.result.location = string.distance(from: string.startIndex, to: location)
            }
            if self.types.contains(.line) {
                self.result.line = if let lineRangeCalculator, let nsLocation = selectedNSRanges.first?.location {
                    lineRangeCalculator.lineNumber(at: nsLocation)
                } else {
                    string.lineNumber(at: location)
                }
            }
            if self.types.contains(.column) {
                self.result.column = string.columnNumber(at: location)
            }
        } else {
            self.invalidateContent()
            self.invalidateSelection()
        }
    }
    
    
    /// Updates selection-related values.
    func invalidateSelection() {
        
        self.selectionTask?.cancel()
        
        guard !self.types.isEmpty else { return }
        
        self.selectionTask = Task {
            try await Task.sleep(for: .milliseconds(180), tolerance: .milliseconds(30))  // debounce
            
            guard let source = self.source() else { return }
            
            let string = source.string.immutable
            let selectedNSRanges = source.selectedRanges.map(\.rangeValue)
            let types = self.types
            let calcLineNumber: Int? = if types.contains(.line), let lineRangeCalculator, let nsLocation = selectedNSRanges.first?.location {
                lineRangeCalculator.lineNumber(at: nsLocation)
            } else {
                nil
            }
            
            let computed = await Task.detached(priority: .utility) { () -> (chars: Int?, lines: Int?, words: Int?, loc: Int?, line: Int?, col: Int?) in
                let selectedRanges = selectedNSRanges.compactMap { Range($0, in: string) }
                let selectedStrings = selectedRanges.map { string[$0] }
                let location = selectedRanges.first?.lowerBound ?? string.startIndex
                
                let chars = types.contains(.characters) ? selectedStrings.map(\.count).reduce(0, +) : nil
                let lines = types.contains(.lines) ? string.numberOfLines(in: selectedRanges) : nil
                let words = types.contains(.words) ? selectedStrings.map(\.numberOfWords).reduce(0, +) : nil
                let loc = types.contains(.location) ? string.distance(from: string.startIndex, to: location) : nil
                let line = (types.contains(.line) && calcLineNumber == nil) ? string.lineNumber(at: location) : nil
                let col = types.contains(.column) ? string.columnNumber(at: location) : nil
                return (chars, lines, words, loc, line, col)
            }.value
            
            try Task.checkCancellation()
            
            if let chars = computed.chars {
                self.result.characters.selected = chars
            }
            if let lines = computed.lines {
                self.result.lines.selected = lines
            }
            if let words = computed.words {
                self.result.words.selected = words
            }
            if let loc = computed.loc {
                self.result.location = loc
            }
            if types.contains(.line) {
                self.result.line = calcLineNumber ?? computed.line
            }
            if let col = computed.col {
                self.result.column = col
            }
        }
    }
    
    
    // MARK: Private Methods
    
    /// Update types to count.
    private func updateTypes() {
        
        let oldValue = self.types
        
        self.types = self.updatesAll ? .all : self.statusBarRequirements
        
        guard self.types != oldValue else { return }
        
        if self.types.isEmpty {
            self.cancel()
            return
        }
        
        let added = self.types.subtracting(oldValue)
        
        if !added.isDisjoint(with: .count) {
            self.invalidateContent()
        }
        if !added.isEmpty {
            self.invalidateSelection()
        }
    }
}
