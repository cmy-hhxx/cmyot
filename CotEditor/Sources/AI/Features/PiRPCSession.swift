//
//  PiRPCSession.swift
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

import Foundation

/// Logical warm Pi RPC channel isolating session history and tool exposure.
nonisolated enum PiAgentChannel: String, Sendable, CaseIterable {
    /// Chief Butler: full Cot tools + Pi workspace coding tools.
    case butler
    /// NEWS AI companion: Cot data/search/note tools only (`--no-builtin-tools`).
    case news
    
    var allowsBuiltinTools: Bool {
        switch self {
            case .butler: true
            case .news: false
        }
    }
}


/// Fine-grained event emitted while a warm Pi RPC turn is streaming.
nonisolated enum PiAgentStreamEvent: Sendable {
    case status(String)
    case thinkingDelta(String)
    case thinkingEnd(String)
    case toolStart(id: String, name: String, label: String, detail: String?)
    case toolUpdate(id: String, outputPreview: String)
    case toolEnd(id: String, name: String, isError: Bool, durationMs: Int?, outputPreview: String?)
    case textDelta(String)
    case textEnd(String)
    case error(String)
    case settled
}


/// Final aggregated result of one Pi RPC conversation turn.
nonisolated struct PiAgentRunResult: Sendable {
    var text: String
    var thinking: String
    var thinkingDurationMs: Int
    var steps: [BeautifulAgentThinkingStep]
    var toolNames: [String]
    var aborted: Bool
}


/// Human-friendly labels & argument summaries for Pi tool calls rendered inside `ThinkingState`.
nonisolated enum PiToolDisplayMeta {
    
    static func label(for toolName: String) -> String {
        switch toolName {
            case "lookup_stock_quote": AppLanguage.text("查询实时行情", en: "Lookup Stock Quote")
            case "search_news": AppLanguage.text("检索资讯热点", en: "Search News")
            case "web_search": AppLanguage.text("全网搜索", en: "Web Search")
            case "web_fetch": AppLanguage.text("读取网页正文", en: "Fetch Web Page")
            case "get_workspace_context": AppLanguage.text("感知当前工作区", en: "Inspect Workspace")
            case "search_documents": AppLanguage.text("检索本地笔记", en: "Search Documents")
            case "read_document": AppLanguage.text("读取文档全文", en: "Read Document")
            case "read_memory": AppLanguage.text("读取长期记忆", en: "Read Memory")
            case "editor_action": AppLanguage.text("执行编辑器操作", en: "Editor Action")
            case "read": AppLanguage.text("读取文件", en: "Read File")
            case "grep": AppLanguage.text("搜索代码/文本", en: "Search Text")
            case "find", "ls": AppLanguage.text("浏览目录", en: "List Files")
            case "bash": AppLanguage.text("执行命令", en: "Run Command")
            case "edit", "write": AppLanguage.text("编辑文件", en: "Edit File")
            default: toolName
        }
    }
    
    
    static func summarizeArgs(_ toolName: String, args: [String: Any]?) -> String? {
        guard let args, !args.isEmpty else { return nil }
        switch toolName {
            case "lookup_stock_quote":
                let q = (args["query"] as? String) ?? ""
                let period = (args["period"] as? String) ?? ""
                return period.isEmpty || period == "day" ? q : "\(q) (\(period))"
            case "search_news", "web_search", "search_documents":
                return args["query"] as? String
            case "web_fetch":
                return args["url"] as? String
            case "read_document":
                return args["idOrTitle"] as? String
            case "editor_action":
                let parts = [
                    args["type"] as? String,
                    args["board"] as? String,
                    args["query"] as? String,
                    args["title"] as? String,
                    args["name"] as? String,
                ].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
                return parts.joined(separator: " · ")
            case "read", "edit", "write":
                return (args["path"] as? String) ?? (args["file_path"] as? String)
            case "bash":
                return (args["command"] as? String).map { String($0.prefix(120)) }
            case "grep":
                return args["pattern"] as? String
            default:
                if let data = try? JSONSerialization.data(withJSONObject: args),
                   let str = String(data: data, encoding: .utf8)
                {
                    return String(str.prefix(120))
                }
                return nil
        }
    }
    
    
    static func extractToolOutputText(from raw: Any?) -> String? {
        guard let raw else { return nil }
        if let str = raw as? String {
            let clean = str.trimmingCharacters(in: .whitespacesAndNewlines)
            return clean.isEmpty ? nil : String(clean.prefix(600))
        }
        if let dict = raw as? [String: Any] {
            if let content = dict["content"] as? [[String: Any]] {
                let joined = content.compactMap { $0["text"] as? String }.joined(separator: "\n")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !joined.isEmpty { return String(joined.prefix(600)) }
            }
            if let text = dict["text"] as? String, !text.isEmpty {
                return String(text.prefix(600))
            }
        }
        return nil
    }
}


/// Configuration snapshot passed into a warm Pi RPC turn.
nonisolated struct PiRPCTurnRequest: Sendable {
    var channel: PiAgentChannel
    var binaryPath: String
    var agentDirectoryURL: URL
    var databasePath: String
    var workspaceConfigStamp: String
    var workingDirectoryURL: URL?
    var logicalSessionKey: String
    var providerID: String
    var modelID: String
    var thinkingLevel: String?
    var systemPrompt: String
    var userPrompt: String
    var priorHistoryContext: String?
}


/// Manages warm, persistent `pi --mode rpc` child processes keyed by `PiAgentChannel`.
///
/// Keeps processes alive between turns so follow-ups start in milliseconds, dynamically refreshes
/// per-turn system prompts via `COT_DYNAMIC_SYSTEM_PROMPT_FILE`, hot-switches models via `set_model`,
/// and immediately drains CotEditor's SQLite action queue whenever `editor_action` completes.
actor PiRPCRuntime {
    
    static let shared = PiRPCRuntime()
    
    private final class ChannelDaemon: @unchecked Sendable {
        let channel: PiAgentChannel
        let process: Process
        let stdinHandle: FileHandle
        let stdoutHandle: FileHandle
        let stderrHandle: FileHandle
        let systemPromptFileURL: URL
        let workspaceConfigStamp: String
        var currentProviderID: String
        var currentModelID: String
        var currentThinkingLevel: String?
        var activeLogicalSessionKey: String?
        var isRunningTurn: Bool = false
        var stdoutTask: Task<Void, Never>?
        var stderrTask: Task<Void, Never>?
        var stderrBuffer: String = ""
        
        init(
            channel: PiAgentChannel,
            process: Process,
            stdinHandle: FileHandle,
            stdoutHandle: FileHandle,
            stderrHandle: FileHandle,
            systemPromptFileURL: URL,
            workspaceConfigStamp: String,
            providerID: String,
            modelID: String
        ) {
            self.channel = channel
            self.process = process
            self.stdinHandle = stdinHandle
            self.stdoutHandle = stdoutHandle
            self.stderrHandle = stderrHandle
            self.systemPromptFileURL = systemPromptFileURL
            self.workspaceConfigStamp = workspaceConfigStamp
            self.currentProviderID = providerID
            self.currentModelID = modelID
        }
    }
    
    private struct ActiveTurn {
        let continuation: CheckedContinuation<PiAgentRunResult, Error>
        let onEvent: @MainActor @Sendable (PiAgentStreamEvent) -> Void
        let startedAt: Date
        var textBlocks: [Int: String] = [:]
        var thinkingBlocks: [Int: String] = [:]
        var finalAssistantText: String?
        var steps: [BeautifulAgentThinkingStep] = []
        var toolNames: [String] = []
        var errorMessage: String?
        var aborted: Bool = false
        var thinkingStepID: String?
        var lastTextEmitUptime: TimeInterval = 0
    }
    
    private var daemons: [PiAgentChannel: ChannelDaemon] = [:]
    private var pendingResponses: [String: CheckedContinuation<[String: Any], Error>] = [:]
    private var promptCommandChannels: [String: PiAgentChannel] = [:]
    private var activeTurns: [PiAgentChannel: ActiveTurn] = [:]
    private var nextCommandSeq: Int = 1
    
    
    // MARK: - Public Control
    
    func runTurn(
        _ request: PiRPCTurnRequest,
        onEvent: @escaping @MainActor @Sendable (PiAgentStreamEvent) -> Void
    ) async throws -> PiAgentRunResult {
        // Ensure any previous stuck turn on this channel is aborted cleanly
        if self.activeTurns[request.channel] != nil {
            await self.abort(channel: request.channel)
            try? await Task.sleep(for: .milliseconds(120))
        }
        
        let daemon = try self.ensureDaemon(for: request)
        
        // Write fresh per-turn dynamic system prompt read by `cot-tools.ts`'s `before_agent_start` hook
        try Data(request.systemPrompt.utf8).write(to: daemon.systemPromptFileURL, options: .atomic)
        
        // Switch logical session if user switched chat thread or NEWS article
        var effectivePrompt = request.userPrompt
        let needsSessionReset = daemon.activeLogicalSessionKey != request.logicalSessionKey
        if needsSessionReset {
            if daemon.activeLogicalSessionKey != nil {
                _ = try? await self.sendCommand(to: daemon, payload: ["type": "new_session"], timeoutSec: 8)
            }
            daemon.activeLogicalSessionKey = request.logicalSessionKey
            if let prior = request.priorHistoryContext?.trimmingCharacters(in: .whitespacesAndNewlines),
               !prior.isEmpty
            {
                effectivePrompt = """
                <previous_conversation_context>
                \(prior)
                </previous_conversation_context>

                当前用户新消息：
                \(request.userPrompt)
                """
            }
        }
        
        // Sync model & thinking level on warm daemon
        if daemon.currentProviderID != request.providerID || daemon.currentModelID != request.modelID {
            let resp = try await self.sendCommand(
                to: daemon,
                payload: [
                    "type": "set_model",
                    "provider": request.providerID,
                    "modelId": request.modelID,
                ],
                timeoutSec: 8
            )
            if (resp["success"] as? Bool) == true {
                daemon.currentProviderID = request.providerID
                daemon.currentModelID = request.modelID
            }
        }
        
        if let desiredThinking = Self.normalizedPiThinkingLevel(request.thinkingLevel),
           daemon.currentThinkingLevel != desiredThinking
        {
            _ = try? await self.sendCommand(
                to: daemon,
                payload: [
                    "type": "set_thinking_level",
                    "level": desiredThinking,
                ],
                timeoutSec: 5
            )
            daemon.currentThinkingLevel = desiredThinking
        }
        
        daemon.isRunningTurn = true
        let promptCommandID = self.makeCommandID(prefix: request.channel.rawValue)
        
        return try await withCheckedThrowingContinuation { continuation in
            let turn = ActiveTurn(
                continuation: continuation,
                onEvent: onEvent,
                startedAt: Date()
            )
            self.activeTurns[request.channel] = turn
            
            let cmd: [String: Any] = [
                "id": promptCommandID,
                "type": "prompt",
                "message": effectivePrompt,
            ]
            self.promptCommandChannels[promptCommandID] = request.channel
            do {
                try self.writeJSONLine(cmd, to: daemon.stdinHandle)
            } catch {
                self.promptCommandChannels.removeValue(forKey: promptCommandID)
                self.finishTurn(channel: request.channel, error: error)
                return
            }
        }
    }
    
    
    func abort(channel: PiAgentChannel) async {
        guard let daemon = self.daemons[channel], daemon.process.isRunning else { return }
        if var turn = self.activeTurns[channel] {
            turn.aborted = true
            self.activeTurns[channel] = turn
        }
        let cmd: [String: Any] = [
            "id": self.makeCommandID(prefix: "abort"),
            "type": "abort",
        ]
        try? self.writeJSONLine(cmd, to: daemon.stdinHandle)
    }
    
    
    func resetSession(channel: PiAgentChannel) async {
        guard let daemon = self.daemons[channel] else { return }
        daemon.activeLogicalSessionKey = nil
        if daemon.process.isRunning && !daemon.isRunningTurn {
            _ = try? await self.sendCommand(to: daemon, payload: ["type": "new_session"], timeoutSec: 5)
        }
    }
    
    
    func shutdownAll() {
        for channel in Array(self.daemons.keys) {
            self.terminateDaemon(channel: channel, reason: "Pi 内核已关闭")
        }
    }
    
    
    // MARK: - Daemon Lifecycle
    
    private func ensureDaemon(for request: PiRPCTurnRequest) throws -> ChannelDaemon {
        if let existing = self.daemons[request.channel] {
            if existing.process.isRunning && existing.workspaceConfigStamp == request.workspaceConfigStamp {
                return existing
            }
            self.terminateDaemon(channel: request.channel, reason: "配置已更新，正在重启 Pi 内核")
        }
        
        let fm = FileManager.default
        let runtimeDir = request.agentDirectoryURL.appending(path: "runtime", directoryHint: .isDirectory)
        let sessionDir = request.agentDirectoryURL
            .appending(path: "sessions", directoryHint: .isDirectory)
            .appending(path: "rpc-\(request.channel.rawValue)", directoryHint: .isDirectory)
        let extensionURL = request.agentDirectoryURL
            .appending(path: "extensions", directoryHint: .isDirectory)
            .appending(path: PiCotToolsExtension.filename)
        try fm.createDirectory(at: runtimeDir, withIntermediateDirectories: true)
        try fm.createDirectory(at: sessionDir, withIntermediateDirectories: true)
        
        let systemPromptFile = runtimeDir.appending(path: "\(request.channel.rawValue)-system.md")
        try Data(request.systemPrompt.utf8).write(to: systemPromptFile, options: .atomic)
        
        var args: [String] = [
            "--mode", "rpc",
            "--offline",
            "--no-extensions",
            "-e", extensionURL.path(percentEncoded: false),
            "--no-mcp",
            "--no-skills",
            "--no-prompt-templates",
            "--no-themes",
            "--no-context-files",
            "--no-approve",
            "--provider", request.providerID,
            "--model", request.modelID,
            "--session-dir", sessionDir.path(percentEncoded: false),
            "--system-prompt", systemPromptFile.path(percentEncoded: false),
        ]
        if !request.channel.allowsBuiltinTools {
            args.append("--no-builtin-tools")
        }
        if let level = Self.normalizedPiThinkingLevel(request.thinkingLevel) {
            args.append(contentsOf: ["--thinking", level])
        }
        
        let process = Process()
        process.executableURL = URL(filePath: request.binaryPath)
        process.arguments = args
        if let cwd = request.workingDirectoryURL, fm.fileExists(atPath: cwd.path(percentEncoded: false)) {
            process.currentDirectoryURL = cwd
        }
        var env = PiKernelManager.augmentedRuntimeEnvironment(
            binaryPath: request.binaryPath,
            agentDirectoryPath: request.agentDirectoryURL.path(percentEncoded: false),
            databasePath: request.databasePath
        )
        env["COT_DYNAMIC_SYSTEM_PROMPT_FILE"] = systemPromptFile.path(percentEncoded: false)
        env["COT_CHANNEL"] = request.channel.rawValue
        process.environment = env
        
        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        
        try process.run()
        
        let daemon = ChannelDaemon(
            channel: request.channel,
            process: process,
            stdinHandle: stdinPipe.fileHandleForWriting,
            stdoutHandle: stdoutPipe.fileHandleForReading,
            stderrHandle: stderrPipe.fileHandleForReading,
            systemPromptFileURL: systemPromptFile,
            workspaceConfigStamp: request.workspaceConfigStamp,
            providerID: request.providerID,
            modelID: request.modelID
        )
        daemon.currentThinkingLevel = Self.normalizedPiThinkingLevel(request.thinkingLevel)
        self.daemons[request.channel] = daemon
        
        let channel = request.channel
        let outHandle = daemon.stdoutHandle
        let errHandle = daemon.stderrHandle
        
        daemon.stderrTask = Task.detached(priority: .utility) { [weak self] in
            while true {
                guard let chunk = try? errHandle.read(upToCount: 4096), !chunk.isEmpty else { break }
                if let text = String(data: chunk, encoding: .utf8), !text.isEmpty {
                    await self?.appendStderr(channel: channel, text: text)
                }
            }
        }
        
        daemon.stdoutTask = Task.detached(priority: .userInitiated) { [weak self] in
            var buffer = Data()
            while true {
                guard let chunk = try? outHandle.read(upToCount: 8192), !chunk.isEmpty else { break }
                buffer.append(chunk)
                while let nl = buffer.firstIndex(of: 0x0A) {
                    var lineData = buffer.subdata(in: 0..<nl)
                    buffer.removeSubrange(0...nl)
                    if lineData.last == 0x0D { lineData.removeLast() }
                    guard !lineData.isEmpty,
                          let obj = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any]
                    else { continue }
                    await self?.handleIncomingJSON(channel: channel, json: obj)
                }
            }
            await self?.handleDaemonEOF(channel: channel)
        }
        
        return daemon
    }
    
    
    private func terminateDaemon(channel: PiAgentChannel, reason: String) {
        if let daemon = self.daemons.removeValue(forKey: channel) {
            daemon.stdoutTask?.cancel()
            daemon.stderrTask?.cancel()
            try? daemon.stdinHandle.close()
            if daemon.process.isRunning {
                daemon.process.terminate()
            }
        }
        if self.activeTurns[channel] != nil {
            self.finishTurn(channel: channel, error: AIError.http(status: 502, message: reason))
        }
    }
    
    
    private func appendStderr(channel: PiAgentChannel, text: String) {
        guard let daemon = self.daemons[channel] else { return }
        daemon.stderrBuffer += text
        if daemon.stderrBuffer.count > 4000 {
            daemon.stderrBuffer = String(daemon.stderrBuffer.suffix(3000))
        }
    }
    
    
    private func handleDaemonEOF(channel: PiAgentChannel) {
        let stderrText = self.daemons[channel]?.stderrBuffer.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        self.daemons.removeValue(forKey: channel)
        if self.activeTurns[channel] != nil {
            let message = stderrText.isEmpty
                ? AppLanguage.text("Pi 内核进程意外退出", en: "Pi RPC process exited unexpectedly")
                : "Pi 内核退出：\(String(stderrText.prefix(240)))"
            self.finishTurn(channel: channel, error: AIError.http(status: 502, message: message))
        }
    }
    
    
    // MARK: - JSONL Command / Response Framing
    
    private func makeCommandID(prefix: String) -> String {
        let seq = self.nextCommandSeq
        self.nextCommandSeq += 1
        return "\(prefix)-\(seq)"
    }
    
    
    private func writeJSONLine(_ obj: [String: Any], to handle: FileHandle) throws {
        var data = try JSONSerialization.data(withJSONObject: obj, options: [])
        data.append(0x0A)
        try handle.write(contentsOf: data)
    }
    
    
    private func sendCommand(
        to daemon: ChannelDaemon,
        payload: [String: Any],
        timeoutSec: Double
    ) async throws -> [String: Any] {
        let id = self.makeCommandID(prefix: "cmd")
        var full = payload
        full["id"] = id
        
        return try await withCheckedThrowingContinuation { continuation in
            self.pendingResponses[id] = continuation
            do {
                try self.writeJSONLine(full, to: daemon.stdinHandle)
            } catch {
                self.pendingResponses.removeValue(forKey: id)
                continuation.resume(throwing: error)
                return
            }
            
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(timeoutSec))
                await self?.timeoutPendingResponse(id: id)
            }
        }
    }
    
    
    private func timeoutPendingResponse(id: String) {
        if let cont = self.pendingResponses.removeValue(forKey: id) {
            cont.resume(throwing: AIError.http(status: 504, message: "Pi RPC command timed out"))
        }
    }
    
    
    private func handleIncomingJSON(channel: PiAgentChannel, json: [String: Any]) {
        guard let eventType = json["type"] as? String else { return }
        
        if eventType == "response", let id = json["id"] as? String {
            if let cont = self.pendingResponses.removeValue(forKey: id) {
                cont.resume(returning: json)
                return
            }
            if let promptChannel = self.promptCommandChannels.removeValue(forKey: id) {
                if (json["success"] as? Bool) == false {
                    let err = (json["error"] as? String) ?? "Pi prompt rejected"
                    self.finishTurn(channel: promptChannel, error: AIError.http(status: 502, message: err))
                }
                return
            }
            return
        }
        
        guard var turn = self.activeTurns[channel] else { return }
        let onEvent = turn.onEvent
        
        switch eventType {
            case "message_start":
                if let message = json["message"] as? [String: Any],
                   (message["role"] as? String) == "assistant"
                {
                    turn.textBlocks = [:]
                    turn.thinkingBlocks = [:]
                    turn.thinkingStepID = nil
                    self.activeTurns[channel] = turn
                }
                
            case "message_update":
                if let assistantEvent = json["assistantMessageEvent"] as? [String: Any],
                   let subType = assistantEvent["type"] as? String
                {
                    let idx = assistantEvent["contentIndex"] as? Int ?? 0
                    switch subType {
                        case "thinking_start":
                            if turn.thinkingStepID == nil {
                                let stepID = "think-\(idx)"
                                turn.thinkingStepID = stepID
                                turn.steps.append(BeautifulAgentThinkingStep(
                                    id: stepID,
                                    label: AppLanguage.text("推理思考", en: "Reasoning"),
                                    chip: nil,
                                    status: "running",
                                    mono: false,
                                    detail: nil,
                                    durationMs: nil
                                ))
                            }
                            self.activeTurns[channel] = turn
                            Task { @MainActor in onEvent(.status(AppLanguage.text("正在推理…", en: "Reasoning..."))) }
                            
                        case "thinking_delta":
                            if let delta = assistantEvent["delta"] as? String, !delta.isEmpty {
                                turn.thinkingBlocks[idx, default: ""] += delta
                                let combinedThinking = turn.thinkingBlocks.keys.sorted().compactMap { turn.thinkingBlocks[$0] }.joined()
                                let previewLines = combinedThinking
                                    .components(separatedBy: .newlines)
                                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                                    .filter { !$0.isEmpty }
                                    .suffix(3)
                                    .map { String($0.prefix(140)) }
                                if let stepID = turn.thinkingStepID,
                                   let i = turn.steps.firstIndex(where: { $0.id == stepID })
                                {
                                    turn.steps[i].detail = previewLines.isEmpty ? nil : previewLines
                                } else {
                                    let stepID = "think-\(idx)"
                                    turn.thinkingStepID = stepID
                                    turn.steps.append(BeautifulAgentThinkingStep(
                                        id: stepID,
                                        label: AppLanguage.text("推理思考", en: "Reasoning"),
                                        chip: nil,
                                        status: "running",
                                        mono: false,
                                        detail: previewLines.isEmpty ? nil : previewLines,
                                        durationMs: nil
                                    ))
                                }
                                self.activeTurns[channel] = turn
                                Task { @MainActor in onEvent(.thinkingDelta(combinedThinking)) }
                            }
                            
                        case "thinking_end":
                            if let content = assistantEvent["content"] as? String, !content.isEmpty {
                                turn.thinkingBlocks[idx] = content
                            }
                            if let stepID = turn.thinkingStepID,
                               let i = turn.steps.firstIndex(where: { $0.id == stepID })
                            {
                                turn.steps[i].status = "done"
                            }
                            let fullThinking = turn.thinkingBlocks.keys.sorted().compactMap { turn.thinkingBlocks[$0] }.joined()
                            self.activeTurns[channel] = turn
                            Task { @MainActor in onEvent(.thinkingEnd(fullThinking)) }
                            
                        case "text_delta":
                            if let delta = assistantEvent["delta"] as? String, !delta.isEmpty {
                                turn.textBlocks[idx, default: ""] += delta
                                let joined = turn.textBlocks.keys.sorted().compactMap { turn.textBlocks[$0] }.joined()
                                let now = ProcessInfo.processInfo.systemUptime
                                let shouldEmit = (now - turn.lastTextEmitUptime) >= 0.025
                                if shouldEmit {
                                    turn.lastTextEmitUptime = now
                                }
                                self.activeTurns[channel] = turn
                                if shouldEmit {
                                    Task { @MainActor in onEvent(.textDelta(joined)) }
                                }
                            }
                            
                        case "text_end":
                            if let content = assistantEvent["content"] as? String {
                                turn.textBlocks[idx] = content
                            }
                            let joined = turn.textBlocks.keys.sorted().compactMap { turn.textBlocks[$0] }.joined()
                            self.activeTurns[channel] = turn
                            Task { @MainActor in onEvent(.textEnd(joined)) }
                            
                        case "error":
                            if let errStr = assistantEvent["error"] as? String, !errStr.isEmpty {
                                turn.errorMessage = errStr
                            } else if let errObj = assistantEvent["error"] as? [String: Any],
                                      let errMsg = errObj["errorMessage"] as? String, !errMsg.isEmpty
                            {
                                turn.errorMessage = errMsg
                            }
                            self.activeTurns[channel] = turn
                            if let msg = turn.errorMessage {
                                Task { @MainActor in onEvent(.error(msg)) }
                            }
                            
                        default:
                            break
                    }
                }
                
            case "tool_execution_start":
                let toolCallID = (json["toolCallId"] as? String) ?? UUID().uuidString
                let toolName = (json["toolName"] as? String) ?? "tool"
                let args = json["args"] as? [String: Any]
                let label = PiToolDisplayMeta.label(for: toolName)
                let detail = PiToolDisplayMeta.summarizeArgs(toolName, args: args)
                
                // Mark running thinking step done once tool begins
                if let thinkID = turn.thinkingStepID,
                   let idx = turn.steps.firstIndex(where: { $0.id == thinkID && $0.status == "running" })
                {
                    turn.steps[idx].status = "done"
                }
                
                if !turn.toolNames.contains(toolName) {
                    turn.toolNames.append(toolName)
                }
                turn.steps.append(BeautifulAgentThinkingStep(
                    id: toolCallID,
                    label: label,
                    chip: detail ?? toolName,
                    status: "running",
                    mono: ["bash", "grep", "read", "edit", "write"].contains(toolName),
                    detail: nil,
                    durationMs: nil
                ))
                self.activeTurns[channel] = turn
                Task { @MainActor in
                    onEvent(.toolStart(id: toolCallID, name: toolName, label: label, detail: detail))
                }
                
            case "tool_execution_update":
                let toolCallID = (json["toolCallId"] as? String) ?? ""
                if let preview = PiToolDisplayMeta.extractToolOutputText(from: json["partialResult"]),
                   let idx = turn.steps.firstIndex(where: { $0.id == toolCallID })
                {
                    let lines = Array(preview.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.prefix(4))
                    turn.steps[idx].detail = lines.isEmpty ? nil : lines
                    self.activeTurns[channel] = turn
                    Task { @MainActor in onEvent(.toolUpdate(id: toolCallID, outputPreview: preview)) }
                }
                
            case "tool_execution_end":
                let toolCallID = (json["toolCallId"] as? String) ?? ""
                let toolName = (json["toolName"] as? String) ?? ""
                let isError = (json["isError"] as? Bool) == true
                let durationMs = json["durationMs"] as? Int
                let preview = PiToolDisplayMeta.extractToolOutputText(from: json["result"])
                if let idx = turn.steps.firstIndex(where: { $0.id == toolCallID }) {
                    turn.steps[idx].status = isError ? "error" : "done"
                    turn.steps[idx].durationMs = durationMs
                    if let preview {
                        let lines = Array(preview.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.prefix(4))
                        turn.steps[idx].detail = lines.isEmpty ? nil : lines
                    }
                }
                self.activeTurns[channel] = turn
                Task { @MainActor in
                    onEvent(.toolEnd(id: toolCallID, name: toolName, isError: isError, durationMs: durationMs, outputPreview: preview))
                    if toolName == "editor_action" {
                        await CotAgentCoordinator.shared.drainCommandQueueNow()
                    }
                }
                
            case "message_end":
                if let message = json["message"] as? [String: Any],
                   (message["role"] as? String) == "assistant"
                {
                    if let errMsg = message["errorMessage"] as? String, !errMsg.isEmpty {
                        turn.errorMessage = errMsg
                    }
                    if let stopReason = message["stopReason"] as? String, stopReason == "aborted" {
                        turn.aborted = true
                    }
                    if let blocks = message["content"] as? [[String: Any]] {
                        let textJoined = blocks.compactMap { block -> String? in
                            guard (block["type"] as? String) == "text" else { return nil }
                            return block["text"] as? String
                        }.joined()
                        if !textJoined.isEmpty {
                            turn.finalAssistantText = textJoined
                        }
                    }
                    self.activeTurns[channel] = turn
                }
                
            case "auto_retry_end":
                if (json["success"] as? Bool) == false,
                   let finalErr = json["finalError"] as? String, !finalErr.isEmpty
                {
                    turn.errorMessage = finalErr
                    self.activeTurns[channel] = turn
                }
                
            case "agent_settled":
                self.completeTurnNormally(channel: channel)
                
            default:
                break
        }
    }
    
    
    private func completeTurnNormally(channel: PiAgentChannel) {
        guard let turn = self.activeTurns.removeValue(forKey: channel) else { return }
        self.daemons[channel]?.isRunningTurn = false
        
        let streamedText = turn.textBlocks.keys.sorted().compactMap { turn.textBlocks[$0] }.joined()
        let finalText = (turn.finalAssistantText ?? streamedText).trimmingCharacters(in: .whitespacesAndNewlines)
        let fullThinking = turn.thinkingBlocks.keys.sorted().compactMap { turn.thinkingBlocks[$0] }.joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let elapsedMs = max(1, Int(Date().timeIntervalSince(turn.startedAt) * 1000))
        
        var finalSteps = turn.steps
        for i in finalSteps.indices where finalSteps[i].status == "running" {
            finalSteps[i].status = turn.aborted ? "error" : "done"
        }
        
        let onEvent = turn.onEvent
        Task { @MainActor in onEvent(.settled) }
        
        if !finalText.isEmpty || turn.aborted {
            turn.continuation.resume(returning: PiAgentRunResult(
                text: finalText,
                thinking: fullThinking,
                thinkingDurationMs: elapsedMs,
                steps: finalSteps,
                toolNames: turn.toolNames,
                aborted: turn.aborted
            ))
            return
        }
        if let err = turn.errorMessage, !err.isEmpty {
            turn.continuation.resume(throwing: AIError.http(status: 502, message: err))
            return
        }
        turn.continuation.resume(throwing: AIError.emptyResponse)
    }
    
    
    private func finishTurn(channel: PiAgentChannel, error: any Error) {
        guard let turn = self.activeTurns.removeValue(forKey: channel) else { return }
        self.daemons[channel]?.isRunningTurn = false
        turn.continuation.resume(throwing: error)
    }
    
    
    private static func normalizedPiThinkingLevel(_ raw: String?) -> String? {
        guard let raw else { return nil }
        switch raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "none", "off": return "off"
            case "minimal": return "minimal"
            case "low": return "low"
            case "medium": return "medium"
            case "high": return "high"
            default: return nil
        }
    }
}


/// Native Swift data-lookup helper used when Pi kernel is unavailable or falls back to direct HTTP SSE.
/// Ensures Butler still fetches real stock quotes & cached news instead of hallucinating empty promises.
@MainActor
enum CotSwiftToolFallback {
    
    struct EnrichedContext {
        var injectedDataBlock: String
        var steps: [BeautifulAgentThinkingStep]
    }
    
    static func enrichIfNeeded(for userText: String) async -> EnrichedContext {
        let lower = userText.lowercased()
        var blocks: [String] = []
        var steps: [BeautifulAgentThinkingStep] = []
        
        // Detect stock/market inquiry and resolve live quote directly via CotMarketService
        let marketKeywords = [
            "股票", "股价", "行情", "看盘", "k线", "涨跌", "市值", "啥情况", "怎么样", "多少钱", "走势", "光电", "科技", "控股", "茅台", "宁德", "英伟达", "nvda", "aapl", "tsla", "hstech", "恒生",
        ]
        if marketKeywords.contains(where: { lower.contains($0) }) {
            let candidates = Self.extractStockCandidates(from: userText)
            for candidate in candidates.prefix(2) {
                if let inst = await CotMarketService.shared.resolveInstrument(for: candidate),
                   let snap = await CotMarketService.shared.refresh(instrument: inst, period: .day, isBackgroundWatchlistRefresh: true)
                {
                    let cur = inst.market.currencyPrefix
                    let sign = snap.changeAmount >= 0 ? "+" : ""
                    let summary = """
                    标的：\(inst.name) (\(inst.namespace.displayName):\(inst.symbol))
                    最新价：\(cur)\(String(format: "%.2f", snap.lastPrice))（\(sign)\(String(format: "%.2f", snap.changeAmount)) / \(sign)\(String(format: "%.2f", snap.changePercent))%）
                    昨收：\(cur)\(String(format: "%.2f", snap.previousClose)) | 今开：\(cur)\(String(format: "%.2f", snap.dayOpen)) | 最高：\(cur)\(String(format: "%.2f", snap.high)) | 最低：\(cur)\(String(format: "%.2f", snap.low))
                    """
                    blocks.append("[实时行情数据]\n\(summary)")
                    steps.append(BeautifulAgentThinkingStep(
                        id: "fallback-quote-\(inst.instrumentID)",
                        label: AppLanguage.text("查询实时行情", en: "Lookup Stock Quote"),
                        chip: "\(inst.name) (\(inst.symbol))",
                        status: "done",
                        mono: false,
                        detail: Array(summary.components(separatedBy: .newlines).prefix(3)),
                        durationMs: nil
                    ))
                    break
                }
            }
        }
        
        // Detect news inquiry and attach cached headlines
        let newsKeywords = ["新闻", "资讯", "热点", "头条", "最新消息", "发生了什么", "news"]
        if newsKeywords.contains(where: { lower.contains($0) }) {
            let items = AIHotNewsService.shared.items.prefix(8)
            if !items.isEmpty {
                let list = items.map { item -> String in
                    let sum = (item.summary ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    let tail = sum.isEmpty ? "" : " — \(sum.prefix(120))"
                    return "- [\(item.resolvedCategory.label)] \(item.title)\(tail)"
                }.joined(separator: "\n")
                blocks.append("[本地最新资讯缓存]\n\(list)")
                steps.append(BeautifulAgentThinkingStep(
                    id: "fallback-news",
                    label: AppLanguage.text("检索资讯热点", en: "Search News"),
                    chip: "\(items.count) 条",
                    status: "done",
                    mono: false,
                    detail: items.prefix(3).map(\.title),
                    durationMs: nil
                ))
            }
        }
        
        return EnrichedContext(injectedDataBlock: blocks.joined(separator: "\n\n"), steps: steps)
    }
    
    
    static func extractStockCandidates(from text: String) -> [String] {
        var candidates: [String] = []
        let ns = text as NSString
        
        // 1. 6-digit A-share / 5-digit HK codes or uppercase tickers (2-6 chars)
        let patterns = [
            #"\b\d{5,6}\b"#,
            #"\b[A-Z]{2,6}\b"#,
        ]
        for pat in patterns {
            if let regex = try? NSRegularExpression(pattern: pat) {
                for match in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
                    let token = ns.substring(with: match.range)
                    if !["AI", "API", "NEWS", "RSS", "CEO", "CFO", "IPO", "ETF", "USD", "CNY", "HKD"].contains(token) {
                        candidates.append(token)
                    }
                }
            }
        }
        
        // 2. Strip common Chinese conversational filler to isolate company name (e.g. "帮我看看现在三安光电啥情况" -> "三安光电")
        var cleaned = text
        let fillers = [
            "帮我看看", "帮我查查", "帮我查一下", "帮我看下", "帮我查下", "帮忙看看", "请帮我", "帮我", "请问",
            "查一下", "看一下", "看下", "查下", "看看", "查查", "现在", "目前", "今天", "今日", "近期", "最近",
            "啥情况", "什么情况", "怎么样了", "怎么样", "咋样", "如何", "股价", "行情", "股票", "走势", "价格",
            "多少钱", "多少", "的表现", "表现", "的", "吧", "呢", "啊", "吗", "？", "?", "。", "！", "!", "，", ",",
        ]
        for f in fillers {
            cleaned = cleaned.replacingOccurrences(of: f, with: " ")
        }
        for part in cleaned.split(whereSeparator: { $0.isWhitespace }) {
            let s = String(part).trimmingCharacters(in: .whitespacesAndNewlines)
            if s.count >= 2 && s.count <= 12 && !candidates.contains(s) {
                candidates.append(s)
            }
        }
        return candidates
    }
}
