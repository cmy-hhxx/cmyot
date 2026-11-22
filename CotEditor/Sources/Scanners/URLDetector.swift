//
//  URLDetector.swift
//
//  CotEditor
//  https://coteditor.com
//
//  Created by 1024jp on 2020-02-15.
//
//  ---------------------------------------------------------------------------
//
//  © 2020-2026 1024jp
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

import AppKit.NSTextStorage
import StringUtils
import ValueRange

@MainActor final class URLDetector {
    
    // MARK: Private Properties
    
    private let textStorage: NSTextStorage
    private var editedRanges: EditedRangeSet
    private let delay: Duration = .seconds(0.5)
    
    private var textEditingObserver: (any NSObjectProtocol)?
    private var task: Task<Void, any Error>?
    
    
    // MARK: Lifecycle
    
    init(textStorage: NSTextStorage) {
        
        self.textStorage = textStorage
        
        self.editedRanges = EditedRangeSet(range: textStorage.range)
        self.textEditingObserver = self.observeTextStorage(textStorage)
        self.task = Task { try await self.detectInvalidRanges() }
    }
    
    
    // MARK: Public Methods
    
    /// Stops the detection and removes highlights.
    func cancel() {
        
        if let textEditingObserver {
            NotificationCenter.default.removeObserver(textEditingObserver, name: NSTextStorage.didProcessEditingNotification, object: self.textStorage)
            self.textEditingObserver = nil
        }
        
        self.task?.cancel()
        self.task = nil
        
        self.textStorage.removeAttribute(.link, range: self.textStorage.range)
        self.editedRanges.clear()
    }
    
    
    // MARK: Private Methods
    
    /// Observes the changes of the given textStorage to detect URLs around the edited area.
    ///
    /// - Parameter textStorage: The text storage to observe.
    /// - Returns: The notification observer.
    private func observeTextStorage(_ textStorage: NSTextStorage) -> any NSObjectProtocol {
        
        NotificationCenter.default.addObserver(forName: NSTextStorage.didProcessEditingNotification, object: textStorage, queue: .main) { [weak self] notification in
            let textStorage = notification.object as! NSTextStorage
            
            guard textStorage.editedMask.contains(.editedCharacters) else { return }
            
            MainActor.assumeIsolated { [range = textStorage.editedRange, length = textStorage.changeInLength] in
                self?.invalidate(in: range, changeInLength: length)
            }
        }
    }
    
    
    /// Updates edited ranges by assuming the textStorage was edited.
    ///
    /// - Parameters:
    ///   - editedRange: The edited range.
    ///   - delta: The change in length.
    private func invalidate(in editedRange: NSRange, changeInLength delta: Int) {
        
        self.editedRanges.append(editedRange: editedRange, changeInLength: delta)
        
        self.task?.cancel()
        self.task = Task {
            try await Task.sleep(for: self.delay, tolerance: self.delay * 0.5)
            try await self.detectInvalidRanges()
        }
    }
    
    
    /// Updates URLs around the edited ranges.
    private func detectInvalidRanges() async throws {
        
        guard let invalidRange = self.editedRanges.range else { return }
        
        let string = self.textStorage.string as NSString
        let lowerBound = max(invalidRange.lowerBound - 1, 0)
        let upperBound = min(invalidRange.upperBound + 1, string.length)
        let parseRange = string.lineRange(for: NSRange(lowerBound..<upperBound))
        
        try await self.textStorage.linkURLs(in: parseRange)
        
        self.editedRanges.clear()
    }
}


extension URLDetector {
    
    private nonisolated static let linkDetector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
    
    
    /// Synchronously detects all clickable URLs and their trimmed UTF-16 ranges inside `range` of `text`,
    /// without mutating text storage attributes.
    nonisolated static func detectedLinkMatches(in text: String, range: NSRange? = nil) -> [(url: URL, range: NSRange)] {
        
        let nsText = text as NSString
        guard nsText.length > 0 else { return [] }
        let targetRange = range.map { NSIntersectionRange($0, NSRange(location: 0, length: nsText.length)) }
            ?? NSRange(location: 0, length: nsText.length)
        guard targetRange.length > 0, let detector = Self.linkDetector else { return [] }
        
        return detector.matches(in: text, range: targetRange).compactMap { match in
            let trimmedRange = self.trimUnbalancedTrailingDelimiters(in: nsText, range: match.range)
            guard trimmedRange.length > 0 else { return nil }
            
            let rawText = nsText.substring(with: trimmedRange)
            if let cleanedURL = URL(string: rawText), cleanedURL.scheme != nil {
                return (cleanedURL, trimmedRange)
            }
            if let fallbackURL = match.url {
                return (fallbackURL, trimmedRange)
            }
            return nil
        }
    }
    
    
    /// Returns all trimmed clickable URL ranges inside `range` of `text`.
    nonisolated static func detectedLinkRanges(in text: String, range: NSRange? = nil) -> [NSRange] {
        
        self.detectedLinkMatches(in: text, range: range).map(\.range)
    }
    
    
    /// Synchronously detects a clickable URL at a UTF-16 offset within a single line of text,
    /// without attaching `.link` attributes to the text storage.
    nonisolated static func detectedURL(in line: String, at utf16Offset: Int) -> URL? {
        
        let nsLine = line as NSString
        guard utf16Offset >= 0, utf16Offset < nsLine.length else { return nil }
        
        return self.detectedLinkMatches(in: line)
            .first { NSLocationInRange(utf16Offset, $0.range) }?
            .url
    }
    
    
    private nonisolated static func trimUnbalancedTrailingDelimiters(in string: NSString, range: NSRange) -> NSRange {
        
        var adjusted = range
        let trailingPunctuation = CharacterSet(charactersIn: ".,;!?，。；！？、】》」』\"'<>")
        
        while adjusted.length > 0 {
            let lastLocation = adjusted.upperBound - 1
            let lastChar = string.character(at: lastLocation)
            guard let scalar = Unicode.Scalar(lastChar) else { break }
            
            if scalar == ")" || scalar == "）" {
                let opening: String = (scalar == ")") ? "(" : "（"
                let closing = String(scalar)
                let substring = string.substring(with: adjusted)
                let openCount = substring.components(separatedBy: opening).count - 1
                let closeCount = substring.components(separatedBy: closing).count - 1
                if closeCount > openCount {
                    adjusted.length -= 1
                    continue
                }
                break
            } else if scalar == "]" {
                let substring = string.substring(with: adjusted)
                let openCount = substring.components(separatedBy: "[").count - 1
                let closeCount = substring.components(separatedBy: "]").count - 1
                if closeCount > openCount {
                    adjusted.length -= 1
                    continue
                }
                break
            } else if trailingPunctuation.contains(scalar) {
                adjusted.length -= 1
                continue
            }
            break
        }
        
        return adjusted
    }
}


extension NSTextStorage {
    
    /// Links detected URLs in the content.
    ///
    /// - Parameter range: The range where links are detected, or nil to detect all.
    /// - Throws: `CancellationError`
    @MainActor final func linkURLs(in range: NSRange? = nil) async throws {
        
        guard self.length > 0 else { return }
        
        let string = self.string.immutable
        let range = range ?? self.range
        
        let task: Task<[ValueRange<URL>], any Error> = .detached {
            try NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
                .cancellableMatches(in: string, range: range)
                .compactMap { match in match.url.map { ValueRange(value: $0, range: match.range) } }
        }
        let links: [ValueRange<URL>] = try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
        
        try Task.checkCancellation()
        
        guard self.string.length == string.length else {
            return assertionFailure("textStorage was edited after starting URL detection")
        }
        
        guard !links.isEmpty || self.hasAttribute(.link, in: range) else { return }
        
        self.beginEditing()
        self.removeAttribute(.link, range: range)
        for link in links {
            self.addAttribute(.link, value: link.value, range: link.range)
        }
        self.endEditing()
    }
}
