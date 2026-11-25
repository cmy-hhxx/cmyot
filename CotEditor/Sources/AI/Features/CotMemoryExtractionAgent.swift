//
//  CotMemoryExtractionAgent.swift
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
import Observation

/// A structured long-term memory fact distilled from archived AI conversations.
nonisolated struct ExtractedMemoryCandidate: Equatable, Sendable {
    var dimension: KYCDimension
    var factKey: String
    var title: String
    var detail: String
    var confidence: Double
}


/// Low-priority background agent that analyzes persisted AI conversation logs (`ai_conversation_logs`)
/// and extracts durable user preferences, context, habits, and boundaries into `CotMemoryStore` (`user_kyc_memories`).
@MainActor @Observable
final class CotMemoryExtractionAgent {
    
    static let shared = CotMemoryExtractionAgent()
    
    static let minimumUnextractedUserTurns = 2
    static let minimumUnextractedUserChars = 120
    static let automaticCooldownSeconds: TimeInterval = 5 * 60
    static let debounceDelaySeconds: TimeInterval = 45
    
    private(set) var isExtracting: Bool = false
    private(set) var lastExtractedCount: Int = 0
    private(set) var lastRunAt: Date?
    private(set) var lastErrorMessage: String?
    
    private let database: CotLocalDatabase
    private let memoryStore: CotMemoryStore
    private let llmRunner: (@Sendable (_ systemPrompt: String, _ userPrompt: String) async throws -> String)?
    @ObservationIgnored private var scheduledTask: Task<Void, Never>?
    
    
    init(
        database: CotLocalDatabase = .shared,
        memoryStore: CotMemoryStore = .shared,
        llmRunner: (@Sendable (_ systemPrompt: String, _ userPrompt: String) async throws -> String)? = nil
    ) {
        self.database = database
        self.memoryStore = memoryStore
        self.llmRunner = llmRunner
    }
    
    
    isolated deinit {
        self.scheduledTask?.cancel()
    }
    
    
    /// Schedules a debounced, low-priority extraction check after an AI conversation turn completes.
    func scheduleExtractionIfNeeded(reason: String = "turn") {
        guard !CotLocalDatabase.isRunningUnitTests else { return }
        if let lastRunAt = self.lastRunAt,
           Date().timeIntervalSince(lastRunAt) < Self.automaticCooldownSeconds
        {
            return
        }
        self.scheduledTask?.cancel()
        self.scheduledTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(Self.debounceDelaySeconds))
            guard !Task.isCancelled, let self else { return }
            if CotButlerManager.shared.isStreaming {
                try? await Task.sleep(for: .seconds(30))
                guard !Task.isCancelled else { return }
            }
            _ = await self.analyzePendingConversations(force: false)
        }
    }
    
    
    /// Analyzes unextracted AI conversation turns and upserts durable memory facts (`>= 0.65` confidence).
    @discardableResult
    func analyzePendingConversations(force: Bool = false) async -> Int {
        guard !self.isExtracting else { return 0 }
        
        let pending = self.database
            .fetchAIConversationLogs(onlyUnextracted: true, limit: 80)
            .filter { !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard !pending.isEmpty else { return 0 }
        
        if !force {
            if let lastRunAt = self.lastRunAt,
               Date().timeIntervalSince(lastRunAt) < Self.automaticCooldownSeconds
            {
                return 0
            }
            let userLogs = pending.filter { $0.role == "user" }
            let userChars = userLogs.reduce(0) { $0 + $1.content.count }
            guard userLogs.count >= Self.minimumUnextractedUserTurns || userChars >= Self.minimumUnextractedUserChars else {
                return 0
            }
        }
        
        self.isExtracting = true
        self.lastErrorMessage = nil
        defer { self.isExtracting = false }
        
        let existingMemories = self.memoryStore.memories
        let userPrompt = Self.buildExtractionPrompt(logs: pending, existingMemories: existingMemories)
        
        var candidates: [ExtractedMemoryCandidate] = []
        var evidenceLabel = "memory_agent"
        var didCompleteAnalysis = false
        
        if let llmRunner = self.llmRunner {
            do {
                let raw = try await llmRunner(Self.extractionSystemPrompt, userPrompt)
                candidates = Self.parseExtractedMemories(from: raw)
                evidenceLabel = "memory_agent_llm"
                didCompleteAnalysis = true
            } catch {
                self.lastErrorMessage = error.localizedDescription
                CotLogger.shared.warning(category: .ai, "Memory extraction runner failed", error: error)
                return 0
            }
        } else if let config = self.resolvedExtractionConfiguration(), config.isUsable {
            do {
                var tuned = config
                tuned.temperature = tuned.temperature ?? 0.2
                tuned.reasoningEffort = "low"
                let client = AIClient(
                    configuration: tuned,
                    maxOutputTokens: 600,
                    timeoutInterval: 25,
                    disablesThinking: !AINextTokenPredictor.isPureReasoningModel(tuned.model)
                )
                let response = try await client.sendWithUsage([
                    .system(Self.extractionSystemPrompt),
                    .user(userPrompt),
                ])
                candidates = Self.parseExtractedMemories(from: response.text)
                evidenceLabel = tuned.model
                didCompleteAnalysis = true
            } catch {
                self.lastErrorMessage = error.localizedDescription
                CotLogger.shared.warning(category: .ai, "Background memory extraction failed", error: error)
                return 0
            }
        } else {
            candidates = Self.extractLocalHeuristicMemories(from: pending)
            evidenceLabel = "local_heuristic"
            didCompleteAnalysis = true
        }
        
        guard didCompleteAnalysis else { return 0 }
        
        let qualified = candidates.filter { $0.confidence >= 0.65 }
        self.database.withTransaction {
            for item in qualified {
                self.database.upsertKYCMemory(
                    dimension: item.dimension,
                    factKey: item.factKey,
                    title: item.title,
                    detail: item.detail,
                    confidence: item.confidence,
                    source: "memory_agent",
                    evidenceRef: evidenceLabel,
                    isPinned: nil,
                    actorBot: "MemoryAgent"
                )
            }
        }
        self.database.markAIConversationLogsExtracted(ids: pending.map(\.id))
        if !qualified.isEmpty {
            self.memoryStore.reloadMemoriesAndJournal()
            if self.database === CotLocalDatabase.shared {
                PiKernelManager.shared.scheduleWorkspaceSync()
            }
        }
        self.lastRunAt = Date()
        self.lastExtractedCount = qualified.count
        return qualified.count
    }
    
    
    private func resolvedExtractionConfiguration() -> AIConfiguration? {
        let base = AIConfiguration.current
        let personaCfg = AIBotStore.shared.resolvedConfiguration(for: .persona, baseConfig: base)
        if personaCfg.isUsable { return personaCfg }
        let butlerCfg = AIBotStore.shared.resolvedConfiguration(for: .butler, baseConfig: base)
        if butlerCfg.isUsable { return butlerCfg }
        return base.isUsable ? base : nil
    }
    
    
    // MARK: - Prompting, Parsing & Local Heuristic Fallback (Testable)
    
    nonisolated static let extractionSystemPrompt = """
    你是 CotEditor 的后台「记忆抽取 Agent」，负责从用户与 AI 的历史对话中提炼真正值得长期记住的个人画像、偏好、目标、习惯与边界。
    只提取长期稳定的信息；忽略一次性闲聊、临时查询、具体股价数字或常规礼貌回复。
    严格输出合法 JSON 对象，不要附加解释文字。
    """
    
    
    nonisolated static func buildExtractionPrompt(
        logs: [AIConversationLogRecord],
        existingMemories: [UserKYCMemoryRecord]
    ) -> String {
        let existingSummary: String = if existingMemories.isEmpty {
            "（暂无）"
        } else {
            existingMemories.prefix(20).map { mem in
                "- [\(mem.dimension.rawValue)] \(mem.factKey): \(mem.title)"
            }.joined(separator: "\n")
        }
        
        let transcript = logs.suffix(48).map { log in
            let speaker = log.role == "user" ? "用户" : "助手"
            let wsTag = log.workspaceName.isEmpty ? "" : "[\(log.workspaceName)]"
            let snippet = String(log.content.prefix(500)).replacingOccurrences(of: "\n", with: " ")
            return "(\(log.channel)\(wsTag)) \(speaker): \(snippet)"
        }.joined(separator: "\n")
        
        return """
        请分析以下用户与 AI 的对话记录，抽取出高价值的长期记忆条目（最多 6 条；如果没有值得长期记住的新事实，返回空数组 `{"memories": []}`）。

        可用维度（dimension 必须严格取下列 8 个值之一）：
        - identity: 身份、职业背景、所在城市/团队
        - cognition: 思考方式、分析框架、决策倾向
        - writingStyle: 表达偏好、行文风格、排版习惯
        - goals: 长期目标、近期重要项目、关注方向
        - finance: 投资偏好、关注板块或资产风格
        - informationDiet: 常看的信息源、博主、播客或领域
        - workflow: 日常工作流、工具使用习惯
        - taboos: 明确讨厌、禁止或不想看到的内容

        已有记忆（避免重复创建不同 fact_key；如果是补充或强化既有事实，可复用同一 fact_key）：
        \(existingSummary)

        对话记录：
        \(transcript)

        严格返回如下 JSON 结构：
        {
          "memories": [
            {
              "dimension": "writingStyle",
              "fact_key": "short_snake_case_key",
              "title": "16字以内精炼概括",
              "detail": "一句话补充说明具体偏好或背景",
              "confidence": 0.85
            }
          ]
        }
        """
    }
    
    
    nonisolated static func parseExtractedMemories(from raw: String) -> [ExtractedMemoryCandidate] {
        var cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return [] }
        
        if cleaned.hasPrefix("```") {
            var lines = cleaned.components(separatedBy: .newlines)
            if lines.first?.hasPrefix("```") == true { lines.removeFirst() }
            if lines.last?.trimmingCharacters(in: .whitespaces) == "```" { lines.removeLast() }
            cleaned = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        guard let startIdx = cleaned.firstIndex(of: "{"),
              let endIdx = cleaned.lastIndex(of: "}"),
              startIdx <= endIdx
        else { return [] }
        
        let slice = String(cleaned[startIdx...endIdx])
        guard let data = slice.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rows = obj["memories"] as? [[String: Any]]
        else { return [] }
        
        var seen: Set<String> = []
        var result: [ExtractedMemoryCandidate] = []
        
        for row in rows {
            guard let dimRaw = (row["dimension"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  let dim = KYCDimension(rawValue: dimRaw)
            else { continue }
            
            let title = ((row["title"] as? String) ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { continue }
            
            let rawKey = ((row["fact_key"] as? String) ?? (row["factKey"] as? String) ?? title)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let factKey = Self.normalizedFactKey(rawKey, fallbackTitle: title)
            guard !factKey.isEmpty else { continue }
            
            let dedupID = "\(dim.rawValue):\(factKey)"
            guard seen.insert(dedupID).inserted else { continue }
            
            let detail = ((row["detail"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let rawConfidence = (row["confidence"] as? Double)
                ?? (row["confidence"] as? NSNumber)?.doubleValue
                ?? 0.8
            let confidence = min(1.0, max(0.1, rawConfidence))
            
            result.append(ExtractedMemoryCandidate(
                dimension: dim,
                factKey: factKey,
                title: String(title.prefix(40)),
                detail: String(detail.prefix(200)),
                confidence: confidence
            ))
            if result.count >= 8 { break }
        }
        return result
    }
    
    
    /// Conservative zero-network extractor used when no AI gateway is configured:
    private nonisolated static let heuristicRules: [(regex: NSRegularExpression, dimension: KYCDimension, confidence: Double)] = [
        (try! NSRegularExpression(pattern: #"(?:记住|请记住|帮我记住)[:：]?\s*(.+)"#), .cognition, 0.86),
        (try! NSRegularExpression(pattern: #"(?:以后请|以后都|以后回答|平时请)[:：]?\s*(.+)"#), .writingStyle, 0.82),
        (try! NSRegularExpression(pattern: #"(?:我习惯|我的习惯是)[:：]?\s*(.+)"#), .workflow, 0.80),
        (try! NSRegularExpression(pattern: #"(?:我喜欢|我偏好|我更喜欢)[:：]?\s*(.+)"#), .cognition, 0.78),
        (try! NSRegularExpression(pattern: #"(?:不要给我|别给我|我不喜欢|请勿)[:：]?\s*(.+)"#), .taboos, 0.82),
    ]
    
    
    /// Zero-network deterministic fallback when the AI gateway is not configured or unreachable;
    /// captures only explicit user preference / memory declarations.
    nonisolated static func extractLocalHeuristicMemories(from logs: [AIConversationLogRecord]) -> [ExtractedMemoryCandidate] {
        var seen: Set<String> = []
        var extracted: [ExtractedMemoryCandidate] = []
        
        for log in logs where log.role == "user" {
            let text = log.content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            for rule in Self.heuristicRules {
                guard let match = rule.regex.firstMatch(in: text, range: NSRange(location: 0, length: (text as NSString).length)),
                      match.numberOfRanges > 1
                else { continue }
                
                let captured = (text as NSString).substring(with: match.range(at: 1))
                    .components(separatedBy: CharacterSet(charactersIn: "\n。！？"))
                    .first?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                guard captured.count >= 4 else { continue }
                
                let title = String(captured.prefix(24))
                let key = Self.normalizedFactKey(title, fallbackTitle: title)
                guard seen.insert("\(rule.dimension.rawValue):\(key)").inserted else { continue }
                
                extracted.append(ExtractedMemoryCandidate(
                    dimension: rule.dimension,
                    factKey: key,
                    title: title,
                    detail: String(captured.prefix(120)),
                    confidence: rule.confidence
                ))
                break
            }
            if extracted.count >= 5 { break }
        }
        return extracted
    }
    
    
    private nonisolated static func normalizedFactKey(_ raw: String, fallbackTitle: String) -> String {
        let base = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: #"\s+"#, with: "_", options: .regularExpression)
            .replacingOccurrences(of: #"[^\p{L}\p{N}_-]"#, with: "", options: .regularExpression)
        if !base.isEmpty {
            return String(base.prefix(48))
        }
        return "mem_\(UserPersonalityAnalyzer.sha256Hex(fallbackTitle).prefix(12))"
    }
}
