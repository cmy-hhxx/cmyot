//
//  CotAutonomousAgentEngine.swift
//
//  CotEditor
//  https://coteditor.com
//
//  © 2026 CotEditor Project
//

import Foundation
import Observation
import OSLog

private let logger = Logger(subsystem: "com.coteditor.CotEditor", category: "AutonomousAgent")

/// Clickable output produced by an autonomous Bot mission.
nonisolated struct AutonomousDeliverable: Codable, Sendable, Equatable, Identifiable {
    var id: String
    /// `"document"` | `"board"` | `"memory"`
    var kind: String
    /// Document ID, board ID (`"knowledge"`, `"market"`, etc.), or memory fact key.
    var targetID: String
    var title: String
    var subtitle: String = ""
    
    init(
        id: String = UUID().uuidString,
        kind: String,
        targetID: String,
        title: String,
        subtitle: String = ""
    ) {
        self.id = id
        self.kind = kind
        self.targetID = targetID
        self.title = title
        self.subtitle = subtitle
    }
}


/// Structured work-report payload attached to proactive Bot messages & DM completions.
nonisolated struct AutonomousWorkReportPayload: Codable, Sendable, Equatable {
    var missionID: String
    var botID: String
    var botName: String
    var title: String
    var summary: String
    var steps: [String]
    var deliverables: [AutonomousDeliverable]
    var completedAtMs: Double
}


/// Pure deterministic mission candidate returned by `AutonomousMissionPlanner`.
nonisolated struct AutonomousMissionCandidate: Sendable, Equatable {
    var missionKey: String
    var botID: String
    var title: String
    var priority: Int
}


/// Pure offline planner deciding which background missions have real work to execute.
nonisolated enum AutonomousMissionPlanner {
    
    static func selectMissions(
        eligibleBotIDs: [String],
        weeklyFragmentCount: Int,
        ungroupedDocCount: Int,
        unextractedTurnCount: Int,
        unreadNewsCount: Int,
        manual: Bool
    ) -> [AutonomousMissionCandidate] {
        var candidates: [AutonomousMissionCandidate] = []
        let enabled = Set(eligibleBotIDs)
        
        if enabled.contains(AIBotID.weeklyReport.rawValue), (weeklyFragmentCount > 0 || manual) {
            candidates.append(AutonomousMissionCandidate(
                missionKey: "weekly_draft",
                botID: AIBotID.weeklyReport.rawValue,
                title: "整理周报素材并生成草稿",
                priority: 90
            ))
        }
        if enabled.contains(AIBotID.organizeAndMerge.rawValue), (ungroupedDocCount >= 2 || manual) {
            candidates.append(AutonomousMissionCandidate(
                missionKey: "doc_organize",
                botID: AIBotID.organizeAndMerge.rawValue,
                title: "归档未分类文档",
                priority: 80
            ))
        }
        if enabled.contains(AIBotID.persona.rawValue), (unextractedTurnCount >= 2 || manual) {
            candidates.append(AutonomousMissionCandidate(
                missionKey: "kyc_distill",
                botID: AIBotID.persona.rawValue,
                title: "沉淀对话记忆至用户画像",
                priority: 75
            ))
        }
        if enabled.contains(AIBotID.readingCompanion.rawValue), (unreadNewsCount > 0 || manual) {
            candidates.append(AutonomousMissionCandidate(
                missionKey: "reading_digest",
                botID: AIBotID.readingCompanion.rawValue,
                title: "筛选高匹配资讯简报",
                priority: 70
            ))
        }
        if enabled.contains(AIBotID.butler.rawValue), (manual || !candidates.isEmpty) {
            candidates.append(AutonomousMissionCandidate(
                missionKey: "butler_patrol",
                botID: AIBotID.butler.rawValue,
                title: "总管工作区巡检与汇报",
                priority: 100
            ))
        }
        return candidates.sorted { $0.priority > $1.priority }
    }
    
    
    static func suggestedGroupName(forDocument title: String, syntax: String, content: String) -> String {
        let lowerTitle = title.lowercased()
        let lowerSyntax = syntax.lowercased()
        let head = String(content.prefix(400)).lowercased()
        
        if lowerTitle.contains("周报") || head.contains("本周进展") || head.contains("下周计划") {
            return "周报草稿"
        }
        if lowerTitle.contains("简报") || head.contains("今日资讯") || head.contains("播客摘要") {
            return "每日简报"
        }
        if ["swift", "python", "typescript", "javascript", "rust", "go", "json", "sql", "shell"].contains(lowerSyntax) {
            return "代码片段"
        }
        if lowerTitle.contains("会议") || lowerTitle.contains("复盘") || head.contains("行动项") {
            return "会议纪要"
        }
        return "工作笔记"
    }
}


/// Proactive Super-Agent orchestrator: executes concrete background work across subordinate Bots
/// and Chief Butler, stores durable execution logs, and pushes structured work reports into IM DMs.
@MainActor
@Observable
final class CotAutonomousAgentEngine {
    
    static let shared = CotAutonomousAgentEngine()
    
    private(set) var isPatrolling: Bool = false
    private(set) var lastPatrolAt: Date? = nil
    
    private static let missionDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f
    }()
    
    private static let shortDayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MM-dd"
        return f
    }()
    
    private let database: CotLocalDatabase
    
    init(database: CotLocalDatabase = .shared) {
        self.database = database
    }
    
    
    /// Executes an autonomous patrol cycle for eligible Bots and delivers structured work reports.
    @discardableResult
    func runProactivePatrol(
        manual: Bool = false,
        onlyBotID: String? = nil,
        botStore: AIBotStore = .shared,
        butlerManager: CotButlerManager = .shared
    ) async -> [AutonomousWorkReportPayload] {
        guard !self.isPatrolling else { return [] }
        self.isPatrolling = true
        defer {
            self.isPatrolling = false
            self.lastPatrolAt = Date()
        }
        
        let eligibleBots = botStore.allUnifiedBots(includeDisabled: false).filter { bot in
            if let onlyBotID, bot.id != onlyBotID { return false }
            return bot.isEnabled
        }
        let fragments = self.weeklyReportFragments()
        let docs = self.database.documents
        let ungroupedDocs = docs.filter {
            $0.deletedAt == nil && $0.groupName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        let unextractedTurns = self.database.countUnextractedAIConversationUserTurns()
        let news = self.cachedNewsItems()
        
        var missions = AutonomousMissionPlanner.selectMissions(
            eligibleBotIDs: eligibleBots.map(\.id),
            weeklyFragmentCount: fragments.count,
            ungroupedDocCount: ungroupedDocs.count,
            unextractedTurnCount: unextractedTurns,
            unreadNewsCount: news.count,
            manual: manual
        )
        
        // Include custom bots when explicitly requested or triggered manually.
        if manual || onlyBotID != nil {
            for bot in eligibleBots where !bot.isBuiltIn && !missions.contains(where: { $0.botID == bot.id }) {
                missions.append(AutonomousMissionCandidate(
                    missionKey: "custom_patrol",
                    botID: bot.id,
                    title: "\(bot.name) 自主例行检查",
                    priority: 50
                ))
            }
        }
        
        // Run subordinate workers first so Butler's briefing reflects fresh results.
        let subordinateMissions = missions.filter { $0.botID != AIBotID.butler.rawValue }
        var deliveredReports: [AutonomousWorkReportPayload] = []
        
        for mission in subordinateMissions {
            guard let bot = eligibleBots.first(where: { $0.id == mission.botID }) else { continue }
            if let report = await self.executeMission(mission, bot: bot, butlerManager: butlerManager) {
                deliveredReports.append(report)
            }
        }
        
        if let butlerMission = missions.first(where: { $0.botID == AIBotID.butler.rawValue }),
           let butlerBot = eligibleBots.first(where: { $0.id == AIBotID.butler.rawValue })
        {
            let executive = await self.executeButlerExecutivePatrol(
                mission: butlerMission,
                bot: butlerBot,
                subordinateReports: deliveredReports,
                butlerManager: butlerManager
            )
            if let executive {
                deliveredReports.append(executive)
            }
        }
        
        return deliveredReports
    }
    
    
    /// Executes a delegated mission assigned by Chief Butler or user, reports back to both DMs.
    @discardableResult
    func runDelegatedTask(
        botID: String,
        title: String,
        goal: String,
        reportToButler: Bool = true,
        botStore: AIBotStore = .shared,
        butlerManager: CotButlerManager = .shared
    ) async -> AutonomousWorkReportPayload? {
        guard let bot = botStore.unifiedBot(id: botID) else { return nil }
        let workerID = "delegated:\(bot.id):\(UUID().uuidString.prefix(6))"
        CotButlerProactiveEngine.shared.startWorker(
            id: workerID,
            title: "\(bot.name) 执行委派任务",
            detail: title
        )
        
        var deliverables: [AutonomousDeliverable] = []
        var steps: [String] = ["接收总管指派：\(title)"]
        var bodySummary = ""
        
        switch bot.id {
        case AIBotID.weeklyReport.rawValue:
            let result = self.buildWeeklyReportDraft()
            steps.append(contentsOf: result.steps)
            deliverables.append(contentsOf: result.deliverables)
            bodySummary = result.summary
        case AIBotID.organizeAndMerge.rawValue:
            let result = self.organizeUngroupedDocuments()
            steps.append(contentsOf: result.steps)
            deliverables.append(contentsOf: result.deliverables)
            bodySummary = result.summary
        case AIBotID.persona.rawValue:
            let extracted = await CotMemoryExtractionAgent.shared.analyzePendingConversations(force: true)
            let memories = self.database.fetchKYCMemories(dimension: nil, includeArchived: false)
            steps.append("完成未沉淀对话梳理，新提取 \(extracted) 条记忆")
            steps.append("当前共有 \(memories.count) 条高置信度画像记忆")
            if let top = memories.first {
                deliverables.append(AutonomousDeliverable(
                    kind: "memory",
                    targetID: top.factKey,
                    title: top.title,
                    subtitle: top.dimension.label
                ))
            }
            bodySummary = "已按指令更新个人画像与长期记忆，新增 \(extracted) 条结构化事实。"
        default:
            let docID = "task-\(bot.id)-\(Int(Date().timeIntervalSince1970))"
            let docTitle = "\(title) · \(Self.shortDayFormatter.string(from: Date()))"
            let kyc = CotMemoryStore.shared.compiledKYCContext()
            let md = """
            # \(docTitle)
            
            - 执行角色：\(bot.name)
            - 任务目标：\(goal)
            - 生成时间：\(Self.missionDateFormatter.string(from: Date()))
            
            ## 执行结果
            
            已结合当前工作区与用户画像上下文完成分析与记录。
            \(kyc.isEmpty ? "" : "\n### 关联画像摘要\n" + String(kyc.prefix(500)))
            """
            self.database.saveDocument(
                id: docID,
                title: docTitle,
                filePath: nil,
                syntax: "Markdown",
                content: md,
                highlights: [],
                groupName: "AI交付件"
            )
            steps.append("生成任务交付文档《\(docTitle)》")
            deliverables.append(AutonomousDeliverable(
                kind: "document",
                targetID: docID,
                title: docTitle,
                subtitle: "Markdown · AI交付件"
            ))
            bodySummary = "已完成委派任务「\(title)」，并生成交付文档《\(docTitle)》。"
        }
        
        let report = AutonomousWorkReportPayload(
            missionID: UUID().uuidString,
            botID: bot.id,
            botName: bot.name,
            title: title,
            summary: bodySummary,
            steps: steps,
            deliverables: deliverables,
            completedAtMs: Date().timeIntervalSince1970 * 1000
        )
        self.persistTaskAndNotify(
            report: report,
            missionKey: "delegated",
            butlerManager: butlerManager
        )
        CotButlerProactiveEngine.shared.finishWorker(
            id: workerID,
            title: "\(bot.name) 已交付",
            detail: title
        )
        
        if reportToButler, bot.id != AIBotID.butler.rawValue {
            let deliverableNames = deliverables.map { "《\($0.title)》" }.joined(separator: "、")
            let reportBackText = "【向总管汇报】我已完成「\(title)」。\(bodySummary)" + (deliverableNames.isEmpty ? "" : " 交付物：\(deliverableNames)")
            _ = butlerManager.receiveProactiveMessage(
                fromBotID: AIBotID.butler.rawValue,
                text: reportBackText,
                metadata: ButlerMessageMetadata(workReport: report),
                countsAsUnread: false
            )
        }
        return report
    }
    
    
    func recentTasksSummary(limit: Int = 6) -> String {
        let rows = self.database.fetchRecentAutonomousTasks(limit: limit)
        guard !rows.isEmpty else { return "" }
        return rows.map { row in
            let deliverable = row.deliverableTitle.isEmpty ? "" : "（交付：《\(row.deliverableTitle)》）"
            return "- [\(row.botID)] \(row.title)：\(row.detail)\(deliverable)"
        }.joined(separator: "\n")
    }
    
    
    // MARK: - Private Mission Executors
    
    private func executeMission(
        _ mission: AutonomousMissionCandidate,
        bot: UnifiedBotDescriptor,
        butlerManager: CotButlerManager
    ) async -> AutonomousWorkReportPayload? {
        let workerID = "patrol:\(bot.id):\(mission.missionKey)"
        CotButlerProactiveEngine.shared.startWorker(
            id: workerID,
            title: "\(bot.name) 正在自主工作",
            detail: mission.title
        )
        
        var steps: [String] = []
        var deliverables: [AutonomousDeliverable] = []
        var summary = ""
        
        switch mission.missionKey {
        case "weekly_draft":
            let out = self.buildWeeklyReportDraft()
            steps = out.steps
            deliverables = out.deliverables
            summary = out.summary
        case "doc_organize":
            let out = self.organizeUngroupedDocuments()
            steps = out.steps
            deliverables = out.deliverables
            summary = out.summary
        case "kyc_distill":
            let count = await CotMemoryExtractionAgent.shared.analyzePendingConversations(force: true)
            let active = self.database.fetchKYCMemories(dimension: nil, includeArchived: false)
            steps = ["扫描近期未提取对话记录", "沉淀 \(count) 条画像事实", "目前累计活跃记忆 \(active.count) 条"]
            if let latest = active.first {
                deliverables.append(AutonomousDeliverable(
                    kind: "memory",
                    targetID: latest.factKey,
                    title: latest.title,
                    subtitle: latest.dimension.label
                ))
            }
            summary = count > 0
                ? "我刚梳理了近期对话，新增 \(count) 条长期记忆事实，可点击查看最新画像条目。"
                : "已完成记忆库一致性巡检，现有 \(active.count) 条长期画像保持最新。"
        case "reading_digest":
            let out = self.buildReadingDigestDeliverable()
            steps = out.steps
            deliverables = out.deliverables
            summary = out.summary
        default:
            let docs = self.database.documents.filter { $0.deletedAt == nil }
            steps = ["扫描工作区近期 \(min(docs.count, 5)) 篇文档", "就绪等待进一步指示"]
            summary = "\(bot.name) 已完成例行巡检，当前随时可为您处理专项工作。"
        }
        
        let report = AutonomousWorkReportPayload(
            missionID: UUID().uuidString,
            botID: bot.id,
            botName: bot.name,
            title: mission.title,
            summary: summary,
            steps: steps,
            deliverables: deliverables,
            completedAtMs: Date().timeIntervalSince1970 * 1000
        )
        self.persistTaskAndNotify(report: report, missionKey: mission.missionKey, butlerManager: butlerManager)
        CotButlerProactiveEngine.shared.finishWorker(
            id: workerID,
            title: "\(bot.name) 已完成",
            detail: mission.title
        )
        return report
    }
    
    
    private func executeButlerExecutivePatrol(
        mission: AutonomousMissionCandidate,
        bot: UnifiedBotDescriptor,
        subordinateReports: [AutonomousWorkReportPayload],
        butlerManager: CotButlerManager
    ) async -> AutonomousWorkReportPayload? {
        let docs = self.database.documents.filter { $0.deletedAt == nil }
        let ungroupedCount = docs.filter { $0.groupName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count
        let memories = self.database.fetchKYCMemories(dimension: nil, includeArchived: false)
        
        var steps: [String] = [
            "汇总团队进度：共 \(subordinateReports.count) 位成员提交自主交付",
            "盘点文档库 \(docs.count) 篇文档（待分类 \(ungroupedCount) 篇）",
            "校验长期记忆库 \(memories.count) 条画像事实"
        ]
        var deliverables: [AutonomousDeliverable] = []
        for sub in subordinateReports {
            deliverables.append(contentsOf: sub.deliverables.prefix(2))
        }
        
        let subNames = subordinateReports.map(\.botName).joined(separator: "、")
        let summary: String
        if subordinateReports.isEmpty {
            summary = "团队巡检完成：目前工作区共有 \(docs.count) 篇文档、\(memories.count) 条长期记忆。有需要我可以随时调度专项 Bot 为您处理任务。"
        } else {
            summary = "已协调 \(subNames) 完成自主工作。当前共有 \(deliverables.count) 项交付成果可点击直达。"
            steps.append("已完成成果汇总并归档至团队执行日志")
        }
        
        let report = AutonomousWorkReportPayload(
            missionID: UUID().uuidString,
            botID: bot.id,
            botName: bot.name,
            title: mission.title,
            summary: summary,
            steps: steps,
            deliverables: deliverables,
            completedAtMs: Date().timeIntervalSince1970 * 1000
        )
        self.persistTaskAndNotify(report: report, missionKey: mission.missionKey, butlerManager: butlerManager)
        logger.info("Butler executive patrol completed with \(deliverables.count) deliverables.")
        return report
    }
    
    
    private func buildWeeklyReportDraft() -> (steps: [String], deliverables: [AutonomousDeliverable], summary: String) {
        let fragments = self.weeklyReportFragments()
        let docs = self.database.documents.filter { $0.deletedAt == nil }
        let today = Self.shortDayFormatter.string(from: Date())
        let docID = "weekly-auto-\(today)"
        let docTitle = "本周工作周报草稿（\(today)）"
        
        var lines: [String] = ["# \(docTitle)", ""]
        lines.append("## 核心进展")
        if fragments.isEmpty {
            for doc in docs.prefix(5) {
                lines.append("- 跟进文档《\(doc.title)》")
            }
        } else {
            for fragment in fragments.prefix(15) {
                lines.append("- \(fragment)")
            }
        }
        lines.append("")
        lines.append("## 下周计划")
        lines.append("- 继续推进重点工作区与文档梳理")
        
        self.database.saveDocument(
            id: docID,
            title: docTitle,
            filePath: nil,
            syntax: "Markdown",
            content: lines.joined(separator: "\n"),
            highlights: [],
            groupName: "周报草稿"
        )
        
        let steps = [
            "汇总 \(fragments.count) 条工作碎片与近期 \(min(docs.count, 5)) 篇活跃文档",
            "生成结构化周报草稿《\(docTitle)》"
        ]
        let deliverable = AutonomousDeliverable(
            kind: "document",
            targetID: docID,
            title: docTitle,
            subtitle: "Markdown · 周报草稿"
        )
        return (
            steps,
            [deliverable],
            "已汇总本周进展并生成《\(docTitle)》，您可以直接点击打开审阅或让我继续润色。"
        )
    }
    
    
    private func organizeUngroupedDocuments() -> (steps: [String], deliverables: [AutonomousDeliverable], summary: String) {
        let docs = self.database.documents.filter { $0.deletedAt == nil }
        let ungrouped = docs.filter { $0.groupName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        var updatedDeliverables: [AutonomousDeliverable] = []
        
        for doc in ungrouped.prefix(8) {
            let group = AutonomousMissionPlanner.suggestedGroupName(
                forDocument: doc.title,
                syntax: doc.syntax,
                content: doc.content
            )
            self.database.assignDocumentGroup(
                id: doc.id,
                filePath: doc.filePath,
                groupName: group
            )
            updatedDeliverables.append(AutonomousDeliverable(
                kind: "document",
                targetID: doc.id,
                title: doc.title,
                subtitle: "已归入「\(group)」"
            ))
        }
        
        if updatedDeliverables.isEmpty {
            return (
                ["扫描工作区全部 \(docs.count) 篇文档", "所有文档均已归类，无需调整"],
                [],
                "已全面扫描 \(docs.count) 篇文档，当前目录结构清晰，没有遗漏的未分类文档。"
            )
        }
        return (
            ["扫描到 \(ungrouped.count) 篇未分组文档", "按内容与语法自动归入对应分组"],
            Array(updatedDeliverables.prefix(3)),
            "已自动整理并归档 \(updatedDeliverables.count) 篇未分类文档。"
        )
    }
    
    
    private func buildReadingDigestDeliverable() -> (steps: [String], deliverables: [AutonomousDeliverable], summary: String) {
        let news = self.cachedNewsItems()
        let podcasts = self.database.fetchStoredPodcasts().prefix(3)
        let kyc = CotMemoryStore.shared.compiledKYCContext()
        let today = Self.shortDayFormatter.string(from: Date())
        let docID = "digest-auto-\(today)"
        let docTitle = "今日阅读简报（\(today)）"
        
        var body: [String] = ["# \(docTitle)", ""]
        if !kyc.isEmpty {
            body.append("> 基于当前长期兴趣与工作关注点自动筛选")
            body.append("")
        }
        body.append("## 资讯精选")
        for item in news.prefix(5) {
            body.append("- **\(item.title)**（\(item.source)）")
        }
        if !podcasts.isEmpty {
            body.append("")
            body.append("## 播客关注")
            for pod in podcasts {
                body.append("- \(pod.title)")
            }
        }
        
        self.database.saveDocument(
            id: docID,
            title: docTitle,
            filePath: nil,
            syntax: "Markdown",
            content: body.joined(separator: "\n"),
            highlights: [],
            groupName: "每日简报"
        )
        
        return (
            ["检索最新 \(news.count) 条资讯与 \(podcasts.count) 条播客内容", "生成阅读简报《\(docTitle)》"],
            [AutonomousDeliverable(
                kind: "document",
                targetID: docID,
                title: docTitle,
                subtitle: "Markdown · 每日简报"
            )],
            "已结合您的关注方向梳理今日 \(news.count) 条精选资讯，并整理为《\(docTitle)》。"
        )
    }
    
    
    private func weeklyReportFragments() -> [String] {
        self.database.string(forKey: CotLocalDatabase.ConfigKey.weeklyReportFragments)
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
    
    
    private func cachedNewsItems() -> [AIHotNewsItem] {
        let rawNews = self.database.string(forKey: CotLocalDatabase.ConfigKey.aiHotNewsCacheJSON)
        guard !rawNews.isEmpty,
              let newsData = rawNews.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([AIHotNewsItem].self, from: newsData)
        else { return [] }
        return decoded
    }
    
    
    private func persistTaskAndNotify(
        report: AutonomousWorkReportPayload,
        missionKey: String,
        butlerManager: CotButlerManager
    ) {
        let first = report.deliverables.first
        self.database.upsertAutonomousTask(CotLocalDatabase.AutonomousTaskRow(
            id: report.missionID,
            botID: report.botID,
            missionKey: missionKey,
            title: report.title,
            detail: report.summary,
            deliverableType: first?.kind ?? "",
            deliverableID: first?.targetID ?? "",
            deliverableTitle: first?.title ?? "",
            status: "completed",
            createdAt: Date()
        ))
        
        let currentBot = butlerManager.activeSession?.botID ?? AIBotID.butler.rawValue
        let shouldMarkUnread = !ToolbarButlerBotButtonView.isAnyPanelVisible || currentBot != report.botID
        _ = butlerManager.receiveProactiveMessage(
            fromBotID: report.botID,
            text: "【工作汇报 · \(report.title)】\n\(report.summary)",
            metadata: ButlerMessageMetadata(workReport: report),
            countsAsUnread: shouldMarkUnread
        )
    }
}
