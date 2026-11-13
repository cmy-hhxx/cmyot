//
//  AIError.swift
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

/// Errors the AI features can run into, with messages meant for the user.
nonisolated enum AIError: LocalizedError {
    
    case notConfigured
    case invalidURL(String)
    case http(status: Int, message: String?)
    case emptyResponse
    case decoding(String)
    case transport(any Error)
    case noModels
    
    
    var errorDescription: String? {
        
        switch self {
            case .notConfigured:
                String(localized: "ai.error.notConfigured",
                       defaultValue: "AI is not configured yet. Choose a service and a model in Settings › AI first.",
                       table: "AI")
            case .invalidURL(let url):
                String(format: String(localized: "ai.error.invalidURL",
                                      defaultValue: "Invalid endpoint URL: %@",
                                      table: "AI"),
                       url)
            case .http(let status, let message):
                if let message, !message.isEmpty {
                    String(format: String(localized: "ai.error.http.message",
                                          defaultValue: "Request failed (HTTP %lld): %@",
                                          table: "AI"),
                           status, message)
                } else {
                    String(format: String(localized: "ai.error.http",
                                          defaultValue: "Request failed (HTTP %lld).",
                                          table: "AI"),
                           status)
                }
            case .emptyResponse:
                String(localized: "ai.error.emptyResponse",
                       defaultValue: "The AI returned no content.",
                       table: "AI")
            case .decoding(let detail):
                String(format: String(localized: "ai.error.decoding",
                                      defaultValue: "Could not read the AI response: %@",
                                      table: "AI"),
                       detail)
            case .transport(let error):
                String(format: String(localized: "ai.error.transport",
                                      defaultValue: "Network request failed: %@",
                                      table: "AI"),
                       error.localizedDescription)
            case .noModels:
                String(localized: "ai.error.noModels",
                       defaultValue: "The service returned no models.",
                       table: "AI")
        }
    }
}
