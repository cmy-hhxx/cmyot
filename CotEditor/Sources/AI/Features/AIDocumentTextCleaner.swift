//
//  AIDocumentTextCleaner.swift
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

import CoreGraphics
import Foundation

/// Rewrites a model answer as plain document text.
///
/// Models answer in Markdown, and the decoration is fine in a preview but unreadable once it
/// is written into a note: every other word ends up wrapped in `**`. This keeps only the
/// structure a plain document can carry — `#` headings, numbered lists, and the four status
/// emoji 🔴 ✅ ❌ ⭐️ — and reduces everything else to its text.
///
/// Fenced code is preserved verbatim, including its indentation and any symbols inside it.
nonisolated enum AIDocumentTextCleaner {
    
    /// Layout measurement metrics used to align multi-column plain-text tables to exact editor Tab stops
    /// across both monospaced and proportional CJK/Latin fonts.
    nonisolated struct TableLayoutMetrics: Sendable {
        let tabInterval: CGFloat
        let minColumnGap: CGFloat
        let measureWidth: @Sendable (String) -> CGFloat
        
        /// Headless East-Asian cell-width fallback (`tabWidth = 4`, CJK = 2, ASCII = 1).
        static let defaultMonospace = TableLayoutMetrics(
            tabInterval: 4.0,
            minColumnGap: 2.0,
            measureWidth: { text in
                text.unicodeScalars.reduce(CGFloat(0)) { acc, scalar in
                    acc + (scalar.isASCII ? 1.0 : 2.0)
                }
            }
        )
    }
    
    /// The only emoji a cleaned document keeps.
    private static let allowedEmoji: Set<Unicode.Scalar> = ["🔴", "✅", "❌", "⭐"]
    
    // Precompiled regexes (never allocated inside line loops).
    private static let trailingWhitespaceRegex = try! NSRegularExpression(pattern: #"[ \t]+$"#)
    private static let trailingHashesRegex = try! NSRegularExpression(pattern: #"\s+#+$"#)
    private static let chineseSectionPrefixRegex = try! NSRegularExpression(pattern: #"^(?:[一二三四五六七八九十]+、|（[一二三四五六七八九十]+）|\([一二三四五六七八九十]+\)|第[一二三四五六七八九十0-9]+[部分章节条点])"#)
    private static let tableSeparatorCellRegex = try! NSRegularExpression(pattern: #"^:?-{3,}:?$"#)
    private static let imageMarkdownRegex = try! NSRegularExpression(pattern: #"!\[([^\]]*)\]\(([^)]*)\)"#)
    private static let linkMarkdownRegex = try! NSRegularExpression(pattern: #"\[([^\]]+)\]\(([^)]+)\)"#)
    private static let tripleBoldRegex = try! NSRegularExpression(pattern: #"\*\*\*(.+?)\*\*\*"#)
    private static let doubleBoldRegex = try! NSRegularExpression(pattern: #"\*\*(.+?)\*\*"#)
    private static let doubleUnderlineRegex = try! NSRegularExpression(pattern: #"__(.+?)__"#)
    private static let strikethroughRegex = try! NSRegularExpression(pattern: #"~~(.+?)~~"#)
    private static let inlineCodeRegex = try! NSRegularExpression(pattern: #"`([^`]+)`"#)
    private static let italicStarRegex = try! NSRegularExpression(pattern: #"(?:^|(?<=[\s（(\[【「『《，。；：、—–\-]))\*(?!\s)([^*\n]+?)(?<!\s)\*(?=$|[\s）)\]】」』》，。；：、！？—–\-])"#)
    private static let italicUnderscoreRegex = try! NSRegularExpression(pattern: #"(?<![A-Za-z0-9_])_(?![\s_])([^_\n]+?)_(?![A-Za-z0-9_])"#)
    private static let danglingTrailingStarRegex = try! NSRegularExpression(pattern: #"(?<=[^\s\*/_\[\\])\*+(?=$|[\s）)\]】」』》，。；：、！？])"#)
    private static let danglingLeadingStarRegex = try! NSRegularExpression(pattern: #"(?:^|(?<=[\s（(\[【「『《，。；：、]))\*+(?=[^\s\*\.\]\)/])"#)
    private static let cjkPunctuationSpaceRegex = try! NSRegularExpression(pattern: #"(?<=[。！？：；，])[ \t]+(?=[\p{Han}])"#)
    
    
    private enum LayoutStyle {
        /// Original plain-text layout: subheadings indented with 4 spaces, body flush left.
        case indentedSubheadings
        /// Organized document layout: headings flush left, formal body content indented with `\t`.
        case flushHeadingsIndentedBody
    }
    
    
    /// Cleans one model answer.
    ///
    /// - Parameter text: The Markdown answer.
    /// - Returns: Plain document text, without a trailing newline.
    static func clean(_ text: String) -> String {
        
        self.clean(text, style: .indentedSubheadings)
    }
    
    
    /// Cleans an AI-organized/merged document into plain text where headings stay flush left
    /// and body paragraphs/lists beneath each heading are indented with a tab (`\t`).
    ///
    /// - Parameter text: The Markdown or plain-text answer.
    /// - Returns: Plain document text, without a trailing newline.
    static func cleanOrganized(_ text: String) -> String {
        
        self.clean(text, style: .flushHeadingsIndentedBody)
    }
    
    
    /// Cleans messy AI-copied Markdown / mixed plain text into crisp, logically structured plain text
    /// indented with `\t` per hierarchy level.
    ///
    /// - Strips paired and broken/unpaired Markdown decorations (`**`, `*`, `` ` ``, `#`, `~~`, `__`, `>`).
    /// - Keeps top-level section headings (ATX headings, numbered sections like `2. **标题*`, Chinese sections)
    ///   flush left with a clean blank line between sections.
    /// - Indents body lines, bullet points (`- `), and nested sub-points cleanly with `\t`, `\t\t`, etc.
    /// - Aligns multi-column tables to exact editor Tab stops using `tableMetrics`, and turns wide 2-column
    ///   key-value tables into crisp `- Key：Value` lists so nothing ever drifts in proportional or CJK fonts.
    /// - Preserves fenced code content, file paths, identifiers, and valid globs/math (`a * b`, `*.py`, `foo/*`).
    static func cleanStructuredPlainText(
        _ text: String,
        tableMetrics: TableLayoutMetrics = .defaultMonospace
    ) -> String {
        
        let lines = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
        
        let hasFlushNumberedSections = Self.detectFlushNumberedSections(in: lines)
        var output: [String] = []
        var insideSection = false
        var insideATXSection = false
        var justEmittedHeading = false
        var sectionBodyBaseTabs = 0
        var indentStack: [Int] = []
        var lastSectionNumber: Int?
        var index = 0
        
        func appendBlankSeparatorIfNeeded() {
            if let last = output.last, !last.isEmpty {
                output.append("")
            }
        }
        
        func relativeIndentLevel(for visualIndent: Int) -> Int {
            while let top = indentStack.last, top > visualIndent {
                indentStack.removeLast()
            }
            if indentStack.last != visualIndent {
                indentStack.append(visualIndent)
            }
            return max(0, indentStack.count - 1)
        }
        
        while index < lines.count {
            let rawLine = lines[index]
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            
            // Preserve fenced code verbatim, removing only the fence markers.
            if trimmed.hasPrefix("```") {
                justEmittedHeading = false
                index += 1
                let codePrefix = insideSection ? String(repeating: "\t", count: max(1, sectionBodyBaseTabs)) : ""
                while index < lines.count,
                      !lines[index].trimmingCharacters(in: .whitespaces).hasPrefix("```")
                {
                    let codeLine = lines[index]
                    output.append(codeLine.isEmpty ? "" : codePrefix + codeLine)
                    index += 1
                }
                index += 1
                indentStack.removeAll()
                continue
            }
            
            if trimmed.isEmpty {
                if !justEmittedHeading {
                    appendBlankSeparatorIfNeeded()
                }
                indentStack.removeAll()
                index += 1
                continue
            }
            
            if Self.isHorizontalRule(trimmed) {
                justEmittedHeading = false
                appendBlankSeparatorIfNeeded()
                indentStack.removeAll()
                index += 1
                continue
            }
            
            // ATX headings (`#`, `##`, `###`, ...)
            if let heading = Self.heading(in: trimmed) {
                let isSubheading = heading.level >= 3 && insideSection
                if !isSubheading {
                    appendBlankSeparatorIfNeeded()
                    output.append(heading.text)
                    insideSection = true
                    insideATXSection = true
                    sectionBodyBaseTabs = 1
                } else {
                    output.append("\t" + heading.text)
                    insideATXSection = true
                    sectionBodyBaseTabs = 2
                }
                justEmittedHeading = true
                indentStack.removeAll()
                index += 1
                continue
            }
            
            // Markdown tables -> smart 2-col Key-Value list OR font-exact Tab-stop aligned table
            if Self.isTableStart(lines: lines, at: index) {
                justEmittedHeading = false
                var tableRows: [[String]] = [Self.tableCells(lines[index]).map { Self.inline($0) }]
                index += 2
                while index < lines.count, Self.isTableRow(lines[index]) {
                    tableRows.append(Self.tableCells(lines[index]).map { Self.inline($0) })
                    index += 1
                }
                let prefix = insideSection ? String(repeating: "\t", count: max(1, sectionBodyBaseTabs)) : ""
                for formatted in Self.formatStructuredTableRows(tableRows, metrics: tableMetrics) {
                    output.append(prefix + formatted)
                }
                indentStack.removeAll()
                continue
            }
            
            if Self.isTableRow(rawLine) {
                justEmittedHeading = false
                let prefix = insideSection ? String(repeating: "\t", count: max(1, sectionBodyBaseTabs)) : ""
                let cells = Self.tableCells(rawLine).map { Self.inline($0) }
                if let formatted = Self.formatStructuredTableRows([cells], metrics: tableMetrics).first {
                    output.append(prefix + formatted)
                }
                indentStack.removeAll()
                index += 1
                continue
            }
            
            let visualIndent = Self.visualIndentWidth(of: rawLine)
            var content = trimmed
            var isBlockquote = false
            if content.hasPrefix(">") {
                isBlockquote = true
                content = String(content.dropFirst()).trimmingCharacters(in: .whitespaces)
                if content.isEmpty {
                    index += 1
                    continue
                }
            }
            
            // Flush-left numbered section heading (e.g. `2. **本次重评范围*` followed by indented bullets/paragraphs)
            if !isBlockquote,
               !insideATXSection,
               visualIndent == 0,
               let numbered = Self.parseNumberedItem(in: content),
               hasFlushNumberedSections || Self.hasIndentedOrBulletFollowers(in: lines, after: index)
            {
                let resolvedNumber: Int
                if let prev = lastSectionNumber, numbered.number <= prev {
                    resolvedNumber = prev + 1
                } else {
                    resolvedNumber = numbered.number
                }
                lastSectionNumber = resolvedNumber
                appendBlankSeparatorIfNeeded()
                output.append("\(resolvedNumber). \(numbered.text)")
                insideSection = true
                justEmittedHeading = true
                sectionBodyBaseTabs = 1
                indentStack.removeAll()
                index += 1
                continue
            }
            
            // Flush-left plain / bold / Chinese section heading (e.g. `一、背景` or `**结论**` followed by body)
            if !isBlockquote,
               visualIndent == 0,
               Self.parseBulletItem(in: content) == nil,
               Self.parseNumberedItem(in: content) == nil,
               Self.isStructuredSectionHeading(rawTrimmed: content, lines: lines, at: index)
            {
                appendBlankSeparatorIfNeeded()
                output.append(Self.inline(content))
                insideSection = true
                justEmittedHeading = true
                sectionBodyBaseTabs = 1
                indentStack.removeAll()
                index += 1
                continue
            }
            
            // Bullet list items (`- `, `* `, `+ `, `• `)
            if let bulletText = Self.parseBulletItem(in: content) {
                justEmittedHeading = false
                let depth = relativeIndentLevel(for: visualIndent)
                let baseTabs = insideSection ? sectionBodyBaseTabs : (visualIndent > 0 ? 1 : 0)
                let tabs = min(4, baseTabs + depth)
                output.append(String(repeating: "\t", count: tabs) + "- " + bulletText)
                index += 1
                continue
            }
            
            // Nested or standalone numbered list items
            if let numbered = Self.parseNumberedItem(in: content) {
                justEmittedHeading = false
                let depth = relativeIndentLevel(for: visualIndent)
                let baseTabs = insideSection ? sectionBodyBaseTabs : (visualIndent > 0 ? 1 : 0)
                let tabs = min(4, baseTabs + depth)
                output.append(String(repeating: "\t", count: tabs) + "\(numbered.number). " + numbered.text)
                index += 1
                continue
            }
            
            // Regular paragraph or blockquote line
            justEmittedHeading = false
            let cleanedText = Self.inline(content)
            if !cleanedText.isEmpty {
                let tabs: Int
                if insideSection {
                    let extra = visualIndent > 0 ? min(2, Self.tabIndentDepth(of: rawLine) - 1) : 0
                    tabs = min(4, max(sectionBodyBaseTabs, sectionBodyBaseTabs + max(0, extra)))
                } else {
                    tabs = min(3, Self.tabIndentDepth(of: rawLine))
                }
                output.append(String(repeating: "\t", count: tabs) + cleanedText)
            }
            index += 1
        }
        
        var cleaned = output.map { Self.stripTrailingWhitespace($0) }
        while cleaned.first?.isEmpty == true { cleaned.removeFirst() }
        while cleaned.last?.isEmpty == true { cleaned.removeLast() }
        
        return cleaned.joined(separator: "\n")
    }
    
    
    private static func clean(_ text: String, style: LayoutStyle) -> String {
        
        let lines = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
        var output: [String] = []
        var counters: [Int: Int] = [:]
        var insideSection = false
        var sectionListBaseDepth: Int?
        var index = 0
        
        while index < lines.count {
            let rawLine = lines[index]
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            
            // Fenced code loses only the fence; its content stays byte-for-byte intact.
            if trimmed.hasPrefix("```") {
                index += 1
                while index < lines.count,
                      !lines[index].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                    let codeLine = lines[index]
                    if style == .flushHeadingsIndentedBody, insideSection, !codeLine.isEmpty {
                        output.append("\t" + codeLine)
                    } else {
                        output.append(codeLine)
                    }
                    index += 1
                }
                index += 1
                counters.removeAll()
                sectionListBaseDepth = nil
                continue
            }
            
            if trimmed.isEmpty {
                output.append("")
                counters.removeAll()
                sectionListBaseDepth = nil
                index += 1
                continue
            }
            
            if Self.isHorizontalRule(trimmed) {
                index += 1
                continue
            }
            
            if let heading = Self.heading(in: trimmed) {
                switch style {
                    case .indentedSubheadings:
                        // No `#` in the finished note: heading depth becomes four-space indentation.
                        let indent = String(repeating: "    ", count: min(3, heading.level - 1))
                        output.append(indent + heading.text)
                    case .flushHeadingsIndentedBody:
                        // Headings stay flush left (no tab/space); body beneath them uses `\t`.
                        output.append(heading.text)
                        insideSection = true
                        sectionListBaseDepth = nil
                }
                counters.removeAll()
                index += 1
                continue
            }
            
            if Self.isTableStart(lines: lines, at: index) {
                let prefix = (style == .flushHeadingsIndentedBody && insideSection) ? "\t" : ""
                output.append(prefix + Self.plainTableRow(lines[index]))
                index += 2  // header row and separator row
                while index < lines.count, Self.isTableRow(lines[index]) {
                    output.append(prefix + Self.plainTableRow(lines[index]))
                    index += 1
                }
                counters.removeAll()
                sectionListBaseDepth = nil
                continue
            }
            
            if Self.isTableRow(rawLine) {
                let prefix = (style == .flushHeadingsIndentedBody && insideSection) ? "\t" : ""
                output.append(prefix + Self.plainTableRow(rawLine))
                counters.removeAll()
                sectionListBaseDepth = nil
                index += 1
                continue
            }
            
            var content = trimmed
            var isBlockquote = false
            if content.hasPrefix(">") {
                isBlockquote = true
                content = String(content.dropFirst()).trimmingCharacters(in: .whitespaces)
                if content.isEmpty {
                    index += 1
                    continue
                }
            }
            
            // In organized plain-text mode, detect flush-left section headings (already written without `#`)
            // when they are followed by `\t`-indented content or look like standalone section headers.
            if style == .flushHeadingsIndentedBody,
               !isBlockquote,
               !Self.hasLeadingIndent(rawLine),
               Self.listItem(in: content) == nil,
               Self.isPlainHeading(content, lines: lines, at: index)
            {
                output.append(Self.inline(content))
                insideSection = true
                sectionListBaseDepth = nil
                counters.removeAll()
                index += 1
                continue
            }
            
            if let item = Self.listItem(in: content) {
                switch style {
                    case .indentedSubheadings:
                        let depth = Self.indentDepth(of: rawLine)
                        for key in counters.keys where key > depth {
                            counters[key] = nil
                        }
                        let number = (counters[depth] ?? 0) + 1
                        counters[depth] = number
                        output.append(String(repeating: "    ", count: depth) + "\(number). " + item)
                    case .flushHeadingsIndentedBody:
                        let rawDepth = Self.tabIndentDepth(of: rawLine)
                        if sectionListBaseDepth == nil {
                            sectionListBaseDepth = rawDepth
                        }
                        let relativeDepth = min(3, max(0, rawDepth - (sectionListBaseDepth ?? 0)))
                        for key in counters.keys where key > relativeDepth {
                            counters[key] = nil
                        }
                        let number = (counters[relativeDepth] ?? 0) + 1
                        counters[relativeDepth] = number
                        let baseTabs = insideSection ? 1 : (rawDepth > 0 ? 1 : 0)
                        let indent = String(repeating: "\t", count: min(4, baseTabs + relativeDepth))
                        output.append(indent + "\(number). " + item)
                }
                index += 1
                continue
            }
            
            counters.removeAll()
            sectionListBaseDepth = nil
            if style == .flushHeadingsIndentedBody {
                let rawDepth = Self.tabIndentDepth(of: rawLine)
                let tabCount = insideSection ? max(1, min(3, rawDepth)) : min(3, rawDepth)
                output.append(String(repeating: "\t", count: tabCount) + Self.inline(content))
            } else {
                output.append(Self.inline(content))
            }
            index += 1
        }
        
        var cleaned = output.map {
            $0.replacingOccurrences(of: "[ \t]+$", with: "", options: .regularExpression)
        }
        while cleaned.first?.isEmpty == true { cleaned.removeFirst() }
        while cleaned.last?.isEmpty == true { cleaned.removeLast() }
        
        return cleaned.joined(separator: "\n")
    }
    
    
    // MARK: Block Parsing
    
    /// The level and cleaned text of an ATX heading.
    private static func heading(in line: String) -> (level: Int, text: String)? {
        
        let hashes = line.prefix { $0 == "#" }
        guard (1...6).contains(hashes.count) else { return nil }
        
        let rest = line.dropFirst(hashes.count)
        guard rest.first == " " else { return nil }
        
        let text = rest
            .trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: #"\s+#+$"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        
        return (hashes.count, Self.inline(text))
    }
    
    
    /// The cleaned text of a list item, whether it was written with a bullet or a number.
    private static func listItem(in line: String) -> String? {
        
        let body: String
        if line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("+ ") || line.hasPrefix("• ") {
            body = String(line.dropFirst(2))
        } else {
            let digits = line.prefix { $0.isNumber }
            guard !digits.isEmpty else { return nil }
            let rest = line.dropFirst(digits.count)
            guard rest.hasPrefix(". ") || rest.hasPrefix(") ") else { return nil }
            body = String(rest.dropFirst(2))
        }
        
        var text = body
        if text.hasPrefix("[x] ") || text.hasPrefix("[X] ") {
            text = "✅ " + String(text.dropFirst(4))
        } else if text.hasPrefix("[ ] ") {
            text = String(text.dropFirst(4))
        }
        
        return Self.inline(text)
    }
    
    
    /// The indentation depth of a list line, in two-space steps.
    private static func indentDepth(of line: String) -> Int {
        
        let width = line.prefix { $0 == " " || $0 == "\t" }
            .reduce(0) { $0 + ($1 == "\t" ? 2 : 1) }
        
        return min(3, width / 2)
    }
    
    
    /// Whether the line starts with any whitespace indentation.
    private static func hasLeadingIndent(_ line: String) -> Bool {
        
        line.first == "\t" || line.first == " "
    }
    
    
    /// Tab-based indentation depth (each `\t` or 2+ spaces counts as one level).
    private static func tabIndentDepth(of line: String) -> Int {
        
        let prefix = line.prefix { $0 == "\t" || $0 == " " }
        let tabs = prefix.count { $0 == "\t" }
        let spaces = prefix.count { $0 == " " }
        return min(4, tabs + spaces / 2)
    }
    
    
    /// Recognizes a flush-left plain-text heading when the following content is indented beneath it.
    private static func isPlainHeading(_ trimmedLine: String, lines: [String], at index: Int) -> Bool {
        
        var nextIndex = index + 1
        while nextIndex < lines.count, lines[nextIndex].trimmingCharacters(in: .whitespaces).isEmpty {
            nextIndex += 1
        }
        guard nextIndex < lines.count else { return false }
        
        let nextLine = lines[nextIndex]
        if nextLine.hasPrefix("\t") || nextLine.hasPrefix("  ") {
            return true
        }
        
        // Also recognize explicit Chinese section prefixes (e.g. `一、...`) followed by a list.
        let nextTrimmed = nextLine.trimmingCharacters(in: .whitespaces)
        if Self.listItem(in: nextTrimmed) != nil,
           trimmedLine.range(of: #"^[一二三四五六七八九十]+、"#, options: .regularExpression) != nil
        {
            return true
        }
        
        return false
    }
    
    
    private static func isHorizontalRule(_ line: String) -> Bool {
        
        let compact = line.replacingOccurrences(of: " ", with: "")
        guard compact.count >= 3, let marker = compact.first, "-*_".contains(marker) else { return false }
        
        return compact.allSatisfy { $0 == marker }
    }
    
    
    // MARK: Tables
    
    private static func isTableStart(lines: [String], at index: Int) -> Bool {
        
        guard Self.isTableRow(lines[index]), index + 1 < lines.count else { return false }
        
        return Self.isTableSeparator(lines[index + 1])
    }
    
    
    private static func isTableSeparator(_ line: String) -> Bool {
        
        let cells = Self.tableCells(line)
        guard !cells.isEmpty else { return false }
        
        return cells.allSatisfy {
            $0.range(of: #"^:?-{3,}:?$"#, options: .regularExpression) != nil
        }
    }
    
    
    private static func isTableRow(_ line: String) -> Bool {
        
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.contains("|"), !trimmed.hasPrefix("```") else { return false }
        
        return Self.tableCells(trimmed).count >= 2
    }
    
    
    private static func tableCells(_ line: String) -> [String] {
        
        line.trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: "|"))
            .components(separatedBy: "|")
            .map { $0.trimmingCharacters(in: .whitespaces) }
    }
    
    
    /// Renders one table row as evenly spaced plain columns.
    private static func plainTableRow(_ line: String) -> String {
        
        Self.tableCells(line)
            .map { Self.inline($0) }
            .joined(separator: "   ")
    }
    
    
    /// Visual indentation width (`\t` = 4, space = 1) for accurate nested list stack tracking.
    private static func visualIndentWidth(of line: String) -> Int {
        
        line.prefix { $0 == " " || $0 == "\t" }
            .reduce(0) { $0 + ($1 == "\t" ? 4 : 1) }
    }
    
    
    /// Parses a bullet item (`- `, `* `, `+ `, `• `, `◦ `, `▪ `), preserving checkbox status cleanly.
    private static func parseBulletItem(in line: String) -> String? {
        
        let prefixes = ["- ", "* ", "+ ", "• ", "◦ ", "▪ "]
        guard let prefix = prefixes.first(where: { line.hasPrefix($0) }) else { return nil }
        var text = String(line.dropFirst(prefix.count))
        if text.hasPrefix("[x] ") || text.hasPrefix("[X] ") {
            text = "✅ " + String(text.dropFirst(4))
        } else if text.hasPrefix("[ ] ") {
            text = String(text.dropFirst(4))
        }
        return Self.inline(text)
    }
    
    
    /// Parses a numbered item (`1. ...`, `2) ...`, `3、...`).
    private static func parseNumberedItem(in line: String) -> (number: Int, text: String)? {
        
        let digits = line.prefix { $0.isASCII && $0.isNumber }
        guard !digits.isEmpty, let number = Int(digits) else { return nil }
        let rest = line.dropFirst(digits.count)
        let body: Substring
        if rest.hasPrefix(". ") || rest.hasPrefix(") ") {
            body = rest.dropFirst(2)
        } else if rest.hasPrefix("、") {
            body = rest.dropFirst(1)
        } else {
            return nil
        }
        return (number, Self.inline(String(body)))
    }
    
    
    /// Returns true when the document uses flush-left numbered items as section headings
    /// (at least one flush-left numbered item is followed by indented lines or bullets).
    private static func detectFlushNumberedSections(in lines: [String]) -> Bool {
        
        for (idx, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty,
                  Self.visualIndentWidth(of: line) == 0,
                  Self.parseNumberedItem(in: trimmed) != nil
            else { continue }
            if Self.hasIndentedOrBulletFollowers(in: lines, after: idx) {
                return true
            }
        }
        return false
    }
    
    
    /// Whether the next non-empty line after `index` is indented or starts a bullet list.
    private static func hasIndentedOrBulletFollowers(in lines: [String], after index: Int) -> Bool {
        
        var nextIndex = index + 1
        while nextIndex < lines.count, lines[nextIndex].trimmingCharacters(in: .whitespaces).isEmpty {
            nextIndex += 1
        }
        guard nextIndex < lines.count else { return false }
        let nextLine = lines[nextIndex]
        if Self.visualIndentWidth(of: nextLine) > 0 {
            return true
        }
        let nextTrimmed = nextLine.trimmingCharacters(in: .whitespaces)
        return Self.parseBulletItem(in: nextTrimmed) != nil
    }
    
    
    /// Recognizes a flush-left section heading in structured cleaning mode:
    /// indented follower lines, Chinese section prefixes (`一、...`), or short bold standalone headings (`**标题**`).
    private static func isStructuredSectionHeading(rawTrimmed: String, lines: [String], at index: Int) -> Bool {
        
        if Self.isPlainHeading(rawTrimmed, lines: lines, at: index) {
            return true
        }
        var nextIndex = index + 1
        while nextIndex < lines.count, lines[nextIndex].trimmingCharacters(in: .whitespaces).isEmpty {
            nextIndex += 1
        }
        guard nextIndex < lines.count else { return false }
        let nextTrimmed = lines[nextIndex].trimmingCharacters(in: .whitespaces)
        let isFollowedByBullet = Self.parseBulletItem(in: nextTrimmed) != nil
            || Self.parseNumberedItem(in: nextTrimmed) != nil
        
        let range = NSRange(location: 0, length: (rawTrimmed as NSString).length)
        if Self.chineseSectionPrefixRegex.firstMatch(in: rawTrimmed, range: range) != nil {
            return true
        }
        let looksBoldStandalone = rawTrimmed.hasPrefix("**")
            && (rawTrimmed.hasSuffix("**") || rawTrimmed.hasSuffix("*") || rawTrimmed.hasSuffix("：") || rawTrimmed.hasSuffix(":"))
            && rawTrimmed.count <= 48
        if looksBoldStandalone && (isFollowedByBullet || !nextTrimmed.isEmpty) {
            return true
        }
        return false
    }
    
    
    /// Formats a Markdown table for plain-text readability:
    /// - Wide or uneven 2-column key-value tables (e.g. `检查项 | 结果`) become crisp `- Key：Value` lines
    ///   so long descriptions never wrap awkwardly or leave huge whitespace chasms.
    /// - Multi-column data tables (and compact 2-column tables) align every column to exact editor Tab stops
    ///   using `metrics`, guaranteeing pixel-exact vertical alignment across proportional and CJK/Latin fonts.
    static func formatStructuredTableRows(
        _ rows: [[String]],
        metrics: TableLayoutMetrics = .defaultMonospace
    ) -> [String] {
        
        guard !rows.isEmpty else { return [] }
        let colCount = rows.map(\.count).max() ?? 0
        guard colCount > 0 else { return [] }
        
        let tabInterval = max(1.0, metrics.tabInterval)
        let normalizedRows = rows.map { row -> [String] in
            if row.count >= colCount { return Array(row.prefix(colCount)) }
            return row + Array(repeating: "", count: colCount - row.count)
        }
        
        if colCount == 2, normalizedRows.count >= 2 {
            let dataRows = Array(normalizedRows.dropFirst())
            let keyWidths = dataRows.map { metrics.measureWidth($0[0]) }
            let valWidths = dataRows.map { metrics.measureWidth($0[1]) }
            let maxKeySlots = (keyWidths.max() ?? 0) / tabInterval
            let minKeySlots = (keyWidths.filter { $0 > 0 }.min() ?? 0) / tabInterval
            let maxValSlots = (valWidths.max() ?? 0) / tabInterval
            
            let shouldFlattenKeyValue = maxKeySlots >= 4.0
                || maxValSlots >= 5.0
                || (minKeySlots > 0 && maxKeySlots >= minKeySlots * 2.5 && maxKeySlots >= 2.5)
            
            if shouldFlattenKeyValue {
                return dataRows.compactMap { row in
                    let key = row[0].trimmingCharacters(in: .whitespaces)
                    let val = row[1].trimmingCharacters(in: .whitespaces)
                    guard !key.isEmpty || !val.isEmpty else { return nil }
                    if key.isEmpty { return "- \(val)" }
                    if val.isEmpty { return "- \(key)" }
                    let sep = (key.hasSuffix("：") || key.hasSuffix(":")) ? "" : "："
                    return "- \(key)\(sep)\(val)"
                }
            }
        }
        
        // Pixel-exact Tab-stop alignment for multi-column & compact tables.
        let minGap = max(0.5, metrics.minColumnGap)
        var cellWidths = Array(repeating: Array(repeating: CGFloat(0), count: colCount), count: normalizedRows.count)
        var colSlots = Array(repeating: 1, count: colCount)
        
        for c in 0..<colCount {
            var maxW: CGFloat = 0
            for r in 0..<normalizedRows.count {
                let w = metrics.measureWidth(normalizedRows[r][c])
                cellWidths[r][c] = w
                if w > maxW { maxW = w }
            }
            if c < colCount - 1 {
                colSlots[c] = max(1, Int(ceil((maxW + minGap) / tabInterval)))
            }
        }
        
        return normalizedRows.enumerated().map { r, row in
            var line = ""
            for c in 0..<colCount {
                let cell = row[c]
                line += cell
                if c < colCount - 1 {
                    let w = cellWidths[r][c]
                    let consumedStops = Int(floor((w + 0.01) / tabInterval))
                    let tabCount = max(1, colSlots[c] - consumedStops)
                    line += String(repeating: "\t", count: tabCount)
                }
            }
            return line
        }
    }
    
    
    private static func stripTrailingWhitespace(_ line: String) -> String {
        
        Self.replacing(Self.trailingWhitespaceRegex, with: "", in: line)
    }
    
    
    // MARK: Inline Cleanup
    
    /// Removes inline Markdown decoration (including broken/unpaired `*` and `**`) and disallowed emoji.
    private static func inline(_ text: String) -> String {
        
        var result = text
        result = Self.replacing(Self.imageMarkdownRegex, with: "$1", in: result)
        result = Self.replacing(Self.linkMarkdownRegex, with: "$1 ($2)", in: result)
        result = Self.replacing(Self.tripleBoldRegex, with: "$1", in: result)
        result = Self.replacing(Self.doubleBoldRegex, with: "$1", in: result)
        result = Self.replacing(Self.doubleUnderlineRegex, with: "$1", in: result)
        result = Self.replacing(Self.strikethroughRegex, with: "$1", in: result)
        result = Self.replacing(Self.inlineCodeRegex, with: "$1", in: result)
        result = Self.replacing(Self.italicStarRegex, with: "$1", in: result)
        result = Self.replacing(Self.italicUnderscoreRegex, with: "$1", in: result)
        result = result
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "`", with: "")
        // Clean broken/unpaired trailing or leading Markdown `*` (e.g. `**标题*`) while keeping `a * b`, `*.py`, `dir/*`, `turns[*]`.
        result = Self.replacing(Self.danglingTrailingStarRegex, with: "", in: result)
        result = Self.replacing(Self.danglingLeadingStarRegex, with: "", in: result)
        result = Self.replacing(Self.cjkPunctuationSpaceRegex, with: "", in: result)
        result = Self.removingDisallowedEmoji(from: result)
        
        return result.trimmingCharacters(in: .whitespaces)
    }
    
    
    private static func replacing(_ regex: NSRegularExpression, with template: String, in text: String) -> String {
        
        regex.stringByReplacingMatches(
            in: text,
            range: NSRange(location: 0, length: (text as NSString).length),
            withTemplate: template
        )
    }
    
    
    /// Drops every emoji except the four status markers the document uses.
    private static func removingDisallowedEmoji(from text: String) -> String {
        
        var result = String.UnicodeScalarView()
        var lastKeptWasAllowedEmoji = false
        
        for scalar in text.unicodeScalars {
            if Self.allowedEmoji.contains(scalar) {
                result.append(scalar)
                lastKeptWasAllowedEmoji = true
            } else if scalar.value == 0xFE0F {
                // A variation selector only belongs to the emoji immediately before it.
                if lastKeptWasAllowedEmoji {
                    result.append(scalar)
                }
            } else if scalar.isASCII {
                result.append(scalar)
                lastKeptWasAllowedEmoji = false
            } else if scalar.properties.isEmoji {
                lastKeptWasAllowedEmoji = false
            } else {
                result.append(scalar)
                lastKeptWasAllowedEmoji = false
            }
        }
        
        return String(result)
    }
}
