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

import AppKit
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
        let botID = AIBotID(action: action)
        let botStore = AIBotStore.shared
        let botConfig = botStore.config(for: botID)
        guard botConfig.isEnabled else {
            throw AIError.http(
                status: 403,
                message: "\(botID.displayName)（\(botID.handle)）已在设置中停用，请在「设置 → Bots」重新开启。"
            )
        }
        
        let customBotPersona = botConfig.customPersona.trimmingCharacters(in: .whitespacesAndNewlines)
        let persona = customBotPersona.isEmpty
            ? db.aiPersona.trimmingCharacters(in: .whitespacesAndNewlines)
            : customBotPersona
        let stagePrompt = db.customStagePrompt(forKey: action.databaseConfigKey) ?? action.defaultSystemPrompt
        let fullSystemPrompt = persona.isEmpty ? stagePrompt : "\(persona)\n\n\(stagePrompt)"
        
        var effectiveContext = context
        if action == .weeklyReport {
            var contextBlocks: [String] = []
            if let context, !context.isEmpty {
                contextBlocks.append(context)
            }
            
            let author = db.weeklyReportAuthor
            let periodHint = Self.currentWeekPeriodLabel()
            contextBlocks.append("周报署名与周期：# \(author)-周报-\(periodHint)")
            
            let references = db.styleReferenceWeeklyReports(limit: 2)
            if !references.isEmpty {
                let refText = references.map { ref in
                    "--- 历史周报参考（\(ref.title)） ---\n\(String(ref.content.prefix(1500)))"
                }.joined(separator: "\n\n")
                contextBlocks.append("""
                以下是用户真实的历史周报范例，请严格参考它的标题格式、分段方式（本周主要干了以下几件事 + ## 模块 + 进展：/ 卡点：）以及直白说人话的口吻（禁止直接照搬历史内容）：
                \(refText)
                """)
            }
            
            let savedFragments = db.string(forKey: CotLocalDatabase.ConfigKey.weeklyReportFragments)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !savedFragments.isEmpty {
                contextBlocks.append("已积累的周报片段（请一并整合进周报）：\n\(savedFragments)")
            }
            
            effectiveContext = contextBlocks.joined(separator: "\n\n")
        }
        
        let userPrompt = action.prompt(for: text, context: effectiveContext)
        let messages: [AIMessage] = [
            .system(fullSystemPrompt),
            .user(userPrompt, images: images),
        ]
        
        let resolvedConfig = botStore.resolvedConfiguration(for: botID)
        let rawResult = try await self.executeBot(
            botID,
            systemPrompt: fullSystemPrompt,
            userPrompt: userPrompt,
            messages: messages,
            hasImages: !images.isEmpty,
            configuration: resolvedConfig,
            analyticsFeature: action.analyticsKey,
            onPartial: onPartial
        )
        let result = action.outputsPlainDocumentText
            ? AIDocumentTextCleaner.clean(rawResult)
            : rawResult
        
        if action == .weeklyReportItem {
            db.appendWeeklyReportFragment(result)
        }
        
        return result
    }
    
    
    /// Runs an inline test turn for any bot using its current persona, prompt, and model override via `PiKernelManager` (with direct HTTP fallback).
    func testBot(_ botID: AIBotID, sampleInput: String) async throws -> String {
        
        let trimmedInput = sampleInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let effectiveInput = trimmedInput.isEmpty ? botID.defaultSampleInput : trimmedInput
        
        if let action = botID.linkedAction {
            return try await self.run(action, on: effectiveInput)
        }
        
        let botStore = AIBotStore.shared
        let botConfig = botStore.config(for: botID)
        let customBotPersona = botConfig.customPersona.trimmingCharacters(in: .whitespacesAndNewlines)
        let persona = customBotPersona.isEmpty
            ? CotLocalDatabase.shared.aiPersona.trimmingCharacters(in: .whitespacesAndNewlines)
            : customBotPersona
        let stagePrompt = botStore.systemPrompt(for: botID)
        let fullSystem = persona.isEmpty ? stagePrompt : "\(persona)\n\n\(stagePrompt)"
        let resolvedConfig = botStore.resolvedConfiguration(for: botID)
        
        return try await self.executeBot(
            botID,
            systemPrompt: fullSystem,
            userPrompt: effectiveInput,
            messages: [.system(fullSystem), .user(effectiveInput)],
            hasImages: false,
            configuration: resolvedConfig,
            analyticsFeature: botID.analyticsFeatureKey,
            onPartial: nil
        )
    }
    
    
    /// Routes a Bot request through `PiKernelManager` when enabled and ready, falling back cleanly to `AIClient` direct HTTP.
    private func executeBot(
        _ botID: AIBotID,
        systemPrompt: String,
        userPrompt: String,
        messages: [AIMessage],
        hasImages: Bool,
        configuration: AIConfiguration,
        analyticsFeature: String,
        onPartial: (@MainActor @Sendable (String) -> Void)?
    ) async throws -> String {
        
        guard configuration.isUsable else { throw AIError.notConfigured }
        
        let piKernel = PiKernelManager.shared
        if piKernel.shouldRouteThroughKernel(for: botID, hasImages: hasImages),
           let endpointProfile = AIBotStore.shared.resolvedEndpointProfile(for: botID)
        {
            self.isRunning = true
            let clock = ContinuousClock()
            let start = clock.now
            let workingDir = (NSDocumentController.shared.currentDocument as? NSDocument)?
                .fileURL?
                .deletingLastPathComponent()
            do {
                let output = try await piKernel.runBot(
                    botID,
                    systemPrompt: systemPrompt,
                    userPrompt: userPrompt,
                    endpointProfile: endpointProfile,
                    configuration: configuration,
                    workingDirectory: workingDir,
                    onPartial: onPartial
                )
                self.isRunning = false
                let elapsed = start.duration(to: clock.now)
                let latencyMs = max(1, Int(elapsed.components.seconds * 1000) + Int(elapsed.components.attoseconds / 1_000_000_000_000_000))
                let effective = configuration.wireConfiguration
                AnalyticsManager.shared.recordAIUsage(
                    feature: analyticsFeature,
                    model: effective.model,
                    provider: "Pi · \(effective.endpoint.label)",
                    inputTokens: AINextTokenPredictor.estimateTokens(in: systemPrompt + "\n" + userPrompt),
                    outputTokens: AINextTokenPredictor.estimateTokens(in: output),
                    latencyMs: latencyMs,
                    success: true
                )
                return output
            } catch {
                self.isRunning = false
                if error is CancellationError {
                    throw error
                }
                // Fall back to direct wire client if Pi CLI fails locally
            }
        }
        
        return try await self.send(
            messages,
            configuration: configuration,
            analyticsFeature: analyticsFeature,
            onPartial: onPartial
        )
    }
    
    
    /// Computes the current Monday–Friday date range formatted as `YYYYMMDD-MMDD` (matching historical reports).
    static func currentWeekPeriodLabel(referenceDate: Date = .now) -> String {
        
        let calendar = Calendar(identifier: .gregorian)
        let weekday = calendar.component(.weekday, from: referenceDate)  // 1 = Sun, 2 = Mon
        let daysFromMonday = (weekday == 1) ? 6 : (weekday - 2)
        let monday = calendar.date(byAdding: .day, value: -daysFromMonday, to: referenceDate) ?? referenceDate
        let friday = calendar.date(byAdding: .day, value: 4, to: monday) ?? referenceDate
        
        let startFormatter = DateFormatter()
        startFormatter.dateFormat = "yyyyMMdd"
        let endFormatter = DateFormatter()
        endFormatter.dateFormat = "MMdd"
        return "\(startFormatter.string(from: monday))-\(endFormatter.string(from: friday))"
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
        analyticsFeature: String? = nil,
        onPartial: (@MainActor @Sendable (String) -> Void)? = nil
    ) async throws -> String {
        
        let configuration = configuration ?? .current
        guard configuration.isUsable else { throw AIError.notConfigured }
        
        self.isRunning = true
        defer { self.isRunning = false }
        
        // Deliver every chunk before the request returns. A detached task here used to let a
        // late chunk land after the final result, which flipped finished UI back to "running".
        let nonisolatedPartial: (@Sendable (String) async -> Void)? = onPartial.map { callback in
            { @Sendable partial in
                await MainActor.run {
                    callback(partial)
                }
            }
        }
        
        let clock = ContinuousClock()
        let start = clock.now
        let effective = configuration.wireConfiguration
        do {
            let response = try await AIClient(configuration: configuration).sendWithUsage(
                messages,
                onPartial: nonisolatedPartial
            )
            if let analyticsFeature {
                let elapsed = start.duration(to: clock.now)
                let latencyMs = max(1, Int(elapsed.components.seconds * 1000) + Int(elapsed.components.attoseconds / 1_000_000_000_000_000))
                let inputTokens = response.inputTokens ?? AINextTokenPredictor.estimateTokens(in: messages.map(\.text).joined(separator: "\n"))
                let outputTokens = response.outputTokens ?? AINextTokenPredictor.estimateTokens(in: response.text)
                AnalyticsManager.shared.recordAIUsage(
                    feature: analyticsFeature,
                    model: effective.model,
                    provider: effective.endpoint.label,
                    inputTokens: inputTokens,
                    outputTokens: outputTokens,
                    latencyMs: latencyMs,
                    success: true
                )
            }
            return response.text
        } catch {
            if !(error is CancellationError) {
                CotLogger.shared.error(
                    category: .ai,
                    "AI request failed",
                    error: error,
                    context: [
                        "endpoint": effective.endpoint.rawValue,
                        "url": effective.requestURL?.absoluteString ?? effective.resolvedBaseURL,
                        "model": effective.model,
                    ]
                )
                if let analyticsFeature {
                    let elapsed = start.duration(to: clock.now)
                    let latencyMs = max(1, Int(elapsed.components.seconds * 1000) + Int(elapsed.components.attoseconds / 1_000_000_000_000_000))
                    AnalyticsManager.shared.recordAIUsage(
                        feature: analyticsFeature,
                        model: effective.model,
                        provider: effective.endpoint.label,
                        inputTokens: 0,
                        outputTokens: 0,
                        latencyMs: latencyMs,
                        success: false
                    )
                }
            }
            throw error
        }
    }
}
