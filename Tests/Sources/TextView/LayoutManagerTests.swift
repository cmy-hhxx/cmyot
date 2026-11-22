//
//  LayoutManagerTests.swift
//  Tests
//
//  CotEditor
//  https://coteditor.com
//
//  Created by 1024jp on 2026-05-08.
//
//  ---------------------------------------------------------------------------
//
//  © 2026 1024jp
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
import Testing
import LineEnding
@testable import CotEditor

struct LayoutManagerTests {
    
    @Test func noLineBreakAfterLeadingIndentAtDocumentStart() {
        
        let textStorage = NSTextStorage(string: "    dog")
        let layoutManager = LayoutManager(lineEndingScanner: LineEndingScanner(textStorage: textStorage, lineEnding: .lf))
        textStorage.addLayoutManager(layoutManager)
        
        #expect(!layoutManager.layoutManager(layoutManager, shouldBreakLineByWordBeforeCharacterAt: 4))
    }
    
    
    @Test @MainActor func shorteningHighlightedDocumentDoesNotCrashOrDesyncLayout() async throws {
        
        let doc = Document()
        doc.textStorage.replaceCharacters(
            in: NSRange(location: 0, length: doc.textStorage.length),
            with: "Hello world, this is a highlighted test string that will be shortened!"
        )
        let wc = DocumentWindowController(document: doc)
        wc.showWindow(nil)
        defer { wc.close() }
        
        let textView = try #require(wc.documentViewController?.focusedTextView)
        doc.addHighlight(range: NSRange(location: 0, length: 20), color: .yellow)
        
        // Force initial layout & draw
        textView.displayIfNeeded()
        
        // Shorten the text sharply while highlights are active (triggers didProcessEditing -> adjustHighlights)
        doc.textStorage.replaceCharacters(in: NSRange(location: 10, length: 50), with: "")
        
        // Redraw immediately and after deferred highlight sync
        textView.displayIfNeeded()
        try await Task.sleep(for: .milliseconds(50))
        textView.displayIfNeeded()
        
        #expect(doc.textStorage.length == 20)
        #expect(doc.textHighlights.count == 1)
        #expect(doc.textHighlights[0].range == NSRange(location: 0, length: 10))
    }
    
    
    @Test @MainActor func inlineImagePartialEditAndUnwrappedContainerRedrawSafely() throws {
        
        // Create a temporary 1x1 PNG in the inline image store so the token resolves
        let image = NSImage(size: NSSize(width: 24, height: 24), flipped: false) { rect in
            NSColor.systemBlue.setFill()
            rect.fill()
            return true
        }
        let stored = try #require(PlainTextInlineImageStore.shared.store(image: image, for: nil))
        defer { try? FileManager.default.removeItem(at: stored.fileURL) }
        
        let textStorage = NSTextStorage(string: "Before\n\(stored.token)\nAfter line with extra text")
        let scanner = LineEndingScanner(textStorage: textStorage, lineEnding: .lf)
        let layoutManager = LayoutManager(lineEndingScanner: scanner)
        layoutManager.rendersPlainTextInlineImages = true
        let textContainer = TextContainer(size: NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude))
        layoutManager.addTextContainer(textContainer)
        textStorage.addLayoutManager(layoutManager)
        let textView = EditorTextView(frame: NSRect(x: 0, y: 0, width: 480, height: 320), textStorage: textStorage, lineEndingScanner: scanner)
        textView.wrapsLines = false
        
        // Force layout & draw with unwrapped (infinite width) container
        layoutManager.ensureLayout(for: textContainer)
        if let rep = textView.bitmapImageRepForCachingDisplay(in: textView.bounds) {
            textView.cacheDisplay(in: textView.bounds, to: rep)
        }
        
        // Partially delete the closing `⟧` of the inline image token -> full line must re-generate normal glyphs
        let nsBefore = textStorage.string as NSString
        let closeRange = nsBefore.range(of: "⟧")
        #expect(closeRange.location != NSNotFound)
        textStorage.replaceCharacters(in: closeRange, with: "")
        
        layoutManager.ensureLayout(for: textContainer)
        if let rep = textView.bitmapImageRepForCachingDisplay(in: textView.bounds) {
            textView.cacheDisplay(in: textView.bounds, to: rep)
        }
        
        // Now delete most of the document and redraw again
        textStorage.replaceCharacters(in: NSRange(location: 3, length: textStorage.length - 3), with: "")
        layoutManager.ensureLayout(for: textContainer)
        if let rep = textView.bitmapImageRepForCachingDisplay(in: textView.bounds) {
            textView.cacheDisplay(in: textView.bounds, to: rep)
        }
        #expect(textStorage.length == 3)
        
        // Out-of-bounds enumeration range should clamp safely instead of throwing NSRangeException
        var visited = 0
        layoutManager.enumerateTemporaryAttribute(.foregroundColor, type: NSColor.self, in: NSRange(location: 0, length: 999)) { _, _, _ in
            visited += 1
        }
        #expect(visited >= 0)
    }
}
