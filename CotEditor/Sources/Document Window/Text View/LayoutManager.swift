//
//  LayoutManager.swift
//
//  CotEditor
//  https://coteditor.com
//
//  Created by nakamuxu on 2005-01-10.
//
//  ---------------------------------------------------------------------------
//
//  © 2004-2007 nakamuxu
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

import AppKit
import Invisible
import StringUtils

class LayoutManager: NSLayoutManager, InvisibleDrawing, ValidationIgnorable {
    
    // MARK: Protocol Properties
    
    // InvisibleDrawing
    var showsControls = false
    var shownInvisibles: Set<Invisible> = []  { didSet { self.invalidateInvisibleDisplay() } }
    
    // ValidationIgnorable
    var ignoresDisplayValidation = false
    
    
    // MARK: Public Properties
    
    let lineEndingScanner: LineEndingScanner
    
    var usesAntialias = true
    
    var textFont: NSFont = .systemFont(ofSize: 0) {
        
        // store text font to avoid the issue where the line height can be inconsistent by using a fallback font
        // -> DO NOT use `self.firstTextView?.font`, because when the specified font doesn't support
        //    the first character of the text view content, it returns a fallback font for the first one.
        didSet {
            // cache metric values
            self.defaultLineHeight = self.defaultLineHeight(for: textFont)
            self.defaultBaselineOffset = self.defaultBaselineOffset(for: textFont)
            self.boundingBoxForControlGlyph = self.boundingBoxForControlGlyph(for: textFont)
        }
    }
    
    var showsInvisibles = false {
        
        didSet {
            guard showsInvisibles != oldValue else { return }
            
            self.invalidateInvisibleDisplay()
        }
    }
    
    var invisiblesColor: NSColor = .disabledControlTextColor
    var unemphasizedSelectedContentBackgroundColor: NSColor?
    
    struct InlineGhostShift: Equatable {
        
        var caretLocation: Int
        var shiftWidth: CGFloat
    }
    
    var showsIndentGuides = false  { didSet { self.invalidateDisplay(forCharacterRange: self.attributedString().range) } }
    var tabWidth = 0
    var lineHeightMultiple: CGFloat = 1.0
    var inlineGhostShift: InlineGhostShift? {
        didSet {
            guard inlineGhostShift != oldValue else { return }
            self.invalidateLineDisplay(around: oldValue?.caretLocation)
            self.invalidateLineDisplay(around: inlineGhostShift?.caretLocation)
        }
    }
    var rendersPlainTextInlineImages = false {
        didSet {
            guard rendersPlainTextInlineImages != oldValue else { return }
            self.invalidateInlineImageLayout()
        }
    }
    var inlineImageDocumentURL: URL? {
        didSet {
            guard inlineImageDocumentURL != oldValue, self.rendersPlainTextInlineImages else { return }
            self.invalidateInlineImageLayout()
        }
    }
    
    
    // MARK: Private Properties
    
    private var defaultLineHeight: CGFloat = 1.0
    private var defaultBaselineOffset: CGFloat = 0
    private var boundingBoxForControlGlyph: NSRect = .zero
    private var hasResolvedInlineImageGlyphs = false
    
    
    // MARK: Lifecycle
    
    init(lineEndingScanner: LineEndingScanner) {
        
        self.lineEndingScanner = lineEndingScanner
        
        super.init()
        
        self.delegate = self
        self.allowsNonContiguousLayout = true
    }
    
    
    required init?(coder: NSCoder) {
        
        fatalError("init(coder:) has not been implemented")
    }
    
    
    // MARK: Layout Manager Methods
    
    /// Adjusts rect of last empty line.
    override func setExtraLineFragmentRect(_ fragmentRect: NSRect, usedRect: NSRect, textContainer container: NSTextContainer) {
        
        // -> The height of the extra line fragment should be the same as other normal fragments that are likewise customized in the delegate.
        var fragmentRect = fragmentRect
        fragmentRect.size.height = self.lineHeight
        var usedRect = usedRect
        usedRect.size.height = self.lineHeight
        
        super.setExtraLineFragmentRect(fragmentRect, usedRect: usedRect, textContainer: container)
    }
    
    
    /// Synchronizes full-line glyph properties when edits touch lines with `⟦🖼 ...⟧` inline image tokens.
    override func processEditing(for textStorage: NSTextStorage, edited editMask: NSTextStorageEditActions, range newCharRange: NSRange, changeInLength delta: Int, invalidatedRange invalidatedCharRange: NSRange) {
        
        super.processEditing(for: textStorage, edited: editMask, range: newCharRange, changeInLength: delta, invalidatedRange: invalidatedCharRange)
        
        guard self.rendersPlainTextInlineImages, editMask.contains(.editedCharacters) else { return }
        
        let nsString = textStorage.string as NSString
        guard nsString.length > 0 else {
            self.hasResolvedInlineImageGlyphs = false
            return
        }
        
        let safeLoc = min(max(0, invalidatedCharRange.location), nsString.length)
        let maxLen = max(0, nsString.length - safeLoc)
        let safeRange = NSRange(location: safeLoc, length: min(max(0, invalidatedCharRange.length), maxLen))
        let probeRange = (safeRange.location == nsString.length && nsString.length > 0)
            ? NSRange(location: nsString.length - 1, length: 1)
            : safeRange
        let lineRange = nsString.lineRange(for: probeRange)
        guard lineRange.length > 0, NSMaxRange(lineRange) <= nsString.length else { return }
        
        let lineSlice = nsString.substring(with: lineRange)
        let touchesTokenMarker = lineSlice.contains("⟦") || lineSlice.contains("⟧")
        guard touchesTokenMarker || self.hasResolvedInlineImageGlyphs else { return }
        
        // Expand glyph and layout invalidation to the full enclosing line so partial edits
        // to `⟦🖼 ...⟧` tokens never leave orphaned `.controlCharacter` / `.null` glyphs.
        if lineRange.location < invalidatedCharRange.location || NSMaxRange(lineRange) > NSMaxRange(invalidatedCharRange) {
            self.invalidateGlyphs(forCharacterRange: lineRange, changeInLength: 0, actualCharacterRange: nil)
            self.invalidateLayout(forCharacterRange: lineRange, actualCharacterRange: nil)
        }
    }
    
    
    /// Draws glyphs.
    override func drawGlyphs(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        
        guard glyphsToShow.location != NSNotFound, glyphsToShow.length > 0 else { return }
        
        NSGraphicsContext.saveGraphicsState()
        
        if NSGraphicsContext.currentContextDrawingToScreen() {
            NSGraphicsContext.current?.shouldAntialias = self.usesAntialias
        }
        
        if self.showsIndentGuides {
            self.drawIndentGuides(forGlyphRange: glyphsToShow, at: origin, color: self.invisiblesColor, tabWidth: self.tabWidth)
        }
        
        if self.showsInvisibles {
            self.drawInvisibles(forGlyphRange: glyphsToShow, at: origin, baselineOffset: self.baselineOffset(for: .horizontal))
        }
        
        if let shift = self.inlineGhostShift, shift.shiftWidth > 0,
           shift.caretLocation >= 0, shift.caretLocation < self.attributedString().length
        {
            let nsString = self.attributedString().string as NSString
            let nextCodeUnit = nsString.character(at: shift.caretLocation)
            if nextCodeUnit != 0xA, nextCodeUnit != 0xD {
                let caretGlyphIndex = self.glyphIndexForCharacter(at: shift.caretLocation)
                if self.isValidGlyphIndex(caretGlyphIndex) {
                    var lineGlyphRange = NSRange.notFound
                    _ = self.lineFragmentRect(forGlyphAt: caretGlyphIndex, effectiveRange: &lineGlyphRange, withoutAdditionalLayout: true)
                    if lineGlyphRange.location != NSNotFound, lineGlyphRange.length > 0, lineGlyphRange.upperBound > caretGlyphIndex {
                        let tailLength = lineGlyphRange.upperBound - caretGlyphIndex
                        let shiftedRange = NSIntersectionRange(glyphsToShow, NSRange(location: caretGlyphIndex, length: tailLength))
                        if shiftedRange.length > 0 {
                            if shiftedRange.location > glyphsToShow.location {
                                let beforeRange = NSRange(location: glyphsToShow.location, length: shiftedRange.location - glyphsToShow.location)
                                super.drawGlyphs(forGlyphRange: beforeRange, at: origin)
                            }
                            super.drawGlyphs(forGlyphRange: shiftedRange, at: NSPoint(x: origin.x + shift.shiftWidth, y: origin.y))
                            if NSMaxRange(shiftedRange) < NSMaxRange(glyphsToShow) {
                                let afterRange = NSRange(location: NSMaxRange(shiftedRange), length: NSMaxRange(glyphsToShow) - NSMaxRange(shiftedRange))
                                super.drawGlyphs(forGlyphRange: afterRange, at: origin)
                            }
                            NSGraphicsContext.restoreGraphicsState()
                            return
                        }
                    }
                }
            }
        }
        
        super.drawGlyphs(forGlyphRange: glyphsToShow, at: origin)
        
        NSGraphicsContext.restoreGraphicsState()
    }
    
    
    /// Draws underline.
    override func drawUnderline(forGlyphRange glyphRange: NSRange, underlineType underlineVal: NSUnderlineStyle, baselineOffset: CGFloat, lineFragmentRect lineRect: NSRect, lineFragmentGlyphRange lineGlyphRange: NSRange, containerOrigin: NSPoint) {
        
        // move single underline position on the vertical orientation to the left side.
        if underlineVal == .single,
           let container = self.textContainer(forGlyphAt: glyphRange.location, effectiveRange: nil),
           container.layoutOrientation == .vertical
        {
            let rect = self.boundingRect(forGlyphRange: glyphRange, in: container).offset(by: containerOrigin)
            let underlineRect = NSRect(x: rect.minX, y: rect.midY + self.defaultLineHeight / 2 - 1, width: rect.width, height: 1)
            
            return underlineRect.fill()
        }
        
        super.drawUnderline(forGlyphRange: glyphRange, underlineType: underlineVal, baselineOffset: baselineOffset, lineFragmentRect: lineRect, lineFragmentGlyphRange: lineGlyphRange, containerOrigin: containerOrigin)
    }
    
    
    /// Fills background rectangles with a color.
    override func fillBackgroundRectArray(_ rectArray: UnsafePointer<NSRect>, count rectCount: Int, forCharacterRange charRange: NSRange, color: NSColor) {
        
        // modify selected highlight color when the window is inactive
        // -> Otherwise, `.unemphasizedSelectedContentBackgroundColor` will be used forcibly and text becomes unreadable
        //    when the window appearance and theme are inconsistent.
        if color == .unemphasizedSelectedContentBackgroundColor,  // check if inactive
           let newColor = self.unemphasizedSelectedContentBackgroundColor,
           newColor != color
        {
            newColor.setFill()
        }
        
        super.fillBackgroundRectArray(rectArray, count: rectCount, forCharacterRange: charRange, color: color)
    }
    
    
    /// Invalidates display for the given character range.
    override func invalidateDisplay(forCharacterRange charRange: NSRange) {
        
        // ignore display validation during applying temporary attributes continuously
        // -> See `NSLayoutManager.groupTemporaryAttributesUpdate(in:work:)` for the usage of this option.
        if self.ignoresDisplayValidation { return }
        
        super.invalidateDisplay(forCharacterRange: charRange)
    }
    
    
    override func setGlyphs(_ glyphs: UnsafePointer<CGGlyph>, properties props: UnsafePointer<NSLayoutManager.GlyphProperty>, characterIndexes charIndexes: UnsafePointer<Int>, font aFont: NSFont, forGlyphRange glyphRange: NSRange) {
        
        guard glyphRange.length > 0 else {
            super.setGlyphs(glyphs, properties: props, characterIndexes: charIndexes, font: aFont, forGlyphRange: glyphRange)
            return
        }
        
        var copiedProps: [NSLayoutManager.GlyphProperty]?
        
        // fix the width of whitespace when the base font is fixed pitch.
        if self.textFont.isFixedPitch {
            var mutableProps = Array(UnsafeBufferPointer(start: props, count: glyphRange.length))
            for index in 0..<glyphRange.length {
                mutableProps[index].subtract(.elastic)
            }
            copiedProps = mutableProps
        }
        
        if self.rendersPlainTextInlineImages {
            let nsString = self.attributedString().string as NSString
            if nsString.length > 0 {
                var minChar = nsString.length - 1
                var maxChar = 0
                for index in 0..<glyphRange.length {
                    let c = charIndexes[index]
                    if c >= 0, c < nsString.length {
                        if c < minChar { minChar = c }
                        if c > maxChar { maxChar = c }
                    }
                }
                if minChar <= maxChar {
                    let span = NSRange(location: minChar, length: maxChar - minChar + 1)
                    let lineRange = nsString.lineRange(for: span)
                    let lineSlice = nsString.substring(with: lineRange)
                    if lineSlice.contains("⟦🖼"), lineSlice.contains("⟧") {
                        let resolvedTokens = PlainTextInlineImageStore.shared.findTokens(in: nsString, range: lineRange)
                            .filter { PlainTextInlineImageStore.shared.image(for: $0.identifier, documentURL: self.inlineImageDocumentURL) != nil }
                        if !resolvedTokens.isEmpty {
                            var mutableProps = copiedProps ?? Array(UnsafeBufferPointer(start: props, count: glyphRange.length))
                            for index in 0..<glyphRange.length {
                                let charIndex = charIndexes[index]
                                guard charIndex >= 0, charIndex < nsString.length else { continue }
                                for token in resolvedTokens where NSLocationInRange(charIndex, token.range) {
                                    mutableProps[index] = (charIndex == token.range.location) ? .controlCharacter : .null
                                    self.hasResolvedInlineImageGlyphs = true
                                    break
                                }
                            }
                            copiedProps = mutableProps
                        }
                    }
                }
            }
        }
        
        if let copiedProps {
            copiedProps.withUnsafeBufferPointer { buffer in
                super.setGlyphs(glyphs, properties: buffer.baseAddress!, characterIndexes: charIndexes, font: aFont, forGlyphRange: glyphRange)
            }
        } else {
            super.setGlyphs(glyphs, properties: props, characterIndexes: charIndexes, font: aFont, forGlyphRange: glyphRange)
        }
    }
    
    
    // MARK: Invisible Drawing Methods
    
    func isInvalidInvisible(_ invisible: Invisible, at characterIndex: Int) -> Bool {
        
        switch invisible {
            case .newLine:
                self.lineEndingScanner.isInvalidLineEnding(at: characterIndex)
            default:
                false
        }
    }
    
    
    // MARK: Public Methods
    
    /// Fixed line height to avoid having different line height by composite font.
    var lineHeight: CGFloat {
        
        self.lineHeightMultiple * self.defaultLineHeight
    }
    
    
    /// Returns adjusted baseline offset to place glyphs vertically in the middle of a line.
    ///
    /// - Parameter layoutOrientation: The text layout orientation.
    /// - Returns: The baseline offset.
    func baselineOffset(for layoutOrientation: TextLayoutOrientation) -> CGFloat {
        
        switch layoutOrientation {
            case .vertical:
                return self.lineHeight / 2
            case .horizontal:
                // remove the space above to make glyphs visually center
                let diff = self.textFont.ascender - self.textFont.capHeight
                return (self.lineHeight + self.defaultBaselineOffset - diff) / 2
            @unknown default: fatalError()
        }
    }
    
    
    // MARK: Inline Image Layout Invalidation
    
    func invalidateInlineImageLayout() {
        
        self.hasResolvedInlineImageGlyphs = false
        let length = self.textStorage?.length ?? self.attributedString().length
        guard length > 0 else { return }
        
        let wholeRange = NSRange(location: 0, length: length)
        self.invalidateGlyphs(forCharacterRange: wholeRange, changeInLength: 0, actualCharacterRange: nil)
        self.invalidateLayout(forCharacterRange: wholeRange, actualCharacterRange: nil)
        self.invalidateDisplay(forCharacterRange: wholeRange)
    }
    
    
    // MARK: Private Methods
    
    
    private func invalidateLineDisplay(around charLocation: Int?) {
        
        guard let charLocation, charLocation >= 0 else { return }
        let nsString = self.attributedString().string as NSString
        guard nsString.length > 0 else { return }
        let safeLoc = min(charLocation, max(0, nsString.length - 1))
        let lineRange = nsString.lineRange(for: NSRange(location: safeLoc, length: 0))
        self.invalidateDisplay(forCharacterRange: lineRange)
        
        guard Thread.isMainThread else { return }
        let glyphRange = self.glyphRange(forCharacterRange: lineRange, actualCharacterRange: nil)
        guard glyphRange.location != NSNotFound, glyphRange.length > 0,
              self.isValidGlyphIndex(glyphRange.location)
        else { return }
        let frag = self.lineFragmentRect(forGlyphAt: glyphRange.location, effectiveRange: nil, withoutAdditionalLayout: true)
        MainActor.assumeIsolated {
            guard let textView = self.firstTextView else { return }
            var dirty = frag.offset(by: textView.textContainerOrigin)
            dirty.origin.x = 0
            dirty.size.width = max(textView.bounds.width, dirty.maxX + 400)
            textView.setNeedsDisplay(dirty.insetBy(dx: -4, dy: -4), avoidAdditionalLayout: true)
        }
    }
    
    
    /// Resolves a finite container width even when line wrapping is disabled (`textContainer.size.width == .greatestFiniteMagnitude`).
    private func finiteContainerWidth(for textContainer: NSTextContainer, fallback: CGFloat) -> CGFloat {
        
        let raw = textContainer.size.width
        if raw.isFinite, raw > 0, raw <= 100_000 {
            return raw
        }
        if fallback.isFinite, fallback > 0, fallback <= 100_000 {
            return fallback
        }
        return 800
    }
    
    
    private func resolvedInlineImageToken(startingAt charIndex: Int) -> (range: NSRange, identifier: String)? {
        
        guard self.rendersPlainTextInlineImages else { return nil }
        let nsString = self.attributedString().string as NSString
        guard charIndex >= 0, charIndex < nsString.length, nsString.character(at: charIndex) == 0x27E6 else { return nil }
        let lineRange = nsString.lineRange(for: NSRange(location: charIndex, length: 0))
        let tokens = PlainTextInlineImageStore.shared.findTokens(in: nsString, range: lineRange)
        guard let match = tokens.first(where: { $0.range.location == charIndex }),
              PlainTextInlineImageStore.shared.image(for: match.identifier, documentURL: self.inlineImageDocumentURL) != nil
        else { return nil }
        return match
    }
}


extension LayoutManager: NSLayoutManagerDelegate {
    
    /// Adjusts line height to be all the same (or expands cleanly to host inline images without a visible title row).
    func layoutManager(_ layoutManager: NSLayoutManager, shouldSetLineFragmentRect lineFragmentRect: UnsafeMutablePointer<NSRect>, lineFragmentUsedRect: UnsafeMutablePointer<NSRect>, baselineOffset: UnsafeMutablePointer<CGFloat>, in textContainer: NSTextContainer, forGlyphRange glyphRange: NSRange) -> Bool {
        
        // avoid inconsistent line height by a composite font
        // -> The line height by normal input keeps consistent when overriding the related methods in NSLayoutManager.
        //    but then, the drawing won't be update properly when the font or line height is changed.
        // -> NSParagraphStyle's `.lineHeightMultiple` can also control the line height,
        //    but it causes an issue when the first character of the string uses a fallback font.
        var tallestCard: CGFloat = 0
        if self.rendersPlainTextInlineImages, textContainer.layoutOrientation == .horizontal,
           glyphRange.location != NSNotFound, glyphRange.length > 0
        {
            let charRange = self.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
            let string = self.attributedString().string as NSString
            if charRange.location != NSNotFound, string.length > 0 {
                let safeRange = NSIntersectionRange(charRange, NSRange(location: 0, length: string.length))
                if safeRange.length > 0 {
                    let lineSubstring = string.substring(with: safeRange)
                    if lineSubstring.contains("⟦🖼"), lineSubstring.contains("⟧") {
                        let tokens = PlainTextInlineImageStore.shared.findTokens(in: string, range: safeRange)
                        let containerW = self.finiteContainerWidth(for: textContainer, fallback: lineFragmentRect.pointee.width)
                        let maxCardWidth = PlainTextInlineImageStore.effectiveMaxImageWidth(containerWidth: containerW, glyphX: 0)
                        for token in tokens {
                            if let size = PlainTextInlineImageStore.shared.cardSize(
                                for: token.identifier,
                                documentURL: self.inlineImageDocumentURL,
                                maxImageWidth: maxCardWidth,
                                containerWidth: containerW
                            ) {
                                tallestCard = max(tallestCard, size.height)
                            }
                        }
                    }
                }
            }
        }
        
        lineFragmentRect.pointee.size.height = (tallestCard > 0) ? max(self.lineHeight, tallestCard + 8) : self.lineHeight
        lineFragmentUsedRect.pointee.size.height = self.lineHeight
        
        // vertically center the glyphs in the top text line of the fragment
        baselineOffset.pointee = self.baselineOffset(for: textContainer.layoutOrientation)
        
        return true
    }
    
    
    /// Treats control characters as whitespace to draw replacement glyphs.
    func layoutManager(_ layoutManager: NSLayoutManager, shouldUse action: NSLayoutManager.ControlCharacterAction, forControlCharacterAt charIndex: Int) -> NSLayoutManager.ControlCharacterAction {
        
        if self.rendersPlainTextInlineImages, self.resolvedInlineImageToken(startingAt: charIndex) != nil {
            return .whitespace
        }
        
        // -> Then, the glyph width can be modified in `layoutManager(_:boundingBoxForControlGlyphAt:...)`.
        return self.showsControlCharacter(at: charIndex, proposedAction: action) ? .whitespace : action
    }
    
    
    /// Makes a blank space to draw the replacement glyph in `drawGlyphs(forGlyphRange:at:)` later.
    func layoutManager(_ layoutManager: NSLayoutManager, boundingBoxForControlGlyphAt glyphIndex: Int, for textContainer: NSTextContainer, proposedLineFragment proposedRect: NSRect, glyphPosition: NSPoint, characterIndex charIndex: Int) -> NSRect {
        
        if self.rendersPlainTextInlineImages,
           textContainer.layoutOrientation == .horizontal,
           let token = self.resolvedInlineImageToken(startingAt: charIndex)
        {
            let containerW = self.finiteContainerWidth(for: textContainer, fallback: proposedRect.width)
            let effectiveProposedW = (proposedRect.width.isFinite && proposedRect.width > 0 && proposedRect.width <= 100_000)
                ? proposedRect.width
                : containerW
            if let cardSize = PlainTextInlineImageStore.shared.cardSize(
                for: token.identifier,
                documentURL: self.inlineImageDocumentURL,
                maxImageWidth: PlainTextInlineImageStore.effectiveMaxImageWidth(containerWidth: effectiveProposedW, glyphX: glyphPosition.x),
                containerWidth: containerW
            ) {
                let width = min(cardSize.width + 4, max(40, effectiveProposedW - glyphPosition.x - 4))
                if width.isFinite, width > 0 {
                    return NSRect(x: 0, y: 0, width: width, height: self.lineHeight)
                }
            }
        }
        
        return self.boundingBoxForControlGlyph
    }
    
    
    /// Avoids soft wrapping just after indent.
    func layoutManager(_ layoutManager: NSLayoutManager, shouldBreakLineByWordBeforeCharacterAt charIndex: Int) -> Bool {
        
        // check if the character is the first non-whitespace character after indent
        let string = self.attributedString().string as NSString
        
        for index in stride(from: charIndex - 1, through: 0, by: -1) {
            switch string.character(at: index) {
                case 0x9, 0x20:  // tab, space
                    continue
                case 0xA, 0xD, 0x85, 0x2028, 0x2029:  // newlines
                    return index == charIndex - 1
                default:
                    return true
            }
        }
        
        return charIndex == 0
    }
    
    
    /// Applies syntax highlighting and Notes-style highlight foreground tints without mutating syntax attributes.
    func layoutManager(_ layoutManager: NSLayoutManager, shouldUseTemporaryAttributes attrs: [NSAttributedString.Key: Any] = [:], forDrawingToScreen toScreen: Bool, atCharacterIndex charIndex: Int, effectiveRange effectiveCharRange: NSRangePointer?) -> [NSAttributedString.Key: Any]? {
        
        if let noteColor = attrs[.notesHighlightTextColor] as? NSColor {
            var updated = attrs
            updated[.foregroundColor] = noteColor
            return updated
        }
        return attrs
    }
}


// MARK: Private Extension

private extension NSLayoutManager {
    
    /// Draw indent guides at every given indent width.
    ///
    /// - Parameters:
    ///   - glyphsToShow: The range of glyphs that are drawn.
    ///   - origin: The position of the text container in the coordinate system of the currently focused view.
    ///   - color: The color of guides.
    ///   - tabWidth: The number of spaces for an indent.
    func drawIndentGuides(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint, color: NSColor, tabWidth: Int) {
        
        guard tabWidth > 0 else { return assertionFailure() }
        
        // calculate characterRange to seek
        let string = self.attributedString().string as NSString
        let charactersToShow = self.characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)
        let lineStartIndex = string.lineStartIndex(at: charactersToShow.location)
        let characterRange = NSRange(location: lineStartIndex, length: charactersToShow.upperBound - lineStartIndex)
        
        // find indent indexes
        var indentIndexes: [(lineRange: NSRange, indexes: [Int])] = []
        string.enumerateSubstrings(in: characterRange, options: [.byLines, .substringNotRequired]) { _, range, _, _ in
            var indexes: [Int] = []
            var spaceCount = 0
            loop: for characterIndex in range.lowerBound..<range.upperBound {
                let isIndentLevel = spaceCount.isMultiple(of: tabWidth) && spaceCount > 0
                
                switch string.character(at: characterIndex) {
                    case 0x20:  // space
                        spaceCount += 1
                    case 0x9:  // tab
                        spaceCount += tabWidth - (spaceCount % tabWidth)
                    default:
                        break loop
                }
                
                if isIndentLevel {
                    indexes.append(characterIndex)
                }
            }
            
            guard !indexes.isEmpty else { return }
            
            indentIndexes.append((range, indexes))
        }
        
        guard !indentIndexes.isEmpty else { return }
        
        NSGraphicsContext.saveGraphicsState()
        
        color.set()
        let lineWidth: CGFloat = 0.5
        let scaleFactor = NSGraphicsContext.current?.cgContext.ctm.a ?? 1
        
        // draw guides logical line by logical line
        for (lineRange, indexes) in indentIndexes {
            // calculate vertical area to draw lines
            let glyphIndex = self.glyphIndexForCharacter(at: lineRange.location)
            var effectiveRange: NSRange = .notFound
            let lineFragment = self.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: &effectiveRange)
            let guideLength: CGFloat = {
                guard !effectiveRange.contains(lineRange.upperBound - 1) else { return lineFragment.height }
                
                let lastGlyphIndex = self.glyphIndexForCharacter(at: lineRange.upperBound - 1)
                let lastLineFragment = self.lineFragmentRect(forGlyphAt: lastGlyphIndex, effectiveRange: nil)
                
                // check whether hanging indent is enabled
                guard lastLineFragment.minX != lineFragment.minX else { return lineFragment.height }
                
                return lastLineFragment.maxY - lineFragment.minY
            }()
            let guideSize = NSSize(width: lineWidth, height: guideLength)
            
            // draw lines
            for index in indexes {
                let glyphIndex = self.glyphIndexForCharacter(at: index)
                let glyphLocation = self.location(forGlyphAt: glyphIndex)
                let guideOrigin = lineFragment.origin.offset(by: origin).offsetBy(dx: glyphLocation.x).aligned(scale: scaleFactor)
                let guideRect = NSRect(origin: guideOrigin, size: guideSize)
                
                guideRect.fill()
            }
        }
        
        NSGraphicsContext.restoreGraphicsState()
    }
}


private extension CGPoint {
    
    /// Make the point pixel-perfect with the desired scale.
    ///
    /// - Parameter scale: The scale factor in which the receiver to be pixel-perfect.
    /// - Returns: An adjusted point.
    func aligned(scale: CGFloat = 1) -> Self {
        
        Self(x: (self.x * scale).rounded() / scale,
             y: (self.y * scale).rounded() / scale)
    }
}
