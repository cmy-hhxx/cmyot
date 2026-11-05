//
//  AIClient.swift
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
    
    
    var errorDescription: String? {
        
        switch self {
            case .notConfigured:
                "还没有配置 AI。请先在“设置 › AI”里填写接口地址、模型和 API Key。"
            case .invalidURL(let url):
                "接口地址无效：\(url)"
            case .http(let status, let message):
                if let message, !message.isEmpty {
                    "请求失败（HTTP \(status)）：\(message)"
                } else {
                    "请求失败（HTTP \(status)）"
                }
            case .emptyResponse:
                "AI 没有返回内容。"
            case .decoding(let detail):
                "无法解析 AI 的返回：\(detail)"
            case .transport(let error):
                "网络请求失败：\(error.localizedDescription)"
        }
    }
}


/// Talks to the configured AI service.
///
/// The client only knows how to turn a list of messages into one request and how to pull the
/// answer out of the reply. Everything above it (which prompt to send, where the result goes)
/// lives in `AIService`, so adding a feature never means touching the protocol code again.
nonisolated struct AIClient: Sendable {
    
    var configuration: AIConfiguration
    
    
    /// Sends the messages and returns the answer text.
    ///
    /// - Parameter messages: The conversation so far.
    /// - Returns: The answer as plain text.
    /// - Throws: ``AIError`` when the request cannot be made or the reply cannot be read.
    func send(_ messages: [AIMessage]) async throws -> String {
        
        guard self.configuration.isUsable else { throw AIError.notConfigured }
        guard let url = self.configuration.requestURL else { throw AIError.invalidURL(self.configuration.resolvedBaseURL) }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        for (field, value) in self.headers {
            request.setValue(value, forHTTPHeaderField: field)
        }
        
        request.httpBody = try JSONSerialization.data(withJSONObject: self.body(for: messages))
        
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw AIError.transport(error)
        }
        
        if let httpResponse = response as? HTTPURLResponse, !(200..<300).contains(httpResponse.statusCode) {
            throw AIError.http(status: httpResponse.statusCode, message: Self.errorMessage(from: data))
        }
        
        return try self.answer(from: data)
    }
    
    
    // MARK: Private Methods
    
    /// The authentication and protocol headers.
    private var headers: [String: String] {
        
        let key = self.configuration.apiKey
        
        switch self.configuration.endpoint {
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
    
    
    /// The JSON body for the protocol in use.
    ///
    /// - Parameter messages: The conversation to send.
    /// - Returns: A JSON-serializable body.
    private func body(for messages: [AIMessage]) -> [String: Any] {
        
        let model = self.configuration.model
        let system = messages.first { $0.role == .system }?.text ?? ""
        let conversation = messages.filter { $0.role != .system }
        
        switch self.configuration.endpoint {
            case .openAIResponses:
                var body: [String: Any] = [
                    "model": model,
                    "input": conversation.map { message in
                        [
                            "role": message.role.rawValue,
                            "content": self.openAIContent(for: message, textType: "input_text"),
                        ]
                    },
                ]
                if !system.isEmpty {
                    body["instructions"] = system
                }
                
                return body
                
            case .openAIChatCompletions:
                var body: [String: Any] = [
                    "model": model,
                    "messages": messages.map { message in
                        [
                            "role": message.role.rawValue,
                            "content": self.openAIContent(for: message, textType: "text"),
                        ]
                    },
                ]
                if let temperature = self.configuration.temperature {
                    body["temperature"] = temperature
                }
                
                return body
                
            case .anthropicMessages:
                var body: [String: Any] = [
                    "model": model,
                    "max_tokens": 4096,
                    "messages": conversation.map { message in
                        [
                            "role": message.role.rawValue,
                            "content": message.images.map {
                                [
                                    "type": "image",
                                    "source": [
                                        "type": "base64",
                                        "media_type": $0.mimeType,
                                        "data": $0.base64,
                                    ],
                                ]
                            } + [["type": "text", "text": message.text]],
                        ]
                    },
                ]
                if !system.isEmpty {
                    body["system"] = system
                }
                if let temperature = self.configuration.temperature {
                    body["temperature"] = temperature
                }
                
                return body
                
            case .googleGemini:
                var body: [String: Any] = [
                    "contents": conversation.map { message in
                        [
                            "role": message.role == .assistant ? "model" : "user",
                            "parts": message.images.map {
                                [
                                    "inline_data": [
                                        "mime_type": $0.mimeType,
                                        "data": $0.base64,
                                    ],
                                ]
                            } + [["text": message.text]],
                        ]
                    },
                ]
                if !system.isEmpty {
                    body["systemInstruction"] = ["parts": [["text": system]]]
                }
                
                return body
                
            case .ollama:
                return [
                    "model": model,
                    "stream": false,
                    "messages": messages.map { message in
                        [
                            "role": message.role.rawValue,
                            "content": message.text,
                            "images": message.images.map(\.base64),
                        ]
                    },
                ]
        }
    }
    
    
    /// The content array for the two OpenAI layouts.
    ///
    /// - Parameters:
    ///   - message: The message to encode.
    ///   - textType: The type name the layout uses for a text part.
    /// - Returns: Either a plain string or an array of content parts.
    private func openAIContent(for message: AIMessage, textType: String) -> Any {
        
        guard !message.images.isEmpty else { return message.text }
        
        return message.images.map {
            [
                "type": "input_image",
                "image_url": "data:\($0.mimeType);base64,\($0.base64)",
            ]
        } + [[
            "type": textType,
            "text": message.text,
        ]]
    }
    
    
    /// Pulls the answer text out of a protocol reply.
    ///
    /// - Parameter data: The raw response body.
    /// - Returns: The answer text.
    /// - Throws: ``AIError`` when the body does not contain an answer.
    private func answer(from data: Data) throws -> String {
        
        guard
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { throw AIError.decoding(String((String(data: data, encoding: .utf8) ?? "").prefix(200))) }
        
        let text: String?
        
        switch self.configuration.endpoint {
            case .openAIResponses:
                text = Self.openAIResponsesText(object)
            case .openAIChatCompletions:
                let message = (object["choices"] as? [[String: Any]])?.first?["message"] as? [String: Any]
                text = Self.text(fromContent: message?["content"])
            case .anthropicMessages:
                let blocks = object["content"] as? [[String: Any]]
                text = blocks?
                    .filter { $0["type"] as? String == "text" }
                    .compactMap { $0["text"] as? String }
                    .joined()
            case .googleGemini:
                let parts = (object["candidates"] as? [[String: Any]])?
                    .first
                    .flatMap { $0["content"] as? [String: Any] }
                    .flatMap { $0["parts"] as? [[String: Any]] }
                text = parts?
                    .compactMap { $0["text"] as? String }
                    .joined()
            case .ollama:
                text = (object["message"] as? [String: Any])?["content"] as? String
        }
        
        guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AIError.emptyResponse
        }
        
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    
    /// Reads the answer out of an OpenAI Responses reply.
    ///
    /// - Parameter object: The decoded reply.
    /// - Returns: The answer text, when there is one.
    private static func openAIResponsesText(_ object: [String: Any]) -> String? {
        
        // most implementations provide this shortcut
        if let text = object["output_text"] as? String, !text.isEmpty {
            return text
        }
        
        let output = object["output"] as? [[String: Any]] ?? []
        let texts = output
            .filter { $0["type"] as? String == "message" }
            .flatMap { $0["content"] as? [[String: Any]] ?? [] }
            .filter { $0["type"] as? String == "output_text" }
            .compactMap { $0["text"] as? String }
        
        return texts.isEmpty ? nil : texts.joined()
    }
    
    
    /// Reads text from an OpenAI-style content value, which is either a string or parts.
    ///
    /// - Parameter content: The content value.
    /// - Returns: The joined text, when there is one.
    private static func text(fromContent content: Any?) -> String? {
        
        if let text = content as? String {
            return text
        }
        
        let parts = content as? [[String: Any]]
        
        return parts?
            .compactMap { $0["text"] as? String }
            .joined()
    }
    
    
    /// Extracts a readable error message from an error reply.
    ///
    /// - Parameter data: The raw response body.
    /// - Returns: The message, when one can be found.
    private static func errorMessage(from data: Data) -> String? {
        
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return String(data: data, encoding: .utf8)
        }
        
        if let error = object["error"] as? [String: Any] {
            return error["message"] as? String
        }
        
        return object["message"] as? String
    }
}
