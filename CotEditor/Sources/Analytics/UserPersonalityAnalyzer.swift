//
//  UserPersonalityAnalyzer.swift
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

import CryptoKit
import Foundation

/// Visual mood/tone classification for a personality danmaku tag.
nonisolated enum PersonalityTagTone: String, Codable, Sendable {
    
    case warm
    case sharp
    case playful
    case calm
}


/// A concise (<= 8 characters) personality tag distilled by background AI from the user's writing.
nonisolated struct UserPersonalityTag: Identifiable, Codable, Sendable, Equatable {
    
    var id: String
    var label: String
    var explanation: String
    var tone: PersonalityTagTone = .calm
    
    
    init(
        id: String = UUID().uuidString,
        label: String,
        explanation: String,
        tone: PersonalityTagTone = .calm
    ) {
        self.id = id
        self.label = UserPersonalityAnalyzer.clampTagLabel(label)
        self.explanation = explanation.trimmingCharacters(in: .whitespacesAndNewlines)
        self.tone = tone
    }
}


/// Persisted AI-distilled portrait and conceptual understanding of the active user.
nonisolated struct UserPersonalityProfile: Codable, Sendable, Equatable {
    
    var tags: [UserPersonalityTag]
    var conceptTitle: String
    var conceptSummary: String
    var writingStyleNotes: [String]
    var sourceFingerprint: String
    var modelUsed: String
    var generatedAt: Date
    
    
    var isLocalFallback: Bool {
        self.modelUsed == "本地行为初判"
    }
}


/// Pure parsing, clamping, scheduling, and fallback synthesis helpers for the 6-hour AI personality analyzer.
nonisolated enum UserPersonalityAnalyzer {
    
    static let autoInterval: TimeInterval = 6 * 3600
    static let maxTagCharacters = 8
    
    
    /// Clamps any candidate personality tag strictly to `<= 8` characters without trailing punctuation.
    static func clampTagLabel(_ raw: String, maxLength: Int = maxTagCharacters) -> String {
        
        var cleaned = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "#「」[]【】\"'“”‘’。，、!！?？:：;；·•"))
            .replacingOccurrences(of: "\n", with: "")
        
        // Strip leading bullet markers if present
        cleaned = cleaned.replacingOccurrences(
            of: #"^(\d+[\.、\)）]|[-*•])\s*"#,
            with: "",
            options: .regularExpression
        )
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard cleaned.count > maxLength else { return cleaned }
        return String(cleaned.prefix(maxLength))
    }
    
    
    /// Deduplicates personality tags by normalized label so orbital danmaku never shows repeat pills.
    static func deduplicatedTags(_ tags: [UserPersonalityTag], maxCount: Int = 8) -> [UserPersonalityTag] {
        var result: [UserPersonalityTag] = []
        var seen = Set<String>()
        for tag in tags {
            let cleanLabel = Self.clampTagLabel(tag.label)
            let key = cleanLabel.lowercased()
            guard !cleanLabel.isEmpty, seen.insert(key).inserted else { continue }
            var normalizedTag = tag
            normalizedTag.label = cleanLabel
            result.append(normalizedTag)
            if result.count >= maxCount { break }
        }
        return result
    }
    
    
    /// Determines whether the automatic 6-hour background personality refresh should execute now.
    static func shouldAutoRun(
        now: Date = Date(),
        lastProfile: UserPersonalityProfile?,
        currentFingerprint: String,
        currentCharCount: Int,
        interval: TimeInterval = autoInterval
    ) -> Bool {
        
        guard currentCharCount >= 30 else { return false }
        guard let lastProfile else { return true }
        if lastProfile.isLocalFallback {
            // Allow an immediate AI upgrade once enough real writing exists or interval elapses.
            return now.timeIntervalSince(lastProfile.generatedAt) >= min(600, interval)
                || lastProfile.sourceFingerprint != currentFingerprint
        }
        let elapsed = now.timeIntervalSince(lastProfile.generatedAt)
        guard elapsed >= interval else { return false }
        return lastProfile.sourceFingerprint != currentFingerprint || lastProfile.tags.isEmpty
    }
    
    
    /// Parses a structured JSON personality report returned by an AI model.
    static func parseResponse(
        _ raw: String,
        sourceFingerprint: String,
        modelUsed: String
    ) -> UserPersonalityProfile? {
        
        var cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return nil }
        
        if cleaned.hasPrefix("```") {
            var lines = cleaned.components(separatedBy: .newlines)
            if lines.first?.hasPrefix("```") == true { lines.removeFirst() }
            if lines.last?.trimmingCharacters(in: .whitespaces) == "```" { lines.removeLast() }
            cleaned = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        guard let startIdx = cleaned.firstIndex(of: "{"),
              let endIdx = cleaned.lastIndex(of: "}"),
              startIdx <= endIdx
        else { return nil }
        
        let slice = String(cleaned[startIdx...endIdx])
        guard let data = slice.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        
        let conceptTitleRaw = (obj["concept_title"] as? String) ?? (obj["conceptTitle"] as? String) ?? ""
        let conceptTitle = AIDocumentTextCleaner.clean(conceptTitleRaw)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        let conceptSummaryRaw = (obj["concept_summary"] as? String) ?? (obj["conceptSummary"] as? String) ?? ""
        let conceptSummary = AIDocumentTextCleaner.clean(conceptSummaryRaw)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        let styleNotes = ((obj["writing_style_notes"] as? [String]) ?? (obj["writingStyleNotes"] as? [String]) ?? [])
            .map { AIDocumentTextCleaner.clean($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        
        var parsedTags: [UserPersonalityTag] = []
        var seenLabels = Set<String>()
        
        if let rawTags = obj["tags"] as? [[String: Any]] {
            for entry in rawTags {
                let rawLabel = (entry["label"] as? String) ?? ""
                let clampedLabel = Self.clampTagLabel(rawLabel)
                let normKey = clampedLabel.lowercased()
                guard !clampedLabel.isEmpty, seenLabels.insert(normKey).inserted else { continue }
                
                let explanation = AIDocumentTextCleaner.clean((entry["explanation"] as? String) ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let toneRaw = (entry["tone"] as? String ?? "calm").lowercased()
                let tone = PersonalityTagTone(rawValue: toneRaw) ?? .calm
                
                parsedTags.append(UserPersonalityTag(
                    label: clampedLabel,
                    explanation: explanation.isEmpty ? "从近期文本与表达习惯中捕捉到的高频特质。" : explanation,
                    tone: tone
                ))
                if parsedTags.count >= 8 { break }
            }
        } else if let stringTags = obj["tags"] as? [String] {
            for rawLabel in stringTags {
                let clampedLabel = Self.clampTagLabel(rawLabel)
                let normKey = clampedLabel.lowercased()
                guard !clampedLabel.isEmpty, seenLabels.insert(normKey).inserted else { continue }
                parsedTags.append(UserPersonalityTag(
                    label: clampedLabel,
                    explanation: "从近期文本与表达习惯中捕捉到的高频特质。",
                    tone: .calm
                ))
                if parsedTags.count >= 8 { break }
            }
        }
        
        guard !parsedTags.isEmpty, !conceptSummary.isEmpty || !conceptTitle.isEmpty else { return nil }
        
        let resolvedTitle = conceptTitle.isEmpty ? "专注记录的造物者" : conceptTitle
        let resolvedSummary = conceptSummary.isEmpty ? styleNotes.joined(separator: "；") : conceptSummary
        
        return UserPersonalityProfile(
            tags: parsedTags,
            conceptTitle: resolvedTitle,
            conceptSummary: resolvedSummary,
            writingStyleNotes: Array(styleNotes.prefix(4)),
            sourceFingerprint: sourceFingerprint,
            modelUsed: modelUsed,
            generatedAt: Date()
        )
    }
    
    
    /// Builds a grounded, zero-network fallback profile from local writing behavior when no AI endpoint is usable yet.
    static func makeLocalHeuristicFallback(
        documents: [StoredDocumentRecord],
        weeklyReports: [StoredWeeklyReport],
        stats: [DailyWritingStats],
        streak: Int,
        fingerprint: String
    ) -> UserPersonalityProfile {
        
        var tags: [UserPersonalityTag] = []
        var notes: [String] = []
        
        let calendar = Calendar.current
        let totalDocs = documents.count
        let totalTyped = stats.reduce(0) { $0 + $1.typedChars }
        
        // 1. Time-of-day rhythm from updatedAt timestamps
        let hours = documents.map { calendar.component(.hour, from: $0.updatedAt) }
        let lateNightCount = hours.filter { $0 >= 22 || $0 <= 3 }.count
        let morningCount = hours.filter { (6...11).contains($0) }.count
        if !hours.isEmpty && lateNightCount * 2 >= hours.count {
            tags.append(UserPersonalityTag(
                label: "夜深更有灵感",
                explanation: "喜欢在安静的夜晚理清思绪，越到夜里写得越顺。",
                tone: .calm
            ))
            notes.append("偏爱在安静的夜晚沉淀想法。")
        } else if !hours.isEmpty && morningCount * 2 >= hours.count {
            tags.append(UserPersonalityTag(
                label: "早起思绪最清",
                explanation: "习惯趁上午精力最好时动笔，干脆利落地推进核心内容。",
                tone: .warm
            ))
            notes.append("上午状态专注，习惯先把手头重要的事写出来。")
        }
        
        // 2. Syntax & genre inclination
        let markdownCount = documents.filter { $0.syntax.localizedCaseInsensitiveContains("markdown") }.count
        let codeCount = documents.filter {
            let s = $0.syntax.lowercased()
            return s.contains("swift") || s.contains("python") || s.contains("json") || s.contains("typescript") || s.contains("javascript") || s.contains("shell")
        }.count
        if codeCount >= max(2, totalDocs / 3) {
            tags.append(UserPersonalityTag(
                label: "逻辑清晰利落",
                explanation: "平时常写代码与技术笔记，表达直接，凡事讲求落地。",
                tone: .sharp
            ))
        } else if markdownCount >= max(2, totalDocs / 2) {
            tags.append(UserPersonalityTag(
                label: "做事很有条理",
                explanation: "习惯把复杂的想法分层列清，看着舒爽、读着清楚。",
                tone: .calm
            ))
        }
        
        // 3. Weekly report habit
        if !weeklyReports.isEmpty {
            tags.append(UserPersonalityTag(
                label: "习惯勤做复盘",
                explanation: "会把做过的事定期收拢成阶段记录，步子走得很稳。",
                tone: .warm
            ))
            notes.append("有定期复盘的习惯，擅长从日常记录里梳理脉络。")
        }
        
        // 4. Streak or volume
        if streak >= 3 {
            tags.append(UserPersonalityTag(
                label: "每天都在写字",
                explanation: "保持着稳定的日常记录节奏，写字已经成了自然习惯。",
                tone: .warm
            ))
        } else if totalTyped >= 10_000 {
            tags.append(UserPersonalityTag(
                label: "一写就停不下",
                explanation: "耐得住性子长篇打磨，一旦进入状态就能持续输出。",
                tone: .sharp
            ))
        }
        
        // 5. Directness / highlights
        let hasHighlights = documents.contains { $0.highlightsJSON.count > 4 }
        if hasHighlights {
            tags.append(UserPersonalityTag(
                label: "抓重点很准",
                explanation: "读文写字时会随手标出关键处，一眼就能拎出核心。",
                tone: .playful
            ))
        }
        
        if tags.count < 5 {
            tags.append(UserPersonalityTag(
                label: "说话直奔主题",
                explanation: "行文干净不绕弯子，喜欢把事情直接说透。",
                tone: .playful
            ))
            tags.append(UserPersonalityTag(
                label: "喜欢安静记录",
                explanation: "习惯把闪过的念头随手记在本地，慢慢攒出自己的思路。",
                tone: .calm
            ))
            tags.append(UserPersonalityTag(
                label: "认真对待细节",
                explanation: "对字句和排版有自己的讲究，看着顺眼才舒心。",
                tone: .warm
            ))
        }
        
        if notes.isEmpty {
            notes.append("行文干净自然，喜欢把想法理顺后再落笔。")
        }
        
        let title = streak >= 3 ? "步调从容的记录者" : "思路清爽的写字人"
        let summary = "你写东西喜欢直奔重点，不爱堆砌客套话；习惯把零散的念头一条条理清，既有自己的节奏，也很在意细节的舒坦感。"
        
        return UserPersonalityProfile(
            tags: Self.deduplicatedTags(tags, maxCount: 7),
            conceptTitle: title,
            conceptSummary: summary,
            writingStyleNotes: Array(notes.prefix(3)),
            sourceFingerprint: fingerprint,
            modelUsed: "本地行为初判",
            generatedAt: Date()
        )
    }
    
    
    static func sha256Hex(_ text: String) -> String {
        let digest = SHA256.hash(data: Data(text.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
