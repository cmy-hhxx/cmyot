//
//  OrganizeDocumentAnalyzer.swift
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

/// Pure deterministic content-substance analysis, multi-section AI dossier formatting,
/// and lossless factual-retention verification for Document Center one-click consolidation.
nonisolated struct DocumentSubstanceReport: Sendable, Equatable {
    let rawChars: Int
    let substantiveBodyChars: Int
    let substantiveLineCount: Int
    let headingCount: Int
    let nonEmptyLineCount: Int
    let hasCodeBlock: Bool
    let hasSubstantiveTable: Bool
    let hasURLOrPath: Bool
    let sawTitleEcho: Bool
    let hasEmptyTemplateMarker: Bool
    let sawEmptyTable: Bool
    let hollowReason: OrganizeJunkReason?
    
    /// True when the document has real, non-trivial substance that AI deletion must never discard.
    var isProtectedSubstantiveContent: Bool {
        if self.substantiveBodyChars >= 140 { return true }
        if self.hasCodeBlock && self.substantiveBodyChars >= 45 { return true }
        if self.hasSubstantiveTable && self.substantiveBodyChars >= 40 { return true }
        if self.substantiveLineCount >= 4 && self.substantiveBodyChars >= 75 { return true }
        return false
    }
    
    /// Compact telemetry tag shown to the holistic AI architect so it spots hollow stubs immediately.
    var telemetryTag: String {
        var flags: [String] = ["body=\(self.substantiveBodyChars)", "lines=\(self.substantiveLineCount)"]
        if self.headingCount > 0 { flags.append("h=\(self.headingCount)") }
        if self.hasCodeBlock { flags.append("code") }
        if self.hasSubstantiveTable { flags.append("table") }
        if self.hasURLOrPath { flags.append("link") }
        if self.substantiveBodyChars < 35 && !self.hasCodeBlock && !self.hasSubstantiveTable {
            flags.append("sparse")
        }
        return flags.joined(separator: ",")
    }
}


nonisolated enum OrganizeDocumentAnalyzer {
    
    // MARK: Static Compiled Patterns & Lexicons
    
    private static let nonWordPunctRegex = try! NSRegularExpression(pattern: #"[\s\p{P}\p{S}]+"#)
    private static let dateOnlyLineRegex = try! NSRegularExpression(
        pattern: #"^(?:20\d{2}[-/\.]\d{1,2}[-/\.]\d{1,2}|\d{1,2}[-/]\d{1,2}|\d{1,2}月\d{1,2}[日号]|周[一二三四五六日天]|星期[一二三四五六日天]|今天|昨天|明天|W\d{1,2})(?:\s+\d{1,2}:\d{2})?$"#,
        options: [.caseInsensitive]
    )
    private static let numberedSectionRegex = try! NSRegularExpression(
        pattern: #"^(?:[一二三四五六七八九十]+[、\.]|\d{1,2}[\.、\)])\s*(.+)$"#
    )
    private static let bulletPrefixRegex = try! NSRegularExpression(
        pattern: #"^(?:[-*+•]\s*(?:\[[ xX]?\]\s*)?|\d{1,2}[\.\)]\s+|>\s*)+"#
    )
    private static let tableSeparatorRegex = try! NSRegularExpression(
        pattern: #"^\|?[\s:\-]+\|[\s:\-\|]*$"#
    )
    private static let concreteNumberRegex = try! NSRegularExpression(
        pattern: #"(?:\b\d{1,3}(?:,\d{3})+\b|\b\d+(?:\.\d+)?(?:\s*(?:%|万|千|亿|GB|MB|KB|ms|s|px|pt|元|条|篇))\b|\b[a-zA-Z]\d{3,}\b)"#,
        options: [.caseInsensitive]
    )
    private static let concreteIdentifierRegex = try! NSRegularExpression(
        pattern: #"(?:https?://[^\s\)\]>]+|(?:/[A-Za-z0-9._\-]+){2,}|\b[A-Za-z][A-Za-z0-9]*(?:_[A-Za-z0-9]+)+\b|\b[A-Za-z][A-Za-z0-9\-]*\.(?:json|jsonl|py|swift|md|ts|tsx|sql|yaml|yml|sh|csv)\b)"#,
        options: [.caseInsensitive]
    )
    private static let metricOrTimeHintRegex = try! NSRegularExpression(
        pattern: #"\d+\s*(?:点|分|号|日|月|年|元|块|万|千|亿|%|GB|MB|KB|ms|px|个|条|次|盒|人|天|周)"#,
        options: [.caseInsensitive]
    )
    
    private static let placeholderLineExact: Set<String> = [
        "待补充", "待完善", "待定", "待填写", "待确认", "待更新", "待整理", "待开始", "待处理",
        "先占坑", "占坑", "占位", "占位符", "暂无", "暂无内容", "无", "无内容", "空白", "略",
        "如题", "未完待续", "待续", "记录一下", "先记一下", "记一下", "随便写", "随便写写",
        "测试", "测试一下", "测试内容", "测试文档", "新建文档", "未命名",
        "todo", "tbd", "wip", "na", "none", "null", "empty", "placeholder", "draft", "test", "testing", "tmp", "temp",
    ]
    
    private static let bareSectionStubLabels: Set<String> = [
        "背景", "目标", "现状", "问题", "方案", "设计", "架构", "需求", "范围", "计划", "排期",
        "进度", "进展", "卡点", "风险", "结论", "总结", "复盘", "待办", "议题", "会议", "纪要",
        "参会人", "时间", "地点", "备注", "参考", "附录", "概述", "简介", "步骤", "结果", "数据",
        "background", "goal", "goals", "overview", "summary", "plan", "todo", "notes", "agenda", "actionitems",
    ]
    
    private static let titleNounCues: [String] = [
        "方案", "设计", "文档", "规划", "计划", "总结", "复盘", "周报", "日报", "月报",
        "纪要", "清单", "待办", "笔记", "想法", "思路", "大纲", "框架", "架构", "需求",
        "指南", "手册", "报告", "分析", "调研", "梳理", "优化", "重构", "记录", "备忘",
        "roadmap", "prd", "spec", "plan", "notes", "todo", "draft", "design", "doc", "summary", "review",
    ]
    
    private static let codeLineMarkers: [String] = [
        "import ", "func ", "class ", "struct ", "enum ", "def ", "return ", "const ", "let ", "var ",
        "select ", "from ", "where ", "curl ", "git ", "docker ", "python ", "npm ", "brew ", "#!/",
    ]
    
    
    // MARK: 1. Deep Substance & Hollow-Document Analysis
    
    private struct SubstanceAccumulator {
        var substantiveBodyChars = 0
        var substantiveLineCount = 0
        var headingCount = 0
        var nonEmptyLineCount = 0
        var hasCodeBlock = false
        var hasSubstantiveTable = false
        var hasURLOrPath = false
        var sawTitleEcho = false
        var hasEmptyTemplateMarker = false
        var sawEmptyTable = false
        var inCodeFence = false
        var tableRowStreak = 0
        var firstSubstantiveLine: String?
    }
    
    
    /// Inspects what a document actually accomplishes inside, distinguishing real substance from
    /// title-only stubs, empty outlines/templates, placeholder-only drafts, and Markdown chrome.
    static func analyzeSubstance(
        title: String,
        content: String,
        filePath: String?,
        isUntitled: Bool
    ) -> DocumentSubstanceReport {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return DocumentSubstanceReport(
                rawChars: 0,
                substantiveBodyChars: 0,
                substantiveLineCount: 0,
                headingCount: 0,
                nonEmptyLineCount: 0,
                hasCodeBlock: false,
                hasSubstantiveTable: false,
                hasURLOrPath: false,
                sawTitleEcho: false,
                hasEmptyTemplateMarker: false,
                sawEmptyTable: false,
                hollowReason: .empty
            )
        }
        
        let normalizedTitle = isUntitled ? "" : Self.compactKey(Self.stripFileExtension(title))
        let rawLines = trimmed.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        var acc = SubstanceAccumulator()
        
        for rawLine in rawLines {
            Self.consumeLine(rawLine, normalizedTitle: normalizedTitle, into: &acc)
        }
        
        let hollowReason = Self.resolveHollowReason(filePath: filePath, acc: acc)
        return DocumentSubstanceReport(
            rawChars: trimmed.count,
            substantiveBodyChars: acc.substantiveBodyChars,
            substantiveLineCount: acc.substantiveLineCount,
            headingCount: acc.headingCount,
            nonEmptyLineCount: acc.nonEmptyLineCount,
            hasCodeBlock: acc.hasCodeBlock,
            hasSubstantiveTable: acc.hasSubstantiveTable,
            hasURLOrPath: acc.hasURLOrPath,
            sawTitleEcho: acc.sawTitleEcho,
            hasEmptyTemplateMarker: acc.hasEmptyTemplateMarker,
            sawEmptyTable: acc.sawEmptyTable,
            hollowReason: hollowReason
        )
    }
    
    
    private static func consumeLine(
        _ rawLine: String,
        normalizedTitle: String,
        into acc: inout SubstanceAccumulator
    ) {
        let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty else {
            acc.tableRowStreak = 0
            return
        }
        acc.nonEmptyLineCount += 1
        
        if line.hasPrefix("```") || line.hasPrefix("~~~") {
            acc.inCodeFence.toggle()
            acc.tableRowStreak = 0
            return
        }
        if acc.inCodeFence {
            let codeCompact = Self.compactKey(line)
            if !codeCompact.isEmpty {
                acc.hasCodeBlock = true
                acc.substantiveBodyChars += codeCompact.count
                acc.substantiveLineCount += 1
                if acc.firstSubstantiveLine == nil { acc.firstSubstantiveLine = line }
            }
            return
        }
        if Self.isHorizontalRule(line) {
            acc.tableRowStreak = 0
            return
        }
        if line.hasPrefix("|") && line.filter({ $0 == "|" }).count >= 2 {
            Self.consumeTableLine(line, into: &acc)
            return
        }
        acc.tableRowStreak = 0
        
        if Self.isATXHeading(line) {
            acc.headingCount += 1
            let headingText = line.drop(while: { $0 == "#" || $0 == " " || $0 == "\t" })
            if !normalizedTitle.isEmpty && Self.compactKey(String(headingText)) == normalizedTitle {
                acc.sawTitleEcho = true
            }
            return
        }
        
        let (strippedBullet, hadBulletChrome) = Self.stripBulletAndCheckbox(line)
        if hadBulletChrome && strippedBullet.isEmpty {
            acc.hasEmptyTemplateMarker = true
            return
        }
        let effectiveLine = hadBulletChrome ? strippedBullet : line
        let compact = Self.compactKey(effectiveLine)
        if compact.isEmpty {
            if hadBulletChrome { acc.hasEmptyTemplateMarker = true }
            return
        }
        if !normalizedTitle.isEmpty && compact == normalizedTitle {
            acc.sawTitleEcho = true
            return
        }
        if Self.placeholderLineExact.contains(compact) {
            acc.hasEmptyTemplateMarker = true
            return
        }
        if Self.matches(Self.dateOnlyLineRegex, in: effectiveLine) {
            return
        }
        if Self.isBareSectionLabelStub(effectiveLine) {
            acc.headingCount += 1
            acc.hasEmptyTemplateMarker = true
            return
        }
        
        let lower = effectiveLine.lowercased()
        if lower.contains("http://") || lower.contains("https://")
            || effectiveLine.contains("/Users/") || effectiveLine.contains("/mnt/")
            || effectiveLine.hasPrefix("~/") || effectiveLine.hasPrefix("./")
        {
            acc.hasURLOrPath = true
        }
        if Self.codeLineMarkers.contains(where: { lower.hasPrefix($0) || lower.contains(" \($0)") }) {
            acc.hasCodeBlock = true
        }
        acc.substantiveBodyChars += compact.count
        acc.substantiveLineCount += 1
        if acc.firstSubstantiveLine == nil { acc.firstSubstantiveLine = effectiveLine }
    }
    
    
    private static func consumeTableLine(_ line: String, into acc: inout SubstanceAccumulator) {
        if Self.matches(Self.tableSeparatorRegex, in: line) {
            acc.sawEmptyTable = true
            return
        }
        let cells = line
            .split(separator: "|", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { cell in
                let key = Self.compactKey(cell)
                return !key.isEmpty && !Self.placeholderLineExact.contains(key)
            }
        acc.tableRowStreak += 1
        if acc.tableRowStreak == 1 {
            acc.sawEmptyTable = true
        } else if !cells.isEmpty {
            acc.hasSubstantiveTable = true
            acc.substantiveBodyChars += cells.reduce(0) { $0 + $1.count }
            acc.substantiveLineCount += 1
            if acc.firstSubstantiveLine == nil { acc.firstSubstantiveLine = line }
        } else {
            acc.hasEmptyTemplateMarker = true
        }
    }
    
    
    private static func resolveHollowReason(
        filePath: String?,
        acc: SubstanceAccumulator
    ) -> OrganizeJunkReason? {
        guard filePath == nil else { return nil }
        if acc.substantiveBodyChars == 0 {
            if acc.headingCount >= 2 || acc.hasEmptyTemplateMarker || acc.sawEmptyTable {
                return .emptyTemplate
            }
            if acc.headingCount == 1 || acc.sawTitleEcho {
                return .titleOnly
            }
            return .empty
        }
        if acc.nonEmptyLineCount == 1,
           acc.substantiveLineCount == 1,
           !acc.hasCodeBlock,
           !acc.hasURLOrPath,
           !acc.hasSubstantiveTable,
           let single = acc.firstSubstantiveLine,
           Self.looksLikeBareSingleTitleLine(single)
        {
            return .titleOnly
        }
        return nil
    }
    
    
    // MARK: 2. Rich Multi-Section AI Dossier Builder
    
    /// Builds a high-signal multi-section dossier for the holistic AI architect so it genuinely sees
    /// what each document does inside (full text for short/medium docs, head+middle+tail + outline for long docs).
    static func buildAIDossier(
        for item: OrganizeFunnelInput,
        index: Int,
        totalInBatch: Int,
        bloatedGroups: Set<String>
    ) -> String {
        let report = Self.analyzeSubstance(
            title: item.title,
            content: item.content,
            filePath: item.filePath,
            isUntitled: item.isUntitled
        )
        let sig = OrganizeTopicSignature.extract(
            title: item.title,
            content: item.content,
            isUntitled: item.isUntitled
        )
        let bodyBudget: Int = switch totalInBatch {
            case ...20: 1_050
            case 21...38: 720
            default: 460
        }
        
        var metaParts: [String] = [
            "[\(index)] id=\"\(item.id)\"",
            "title=\"\(item.title)\"",
            "scratch=\(item.filePath == nil ? "true" : "false")",
            "untitled=\(item.isUntitled ? "true" : "false")",
            "stats=(\(report.telemetryTag))",
        ]
        if !item.currentGroup.isEmpty {
            let groupTag = bloatedGroups.contains(item.currentGroup) ? "\(item.currentGroup)[待重分]" : item.currentGroup
            metaParts.append("group=\"\(groupTag)\"")
        }
        if !sig.allProjectStems.isEmpty {
            metaParts.append("entities=[\(sig.allProjectStems.sorted().prefix(4).joined(separator: ","))]")
        }
        if !sig.headings.isEmpty {
            let outline = sig.headings.prefix(6).map { String($0.prefix(28)) }.joined(separator: " / ")
            metaParts.append("outline=\"\(outline)\"")
        }
        
        let sampledBody = Self.multiSectionSample(from: item.content, maxChars: bodyBudget)
        return "\(metaParts.joined(separator: " | "))\n  内容: \(sampledBody)"
    }
    
    
    /// Samples full text when short, or head (45%) + middle (28%) + tail (27%) when long, collapsing
    /// blank runs so the AI sees the actual work happening throughout the document.
    static func multiSectionSample(from content: String, maxChars: Int) -> String {
        let cleaned = content
            .replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ⏎ ")
        guard cleaned.count > maxChars else {
            return cleaned
        }
        let headLen = max(120, Int(Double(maxChars) * 0.45))
        let midLen = max(80, Int(Double(maxChars) * 0.28))
        let tailLen = max(80, maxChars - headLen - midLen)
        
        let head = String(cleaned.prefix(headLen))
        let midCenter = cleaned.count / 2
        let midStartOffset = max(headLen, midCenter - midLen / 2)
        let midStart = cleaned.index(cleaned.startIndex, offsetBy: min(midStartOffset, cleaned.count))
        let midEnd = cleaned.index(midStart, offsetBy: min(midLen, cleaned.distance(from: midStart, to: cleaned.endIndex)))
        let mid = String(cleaned[midStart..<midEnd])
        let tail = String(cleaned.suffix(tailLen))
        return "\(head) ... [中段] \(mid) ... [末段] \(tail)"
    }
    
    
    // MARK: 3. Lossless Factual-Retention Guardrail for AI Merge Synthesis
    
    /// Cleans AI wrapper chatter and verifies that an AI-synthesized merge preserves concrete facts
    /// (numbers, metrics, paths, URLs, technical identifiers, and code blocks) from the baseline merge.
    static func validateSynthesizedContent(
        _ rawSynthesized: String,
        localBaseline: String
    ) -> String? {
        let candidate = Self.stripAIWrapperChatter(rawSynthesized)
        let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 40 else { return nil }
        
        // Guard against over-aggressive summarization that drops real detail.
        if localBaseline.count >= 240 {
            let minAcceptable = max(100, Int(Double(localBaseline.count) * 0.36))
            guard trimmed.count >= minAcceptable else { return nil }
        }
        
        // Preserve fenced code blocks whenever baseline had code.
        if localBaseline.contains("```") && !trimmed.contains("```") {
            return nil
        }
        
        // Verify concrete factual anchors (numbers/metrics, paths, URLs, snake_case/filename tokens).
        let anchors = Self.extractFactualAnchors(from: localBaseline)
        if anchors.count >= 3 {
            let candidateLower = trimmed.lowercased()
            let retained = anchors.filter { candidateLower.contains($0) }.count
            let ratio = Double(retained) / Double(anchors.count)
            if ratio < 0.78 {
                return nil
            }
        }
        
        return trimmed
    }
    
    
    static func extractFactualAnchors(from text: String) -> [String] {
        let sample = String(text.prefix(12_000))
        let ns = sample as NSString
        let range = NSRange(location: 0, length: ns.length)
        var seen = Set<String>()
        var anchors: [String] = []
        
        for regex in [Self.concreteIdentifierRegex, Self.concreteNumberRegex] {
            for match in regex.matches(in: sample, range: range) {
                let raw = ns.substring(with: match.range)
                    .trimmingCharacters(in: CharacterSet(charactersIn: ".,;:()[]<>\"'"))
                    .lowercased()
                guard raw.count >= 3, seen.insert(raw).inserted else { continue }
                anchors.append(raw)
                if anchors.count >= 24 { return anchors }
            }
        }
        return anchors
    }
    
    
    // MARK: Private Helpers
    
    private static func stripAIWrapperChatter(_ raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // Strip leading conversational preamble line if present
        let chatterPrefixes = ["以下是合并", "已为您合并", "已将上述", "好的，", "下面是我整理", "合并后的文档"]
        let lines = text.components(separatedBy: "\n")
        if let first = lines.first?.trimmingCharacters(in: .whitespaces),
           first.count <= 45,
           chatterPrefixes.contains(where: { first.hasPrefix($0) })
        {
            text = lines.dropFirst().joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        }
        // Unwrap outer ```markdown ... ``` fence if model wrapped the entire document
        if text.hasPrefix("```") && text.hasSuffix("```") {
            let innerLines = text.components(separatedBy: "\n")
            if innerLines.count >= 3 {
                text = innerLines.dropFirst().dropLast().joined(separator: "\n")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return text
    }
    
    
    private static func isATXHeading(_ line: String) -> Bool {
        guard line.hasPrefix("#") else { return false }
        let hashes = line.prefix(while: { $0 == "#" })
        guard (1...6).contains(hashes.count) else { return false }
        let after = line.dropFirst(hashes.count)
        return after.isEmpty || after.first == " " || after.first == "\t"
    }
    
    
    private static func isHorizontalRule(_ line: String) -> Bool {
        let compact = line.filter { !$0.isWhitespace }
        guard compact.count >= 3 else { return false }
        let ruleChars = Set<Character>(["-", "*", "_", "=", "~"])
        return compact.allSatisfy { ruleChars.contains($0) }
    }
    
    
    private static func stripBulletAndCheckbox(_ line: String) -> (remainder: String, hadChrome: Bool) {
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        guard let match = Self.bulletPrefixRegex.firstMatch(in: line, range: range), match.range.length > 0 else {
            return (line, false)
        }
        let remainder = (line as NSString)
            .substring(from: match.range.length)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (remainder, true)
    }
    
    
    private static func isBareSectionLabelStub(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count <= 18 else { return false }
        
        // "背景：" / "目标:" with nothing after colon
        if trimmed.hasSuffix(":") || trimmed.hasSuffix("：") {
            let stem = Self.compactKey(String(trimmed.dropLast()))
            if stem.count <= 10 && Self.bareSectionStubLabels.contains(stem) {
                return true
            }
        }
        
        // "一、背景" / "1. 目标" with no body
        let range = NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)
        if let match = Self.numberedSectionRegex.firstMatch(in: trimmed, range: range), match.numberOfRanges >= 2 {
            let label = (trimmed as NSString).substring(with: match.range(at: 1))
            let stem = Self.compactKey(label)
            if stem.count <= 10 && Self.bareSectionStubLabels.contains(stem) {
                return true
            }
        }
        return false
    }
    
    
    private static func looksLikeBareSingleTitleLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2, trimmed.count <= 22 else { return false }
        
        // Keep real sentences, key-value pairs, lists, paths, or concrete times/quantities
        let sentenceOrDataPunct: Set<Character> = ["。", "！", "？", "；", "：", ":", "=", "→", "，", ",", "|", "/"]
        if trimmed.contains(where: { sentenceOrDataPunct.contains($0) }) { return false }
        if Self.matches(Self.metricOrTimeHintRegex, in: trimmed) { return false }
        
        let lower = trimmed.lowercased()
        return Self.titleNounCues.contains(where: { lower.contains($0) })
    }
    
    
    private static func stripFileExtension(_ title: String) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if let dot = trimmed.lastIndex(of: "."), trimmed.distance(from: dot, to: trimmed.endIndex) <= 6 {
            return String(trimmed[..<dot])
        }
        return trimmed
    }
    
    
    private static func compactKey(_ text: String) -> String {
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return Self.nonWordPunctRegex
            .stringByReplacingMatches(in: text, range: range, withTemplate: "")
            .lowercased()
    }
    
    
    private static func matches(_ regex: NSRegularExpression, in text: String) -> Bool {
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.firstMatch(in: text, range: range) != nil
    }
}
