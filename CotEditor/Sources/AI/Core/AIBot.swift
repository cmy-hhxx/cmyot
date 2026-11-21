//
//  AIBot.swift
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

/// GrokBot-inspired specialized AI bot identity representing a distinct editor capability.
nonisolated enum AIBotID: String, CaseIterable, Identifiable, Codable, Sendable {
    
    case ghost
    case translate
    case summarize
    case explain
    case weeklyReport
    case weeklyReportItem
    case interactiveChart
    case ocrPolish
    case organizeAndMerge
    case persona
    
    var id: String { self.rawValue }
    
    
    init(action: AIAction) {
        
        switch action {
            case .translate: self = .translate
            case .summarize: self = .summarize
            case .explain: self = .explain
            case .weeklyReport: self = .weeklyReport
            case .weeklyReportItem: self = .weeklyReportItem
            case .interactiveChart: self = .interactiveChart
            case .ocrPolish: self = .ocrPolish
            case .organizeAndMerge: self = .organizeAndMerge
        }
    }
    
    
    var linkedAction: AIAction? {
        
        switch self {
            case .translate: .translate
            case .summarize: .summarize
            case .explain: .explain
            case .weeklyReport: .weeklyReport
            case .weeklyReportItem: .weeklyReportItem
            case .interactiveChart: .interactiveChart
            case .ocrPolish: .ocrPolish
            case .organizeAndMerge: .organizeAndMerge
            case .ghost, .persona: nil
        }
    }
    
    
    var handle: String {
        
        switch self {
            case .ghost: "@GhostBot"
            case .translate: "@TranslateBot"
            case .summarize: "@SummaryBot"
            case .explain: "@ExplainBot"
            case .weeklyReport: "@WeeklyBot"
            case .weeklyReportItem: "@SnippetBot"
            case .interactiveChart: "@ChartBot"
            case .ocrPolish: "@OCRBot"
            case .organizeAndMerge: "@TidyBot"
            case .persona: "@PersonaBot"
        }
    }
    
    
    var displayName: String {
        
        switch self {
            case .ghost: "续写幽灵"
            case .translate: "双语翻译官"
            case .summarize: "极简提炼师"
            case .explain: "大白话解释官"
            case .weeklyReport: "周报搭子"
            case .weeklyReportItem: "周报速记员"
            case .interactiveChart: "图表画师"
            case .ocrPolish: "识图整理员"
            case .organizeAndMerge: "工作区整理师"
            case .persona: "性格观察员"
        }
    }
    
    
    var tagline: String {
        
        switch self {
            case .ghost: "光标后静默预测半句，按 Tab 一次落笔"
            case .translate: "中英地道德互译，保留代码与格式骨架"
            case .summarize: "剥离铺垫，提炼高信噪比纯文本要点"
            case .explain: "去掉黑话与术语堆砌，几句话讲清重点"
            case .weeklyReport: "聚合片段并参考历史文风，直接说人话"
            case .weeklyReportItem: "选中记录一秒收编进本周周报素材库"
            case .interactiveChart: "把表格或杂乱数字变成可交互 HTML 图表"
            case .ocrPolish: "结合本地 OCR 与视觉纠错还原表格代码"
            case .organizeAndMerge: "多窗口零散草稿归类合并并重起正经标题"
            case .persona: "每 6 小时静默感知写作习惯，凝练个性弹幕"
        }
    }
    
    
    var symbolName: String {
        
        switch self {
            case .ghost: "bolt.horizontal.fill"
            case .translate: "character.bubble.fill"
            case .summarize: "text.alignleft"
            case .explain: "lightbulb.fill"
            case .weeklyReport: "calendar.badge.checkmark"
            case .weeklyReportItem: "text.badge.plus"
            case .interactiveChart: "chart.xyaxis.line"
            case .ocrPolish: "doc.text.viewfinder"
            case .organizeAndMerge: "square.stack.3d.up.fill"
            case .persona: "theatermasks.fill"
        }
    }
    
    
    var accentHex: String {
        
        switch self {
            case .ghost: "#10B981"
            case .translate: "#3B82F6"
            case .summarize: "#6366F1"
            case .explain: "#F59E0B"
            case .weeklyReport: "#0EA5E9"
            case .weeklyReportItem: "#14B8A6"
            case .interactiveChart: "#EC4899"
            case .ocrPolish: "#8B5CF6"
            case .organizeAndMerge: "#F97316"
            case .persona: "#E11D48"
        }
    }
    
    
    var analyticsFeatureKey: String {
        
        switch self {
            case .ghost: "nextToken"
            case .persona: "personalityAnalyze"
            default: self.linkedAction?.analyticsKey ?? self.rawValue
        }
    }
    
    
    var defaultSampleInput: String {
        
        switch self {
            case .ghost: "今天把设置界面重写了一遍，接下来"
            case .translate: "The local SQLite migration now preserves all API endpoints, keys, and user avatars."
            case .summarize: "本周重构了设置窗口为侧边栏模式，补全了本地数据库迁移时对 API Key 和头像的备份，同时修复了 Vim Visual 模式下 j/k 移动留下的 1px 残影问题。"
            case .explain: "通过对 CAShapeLayer 显式绑定 shadowPath 并对 Selection 变动范围做上下 6pt 像素对齐重绘，消除亚像素残影。"
            case .weeklyReport: "1. 修复了分屏放大下的快捷键冲突\n2. 完成了个人数据看板重构\n3. 优化了本地词库续写"
            case .weeklyReportItem: "给个人设置加了 ASCII 通行证和 5 套主题配色，支持导出 PNG"
            case .interactiveChart: "周一: 1800字, 周二: 2400字, 周三: 3100字, 周四: 1500字, 周五: 2700字"
            case .ocrPolish: "CotEditor 7.O  设 置 -> AI 助 手\n端 点 : deepseek-chat  延 迟 210 ms"
            case .organizeAndMerge: "草稿1：周末去买咖啡豆；草稿2：下周先把设置页精简和数据库迁移写完，再测试单副本构建。"
            case .persona: "常在深夜写技术总结，喜欢用直白短句和分点，写完代码必先测试再 commit 推送。"
        }
    }
    
    
    var defaultSystemPrompt: String {
        
        if let action = self.linkedAction {
            return action.defaultSystemPrompt
        }
        switch self {
            case .ghost:
                return "你是嵌入编辑器光标处的续写幽灵。只接续光标后最自然的半句或短词，不重复前文，不加引号与解释。"
            case .persona:
                return """
                你是一位敏锐、幽默但不刻薄的私人写作观察员。阅读用户近期写下的文字与习惯，提炼出最贴切的人物概念标题、深入理解与 5~7 个不超过 8 个汉字的个性弹幕标签（如「深夜架构狂」「极简主义者」「说人话专家」）。严格输出 JSON，不添油加醋。
                """
            default:
                return ""
        }
    }
}


/// Per-bot persisted configuration (enabled toggle, dedicated model override, tone/persona, and temperature).
nonisolated struct AIBotConfig: Codable, Sendable, Equatable {
    
    var isEnabled: Bool = true
    var modelOverride: String = ""
    var customPersona: String = ""
    var temperature: Double? = nil
    
    
    init(
        isEnabled: Bool = true,
        modelOverride: String = "",
        customPersona: String = "",
        temperature: Double? = nil
    ) {
        self.isEnabled = isEnabled
        self.modelOverride = modelOverride
        self.customPersona = customPersona
        self.temperature = temperature
    }
    
    
    enum CodingKeys: String, CodingKey {
        case isEnabled, modelOverride, customPersona, temperature
    }
    
    
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        self.modelOverride = try container.decodeIfPresent(String.self, forKey: .modelOverride) ?? ""
        self.customPersona = try container.decodeIfPresent(String.self, forKey: .customPersona) ?? ""
        self.temperature = try container.decodeIfPresent(Double.self, forKey: .temperature)
    }
}


/// Manages per-bot settings, prompts, and model routing backed by `CotLocalDatabase`.
@MainActor @Observable final class AIBotStore {
    
    static let shared = AIBotStore()
    
    struct PersonaPreset: Identifiable, Sendable {
        let id: String
        let title: String
        let prompt: String
    }
    
    static let personaPresets: [PersonaPreset] = [
        .init(id: "expert",
              title: "精炼技术专家",
              prompt: "严谨资深的系统工程师，回答直击本质、注重准确性与高信噪比，避免空话和冗余铺垫。"),
        .init(id: "weekly",
              title: "直白周报搭档",
              prompt: "高效务实的研发协作伙伴，善于把零散工作记录提炼为清晰、实在、不堆砌套话的周报总结。"),
        .init(id: "architect",
              title: "深度架构顾问",
              prompt: "擅长从边界设计、并发安全、可维护性与性能权衡角度审视方案的架构顾问，兼顾落地成本与长期演进。"),
        .init(id: "editor",
              title: "双语润色编辑",
              prompt: "兼具中文书面表达功底与英文技术术语准确性的编辑，善于梳理文档结构、消除翻译腔并提升可读性。"),
    ]
    
    private(set) var configs: [String: AIBotConfig] = [:]
    private let database: CotLocalDatabase
    
    
    init(database: CotLocalDatabase = .shared) {
        self.database = database
        self.reloadFromDatabase()
    }
    
    
    func reloadFromDatabase() {
        
        let raw = self.database.string(forKey: CotLocalDatabase.ConfigKey.aiBotsConfigJSON)
        guard !raw.isEmpty,
              let data = raw.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([String: AIBotConfig].self, from: data)
        else {
            self.configs = [:]
            return
        }
        self.configs = decoded
    }
    
    
    func config(for botID: AIBotID) -> AIBotConfig {
        
        var config = self.configs[botID.rawValue] ?? AIBotConfig()
        if botID == .ghost {
            config.isEnabled = self.database.bool(forKey: CotLocalDatabase.ConfigKey.aiNextTokenEnabled, default: true)
            let ghostOverride = self.database.string(forKey: CotLocalDatabase.ConfigKey.aiNextTokenModelOverride)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if config.modelOverride.isEmpty, !ghostOverride.isEmpty {
                config.modelOverride = ghostOverride
            }
        } else if botID == .persona {
            config.isEnabled = self.database.bool(forKey: CotLocalDatabase.ConfigKey.aiPersonalityAutoEnabled, default: true)
        }
        return config
    }
    
    
    func updateConfig(_ config: AIBotConfig, for botID: AIBotID) {
        
        var clean = config
        clean.modelOverride = config.modelOverride.trimmingCharacters(in: .whitespacesAndNewlines)
        self.configs[botID.rawValue] = clean
        
        if botID == .ghost {
            self.database.set(clean.isEnabled, forKey: CotLocalDatabase.ConfigKey.aiNextTokenEnabled)
            if self.database === CotLocalDatabase.shared {
                UserDefaults.standard.set(clean.isEnabled, forKey: CotLocalDatabase.ConfigKey.aiNextTokenEnabled)
            }
            self.database.set(clean.modelOverride, forKey: CotLocalDatabase.ConfigKey.aiNextTokenModelOverride)
            if self.database === CotLocalDatabase.shared {
                UserDefaults.standard.set(clean.modelOverride, forKey: CotLocalDatabase.ConfigKey.aiNextTokenModelOverride)
            }
        } else if botID == .persona {
            self.database.set(clean.isEnabled, forKey: CotLocalDatabase.ConfigKey.aiPersonalityAutoEnabled)
        }
        
        if let data = try? JSONEncoder().encode(self.configs),
           let json = String(data: data, encoding: .utf8)
        {
            self.database.set(json, forKey: CotLocalDatabase.ConfigKey.aiBotsConfigJSON)
        }
    }
    
    
    func systemPrompt(for botID: AIBotID) -> String {
        
        if let action = botID.linkedAction {
            return self.database.customStagePrompt(forKey: action.databaseConfigKey)
                ?? action.defaultSystemPrompt
        }
        let custom = self.database.string(forKey: "ai.bot.\(botID.rawValue).prompt")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return custom.isEmpty ? botID.defaultSystemPrompt : custom
    }
    
    
    func setSystemPrompt(_ prompt: String, for botID: AIBotID) {
        
        if let action = botID.linkedAction {
            self.database.set(prompt, forKey: action.databaseConfigKey)
        } else {
            self.database.set(prompt, forKey: "ai.bot.\(botID.rawValue).prompt")
        }
    }
    
    
    func resetBotToDefaults(_ botID: AIBotID) {
        
        self.setSystemPrompt(botID.defaultSystemPrompt, for: botID)
        self.updateConfig(AIBotConfig(), for: botID)
    }
    
    
    /// Resolves the effective `AIConfiguration` for a bot, honoring any per-bot model override & temperature.
    func resolvedConfiguration(
        for botID: AIBotID,
        baseConfig: AIConfiguration? = nil
    ) -> AIConfiguration {
        
        var resolved = baseConfig ?? AIConfiguration.current
        let botConfig = self.config(for: botID)
        if !botConfig.modelOverride.isEmpty {
            resolved.model = botConfig.modelOverride
        }
        if let temp = botConfig.temperature {
            resolved.temperature = temp
        }
        return resolved
    }
}
