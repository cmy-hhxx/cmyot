//
//  AIHotNewsService.swift
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
import CryptoKit
import Foundation
import ImageIO
import Observation

/// Editorial category for the Dashboard NEWS stream (Finance, X / Social signals, AI & Tech).
nonisolated enum NewsFeedCategory: String, CaseIterable, Identifiable, Codable, Sendable {
    
    case all
    case finance
    case xSocial
    case ai
    
    var id: String { self.rawValue }
    
    var label: String {
        switch self {
            case .all: AppLanguage.text("全部", en: "All")
            case .finance: AppLanguage.text("金融", en: "Finance")
            case .xSocial: AppLanguage.text("X 动态", en: "X")
            case .ai: "AI"
        }
    }
    
    var badgeLabel: String {
        switch self {
            case .all: ""
            case .finance: AppLanguage.text("金融", en: "Finance")
            case .xSocial: "X"
            case .ai: "AI"
        }
    }
}


/// Structured readable block extracted from RSS `<content:encoded>`, JSON `articleBody`, or web `<article>` HTML.
nonisolated enum NewsArticleBlock: Codable, Hashable, Sendable {
    
    case heading(level: Int, text: String)
    case paragraph(String)
    case quote(String)
    case code(String)
    case list([String])
    
    var markdownText: String {
        switch self {
            case .heading(let level, let text):
                return "\(String(repeating: "#", count: min(4, max(2, level)))) \(text)"
            case .paragraph(let text):
                return text
            case .quote(let text):
                return "> \(text.replacingOccurrences(of: "\n", with: "\n> "))"
            case .code(let code):
                return "```\n\(code)\n```"
            case .list(let items):
                return items.map { "- \($0)" }.joined(separator: "\n")
        }
    }
}


/// Cached full-article payload for distraction-free magazine reading inside `DashboardNewsCenterView`.
nonisolated struct NewsArticleContent: Codable, Hashable, Sendable {
    
    var blocks: [NewsArticleBlock]
    var leadExcerpt: String?
    var author: String?
    var extractedAt: Date
    
    var markdownBody: String {
        self.blocks.map(\.markdownText).joined(separator: "\n\n")
    }
    
    var plainTextLength: Int {
        self.blocks.reduce(0) { acc, block in
            switch block {
                case .heading(_, let text), .paragraph(let text), .quote(let text), .code(let text):
                    acc + text.count
                case .list(let items):
                    acc + items.reduce(0) { $0 + $1.count }
            }
        }
    }
    
    var isSubstantial: Bool {
        self.plainTextLength >= 140 || (self.blocks.count >= 2 && self.plainTextLength >= 90)
    }
}


/// Deterministic, pure Readability-style HTML & Markdown article extractor for the NEWS reader.
nonisolated enum NewsArticleExtractor {
    
    private static let noisePatterns: [String] = [
        "all rights reserved", "privacy policy", "terms of service", "cookie policy",
        "accept cookies", "sign up for our newsletter", "subscribe to our", "already a subscriber",
        "share this article", "follow us on", "advertisement", "版权所有", "未经允许不得转载",
        "javascript is not available", "enable javascript", "please enable javascript",
        "please enable cookies", "verify you are human", "checking your browser",
        "just a moment", "access denied", "403 forbidden", "sign in to continue",
        "subscribe to continue", "subscribe to read",
    ]
    
    private nonisolated(unsafe) static let numericEntityRegex = try? NSRegularExpression(pattern: #"&#(x?[0-9A-Fa-f]{1,6});"#)
    private nonisolated(unsafe) static let blockRegex = try? NSRegularExpression(
        pattern: #"<(h[1-4]|pre|blockquote|ul|ol|p)\b[^>]*>([\s\S]*?)</\1>"#,
        options: [.caseInsensitive]
    )
    private nonisolated(unsafe) static let leafDivSectionRegex = try? NSRegularExpression(
        pattern: #"<(div|section)\b[^>]*>((?:(?!</?(?:div|section)\b)[\s\S]){35,3200})</\1>"#,
        options: [.caseInsensitive]
    )
    private nonisolated(unsafe) static let listItemRegex = try? NSRegularExpression(
        pattern: #"<li\b[^>]*>([\s\S]*?)</li>"#,
        options: [.caseInsensitive]
    )
    private nonisolated(unsafe) static let ldJSONRegex = try? NSRegularExpression(
        pattern: #"<script[^>]+type\s*=\s*["']application/ld\+json["'][^>]*>([\s\S]*?)</script>"#,
        options: [.caseInsensitive]
    )
    private nonisolated(unsafe) static let nextDataRegex = try? NSRegularExpression(
        pattern: #"<script[^>]+id\s*=\s*["']__NEXT_DATA__["'][^>]*>([\s\S]*?)</script>"#,
        options: [.caseInsensitive]
    )
    private nonisolated(unsafe) static let articleContainerRegex = try? NSRegularExpression(
        pattern: #"<article\b[^>]*>([\s\S]*?)</article>"#,
        options: [.caseInsensitive]
    )
    private nonisolated(unsafe) static let mainContainerRegex = try? NSRegularExpression(
        pattern: #"<main\b[^>]*>([\s\S]*?)</main>"#,
        options: [.caseInsensitive]
    )
    private nonisolated(unsafe) static let bodyContainerRegex = try? NSRegularExpression(
        pattern: #"<body\b[^>]*>([\s\S]*?)</body>"#,
        options: [.caseInsensitive]
    )
    
    
    static func decodeHTMLEntities(_ raw: String) -> String {
        var text = raw
        let named: [(String, String)] = [
            ("&nbsp;", " "), ("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"),
            ("&quot;", "\""), ("&#39;", "'"), ("&apos;", "'"),
            ("&mdash;", "—"), ("&ndash;", "–"), ("&hellip;", "…"),
            ("&ldquo;", "“"), ("&rdquo;", "”"), ("&lsquo;", "‘"), ("&rsquo;", "’"),
            ("&bull;", "•"), ("&middot;", "·"), ("&copy;", "©"), ("&rarr;", "→"),
        ]
        for (entity, value) in named {
            text = text.replacingOccurrences(of: entity, with: value)
        }
        if text.contains("&#"),
           let numRegex = Self.numericEntityRegex
        {
            let ns = text as NSString
            let matches = numRegex.matches(in: text, range: NSRange(location: 0, length: ns.length)).reversed()
            for m in matches where m.numberOfRanges >= 2 {
                let token = ns.substring(with: m.range(at: 1))
                let code: UInt32? = if token.lowercased().hasPrefix("x") {
                    UInt32(token.dropFirst(), radix: 16)
                } else {
                    UInt32(token, radix: 10)
                }
                if let code, let scalar = UnicodeScalar(code) {
                    text = (text as NSString).replacingCharacters(in: m.range, with: String(scalar))
                }
            }
        }
        return text
    }
    
    
    private static func isBoilerplate(_ text: String) -> Bool {
        let lower = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard lower.count >= 4 else { return true }
        return Self.noisePatterns.contains { lower.contains($0) }
    }
    
    
    private static func cleanInlineHTML(_ raw: String, preserveNewlines: Bool = false) -> String {
        var text = raw
        text = text.replacingOccurrences(of: #"<br\s*/?>"#, with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(
            of: #"<code\b[^>]*>([\s\S]*?)</code>"#,
            with: "`$1`",
            options: [.regularExpression, .caseInsensitive]
        )
        text = text.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
        text = Self.decodeHTMLEntities(text)
        if preserveNewlines {
            let lines = text.components(separatedBy: .newlines).map {
                $0.replacingOccurrences(of: #"[ \t]+"#, with: " ", options: .regularExpression)
                    .trimmingCharacters(in: .whitespaces)
            }
            return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            return text.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }
    
    
    static func extractBlocks(fromHTMLFragment raw: String, maxBlocks: Int = 40) -> [NewsArticleBlock] {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 40 else { return [] }
        
        // Strip comments & non-editorial containers first
        var cleaned = trimmed.replacingOccurrences(of: #"<!--[\s\S]*?-->"#, with: " ", options: .regularExpression)
        cleaned = cleaned.replacingOccurrences(
            of: #"<(script|style|svg|noscript|nav|header|footer|aside|form|iframe|button)\b[^>]*>[\s\S]*?</\1>"#,
            with: " ",
            options: [.regularExpression, .caseInsensitive]
        )
        
        let hasBlockTags = cleaned.range(
            of: #"<(p|h[1-4]|blockquote|pre|ul|ol|article|div)\b"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil
        
        if !hasBlockTags {
            return Self.extractBlocksFromPlainText(Self.decodeHTMLEntities(cleaned), maxBlocks: maxBlocks)
        }
        
        var blocks: [NewsArticleBlock] = []
        var seenNorm = Set<String>()
        
        guard let blockRegex = Self.blockRegex else {
            return []
        }
        
        let ns = cleaned as NSString
        let matches = blockRegex.matches(in: cleaned, range: NSRange(location: 0, length: ns.length))
        for match in matches {
            guard blocks.count < maxBlocks, match.numberOfRanges >= 3 else { break }
            let tag = ns.substring(with: match.range(at: 1)).lowercased()
            let inner = ns.substring(with: match.range(at: 2))
            
            if tag.hasPrefix("h"), let lvl = Int(tag.dropFirst()) {
                let title = Self.cleanInlineHTML(inner)
                guard (3...130).contains(title.count), !Self.isBoilerplate(title) else { continue }
                let key = "h:\(title.lowercased())"
                if seenNorm.insert(key).inserted {
                    blocks.append(.heading(level: max(2, lvl), text: title))
                }
            } else if tag == "pre" {
                var code = inner.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
                code = Self.decodeHTMLEntities(code).trimmingCharacters(in: .newlines)
                guard code.trimmingCharacters(in: .whitespacesAndNewlines).count >= 8 else { continue }
                blocks.append(.code(String(code.prefix(2400))))
            } else if tag == "blockquote" {
                let quote = Self.cleanInlineHTML(inner, preserveNewlines: true)
                guard quote.count >= 14, !Self.isBoilerplate(quote) else { continue }
                let key = quote.lowercased()
                if seenNorm.insert(key).inserted {
                    blocks.append(.quote(String(quote.prefix(900))))
                }
            } else if tag == "ul" || tag == "ol" {
                if let liRegex = Self.listItemRegex {
                    let nsInner = inner as NSString
                    let liMatches = liRegex.matches(in: inner, range: NSRange(location: 0, length: nsInner.length))
                    var items: [String] = []
                    for li in liMatches.prefix(10) where li.numberOfRanges >= 2 {
                        let txt = Self.cleanInlineHTML(nsInner.substring(with: li.range(at: 1)))
                        if (4...260).contains(txt.count), !Self.isBoilerplate(txt) {
                            items.append(txt)
                        }
                    }
                    if items.count >= 2 {
                        blocks.append(.list(items))
                    }
                }
            } else if tag == "p" {
                let para = Self.cleanInlineHTML(inner)
                guard para.count >= 14, !Self.isBoilerplate(para) else { continue }
                let key = para.lowercased()
                if seenNorm.insert(key).inserted {
                    blocks.append(.paragraph(para))
                }
            }
        }
        
        // Secondary pass for blogs/CMS that wrap paragraphs in `<div>` or `<section>` instead of `<p>`
        let currentLength = blocks.reduce(0) { acc, b in
            switch b {
                case .heading(_, let t), .paragraph(let t), .quote(let t), .code(let t): acc + t.count
                case .list(let items): acc + items.reduce(0) { $0 + $1.count }
            }
        }
        if currentLength < 160, blocks.count < maxBlocks, let leafRegex = Self.leafDivSectionRegex {
            let leafMatches = leafRegex.matches(in: cleaned, range: NSRange(location: 0, length: ns.length))
            for match in leafMatches {
                guard blocks.count < maxBlocks, match.numberOfRanges >= 3 else { break }
                let inner = ns.substring(with: match.range(at: 2))
                let text = Self.cleanInlineHTML(inner)
                guard text.count >= 28, !Self.isBoilerplate(text) else { continue }
                let key = text.lowercased()
                if seenNorm.insert(key).inserted {
                    blocks.append(.paragraph(text))
                }
            }
        }
        
        return blocks
    }
    
    
    static func extractBlocksFromPlainText(_ raw: String, maxBlocks: Int = 50) -> [NewsArticleBlock] {
        var blocks: [NewsArticleBlock] = []
        var seen = Set<String>()
        let chunks = raw
            .replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n\n")
        
        for rawChunk in chunks {
            guard blocks.count < maxBlocks else { break }
            let chunk = rawChunk.trimmingCharacters(in: .whitespacesAndNewlines)
            guard chunk.count >= 12, !Self.isBoilerplate(chunk) else { continue }
            
            if chunk.hasPrefix("#") {
                let hashes = chunk.prefix(while: { $0 == "#" }).count
                let heading = chunk.dropFirst(hashes).trimmingCharacters(in: .whitespaces)
                if !heading.isEmpty {
                    blocks.append(.heading(level: max(2, min(4, hashes)), text: heading))
                }
            } else if chunk.hasPrefix(">") {
                let q = chunk.replacingOccurrences(of: #"(?m)^>\s*"#, with: "", options: .regularExpression)
                if q.count >= 12 {
                    blocks.append(.quote(q))
                }
            } else {
                let lines = chunk.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }
                if lines.count >= 2, lines.allSatisfy({ $0.hasPrefix("- ") || $0.hasPrefix("* ") }) {
                    let listItems = lines.map { String($0.dropFirst(2)).trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                    if !listItems.isEmpty {
                        blocks.append(.list(listItems))
                        continue
                    }
                }
                let normalized = chunk.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                guard normalized.count >= 14, seen.insert(normalized.lowercased()).inserted else { continue }
                blocks.append(.paragraph(normalized))
            }
        }
        return blocks
    }
    
    
    static func extractBlocksFromMarkdown(_ raw: String, maxBlocks: Int = 60) -> [NewsArticleBlock] {
        let normalizedRaw = raw.replacingOccurrences(of: "\r\n", with: "\n")
        var filteredLines: [String] = []
        var inCodeFence = false
        
        for line in normalizedRaw.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") {
                inCodeFence.toggle()
                filteredLines.append(line)
                continue
            }
            if inCodeFence {
                filteredLines.append(line)
                continue
            }
            // Strip Jina Reader header preamble lines
            let lower = trimmed.lowercased()
            if lower.hasPrefix("title:") || lower.hasPrefix("url source:")
                || lower.hasPrefix("published time:") || lower.hasPrefix("markdown content:")
                || lower.hasPrefix("warning:")
            {
                continue
            }
            // Strip standalone markdown images or nav-only bullet links
            if trimmed.hasPrefix("![") && trimmed.contains("](") && trimmed.hasSuffix(")") {
                continue
            }
            if trimmed.hasPrefix("[![") && trimmed.hasSuffix(")") {
                continue
            }
            if (trimmed.hasPrefix("* [") || trimmed.hasPrefix("- [")) && trimmed.hasSuffix(")") && trimmed.count < 110 {
                let stripped = trimmed.replacingOccurrences(of: #"^[-*]\s+\[([^\]]+)\]\([^\)]+\)$"#, with: "$1", options: .regularExpression)
                if stripped.count < 32 {
                    continue
                }
            }
            // Convert inline markdown links `[label](url)` into readable text
            let readable = line
                .replacingOccurrences(of: #"!\[[^\]]*\]\([^\)]+\)"#, with: "", options: .regularExpression)
                .replacingOccurrences(of: #"\[([^\]\n]+)\]\((?:https?://|/)[^\)\n]+\)"#, with: "$1", options: .regularExpression)
            filteredLines.append(readable)
        }
        
        // Parse fenced code blocks + paragraph/heading/quote/list chunks
        var blocks: [NewsArticleBlock] = []
        var seen = Set<String>()
        var buffer: [String] = []
        var codeBuffer: [String] = []
        var collectingCode = false
        
        func flushProseBuffer() {
            guard !buffer.isEmpty, blocks.count < maxBlocks else {
                buffer.removeAll()
                return
            }
            let chunk = buffer.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            buffer.removeAll()
            guard !chunk.isEmpty, !Self.isBoilerplate(chunk) else { return }
            
            if chunk.hasPrefix("#") {
                let hashes = chunk.prefix(while: { $0 == "#" }).count
                let heading = chunk.dropFirst(hashes).trimmingCharacters(in: .whitespaces)
                if heading.count >= 2 && seen.insert("h:\(heading.lowercased())").inserted {
                    blocks.append(.heading(level: max(2, min(4, hashes)), text: heading))
                }
                return
            }
            if chunk.hasPrefix(">") {
                let q = chunk.replacingOccurrences(of: #"(?m)^>\s*"#, with: "", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if q.count >= 12 && seen.insert(q.lowercased()).inserted {
                    blocks.append(.quote(String(q.prefix(1200))))
                }
                return
            }
            let lines = chunk.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }
            if lines.count >= 2, lines.allSatisfy({ $0.hasPrefix("- ") || $0.hasPrefix("* ") }) {
                let items = lines
                    .map { String($0.dropFirst(2)).trimmingCharacters(in: .whitespaces) }
                    .filter { $0.count >= 4 && !Self.isBoilerplate($0) }
                if items.count >= 2 {
                    blocks.append(.list(Array(items.prefix(12))))
                    return
                }
            }
            let para = chunk.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            guard para.count >= 18, !Self.isBoilerplate(para), seen.insert(para.lowercased()).inserted else { return }
            blocks.append(.paragraph(para))
        }
        
        for line in filteredLines {
            guard blocks.count < maxBlocks else { break }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") {
                if collectingCode {
                    let codeText = codeBuffer.joined(separator: "\n").trimmingCharacters(in: .newlines)
                    codeBuffer.removeAll()
                    collectingCode = false
                    if codeText.count >= 8 {
                        blocks.append(.code(String(codeText.prefix(2400))))
                    }
                } else {
                    flushProseBuffer()
                    collectingCode = true
                    codeBuffer.removeAll()
                }
                continue
            }
            if collectingCode {
                codeBuffer.append(line)
                continue
            }
            if trimmed.isEmpty || trimmed == "---" || trimmed == "===" {
                flushProseBuffer()
                continue
            }
            if trimmed.hasPrefix("#") && !buffer.isEmpty {
                flushProseBuffer()
            }
            buffer.append(line)
        }
        flushProseBuffer()
        return blocks
    }
    
    
    static func extractFromWebPageHTML(_ html: String) -> (blocks: [NewsArticleBlock], author: String?) {
        var bestBlocks: [NewsArticleBlock] = []
        var bestLength = 0
        var resolvedAuthor: String?
        
        func considerCandidate(_ blocks: [NewsArticleBlock]) {
            let len = NewsArticleContent(blocks: blocks, leadExcerpt: nil, author: nil, extractedAt: .now).plainTextLength
            if len > bestLength {
                bestLength = len
                bestBlocks = blocks
            }
        }
        
        // 1. Inspect JSON-LD `articleBody` / `text` / `description` & `author`
        if let ldRegex = Self.ldJSONRegex {
            let ns = html as NSString
            for match in ldRegex.matches(in: html, range: NSRange(location: 0, length: ns.length)) where match.numberOfRanges >= 2 {
                let jsonStr = ns.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
                guard let data = jsonStr.data(using: .utf8),
                      let obj = try? JSONSerialization.jsonObject(with: data)
                else { continue }
                let candidates: [[String: Any]] = if let dict = obj as? [String: Any] {
                    if let graph = dict["@graph"] as? [[String: Any]] { [dict] + graph } else { [dict] }
                } else if let arr = obj as? [[String: Any]] {
                    arr
                } else {
                    []
                }
                for item in candidates {
                    if resolvedAuthor == nil {
                        if let authStr = item["author"] as? String {
                            resolvedAuthor = authStr
                        } else if let authDict = item["author"] as? [String: Any], let name = authDict["name"] as? String {
                            resolvedAuthor = name
                        } else if let authArr = item["author"] as? [[String: Any]], let name = authArr.first?["name"] as? String {
                            resolvedAuthor = name
                        }
                    }
                    if let bodyStr = (item["articleBody"] as? String) ?? (item["text"] as? String), bodyStr.count > 120 {
                        considerCandidate(Self.extractBlocks(fromHTMLFragment: bodyStr))
                    }
                }
            }
        }
        
        // 2. Inspect Next.js / SSR `__NEXT_DATA__` payloads when pages hydrate body in script JSON
        if let nextRegex = Self.nextDataRegex {
            let ns = html as NSString
            if let match = nextRegex.firstMatch(in: html, range: NSRange(location: 0, length: ns.length)),
               match.numberOfRanges >= 2
            {
                let jsonStr = ns.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
                if let data = jsonStr.data(using: .utf8),
                   let obj = try? JSONSerialization.jsonObject(with: data)
                {
                    let extractedSSRStrings = Self.collectSSRArticleStrings(from: obj, depth: 0)
                    for candidateStr in extractedSSRStrings {
                        let candidateBlocks = candidateStr.contains("<") && candidateStr.contains(">")
                            ? Self.extractBlocks(fromHTMLFragment: candidateStr)
                            : Self.extractBlocksFromMarkdown(candidateStr)
                        considerCandidate(candidateBlocks)
                    }
                }
            }
        }
        
        // 3. Semantic `<article>` / `<main>` containers (test longest + concatenated)
        let nsHTML = html as NSString
        for regex in [Self.articleContainerRegex, Self.mainContainerRegex].compactMap(\.self) {
            let matches = regex.matches(in: html, range: NSRange(location: 0, length: nsHTML.length))
            if let longest = matches.max(by: { $0.range(at: 1).length < $1.range(at: 1).length }),
               longest.range(at: 1).length > 200
            {
                let longestFrag = nsHTML.substring(with: longest.range(at: 1))
                considerCandidate(Self.extractBlocks(fromHTMLFragment: longestFrag))
            }
            if matches.count > 1 && matches.count <= 8 {
                let joined = matches
                    .map { nsHTML.substring(with: $0.range(at: 1)) }
                    .joined(separator: "\n")
                if joined.count > 200 {
                    considerCandidate(Self.extractBlocks(fromHTMLFragment: joined))
                }
            }
        }
        
        // 4. Full `<body>` / full-HTML fallback when semantic tags missed content or gave < 180 chars
        if bestLength < 180 {
            let bodyFragment: String = {
                if let bodyRegex = Self.bodyContainerRegex,
                   let m = bodyRegex.firstMatch(in: html, range: NSRange(location: 0, length: nsHTML.length)),
                   m.numberOfRanges >= 2
                {
                    return nsHTML.substring(with: m.range(at: 1))
                }
                return html
            }()
            considerCandidate(Self.extractBlocks(fromHTMLFragment: bodyFragment))
        }
        
        return (bestBlocks, resolvedAuthor)
    }
    
    
    private static func collectSSRArticleStrings(from node: Any, depth: Int) -> [String] {
        guard depth <= 8 else { return [] }
        let targetKeys: Set<String> = [
            "articlebody", "body", "bodyhtml", "content", "contenthtml", "markdown", "fulltext", "text",
        ]
        var collected: [String] = []
        if let dict = node as? [String: Any] {
            for (k, v) in dict {
                if targetKeys.contains(k.lowercased()), let s = v as? String, s.count >= 180 {
                    collected.append(s)
                } else if v is [String: Any] || v is [Any] {
                    collected.append(contentsOf: Self.collectSSRArticleStrings(from: v, depth: depth + 1))
                }
            }
        } else if let arr = node as? [Any] {
            for element in arr.prefix(24) {
                collected.append(contentsOf: Self.collectSSRArticleStrings(from: element, depth: depth + 1))
            }
        }
        return collected
    }
}


/// A single chat message in the NEWS article AI commentary & follow-up conversation.
nonisolated struct NewsChatMessage: Identifiable, Codable, Hashable, Sendable {
    
    enum Role: String, Codable, Hashable, Sendable {
        case user
        case assistant
    }
    
    var id: String = UUID().uuidString
    var role: Role
    var text: String
    var thinking: String? = nil
    var thinkingDurationMs: Int? = nil
    var steps: [BeautifulAgentThinkingStep]? = nil
    var toolChips: [String]? = nil
    var followUps: [String]? = nil
    var quoteContext: String? = nil
    var isError: Bool = false
    var createdAt: Date = Date()
}


/// Selectable gateway + model option shown in the Deep Agent NEWS Chat composer.
nonisolated struct NewsChatModelOption: Identifiable, Hashable, Sendable {
    
    let endpointID: UUID
    let endpointName: String
    let modelID: String
    
    var id: String { "\(self.endpointID.uuidString)::\(self.modelID)" }
    
    var displayName: String { self.modelID }
}


/// Three-stop reasoning effort matching the LeiBox Deep Agent Composer (`简单 / 中度 / 深度`).
nonisolated enum NewsReasoningEffort: Int, CaseIterable, Identifiable, Sendable {
    case simple = 0
    case balanced = 1
    case deep = 2
    
    var id: Int { self.rawValue }
    
    var title: String {
        switch self {
            case .simple: AppLanguage.text("简单", en: "Simple")
            case .balanced: AppLanguage.text("中度", en: "Medium")
            case .deep: AppLanguage.text("深度", en: "Deep")
        }
    }
    
    var apiValue: String {
        switch self {
            case .simple: "low"
            case .balanced: "medium"
            case .deep: "high"
        }
    }
    
    var temperature: Double {
        switch self {
            case .simple: 0.35
            case .balanced: 0.55
            case .deep: 0.72
        }
    }
    
    var styleDirective: String {
        switch self {
            case .simple:
                "回答风格：默认快速精读模式。直接输出结构清晰的 Markdown 要点（含核心结论、关键事实/数字、一句话点评），总字数精炼、零客套、首屏可读。"
            case .balanced:
                "回答风格：结构清晰的 Markdown 排版（含小标题、加粗关键词、要点列表），兼顾核心事实、犀利点评与实操启发。"
            case .deep:
                "回答风格：深度分析型 Markdown（含分层标题、核心判断、反面视角、风险拆解与对比表格/引用），给出有洞察力的判断。"
        }
    }
}


/// A single industry news item displayed in the Analytics Dashboard NEWS feed.
nonisolated struct AIHotNewsItem: Identifiable, Codable, Hashable, Sendable {
    
    var id: String
    var title: String
    var source: String
    var urlString: String
    var publishedAt: Date?
    var heatScore: Int?
    var tag: String?
    var coverURLString: String? = nil
    var category: NewsFeedCategory? = nil
    var summary: String? = nil
    var contentBlocks: [NewsArticleBlock]? = nil
    
    var resolvedCategory: NewsFeedCategory {
        if let category, category != .all {
            return category
        }
        let host = URL(string: self.urlString)?.host?.lowercased() ?? ""
        if host.contains("x.com") || host.contains("twitter.com") || host.contains("nitter.") {
            return .xSocial
        }
        let haystack = "\(self.source) \(self.tag ?? "") \(self.title) \(self.urlString)".lowercased()
        if haystack.contains("x.com") || haystack.contains("twitter") || haystack.contains("x 热议") || haystack.contains("x 动态") {
            return .xSocial
        }
        if host.contains("cnbc") || host.contains("wsj") || host.contains("marketwatch") || host.contains("finance.yahoo")
            || host.contains("ft.com") || host.contains("seekingalpha")
            || haystack.contains("cnbc") || haystack.contains("wsj") || haystack.contains("yahoo") || haystack.contains("investing")
            || haystack.contains("bloomberg") || haystack.contains("reuters") || haystack.contains("marketwatch")
            || haystack.contains("财经") || haystack.contains("金融") || haystack.contains("美股") || haystack.contains("美联储")
            || haystack.contains("market") || haystack.contains("fed") || haystack.contains("stock") || haystack.contains("nasdaq")
        {
            return .finance
        }
        return .ai
    }
    
    var url: URL? {
        guard let sanitized = AIHotNewsService.sanitizedHTTPURLString(self.urlString) else { return nil }
        return URL(string: sanitized)
    }
    
    var coverURL: URL? {
        guard let sanitized = AIHotNewsService.sanitizedHTTPURLString(self.coverURLString) else { return nil }
        return URL(string: sanitized)
    }
    
    
    /// Publisher or domain label for the full reader workspace, suppressing generic `News` / `aihot` placeholders.
    var displayPublisherLabel: String {
        let clean = AIHotNewsService.sanitizedDisplaySource(self.source)
        if clean.caseInsensitiveCompare("News") == .orderedSame {
            return ""
        }
        return clean
    }
    
    
    /// Short, pill-free metadata string (never displays `ai.hot` / `aihot.news`).
    var conciseMetaLabel: String {
        var parts: [String] = []
        let cleanSource = self.displayPublisherLabel
        if !cleanSource.isEmpty {
            parts.append(cleanSource)
        }
        if let score = self.heatScore, score > 0 {
            parts.append("\(score)°")
        } else if let tag = self.tag, !tag.isEmpty, !tag.lowercased().contains("aihot") {
            parts.append(tag)
        }
        return parts.joined(separator: " · ")
    }
}


/// Persisted browsing history entry recorded when a user opens an article in the NEWS workspace.
nonisolated struct NewsBrowsingHistoryItem: Identifiable, Codable, Hashable, Sendable {
    
    let id: String
    var item: AIHotNewsItem
    var visitedAt: Date
    var visitCount: Int
}


/// Unified high-signal news aggregator for the Analytics Dashboard's NEWS column and fullscreen News Center:
/// Balances AI, Finance, and X/Social streams with Douyin/Xiaohongshu-style fresh-batch refresh,
/// persistent browsing history, multi-stage full-text extraction, and fast-summarizing AI tools.
@MainActor @Observable
final class AIHotNewsService {
    
    static let shared = AIHotNewsService()
    nonisolated static let portalURL = URL(string: "https://aihot.news/agent")!
    
    private enum FeedFormat: Sendable {
        case aihotJSON
        case aihotMarkdown
        case aihotRSS
        case rss
        case hnJSON
    }
    
    private struct FeedSource: Sendable {
        let urlString: String
        let label: String
        let category: NewsFeedCategory
        let format: FeedFormat
        let isPrimaryAIHot: Bool
    }
    
    private static let cacheTTL: TimeInterval = 5 * 60
    private static let feedSources: [FeedSource] = [
        // AI & Tech
        .init(urlString: "https://aihot.news/api/v1/items", label: "AIHot", category: .ai, format: .aihotJSON, isPrimaryAIHot: true),
        .init(urlString: "https://aihot.news/agent", label: "AIHot", category: .ai, format: .aihotMarkdown, isPrimaryAIHot: true),
        .init(urlString: "https://aihot.news/rss.xml", label: "AIHot", category: .ai, format: .aihotRSS, isPrimaryAIHot: true),
        .init(urlString: "https://openai.com/news/rss.xml", label: "OpenAI", category: .ai, format: .rss, isPrimaryAIHot: false),
        .init(urlString: "https://huggingface.co/blog/feed.xml", label: "Hugging Face", category: .ai, format: .rss, isPrimaryAIHot: false),
        .init(urlString: "https://techcrunch.com/category/artificial-intelligence/feed/", label: "TechCrunch", category: .ai, format: .rss, isPrimaryAIHot: false),
        .init(urlString: "https://feeds.arstechnica.com/arstechnica/technology-lab", label: "Ars Technica", category: .ai, format: .rss, isPrimaryAIHot: false),
        // Finance
        .init(urlString: "https://search.cnbc.com/rs/search/combinedcms/view.xml?partnerId=wrss01&id=10000664", label: "CNBC Markets", category: .finance, format: .rss, isPrimaryAIHot: false),
        .init(urlString: "https://search.cnbc.com/rs/search/combinedcms/view.xml?partnerId=wrss01&id=100003114", label: "CNBC Top", category: .finance, format: .rss, isPrimaryAIHot: false),
        .init(urlString: "https://search.cnbc.com/rs/search/combinedcms/view.xml?partnerId=wrss01&id=19854910", label: "CNBC Tech", category: .finance, format: .rss, isPrimaryAIHot: false),
        .init(urlString: "https://feeds.content.dowjones.io/public/rss/RSSMarketsMain", label: "WSJ", category: .finance, format: .rss, isPrimaryAIHot: false),
        .init(urlString: "https://feeds.content.dowjones.io/public/rss/mw_topstories", label: "MarketWatch", category: .finance, format: .rss, isPrimaryAIHot: false),
        .init(urlString: "https://finance.yahoo.com/news/rssindex", label: "Yahoo Finance", category: .finance, format: .rss, isPrimaryAIHot: false),
        // X / Social & Hacker Discussions
        .init(urlString: "https://hn.algolia.com/api/v1/search?tags=front_page&hitsPerPage=30", label: "HN Hot", category: .xSocial, format: .hnJSON, isPrimaryAIHot: false),
        .init(urlString: "https://hn.algolia.com/api/v1/search_by_date?tags=story&numericFilters=points%3E20&hitsPerPage=30", label: "HN Rising", category: .xSocial, format: .hnJSON, isPrimaryAIHot: false),
        .init(urlString: "https://hn.algolia.com/api/v1/search_by_date?query=x.com%20OR%20twitter&tags=story&hitsPerPage=24", label: "X / HN", category: .xSocial, format: .hnJSON, isPrimaryAIHot: false),
        .init(urlString: "https://lobste.rs/rss", label: "Lobsters", category: .xSocial, format: .rss, isPrimaryAIHot: false),
    ]
    
    private(set) var items: [AIHotNewsItem] = []
    private(set) var isLoading = false
    private(set) var lastUpdatedAt: Date?
    private(set) var loadFailed = false
    private(set) var feedRefreshToken: UInt64 = 0
    @ObservationIgnored private var categoryDisplayOrder: [NewsFeedCategory: [String]] = [:]
    @ObservationIgnored private var shownBatchIDsByCategory: [NewsFeedCategory: Set<String>] = [:]
    var selectedCategory: NewsFeedCategory = .all {
        didSet {
            guard self.selectedCategory != oldValue else { return }
            self.prefetchCovers(for: self.selectedCategory, limit: 12)
        }
    }
    private(set) var coverImages: [String: NSImage] = [:]
    private(set) var articleContents: [String: NewsArticleContent] = [:]
    private(set) var loadingArticleIDs: Set<String> = []
    private(set) var bookmarkedIDs: Set<String> = []
    private(set) var savedBookmarkedItems: [AIHotNewsItem] = []
    private(set) var readIDs: Set<String> = []
    private(set) var browsingHistory: [NewsBrowsingHistoryItem] = []
    private(set) var personalNotes: [String: String] = [:]
    private(set) var aiBriefs: [String: String] = [:]
    private(set) var isGeneratingBriefID: String? = nil
    private(set) var briefErrorMessage: String? = nil
    private(set) var chatHistories: [String: [NewsChatMessage]] = [:]
    @ObservationIgnored private var clearedNewsChatIDs: Set<String> = []
    private(set) var streamingChatItemID: String? = nil
    private(set) var streamingChatMessageID: String? = nil
    private(set) var streamingChatStatusLabel: String = ""
    private(set) var chatErrorMessage: String? = nil
    @ObservationIgnored private var activeChatTask: Task<Void, Never>?
    @ObservationIgnored private var activeChatGeneration: UInt64 = 0
    @ObservationIgnored private var chatStreamPatchListeners: [UUID: @MainActor (String, BeautifulAgentStreamPatchPayload) -> Void] = [:]
    
    @ObservationIgnored private var checkedDiskCoverIDs: Set<String> = []
    @ObservationIgnored private var checkedDiskArticleIDs: Set<String> = []
    @ObservationIgnored private var coverAccessOrder: [String] = []
    @ObservationIgnored private var articleAccessOrder: [String] = []
    @ObservationIgnored private var inFlightCoverIDs: Set<String> = []
    @ObservationIgnored private var resolvedNoCoverIDs: Set<String> = []
    @ObservationIgnored private var fetchedDetailIDs: Set<String> = []
    @ObservationIgnored private var preloadTask: Task<Void, Never>?
    @ObservationIgnored private var memoryPressureSource: DispatchSourceMemoryPressure?
    private let database: CotLocalDatabase
    private let coverCacheDirectory: URL
    private let articleCacheDirectory: URL
    
    private static let maxCachedCovers = 128
    private static let maxCachedArticles = 48
    private static let bookmarksDefaultsKey = "cot.news.bookmarkedItemsJSON"
    private static let readIDsDefaultsKey = "cot.news.readIDs"
    private static let notesDefaultsKey = "cot.news.personalNotes"
    
    private nonisolated(unsafe) static let parseDateLock = NSLock()
    private nonisolated(unsafe) static let isoFracFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private nonisolated(unsafe) static let isoStdFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
    private nonisolated(unsafe) static let fallbackDateFormatters: [DateFormatter] = [
        "EEE, dd MMM yyyy HH:mm:ss Z",
        "EEE, dd MMM yyyy HH:mm:ss zzz",
        "yyyy-MM-dd HH:mm:ss",
        "yyyy-MM-dd",
    ].map { fmt in
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = fmt
        return f
    }
    private nonisolated(unsafe) static let agentLinkRegex = try? NSRegularExpression(pattern: #"\[([^\]]+)\]\((https?://[^\s\)]+)\)"#)
    private nonisolated(unsafe) static let agentBareURLRegex = try? NSRegularExpression(pattern: #"https?://[^\s\)\]>]+"#)
    private nonisolated(unsafe) static let ogImageRegexes: [NSRegularExpression] = [
        #"<meta[^>]+(?:property|name)\s*=\s*["'](?:og:image:secure_url|og:image|twitter:image:src|twitter:image)["'][^>]+content\s*=\s*["']([^"']+)["']"#,
        #"<meta[^>]+content\s*=\s*["']([^"']+)["'][^>]+(?:property|name)\s*=\s*["'](?:og:image:secure_url|og:image|twitter:image:src|twitter:image)["']"#,
        #"<link[^>]+rel\s*=\s*["']image_src["'][^>]+href\s*=\s*["']([^"']+)["']"#,
    ].compactMap { try? NSRegularExpression(pattern: $0, options: [.caseInsensitive]) }
    private nonisolated(unsafe) static let firstHTMLImageRegex = try? NSRegularExpression(
        pattern: #"<img[^>]+src\s*=\s*["']([^"']+)["']"#,
        options: [.caseInsensitive]
    )
    private nonisolated(unsafe) static let ogDescRegexes: [NSRegularExpression] = [
        #"<meta[^>]+(?:property|name)\s*=\s*["'](?:og:description|twitter:description|description)["'][^>]+content\s*=\s*["']([^"']+)["']"#,
        #"<meta[^>]+content\s*=\s*["']([^"']+)["'][^>]+(?:property|name)\s*=\s*["'](?:og:description|twitter:description|description)["']"#,
    ].compactMap { try? NSRegularExpression(pattern: $0, options: [.caseInsensitive]) }
    
    
    func feedItems(for category: NewsFeedCategory) -> [AIHotNewsItem] {
        let base = (category == .all)
            ? self.items
            : self.items.filter { $0.resolvedCategory == category }
        guard let customOrder = self.categoryDisplayOrder[category], !customOrder.isEmpty else {
            return base
        }
        let rankByID = Dictionary(uniqueKeysWithValues: customOrder.enumerated().map { ($0.element, $0.offset) })
        let enumerated = Array(base.enumerated())
        return enumerated.sorted { lhs, rhs in
            switch (rankByID[lhs.element.id], rankByID[rhs.element.id]) {
                case (.some(let lRank), .some(let rRank)):
                    return lRank < rRank
                case (.some, .none):
                    return false
                case (.none, .some):
                    return true
                case (.none, .none):
                    return lhs.offset < rhs.offset
            }
        }.map(\.element)
    }
    
    
    var filteredItems: [AIHotNewsItem] {
        self.feedItems(for: self.selectedCategory)
    }
    
    
    func replaceItemsForTesting(_ newItems: [AIHotNewsItem]) {
        self.items = newItems
        self.categoryDisplayOrder.removeAll()
        self.shownBatchIDsByCategory.removeAll()
        self.feedRefreshToken &+= 1
    }
    
    
    init(database: CotLocalDatabase = .shared, cacheRootDirectory: URL? = nil) {
        self.database = database
        let baseRoot: URL = if let cacheRootDirectory {
            cacheRootDirectory
        } else {
            (FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
                ?? URL(filePath: NSTemporaryDirectory(), directoryHint: .isDirectory))
                .appending(path: "CotEditor", directoryHint: .isDirectory)
        }
        self.coverCacheDirectory = baseRoot.appending(path: "NewsCovers", directoryHint: .isDirectory)
        self.articleCacheDirectory = baseRoot.appending(path: "NewsArticlesV1", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: self.coverCacheDirectory, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: self.articleCacheDirectory, withIntermediateDirectories: true)
        self.loadCachedItems()
        self.loadInteractiveState()
        
        if Self.isNetworkPreloadAllowed, database === CotLocalDatabase.shared {
            let source = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: .main)
            source.setEventHandler { [weak self] in
                Task { @MainActor [weak self] in
                    self?.trimCachesForMemoryPressure()
                }
            }
            source.resume()
            self.memoryPressureSource = source
        }
    }
    
    
    isolated deinit {
        self.preloadTask?.cancel()
        self.memoryPressureSource?.cancel()
    }
    
    
    func trimCachesForMemoryPressure() {
        let activeFeedIDs = Set(self.items.map(\.id))
        for key in Array(self.coverImages.keys) where !activeFeedIDs.contains(key) {
            self.coverImages.removeValue(forKey: key)
            self.checkedDiskCoverIDs.remove(key)
        }
        self.coverAccessOrder.removeAll { !activeFeedIDs.contains($0) }
        self.articleContents.removeAll()
        self.articleAccessOrder.removeAll()
        self.checkedDiskArticleIDs.removeAll()
    }
    
    
    func storeCoverImage(_ image: NSImage, for itemID: String) {
        self.coverImages[itemID] = image
        self.coverAccessOrder.removeAll { $0 == itemID }
        self.coverAccessOrder.append(itemID)
        if self.coverAccessOrder.count > Self.maxCachedCovers {
            let activeFeedIDs = Set(self.items.map(\.id))
            var idx = 0
            while self.coverAccessOrder.count > Self.maxCachedCovers && idx < self.coverAccessOrder.count {
                let candidate = self.coverAccessOrder[idx]
                if activeFeedIDs.contains(candidate) && self.coverAccessOrder.count > activeFeedIDs.count {
                    idx += 1
                    continue
                }
                self.coverAccessOrder.remove(at: idx)
                self.coverImages.removeValue(forKey: candidate)
                if !activeFeedIDs.contains(candidate) {
                    self.checkedDiskCoverIDs.remove(candidate)
                }
            }
        }
    }
    
    
    private func storeArticleContent(_ content: NewsArticleContent, for itemID: String) {
        var normalized = content
        normalized.blocks = Self.sanitizedArticleBlocks(content.blocks)
        self.articleContents[itemID] = normalized
        self.articleAccessOrder.removeAll { $0 == itemID }
        self.articleAccessOrder.append(itemID)
        while self.articleAccessOrder.count > Self.maxCachedArticles {
            let evicted = self.articleAccessOrder.removeFirst()
            self.articleContents.removeValue(forKey: evicted)
            self.checkedDiskArticleIDs.remove(evicted)
        }
    }
    
    
    // MARK: Interactive Reader State (Bookmarks, Read Status, Full Articles, AI Briefs)
    
    func isBookmarked(_ item: AIHotNewsItem) -> Bool {
        self.bookmarkedIDs.contains(item.id)
    }
    
    
    func toggleBookmark(_ item: AIHotNewsItem) {
        if self.bookmarkedIDs.contains(item.id) {
            self.bookmarkedIDs.remove(item.id)
            self.savedBookmarkedItems.removeAll { $0.id == item.id }
        } else {
            self.bookmarkedIDs.insert(item.id)
            if !self.savedBookmarkedItems.contains(where: { $0.id == item.id }) {
                var enriched = item
                if enriched.contentBlocks == nil, let cached = self.articleContents[item.id]?.blocks, !cached.isEmpty {
                    enriched.contentBlocks = cached
                }
                self.savedBookmarkedItems.insert(enriched, at: 0)
            }
        }
        self.saveBookmarkedItems()
    }
    
    
    func isRead(_ item: AIHotNewsItem) -> Bool {
        self.readIDs.contains(item.id)
    }
    
    
    func markRead(_ item: AIHotNewsItem) {
        guard self.readIDs.insert(item.id).inserted else { return }
        let trimmed = Array(self.readIDs.prefix(500))
        if let data = try? JSONEncoder().encode(trimmed), let str = String(data: data, encoding: .utf8) {
            self.database.set(str, forKey: CotLocalDatabase.ConfigKey.newsReadIDsJSON)
        }
    }
    
    
    /// Records or updates an article in persistent browsing history (most-recent first, bounded to 200 items).
    func recordBrowsingHistory(_ item: AIHotNewsItem) {
        self.markRead(item)
        var snapshot = item
        if (snapshot.contentBlocks?.isEmpty ?? true),
           let cachedBlocks = self.articleContents[item.id]?.blocks,
           !cachedBlocks.isEmpty
        {
            snapshot.contentBlocks = cachedBlocks
        }
        if snapshot.summary == nil || snapshot.summary?.isEmpty == true,
           let live = self.items.first(where: { $0.id == item.id }),
           let liveSummary = live.summary, !liveSummary.isEmpty
        {
            snapshot.summary = liveSummary
        }
        
        if let existingIndex = self.browsingHistory.firstIndex(where: { $0.id == item.id }) {
            var entry = self.browsingHistory.remove(at: existingIndex)
            entry.item = snapshot
            entry.visitedAt = Date()
            entry.visitCount += 1
            self.browsingHistory.insert(entry, at: 0)
        } else {
            let entry = NewsBrowsingHistoryItem(
                id: item.id,
                item: snapshot,
                visitedAt: Date(),
                visitCount: 1
            )
            self.browsingHistory.insert(entry, at: 0)
        }
        if self.browsingHistory.count > 200 {
            self.browsingHistory = Array(self.browsingHistory.prefix(200))
        }
        self.saveBrowsingHistory()
    }
    
    
    func removeBrowsingHistory(id: String) {
        self.browsingHistory.removeAll { $0.id == id }
        self.saveBrowsingHistory()
    }
    
    
    func clearBrowsingHistory() {
        self.browsingHistory.removeAll()
        self.saveBrowsingHistory()
    }
    
    
    func findItem(byID id: String) -> AIHotNewsItem? {
        self.items.first(where: { $0.id == id })
            ?? self.savedBookmarkedItems.first(where: { $0.id == id })
            ?? self.browsingHistory.first(where: { $0.id == id })?.item
    }
    
    
    private func saveBrowsingHistory() {
        if let encoded = try? JSONEncoder().encode(self.browsingHistory),
           let str = String(data: encoded, encoding: .utf8)
        {
            self.database.set(str, forKey: CotLocalDatabase.ConfigKey.newsBrowsingHistoryJSON)
        }
    }
    
    
    func note(for itemID: String) -> String {
        self.personalNotes[itemID] ?? ""
    }
    
    
    func setNote(_ note: String, for itemID: String) {
        let trimmed = note.trimmingCharacters(in: .newlines)
        if trimmed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            self.personalNotes.removeValue(forKey: itemID)
        } else {
            self.personalNotes[itemID] = trimmed
        }
        if let data = try? JSONEncoder().encode(self.personalNotes), let str = String(data: data, encoding: .utf8) {
            self.database.set(str, forKey: CotLocalDatabase.ConfigKey.newsPersonalNotesJSON)
        }
    }
    
    
    func setAIBrief(_ brief: String, for itemID: String) {
        let cleaned = brief.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.isEmpty {
            self.aiBriefs.removeValue(forKey: itemID)
        } else {
            self.aiBriefs[itemID] = cleaned
        }
        // Keep bounded most-recent 120 briefs in SQLite
        if self.aiBriefs.count > 120, let dropKey = self.aiBriefs.keys.first {
            self.aiBriefs.removeValue(forKey: dropKey)
        }
        if let data = try? JSONEncoder().encode(self.aiBriefs), let str = String(data: data, encoding: .utf8) {
            self.database.set(str, forKey: CotLocalDatabase.ConfigKey.newsAIBriefsJSON)
        }
    }
    
    
    func resolvedArticleBlocks(for item: AIHotNewsItem) -> [NewsArticleBlock] {
        if let loaded = self.articleContents[item.id]?.blocks, !loaded.isEmpty {
            return Self.sanitizedArticleBlocks(loaded, title: item.title)
        }
        if let embedded = item.contentBlocks, !embedded.isEmpty {
            return Self.sanitizedArticleBlocks(embedded, title: item.title)
        }
        if !self.checkedDiskArticleIDs.contains(item.id) {
            self.checkedDiskArticleIDs.insert(item.id)
            let itemID = item.id
            let diskURL = self.diskArticleURL(for: item)
            Task.detached(priority: .userInitiated) { [weak self] in
                guard let data = try? Data(contentsOf: diskURL),
                      let decoded = try? JSONDecoder().decode(NewsArticleContent.self, from: data),
                      !decoded.blocks.isEmpty
                else { return }
                await MainActor.run {
                    self?.storeArticleContent(decoded, for: itemID)
                }
            }
        }
        return []
    }
    
    
    /// Detects synthetic auto-generated OG text/scorecard banners (such as `aihot.news` dark scorecards)
    /// that repeat the article headline and clutter the editorial detail reader.
    nonisolated static func isSyntheticOGCardURL(_ urlString: String?) -> Bool {
        guard let raw = urlString?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return false
        }
        let lower = raw.lowercased()
        if let host = URL(string: raw)?.host?.lowercased() {
            if host == "aihot.news" || host.hasSuffix(".aihot.news") || host == "ai.hot" || host.hasSuffix(".ai.hot") {
                return true
            }
        }
        let syntheticMarkers = [
            "aihot.news", "/api/og", "/og-image", "/og_image", "og-card", "og_card",
            "share-card", "share_card", "opengraph-image", "social-card",
        ]
        return syntheticMarkers.contains { lower.contains($0) }
    }
    
    
    /// Strips empty/orphan headings (such as trailing "所属事件", "相关事件", "延伸阅读")
    /// and removes leading headings/paragraphs that duplicate the article `title`.
    nonisolated static func sanitizedArticleBlocks(_ blocks: [NewsArticleBlock], title: String? = nil) -> [NewsArticleBlock] {
        let boilerplateHeadings: Set<String> = [
            "所属事件", "相关事件", "相关阅读", "延伸阅读", "相关推荐", "更多阅读", "原文链接",
        ]
        let normalizedTitle = Self.normalizedComparisonText(title ?? "")
        var cleaned: [NewsArticleBlock] = []
        for (idx, block) in blocks.enumerated() {
            if cleaned.isEmpty, !normalizedTitle.isEmpty {
                switch block {
                    case .heading(_, let text), .paragraph(let text):
                        let normBlock = Self.normalizedComparisonText(text)
                        if !normBlock.isEmpty && Self.isDuplicateTitle(normBlock, normalizedTitle) {
                            continue
                        }
                    default:
                        break
                }
            }
            if case .heading(_, let text) = block {
                let norm = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if norm.isEmpty || boilerplateHeadings.contains(norm) {
                    continue
                }
                // Drop heading if no non-heading content follows it
                let hasFollowingBody = blocks.dropFirst(idx + 1).contains { next in
                    if case .heading = next { return false }
                    return true
                }
                if !hasFollowingBody { continue }
            }
            cleaned.append(block)
        }
        while case .heading = cleaned.last {
            cleaned.removeLast()
        }
        return cleaned
    }
    
    
    private nonisolated static func normalizedComparisonText(_ text: String) -> String {
        text.lowercased()
            .replacingOccurrences(of: #"[\s\p{P}\p{S}]+"#, with: "", options: .regularExpression)
    }
    
    
    private nonisolated static func isDuplicateTitle(_ candidate: String, _ title: String) -> Bool {
        if candidate == title { return true }
        let shorter = min(candidate.count, title.count)
        let longer = max(candidate.count, title.count)
        guard shorter >= 6, longer > 0 else { return false }
        if (candidate.contains(title) || title.contains(candidate)), Double(shorter) / Double(longer) >= 0.80 {
            return true
        }
        return false
    }
    
    
    func hasFinishedDetailFetch(for itemID: String) -> Bool {
        self.fetchedDetailIDs.contains(itemID)
    }
    
    
    private func diskArticleURL(for item: AIHotNewsItem) -> URL {
        let digest = SHA256.hash(data: Data(item.urlString.utf8))
        let hex = digest.prefix(12).map { String(format: "%02x", $0) }.joined()
        return self.articleCacheDirectory.appending(path: "\(hex).json")
    }
    
    
    func fetchArticleExcerptIfNeeded(for item: AIHotNewsItem) async {
        if let loaded = self.articleContents[item.id], loaded.isSubstantial {
            self.fetchedDetailIDs.insert(item.id)
            return
        }
        if let embedded = item.contentBlocks,
           NewsArticleContent(blocks: embedded, leadExcerpt: item.summary, author: nil, extractedAt: .now).isSubstantial
        {
            self.fetchedDetailIDs.insert(item.id)
            return
        }
        self.checkedDiskArticleIDs.insert(item.id)
        let diskURL = self.diskArticleURL(for: item)
        let diskCached: NewsArticleContent? = await Task.detached(priority: .userInitiated) {
            guard let data = try? Data(contentsOf: diskURL),
                  let decoded = try? JSONDecoder().decode(NewsArticleContent.self, from: data),
                  decoded.isSubstantial
            else { return nil }
            return decoded
        }.value
        if let diskCached {
            self.storeArticleContent(diskCached, for: item.id)
            self.fetchedDetailIDs.insert(item.id)
            return
        }
        guard Self.isNetworkPreloadAllowed,
              !self.loadingArticleIDs.contains(item.id),
              !self.fetchedDetailIDs.contains(item.id),
              let pageURL = item.url
        else { return }
        
        self.loadingArticleIDs.insert(item.id)
        defer {
            self.loadingArticleIDs.remove(item.id)
            self.fetchedDetailIDs.insert(item.id)
        }
        
        let fetched = await Self.fetchFullArticleAndMeta(from: pageURL)
        guard !Task.isCancelled else { return }
        
        if let content = fetched.content, !content.blocks.isEmpty {
            let candidateNorm = NewsArticleContent(
                blocks: Self.sanitizedArticleBlocks(content.blocks, title: item.title),
                leadExcerpt: content.leadExcerpt,
                author: content.author,
                extractedAt: content.extractedAt
            )
            let existingLen = self.articleContents[item.id]?.plainTextLength ?? 0
            if candidateNorm.plainTextLength > existingLen {
                self.storeArticleContent(candidateNorm, for: item.id)
            }
            if candidateNorm.isSubstantial, let encoded = try? JSONEncoder().encode(candidateNorm) {
                try? encoded.write(to: diskURL, options: .atomic)
            }
        }
        if let desc = fetched.description, !desc.isEmpty,
           let idx = self.items.firstIndex(where: { $0.id == item.id }),
           (self.items[idx].summary ?? "").count < desc.count
        {
            self.items[idx].summary = desc
        }
        if let img = fetched.imageURLString,
           let idx = self.items.firstIndex(where: { $0.id == item.id }),
           self.items[idx].coverURLString == nil
        {
            self.items[idx].coverURLString = img
            self.triggerCoverLoadIfNeeded(for: self.items[idx])
        }
    }
    
    
    /// Forces a fresh multi-stage full-text fetch (ignoring prior negative or short cache).
    func refetchArticleExcerpt(for item: AIHotNewsItem) async {
        self.fetchedDetailIDs.remove(item.id)
        self.articleContents.removeValue(forKey: item.id)
        try? FileManager.default.removeItem(at: self.diskArticleURL(for: item))
        await self.fetchArticleExcerptIfNeeded(for: item)
    }
    
    
    func generateAIBrief(for item: AIHotNewsItem) async {
        guard self.isGeneratingBriefID == nil else { return }
        guard AIService.shared.isConfigured(for: .summarize) else {
            self.briefErrorMessage = AppLanguage.text("未配置 AI 模型", en: "AI unconfigured")
            return
        }
        
        self.briefErrorMessage = nil
        self.isGeneratingBriefID = item.id
        defer {
            if self.isGeneratingBriefID == item.id {
                self.isGeneratingBriefID = nil
            }
        }
        
        let sourceNote = item.displayPublisherLabel.isEmpty ? item.resolvedCategory.badgeLabel : item.displayPublisherLabel
        let blocks = self.resolvedArticleBlocks(for: item)
        let fullBody = blocks.map(\.markdownText).joined(separator: "\n\n")
        let bodyContext = !fullBody.isEmpty
            ? String(fullBody.prefix(3600))
            : (item.summary?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "")
        
        let payload = """
        标题：\(item.title)
        分类：\(item.resolvedCategory.label)\(sourceNote.isEmpty ? "" : " · \(sourceNote)")
        链接：\(item.urlString)
        \(bodyContext.isEmpty ? "" : "正文内容：\n\(bodyContext)")

        请用中文直接输出 3 条高密度精读要点（严禁客套开场白）：
        1. 核心突破或事实数据
        2. 技术/产业深层逻辑与影响
        3. 可借鉴切入点或后续跟进方向
        """
        
        final class BriefEmitGate: @unchecked Sendable {
            var lastUptime: TimeInterval = 0
        }
        let emitGate = BriefEmitGate()
        let itemID = item.id
        do {
            let output = try await AIService.shared.run(.summarize, on: payload) { partial in
                let now = ProcessInfo.processInfo.systemUptime
                guard now - emitGate.lastUptime >= 0.05 else { return }
                emitGate.lastUptime = now
                AIHotNewsService.shared.aiBriefs[itemID] = partial
            }
            self.setAIBrief(output, for: itemID)
        } catch {
            self.briefErrorMessage = error.localizedDescription
        }
    }
    
    
        // MARK: Simple Article AI Chat (Commentary/Summary + Follow-Up)
    
    func chatMessages(for item: AIHotNewsItem) -> [NewsChatMessage] {
        if let history = self.chatHistories[item.id] {
            if !history.isEmpty {
                return history
            }
            if self.clearedNewsChatIDs.contains(item.id) {
                return []
            }
        }
        if !self.clearedNewsChatIDs.contains(item.id) {
            let archived = self.database.fetchAIConversationLogs(channel: "news", sessionID: item.id, limit: 80)
            if !archived.isEmpty {
                return archived.map { log in
                    NewsChatMessage(
                        id: log.id,
                        role: log.role == "user" ? .user : .assistant,
                        text: log.content,
                        createdAt: log.createdAt
                    )
                }
            }
        }
        if let savedBrief = self.aiBriefs[item.id]?.trimmingCharacters(in: .whitespacesAndNewlines), !savedBrief.isEmpty {
            return [NewsChatMessage(id: "brief-\(item.id)", role: .assistant, text: savedBrief)]
        }
        return []
    }
    
    
    private func cancelAndResetChatStreaming(resetRPC: Bool) {
        let wasStreaming = self.streamingChatItemID != nil
        let priorItemID = self.streamingChatItemID
        let priorMessageID = self.streamingChatMessageID
        let priorTask = self.activeChatTask
        
        self.activeChatGeneration &+= 1
        self.streamingChatItemID = nil
        self.streamingChatMessageID = nil
        self.streamingChatStatusLabel = ""
        self.activeChatTask = nil
        
        priorTask?.cancel()
        
        // Remove blank placeholder assistant message if cancelled before any token arrived.
        if let priorItemID, let priorMessageID, var list = self.chatHistories[priorItemID] {
            if let idx = list.firstIndex(where: { $0.id == priorMessageID }),
               list[idx].text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            {
                list.remove(at: idx)
                self.chatHistories[priorItemID] = list
            }
        }
        
        if self.database === CotLocalDatabase.shared {
            if resetRPC {
                PiKernelManager.shared.resetRPCSession(channel: .news, forceAbort: true)
            } else if wasStreaming {
                PiKernelManager.shared.abortRPCTurn(channel: .news)
            }
        }
    }
    
    
    func clearChat(for itemID: String) {
        if self.streamingChatItemID == itemID {
            self.cancelAndResetChatStreaming(resetRPC: true)
        } else if self.database === CotLocalDatabase.shared {
            PiKernelManager.shared.resetRPCSession(channel: .news, forceAbort: true)
        }
        self.clearedNewsChatIDs.insert(itemID)
        self.chatHistories[itemID] = []
        self.chatErrorMessage = nil
    }
    
    
    @discardableResult
    func addChatStreamPatchListener(
        _ listener: @escaping @MainActor (String, BeautifulAgentStreamPatchPayload) -> Void
    ) -> UUID {
        let id = UUID()
        self.chatStreamPatchListeners[id] = listener
        return id
    }
    
    
    func removeChatStreamPatchListener(_ id: UUID) {
        self.chatStreamPatchListeners.removeValue(forKey: id)
    }
    
    
    private func emitChatStreamPatch(itemID: String, patch: BeautifulAgentStreamPatchPayload) {
        for listener in self.chatStreamPatchListeners.values {
            listener(itemID, patch)
        }
    }
    
    
    func abortChat() {
        guard self.streamingChatItemID != nil else { return }
        self.cancelAndResetChatStreaming(resetRPC: false)
    }
    
    
    func retryLastChat(
        for item: AIHotNewsItem,
        effort: NewsReasoningEffort = .simple,
        selectedModel: NewsChatModelOption? = nil
    ) {
        guard self.streamingChatItemID == nil else { return }
        let history = self.chatMessages(for: item)
        guard let lastUser = history.last(where: { $0.role == .user }) else { return }
        Task {
            await self.sendChatFollowUp(
                lastUser.text,
                for: item,
                quote: lastUser.quoteContext,
                effort: effort,
                selectedModel: selectedModel
            )
        }
    }
    
    
    /// Builds a clean Markdown study note combining the article content and AI chat insights.
    func buildMarkdownStudyNote(for item: AIHotNewsItem) -> String {
        var lines: [String] = []
        lines.append("# \(item.title)")
        lines.append("")
        var meta: [String] = [item.resolvedCategory.label]
        if !item.displayPublisherLabel.isEmpty { meta.append(item.displayPublisherLabel) }
        if !item.urlString.isEmpty { meta.append("[原文链接](\(item.urlString))") }
        lines.append("> \(meta.joined(separator: " · "))")
        lines.append("")
        
        let messages = self.chatMessages(for: item).filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        if !messages.isEmpty {
            lines.append("## AI 解读与思考")
            lines.append("")
            for msg in messages {
                if msg.role == .user {
                    lines.append("**问**：\(msg.text)")
                } else {
                    lines.append(msg.text)
                }
                lines.append("")
            }
        }
        
        let blocks = self.resolvedArticleBlocks(for: item)
        if !blocks.isEmpty {
            lines.append("## 原文摘录")
            lines.append("")
            lines.append(blocks.map(\.markdownText).joined(separator: "\n\n"))
        } else if let summary = item.summary?.trimmingCharacters(in: .whitespacesAndNewlines), !summary.isEmpty {
            lines.append("## 摘要")
            lines.append("")
            lines.append(summary)
        }
        return lines.joined(separator: "\n")
    }
    
    
    /// Collects all usable models across configured API gateways, active gateway first.
    static func availableChatModels() -> [NewsChatModelOption] {
        let profiles = AIEndpointStore.profiles
        let activeID = AIEndpointStore.activeID
        let ordered = profiles.sorted { lhs, rhs in
            if lhs.id == activeID { return true }
            if rhs.id == activeID { return false }
            return lhs.displayName.localizedStandardCompare(rhs.displayName) == .orderedAscending
        }
        
        var seen = Set<String>()
        var options: [NewsChatModelOption] = []
        for profile in ordered {
            let candidates = ([profile.model] + profile.savedModels + profile.provider.recommendedModels)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            for modelID in candidates {
                let dedupeKey = "\(profile.id.uuidString)::\(modelID.lowercased())"
                guard seen.insert(dedupeKey).inserted else { continue }
                options.append(NewsChatModelOption(
                    endpointID: profile.id,
                    endpointName: profile.displayName,
                    modelID: modelID
                ))
            }
        }
        return options
    }
    
    
    /// Resolves the exact `AIConfiguration` for the selected model and reasoning effort.
    static func resolveChatConfiguration(
        for selectedModel: NewsChatModelOption?,
        effort: NewsReasoningEffort
    ) -> AIConfiguration {
        var config: AIConfiguration
        if let selectedModel,
           let profile = AIEndpointStore.profiles.first(where: { $0.id == selectedModel.endpointID })
        {
            var overridden = profile
            overridden.model = selectedModel.modelID
            config = overridden.configuration(apiKey: AIEndpointStore.apiKey(for: profile))
        } else {
            config = AIBotStore.shared.resolvedConfiguration(for: .readingCompanion, baseConfig: .current)
        }
        config.reasoningEffort = effort.apiValue
        config.temperature = effort.temperature
        return config
    }
    
    
    /// Triggers one-click sharp AI commentary & summary for `item` as the first chat turn.
    func requestAICommentary(
        for item: AIHotNewsItem,
        effort: NewsReasoningEffort = .simple,
        selectedModel: NewsChatModelOption? = nil
    ) async {
        let prompt = AppLanguage.text(
            "请快速总结这篇文章的核心事实、关键数字，并给出 1-2 条犀利点评。",
            en: "Quickly summarize this article's core facts, key numbers, and 1-2 sharp takeaways."
        )
        await self.sendChatFollowUp(
            prompt,
            for: item,
            displayUserText: AppLanguage.text("快速提炼核心事实与点评", en: "Quick summary & critique"),
            saveAsBrief: true,
            effort: effort,
            selectedModel: selectedModel
        )
    }
    
    
    /// Appends a user follow-up question and streams the AI reply via warm Pi RPC (`channel: .news`, with live stock/web tools)
    /// or falls back seamlessly to direct SSE streaming.
    func sendChatFollowUp(
        _ question: String,
        for item: AIHotNewsItem,
        displayUserText: String? = nil,
        quote: String? = nil,
        saveAsBrief: Bool = false,
        effort: NewsReasoningEffort = .simple,
        selectedModel: NewsChatModelOption? = nil
    ) async {
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if let activeID = self.streamingChatItemID {
            if self.activeChatTask == nil || activeID != item.id {
                self.cancelAndResetChatStreaming(resetRPC: false)
            } else {
                return
            }
        }
        
        let resolvedConfig = Self.resolveChatConfiguration(for: selectedModel, effort: effort)
        guard resolvedConfig.isUsable else {
            self.chatErrorMessage = AppLanguage.text("请先在「设置 → API 网关」配置 AI 模型", en: "Configure an AI model in Settings first")
            return
        }
        
        self.chatErrorMessage = nil
        let itemID = item.id
        let cleanQuote = quote?.trimmingCharacters(in: .whitespacesAndNewlines)
        var history = self.chatMessages(for: item)
        
        self.clearedNewsChatIDs.remove(itemID)
        let userMsg = NewsChatMessage(
            role: .user,
            text: displayUserText ?? trimmed,
            quoteContext: (cleanQuote?.isEmpty == false) ? cleanQuote : nil
        )
        let assistantID = UUID().uuidString
        let placeholderAssistant = NewsChatMessage(id: assistantID, role: .assistant, text: "")
        history.append(userMsg)
        history.append(placeholderAssistant)
        self.chatHistories[itemID] = history
        self.database.appendAIConversationLog(AIConversationLogRecord(
            id: "news:\(userMsg.id)",
            channel: "news",
            sessionID: itemID,
            workspaceName: item.title,
            botID: AIBotID.readingCompanion.rawValue,
            role: "user",
            content: userMsg.text,
            createdAt: userMsg.createdAt,
            memoryExtracted: false
        ))
        self.activeChatGeneration &+= 1
        let turnGeneration = self.activeChatGeneration
        self.streamingChatItemID = itemID
        self.streamingChatMessageID = assistantID
        self.streamingChatStatusLabel = AppLanguage.text("正在总结…", en: "Summarizing...")
        
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.performNewsChatTurn(
                question: trimmed,
                quote: cleanQuote,
                item: item,
                assistantID: assistantID,
                priorHistory: Array(history.dropLast(2).suffix(10)),
                saveAsBrief: saveAsBrief,
                effort: effort,
                selectedModel: selectedModel,
                resolvedConfig: resolvedConfig,
                generation: turnGeneration
            )
        }
        self.activeChatTask = task
        await task.value
        if self.activeChatGeneration == turnGeneration {
            self.activeChatTask = nil
        }
    }
    
    
    private func performNewsChatTurn(
        question: String,
        quote: String?,
        item: AIHotNewsItem,
        assistantID: String,
        priorHistory: [NewsChatMessage],
        saveAsBrief: Bool,
        effort: NewsReasoningEffort,
        selectedModel: NewsChatModelOption?,
        resolvedConfig: AIConfiguration,
        generation: UInt64
    ) async {
        let itemID = item.id
        let startedAt = Date()
        let turnClockStart = ContinuousClock.now
        defer {
            if self.activeChatGeneration == generation && self.streamingChatItemID == itemID {
                self.streamingChatItemID = nil
                self.streamingChatMessageID = nil
                self.streamingChatStatusLabel = ""
            }
        }
        
        let sourceNote = item.displayPublisherLabel.isEmpty ? item.resolvedCategory.badgeLabel : item.displayPublisherLabel
        var blocks = self.resolvedArticleBlocks(for: item)
        let initialContent = NewsArticleContent(blocks: blocks, leadExcerpt: item.summary, author: nil, extractedAt: .now)
        if !initialContent.isSubstantial, !self.loadingArticleIDs.contains(itemID) {
            await self.fetchArticleExcerptIfNeeded(for: item)
            guard self.activeChatGeneration == generation, !Task.isCancelled else { return }
            blocks = self.resolvedArticleBlocks(for: item)
        }
        let liveItem = self.findItem(byID: itemID) ?? item
        let fullBody = blocks.map(\.markdownText).joined(separator: "\n\n")
        let summaryFallback = liveItem.summary?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let bodyContext = !fullBody.isEmpty
            ? String(fullBody.prefix(4800))
            : summaryFallback
        
        let promptWithQuote: String = if let quote, !quote.isEmpty {
            """
            <selected_article_excerpt>
            \(quote)
            </selected_article_excerpt>

            针对上面这段摘录，我的问题是：
            \(question)
            """
        } else {
            question
        }
        
        let resolvedEndpointProfile: AIEndpointProfile? = {
            if let selectedModel,
               let profile = AIEndpointStore.profiles.first(where: { $0.id == selectedModel.endpointID })
            {
                return profile
            }
            return AIBotStore.shared.resolvedEndpointProfile(for: .readingCompanion)
        }()
        
        // 1. Primary path: Warm Persistent Pi RPC (`channel: .news`, Cot tools enabled, no builtin shell/fs)
        if self.database === CotLocalDatabase.shared,
           PiKernelManager.shared.canRunRPC,
           let endpointProfile = resolvedEndpointProfile
        {
            let piSystemContext = """
            你是 CotEditor 内置的快速资讯精读助手。默认以高响应速度输出精准、清晰、结构化的摘要与犀利结论。
            \(effort.styleDirective)
            工具使用准则（非常重要）：
            - 若下方「正文内容」为空或明显不完整，**必须立即先调用 `web_fetch(url: "\(item.urlString)")`** 获取原文，再做总结，严禁凭标题脑补。
            - 当文章涉及上市公司/芯片/指数或用户询问股价与市场表现时，立即调用 `lookup_stock_quote` 获取真实行情。
            - 当需要核查最新进展、财报数据或关联背景时，调用 `web_search` 或 `search_news`。
            - 当用户要求把结论存成笔记时，调用 `editor_action(type:"open_document", title:..., content:...)`。
            - 使用干净的 Markdown 排版（重点加粗、精炼要点列表、必要时引用或表格），直奔主题、禁止废话客套、不要暴露内部工具名。

            标题：\(liveItem.title)
            分类：\(liveItem.resolvedCategory.label)\(sourceNote.isEmpty ? "" : " · \(sourceNote)")
            链接：\(liveItem.urlString)
            \(bodyContext.isEmpty ? "（当前正文尚未加载，建议调用 web_fetch 抓取原文）" : "正文内容：\n\(bodyContext)")
            """
            
            let priorSummary: String? = priorHistory.isEmpty ? nil : priorHistory.compactMap { turn -> String? in
                let c = turn.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !c.isEmpty else { return nil }
                return "[\(turn.role == .user ? "用户" : "助手")]: \(String(c.prefix(600)))"
            }.joined(separator: "\n\n")
            
            var liveSteps: [BeautifulAgentThinkingStep] = []
            var liveThinking = ""
            var liveText = ""
            
            let closeNewsThinkingSteps: (Int?) -> Void = { explicitDurationMs in
                let nowMs = Date().timeIntervalSince1970 * 1000
                for i in liveSteps.indices where liveSteps[i].id == "news-think" && liveSteps[i].status == "running" {
                    liveSteps[i].status = "done"
                    if let explicitDurationMs, explicitDurationMs > 0 {
                        liveSteps[i].durationMs = explicitDurationMs
                    } else if liveSteps[i].durationMs == nil, let s = liveSteps[i].startedAtMs {
                        liveSteps[i].durationMs = max(1, Int(nowMs - s))
                    }
                }
            }
            
            do {
                let result = try await PiKernelManager.shared.runRPCTurn(
                    channel: .news,
                    logicalSessionKey: "news-\(itemID)",
                    systemPrompt: piSystemContext,
                    userPrompt: promptWithQuote,
                    priorHistoryContext: priorSummary,
                    endpointProfile: endpointProfile,
                    configuration: resolvedConfig,
                    thinkingLevel: effort.apiValue
                ) { [weak self] event in
                    guard let self, self.activeChatGeneration == generation else { return }
                    let elapsedMs = max(0, Int(Date().timeIntervalSince(startedAt) * 1000))
                    switch event {
                        case .status(let label):
                            self.streamingChatStatusLabel = label
                        case .thinkingStart(let startedAtMs):
                            self.streamingChatStatusLabel = AppLanguage.text("正在深度分析…", en: "Analyzing...")
                            if !liveSteps.contains(where: { $0.id == "news-think" }) {
                                liveSteps.append(BeautifulAgentThinkingStep(
                                    id: "news-think",
                                    label: AppLanguage.text("深度推理", en: "Reasoning"),
                                    status: "running",
                                    kind: "thinking",
                                    startedAtMs: startedAtMs
                                ))
                            }
                        case .thinkingDelta(let thinking):
                            liveThinking = thinking
                            self.streamingChatStatusLabel = AppLanguage.text("正在深度分析…", en: "Analyzing...")
                            let previewLines = thinking.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.suffix(3).map { String($0.prefix(140)) }
                            if let i = liveSteps.firstIndex(where: { $0.id == "news-think" }) {
                                liveSteps[i].detail = previewLines.isEmpty ? nil : previewLines
                                liveSteps[i].status = "running"
                            } else {
                                liveSteps.append(BeautifulAgentThinkingStep(
                                    id: "news-think",
                                    label: AppLanguage.text("深度推理", en: "Reasoning"),
                                    status: "running",
                                    detail: previewLines.isEmpty ? nil : previewLines,
                                    kind: "thinking",
                                    startedAtMs: Date().timeIntervalSince1970 * 1000
                                ))
                            }
                        case .thinkingEnd(let thinking, let durationMs):
                            liveThinking = thinking
                            closeNewsThinkingSteps(durationMs)
                        case .toolStart(let id, let name, let label, let detail, let startedAtMs):
                            closeNewsThinkingSteps(nil)
                            self.streamingChatStatusLabel = detail.map { "\(label)：\($0)" } ?? label
                            let step = BeautifulAgentThinkingStep(
                                id: id,
                                label: label,
                                chip: detail ?? name,
                                status: "running",
                                kind: "tool",
                                startedAtMs: startedAtMs
                            )
                            if let i = liveSteps.firstIndex(where: { $0.id == id }) {
                                liveSteps[i] = step
                            } else {
                                liveSteps.append(step)
                            }
                        case .toolUpdate(let id, let preview):
                            if let i = liveSteps.firstIndex(where: { $0.id == id }) {
                                liveSteps[i].detail = Array(preview.components(separatedBy: .newlines).filter { !$0.isEmpty }.prefix(4))
                            }
                        case .toolEnd(let id, _, let isError, let durationMs, let preview):
                            if let i = liveSteps.firstIndex(where: { $0.id == id }) {
                                liveSteps[i].status = isError ? "error" : "done"
                                if let durationMs {
                                    liveSteps[i].durationMs = durationMs
                                } else if let s = liveSteps[i].startedAtMs {
                                    liveSteps[i].durationMs = max(1, Int(Date().timeIntervalSince1970 * 1000 - s))
                                }
                                if let preview {
                                    liveSteps[i].detail = Array(preview.components(separatedBy: .newlines).filter { !$0.isEmpty }.prefix(4))
                                }
                            }
                            self.streamingChatStatusLabel = AppLanguage.text("正在整理回复…", en: "Composing...")
                        case .textDelta(let text), .textEnd(let text):
                            closeNewsThinkingSteps(nil)
                            liveText = text
                        case .error(let msg):
                            self.chatErrorMessage = msg
                        case .settled:
                            break
                    }
                    self.emitChatStreamPatch(
                        itemID: itemID,
                        patch: BeautifulAgentStreamPatchPayload(
                            messageId: assistantID,
                            text: liveText,
                            thinking: liveThinking.isEmpty ? nil : liveThinking,
                            thinkingDurationMs: elapsedMs,
                            steps: liveSteps.isEmpty ? nil : liveSteps,
                            statusLabel: self.streamingChatStatusLabel.isEmpty ? nil : self.streamingChatStatusLabel
                        )
                    )
                }
                
                guard self.activeChatGeneration == generation else { return }
                await CotAgentCoordinator.shared.drainCommandQueueNow()
                guard self.activeChatGeneration == generation else { return }
                
                let finalText = result.text.isEmpty && result.aborted
                    ? AppLanguage.text("已停止生成。", en: "Generation stopped.")
                    : result.text
                let elapsed = turnClockStart.duration(to: .now)
                let latencyMs = max(1, Int(elapsed.components.seconds * 1000) + Int(elapsed.components.attoseconds / 1_000_000_000_000_000))
                let effective = resolvedConfig.wireConfiguration
                AnalyticsManager.shared.recordAIUsage(
                    feature: "newsChat",
                    model: effective.model,
                    provider: "Pi RPC · \(effective.endpoint.label)",
                    inputTokens: AINextTokenPredictor.estimateTokens(in: piSystemContext + "\n" + promptWithQuote),
                    outputTokens: AINextTokenPredictor.estimateTokens(in: finalText + "\n" + result.thinking),
                    latencyMs: latencyMs,
                    success: true
                )
                
                let toolChips = result.toolNames.map { PiToolDisplayMeta.label(for: $0) }
                let followUps = Self.newsFollowUpSuggestions(for: item, toolNames: result.toolNames)
                self.updateAssistantMessage(
                    id: assistantID,
                    itemID: itemID,
                    text: finalText,
                    thinking: result.thinking.isEmpty ? nil : result.thinking,
                    thinkingDurationMs: result.thinkingDurationMs,
                    steps: result.steps.isEmpty ? nil : result.steps,
                    toolChips: toolChips.isEmpty ? nil : toolChips,
                    followUps: followUps
                )
                if saveAsBrief, !finalText.isEmpty {
                    self.setAIBrief(finalText, for: itemID)
                }
                return
            } catch is CancellationError {
                guard self.activeChatGeneration == generation else { return }
                let partial = liveText.trimmingCharacters(in: .whitespacesAndNewlines)
                self.updateAssistantMessage(
                    id: assistantID,
                    itemID: itemID,
                    text: partial.isEmpty ? AppLanguage.text("已停止生成。", en: "Stopped.") : partial,
                    thinking: liveThinking.isEmpty ? nil : liveThinking,
                    steps: liveSteps.isEmpty ? nil : liveSteps
                )
                return
            } catch {
                guard self.activeChatGeneration == generation, !Task.isCancelled else { return }
                // Fall through cleanly to direct SSE
            }
        }
        
        guard self.activeChatGeneration == generation, !Task.isCancelled else { return }
        
        // 2. Fallback path: direct SSE streaming into BeautifulAgentWebView
        let systemContext = """
        你是一位视野敏锐、说人话的科技与资讯分析助手。请紧扣下面这篇资讯原文回答用户的点评、总结和追问。
        \(effort.styleDirective)
        要求：使用标准 Markdown 排版（善用标题、加粗、列表、引用、代码块或表格），直接给干货与犀利观点，方便用户阅读与复制分享，不要废话客套。

        标题：\(item.title)
        分类：\(item.resolvedCategory.label)\(sourceNote.isEmpty ? "" : " · \(sourceNote)")
        链接：\(item.urlString)
        \(bodyContext.isEmpty ? "" : "正文内容：\n\(bodyContext)")
        """
        
        var wireMessages: [AIMessage] = [.system(systemContext)]
        for turn in priorHistory {
            let cleanText = turn.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleanText.isEmpty else { continue }
            wireMessages.append(turn.role == .user ? .user(cleanText) : AIMessage(role: .assistant, text: cleanText))
        }
        wireMessages.append(.user(promptWithQuote))
        
        var lastEmitUptime: TimeInterval = 0
        var latestPartial = ""
        do {
            let output = try await AIService.shared.chat(
                wireMessages,
                configuration: resolvedConfig,
                analyticsFeature: "newsChat"
            ) { [weak self] partial in
                guard let self, self.activeChatGeneration == generation else { return }
                latestPartial = partial
                let now = ProcessInfo.processInfo.systemUptime
                guard now - lastEmitUptime >= 0.03 else { return }
                lastEmitUptime = now
                self.emitChatStreamPatch(
                    itemID: itemID,
                    patch: BeautifulAgentStreamPatchPayload(
                        messageId: assistantID,
                        text: partial,
                        thinking: nil,
                        thinkingDurationMs: max(0, Int(Date().timeIntervalSince(startedAt) * 1000)),
                        steps: nil,
                        statusLabel: nil
                    )
                )
            }
            guard self.activeChatGeneration == generation else { return }
            let finalClean = output.trimmingCharacters(in: .whitespacesAndNewlines)
            self.updateAssistantMessage(
                id: assistantID,
                itemID: itemID,
                text: finalClean,
                followUps: Self.newsFollowUpSuggestions(for: item, toolNames: [])
            )
            if saveAsBrief, !finalClean.isEmpty {
                self.setAIBrief(finalClean, for: itemID)
            }
        } catch is CancellationError {
            guard self.activeChatGeneration == generation else { return }
            let partial = latestPartial.trimmingCharacters(in: .whitespacesAndNewlines)
            if !partial.isEmpty {
                self.updateAssistantMessage(id: assistantID, itemID: itemID, text: partial)
            }
        } catch {
            guard self.activeChatGeneration == generation else { return }
            self.chatErrorMessage = error.localizedDescription
            self.updateAssistantMessage(
                id: assistantID,
                itemID: itemID,
                text: error.localizedDescription,
                isError: true
            )
        }
    }
    
    
    private static func newsFollowUpSuggestions(for item: AIHotNewsItem, toolNames: [String]) -> [String] {
        var result: [String] = []
        if !toolNames.contains("lookup_stock_quote") {
            result.append(AppLanguage.text("查一下相关公司最新股价与市场反应", en: "Check related stock quotes"))
        }
        result.append(AppLanguage.text("反面视角：这件事有哪些被忽视的风险？", en: "What are the counter-arguments & risks?"))
        result.append(AppLanguage.text("整理成结构化 Markdown 笔记打开", en: "Save as structured Markdown note"))
        return Array(result.prefix(3))
    }
    
    
    private func updateAssistantMessage(
        id: String,
        itemID: String,
        text: String,
        thinking: String? = nil,
        thinkingDurationMs: Int? = nil,
        steps: [BeautifulAgentThinkingStep]? = nil,
        toolChips: [String]? = nil,
        followUps: [String]? = nil,
        isError: Bool = false
    ) {
        guard var list = self.chatHistories[itemID],
              let idx = list.lastIndex(where: { $0.id == id })
        else { return }
        list[idx].text = text
        if let thinking { list[idx].thinking = thinking }
        if let thinkingDurationMs { list[idx].thinkingDurationMs = thinkingDurationMs }
        if let steps { list[idx].steps = steps }
        if let toolChips { list[idx].toolChips = toolChips }
        if let followUps { list[idx].followUps = followUps }
        list[idx].isError = isError
        self.chatHistories[itemID] = list
        
        if !isError, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let itemTitle = self.items.first(where: { $0.id == itemID })?.title ?? ""
            self.database.appendAIConversationLog(AIConversationLogRecord(
                id: "news:\(id)",
                channel: "news",
                sessionID: itemID,
                workspaceName: itemTitle,
                botID: AIBotID.readingCompanion.rawValue,
                role: "assistant",
                content: text,
                createdAt: Date(),
                memoryExtracted: false
            ))
            if self.database === CotLocalDatabase.shared && !CotLocalDatabase.isRunningUnitTests {
                CotMemoryExtractionAgent.shared.scheduleExtractionIfNeeded(reason: "news_turn")
            }
        }
    }
    
    
    private func loadInteractiveState() {
        let rawReads = self.database.string(forKey: CotLocalDatabase.ConfigKey.newsReadIDsJSON)
        if !rawReads.isEmpty, let data = rawReads.data(using: .utf8), let ids = try? JSONDecoder().decode([String].self, from: data) {
            self.readIDs = Set(ids)
        } else if self.database === CotLocalDatabase.shared,
                  let legacy = UserDefaults.standard.array(forKey: Self.readIDsDefaultsKey) as? [String]
        {
            self.readIDs = Set(legacy)
            if let data = try? JSONEncoder().encode(legacy), let str = String(data: data, encoding: .utf8) {
                self.database.set(str, forKey: CotLocalDatabase.ConfigKey.newsReadIDsJSON)
            }
        }
        
        let rawNotes = self.database.string(forKey: CotLocalDatabase.ConfigKey.newsPersonalNotesJSON)
        if !rawNotes.isEmpty, let data = rawNotes.data(using: .utf8), let dict = try? JSONDecoder().decode([String: String].self, from: data) {
            self.personalNotes = dict
        } else if self.database === CotLocalDatabase.shared,
                  let legacy = UserDefaults.standard.dictionary(forKey: Self.notesDefaultsKey) as? [String: String]
        {
            self.personalNotes = legacy
            if let data = try? JSONEncoder().encode(legacy), let str = String(data: data, encoding: .utf8) {
                self.database.set(str, forKey: CotLocalDatabase.ConfigKey.newsPersonalNotesJSON)
            }
        }
        
        let rawBookmarks = self.database.string(forKey: CotLocalDatabase.ConfigKey.newsBookmarkedItemsJSON)
        if !rawBookmarks.isEmpty, let data = rawBookmarks.data(using: .utf8), let items = try? JSONDecoder().decode([AIHotNewsItem].self, from: data) {
            self.savedBookmarkedItems = items
            self.bookmarkedIDs = Set(items.map(\.id))
        } else if self.database === CotLocalDatabase.shared,
                  let legacyData = UserDefaults.standard.data(forKey: Self.bookmarksDefaultsKey),
                  let items = try? JSONDecoder().decode([AIHotNewsItem].self, from: legacyData)
        {
            self.savedBookmarkedItems = items
            self.bookmarkedIDs = Set(items.map(\.id))
            self.saveBookmarkedItems()
        }
        
        let rawBriefs = self.database.string(forKey: CotLocalDatabase.ConfigKey.newsAIBriefsJSON)
        if !rawBriefs.isEmpty, let data = rawBriefs.data(using: .utf8), let dict = try? JSONDecoder().decode([String: String].self, from: data) {
            self.aiBriefs = dict
        }
        
        let rawHistory = self.database.string(forKey: CotLocalDatabase.ConfigKey.newsBrowsingHistoryJSON)
        if !rawHistory.isEmpty, let data = rawHistory.data(using: .utf8),
           let decoded = try? JSONDecoder().decode([NewsBrowsingHistoryItem].self, from: data)
        {
            self.browsingHistory = decoded
        }
    }
    
    
    private func saveBookmarkedItems() {
        if let encoded = try? JSONEncoder().encode(self.savedBookmarkedItems),
           let str = String(data: encoded, encoding: .utf8)
        {
            self.database.set(str, forKey: CotLocalDatabase.ConfigKey.newsBookmarkedItemsJSON)
        }
    }
    
    
    func cachedCoverImage(for item: AIHotNewsItem) -> NSImage? {
        self.coverImages[item.id]
    }
    
    
    func requestCoverLoad(for item: AIHotNewsItem) {
        guard self.coverImages[item.id] == nil,
              !self.checkedDiskCoverIDs.contains(item.id),
              !self.inFlightCoverIDs.contains(item.id),
              !self.resolvedNoCoverIDs.contains(item.id)
        else { return }
        
        self.checkedDiskCoverIDs.insert(item.id)
        let itemID = item.id
        let diskURL = self.diskCoverURL(for: item)
        let legacyURL = self.legacyDiskCoverURL(for: item)
        Task.detached(priority: .utility) { [weak self] in
            let diskImage = Self.downsampledThumbnail(fromFileAt: diskURL, maxPixelSize: Self.retinaCoverMaxPixelSize)
                ?? Self.downsampledThumbnail(fromFileAt: legacyURL, maxPixelSize: Self.retinaCoverMaxPixelSize)
            await MainActor.run {
                guard let self else { return }
                if let diskImage {
                    self.storeCoverImage(diskImage, for: itemID)
                } else {
                    self.triggerCoverLoadIfNeeded(for: item)
                }
            }
        }
    }
    
    
    func coverImage(for item: AIHotNewsItem) -> NSImage? {
        if let cached = self.coverImages[item.id] {
            return cached
        }
        self.requestCoverLoad(for: item)
        return nil
    }
    
    
    func prefetchCovers(for category: NewsFeedCategory? = nil, limit: Int = 12) {
        let pool = self.feedItems(for: category ?? self.selectedCategory)
        guard !pool.isEmpty else { return }
        for item in pool.prefix(max(1, limit)) {
            _ = self.coverImage(for: item)
        }
    }
    
    
    /// Proactively preloads cover thumbnails and OpenGraph article excerpts in bounded background batches
    /// so hovering pages and opening the NEWS reader renders instantaneously.
    func preloadFeedResources(limit: Int = 12) {
        guard Self.isNetworkPreloadAllowed else { return }
        let snapshotItems = Array(self.feedItems(for: self.selectedCategory).prefix(limit))
        guard !snapshotItems.isEmpty else { return }
        
        self.preloadTask?.cancel()
        self.preloadTask = Task(priority: .utility) { [weak self] in
            guard let self else { return }
            
            struct PreloadWork: Sendable {
                let item: AIHotNewsItem
                let index: Int
                let diskURL: URL
                let legacyDiskURL: URL
                let articleDiskURL: URL
                let needsCover: Bool
                let needsExcerpt: Bool
                let needsFullArticle: Bool
            }
            
            struct PreloadOutcome: Sendable {
                let id: String
                let coverImage: NSImage?
                let articleContent: NewsArticleContent?
                let resolvedCoverURL: String?
                let resolvedSummary: String?
                let attemptedDetail: Bool
                let failedCover: Bool
            }
            
            var pendingSummaries: [String: String] = [:]
            var pendingCoverURLs: [String: String] = [:]
            let batchSize = 4
            for batchStart in stride(from: 0, to: snapshotItems.count, by: batchSize) {
                if Task.isCancelled { return }
                let slice = Array(snapshotItems[batchStart..<min(snapshotItems.count, batchStart + batchSize)])
                
                var workQueue: [PreloadWork] = []
                for (offset, item) in slice.enumerated() {
                    let absIdx = batchStart + offset
                    let hasMemCover = (self.coverImages[item.id] != nil)
                    let needsCover = !hasMemCover && !self.inFlightCoverIDs.contains(item.id) && !self.resolvedNoCoverIDs.contains(item.id)
                    let existingSummaryLen = item.summary?.trimmingCharacters(in: .whitespacesAndNewlines).count ?? 0
                    let hasSubstantialMem = self.articleContents[item.id]?.isSubstantial == true
                    let hasSubstantialEmbedded = item.contentBlocks.map {
                        NewsArticleContent(blocks: $0, leadExcerpt: nil, author: nil, extractedAt: .now).isSubstantial
                    } ?? false
                    let hasFullBlocks = hasSubstantialMem || hasSubstantialEmbedded
                    let needsFullArticle = absIdx < 6 && !hasFullBlocks && !self.fetchedDetailIDs.contains(item.id)
                    let needsExcerpt = !needsFullArticle && (existingSummaryLen < 40) && !self.fetchedDetailIDs.contains(item.id)
                    if needsCover || needsExcerpt || needsFullArticle {
                        if needsCover {
                            self.inFlightCoverIDs.insert(item.id)
                            self.checkedDiskCoverIDs.insert(item.id)
                        }
                        if needsFullArticle { self.fetchedDetailIDs.insert(item.id) }
                        workQueue.append(PreloadWork(
                            item: item,
                            index: absIdx,
                            diskURL: self.diskCoverURL(for: item),
                            legacyDiskURL: self.legacyDiskCoverURL(for: item),
                            articleDiskURL: self.diskArticleURL(for: item),
                            needsCover: needsCover,
                            needsExcerpt: needsExcerpt,
                            needsFullArticle: needsFullArticle
                        ))
                    }
                }
                if workQueue.isEmpty { continue }
                
                let outcomes = await withTaskGroup(of: PreloadOutcome.self, returning: [PreloadOutcome].self) { group in
                    for work in workQueue {
                        group.addTask(priority: .utility) {
                            var loadedCover: NSImage?
                            var loadedArticle: NewsArticleContent?
                            var discoveredCoverURL = work.item.coverURLString
                            var discoveredSummary: String?
                            var failedCover = false
                            
                            if work.needsCover {
                                if FileManager.default.fileExists(atPath: work.diskURL.path),
                                   let diskImage = Self.downsampledThumbnail(fromFileAt: work.diskURL, maxPixelSize: Self.retinaCoverMaxPixelSize)
                                {
                                    loadedCover = diskImage
                                } else if FileManager.default.fileExists(atPath: work.legacyDiskURL.path),
                                          let diskImage = Self.downsampledThumbnail(fromFileAt: work.legacyDiskURL, maxPixelSize: Self.retinaCoverMaxPixelSize)
                                {
                                    loadedCover = diskImage
                                }
                            }
                            
                            if work.needsFullArticle,
                               let diskData = try? Data(contentsOf: work.articleDiskURL),
                               let cachedArt = try? JSONDecoder().decode(NewsArticleContent.self, from: diskData),
                               cachedArt.isSubstantial
                            {
                                loadedArticle = cachedArt
                            }
                            
                            let shouldFetchFullPage = (work.needsFullArticle && loadedArticle == nil)
                            let shouldFetchPageMeta = !shouldFetchFullPage && (work.needsExcerpt || (work.needsCover && loadedCover == nil && work.item.coverURL == nil))
                            
                            if shouldFetchFullPage, let pageURL = work.item.url {
                                let full = await Self.fetchFullArticleAndMeta(from: pageURL)
                                if let art = full.content, !art.blocks.isEmpty {
                                    loadedArticle = art
                                    if art.isSubstantial, let encoded = try? JSONEncoder().encode(art) {
                                        try? encoded.write(to: work.articleDiskURL, options: .atomic)
                                    }
                                }
                                if let desc = full.description, !desc.isEmpty {
                                    discoveredSummary = desc
                                }
                                if discoveredCoverURL == nil, let ogImg = full.imageURLString {
                                    discoveredCoverURL = ogImg
                                }
                            } else if shouldFetchPageMeta, let pageURL = work.item.url {
                                let meta = await Self.fetchOpenGraphMetadata(from: pageURL)
                                if let desc = meta.description, !desc.isEmpty {
                                    discoveredSummary = desc
                                }
                                if discoveredCoverURL == nil, let ogImg = meta.imageURLString {
                                    discoveredCoverURL = ogImg
                                }
                            }
                            
                            if work.needsCover && loadedCover == nil {
                                if let resolvedStr = Self.sanitizedHTTPURLString(discoveredCoverURL).map(Self.upgradeCoverURLResolution),
                                   let imgURL = URL(string: resolvedStr)
                                {
                                    var req = URLRequest(url: imgURL, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 8)
                                    req.setValue("image/webp,image/jpeg,image/png,image/*;q=0.8", forHTTPHeaderField: "Accept")
                                    req.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")
                                    if let (data, response) = try? await URLSession.shared.data(for: req),
                                       let http = response as? HTTPURLResponse,
                                       (200..<300).contains(http.statusCode),
                                       data.count > 256,
                                       let thumbnail = Self.downsampledThumbnail(from: data, maxPixelSize: Self.retinaCoverMaxPixelSize)
                                    {
                                        if let encoded = Self.encodeCrispCoverData(thumbnail) {
                                            try? encoded.write(to: work.diskURL, options: .atomic)
                                        }
                                        loadedCover = thumbnail
                                    } else {
                                        failedCover = true
                                    }
                                } else {
                                    failedCover = true
                                }
                            }
                            
                            return PreloadOutcome(
                                id: work.item.id,
                                coverImage: loadedCover,
                                articleContent: loadedArticle,
                                resolvedCoverURL: discoveredCoverURL,
                                resolvedSummary: discoveredSummary,
                                attemptedDetail: shouldFetchFullPage || shouldFetchPageMeta,
                                failedCover: failedCover
                            )
                        }
                    }
                    
                    var collected: [PreloadOutcome] = []
                    for await result in group {
                        collected.append(result)
                    }
                    return collected
                }
                
                if Task.isCancelled { return }
                
                for outcome in outcomes {
                    self.inFlightCoverIDs.remove(outcome.id)
                    if let thumb = outcome.coverImage {
                        self.storeCoverImage(thumb, for: outcome.id)
                    } else if outcome.failedCover {
                        self.resolvedNoCoverIDs.insert(outcome.id)
                    }
                    if let art = outcome.articleContent {
                        self.storeArticleContent(art, for: outcome.id)
                    }
                    if let sum = outcome.resolvedSummary, !sum.isEmpty {
                        pendingSummaries[outcome.id] = sum
                    }
                    if let coverStr = outcome.resolvedCoverURL, !coverStr.isEmpty {
                        pendingCoverURLs[outcome.id] = coverStr
                    }
                }
            }
            
            if !pendingSummaries.isEmpty || !pendingCoverURLs.isEmpty {
                var updated = self.items
                var didMutate = false
                for idx in updated.indices {
                    let id = updated[idx].id
                    if let sum = pendingSummaries[id], (updated[idx].summary ?? "").count < 40 {
                        updated[idx].summary = sum
                        didMutate = true
                    }
                    if let coverStr = pendingCoverURLs[id], updated[idx].coverURLString == nil {
                        updated[idx].coverURLString = coverStr
                        didMutate = true
                    }
                }
                if didMutate && !updated.isEmpty {
                    self.items = updated
                    self.saveCachedItems(updated)
                }
            }
        }
    }
    
    
    private nonisolated static var isNetworkPreloadAllowed: Bool {
        let env = ProcessInfo.processInfo.environment
        return NSClassFromString("XCTestCase") == nil
            && env["XCTestConfigurationFilePath"] == nil
            && env["XCTestBundlePath"] == nil
    }
    
    
    /// Douyin / Xiaohongshu-style feed refresh: immediately rotates fresh unseen items to the front for `category`
    /// and optionally fetches fresh network updates without snapping the rotated batch back to static stale items.
    func refreshFeed(
        for category: NewsFeedCategory? = nil,
        visibleCount: Int = 8,
        forceNetwork: Bool = true
    ) async {
        let target = category ?? self.selectedCategory
        self.rotateDisplayBatch(for: target, visibleCount: max(1, visibleCount))
        self.prefetchCovers(for: target, limit: max(12, visibleCount * 2))
        
        guard forceNetwork, Self.isNetworkPreloadAllowed else { return }
        guard !self.isLoading else { return }
        await self.performNetworkRefresh(force: true, preservingRotationFor: target, visibleCount: visibleCount)
    }
    
    
    /// Rotates unseen items in `category` to the front so every Refresh click visibly surfaces fresh cards
    /// across `.all`, `.ai`, `.finance`, and `.xSocial`.
    private func rotateDisplayBatch(for category: NewsFeedCategory, visibleCount: Int) {
        let current = self.feedItems(for: category)
        guard current.count > 1 else {
            self.feedRefreshToken &+= 1
            return
        }
        
        let currentHeadCount = min(visibleCount, max(1, current.count / 2))
        let previousHeadIDs = Array(current.prefix(currentHeadCount).map(\.id))
        var shown = self.shownBatchIDsByCategory[category] ?? []
        shown.formUnion(previousHeadIDs)
        
        var unseen = current.filter { !shown.contains($0.id) }
        if unseen.count < min(visibleCount, max(1, current.count - currentHeadCount)) {
            let excluded = Set(previousHeadIDs)
            shown.removeAll()
            unseen = current.filter { !excluded.contains($0.id) }
        }
        self.shownBatchIDsByCategory[category] = shown
        
        let seenSet = Set(unseen.map(\.id))
        let remainder = current.filter { !seenSet.contains($0.id) }
        
        // Unread items surface first within a lightly randomized batch for lively feed discovery
        var unreadUnseen = unseen.filter { !self.isRead($0) }
        var readUnseen = unseen.filter { self.isRead($0) }
        unreadUnseen.shuffle()
        readUnseen.shuffle()
        
        var rotated = unreadUnseen + readUnseen + remainder
        // Guarantee head change even on minimal pools where shuffle could land on the same prefix
        if rotated.prefix(currentHeadCount).map(\.id) == previousHeadIDs, rotated.count > 1 {
            let shift = min(currentHeadCount, rotated.count - 1)
            rotated = Array(rotated.dropFirst(shift)) + Array(rotated.prefix(shift))
        }
        
        self.categoryDisplayOrder[category] = rotated.map(\.id)
        self.feedRefreshToken &+= 1
    }
    
    
    /// Refreshes the unified mixed news stream, balancing AI, Finance, and X discussions across up to 120 items.
    func refreshIfNeeded(force: Bool = false) async {
        guard !self.isLoading else { return }
        if !force,
           let lastUpdatedAt = self.lastUpdatedAt,
           Date().timeIntervalSince(lastUpdatedAt) < Self.cacheTTL,
           !self.items.isEmpty
        {
            self.prefetchCovers(for: self.selectedCategory, limit: 12)
            self.preloadFeedResources(limit: 12)
            return
        }
        
        if force, !self.items.isEmpty {
            await self.refreshFeed(for: self.selectedCategory, visibleCount: 8, forceNetwork: true)
            return
        }
        
        await self.performNetworkRefresh(force: force, preservingRotationFor: nil, visibleCount: 8)
    }
    
    
    private func performNetworkRefresh(
        force: Bool,
        preservingRotationFor targetCategory: NewsFeedCategory?,
        visibleCount: Int
    ) async {
        guard !self.isLoading else { return }
        self.isLoading = true
        defer { self.isLoading = false }
        
        let sources = Self.feedSources
        var primaryPool: [AIHotNewsItem] = []
        var secondaryPool: [AIHotNewsItem] = []
        
        await withTaskGroup(of: (Bool, [AIHotNewsItem]).self) { group in
            for feed in sources {
                group.addTask {
                    let fetched = await Self.fetchSingleFeed(feed)
                    return (feed.isPrimaryAIHot, fetched)
                }
            }
            for await (isPrimary, batch) in group {
                if isPrimary {
                    primaryPool.append(contentsOf: batch)
                } else {
                    secondaryPool.append(contentsOf: batch)
                }
            }
        }
        
        guard !Task.isCancelled else { return }
        
        let rankedPrimary = primaryPool
            .filter { Self.isHighSignalPost($0) }
            .sorted { Self.signalRankScore($0, isPrimaryAIHot: true) > Self.signalRankScore($1, isPrimaryAIHot: true) }
        let rankedSecondary = secondaryPool
            .filter { Self.isHighSignalPost($0) }
            .sorted { Self.signalRankScore($0, isPrimaryAIHot: false) > Self.signalRankScore($1, isPrimaryAIHot: false) }
        
        let rankedFinance = rankedSecondary.filter { $0.resolvedCategory == .finance }
        let rankedX = rankedSecondary.filter { $0.resolvedCategory == .xSocial }
        let rankedOtherAI = rankedSecondary.filter { $0.resolvedCategory == .ai }
        
        var seenTitles = Set<String>()
        var seenIDs = Set<String>()
        var mergedItems: [AIHotNewsItem] = []
        var pIdx = 0
        var fIdx = 0
        var xIdx = 0
        var ai2Idx = 0
        
        func takeNext(from list: [AIHotNewsItem], cursor: inout Int) -> Bool {
            while cursor < list.count {
                let candidate = list[cursor]
                cursor += 1
                let titleKey = candidate.title.lowercased()
                if seenTitles.insert(titleKey).inserted && seenIDs.insert(candidate.id).inserted {
                    mergedItems.append(candidate)
                    return true
                }
            }
            return false
        }
        
        // Balanced interleaving so AI, Finance, and X all retain rich inventory (up to 120 items)
        let poolCap = 120
        while mergedItems.count < poolCap {
            var progressed = false
            if takeNext(from: rankedPrimary, cursor: &pIdx) { progressed = true }
            if mergedItems.count < poolCap, takeNext(from: rankedFinance, cursor: &fIdx) { progressed = true }
            if mergedItems.count < poolCap, takeNext(from: rankedX, cursor: &xIdx) { progressed = true }
            if mergedItems.count < poolCap, takeNext(from: rankedPrimary, cursor: &pIdx) { progressed = true }
            if mergedItems.count < poolCap, takeNext(from: rankedOtherAI, cursor: &ai2Idx) { progressed = true }
            if !progressed { break }
        }
        
        if !mergedItems.isEmpty {
            let priorIDs = Set(self.items.map(\.id))
            let existingByID = Dictionary(uniqueKeysWithValues: self.items.map { ($0.id, $0) })
            for idx in mergedItems.indices {
                if let prior = existingByID[mergedItems[idx].id] {
                    if mergedItems[idx].coverURLString == nil, let priorCover = prior.coverURLString {
                        mergedItems[idx].coverURLString = priorCover
                    }
                    let newSumLen = mergedItems[idx].summary?.trimmingCharacters(in: .whitespacesAndNewlines).count ?? 0
                    let priorSumLen = prior.summary?.trimmingCharacters(in: .whitespacesAndNewlines).count ?? 0
                    if newSumLen < 40 && priorSumLen > newSumLen {
                        mergedItems[idx].summary = prior.summary
                    }
                    if (mergedItems[idx].contentBlocks?.isEmpty ?? true), let priorBlocks = prior.contentBlocks, !priorBlocks.isEmpty {
                        mergedItems[idx].contentBlocks = priorBlocks
                    }
                }
            }
            
            let newItemIDs = mergedItems.filter { !priorIDs.contains($0.id) }.map(\.id)
            let sameOrderAndIDs = (self.items.map(\.id) == mergedItems.map(\.id))
            if force || !sameOrderAndIDs {
                self.items = mergedItems
            }
            if let targetCategory,
               var existingOrder = self.categoryDisplayOrder[targetCategory],
               !newItemIDs.isEmpty
            {
                let targetSet = Set(mergedItems.filter { targetCategory == .all || $0.resolvedCategory == targetCategory }.map(\.id))
                let relevantNew = newItemIDs.filter { targetSet.contains($0) && !existingOrder.contains($0) }
                if !relevantNew.isEmpty {
                    existingOrder.insert(contentsOf: relevantNew, at: 0)
                    self.categoryDisplayOrder[targetCategory] = existingOrder
                    self.feedRefreshToken &+= 1
                }
            }
            if force {
                self.resolvedNoCoverIDs.removeAll()
            }
            self.lastUpdatedAt = Date()
            self.loadFailed = false
            self.saveCachedItems(mergedItems)
            self.prefetchCovers(for: targetCategory ?? self.selectedCategory, limit: max(12, visibleCount * 2))
            self.preloadFeedResources(limit: 16)
        } else {
            self.loadFailed = self.items.isEmpty
        }
    }
    
    
    /// Filters out empty or ultra-low-signal headlines so the mixed stream stays information-dense.
    nonisolated static func isHighSignalPost(_ item: AIHotNewsItem) -> Bool {
        let title = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard title.count >= 8 else { return false }
        let lower = title.lowercased()
        let lowSignalPrefixes = ["subscribe", "sign up", "privacy policy", "terms of service", "sponsored:"]
        if lowSignalPrefixes.contains(where: { lower.hasPrefix($0) }) {
            return false
        }
        return true
    }
    
    
    /// Scores a post by information density, community heat, and recency.
    nonisolated static func signalRankScore(_ item: AIHotNewsItem, isPrimaryAIHot: Bool) -> Double {
        var score: Double = isPrimaryAIHot ? 40.0 : 12.0
        if let heat = item.heatScore, heat > 0 {
            score += min(120.0, Double(heat) * 0.85)
        }
        let len = item.title.count
        if (14...110).contains(len) {
            score += 18.0
        }
        if item.coverURLString != nil {
            score += 8.0
        }
        let lower = item.title.lowercased()
        let denseKeywords = [
            "release", "open source", "paper", "benchmark", "agent", "llm", "model", "gpt", "claude",
            "gemini", "deepseek", "qwen", "architecture", "inference", "training", "mcp", "swift",
            "开源", "发布", "架构", "论文", "模型", "推理", "基准", "深度", "财报", "美联储", "芯片",
        ]
        if denseKeywords.contains(where: { lower.contains($0) }) {
            score += 16.0
        }
        if let published = item.publishedAt {
            let ageHours = max(0, Date().timeIntervalSince(published) / 3600.0)
            score += max(0, 24.0 - ageHours * 0.5)
        }
        return score
    }
    
    
    private nonisolated static func fetchSingleFeed(_ feed: FeedSource) async -> [AIHotNewsItem] {
        guard let url = URL(string: feed.urlString) else { return [] }
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue(
            "application/json, text/markdown, application/rss+xml, application/atom+xml, application/xml, text/xml;q=0.9, */*;q=0.8",
            forHTTPHeaderField: "Accept"
        )
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard !Task.isCancelled,
                  let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode),
                  !data.isEmpty
            else { return [] }
            
            let parsed: [AIHotNewsItem] = switch feed.format {
                case .aihotJSON:
                    Self.parseJSON(data)
                case .aihotMarkdown:
                    String(data: data, encoding: .utf8).map { Self.parseAgentMarkdown($0) } ?? []
                case .aihotRSS, .rss:
                    Self.parseRSS(data)
                case .hnJSON:
                    Self.parseHackerNewsAlgoliaJSON(data, defaultSource: feed.label, category: feed.category)
            }
            
            let limit = feed.isPrimaryAIHot ? 32 : 24
            return parsed.prefix(limit).map { item in
                var tagged = item
                if tagged.category == nil {
                    tagged.category = feed.category
                }
                if tagged.source.isEmpty || tagged.source.lowercased().contains("google") {
                    tagged.source = feed.label
                }
                return tagged
            }
        } catch {
            return []
        }
    }
    
    
    /// Parses Hacker News Algolia search JSON (`{"hits": [...]}`) into `AIHotNewsItem` entries.
    nonisolated static func parseHackerNewsAlgoliaJSON(
        _ data: Data,
        defaultSource: String = "X / HN",
        category: NewsFeedCategory = .xSocial
    ) -> [AIHotNewsItem] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let hits = root["hits"] as? [[String: Any]]
        else { return [] }
        
        var results: [AIHotNewsItem] = []
        var seen = Set<String>()
        for (idx, hit) in hits.enumerated() {
            guard let rawTitle = (hit["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  rawTitle.count >= 4
            else { continue }
            
            let rawURL = (hit["url"] as? String)
                ?? (hit["objectID"] as? String).map { "https://news.ycombinator.com/item?id=\($0)" }
            guard let safeURL = Self.sanitizedHTTPURLString(rawURL) else { continue }
            let dedupe = rawTitle.lowercased()
            guard seen.insert(dedupe).inserted else { continue }
            
            let host = Self.hostLabel(from: safeURL)
            let isXLink = host.contains("x.com") || host.contains("twitter.com")
            let displaySource = isXLink ? "X (@\(Self.extractXHandle(from: safeURL) ?? "x.com"))" : (host.isEmpty ? defaultSource : host)
            let points = hit["points"] as? Int
            let itemID = (hit["objectID"] as? String) ?? "hn-\(idx)-\(dedupe.prefix(18))"
            let publishedAt = (hit["created_at"] as? String).flatMap { Self.parseDateString($0) }
            
            results.append(AIHotNewsItem(
                id: itemID,
                title: rawTitle,
                source: displaySource,
                urlString: safeURL,
                publishedAt: publishedAt,
                heatScore: points,
                tag: isXLink ? "X" : category.badgeLabel,
                coverURLString: nil,
                category: category
            ))
        }
        return results
    }
    
    
    private nonisolated static func extractXHandle(from urlString: String) -> String? {
        guard let url = URL(string: urlString) else { return nil }
        let segments = url.pathComponents.filter { $0 != "/" && !$0.isEmpty }
        guard let first = segments.first,
              !["i", "search", "explore", "home", "hashtag", "intent"].contains(first.lowercased())
        else { return nil }
        return first
    }
    
    
    nonisolated static func containsBlockedBrand(_ item: AIHotNewsItem) -> Bool {
        let lowerSource = item.source.lowercased()
        let lowerURL = item.urlString.lowercased()
        return lowerSource.contains("aihot") || lowerSource.contains("ai.hot")
            || lowerURL.contains("aihot.news") || lowerURL.contains("ai.hot")
    }
    
    
    nonisolated static func sanitizedDisplaySource(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()
        if lower.contains("aihot") || lower.contains("ai.hot") {
            return "News"
        }
        return trimmed
    }
    
    
    // MARK: Real Post Cover Thumbnail Loader (Retina High-DPI Cover + og:image Fallback)
    
    nonisolated static let retinaCoverMaxPixelSize: CGFloat = 1080
    
    
    private func diskCoverURL(for item: AIHotNewsItem) -> URL {
        let digest = SHA256.hash(data: Data((item.coverURLString ?? item.urlString).utf8))
        let hex = digest.prefix(12).map { String(format: "%02x", $0) }.joined()
        return self.coverCacheDirectory.appending(path: "\(hex)-hd2x.jpg")
    }
    
    
    private func legacyDiskCoverURL(for item: AIHotNewsItem) -> URL {
        let digest = SHA256.hash(data: Data((item.coverURLString ?? item.urlString).utf8))
        let hex = digest.prefix(12).map { String(format: "%02x", $0) }.joined()
        return self.coverCacheDirectory.appending(path: "\(hex)-hd2x.png")
    }
    
    
    private func triggerCoverLoadIfNeeded(for item: AIHotNewsItem) {
        guard Self.isNetworkPreloadAllowed,
              !self.inFlightCoverIDs.contains(item.id),
              !self.resolvedNoCoverIDs.contains(item.id)
        else { return }
        
        let itemID = item.id
        let directCoverURL = item.coverURL.flatMap { URL(string: Self.upgradeCoverURLResolution($0.absoluteString)) } ?? item.coverURL
        let pageURL = item.url
        let diskURL = self.diskCoverURL(for: item)
        self.inFlightCoverIDs.insert(itemID)
        
        Task.detached(priority: .utility) { [weak self] in
            var resolvedImageURL = directCoverURL
            if resolvedImageURL == nil, let pageURL {
                resolvedImageURL = await Self.fetchOpenGraphCoverURL(from: pageURL)
            }
            
            guard let imgURL = resolvedImageURL else {
                await MainActor.run {
                    _ = self?.inFlightCoverIDs.remove(itemID)
                    _ = self?.resolvedNoCoverIDs.insert(itemID)
                }
                return
            }
            
            var req = URLRequest(url: imgURL, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 8)
            req.setValue("image/webp,image/jpeg,image/png,image/*;q=0.8", forHTTPHeaderField: "Accept")
            req.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")
            
            guard let (data, response) = try? await URLSession.shared.data(for: req),
                  let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode),
                  data.count > 256,
                  let thumbnail = Self.downsampledThumbnail(from: data, maxPixelSize: Self.retinaCoverMaxPixelSize)
            else {
                await MainActor.run {
                    _ = self?.inFlightCoverIDs.remove(itemID)
                    _ = self?.resolvedNoCoverIDs.insert(itemID)
                }
                return
            }
            
            if let encoded = Self.encodeCrispCoverData(thumbnail) {
                try? encoded.write(to: diskURL, options: .atomic)
            }
            
            await MainActor.run {
                guard let self else { return }
                self.storeCoverImage(thumbnail, for: itemID)
                if let idx = self.items.firstIndex(where: { $0.id == itemID }),
                   self.items[idx].coverURLString == nil
                {
                    self.items[idx].coverURLString = imgURL.absoluteString
                }
                _ = self.inFlightCoverIDs.remove(itemID)
            }
        }
    }
    
    
    private nonisolated static func fetchFullArticleAndMeta(from pageURL: URL) async -> (content: NewsArticleContent?, imageURLString: String?, description: String?) {
        let host = pageURL.host?.lowercased() ?? ""
        
        // 1. Special-case X / Twitter status URLs via FxTwitter JSON API (handles JS-only X pages & Long-form Articles)
        if host.contains("x.com") || host.contains("twitter.com") {
            let segments = pageURL.pathComponents.filter { $0 != "/" && !$0.isEmpty }
            if segments.count >= 3, segments[1].lowercased() == "status" {
                let user = segments[0]
                let statusID = segments[2]
                if let fxResult = await Self.fetchFxTwitterArticle(user: user, statusID: statusID) {
                    return fxResult
                }
            }
        }
        
        // 2. Special-case Hacker News item URLs via HN Algolia API
        if host == "news.ycombinator.com",
           let comps = URLComponents(url: pageURL, resolvingAgainstBaseURL: false),
           let hnID = comps.queryItems?.first(where: { $0.name == "id" })?.value,
           !hnID.isEmpty,
           let hnResult = await Self.fetchHackerNewsItem(id: hnID)
        {
            return hnResult
        }
        
        // 3. Direct HTML fetch with realistic browser headers & higher 1.2 MB byte limit
        var ogImg: String?
        var ogDesc: String?
        var directContent: NewsArticleContent?
        
        var req = URLRequest(url: pageURL, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 9)
        req.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
        req.setValue("zh-CN,zh;q=0.9,en;q=0.8", forHTTPHeaderField: "Accept-Language")
        req.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36",
            forHTTPHeaderField: "User-Agent"
        )
        
        if let (data, response) = try? await URLSession.shared.data(for: req),
           let http = response as? HTTPURLResponse,
           (200..<300).contains(http.statusCode),
           !data.isEmpty
        {
            let cappedData = data.prefix(1_200_000)
            if let html = String(data: cappedData, encoding: .utf8) ?? String(data: cappedData, encoding: .isoLatin1) {
                let headSnippet = String(html.prefix(48_000))
                ogImg = Self.extractOpenGraphImageURL(from: headSnippet, pageURL: pageURL)
                ogDesc = Self.extractOpenGraphDescription(from: headSnippet)
                let extracted = NewsArticleExtractor.extractFromWebPageHTML(html)
                if !extracted.blocks.isEmpty {
                    directContent = NewsArticleContent(
                        blocks: extracted.blocks,
                        leadExcerpt: ogDesc,
                        author: extracted.author,
                        extractedAt: Date()
                    )
                }
            }
        }
        
        if let directContent, directContent.isSubstantial {
            return (directContent, ogImg, ogDesc)
        }
        
        // 4. Automatic Jina Reader fallback for JS-rendered SPAs, Substack/Medium/anti-bot gates, or short scrapes
        if let jinaBlocks = await Self.fetchViaJinaReader(pageURL: pageURL) {
            let jinaContent = NewsArticleContent(
                blocks: jinaBlocks,
                leadExcerpt: ogDesc,
                author: directContent?.author,
                extractedAt: Date()
            )
            let directLen = directContent?.plainTextLength ?? 0
            if jinaContent.plainTextLength > directLen {
                return (jinaContent, ogImg, ogDesc)
            }
        }
        
        return (directContent, ogImg, ogDesc)
    }
    
    
    private nonisolated static func fetchFxTwitterArticle(
        user: String,
        statusID: String
    ) async -> (content: NewsArticleContent?, imageURLString: String?, description: String?)? {
        guard let apiURL = URL(string: "https://api.fxtwitter.com/\(user)/status/\(statusID)") else { return nil }
        var req = URLRequest(url: apiURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 7)
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)", forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await URLSession.shared.data(for: req),
              let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tweet = root["tweet"] as? [String: Any]
        else { return nil }
        
        var blocks: [NewsArticleBlock] = []
        let authorObj = tweet["author"] as? [String: Any]
        let authorName = authorObj?["name"] as? String
        let tweetText = (tweet["text"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !tweetText.isEmpty {
            blocks.append(contentsOf: NewsArticleExtractor.extractBlocksFromPlainText(tweetText))
        }
        if let article = tweet["article"] as? [String: Any] {
            if let artTitle = (article["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !artTitle.isEmpty {
                blocks.append(.heading(level: 2, text: artTitle))
            }
            if let artContent = article["content"] as? [String: Any],
               let rawBlocks = artContent["blocks"] as? [[String: Any]]
            {
                for b in rawBlocks {
                    let t = (b["text"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    guard !t.isEmpty else { continue }
                    let kind = (b["type"] as? String)?.lowercased() ?? ""
                    if kind.contains("header") {
                        blocks.append(.heading(level: 3, text: t))
                    } else if kind.contains("blockquote") {
                        blocks.append(.quote(t))
                    } else {
                        blocks.append(.paragraph(t))
                    }
                }
            }
        }
        if let quote = tweet["quote"] as? [String: Any],
           let quoteText = (quote["text"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !quoteText.isEmpty
        {
            let qAuthor = (quote["author"] as? [String: Any])?["screen_name"] as? String ?? "quote"
            blocks.append(.quote("@\(qAuthor): \(quoteText)"))
        }
        
        var photoURL: String?
        if let media = tweet["media"] as? [String: Any],
           let photos = media["photos"] as? [[String: Any]],
           let firstURL = photos.first?["url"] as? String
        {
            photoURL = Self.sanitizedHTTPURLString(firstURL).map(Self.upgradeCoverURLResolution)
        }
        guard !blocks.isEmpty else { return nil }
        let summary = tweetText.isEmpty ? nil : String(tweetText.prefix(240))
        return (
            NewsArticleContent(blocks: blocks, leadExcerpt: summary, author: authorName, extractedAt: Date()),
            photoURL,
            summary
        )
    }
    
    
    private nonisolated static func fetchHackerNewsItem(
        id: String
    ) async -> (content: NewsArticleContent?, imageURLString: String?, description: String?)? {
        guard let apiURL = URL(string: "https://hn.algolia.com/api/v1/items/\(id)") else { return nil }
        var req = URLRequest(url: apiURL, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 7)
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        guard let (data, response) = try? await URLSession.shared.data(for: req),
              let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        
        var blocks: [NewsArticleBlock] = []
        let author = root["author"] as? String
        if let storyText = root["text"] as? String, !storyText.isEmpty {
            blocks.append(contentsOf: NewsArticleExtractor.extractBlocks(fromHTMLFragment: storyText))
        }
        if let children = root["children"] as? [[String: Any]] {
            var commentCount = 0
            var commentItems: [NewsArticleBlock] = []
            for child in children where commentCount < 8 {
                if (child["deleted"] as? Bool) == true || (child["dead"] as? Bool) == true { continue }
                guard let rawHTML = child["text"] as? String,
                      let clean = Self.stripHTMLToPlainText(rawHTML, maxLength: 600),
                      clean.count >= 24
                else { continue }
                let commenter = (child["author"] as? String) ?? "hn"
                commentItems.append(.quote("\(commenter): \(clean)"))
                commentCount += 1
            }
            if !commentItems.isEmpty {
                blocks.append(.heading(level: 3, text: AppLanguage.text("社区精选讨论", en: "Top Discussions")))
                blocks.append(contentsOf: commentItems)
            }
        }
        guard !blocks.isEmpty else { return nil }
        return (NewsArticleContent(blocks: blocks, leadExcerpt: nil, author: author, extractedAt: Date()), nil, nil)
    }
    
    
    private nonisolated static func fetchViaJinaReader(pageURL: URL) async -> [NewsArticleBlock]? {
        guard let readerURL = URL(string: "https://r.jina.ai/\(pageURL.absoluteString)") else { return nil }
        var req = URLRequest(url: readerURL, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 10)
        req.setValue("text/plain", forHTTPHeaderField: "Accept")
        req.setValue("markdown", forHTTPHeaderField: "X-Return-Format")
        req.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)", forHTTPHeaderField: "User-Agent")
        
        guard let (data, response) = try? await URLSession.shared.data(for: req),
              let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode),
              !data.isEmpty,
              let markdown = String(data: data.prefix(650_000), encoding: .utf8)
        else { return nil }
        
        let blocks = NewsArticleExtractor.extractBlocksFromMarkdown(markdown)
        return blocks.isEmpty ? nil : blocks
    }
    
    
    private nonisolated static func fetchOpenGraphMetadata(from pageURL: URL) async -> (imageURLString: String?, description: String?) {
        var req = URLRequest(url: pageURL, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 6)
        req.setValue("text/html,application/xhtml+xml;q=0.9", forHTTPHeaderField: "Accept")
        req.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")
        req.setValue("bytes=0-32767", forHTTPHeaderField: "Range")
        
        guard let (data, response) = try? await URLSession.shared.data(for: req),
              let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode),
              !data.isEmpty
        else { return (nil, nil) }
        
        let snippetData = data.prefix(36_000)
        guard let html = String(data: snippetData, encoding: .utf8) ?? String(data: snippetData, encoding: .isoLatin1) else {
            return (nil, nil)
        }
        return (
            Self.extractOpenGraphImageURL(from: html, pageURL: pageURL),
            Self.extractOpenGraphDescription(from: html)
        )
    }
    
    
    private nonisolated static func fetchOpenGraphCoverURL(from pageURL: URL) async -> URL? {
        let meta = await Self.fetchOpenGraphMetadata(from: pageURL)
        guard let urlString = meta.imageURLString else { return nil }
        return URL(string: urlString)
    }
    
    
    nonisolated static func downsampledThumbnail(from data: Data, maxPixelSize: CGFloat = AIHotNewsService.retinaCoverMaxPixelSize) -> NSImage? {
        let cfData = data as CFData
        guard let source = CGImageSourceCreateWithData(cfData, nil) else {
            return NSImage(data: data)
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return NSImage(data: data)
        }
        let scale: CGFloat = cg.width >= 360 ? 2.0 : 1.0
        return NSImage(cgImage: cg, size: NSSize(width: CGFloat(cg.width) / scale, height: CGFloat(cg.height) / scale))
    }
    
    
    nonisolated static func downsampledThumbnail(fromFileAt url: URL, maxPixelSize: CGFloat = AIHotNewsService.retinaCoverMaxPixelSize) -> NSImage? {
        guard FileManager.default.fileExists(atPath: url.path),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil)
        else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        let scale: CGFloat = cg.width >= 360 ? 2.0 : 1.0
        return NSImage(cgImage: cg, size: NSSize(width: CGFloat(cg.width) / scale, height: CGFloat(cg.height) / scale))
    }
    
    
    private nonisolated static func retinaAwareImage(fromFileAt url: URL) -> NSImage? {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe), !data.isEmpty else {
            return nil
        }
        let cfData = data as CFData
        guard let source = CGImageSourceCreateWithData(cfData, nil),
              let cg = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
        else {
            return NSImage(data: data)
        }
        let scale: CGFloat = cg.width >= 360 ? 2.0 : 1.0
        return NSImage(cgImage: cg, size: NSSize(width: CGFloat(cg.width) / scale, height: CGFloat(cg.height) / scale))
    }
    
    
    private nonisolated static func encodeCrispCoverData(_ image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff)
        else { return nil }
        return rep.representation(using: .jpeg, properties: [.compressionFactor: 0.84])
            ?? rep.representation(using: .png, properties: [:])
    }
    
    
    nonisolated static func upgradeCoverURLResolution(_ raw: String) -> String {
        var result = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !result.isEmpty else { return result }
        if result.contains("pbs.twimg.com") {
            result = result.replacingOccurrences(
                of: #"([?&]name=)(?:tiny|thumb|small|medium|240x240|360x360)\b"#,
                with: "$1large",
                options: .regularExpression
            )
        }
        result = result.replacingOccurrences(
            of: #"([?&](?:w|width)=)(?:1\d\d|2\d\d|3\d\d|4\d\d)\b"#,
            with: "$11080",
            options: .regularExpression
        )
        return result
    }
    
    
    // MARK: Persistence
    
    private func loadCachedItems() {
        
        let raw = self.database.string(forKey: CotLocalDatabase.ConfigKey.aiHotNewsCacheJSON, default: "")
        guard !raw.isEmpty, let data = raw.data(using: .utf8) else { return }
        if let decoded = try? JSONDecoder().decode([AIHotNewsItem].self, from: data) {
            let cleaned = decoded.filter { Self.isHighSignalPost($0) }
            if !cleaned.isEmpty {
                self.items = cleaned
            }
        }
    }
    
    
    private func saveCachedItems(_ items: [AIHotNewsItem]) {
        
        guard let encoded = try? JSONEncoder().encode(items),
              let string = String(data: encoded, encoding: .utf8)
        else { return }
        self.database.set(string, forKey: CotLocalDatabase.ConfigKey.aiHotNewsCacheJSON)
    }
    
    
    // MARK: Pure Parsers (Testable & Nonisolated)
    
    nonisolated static func parseJSON(_ data: Data) -> [AIHotNewsItem] {
        
        guard let root = try? JSONSerialization.jsonObject(with: data) else { return [] }
        let rawObjects = Self.extractItemDictionaries(from: root)
        guard !rawObjects.isEmpty else { return [] }
        
        var seenTitles = Set<String>()
        var seenIDs = Set<String>()
        var results: [AIHotNewsItem] = []
        
        for (index, dict) in rawObjects.enumerated() {
            guard let rawTitle = Self.firstString(in: dict, keys: ["title", "headline", "name", "subject"]),
                  !rawTitle.isEmpty
            else { continue }
            
            let title = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            let directURL = Self.firstString(in: dict, keys: ["url", "link", "source_url", "sourceUrl", "href", "canonical_url"])
            let fallbackSlug = Self.firstString(in: dict, keys: ["slug", "id"])
            let resolvedURL: String
            if let sanitized = Self.sanitizedHTTPURLString(directURL) {
                resolvedURL = sanitized
            } else if let fallbackSlug,
                      !fallbackSlug.isEmpty,
                      let encodedSlug = fallbackSlug.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
            {
                resolvedURL = "https://aihot.news/items/\(encodedSlug)"
            } else {
                resolvedURL = Self.portalURL.absoluteString
            }
            
            let explicitSource = Self.firstString(in: dict, keys: ["source", "source_name", "sourceName", "domain", "site", "publisher", "author"])
            let source = (explicitSource.flatMap { $0.isEmpty ? nil : $0 }) ?? Self.hostLabel(from: resolvedURL)
            let heatScore = Self.firstInt(in: dict, keys: ["heat", "heat_score", "heatScore", "score", "points", "upvotes", "hot"])
            let tag = Self.firstString(in: dict, keys: ["tag", "category", "topic", "cluster"])
            let publishedAt = Self.firstDate(in: dict, keys: ["published_at", "publishedAt", "created_at", "createdAt", "date", "timestamp", "time"])
            let baseID = Self.firstString(in: dict, keys: ["id", "guid", "slug"]) ?? "\(resolvedURL)#\(index)"
            let itemID = seenIDs.contains(baseID) ? "\(baseID)#\(index)" : baseID
            
            let dedupeKey = title.lowercased()
            guard seenTitles.insert(dedupeKey).inserted else { continue }
            seenIDs.insert(itemID)
            
            let rawCover = Self.extractCoverURLString(from: dict)
            let coverURLString = Self.sanitizedHTTPURLString(rawCover)
            let rawBody = Self.firstString(in: dict, keys: ["content_html", "body_html", "html", "content", "body", "markdown"])
            let embeddedBlocks = rawBody.map { NewsArticleExtractor.extractBlocks(fromHTMLFragment: $0) } ?? []
            let rawSummary = Self.firstString(in: dict, keys: ["summary", "description", "excerpt", "snippet", "text", "content", "abstract"])
            let summary = rawSummary.flatMap { Self.stripHTMLToPlainText($0, maxLength: 420) }
            
            results.append(AIHotNewsItem(
                id: itemID,
                title: title,
                source: source,
                urlString: resolvedURL,
                publishedAt: publishedAt,
                heatScore: heatScore,
                tag: tag,
                coverURLString: coverURLString,
                summary: summary,
                contentBlocks: embeddedBlocks.count >= 2 ? embeddedBlocks : nil
            ))
        }
        
        return results
    }
    
    
    nonisolated static func parseAgentMarkdown(_ text: String) -> [AIHotNewsItem] {
        
        let linkRegex = Self.agentLinkRegex
        let bareURLRegex = Self.agentBareURLRegex
        
        var seen = Set<String>()
        var results: [AIHotNewsItem] = []
        
        for (idx, rawLine) in text.components(separatedBy: .newlines).enumerated() {
            var line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }
            guard !line.hasPrefix("```"), !line.hasPrefix("---"), !line.hasPrefix("<!--") else { continue }
            
            // Skip plain frontmatter metadata keys like `updated_at: ...`
            if !line.contains("http://") && !line.contains("https://") {
                continue
            }
            
            // Strip bullet / numbering / heading prefix
            line = line.replacingOccurrences(
                of: #"^(?:[-*•]+|\d+[.)]|#+)\s+"#,
                with: "",
                options: .regularExpression
            )
            
            let nsLine = line as NSString
            let fullRange = NSRange(location: 0, length: nsLine.length)
            
            var title = ""
            var urlString = ""
            var trailingContext = ""
            
            if let linkMatch = linkRegex?.firstMatch(in: line, range: fullRange),
               linkMatch.numberOfRanges >= 3
            {
                title = nsLine.substring(with: linkMatch.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
                urlString = nsLine.substring(with: linkMatch.range(at: 2)).trimmingCharacters(in: .whitespacesAndNewlines)
                let after = NSMaxRange(linkMatch.range)
                if after < nsLine.length {
                    trailingContext = nsLine.substring(from: after)
                }
            } else if let urlMatch = bareURLRegex?.firstMatch(in: line, range: fullRange) {
                urlString = nsLine.substring(with: urlMatch.range)
                let withoutURL = nsLine.replacingCharacters(in: urlMatch.range, with: "")
                    .trimmingCharacters(in: CharacterSet(charactersIn: " -–—|:•·*"))
                title = withoutURL.isEmpty ? Self.hostLabel(from: urlString) : withoutURL
            } else {
                continue
            }
            
            title = title.replacingOccurrences(of: "**", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard title.count >= 4, let sanitizedURL = Self.sanitizedHTTPURLString(urlString) else { continue }
            urlString = sanitizedURL
            
            // Optional `· Source` or `(Source)` extraction from trailing text
            var source = ""
            var heatScore: Int?
            let cleanedTrailing = trailingContext
                .trimmingCharacters(in: CharacterSet(charactersIn: " -–—|:()[]·•"))
            if !cleanedTrailing.isEmpty {
                let tokens = cleanedTrailing
                    .components(separatedBy: CharacterSet(charactersIn: "|·•—"))
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                for token in tokens {
                    if let parsedHeat = Self.parseHeatToken(token) {
                        heatScore = heatScore ?? parsedHeat
                    } else if Self.isRelativeTimeToken(token) {
                        continue
                    } else if source.isEmpty, token.count <= 24 {
                        source = token
                    }
                }
            }
            if source.isEmpty {
                source = Self.hostLabel(from: urlString)
            }
            
            let dedupe = title.lowercased()
            guard seen.insert(dedupe).inserted else { continue }
            
            results.append(AIHotNewsItem(
                id: "md-\(idx)-\(dedupe.prefix(24))",
                title: title,
                source: source,
                urlString: urlString,
                publishedAt: nil,
                heatScore: heatScore,
                tag: nil
            ))
        }
        
        return results
    }
    
    
    nonisolated static func parseRSS(_ data: Data) -> [AIHotNewsItem] {
        
        let delegate = RSSFeedParserDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse() else { return [] }
        return delegate.items
    }
    
    
    // MARK: Private Parsing Helpers
    
    private nonisolated static func extractItemDictionaries(from root: Any) -> [[String: Any]] {
        
        if let array = root as? [[String: Any]] {
            return array
        }
        guard let dict = root as? [String: Any] else { return [] }
        
        for key in ["items", "stories", "news", "articles", "results", "entries", "data"] {
            if let list = dict[key] as? [[String: Any]], !list.isEmpty {
                return list
            }
        }
        if let nested = dict["data"] as? [String: Any] {
            for key in ["items", "stories", "news", "articles", "results", "entries"] {
                if let list = nested[key] as? [[String: Any]], !list.isEmpty {
                    return list
                }
            }
        }
        return []
    }
    
    
    private nonisolated static func firstString(in dict: [String: Any], keys: [String]) -> String? {
        
        for key in keys {
            if let str = dict[key] as? String {
                let trimmed = str.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return trimmed }
            } else if let num = dict[key] as? NSNumber, !(dict[key] is Bool) {
                return num.stringValue
            }
        }
        return nil
    }
    
    
    private nonisolated static func firstInt(in dict: [String: Any], keys: [String]) -> Int? {
        
        for key in keys {
            if let intVal = dict[key] as? Int {
                return intVal
            }
            if let doubleVal = dict[key] as? Double,
               doubleVal.isFinite,
               doubleVal >= Double(Int.min),
               doubleVal <= Double(Int.max)
            {
                return Int(doubleVal.rounded())
            }
            if let str = dict[key] as? String, let parsed = Int(str.trimmingCharacters(in: .whitespacesAndNewlines)) {
                return parsed
            }
        }
        return nil
    }
    
    
    private nonisolated static func firstDate(in dict: [String: Any], keys: [String]) -> Date? {
        
        for key in keys {
            if let ts = dict[key] as? Double {
                return ts > 1_000_000_000_000 ? Date(timeIntervalSince1970: ts / 1000.0) : Date(timeIntervalSince1970: ts)
            }
            if let tsInt = dict[key] as? Int {
                let ts = Double(tsInt)
                return ts > 1_000_000_000_000 ? Date(timeIntervalSince1970: ts / 1000.0) : Date(timeIntervalSince1970: ts)
            }
            if let str = dict[key] as? String, let date = Self.parseDateString(str) {
                return date
            }
        }
        return nil
    }
    
    
    fileprivate nonisolated static func parseDateString(_ raw: String) -> Date? {
        
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        
        Self.parseDateLock.lock()
        defer { Self.parseDateLock.unlock() }
        
        if let d = Self.isoFracFormatter.date(from: trimmed) { return d }
        if let d = Self.isoStdFormatter.date(from: trimmed) { return d }
        
        for formatter in Self.fallbackDateFormatters {
            if let d = formatter.date(from: trimmed) { return d }
        }
        return nil
    }
    
    
    /// Validates and normalizes remote news URLs to strictly `http` or `https` with a non-empty host.
    /// Relative paths (e.g. `/items/123`) are resolved against `portalURL`; unsafe schemes (`file:`, `smb:`, `javascript:`) return `nil`.
    nonisolated static func sanitizedHTTPURLString(_ raw: String?) -> String? {
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty
        else { return nil }
        let resolved: URL?
        if trimmed.hasPrefix("/") {
            resolved = URL(string: trimmed, relativeTo: Self.portalURL)?.absoluteURL
        } else {
            resolved = URL(string: trimmed)
        }
        guard let url = resolved,
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = url.host,
              !host.isEmpty
        else { return nil }
        return url.absoluteString
    }
    
    
    private nonisolated static func isRelativeTimeToken(_ token: String) -> Bool {
        let lower = token.lowercased().trimmingCharacters(in: .whitespaces)
        return lower.range(of: #"^\d+\s*(s|sec|secs|m|min|mins|h|hr|hrs|d|w|分钟前|小时前|天前)$"#, options: .regularExpression) != nil
    }
    
    
    private nonisolated static func parseHeatToken(_ token: String) -> Int? {
        guard !Self.isRelativeTimeToken(token) else { return nil }
        let lower = token.lowercased().trimmingCharacters(in: .whitespaces)
        guard lower.range(of: #"^(?:热度\s*)?\d{1,6}(?:\s*(?:°|🔥|pts?|pt|热度))?$"#, options: .regularExpression) != nil else {
            return nil
        }
        return Int(lower.filter(\.isNumber))
    }
    
    
    /// Extracts `og:image`, `twitter:image`, or `<link rel="image_src">` from a post's HTML head.
    nonisolated static func extractOpenGraphImageURL(from html: String, pageURL: URL) -> String? {
        let nsHTML = html as NSString
        let range = NSRange(location: 0, length: nsHTML.length)
        for regex in Self.ogImageRegexes {
            if let match = regex.firstMatch(in: html, range: range), match.numberOfRanges >= 2 {
                let raw = nsHTML.substring(with: match.range(at: 1))
                    .replacingOccurrences(of: "&amp;", with: "&")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if let resolved = URL(string: raw, relativeTo: pageURL)?.absoluteURL.absoluteString,
                   let sanitized = Self.sanitizedHTTPURLString(resolved)
                {
                    return Self.upgradeCoverURLResolution(sanitized)
                }
            }
        }
        return nil
    }
    
    
    private nonisolated static func extractCoverURLString(from dict: [String: Any]) -> String? {
        if let direct = Self.firstString(in: dict, keys: [
            "og_image", "ogImage", "cover", "cover_url", "coverUrl",
            "banner", "image", "image_url", "imageUrl", "pic",
            "thumbnail", "thumbnail_url", "thumbnailUrl",
        ]) {
            return Self.upgradeCoverURLResolution(direct)
        }
        for nestedKey in ["og", "meta", "media", "enclosure"] {
            if let sub = dict[nestedKey] as? [String: Any],
               let nested = Self.firstString(in: sub, keys: ["image", "cover", "url", "src", "thumbnail"])
            {
                return Self.upgradeCoverURLResolution(nested)
            }
        }
        if let images = dict["images"] as? [String], let first = images.first {
            return Self.upgradeCoverURLResolution(first)
        }
        return nil
    }
    
    
    fileprivate nonisolated static func firstHTMLImageURL(in html: String) -> String? {
        guard let regex = Self.firstHTMLImageRegex else { return nil }
        let ns = html as NSString
        if let match = regex.firstMatch(in: html, range: NSRange(location: 0, length: ns.length)),
           match.numberOfRanges >= 2
        {
            let raw = ns.substring(with: match.range(at: 1)).replacingOccurrences(of: "&amp;", with: "&")
            return Self.sanitizedHTTPURLString(raw)
        }
        return nil
    }
    
    
    nonisolated static func extractOpenGraphDescription(from html: String) -> String? {
        let nsHTML = html as NSString
        let range = NSRange(location: 0, length: nsHTML.length)
        for regex in Self.ogDescRegexes {
            if let match = regex.firstMatch(in: html, range: range), match.numberOfRanges >= 2 {
                let raw = nsHTML.substring(with: match.range(at: 1))
                if let clean = Self.stripHTMLToPlainText(raw, maxLength: 360) {
                    return clean
                }
            }
        }
        return nil
    }
    
    
    nonisolated static func stripHTMLToPlainText(_ raw: String, maxLength: Int = 360) -> String? {
        var text = raw.replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
        for (entity, replacement) in [
            ("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"),
            ("&quot;", "\""), ("&#39;", "'"), ("&apos;", "'"), ("&nbsp;", " "),
        ] {
            text = text.replacingOccurrences(of: entity, with: replacement)
        }
        text = text.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count >= 8 else { return nil }
        if text.count > maxLength {
            return String(text.prefix(maxLength - 1)) + "…"
        }
        return text
    }
    
    
    fileprivate nonisolated static func hostLabel(from urlString: String) -> String {
        
        guard let host = URL(string: urlString)?.host?.lowercased(), !host.isEmpty else {
            return "News"
        }
        let cleaned = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        return (cleaned.contains("aihot") || cleaned.contains("ai.hot")) ? "News" : cleaned
    }
}


private nonisolated final class RSSFeedParserDelegate: NSObject, XMLParserDelegate {
    
    var items: [AIHotNewsItem] = []
    
    private var inEntry = false
    private var elementStack: [String] = []
    private var currentTitle = ""
    private var currentLink = ""
    private var currentSource = ""
    private var currentDate = ""
    private var currentCategory = ""
    private var currentID = ""
    private var currentCover = ""
    private var currentSummary = ""
    private var currentRichBodyHTML = ""
    private var elementBuffer = ""
    private var seenTitles = Set<String>()
    private var seenIDs = Set<String>()
    
    
    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        let local = elementName.lowercased()
        self.elementStack.append(local)
        self.elementBuffer = ""
        
        if local == "item" || local == "entry" {
            self.inEntry = true
            self.currentTitle = ""
            self.currentLink = ""
            self.currentSource = ""
            self.currentDate = ""
            self.currentCategory = ""
            self.currentID = ""
            self.currentCover = ""
            self.currentSummary = ""
            self.currentRichBodyHTML = ""
        } else if self.inEntry {
            if self.isDirectEntryChild,
               local == "link",
               let href = attributeDict["href"],
               !href.isEmpty
            {
                let rel = attributeDict["rel"]?.lowercased()
                if rel == nil || rel == "alternate" || self.currentLink.isEmpty {
                    self.currentLink = href
                }
            } else if self.currentCover.isEmpty,
                      (local == "media:thumbnail" || local == "media:content" || local == "enclosure"),
                      let mediaURL = attributeDict["url"],
                      !mediaURL.isEmpty
            {
                let mime = attributeDict["type"]?.lowercased() ?? ""
                let medium = attributeDict["medium"]?.lowercased() ?? ""
                if local != "enclosure" || mime.hasPrefix("image/") || medium == "image" {
                    self.currentCover = mediaURL
                }
            }
        }
    }
    
    
    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard self.inEntry else { return }
        self.elementBuffer += string
    }
    
    
    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        guard self.inEntry, let decoded = String(data: CDATABlock, encoding: .utf8) else { return }
        self.elementBuffer += decoded
    }
    
    
    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        let local = elementName.lowercased()
        let text = self.elementBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
        let parent = self.elementStack.count >= 2 ? self.elementStack[self.elementStack.count - 2] : ""
        
        if self.inEntry && !text.isEmpty {
            let isEntryDirect = (parent == "item" || parent == "entry")
            if isEntryDirect {
                switch local {
                    case "title":
                        if self.currentTitle.isEmpty { self.currentTitle = text }
                    case "link":
                        if self.currentLink.isEmpty { self.currentLink = text }
                    case "source", "dc:creator", "author":
                        if self.currentSource.isEmpty { self.currentSource = text }
                    case "pubdate", "published", "updated", "dc:date":
                        if self.currentDate.isEmpty { self.currentDate = text }
                    case "category":
                        if self.currentCategory.isEmpty { self.currentCategory = text }
                    case "guid", "id":
                        if self.currentID.isEmpty { self.currentID = text }
                    case "description", "summary", "content", "content:encoded", "encoded":
                        if self.currentCover.isEmpty, let img = AIHotNewsService.firstHTMLImageURL(in: text) {
                            self.currentCover = AIHotNewsService.upgradeCoverURLResolution(img)
                        }
                        if text.count > self.currentRichBodyHTML.count {
                            self.currentRichBodyHTML = text
                        }
                        if let clean = AIHotNewsService.stripHTMLToPlainText(text, maxLength: 420),
                           clean.count > self.currentSummary.count
                        {
                            self.currentSummary = clean
                        }
                    default:
                        break
                }
            } else if (parent == "author" && local == "name") || (parent == "source" && local == "title") {
                if self.currentSource.isEmpty {
                    self.currentSource = text
                }
            }
        }
        
        if local == "item" || local == "entry", self.inEntry {
            self.inEntry = false
            let title = self.currentTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else {
                self.popStack()
                return
            }
            let dedupeTitle = title.lowercased()
            if self.seenTitles.insert(dedupeTitle).inserted {
                let resolvedURL = AIHotNewsService.sanitizedHTTPURLString(self.currentLink)
                    ?? AIHotNewsService.portalURL.absoluteString
                let source = self.currentSource.isEmpty
                    ? AIHotNewsService.hostLabel(from: resolvedURL)
                    : self.currentSource
                let publishedAt = AIHotNewsService.parseDateString(self.currentDate)
                let baseID = self.currentID.isEmpty ? "\(resolvedURL)#\(self.items.count)" : self.currentID
                let itemID = self.seenIDs.contains(baseID) ? "\(baseID)#\(self.items.count)" : baseID
                self.seenIDs.insert(itemID)
                let sanitizedCover = AIHotNewsService.sanitizedHTTPURLString(self.currentCover)
                    .map(AIHotNewsService.upgradeCoverURLResolution)
                let extractedBlocks = self.currentRichBodyHTML.count >= 160
                    ? NewsArticleExtractor.extractBlocks(fromHTMLFragment: self.currentRichBodyHTML)
                    : []
                
                self.items.append(AIHotNewsItem(
                    id: itemID,
                    title: title,
                    source: source,
                    urlString: resolvedURL,
                    publishedAt: publishedAt,
                    heatScore: nil,
                    tag: self.currentCategory.isEmpty ? nil : self.currentCategory,
                    coverURLString: sanitizedCover,
                    summary: self.currentSummary.isEmpty ? nil : self.currentSummary,
                    contentBlocks: extractedBlocks.count >= 2 ? extractedBlocks : nil
                ))
            }
        }
        self.popStack()
    }
    
    
    private var isDirectEntryChild: Bool {
        guard self.elementStack.count >= 2 else { return false }
        let parent = self.elementStack[self.elementStack.count - 2]
        return parent == "item" || parent == "entry"
    }
    
    
    private func popStack() {
        if !self.elementStack.isEmpty {
            self.elementStack.removeLast()
        }
        self.elementBuffer = ""
    }
}
