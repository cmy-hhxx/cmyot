//
//  DocumentOrganizeFunnel.swift
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

// MARK: - Data Funnel Models

nonisolated struct OrganizeFunnelInput: Sendable, Equatable {
    let id: String
    let dbRecordID: String
    let title: String
    let filePath: String?
    let syntax: String
    let currentGroup: String
    let content: String
    let updatedAt: Date
    let isOpenNow: Bool
    let isUntitled: Bool
}


nonisolated enum OrganizeJunkReason: String, Sendable, Equatable {
    case empty
    case titleOnly
    case emptyTemplate
    case meaninglessTest
    case keyboardSmash
    case garbled
    case aiHollow
    
    var label: String {
        switch self {
            case .empty: "空白文档"
            case .titleOnly: "仅标题无正文"
            case .emptyTemplate: "空白模板"
            case .meaninglessTest: "无效测试"
            case .keyboardSmash: "乱敲文本"
            case .garbled: "乱码内容"
            case .aiHollow: "无实质内容"
        }
    }
}


nonisolated struct OrganizeJunkDecision: Sendable, Equatable {
    let item: OrganizeFunnelInput
    let reason: OrganizeJunkReason
    let detail: String?
    
    init(item: OrganizeFunnelInput, reason: OrganizeJunkReason, detail: String? = nil) {
        self.item = item
        self.reason = reason
        self.detail = detail
    }
    
    var displayReason: String {
        if let detail = self.detail?.trimmingCharacters(in: .whitespacesAndNewlines), !detail.isEmpty {
            return detail
        }
        return self.reason.label
    }
}


nonisolated struct OrganizeMergeCluster: Sendable, Equatable {
    let primary: OrganizeFunnelInput
    let duplicates: [OrganizeFunnelInput]
    let mergedContent: String
    let bestGroup: String
    let bestTitle: String
    let reason: String
}


nonisolated struct OrganizeFunnelStageResult: Sendable, Equatable {
    let junkToDelete: [OrganizeJunkDecision]
    let mergeClusters: [OrganizeMergeCluster]
    let survivors: [OrganizeFunnelInput]
    
    var deletedDuplicateCount: Int {
        self.mergeClusters.reduce(0) { $0 + $1.duplicates.count }
    }
}


nonisolated enum OrganizeFunnelProgress: Sendable, Equatable {
    case filteringJunk(total: Int)
    case mergingDuplicates(remaining: Int, junkDeleted: Int)
    case shardedOrganizing(completedBatches: Int, totalBatches: Int, survivorCount: Int)
    case synthesizingMerges(completed: Int, total: Int)
    case consolidating
    
    var statusText: String {
        switch self {
            case .filteringJunk(let total):
                "筛查无效文档 \(total) 篇"
            case .mergingDuplicates(let remaining, let junk):
                junk > 0 ? "已清 \(junk) 无效 · 深度分析 \(remaining) 篇" : "深度分析 \(remaining) 篇"
            case .shardedOrganizing(let done, let total, let survivorCount):
                total <= 1 ? "AI 深度整合 \(survivorCount) 篇" : "AI 整合 \(done)/\(total) 批"
            case .synthesizingMerges(let done, let total):
                "精炼合并 \(done)/\(total) 组"
            case .consolidating:
                "收敛整理星图"
        }
    }
}


nonisolated struct OrganizeFullPlan: Sendable, Equatable {
    let funnel: OrganizeFunnelStageResult
    let assignments: [DocumentCenterAgentOrganizer.Assignment]
    let batchCount: Int
    let usedAI: Bool
}


// MARK: - Pure Deterministic Data Funnel Engine

nonisolated enum DocumentOrganizeFunnel {
    
    static let defaultShardSize = 42
    static let defaultMaxConcurrency = 4
    
    private static let copySuffixRegex = try! NSRegularExpression(
        pattern: #"(?:\s*(?:\(\d+\)|（\d+）|[-_]\d+|\s+\d+|副本\s*\d*|copy\s*\d*))+(\.[a-z0-9]{1,6})?$"#,
        options: [.caseInsensitive]
    )
    private static let nonWordPunctRegex = try! NSRegularExpression(
        pattern: #"[\s\p{P}\p{S}]+"#
    )
    private static let multiBlankLinesRegex = try! NSRegularExpression(
        pattern: #"\n{3,}"#
    )
    
    private static let meaninglessExactBodies: Set<String> = [
        "test", "test1", "test2", "test3", "test123", "testing", "tested",
        "tmp", "temp", "demo", "sample", "example", "hello", "helloworld",
        "hi", "hey", "foo", "bar", "foobar", "baz", "abc", "abcd", "abcde", "abcdef",
        "123", "1234", "12345", "123456", "111", "222", "333", "000", "666",
        "aaa", "bbb", "ccc", "xxx", "yyy", "zzz", "zzz123",
        "asdf", "asdfg", "asdfgh", "asdfghjkl", "qwer", "qwert", "qwerty",
        "zxcv", "zxcvb", "zxcvbn", "loremipsum", "todo", "tbd", "wip", "na", "null", "none",
        "测试", "测试1", "测试2", "测试3", "测试一下", "测试文档", "测试用", "测试内容", "测试标题",
        "随便写", "随便写写", "试试", "试试看", "你好", "待补充", "新建文档", "未命名", "无内容", "空白", "占位",
    ]
    
    private static let keyboardRuns: [String] = [
        "asdf", "sdfg", "dfgh", "fghj", "ghjk", "hjkl",
        "qwer", "wert", "erty", "rtyu", "tyui", "yuio", "uiop",
        "zxcv", "xcvb", "cvbn", "vbnm",
        "fdsa", "gfds", "hgfd", "jhgf", "kjhg", "lkjh",
        "rewq", "trew", "ytre", "vcxz",
    ]
    
    private static let mojibakeMarkers: [String] = [
        "锟斤拷", "烫烫烫", "屯屯屯", "锘", "Ã©", "Ã¤", "Ã¶", "Ã¼", "Ã¡", "Ã¨", "Ã®",
        "â€™", "â€œ", "â€", "æœ", "çš", "ï»¿", "å›", "ä¸",
    ]
    
    private static let groupSynonymMap: [String: String] = [
        "代码": "代码开发",
        "编程": "代码开发",
        "编程开发": "代码开发",
        "程序代码": "代码开发",
        "源码": "代码开发",
        "工程开发": "代码开发",
        "开发文档": "技术笔记",
        "技术文档": "技术笔记",
        "开发笔记": "技术笔记",
        "学习笔记": "技术笔记",
        "知识笔记": "技术笔记",
        "技术总结": "技术笔记",
        "会议": "会议纪要",
        "会议记录": "会议纪要",
        "沟通纪要": "会议纪要",
        "讨论纪要": "会议纪要",
        "待办": "工作清单",
        "待办清单": "工作清单",
        "任务清单": "工作清单",
        "工作记录": "工作清单",
        "总结复盘": "工作清单",
        "复盘总结": "工作清单",
        "产品方案": "项目方案",
        "设计方案": "项目方案",
        "需求方案": "项目方案",
        "需求文档": "项目方案",
        "架构设计": "项目方案",
        "项目规划": "项目方案",
        "配置文件": "配置数据",
        "数据配置": "配置数据",
        "环境配置": "配置数据",
        "随笔": "日常记录",
        "杂记": "日常记录",
        "日常笔记": "日常记录",
        "个人记录": "日常记录",
        "灵感记录": "日常记录",
    ]
    
    
    // MARK: Stage 1 — Junk & Garbled Document Filter
    
    /// Classifies meaningless test documents, empty drafts, title-only stubs, empty outlines/templates,
    /// keyboard smashes, and garbled mojibake text.
    static func classifyJunk(
        title: String,
        content: String,
        filePath: String? = nil,
        isUntitled: Bool? = nil
    ) -> OrganizeJunkReason? {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return .empty
        }
        
        // Check garbled/mojibake first (even on longer documents).
        if Self.looksGarbled(trimmed) {
            return .garbled
        }
        
        // Strip pure markdown chrome (#, -, *, >, `, _, ~) to detect empty structural shells.
        let markdownStripped = trimmed.unicodeScalars.filter { scalar in
            !CharacterSet.whitespacesAndNewlines.contains(scalar)
                && !CharacterSet(charactersIn: "#*-•>`_~|=+").contains(scalar)
        }
        if markdownStripped.isEmpty {
            return .empty
        }
        
        // Deep substance analysis catches title-only stubs ("# 方案设计") and empty templates
        // even when headings/tables make raw character count > 120.
        let resolvedUntitled = isUntitled ?? DocumentCenterAgentOrganizer.isGenericUntitled(title, hasFilePath: filePath != nil)
        let substance = OrganizeDocumentAnalyzer.analyzeSubstance(
            title: title,
            content: trimmed,
            filePath: filePath,
            isUntitled: resolvedUntitled
        )
        if let hollowReason = substance.hollowReason {
            return hollowReason
        }
        
        // Never discard substantial real files/documents that passed the garbled & substance checks.
        if substance.substantiveBodyChars >= 120 || trimmed.count >= 120 {
            return nil
        }
        if filePath != nil, trimmed.count >= 48 {
            return nil
        }
        
        // Single-character or 2/3-char repeated spam (e.g. "aaaaaaaa", "11111111", "asdfasdfasdf").
        if Self.isRepeatedNoise(trimmed) {
            return .keyboardSmash
        }
        
        // Normalized body (lowercase, no whitespace/punctuation).
        let compact = Self.stripPunctuationAndSpace(trimmed).lowercased()
        if compact.isEmpty {
            return .empty
        }
        if Self.meaninglessExactBodies.contains(compact) {
            return .meaninglessTest
        }
        
        // Pure digits / timestamps / counters with no letters or CJK.
        if trimmed.count <= 48, compact.unicodeScalars.allSatisfy({ CharacterSet.decimalDigits.contains($0) }) {
            return .meaninglessTest
        }
        
        // Keyboard smash detection on short ASCII strings without CJK or URLs.
        if Self.looksLikeKeyboardSmash(trimmed) {
            return .keyboardSmash
        }
        
        // Generic/test title + ultra-short trivial test body.
        if Self.isTestTitle(title), trimmed.count <= 24 {
            let lower = trimmed.lowercased()
            let tokens = lower.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
            if !lower.contains("http"),
               !lower.contains("/"),
               tokens.count <= 2,
               tokens.allSatisfy({ Self.meaninglessExactBodies.contains($0) || $0.count <= 3 })
            {
                return .meaninglessTest
            }
        }
        
        return nil
    }
    
    
    private static func looksGarbled(_ text: String) -> Bool {
        let sample = String(text.prefix(2_400))
        let scalars = Array(sample.unicodeScalars)
        guard !scalars.isEmpty else { return false }
        
        var replacementCount = 0
        var controlOrPUACount = 0
        var latin1BrokenCount = 0
        var cjkCount = 0
        var asciiLetterCount = 0
        var symbolCount = 0
        var nonWhitespaceCount = 0
        
        for scalar in scalars {
            let v = scalar.value
            if CharacterSet.whitespacesAndNewlines.contains(scalar) {
                continue
            }
            nonWhitespaceCount += 1
            if v == 0xFFFD {
                replacementCount += 1
            } else if (v < 0x20) || v == 0x7F || (0x0080...0x009F).contains(v) || (0xE000...0xF8FF).contains(v) {
                controlOrPUACount += 1
            } else if (0x4E00...0x9FFF).contains(v) {
                cjkCount += 1
            } else if (0x41...0x5A).contains(v) || (0x61...0x7A).contains(v) {
                asciiLetterCount += 1
            } else if (0x00C0...0x00FF).contains(v) {
                latin1BrokenCount += 1
            } else if !(0x30...0x39).contains(v) {
                symbolCount += 1
            }
        }
        guard nonWhitespaceCount > 0 else { return false }
        
        let total = Double(nonWhitespaceCount)
        if replacementCount >= 3 || (replacementCount >= 2 && Double(replacementCount) / total >= 0.06) {
            return true
        }
        if controlOrPUACount >= 4 || (controlOrPUACount >= 2 && Double(controlOrPUACount) / total >= 0.05) {
            return true
        }
        
        var markerHits = 0
        for marker in Self.mojibakeMarkers {
            var start = sample.startIndex
            while let range = sample.range(of: marker, range: start..<sample.endIndex) {
                markerHits += 1
                start = range.upperBound
                if markerHits >= 4 { break }
            }
            if markerHits >= 4 { break }
        }
        if markerHits >= 2 && (Double(markerHits * 2) / total >= 0.12 || markerHits >= 4) {
            return true
        }
        
        // UTF-8 decoded as Latin-1 typically produces dense Ã/Â/æ/ç runs.
        if latin1BrokenCount >= 6, Double(latin1BrokenCount) / total >= 0.22 {
            return true
        }
        
        // Dense non-code symbol soup with zero CJK and almost no alphabetic words.
        if nonWhitespaceCount >= 12,
           cjkCount == 0,
           asciiLetterCount <= 2,
           Double(symbolCount) / total >= 0.72,
           !sample.contains("http"),
           !sample.contains("{")
        {
            return true
        }
        
        return false
    }
    
    
    private static func isRepeatedNoise(_ text: String) -> Bool {
        let nonWS = text.filter { !$0.isWhitespace && !$0.isNewline }
        guard nonWS.count >= 5, nonWS.count <= 240 else { return false }
        
        var counts: [Character: Int] = [:]
        for ch in nonWS {
            counts[ch, default: 0] += 1
        }
        if let top = counts.values.max(), Double(top) / Double(nonWS.count) >= 0.80 {
            return true
        }
        
        // Check 2-char to 4-char repeating cycles (e.g. "asdfasdfasdf", "12121212").
        let chars = Array(nonWS)
        for period in 2...4 where chars.count >= period * 3 {
            var matches = 0
            for idx in 0..<chars.count where chars[idx] == chars[idx % period] {
                matches += 1
            }
            if Double(matches) / Double(chars.count) >= 0.88 {
                let isPureASCII = nonWS.unicodeScalars.allSatisfy(\.isASCII)
                if isPureASCII || nonWS.count <= 24 {
                    return true
                }
            }
        }
        return false
    }
    
    
    private static func looksLikeKeyboardSmash(_ text: String) -> Bool {
        guard text.count <= 64 else { return false }
        if text.unicodeScalars.contains(where: { (0x4E00...0x9FFF).contains($0.value) }) {
            return false
        }
        let lower = text.lowercased()
        if lower.contains("http://") || lower.contains("https://") || lower.contains("/") || lower.contains("_") {
            return false
        }
        let letters = lower.filter { $0 >= "a" && $0 <= "z" }
        guard letters.count >= 5 else { return false }
        
        if Self.keyboardRuns.contains(where: { letters.contains($0) }) {
            let words = lower.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
            if words.count <= 3 {
                return true
            }
        }
        
        if letters.count >= 8 {
            let vowels = letters.filter { "aeiouy".contains($0) }.count
            let digitCount = lower.filter(\.isNumber).count
            // Consonant mash with almost no vowels (ignore hex/UUID-like tokens containing digits or dashes).
            if digitCount == 0 && !lower.contains("-") && Double(vowels) / Double(letters.count) < 0.08 {
                return true
            }
        }
        return false
    }
    
    
    private static func isTestTitle(_ title: String) -> Bool {
        let lower = title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if lower.isEmpty { return true }
        if GeneratedDocumentName.isGeneratedName(title) { return true }
        let markers = ["test", "tmp", "temp", "demo", "测试", "随便", "草稿", "untitled", "未命名", "新建文档"]
        return markers.contains(where: { lower == $0 || lower.hasPrefix($0) })
    }
    
    
    // MARK: Stage 2 — Duplicate & Near-Duplicate Merger
    
    /// Runs Stage 1 (junk deletion) and Stage 2 (exact + near-duplicate merging) locally in milliseconds.
    static func runLocalFunnel(items: [OrganizeFunnelInput]) -> OrganizeFunnelStageResult {
        var junkDecisions: [OrganizeJunkDecision] = []
        var cleanItems: [OrganizeFunnelInput] = []
        cleanItems.reserveCapacity(items.count)
        
        for item in items {
            if let reason = Self.classifyJunk(
                title: item.title,
                content: item.content,
                filePath: item.filePath,
                isUntitled: item.isUntitled
            ) {
                junkDecisions.append(OrganizeJunkDecision(item: item, reason: reason))
            } else {
                cleanItems.append(item)
            }
        }
        
        guard cleanItems.count > 1 else {
            return OrganizeFunnelStageResult(junkToDelete: junkDecisions, mergeClusters: [], survivors: cleanItems)
        }
        
        let clustered = Self.clusterDuplicateGroups(cleanItems)
        let (mergeClusters, survivors) = Self.materializeMergedSurvivors(
            cleanItems: cleanItems,
            groups: clustered.groups,
            reasons: clustered.reasons
        )
        return OrganizeFunnelStageResult(
            junkToDelete: junkDecisions,
            mergeClusters: mergeClusters,
            survivors: survivors
        )
    }
    
    
    private static func clusterDuplicateGroups(
        _ cleanItems: [OrganizeFunnelInput]
    ) -> (groups: [[Int]], reasons: [String]) {
        let n = cleanItems.count
        var parent = Array(0..<n)
        var mergeReasons: [Int: String] = [:]
        
        func find(_ x: Int) -> Int {
            var root = x
            while parent[root] != root { root = parent[root] }
            var curr = x
            while parent[curr] != root {
                let next = parent[curr]
                parent[curr] = root
                curr = next
            }
            return root
        }
        
        func unite(_ a: Int, _ b: Int, reason: String) {
            let ra = find(a)
            let rb = find(b)
            guard ra != rb else { return }
            parent[rb] = ra
            if mergeReasons[ra] == nil { mergeReasons[ra] = reason }
        }
        
        let normalizedBodies = cleanItems.map { Self.normalizeBody($0.content) }
        let normalizedTitles = cleanItems.map { Self.normalizeMeaningfulTitle($0.title, isUntitled: $0.isUntitled) }
        
        // Pass 2A: Exact normalized content duplicates (O(N))
        var firstIndexByBody: [String: Int] = [:]
        for idx in 0..<n {
            let body = normalizedBodies[idx]
            guard !body.isEmpty else { continue }
            if let first = firstIndexByBody[body] {
                unite(first, idx, reason: "内容完全重复")
            } else {
                firstIndexByBody[body] = idx
            }
        }
        
        // Pass 2B: Same normalized meaningful title (e.g. "周会纪要" & "周会纪要 副本")
        var indicesByTitle: [String: [Int]] = [:]
        for idx in 0..<n {
            guard let normTitle = normalizedTitles[idx] else { continue }
            indicesByTitle[normTitle, default: []].append(idx)
        }
        for (_, group) in indicesByTitle where group.count >= 2 {
            let anchor = group[0]
            for other in group.dropFirst() {
                unite(anchor, other, reason: "同名重复文档")
            }
        }
        
        // Pass 2C: Subset containment & 3-gram Jaccard near-duplicates on remaining distinct roots
        var rootIndices: [Int] = []
        var seenRoots = Set<Int>()
        for idx in 0..<n {
            let r = find(idx)
            if seenRoots.insert(r).inserted { rootIndices.append(r) }
        }
        Self.mergeNearDuplicateRoots(
            Array(rootIndices.prefix(240)),
            normalizedBodies: normalizedBodies,
            find: find,
            unite: unite
        )
        
        // Pass 2C+: Same-project / same-series iterative docs (e.g. "cot优化roadmap 7" + "CoTEditor Roadmap 3")
        var postNearRoots: [Int] = []
        var seenPostNear = Set<Int>()
        for idx in 0..<n {
            let r = find(idx)
            if seenPostNear.insert(r).inserted { postNearRoots.append(r) }
        }
        Self.mergeSameSeriesRoots(
            Array(postNearRoots.prefix(240)),
            cleanItems: cleanItems,
            find: find,
            unite: unite
        )
        
        // Pass 2D: Content-aware semantic merge for fragmented scratch notes on the exact same concrete topic.
        var postSeriesRoots: [Int] = []
        var seenPostSeries = Set<Int>()
        for idx in 0..<n {
            let r = find(idx)
            if seenPostSeries.insert(r).inserted { postSeriesRoots.append(r) }
        }
        Self.mergeSemanticSameTopicRoots(
            Array(postSeriesRoots.prefix(180)),
            cleanItems: cleanItems,
            find: find,
            unite: unite
        )
        
        var bucketsByRoot: [Int: [Int]] = [:]
        var rootOrder: [Int] = []
        for idx in 0..<n {
            let r = find(idx)
            if bucketsByRoot[r] == nil { rootOrder.append(r) }
            bucketsByRoot[r, default: []].append(idx)
        }
        let groups = rootOrder.compactMap { bucketsByRoot[$0] }
        let reasons = rootOrder.map { mergeReasons[$0] ?? "重复文档合并" }
        return (groups, reasons)
    }
    
    
    private static let genericTopicStopWords: Set<String> = [
        "优化", "方案", "设计", "文档", "记录", "测试", "项目", "数据", "统计", "会议",
        "纪要", "周报", "总结", "清单", "待办", "脚本", "配置", "架构", "需求", "计划",
        "任务", "处理", "更新", "检查", "结果", "说明", "背景", "目标", "问题", "排查",
        "分析", "整理", "内容", "核心", "阶段", "第一", "第二", "补充", "支持", "实现",
        "功能", "页面", "版本", "时间", "状态", "步骤", "建议", "注意", "如下", "需要",
    ]
    
    private static let maxSemanticClusterDocs = 6
    private static let maxSemanticClusterChars = 64_000
    private static let maxSingleDocSemanticChars = 32_000
    
    
    /// Pass 2C+: Merges living document series sharing the same project stem and artifact role
    /// (e.g., `"cot优化roadmap 7"` and `"CoTEditor Roadmap 3"`), even across 10K+ char drafts.
    private static func mergeSameSeriesRoots(
        _ roots: [Int],
        cleanItems: [OrganizeFunnelInput],
        find: (Int) -> Int,
        unite: (Int, Int, String) -> Void
    ) {
        guard roots.count >= 2 else { return }
        
        var sigByRoot: [Int: OrganizeTopicSignature] = [:]
        sigByRoot.reserveCapacity(roots.count)
        for idx in roots {
            let item = cleanItems[idx]
            sigByRoot[idx] = OrganizeTopicSignature.extract(
                title: item.title,
                content: item.content,
                isUntitled: item.isUntitled
            )
        }
        
        var clusterSize: [Int: Int] = [:]
        var clusterChars: [Int: Int] = [:]
        for itemIdx in 0..<cleanItems.count {
            let r = find(itemIdx)
            clusterSize[r, default: 0] += 1
            clusterChars[r, default: 0] += cleanItems[itemIdx].content.count
        }
        
        for i in 0..<roots.count {
            let a = roots[i]
            let itemA = cleanItems[a]
            guard let sigA = sigByRoot[a], !sigA.titleProjectStems.isEmpty else { continue }
            
            for j in (i + 1)..<roots.count {
                let b = roots[j]
                let ra = find(a)
                let rb = find(b)
                if ra == rb { continue }
                
                let itemB = cleanItems[b]
                if itemA.filePath != nil && itemB.filePath != nil { continue }
                guard let sigB = sigByRoot[b], !sigB.titleProjectStems.isEmpty else { continue }
                
                let combinedDocs = (clusterSize[ra] ?? 1) + (clusterSize[rb] ?? 1)
                let combinedChars = (clusterChars[ra] ?? itemA.content.count) + (clusterChars[rb] ?? itemB.content.count)
                guard combinedDocs <= Self.maxSemanticClusterDocs,
                      combinedChars <= Self.maxSemanticClusterChars
                else { continue }
                
                if OrganizeTopicSignature.isSameSeries(sigA, sigB) {
                    unite(a, b, "同系列版本合并")
                    let newRoot = find(a)
                    clusterSize[newRoot] = combinedDocs
                    clusterChars[newRoot] = combinedChars
                }
            }
        }
    }
    
    
    private static func isStrongEntityToken(_ token: String) -> Bool {
        if token.unicodeScalars.allSatisfy(\.isASCII) {
            let hasDetail = token.contains("_") || token.contains("-") || token.contains(".")
                || token.contains(where: \.isNumber)
                || (token.count >= 4 && token.contains(where: \.isUppercase))
            return token.count >= 3 && (hasDetail || token.count >= 5)
        }
        return token.count >= 3 && !Self.genericTopicStopWords.contains(token)
    }
    
    
    private static func mergeSemanticSameTopicRoots(
        _ roots: [Int],
        cleanItems: [OrganizeFunnelInput],
        find: (Int) -> Int,
        unite: (Int, Int, String) -> Void
    ) {
        guard roots.count >= 2 else { return }
        
        var rawTermsByRoot: [Int: Set<String>] = [:]
        var docFreq: [String: Int] = [:]
        for idx in roots {
            let item = cleanItems[idx]
            let titleForTerms = item.isUntitled ? "" : item.title
            let extracted = StarMapRelationEngine.extractKeyTerms(title: titleForTerms, content: item.content)
                .map { $0.lowercased() }
                .filter { !Self.genericTopicStopWords.contains($0) && $0.count >= 2 }
            let termSet = Set(extracted)
            rawTermsByRoot[idx] = termSet
            for term in termSet {
                docFreq[term, default: 0] += 1
            }
        }
        
        let maxCommonDF = roots.count >= 6 ? max(3, Int(Double(roots.count) * 0.45)) : roots.count
        var specificTermsByRoot: [Int: Set<String>] = [:]
        for idx in roots {
            let filtered = (rawTermsByRoot[idx] ?? []).filter { (docFreq[$0] ?? 0) <= maxCommonDF }
            specificTermsByRoot[idx] = filtered
        }
        
        var clusterSize: [Int: Int] = [:]
        var clusterChars: [Int: Int] = [:]
        for itemIdx in 0..<cleanItems.count {
            let r = find(itemIdx)
            clusterSize[r, default: 0] += 1
            clusterChars[r, default: 0] += cleanItems[itemIdx].content.count
        }
        let maxAllowedByCorpus = roots.count >= 6 ? max(3, roots.count / 2) : Self.maxSemanticClusterDocs
        
        for i in 0..<roots.count {
            let a = roots[i]
            let itemA = cleanItems[a]
            guard itemA.content.count <= Self.maxSingleDocSemanticChars else { continue }
            let termsA = specificTermsByRoot[a] ?? []
            guard termsA.count >= 2 else { continue }
            
            for j in (i + 1)..<roots.count {
                let b = roots[j]
                let ra = find(a)
                let rb = find(b)
                if ra == rb { continue }
                
                let itemB = cleanItems[b]
                guard itemB.content.count <= Self.maxSingleDocSemanticChars else { continue }
                // Protect two distinct saved files on disk from local heuristic merging.
                if itemA.filePath != nil && itemB.filePath != nil { continue }
                
                let combinedDocs = (clusterSize[ra] ?? 1) + (clusterSize[rb] ?? 1)
                let combinedChars = (clusterChars[ra] ?? itemA.content.count) + (clusterChars[rb] ?? itemB.content.count)
                guard combinedDocs <= min(Self.maxSemanticClusterDocs, maxAllowedByCorpus),
                      combinedChars <= Self.maxSemanticClusterChars
                else { continue }
                
                let termsB = specificTermsByRoot[b] ?? []
                guard termsB.count >= 2 else { continue }
                let shared = termsA.intersection(termsB)
                guard shared.count >= 3 else { continue }
                
                let minLen = min(termsA.count, termsB.count)
                let overlap = Double(shared.count) / Double(max(1, minLen))
                let dice = (2.0 * Double(shared.count)) / Double(max(1, termsA.count + termsB.count))
                let strongShared = shared.filter(Self.isStrongEntityToken).count
                
                let isSameTopic = (shared.count >= 4 && dice >= 0.30 && overlap >= 0.42)
                    || (strongShared >= 2 && shared.count >= 3 && overlap >= 0.35)
                if isSameTopic {
                    unite(a, b, "同主题文档合并")
                    let newRoot = find(a)
                    clusterSize[newRoot] = combinedDocs
                    clusterChars[newRoot] = combinedChars
                }
            }
        }
    }
    
    
    private static func mergeNearDuplicateRoots(
        _ comparePool: [Int],
        normalizedBodies: [String],
        find: (Int) -> Int,
        unite: (Int, Int, String) -> Void
    ) {
        let shinglesByIdx: [Int: Set<String>] = Dictionary(uniqueKeysWithValues: comparePool.map { idx in
            (idx, Self.charShingles(normalizedBodies[idx], size: 3))
        })
        
        for i in 0..<comparePool.count {
            let a = comparePool[i]
            let bodyA = normalizedBodies[a]
            guard bodyA.count >= 24 else { continue }
            let setA = shinglesByIdx[a] ?? []
            
            for j in (i + 1)..<comparePool.count {
                let b = comparePool[j]
                if find(a) == find(b) { continue }
                let bodyB = normalizedBodies[b]
                guard bodyB.count >= 24 else { continue }
                
                let shorterLen = min(bodyA.count, bodyB.count)
                let longerLen = max(bodyA.count, bodyB.count)
                let ratio = Double(shorterLen) / Double(max(1, longerLen))
                
                if ratio >= 0.45 || shorterLen >= 48 {
                    if bodyA.count >= bodyB.count, bodyA.contains(bodyB) {
                        unite(a, b, "包含重复草稿")
                        continue
                    } else if bodyB.count > bodyA.count, bodyB.contains(bodyA) {
                        unite(a, b, "包含重复草稿")
                        continue
                    }
                }
                
                guard ratio >= 0.55 else { continue }
                let setB = shinglesByIdx[b] ?? []
                guard !setA.isEmpty, !setB.isEmpty else { continue }
                if Self.jaccardSimilarity(setA, setB) >= 0.78 {
                    unite(a, b, "高度相似合并")
                }
            }
        }
    }
    
    
    private static func materializeMergedSurvivors(
        cleanItems: [OrganizeFunnelInput],
        groups: [[Int]],
        reasons: [String]
    ) -> (mergeClusters: [OrganizeMergeCluster], survivors: [OrganizeFunnelInput]) {
        var mergeClusters: [OrganizeMergeCluster] = []
        var survivors: [OrganizeFunnelInput] = []
        survivors.reserveCapacity(groups.count)
        
        for (idx, indexGroup) in groups.enumerated() {
            let group = indexGroup.map { cleanItems[$0] }
            guard let first = group.first else { continue }
            if group.count == 1 {
                survivors.append(first)
                continue
            }
            
            let ranked = group.sorted(by: Self.isBetterPrimary)
            let primary = ranked[0]
            let duplicates = Array(ranked.dropFirst())
            let mergedContent = Self.mergeStructuredContents(primary: primary, secondaries: duplicates)
            let reason = reasons[idx]
            let bestTitle: String = (reason == "同系列版本合并")
                ? OrganizeTopicSignature.cleanSeriesTitle(primary: primary, secondaries: duplicates)
                : (ranked.first(where: { !$0.isUntitled })?.title ?? primary.title)
            let clusterSig = OrganizeTopicSignature.extract(
                title: bestTitle,
                content: mergedContent,
                isUntitled: DocumentCenterAgentOrganizer.isGenericUntitled(bestTitle, hasFilePath: primary.filePath != nil)
            )
            let nonEmptyGroups = ranked.map(\.currentGroup).filter { !$0.isEmpty }
            let bestGroup = nonEmptyGroups.max { lhs, rhs in
                OrganizeTopicSignature.titleAffinityScore(for: clusterSig, groupName: lhs)
                    < OrganizeTopicSignature.titleAffinityScore(for: clusterSig, groupName: rhs)
            } ?? primary.currentGroup
            
            mergeClusters.append(OrganizeMergeCluster(
                primary: primary,
                duplicates: duplicates,
                mergedContent: mergedContent,
                bestGroup: bestGroup,
                bestTitle: bestTitle,
                reason: reason
            ))
            survivors.append(OrganizeFunnelInput(
                id: primary.id,
                dbRecordID: primary.dbRecordID,
                title: bestTitle,
                filePath: primary.filePath,
                syntax: primary.syntax,
                currentGroup: bestGroup,
                content: mergedContent,
                updatedAt: ranked.map(\.updatedAt).max() ?? primary.updatedAt,
                isOpenNow: ranked.contains(where: \.isOpenNow),
                isUntitled: DocumentCenterAgentOrganizer.isGenericUntitled(bestTitle, hasFilePath: primary.filePath != nil)
            ))
        }
        return (mergeClusters, survivors)
    }
    
    
    /// Losslessly merges secondary duplicate drafts into the primary content without duplicating existing paragraphs.
    static func mergeContents(primary: String, secondaries: [String]) -> String {
        let baseNormalized = Self.normalizeBody(primary)
        var resultParagraphs = Self.splitParagraphs(primary)
        var seenParagraphKeys = Set(resultParagraphs.map(Self.normalizeBody).filter { !$0.isEmpty })
        var runningNormalized = baseNormalized
        
        for secondary in secondaries {
            let secNorm = Self.normalizeBody(secondary)
            if secNorm.isEmpty || runningNormalized.contains(secNorm) {
                continue
            }
            for paragraph in Self.splitParagraphs(secondary) {
                let pKey = Self.normalizeBody(paragraph)
                guard pKey.count >= 4 else { continue }
                if seenParagraphKeys.contains(pKey) || runningNormalized.contains(pKey) {
                    continue
                }
                seenParagraphKeys.insert(pKey)
                runningNormalized += " " + pKey
                resultParagraphs.append(paragraph)
            }
        }
        
        let joined = resultParagraphs.joined(separator: "\n\n")
        let range = NSRange(joined.startIndex..<joined.endIndex, in: joined)
        return Self.multiBlankLinesRegex
            .stringByReplacingMatches(in: joined, range: range, withTemplate: "\n\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    
    /// Merges same-topic fragments cleanly in chronological order, deduplicating repeated paragraphs
    /// and near-duplicate list lines, stripping redundant leading titles, and inserting readable
    /// section separators without leaking whimsical placeholder titles.
    static func mergeStructuredContents(
        primary: OrganizeFunnelInput,
        secondaries: [OrganizeFunnelInput]
    ) -> String {
        let orderedSecondaries = secondaries.sorted { $0.updatedAt < $1.updatedAt }
        let baseNormalized = Self.normalizeBody(primary.content)
        var resultParagraphs = Self.splitParagraphs(primary.content)
        var seenParagraphKeys = Set(resultParagraphs.map(Self.normalizeBody).filter { !$0.isEmpty })
        var seenLineKeys = Set(
            primary.content
                .replacingOccurrences(of: "\r\n", with: "\n")
                .components(separatedBy: "\n")
                .map(Self.normalizeBody)
                .filter { $0.count >= 8 }
        )
        var seenLineShingles: [Set<String>] = seenLineKeys
            .filter { $0.count >= 16 }
            .prefix(200)
            .map { Self.charShingles($0, size: 3) }
        var runningNormalized = baseNormalized
        let primaryTitleKey = Self.normalizeBody(primary.title)
        
        for sec in orderedSecondaries {
            let secNorm = Self.normalizeBody(sec.content)
            if secNorm.isEmpty || runningNormalized.contains(secNorm) {
                continue
            }
            var freshParagraphs: [String] = []
            for (pIdx, paragraph) in Self.splitParagraphs(sec.content).enumerated() {
                let pKey = Self.normalizeBody(paragraph)
                guard pKey.count >= 4 else { continue }
                if seenParagraphKeys.contains(pKey) || runningNormalized.contains(pKey) {
                    continue
                }
                // Skip redundant leading H1 title that duplicates primary's title.
                if pIdx == 0,
                   paragraph.trimmingCharacters(in: .whitespaces).hasPrefix("# "),
                   !primaryTitleKey.isEmpty,
                   Self.normalizeBody(String(paragraph.dropFirst(2))) == primaryTitleKey
                {
                    continue
                }
                let cleanedParagraph = Self.deduplicateLinesInParagraph(
                    paragraph,
                    seenLineKeys: &seenLineKeys,
                    seenLineShingles: &seenLineShingles
                )
                guard !cleanedParagraph.isEmpty else { continue }
                let cleanedKey = Self.normalizeBody(cleanedParagraph)
                guard cleanedKey.count >= 4 else { continue }
                seenParagraphKeys.insert(cleanedKey)
                runningNormalized += " " + cleanedKey
                freshParagraphs.append(cleanedParagraph)
            }
            guard !freshParagraphs.isEmpty else { continue }
            
            // Add a clean sub-heading only when this fragment adds distinct content and doesn't already start with one.
            let startsWithHeading = freshParagraphs[0].trimmingCharacters(in: .whitespaces).hasPrefix("#")
            if !startsWithHeading,
               !sec.isUntitled,
               sec.title.caseInsensitiveCompare(primary.title) != .orderedSame,
               !DocumentCenterAgentOrganizer.isWeakScratchTitle(sec.title, hasFilePath: false)
            {
                let headingKey = Self.normalizeBody(sec.title)
                if !headingKey.isEmpty && !runningNormalized.contains(headingKey) {
                    resultParagraphs.append("## \(sec.title)")
                }
            }
            resultParagraphs.append(contentsOf: freshParagraphs)
        }
        
        let joined = resultParagraphs.joined(separator: "\n\n")
        let range = NSRange(joined.startIndex..<joined.endIndex, in: joined)
        return Self.multiBlankLinesRegex
            .stringByReplacingMatches(in: joined, range: range, withTemplate: "\n\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    
    private static func deduplicateLinesInParagraph(
        _ paragraph: String,
        seenLineKeys: inout Set<String>,
        seenLineShingles: inout [Set<String>]
    ) -> String {
        let lines = paragraph.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        guard lines.count > 1 else {
            let key = Self.normalizeBody(paragraph)
            if key.count >= 8 { seenLineKeys.insert(key) }
            return paragraph
        }
        var kept: [String] = []
        kept.reserveCapacity(lines.count)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            let key = Self.normalizeBody(trimmed)
            if key.count >= 8 {
                if seenLineKeys.contains(key) { continue }
                if key.count >= 16 {
                    let shingles = Self.charShingles(key, size: 3)
                    let isNearDup = seenLineShingles.contains { Self.jaccardSimilarity($0, shingles) >= 0.84 }
                    if isNearDup { continue }
                    if seenLineShingles.count < 240 {
                        seenLineShingles.append(shingles)
                    }
                }
                seenLineKeys.insert(key)
            }
            kept.append(line)
        }
        return kept.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    
    // MARK: Stage 3 & 4 — Sharded Parallel AI Batching + Group Convergence
    
    static func makeShards<T>(_ items: [T], shardSize: Int = defaultShardSize) -> [[T]] {
        let step = max(1, shardSize)
        guard !items.isEmpty else { return [] }
        var shards: [[T]] = []
        shards.reserveCapacity((items.count + step - 1) / step)
        var start = 0
        while start < items.count {
            let end = min(items.count, start + step)
            shards.append(Array(items[start..<end]))
            start = end
        }
        return shards
    }
    
    
    /// Normalizes slight synonym drift across parallel AI shards while preserving user-defined groups.
    static func consolidateAssignments(
        _ assignments: [DocumentCenterAgentOrganizer.Assignment],
        existingGroups: [String]
    ) -> [DocumentCenterAgentOrganizer.Assignment] {
        let existingSet = Set(existingGroups)
        return assignments.map { assignment in
            let raw = assignment.group.trimmingCharacters(in: .whitespacesAndNewlines)
            if raw.isEmpty || raw == "未分组" || existingSet.contains(raw) {
                return assignment
            }
            if let canonical = Self.groupSynonymMap[raw] {
                return DocumentCenterAgentOrganizer.Assignment(
                    id: assignment.id,
                    group: canonical,
                    suggestedTitle: assignment.suggestedTitle
                )
            }
            return assignment
        }
    }
    
    
    /// Validates AI-proposed semantic merges with strict anti-over-merge guardrails and folds them
    /// losslessly into the funnel result so Undo tracks every original pre-merge document cleanly.
    static func applyValidatedAIMerges(
        _ proposals: [DocumentCenterAgentOrganizer.SemanticMergeProposal],
        baseFunnel: OrganizeFunnelStageResult,
        rawAssignments: [DocumentCenterAgentOrganizer.Assignment]
    ) -> (funnel: OrganizeFunnelStageResult, assignments: [DocumentCenterAgentOrganizer.Assignment]) {
        guard !proposals.isEmpty, baseFunnel.survivors.count >= 2 else {
            return (baseFunnel, rawAssignments)
        }
        
        let survivorByID = Dictionary(uniqueKeysWithValues: baseFunnel.survivors.map { ($0.id, $0) })
        let maxSingleClusterDocs = baseFunnel.survivors.count >= 5
            ? min(6, max(2, Int(Double(baseFunnel.survivors.count) * 0.60)))
            : min(4, max(2, baseFunnel.survivors.count - 1))
        let maxMergedChars = 80_000
        
        var claimedIDs = Set<String>()
        var existingClustersByPrimary = Dictionary(uniqueKeysWithValues: baseFunnel.mergeClusters.map { ($0.primary.id, $0) })
        var absorbedSurvivorIDs = Set<String>()
        var updatedSurvivorsByID = survivorByID
        var assignmentPatchByPrimaryID: [String: (group: String?, title: String?)] = [:]
        
        for proposal in proposals {
            let candidateIDs = [proposal.primaryId] + proposal.mergeIds
            let validCandidates = candidateIDs.compactMap { id -> OrganizeFunnelInput? in
                guard !claimedIDs.contains(id), let doc = survivorByID[id] else { return nil }
                return doc
            }
            guard validCandidates.count >= 2, validCandidates.count <= maxSingleClusterDocs else { continue }
            
            // Protect multiple distinct saved disk files from being folded together by AI heuristics.
            let ranked = validCandidates.sorted(by: Self.isBetterPrimary)
            let primary = ranked[0]
            let mergeables = ranked.dropFirst().filter { sec in
                !(primary.filePath != nil && sec.filePath != nil)
            }
            guard !mergeables.isEmpty else { continue }
            
            let totalChars = primary.content.count + mergeables.reduce(0) { $0 + $1.content.count }
            guard totalChars <= maxMergedChars else { continue }
            
            claimedIDs.insert(primary.id)
            for sec in mergeables { claimedIDs.insert(sec.id) }
            
            let mergedContent = Self.mergeStructuredContents(primary: primary, secondaries: Array(mergeables))
            let preferredTitle = proposal.mergedTitle
                ?? (primary.isUntitled ? DocumentCenterAgentOrganizer.deriveTitleFromExcerpt(mergedContent) : nil)
                ?? ranked.first(where: { !$0.isUntitled })?.title
                ?? primary.title
            let preferredGroup = proposal.group
                ?? ranked.first(where: { !$0.currentGroup.isEmpty })?.currentGroup
                ?? primary.currentGroup
            
            // Flatten any earlier Stage-2 clusters so every original pre-organize item stays in `duplicates`.
            let originalPrimary = existingClustersByPrimary[primary.id]?.primary ?? primary
            var combinedDuplicates: [OrganizeFunnelInput] = existingClustersByPrimary[primary.id]?.duplicates ?? []
            for sec in mergeables {
                absorbedSurvivorIDs.insert(sec.id)
                if let secCluster = existingClustersByPrimary.removeValue(forKey: sec.id) {
                    combinedDuplicates.append(secCluster.primary)
                    combinedDuplicates.append(contentsOf: secCluster.duplicates)
                } else {
                    combinedDuplicates.append(sec)
                }
            }
            
            existingClustersByPrimary[primary.id] = OrganizeMergeCluster(
                primary: originalPrimary,
                duplicates: combinedDuplicates,
                mergedContent: mergedContent,
                bestGroup: preferredGroup,
                bestTitle: preferredTitle,
                reason: proposal.reason ?? "AI 同主题语义合并"
            )
            
            updatedSurvivorsByID[primary.id] = OrganizeFunnelInput(
                id: primary.id,
                dbRecordID: primary.dbRecordID,
                title: preferredTitle,
                filePath: primary.filePath,
                syntax: primary.syntax,
                currentGroup: preferredGroup,
                content: mergedContent,
                updatedAt: ([primary] + mergeables).map(\.updatedAt).max() ?? primary.updatedAt,
                isOpenNow: ([primary] + mergeables).contains(where: \.isOpenNow),
                isUntitled: DocumentCenterAgentOrganizer.isGenericUntitled(preferredTitle, hasFilePath: primary.filePath != nil)
            )
            assignmentPatchByPrimaryID[primary.id] = (proposal.group, proposal.mergedTitle)
        }
        
        guard !absorbedSurvivorIDs.isEmpty else {
            return (baseFunnel, rawAssignments)
        }
        
        let finalSurvivors = baseFunnel.survivors.compactMap { item -> OrganizeFunnelInput? in
            guard !absorbedSurvivorIDs.contains(item.id) else { return nil }
            return updatedSurvivorsByID[item.id] ?? item
        }
        let orderedPrimaryIDs = finalSurvivors.map(\.id)
        let finalClusters = orderedPrimaryIDs.compactMap { existingClustersByPrimary[$0] }
        
        let filteredAssignments: [DocumentCenterAgentOrganizer.Assignment] = rawAssignments.compactMap { item in
            guard !absorbedSurvivorIDs.contains(item.id) else { return nil }
            if let patch = assignmentPatchByPrimaryID[item.id] {
                return DocumentCenterAgentOrganizer.Assignment(
                    id: item.id,
                    group: patch.group ?? item.group,
                    suggestedTitle: patch.title ?? item.suggestedTitle
                )
            }
            return item
        }
        
        let updatedFunnel = OrganizeFunnelStageResult(
            junkToDelete: baseFunnel.junkToDelete,
            mergeClusters: finalClusters,
            survivors: finalSurvivors
        )
        return (updatedFunnel, filteredAssignments)
    }
    
    
    /// Validates AI-proposed deletions of meaningless/hollow scratch documents with strict substance
    /// guardrails: never deletes saved disk files or documents with substantial real body content,
    /// and preserves full Undo traceability for every removed document.
    static func applyValidatedAIDeletes(
        _ proposals: [DocumentCenterAgentOrganizer.SemanticDeleteProposal],
        baseFunnel: OrganizeFunnelStageResult,
        rawAssignments: [DocumentCenterAgentOrganizer.Assignment],
        protectedIDs: Set<String> = []
    ) -> (funnel: OrganizeFunnelStageResult, assignments: [DocumentCenterAgentOrganizer.Assignment]) {
        guard !proposals.isEmpty, !baseFunnel.survivors.isEmpty else {
            return (baseFunnel, rawAssignments)
        }
        
        let survivorByID = Dictionary(uniqueKeysWithValues: baseFunnel.survivors.map { ($0.id, $0) })
        let clusterByPrimaryID = Dictionary(uniqueKeysWithValues: baseFunnel.mergeClusters.map { ($0.primary.id, $0) })
        
        var deletedIDs = Set<String>()
        var addedJunk: [OrganizeJunkDecision] = []
        var nonHollowDeleteCount = 0
        let maxNonHollowDeletes = max(2, Int(Double(baseFunnel.survivors.count) * 0.45))
        
        for proposal in proposals {
            guard !protectedIDs.contains(proposal.id),
                  !deletedIDs.contains(proposal.id),
                  let doc = survivorByID[proposal.id]
            else { continue }
            
            // Guardrail 1: Never delete saved disk files via AI semantic judgment.
            guard doc.filePath == nil else { continue }
            
            // Guardrail 2: Inspect actual substance inside the document.
            let report = OrganizeDocumentAnalyzer.analyzeSubstance(
                title: doc.title,
                content: doc.content,
                filePath: nil,
                isUntitled: doc.isUntitled
            )
            guard !report.isProtectedSubstantiveContent else { continue }
            
            let isClearlyHollow = (report.substantiveBodyChars < 45 && !report.hasCodeBlock && !report.hasSubstantiveTable)
            if !isClearlyHollow {
                guard nonHollowDeleteCount < maxNonHollowDeletes else { continue }
                nonHollowDeleteCount += 1
            }
            
            deletedIDs.insert(doc.id)
            let detail = proposal.reason?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let existingCluster = clusterByPrimaryID[doc.id] {
                addedJunk.append(OrganizeJunkDecision(item: existingCluster.primary, reason: .aiHollow, detail: detail))
                for dup in existingCluster.duplicates {
                    addedJunk.append(OrganizeJunkDecision(item: dup, reason: .aiHollow, detail: detail))
                }
            } else {
                addedJunk.append(OrganizeJunkDecision(item: doc, reason: .aiHollow, detail: detail))
            }
        }
        
        guard !deletedIDs.isEmpty else {
            return (baseFunnel, rawAssignments)
        }
        
        let remainingSurvivors = baseFunnel.survivors.filter { !deletedIDs.contains($0.id) }
        let remainingClusters = baseFunnel.mergeClusters.filter { !deletedIDs.contains($0.primary.id) }
        let remainingAssignments = rawAssignments.filter { !deletedIDs.contains($0.id) }
        let updatedFunnel = OrganizeFunnelStageResult(
            junkToDelete: baseFunnel.junkToDelete + addedJunk,
            mergeClusters: remainingClusters,
            survivors: remainingSurvivors
        )
        return (updatedFunnel, remainingAssignments)
    }
    
    
    /// Target maximum group count so the Star Map stays crisp and avoids tiny 1–2 doc micro-groups.
    static func targetMaxGroups(for survivorCount: Int) -> Int {
        switch survivorCount {
            case ...4: 2
            case 5...10: 3
            case 11...18: 4
            case 19...30: 5
            default: 6
        }
    }
    
    
    private static let coarseGroupParentMap: [String: String] = [
        "评测分析": "评测与数据",
        "数据分析": "评测与数据",
        "配置数据": "工程与开发",
        "代码开发": "工程与开发",
        "技术笔记": "工程与开发",
        "项目方案": "方案与会议",
        "会议纪要": "方案与会议",
        "工作清单": "周报与待办",
        "日常记录": "日常随记",
    ]
    
    
    /// Compacts overly fine-grained or 1-doc singleton groups into a crisp, balanced set of 2–5 pillars.
    static func compactFragmentedGroups(
        _ assignments: [DocumentCenterAgentOrganizer.Assignment],
        survivorByID: [String: OrganizeFunnelInput]
    ) -> [DocumentCenterAgentOrganizer.Assignment] {
        guard assignments.count >= 4 else { return assignments }
        var result = assignments
        let maxGroups = Self.targetMaxGroups(for: assignments.count)
        
        func countsByGroup() -> [String: Int] {
            var counts: [String: Int] = [:]
            for a in result where !a.group.isEmpty { counts[a.group, default: 0] += 1 }
            return counts
        }
        
        // Pass 1: Roll overlapping micro-categories (e.g. 评测分析 + 数据分析) into clean pillars when over-fragmented.
        var counts = countsByGroup()
        let hasSingleton = counts.values.contains(1)
        if counts.count > maxGroups || (counts.count >= 4 && hasSingleton) {
            for idx in 0..<result.count {
                let g = result[idx].group
                guard let parent = Self.coarseGroupParentMap[g] else { continue }
                let isSmallOrOverBudget = (counts[g] ?? 0) <= 2 || counts.count > maxGroups
                if isSmallOrOverBudget {
                    result[idx] = DocumentCenterAgentOrganizer.Assignment(
                        id: result[idx].id,
                        group: parent,
                        suggestedTitle: result[idx].suggestedTitle
                    )
                }
            }
            counts = countsByGroup()
        }
        
        // Pass 2: Absorb any remaining excess smallest/singleton groups into the nearest semantic sibling (< 8 docs).
        while counts.count > maxGroups || (counts.count >= 4 && counts.values.contains(1)) {
            let sortedGroups = counts.sorted { lhs, rhs in
                if lhs.value != rhs.value { return lhs.value < rhs.value }
                return lhs.key < rhs.key
            }
            guard let smallest = sortedGroups.first else { break }
            let donorGroup = smallest.key
            let donorCount = smallest.value
            let donorIndices = result.indices.filter { result[$0].group == donorGroup }
            let donorTerms = Set(donorIndices.flatMap { idx -> [String] in
                guard let doc = survivorByID[result[idx].id] else { return [] }
                return Array(StarMapRelationEngine.extractKeyTerms(title: doc.isUntitled ? "" : doc.title, content: doc.content))
            })
            
            var bestTarget: String?
            var bestScore = -1
            let maxAbsorbedGroupSize = max(8, result.count / 2)
            for (candidateGroup, candidateCount) in counts where candidateGroup != donorGroup {
                guard candidateCount + donorCount <= maxAbsorbedGroupSize else { continue }
                let candidateTerms = Set(result.indices.filter { result[$0].group == candidateGroup }.flatMap { idx -> [String] in
                    guard let doc = survivorByID[result[idx].id] else { return [] }
                    return Array(StarMapRelationEngine.extractKeyTerms(title: doc.isUntitled ? "" : doc.title, content: doc.content))
                })
                let affinity = donorTerms.intersection(candidateTerms).count * 10 + candidateCount
                if affinity > bestScore {
                    bestScore = affinity
                    bestTarget = candidateGroup
                }
            }
            guard let targetGroup = bestTarget else { break }
            for idx in donorIndices {
                result[idx] = DocumentCenterAgentOrganizer.Assignment(
                    id: result[idx].id,
                    group: targetGroup,
                    suggestedTitle: result[idx].suggestedTitle
                )
            }
            counts = countsByGroup()
        }
        
        return result
    }
    
    
    /// Reconciles any misgrouped document whose title strongly names an existing active group
    /// (e.g., `"cot优化roadmap 7"` stranded in `"评测与数据"` while group `"cot优化"` exists).
    static func reconcileTitleGroupCoherence(
        _ assignments: [DocumentCenterAgentOrganizer.Assignment],
        survivorByID: [String: OrganizeFunnelInput]
    ) -> [DocumentCenterAgentOrganizer.Assignment] {
        let activeGroups = Array(Set(assignments.map(\.group).filter { !$0.isEmpty })).sorted()
        guard activeGroups.count >= 2 else { return assignments }
        
        return assignments.map { current in
            guard let doc = survivorByID[current.id] else { return current }
            let effectiveTitle = current.suggestedTitle ?? doc.title
            let isUntitled = DocumentCenterAgentOrganizer.isGenericUntitled(effectiveTitle, hasFilePath: doc.filePath != nil)
            guard !isUntitled else { return current }
            
            let sig = OrganizeTopicSignature.extract(title: effectiveTitle, content: doc.content, isUntitled: false)
            guard !sig.titleProjectStems.isEmpty else { return current }
            
            let currentScore = OrganizeTopicSignature.titleAffinityScore(for: sig, groupName: current.group)
            var bestGroup = current.group
            var bestScore = currentScore
            for candidateGroup in activeGroups where candidateGroup != current.group {
                let candidateScore = OrganizeTopicSignature.titleAffinityScore(for: sig, groupName: candidateGroup)
                if candidateScore >= 12 && candidateScore > bestScore + 8 {
                    bestScore = candidateScore
                    bestGroup = candidateGroup
                }
            }
            guard bestGroup != current.group else { return current }
            return DocumentCenterAgentOrganizer.Assignment(
                id: current.id,
                group: bestGroup,
                suggestedTitle: current.suggestedTitle
            )
        }
    }
    
    
    /// Guarantees clean Star-Map output after AI or local classification:
    /// 1) Consolidates synonym drift;
    /// 2) Reconciles title-to-group coherence;
    /// 3) Splits any remaining oversized monolithic group (`>= 10` docs) into crisp topic buckets;
    /// 4) Compacts overly fine-grained / singleton micro-groups into a balanced 2–5 pillar overview;
    /// 5) Re-verifies title coherence & ensures every untitled / whimsical document gets a unique title.
    static func finalizeAssignments(
        _ assignments: [DocumentCenterAgentOrganizer.Assignment],
        survivors: [OrganizeFunnelInput],
        existingGroups: [String]
    ) -> [DocumentCenterAgentOrganizer.Assignment] {
        var result = Self.consolidateAssignments(assignments, existingGroups: existingGroups)
        let survivorByID = Dictionary(uniqueKeysWithValues: survivors.map { ($0.id, $0) })
        result = Self.reconcileTitleGroupCoherence(result, survivorByID: survivorByID)
        
        // 1. Anti-monolith guard: if any single group holds >= 10 docs or swallows >= 80% of a >= 5 doc workspace, split by content semantics.
        var indicesByGroup: [String: [Int]] = [:]
        for (idx, item) in result.enumerated() where !item.group.isEmpty {
            indicesByGroup[item.group, default: []].append(idx)
        }
        for (_, bucketIndices) in indicesByGroup where bucketIndices.count >= 10 || (result.count >= 5 && bucketIndices.count == result.count) {
            let subInputs: [DocumentCenterAgentOrganizer.InputItem] = bucketIndices.compactMap { idx in
                guard let doc = survivorByID[result[idx].id] else { return nil }
                return DocumentCenterAgentOrganizer.InputItem(
                    id: doc.id,
                    title: doc.title,
                    syntax: doc.syntax,
                    currentGroup: doc.currentGroup,
                    excerpt: String(doc.content.prefix(480)),
                    isUntitled: doc.isUntitled
                )
            }
            let splitPlan = DocumentCenterAgentOrganizer.buildLocalFallbackPlan(
                items: subInputs,
                existingGroups: [],
                allowPreserveExisting: false
            )
            let distinctGroups = Set(splitPlan.assignments.map(\.group).filter { !$0.isEmpty })
            if distinctGroups.count >= 2 {
                let splitByID = Dictionary(uniqueKeysWithValues: splitPlan.assignments.map { ($0.id, $0.group) })
                for idx in bucketIndices {
                    let current = result[idx]
                    if let betterGroup = splitByID[current.id], !betterGroup.isEmpty {
                        result[idx] = DocumentCenterAgentOrganizer.Assignment(
                            id: current.id,
                            group: betterGroup,
                            suggestedTitle: current.suggestedTitle
                        )
                    }
                }
            }
        }
        
        // 2. Compact fragmented micro-groups so the Star Map stays genuinely uncluttered,
        // then re-verify title-group coherence so named project docs never drift into unrelated buckets.
        result = Self.compactFragmentedGroups(result, survivorByID: survivorByID)
        result = Self.reconcileTitleGroupCoherence(result, survivorByID: survivorByID)
        
        // 3. Guaranteed meaningful title + deduplication for every untitled / weak-scratch survivor.
        var usedTitles = Set(
            survivors
                .filter { !DocumentCenterAgentOrganizer.isWeakScratchTitle($0.title, hasFilePath: $0.filePath != nil) }
                .map { $0.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        )
        
        for idx in 0..<result.count {
            let current = result[idx]
            guard let doc = survivorByID[current.id] else { continue }
            let isWeak = doc.isUntitled || DocumentCenterAgentOrganizer.isWeakScratchTitle(doc.title, hasFilePath: doc.filePath != nil)
            guard isWeak else { continue }
            
            var candidate = current.suggestedTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let existing = candidate,
               (existing.isEmpty || DocumentCenterAgentOrganizer.isWeakScratchTitle(existing, hasFilePath: false))
            {
                candidate = nil
            }
            if candidate == nil {
                candidate = DocumentCenterAgentOrganizer.deriveTitleFromExcerpt(doc.content)
            }
            guard var finalTitle = candidate, !finalTitle.isEmpty else { continue }
            
            let base = finalTitle
            var suffix = 2
            while usedTitles.contains(finalTitle.lowercased()) && suffix <= 99 {
                finalTitle = "\(base) \(suffix)"
                suffix += 1
            }
            usedTitles.insert(finalTitle.lowercased())
            
            if finalTitle != current.suggestedTitle {
                result[idx] = DocumentCenterAgentOrganizer.Assignment(
                    id: current.id,
                    group: current.group,
                    suggestedTitle: finalTitle
                )
            }
        }
        
        return result
    }
    
    
    /// Executes the complete multi-stage Chief-of-Staff Data Funnel:
    /// 1) Deep substance & hollow/title-only cleanup -> 2) Exact & same-series semantic merging ->
    /// 3) Holistic AI architect (deletes + merges + content-first workstream grouping + renames) ->
    /// 3.5) Parallel lossless AI synthesis for merged clusters -> 4) Group convergence & title guarantee.
    @MainActor
    static func runFullPipeline(
        items: [OrganizeFunnelInput],
        existingGroups: [String],
        allowRemoteAI: Bool = true,
        shardSize: Int = defaultShardSize,
        maxConcurrency: Int = defaultMaxConcurrency,
        analyticsFeature: String = "documentCenterAgentOrganize",
        onProgress: (@MainActor (OrganizeFunnelProgress) -> Void)? = nil
    ) async -> OrganizeFullPlan {
        guard !items.isEmpty else {
            return OrganizeFullPlan(
                funnel: OrganizeFunnelStageResult(junkToDelete: [], mergeClusters: [], survivors: []),
                assignments: [],
                batchCount: 0,
                usedAI: false
            )
        }
        
        onProgress?(.filteringJunk(total: items.count))
        let localFunnel = await Task.detached(priority: .userInitiated) {
            Self.runLocalFunnel(items: items)
        }.value
        
        onProgress?(.mergingDuplicates(
            remaining: localFunnel.survivors.count,
            junkDeleted: localFunnel.junkToDelete.count
        ))
        
        guard !localFunnel.survivors.isEmpty else {
            return OrganizeFullPlan(funnel: localFunnel, assignments: [], batchCount: 0, usedAI: false)
        }
        
        let agentInputs = Self.makeAgentInputs(from: localFunnel.survivors)
        let shards = Self.makeCohesiveShards(agentInputs, survivors: localFunnel.survivors, shardSize: shardSize)
        let useAI = allowRemoteAI && AIService.shared.isConfigured
        
        if !useAI {
            return Self.buildOfflinePlan(
                localFunnel: localFunnel,
                agentInputs: agentInputs,
                existingGroups: existingGroups,
                batchCount: shards.count
            )
        }
        
        let architectOutcome = await Self.runAIShardedArchitect(
            shards: shards,
            localFunnel: localFunnel,
            existingGroups: existingGroups,
            maxConcurrency: maxConcurrency,
            analyticsFeature: analyticsFeature,
            onProgress: onProgress
        )
        
        // Apply validated AI merges first, then validated AI deletes (protecting merge primaries).
        let mergedOutcome = Self.applyValidatedAIMerges(
            architectOutcome.merges,
            baseFunnel: localFunnel,
            rawAssignments: architectOutcome.assignments
        )
        let mergePrimaryIDs = Set(mergedOutcome.funnel.mergeClusters.map(\.primary.id))
        let cleanedOutcome = Self.applyValidatedAIDeletes(
            architectOutcome.deletes,
            baseFunnel: mergedOutcome.funnel,
            rawAssignments: mergedOutcome.assignments,
            protectedIDs: mergePrimaryIDs
        )
        
        // Stage 3.5: Losslessly synthesize multi-doc merged clusters with factual-retention guardrails.
        let synthesizedFunnel = architectOutcome.usedAI
            ? await Self.synthesizeMergedClustersWithAI(
                cleanedOutcome.funnel,
                analyticsFeature: analyticsFeature,
                onProgress: onProgress
            )
            : cleanedOutcome.funnel
        
        onProgress?(.consolidating)
        let finalized = Self.finalizeAssignments(
            cleanedOutcome.assignments,
            survivors: synthesizedFunnel.survivors,
            existingGroups: existingGroups
        )
        
        return OrganizeFullPlan(
            funnel: synthesizedFunnel,
            assignments: finalized,
            batchCount: shards.count,
            usedAI: architectOutcome.usedAI
        )
    }
    
    
    private static func makeAgentInputs(from survivors: [OrganizeFunnelInput]) -> [DocumentCenterAgentOrganizer.InputItem] {
        survivors.map { item in
            DocumentCenterAgentOrganizer.InputItem(
                id: item.id,
                title: item.title,
                syntax: item.syntax,
                currentGroup: item.currentGroup,
                excerpt: String(item.content.prefix(640)),
                isUntitled: item.isUntitled
            )
        }
    }
    
    
    private static func makeCohesiveShards(
        _ agentInputs: [DocumentCenterAgentOrganizer.InputItem],
        survivors: [OrganizeFunnelInput],
        shardSize: Int
    ) -> [[DocumentCenterAgentOrganizer.InputItem]] {
        let metaByID = Dictionary(uniqueKeysWithValues: survivors.map { ($0.id, $0) })
        let ordered = agentInputs.sorted { lhs, rhs in
            let metaL = metaByID[lhs.id]
            let metaR = metaByID[rhs.id]
            let stemL = OrganizeTopicSignature.extract(title: lhs.title, content: metaL?.content ?? lhs.excerpt, isUntitled: lhs.isUntitled).primaryProjectStem
            let stemR = OrganizeTopicSignature.extract(title: rhs.title, content: metaR?.content ?? rhs.excerpt, isUntitled: rhs.isUntitled).primaryProjectStem
            if stemL != stemR { return stemL < stemR }
            if lhs.currentGroup != rhs.currentGroup { return lhs.currentGroup < rhs.currentGroup }
            return lhs.title < rhs.title
        }
        return Self.makeShards(ordered, shardSize: shardSize)
    }
    
    
    private static func buildOfflinePlan(
        localFunnel: OrganizeFunnelStageResult,
        agentInputs: [DocumentCenterAgentOrganizer.InputItem],
        existingGroups: [String],
        batchCount: Int
    ) -> OrganizeFullPlan {
        let localPlan = DocumentCenterAgentOrganizer.buildLocalFallbackPlan(
            items: agentInputs,
            existingGroups: existingGroups
        )
        let healthyExisting = Self.computeGroupHealth(
            survivors: localFunnel.survivors,
            existingGroups: existingGroups
        ).healthy
        let workstreamMap = OrganizeTopicSignature.discoverWorkstreamGroupMap(
            for: localFunnel.survivors,
            healthyExistingGroups: healthyExisting
        )
        let enriched = localPlan.assignments.map { item -> DocumentCenterAgentOrganizer.Assignment in
            if let workstream = workstreamMap[item.id], !workstream.isEmpty {
                return DocumentCenterAgentOrganizer.Assignment(
                    id: item.id,
                    group: workstream,
                    suggestedTitle: item.suggestedTitle
                )
            }
            return item
        }
        let finalized = Self.finalizeAssignments(
            enriched,
            survivors: localFunnel.survivors,
            existingGroups: existingGroups
        )
        return OrganizeFullPlan(
            funnel: localFunnel,
            assignments: finalized,
            batchCount: batchCount,
            usedAI: false
        )
    }
    
    
    private static func computeGroupHealth(
        survivors: [OrganizeFunnelInput],
        existingGroups: [String]
    ) -> (healthy: [String], bloated: [String]) {
        var survivorGroupCounts: [String: Int] = [:]
        for item in survivors where !item.currentGroup.isEmpty {
            survivorGroupCounts[item.currentGroup, default: 0] += 1
        }
        let total = survivors.count
        let bloated = survivorGroupCounts
            .filter {
                DocumentCenterAgentOrganizer.isMonolithicGroup(count: $0.value, totalItems: total)
                    || DocumentCenterAgentOrganizer.catchAllGroupNames.contains($0.key)
            }
            .map(\.key)
            .sorted()
        let healthy = existingGroups.filter {
            !DocumentCenterAgentOrganizer.catchAllGroupNames.contains($0)
                && !DocumentCenterAgentOrganizer.isMonolithicGroup(count: survivorGroupCounts[$0, default: 0], totalItems: total)
        }
        return (healthy, bloated)
    }
    
    
    @MainActor
    private static func runAIShardedArchitect(
        shards: [[DocumentCenterAgentOrganizer.InputItem]],
        localFunnel: OrganizeFunnelStageResult,
        existingGroups: [String],
        maxConcurrency: Int,
        analyticsFeature: String,
        onProgress: (@MainActor (OrganizeFunnelProgress) -> Void)?
    ) async -> (
        assignments: [DocumentCenterAgentOrganizer.Assignment],
        merges: [DocumentCenterAgentOrganizer.SemanticMergeProposal],
        deletes: [DocumentCenterAgentOrganizer.SemanticDeleteProposal],
        usedAI: Bool
    ) {
        let health = Self.computeGroupHealth(survivors: localFunnel.survivors, existingGroups: existingGroups)
        let targetGroups = Self.targetMaxGroups(for: localFunnel.survivors.count)
        let survivorMetaByID = Dictionary(uniqueKeysWithValues: localFunnel.survivors.map { ($0.id, $0) })
        let totalBatches = shards.count
        
        onProgress?(.shardedOrganizing(completedBatches: 0, totalBatches: totalBatches, survivorCount: localFunnel.survivors.count))
        
        typealias ShardOutcome = (
            index: Int,
            assignments: [DocumentCenterAgentOrganizer.Assignment],
            merges: [DocumentCenterAgentOrganizer.SemanticMergeProposal],
            deletes: [DocumentCenterAgentOrganizer.SemanticDeleteProposal],
            usedAI: Bool
        )
        var orderedResults: [ShardOutcome] = []
        orderedResults.reserveCapacity(totalBatches)
        var completedBatches = 0
        let concurrencyLimit = max(1, min(maxConcurrency, totalBatches))
        
        await withTaskGroup(of: ShardOutcome.self) { group in
            var nextShardIndex = 0
            func enqueueNext() {
                guard nextShardIndex < totalBatches, !Task.isCancelled else { return }
                let idx = nextShardIndex
                let shard = shards[idx]
                nextShardIndex += 1
                group.addTask {
                    let outcome = await Self.organizeSingleShard(
                        shard,
                        survivorMetaByID: survivorMetaByID,
                        healthyExistingGroups: health.healthy,
                        bloatedGroups: health.bloated,
                        targetMaxGroups: targetGroups,
                        shardIndex: idx,
                        totalShards: totalBatches,
                        analyticsFeature: analyticsFeature
                    )
                    return (idx, outcome.assignments, outcome.merges, outcome.deletes, outcome.usedAI)
                }
            }
            for _ in 0..<concurrencyLimit { enqueueNext() }
            while let result = await group.next() {
                orderedResults.append(result)
                completedBatches += 1
                onProgress?(.shardedOrganizing(
                    completedBatches: completedBatches,
                    totalBatches: totalBatches,
                    survivorCount: localFunnel.survivors.count
                ))
                enqueueNext()
            }
        }
        
        orderedResults.sort { $0.index < $1.index }
        return (
            assignments: orderedResults.flatMap(\.assignments),
            merges: orderedResults.flatMap(\.merges),
            deletes: orderedResults.flatMap(\.deletes),
            usedAI: orderedResults.contains(where: \.usedAI)
        )
    }
    
    
    @MainActor
    private static func organizeSingleShard(
        _ shard: [DocumentCenterAgentOrganizer.InputItem],
        survivorMetaByID: [String: OrganizeFunnelInput],
        healthyExistingGroups: [String],
        bloatedGroups: [String],
        targetMaxGroups: Int,
        shardIndex: Int,
        totalShards: Int,
        analyticsFeature: String
    ) async -> (
        assignments: [DocumentCenterAgentOrganizer.Assignment],
        merges: [DocumentCenterAgentOrganizer.SemanticMergeProposal],
        deletes: [DocumentCenterAgentOrganizer.SemanticDeleteProposal],
        usedAI: Bool
    ) {
        let validIDs = Set(shard.map(\.id))
        let bloatedSet = Set(bloatedGroups)
        let manifestLines = shard.enumerated().map { idx, item -> String in
            let meta = survivorMetaByID[item.id] ?? OrganizeFunnelInput(
                id: item.id,
                dbRecordID: item.id,
                title: item.title,
                filePath: nil,
                syntax: item.syntax,
                currentGroup: item.currentGroup,
                content: item.excerpt,
                updatedAt: Date(),
                isOpenNow: false,
                isUntitled: item.isUntitled
            )
            return OrganizeDocumentAnalyzer.buildAIDossier(
                for: meta,
                index: idx + 1,
                totalInBatch: shard.count,
                bloatedGroups: bloatedSet
            )
        }.joined(separator: "\n\n")
        
        let existingHint = healthyExistingGroups.isEmpty
            ? "（当前无预设健康分组，请完全依据文档内部真实工作主线自拟高辨识度分组名）"
            : "已有健康分组（若契合可沿用）：\(healthyExistingGroups.prefix(6).joined(separator: "、"))"
        let bloatedHint = bloatedGroups.isEmpty
            ? ""
            : "\n   - 原分组「\(bloatedGroups.joined(separator: "、"))」过于臃肿或泛化，禁止原封不动塞回同一组。"
        
        let systemPrompt = """
        你是用户专属的高智商首席幕僚与知识架构师（第 \(shardIndex + 1)/\(totalShards) 批）。
        你的使命：真正读懂每篇文档**内部实际在做的工作与事项**，把杂乱的工作区重塑成一眼惊艳、干净利落的知识星图。

        严格执行以下四项原则：
        1. **果断清理无意义文档（deletes）**：
           - 凡是 scratch=true 且**实质没有干任何事情**的文档（如：只写了标题或空提纲没有正文、空白模板、仅有占位词/日期/半截未展开的随手念头、无意义测试/乱敲、或内容已完全被另一篇主文档涵盖的极短碎片），果断放入 `deletes`，并给出 4-12 字清晰理由（如 `"仅标题无正文"`、`"空白模板"`、`"未展开的临时占位"`）。
           - **红线**：严禁删除 scratch=false（本地磁盘文件），严禁删除包含真实方案、代码、数据指标、排查结论、会议纪要或完整待办的有效文档。
        2. **深度语义与同事项合并（merges）**：
           - 看透表面标题差异（包括随机趣名如「啃瓜的小浣熊」）：只要多篇 scratch=true 文档**内部实际在推进同一件事、同一个项目迭代、同一个问题排查或同一份方案的多个草稿**，必须果断合并为 1 篇，并给出去掉版本号、直击主题的清晰标题（如 `"CotEditor 星图演进路线图"`、`"AIME r533 重评与聚类回写"`）。
           - 单组合并 2-6 篇；严禁合并不同项目、不同日期的独立周报/例会纪要、或两篇 scratch=false 的独立磁盘文件。
        3. **按“内部真正在做的事情”划分工作主线（assignments）**：
           - **绝对禁止**偷懒把所有文档塞进“工程与开发 / 方案与会议 / 日常随记”这类空泛词；请直接从文档内容中提炼出 **2-\(targetMaxGroups) 个真实的工作主线/项目分组名**（2-7 字，如 `"CotEditor 研发"`、`"AIME 评测"`、`"权限与架构"`、`"周报与排期"`），让用户一眼看清自己最近在做哪几条主线。
           - 归组以**正文真实做的事情与核心项目实体**为第一依据，绝不被局部举例词带偏；同一项目主线的文档必须收拢到同一组，避免 1 篇孤立小组。
           - \(existingHint)\(bloatedHint)
        4. **智能重命名**：
           - 所有 untitled=true，以及标题过于敷衍/泛化（如 `"笔记1"`、`"方案"`、`"文档"`、`"想法"`）或与正文严重不符的 scratch=true 文档，必须在 `suggestedTitle` 中给出 4-18 字直白精准的中文标题（不含 Markdown 符号）。标题已经清晰准确的文档，`suggestedTitle` 填 `null`。

        仅输出严格合法 JSON，不要输出任何额外文字或解释：
        {"deletes":[{"id":"无效文档id","reason":"简短清理理由"}],"merges":[{"primaryId":"主文档id","mergeIds":["被并入id"],"mergedTitle":"合并后清晰标题","group":"工作主线分组名","reason":"简短合并理由"}],"assignments":[{"id":"保留文档id","group":"工作主线分组名","suggestedTitle":"需要改名时填新标题，否则null"}]}
        约束：每个文档 id 仅归属 `deletes`、`merges[].mergeIds` 或 `assignments` 之一；`merges[].primaryId` 必须出现在 `assignments` 中且与合并结果一致。
        """
        let userPrompt = "工作区待整理文档（共 \(shard.count) 篇，已附正文采样与结构统计）：\n\n\(manifestLines)"
        
        var architectConfig = AIBotStore.shared.resolvedConfiguration(for: .organizeAndMerge, baseConfig: .current)
        if architectConfig.reasoningEffort == nil || architectConfig.reasoningEffort == "low" {
            architectConfig.reasoningEffort = "medium"
        }
        
        do {
            let raw = try await AIService.shared.chat(
                [.system(systemPrompt), .user(userPrompt)],
                configuration: architectConfig,
                disablesThinking: false,
                maxOutputTokens: 4096,
                timeoutInterval: 90,
                analyticsFeature: analyticsFeature
            )
            if let parsed = DocumentCenterAgentOrganizer.parsePlan(from: raw, validIDs: validIDs) {
                let absorbed = Set(parsed.merges.flatMap(\.mergeIds))
                let deleted = Set(parsed.deletes.map(\.id))
                let covered = Set(parsed.assignments.map(\.id)).union(absorbed).union(deleted)
                let missed = shard.filter { !covered.contains($0.id) }
                if missed.isEmpty {
                    return (parsed.assignments, parsed.merges, parsed.deletes, true)
                }
                let patch = DocumentCenterAgentOrganizer.buildLocalFallbackPlan(
                    items: missed,
                    existingGroups: healthyExistingGroups
                ).assignments
                return (parsed.assignments + patch, parsed.merges, parsed.deletes, true)
            }
        } catch {
            CotLogger.shared.error(category: .ai, "Shard organize fallback (\(shardIndex + 1)/\(totalShards))", error: error)
        }
        
        let fallback = DocumentCenterAgentOrganizer.buildLocalFallbackPlan(
            items: shard,
            existingGroups: healthyExistingGroups
        )
        return (fallback.assignments, [], [], false)
    }
    
    
    /// Stage 3.5: Runs parallel AI lossless synthesis for multi-doc semantic/series merge clusters,
    /// protected by a strict deterministic factual-retention verifier (`validateSynthesizedContent`).
    @MainActor
    private static func synthesizeMergedClustersWithAI(
        _ funnel: OrganizeFunnelStageResult,
        analyticsFeature: String,
        onProgress: (@MainActor (OrganizeFunnelProgress) -> Void)?
    ) async -> OrganizeFunnelStageResult {
        let eligibleIndices: [Int] = funnel.mergeClusters.indices.filter { idx in
            let c = funnel.mergeClusters[idx]
            return c.primary.filePath == nil
                && !c.duplicates.isEmpty
                && c.reason != "内容完全重复"
                && c.mergedContent.count >= 120
                && c.mergedContent.count <= 24_000
        }
        guard !eligibleIndices.isEmpty else { return funnel }
        
        let total = eligibleIndices.count
        onProgress?(.synthesizingMerges(completed: 0, total: total))
        
        var synthConfig = AIBotStore.shared.resolvedConfiguration(for: .organizeAndMerge, baseConfig: .current)
        synthConfig.reasoningEffort = "low"
        
        var updatedClusters = funnel.mergeClusters
        var synthesizedByPrimaryID: [String: String] = [:]
        var completed = 0
        let concurrency = min(3, total)
        
        await withTaskGroup(of: (Int, String?).self) { group in
            var nextPos = 0
            func enqueue() {
                guard nextPos < total, !Task.isCancelled else { return }
                let clusterIdx = eligibleIndices[nextPos]
                let cluster = funnel.mergeClusters[clusterIdx]
                nextPos += 1
                group.addTask {
                    let result = await Self.synthesizeSingleCluster(
                        cluster,
                        configuration: synthConfig,
                        analyticsFeature: analyticsFeature
                    )
                    return (clusterIdx, result)
                }
            }
            for _ in 0..<concurrency { enqueue() }
            while let (clusterIdx, synthesized) = await group.next() {
                if let synthesized {
                    let old = updatedClusters[clusterIdx]
                    updatedClusters[clusterIdx] = OrganizeMergeCluster(
                        primary: old.primary,
                        duplicates: old.duplicates,
                        mergedContent: synthesized,
                        bestGroup: old.bestGroup,
                        bestTitle: old.bestTitle,
                        reason: old.reason
                    )
                    synthesizedByPrimaryID[old.primary.id] = synthesized
                }
                completed += 1
                onProgress?(.synthesizingMerges(completed: completed, total: total))
                enqueue()
            }
        }
        
        guard !synthesizedByPrimaryID.isEmpty else { return funnel }
        let updatedSurvivors = funnel.survivors.map { item -> OrganizeFunnelInput in
            guard let newContent = synthesizedByPrimaryID[item.id] else { return item }
            return OrganizeFunnelInput(
                id: item.id,
                dbRecordID: item.dbRecordID,
                title: item.title,
                filePath: item.filePath,
                syntax: item.syntax,
                currentGroup: item.currentGroup,
                content: newContent,
                updatedAt: item.updatedAt,
                isOpenNow: item.isOpenNow,
                isUntitled: item.isUntitled
            )
        }
        return OrganizeFunnelStageResult(
            junkToDelete: funnel.junkToDelete,
            mergeClusters: updatedClusters,
            survivors: updatedSurvivors
        )
    }
    
    
    @MainActor
    private static func synthesizeSingleCluster(
        _ cluster: OrganizeMergeCluster,
        configuration: AIConfiguration,
        analyticsFeature: String
    ) async -> String? {
        let allSources = ([cluster.primary] + cluster.duplicates).sorted { $0.updatedAt < $1.updatedAt }
        let sourceBlocks = allSources.enumerated().map { idx, doc in
            let header = doc.isUntitled ? "草稿 \(idx + 1)" : doc.title
            return "=== 文档 \(idx + 1)：\(header) ===\n\(doc.content)"
        }.joined(separator: "\n\n")
        
        let systemPrompt = """
        你是专业文档无损整合编辑。请将多份关于同一主题的草稿/迭代文档，融合成一份**结构清晰、零重复、可直接阅读**的精炼主文档。
        铁律：
        1. **严格无损保留事实**：原样保留所有具体数字、指标、版本号、文件路径、命令、代码块、URL、人名、日期与结论，严禁编造或悄悄删掉有效细节。
        2. **智能去重与演进收敛**：删除重复段落和冗余措辞；若同一事项在较新文档中有更新进展，以较新状态为主线并保留必要历史上下文。
        3. **清爽排版**：使用简洁自然的标题与条目结构，直接输出整合后的正文，不要输出任何“以下是合并结果”之类的开场白或结束语。
        """
        let userPrompt = "合并目标标题：\(cluster.bestTitle)\n合并原因：\(cluster.reason)\n\n\(sourceBlocks)"
        
        do {
            let raw = try await AIService.shared.chat(
                [.system(systemPrompt), .user(userPrompt)],
                configuration: configuration,
                disablesThinking: true,
                maxOutputTokens: 4096,
                timeoutInterval: 45,
                analyticsFeature: "\(analyticsFeature).synthesize"
            )
            return OrganizeDocumentAnalyzer.validateSynthesizedContent(raw, localBaseline: cluster.mergedContent)
        } catch {
            return nil
        }
    }
    
    
    // MARK: Private Normalization & Similarity Helpers
    
    private static func isBetterPrimary(_ lhs: OrganizeFunnelInput, _ rhs: OrganizeFunnelInput) -> Bool {
        if (lhs.filePath != nil) != (rhs.filePath != nil) {
            return lhs.filePath != nil
        }
        if lhs.isUntitled != rhs.isUntitled {
            return !lhs.isUntitled
        }
        let lenL = lhs.content.trimmingCharacters(in: .whitespacesAndNewlines).count
        let lenR = rhs.content.trimmingCharacters(in: .whitespacesAndNewlines).count
        if lenL != lenR {
            return lenL > lenR
        }
        if lhs.updatedAt != rhs.updatedAt {
            return lhs.updatedAt > rhs.updatedAt
        }
        if lhs.isOpenNow != rhs.isOpenNow {
            return lhs.isOpenNow
        }
        return lhs.id < rhs.id
    }
    
    
    static func normalizeMeaningfulTitle(_ title: String, isUntitled: Bool) -> String? {
        guard !isUntitled else { return nil }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let range = NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)
        let stripped = Self.copySuffixRegex
            .stringByReplacingMatches(in: trimmed, range: range, withTemplate: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard stripped.count >= 2 else { return nil }
        if DocumentCenterAgentOrganizer.isGenericUntitled(stripped, hasFilePath: false) {
            return nil
        }
        return stripped
    }
    
    
    private static func normalizeBody(_ text: String) -> String {
        text.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .lowercased()
    }
    
    
    private static func stripPunctuationAndSpace(_ text: String) -> String {
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return Self.nonWordPunctRegex.stringByReplacingMatches(in: text, range: range, withTemplate: "")
    }
    
    
    private static func splitParagraphs(_ text: String) -> [String] {
        text.replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
    
    
    private static func charShingles(_ normalizedText: String, size: Int) -> Set<String> {
        let compact = String(normalizedText.prefix(2_000)).filter { !$0.isWhitespace }
        let chars = Array(compact)
        guard chars.count >= size else {
            return compact.isEmpty ? [] : [compact]
        }
        var set = Set<String>()
        set.reserveCapacity(min(chars.count, 512))
        let strideStep = chars.count > 600 ? 2 : 1
        var idx = 0
        while idx + size <= chars.count {
            set.insert(String(chars[idx..<(idx + size)]))
            idx += strideStep
        }
        return set
    }
    
    
    private static func jaccardSimilarity(_ a: Set<String>, _ b: Set<String>) -> Double {
        let smaller = a.count <= b.count ? a : b
        let larger = a.count <= b.count ? b : a
        var intersection = 0
        for item in smaller where larger.contains(item) {
            intersection += 1
        }
        let union = a.count + b.count - intersection
        return union > 0 ? Double(intersection) / Double(union) : 0.0
    }
}
