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
    
    /// Reorganize verbose or messy text into a clear, easy-to-understand, Tab-structured plain-text version.
    case semanticRestructure
    
    /// Turn notes or work logs into a structured weekly report.
    case weeklyReport
    
    /// Turn a selected snippet into a concise bullet item for a weekly report.
    case weeklyReportItem
    
    /// Generate an interactive HTML/SVG chart from tabular or structured data.
    case interactiveChart
    
    /// Polish or structure OCR-extracted text (with optional multimodal image).
    case ocrPolish
    
    /// Analyze all open documents across windows, merge similar content cleanly, rename them, and create a summary map.
    case organizeAndMerge
    
    
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
            case .semanticRestructure:
                AppLanguage.text("语义规整", en: "Semantic Restructure")
            case .weeklyReport:
                String(localized: "ai.action.weeklyReport",
                       defaultValue: "Summarize All to Weekly Report",
                       table: "AI")
            case .weeklyReportItem:
                String(localized: "ai.action.weeklyReportItem",
                       defaultValue: "Summarize Selection to Weekly Report",
                       table: "AI")
            case .interactiveChart:
                String(localized: "ai.action.interactiveChart",
                       defaultValue: "AI Interactive Chart",
                       table: "AI")
            case .ocrPolish:
                String(localized: "ai.action.ocrPolish",
                       defaultValue: "OCR + AI Smart Extract",
                       table: "AI")
            case .organizeAndMerge:
                String(localized: "ai.action.organizeAndMerge",
                       defaultValue: "Organize & Merge All",
                       table: "AI")
        }
    }
    
    
    /// Short stable identifier used for analytics telemetry.
    var analyticsKey: String {
        
        switch self {
            case .translate: "translate"
            case .summarize: "summarize"
            case .explain: "explain"
            case .semanticRestructure: "semanticRestructure"
            case .weeklyReport: "weeklyReport"
            case .weeklyReportItem: "weeklyReportItem"
            case .interactiveChart: "interactiveChart"
            case .ocrPolish: "ocrPolish"
            case .organizeAndMerge: "organizeAndMerge"
        }
    }
    
    
    /// The database configuration key that overrides this action's prompt.
    var databaseConfigKey: String {
        
        switch self {
            case .translate: CotLocalDatabase.ConfigKey.promptTranslate
            case .summarize: CotLocalDatabase.ConfigKey.promptSummarize
            case .explain: CotLocalDatabase.ConfigKey.promptExplain
            case .semanticRestructure: CotLocalDatabase.ConfigKey.promptSemanticRestructure
            case .weeklyReport: CotLocalDatabase.ConfigKey.promptWeeklyReport
            case .weeklyReportItem: CotLocalDatabase.ConfigKey.promptWeeklyReportPart
            case .interactiveChart: CotLocalDatabase.ConfigKey.promptChart
            case .ocrPolish: CotLocalDatabase.ConfigKey.promptOCR
            case .organizeAndMerge: CotLocalDatabase.ConfigKey.promptOrganizeMerge
        }
    }
    
    
    /// Whether the answer is prose that ends up inside a text document.
    ///
    /// Those answers are cleaned of Markdown decoration before they leave the AI layer, because
    /// `**`/backticks/pipe tables are unreadable once they are written into a plain note.
    var outputsPlainDocumentText: Bool {
        
        switch self {
            case .summarize, .weeklyReport, .weeklyReportItem:
                true
            case .translate, .explain, .semanticRestructure, .interactiveChart, .ocrPolish, .organizeAndMerge:
                false
        }
    }
    
    
    /// Whether the answer is structured plain text indented with `\t` per logical section.
    var outputsStructuredPlainText: Bool {
        
        self == .semanticRestructure
    }
    
    
    /// Legacy v1 built-in prompts that should be migrated automatically when untouched by the user.
    var legacyDefaultSystemPrompts: [String] {
        
        switch self {
            case .weeklyReport:
                [
                    """
                    你是一名擅长整理技术与业务周报的资深专家。规则：
                    1. 将用户提供的零散记录、TODO 或工作流水整合成一份结构清晰、重点突出的 Markdown 周报。
                    2. 包含三个核心板块：`## 本周核心进展`、`## 关键产出与数据`、`## 下周计划与风险`。
                    3. 用词精炼专业，突出“做了什么 → 解决了什么问题 → 带来了什么结果”，去掉口水话。
                    4. 只输出周报 Markdown 正文，不要寒暄或额外解释。
                    """,
                    """
                    你正在帮用户整理每周工作周报。核心原则：**说人话，且严格符合用户的历史周报规范。**
                    规范格式如下：
                    1. 标题行：`# {姓名}-周报-{日期范围}`（例如 `# 陈明扬-周报-20261012-1016`；若上下文给出了姓名和周期请直接使用）。
                    2. 紧接一行总览：`本周主要干了以下几件事：`，下面用数字列表 `1. ...`、`2. ...` 列出 2~5 条核心结果，每条一句话说明白做了啥、结果如何。
                    3. 按项目/工作线拆分 `## 模块名称`，每个模块下固定使用：
                       `进展：`
                       `1. ...`
                       `2. ...`
                       （如果确实有阻塞、等待别人、风险或未解决的问题，再加 `卡点：` 及数字列表；没有就别硬写。）
                    4. 如果素材里明确提到下周安排，可在最后加 `## 下周计划` 与数字列表。

                    语言要求（说人话）：
                    - 像跟直属同事/Leader 面对面同步进度一样自然直白：做了什么、现在能不能用、跑了多少数据/耗时、还在等谁或卡在哪，直接说清楚。
                    - **严禁黑话和空话**：不要出现“赋能、抓手、闭环、沉淀、拉通、对齐颗粒度、打造生态、显著提升、全链路赋能”等套话。
                    - 保留素材里的真实人名（如 `@xxx`）、具体数字、仓库/项目名和日期，绝对不要编造素材里没有的事实或数据。
                    - 如果上下文附带了历史周报示例，严格对齐它的语气、分点习惯和简洁程度。
                    - 只输出周报 Markdown 正文，不要额外前言或解释。
                    """,
                ]
            case .weeklyReportItem:
                [
                    """
                    你是一名高效的技术周报提炼助手。规则：
                    1. 将用户选中的这段零散记录、代码改动或笔记，提炼成 1~2 条可以直接放进周报的 Markdown 列表项（以 `- **【模块/主题】**` 开头）。
                    2. 突出核心动作、技术价值或量化结果，控制在两行以内。
                    3. 只输出提炼后的周报条目本身，不要任何前缀或解释。
                    """,
                    """
                    你是帮用户把零散工作记录整理成周报条目的助手。规则：
                    1. 用大白话（说人话）把选中内容提炼成 1~3 条可以直接放进周报“进展：”或“卡点：”下面的编号条目（例如 `1. ...`）。
                    2. 直接讲清“做了啥 → 现在啥状态 / 带来啥效果（或卡在哪）”，保留真实数字、日期、模块名和 `@相关同事`，禁止空洞黑话（赋能、抓手、闭环等）。
                    3. 只输出提炼后的条目本身，不要前言或解释。
                    """,
                ]
            case .summarize:
                [
                    """
                    你是一名擅长提炼的编辑。规则：
                    1. 用与原文相同的语言总结，长度约为原文的 1/4，最多 6 条。
                    2. 用 Markdown 无序列表输出，每条一句话，抓结论而不是复述过程。
                    3. 保留关键数字、人名、日期和结论性判断。
                    4. 只输出总结本身，不要前言和后记。
                    """,
                ]
            case .organizeAndMerge:
                [
                    """
                    你是一名顶尖的信息架构师与文档整理专家。用户当前在多个编辑器窗口和标签页里散落了若干文档/笔记，很多临时文档还带着随机名字（如“摸鱼的洗衣机”、“秃头的变色龙”）。
                    你的任务：
                    1. 识别所有文档中相似、重叠或同属一个主题的内容，将同类内容整理合并到一起。
                    2. 为**每一份**整理后或保留的文档起一个**清晰、简洁、完全贴合其正文实际内容**的新标题（例如“评测框架与指标整理”、“CotEditor 优化待办清单”），**严禁继续保留“摸鱼的洗衣机”之类的随机娱乐名**；每一份输入文档都必须被归入 `groups` 中并拥有准确的 `newTitle`。
                    3. 整理后的正文（`mergedContent`）必须：**清晰简洁、去掉重复与废话、排版极其工整**（合理使用 `#` / `##` 层级标题、对齐的 Markdown 表格、有序/无序列表、代码块）。
                    4. **严格保真**：保留原文所有重要事实、数字、代码、链接、人名和待办事项，不得凭空捏造或遗漏关键信息。
                    5. 严格输出一个合法的 JSON 对象（不要输出 JSON 之外的多余解释），格式如下：
                    {
                      "overview": "一句话概括本次整理结果",
                      "groups": [
                        {
                          "newTitle": "根据正文内容拟定的准确文档标题",
                          "syntax": "Markdown 或 Plain Text",
                          "summary": "一句话核心摘要",
                          "sourceIDs": ["doc_id_1", "doc_id_2"],
                          "mergedContent": "整理合并后排版工整的完整正文"
                        }
                      ],
                      "mapping": [
                        {
                          "sourceID": "doc_id_1",
                          "sourceTitle": "原文档名",
                          "action": "合并 / 重命名 / 整理保留",
                          "targetTitle": "新文档标题",
                          "note": "简短说明合并或改动点"
                        }
                      ]
                    }
                    """,
                    """
                    你是一名顶尖的信息架构师与文档整理专家。用户当前在多个编辑器窗口和标签页里散落了若干文档/笔记，很多临时文档还带着随机名字（如“摸鱼的洗衣机”、“秃头的变色龙”）。
                    你的任务：
                    1. 识别所有文档中相似、重叠或同属一个主题的内容，将同类内容整理合并到一起。
                    2. 为每一份整理后或保留的文档起一个清晰、简洁、完全贴合其正文实际内容的新标题（例如“评测框架与指标整理”、“CotEditor 优化待办清单”），严禁继续保留“摸鱼的洗衣机”之类的随机娱乐名；每一份输入文档都必须被归入 `groups` 中并拥有准确的 `newTitle`。
                    3. 整理后的正文（`mergedContent`）必须是可直接阅读的纯文本：用四个空格的缩进表示层级，条目统一用 1. 2. 3. 这样的数字编号；不要使用 # 标题符号，禁止 **、*、__、反引号、> 引用、[]() 链接、| 表格和 - 项目符号；需要强调时只用 🔴（风险/阻塞）、✅（完成）、❌（失败/取消）、⭐️（重点）这四种 emoji，不要使用其它 emoji。
                    4. 内容要求：清晰简洁、去掉重复与废话、分层清楚；代码和命令保留原样即可，不要加 Markdown 代码围栏。
                    5. 严格保真：保留原文所有重要事实、数字、代码、链接、人名和待办事项，不得凭空捏造或遗漏关键信息。
                    6. 严格输出一个合法的 JSON 对象（不要输出 JSON 之外的多余解释），格式如下：
                    {
                      "overview": "一句话概括本次整理结果",
                      "groups": [
                        {
                          "newTitle": "根据正文内容拟定的准确文档标题",
                          "syntax": "Markdown 或 Plain Text",
                          "summary": "一句话核心摘要",
                          "sourceIDs": ["doc_id_1", "doc_id_2"],
                          "mergedContent": "整理合并后排版工整的完整正文"
                        }
                      ],
                      "mapping": [
                        {
                          "sourceID": "doc_id_1",
                          "sourceTitle": "原文档名",
                          "action": "合并 / 重命名 / 整理保留",
                          "targetTitle": "新文档标题",
                          "note": "简短说明合并或改动点"
                        }
                      ]
                    }
                    """,
                ]
            default:
                []
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
                2. 只用阿拉伯数字编号（1. 2. 3.）逐条输出，每条一句话，抓结论而不是复述过程。
                3. 用四个空格的缩进表示层级，不要使用 # 标题符号，也不要用空行堆砌层级。
                4. 禁止任何 Markdown 标记：不要使用 **、*、__、反引号、> 引用、[]() 链接、| 表格，也不要用 - 或 • 做项目符号。
                5. 需要强调时只用这四个 emoji：🔴 风险/阻塞、✅ 已完成、❌ 失败/取消、⭐️ 重点；不要使用其它 emoji。
                6. 保留关键数字、人名、日期和结论性判断。
                7. 只输出总结本身，不要前言和后记。
                """
            case .explain:
                """
                你是一名把复杂内容讲明白的同事。规则：
                1. 用与原文相同的语言，把内容说得简洁易懂，像当面解释给同事听。
                2. 去掉行话和套话，遇到专业词就顺手用一句话解释它。
                3. 保留原文的关键结论和可执行的动作，不添加原文没有的事实。
                4. 只输出改写后的内容，不要“这段话的意思是”之类的前缀。
                """
            case .semanticRestructure:
                """
                你是一名擅长把啰嗦、杂乱文档梳理清晰的技术编辑。请把用户提供的内容重新梳理成结构清楚、容易理解的纯文本版本。

                内容要求：
                1. 删掉废话、重复铺垫和绕弯子的表达，把同一件事合并讲透，用直白自然的语言讲清结论、影响和需要配合的动作。
                2. 按清晰逻辑重新归类分段（例如：范围与结论 → 路径与影响 → 需要配合的动作/注意点），让读者一眼看懂重点。
                3. 严格保真：保留原文中的关键数字、日期范围、字段名、文件路径、口径差异与限制条件，绝不编造原文没有的事实，也不遗漏关键约束。
                4. 使用与原文相同的语言。

                排版要求（纯文本 Tab 分层）：
                1. 一级分节标题顶格写（可用 1. 2. 3. 编号），节与节之间空一行；禁止使用 # 标题符号。
                2. 标题下的要点与说明统一在行首用一个 Tab（\t）缩进；子要点再用两个 Tab（\t\t）缩进；要点统一用 "- " 开头。
                3. 严禁任何 Markdown 修饰符号：不要输出 **、*、__、~~、反引号 `、> 引用、| 表格或多余装饰 emoji。
                4. 只输出梳理后的正文，不要任何开场白、总结语或解释。
                """
            case .weeklyReport:
                """
                你正在帮用户整理每周工作周报。核心原则：说人话，且严格符合用户的历史周报规范。
                规范格式如下：
                1. 标题行：`# {姓名}-周报-{日期范围}`（例如 `# 陈明扬-周报-20261012-1016`；若上下文给出了姓名和周期请直接使用）。
                2. 紧接一行总览：`本周主要干了以下几件事：`，下面用数字列表 `1. ...`、`2. ...` 列出 2~5 条核心结果，每条一句话说明白做了啥、结果如何。
                3. 按项目/工作线拆分 `## 模块名称`，每个模块下固定使用：
                   `进展：`
                   `1. ...`
                   `2. ...`
                   （如果确实有阻塞、等待别人、风险或未解决的问题，再加 `卡点：` 及数字列表；没有就别硬写。）
                4. 如果素材里明确提到下周安排，可在最后加 `## 下周计划` 与数字列表。

                语言要求（说人话）：
                - 像跟直属同事/Leader 面对面同步进度一样自然直白：做了什么、现在能不能用、跑了多少数据/耗时、还在等谁或卡在哪，直接说清楚。
                - 严禁黑话和空话：不要出现“赋能、抓手、闭环、沉淀、拉通、对齐颗粒度、打造生态、显著提升、全链路赋能”等套话。
                - 保留素材里的真实人名（如 `@xxx`）、具体数字、仓库/项目名和日期，绝对不要编造素材里没有的事实或数据。
                - 如果上下文附带了历史周报示例，严格对齐它的语气、分点习惯和简洁程度。

                排版要求：
                - 用四个空格的缩进表示层级，不要使用 # 标题符号。
                - 条目统一用 1. 2. 3. 这样的数字编号。
                - 禁止 **、*、__、反引号、> 引用、[]() 链接、| 表格和 - 项目符号。
                - 需要标记状态时只用这四个 emoji：🔴 风险/阻塞、✅ 已完成、❌ 失败/取消、⭐️ 重点；不要使用其它 emoji。
                - 只输出周报正文，不要额外前言或解释。
                """
            case .weeklyReportItem:
                """
                你是帮用户把零散工作记录整理成周报条目的助手。规则：
                1. 用大白话（说人话）把选中内容提炼成 1~3 条可以直接放进周报“进展：”或“卡点：”下面的编号条目（例如 1. ...）。
                2. 直接讲清“做了啥 → 现在啥状态 / 带来啥效果（或卡在哪）”，保留真实数字、日期、模块名和 @相关同事，禁止空洞黑话（赋能、抓手、闭环等）。
                3. 不要加粗、不要任何 Markdown 标记，不要使用 # 标题符号；需要标记状态时只用 🔴、✅、❌、⭐️ 这四种 emoji。
                4. 只输出提炼后的条目本身，不要前言或解释。
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
            case .organizeAndMerge:
                """
                你是一名顶尖的信息架构师与文档整理专家。用户当前在多个编辑器窗口和标签页里散落了若干文档/笔记，很多临时文档还带着随机名字（如“摸鱼的洗衣机”、“秃头的变色龙”）。
                你的任务：
                1. 识别所有文档中相似、重叠或同属一个主题的内容，将同类内容整理合并到一起。
                2. 为每一份整理后或保留的文档起一个清晰、简洁、完全贴合其正文实际内容的新标题（例如“评测框架与指标整理”、“CotEditor 优化待办清单”，不要加 `.md` 后缀），严禁继续保留“摸鱼的洗衣机”之类的随机娱乐名；每一份输入文档都必须被归入 `groups` 中并拥有准确的 `newTitle`。
                3. 所有整理结果统一保留为纯文本（Plain Text），绝不输出 Markdown 格式：
                   - 标题（一级/分节标题）一律顶格写，行首不要加 Tab 或空格，也不要使用 # 符号。
                   - 标题下方的正式内容（段落说明、数字条目）统一在行首用一个 Tab（`\\t`）缩进；条目下如有子条目，再增加一层 Tab（`\\t\\t`）缩进，保证段落层次优雅清晰。
                   - 条目统一用 1. 2. 3. 这样的数字编号；禁止 **、*、__、反引号、> 引用、[]() 链接、| 表格和 - / • 项目符号。
                   - 需要强调时只用 🔴（风险/阻塞）、✅（完成）、❌（失败/取消）、⭐️（重点）这四种 emoji，不要使用其它 emoji。
                4. 内容要求：清晰简洁、去掉重复与废话、分层清楚；代码和命令保留原样即可，不要加 Markdown 代码围栏。
                5. 严格保真：保留原文所有重要事实、数字、代码、链接、人名和待办事项，不得凭空捏造或遗漏关键信息。
                6. 严格输出一个合法的 JSON 对象（不要输出 JSON 之外的多余解释），格式如下：
                {
                  "overview": "一句话概括本次整理结果",
                  "groups": [
                    {
                      "newTitle": "根据正文内容拟定的准确文档标题",
                      "syntax": "Plain Text",
                      "summary": "一句话核心摘要",
                      "sourceIDs": ["doc_id_1", "doc_id_2"],
                      "mergedContent": "标题顶格、正文用\\t缩进的纯文本完整内容"
                    }
                  ],
                  "mapping": [
                    {
                      "sourceID": "doc_id_1",
                      "sourceTitle": "原文档名",
                      "action": "合并 / 重命名 / 整理保留",
                      "targetTitle": "新文档标题",
                      "note": "简短说明合并或改动点"
                    }
                  ]
                }
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
