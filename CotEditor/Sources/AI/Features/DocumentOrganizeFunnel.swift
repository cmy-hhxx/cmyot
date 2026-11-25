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
    case meaninglessTest
    case keyboardSmash
    case garbled
    
    var label: String {
        switch self {
            case .empty: "空白文档"
            case .meaninglessTest: "无效测试"
            case .keyboardSmash: "乱敲文本"
            case .garbled: "乱码内容"
        }
    }
}


nonisolated struct OrganizeJunkDecision: Sendable, Equatable {
    let item: OrganizeFunnelInput
    let reason: OrganizeJunkReason
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
    case consolidating
    
    var statusText: String {
        switch self {
            case .filteringJunk(let total):
                "漏斗清洗 \(total) 篇"
            case .mergingDuplicates(let remaining, let junk):
                junk > 0 ? "已筛 \(junk) 篇 · 去重合并 \(remaining) 篇" : "去重合并 \(remaining) 篇"
            case .shardedOrganizing(let done, let total, _):
                "分片整理 \(done)/\(total) 批"
            case .consolidating:
                "收敛星图分组"
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
    
    static let defaultShardSize = 14
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
    
    /// Classifies meaningless test documents, empty drafts, keyboard smashes, and garbled mojibake text.
    static func classifyJunk(title: String, content: String, filePath: String? = nil) -> OrganizeJunkReason? {
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
        
        // Never discard substantial real files/documents that passed the garbled check.
        if trimmed.count >= 120 {
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
            if let reason = Self.classifyJunk(title: item.title, content: item.content, filePath: item.filePath) {
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
            let mergedContent = Self.mergeContents(primary: primary.content, secondaries: duplicates.map(\.content))
            let bestGroup = ranked.first(where: { !$0.currentGroup.isEmpty })?.currentGroup ?? primary.currentGroup
            let bestTitle = ranked.first(where: { !$0.isUntitled })?.title ?? primary.title
            let reason = reasons[idx]
            
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
    
    
    /// Executes the complete 4-stage Data Funnel:
    /// 1) Local junk/gibberish deletion -> 2) Duplicate merging -> 3) Parallel sharded AI classification -> 4) Group convergence.
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
        let funnel = await Task.detached(priority: .userInitiated) {
            Self.runLocalFunnel(items: items)
        }.value
        
        onProgress?(.mergingDuplicates(
            remaining: funnel.survivors.count,
            junkDeleted: funnel.junkToDelete.count
        ))
        
        guard !funnel.survivors.isEmpty else {
            return OrganizeFullPlan(funnel: funnel, assignments: [], batchCount: 0, usedAI: false)
        }
        
        let agentInputs: [DocumentCenterAgentOrganizer.InputItem] = funnel.survivors.map { item in
            DocumentCenterAgentOrganizer.InputItem(
                id: item.id,
                title: item.title,
                syntax: item.syntax,
                currentGroup: item.currentGroup,
                excerpt: String(item.content.prefix(360)),
                isUntitled: item.isUntitled
            )
        }
        
        let shards = Self.makeShards(agentInputs, shardSize: shardSize)
        let totalBatches = shards.count
        let useAI = allowRemoteAI && AIService.shared.isConfigured
        
        if !useAI {
            let localPlan = DocumentCenterAgentOrganizer.buildLocalFallbackPlan(
                items: agentInputs,
                existingGroups: existingGroups
            )
            let consolidated = Self.consolidateAssignments(localPlan.assignments, existingGroups: existingGroups)
            return OrganizeFullPlan(
                funnel: funnel,
                assignments: consolidated,
                batchCount: totalBatches,
                usedAI: false
            )
        }
        
        onProgress?(.shardedOrganizing(completedBatches: 0, totalBatches: totalBatches, survivorCount: agentInputs.count))
        
        var orderedResults: [(index: Int, assignments: [DocumentCenterAgentOrganizer.Assignment], usedAI: Bool)] = []
        orderedResults.reserveCapacity(totalBatches)
        var completedBatches = 0
        let concurrencyLimit = max(1, min(maxConcurrency, totalBatches))
        
        await withTaskGroup(of: (Int, [DocumentCenterAgentOrganizer.Assignment], Bool).self) { group in
            var nextShardIndex = 0
            
            func enqueueNext() {
                guard nextShardIndex < totalBatches, !Task.isCancelled else { return }
                let idx = nextShardIndex
                let shard = shards[idx]
                nextShardIndex += 1
                group.addTask {
                    let outcome = await Self.organizeSingleShard(
                        shard,
                        existingGroups: existingGroups,
                        shardIndex: idx,
                        totalShards: totalBatches,
                        analyticsFeature: analyticsFeature
                    )
                    return (idx, outcome.assignments, outcome.usedAI)
                }
            }
            
            for _ in 0..<concurrencyLimit {
                enqueueNext()
            }
            
            while let result = await group.next() {
                orderedResults.append(result)
                completedBatches += 1
                onProgress?(.shardedOrganizing(
                    completedBatches: completedBatches,
                    totalBatches: totalBatches,
                    survivorCount: agentInputs.count
                ))
                enqueueNext()
            }
        }
        
        onProgress?(.consolidating)
        orderedResults.sort { $0.index < $1.index }
        let mergedAssignments = orderedResults.flatMap(\.assignments)
        let consolidated = Self.consolidateAssignments(mergedAssignments, existingGroups: existingGroups)
        let anyUsedAI = orderedResults.contains(where: \.usedAI)
        
        return OrganizeFullPlan(
            funnel: funnel,
            assignments: consolidated,
            batchCount: totalBatches,
            usedAI: anyUsedAI
        )
    }
    
    
    @MainActor
    private static func organizeSingleShard(
        _ shard: [DocumentCenterAgentOrganizer.InputItem],
        existingGroups: [String],
        shardIndex: Int,
        totalShards: Int,
        analyticsFeature: String
    ) async -> (assignments: [DocumentCenterAgentOrganizer.Assignment], usedAI: Bool) {
        let validIDs = Set(shard.map(\.id))
        let manifestLines = shard.enumerated().map { idx, item -> String in
            let snippet = DocumentCenterState.cleanExcerpt(from: item.excerpt, maxLength: 150)
            return "[\(idx + 1)] id=\"\(item.id)\" | title=\"\(item.title)\" | syntax=\"\(item.syntax)\" | group=\"\(item.currentGroup)\" | untitled=\(item.isUntitled ? "true" : "false") | snippet=\"\(snippet)\""
        }.joined(separator: "\n")
        
        let baseGroups = existingGroups.isEmpty
            ? ["项目方案", "技术笔记", "代码开发", "会议纪要", "工作清单", "配置数据", "日常记录"]
            : existingGroups
        let groupPalette = baseGroups.joined(separator: "、")
        
        let systemPrompt = """
        你是文档星图分片整理 Agent（第 \(shardIndex + 1)/\(totalShards) 批）。请高速、精准地为本批文档归类，并为未命名草稿提炼简短准确的中文标题。
        规则：
        1. 优先复用给定分组体系：\(groupPalette)（如需新增分组仅限 2-5 字中文名，保持克制）。
        2. 仅输出严格合法 JSON，禁止任何解释文字：{"assignments":[{"id":"原id","group":"分组名","suggestedTitle":"仅当untitled=true时填4-16字精准标题，否则null"}]}
        3. 本批每个 id 必须出现且仅出现一次。
        """
        let userPrompt = "本批待整理文档（\(shard.count) 篇）：\n\(manifestLines)"
        
        do {
            let raw = try await AIService.shared.chat(
                [.system(systemPrompt), .user(userPrompt)],
                analyticsFeature: analyticsFeature
            )
            if let parsed = DocumentCenterAgentOrganizer.parsePlan(from: raw, validIDs: validIDs) {
                // Fill any missed IDs in this shard deterministically so 100% of items are covered.
                let covered = Set(parsed.assignments.map(\.id))
                let missed = shard.filter { !covered.contains($0.id) }
                if missed.isEmpty {
                    return (parsed.assignments, true)
                }
                let patch = DocumentCenterAgentOrganizer.buildLocalFallbackPlan(
                    items: missed,
                    existingGroups: existingGroups
                ).assignments
                return (parsed.assignments + patch, true)
            }
        } catch {
            CotLogger.shared.error(category: .ai, "Shard organize fallback (\(shardIndex + 1)/\(totalShards))", error: error)
        }
        
        let fallback = DocumentCenterAgentOrganizer.buildLocalFallbackPlan(
            items: shard,
            existingGroups: existingGroups
        )
        return (fallback.assignments, false)
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
