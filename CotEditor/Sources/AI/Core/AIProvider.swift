//
//  AIProvider.swift
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

/// The service the user picked, as a preset of a protocol and a base URL.
///
/// The preset is not stored anywhere: it is derived from the stored protocol and base URL by
/// ``detect(endpoint:baseURL:)``. That keeps the preferences file unchanged and lets the
/// stored values always stay the source of truth.
nonisolated enum AIProvider: String, CaseIterable, Sendable, Codable {
    
    /// OpenAI's own service.
    case openAI
    
    /// DeepSeek.
    case deepSeek
    
    /// Moonshot (Kimi).
    case moonshot
    
    /// Alibaba's Qwen (通义千问).
    case qwen
    
    /// OpenRouter's model gateway.
    case openRouter
    
    /// Anthropic's Claude.
    case anthropic
    
    /// Google Gemini.
    case google
    
    /// Ollama running on the same machine.
    case ollama
    
    /// Any other service that speaks one of the supported protocols.
    case custom
    
    
    /// The name shown in the settings window.
    ///
    /// Brand names read the same in every language, but they still come from the catalog so
    /// the picker has a single source of strings.
    var label: String {
        
        switch self {
            case .openAI:
                String(localized: "ai.provider.openAI",
                       defaultValue: "OpenAI",
                       table: "AI")
            case .deepSeek:
                String(localized: "ai.provider.deepSeek",
                       defaultValue: "DeepSeek",
                       table: "AI")
            case .moonshot:
                String(localized: "ai.provider.moonshot",
                       defaultValue: "Moonshot (Kimi)",
                       table: "AI")
            case .qwen:
                String(localized: "ai.provider.qwen",
                       defaultValue: "Qwen (Alibaba)",
                       table: "AI")
            case .openRouter:
                String(localized: "ai.provider.openRouter",
                       defaultValue: "OpenRouter",
                       table: "AI")
            case .anthropic:
                String(localized: "ai.provider.anthropic",
                       defaultValue: "Anthropic",
                       table: "AI")
            case .google:
                String(localized: "ai.provider.google",
                       defaultValue: "Google Gemini",
                       table: "AI")
            case .ollama:
                String(localized: "ai.provider.ollama",
                       defaultValue: "Ollama (Local)",
                       table: "AI")
            case .custom:
                String(localized: "ai.provider.custom",
                       defaultValue: "Custom",
                       table: "AI")
        }
    }
    
    
    /// The protocol this service speaks.
    var endpoint: AIEndpoint {
        
        switch self {
            case .openAI, .deepSeek, .moonshot, .qwen, .openRouter, .custom:
                .openAIChatCompletions
            case .anthropic:
                .anthropicMessages
            case .google:
                .googleGemini
            case .ollama:
                .ollama
        }
    }
    
    
    /// The base URL to use when the user has not typed one.
    ///
    /// An empty string means "no default"; only ``custom`` has none.
    var defaultBaseURL: String {
        
        switch self {
            case .openAI: "https://api.openai.com/v1"
            case .deepSeek: "https://api.deepseek.com/v1"
            case .moonshot: "https://api.moonshot.cn/v1"
            case .qwen: "https://dashscope.aliyuncs.com/compatible-mode/v1"
            case .openRouter: "https://openrouter.ai/api/v1"
            case .anthropic: "https://api.anthropic.com/v1"
            case .google: "https://generativelanguage.googleapis.com/v1beta"
            case .ollama: "http://localhost:11434"
            case .custom: ""
        }
    }
    
    
    /// Derives the provider from the stored protocol and base URL.
    ///
    /// An empty base URL means "the protocol default", so a clean configuration detects as
    /// the first preset that matches those two values. Anything else is a custom service.
    ///
    /// - Parameters:
    ///   - endpoint: The stored protocol.
    ///   - baseURL: The stored base URL, possibly empty.
    /// - Returns: The matching preset, or ``custom`` when nothing matches.
    static func detect(endpoint: AIEndpoint, baseURL: String) -> AIProvider {
        
        var url = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while url.hasSuffix("/") {
            url.removeLast()
        }
        if url.isEmpty {
            url = endpoint.defaultBaseURL
        }
        
        return self.allCases.first {
            $0 != .custom && $0.endpoint == endpoint && $0.defaultBaseURL == url
        } ?? .custom
    }
}
