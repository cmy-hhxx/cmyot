//
//  Round35AIBackendAndDashboardHeroTests.swift
//
//  CotEditor
//  https://coteditor.com
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
import SwiftUI
import Testing
@testable import CotEditor

@Suite(.serialized)
@MainActor
struct Round35AIBackendAndDashboardHeroTests {
    
    private func makeTempDir() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appending(path: "coteditor-round35-\(UUID().uuidString)", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
    
    
    /// Writes a self-contained executable mock `pi --mode rpc` script using `/usr/bin/python3`
    /// so timeout, cancellation, reset, and recovery paths run deterministically with zero network calls.
    private func writeMockPiRPCScript(in dir: URL) throws -> URL {
        let scriptURL = dir.appending(path: "mock-pi-rpc.py")
        let script = """
        #!/usr/bin/env python3
        import json, sys, time

        def emit(obj):
            sys.stdout.write(json.dumps(obj) + "\\n")
            sys.stdout.flush()

        for raw in sys.stdin:
            raw = raw.strip()
            if not raw:
                continue
            try:
                cmd = json.loads(raw)
            except Exception:
                continue
            cid = cmd.get("id")
            ctype = cmd.get("type")

            if ctype in ("set_model", "set_thinking_level", "new_session", "get_state"):
                emit({"type": "response", "id": cid, "command": ctype, "success": True})
                continue

            if ctype == "abort":
                emit({"type": "response", "id": cid, "command": "abort", "success": True})
                continue

            if ctype == "prompt":
                msg = cmd.get("message", "")
                if "CASE_HANDLED" in msg:
                    emit({"type": "response", "id": cid, "command": "prompt", "success": True, "data": {"disposition": "handled"}})
                    continue

                emit({"type": "response", "id": cid, "command": "prompt", "success": True})

                if "CASE_HANG_TOOL" in msg:
                    emit({
                        "type": "tool_execution_start",
                        "toolCallId": "tc-hang-1",
                        "toolName": "lookup_stock_quote",
                        "args": {"query": "NVDA"}
                    })
                    # Intentionally hang without ending tool or settling turn
                    time.sleep(30)
                    continue

                if "CASE_HANG_IDLE" in msg:
                    time.sleep(30)
                    continue

                # Normal fast turn with thinking + tool + text
                emit({"type": "message_update", "assistantMessageEvent": {"type": "thinking_start", "contentIndex": 0}})
                emit({"type": "message_update", "assistantMessageEvent": {"type": "thinking_delta", "contentIndex": 0, "delta": "Checking live quote"}})
                time.sleep(0.06)
                emit({"type": "message_update", "assistantMessageEvent": {"type": "thinking_end", "contentIndex": 0, "content": "Checking live quote"}})
                emit({
                    "type": "tool_execution_start",
                    "toolCallId": "tc-ok-1",
                    "toolName": "lookup_stock_quote",
                    "args": {"query": "600703"}
                })
                time.sleep(0.08)
                emit({
                    "type": "tool_execution_end",
                    "toolCallId": "tc-ok-1",
                    "toolName": "lookup_stock_quote",
                    "isError": False,
                    "result": "三安光电 14.20 (+2.1%)"
                })
                emit({"type": "message_update", "assistantMessageEvent": {"type": "text_delta", "contentIndex": 1, "delta": "OK_RECOVERY_REPLY"}})
                emit({"type": "agent_settled"})
        """
        try Data(script.utf8).write(to: scriptURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path(percentEncoded: false))
        return scriptURL
    }
    
    
    private func makeRGBImage(
        width: Int,
        height: Int,
        pixelColor: (_ x: Int, _ y: Int) -> (UInt8, UInt8, UInt8)
    ) -> NSImage {
        var bytes = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let (r, g, b) = pixelColor(x, y)
                let i = (y * width + x) * 4
                bytes[i] = r
                bytes[i + 1] = g
                bytes[i + 2] = b
                bytes[i + 3] = 255
            }
        }
        let cs = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        let info = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        let provider = CGDataProvider(data: Data(bytes) as CFData)!
        let cgImage = CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: cs,
            bitmapInfo: CGBitmapInfo(rawValue: info),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )!
        return NSImage(cgImage: cgImage, size: NSSize(width: width, height: height))
    }
    
    
    // MARK: 1. Pi Base URL Normalization, Safe CWD & Non-Blocking cot-tools.ts
    
    @Test func piKernelNormalizesAnthropicBaseURLAndWritesAsyncTools() throws {
        #expect(PiKernelManager.normalizedPiBaseURL("https://api.anthropic.com/v1", endpoint: .anthropicMessages) == "https://api.anthropic.com")
        #expect(PiKernelManager.normalizedPiBaseURL("https://api.anthropic.com/v1/messages", endpoint: .anthropicMessages) == "https://api.anthropic.com")
        #expect(PiKernelManager.normalizedPiBaseURL("https://opencode.ai/zen/go/v1", endpoint: .anthropicMessages) == "https://opencode.ai/zen/go")
        #expect(PiKernelManager.normalizedPiBaseURL("https://opencode.ai/zen/go", endpoint: .anthropicMessages) == "https://opencode.ai/zen/go")
        #expect(PiKernelManager.normalizedPiBaseURL("https://api.openai.com/v1/chat/completions", endpoint: .openAIChatCompletions) == "https://api.openai.com/v1")
        #expect(PiKernelManager.normalizedPiBaseURL("http://localhost:11434", endpoint: .ollama) == "http://localhost:11434/v1")
        
        let tempDir = self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        let db = CotLocalDatabase(customURL: tempDir.appending(path: "cot.sqlite3"))
        let piDir = tempDir.appending(path: "PiKernel", directoryHint: .isDirectory)
        let manager = PiKernelManager(customAgentDirectoryURL: piDir, database: db)
        
        let profile = AIProvider.openCodeGo.makeProfile(customName: "OpenCode Go", modelOverride: "glm-5.3")
        _ = try manager.syncWorkspace(endpoints: [profile], keyLookup: { _ in "sk-test" })
        
        // Workspace dir exists and safeWorkingDirectory never falls back to `/`
        let safeNil = PiRPCRuntime.safeWorkingDirectory(preferred: nil, agentDirectoryURL: piDir)
        let safeRoot = PiRPCRuntime.safeWorkingDirectory(preferred: URL(filePath: "/"), agentDirectoryURL: piDir)
        #expect(safeNil.path(percentEncoded: false) != "/")
        #expect(safeRoot.path(percentEncoded: false) != "/")
        #expect(safeRoot.lastPathComponent == "workspace")
        
        // Non-blocking cot-tools.ts (no event-loop-freezing execFileSync) + bash timeout & root guard
        let extURL = piDir.appending(path: "extensions/\(PiCotToolsExtension.filename)")
        let extSource = try String(contentsOf: extURL, encoding: .utf8)
        #expect(!extSource.contains("execFileSync"))
        #expect(extSource.contains("execFileAsync"))
        #expect(extSource.contains("pi.on(\"tool_call\""))
        
        // All recommended models for provider synced into models.json
        let modelsData = try Data(contentsOf: piDir.appending(path: "models.json"))
        let root = try #require(try JSONSerialization.jsonObject(with: modelsData) as? [String: Any])
        let providers = try #require(root["providers"] as? [String: Any])
        let providerEntry = try #require(providers[PiKernelManager.providerID(for: profile)] as? [String: Any])
        let models = try #require(providerEntry["models"] as? [[String: Any]])
        let modelIDs = Set(models.compactMap { $0["id"] as? String })
        for recommended in AIProvider.openCodeGo.recommendedModels {
            #expect(modelIDs.contains(recommended))
        }
    }
    
    
    // MARK: 2. Accurate Tool Duration Resolution
    
    @Test func piRPCRuntimeResolvesToolDurationsFromNumbersAndWallClockFallback() {
        let t0 = Date(timeIntervalSince1970: 1_000.0)
        let t1 = Date(timeIntervalSince1970: 1_001.25)
        
        #expect(PiRPCRuntime.resolvedToolDurationMs(rawDurationValue: 345, startedAt: t0, now: t1) == 345)
        #expect(PiRPCRuntime.resolvedToolDurationMs(rawDurationValue: 412.6, startedAt: t0, now: t1) == 413)
        #expect(PiRPCRuntime.resolvedToolDurationMs(rawDurationValue: NSNumber(value: 88.2), startedAt: t0, now: t1) == 88)
        #expect(PiRPCRuntime.resolvedToolDurationMs(rawDurationValue: nil, startedAt: t0, now: t1) == 1250)
        #expect(PiRPCRuntime.resolvedToolDurationMs(rawDurationValue: 0, startedAt: t0, now: t1) == 1250)
    }
    
    
    // MARK: 3. Tool Timeout Recycles Wedged Daemon & Next Turn Succeeds (Zero Session Lock)
    
    @Test func piRPCRuntimeRecoversFromHungToolWithoutSessionLock() async throws {
        let tempDir = self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        let mockPi = try self.writeMockPiRPCScript(in: tempDir)
        let piDir = tempDir.appending(path: "PiKernel", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: piDir.appending(path: "extensions", directoryHint: .isDirectory), withIntermediateDirectories: true)
        try Data("// noop".utf8).write(to: piDir.appending(path: "extensions/\(PiCotToolsExtension.filename)"))
        
        let runtime = PiRPCRuntime(timeoutPolicy: .init(
            promptAckSeconds: 6,
            cotToolTimeoutSeconds: 0.45,
            workspaceToolTimeoutSeconds: 0.45,
            idleTurnTimeoutSeconds: 4,
            maxTurnDurationSeconds: 10,
            abortGraceMilliseconds: 120
        ))
        defer {
            Task { await runtime.shutdownAll() }
        }
        
        var sawTimedOutToolEnd = false
        var measuredTimeoutDurationMs = 0
        
        let hangReq = PiRPCTurnRequest(
            channel: .butler,
            binaryPath: mockPi.path(percentEncoded: false),
            agentDirectoryURL: piDir,
            databasePath: tempDir.appending(path: "cot.sqlite3").path(percentEncoded: false),
            workspaceConfigStamp: "s1",
            workingDirectoryURL: nil,
            logicalSessionKey: "sess-1",
            providerID: "mock-provider",
            modelID: "mock-model",
            thinkingLevel: nil,
            systemPrompt: "sys",
            userPrompt: "CASE_HANG_TOOL",
            priorHistoryContext: nil
        )
        
        do {
            _ = try await runtime.runTurn(hangReq) { event in
                if case .toolEnd(_, let name, let isError, let durationMs, _) = event, name == "lookup_stock_quote" {
                    sawTimedOutToolEnd = isError
                    measuredTimeoutDurationMs = durationMs ?? 0
                }
            }
            Issue.record("Expected hung tool turn to fail with timeout")
        } catch {
            // Expected timeout failure
        }
        
        #expect(sawTimedOutToolEnd == true)
        #expect(measuredTimeoutDurationMs >= 300)
        
        // Immediately send a second turn on a brand new session — must NOT be locked!
        let recoveryReq = PiRPCTurnRequest(
            channel: .butler,
            binaryPath: mockPi.path(percentEncoded: false),
            agentDirectoryURL: piDir,
            databasePath: tempDir.appending(path: "cot.sqlite3").path(percentEncoded: false),
            workspaceConfigStamp: "s1",
            workingDirectoryURL: nil,
            logicalSessionKey: "sess-2",
            providerID: "mock-provider",
            modelID: "mock-model",
            thinkingLevel: nil,
            systemPrompt: "sys",
            userPrompt: "NORMAL_SECOND_TURN",
            priorHistoryContext: nil
        )
        let result = try await runtime.runTurn(recoveryReq) { _ in }
        #expect(result.text == "OK_RECOVERY_REPLY")
        #expect(result.toolNames == ["lookup_stock_quote"])
        
        // Verify thinking step is separated (`kind == "thinking"`) and tool step has real measured durationMs
        let thinkingStep = try #require(result.steps.first(where: { $0.kind == "thinking" }))
        #expect((thinkingStep.durationMs ?? 0) >= 30)
        let toolStep = try #require(result.steps.first(where: { $0.kind == "tool" }))
        #expect(toolStep.status == "done")
        #expect((toolStep.durationMs ?? 0) >= 40)
    }
    
    
    // MARK: 4. Cooperative Cancellation, ResetSession & Handled Disposition
    
    @Test func piRPCRuntimeHandlesTaskCancellationAndHandledDispositionCleanly() async throws {
        let tempDir = self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        let mockPi = try self.writeMockPiRPCScript(in: tempDir)
        let piDir = tempDir.appending(path: "PiKernel", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: piDir.appending(path: "extensions", directoryHint: .isDirectory), withIntermediateDirectories: true)
        try Data("// noop".utf8).write(to: piDir.appending(path: "extensions/\(PiCotToolsExtension.filename)"))
        
        let runtime = PiRPCRuntime(timeoutPolicy: .init(
            promptAckSeconds: 6,
            cotToolTimeoutSeconds: 5,
            workspaceToolTimeoutSeconds: 5,
            idleTurnTimeoutSeconds: 10,
            maxTurnDurationSeconds: 15,
            abortGraceMilliseconds: 100
        ))
        defer {
            Task { await runtime.shutdownAll() }
        }
        
        let idleReq = PiRPCTurnRequest(
            channel: .news,
            binaryPath: mockPi.path(percentEncoded: false),
            agentDirectoryURL: piDir,
            databasePath: tempDir.appending(path: "cot.sqlite3").path(percentEncoded: false),
            workspaceConfigStamp: "s1",
            workingDirectoryURL: nil,
            logicalSessionKey: "news-1",
            providerID: "mock-provider",
            modelID: "mock-model",
            thinkingLevel: nil,
            systemPrompt: "sys",
            userPrompt: "CASE_HANG_IDLE",
            priorHistoryContext: nil
        )
        
        let task = Task {
            try await runtime.runTurn(idleReq) { _ in }
        }
        try await Task.sleep(for: .milliseconds(250))
        task.cancel()
        
        do {
            _ = try await task.value
            Issue.record("Expected CancellationError")
        } catch is CancellationError {
            // Expected instant cooperative cancellation
        }
        
        // Immediately follow up with a `disposition == "handled"` command — must settle without hanging
        let handledReq = PiRPCTurnRequest(
            channel: .news,
            binaryPath: mockPi.path(percentEncoded: false),
            agentDirectoryURL: piDir,
            databasePath: tempDir.appending(path: "cot.sqlite3").path(percentEncoded: false),
            workspaceConfigStamp: "s1",
            workingDirectoryURL: nil,
            logicalSessionKey: "news-2",
            providerID: "mock-provider",
            modelID: "mock-model",
            thinkingLevel: nil,
            systemPrompt: "sys",
            userPrompt: "CASE_HANDLED",
            priorHistoryContext: nil
        )
        let handledResult = try await runtime.runTurn(handledReq) { _ in }
        #expect(handledResult.aborted == false)
    }
    
    
    // MARK: 5. CotButlerManager Session Switching & New Session Never Lock
    
    @Test func butlerManagerSessionOperationsStayUnlockedAndConsistent() {
        let tempDir = self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        let db = CotLocalDatabase(customURL: tempDir.appending(path: "butler.sqlite3"))
        let mem = CotMemoryStore(database: db)
        let manager = CotButlerManager(database: db, memoryStore: mem)
        
        let initialSessionID = manager.activeSessionID
        #expect(!initialSessionID.isEmpty)
        #expect(manager.isStreaming == false)
        
        // Add a message to the initial session, then create a new session
        db.appendButlerMessage(ButlerChatMessage(
            id: UUID().uuidString,
            sessionID: initialSessionID,
            role: "user",
            content: "第一条消息",
            actionsJSON: "[]",
            createdAt: Date()
        ))
        manager.reloadFromDatabase()
        #expect(manager.messages.count == 1)
        
        manager.startNewSession()
        #expect(manager.activeSessionID != initialSessionID)
        #expect(manager.messages.isEmpty)
        #expect(manager.isStreaming == false)
        
        // Switch back, abort (no-op when idle), clear, and delete cleanly
        manager.selectSession(initialSessionID)
        #expect(manager.activeSessionID == initialSessionID)
        #expect(manager.messages.count == 1)
        manager.abortStreaming()
        #expect(manager.isStreaming == false)
        manager.clearCurrentSession()
        #expect(manager.messages.isEmpty)
        manager.deleteSession(initialSessionID)
        #expect(manager.activeSessionID != initialSessionID)
        #expect(manager.isStreaming == false)
    }
    
    
    // MARK: 6. Dashboard Hero Cover Real-Time Regional Tone Sampler & Adaptive Glass
    
    @Test func heroCoverToneSamplerAdaptsBackAndDanmakuAcrossLightDarkSplitAndFocalShift() {
        let lightPalette = DashPalette(.light)
        
        // 1. Pure bright white image -> light background, dark ink (never pure black glass)
        let whiteImg = self.makeRGBImage(width: 120, height: 40) { _, _ in (248, 250, 252) }
        let whiteSample = HeroCoverToneSampler.sample(
            image: whiteImg,
            focalY: 0.5,
            canvasAspect: 3.0,
            fallbackRGB: (0.95, 0.95, 0.96)
        )
        #expect(whiteSample.hasPhoto == true)
        #expect(whiteSample.topLeft.isLightBackground == true)
        #expect(whiteSample.topRight.isLightBackground == true)
        #expect(HeroAdaptiveGlassTokens.resolve(for: whiteSample.topLeft, hasPhoto: true, palette: lightPalette).usesLightInk == false)
        
        // 2. Deep dark twilight image -> dark background, luminous light ink
        let darkImg = self.makeRGBImage(width: 120, height: 40) { _, _ in (18, 28, 48) }
        let darkSample = HeroCoverToneSampler.sample(
            image: darkImg,
            focalY: 0.5,
            canvasAspect: 3.0,
            fallbackRGB: (0.95, 0.95, 0.96)
        )
        #expect(darkSample.topLeft.isLightBackground == false)
        #expect(HeroAdaptiveGlassTokens.resolve(for: darkSample.topLeft, hasPhoto: true, palette: lightPalette).usesLightInk == true)
        
        // 3. Left-bright / Right-dark split -> Back button & top-right controls adapt independently,
        //    and danmakuTone(atNormalizedX:) adapts smoothly as a pill glides from right to left!
        let splitImg = self.makeRGBImage(width: 120, height: 40) { x, _ in
            x < 60 ? (245, 245, 248) : (16, 22, 34)
        }
        let splitSample = HeroCoverToneSampler.sample(
            image: splitImg,
            focalY: 0.5,
            canvasAspect: 3.0,
            fallbackRGB: (0.5, 0.5, 0.5)
        )
        #expect(splitSample.topLeft.isLightBackground == true)
        #expect(splitSample.topRight.isLightBackground == false)
        let leftDanmaku = splitSample.danmakuTone(atNormalizedX: 0.12)
        let midDanmaku = splitSample.danmakuTone(atNormalizedX: 0.50)
        let rightDanmaku = splitSample.danmakuTone(atNormalizedX: 0.88)
        #expect(leftDanmaku.isLightBackground == true)
        #expect(rightDanmaku.isLightBackground == false)
        #expect(leftDanmaku.luminance > midDanmaku.luminance)
        #expect(midDanmaku.luminance > rightDanmaku.luminance)
        
        // 4. Tall top-bright / bottom-dark image: shifting focalY from 0.0 -> 1.0 flips sampled tone in real time!
        let verticalSplit = self.makeRGBImage(width: 120, height: 240) { _, y in
            y < 120 ? (245, 248, 250) : (14, 20, 30)
        }
        let focusedTop = HeroCoverToneSampler.sample(
            image: verticalSplit,
            focalY: 0.0,
            canvasAspect: 3.0,
            fallbackRGB: (0.5, 0.5, 0.5)
        )
        let focusedBottom = HeroCoverToneSampler.sample(
            image: verticalSplit,
            focalY: 1.0,
            canvasAspect: 3.0,
            fallbackRGB: (0.5, 0.5, 0.5)
        )
        #expect(focusedTop.topLeft.isLightBackground == true)
        #expect(focusedBottom.topLeft.isLightBackground == false)
    }
}
