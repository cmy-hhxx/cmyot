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

import Darwin
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
    case thinkingStart(startedAtMs: Double)
    case thinkingDelta(String)
    case thinkingEnd(String, durationMs: Int?)
    case toolStart(id: String, name: String, label: String, detail: String?, startedAtMs: Double)
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
/// enforces strict per-tool and per-turn timeouts with automatic wedged-daemon recycling,
/// responds instantly to Swift Task cancellation, and immediately drains CotEditor's SQLite action
/// queue whenever `editor_action` completes.
actor PiRPCRuntime {
    
    /// Configurable timeouts governing prompt acknowledgement, per-tool execution, idle stalls, and overall turn cap.
    nonisolated struct TimeoutPolicy: Sendable {
        var promptAckSeconds: Double = 12.0
        var cotToolTimeoutSeconds: Double = 25.0
        var workspaceToolTimeoutSeconds: Double = 45.0
        var idleTurnTimeoutSeconds: Double = 55.0
        var maxTurnDurationSeconds: Double = 180.0
        var abortGraceMilliseconds: Int = 600
        
        static let `default` = TimeoutPolicy()
    }
    
    static let shared = PiRPCRuntime()
    
    private static let fastCotToolNames: Set<String> = [
        "lookup_stock_quote", "search_news", "web_search", "web_fetch",
        "get_workspace_context", "search_documents", "read_document", "read_memory", "editor_action",
    ]
    
    private final class ChannelDaemon: @unchecked Sendable {
        let id = UUID()
        let channel: PiAgentChannel
        let process: Process
        let stdinHandle: FileHandle
        let stdoutHandle: FileHandle
        let stderrHandle: FileHandle
        let systemPromptFileURL: URL
        let workingDirectoryURL: URL
        let workspaceConfigStamp: String
        var currentProviderID: String
        var currentModelID: String
        var currentThinkingLevel: String?
        var activeLogicalSessionKey: String?
        var isRunningTurn: Bool = false
        var stdoutTask: Task<Void, Never>?
        var stderrTask: Task<Void, Never>?
        var finishStreams: (@Sendable () -> Void)?
        var stderrBuffer: String = ""
        
        init(
            channel: PiAgentChannel,
            process: Process,
            stdinHandle: FileHandle,
            stdoutHandle: FileHandle,
            stderrHandle: FileHandle,
            systemPromptFileURL: URL,
            workingDirectoryURL: URL,
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
            self.workingDirectoryURL = workingDirectoryURL
            self.workspaceConfigStamp = workspaceConfigStamp
            self.currentProviderID = providerID
            self.currentModelID = modelID
        }
    }
    
    private struct PendingResponseEntry {
        let channel: PiAgentChannel
        let daemonID: UUID
        let continuation: CheckedContinuation<[String: Any], Error>
        var timeoutTask: Task<Void, Never>?
    }
    
    private struct ActiveTurn {
        let id = UUID()
        let daemonID: UUID
        let logicalSessionKey: String
        let continuation: CheckedContinuation<PiAgentRunResult, Error>
        let onEvent: @MainActor @Sendable (PiAgentStreamEvent) -> Void
        let startedAt: Date
        var lastActivityUptime: TimeInterval
        var promptAcked: Bool = false
        var textBlocks: [Int: String] = [:]
        var thinkingBlocks: [Int: String] = [:]
        var finalAssistantText: String?
        var steps: [BeautifulAgentThinkingStep] = []
        var toolNames: [String] = []
        var errorMessage: String?
        var aborted: Bool = false
        var thinkingStepID: String?
        var thinkingStartedAt: Date?
        var firstAnswerTextAt: Date?
        var toolStartedAt: [String: Date] = [:]
        var toolTimeoutTasks: [String: Task<Void, Never>] = [:]
        var promptAckTask: Task<Void, Never>?
        var turnWatchdogTask: Task<Void, Never>?
        var settleFallbackTask: Task<Void, Never>?
        var lastTextEmitUptime: TimeInterval = 0
        
        mutating func cancelAllWatchdogs() {
            self.promptAckTask?.cancel()
            self.promptAckTask = nil
            self.turnWatchdogTask?.cancel()
            self.turnWatchdogTask = nil
            self.settleFallbackTask?.cancel()
            self.settleFallbackTask = nil
            for task in self.toolTimeoutTasks.values {
                task.cancel()
            }
            self.toolTimeoutTasks.removeAll()
        }
    }
    
    private let timeoutPolicy: TimeoutPolicy
    private var daemons: [PiAgentChannel: ChannelDaemon] = [:]
    private var pendingResponses: [String: PendingResponseEntry] = [:]
    private var promptCommandChannels: [String: (channel: PiAgentChannel, turnID: UUID, daemonID: UUID)] = [:]
    private var activeTurns: [PiAgentChannel: ActiveTurn] = [:]
    private var nextCommandSeq: Int = 1
    
    
    init(timeoutPolicy: TimeoutPolicy = .default) {
        self.timeoutPolicy = timeoutPolicy
    }
    
    
    // MARK: - Public Control
    
    func runTurn(
        _ request: PiRPCTurnRequest,
        onEvent: @escaping @MainActor @Sendable (PiAgentStreamEvent) -> Void
    ) async throws -> PiAgentRunResult {
        try Task.checkCancellation()
        
        // 1. Force-clear any previous stuck or in-flight turn on this channel without leaking its continuation
        if let priorTurn = self.activeTurns[request.channel] {
            self.cancelActiveTurn(channel: request.channel, turnID: priorTurn.id, sendAbort: true)
        }
        if let existingDaemon = self.daemons[request.channel], existingDaemon.isRunningTurn {
            let settled = await self.waitForDaemonIdle(
                channel: request.channel,
                daemonID: existingDaemon.id,
                maxWaitMs: self.timeoutPolicy.abortGraceMilliseconds
            )
            if !settled {
                self.terminateDaemon(
                    channel: request.channel,
                    expectedDaemonID: existingDaemon.id,
                    reason: AppLanguage.text("上一次工具执行未及时退出，已自动重启内核", en: "Previous run wedged; recycled Pi daemon")
                )
            }
        }
        
        try Task.checkCancellation()
        
        var daemon = try self.ensureDaemon(for: request)
        
        // Write fresh per-turn dynamic system prompt read by `cot-tools.ts`'s `before_agent_start` hook
        try Data(request.systemPrompt.utf8).write(to: daemon.systemPromptFileURL, options: .atomic)
        
        // Switch logical session if user switched chat thread or NEWS article
        var effectivePrompt = request.userPrompt
        let needsSessionReset = daemon.activeLogicalSessionKey != request.logicalSessionKey
        if needsSessionReset {
            if daemon.activeLogicalSessionKey != nil {
                do {
                    _ = try await self.sendCommand(to: daemon, payload: ["type": "new_session"], timeoutSec: 5)
                } catch {
                    // If warm daemon refuses or stalls on `new_session`, recycle cleanly rather than hanging
                    self.terminateDaemon(
                        channel: request.channel,
                        expectedDaemonID: daemon.id,
                        reason: AppLanguage.text("切换会话超时，正在重启 Pi 内核", en: "Session reset timed out; restarting Pi daemon")
                    )
                    daemon = try self.ensureDaemon(for: request)
                    try Data(request.systemPrompt.utf8).write(to: daemon.systemPromptFileURL, options: .atomic)
                }
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
        
        // Sync model & thinking level on warm daemon; recycle if model catalog refreshed or `set_model` fails
        if daemon.currentProviderID != request.providerID || daemon.currentModelID != request.modelID {
            let modelSwitched: Bool
            do {
                let resp = try await self.sendCommand(
                    to: daemon,
                    payload: [
                        "type": "set_model",
                        "provider": request.providerID,
                        "modelId": request.modelID,
                    ],
                    timeoutSec: 6
                )
                modelSwitched = (resp["success"] as? Bool) == true
            } catch {
                modelSwitched = false
            }
            if modelSwitched {
                daemon.currentProviderID = request.providerID
                daemon.currentModelID = request.modelID
            } else {
                self.terminateDaemon(
                    channel: request.channel,
                    expectedDaemonID: daemon.id,
                    reason: AppLanguage.text("模型切换需要刷新 Pi 内核", en: "Restarting Pi daemon for model switch")
                )
                daemon = try self.ensureDaemon(for: request)
                try Data(request.systemPrompt.utf8).write(to: daemon.systemPromptFileURL, options: .atomic)
                daemon.activeLogicalSessionKey = request.logicalSessionKey
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
                timeoutSec: 4
            )
            daemon.currentThinkingLevel = desiredThinking
        }
        
        try Task.checkCancellation()
        
        daemon.isRunningTurn = true
        let promptCommandID = self.makeCommandID(prefix: request.channel.rawValue)
        let activeDaemon = daemon
        let channel = request.channel
        let turnBox = TurnIDBox()
        
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                var turn = ActiveTurn(
                    daemonID: activeDaemon.id,
                    logicalSessionKey: request.logicalSessionKey,
                    continuation: continuation,
                    onEvent: onEvent,
                    startedAt: Date(),
                    lastActivityUptime: ProcessInfo.processInfo.systemUptime
                )
                let turnID = turn.id
                turnBox.set(turnID)
                
                // Guard against pre-cancelled tasks entering the continuation
                if Task.isCancelled {
                    activeDaemon.isRunningTurn = false
                    continuation.resume(throwing: CancellationError())
                    return
                }
                
                // Prompt-ack watchdog: if Pi never acknowledges `prompt`, recycle wedged daemon
                let ackSec = self.timeoutPolicy.promptAckSeconds
                turn.promptAckTask = Task { [weak self] in
                    try? await Task.sleep(for: .seconds(ackSec))
                    guard !Task.isCancelled else { return }
                    await self?.handlePromptAckTimeout(channel: channel, turnID: turnID, daemonID: activeDaemon.id)
                }
                
                // Turn idle & overall duration watchdog
                let idleSec = self.timeoutPolicy.idleTurnTimeoutSeconds
                let maxTurnSec = self.timeoutPolicy.maxTurnDurationSeconds
                turn.turnWatchdogTask = Task { [weak self] in
                    while !Task.isCancelled {
                        try? await Task.sleep(for: .seconds(2))
                        guard !Task.isCancelled else { return }
                        let shouldContinue = await self?.checkTurnWatchdog(
                            channel: channel,
                            turnID: turnID,
                            daemonID: activeDaemon.id,
                            idleTimeoutSec: idleSec,
                            maxTurnSec: maxTurnSec
                        ) ?? false
                        if !shouldContinue { return }
                    }
                }
                
                self.activeTurns[channel] = turn
                self.promptCommandChannels[promptCommandID] = (channel: channel, turnID: turnID, daemonID: activeDaemon.id)
                
                let cmd: [String: Any] = [
                    "id": promptCommandID,
                    "type": "prompt",
                    "message": effectivePrompt,
                ]
                do {
                    try self.writeJSONLine(cmd, to: activeDaemon.stdinHandle)
                } catch {
                    self.promptCommandChannels.removeValue(forKey: promptCommandID)
                    self.finishTurn(channel: channel, expectedTurnID: turnID, error: error)
                    return
                }
            }
        } onCancel: {
            Task { [weak self] in
                await self?.cancelActiveTurn(channel: channel, turnID: turnBox.get(), sendAbort: true)
            }
        }
    }
    
    
    func abort(channel: PiAgentChannel) async {
        if let active = self.activeTurns[channel] {
            self.cancelActiveTurn(channel: channel, turnID: active.id, sendAbort: true)
            return
        }
        guard let daemon = self.daemons[channel], daemon.process.isRunning else { return }
        self.sendAbortPacket(to: daemon)
    }
    
    
    func resetSession(channel: PiAgentChannel, forceAbort: Bool = true) async {
        if forceAbort, let active = self.activeTurns[channel] {
            self.cancelActiveTurn(channel: channel, turnID: active.id, sendAbort: true)
        }
        guard let daemon = self.daemons[channel] else { return }
        daemon.activeLogicalSessionKey = nil
        
        guard daemon.process.isRunning else {
            self.daemons.removeValue(forKey: channel)
            return
        }
        if daemon.isRunningTurn {
            let settled = await self.waitForDaemonIdle(
                channel: channel,
                daemonID: daemon.id,
                maxWaitMs: self.timeoutPolicy.abortGraceMilliseconds
            )
            if !settled {
                self.terminateDaemon(
                    channel: channel,
                    expectedDaemonID: daemon.id,
                    reason: AppLanguage.text("已重置会话并重启 Pi 内核", en: "Reset session and recycled Pi daemon")
                )
                return
            }
        }
        do {
            _ = try await self.sendCommand(to: daemon, payload: ["type": "new_session"], timeoutSec: 3.5)
        } catch {
            self.terminateDaemon(
                channel: channel,
                expectedDaemonID: daemon.id,
                reason: AppLanguage.text("新建会话超时，已重置 Pi 内核", en: "New session timed out; recycled Pi daemon")
            )
        }
    }
    
    
    func shutdownAll() {
        for channel in Array(self.daemons.keys) {
            self.terminateDaemon(channel: channel, expectedDaemonID: nil, reason: "Pi 内核已关闭")
        }
    }
    
    
    /// Pure helper safely parsing Pi's `durationMs` (Int or Double) and falling back to Swift wall-clock measurement.
    nonisolated static func resolvedToolDurationMs(
        rawDurationValue: Any?,
        startedAt: Date?,
        now: Date = Date()
    ) -> Int? {
        if let num = rawDurationValue as? NSNumber {
            let rounded = Int(num.doubleValue.rounded())
            if rounded > 0 {
                return rounded
            }
        } else if let intVal = rawDurationValue as? Int, intVal > 0 {
            return intVal
        } else if let dblVal = rawDurationValue as? Double, dblVal.isFinite, dblVal > 0 {
            return max(1, Int(dblVal.rounded()))
        }
        if let startedAt {
            let wallMs = Int((now.timeIntervalSince(startedAt) * 1000.0).rounded())
            return max(1, wallMs)
        }
        return nil
    }
    
    
    /// Resolves a safe non-root working directory for Pi so built-in `find`/`grep`/`bash` never scan `/`.
    nonisolated static func safeWorkingDirectory(preferred: URL?, agentDirectoryURL: URL) -> URL {
        let fm = FileManager.default
        if let preferred {
            let path = preferred.standardizedFileURL.path(percentEncoded: false)
            if !path.isEmpty, path != "/", fm.fileExists(atPath: path) {
                return preferred.standardizedFileURL
            }
        }
        let fallback = agentDirectoryURL.appending(path: "workspace", directoryHint: .isDirectory)
        try? fm.createDirectory(at: fallback, withIntermediateDirectories: true)
        return fallback
    }
    
    
    // MARK: - Watchdogs & Cancellation
    
    private func cancelActiveTurn(channel: PiAgentChannel, turnID: UUID?, sendAbort: Bool) {
        if let current = self.activeTurns[channel],
           turnID == nil || current.id == turnID
        {
            var removed = self.activeTurns.removeValue(forKey: channel)!
            removed.cancelAllWatchdogs()
            removed.aborted = true
            self.clearPromptCommands(for: channel, turnID: removed.id)
            
            let daemon = self.daemons[channel]
            if sendAbort, let daemon, daemon.id == removed.daemonID, daemon.process.isRunning {
                self.sendAbortPacket(to: daemon)
                let targetDaemonID = daemon.id
                let graceMs = max(900, self.timeoutPolicy.abortGraceMilliseconds * 2)
                Task { [weak self] in
                    try? await Task.sleep(for: .milliseconds(graceMs))
                    await self?.recycleDaemonIfStillRunningTurn(channel: channel, daemonID: targetDaemonID)
                }
            }
            removed.continuation.resume(throwing: CancellationError())
        }
    }
    
    
    private func sendAbortPacket(to daemon: ChannelDaemon) {
        let cmd: [String: Any] = [
            "id": self.makeCommandID(prefix: "abort"),
            "type": "abort",
        ]
        try? self.writeJSONLine(cmd, to: daemon.stdinHandle)
    }
    
    
    private func waitForDaemonIdle(channel: PiAgentChannel, daemonID: UUID, maxWaitMs: Int) async -> Bool {
        let deadline = ProcessInfo.processInfo.systemUptime + Double(max(50, maxWaitMs)) / 1000.0
        while ProcessInfo.processInfo.systemUptime < deadline {
            guard let daemon = self.daemons[channel], daemon.id == daemonID else { return true }
            if !daemon.process.isRunning || !daemon.isRunningTurn {
                return true
            }
            try? await Task.sleep(for: .milliseconds(40))
        }
        guard let daemon = self.daemons[channel], daemon.id == daemonID else { return true }
        return !daemon.process.isRunning || !daemon.isRunningTurn
    }
    
    
    private func recycleDaemonIfStillRunningTurn(channel: PiAgentChannel, daemonID: UUID) {
        guard let daemon = self.daemons[channel], daemon.id == daemonID else { return }
        guard self.activeTurns[channel] == nil, daemon.isRunningTurn else { return }
        self.terminateDaemon(
            channel: channel,
            expectedDaemonID: daemonID,
            reason: AppLanguage.text("中断后后台进程未响应，已回收重启", en: "Recycled unresponsive Pi daemon after abort")
        )
    }
    
    
    private func handlePromptAckTimeout(channel: PiAgentChannel, turnID: UUID, daemonID: UUID) {
        guard let turn = self.activeTurns[channel], turn.id == turnID, !turn.promptAcked else { return }
        let stderrHint = self.daemons[channel]?.stderrBuffer.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let baseMsg = AppLanguage.text("Pi 内核响应超时，已自动重置连接", en: "Pi RPC prompt acknowledgement timed out")
        let msg = stderrHint.isEmpty ? baseMsg : "\(baseMsg) (\(String(stderrHint.prefix(200))))"
        self.terminateDaemon(channel: channel, expectedDaemonID: daemonID, reason: msg)
        self.finishTurn(channel: channel, expectedTurnID: turnID, error: AIError.http(status: 504, message: msg))
    }
    
    
    private func handleToolTimeout(channel: PiAgentChannel, turnID: UUID, toolCallID: String, toolName: String) {
        guard var turn = self.activeTurns[channel], turn.id == turnID else { return }
        guard let startedAt = turn.toolStartedAt.removeValue(forKey: toolCallID) else { return }
        turn.toolTimeoutTasks.removeValue(forKey: toolCallID)?.cancel()
        
        let elapsedMs = max(1, Int((Date().timeIntervalSince(startedAt) * 1000.0).rounded()))
        let timeoutDetail = AppLanguage.text("工具执行超时，已自动终止", en: "Tool timed out and was aborted")
        if let idx = turn.steps.firstIndex(where: { $0.id == toolCallID }) {
            turn.steps[idx].status = "error"
            turn.steps[idx].durationMs = elapsedMs
            turn.steps[idx].detail = [timeoutDetail]
        }
        let label = PiToolDisplayMeta.label(for: toolName)
        let msg = AppLanguage.text("工具「\(label)」执行超时，已自动中断并解除会话锁定", en: "Tool '\(label)' timed out and was aborted")
        turn.errorMessage = msg
        self.activeTurns[channel] = turn
        
        let onEvent = turn.onEvent
        Task { @MainActor in
            onEvent(.toolEnd(id: toolCallID, name: toolName, isError: true, durationMs: elapsedMs, outputPreview: timeoutDetail))
            onEvent(.error(msg))
        }
        
        // Abort & recycle wedged daemon so the channel is immediately ready for the next message
        self.terminateDaemon(channel: channel, expectedDaemonID: turn.daemonID, reason: msg)
        self.finishTurn(channel: channel, expectedTurnID: turnID, error: AIError.http(status: 504, message: msg))
    }
    
    
    private func checkTurnWatchdog(
        channel: PiAgentChannel,
        turnID: UUID,
        daemonID: UUID,
        idleTimeoutSec: Double,
        maxTurnSec: Double
    ) -> Bool {
        guard let turn = self.activeTurns[channel], turn.id == turnID else { return false }
        let nowUptime = ProcessInfo.processInfo.systemUptime
        let totalElapsed = Date().timeIntervalSince(turn.startedAt)
        
        if totalElapsed >= maxTurnSec {
            let msg = AppLanguage.text("本轮推理总耗时超过上限，已自动中止", en: "Turn exceeded maximum duration and was aborted")
            self.terminateDaemon(channel: channel, expectedDaemonID: daemonID, reason: msg)
            self.finishTurn(channel: channel, expectedTurnID: turnID, error: AIError.http(status: 504, message: msg))
            return false
        }
        
        // While a tool is running, the per-tool watchdog handles its timeout; otherwise enforce idle timeout
        if turn.toolStartedAt.isEmpty, (nowUptime - turn.lastActivityUptime) >= idleTimeoutSec {
            let msg = AppLanguage.text("模型长时间无响应，已自动释放会话", en: "Model stream stalled; released session")
            self.terminateDaemon(channel: channel, expectedDaemonID: daemonID, reason: msg)
            self.finishTurn(channel: channel, expectedTurnID: turnID, error: AIError.http(status: 504, message: msg))
            return false
        }
        return true
    }
    
    
    // MARK: - Daemon Lifecycle
    
    private func ensureDaemon(for request: PiRPCTurnRequest) throws -> ChannelDaemon {
        let safeCWD = Self.safeWorkingDirectory(
            preferred: request.workingDirectoryURL,
            agentDirectoryURL: request.agentDirectoryURL
        )
        if let existing = self.daemons[request.channel] {
            let sameCWD = existing.workingDirectoryURL.standardizedFileURL == safeCWD.standardizedFileURL
            if existing.process.isRunning && existing.workspaceConfigStamp == request.workspaceConfigStamp && sameCWD {
                return existing
            }
            self.terminateDaemon(
                channel: request.channel,
                expectedDaemonID: existing.id,
                reason: "配置或工作目录已更新，正在重启 Pi 内核"
            )
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
        process.currentDirectoryURL = safeCWD
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
            workingDirectoryURL: safeCWD,
            workspaceConfigStamp: request.workspaceConfigStamp,
            providerID: request.providerID,
            modelID: request.modelID
        )
        daemon.currentThinkingLevel = Self.normalizedPiThinkingLevel(request.thinkingLevel)
        self.daemons[request.channel] = daemon
        
        let channel = request.channel
        let daemonID = daemon.id
        let outHandle = daemon.stdoutHandle
        let errHandle = daemon.stderrHandle
        
        let (stdoutStream, stdoutContinuation) = AsyncStream<Data>.makeStream()
        let (stderrStream, stderrContinuation) = AsyncStream<Data>.makeStream()
        
        // Event-driven pipe streaming via `readabilityHandler` + `availableData`.
        // CRITICAL: Never use `FileHandle.read(upToCount: N)` on a persistent RPC pipe because
        // Foundation loops until N bytes OR EOF arrive, which permanently deadlocks short JSONL
        // responses (`prompt` ack, `new_session`, `set_model`, `agent_settled`) when stdout stays open.
        outHandle.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                stdoutContinuation.finish()
            } else {
                stdoutContinuation.yield(data)
            }
        }
        errHandle.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                stderrContinuation.finish()
            } else {
                stderrContinuation.yield(data)
            }
        }
        daemon.finishStreams = {
            outHandle.readabilityHandler = nil
            errHandle.readabilityHandler = nil
            stdoutContinuation.finish()
            stderrContinuation.finish()
        }
        
        daemon.stderrTask = Task.detached(priority: .utility) { [weak self] in
            for await chunk in stderrStream {
                if let text = String(data: chunk, encoding: .utf8), !text.isEmpty {
                    await self?.appendStderr(channel: channel, daemonID: daemonID, text: text)
                }
            }
        }
        
        daemon.stdoutTask = Task.detached(priority: .userInitiated) { [weak self] in
            var buffer = Data()
            for await chunk in stdoutStream {
                buffer.append(chunk)
                while let nl = buffer.firstIndex(of: 0x0A) {
                    var lineData = buffer.subdata(in: 0..<nl)
                    buffer.removeSubrange(0...nl)
                    if lineData.last == 0x0D { lineData.removeLast() }
                    guard !lineData.isEmpty,
                          let obj = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any]
                    else { continue }
                    await self?.handleIncomingJSON(channel: channel, daemonID: daemonID, json: obj)
                }
            }
            await self?.handleDaemonEOF(channel: channel, daemonID: daemonID)
        }
        
        return daemon
    }
    
    
    private func terminateDaemon(channel: PiAgentChannel, expectedDaemonID: UUID?, reason: String) {
        if let expectedDaemonID, let current = self.daemons[channel], current.id != expectedDaemonID {
            return
        }
        if let daemon = self.daemons.removeValue(forKey: channel) {
            daemon.finishStreams?()
            daemon.finishStreams = nil
            daemon.stdoutTask?.cancel()
            daemon.stderrTask?.cancel()
            try? daemon.stdinHandle.close()
            let proc = daemon.process
            if proc.isRunning {
                proc.terminate()
                let pid = proc.processIdentifier
                Task.detached(priority: .utility) {
                    try? await Task.sleep(for: .milliseconds(900))
                    if proc.isRunning && pid > 0 {
                        kill(pid, SIGKILL)
                    }
                }
            }
            self.failPendingResponses(for: channel, daemonID: daemon.id, reason: reason)
            self.clearPromptCommands(for: channel, daemonID: daemon.id)
            if let active = self.activeTurns[channel], active.daemonID == daemon.id {
                self.finishTurn(channel: channel, expectedTurnID: active.id, error: AIError.http(status: 502, message: reason))
            }
        } else if expectedDaemonID == nil, let active = self.activeTurns[channel] {
            self.finishTurn(channel: channel, expectedTurnID: active.id, error: AIError.http(status: 502, message: reason))
        }
    }
    
    
    private func appendStderr(channel: PiAgentChannel, daemonID: UUID, text: String) {
        guard let daemon = self.daemons[channel], daemon.id == daemonID else { return }
        daemon.stderrBuffer += text
        if daemon.stderrBuffer.count > 4000 {
            daemon.stderrBuffer = String(daemon.stderrBuffer.suffix(3000))
        }
    }
    
    
    private func handleDaemonEOF(channel: PiAgentChannel, daemonID: UUID) {
        guard let daemon = self.daemons[channel], daemon.id == daemonID else {
            // Late EOF from an already-replaced daemon — ignore so we never disrupt a fresh daemon!
            return
        }
        let stderrText = daemon.stderrBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
        self.daemons.removeValue(forKey: channel)
        let message = stderrText.isEmpty
            ? AppLanguage.text("Pi 内核进程意外退出", en: "Pi RPC process exited unexpectedly")
            : "Pi 内核退出：\(String(stderrText.prefix(240)))"
        self.failPendingResponses(for: channel, daemonID: daemonID, reason: message)
        self.clearPromptCommands(for: channel, daemonID: daemonID)
        if let active = self.activeTurns[channel], active.daemonID == daemonID {
            self.finishTurn(channel: channel, expectedTurnID: active.id, error: AIError.http(status: 502, message: message))
        }
    }
    
    
    private func failPendingResponses(for channel: PiAgentChannel, daemonID: UUID, reason: String) {
        let matchingKeys = self.pendingResponses.compactMap { key, entry -> String? in
            (entry.channel == channel && entry.daemonID == daemonID) ? key : nil
        }
        for key in matchingKeys {
            if let entry = self.pendingResponses.removeValue(forKey: key) {
                entry.timeoutTask?.cancel()
                entry.continuation.resume(throwing: AIError.http(status: 502, message: reason))
            }
        }
    }
    
    
    private func clearPromptCommands(for channel: PiAgentChannel, turnID: UUID? = nil, daemonID: UUID? = nil) {
        let keys = self.promptCommandChannels.compactMap { key, meta -> String? in
            guard meta.channel == channel else { return nil }
            if let turnID, meta.turnID != turnID { return nil }
            if let daemonID, meta.daemonID != daemonID { return nil }
            return key
        }
        for key in keys {
            self.promptCommandChannels.removeValue(forKey: key)
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
        let channel = daemon.channel
        let daemonID = daemon.id
        
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                if Task.isCancelled {
                    continuation.resume(throwing: CancellationError())
                    return
                }
                let timeoutTask = Task { [weak self] in
                    try? await Task.sleep(for: .seconds(timeoutSec))
                    guard !Task.isCancelled else { return }
                    await self?.timeoutPendingResponse(id: id)
                }
                self.pendingResponses[id] = PendingResponseEntry(
                    channel: channel,
                    daemonID: daemonID,
                    continuation: continuation,
                    timeoutTask: timeoutTask
                )
                do {
                    try self.writeJSONLine(full, to: daemon.stdinHandle)
                } catch {
                    if let removed = self.pendingResponses.removeValue(forKey: id) {
                        removed.timeoutTask?.cancel()
                        removed.continuation.resume(throwing: error)
                    }
                    return
                }
            }
        } onCancel: {
            Task { [weak self] in
                await self?.cancelPendingResponse(id: id)
            }
        }
    }
    
    
    private func timeoutPendingResponse(id: String) {
        if let entry = self.pendingResponses.removeValue(forKey: id) {
            entry.timeoutTask?.cancel()
            entry.continuation.resume(throwing: AIError.http(status: 504, message: "Pi RPC command timed out"))
        }
    }
    
    
    private func cancelPendingResponse(id: String) {
        if let entry = self.pendingResponses.removeValue(forKey: id) {
            entry.timeoutTask?.cancel()
            entry.continuation.resume(throwing: CancellationError())
        }
    }
    
    
    private func handleIncomingJSON(channel: PiAgentChannel, daemonID: UUID, json: [String: Any]) {
        guard let daemon = self.daemons[channel], daemon.id == daemonID else { return }
        guard let eventType = json["type"] as? String else { return }
        
        // Auto-cancel headless extension UI dialog prompts so Pi never blocks waiting for TUI confirmation
        if eventType == "extension_ui_request",
           let reqID = json["id"] as? String,
           let method = json["method"] as? String,
           ["select", "confirm", "input", "editor"].contains(method)
        {
            let reply: [String: Any] = [
                "type": "extension_ui_response",
                "id": reqID,
                "cancelled": true,
            ]
            try? self.writeJSONLine(reply, to: daemon.stdinHandle)
            return
        }
        
        if eventType == "response", let id = json["id"] as? String {
            if let entry = self.pendingResponses.removeValue(forKey: id) {
                entry.timeoutTask?.cancel()
                entry.continuation.resume(returning: json)
                return
            }
            if let promptMeta = self.promptCommandChannels.removeValue(forKey: id) {
                if var turn = self.activeTurns[promptMeta.channel], turn.id == promptMeta.turnID {
                    turn.promptAcked = true
                    turn.promptAckTask?.cancel()
                    turn.promptAckTask = nil
                    turn.lastActivityUptime = ProcessInfo.processInfo.systemUptime
                    self.activeTurns[promptMeta.channel] = turn
                    
                    if (json["success"] as? Bool) == false {
                        let err = (json["error"] as? String) ?? "Pi prompt rejected"
                        self.finishTurn(channel: promptMeta.channel, expectedTurnID: promptMeta.turnID, error: AIError.http(status: 502, message: err))
                        return
                    }
                    let disposition = ((json["data"] as? [String: Any])?["disposition"] as? String)
                        ?? (json["disposition"] as? String)
                    if disposition == "handled" {
                        self.completeTurnNormally(channel: promptMeta.channel, expectedTurnID: promptMeta.turnID, allowEmptyText: true)
                        return
                    }
                }
                return
            }
            return
        }
        
        // Even if the Swift caller already cancelled/released the turn, keep `daemon.isRunningTurn` accurate on settle
        if eventType == "agent_settled" {
            daemon.isRunningTurn = false
        }
        
        guard var turn = self.activeTurns[channel], turn.daemonID == daemonID else { return }
        turn.lastActivityUptime = ProcessInfo.processInfo.systemUptime
        let onEvent = turn.onEvent
        let turnID = turn.id
        
        func closeActiveThinkingStepIfNeeded(now: Date = Date()) -> Int? {
            guard let thinkID = turn.thinkingStepID,
                  let idx = turn.steps.firstIndex(where: { $0.id == thinkID && $0.status == "running" })
            else { return nil }
            let durMs = turn.thinkingStartedAt.map { max(1, Int((now.timeIntervalSince($0) * 1000.0).rounded())) }
            turn.steps[idx].status = "done"
            if let durMs {
                turn.steps[idx].durationMs = durMs
            }
            turn.thinkingStartedAt = nil
            return durMs
        }
        
        switch eventType {
            case "message_start":
                if let message = json["message"] as? [String: Any],
                   (message["role"] as? String) == "assistant"
                {
                    turn.textBlocks = [:]
                    turn.thinkingBlocks = [:]
                    turn.thinkingStepID = nil
                    turn.thinkingStartedAt = nil
                    self.activeTurns[channel] = turn
                }
                
            case "message_update":
                if let assistantEvent = json["assistantMessageEvent"] as? [String: Any],
                   let subType = assistantEvent["type"] as? String
                {
                    let idx = assistantEvent["contentIndex"] as? Int ?? 0
                    switch subType {
                        case "thinking_start":
                            let now = Date()
                            let startedMs = now.timeIntervalSince1970 * 1000.0
                            if turn.thinkingStepID == nil {
                                let stepID = "think-\(turn.steps.count)-\(idx)"
                                turn.thinkingStepID = stepID
                                turn.thinkingStartedAt = now
                                turn.steps.append(BeautifulAgentThinkingStep(
                                    id: stepID,
                                    label: AppLanguage.text("推理思考", en: "Reasoning"),
                                    chip: nil,
                                    status: "running",
                                    mono: false,
                                    detail: nil,
                                    durationMs: nil,
                                    kind: "thinking",
                                    startedAtMs: startedMs
                                ))
                            }
                            self.activeTurns[channel] = turn
                            Task { @MainActor in
                                onEvent(.thinkingStart(startedAtMs: startedMs))
                                onEvent(.status(AppLanguage.text("正在推理…", en: "Reasoning...")))
                            }
                            
                        case "thinking_delta":
                            if let delta = assistantEvent["delta"] as? String, !delta.isEmpty {
                                let now = Date()
                                turn.thinkingBlocks[idx, default: ""] += delta
                                let combinedThinking = turn.thinkingBlocks.keys.sorted().compactMap { turn.thinkingBlocks[$0] }.joined()
                                let previewLines = combinedThinking
                                    .components(separatedBy: .newlines)
                                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                                    .filter { !$0.isEmpty }
                                    .suffix(3)
                                    .map { String($0.prefix(140)) }
                                var emittedStartMs: Double?
                                if let stepID = turn.thinkingStepID,
                                   let i = turn.steps.firstIndex(where: { $0.id == stepID })
                                {
                                    turn.steps[i].detail = previewLines.isEmpty ? nil : previewLines
                                } else {
                                    let stepID = "think-\(turn.steps.count)-\(idx)"
                                    let startedMs = now.timeIntervalSince1970 * 1000.0
                                    emittedStartMs = startedMs
                                    turn.thinkingStepID = stepID
                                    turn.thinkingStartedAt = now
                                    turn.steps.append(BeautifulAgentThinkingStep(
                                        id: stepID,
                                        label: AppLanguage.text("推理思考", en: "Reasoning"),
                                        chip: nil,
                                        status: "running",
                                        mono: false,
                                        detail: previewLines.isEmpty ? nil : previewLines,
                                        durationMs: nil,
                                        kind: "thinking",
                                        startedAtMs: startedMs
                                    ))
                                }
                                self.activeTurns[channel] = turn
                                Task { @MainActor in
                                    if let emittedStartMs {
                                        onEvent(.thinkingStart(startedAtMs: emittedStartMs))
                                    }
                                    onEvent(.thinkingDelta(combinedThinking))
                                }
                            }
                            
                        case "thinking_end":
                            if let content = assistantEvent["content"] as? String, !content.isEmpty {
                                turn.thinkingBlocks[idx] = content
                            }
                            let durMs = closeActiveThinkingStepIfNeeded()
                            let fullThinking = turn.thinkingBlocks.keys.sorted().compactMap { turn.thinkingBlocks[$0] }.joined()
                            self.activeTurns[channel] = turn
                            Task { @MainActor in onEvent(.thinkingEnd(fullThinking, durationMs: durMs)) }
                            
                        case "text_delta":
                            if let delta = assistantEvent["delta"] as? String, !delta.isEmpty {
                                let nowDate = Date()
                                if turn.firstAnswerTextAt == nil {
                                    turn.firstAnswerTextAt = nowDate
                                }
                                let closedThinkingMs = closeActiveThinkingStepIfNeeded(now: nowDate)
                                turn.textBlocks[idx, default: ""] += delta
                                let joined = turn.textBlocks.keys.sorted().compactMap { turn.textBlocks[$0] }.joined()
                                let nowUptime = ProcessInfo.processInfo.systemUptime
                                let shouldEmit = (nowUptime - turn.lastTextEmitUptime) >= 0.025
                                if shouldEmit {
                                    turn.lastTextEmitUptime = nowUptime
                                }
                                let fullThinking = closedThinkingMs != nil
                                    ? turn.thinkingBlocks.keys.sorted().compactMap { turn.thinkingBlocks[$0] }.joined()
                                    : nil
                                self.activeTurns[channel] = turn
                                if shouldEmit || closedThinkingMs != nil {
                                    Task { @MainActor in
                                        if let fullThinking {
                                            onEvent(.thinkingEnd(fullThinking, durationMs: closedThinkingMs))
                                        }
                                        if shouldEmit {
                                            onEvent(.textDelta(joined))
                                        }
                                    }
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
                let now = Date()
                let startedMs = now.timeIntervalSince1970 * 1000.0
                let toolCallID = (json["toolCallId"] as? String) ?? UUID().uuidString
                let toolName = (json["toolName"] as? String) ?? "tool"
                let args = json["args"] as? [String: Any]
                let label = PiToolDisplayMeta.label(for: toolName)
                let detail = PiToolDisplayMeta.summarizeArgs(toolName, args: args)
                
                let closedThinkingMs = closeActiveThinkingStepIfNeeded(now: now)
                let fullThinking = closedThinkingMs != nil
                    ? turn.thinkingBlocks.keys.sorted().compactMap { turn.thinkingBlocks[$0] }.joined()
                    : nil
                
                if !turn.toolNames.contains(toolName) {
                    turn.toolNames.append(toolName)
                }
                turn.toolStartedAt[toolCallID] = now
                turn.toolTimeoutTasks[toolCallID]?.cancel()
                let toolTimeoutSec = Self.fastCotToolNames.contains(toolName)
                    ? self.timeoutPolicy.cotToolTimeoutSeconds
                    : self.timeoutPolicy.workspaceToolTimeoutSeconds
                turn.toolTimeoutTasks[toolCallID] = Task { [weak self] in
                    try? await Task.sleep(for: .seconds(toolTimeoutSec))
                    guard !Task.isCancelled else { return }
                    await self?.handleToolTimeout(channel: channel, turnID: turnID, toolCallID: toolCallID, toolName: toolName)
                }
                
                turn.steps.append(BeautifulAgentThinkingStep(
                    id: toolCallID,
                    label: label,
                    chip: detail ?? toolName,
                    status: "running",
                    mono: ["bash", "grep", "read", "edit", "write"].contains(toolName),
                    detail: nil,
                    durationMs: nil,
                    kind: "tool",
                    startedAtMs: startedMs
                ))
                self.activeTurns[channel] = turn
                Task { @MainActor in
                    if let fullThinking {
                        onEvent(.thinkingEnd(fullThinking, durationMs: closedThinkingMs))
                    }
                    onEvent(.toolStart(id: toolCallID, name: toolName, label: label, detail: detail, startedAtMs: startedMs))
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
                turn.toolTimeoutTasks.removeValue(forKey: toolCallID)?.cancel()
                let startedAt = turn.toolStartedAt.removeValue(forKey: toolCallID)
                let durationMs = Self.resolvedToolDurationMs(
                    rawDurationValue: json["durationMs"],
                    startedAt: startedAt,
                    now: Date()
                )
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
                
            case "agent_end":
                // `agent_settled` normally follows immediately; guard with a 1.5s fallback if `willRetry == false`
                if (json["willRetry"] as? Bool) != true {
                    turn.settleFallbackTask?.cancel()
                    turn.settleFallbackTask = Task { [weak self] in
                        try? await Task.sleep(for: .milliseconds(1500))
                        guard !Task.isCancelled else { return }
                        await self?.completeTurnNormally(channel: channel, expectedTurnID: turnID)
                    }
                    self.activeTurns[channel] = turn
                }
                
            case "agent_settled":
                self.completeTurnNormally(channel: channel, expectedTurnID: turnID)
                
            default:
                break
        }
    }
    
    
    private func completeTurnNormally(
        channel: PiAgentChannel,
        expectedTurnID: UUID? = nil,
        allowEmptyText: Bool = false
    ) {
        if let expectedTurnID, let current = self.activeTurns[channel], current.id != expectedTurnID {
            return
        }
        guard var turn = self.activeTurns.removeValue(forKey: channel) else { return }
        turn.cancelAllWatchdogs()
        self.clearPromptCommands(for: channel, turnID: turn.id)
        if let daemon = self.daemons[channel], daemon.id == turn.daemonID {
            daemon.isRunningTurn = false
        }
        
        let now = Date()
        let streamedText = turn.textBlocks.keys.sorted().compactMap { turn.textBlocks[$0] }.joined()
        let finalText = (turn.finalAssistantText ?? streamedText).trimmingCharacters(in: .whitespacesAndNewlines)
        let fullThinking = turn.thinkingBlocks.keys.sorted().compactMap { turn.thinkingBlocks[$0] }.joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        var finalSteps = turn.steps
        for i in finalSteps.indices where finalSteps[i].status == "running" {
            finalSteps[i].status = turn.aborted ? "error" : "done"
            if finalSteps[i].durationMs == nil, let startedMs = finalSteps[i].startedAtMs {
                let delta = Int((now.timeIntervalSince1970 * 1000.0 - startedMs).rounded())
                finalSteps[i].durationMs = max(1, delta)
            }
        }
        
        // Prefer sum of actual reasoning+tool durations (or time until first answer text), avoiding text-streaming tail inflation
        let sumStepDurations = finalSteps.reduce(0) { $0 + max(0, $1.durationMs ?? 0) }
        let wallMs = max(1, Int((now.timeIntervalSince(turn.startedAt) * 1000.0).rounded()))
        let preAnswerMs = turn.firstAnswerTextAt.map { max(1, Int(($0.timeIntervalSince(turn.startedAt) * 1000.0).rounded())) }
        let resolvedThinkingMs: Int = if sumStepDurations > 0 {
            min(wallMs, sumStepDurations)
        } else if let preAnswerMs {
            min(wallMs, preAnswerMs)
        } else {
            wallMs
        }
        
        let onEvent = turn.onEvent
        Task { @MainActor in onEvent(.settled) }
        
        if !finalText.isEmpty || turn.aborted || allowEmptyText {
            turn.continuation.resume(returning: PiAgentRunResult(
                text: finalText,
                thinking: fullThinking,
                thinkingDurationMs: resolvedThinkingMs,
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
    
    
    private func finishTurn(channel: PiAgentChannel, expectedTurnID: UUID? = nil, error: any Error) {
        if let expectedTurnID, let current = self.activeTurns[channel], current.id != expectedTurnID {
            return
        }
        guard var turn = self.activeTurns.removeValue(forKey: channel) else { return }
        turn.cancelAllWatchdogs()
        self.clearPromptCommands(for: channel, turnID: turn.id)
        if let daemon = self.daemons[channel], daemon.id == turn.daemonID {
            daemon.isRunningTurn = false
        }
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


private final class TurnIDBox: @unchecked Sendable {
    private let lock = NSLock()
    private var value: UUID?
    
    func set(_ id: UUID) {
        self.lock.lock()
        self.value = id
        self.lock.unlock()
    }
    
    func get() -> UUID? {
        self.lock.lock()
        let current = self.value
        self.lock.unlock()
        return current
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
                let lookupStart = Date()
                if let inst = await CotMarketService.shared.resolveInstrument(for: candidate),
                   let snap = await CotMarketService.shared.refresh(instrument: inst, period: .day, isBackgroundWatchlistRefresh: true)
                {
                    let elapsedMs = max(1, Int((Date().timeIntervalSince(lookupStart) * 1000.0).rounded()))
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
                        durationMs: elapsedMs,
                        kind: "tool",
                        startedAtMs: lookupStart.timeIntervalSince1970 * 1000.0
                    ))
                    break
                }
            }
        }
        
        // Detect news inquiry and attach cached headlines
        let newsKeywords = ["新闻", "资讯", "热点", "头条", "最新消息", "发生了什么", "news"]
        if newsKeywords.contains(where: { lower.contains($0) }) {
            let newsStart = Date()
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
                    durationMs: max(1, Int((Date().timeIntervalSince(newsStart) * 1000.0).rounded())),
                    kind: "tool",
                    startedAtMs: newsStart.timeIntervalSince1970 * 1000.0
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
