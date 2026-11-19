//
//  Round16FeatureTests.swift
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
import SwiftUI
import Testing
@testable import CotEditor

@Suite(.serialized)
@MainActor
struct Round16FeatureTests {
    
    @Test func smartModelAutoRoutingAndFallback() {
        
        let predictor = AINextTokenPredictor.shared
        predictor.clearUnavailableModels()
        defer { predictor.clearUnavailableModels() }
        
        // 1. DeepSeek reasoner auto-routes to deepseek-chat
        let dsProfile = AIEndpointProfile(
            name: "DeepSeek",
            endpoint: .openAIChatCompletions,
            baseURL: AIProvider.deepSeek.defaultBaseURL,
            model: "deepseek-reasoner"
        )
        let dsConfig = dsProfile.configuration(apiKey: "sk-test")
        let dsRoute = predictor.resolveModelRouting(profile: dsProfile, baseConfig: dsConfig, explicitOverride: "")
        #expect(dsRoute.effectiveModel == "deepseek-chat")
        #expect(dsRoute.isAutoRouted == true)
        #expect(dsRoute.isReasoningBlocked == false)
        
        // 2. OpenAI o3 & gpt-4o auto-route to gpt-4o-mini
        let oaiProfile = AIEndpointProfile(
            name: "OpenAI",
            endpoint: .openAIResponses,
            baseURL: "https://api.openai.com/v1",
            model: "o3"
        )
        let oaiRoute = predictor.resolveModelRouting(
            profile: oaiProfile,
            baseConfig: AIConfiguration(endpoint: .openAIResponses, baseURL: "https://api.openai.com/v1", model: "o3", apiKey: "sk-test"),
            explicitOverride: ""
        )
        #expect(oaiRoute.effectiveModel == "gpt-4o-mini")
        #expect(oaiRoute.isAutoRouted == true)
        
        let gpt4oRoute = predictor.resolveModelRouting(
            profile: oaiProfile,
            baseConfig: AIConfiguration(endpoint: .openAIChatCompletions, baseURL: "https://api.openai.com/v1", model: "gpt-4o", apiKey: "sk-test"),
            explicitOverride: ""
        )
        #expect(gpt4oRoute.effectiveModel == "gpt-4o-mini")
        #expect(gpt4oRoute.isAutoRouted == true)
        
        // 3. Custom gateway profile uses discovered lightweight savedModels first
        let relayProfile = AIEndpointProfile(
            name: "Relay",
            endpoint: .anthropicMessages,
            baseURL: "https://relay.example.com/v1",
            model: "claude-opus-4-6",
            savedModels: ["claude-opus-4-6", "claude-haiku-4-5"]
        )
        let relayConfig = relayProfile.configuration(apiKey: "sk-test")
        let relayRoute = predictor.resolveModelRouting(profile: relayProfile, baseConfig: relayConfig, explicitOverride: "")
        #expect(relayRoute.effectiveModel == "claude-haiku-4-5")
        #expect(relayRoute.isAutoRouted == true)
        #expect(relayRoute.isReasoningBlocked == false)
        
        // 4. Marking auto-routed model unavailable falls back cleanly (blocks auto reasoning, keeps heavy fallback disabled)
        predictor.markAutoRoutedModelUnavailable("deepseek-chat", baseURL: dsConfig.resolvedBaseURL)
        let dsUnavailableRoute = predictor.resolveModelRouting(profile: dsProfile, baseConfig: dsConfig, explicitOverride: "")
        #expect(dsUnavailableRoute.isAutoRouted == false)
        #expect(dsUnavailableRoute.isReasoningBlocked == true)
        
        // 5. Custom gateway with pure reasoning model & no lightweight sibling blocks automatic calls
        let customReasoner = AIEndpointProfile(
            name: "CustomR1",
            endpoint: .openAIChatCompletions,
            baseURL: "https://custom-llm.internal/v1",
            model: "deepseek-r1"
        )
        let customConfig = customReasoner.configuration(apiKey: "sk-test")
        let blockedRoute = predictor.resolveModelRouting(profile: customReasoner, baseConfig: customConfig, explicitOverride: "")
        #expect(blockedRoute.isReasoningBlocked == true)
        #expect(blockedRoute.isAutoRouted == false)
        
        // 6. Lightweight model & local Ollama stay untouched
        let qwenLight = AIConfiguration(endpoint: .openAIChatCompletions, baseURL: AIProvider.qwen.defaultBaseURL, model: "qwen-turbo", apiKey: "sk-test")
        let qwenRoute = predictor.resolveModelRouting(profile: nil, baseConfig: qwenLight, explicitOverride: "")
        #expect(qwenRoute.effectiveModel == "qwen-turbo")
        #expect(qwenRoute.isAutoRouted == false)
        
        let ollamaHeavy = AIConfiguration(endpoint: .ollama, baseURL: "http://localhost:11434", model: "deepseek-r1:14b", apiKey: "")
        let ollamaRoute = predictor.resolveModelRouting(profile: nil, baseConfig: ollamaHeavy, explicitOverride: "")
        #expect(ollamaRoute.effectiveModel == "deepseek-r1:14b")
        #expect(ollamaRoute.isAutoRouted == false)
        #expect(ollamaRoute.isReasoningBlocked == false)
        
        // 7. Vendor-prefixed savedModels adaptation for bare model override across gateways
        let cmdCodeProfile = AIEndpointProfile(
            name: "CommandCode",
            endpoint: .openAIResponses,
            baseURL: "https://api.commandcode.ai/provider/v1",
            model: "google/gemini-3.8-flash",
            savedModels: ["deepseek/deepseek-v4.1-flash", "claude-haiku-5-5"]
        )
        let cmdRoute = predictor.resolveModelRouting(
            profile: cmdCodeProfile,
            baseConfig: cmdCodeProfile.configuration(apiKey: "sk-test"),
            explicitOverride: "deepseek-v4.1-flash"
        )
        #expect(cmdRoute.effectiveModel == "deepseek/deepseek-v4.1-flash")
        #expect(cmdRoute.isAutoRouted == true)
    }
    
    
    @Test func contextualTriggerIntentAndNegativeCacheAndBackoff() {
        
        let predictor = AINextTokenPredictor.shared
        predictor.recordSuggestionAccepted()
        defer { predictor.recordSuggestionAccepted() }
        
        // Smart mode skips sentence & code statement terminators
        #expect(AINextTokenPredictor.evaluateTriggerIntent(
            linePrefix: "本周工作总结已完成。",
            lineSuffix: "",
            isCode: false,
            strategy: .smart,
            isManual: false
        ) == .skip(reason: "sentenceEnd"))
        
        #expect(AINextTokenPredictor.evaluateTriggerIntent(
            linePrefix: "return value;",
            lineSuffix: "",
            isCode: true,
            strategy: .smart,
            isManual: false
        ) == .skip(reason: "sentenceEnd"))
        
        // Smart mode fast-tracks high-intent continuation cues (including 2-char CJK openings)
        #expect(AINextTokenPredictor.evaluateTriggerIntent(
            linePrefix: "主要进展：",
            lineSuffix: "",
            isCode: false,
            strategy: .smart,
            isManual: false
        ) == .schedule(delayMultiplier: 0.85))
        #expect(AINextTokenPredictor.evaluateTriggerIntent(
            linePrefix: "背景：",
            lineSuffix: "",
            isCode: false,
            strategy: .smart,
            isManual: false
        ) == .schedule(delayMultiplier: 0.85))
        #expect(AINextTokenPredictor.evaluateTriggerIntent(
            linePrefix: "周报",
            lineSuffix: "",
            isCode: false,
            strategy: .smart,
            isManual: false
        ) == .schedule(delayMultiplier: 1.0))
        #expect(AINextTokenPredictor.evaluateTriggerIntent(
            linePrefix: "我",
            lineSuffix: "",
            isCode: false,
            strategy: .smart,
            isManual: false
        ) == .skip(reason: "tooShort"))
        #expect(AINextTokenPredictor.evaluateTriggerIntent(
            linePrefix: "abc",
            lineSuffix: "",
            isCode: false,
            strategy: .smart,
            isManual: false
        ) == .skip(reason: "tooShort"))
        
        // Numbered list item `1.` is NOT treated as finished prose sentence
        #expect(AINextTokenPredictor.evaluateTriggerIntent(
            linePrefix: "本周计划 1.",
            lineSuffix: "",
            isCode: false,
            strategy: .smart,
            isManual: false
        ) != .skip(reason: "sentenceEnd"))
        
        // URL and inline image lines are skipped
        #expect(AINextTokenPredictor.evaluateTriggerIntent(
            linePrefix: "查看 https://coteditor.com/docs",
            lineSuffix: "",
            isCode: false,
            strategy: .smart,
            isManual: false
        ) == .skip(reason: "urlInput"))
        
        // Manual strategy skips automatic triggers, but explicit manual call fires with 0 delay multiplier
        #expect(AINextTokenPredictor.evaluateTriggerIntent(
            linePrefix: "主要进展：",
            lineSuffix: "",
            isCode: false,
            strategy: .manual,
            isManual: false
        ) == .skip(reason: "manualOnly"))
        #expect(AINextTokenPredictor.evaluateTriggerIntent(
            linePrefix: "主要进展：",
            lineSuffix: "",
            isCode: false,
            strategy: .manual,
            isManual: true
        ) == .schedule(delayMultiplier: 0))
        
        // Adaptive ignore backoff: 3 ignores -> 1.8x, acceptance resets to 1.0x
        let prevStrategy = UserDefaults.standard.object(forKey: CotLocalDatabase.ConfigKey.aiNextTokenStrategy)
        defer {
            if let prevStrategy {
                UserDefaults.standard.set(prevStrategy, forKey: CotLocalDatabase.ConfigKey.aiNextTokenStrategy)
            } else {
                UserDefaults.standard.removeObject(forKey: CotLocalDatabase.ConfigKey.aiNextTokenStrategy)
            }
        }
        UserDefaults.standard.set(AINextTokenStrategy.smart.rawValue, forKey: CotLocalDatabase.ConfigKey.aiNextTokenStrategy)
        
        #expect(predictor.effectiveBackoffMultiplier == 1.0)
        predictor.recordSuggestionIgnored()
        predictor.recordSuggestionIgnored()
        #expect(predictor.effectiveBackoffMultiplier == 1.0)
        predictor.recordSuggestionIgnored()
        #expect(predictor.consecutiveIgnores == 3)
        #expect(predictor.effectiveBackoffMultiplier == 1.8)
        predictor.recordSuggestionAccepted()
        #expect(predictor.consecutiveIgnores == 0)
        #expect(predictor.effectiveBackoffMultiplier == 1.0)
        
        // Negative / empty cache deduplicates exact context but allows new typed characters through
        let uniquePrefix = "unlikely-unique-prefix-\(UUID().uuidString)"
        #expect(predictor.lookupCache(linePrefix: uniquePrefix, lineSuffix: "") == .miss)
        predictor.storeEmptyCache(linePrefix: uniquePrefix, lineSuffix: "")
        #expect(predictor.lookupCache(linePrefix: uniquePrefix, lineSuffix: "") == .knownEmpty)
        #expect(predictor.lookupCache(linePrefix: uniquePrefix + "x", lineSuffix: "") == .miss)
    }
    
    
    @Test func compactContextSlicingAndDailyStatsLedger() {
        
        // Long document slices tightly under `.smart` strategy while snapping at line boundary
        var paragraphs: [String] = []
        for idx in 1...40 {
            paragraphs.append("第\(idx)段工作记录：完成了模块化拆解与接口联调，验证性能无回退。")
        }
        let fullText = paragraphs.joined(separator: "\n") as NSString
        let caret = Int(Double(fullText.length) * 0.7)
        
        let smartSlice = AINextTokenPredictor.extractCompactContext(
            from: fullText,
            caret: caret,
            isCode: false,
            strategy: .smart
        )
        #expect(smartSlice.prefix.count <= 360)
        #expect(smartSlice.suffix.count <= 120)
        #expect(smartSlice.prefix.isEmpty == false)
        
        // Token estimator distinguishes CJK and ASCII cleanly
        #expect(AINextTokenPredictor.estimateTokens(in: "") == 0)
        let asciiTokens = AINextTokenPredictor.estimateTokens(in: "let result = computeValue()")
        let cjkTokens = AINextTokenPredictor.estimateTokens(in: "完成本周迭代开发与测试")
        #expect(asciiTokens >= 6 && asciiTokens <= 10)
        #expect(cjkTokens >= 6 && cjkTokens <= 10)
        
        // Daily ledger accounting & reset (restore previous value after test)
        let db = CotLocalDatabase.shared
        let prevDefaultsStats = UserDefaults.standard.object(forKey: CotLocalDatabase.ConfigKey.aiNextTokenDailyStatsJSON)
        let prevDBStats = db.string(forKey: CotLocalDatabase.ConfigKey.aiNextTokenDailyStatsJSON, default: "")
        defer {
            if let prevDefaultsStats {
                UserDefaults.standard.set(prevDefaultsStats, forKey: CotLocalDatabase.ConfigKey.aiNextTokenDailyStatsJSON)
            } else {
                UserDefaults.standard.removeObject(forKey: CotLocalDatabase.ConfigKey.aiNextTokenDailyStatsJSON)
            }
            db.set(prevDBStats, forKey: CotLocalDatabase.ConfigKey.aiNextTokenDailyStatsJSON)
        }
        
        let predictor = AINextTokenPredictor.shared
        predictor.resetTodayStats()
        #expect(predictor.todayStats.aiRequests == 0)
        #expect(predictor.todayStats.localHits == 0)
        #expect(predictor.todayStats.totalEstimatedTokens == 0)
        
        predictor.recordLocalHit()
        predictor.recordAIUsage(inputText: "今天完成了周报整理", outputText: "与代码提交")
        let updated = predictor.todayStats
        #expect(updated.localHits == 1)
        #expect(updated.aiRequests == 1)
        #expect(updated.estimatedInputTokens > 0)
        #expect(updated.estimatedOutputTokens > 0)
        #expect(updated.totalEstimatedTokens == updated.estimatedInputTokens + updated.estimatedOutputTokens)
        
        predictor.resetTodayStats()
        #expect(predictor.todayStats.aiRequests == 0)
        #expect(predictor.todayStats.localHits == 0)
    }
    
    
    @Test func thinkingRejectionMultiBranchHabitsAndSameCaretSelection() {
        
        // 1. AIClient detects HTTP 400 thinking-parameter rejections while ignoring unrelated 400 errors
        let client = AIClient(configuration: .empty, maxOutputTokens: 200, timeoutInterval: 9, disablesThinking: true)
        #expect(client.disablesThinking == true)
        #expect(AIClient.isThinkingParameterRejectedError(AIError.http(status: 400, message: "thinking: Extra inputs are not permitted")))
        #expect(AIClient.isThinkingParameterRejectedError(AIError.http(status: 400, message: "thinkingConfig is not supported for this model")))
        #expect(!AIClient.isThinkingParameterRejectedError(AIError.http(status: 400, message: "Invalid API key")))
        
        // 2. Multi-branch dominant habit survives even when share is ~38% (30 vs 6x4 branches)
        let habitPredictor = UserHabitPredictor(persistenceKey: nil)
        for _ in 0..<10 {
            habitPredictor.recordAcceptedCompletion(prefixContext: "复盘本次需求", acceptedPhrase: "拆分三个阶段推进")
        }
        for _ in 0..<2 {
            habitPredictor.recordAcceptedCompletion(prefixContext: "复盘本次需求", acceptedPhrase: "补充日志埋点")
            habitPredictor.recordAcceptedCompletion(prefixContext: "复盘本次需求", acceptedPhrase: "完善监控告警")
            habitPredictor.recordAcceptedCompletion(prefixContext: "复盘本次需求", acceptedPhrase: "评审接口契约")
            habitPredictor.recordAcceptedCompletion(prefixContext: "复盘本次需求", acceptedPhrase: "同步交付排期")
        }
        let multiBranchPrediction = habitPredictor.predictNextPhrase(in: "复盘本次需求", caretLocation: 6)
        #expect(multiBranchPrediction == "拆分三个阶段推进")
        
        // 3. Redundant setSelectedRanges at identical caret position preserves activeGhostSuggestion
        let doc = Document()
        doc.textStorage.replaceCharacters(in: doc.textStorage.range, with: "搞定以后")
        let textView = EditorTextView(textStorage: doc.textStorage, lineEndingScanner: doc.lineEndingScanner)
        textView.frame = NSRect(x: 0, y: 0, width: 420, height: 180)
        textView.font = .systemFont(ofSize: 13)
        let sameRange = NSRange(location: 4, length: 0)
        textView.setSelectedRanges([NSValue(range: sameRange)], affinity: .downstream, stillSelecting: false)
        textView.showGhostCandidate("进行一次commit", animateEntrance: false, isFromAI: true)
        #expect(textView.activeGhostSuggestion == "进行一次commit")
        
        // Redundant re-sync to the exact same caret (as done by IME commit) keeps ghost intact
        textView.setSelectedRanges([NSValue(range: sameRange)], affinity: .downstream, stillSelecting: false)
        #expect(textView.activeGhostSuggestion == "进行一次commit")
        
        // Moving caret to another position clears the ghost cleanly
        textView.setSelectedRanges([NSValue(range: NSRange(location: 2, length: 0))], affinity: .downstream, stillSelecting: false)
        #expect(textView.activeGhostSuggestion == nil)
    }
    
    
    @Test func aiSettingsPanePreservesUnifiedDimensions() {
        
        let host = NSHostingController(rootView: AnyView(SettingsPane.ai.view))
        host.view.frame = NSRect(x: 0, y: 0, width: SettingsPaneLayout.width, height: SettingsPaneLayout.height)
        host.view.layoutSubtreeIfNeeded()
        
        let size = host.view.fittingSize
        #expect(abs(size.width - SettingsPaneLayout.width) <= 1)
        #expect(abs(size.height - SettingsPaneLayout.height) <= 1)
        #expect(Self.descendants(ofType: NSTableView.self, in: host.view).isEmpty)
    }
    
    
    private static func descendants<T: NSView>(ofType type: T.Type, in view: NSView) -> [T] {
        
        var matches: [T] = []
        if let typed = view as? T {
            matches.append(typed)
        }
        for subview in view.subviews {
            matches.append(contentsOf: Self.descendants(ofType: type, in: subview))
        }
        return matches
    }
}
