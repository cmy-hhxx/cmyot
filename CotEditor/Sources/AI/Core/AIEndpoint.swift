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
            case .openAIResponses:
                String(localized: "ai.endpoint.openAIResponses.label",
                       defaultValue: "OpenAI Responses",
                       table: "AI")
            case .openAIChatCompletions:
                String(localized: "ai.endpoint.openAIChatCompletions.label",
                       defaultValue: "OpenAI Chat Completions",
                       table: "AI")
            case .anthropicMessages:
                String(localized: "ai.endpoint.anthropicMessages.label",
                       defaultValue: "Anthropic Messages",
                       table: "AI")
            case .googleGemini:
                String(localized: "ai.endpoint.googleGemini.label",
                       defaultValue: "Google Gemini",
                       table: "AI")
            case .ollama:
                String(localized: "ai.endpoint.ollama.label",
                       defaultValue: "Ollama (Local)",
                       table: "AI")
        }
    }
    
    
    /// A short hint about which services this protocol works with.
    var hint: String {
        
        switch self {
            case .openAIResponses:
                String(localized: "ai.endpoint.openAIResponses.hint",
                       defaultValue: "OpenAI's newer API; some compatible services implement it too.",
                       table: "AI")
            case .openAIChatCompletions:
                String(localized: "ai.endpoint.openAIChatCompletions.hint",
                       defaultValue: "The most widely supported protocol: OpenAI, DeepSeek, Moonshot, Qwen, OpenRouter, LM Studio and others.",
                       table: "AI")
            case .anthropicMessages:
                String(localized: "ai.endpoint.anthropicMessages.hint",
                       defaultValue: "Claude models.",
                       table: "AI")
            case .googleGemini:
                String(localized: "ai.endpoint.googleGemini.hint",
                       defaultValue: "Gemini models.",
                       table: "AI")
            case .ollama:
                String(localized: "ai.endpoint.ollama.hint",
                       defaultValue: "Ollama running on this Mac; no API key is needed by default.",
                       table: "AI")
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
