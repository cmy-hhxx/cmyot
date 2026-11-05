//
//  Document+Highlight.swift
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
import DocumentFile
import URLUtils

extension ExtendedFileAttributeName {
    
    /// The highlights painted on a document, stored as an extended attribute.
    ///
    /// An extended attribute keeps the document itself pure plain text and travels with
    /// the file when it is moved or renamed. A sidecar file cannot be used instead: the
    /// app is sandboxed and only gets access to the file the user opened.
    static let textHighlights = "local.cmy.CotEditor.TextHighlights"
}


extension Document {
    
    // MARK: Public Methods
    
    /// Reads the highlights stored on the document file, if any.
    func loadHighlights() {
        
        guard
            let fileURL = self.fileURL,
            let data = try? fileURL.extendedAttribute(for: ExtendedFileAttributeName.textHighlights),
            let store = try? JSONDecoder().decode(TextHighlightStore.self, from: data),
            store.version == TextHighlightStore.currentVersion,
            store.sourceLength == self.textStorage.length  // the text changed while closed
        else {
            self.textHighlights = []
            self.applyHighlightRendering()
            return
        }
        
        self.textHighlights = store.marks
        self.applyHighlightRendering()
    }
    
    
    /// Paints the given range, replacing any highlight it touches.
    func addHighlight(range: NSRange, color: HighlightColor) {
        
        guard
            range.length > 0,
            NSMaxRange(range) <= self.textStorage.length
        else { return }
        
        self.textHighlights.removeAll { NSIntersectionRange($0.range, range).length > 0 }
        self.textHighlights.append(TextHighlight(range: range, color: color))
        self.textHighlights.sort { $0.location < $1.location }
        
        self.applyHighlightRendering()
        self.saveHighlightsSoon()
    }
    
    
    /// Removes every highlight overlapping the given range.
    func removeHighlights(in range: NSRange) {
        
        let count = self.textHighlights.count
        self.textHighlights.removeAll { NSIntersectionRange($0.range, range).length > 0 }
        
        guard self.textHighlights.count != count else { return }
        
        self.applyHighlightRendering()
        self.saveHighlightsSoon()
    }
    
    
    /// Keeps the stored highlights attached to their text after an edit.
    ///
    /// - Parameters:
    ///   - editedRange: The range the edit produced, in post-edit coordinates.
    ///   - changeInLength: The length delta the edit introduced.
    func adjustHighlights(forEditIn editedRange: NSRange, changeInLength delta: Int) {
        
        guard !self.textHighlights.isEmpty, delta != 0 else { return }
        
        // `NSTextStorage` reports the edited range after the change has been applied, so
        // the replaced range is the same location with the delta removed again.
        let replacedRange = NSRange(location: editedRange.location,
                                    length: max(0, editedRange.length - delta))
        
        self.textHighlights = self.textHighlights.adjusting(forEditIn: replacedRange,
                                                            changeInLength: delta)
        self.applyHighlightRendering()
        self.saveHighlightsSoon()
    }
    
    
    /// Draws the current highlights over the text.
    ///
    /// Temporary attributes are used so that the highlights never become part of the text
    /// storage, cannot be saved with the text and do not disturb the syntax highlighting.
    func applyHighlightRendering() {
        
        let textStorage = self.textStorage
        let wholeRange = NSRange(location: 0, length: textStorage.length)
        
        for layoutManager in textStorage.layoutManagers {
            layoutManager.removeTemporaryAttribute(.backgroundColor, forCharacterRange: wholeRange)
            
            for highlight in self.textHighlights {
                let range = NSIntersectionRange(highlight.range, wholeRange)
                guard range.length > 0 else { continue }
                
                layoutManager.addTemporaryAttribute(.backgroundColor,
                                                    value: highlight.color.backgroundColor,
                                                    forCharacterRange: range)
            }
            
            layoutManager.invalidateDisplay(forCharacterRange: wholeRange)
        }
    }
    
    
    // MARK: Private Methods
    
    /// Writes the highlights after a short delay so that a burst of edits results in one write.
    private func saveHighlightsSoon() {
        
        self.highlightSaveTask?.cancel()
        self.highlightSaveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            
            self?.saveHighlights()
        }
    }
    
    
    /// Writes the highlights onto the document file's extended attribute.
    private func saveHighlights() {
        
        guard let fileURL = self.fileURL else { return }
        
        guard !self.textHighlights.isEmpty else {
            try? fileURL.setExtendedAttribute(data: nil, for: ExtendedFileAttributeName.textHighlights)  // FILE_ACCESS
            return
        }
        
        let store = TextHighlightStore(marks: self.textHighlights,
                                       sourceLength: self.textStorage.length)
        guard let data = try? JSONEncoder().encode(store) else { return }
        
        try? fileURL.setExtendedAttribute(data: data, for: ExtendedFileAttributeName.textHighlights)  // FILE_ACCESS
    }
}
