//
//  AIService.swift
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
import Observation

/// One thing the editor can ask the AI to do.
///
/// A case carries only what the feature means, never how a protocol encodes it, so adding a
/// feature is a matter of adding a case and its prompts. That is the seam the later ideas
/// (screenshot summary, checklists, prompt polishing, inline completion) plug into.
nonisolated enum AIAction: Sendable {
    
    /// Translate between Chinese and English, following the text's own language.
    case translate
    
    /// Summarize the text.
    case summarize
    
    /// Rewrite the text in plain, easy words.
    case explain
    
    
    /// The name shown while the request runs.
    var title: String {
        
        switch self {
            case .translate: "翻译"
            case .summarize: "总结"
            case .explain: "说人话"
        }
    }
    
    
    /// The instruction that defines the task.
    var systemPrompt: String {
        
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
        }
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


/// The entry point the rest of the app uses to talk to AI.
@MainActor @Observable final class AIService {
    
    // MARK: Public Properties
    
    /// The shared service.
    static let shared = AIService()
    
    /// Whether a request is currently running.
    private(set) var isRunning = false
    
    /// Whether the stored configuration is complete enough to make a request.
    var isConfigured: Bool {
        
        AIConfiguration.current.isUsable
    }
    
    
    // MARK: Public Methods
    
    /// Runs one action on the given text.
    ///
    /// - Parameters:
    ///   - action: What to do.
    ///   - text: The text to work on.
    ///   - context: Extra context, when the feature has some.
    ///   - images: Pictures to add, for the features that look at the screen or at a file.
    /// - Returns: The answer text.
    /// - Throws: ``AIError`` when the request fails.
    func run(_ action: AIAction, on text: String, context: String? = nil, images: [AIImage] = []) async throws -> String {
        
        let messages: [AIMessage] = [
            .system(action.systemPrompt),
            .user(action.prompt(for: text, context: context), images: images),
        ]
        
        return try await self.send(messages)
    }
    
    
    /// Checks that the configuration actually reaches the service.
    ///
    /// - Returns: The short reply from the model.
    /// - Throws: ``AIError`` when the request fails.
    func testConnection() async throws -> String {
        
        try await self.send([
            .system("你是一个连通性测试。无论收到什么，都只回复两个字：可用。"),
            .user("测试"),
        ])
    }
    
    
    // MARK: Private Methods
    
    /// Sends messages, keeping the running flag in sync.
    ///
    /// - Parameter messages: The conversation to send.
    /// - Returns: The answer text.
    /// - Throws: ``AIError`` when the request fails.
    private func send(_ messages: [AIMessage]) async throws -> String {
        
        let configuration = AIConfiguration.current
        guard configuration.isUsable else { throw AIError.notConfigured }
        
        self.isRunning = true
        defer { self.isRunning = false }
        
        return try await AIClient(configuration: configuration).send(messages)
    }
}
