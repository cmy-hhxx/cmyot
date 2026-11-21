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
                guard !clampedLabel.isEmpty, seenLabels.insert(clampedLabel).inserted else { continue }
                
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
                guard !clampedLabel.isEmpty, seenLabels.insert(clampedLabel).inserted else { continue }
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
                label: "深夜灵感捕手",
                explanation: "最近记录中有不少是在 22:00 之后保存落笔的，夜间进入心流更顺。",
                tone: .calm
            ))
            notes.append("偏好在安静的夜间整理思路并落地文稿。")
        } else if !hours.isEmpty && morningCount * 2 >= hours.count {
            tags.append(UserPersonalityTag(
                label: "晨间清冽派",
                explanation: "高频在上午集中开写，趁精力充沛把核心内容先敲出来。",
                tone: .warm
            ))
            notes.append("上午产出集中，习惯在一天的开端完成主要起草。")
        }
        
        // 2. Syntax & genre inclination
        let markdownCount = documents.filter { $0.syntax.localizedCaseInsensitiveContains("markdown") }.count
        let codeCount = documents.filter {
            let s = $0.syntax.lowercased()
            return s.contains("swift") || s.contains("python") || s.contains("json") || s.contains("typescript") || s.contains("javascript") || s.contains("shell")
        }.count
        if codeCount >= max(2, totalDocs / 3) {
            tags.append(UserPersonalityTag(
                label: "工程实干派",
                explanation: "库里有不少代码与结构化技术文档，思考偏向直接可落地。",
                tone: .sharp
            ))
        } else if markdownCount >= max(2, totalDocs / 2) {
            tags.append(UserPersonalityTag(
                label: "结构控写手",
                explanation: "高频使用 Markdown 组织层级与要点，喜欢把复杂事理顺再动。",
                tone: .calm
            ))
        }
        
        // 3. Weekly report habit
        if !weeklyReports.isEmpty {
            tags.append(UserPersonalityTag(
                label: "复盘有章法",
                explanation: "已沉淀 \(weeklyReports.count) 份周报，会定期把零散产出收束成阶段结论。",
                tone: .warm
            ))
            notes.append("重视阶段复盘，持续在周报库沉淀工作线索。")
        }
        
        // 4. Streak or volume
        if streak >= 3 {
            tags.append(UserPersonalityTag(
                label: "连续\(streak)天在写",
                explanation: "保持了连续 \(streak) 天动笔的节奏，输出习惯相当稳定。",
                tone: .warm
            ))
        } else if totalTyped >= 10_000 {
            tags.append(UserPersonalityTag(
                label: "高密输出者",
                explanation: "累计已手写超过 \(totalTyped.formatted(.number.grouping(.automatic))) 字，耐得住长程打磨。",
                tone: .sharp
            ))
        }
        
        // 5. Directness / highlights
        let hasHighlights = documents.contains { $0.highlightsJSON.count > 4 }
        if hasHighlights {
            tags.append(UserPersonalityTag(
                label: "细节标红控",
                explanation: "习惯在文稿里随手做高亮标注，抓重点很果断。",
                tone: .playful
            ))
        }
        
        if tags.count < 4 {
            tags.append(UserPersonalityTag(
                label: "直白说人话",
                explanation: "表达偏向务实直接，先把事情说清，再考虑修饰。",
                tone: .playful
            ))
            tags.append(UserPersonalityTag(
                label: "自留地耕作者",
                explanation: "把零散想法收进本地文档库，慢慢养出自己的知识体系。",
                tone: .calm
            ))
        }
        
        if notes.isEmpty {
            notes.append("目前由本地行为轨迹初判；配置可用 AI 端点后，每隔 6 小时会自动精读正文提炼深度性格概念。")
        }
        
        let title = streak >= 3 ? "有节奏感的实干记录者" : "持续耕耘的思考者"
        let summary = "基于当前 \(totalDocs) 篇本地文稿与 \(weeklyReports.count) 份周报的初判：你习惯把想法直接落到文字与结构里，不绕弯子。接通 AI 端点后，系统将每 6 小时自动细读近期内容，生成更犀利、更贴合文风的性格概念与个性弹幕。"
        
        return UserPersonalityProfile(
            tags: Array(tags.prefix(7)),
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
