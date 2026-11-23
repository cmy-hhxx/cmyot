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

/// The service the user picked, as a preset of a protocol, base URL, curated models, and optional headers.
///
/// The preset is not stored anywhere: it is derived from the stored protocol and base URL by
/// ``detect(endpoint:baseURL:)``. That keeps the preferences file unchanged and lets the
/// stored values always stay the source of truth.
nonisolated enum AIProvider: String, CaseIterable, Sendable, Codable {
    
    /// OpenCode Go unified coding & writing gateway (featured flagship preset).
    case openCodeGo
    
    /// OpenAI's own service.
    case openAI
    
    /// Anthropic's Claude.
    case anthropic
    
    /// DeepSeek.
    case deepSeek
    
    /// Google Gemini.
    case google
    
    /// OpenRouter's model gateway.
    case openRouter
    
    /// Moonshot (Kimi).
    case moonshot
    
    /// Zhipu AI (智谱 GLM).
    case zhipu
    
    /// MiniMax.
    case miniMax
    
    /// Alibaba's Qwen (阿里云百炼 / 通义千问).
    case qwen
    
    /// ByteDance Volcengine Ark (火山方舟 / 豆包).
    case volcengine
    
    /// SiliconFlow (硅基流动).
    case siliconFlow
    
    /// AiHubMix multi-provider aggregator.
    case aiHubMix
    
    /// Ollama running on the same machine.
    case ollama
    
    /// Any other service that speaks one of the supported protocols.
    case custom
    
    
    /// All curated presets displayed in the cc-switch style quick-add grid (excluding `.custom`).
    static let curatedPresets: [AIProvider] = [
        .openCodeGo, .openAI, .anthropic, .deepSeek, .google, .openRouter,
        .moonshot, .zhipu, .miniMax, .qwen, .volcengine, .siliconFlow, .aiHubMix, .ollama,
    ]
    
    
    /// Whether this preset is highlighted as the flagship recommendation.
    var isFeatured: Bool {
        self == .openCodeGo
    }
    
    
    /// The name shown in the settings window.
    var label: String {
        switch self {
            case .openCodeGo: "OpenCode Go"
            case .openAI:
                String(localized: "ai.provider.openAI", defaultValue: "OpenAI", table: "AI")
            case .anthropic:
                String(localized: "ai.provider.anthropic", defaultValue: "Anthropic", table: "AI")
            case .deepSeek:
                String(localized: "ai.provider.deepSeek", defaultValue: "DeepSeek", table: "AI")
            case .google:
                String(localized: "ai.provider.google", defaultValue: "Google Gemini", table: "AI")
            case .openRouter:
                String(localized: "ai.provider.openRouter", defaultValue: "OpenRouter", table: "AI")
            case .moonshot:
                String(localized: "ai.provider.moonshot", defaultValue: "Kimi (Moonshot)", table: "AI")
            case .zhipu: "智谱 GLM"
            case .miniMax: "MiniMax"
            case .qwen:
                String(localized: "ai.provider.qwen", defaultValue: "通义千问 (百炼)", table: "AI")
            case .volcengine: "火山方舟"
            case .siliconFlow: "硅基流动"
            case .aiHubMix: "AiHubMix"
            case .ollama:
                String(localized: "ai.provider.ollama", defaultValue: "Ollama (本地)", table: "AI")
            case .custom:
                String(localized: "ai.provider.custom", defaultValue: "自定义网关", table: "AI")
        }
    }
    
    
    /// Short badge caption for preset cards.
    var badgeLabel: String {
        switch self {
            case .openCodeGo: "推荐"
            case .openAI: "GPT"
            case .anthropic: "Claude"
            case .deepSeek: "V3/R1"
            case .google: "Gemini"
            case .openRouter: "聚合"
            case .moonshot: "K2"
            case .zhipu: "GLM"
            case .miniMax: "M2"
            case .qwen: "Qwen"
            case .volcengine: "豆包"
            case .siliconFlow: "国产"
            case .aiHubMix: "中转"
            case .ollama: "本地"
            case .custom: "自定义"
        }
    }
    
    
    /// Brand accent hex used on cc-switch provider badges.
    var accentHex: String {
        switch self {
            case .openCodeGo: "#2F6BFF"
            case .openAI: "#10A37F"
            case .anthropic: "#D97757"
            case .deepSeek: "#4D6BFE"
            case .google: "#4285F4"
            case .openRouter: "#6366F1"
            case .moonshot: "#1D1D1F"
            case .zhipu: "#2563EB"
            case .miniMax: "#F43F5E"
            case .qwen: "#7C3AED"
            case .volcengine: "#0EA5E9"
            case .siliconFlow: "#6D28D9"
            case .aiHubMix: "#059669"
            case .ollama: "#64748B"
            case .custom: "#6B7280"
        }
    }
    
    
    /// The protocol this service speaks.
    var endpoint: AIEndpoint {
        switch self {
            case .openCodeGo, .openAI, .deepSeek, .moonshot, .zhipu, .miniMax,
                 .qwen, .volcengine, .siliconFlow, .aiHubMix, .openRouter, .custom:
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
    var defaultBaseURL: String {
        switch self {
            case .openCodeGo: "https://opencode.ai/zen/go/v1"
            case .openAI: "https://api.openai.com/v1"
            case .anthropic: "https://api.anthropic.com/v1"
            case .deepSeek: "https://api.deepseek.com/v1"
            case .google: "https://generativelanguage.googleapis.com/v1beta"
            case .openRouter: "https://openrouter.ai/api/v1"
            case .moonshot: "https://api.moonshot.cn/v1"
            case .zhipu: "https://open.bigmodel.cn/api/paas/v4"
            case .miniMax: "https://api.minimax.chat/v1"
            case .qwen: "https://dashscope.aliyuncs.com/compatible-mode/v1"
            case .volcengine: "https://ark.cn-beijing.volces.com/api/v3"
            case .siliconFlow: "https://api.siliconflow.cn/v1"
            case .aiHubMix: "https://aihubmix.com/v1"
            case .ollama: "http://localhost:11434"
            case .custom: ""
        }
    }
    
    
    /// The default model pre-selected when creating a new endpoint from this preset.
    var defaultModel: String {
        self.recommendedModels.first ?? ""
    }
    
    
    /// Curated models pre-populated into the model switcher so the user can switch immediately without waiting for `/models`.
    var recommendedModels: [String] {
        switch self {
            case .openCodeGo:
                ["kimi-k2.5", "glm-5", "minimax-m2.5", "deepseek-v4-pro", "claude-sonnet-4-5", "gpt-5.2-codex"]
            case .openAI:
                ["gpt-4.1-mini", "gpt-4.1", "gpt-4o-mini", "o4-mini"]
            case .anthropic:
                ["claude-sonnet-4-5", "claude-haiku-4-5", "claude-opus-4-1"]
            case .deepSeek:
                ["deepseek-chat", "deepseek-reasoner"]
            case .google:
                ["gemini-2.5-flash", "gemini-2.5-pro"]
            case .openRouter:
                ["anthropic/claude-sonnet-4", "deepseek/deepseek-chat", "google/gemini-2.5-flash"]
            case .moonshot:
                ["kimi-k2-0711-preview", "moonshot-v1-8k"]
            case .zhipu:
                ["glm-5", "glm-4.5-air", "glm-4-flash"]
            case .miniMax:
                ["MiniMax-M2.5", "MiniMax-Text-01"]
            case .qwen:
                ["qwen-plus", "qwen-turbo", "qwen-max", "qwen3-coder-plus"]
            case .volcengine:
                ["doubao-1-5-pro-32k", "deepseek-v3-250324"]
            case .siliconFlow:
                ["deepseek-ai/DeepSeek-V3", "Qwen/Qwen3-32B"]
            case .aiHubMix:
                ["claude-sonnet-4-5", "gpt-4.1-mini", "deepseek-chat"]
            case .ollama:
                ["qwen2.5:7b", "deepseek-r1:8b", "llama3.2:latest"]
            case .custom:
                []
        }
    }
    
    
    /// Optional default HTTP headers required or recommended by this provider.
    var defaultCustomHeaders: [String: String] {
        switch self {
            case .openCodeGo:
                ["x-opencode-session": "coteditor-go-session"]
            default:
                [:]
        }
    }
    
    
    /// Placeholder text shown in the quick-setup API Key input.
    var apiKeyPlaceholder: String {
        switch self {
            case .openCodeGo: "oc_sk_... / OpenCode Go API Key"
            case .openAI: "sk-..."
            case .anthropic: "sk-ant-..."
            case .deepSeek: "sk-..."
            case .google: "AIza..."
            case .openRouter: "sk-or-..."
            case .ollama: "本地模型通常无需填写"
            default: "粘贴 API Key"
        }
    }
    
    
    /// Builds a ready-to-save `AIEndpointProfile` pre-filled with this provider's base URL, models, and headers.
    func makeProfile(customName: String? = nil, modelOverride: String? = nil, useAnthropicProtocol: Bool = false) -> AIEndpointProfile {
        let resolvedEndpoint: AIEndpoint
        let resolvedURL: String
        if self == .openCodeGo && useAnthropicProtocol {
            resolvedEndpoint = .anthropicMessages
            resolvedURL = "https://opencode.ai/zen/go"
        } else {
            resolvedEndpoint = self.endpoint
            resolvedURL = self.defaultBaseURL
        }
        let chosenModel = (modelOverride?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
            ? modelOverride!.trimmingCharacters(in: .whitespacesAndNewlines)
            : self.defaultModel
        return AIEndpointProfile(
            name: customName ?? self.label,
            endpoint: resolvedEndpoint,
            baseURL: resolvedURL,
            model: chosenModel,
            customHeaders: self.defaultCustomHeaders,
            savedModels: self.recommendedModels
        )
    }
    
    
    /// Derives the provider from the stored protocol and base URL.
    static func detect(endpoint: AIEndpoint, baseURL: String) -> AIProvider {
        var url = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while url.hasSuffix("/") {
            url.removeLast()
        }
        if url.isEmpty {
            url = endpoint.defaultBaseURL
        }
        let lower = url.lowercased()
        if lower.contains("opencode.ai") {
            return .openCodeGo
        }
        if lower.contains("bigmodel.cn") { return .zhipu }
        if lower.contains("minimax") { return .miniMax }
        if lower.contains("volces.com") { return .volcengine }
        if lower.contains("siliconflow") { return .siliconFlow }
        if lower.contains("aihubmix") { return .aiHubMix }
        
        return self.allCases.first {
            $0 != .custom && $0.endpoint == endpoint && $0.defaultBaseURL == url
        } ?? .custom
    }
}
