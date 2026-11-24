//
//  PaneBoardModel.swift
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

/// Interactive modular board kinds that a pane tab can host instead of a plain text editor.
nonisolated enum PaneBoardKind: String, CaseIterable, Codable, Identifiable, Sendable {
    
    case market
    case podcast
    case news
    case butler
    
    var id: String { self.rawValue }
    
    var title: String {
        switch self {
            case .market: AppLanguage.text("股票看盘", en: "Markets")
            case .podcast: AppLanguage.text("播客", en: "Podcasts")
            case .news: "NEWS"
            case .butler: AppLanguage.text("总管对话", en: "Butler")
        }
    }
    
    var symbolName: String {
        switch self {
            case .market: "chart.xyaxis.line"
            case .podcast: "waveform"
            case .news: "newspaper"
            case .butler: "sparkles"
        }
    }
}


/// Chart time frame displayed inside the embedded Market board.
nonisolated enum MarketChartPeriod: String, CaseIterable, Codable, Identifiable, Sendable {
    
    case intraday
    case day
    case week
    case month
    
    var id: String { self.rawValue }
    
    var label: String {
        switch self {
            case .intraday: AppLanguage.text("分时", en: "1D")
            case .day: AppLanguage.text("日K", en: "Day")
            case .week: AppLanguage.text("周K", en: "Week")
            case .month: AppLanguage.text("月K", en: "Month")
        }
    }
}


/// Persistent state describing what a board tab displays so sessions restore seamlessly.
nonisolated struct PaneBoardState: Codable, Sendable, Equatable {
    
    var kind: PaneBoardKind
    var query: String = ""
    var selectedInstrumentID: String? = nil
    var marketPeriod: MarketChartPeriod = .day
    var topicChips: [String] = []
    var newsCategoryRaw: String? = nil
    var dynamicTitle: String? = nil
    var isAnalyzingIntent: Bool = false
    
    
    init(
        kind: PaneBoardKind,
        query: String = "",
        selectedInstrumentID: String? = nil,
        marketPeriod: MarketChartPeriod = .day,
        topicChips: [String] = [],
        newsCategoryRaw: String? = nil,
        dynamicTitle: String? = nil,
        isAnalyzingIntent: Bool = false
    ) {
        self.kind = kind
        self.query = query
        self.selectedInstrumentID = selectedInstrumentID
        self.marketPeriod = marketPeriod
        self.topicChips = topicChips
        self.newsCategoryRaw = newsCategoryRaw
        self.dynamicTitle = dynamicTitle
        self.isAnalyzingIntent = isAnalyzingIntent
    }
}


/// Translates a pane document's text into an initial board configuration synchronously (<5 ms)
/// and refines it asynchronously with the Pi Agent + KYC memory layer when text is present.
@MainActor
enum PaneBoardIntentAnalyzer {
    
    struct RefinedIntent: Sendable, Equatable {
        var primaryQuery: String
        var additionalQueries: [String]
        var marketPeriod: MarketChartPeriod?
        var newsCategory: NewsFeedCategory?
        var kycDimension: KYCDimension?
        var kycTitle: String?
        var kycDetail: String?
    }
    
    
    /// Synchronous zero-latency local extraction so boards start loading immediately on conversion.
    static func initialState(for kind: PaneBoardKind, text: String) -> PaneBoardState {
        
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return PaneBoardState(kind: kind)
        }
        
        let firstNonEmptyLine = trimmed
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty } ?? trimmed
        
        switch kind {
            case .market:
                let resolved = MarketAliasCatalog.resolve(trimmed) ?? MarketAliasCatalog.resolve(firstNonEmptyLine)
                let query = resolved?.name ?? String(firstNonEmptyLine.prefix(24))
                let chips = Self.extractCandidateTokens(from: trimmed, maxCount: 4)
                return PaneBoardState(
                    kind: .market,
                    query: resolved?.symbol ?? query,
                    selectedInstrumentID: resolved?.instrumentID,
                    marketPeriod: .day,
                    topicChips: chips,
                    dynamicTitle: resolved?.name ?? (query.count <= 14 ? query : nil),
                    isAnalyzingIntent: AIService.shared.isConfigured
                )
                
            case .podcast:
                if let url = Self.extractFirstURL(in: trimmed) {
                    return PaneBoardState(
                        kind: .podcast,
                        query: url.absoluteString,
                        topicChips: [],
                        dynamicTitle: nil,
                        isAnalyzingIntent: false
                    )
                }
                let query = Self.condenseSearchQuery(from: trimmed)
                let chips = Self.extractCandidateTokens(from: trimmed, maxCount: 4)
                return PaneBoardState(
                    kind: .podcast,
                    query: query,
                    topicChips: chips.isEmpty ? [query] : chips,
                    dynamicTitle: query.count <= 14 ? query : nil,
                    isAnalyzingIntent: AIService.shared.isConfigured
                )
                
            case .news:
                let lower = trimmed.lowercased()
                let category: NewsFeedCategory = if lower.contains("x") || lower.contains("twitter") || lower.contains("马斯克") || lower.contains("推文") {
                    .xSocial
                } else if lower.contains("股") || lower.contains("恒生") || lower.contains("a股") || lower.contains("金融") || lower.contains("财报") || lower.contains("fed") || lower.contains("nasdaq") {
                    .finance
                } else if lower.contains("ai") || lower.contains("llm") || lower.contains("agent") || lower.contains("模型") || lower.contains("claude") || lower.contains("gpt") {
                    .ai
                } else {
                    .all
                }
                let query = Self.condenseSearchQuery(from: trimmed)
                return PaneBoardState(
                    kind: .news,
                    query: trimmed.count <= 32 ? query : "",
                    newsCategoryRaw: category.rawValue,
                    dynamicTitle: category == .all ? nil : category.label,
                    isAnalyzingIntent: AIService.shared.isConfigured && trimmed.count > 16
                )
                
            case .butler:
                return PaneBoardState(
                    kind: .butler,
                    query: String(trimmed.prefix(240)),
                    dynamicTitle: AppLanguage.text("总管对话", en: "Butler"),
                    isAnalyzingIntent: false
                )
        }
    }
    
    
    /// Uses `AIService` / Pi Agent to interpret nuanced text (e.g. confusion/reflections -> podcast keywords,
    /// investment notes -> ticker symbol, reading notes -> news filter) and updates KYC memory.
    static func refineWithPiAgent(kind: PaneBoardKind, documentText: String) async -> RefinedIntent? {
        
        let trimmed = documentText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, AIService.shared.isConfigured else { return nil }
        
        let excerpt = String(trimmed.prefix(1800))
        let kycContext = CotMemoryStore.shared.compiledKYCContext(maxMemories: 8)
        
        let schemaHint: String = switch kind {
            case .market:
                """
                {"primarySymbolQuery":"标的名称或代码（如 恒生科技 / 00700 / NVDA / 600519）","additionalQueries":["备用关联标的"],"period":"day|intraday|week|month","kycTitle":"简短兴趣点（<=14字）","kycDetail":"一句话背景"}
                """
            case .podcast:
                """
                {"searchQueries":["核心中文播客搜索词（2-4字）","延伸心理或成长关键词","相关人物或话题"],"kycTitle":"用户关注或困惑主题（<=14字）","kycDetail":"一句话背景"}
                """
            case .news:
                """
                {"category":"all|finance|xSocial|ai","searchQuery":"精简筛选词（可空）","kycTitle":"信息兴趣标签（<=14字）","kycDetail":"一句话背景"}
                """
            case .butler:
                ""
        }
        if kind == .butler { return nil }
        
        let systemPrompt = """
        你是 CotEditor 的轻量意图路由内核。根据用户当前窗格里的内容和已有记忆画像，把文档转换成最贴合目标看板的查询参数。
        只输出严格合法的 JSON，不要代码块，不要任何多余解释。
        \(kycContext)
        """
        let userPrompt = """
        目标看板：\(kind.rawValue)
        输出格式：\(schemaHint)

        文档内容：
        \(excerpt)
        """
        
        do {
            let raw = try await AIService.shared.chat(
                [.system(systemPrompt), .user(userPrompt)],
                analyticsFeature: "boardConvert.\(kind.rawValue)"
            )
            return Self.parseIntentJSON(raw, kind: kind)
        } catch {
            return nil
        }
    }
    
    
    static func parseIntentJSON(_ raw: String, kind: PaneBoardKind) -> RefinedIntent? {
        
        var cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("```") {
            var lines = cleaned.components(separatedBy: .newlines)
            if lines.first?.hasPrefix("```") == true { lines.removeFirst() }
            if lines.last?.trimmingCharacters(in: .whitespaces) == "```" { lines.removeLast() }
            cleaned = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard let start = cleaned.firstIndex(of: "{"),
              let end = cleaned.lastIndex(of: "}"),
              start <= end,
              let data = String(cleaned[start...end]).data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        
        let kycTitle = (obj["kycTitle"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let kycDetail = (obj["kycDetail"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        
        switch kind {
            case .market:
                let primary = ((obj["primarySymbolQuery"] as? String) ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let extra = (obj["additionalQueries"] as? [String] ?? [])
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                let period = (obj["period"] as? String).flatMap(MarketChartPeriod.init(rawValue:))
                guard !primary.isEmpty || !extra.isEmpty else { return nil }
                return RefinedIntent(
                    primaryQuery: primary.isEmpty ? (extra.first ?? "") : primary,
                    additionalQueries: extra,
                    marketPeriod: period,
                    newsCategory: nil,
                    kycDimension: .finance,
                    kycTitle: kycTitle,
                    kycDetail: kycDetail
                )
                
            case .podcast:
                let queries = (obj["searchQueries"] as? [String] ?? [])
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                let fallback = ((obj["searchQuery"] as? String) ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let all = queries.isEmpty ? (fallback.isEmpty ? [] : [fallback]) : queries
                guard let first = all.first else { return nil }
                return RefinedIntent(
                    primaryQuery: first,
                    additionalQueries: all,
                    marketPeriod: nil,
                    newsCategory: nil,
                    kycDimension: .goals,
                    kycTitle: kycTitle,
                    kycDetail: kycDetail
                )
                
            case .news:
                let catRaw = (obj["category"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                let cat = catRaw.flatMap(NewsFeedCategory.init(rawValue:))
                let query = ((obj["searchQuery"] as? String) ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return RefinedIntent(
                    primaryQuery: query,
                    additionalQueries: [],
                    marketPeriod: nil,
                    newsCategory: cat,
                    kycDimension: .informationDiet,
                    kycTitle: kycTitle,
                    kycDetail: kycDetail
                )
                
            case .butler:
                return nil
        }
    }
    
    
    // MARK: Helpers
    
    private static func extractFirstURL(in text: String) -> URL? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return nil
        }
        let range = NSRange(location: 0, length: (text as NSString).length)
        return detector.firstMatch(in: text, options: [], range: range)?.url
    }
    
    
    private static func condenseSearchQuery(from text: String) -> String {
        let cleaned = text
            .replacingOccurrences(of: #"[#>*`\[\]()【】「」，。！？、：；,\.!?\n\r]+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.count <= 22 {
            return cleaned
        }
        return String(cleaned.prefix(22)).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    
    private static func extractCandidateTokens(from text: String, maxCount: Int) -> [String] {
        let parts = text
            .components(separatedBy: CharacterSet(charactersIn: "\n,，、;；|｜/"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0.count <= 18 }
        var seen = Set<String>()
        var result: [String] = []
        for part in parts where seen.insert(part).inserted {
            result.append(part)
            if result.count >= maxCount { break }
        }
        return result
    }
}
