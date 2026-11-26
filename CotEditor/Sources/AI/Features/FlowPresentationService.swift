//
//  FlowPresentationService.swift
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

/// Transforms arbitrary selected workflow/architecture text into a crisp structured `FlowPresentationBlueprint`.
@MainActor
enum FlowPresentationService {
    
    static func generateBlueprint(from text: String) async -> FlowPresentationBlueprint {
        let offline = FlowPresentationParser.parseOffline(from: text)
        let config = AIBotStore.shared.resolvedConfiguration(for: .interactiveChart)
        guard AIService.shared.isConfigured, config.isUsable else {
            return offline
        }
        
        let systemPrompt = """
        你是技术演讲视觉架构师。把用户选中的工作流/系统说明拆解成严格 JSON 蓝图，用于大屏演示讲解。
        铁律：
        1. 只输出合法 JSON，禁止输出 Markdown 围栏之外的任何解释文字、教学文案或 emoji。
        2. 保留原文中的全部真实路径、目录名、步骤顺序和分支关系，严禁编造。
        3. 每个字段文案必须精炼高信噪比，严禁出现「点击」「提示」「说明」等引导废话。
        JSON 结构：
        {
          "title": "简短标题",
          "layout": "pipeline",
          "steps": [
            {"id":"step_1","indexLabel":"01","title":"短标题","badge":"英文标识","summary":"精炼一句话","linkedArtifactIDs":["art_1"],"accentTone":"blue"}
          ],
          "artifacts": [
            {"id":"art_1","label":"目录名","path":"/真实/路径","role":"权威作用","linkedStepIDs":["step_1"]}
          ],
          "branches": [
            {"id":"br_1","title":"分支名","tag":"PARALLEL","path":"/分支/路径","summary":"分支定位","relationLabel":"与主链路一致"}
          ],
          "coreTakeaway": "一句话核心结论（没有可为 null）"
        }
        layout 可选："pipeline" | "architecture" | "comparison" | "topology"。
        accentTone 可选："blue" | "teal" | "amber" | "violet" | "slate"。
        """
        
        do {
            let raw = try await AIService.shared.chat(
                [.system(systemPrompt), .user(text)],
                configuration: config,
                disablesThinking: true,
                maxOutputTokens: 1600,
                timeoutInterval: 25,
                analyticsFeature: "flow_presentation"
            )
            if let parsed = FlowPresentationParser.parseJSON(from: raw) {
                return parsed
            }
        } catch {
            // Seamlessly keep offline deterministic blueprint
        }
        return offline
    }
}
