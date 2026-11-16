//
//  AIAnswerFormatter.swift
//
//  CotEditor
//  https://coteditor.com
//
//  Created by 1024jp on 2026-11-16.
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

/// Turns a model's answer into the text the result sheet shows.
///
/// Answers arrive as Markdown. Printing those bytes verbatim shows `-`, `##` and `**` literally,
/// which is what makes a raw answer look like a log. This renders the block shapes a chat answer
/// actually uses — paragraphs, headings, lists, quotes and fenced code — and hands every run of
/// running text to Foundation's own inline parser, so emphasis, inline code and links come out
/// as text rather than as punctuation.
///
/// It deliberately does not try to be a full Markdown implementation: tables, images and
/// reference links fall back to their plain text, because an editor's answer sheet is not a
/// preview pane.
enum AIAnswerFormatter {
    
    /// Renders the answer.
    ///
    /// - Parameter markdown: The answer as the model returned it.
    /// - Returns: The attributed text to display.
    static func attributedString(from markdown: String) -> NSAttributedString {
        
        let text = markdown
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let lines = text.components(separatedBy: "\n")
        
        let output = NSMutableAttributedString()
        var index = 0
        
        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            if trimmed.isEmpty {
                index += 1
                continue
            }
            
            if trimmed.hasPrefix("```") {
                var code: [String] = []
                index += 1
                while index < lines.count, !lines[index].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                    code.append(lines[index])
                    index += 1
                }
                index += 1
                
                output.append(self.codeBlock(code.joined(separator: "\n")))
                continue
            }
            
            if let heading = self.heading(in: trimmed) {
                output.append(self.heading(heading.text, level: heading.level))
                index += 1
                continue
            }
            
            if let item = self.listItem(in: line) {
                output.append(self.listItem(item.text, marker: item.marker, depth: item.depth))
                index += 1
                continue
            }
            
            if trimmed.hasPrefix(">") {
                output.append(self.quote(String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)))
                index += 1
                continue
            }
            
            if ["---", "***", "___"].contains(trimmed) {
                output.append(self.rule())
                index += 1
                continue
            }
            
            var paragraph = [trimmed]
            index += 1
            while index < lines.count, !self.startsBlock(lines[index]) {
                paragraph.append(lines[index].trimmingCharacters(in: .whitespaces))
                index += 1
            }
            
            output.append(self.paragraph(paragraph.joined(separator: " ")))
        }
        
        return output
    }
    
    
    // MARK: Private Block Builders
    
    private static func paragraph(_ text: String) -> NSAttributedString {
        
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 2
        style.paragraphSpacing = 8
        
        return self.block(self.inline(text, font: .systemFont(ofSize: 13)), style: style)
    }
    
    
    private static func heading(_ text: String, level: Int) -> NSAttributedString {
        
        let size: CGFloat = switch level {
            case 1: 16
            case 2: 14.5
            default: 13
        }
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 2
        style.paragraphSpacingBefore = level == 1 ? 10 : 8
        style.paragraphSpacing = 4
        
        return self.block(self.inline(text, font: .systemFont(ofSize: size, weight: .semibold)), style: style)
    }
    
    
    private static func listItem(_ text: String, marker: String, depth: Int) -> NSAttributedString {
        
        let indent = 4 + CGFloat(depth) * 16
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 2
        style.paragraphSpacing = 4
        style.firstLineHeadIndent = indent
        style.headIndent = indent + 16
        
        let body = NSMutableAttributedString(string: marker + "  ")
        body.append(self.inline(text, font: .systemFont(ofSize: 13)))
        
        return self.block(body, style: style)
    }
    
    
    private static func quote(_ text: String) -> NSAttributedString {
        
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 2
        style.paragraphSpacing = 8
        style.firstLineHeadIndent = 12
        style.headIndent = 12
        
        let body = self.inline(text, font: .systemFont(ofSize: 13), color: .secondaryLabelColor)
        
        return self.block(body, style: style)
    }
    
    
    private static func codeBlock(_ code: String) -> NSAttributedString {
        
        let lines = code.components(separatedBy: "\n")
        let block = NSMutableAttributedString()
        
        // Every line is its own paragraph, so the spacing belongs to the block's edges rather
        // than to the gaps between its lines.
        for (index, line) in lines.enumerated() {
            let style = NSMutableParagraphStyle()
            style.lineSpacing = 1.5
            style.firstLineHeadIndent = 10
            style.headIndent = 10
            if index == 0 {
                style.paragraphSpacingBefore = 6
            }
            if index == lines.count - 1 {
                style.paragraphSpacing = 10
            }
            
            block.append(NSAttributedString(string: line + "\n", attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
                .foregroundColor: NSColor.labelColor,
                .backgroundColor: NSColor.labelColor.withAlphaComponent(0.07),
                .paragraphStyle: style,
            ]))
        }
        
        return block
    }
    
    
    private static func rule() -> NSAttributedString {
        
        let style = NSMutableParagraphStyle()
        style.paragraphSpacing = 8
        
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: NSColor.tertiaryLabelColor,
            .paragraphStyle: style,
        ]
        
        return NSMutableAttributedString(string: String(repeating: "─", count: 40) + "\n", attributes: attributes)
    }
    
    
    // MARK: Private Inline Rendering
    
    /// Wraps one finished block with its line terminator and paragraph style.
    private static func block(_ body: NSAttributedString, style: NSParagraphStyle) -> NSAttributedString {
        
        let block = NSMutableAttributedString(attributedString: body)
        block.append(NSAttributedString(string: "\n",
                                        attributes: [.font: NSFont.systemFont(ofSize: 13)]))
        block.addAttribute(.paragraphStyle, value: style, range: NSRange(location: 0, length: block.length))
        
        return block
    }
    
    
    /// Renders the inline Markdown of one run of text.
    ///
    /// Foundation parses emphasis, inline code and links on its own; this only maps the result
    /// onto the sheet's typography.
    private static func inline(_ text: String, font: NSFont, color: NSColor = .labelColor) -> NSAttributedString {
        
        guard !text.isEmpty else { return NSAttributedString() }
        
        var options = AttributedString.MarkdownParsingOptions()
        options.interpretedSyntax = .inlineOnlyPreservingWhitespace
        options.failurePolicy = .returnPartiallyParsedIfPossible
        
        guard let parsed = try? AttributedString(markdown: text, options: options) else {
            return NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color])
        }
        
        let result = NSMutableAttributedString()
        for run in parsed.runs {
            var attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
            let intents = run.inlinePresentationIntent
            
            if intents?.contains(.stronglyEmphasized) == true {
                attributes[.font] = NSFont.systemFont(ofSize: font.pointSize, weight: .semibold)
            }
            if intents?.contains(.emphasized) == true {
                attributes[.font] = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask)
            }
            if intents?.contains(.strikethrough) == true {
                attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
            }
            if intents?.contains(.code) == true {
                attributes[.font] = NSFont.monospacedSystemFont(ofSize: font.pointSize - 1, weight: .regular)
                attributes[.backgroundColor] = NSColor.labelColor.withAlphaComponent(0.07)
            }
            if let link = run.link {
                attributes[.link] = link
                attributes[.foregroundColor] = NSColor.linkColor
            }
            
            result.append(NSAttributedString(string: String(parsed[run.range].characters), attributes: attributes))
        }
        
        return result
    }
    
    
    // MARK: Private Parsing
    
    /// The heading level and text of a line, when it is a heading.
    private static func heading(in line: String) -> (level: Int, text: String)? {
        
        let hashes = line.prefix { $0 == "#" }
        guard (1...6).contains(hashes.count) else { return nil }
        
        let rest = line.dropFirst(hashes.count)
        guard rest.first == " " else { return nil }
        
        return (hashes.count, rest.trimmingCharacters(in: .whitespaces))
    }
    
    
    /// The marker, indentation and text of a list line, when it is one.
    private static func listItem(in line: String) -> (marker: String, depth: Int, text: String)? {
        
        let indent = line.prefix { $0 == " " || $0 == "\t" }
        let depth = indent.reduce(0) { $0 + ($1 == "\t" ? 2 : 1) } / 2
        let rest = line.dropFirst(indent.count)
        
        for bullet in ["- ", "* ", "+ "] where rest.hasPrefix(bullet) {
            return ("•", depth, String(rest.dropFirst(bullet.count)))
        }
        
        let digits = rest.prefix { $0.isNumber }
        guard !digits.isEmpty else { return nil }
        
        let afterDigits = rest.dropFirst(digits.count)
        guard afterDigits.hasPrefix(". ") || afterDigits.hasPrefix(") ") else { return nil }
        
        return (digits + ".", depth, String(afterDigits.dropFirst(2)))
    }
    
    
    /// Whether a line ends the current paragraph.
    private static func startsBlock(_ line: String) -> Bool {
        
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        
        return trimmed.isEmpty
            || trimmed.hasPrefix("```")
            || trimmed.hasPrefix(">")
            || self.heading(in: trimmed) != nil
            || self.listItem(in: line) != nil
    }
}
