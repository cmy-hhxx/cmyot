//
//  AIService.swift
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
import Observation

/// The entry point the rest of the app uses to talk to AI.
///
/// The module is layered bottom-up, and each layer only knows the one below it:
///
/// - `Core` holds the value types that never touch the network: the wire protocol
///   (``AIEndpoint``), the service presets (``AIProvider``), the stored configuration
///   (``AIConfiguration``), the conversation model (``AIMessage``) and ``AIError``.
/// - `Wire` speaks HTTP: ``AIClient`` turns messages into one chat request, ``AIModelCatalog``
///   reads the model list a service offers, and ``AIKeychain`` keeps the secret.
/// - `Features` decides what to ask: an ``AIAction`` case owns its prompts, and this service
///   is the one facade the rest of the app calls.
/// - `UI` shows an answer: ``AIResultPanelController`` is a single presentation of a result.
///
/// A new feature therefore adds an ``AIAction`` case (or a feature type in `Features`) and
/// calls this service. It never edits the protocol code, and it shares the one configuration
/// the user set up in Settings › AI.
@MainActor @Observable final class AIService {
    
    // MARK: Public Properties
    
    /// The shared service.
    static let shared = AIService()
    
    /// Whether a request is currently running.
    private(set) var isRunning = false
    
    /// Whether the stored configuration is complete enough to make a request.
    var isConfigured: Bool {
        
        AIConfiguration.current.isUsable
    }
    
    
    // MARK: Public Methods
    
    /// Runs one action on the given text.
    ///
    /// - Parameters:
    ///   - action: What to do.
    ///   - text: The text to work on.
    ///   - context: Extra context, when the feature has some.
    ///   - images: Pictures to add, for the features that look at the screen or at a file.
    /// - Returns: The answer text.
    /// - Throws: ``AIError`` when the request fails.
    func run(_ action: AIAction, on text: String, context: String? = nil, images: [AIImage] = []) async throws -> String {
        
        let messages: [AIMessage] = [
            .system(action.systemPrompt),
            .user(action.prompt(for: text, context: context), images: images),
        ]
        
        return try await self.send(messages)
    }
    
    
    /// Checks that the configuration actually reaches the service.
    ///
    /// - Returns: The short reply from the model.
    /// - Throws: ``AIError`` when the request fails.
    func testConnection() async throws -> String {
        
        try await self.send([
            .system("You are a connectivity test. Whatever you receive, reply with exactly one word: OK."),
            .user("Ping"),
        ])
    }
    
    
    /// Fetches the models the configured service offers.
    ///
    /// This reads the same stored configuration as ``run(_:on:context:images:)``, so the
    /// settings pane only has to save its fields before asking.
    ///
    /// - Returns: The models, in the order the service returned them.
    /// - Throws: ``AIError`` when the list cannot be fetched or is empty.
    func fetchModels() async throws -> [AIModel] {
        
        try await AIModelCatalog.fetch(configuration: AIConfiguration.current)
    }
    
    
    // MARK: Private Methods
    
    /// Sends messages, keeping the running flag in sync.
    ///
    /// - Parameter messages: The conversation to send.
    /// - Returns: The answer text.
    /// - Throws: ``AIError`` when the request fails.
    private func send(_ messages: [AIMessage]) async throws -> String {
        
        let configuration = AIConfiguration.current
        guard configuration.isUsable else { throw AIError.notConfigured }
        
        self.isRunning = true
        defer { self.isRunning = false }
        
        return try await AIClient(configuration: configuration).send(messages)
    }
}
