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

/// Response payload from ``AIClient`` containing answer text and optional provider-reported token counts.
nonisolated struct AICompletionResponse: Sendable, Equatable {
    
    let text: String
    let inputTokens: Int?
    let outputTokens: Int?
}


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
    var maxOutputTokens: Int? = nil
    var timeoutInterval: TimeInterval = 120
    var disablesThinking: Bool = false
    
    private var wireConfig: AIConfiguration { self.configuration.wireConfiguration }
    
    
    /// Sends the messages and streams partial text chunks as they arrive, returning the final answer.
    ///
    /// - Parameters:
    ///   - messages: The conversation so far.
    ///   - onPartial: Optional callback invoked with the accumulated answer text as tokens arrive.
    /// - Returns: The answer as plain text.
    /// - Throws: ``AIError`` when the request cannot be made or the reply cannot be read.
    func send(_ messages: [AIMessage], onPartial: (@Sendable (String) async -> Void)? = nil) async throws -> String {
        
        try await self.sendWithUsage(messages, onPartial: onPartial).text
    }
    
    
    /// Sends the messages and returns both the final answer and any token usage reported by the provider.
    func sendWithUsage(
        _ messages: [AIMessage],
        onPartial: (@Sendable (String) async -> Void)? = nil
    ) async throws -> AICompletionResponse {
        
        var allowTemperature = Self.supportsTemperature(for: self.wireConfig.model)
        var allowThinkingControl = true
        
        while true {
            do {
                return try await self.sendAttempt(
                    messages,
                    allowTemperature: allowTemperature,
                    allowThinkingControl: allowThinkingControl,
                    onPartial: onPartial
                )
            } catch let error where allowTemperature && Self.isTemperatureRejectedError(error) {
                allowTemperature = false
                CotLogger.shared.info(
                    category: .ai,
                    "Model rejected temperature parameter; retrying without temperature: model=\(self.wireConfig.model)"
                )
            } catch let error where allowThinkingControl && Self.isThinkingParameterRejectedError(error) {
                allowThinkingControl = false
                CotLogger.shared.info(
                    category: .ai,
                    "Model rejected thinking parameter; retrying without thinking control: model=\(self.wireConfig.model)"
                )
            }
        }
    }
    
    
    /// Returns whether the model accepts a custom `temperature` sampling parameter.
    ///
    /// Claude 5+ and reasoning-oriented models reject `temperature` with HTTP 400.
    static func supportsTemperature(for model: String) -> Bool {
        
        let normalized = model
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !normalized.isEmpty else { return true }
        
        if normalized.range(
            of: "claude-(?:(?:haiku|sonnet|opus)-)?[5-9](?:[.-]|$)",
            options: .regularExpression
        ) != nil {
            return false
        }
        
        if normalized.contains("reasoner")
            || normalized.hasPrefix("o1")
            || normalized.hasPrefix("o3")
            || normalized.hasPrefix("o4")
            || normalized.hasPrefix("gpt-5")
        {
            return false
        }
        
        return true
    }
    
    
    /// Detects provider HTTP 400 errors rejecting `temperature` so requests can retry once without it.
    static func isTemperatureRejectedError(_ error: any Error) -> Bool {
        
        guard case AIError.http(let status, let message?) = error, status == 400 else {
            return false
        }
        let lower = message.lowercased()
        return lower.contains("temperature")
            && (lower.contains("deprecated")
                || lower.contains("unsupported")
                || lower.contains("not allowed")
                || lower.contains("not supported")
                || lower.contains("cannot specify")
                || lower.contains("invalid"))
    }
    
    
    /// Detects provider HTTP 400 errors rejecting `thinking` / `reasoning` parameters so requests retry cleanly without them.
    static func isThinkingParameterRejectedError(_ error: any Error) -> Bool {
        
        guard case AIError.http(let status, let message?) = error, status == 400 else {
            return false
        }
        let lower = message.lowercased()
        return lower.contains("thinking")
            || lower.contains("thinkingconfig")
            || lower.contains("thinking_budget")
            || lower.contains("reasoning")
    }
    
    
    private func sendAttempt(
        _ messages: [AIMessage],
        allowTemperature: Bool,
        allowThinkingControl: Bool,
        onPartial: (@Sendable (String) async -> Void)?
    ) async throws -> AICompletionResponse {
        
        let config = self.wireConfig
        guard config.isUsable else { throw AIError.notConfigured }
        
        if let onPartial, self.supportsSSEStreaming {
            do {
                let streamed = try await self.sendStreaming(
                    messages,
                    allowTemperature: allowTemperature,
                    allowThinkingControl: allowThinkingControl,
                    onPartial: onPartial
                )
                let cleaned = streamed.text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !cleaned.isEmpty {
                    return AICompletionResponse(
                        text: cleaned,
                        inputTokens: streamed.inputTokens,
                        outputTokens: streamed.outputTokens
                    )
                }
            } catch let error as AIError where Self.shouldFallbackFromStreamingError(error) {
                // Fall back to standard non-streaming request only when SSE itself is rejected
                // or yields an empty stream; never mask auth/rate-limit/404/transport/temperature errors.
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                throw error
            }
        }
        
        guard let url = config.requestURL else { throw AIError.invalidURL(config.resolvedBaseURL) }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = self.timeoutInterval
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        for (field, value) in config.requestHeaders {
            request.setValue(value, forHTTPHeaderField: field)
        }
        
        request.httpBody = try JSONSerialization.data(
            withJSONObject: self.body(
                for: messages,
                stream: false,
                allowTemperature: allowTemperature,
                allowThinkingControl: allowThinkingControl
            )
        )
        
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch {
            throw AIError.transport(error)
        }
        
        if let httpResponse = response as? HTTPURLResponse, !(200..<300).contains(httpResponse.statusCode) {
            throw AIError.http(status: httpResponse.statusCode, message: Self.errorMessage(from: data))
        }
        
        let parsed = try self.answerAndUsage(from: data)
        await onPartial?(parsed.text)
        return parsed
    }
    
    
    // MARK: Private Streaming Methods
    
    private static func shouldFallbackFromStreamingError(_ error: AIError) -> Bool {
        
        if self.isTemperatureRejectedError(error) || self.isThinkingParameterRejectedError(error) {
            return false
        }
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
    
    
    private func sendStreaming(
        _ messages: [AIMessage],
        allowTemperature: Bool,
        allowThinkingControl: Bool,
        onPartial: @Sendable (String) async -> Void
    ) async throws -> AICompletionResponse {
        
        let config = self.wireConfig
        guard let url = config.requestURL else { throw AIError.invalidURL(config.resolvedBaseURL) }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = self.timeoutInterval
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        for (field, value) in config.requestHeaders {
            request.setValue(value, forHTTPHeaderField: field)
        }
        
        request.httpBody = try JSONSerialization.data(
            withJSONObject: self.body(
                for: messages,
                stream: true,
                allowTemperature: allowTemperature,
                allowThinkingControl: allowThinkingControl
            )
        )
        
        let (bytes, response): (URLSession.AsyncBytes, URLResponse)
        do {
            (bytes, response) = try await URLSession.shared.bytes(for: request)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
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
        var inputTokens: Int?
        var outputTokens: Int?
        
        for try await line in bytes.lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            
            if config.endpoint == .ollama {
                if let data = trimmed.data(using: .utf8),
                   let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                {
                    if let promptEval = obj["prompt_eval_count"] as? Int {
                        inputTokens = promptEval
                    }
                    if let evalCount = obj["eval_count"] as? Int {
                        outputTokens = evalCount
                    }
                    if let msg = obj["message"] as? [String: Any],
                       let delta = msg["content"] as? String,
                       !delta.isEmpty
                    {
                        accumulated += delta
                        await onPartial(accumulated)
                    }
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
                    if let usage = obj["usage"] as? [String: Any] {
                        if let prompt = (usage["prompt_tokens"] as? Int) ?? (usage["input_tokens"] as? Int) {
                            inputTokens = prompt
                        }
                        if let completion = (usage["completion_tokens"] as? Int) ?? (usage["output_tokens"] as? Int) {
                            outputTokens = completion
                        }
                    }
                    if let choices = obj["choices"] as? [[String: Any]],
                       let delta = choices.first?["delta"] as? [String: Any],
                       let text = delta["content"] as? String,
                       !text.isEmpty
                    {
                        accumulated += text
                        await onPartial(accumulated)
                    } else if let choices = obj["choices"] as? [[String: Any]],
                              let message = choices.first?["message"] as? [String: Any],
                              let text = Self.text(fromContent: message["content"]),
                              !text.isEmpty
                    {
                        accumulated += text
                        await onPartial(accumulated)
                    }
                case .anthropicMessages:
                    let eventType = obj["type"] as? String
                    if eventType == "error" {
                        throw AIError.http(status: 400, message: Self.errorMessage(from: data))
                    }
                    if eventType == "message_start",
                       let message = obj["message"] as? [String: Any],
                       let usage = message["usage"] as? [String: Any]
                    {
                        if let inTok = usage["input_tokens"] as? Int {
                            inputTokens = inTok
                        }
                        if let outTok = usage["output_tokens"] as? Int {
                            outputTokens = outTok
                        }
                    } else if eventType == "message_delta",
                              let usage = obj["usage"] as? [String: Any]
                    {
                        if let inTok = usage["input_tokens"] as? Int {
                            inputTokens = inTok
                        }
                        if let outTok = usage["output_tokens"] as? Int {
                            outputTokens = outTok
                        }
                    } else if eventType == "content_block_delta",
                              let delta = obj["delta"] as? [String: Any],
                              (delta["type"] as? String == nil || delta["type"] as? String == "text_delta"),
                              let text = delta["text"] as? String,
                              !text.isEmpty
                    {
                        accumulated += text
                        await onPartial(accumulated)
                    }
                default:
                    break
            }
        }
        
        guard !accumulated.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AIError.emptyResponse
        }
        
        return AICompletionResponse(text: accumulated, inputTokens: inputTokens, outputTokens: outputTokens)
    }
    
    
    /// Returns whether `model` accepts OpenAI-style `reasoning_effort` / `reasoning.effort` controls.
    static func supportsOpenAIReasoningEffort(for model: String) -> Bool {
        let m = model.lowercased()
        return m.contains("reasoner")
            || m.contains("thinking")
            || m.contains("qwq")
            || m.contains("-r1")
            || m.hasPrefix("o1")
            || m.hasPrefix("o3")
            || m.hasPrefix("o4")
            || m.hasPrefix("gpt-5")
            || m.contains("/o1")
            || m.contains("/o3")
            || m.contains("/o4")
            || m.contains("/gpt-5")
    }
    
    
    /// Maps `"low" | "medium" | "high"` into Anthropic extended-thinking `budget_tokens`.
    static func anthropicThinkingBudget(for effort: String?, model: String) -> Int? {
        let m = model.lowercased()
        let isThinkingCapable = m.contains("claude-3-7")
            || m.contains("claude-3.7")
            || m.contains("claude-sonnet-4")
            || m.contains("claude-opus-4")
            || m.contains("claude-haiku-4-5")
            || m.contains("claude-4")
        guard isThinkingCapable else { return nil }
        switch effort?.lowercased() {
            case "medium": return 4096
            case "high": return 12288
            default: return nil
        }
    }
    
    
    /// Maps `"low" | "medium" | "high"` into Google Gemini `thinkingConfig.thinkingBudget`.
    static func geminiThinkingBudget(for effort: String?, model: String) -> Int? {
        let m = model.lowercased()
        guard m.contains("gemini-2.5") || m.contains("gemini-3") || m.contains("thinking") else { return nil }
        switch effort?.lowercased() {
            case "low": return 512
            case "medium": return 4096
            case "high": return 12288
            default: return nil
        }
    }
    
    
    /// Internal test hook returning the wire JSON body for `messages`.
    func debugRequestBody(for messages: [AIMessage], stream: Bool = true) -> [String: Any] {
        self.body(for: messages, stream: stream)
    }
    
    
    // MARK: Private Methods
    
    /// The JSON body for the protocol in use.
    ///
    /// - Parameters:
    ///   - messages: The conversation to send.
    ///   - stream: Whether to request Server-Sent Events streaming.
    /// - Returns: A JSON-serializable body.
    private func body(
        for messages: [AIMessage],
        stream: Bool = false,
        allowTemperature: Bool = true,
        allowThinkingControl: Bool = true
    ) -> [String: Any] {
        
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
                if allowThinkingControl, !self.disablesThinking,
                   Self.supportsOpenAIReasoningEffort(for: model),
                   let effort = config.reasoningEffort, !effort.isEmpty
                {
                    body["reasoning"] = ["effort": effort]
                }
                if let maxTokens = self.maxOutputTokens {
                    body["max_output_tokens"] = maxTokens
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
                if allowTemperature, Self.supportsTemperature(for: model), let temperature = config.temperature {
                    body["temperature"] = temperature
                }
                let lowerModel = model.lowercased()
                if let maxTokens = self.maxOutputTokens {
                    if lowerModel.contains("reasoner") || lowerModel.hasPrefix("o1") || lowerModel.hasPrefix("o3") || lowerModel.hasPrefix("o4") || lowerModel.hasPrefix("gpt-5") {
                        body["max_completion_tokens"] = maxTokens
                    } else {
                        body["max_tokens"] = maxTokens
                    }
                }
                if allowThinkingControl, !self.disablesThinking,
                   Self.supportsOpenAIReasoningEffort(for: model),
                   let effort = config.reasoningEffort, !effort.isEmpty
                {
                    body["reasoning_effort"] = effort
                }
                
                return body
                
            case .anthropicMessages:
                let anthropicThinkingBudget = (allowThinkingControl && !self.disablesThinking)
                    ? Self.anthropicThinkingBudget(for: config.reasoningEffort, model: model)
                    : nil
                let resolvedMaxTokens = max(self.maxOutputTokens ?? 16384, (anthropicThinkingBudget ?? 0) + 4096)
                var body: [String: Any] = [
                    "model": model,
                    "max_tokens": resolvedMaxTokens,
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
                // Anthropic requires temperature unset when extended thinking is enabled
                if anthropicThinkingBudget == nil,
                   allowTemperature, Self.supportsTemperature(for: model),
                   let temperature = config.temperature
                {
                    body["temperature"] = temperature
                }
                if allowThinkingControl, self.disablesThinking {
                    body["thinking"] = ["type": "disabled"]
                } else if let budget = anthropicThinkingBudget {
                    body["thinking"] = ["type": "enabled", "budget_tokens": budget]
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
                var genConfig: [String: Any] = [:]
                if let maxTokens = self.maxOutputTokens {
                    genConfig["maxOutputTokens"] = maxTokens
                }
                if allowTemperature, let temperature = config.temperature {
                    genConfig["temperature"] = temperature
                }
                if allowThinkingControl, self.disablesThinking {
                    genConfig["thinkingConfig"] = ["thinkingBudget": 0]
                } else if allowThinkingControl,
                          let budget = Self.geminiThinkingBudget(for: config.reasoningEffort, model: model)
                {
                    genConfig["thinkingConfig"] = ["thinkingBudget": budget]
                }
                if !genConfig.isEmpty {
                    body["generationConfig"] = genConfig
                }
                
                return body
                
            case .ollama:
                var body: [String: Any] = [
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
                if let maxTokens = self.maxOutputTokens {
                    body["options"] = ["num_predict": maxTokens]
                }
                return body
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
    
    
    /// Pulls the answer text and optional token counts out of a protocol reply.
    private func answerAndUsage(from data: Data) throws -> AICompletionResponse {
        
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
        
        let usage = Self.tokenUsage(from: object, endpoint: self.wireConfig.endpoint)
        return AICompletionResponse(
            text: text.trimmingCharacters(in: .whitespacesAndNewlines),
            inputTokens: usage.inputTokens,
            outputTokens: usage.outputTokens
        )
    }
    
    
    /// Extracts input/output token counts from a parsed non-streaming JSON response.
    private static func tokenUsage(from object: [String: Any], endpoint: AIEndpoint) -> (inputTokens: Int?, outputTokens: Int?) {
        
        switch endpoint {
            case .openAIChatCompletions:
                let usage = object["usage"] as? [String: Any]
                let input = (usage?["prompt_tokens"] as? Int) ?? (usage?["input_tokens"] as? Int)
                let output = (usage?["completion_tokens"] as? Int) ?? (usage?["output_tokens"] as? Int)
                return (input, output)
            case .openAIResponses:
                let usage = object["usage"] as? [String: Any]
                let input = (usage?["input_tokens"] as? Int) ?? (usage?["prompt_tokens"] as? Int)
                let output = (usage?["output_tokens"] as? Int) ?? (usage?["completion_tokens"] as? Int)
                return (input, output)
            case .anthropicMessages:
                let usage = object["usage"] as? [String: Any]
                return (usage?["input_tokens"] as? Int, usage?["output_tokens"] as? Int)
            case .googleGemini:
                let usage = object["usageMetadata"] as? [String: Any]
                return (usage?["promptTokenCount"] as? Int, usage?["candidatesTokenCount"] as? Int)
            case .ollama:
                return (object["prompt_eval_count"] as? Int, object["eval_count"] as? Int)
        }
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
