//
//  AINextTokenPredictor.swift
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
import Foundation
import StringUtils
import SyntaxFormat

/// User-facing cost/proactivity strategy for AI Next Token completion.
nonisolated enum AINextTokenStrategy: String, CaseIterable, Sendable {
    
    case smart = "smart"
    case proactive = "proactive"
}


/// Daily token-conservation ledger persisted locally.
nonisolated struct AINextTokenDailyStats: Codable, Equatable, Sendable {
    
    var dateKey: String
    var aiRequests: Int = 0
    var estimatedInputTokens: Int = 0
    var estimatedOutputTokens: Int = 0
    var localHits: Int = 0
    
    var totalEstimatedTokens: Int {
        
        self.estimatedInputTokens + self.estimatedOutputTokens
    }
}


/// Result of routing Next Token requests to the most cost-effective model.
nonisolated struct ModelRoutingResolution: Equatable, Sendable {
    
    var effectiveModel: String
    var baseModel: String
    var isAutoRouted: Bool
    var isReasoningBlocked: Bool
    var statusNote: String?
}


/// Tier-2 asynchronous Fill-in-the-Middle (FIM) Next Token predictor powered by the active AI endpoint.
///
/// Designed around zero-waste token discipline:
/// 1. Local habit / cross-tab predictions and 90s speculative cache run first at 0 Token cost;
/// 2. Heavy flagship or reasoning models automatically route to lightweight siblings (`deepseek-chat`, `gpt-4o-mini`, etc.);
/// 3. Sentence-end / URL / image / mid-word triggers are skipped, ignored suggestions back off automatically,
///    empty answers are negative-cached for 60s, and `Option + \` stays always available for on-demand completion.
@MainActor final class AINextTokenPredictor {
    
    static let shared = AINextTokenPredictor()
    
    static let statsDidChangeNotification = Notification.Name("AINextTokenPredictorStatsDidChange")
    
    enum CacheLookupResult: Equatable, Sendable {
        case hit(String)
        case knownEmpty
        case miss
    }
    
    enum TriggerDecision: Equatable, Sendable {
        case skip(reason: String)
        case schedule(delayMultiplier: Double)
    }
    
    private struct CacheEntry {
        let anchorLinePrefix: String
        let anchorLineSuffix: String
        let completion: String?
        let createdAt: Date
    }
    
    private var cache: [CacheEntry] = []
    private var pendingTask: Task<Void, Never>?
    private var errorCooldownUntil: Date?
    private var unavailableAutoRoutedModels: Set<String> = []
    private var cachedTodayStats: AINextTokenDailyStats?
    private(set) var consecutiveIgnores: Int = 0
    
    
    private init() {}
    
    
    // MARK: Settings Helpers
    
    static var isInlineCompletionEnabled: Bool {
        
        if let obj = UserDefaults.standard.object(forKey: CotLocalDatabase.ConfigKey.inlineCompletionEnabled) as? Bool {
            return obj
        }
        return CotLocalDatabase.shared.bool(forKey: CotLocalDatabase.ConfigKey.inlineCompletionEnabled, default: true)
    }
    
    
    static var isAINextTokenEnabled: Bool {
        
        if let obj = UserDefaults.standard.object(forKey: CotLocalDatabase.ConfigKey.aiNextTokenEnabled) as? Bool {
            return obj
        }
        return CotLocalDatabase.shared.bool(forKey: CotLocalDatabase.ConfigKey.aiNextTokenEnabled, default: true)
    }
    
    
    static var modelOverride: String {
        
        let raw = UserDefaults.standard.string(forKey: CotLocalDatabase.ConfigKey.aiNextTokenModelOverride)
            ?? CotLocalDatabase.shared.string(forKey: CotLocalDatabase.ConfigKey.aiNextTokenModelOverride, default: "")
        return raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    
    static var debounceMilliseconds: Int {
        
        let val = UserDefaults.standard.object(forKey: CotLocalDatabase.ConfigKey.aiNextTokenDebounceMs) as? Int
            ?? Int(CotLocalDatabase.shared.string(forKey: CotLocalDatabase.ConfigKey.aiNextTokenDebounceMs, default: "420"))
            ?? 420
        return min(1500, max(180, val))
    }
    
    
    static var strategy: AINextTokenStrategy {
        
        let raw = UserDefaults.standard.string(forKey: CotLocalDatabase.ConfigKey.aiNextTokenStrategy)
            ?? CotLocalDatabase.shared.string(forKey: CotLocalDatabase.ConfigKey.aiNextTokenStrategy, default: AINextTokenStrategy.smart.rawValue)
        return AINextTokenStrategy(rawValue: raw) ?? .smart
    }
    
    
    static var dailyCap: Int {
        
        if let val = UserDefaults.standard.object(forKey: CotLocalDatabase.ConfigKey.aiNextTokenDailyCap) as? Int {
            return max(0, val)
        }
        if let val = Int(CotLocalDatabase.shared.string(forKey: CotLocalDatabase.ConfigKey.aiNextTokenDailyCap, default: "300")) {
            return max(0, val)
        }
        return 300
    }
    
    
    static var effectiveConfiguration: AIConfiguration {
        
        let base = AIBotStore.shared.resolvedConfiguration(for: .ghost)
        let routing = Self.shared.resolveModelRouting(baseConfig: base)
        var config = base
        if !routing.effectiveModel.isEmpty {
            config.model = routing.effectiveModel
        }
        config.temperature = 0.10
        config.reasoningEffort = "low"
        return config
    }
    
    
    var effectiveBackoffMultiplier: Double {
        
        (Self.strategy == .smart && self.consecutiveIgnores >= 3) ? 1.8 : 1.0
    }
    
    
    var todayStats: AINextTokenDailyStats {
        
        let key = Self.currentDateKey()
        if let existing = self.cachedTodayStats, existing.dateKey == key {
            return existing
        }
        
        let raw = UserDefaults.standard.string(forKey: CotLocalDatabase.ConfigKey.aiNextTokenDailyStatsJSON)
            ?? CotLocalDatabase.shared.string(forKey: CotLocalDatabase.ConfigKey.aiNextTokenDailyStatsJSON, default: "")
        if !raw.isEmpty,
           let data = raw.data(using: .utf8),
           let decoded = try? JSONDecoder().decode(AINextTokenDailyStats.self, from: data),
           decoded.dateKey == key
        {
            self.cachedTodayStats = decoded
            return decoded
        }
        
        let fresh = AINextTokenDailyStats(dateKey: key)
        self.persistStats(fresh)
        return fresh
    }
    
    
    // MARK: Model Classification & Routing
    
    static func isPureReasoningModel(_ model: String) -> Bool {
        
        let m = model.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !m.isEmpty else { return false }
        
        if m.contains("reasoner")
            || m.contains("deepseek-r1")
            || m.contains("/r1")
            || m.contains("-r1")
            || m.contains("qwq")
            || m.contains("-thinking")
        {
            return true
        }
        
        return m.hasPrefix("o1") || m.hasPrefix("o3") || m.hasPrefix("o4")
    }
    
    
    static func isLightweightModel(_ model: String) -> Bool {
        
        guard !Self.isPureReasoningModel(model) else { return false }
        
        let m = model.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !m.isEmpty else { return false }
        
        let tokens = [
            "mini", "nano", "flash", "haiku", "turbo", "lite",
            "deepseek-chat", "moonshot-v1-8k", ":1.5b", ":3b", ":7b", ":8b",
        ]
        return tokens.contains { m.contains($0) }
    }
    
    
    static func isHeavyOrReasoningModel(_ model: String) -> Bool {
        
        if Self.isPureReasoningModel(model) { return true }
        if Self.isLightweightModel(model) { return false }
        
        let m = model.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !m.isEmpty else { return false }
        
        let heavyTokens = [
            "opus", "sonnet", "qwen-max", "yi-large",
            "gemini-2.5-pro", "gemini-1.5-pro",
            "gpt-4o", "gpt-4.1", "gpt-4.5", "gpt-5",
            "claude-4", "claude-5",
        ]
        return heavyTokens.contains { m.contains($0) }
    }
    
    
    func markAutoRoutedModelUnavailable(_ model: String, baseURL: String) {
        
        let normalizedURL = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedModel = model.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedModel.isEmpty else { return }
        self.unavailableAutoRoutedModels.insert("\(normalizedURL)|\(normalizedModel)")
    }
    
    
    func clearUnavailableModels() {
        
        self.unavailableAutoRoutedModels.removeAll()
    }
    
    
    func resolveModelRouting(
        profile: AIEndpointProfile? = AIEndpointStore.activeProfile,
        baseConfig: AIConfiguration = .current,
        explicitOverride: String = AINextTokenPredictor.modelOverride
    ) -> ModelRoutingResolution {
        
        let resolvedBase = baseConfig.resolvedBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let savedModels = profile?.savedModels ?? []
        let cleanOverride = explicitOverride.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if !cleanOverride.isEmpty,
           !self.unavailableAutoRoutedModels.contains("\(resolvedBase)|\(cleanOverride.lowercased())")
        {
            if !savedModels.isEmpty,
               !savedModels.contains(where: { $0.caseInsensitiveCompare(cleanOverride) == .orderedSame }),
               let vendorPrefixed = savedModels.first(where: {
                   $0.lowercased().hasSuffix("/" + cleanOverride.lowercased())
                   && !self.unavailableAutoRoutedModels.contains("\(resolvedBase)|\($0.lowercased())")
               })
            {
                return ModelRoutingResolution(
                    effectiveModel: vendorPrefixed,
                    baseModel: baseConfig.model,
                    isAutoRouted: true,
                    isReasoningBlocked: false,
                    statusNote: "已匹配当前端点模型 \(vendorPrefixed)"
                )
            }
            
            let note = Self.isPureReasoningModel(cleanOverride)
                ? "当前指定为推理模型，耗费思考 Token 且较慢，建议改用 flash / mini / chat 模型"
                : nil
            return ModelRoutingResolution(
                effectiveModel: cleanOverride,
                baseModel: baseConfig.model,
                isAutoRouted: cleanOverride.caseInsensitiveCompare(baseConfig.model) != .orderedSame,
                isReasoningBlocked: false,
                statusNote: note
            )
        }
        
        if baseConfig.endpoint == .ollama || !Self.isHeavyOrReasoningModel(baseConfig.model) {
            return ModelRoutingResolution(
                effectiveModel: baseConfig.model,
                baseModel: baseConfig.model,
                isAutoRouted: false,
                isReasoningBlocked: false,
                statusNote: nil
            )
        }
        
        let isAvailable: (String) -> Bool = { candidate in
            let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return false }
            guard trimmed.caseInsensitiveCompare(baseConfig.model) != .orderedSame else { return false }
            return !self.unavailableAutoRoutedModels.contains("\(resolvedBase)|\(trimmed.lowercased())")
        }
        
        // Priority 1: Pick a lightweight (or non-heavy) saved model from the active endpoint's fetched catalog.
        if let lightweightSaved = savedModels.first(where: { Self.isLightweightModel($0) && isAvailable($0) }) {
            return ModelRoutingResolution(
                effectiveModel: lightweightSaved,
                baseModel: baseConfig.model,
                isAutoRouted: true,
                isReasoningBlocked: false,
                statusNote: "已自动路由至轻量模型 \(lightweightSaved) 节省 Token"
            )
        }
        if let standardSaved = savedModels.first(where: {
            !Self.isHeavyOrReasoningModel($0) && !Self.isPureReasoningModel($0) && isAvailable($0)
        }) {
            return ModelRoutingResolution(
                effectiveModel: standardSaved,
                baseModel: baseConfig.model,
                isAutoRouted: true,
                isReasoningBlocked: false,
                statusNote: "已自动路由至轻量模型 \(standardSaved) 节省 Token"
            )
        }
        
        // Priority 2: Map known providers (including both OpenAI Responses & Chat endpoints) to economy siblings.
        let mappedModel = Self.economySiblingModel(for: baseConfig)
        
        if let mappedModel, isAvailable(mappedModel) {
            return ModelRoutingResolution(
                effectiveModel: mappedModel,
                baseModel: baseConfig.model,
                isAutoRouted: true,
                isReasoningBlocked: false,
                statusNote: "主模型较重，已自动省流路由至 \(mappedModel)"
            )
        }
        
        // Priority 3: Protect the user from wasting reasoning tokens automatically on custom gateways.
        if Self.isPureReasoningModel(baseConfig.model) {
            return ModelRoutingResolution(
                effectiveModel: baseConfig.model,
                baseModel: baseConfig.model,
                isAutoRouted: false,
                isReasoningBlocked: true,
                statusNote: "主模型为推理模型，自动续写已转为本地 0 成本模式（可指定轻量续写模型）"
            )
        }
        
        return ModelRoutingResolution(
            effectiveModel: baseConfig.model,
            baseModel: baseConfig.model,
            isAutoRouted: false,
            isReasoningBlocked: false,
            statusNote: nil
        )
    }
    
    
    // MARK: Stats & Backoff Accounting
    
    static func estimateTokens(in text: String) -> Int {
        
        guard !text.isEmpty else { return 0 }
        var score = 0.0
        for scalar in text.unicodeScalars {
            score += scalar.isASCII ? 0.25 : 0.68
        }
        return max(1, Int(ceil(score)))
    }
    
    
    func resetTodayStats() {
        
        self.persistStats(AINextTokenDailyStats(dateKey: Self.currentDateKey()))
    }
    
    
    func recordLocalHit() {
        
        var stats = self.todayStats
        stats.localHits += 1
        self.persistStats(stats)
    }
    
    
    func recordAIUsage(inputText: String, outputText: String) {
        
        var stats = self.todayStats
        stats.aiRequests += 1
        stats.estimatedInputTokens += Self.estimateTokens(in: inputText)
        stats.estimatedOutputTokens += Self.estimateTokens(in: outputText)
        self.persistStats(stats)
    }
    
    
    func recordSuggestionIgnored() {
        
        self.consecutiveIgnores = min(10, self.consecutiveIgnores + 1)
    }
    
    
    func recordSuggestionAccepted() {
        
        self.consecutiveIgnores = 0
    }
    
    
    // MARK: Cache Lookup
    
    func cancel() {
        
        self.pendingTask?.cancel()
        self.pendingTask = nil
    }
    
    
    /// Clears cached predictions and reloads daily stats after switching local users.
    func reloadForActiveUser() {
        
        self.cancel()
        self.cache.removeAll()
        self.errorCooldownUntil = nil
        self.consecutiveIgnores = 0
        self.cachedTodayStats = nil
        _ = self.todayStats
        NotificationCenter.default.post(name: Self.statsDidChangeNotification, object: nil)
    }
    
    
    /// Checks speculative positive cache (0ms type-through) and negative/empty cache (60s deduplication).
    func lookupCache(linePrefix: String, lineSuffix: String) -> CacheLookupResult {
        
        let now = Date()
        let cleanSuffix = lineSuffix.trimmingCharacters(in: .newlines)
        
        for entry in self.cache.reversed() {
            guard entry.anchorLineSuffix == cleanSuffix else { continue }
            
            if let completion = entry.completion {
                guard now.timeIntervalSince(entry.createdAt) < 90 else { continue }
                guard linePrefix.hasPrefix(entry.anchorLinePrefix) else { continue }
                
                let typedSinceAnchor = String(linePrefix.dropFirst(entry.anchorLinePrefix.count))
                if typedSinceAnchor.isEmpty {
                    return .hit(completion)
                }
                if completion.hasPrefix(typedSinceAnchor),
                   completion.count > typedSinceAnchor.count
                {
                    return .hit(String(completion.dropFirst(typedSinceAnchor.count)))
                }
            } else {
                guard now.timeIntervalSince(entry.createdAt) < 60 else { continue }
                if linePrefix == entry.anchorLinePrefix {
                    return .knownEmpty
                }
            }
        }
        return .miss
    }
    
    
    /// Convenience wrapper preserved for callers & tests checking only positive cache hits.
    func lookupCachedContinuation(linePrefix: String, lineSuffix: String) -> String? {
        
        if case .hit(let completion) = self.lookupCache(linePrefix: linePrefix, lineSuffix: lineSuffix) {
            return completion
        }
        return nil
    }
    
    
    // MARK: Context Classification & Compact Slicing
    
    /// Decides whether the current cursor position warrants an AI completion request, and at what cadence.
    static func evaluateTriggerIntent(
        linePrefix: String,
        lineSuffix: String,
        isCode: Bool,
        strategy: AINextTokenStrategy
    ) -> TriggerDecision {
        
        if let firstSuffixScalar = lineSuffix.unicodeScalars.first,
           CharacterSet.alphanumerics.contains(firstSuffixScalar) || firstSuffixScalar == "_"
        {
            return .skip(reason: "midWord")
        }
        
        // Respect Tab/space alignment and bare outline/list indentation contexts.
        if linePrefix.isEmpty || linePrefix.allSatisfy(\.isWhitespace) {
            return .skip(reason: "leadingIndent")
        }
        if linePrefix.hasSuffix("\t") || linePrefix.hasSuffix("  ") {
            return .skip(reason: "tabFormatting")
        }
        if linePrefix.range(of: #"^\s*(?:[-*+•‣▪︎>]|\d+[\.、\)）]|#{1,6})\s*$"#, options: .regularExpression) != nil {
            return .skip(reason: "listPrefix")
        }
        if !lineSuffix.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           linePrefix.last?.isWhitespace == true
        {
            return .skip(reason: "tabAlignment")
        }
        
        let trimmedPrefix = linePrefix.trimmingCharacters(in: .whitespaces)
        let hasNonASCII = trimmedPrefix.unicodeScalars.contains { !$0.isASCII }
        let minChars = isCode ? 3 : (hasNonASCII ? 2 : 4)
        guard trimmedPrefix.count >= minChars else {
            return .skip(reason: "tooShort")
        }
        
        if trimmedPrefix.contains("⟦🖼") {
            return .skip(reason: "inlineImage")
        }
        if let lastToken = trimmedPrefix.split(whereSeparator: \.isWhitespace).last?.lowercased(),
           lastToken.hasPrefix("http://") || lastToken.hasPrefix("https://")
        {
            return .skip(reason: "urlInput")
        }
        
        if let lastChar = trimmedPrefix.last {
            let isTerminator: Bool
            if isCode {
                isTerminator = lastChar == ";" || lastChar == "}"
            } else if lastChar == "." {
                // Keep numeric list numbering like `1.` eligible while skipping finished English sentences.
                let charBeforeDot = trimmedPrefix.dropLast().last
                let isListDigit = (charBeforeDot?.isASCII == true && charBeforeDot?.isWholeNumber == true)
                isTerminator = !isListDigit
            } else {
                isTerminator = ["。", "！", "？", "!", "?", "…"].contains(lastChar)
            }
            
            if isTerminator {
                return strategy == .smart
                    ? .skip(reason: "sentenceEnd")
                    : .schedule(delayMultiplier: 1.3)
            }
            
            let highIntentChars: Set<Character> = ["，", ",", "：", ":", "、", "(", "（", "=", ">"]
            if highIntentChars.contains(lastChar) || (linePrefix.hasSuffix(" ") && trimmedPrefix.count >= minChars) {
                return .schedule(delayMultiplier: 0.85)
            }
        }
        
        return .schedule(delayMultiplier: 1.0)
    }
    
    
    /// Extracts compact, line-aligned `<PREFIX>` and `<SUFFIX>` slices tailored to strategy & syntax.
    static func extractCompactContext(
        from nsText: NSString,
        caret: Int,
        isCode: Bool,
        strategy: AINextTokenStrategy
    ) -> (prefix: String, suffix: String) {
        
        let safeCaret = min(max(0, caret), nsText.length)
        let maxPrefix = strategy == .proactive ? (isCode ? 1400 : 1100) : (isCode ? 800 : 640)
        let maxSuffix = strategy == .proactive ? (isCode ? 320 : 280) : (isCode ? 240 : 200)
        
        let rawPrefixStart = max(0, safeCaret - maxPrefix)
        var prefix = nsText.substring(with: NSRange(location: rawPrefixStart, length: safeCaret - rawPrefixStart))
        if rawPrefixStart > 0,
           let firstNewline = prefix.firstIndex(of: "\n")
        {
            let headCount = prefix.distance(from: prefix.startIndex, to: firstNewline)
            let afterNewline = prefix.index(after: firstNewline)
            let remainingCount = prefix.distance(from: afterNewline, to: prefix.endIndex)
            if headCount < 72, remainingCount >= 80 {
                prefix = String(prefix[afterNewline...])
            }
        }
        
        let rawSuffixLength = min(maxSuffix, nsText.length - safeCaret)
        var suffix = rawSuffixLength > 0
            ? nsText.substring(with: NSRange(location: safeCaret, length: rawSuffixLength))
            : ""
        if safeCaret + rawSuffixLength < nsText.length,
           let lastNewline = suffix.lastIndex(of: "\n"),
           suffix.distance(from: suffix.startIndex, to: lastNewline) >= 40
        {
            suffix = String(suffix[..<lastNewline])
        }
        
        return (prefix, suffix)
    }
    
    
    // MARK: Scheduling
    
    /// Schedules a debounced AI Fill-in-the-Middle completion for `textView`.
    func schedulePrediction(
        for textView: EditorTextView,
        syntaxName: String = SyntaxName.none,
        documentTitle: String = ""
    ) {
        self.cancel()
        
        guard
            Self.isInlineCompletionEnabled,
            Self.isAINextTokenEnabled,
            textView.isEditable,
            textView.window?.isKeyWindow == true,
            !textView.hasMarkedText(),
            !textView.hasMultipleInsertions,
            textView.selectedRange.isEmpty
        else { return }
        
        if let cooldown = self.errorCooldownUntil, Date() < cooldown {
            return
        }
        
        let cap = Self.dailyCap
        if cap > 0, self.todayStats.aiRequests >= cap {
            return
        }
        
        let baseConfig = AIBotStore.shared.resolvedConfiguration(for: .ghost)
        let routing = self.resolveModelRouting(baseConfig: baseConfig)
        guard !routing.effectiveModel.isEmpty, !routing.isReasoningBlocked else { return }
        
        var effectiveConfig = baseConfig
        effectiveConfig.model = routing.effectiveModel
        effectiveConfig.temperature = 0.10
        effectiveConfig.reasoningEffort = "low"
        guard effectiveConfig.isUsable else { return }
        
        let nsText = textView.string as NSString
        let expectedRange = textView.selectedRange
        let expectedTextVersion = textView.ghostTextVersion
        let caret = expectedRange.location
        guard caret >= 0, caret <= nsText.length else { return }
        
        let lineRange = nsText.lineRange(for: NSRange(location: min(caret, max(0, nsText.length - 1)), length: 0))
        let linePrefix = nsText.substring(with: NSRange(location: lineRange.location, length: max(0, caret - lineRange.location)))
        let lineEnd = NSMaxRange(lineRange)
        let lineSuffix = (caret < lineEnd)
            ? nsText.substring(with: NSRange(location: caret, length: lineEnd - caret)).trimmingCharacters(in: .newlines)
            : ""
        
        switch self.lookupCache(linePrefix: linePrefix, lineSuffix: lineSuffix) {
            case .knownEmpty:
                return
            case .hit(let cached):
                self.recordLocalHit()
                AnalyticsManager.shared.recordLocalCompletionHit()
                textView.applyAIGhostSuggestion(cached)
                return
            case .miss:
                break
        }
        
        let isCode = (syntaxName != SyntaxName.none && syntaxName != "Plain Text")
        let strategy = Self.strategy
        let intent = Self.evaluateTriggerIntent(
            linePrefix: linePrefix,
            lineSuffix: lineSuffix,
            isCode: isCode,
            strategy: strategy
        )
        let delayMultiplier: Double
        switch intent {
            case .skip:
                return
            case .schedule(let mult):
                delayMultiplier = mult
        }
        
        let delayMs = max(120, Int(Double(Self.debounceMilliseconds) * delayMultiplier * self.effectiveBackoffMultiplier))
        
        let context = Self.extractCompactContext(from: nsText, caret: caret, isCode: isCode, strategy: strategy)
        let messages = Self.buildMessages(
            prefix: context.prefix,
            suffix: context.suffix,
            syntaxName: syntaxName,
            documentTitle: documentTitle,
            isCode: isCode
        )
        let inputTextForAccounting = messages.map(\.text).joined(separator: "\n")
        // Thinking is disabled via `disablesThinking` on non-reasoning models so actual output stays ~10-20 tokens,
        // while keeping a 200-token ceiling avoids empty responses on hybrid gateways that still emit brief thoughts.
        let maxOut = 200
        
        self.pendingTask = Task { [weak self, weak textView] in
            if delayMs > 0 {
                do {
                    try await Task.sleep(for: .milliseconds(delayMs))
                } catch {
                    return
                }
            }
            guard !Task.isCancelled, let self, let textView else { return }
            guard textView.window?.isKeyWindow == true,
                  !textView.hasMarkedText(),
                  textView.ghostTextVersion == expectedTextVersion,
                  textView.selectedRange == expectedRange
            else { return }
            
            if lineSuffix.isEmpty, textView.activeGhostSuggestion == nil {
                textView.showAIGhostLoadingIndicator()
            }
            defer {
                textView.hideAIGhostLoadingIndicatorIfNeeded()
            }
            
            var activeRequestConfig = effectiveConfig
            let clock = ContinuousClock()
            let requestStart = clock.now
            do {
                var completionResponse: AICompletionResponse
                do {
                    completionResponse = try await self.performCompletionRequest(
                        config: activeRequestConfig,
                        messages: messages,
                        maxOutputTokens: maxOut
                    )
                } catch let AIError.http(status, _) where routing.isAutoRouted && [400, 403, 404].contains(status) {
                    self.markAutoRoutedModelUnavailable(routing.effectiveModel, baseURL: effectiveConfig.resolvedBaseURL)
                    guard !Self.isPureReasoningModel(baseConfig.model)
                        && baseConfig.model.caseInsensitiveCompare(routing.effectiveModel) != .orderedSame
                    else { return }
                    
                    var fallbackConfig = baseConfig
                    fallbackConfig.temperature = 0.10
                    fallbackConfig.reasoningEffort = "low"
                    activeRequestConfig = fallbackConfig
                    completionResponse = try await self.performCompletionRequest(
                        config: activeRequestConfig,
                        messages: messages,
                        maxOutputTokens: maxOut
                    )
                }
                
                guard !Task.isCancelled else { return }
                let raw = completionResponse.text
                let elapsed = requestStart.duration(to: clock.now)
                let latencyMs = max(1, Int(elapsed.components.seconds * 1000) + Int(elapsed.components.attoseconds / 1_000_000_000_000_000))
                let actualInputTokens = completionResponse.inputTokens ?? Self.estimateTokens(in: inputTextForAccounting)
                let actualOutputTokens = completionResponse.outputTokens ?? Self.estimateTokens(in: raw)
                
                self.recordAIUsage(inputText: inputTextForAccounting, outputText: raw)
                AnalyticsManager.shared.recordAIUsage(
                    feature: "nextToken",
                    model: activeRequestConfig.model,
                    provider: activeRequestConfig.endpoint.label,
                    inputTokens: actualInputTokens,
                    outputTokens: actualOutputTokens,
                    latencyMs: latencyMs,
                    success: true
                )
                
                guard let completion = Self.sanitizeCompletion(
                    raw: raw,
                    linePrefix: linePrefix,
                    lineSuffix: lineSuffix,
                    isCode: isCode
                ) else {
                    self.storeEmptyCache(linePrefix: linePrefix, lineSuffix: lineSuffix)
                    return
                }
                
                self.storeCache(linePrefix: linePrefix, lineSuffix: lineSuffix, completion: completion)
                
                guard
                    textView.isEditable,
                    textView.window?.isKeyWindow == true,
                    !textView.hasMarkedText(),
                    textView.ghostTextVersion == expectedTextVersion,
                    textView.selectedRange == expectedRange,
                    textView.activeGhostSuggestion == nil
                else { return }
                
                textView.applyAIGhostSuggestion(completion)
            } catch is CancellationError {
                return
            } catch AIError.emptyResponse {
                self.storeEmptyCache(linePrefix: linePrefix, lineSuffix: lineSuffix)
                return
            } catch {
                CotLogger.shared.warning(
                    category: .ai,
                    "Next token prediction failed",
                    error: error,
                    context: [
                        "model": activeRequestConfig.model,
                        "endpoint": activeRequestConfig.endpoint.rawValue,
                    ]
                )
                // Quietly back off briefly on failure so offline/invalid gateways never cause UI noise or spam
                self.errorCooldownUntil = Date().addingTimeInterval(8)
            }
        }
    }
    
    
    // MARK: Prompt & Sanitization (Testable)
    
    static func buildMessages(
        prefix: String,
        suffix: String,
        syntaxName: String,
        documentTitle: String,
        isCode: Bool
    ) -> [AIMessage] {
        
        let styleRule = isCode
            ? "Output one short single-line code continuation (<=48 chars)."
            : "Continue seamlessly on the exact same line in the user's language (<=28 chars)."
        
        let system = """
        Inline FIM autocomplete engine. Output ONLY the exact text to insert at <CURSOR> inside <LINE> so <LINE> reads as one smooth, unbroken thought. NEVER emit newlines, NEVER jump to a new list item, and NEVER output numbered or bullet prefixes like "1. ", "2. ", "3、", "- ", or "• ". Never duplicate the end of prefix or start of suffix. \(styleRule) If the current thought is already complete or uncertain, reply EMPTY.
        """
        
        let (beforeLines, currentLinePrefix): (String, String) = {
            if let lastNL = prefix.lastIndex(of: "\n") {
                return (String(prefix[..<lastNL]), String(prefix[prefix.index(after: lastNL)...]))
            }
            return ("", prefix)
        }()
        let (currentLineSuffix, afterLines): (String, String) = {
            if let firstNL = suffix.firstIndex(of: "\n") {
                return (String(suffix[..<firstNL]), String(suffix[suffix.index(after: firstNL)...]))
            }
            return (suffix, "")
        }()
        
        let docTag = documentTitle.isEmpty ? "" : "\(documentTitle) | "
        var sections: [String] = ["[\(docTag)\(syntaxName)]"]
        if !beforeLines.isEmpty {
            sections.append("<BEFORE>\(beforeLines)</BEFORE>")
        }
        sections.append("<LINE>\(currentLinePrefix)<CURSOR>\(currentLineSuffix)</LINE>")
        if !afterLines.isEmpty {
            sections.append("<AFTER>\(afterLines)</AFTER>")
        }
        let user = sections.joined(separator: "\n")
        
        return [.system(system), .user(user)]
    }
    
    
    /// Cleans a raw AI FIM response into a crisp single-line inline ghost insertion,
    /// stripping prefix echo, code fences, chatter, disjointed list prefixes (`1. xxx`), and `lineSuffix` overlap.
    static func sanitizeCompletion(
        raw: String,
        linePrefix: String,
        lineSuffix: String,
        isCode: Bool = false
    ) -> String? {
        
        let trimmedLeadingSpaces = raw.drop { $0 == " " || $0 == "\t" }
        let hadCodeFence = trimmedLeadingSpaces.hasPrefix("```")
        
        // If a non-fenced response opens with a newline, the model tried to start a new line/list item instead of continuing inline.
        if !hadCodeFence, trimmedLeadingSpaces.first?.isNewline == true {
            return nil
        }
        
        var text = raw.trimmingCharacters(in: .newlines)
        guard !text.isEmpty else { return nil }
        
        // Strip markdown code fences if the model wrapped its completion
        if text.hasPrefix("```") {
            var lines = text.components(separatedBy: .newlines)
            if lines.first?.hasPrefix("```") == true { lines.removeFirst() }
            if lines.last?.trimmingCharacters(in: .whitespaces) == "```" { lines.removeLast() }
            text = lines.joined(separator: "\n")
        }
        
        // Strip XML tags if echoed
        for tag in ["<CURSOR>", "</CURSOR>", "<COMPLETION>", "</COMPLETION>", "<LINE>", "</LINE>", "<BEFORE>", "</BEFORE>", "<AFTER>", "</AFTER>"] {
            text = text.replacingOccurrences(of: tag, with: "")
        }
        
        // Take the first non-empty line
        guard let firstLine = text
            .components(separatedBy: .newlines)
            .first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty })
        else { return nil }
        
        var clean = firstLine
        let trimmedUpper = clean.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if trimmedUpper == "EMPTY" || trimmedUpper == "NONE" || trimmedUpper == "[EMPTY]" || trimmedUpper == "N/A" || trimmedUpper == "NULL" {
            return nil
        }
        
        // Strip accidental prefix echo (e.g. prefix ends with "进行" and completion starts with "进行一次commit")
        let maxEcho = min(24, linePrefix.count, clean.count)
        if maxEcho >= 2 {
            for len in stride(from: maxEcho, through: 2, by: -1) {
                let candidateEcho = String(clean.prefix(len))
                if linePrefix.hasSuffix(candidateEcho), clean.count > len {
                    clean.removeFirst(len)
                    break
                }
            }
        }
        if linePrefix.hasSuffix(" ") && clean.hasPrefix(" ") {
            while clean.hasPrefix(" ") {
                clean.removeFirst()
            }
        }
        if let lastPrefixChar = linePrefix.trimmingCharacters(in: .whitespaces).last,
           ["，", ",", "：", ":", "、", "(", "（", "《"].contains(lastPrefixChar)
        {
            while clean.first == lastPrefixChar, clean.count > 1 {
                clean.removeFirst()
            }
        }
        
        // Block disjointed leading list markers like "1. xxx", "2. xxx", "3、xxx", "(1) xxx", "- xxx", "• xxx"
        // while keeping genuine inline numbers like "2026年", "100%", "1步", "30天".
        if clean.range(
            of: #"^\s*(?:\d{1,2}\s*[\.、\)）](?!\d)\s*|[(（]\d{1,2}[)）]\s*|[-*•·▪︎‣]\s+)"#,
            options: .regularExpression
        ) != nil {
            return nil
        }
        
        // Trim any mid-line list item jump (e.g. "完成排版 2. 优化预测" -> "完成排版"), without breaking "Python 3.11".
        if !isCode,
           let trailingJump = clean.range(of: #"\s+\d{1,2}[\.、\)）](?!\d)\s*"#, options: .regularExpression)
        {
            let beforeJump = String(clean[..<trailingJump.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            if beforeJump.isEmpty {
                return nil
            }
            clean = String(clean[..<trailingJump.lowerBound])
        }
        
        // Reject leading conversational meta-replies
        let trimmedClean = clean.trimmingCharacters(in: .whitespaces)
        let lowerClean = trimmedClean.lowercased()
        if lowerClean.hasPrefix("here is")
            || lowerClean.hasPrefix("sure,")
            || lowerClean.hasPrefix("certainly")
            || trimmedClean.hasPrefix("好的，")
            || trimmedClean.hasPrefix("好的：")
            || trimmedClean.hasPrefix("以下是")
            || trimmedClean.hasPrefix("建议补全")
        {
            return nil
        }
        
        // Strip suffix overlap (e.g. trailing `)` already right after the cursor)
        guard let trimmedSuffix = UserHabitPredictor.trimOverlapWithLineSuffix(clean, lineSuffix: lineSuffix) else {
            return nil
        }
        clean = trimmedSuffix
        
        let maxLength = isCode ? 72 : 42
        if clean.count > maxLength {
            let capped = String(clean.prefix(maxLength))
            if let breakIdx = capped.lastIndex(where: { $0 == " " || $0 == "，" || $0 == "," || $0 == "。" || $0 == ";" }),
               capped.distance(from: capped.startIndex, to: breakIdx) >= maxLength / 2
            {
                clean = String(capped[..<breakIdx])
            } else {
                clean = capped
            }
        }
        
        return clean.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : clean
    }
    
    
    // MARK: Private Helpers
    
    private func performCompletionRequest(
        config: AIConfiguration,
        messages: [AIMessage],
        maxOutputTokens: Int
    ) async throws -> AICompletionResponse {
        
        let client = AIClient(
            configuration: config,
            maxOutputTokens: maxOutputTokens,
            timeoutInterval: 9,
            disablesThinking: !Self.isPureReasoningModel(config.model)
        )
        return try await client.sendWithUsage(messages)
    }
    
    
    func storeCache(linePrefix: String, lineSuffix: String, completion: String) {
        
        self.storeCacheEntry(linePrefix: linePrefix, lineSuffix: lineSuffix, completion: completion)
    }
    
    
    func storeEmptyCache(linePrefix: String, lineSuffix: String) {
        
        self.storeCacheEntry(linePrefix: linePrefix, lineSuffix: lineSuffix, completion: nil)
    }
    
    
    private func storeCacheEntry(linePrefix: String, lineSuffix: String, completion: String?) {
        
        let cleanSuffix = lineSuffix.trimmingCharacters(in: .newlines)
        self.cache.removeAll { $0.anchorLinePrefix == linePrefix && $0.anchorLineSuffix == cleanSuffix }
        self.cache.append(CacheEntry(
            anchorLinePrefix: linePrefix,
            anchorLineSuffix: cleanSuffix,
            completion: completion,
            createdAt: Date()
        ))
        if self.cache.count > 48 {
            self.cache.removeFirst(self.cache.count - 48)
        }
    }
    
    
    private static func economySiblingModel(for config: AIConfiguration) -> String? {
        
        switch config.provider {
            case .openCodeGo: return "kimi-k2.5"
            case .deepSeek: return "deepseek-chat"
            case .openAI: return "gpt-4o-mini"
            case .anthropic: return "claude-3-5-haiku-latest"
            case .google: return "gemini-2.5-flash"
            case .qwen: return "qwen-turbo"
            case .moonshot: return "moonshot-v1-8k"
            case .zhipu: return "glm-4-flash"
            case .miniMax: return "MiniMax-M2.5"
            case .volcengine: return "doubao-1-5-pro-32k"
            case .siliconFlow: return "deepseek-ai/DeepSeek-V3"
            case .aiHubMix: return "gpt-4.1-mini"
            case .openRouter: return Self.openRouterEconomySibling(for: config.model)
            case .ollama: return nil
            case .custom: break
        }
        
        let host = (URL(string: config.resolvedBaseURL)?.host ?? "").lowercased()
        if host.contains("api.openai.com") { return "gpt-4o-mini" }
        if host.contains("api.deepseek.com") { return "deepseek-chat" }
        if host.contains("api.anthropic.com") { return "claude-3-5-haiku-latest" }
        if host.contains("generativelanguage.googleapis.com") { return "gemini-2.5-flash" }
        if host.contains("dashscope.aliyuncs.com") { return "qwen-turbo" }
        if host.contains("api.moonshot.cn") { return "moonshot-v1-8k" }
        if host.contains("openrouter.ai") { return Self.openRouterEconomySibling(for: config.model) }
        return nil
    }
    
    
    private static func openRouterEconomySibling(for model: String) -> String {
        
        let lower = model.lowercased()
        if lower.hasPrefix("deepseek/") { return "deepseek/deepseek-chat" }
        if lower.hasPrefix("openai/") { return "openai/gpt-4o-mini" }
        if lower.hasPrefix("anthropic/") { return "anthropic/claude-3.5-haiku" }
        if lower.hasPrefix("google/") { return "google/gemini-2.5-flash" }
        return "deepseek/deepseek-chat"
    }
    
    
    private static func currentDateKey(date: Date = Date()) -> String {
        
        let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }
    
    
    private func persistStats(_ stats: AINextTokenDailyStats) {
        
        self.cachedTodayStats = stats
        if let data = try? JSONEncoder().encode(stats),
           let json = String(data: data, encoding: .utf8)
        {
            UserDefaults.standard.set(json, forKey: CotLocalDatabase.ConfigKey.aiNextTokenDailyStatsJSON)
            CotLocalDatabase.shared.set(json, forKey: CotLocalDatabase.ConfigKey.aiNextTokenDailyStatsJSON)
        }
        NotificationCenter.default.post(name: Self.statsDidChangeNotification, object: nil)
    }
}
