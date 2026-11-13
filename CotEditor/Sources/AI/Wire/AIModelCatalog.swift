//
//  AIModelCatalog.swift
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

/// Reads the list of models a service offers.
///
/// This is the `Wire` layer together with ``AIClient``: the URL, the authentication headers
/// and the shape of the reply are the only protocol-specific parts, so the settings pane can
/// ask any supported service for its models without knowing which one it is. The list is
/// read for the service that is currently configured.
nonisolated enum AIModelCatalog {
    
    /// Fetches the models of the given configuration.
    ///
    /// - Parameter configuration: The service to ask.
    /// - Returns: The models, in the order the service returned them.
    /// - Throws: ``AIError`` when the list cannot be fetched or is empty.
    static func fetch(configuration: AIConfiguration) async throws -> [AIModel] {
        
        guard let url = configuration.modelsRequestURL else {
            throw AIError.invalidURL(configuration.resolvedBaseURL)
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        for (field, value) in configuration.requestHeaders {
            request.setValue(value, forHTTPHeaderField: field)
        }
        
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw AIError.transport(error)
        }
        
        if let httpResponse = response as? HTTPURLResponse, !(200..<300).contains(httpResponse.statusCode) {
            throw AIError.http(status: httpResponse.statusCode, message: AIClient.errorMessage(from: data))
        }
        
        let models = try self.parse(data, endpoint: configuration.endpoint)
        
        guard !models.isEmpty else { throw AIError.noModels }
        
        return models
    }
    
    
    // MARK: Private Methods
    
    /// Reads the model list out of a protocol reply.
    ///
    /// - Parameters:
    ///   - data: The raw response body.
    ///   - endpoint: The protocol that produced the body.
    /// - Returns: The models found, possibly empty.
    /// - Throws: ``AIError`` when the body cannot be decoded at all.
    private static func parse(_ data: Data, endpoint: AIEndpoint) throws -> [AIModel] {
        
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AIError.decoding(String((String(data: data, encoding: .utf8) ?? "").prefix(200)))
        }
        
        switch endpoint {
            case .openAIResponses, .openAIChatCompletions:
                // {"data": [{"id": "gpt-4o-mini", …}, …]}
                return (object["data"] as? [[String: Any]] ?? []).compactMap { item in
                    guard let id = item["id"] as? String, !id.isEmpty else { return nil }
                    
                    return AIModel(id: id, name: id)
                }
                
            case .anthropicMessages:
                // {"data": [{"id": "claude-sonnet-4-5", "display_name": "Claude Sonnet 4.5", …}, …]}
                return (object["data"] as? [[String: Any]] ?? []).compactMap { item in
                    guard let id = item["id"] as? String, !id.isEmpty else { return nil }
                    
                    return AIModel(id: id, name: Self.displayName(item["display_name"], fallback: id))
                }
                
            case .googleGemini:
                // {"models": [{"name": "models/gemini-2.5-flash",
                //              "displayName": "Gemini 2.5 Flash",
                //              "supportedGenerationMethods": ["generateContent", …]}, …]}
                return (object["models"] as? [[String: Any]] ?? []).compactMap { item in
                    guard
                        let name = item["name"] as? String, !name.isEmpty,
                        (item["supportedGenerationMethods"] as? [String] ?? []).contains("generateContent")
                    else { return nil }
                    
                    let id = name.hasPrefix("models/") ? String(name.dropFirst("models/".count)) : name
                    
                    return AIModel(id: id, name: Self.displayName(item["displayName"], fallback: id))
                }
                
            case .ollama:
                // {"models": [{"name": "qwen3:8b", "model": "qwen3:8b", …}, …]}
                return (object["models"] as? [[String: Any]] ?? []).compactMap { item in
                    let name = item["name"] as? String ?? item["model"] as? String
                    guard let name, !name.isEmpty else { return nil }
                    
                    return AIModel(id: name, name: name)
                }
        }
    }
    
    
    /// Uses the service's display name when it has one.
    ///
    /// - Parameters:
    ///   - value: The optional display name from the reply.
    ///   - fallback: The id to show instead.
    /// - Returns: The name to show.
    private static func displayName(_ value: Any?, fallback: String) -> String {
        
        guard let name = value as? String, !name.isEmpty else { return fallback }
        
        return name
    }
}
