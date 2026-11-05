//
//  AIEndpoint.swift
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

/// The wire protocol used to talk to an AI service.
///
/// Every provider that speaks one of these protocols works, which covers the hosted services
/// and the local runners that imitate them. The protocol only decides how a request is shaped;
/// the base URL and the model name are free-form, so providers such as DeepSeek, Moonshot,
/// OpenRouter or LM Studio reach the same code through their OpenAI-compatible endpoint.
nonisolated enum AIEndpoint: String, CaseIterable, Sendable, Codable {
    
    /// OpenAI's newer Responses API.
    case openAIResponses
    
    /// OpenAI Chat Completions, also spoken by most compatible services.
    case openAIChatCompletions
    
    /// Anthropic Messages API.
    case anthropicMessages
    
    /// Google Gemini API.
    case googleGemini
    
    /// Ollama's local chat endpoint.
    case ollama
    
    
    /// The name shown in the settings window.
    var label: String {
        
        switch self {
            case .openAIResponses: "OpenAI Responses"
            case .openAIChatCompletions: "OpenAI Chat Completions"
            case .anthropicMessages: "Anthropic Messages"
            case .googleGemini: "Google Gemini"
            case .ollama: "Ollama (本地)"
        }
    }
    
    
    /// A short hint about which services this protocol works with.
    var hint: String {
        
        switch self {
            case .openAIResponses: "OpenAI 官方的新版接口，也兼容部分第三方实现。"
            case .openAIChatCompletions: "兼容面最广：OpenAI、DeepSeek、Moonshot、通义、OpenRouter、LM Studio 等。"
            case .anthropicMessages: "Claude 系列模型。"
            case .googleGemini: "Gemini 系列模型。"
            case .ollama: "本机运行的 Ollama，默认无需 API Key。"
        }
    }
    
    
    /// The base URL to start from when the user has not typed one.
    var defaultBaseURL: String {
        
        switch self {
            case .openAIResponses, .openAIChatCompletions: "https://api.openai.com/v1"
            case .anthropicMessages: "https://api.anthropic.com/v1"
            case .googleGemini: "https://generativelanguage.googleapis.com/v1beta"
            case .ollama: "http://localhost:11434"
        }
    }
    
    
    /// The path appended to the base URL, relative to it.
    var path: String {
        
        switch self {
            case .openAIResponses: "responses"
            case .openAIChatCompletions: "chat/completions"
            case .anthropicMessages: "messages"
            case .googleGemini: "models/%@:generateContent"
            case .ollama: "api/chat"
        }
    }
    
    
    /// Whether an API key is required.
    var requiresAPIKey: Bool {
        
        self != .ollama
    }
    
    
    /// Whether the protocol switches to the newer structured "responses" request layout.
    var usesResponsesLayout: Bool {
        
        self == .openAIResponses
    }
}
