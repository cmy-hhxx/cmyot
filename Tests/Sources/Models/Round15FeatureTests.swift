//
//  Round15FeatureTests.swift
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
import Defaults
import Foundation
import LineEnding
import StringUtils
import SwiftUI
import Testing
@testable import CotEditor

@Suite(.serialized)
@MainActor
struct Round15FeatureTests {
    
    @Test func urlCmdClickDetectionAndNoAutoLinkAttributes() {
        
        let line = "参考文档：[官网](https://coteditor.com/guide?a=1) 或 https://example.com。"
        let nsLine = line as NSString
        
        let firstURLRange = nsLine.range(of: "https://coteditor.com/guide?a=1")
        #expect(URLDetector.detectedURL(in: line, at: firstURLRange.location) == URL(string: "https://coteditor.com/guide?a=1"))
        #expect(URLDetector.detectedURL(in: line, at: firstURLRange.upperBound - 1) == URL(string: "https://coteditor.com/guide?a=1"))
        // Trailing ')' right outside the URL should not trigger a link click
        #expect(URLDetector.detectedURL(in: line, at: firstURLRange.upperBound) == nil)
        // Normal Markdown label text keeps multi-cursor behavior instead of opening links
        #expect(URLDetector.detectedURL(in: line, at: 1) == nil)
        
        let secondURLRange = nsLine.range(of: "https://example.com")
        #expect(URLDetector.detectedURL(in: line, at: secondURLRange.location + 3) == URL(string: "https://example.com"))
        #expect(URLDetector.detectedURL(in: line, at: secondURLRange.upperBound) == nil)  // trailing CJK period
        
        // Documents never attach clickable `.link` attributes automatically
        let prevAutoLink = UserDefaults.standard[.autoLinkDetection]
        defer { UserDefaults.standard[.autoLinkDetection] = prevAutoLink }
        UserDefaults.standard[.autoLinkDetection] = true
        
        let doc = Document()
        doc.textStorage.replaceCharacters(in: doc.textStorage.range, with: line)
        #expect(doc.textStorage.hasAttribute(.link, in: doc.textStorage.range) == false)
        
        let textView = EditorTextView(
            textStorage: doc.textStorage,
            lineEndingScanner: doc.lineEndingScanner
        )
        #expect(textView.isAutomaticLinkDetectionEnabled == false)
        #expect(textView.linkTextAttributes?.isEmpty == true)
    }
    
    
    @Test func inlineImageAspectRatioTitleHidingAndAtomicDeletion() throws {
        
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("CotInlineImgR15-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        let docURL = tempDir.appendingPathComponent("note.txt")
        try Data().write(to: docURL)
        
        // 1. Wide, short toolbar strip (480x36) must NOT stretch to minHeight 44!
        let wideImage = Self.makeSolidImage(pixelWidth: 480, pixelHeight: 36, color: .systemBlue)
        let storedWide = try #require(PlainTextInlineImageStore.shared.store(image: wideImage, for: docURL))
        let wideCardSize = try #require(PlainTextInlineImageStore.shared.cardSize(
            for: storedWide.token.replacingOccurrences(of: "⟦🖼 ", with: "").replacingOccurrences(of: "⟧", with: ""),
            documentURL: docURL
        ))
        let wideDrawW = wideCardSize.width - 8
        let wideDrawH = wideCardSize.height - 8
        let expectedWideRatio = 480.0 / 36.0
        #expect(abs((wideDrawW / wideDrawH) - expectedWideRatio) < 0.4)
        
        // 2. Tall narrow image (48x320) must NOT stretch horizontally to minWidth 64!
        let tallImage = Self.makeSolidImage(pixelWidth: 48, pixelHeight: 320, color: .systemGreen)
        let storedTall = try #require(PlainTextInlineImageStore.shared.store(image: tallImage, for: docURL))
        let tallID = storedTall.token
            .replacingOccurrences(of: "⟦🖼 ", with: "")
            .replacingOccurrences(of: "⟧", with: "")
        let tallCardSize = try #require(PlainTextInlineImageStore.shared.cardSize(
            for: tallID,
            documentURL: docURL,
            maxImageWidth: 460,
            maxImageHeight: 260
        ))
        let tallDrawW = tallCardSize.width - 8
        let tallDrawH = tallCardSize.height - 8
        #expect(abs((tallDrawW / tallDrawH) - (48.0 / 320.0)) < 0.03)
        
        // 3. LayoutManager hides `⟦🖼 ...⟧` glyphs cleanly without reserving an extra title row
        let doc = Document()
        doc.fileURL = docURL
        doc.textStorage.replaceCharacters(in: doc.textStorage.range, with: "\(storedWide.token)\n正文")
        let textView = EditorTextView(textStorage: doc.textStorage, lineEndingScanner: doc.lineEndingScanner)
        textView.frame = NSRect(x: 0, y: 0, width: 640, height: 320)
        textView.font = .systemFont(ofSize: 13)
        let layoutManager = try #require(textView.layoutManager as? LayoutManager)
        layoutManager.inlineImageDocumentURL = docURL
        layoutManager.rendersPlainTextInlineImages = true
        layoutManager.ensureLayout(forCharacterRange: doc.textStorage.range)
        
        let firstGlyph = layoutManager.glyphIndexForCharacter(at: 0)
        let secondGlyph = layoutManager.glyphIndexForCharacter(at: 1)
        #expect(layoutManager.propertyForGlyph(at: firstGlyph).contains(.controlCharacter))
        #expect(layoutManager.propertyForGlyph(at: secondGlyph).contains(.null))
        
        let fragmentRect = layoutManager.lineFragmentRect(forGlyphAt: firstGlyph, effectiveRange: nil)
        #expect(abs(fragmentRect.height - max(layoutManager.lineHeight, wideCardSize.height + 8)) < 1.5)
        
        // 4. Single Backspace immediately after `⟦🖼 ...⟧` deletes the entire token atomically
        let tokenLen = (storedWide.token as NSString).length
        textView.setSelectedRange(NSRange(location: tokenLen, length: 0))
        textView.deleteBackward(nil)
        #expect(textView.string == "\n正文")
    }
    
    
    @Test func modernOverlayVerticalScrollerEnabledOnEditor() throws {
        
        let doc = Document()
        doc.textStorage.replaceCharacters(in: doc.textStorage.range, with: String(repeating: "Line\n", count: 120))
        let editorVC = EditorTextViewController(document: doc)
        editorVC.loadViewIfNeeded()
        editorVC.view.frame = NSRect(x: 0, y: 0, width: 520, height: 300)
        editorVC.view.layoutSubtreeIfNeeded()
        
        let scrollView = try #require(editorVC.textView.enclosingScrollView)
        #expect(scrollView.scrollerStyle == .overlay)
        let verticalScroller = try #require(scrollView.verticalScroller)
        #expect(String(describing: type(of: verticalScroller)) == "ModernVerticalScroller")
        #expect(type(of: verticalScroller).scrollerWidth(for: .regular, scrollerStyle: .overlay) == 11)
        
        // Remains overlay even if AppKit / mouse-style tries switching to `.legacy`
        scrollView.scrollerStyle = .legacy
        #expect(scrollView.scrollerStyle == .overlay)
    }
    
    
    @Test func smoothAppearanceTransitionUpdatesAndCleansOverlay() async {
        
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 220),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.animationBehavior = .none
        window.appearance = NSAppearance(named: .aqua)
        window.orderFront(nil)
        defer { window.orderOut(nil) }
        
        window.performSmoothAppearanceTransition(duration: 0.05) {
            window.appearance = NSAppearance(named: .darkAqua)
        }
        #expect(window.appearance?.name == .darkAqua)
        
        try? await Task.sleep(for: .milliseconds(200))
        #expect(window.isAppearanceTransitionActive == false)
    }
    
    
    @Test func settingsDefaultChineseAndNoNestedListScrollTrap() throws {
        
        let suiteName = "Round15LanguageTest.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        
        AppLanguage.ensureDefaultInitialized(defaults: defaults)
        #expect(AppLanguage.current(in: defaults) == .simplifiedChinese)
        // `CotEditor.xcscheme` passes `-AppleLanguages (en)` in `NSArgumentDomain` during XCTest,
        // so inspect the suite's persisted domain directly.
        let persistedChineseDomain = defaults.persistentDomain(forName: suiteName)
        #expect(persistedChineseDomain?[AppLanguage.explicitPreferenceKey] as? String == AppLanguage.simplifiedChinese.rawValue)
        #expect(persistedChineseDomain?["AppleLanguages"] as? [String] == ["zh-Hans"])
        
        AppLanguage.english.apply(to: defaults)
        AppLanguage.ensureDefaultInitialized(defaults: defaults)
        #expect(AppLanguage.current(in: defaults) == .english)
        #expect(defaults.persistentDomain(forName: suiteName)?["AppleLanguages"] as? [String] == ["en"])
        
        // Verify AI & AI Persona panes have no nested NSTableView (no List scroll trap) and keep 660x500 frame
        for pane in [SettingsPane.ai, SettingsPane.aiPersona] {
            let host = NSHostingController(rootView: AnyView(pane.view))
            host.view.frame = NSRect(x: 0, y: 0, width: SettingsPaneLayout.width, height: SettingsPaneLayout.height)
            host.view.layoutSubtreeIfNeeded()
            let size = host.view.fittingSize
            #expect(abs(size.width - SettingsPaneLayout.width) <= 1)
            #expect(abs(size.height - SettingsPaneLayout.height) <= 1)
            #expect(Self.descendants(ofType: NSTableView.self, in: host.view).isEmpty)
        }
    }
    
    
    @Test func nextTokenMidLineShiftOverlapTrimAndSanitization() {
        
        // Suffix overlap trimming prevents duplicate `)` in `后面整体就变成|)`
        #expect(UserHabitPredictor.trimOverlapWithLineSuffix("周报)", lineSuffix: ")") == "周报")
        #expect(UserHabitPredictor.trimOverlapWithLineSuffix("进行一次commit，", lineSuffix: "，测试") == "进行一次commit")
        #expect(UserHabitPredictor.trimOverlapWithLineSuffix(")", lineSuffix: ")") == nil)
        
        // Partial chunk splitting for Option + Right Arrow
        let cjkSplit = UserHabitPredictor.splitFirstAcceptUnit(from: "进行一次commit")
        #expect(cjkSplit.accepted == "进行")
        #expect(cjkSplit.remainder == "一次commit")
        
        let asciiSplit = UserHabitPredictor.splitFirstAcceptUnit(from: "hello world")
        #expect(asciiSplit.accepted == "hello ")
        #expect(asciiSplit.remainder == "world")
        
        // AI FIM response sanitization strips code fences, echoed prefix, and trailing suffix overlap
        let sanitized = AINextTokenPredictor.sanitizeCompletion(
            raw: "```txt\n进行一次commit)\n```",
            linePrefix: "搞定以后进行",
            lineSuffix: ")"
        )
        #expect(sanitized == "一次commit")
        #expect(AINextTokenPredictor.sanitizeCompletion(raw: "EMPTY", linePrefix: "hello", lineSuffix: "") == nil)
        
        // LayoutManager.inlineGhostShift tracks mid-line caret shift cleanly
        let storage = NSTextStorage(string: "后面整体就变成)")
        let lm = LayoutManager(lineEndingScanner: LineEndingScanner(textStorage: storage, lineEnding: .lf))
        let tc = NSTextContainer(size: NSSize(width: 400, height: 400))
        storage.addLayoutManager(lm)
        lm.addTextContainer(tc)
        lm.ensureLayout(forCharacterRange: NSRange(location: 0, length: storage.length))
        
        lm.inlineGhostShift = LayoutManager.InlineGhostShift(caretLocation: 7, shiftWidth: 28)
        #expect(lm.inlineGhostShift?.caretLocation == 7)
        #expect(lm.inlineGhostShift?.shiftWidth == 28)
        lm.inlineGhostShift = nil
        #expect(lm.inlineGhostShift == nil)
    }
    
    
    // MARK: Private Helpers
    
    private static func makeSolidImage(pixelWidth: Int, pixelHeight: Int, color: NSColor) -> NSImage {
        
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelWidth,
            pixelsHigh: pixelHeight,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        color.setFill()
        NSRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight).fill()
        NSGraphicsContext.restoreGraphicsState()
        
        let image = NSImage(size: NSSize(width: pixelWidth, height: pixelHeight))
        image.addRepresentation(rep)
        return image
    }
    
    
    private static func descendants<T: NSView>(ofType type: T.Type, in view: NSView) -> [T] {
        
        var matches: [T] = []
        if let typed = view as? T {
            matches.append(typed)
        }
        for subview in view.subviews {
            matches.append(contentsOf: Self.descendants(ofType: type, in: subview))
        }
        return matches
    }
}
