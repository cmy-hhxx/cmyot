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
    
    /// Runs one action on the given text, streaming partial updates when `onPartial` is provided.
    ///
    /// - Parameters:
    ///   - action: What to do.
    ///   - text: The text to work on.
    ///   - context: Extra context, when the feature has some.
    ///   - images: Pictures to add, for the features that look at the screen or at a file.
    ///   - onPartial: Optional callback receiving progressive text on the MainActor.
    /// - Returns: The answer text.
    /// - Throws: ``AIError`` when the request fails.
    func run(
        _ action: AIAction,
        on text: String,
        context: String? = nil,
        images: [AIImage] = [],
        onPartial: (@MainActor @Sendable (String) -> Void)? = nil
    ) async throws -> String {
        
        let db = CotLocalDatabase.shared
        let persona = db.aiPersona.trimmingCharacters(in: .whitespacesAndNewlines)
        let stagePrompt = db.customStagePrompt(forKey: action.databaseConfigKey) ?? action.defaultSystemPrompt
        let fullSystemPrompt = persona.isEmpty ? stagePrompt : "\(persona)\n\n\(stagePrompt)"
        
        var effectiveContext = context
        if action == .weeklyReport {
            let savedFragments = db.string(forKey: CotLocalDatabase.ConfigKey.weeklyReportFragments)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !savedFragments.isEmpty {
                let note = "已积累的周报片段（请一并整合进周报）：\n\(savedFragments)"
                effectiveContext = effectiveContext.map { "\($0)\n\n\(note)" } ?? note
            }
        }
        
        let messages: [AIMessage] = [
            .system(fullSystemPrompt),
            .user(action.prompt(for: text, context: effectiveContext), images: images),
        ]
        
        let result = try await self.send(messages, onPartial: onPartial)
        
        if action == .weeklyReportItem {
            db.appendWeeklyReportFragment(result)
        }
        
        return result
    }
    
    
    /// Checks that the configuration actually reaches the service.
    ///
    /// - Returns: The short reply from the model.
    /// - Throws: ``AIError`` when the request fails.
    func testConnection() async throws -> String {
        
        try await self.testConnection(configuration: .current)
    }
    
    
    /// Checks one configuration, without it having to be the one in use.
    ///
    /// The settings pane tests the values on screen before saving them, so a new endpoint can
    /// prove itself while the endpoint actually in use keeps working.
    ///
    /// - Parameter configuration: The configuration to try.
    /// - Returns: The short reply from the model.
    /// - Throws: ``AIError`` when the request fails.
    func testConnection(configuration: AIConfiguration) async throws -> String {
        
        try await self.send([
            .system("You are a connectivity test. Whatever you receive, reply with exactly one word: OK."),
            .user("Ping"),
        ], configuration: configuration)
    }
    
    
    /// Fetches the models the configured service offers.
    ///
    /// This reads the same stored configuration as ``run(_:on:context:images:)``, so the
    /// settings pane only has to save its fields before asking.
    ///
    /// - Returns: The models, in the order the service returned them.
    /// - Throws: ``AIError`` when the list cannot be fetched or is empty.
    func fetchModels() async throws -> [AIModel] {
        
        try await self.fetchModels(configuration: .current)
    }
    
    
    /// Fetches the models one configuration offers, without it having to be the one in use.
    ///
    /// - Parameter configuration: The configuration to ask.
    /// - Returns: The models, in the order the service returned them.
    /// - Throws: ``AIError`` when the list cannot be fetched or is empty.
    func fetchModels(configuration: AIConfiguration) async throws -> [AIModel] {
        
        try await AIModelCatalog.fetch(configuration: configuration)
    }
    
    
    // MARK: Private Methods
    
    /// Sends messages, keeping the running flag in sync.
    ///
    /// - Parameters:
    ///   - messages: The conversation to send.
    ///   - configuration: The service to talk to; the one in use when `nil`.
    ///   - onPartial: Optional progressive streaming callback.
    /// - Returns: The answer text.
    /// - Throws: ``AIError`` when the request fails.
    private func send(
        _ messages: [AIMessage],
        configuration: AIConfiguration? = nil,
        onPartial: (@MainActor @Sendable (String) -> Void)? = nil
    ) async throws -> String {
        
        let configuration = configuration ?? .current
        guard configuration.isUsable else { throw AIError.notConfigured }
        
        self.isRunning = true
        defer { self.isRunning = false }
        
        let nonisolatedPartial: (@Sendable (String) -> Void)? = onPartial.map { callback in
            { partial in
                Task { @MainActor in
                    callback(partial)
                }
            }
        }
        
        return try await AIClient(configuration: configuration).send(messages, onPartial: nonisolatedPartial)
    }
}
