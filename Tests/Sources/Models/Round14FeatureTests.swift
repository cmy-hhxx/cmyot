//
//  Round14FeatureTests.swift
//
//  CotEditor
//
//  ---------------------------------------------------------------------------
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
import Testing
@testable import CotEditor

@Suite(.serialized)
@MainActor
struct Round14FeatureTests {
    
    @Test func cotLoggerRollingSevenDaysAndRedaction() throws {
        
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("CotLoggerTest-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        let today = cal.startOfDay(for: Date())
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.calendar = cal
        fmt.timeZone = .current
        fmt.dateFormat = "yyyy-MM-dd"
        
        // Create log files from today back through 9 days ago
        for offset in 0...9 {
            let day = cal.date(byAdding: .day, value: -offset, to: today)!
            let url = tempDir.appendingPathComponent("cot-\(fmt.string(from: day)).log")
            try Data("entry-\(offset)\n".utf8).write(to: url)
        }
        
        let logger = CotLogger(directoryURL: tempDir, retentionDays: 7, nowProvider: { today })
        logger.pruneExpiredLogs(referenceDate: today)
        
        let retainedNames = logger.availableLogFiles().map(\.lastPathComponent)
        #expect(retainedNames.count == 7)
        #expect(retainedNames.contains("cot-\(fmt.string(from: today)).log"))
        let day6Ago = cal.date(byAdding: .day, value: -6, to: today)!
        let day7Ago = cal.date(byAdding: .day, value: -7, to: today)!
        #expect(retainedNames.contains("cot-\(fmt.string(from: day6Ago)).log"))
        #expect(!retainedNames.contains("cot-\(fmt.string(from: day7Ago)).log"))
        
        logger.logSynchronously(
            level: .error,
            category: .ai,
            "Failed with oc_sk_1234567890_secret and user_ABCDEF1234567890",
            context: ["auth": "Authorization: Bearer my-secret-token-value"]
        )
        let todayContent = try String(contentsOf: logger.currentLogFileURL, encoding: .utf8)
        #expect(!todayContent.contains("oc_sk_1234567890_secret"))
        #expect(!todayContent.contains("user_ABCDEF1234567890"))
        #expect(!todayContent.contains("my-secret-token-value"))
        #expect(todayContent.contains("[ERROR] [AI]"))
    }
    
    
    @Test func localSecretsStorePersistsWithoutKeychain() throws {
        
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AISecretsTest-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer {
            AIKeychain.setStoreURLForTesting(nil)
            try? FileManager.default.removeItem(at: tempDir)
        }
        
        let secretURL = tempDir.appendingPathComponent("ai_secrets.json")
        AIKeychain.setStoreURLForTesting(secretURL)
        
        let profileID = UUID()
        AIKeychain.setAPIKey("oc_sk_test_key_value", for: profileID)
        #expect(AIKeychain.apiKey(for: profileID) == "oc_sk_test_key_value")
        
        // Reset in-memory cache via setStoreURLForTesting and verify reload from disk
        AIKeychain.setStoreURLForTesting(secretURL)
        #expect(AIKeychain.apiKey(for: profileID) == "oc_sk_test_key_value")
        
        AIKeychain.removeAPIKey(for: profileID)
        #expect(AIKeychain.apiKey(for: profileID).isEmpty)
    }
    
    
    @Test func endpointRoutingAndHeadersAndProfileDecoding() throws {
        
        // OpenCode Go baseURL without /v1 gets /v1 inserted for Anthropic Messages & models
        let openCodeConfig = AIConfiguration(
            endpoint: .anthropicMessages,
            baseURL: "https://opencode.ai/inference/go",
            model: "deepseek-v4.1-flash",
            apiKey: "oc_sk_dummy",
            customHeaders: ["x-opencode-session": "omp-opencode-go-1"]
        )
        #expect(openCodeConfig.requestURL?.absoluteString == "https://opencode.ai/inference/go/v1/messages")
        #expect(openCodeConfig.modelsRequestURL?.absoluteString == "https://opencode.ai/inference/go/v1/models?limit=1000")
        #expect(openCodeConfig.requestHeaders["x-opencode-session"] == "omp-opencode-go-1")
        #expect(openCodeConfig.requestHeaders["x-api-key"] == "oc_sk_dummy")
        
        // CommandCode routes claude-* models to /provider/v1/messages while keeping deepseek on /responses
        let ccClaude = AIConfiguration(
            endpoint: .openAIResponses,
            baseURL: "https://api.commandcode.ai/provider/v1",
            model: "claude-haiku-5-5",
            apiKey: "user_dummy"
        )
        let wiredClaude = ccClaude.wireConfiguration
        #expect(wiredClaude.endpoint == .anthropicMessages)
        #expect(wiredClaude.requestURL?.absoluteString == "https://api.commandcode.ai/provider/v1/messages")
        #expect(wiredClaude.requestHeaders["x-api-key"] == "user_dummy")
        
        let ccDeepSeek = AIConfiguration(
            endpoint: .openAIResponses,
            baseURL: "https://api.commandcode.ai/provider/v1",
            model: "deepseek/deepseek-v4.1-flash",
            apiKey: "user_dummy"
        )
        #expect(ccDeepSeek.wireConfiguration.endpoint == .openAIResponses)
        #expect(ccDeepSeek.wireConfiguration.requestURL?.absoluteString == "https://api.commandcode.ai/provider/v1/responses")
        
        // Legacy profile JSON without customHeaders/savedModels still decodes cleanly
        let legacyJSON = """
        {"id":"11111111-1111-1111-1111-111111111111","name":"Legacy","endpoint":"openAIChatCompletions","baseURL":"https://example.com/v1","model":"gpt-4o"}
        """
        var decoded = try JSONDecoder().decode(AIEndpointProfile.self, from: Data(legacyJSON.utf8))
        #expect(decoded.customHeaders.isEmpty)
        decoded.rememberModels(["claude-haiku-5-5", "gpt-4o", "claude-haiku-5-5"])
        #expect(decoded.availableModelIDs == ["gpt-4o", "claude-haiku-5-5"])
    }
    
    
    @Test func renamePreservesDatabaseRecordAndResolvesExtensions() throws {
        
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("CotDBRenameTest-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        let dbURL = tempDir.appendingPathComponent("test.sqlite3")
        let db = CotLocalDatabase(customURL: dbURL)
        let oldPath = tempDir.appendingPathComponent("old-note.md").path
        let newPath = tempDir.appendingPathComponent("2026.11 周报.md").path
        
        db.saveDocument(
            id: oldPath,
            title: "old-note.md",
            filePath: oldPath,
            syntax: "Markdown",
            content: "# 周报记录\n具体事项",
            groupName: "工作"
        )
        #expect(db.documents.count == 1)
        
        db.renameDocument(
            oldID: oldPath,
            oldFilePath: oldPath,
            newID: newPath,
            newTitle: "2026.11 周报.md",
            newFilePath: newPath
        )
        #expect(db.documents.count == 1)
        let updated = try #require(db.documents.first)
        #expect(updated.id == newPath)
        #expect(updated.filePath == newPath)
        #expect(updated.title == "2026.11 周报.md")
        #expect(updated.groupName == "工作")
        #expect(updated.content == "# 周报记录\n具体事项")
        
        // Dotted names keep the existing extension instead of stripping it
        let srcURL = URL(filePath: oldPath)
        #expect(WorkspaceOrganizer.resolvedRenamedFilename(for: "2026.11 周报", preservingExtensionOf: srcURL) == "2026.11 周报.md")
        #expect(WorkspaceOrganizer.resolvedRenamedFilename(for: "v2.1", preservingExtensionOf: srcURL) == "v2.1.md")
        #expect(WorkspaceOrganizer.resolvedRenamedFilename(for: "readme.txt", preservingExtensionOf: srcURL) == "readme.txt")
    }
    
    
    @Test func funNamingGrammarAndSpringParameters() {
        
        let badFragments = ["底下里的", "上方里的", "边缘里的", "山顶里的", "太平洋底里的", "傍晚里的", "季节里的", "天台里的"]
        for _ in 0..<250 {
            let name = GeneratedDocumentName.generateCandidate()
            #expect(name.count <= 6)
            for fragment in badFragments {
                #expect(!name.contains(fragment))
            }
        }
        
        // Tab preferredWidth must accommodate 7-char CJK titles without ellipsis truncation
        for title in ["背单词的泡面", "抽屉里的魔法师"] {
            let doc = Document()
            doc.displayName = title
            let tab = PaneTab(document: doc)
            let itemView = PaneTabItemView(frame: NSRect(x: 0, y: 0, width: 120, height: 22))
            itemView.configure(tab: tab, isSelected: true, isRenaming: false)
            let width = itemView.preferredWidth(minWidth: 80, maxWidth: 240)
            itemView.frame = NSRect(x: 0, y: 0, width: width, height: 22)
            itemView.layoutSubtreeIfNeeded()
            let availableTextWidth = width - (8 + 4 + 20 + 12)
            let neededTextWidth = (title as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 12, weight: .medium)]).width
            #expect(availableTextWidth >= neededTextWidth)
        }
        
        // Content-based title fallback avoids leaving generic/empty names
        let derived = WorkspaceOrganizer.fallbackContentTitle(
            from: "# AIME Bench 可视化优化\n\n具体设计如下",
            currentTitle: "摸鱼的洗衣机"
        )
        #expect(derived == "AIME Bench 可视化优化")
        
        // Apple Fluid Interface cursor spring stays crisp and subtly luminous without jelly wobble
        let shortParams = EditorFunEffectsController.fluidSpringParameters(distance: 12, isContinuous: false)
        let jumpParams = EditorFunEffectsController.fluidSpringParameters(distance: 140, isContinuous: false)
        let holdParams = EditorFunEffectsController.fluidSpringParameters(distance: 12, isContinuous: true)
        #expect(shortParams.zeta >= 0.84 && shortParams.zeta < 1.0)
        #expect(jumpParams.zeta >= 0.84 && jumpParams.zeta < 1.0)
        #expect(holdParams.omega >= shortParams.omega)
        #expect(holdParams.zeta > jumpParams.zeta)
        
        // Luminous wake tapers monotonically across the 4 trail capsules and hides cleanly at rest
        let idleTrail = EditorFunEffectsController.trailFrameParameters(layerIndex: 0, activity: 0, cursorAlpha: 0.56)
        #expect(idleTrail.alpha == 0)
        let trail0 = EditorFunEffectsController.trailFrameParameters(layerIndex: 0, activity: 1.0, cursorAlpha: 0.56)
        let trail3 = EditorFunEffectsController.trailFrameParameters(layerIndex: 3, activity: 1.0, cursorAlpha: 0.56)
        #expect(trail0.scale > trail3.scale)
        #expect(trail0.alpha > trail3.alpha && trail3.alpha > 0)
        
        let stretched = EditorFunEffectsController.fluidStretchedRect(
            center: CGPoint(x: 100, y: 50),
            baseSize: CGSize(width: 8, height: 18),
            velocity: CGPoint(x: 400, y: 0)
        )
        #expect(stretched.width > 8 && stretched.width <= 12.1)
        #expect(stretched.midX == 100 && stretched.midY == 50)
        
        // Vim motion acceleration protects gentle taps (1) and ramps smoothly on hold/rapid repeat
        #expect(VimEngine.acceleratedRepeatStep(for: .lineDown, streak: 0, elapsed: 0, fromKeyRepeat: false) == 1)
        #expect(VimEngine.acceleratedRepeatStep(for: .lineDown, streak: 3, elapsed: 0.25, fromKeyRepeat: false) == 1)
        #expect(VimEngine.acceleratedRepeatStep(for: .lineDown, streak: 1, elapsed: 0.02, fromKeyRepeat: true) == 1)
        #expect(VimEngine.acceleratedRepeatStep(for: .lineDown, streak: 4, elapsed: 0.13, fromKeyRepeat: true) == 1)
        let midHold = VimEngine.acceleratedRepeatStep(for: .lineDown, streak: 8, elapsed: 0.40, fromKeyRepeat: true)
        let longHold = VimEngine.acceleratedRepeatStep(for: .lineDown, streak: 20, elapsed: 1.0, fromKeyRepeat: true)
        #expect(midHold == 3)
        #expect(longHold == 4)
        
        let wordHold = VimEngine.acceleratedRepeatStep(for: .wordForward, streak: 12, elapsed: 0.6, fromKeyRepeat: true)
        #expect(wordHold == 3)
    }
    
    
    @Test func aiDocumentTextCleanerRemovesMarkdownButKeepsStructure() {
        
        let cleaned = AIDocumentTextCleaner.clean("""
        # 标题 **加粗**
        
        - **要点一**：完成 ✅ 😀
        - [x] 事项二
        - [ ] 事项三
        
        > 引用文字
        
        | 名称 | 状态 |
        | --- | --- |
        | 光标 | ✅ 完成 |
        
        链接 [文档](https://example.com) 和 `code`
        """)
        
        #expect(cleaned.contains("# 标题 加粗"))
        #expect(!cleaned.contains("**"))
        #expect(cleaned.contains("1. 要点一：完成 ✅"))
        #expect(!cleaned.contains("😀"))
        #expect(cleaned.contains("2. ✅ 事项二"))
        #expect(cleaned.contains("3. 事项三"))
        #expect(cleaned.contains("引用文字"))
        #expect(!cleaned.contains("|"))
        #expect(cleaned.contains("名称   状态"))
        #expect(cleaned.contains("光标   ✅ 完成"))
        #expect(cleaned.contains("文档 (https://example.com)"))
        #expect(cleaned.contains("code"))
        
        // Symbols inside a fenced code block are content, not decoration.
        let fenced = """
        ```swift
        let value = "**keep**"
        ```
        """
        #expect(AIDocumentTextCleaner.clean(fenced) == "let value = \"**keep**\"")
    }
    
    
    @Test func organizeProgressIgnoresLateChunksAfterCompletion() {
        
        let state = WorkspaceOrganizeProgressState(
            totalDocumentCount: 2,
            endpointDescription: "test · model"
        )
        state.markCompleted(summary: "完成")
        
        state.markStepActive(1, detail: "迟到的流式内容", progress: 1.0, headline: "步骤 2/4：正在接收")
        state.markStepActive(2, detail: "迟到的流式内容", progress: 1.0, headline: "步骤 3/4：正在更新")
        
        #expect(state.isFinished)
        #expect(state.statusHeadline == "全部文档已规整完毕")
        #expect(state.steps.allSatisfy { $0.status == .completed })
    }
    
    
    @Test func modelCatalogParsesOpenCodeGoNameField() throws {
        
        let json = """
        {"data":[{"id":"claude-haiku-5-5","name":"Claude Haiku 5.5"},{"id":"deepseek-v4.1-flash","name":"DeepSeek V4.1 Flash"}]}
        """
        let config = AIConfiguration(
            endpoint: .anthropicMessages,
            baseURL: "https://opencode.ai/inference/go",
            model: "deepseek-v4.1-flash",
            apiKey: "oc_sk_dummy"
        )
        #expect(config.modelsRequestURL?.absoluteString == "https://opencode.ai/inference/go/v1/models?limit=1000")
        let parsed = try AIModelCatalog.parse(Data(json.utf8), endpoint: .anthropicMessages)
        #expect(parsed.count == 2)
        #expect(parsed.first?.id == "claude-haiku-5-5")
        #expect(parsed.first?.name == "Claude Haiku 5.5 (claude-haiku-5-5)")
        
        // Also test OpenCode / OpenAI compatible format
        let ccModels = try AIModelCatalog.parse(Data(json.utf8), endpoint: .openAIResponses)
        #expect(ccModels.map(\.id) == ["claude-haiku-5-5", "deepseek-v4.1-flash"])
    }
    
    
    @Test func coordinatedDocumentRenameUpdatesFileURLAndDisplayName() throws {
        
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("CotCoordinatedRename-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        let sourceURL = tempDir.appendingPathComponent("scratch-old.txt")
        try "Line 1\nLine 2\n".write(to: sourceURL, atomically: true, encoding: .utf8)
        
        let doc = try Document(contentsOf: sourceURL, ofType: "public.plain-text")
        // Simulate a sticky custom displayName set before saving
        doc.displayName = "摸鱼的洗衣机"
        
        let newTitle = try WorkspaceOrganizer.renameDocument(doc, to: "2026.11 周报")
        #expect(newTitle == "2026.11 周报.txt")
        #expect(doc.fileURL?.lastPathComponent == "2026.11 周报.txt")
        #expect(doc.displayName == "2026.11 周报.txt")
        #expect(doc.isExplicitlyNamed == true)
        #expect(!FileManager.default.fileExists(atPath: sourceURL.path))
        #expect(FileManager.default.fileExists(atPath: tempDir.appendingPathComponent("2026.11 周报.txt").path))
        
        let canonical = DocumentCenterState.canonicalKey(
            filePath: doc.fileURL?.path(percentEncoded: false),
            rawID: doc.databaseDocumentID
        )
        #expect(canonical.hasPrefix("file:"))
        #expect(canonical.hasSuffix("/2026.11 周报.txt"))
    }
    
    
    @Test func aiClientTemperatureCompatibilityAndErrorDetection() {
        
        #expect(AIClient.supportsTemperature(for: "claude-haiku-5-5") == false)
        #expect(AIClient.supportsTemperature(for: "anthropic/claude-haiku-5-5") == false)
        #expect(AIClient.supportsTemperature(for: "claude-sonnet-5.0") == false)
        #expect(AIClient.supportsTemperature(for: "gpt-5") == false)
        #expect(AIClient.supportsTemperature(for: "o3-mini") == false)
        #expect(AIClient.supportsTemperature(for: "deepseek-reasoner") == false)
        
        #expect(AIClient.supportsTemperature(for: "claude-3-5-sonnet") == true)
        #expect(AIClient.supportsTemperature(for: "deepseek-v4.1-flash") == true)
        #expect(AIClient.supportsTemperature(for: "deepseek/deepseek-v4.1-flash") == true)
        
        let deprecatedError = AIError.http(
            status: 400,
            message: #"{"type":"error","error":{"type":"invalid_request_error","message":"`temperature` is deprecated for this model."}}"#
        )
        #expect(AIClient.isTemperatureRejectedError(deprecatedError) == true)
        #expect(AIClient.isTemperatureRejectedError(AIError.http(status: 400, message: "max_tokens invalid")) == false)
        #expect(AIClient.isTemperatureRejectedError(AIError.http(status: 401, message: "temperature deprecated")) == false)
    }
    
    
    @Test func organizeProgressControllerDismissesAndRetainsLifecycle() {
        
        let controller = WorkspaceOrganizeProgressController(
            totalDocumentCount: 3,
            endpointDescription: "cmy-command-code-1 · claude-haiku-5-5"
        )
        var dismissCount = 0
        controller.onDismiss = { dismissCount += 1 }
        controller.onRetry = { }
        
        #expect(controller.state.canRetry == true)
        controller.state.markFailed(message: "temperature is deprecated")
        #expect(controller.state.isFinished == true)
        #expect(controller.state.errorMessage == "temperature is deprecated")
        
        controller.cancelOperation(nil)
        #expect(dismissCount == 1)
        
        // Idempotent repeat close does not double-fire
        controller.dismissSheet()
        #expect(dismissCount == 1)
    }
}
