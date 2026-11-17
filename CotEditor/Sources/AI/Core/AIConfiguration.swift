//
//  AIConfiguration.swift
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

import Defaults
import Foundation

/// Everything needed to reach the configured AI service.
nonisolated struct AIConfiguration: Sendable {
    
    // MARK: Public Properties
    
    var endpoint: AIEndpoint
    var baseURL: String
    var model: String
    var apiKey: String
    var temperature: Double?
    var reasoningEffort: String? = "low"
    
    
    // MARK: Lifecycle
    
    /// A configuration that cannot be used, for when no endpoint is configured yet.
    static let empty = AIConfiguration(endpoint: .openAIChatCompletions, baseURL: "", model: "", apiKey: "")
    
    
    /// The configuration of the endpoint currently in use.
    static var current: AIConfiguration {
        
        AIEndpointStore.activeConfiguration
    }
    
    
    // MARK: Public Properties
    
    /// Whether the configuration can actually be used.
    var isUsable: Bool {
        
        !self.model.trimmingCharacters(in: .whitespaces).isEmpty
            && !self.resolvedBaseURL.isEmpty
            && (!self.endpoint.requiresAPIKey || !self.apiKey.isEmpty)
    }
    
    
    /// The service preset the stored protocol and base URL add up to.
    var provider: AIProvider {
        
        AIProvider.detect(endpoint: self.endpoint, baseURL: self.baseURL)
    }
    
    
    /// The base URL to show as a placeholder in the settings window.
    var defaultBaseURL: String {
        
        self.endpoint.defaultBaseURL
    }
    
    
    /// The base URL in effect, falling back to the protocol default.
    ///
    /// A trailing slash is dropped, and a URL that already points at the endpoint path is
    /// accepted as-is, so pasting a full API URL works too.
    var resolvedBaseURL: String {
        
        var url = self.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if url.isEmpty {
            url = self.endpoint.defaultBaseURL
        }
        while url.hasSuffix("/") {
            url.removeLast()
        }
        
        return url
    }
    
    
    /// The request URL for this configuration.
    ///
    /// - Returns: The full endpoint URL, or `nil` when the base URL is malformed.
    var requestURL: URL? {
        
        let base = self.resolvedBaseURL
        let path = self.endpoint.path
        
        if self.endpoint == .googleGemini {
            let model = self.model.hasPrefix("models/") ? String(self.model.dropFirst("models/".count)) : self.model
            let suffix = String(format: path, model)
            
            return base.hasSuffix(suffix) ? URL(string: base) : URL(string: "\(base)/\(suffix)")
        }
        
        // accept a fully pasted endpoint URL
        if base.hasSuffix(path) {
            return URL(string: base)
        }
        
        return URL(string: "\(base)/\(path)")
    }
    
    
    /// The URL that lists the models the service offers.
    ///
    /// The same URL is used by every provider; only the path and the paging query differ per
    /// protocol. A base URL that was pasted with a full operation path is trimmed back to the
    /// service root first.
    ///
    /// - Returns: The model list URL, or `nil` when the base URL is malformed.
    var modelsRequestURL: URL? {
        
        var base = self.resolvedBaseURL
        
        for operation in ["chat/completions", "responses", "messages"] {
            let suffix = "/" + operation
            if base.hasSuffix(suffix) {
                base.removeLast(suffix.count)
                break
            }
        }
        
        let path = switch self.endpoint {
            case .openAIResponses, .openAIChatCompletions, .anthropicMessages, .googleGemini: "models"
            case .ollama: "api/tags"
        }
        let query = switch self.endpoint {
            case .anthropicMessages: "?limit=1000"
            case .googleGemini: "?pageSize=1000"
            default: ""
        }
        
        return URL(string: "\(base)/\(path)\(query)")
    }
    
    
    /// The authentication and protocol headers.
    ///
    /// Shared by the chat client and the model list so a new protocol only needs one place
    /// to describe how it authenticates.
    var requestHeaders: [String: String] {
        
        let key = self.apiKey
        
        switch self.endpoint {
            case .openAIResponses, .openAIChatCompletions:
                return key.isEmpty ? [:] : ["Authorization": "Bearer \(key)"]
            case .anthropicMessages:
                return [
                    "x-api-key": key,
                    "anthropic-version": "2023-06-01",
                ]
            case .googleGemini:
                return key.isEmpty ? [:] : ["x-goog-api-key": key]
            case .ollama:
                return [:]
        }
    }
}
