//
//  CotStickerModels.swift
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

/// Structured sticker categories matching local meme packs and user uploads.
nonisolated enum StickerCategory: String, CaseIterable, Codable, Identifiable, Sendable {
    
    case deepseek
    case claude
    case openai
    case gemini
    case cat
    case dog
    case baoman
    case reaction
    case custom
    
    var id: String { self.rawValue }
    
    var displayName: String {
        switch self {
            case .deepseek: "DeepSeek"
            case .claude: "Claude"
            case .openai: "GPT"
            case .gemini: "Gemini"
            case .cat: "猫 meme"
            case .dog: "狗 meme"
            case .baoman: "暴漫"
            case .reaction: "表态"
            case .custom: "自定义"
        }
    }
    
    var defaultMoods: [String] {
        switch self {
            case .deepseek: ["开心", "摸鱼", "认真"]
            case .claude: ["平静", "专注", "暖心"]
            case .openai: ["开心", "兴奋", "专注"]
            case .gemini: ["兴奋", "开心", "平静"]
            case .cat: ["摸鱼", "无语", "委屈", "开心"]
            case .dog: ["开心", "委屈", "摸鱼"]
            case .baoman: ["无语", "兴奋", "委屈"]
            case .reaction: ["无语", "开心", "平静"]
            case .custom: ["开心", "平静"]
        }
    }
    
    static func normalize(_ raw: String) -> String {
        let lower = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if lower.contains("deepseek") { return StickerCategory.deepseek.rawValue }
        if lower.contains("claude") { return StickerCategory.claude.rawValue }
        if lower.contains("openai") || lower.contains("gpt") { return StickerCategory.openai.rawValue }
        if lower.contains("gemini") { return StickerCategory.gemini.rawValue }
        if lower.contains("cat") || lower.contains("猫") { return StickerCategory.cat.rawValue }
        if lower.contains("dog") || lower.contains("狗") { return StickerCategory.dog.rawValue }
        if lower.contains("baoman") || lower.contains("暴漫") || lower.contains("熊猫") { return StickerCategory.baoman.rawValue }
        if lower.contains("reaction") || lower.contains("表态") { return StickerCategory.reaction.rawValue }
        if let exact = Self(rawValue: lower) { return exact.rawValue }
        return StickerCategory.custom.rawValue
    }
}


/// A structured meme/sticker asset managed in the local Media Library and SQLite index.
nonisolated struct StickerAsset: Identifiable, Codable, Equatable, Sendable, Hashable {
    
    var id: String
    /// Relative path inside `<MediaLibrary>/stickers/`, e.g. `cat/cat_001.gif`.
    var fileName: String
    var category: String
    var format: String
    var width: Int
    var height: Int
    var bytes: Int
    var sha256: String
    var ocrText: String
    var meaning: String
    var moods: [String]
    var tags: [String]
    var sourceSite: String
    var sourceURL: String
    var isFavorite: Bool
    var useCount: Int
    var lastUsedAt: Double?
    var createdAt: Double
    
    var isAnimated: Bool {
        self.format.lowercased() == "gif"
    }
    
    var searchableSummary: String {
        let primary = !self.meaning.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? self.meaning
            : self.ocrText
        let clean = primary
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !clean.isEmpty {
            return String(clean.prefix(48))
        }
        return StickerCategory(rawValue: self.category)?.displayName ?? self.category
    }
    
    var promptDescription: String {
        var parts: [String] = []
        let catName = StickerCategory(rawValue: self.category)?.displayName ?? self.category
        parts.append("分类:\(catName)")
        let ocr = self.ocrText.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        if !ocr.isEmpty {
            parts.append("文字:\(String(ocr.prefix(36)))")
        }
        let mean = self.meaning.trimmingCharacters(in: .whitespacesAndNewlines)
        if !mean.isEmpty {
            parts.append("含义:\(String(mean.prefix(36)))")
        }
        if !self.moods.isEmpty {
            parts.append("情绪:\(self.moods.prefix(3).joined(separator: "/"))")
        }
        return parts.joined(separator: " | ")
    }
}


nonisolated struct StickerImportResult: Equatable, Sendable {
    var addedCount: Int = 0
    var skippedDuplicates: Int = 0
    var failedCount: Int = 0
    var firstAddedID: String? = nil
    
    var summaryText: String {
        var parts: [String] = []
        if self.addedCount > 0 {
            parts.append(AppLanguage.text("新增 \(self.addedCount) 张表情", en: "Added \(self.addedCount) stickers"))
        }
        if self.skippedDuplicates > 0 {
            parts.append(AppLanguage.text("跳过 \(self.skippedDuplicates) 张重复", en: "\(self.skippedDuplicates) duplicates skipped"))
        }
        if self.failedCount > 0 {
            parts.append(AppLanguage.text("\(self.failedCount) 张无法解析", en: "\(self.failedCount) failed"))
        }
        if parts.isEmpty {
            return AppLanguage.text("未发现可导入的表情包", en: "No supported stickers found")
        }
        return parts.joined(separator: " · ")
    }
}


/// Pure deterministic semantic search and keyword-to-mood tagging for stickers.
nonisolated enum StickerSearchEngine {
    
    private static let moodKeywordRules: [(mood: String, keywords: [String])] = [
        ("开心", ["开心", "哈哈", "笑", "nice", "good", "棒", "爽", "快乐", "耶", "赞", "喜欢", "爱", "可爱", "冲"]),
        ("兴奋", ["冲", "牛", "厉害", "起飞", "震惊", "卧槽", "绝了", "稳", "太强", "nb", "666"]),
        ("无语", ["无语", "汗", "裂开", "服了", "啊？", "什么", "离谱", "不懂", "呆", "沉默", "算了", "?", "？"]),
        ("委屈", ["哭", "泪", "难受", "委屈", "求", "救命", "崩", "累", "痛", "困", "惨", "寄"]),
        ("摸鱼", ["摸鱼", "躺", "睡", "困", "下班", "咖啡", "摸", "发呆", "摆烂", "算了"]),
        ("专注", ["思考", "想", "研究", "看", "写", "代码", "工作", "盯", "查", "认真", "学习"]),
        ("平静", ["好", "行", "ok", "嗯", "收到", "明白", "喝茶", "淡定"]),
    ]
    
    
    static func inferMoodsAndTags(category: String, ocrText: String, meaning: String) -> (moods: [String], tags: [String]) {
        let normalizedCat = StickerCategory.normalize(category)
        let combined = "\(ocrText) \(meaning)".lowercased()
        
        var moods: [String] = []
        for rule in Self.moodKeywordRules {
            if rule.keywords.contains(where: { combined.contains($0) }) {
                moods.append(rule.mood)
            }
        }
        if moods.isEmpty {
            moods = StickerCategory(rawValue: normalizedCat)?.defaultMoods ?? ["平静"]
        }
        
        var tags: [String] = []
        if let catTitle = StickerCategory(rawValue: normalizedCat)?.displayName {
            tags.append(catTitle)
        }
        let tokens = combined
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.count >= 2 && $0.count <= 14 }
        for token in tokens.prefix(8) where !tags.contains(token) {
            tags.append(token)
        }
        if !ocrText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            for line in ocrText.components(separatedBy: .newlines) {
                let clean = line.trimmingCharacters(in: .whitespacesAndNewlines)
                if clean.count >= 2 && clean.count <= 16 && !tags.contains(clean) {
                    tags.append(clean)
                    if tags.count >= 10 { break }
                }
            }
        }
        return (Array(moods.prefix(4)), Array(tags.prefix(10)))
    }
    
    
    static func search(
        _ stickers: [StickerAsset],
        query: String,
        mood: String? = nil,
        preferredCategories: [String] = [],
        onlyFavorites: Bool = false,
        categoryFilter: String? = nil,
        limit: Int = 12
    ) -> [StickerAsset] {
        let cleanQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let queryTerms = Self.tokenize(cleanQuery)
        let cleanMood = mood?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        let prefSet = Set(preferredCategories.map { StickerCategory.normalize($0) })
        let catFilter = categoryFilter.map { StickerCategory.normalize($0) }
        
        let filtered = stickers.filter { item in
            if onlyFavorites && !item.isFavorite { return false }
            if let catFilter, item.category != catFilter { return false }
            return true
        }
        
        if queryTerms.isEmpty && cleanMood.isEmpty && prefSet.isEmpty {
            return Array(filtered.sorted { lhs, rhs in
                if lhs.isFavorite != rhs.isFavorite { return lhs.isFavorite }
                if lhs.useCount != rhs.useCount { return lhs.useCount > rhs.useCount }
                return lhs.createdAt > rhs.createdAt
            }.prefix(limit))
        }
        
        var scored: [(asset: StickerAsset, score: Double)] = []
        scored.reserveCapacity(filtered.count)
        
        for item in filtered {
            var score = 0.0
            let ocr = item.ocrText.lowercased()
            let mean = item.meaning.lowercased()
            let tagsJoined = item.tags.joined(separator: " ").lowercased()
            let moodsJoined = item.moods.joined(separator: " ").lowercased()
            let catLower = item.category.lowercased()
            
            for term in queryTerms {
                if ocr.contains(term) { score += 4.0 }
                if mean.contains(term) { score += 3.5 }
                if tagsJoined.contains(term) { score += 3.0 }
                if moodsJoined.contains(term) { score += 2.5 }
                if catLower.contains(term) { score += 1.5 }
            }
            
            if !cleanMood.isEmpty {
                if moodsJoined.contains(cleanMood) {
                    score += 3.2
                }
                if mean.contains(cleanMood) || ocr.contains(cleanMood) {
                    score += 1.5
                }
            }
            
            if !prefSet.isEmpty && prefSet.contains(item.category) {
                score += 1.4
            }
            
            // For AI selection queries, prioritize stickers that actually have readable semantics.
            if !ocr.isEmpty || !mean.isEmpty {
                score += 0.8
            }
            if item.isFavorite {
                score += 0.5
            }
            if item.useCount > 0 {
                score += min(1.0, Double(item.useCount) * 0.12)
            }
            
            if !queryTerms.isEmpty {
                // Keep at least semantic/mood hits when searching explicitly.
                if score > 0 {
                    scored.append((item, score))
                }
            } else {
                scored.append((item, score))
            }
        }
        
        if scored.isEmpty && !queryTerms.isEmpty && cleanQuery.count >= 2 {
            // Fall back to semantic stickers matching mood/preferred categories if exact terms didn't hit.
            return Array(filtered.filter { !$0.ocrText.isEmpty || !$0.meaning.isEmpty }.prefix(limit))
        }
        
        scored.sort { lhs, rhs in
            if abs(lhs.score - rhs.score) > 0.01 { return lhs.score > rhs.score }
            if lhs.asset.useCount != rhs.asset.useCount { return lhs.asset.useCount > rhs.asset.useCount }
            return lhs.asset.createdAt > rhs.asset.createdAt
        }
        return Array(scored.prefix(limit).map(\.asset))
    }
    
    
    /// Strict semantic search for AI replies: returns stickers ONLY when the query/topic
    /// genuinely matches a sticker's text, meaning, tags, or category (`conceptScore >= minConceptScore`).
    /// Returns `[]` when nothing in the library fits, preventing repetitive/unrelated sticker spam.
    static func searchRelevantForReply(
        _ stickers: [StickerAsset],
        query: String,
        mood: String? = nil,
        preferredCategories: [String] = [],
        limit: Int = 5,
        minConceptScore: Double = 3.0
    ) -> [StickerAsset] {
        let queryTerms = Self.tokenize(query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
        guard !queryTerms.isEmpty else { return [] }
        let cleanMood = mood?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        let prefSet = Set(preferredCategories.map { StickerCategory.normalize($0) })
        
        var scored: [(asset: StickerAsset, score: Double)] = []
        for item in stickers {
            let ocr = item.ocrText.lowercased()
            let mean = item.meaning.lowercased()
            let tagsJoined = item.tags.joined(separator: " ").lowercased()
            let moodsJoined = item.moods.joined(separator: " ").lowercased()
            let catLower = item.category.lowercased()
            guard !ocr.isEmpty || !mean.isEmpty || !tagsJoined.isEmpty else { continue }
            
            var conceptScore = 0.0
            for term in queryTerms {
                if ocr.contains(term) { conceptScore += 4.0 }
                if mean.contains(term) { conceptScore += 3.5 }
                if tagsJoined.contains(term) { conceptScore += 3.0 }
                if moodsJoined.contains(term) { conceptScore += 2.0 }
                if catLower.contains(term) { conceptScore += 1.5 }
            }
            guard conceptScore >= minConceptScore else { continue }
            
            var total = conceptScore
            if !cleanMood.isEmpty && moodsJoined.contains(cleanMood) { total += 1.5 }
            if !prefSet.isEmpty && prefSet.contains(item.category) { total += 1.0 }
            if item.isFavorite { total += 0.4 }
            total -= min(0.8, Double(item.useCount) * 0.1)
            scored.append((item, total))
        }
        scored.sort { lhs, rhs in
            if abs(lhs.score - rhs.score) > 0.01 { return lhs.score > rhs.score }
            return lhs.asset.createdAt > rhs.asset.createdAt
        }
        return Array(scored.prefix(limit).map(\.asset))
    }
    
    
    private static func tokenize(_ text: String) -> [String] {
        guard !text.isEmpty else { return [] }
        var parts = text
            .components(separatedBy: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if parts.isEmpty {
            parts = [text]
        }
        // Also add 2-char CJK bigrams for fuzzy Chinese phrase matching when a long phrase is passed.
        var expanded = parts
        for part in parts where part.count >= 3 {
            let chars = Array(part)
            for idx in 0..<(chars.count - 1) {
                let gram = String(chars[idx...(idx + 1)])
                if !expanded.contains(gram) {
                    expanded.append(gram)
                }
                if expanded.count >= 16 { break }
            }
            if expanded.count >= 16 { break }
        }
        return expanded
    }
}
