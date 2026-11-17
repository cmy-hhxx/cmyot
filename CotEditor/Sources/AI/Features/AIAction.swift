//
//  AIAction.swift
//
//  CotEditor
//  https://coteditor.com
//
//  Created by 1024jp on 2026-11-05.
//
//  ---------------------------------------------------------------------------
//
//  © 2026 1024jp
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

/// One thing the editor can ask the AI to do.
///
/// A case carries only what the feature means, never how a protocol encodes it, so adding a
/// feature is a matter of adding a case and its prompts.
nonisolated enum AIAction: Sendable, CaseIterable {
    
    /// Translate between Chinese and English, following the text's own language.
    case translate
    
    /// Summarize the text.
    case summarize
    
    /// Rewrite the text in plain, easy words.
    case explain
    
    /// Turn notes or work logs into a structured weekly report.
    case weeklyReport
    
    /// Turn a selected snippet into a concise bullet item for a weekly report.
    case weeklyReportItem
    
    /// Generate an interactive HTML/SVG chart from tabular or structured data.
    case interactiveChart
    
    /// Polish or structure OCR-extracted text (with optional multimodal image).
    case ocrPolish
    
    
    /// The name shown while the request runs.
    var title: String {
        
        switch self {
            case .translate:
                String(localized: "ai.action.translate",
                       defaultValue: "Translate",
                       table: "AI")
            case .summarize:
                String(localized: "ai.action.summarize",
                       defaultValue: "Summarize",
                       table: "AI")
            case .explain:
                String(localized: "ai.action.explain",
                       defaultValue: "Explain",
                       table: "AI")
            case .weeklyReport:
                String(localized: "ai.action.weeklyReport",
                       defaultValue: "Generate Weekly Report",
                       table: "AI")
            case .weeklyReportItem:
                String(localized: "ai.action.weeklyReportItem",
                       defaultValue: "Turn Into Weekly Report Item",
                       table: "AI")
            case .interactiveChart:
                String(localized: "ai.action.interactiveChart",
                       defaultValue: "AI Interactive Chart",
                       table: "AI")
            case .ocrPolish:
                String(localized: "ai.action.ocrPolish",
                       defaultValue: "OCR + AI Smart Extract",
                       table: "AI")
        }
    }
    
    
    /// The database configuration key that overrides this action's prompt.
    var databaseConfigKey: String {
        
        switch self {
            case .translate: CotLocalDatabase.ConfigKey.promptTranslate
            case .summarize: CotLocalDatabase.ConfigKey.promptSummarize
            case .explain: CotLocalDatabase.ConfigKey.promptExplain
            case .weeklyReport: CotLocalDatabase.ConfigKey.promptWeeklyReport
            case .weeklyReportItem: CotLocalDatabase.ConfigKey.promptWeeklyReportPart
            case .interactiveChart: CotLocalDatabase.ConfigKey.promptChart
            case .ocrPolish: CotLocalDatabase.ConfigKey.promptOCR
        }
    }
    
    
    /// The built-in default instruction that defines the task.
    var defaultSystemPrompt: String {
        
        switch self {
            case .translate:
                """
                你是一名专业翻译。规则：
                1. 中文内容翻译成地道的英文，英文内容翻译成地道的中文，其它语言翻译成中文。
                2. 保持原文的 Markdown 结构、代码块、行内代码、链接和标点风格。
                3. 专有名词、产品名、代码标识符不翻译。
                4. 只输出译文本身，不要解释、不要引号、不要“以下是译文”之类的前缀。
                """
            case .summarize:
                """
                你是一名擅长提炼的编辑。规则：
                1. 用与原文相同的语言总结，长度约为原文的 1/4，最多 6 条。
                2. 用 Markdown 无序列表输出，每条一句话，抓结论而不是复述过程。
                3. 保留关键数字、人名、日期和结论性判断。
                4. 只输出总结本身，不要前言和后记。
                """
            case .explain:
                """
                你是一名把复杂内容讲明白的同事。规则：
                1. 用与原文相同的语言，把内容说得简洁易懂，像当面解释给同事听。
                2. 去掉行话和套话，遇到专业词就顺手用一句话解释它。
                3. 保留原文的关键结论和可执行的动作，不添加原文没有的事实。
                4. 只输出改写后的内容，不要“这段话的意思是”之类的前缀。
                """
            case .weeklyReport:
                """
                你是一名擅长整理技术与业务周报的资深专家。规则：
                1. 将用户提供的零散记录、TODO 或工作流水整合成一份结构清晰、重点突出的 Markdown 周报。
                2. 包含三个核心板块：`## 本周核心进展`、`## 关键产出与数据`、`## 下周计划与风险`。
                3. 用词精炼专业，突出“做了什么 → 解决了什么问题 → 带来了什么结果”，去掉口水话。
                4. 只输出周报 Markdown 正文，不要寒暄或额外解释。
                """
            case .weeklyReportItem:
                """
                你是一名高效的技术周报提炼助手。规则：
                1. 将用户选中的这段零散记录、代码改动或笔记，提炼成 1~2 条可以直接放进周报的 Markdown 列表项（以 `- **【模块/主题】**` 开头）。
                2. 突出核心动作、技术价值或量化结果，控制在两行以内。
                3. 只输出提炼后的周报条目本身，不要任何前缀或解释。
                """
            case .interactiveChart:
                """
                你是一名数据可视化专家。请根据用户提供的 Markdown 表格或数据，先输出一段简明的数据洞察总结（Markdown 列表，2~3 条），然后紧接着输出一个完整、可独立运行的交互式 HTML 数据图表代码块（使用 ```html ... ``` 包裹）。
                HTML 图表要求：
                1. 零外部网络依赖（纯原生 HTML5 + CSS + SVG/Canvas + Vanilla JS），支持深浅色自适应。
                2. 支持鼠标悬浮 Tooltip 显示详细数值、支持切换图表视图（柱状图 / 折线图 / 占比条）或点击列排序。
                3. 视觉现代精致，配色優雅，圆角卡片布局。
                """
            case .ocrPolish:
                """
                你是一名多模态 OCR 校对与结构化专家。规则：
                1. 结合本地 OCR 识别出的原始文本（以及附图，如有），修正明显的识别错别字、断行错误和标点混乱。
                2. 如果内容包含表格或列表，还原为整洁对齐的 Markdown 表格或列表；如果是代码片段，还原为带语法标记的代码块。
                3. 只输出整理后的纯净文本/Markdown，不要添加多余的客套话。
                """
        }
    }
    
    
    /// The instruction that defines the task.
    var systemPrompt: String {
        
        self.defaultSystemPrompt
    }
    
    
    /// The user turn for a given input.
    ///
    /// - Parameters:
    ///   - text: The selected text.
    ///   - context: Extra context, such as the surrounding lines, when the feature wants it.
    /// - Returns: The message to send.
    func prompt(for text: String, context: String? = nil) -> String {
        
        var prompt = text
        
        if let context, !context.isEmpty {
            prompt = """
            上下文（仅供参考，不要翻译或总结这部分）：
            \(context)

            需要处理的内容：
            \(text)
            """
        }
        
        return prompt
    }
}
