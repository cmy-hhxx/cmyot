//
//  OrganizeTopicSignature.swift
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

/// Pure, deterministic entity/series signature extracted from a document's title and heading outline.
///
/// Enables high-precision detection of same-project/same-series iterations (e.g. `"cot优化roadmap 7"`
/// and `"CoTEditor Roadmap 3"`), title-to-group coherence reconciliation, and smart manual merge ranking.
nonisolated struct OrganizeTopicSignature: Equatable, Sendable {
    
    let titleProjectStems: Set<String>
    let allProjectStems: Set<String>
    let titleDistinctiveTokens: Set<String>
    let artifactRole: String?
    let hasVersionNumber: Bool
    let explicitDateKey: String?
    let headings: [String]
    let primaryProjectStem: String
    
    
    // MARK: Static Lexicons & Compiled Patterns
    
    private static let asciiTokenRegex = try! NSRegularExpression(pattern: #"[A-Za-z][A-Za-z0-9_\-]{1,30}"#)
    private static let cjkTokenRegex = try! NSRegularExpression(pattern: #"[\p{Han}]{2,10}"#)
    private static let trailingVersionRegex = try! NSRegularExpression(
        pattern: #"(?:[\s_\-·#]+(?:v|ver|version|draft|rev|part|p|第)?\s*\d{1,3}(?:版|稿|期)?|(?:\(\d{1,3}\)|（\d{1,3}）)|(?<=[\p{Han}a-zA-Z])\s+\d{1,3})\s*$"#,
        options: [.caseInsensitive]
    )
    private static let explicitDateRegex = try! NSRegularExpression(
        pattern: #"(?:\b20\d{2}[-/\.]\d{1,2}[-/\.]\d{1,2}\b|\b\d{1,2}[-/]\d{1,2}\b|\d{1,2}月\d{1,2}[日号]|\bW\d{1,2}\b)"#,
        options: [.caseInsensitive]
    )
    private static let headingRegex = try! NSRegularExpression(
        pattern: #"(?m)^(?:#{1,4}\s+|(?:\d{1,2}[\.、\)]\s+)|[一二三四五六七八九十]+、\s*)(.+)$"#
    )
    
    private static let productTechSuffixes: [String] = [
        "editor", "studio", "center", "worker", "engine", "server", "client", "service",
        "system", "platform", "agent", "panel", "board", "viewer", "runner", "manager",
        "helper", "tool", "tools", "app", "bot", "cli", "web", "kit", "lab", "hub", "pro", "dev", "core", "ui",
    ]
    
    private static let genericTokens: Set<String> = [
        "the", "and", "for", "with", "from", "this", "that", "note", "notes", "doc", "docs",
        "draft", "copy", "new", "test", "tmp", "temp", "demo", "file", "text", "markdown", "plain",
        "v1", "v2", "v3", "v4", "v5", "ver", "version", "part", "final", "update", "updated", "fix",
        "优化", "方案", "设计", "文档", "记录", "测试", "项目", "数据", "统计", "会议", "纪要",
        "周报", "日报", "月报", "总结", "清单", "待办", "脚本", "配置", "架构", "需求", "计划",
        "任务", "处理", "更新", "检查", "结果", "说明", "背景", "目标", "问题", "排查", "分析",
        "整理", "内容", "核心", "阶段", "第一", "第二", "补充", "支持", "实现", "功能", "页面",
        "版本", "时间", "状态", "步骤", "建议", "注意", "如下", "需要", "副本", "草稿", "梳理",
        "合并", "归因", "看板", "评测", "路线", "路线图", "规划", "里程碑", "指南", "手册", "笔记",
    ]
    
    private static let artifactRoleKeywords: [(role: String, keywords: [String])] = [
        ("roadmap", ["roadmap", "路线图", "里程碑", "milestone", "迭代规划", "演进规划"]),
        ("prd", ["prd", "需求文档", "产品需求", "spec", "规格说明"]),
        ("design", ["architecture", "架构设计", "系统设计", "设计方案", "设计稿", "design"]),
        ("proposal", ["proposal", "rfc", "优化方案", "技术方案", "实施方案", "方案"]),
        ("debug", ["postmortem", "故障复盘", "排查", "排障", "debug", "bugfix", "oom"]),
        ("checklist", ["checklist", "todo", "待办清单", "任务清单", "清单", "排期"]),
        ("report", ["周报", "日报", "月报", "weekly", "report", "总结复盘"]),
        ("meeting", ["会议纪要", "周会", "例会", "评审会", "meeting", "sync"]),
    ]
    
    private static let artifactRoleBareTokens: Set<String> = [
        "roadmap", "milestone", "prd", "spec", "design", "architecture", "arch", "proposal",
        "rfc", "debug", "bug", "postmortem", "checklist", "todo", "weekly", "report", "meeting", "sync",
    ]
    
    
    // MARK: Extraction
    
    static func extract(title: String, content: String, isUntitled: Bool) -> OrganizeTopicSignature {
        let headings = Self.extractHeadings(from: content, maxCount: 8)
        // For untitled/whimsical docs (e.g. "啃瓜的小浣熊"), promote H1 heading as the effective topic title
        // so same-series detection and title-group coherence work on what's actually inside the doc.
        let effectiveTitle: String = {
            if !isUntitled {
                return Self.stripFileExtension(title)
            }
            if let firstHeading = headings.first, !firstHeading.isEmpty {
                return firstHeading
            }
            return DocumentCenterAgentOrganizer.deriveTitleFromExcerpt(String(content.prefix(320))) ?? ""
        }()
        
        let titleLower = effectiveTitle.lowercased()
        let titleRange = NSRange(effectiveTitle.startIndex..<effectiveTitle.endIndex, in: effectiveTitle)
        let hasVersion = !effectiveTitle.isEmpty && Self.trailingVersionRegex.firstMatch(in: effectiveTitle, range: titleRange) != nil
        
        let dateKey = Self.extractExplicitDate(in: effectiveTitle)
            ?? headings.first.flatMap { Self.extractExplicitDate(in: $0) }
        
        let titleProject = Self.extractProjectStems(from: effectiveTitle)
        var allProject = titleProject
        for h in headings.prefix(5) {
            allProject.formUnion(Self.extractProjectStems(from: h))
        }
        if allProject.isEmpty {
            let leadSnippet = String(content.prefix(480))
            allProject.formUnion(Self.extractProjectStems(from: leadSnippet))
        }
        
        let titleTokens = Self.extractDistinctiveTitleTokens(from: effectiveTitle)
        let role = Self.detectArtifactRole(in: titleLower)
            ?? headings.first.flatMap { Self.detectArtifactRole(in: $0.lowercased()) }
        
        let primaryStem = titleProject.sorted { lhs, rhs in
            if lhs.count != rhs.count { return lhs.count < rhs.count }
            return lhs < rhs
        }.first ?? allProject.sorted().first ?? ""
        
        return OrganizeTopicSignature(
            titleProjectStems: titleProject,
            allProjectStems: allProject,
            titleDistinctiveTokens: titleTokens,
            artifactRole: role,
            hasVersionNumber: hasVersion,
            explicitDateKey: dateKey,
            headings: headings,
            primaryProjectStem: primaryStem
        )
    }
    
    
    /// Discovers recurring concrete project/workstream group names directly from document contents
    /// (e.g. 3+ docs genuinely working on `CotEditor` -> `"CotEditor"`, `AIME` -> `"AIME"`)
    /// so even offline organization groups by what documents actually do inside instead of generic buckets.
    static func discoverWorkstreamGroupMap(
        for items: [OrganizeFunnelInput],
        healthyExistingGroups: [String]
    ) -> [String: String] {
        guard items.count >= 4 else { return [:] }
        var sigByID: [String: OrganizeTopicSignature] = [:]
        var stemDocIDs: [String: [String]] = [:]
        var displayByStem: [String: [String]] = [:]
        
        for item in items {
            let sig = Self.extract(title: item.title, content: item.content, isUntitled: item.isUntitled)
            sigByID[item.id] = sig
            let candidateStems = !sig.titleProjectStems.isEmpty ? sig.titleProjectStems : sig.allProjectStems
            let canonicalStem = Self.shortestCanonicalStem(in: candidateStems)
            guard !canonicalStem.isEmpty else { continue }
            stemDocIDs[canonicalStem, default: []].append(item.id)
            let sourceText = item.isUntitled ? (sig.headings.first ?? "") : item.title
            if let brand = Self.preferredDisplayName(forStem: canonicalStem, in: sourceText) {
                displayByStem[canonicalStem, default: []].append(brand)
            }
        }
        
        // Require a recurring project (>= 3 docs, or >= 2 docs when corpus >= 6) that isn't swallowing the entire workspace.
        let minClusterDocs = items.count >= 10 ? 3 : 2
        let maxClusterDocs = max(minClusterDocs, Int(Double(items.count) * 0.65))
        var result: [String: String] = [:]
        
        for (stem, docIDs) in stemDocIDs where docIDs.count >= minClusterDocs && docIDs.count <= maxClusterDocs {
            // Reuse a matching healthy existing user group name if one already exists (e.g. "cot优化")
            let matchingExisting = healthyExistingGroups.first { group in
                let groupStems = Self.extractProjectStems(from: group)
                return Self.sharesProjectStem(groupStems, [stem]) || group.lowercased().contains(stem)
            }
            let groupName: String = matchingExisting ?? {
                let candidates = displayByStem[stem] ?? []
                let bestBrand = candidates.max { lhs, rhs in
                    let lMixed = lhs.contains(where: \.isUppercase) && lhs.contains(where: \.isLowercase)
                    let rMixed = rhs.contains(where: \.isUppercase) && rhs.contains(where: \.isLowercase)
                    if lMixed != rMixed { return !lMixed && rMixed }
                    return lhs.count < rhs.count
                }
                return bestBrand ?? (stem.unicodeScalars.allSatisfy(\.isASCII) ? stem.uppercased() : stem)
            }()
            guard groupName.count >= 2, groupName.count <= 14 else { continue }
            for docID in docIDs {
                result[docID] = groupName
            }
        }
        return result
    }
    
    
    private static func shortestCanonicalStem(in stems: Set<String>) -> String {
        guard !stems.isEmpty else { return "" }
        // Prefer ASCII root brand stem (e.g. "cot" over "coteditor") so abbreviations unify automatically.
        let sorted = stems.sorted { lhs, rhs in
            if lhs.count != rhs.count { return lhs.count < rhs.count }
            return lhs < rhs
        }
        for candidate in sorted {
            if sorted.contains(where: { $0 != candidate && Self.isAbbreviatedProjectPair(candidate, $0) }) {
                return candidate
            }
        }
        return sorted.first ?? ""
    }
    
    
    private static func preferredDisplayName(forStem stem: String, in text: String) -> String? {
        guard !text.isEmpty else { return nil }
        let ns = text as NSString
        let range = NSRange(location: 0, length: ns.length)
        if stem.unicodeScalars.allSatisfy(\.isASCII) {
            var best: String?
            for match in Self.asciiTokenRegex.matches(in: text, range: range) {
                let token = ns.substring(with: match.range)
                let lower = token.lowercased()
                if lower == stem || Self.isAbbreviatedProjectPair(stem, lower) {
                    if let current = best {
                        if token.count > current.count { best = token }
                    } else {
                        best = token
                    }
                }
            }
            return best
        }
        return text.contains(stem) ? stem : nil
    }
    
    
    /// Checks whether two project stem sets represent the same concrete project/product
    /// (including exact match or product-suffix abbreviation such as `"cot"` ↔ `"coteditor"`).
    static func sharesProjectStem(_ lhs: Set<String>, _ rhs: Set<String>) -> Bool {
        if !lhs.isDisjoint(with: rhs) {
            return true
        }
        for a in lhs where a.count >= 3 && a.unicodeScalars.allSatisfy(\.isASCII) {
            for b in rhs where b.count >= 3 && b.unicodeScalars.allSatisfy(\.isASCII) {
                if Self.isAbbreviatedProjectPair(a, b) {
                    return true
                }
            }
        }
        return false
    }
    
    
    /// Returns true when `docSignature` clearly represents an iteration/sibling in the same living document series.
    static func isSameSeries(_ lhs: OrganizeTopicSignature, _ rhs: OrganizeTopicSignature) -> Bool {
        // Never collapse two entries anchored to different explicit calendar dates (e.g. 11-18 vs 11-25).
        if let dA = lhs.explicitDateKey, let dB = rhs.explicitDateKey, dA != dB {
            return false
        }
        guard Self.sharesProjectStem(lhs.titleProjectStems, rhs.titleProjectStems) else {
            return false
        }
        
        // Case 1: Same project stem + identical artifact role (e.g. "cot优化roadmap 7" & "CoTEditor Roadmap 3").
        if let roleA = lhs.artifactRole, let roleB = rhs.artifactRole, roleA == roleB {
            // Avoid merging two undated weekly reports/meetings unless explicitly version-numbered.
            if (roleA == "report" || roleA == "meeting") && !(lhs.hasVersionNumber || rhs.hasVersionNumber) {
                return false
            }
            return true
        }
        
        // Case 2: Both have version numbers AND share at least one additional distinctive title/role cue.
        if lhs.hasVersionNumber && rhs.hasVersionNumber {
            let sharedExtra = lhs.titleDistinctiveTokens.intersection(rhs.titleDistinctiveTokens)
            if sharedExtra.count >= 2 {
                return true
            }
        }
        
        return false
    }
    
    
    /// Scores how strongly a document's title matches a group name (used to fix misgrouped project docs).
    static func titleAffinityScore(for signature: OrganizeTopicSignature, groupName: String) -> Int {
        let trimmed = groupName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return 0 }
        let groupStems = Self.extractProjectStems(from: trimmed)
        let groupLower = trimmed.lowercased()
        var score = 0
        
        if !groupStems.isEmpty && Self.sharesProjectStem(signature.titleProjectStems, groupStems) {
            score += 20
        }
        for stem in signature.titleProjectStems where stem.count >= 3 {
            if groupLower.contains(stem) {
                score += 12
            }
        }
        if let role = signature.artifactRole,
           let groupRole = Self.detectArtifactRole(in: groupLower),
           role == groupRole
        {
            score += 6
        }
        return score
    }
    
    
    /// Synthesizes a clean, version-number-free title when merging a same-series cluster
    /// (e.g., `"cot优化roadmap 7"` + `"CoTEditor Roadmap 3"` -> `"CoTEditor Roadmap"` or clean stripped title).
    static func cleanSeriesTitle(primary: OrganizeFunnelInput, secondaries: [OrganizeFunnelInput]) -> String {
        let all = ([primary] + secondaries).filter { !$0.isUntitled }
        guard !all.isEmpty else { return primary.title }
        
        func strippedVersion(_ raw: String) -> String {
            let noExt = Self.stripFileExtension(raw)
            let range = NSRange(noExt.startIndex..<noExt.endIndex, in: noExt)
            let cleaned = Self.trailingVersionRegex
                .stringByReplacingMatches(in: noExt, range: range, withTemplate: "")
                .trimmingCharacters(in: CharacterSet(charactersIn: " \t-_·#"))
            return cleaned.count >= 2 ? cleaned : noExt
        }
        
        let candidates = all.map { strippedVersion($0.title) }
        // Prefer a clean canonical candidate with both uppercase/mixed branding or descriptive CJK over raw lowercase shorthand.
        let scored = candidates.sorted { lhs, rhs in
            let lHasBrand = lhs.contains(where: \.isUppercase) && lhs.contains(where: \.isLowercase)
            let rHasBrand = rhs.contains(where: \.isUppercase) && rhs.contains(where: \.isLowercase)
            if lHasBrand != rHasBrand { return lHasBrand }
            if lhs.count != rhs.count { return lhs.count > rhs.count }
            return lhs < rhs
        }
        return scored.first ?? strippedVersion(primary.title)
    }
    
    
    /// Builds a compact outline-rich digest (entity tags + full-document headings + clean opening)
    /// so fast-lane AI sees the real theme of 10K+ char documents instead of just paragraph 1.
    static func outlineDigest(title: String, content: String, isUntitled: Bool) -> String {
        let sig = Self.extract(title: title, content: content, isUntitled: isUntitled)
        var parts: [String] = []
        if !sig.titleProjectStems.isEmpty {
            let tags = sig.titleProjectStems.sorted().prefix(3).joined(separator: ",")
            parts.append("实体[\(tags)]")
        }
        if let role = sig.artifactRole {
            parts.append("类型[\(role)]")
        }
        if !sig.headings.isEmpty {
            let outline = sig.headings.prefix(5).map { String($0.prefix(24)) }.joined(separator: " / ")
            parts.append("纲要: \(outline)")
        }
        let opening = DocumentCenterState.cleanExcerpt(from: content, maxLength: 170)
        if !opening.isEmpty {
            parts.append("摘要: \(opening)")
        }
        let joined = parts.joined(separator: " | ")
        return String(joined.prefix(380))
    }
    
    
    /// Ranks potential manual merge targets for `source` in descending semantic/series affinity order.
    static func rankedMergeCandidates(
        for source: OrganizeFunnelInput,
        in candidates: [OrganizeFunnelInput],
        limit: Int = 10
    ) -> [(item: OrganizeFunnelInput, score: Int, badge: String)] {
        let srcSig = Self.extract(title: source.title, content: source.content, isUntitled: source.isUntitled)
        let srcTerms = Set(StarMapRelationEngine.extractKeyTerms(title: source.isUntitled ? "" : source.title, content: source.content).map { $0.lowercased() })
        
        var scored: [(item: OrganizeFunnelInput, score: Int, badge: String)] = []
        for cand in candidates where cand.id != source.id {
            let candSig = Self.extract(title: cand.title, content: cand.content, isUntitled: cand.isUntitled)
            var score = 0
            var badge = cand.groupNameFallback
            
            if Self.isSameSeries(srcSig, candSig) {
                score += 120
                badge = "同系列"
            } else if Self.sharesProjectStem(srcSig.titleProjectStems, candSig.titleProjectStems) {
                score += 75
                badge = "同项目"
            } else if Self.sharesProjectStem(srcSig.allProjectStems, candSig.allProjectStems) {
                score += 40
                badge = "强相关"
            }
            
            if !source.currentGroup.isEmpty && source.currentGroup == cand.currentGroup {
                score += 22
            }
            
            let candTerms = Set(StarMapRelationEngine.extractKeyTerms(title: cand.isUntitled ? "" : cand.title, content: cand.content).map { $0.lowercased() })
            let sharedCount = srcTerms.intersection(candTerms).count
            score += min(36, sharedCount * 6)
            
            scored.append((cand, score, badge))
        }
        
        scored.sort { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            return lhs.item.updatedAt > rhs.item.updatedAt
        }
        return Array(scored.prefix(limit))
    }
    
    
    // MARK: Private Helpers
    
    private static func stripFileExtension(_ title: String) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if let dot = trimmed.lastIndex(of: "."), trimmed.distance(from: dot, to: trimmed.endIndex) <= 6 {
            return String(trimmed[..<dot])
        }
        return trimmed
    }
    
    
    private static func extractHeadings(from content: String, maxCount: Int) -> [String] {
        guard !content.isEmpty else { return [] }
        // Sample beginning, middle, and tail for long documents so full outline is visible in O(1) time.
        let sample: String
        if content.count <= 8_000 {
            sample = content
        } else {
            let head = String(content.prefix(3_000))
            let midStart = content.index(content.startIndex, offsetBy: content.count / 2)
            let midEnd = content.index(midStart, offsetBy: min(2_500, content.distance(from: midStart, to: content.endIndex)))
            let tail = String(content.suffix(2_500))
            sample = head + "\n" + String(content[midStart..<midEnd]) + "\n" + tail
        }
        let ns = sample as NSString
        var results: [String] = []
        var seen = Set<String>()
        for match in Self.headingRegex.matches(in: sample, range: NSRange(location: 0, length: ns.length)) {
            guard match.numberOfRanges >= 2 else { continue }
            let raw = ns.substring(with: match.range(at: 1))
                .replacingOccurrences(of: "**", with: "")
                .replacingOccurrences(of: "`", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard raw.count >= 2, raw.count <= 60 else { continue }
            let key = raw.lowercased()
            if seen.insert(key).inserted {
                results.append(raw)
                if results.count >= maxCount { break }
            }
        }
        return results
    }
    
    
    private static func extractExplicitDate(in text: String) -> String? {
        guard !text.isEmpty else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = Self.explicitDateRegex.firstMatch(in: text, range: range) else { return nil }
        return (text as NSString).substring(with: match.range).lowercased()
    }
    
    
    private static func detectArtifactRole(in lowerText: String) -> String? {
        guard !lowerText.isEmpty else { return nil }
        for entry in Self.artifactRoleKeywords {
            if entry.keywords.contains(where: { lowerText.contains($0) }) {
                return entry.role
            }
        }
        return nil
    }
    
    
    private static func extractProjectStems(from text: String) -> Set<String> {
        guard !text.isEmpty else { return [] }
        let ns = text as NSString
        let fullRange = NSRange(location: 0, length: ns.length)
        var stems = Set<String>()
        
        // 1. ASCII brand/project tokens + camelCase & known-product-suffix root stems (e.g. CoTEditor -> coteditor + cot)
        for match in Self.asciiTokenRegex.matches(in: text, range: fullRange) {
            let raw = ns.substring(with: match.range).trimmingCharacters(in: CharacterSet(charactersIn: "_-"))
            let lower = raw.lowercased()
            guard lower.count >= 2 else { continue }
            if !Self.genericTokens.contains(lower) && !Self.artifactRoleBareTokens.contains(lower) && lower.count >= 3 {
                stems.insert(lower)
            }
            for sub in Self.splitProductAndCamelStems(raw) {
                if sub.count >= 3 && !Self.genericTokens.contains(sub) && !Self.artifactRoleBareTokens.contains(sub) {
                    stems.insert(sub)
                }
            }
        }
        
        // 2. Distinctive CJK project nouns (excluding generic document words)
        for match in Self.cjkTokenRegex.matches(in: text, range: fullRange) {
            let span = ns.substring(with: match.range)
            if span.count >= 2 && span.count <= 6 && !Self.genericTokens.contains(span) {
                // Skip spans purely composed of generic 2-char words (e.g. "优化方案")
                if !Self.isPurelyGenericCJK(span) {
                    stems.insert(span)
                }
            }
        }
        
        return stems
    }
    
    
    private static func extractDistinctiveTitleTokens(from text: String) -> Set<String> {
        var tokens = Self.extractProjectStems(from: text)
        let lower = text.lowercased()
        if let role = Self.detectArtifactRole(in: lower) {
            tokens.insert(role)
        }
        return tokens
    }
    
    
    private static func splitProductAndCamelStems(_ raw: String) -> [String] {
        var results: [String] = []
        let lower = raw.lowercased()
        
        // Known product/tech suffix stripping (e.g. CoTEditor -> cot, AimeWorker -> aime)
        for suffix in Self.productTechSuffixes where lower.hasSuffix(suffix) {
            let prefixLen = lower.count - suffix.count
            if prefixLen >= 3 {
                let prefix = String(lower.prefix(prefixLen)).trimmingCharacters(in: CharacterSet(charactersIn: "_-"))
                if prefix.count >= 3 {
                    results.append(prefix)
                }
            }
        }
        
        // Split on delimiters (`_`, `-`)
        for part in lower.components(separatedBy: CharacterSet(charactersIn: "_-")) where part.count >= 3 {
            results.append(part)
        }
        
        // Split camelCase transitions (e.g. "CoTEditor" -> "CoT", "Editor"; "AimeEval" -> "Aime", "Eval")
        let chars = Array(raw)
        if chars.count >= 5 {
            var start = 0
            for idx in 1..<chars.count {
                let prev = chars[idx - 1]
                let cur = chars[idx]
                let next: Character? = (idx + 1 < chars.count) ? chars[idx + 1] : nil
                let lowerToUpper = prev.isLowercase && cur.isUppercase
                let acronymToWord = prev.isUppercase && cur.isUppercase && (next?.isLowercase == true)
                if lowerToUpper || acronymToWord {
                    let piece = String(chars[start..<idx]).lowercased()
                    if piece.count >= 3 { results.append(piece) }
                    start = idx
                }
            }
            let tail = String(chars[start...]).lowercased()
            if tail.count >= 3 { results.append(tail) }
        }
        return results
    }
    
    
    private static func isAbbreviatedProjectPair(_ a: String, _ b: String) -> Bool {
        let shorter = a.count <= b.count ? a : b
        let longer = a.count <= b.count ? b : a
        guard shorter.count >= 3, longer.count >= shorter.count + 2, longer.hasPrefix(shorter) else {
            return false
        }
        let remainder = String(longer.dropFirst(shorter.count))
        return Self.productTechSuffixes.contains(remainder)
    }
    
    
    private static func isPurelyGenericCJK(_ span: String) -> Bool {
        if Self.genericTokens.contains(span) { return true }
        let chars = Array(span)
        guard chars.count == 4 else { return false }
        let left = String(chars[0..<2])
        let right = String(chars[2..<4])
        return Self.genericTokens.contains(left) && Self.genericTokens.contains(right)
    }
}


private extension OrganizeFunnelInput {
    var groupNameFallback: String {
        self.currentGroup.isEmpty ? "未分组" : self.currentGroup
    }
}
