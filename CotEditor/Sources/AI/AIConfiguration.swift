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
    
    
    // MARK: Lifecycle
    
    /// The configuration currently stored in the preferences and the keychain.
    static var current: AIConfiguration {
        
        AIConfiguration(endpoint: UserDefaults.standard[.aiEndpoint] ?? .openAIChatCompletions,
                        baseURL: UserDefaults.standard[.aiBaseURL],
                        model: UserDefaults.standard[.aiModel],
                        apiKey: AIKeychain.apiKey)
    }
    
    
    // MARK: Public Properties
    
    /// Whether the configuration can actually be used.
    var isUsable: Bool {
        
        !self.model.trimmingCharacters(in: .whitespaces).isEmpty
            && !self.resolvedBaseURL.isEmpty
            && (!self.endpoint.requiresAPIKey || !self.apiKey.isEmpty)
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
    
    
    // MARK: Public Methods
    
    /// Stores the non-secret part of the configuration.
    ///
    /// The API key is written separately, because it belongs in the keychain.
    func save() {
        
        UserDefaults.standard[.aiEndpoint] = self.endpoint
        UserDefaults.standard[.aiBaseURL] = self.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        UserDefaults.standard[.aiModel] = self.model.trimmingCharacters(in: .whitespacesAndNewlines)
        AIKeychain.apiKey = self.apiKey
    }
}
