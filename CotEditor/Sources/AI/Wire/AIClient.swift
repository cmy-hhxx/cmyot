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

/// Talks to the configured AI service.
///
/// This is the `Wire` layer: the client only knows how to turn a list of messages into one
/// request and how to pull the answer out of the reply. Which prompt to send and what happens
/// to the result belong to `Features`, so adding a feature never means touching the protocol
/// code. The service presets, the configuration and the error type it works with live in
/// `Core`, and the authentication headers come from `AIConfiguration.requestHeaders` so the
/// model list can use exactly the same ones.
nonisolated struct AIClient: Sendable {
    
    var configuration: AIConfiguration
    
    private var wireConfig: AIConfiguration { self.configuration.wireConfiguration }
    
    
    /// Sends the messages and streams partial text chunks as they arrive, returning the final answer.
    ///
    /// - Parameters:
    ///   - messages: The conversation so far.
    ///   - onPartial: Optional callback invoked with the accumulated answer text as tokens arrive.
    /// - Returns: The answer as plain text.
    /// - Throws: ``AIError`` when the request cannot be made or the reply cannot be read.
    func send(_ messages: [AIMessage], onPartial: (@Sendable (String) -> Void)? = nil) async throws -> String {
        
        let config = self.wireConfig
        guard config.isUsable else { throw AIError.notConfigured }
        
        if let onPartial, self.supportsSSEStreaming {
            do {
                let streamed = try await self.sendStreaming(messages, onPartial: onPartial)
                if !streamed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return streamed.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            } catch let error as AIError where Self.shouldFallbackFromStreamingError(error) {
                // Fall back to standard non-streaming request only when SSE itself is rejected
                // or yields an empty stream; never mask auth/rate-limit/404/transport errors.
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                throw error
            }
        }
        
        guard let url = config.requestURL else { throw AIError.invalidURL(config.resolvedBaseURL) }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        for (field, value) in config.requestHeaders {
            request.setValue(value, forHTTPHeaderField: field)
        }
        
        request.httpBody = try JSONSerialization.data(withJSONObject: self.body(for: messages, stream: false))
        
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
        
        let finalAnswer = try self.answer(from: data)
        onPartial?(finalAnswer)
        return finalAnswer
    }
    
    
    // MARK: Private Streaming Methods
    
    private static func shouldFallbackFromStreamingError(_ error: AIError) -> Bool {
        
        switch error {
            case .emptyResponse, .decoding:
                return true
            case .http(let status, _):
                return status == 400 || status == 415 || status == 501
            default:
                return false
        }
    }
    
    
    private var supportsSSEStreaming: Bool {
        
        switch self.wireConfig.endpoint {
            case .openAIChatCompletions, .anthropicMessages, .ollama:
                true
            case .openAIResponses, .googleGemini:
                false
        }
    }
    
    
    private func sendStreaming(_ messages: [AIMessage], onPartial: @Sendable (String) -> Void) async throws -> String {
        
        let config = self.wireConfig
        guard let url = config.requestURL else { throw AIError.invalidURL(config.resolvedBaseURL) }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        for (field, value) in config.requestHeaders {
            request.setValue(value, forHTTPHeaderField: field)
        }
        
        request.httpBody = try JSONSerialization.data(withJSONObject: self.body(for: messages, stream: true))
        
        let (bytes, response): (URLSession.AsyncBytes, URLResponse)
        do {
            (bytes, response) = try await URLSession.shared.bytes(for: request)
        } catch {
            throw AIError.transport(error)
        }
        
        if let httpResponse = response as? HTTPURLResponse, !(200..<300).contains(httpResponse.statusCode) {
            var errorData = Data()
            for try await byte in bytes {
                errorData.append(byte)
                if errorData.count > 4096 { break }
            }
            throw AIError.http(status: httpResponse.statusCode, message: Self.errorMessage(from: errorData))
        }
        
        var accumulated = ""
        for try await line in bytes.lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            
            if config.endpoint == .ollama {
                if let data = trimmed.data(using: .utf8),
                   let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let msg = obj["message"] as? [String: Any],
                   let delta = msg["content"] as? String,
                   !delta.isEmpty
                {
                    accumulated += delta
                    onPartial(accumulated)
                }
                continue
            }
            
            guard trimmed.hasPrefix("data:") else { continue }
            let payload = String(trimmed.dropFirst(5)).trimmingCharacters(in: .whitespaces)
            if payload == "[DONE]" { break }
            
            guard
                let data = payload.data(using: .utf8),
                let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { continue }
            
            switch config.endpoint {
                case .openAIChatCompletions:
                    if let choices = obj["choices"] as? [[String: Any]],
                       let delta = choices.first?["delta"] as? [String: Any],
                       let text = delta["content"] as? String,
                       !text.isEmpty
                    {
                        accumulated += text
                        onPartial(accumulated)
                    } else if let choices = obj["choices"] as? [[String: Any]],
                              let message = choices.first?["message"] as? [String: Any],
                              let text = Self.text(fromContent: message["content"]),
                              !text.isEmpty
                    {
                        accumulated += text
                        onPartial(accumulated)
                    }
                case .anthropicMessages:
                    if obj["type"] as? String == "error" {
                        throw AIError.http(status: 400, message: Self.errorMessage(from: data))
                    }
                    if obj["type"] as? String == "content_block_delta",
                       let delta = obj["delta"] as? [String: Any],
                       (delta["type"] as? String == nil || delta["type"] as? String == "text_delta"),
                       let text = delta["text"] as? String,
                       !text.isEmpty
                    {
                        accumulated += text
                        onPartial(accumulated)
                    }
                default:
                    break
            }
        }
        
        guard !accumulated.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AIError.emptyResponse
        }
        
        return accumulated
    }
    
    
    // MARK: Private Methods
    
    /// The JSON body for the protocol in use.
    ///
    /// - Parameters:
    ///   - messages: The conversation to send.
    ///   - stream: Whether to request Server-Sent Events streaming.
    /// - Returns: A JSON-serializable body.
    private func body(for messages: [AIMessage], stream: Bool = false) -> [String: Any] {
        
        let config = self.wireConfig
        let model = config.model
        let system = messages.first { $0.role == .system }?.text ?? ""
        let conversation = messages.filter { $0.role != .system }
        
        switch config.endpoint {
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
                if let effort = config.reasoningEffort, !effort.isEmpty {
                    body["reasoning"] = ["effort": effort]
                }
                
                return body
                
            case .openAIChatCompletions:
                var body: [String: Any] = [
                    "model": model,
                    "stream": stream,
                    "messages": messages.map { message in
                        [
                            "role": message.role.rawValue,
                            "content": self.openAIContent(for: message, textType: "text"),
                        ]
                    },
                ]
                if let temperature = config.temperature {
                    body["temperature"] = temperature
                }
                // For reasoning models (o1/o3/deepseek-reasoner), pass low reasoning effort to accelerate generation.
                let lowerModel = model.lowercased()
                if lowerModel.contains("reasoner") || lowerModel.hasPrefix("o1") || lowerModel.hasPrefix("o3") || lowerModel.hasPrefix("o4"),
                   let effort = config.reasoningEffort, !effort.isEmpty
                {
                    body["reasoning_effort"] = effort
                }
                
                return body
                
            case .anthropicMessages:
                var body: [String: Any] = [
                    "model": model,
                    "max_tokens": 16384,
                    "stream": stream,
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
                if let temperature = config.temperature {
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
                    "stream": stream,
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
        
        switch self.wireConfig.endpoint {
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
    /// Shared with ``AIModelCatalog``, since an error reply looks the same for both calls.
    ///
    /// - Parameter data: The raw response body.
    /// - Returns: The message, when one can be found.
    static func errorMessage(from data: Data) -> String? {
        
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return String(data: data, encoding: .utf8)
        }
        
        if let error = object["error"] as? [String: Any] {
            return error["message"] as? String
        }
        
        return object["message"] as? String
    }
}
