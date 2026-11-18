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
    
    /// The only emoji a cleaned document keeps.
    private static let allowedEmoji: Set<Unicode.Scalar> = ["🔴", "✅", "❌", "⭐"]
    
    
    /// Cleans one model answer.
    ///
    /// - Parameter text: The Markdown answer.
    /// - Returns: Plain document text, without a trailing newline.
    static func clean(_ text: String) -> String {
        
        let lines = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
        var output: [String] = []
        var counters: [Int: Int] = [:]
        var index = 0
        
        while index < lines.count {
            let rawLine = lines[index]
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            
            // Fenced code loses only the fence; its content stays byte-for-byte intact.
            if trimmed.hasPrefix("```") {
                index += 1
                while index < lines.count,
                      !lines[index].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                    output.append(lines[index])
                    index += 1
                }
                index += 1
                counters.removeAll()
                continue
            }
            
            if trimmed.isEmpty {
                output.append("")
                counters.removeAll()
                index += 1
                continue
            }
            
            if Self.isHorizontalRule(trimmed) {
                index += 1
                continue
            }
            
            if let heading = Self.heading(in: trimmed) {
                // No `#` in the finished note: heading depth becomes four-space indentation.
                let indent = String(repeating: "    ", count: min(3, heading.level - 1))
                output.append(indent + heading.text)
                counters.removeAll()
                index += 1
                continue
            }
            
            if Self.isTableStart(lines: lines, at: index) {
                output.append(Self.plainTableRow(lines[index]))
                index += 2  // header row and separator row
                while index < lines.count, Self.isTableRow(lines[index]) {
                    output.append(Self.plainTableRow(lines[index]))
                    index += 1
                }
                counters.removeAll()
                continue
            }
            
            if Self.isTableRow(rawLine) {
                output.append(Self.plainTableRow(rawLine))
                counters.removeAll()
                index += 1
                continue
            }
            
            var content = trimmed
            if content.hasPrefix(">") {
                content = String(content.dropFirst()).trimmingCharacters(in: .whitespaces)
                if content.isEmpty {
                    index += 1
                    continue
                }
            }
            
            if let item = Self.listItem(in: content) {
                let depth = Self.indentDepth(of: rawLine)
                for key in counters.keys where key > depth {
                    counters[key] = nil
                }
                let number = (counters[depth] ?? 0) + 1
                counters[depth] = number
                output.append(String(repeating: "    ", count: depth) + "\(number). " + item)
                index += 1
                continue
            }
            
            counters.removeAll()
            output.append(Self.inline(content))
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
    
    
    // MARK: Inline Cleanup
    
    /// Removes inline Markdown decoration and disallowed emoji from one run of text.
    private static func inline(_ text: String) -> String {
        
        var result = text
        result = Self.replacing(#"!\[([^\]]*)\]\(([^)]*)\)"#, with: "$1", in: result)
        result = Self.replacing(#"\[([^\]]+)\]\(([^)]+)\)"#, with: "$1 ($2)", in: result)
        result = Self.replacing(#"\*\*(.+?)\*\*"#, with: "$1", in: result)
        result = Self.replacing(#"__(.+?)__"#, with: "$1", in: result)
        result = Self.replacing(#"~~(.+?)~~"#, with: "$1", in: result)
        result = Self.replacing(#"`([^`]+)`"#, with: "$1", in: result)
        result = Self.replacing(#"(?<![A-Za-z0-9*])\*(?![\s*])([^*\n]+?)\*(?![A-Za-z0-9*])"#, with: "$1", in: result)
        result = Self.replacing(#"(?<![A-Za-z0-9_])_(?![\s_])([^_\n]+?)_(?![A-Za-z0-9_])"#, with: "$1", in: result)
        result = result
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "`", with: "")
        result = Self.removingDisallowedEmoji(from: result)
        
        return result.trimmingCharacters(in: .whitespaces)
    }
    
    
    private static func replacing(_ pattern: String, with template: String, in text: String) -> String {
        
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        
        return regex.stringByReplacingMatches(
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
