//
//  PiKernelManager.swift
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
import Observation

/// Capability tier governing which `pi` kernel tools a Bot may invoke when working.
nonisolated enum PiBotToolProfile: String, CaseIterable, Codable, Identifiable, Sendable {
    
    /// Pure fast LLM generation via `pi` (`--no-tools`) for low-latency text transforms.
    case pureChat
    
    /// Read-only workspace inspection (`read,grep,find,ls`) for analysis and reporting agents.
    case workspaceRead
    
    /// Full autonomous agent (`read,bash,edit,write,grep,find,ls`) capable of acting on files and shell tasks.
    case autonomousAgent
    
    var id: String { self.rawValue }
    
    var label: String {
        switch self {
            case .pureChat: AppLanguage.text("纯对话执行", en: "Fast Chat")
            case .workspaceRead: AppLanguage.text("只读检索 Agent", en: "Workspace Reader")
            case .autonomousAgent: AppLanguage.text("全功能干活 Agent", en: "Autonomous Agent")
        }
    }
    
    var shortBadge: String {
        switch self {
            case .pureChat: "Chat"
            case .workspaceRead: "Read"
            case .autonomousAgent: "Agent"
        }
    }
    
    var symbolName: String {
        switch self {
            case .pureChat: "bolt.fill"
            case .workspaceRead: "doc.text.magnifyingglass"
            case .autonomousAgent: "hammer.fill"
        }
    }
    
    var cliArguments: [String] {
        switch self {
            case .pureChat:
                ["--no-tools"]
            case .workspaceRead:
                ["--tools", "read,grep,find,ls"]
            case .autonomousAgent:
                ["--tools", "read,bash,edit,write,grep,find,ls"]
        }
    }
}


/// Summary returned after synchronizing API gateways and Bots into the managed `PiKernel` workspace.
nonisolated struct PiWorkspaceSyncSummary: Sendable, Equatable {
    
    let agentDirectory: URL
    let providerCount: Int
    let modelCount: Int
    let botCount: Int
}


/// Manages the embedded `pi` (`pi-coding-agent`) kernel workspace, gateway `models.json` synthesis,
/// per-bot agent manifests/sessions, headless JSONL streaming runs, and interactive TUI agent launches.
@MainActor @Observable
final class PiKernelManager {
    
    static let shared = PiKernelManager()
    
    static let kernelEnabledConfigKey = "ai.pi.kernelEnabled"
    static let customBinaryConfigKey = "ai.pi.binaryPath"
    static let minimumRecommendedVersion = "1.6.0"
    
    /// Copy-ready installation prompt (< 50 lines) users can paste into an AI assistant or run themselves
    /// when `pi` is not yet installed locally.
    nonisolated static let installPrompt: String = """
    请帮我在当前 macOS 环境中安装并验证 Pi 本地内核（@earendil-works/pi-coding-agent），供 CotEditor 调用：

    1. 检查是否已有 `pi` 命令：
       `command -v pi && pi --version`
    2. 如未安装，优先使用官方一键脚本安装（无需 Node 环境，自动固定依赖）：
       `curl -fsSL https://pi.dev/install.sh | sh`
    3. 如网络或环境更适合 npm（需 Node.js >= 22.19），改用：
       `npm install -g --ignore-scripts @earendil-works/pi-coding-agent`
    4. 若已安装但版本较旧，直接升级到最新内核：
       `pi update`
    5. 确保 `~/.local/bin` 或 `~/.pi/bin` 已加入 `~/.zshrc` 的 `PATH`，然后执行：
       `which pi && pi --version`
    6. 返回最终 `pi` 路径与版本号即可，无需在 `~/.pi/agent` 额外手写模型配置（CotEditor 会自动同步 API 网关与 Bot 配置到独立工作区）。
    """
    
    private(set) var piBinaryPath: String?
    private(set) var piVersion: String?
    private(set) var activeBotRuns: Set<AIBotID> = []
    private(set) var lastSyncedAt: Date?
    private(set) var syncedProviderCount: Int = 0
    private(set) var syncedBotCount: Int = 0
    
    let agentDirectoryURL: URL
    private let database: CotLocalDatabase
    @ObservationIgnored private var workspaceSyncTask: Task<Void, Never>?
    @ObservationIgnored private var writtenFileCache: [String: Data] = [:]
    @ObservationIgnored private var ensuredDirectoryPaths: Set<String> = []
    @ObservationIgnored private var terminationObserver: (any NSObjectProtocol)?
    private(set) var workspaceConfigStamp: String = "initial"
    private static let extraBinsLock = NSLock()
    private nonisolated(unsafe) static var cachedNodeRuntimeBins: (expiresAt: TimeInterval, bins: [String])?
    
    var isAvailable: Bool {
        guard let path = self.piBinaryPath else { return false }
        return FileManager.default.isExecutableFile(atPath: path)
    }
    
    var isKernelEnabled: Bool {
        get {
            self.database.bool(forKey: Self.kernelEnabledConfigKey, default: true)
        }
        set {
            self.database.set(newValue, forKey: Self.kernelEnabledConfigKey)
        }
    }
    
    var statusSummary: String {
        if let version = self.piVersion, self.isAvailable {
            return self.isKernelEnabled
                ? "Pi v\(version)"
                : AppLanguage.text("Pi v\(version) · 已暂停", en: "Pi v\(version) · Paused")
        }
        if self.isAvailable {
            return self.isKernelEnabled
                ? AppLanguage.text("Pi 已就绪", en: "Pi Ready")
                : AppLanguage.text("Pi 已暂停", en: "Pi Paused")
        }
        return AppLanguage.text("未安装 Pi", en: "Pi Not Installed")
    }
    
    
    init(customAgentDirectoryURL: URL? = nil, database: CotLocalDatabase = .shared) {
        self.database = database
        if let customAgentDirectoryURL {
            self.agentDirectoryURL = customAgentDirectoryURL
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? URL(filePath: NSTemporaryDirectory(), directoryHint: .isDirectory)
            self.agentDirectoryURL = appSupport
                .appending(path: "Cot", directoryHint: .isDirectory)
                .appending(path: "PiKernel", directoryHint: .isDirectory)
        }
        
        let isTesting = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || NSClassFromString("XCTestCase") != nil
        if isTesting {
            self.piBinaryPath = Self.discoverPiBinary(customOverride: database.string(forKey: Self.customBinaryConfigKey))
        } else {
            self.piBinaryPath = nil
            self.terminationObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.willTerminateNotification,
                object: nil,
                queue: .main
            ) { _ in
                Task.detached(priority: .userInitiated) {
                    await PiRPCRuntime.shared.shutdownAll()
                }
            }
            Task { @MainActor [weak self] in
                await self?.refreshEnvironment()
            }
        }
    }
    
    
    // MARK: Binary Discovery & Runtime Environment
    
    nonisolated static func discoverPiBinary(customOverride: String? = nil) -> String? {
        let fm = FileManager.default
        if let custom = customOverride?.trimmingCharacters(in: .whitespacesAndNewlines),
           !custom.isEmpty,
           fm.isExecutableFile(atPath: custom)
        {
            return custom
        }
        
        let home = fm.homeDirectoryForCurrentUser.path(percentEncoded: false)
        var candidates: [String] = [
            "\(home)/.pi/bin/pi",
            "\(home)/.local/bin/pi",
            "\(home)/.local/share/mise/shims/pi",
            "\(home)/.local/share/mise/installs/npm-earendil-works-pi-coding-agent/latest/bin/pi",
            "\(home)/.bun/bin/pi",
            "\(home)/.volta/bin/pi",
            "\(home)/.nix-profile/bin/pi",
            "\(home)/.npm-global/bin/pi",
            "/opt/homebrew/bin/pi",
            "/usr/local/bin/pi",
        ]
        
        if let pathEnv = ProcessInfo.processInfo.environment["PATH"] {
            for entry in pathEnv.split(separator: ":") {
                candidates.append("\(entry)/pi")
            }
        }
        
        // Check mise installs directory (both `latest` and versioned subdirectories)
        let miseRoot = URL(filePath: "\(home)/.local/share/mise/installs", directoryHint: .isDirectory)
        if let subdirs = try? fm.contentsOfDirectory(at: miseRoot, includingPropertiesForKeys: nil) {
            for dir in subdirs where dir.lastPathComponent.localizedCaseInsensitiveContains("pi") {
                candidates.append(dir.appending(path: "latest/bin/pi").path(percentEncoded: false))
                if let versions = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) {
                    for ver in versions.sorted(by: { $0.lastPathComponent > $1.lastPathComponent }) {
                        candidates.append(ver.appending(path: "bin/pi").path(percentEncoded: false))
                    }
                }
            }
        }
        
        for candidate in candidates {
            if fm.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        return nil
    }
    
    
    /// Augments `PATH` for GUI-launched macOS apps so `#!/usr/bin/env node` / Bun / mise shims resolve reliably.
    nonisolated static func augmentedRuntimeEnvironment(
        binaryPath: String? = nil,
        agentDirectoryPath: String? = nil,
        databasePath: String? = nil,
        base: [String: String] = ProcessInfo.processInfo.environment
    ) -> [String: String] {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser.path(percentEncoded: false)
        var extraBins: [String] = []
        if let binaryPath {
            let parent = URL(filePath: binaryPath).deletingLastPathComponent().path(percentEncoded: false)
            if !parent.isEmpty { extraBins.append(parent) }
        }
        extraBins.append(contentsOf: [
            "\(home)/.pi/bin",
            "\(home)/.local/bin",
            "\(home)/.local/share/mise/shims",
            "\(home)/.bun/bin",
            "\(home)/.volta/bin",
            "\(home)/.fnm/current/bin",
            "\(home)/.nix-profile/bin",
            "/opt/homebrew/bin",
            "/usr/local/bin",
        ])
        
        // Include mise/nvm Node runtimes if present for npm-installed Pi 1.6+ (`#!/usr/bin/env node`), cached 60s.
        let nowUptime = ProcessInfo.processInfo.systemUptime
        let nodeBins: [String] = {
            Self.extraBinsLock.lock()
            if let cached = Self.cachedNodeRuntimeBins, nowUptime < cached.expiresAt {
                let bins = cached.bins
                Self.extraBinsLock.unlock()
                return bins
            }
            Self.extraBinsLock.unlock()
            
            var discovered: [String] = []
            let miseNodeDir = URL(filePath: "\(home)/.local/share/mise/installs/node", directoryHint: .isDirectory)
            if let versions = try? fm.contentsOfDirectory(at: miseNodeDir, includingPropertiesForKeys: nil) {
                for ver in versions.sorted(by: { $0.lastPathComponent > $1.lastPathComponent }) {
                    discovered.append(ver.appending(path: "bin").path(percentEncoded: false))
                }
            }
            let nvmNodeDir = URL(filePath: "\(home)/.nvm/versions/node", directoryHint: .isDirectory)
            if let versions = try? fm.contentsOfDirectory(at: nvmNodeDir, includingPropertiesForKeys: nil) {
                for ver in versions.sorted(by: { $0.lastPathComponent > $1.lastPathComponent }) {
                    discovered.append(ver.appending(path: "bin").path(percentEncoded: false))
                }
            }
            Self.extraBinsLock.lock()
            Self.cachedNodeRuntimeBins = (nowUptime + 60.0, discovered)
            Self.extraBinsLock.unlock()
            return discovered
        }()
        extraBins.append(contentsOf: nodeBins)
        
        let existingPath = base["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        var seen = Set<String>()
        var merged: [String] = []
        for entry in extraBins + existingPath.split(separator: ":").map(String.init) {
            let trimmed = entry.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, seen.insert(trimmed).inserted else { continue }
            merged.append(trimmed)
        }
        
        var env = base
        env["PATH"] = merged.joined(separator: ":")
        if let agentDirectoryPath {
            env["PI_CODING_AGENT_DIR"] = agentDirectoryPath
        }
        env["PI_OFFLINE"] = "1"
        env["PI_SKIP_VERSION_CHECK"] = "1"
        env["PI_TELEMETRY"] = "0"
        if let databasePath, !databasePath.isEmpty {
            env["COT_DB_PATH"] = databasePath
        }
        return env
    }
    
    
    func refreshEnvironment() async {
        let custom = self.database.string(forKey: Self.customBinaryConfigKey)
        let dbPath = self.database.databaseURL.path(percentEncoded: false)
        let resolvedPath = await Task.detached(priority: .utility) {
            Self.discoverPiBinary(customOverride: custom)
        }.value
        self.piBinaryPath = resolvedPath
        
        guard let resolvedPath else {
            self.piVersion = nil
            _ = try? self.syncWorkspace()
            return
        }
        
        let detectedVersion = await Task.detached(priority: .utility) { () -> String? in
            let proc = Process()
            proc.executableURL = URL(filePath: resolvedPath)
            proc.arguments = ["--version"]
            proc.environment = Self.augmentedRuntimeEnvironment(binaryPath: resolvedPath, databasePath: dbPath)
            let outPipe = Pipe()
            proc.standardOutput = outPipe
            proc.standardError = Pipe()
            do {
                try proc.run()
                proc.waitUntilExit()
                guard proc.terminationStatus == 0 else { return nil }
                let data = outPipe.fileHandleForReading.readDataToEndOfFile()
                return String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            } catch {
                return nil
            }
        }.value
        
        if let detectedVersion, !detectedVersion.isEmpty {
            self.piVersion = detectedVersion
        }
        _ = try? self.syncWorkspace()
    }
    
    
    // MARK: Gateway & Bot Workspace Synchronization
    
    nonisolated static func providerID(for profile: AIEndpointProfile) -> String {
        let compact = profile.id.uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        return "cot-gw-\(compact.prefix(10))"
    }
    
    
    nonisolated static func piAPIType(for endpoint: AIEndpoint) -> String {
        switch endpoint {
            case .openAIChatCompletions, .ollama:
                "openai-completions"
            case .openAIResponses:
                "openai-responses"
            case .anthropicMessages:
                "anthropic-messages"
            case .googleGemini:
                "google-generative-ai"
        }
    }
    
    
    nonisolated static func normalizedPiBaseURL(_ rawBaseURL: String, endpoint: AIEndpoint) -> String {
        var url = rawBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if url.isEmpty {
            url = endpoint.defaultBaseURL
        }
        while url.hasSuffix("/") {
            url.removeLast()
        }
        for op in ["/chat/completions", "/responses", "/messages"] {
            if url.hasSuffix(op) {
                url.removeLast(op.count)
                break
            }
        }
        if endpoint == .ollama, !url.hasSuffix("/v1") {
            url += "/v1"
        }
        return url
    }
    
    
    /// Debounces non-urgent `syncWorkspace()` calls so rapid memory/bot edits coalesce into one write.
    func scheduleWorkspaceSync(delayMs: Int = 250) {
        self.workspaceSyncTask?.cancel()
        self.workspaceSyncTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(max(10, delayMs)))
            guard let self, !Task.isCancelled else { return }
            self.workspaceSyncTask = nil
            _ = try? self.syncWorkspace()
        }
    }
    
    
    private func ensureDirectory(_ url: URL, fileManager: FileManager = .default) throws {
        let path = url.path(percentEncoded: false)
        if self.ensuredDirectoryPaths.contains(path), fileManager.fileExists(atPath: path) {
            return
        }
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        self.ensuredDirectoryPaths.insert(path)
    }
    
    
    @discardableResult
    private func writeIfChanged(
        _ data: Data,
        to url: URL,
        permissions: Int? = nil,
        fileManager: FileManager = .default
    ) throws -> Bool {
        let path = url.path(percentEncoded: false)
        if self.writtenFileCache[path] == data, fileManager.fileExists(atPath: path) {
            return false
        }
        try data.write(to: url, options: .atomic)
        if let permissions {
            try? fileManager.setAttributes([.posixPermissions: permissions], ofItemAtPath: path)
        }
        self.writtenFileCache[path] = data
        return true
    }
    
    
    /// Synchronizes all configured API Gateways and Bots into `<agentDirectoryURL>/models.json`,
    /// `auth.json` (`0o600`), and `agents/<botID>/` manifests + `SYSTEM.md` instructions.
    @discardableResult
    func syncWorkspace(
        endpoints: [AIEndpointProfile]? = nil,
        botStore: AIBotStore? = nil,
        keyLookup: ((AIEndpointProfile) -> String)? = nil
    ) throws -> PiWorkspaceSyncSummary {
        
        let fm = FileManager.default
        let resolvedEndpoints = endpoints ?? AIEndpointStore.profiles
        let resolvedBotStore = botStore ?? AIBotStore.shared
        let activeID = AIEndpointStore.activeID ?? resolvedEndpoints.first?.id
        let activeEndpoint = resolvedEndpoints.first(where: { $0.id == activeID }) ?? resolvedEndpoints.first
        let globalPersona = self.database.aiPersona.trimmingCharacters(in: .whitespacesAndNewlines)
        let kycContext = CotMemoryStore.shared.compiledKYCContext()
        let workspaceContext = CotAgentCoordinator.shared.workspaceContextSummary()
        
        try self.ensureDirectory(self.agentDirectoryURL, fileManager: fm)
        let agentsDir = self.agentDirectoryURL.appending(path: "agents", directoryHint: .isDirectory)
        let sessionsDir = self.agentDirectoryURL.appending(path: "sessions", directoryHint: .isDirectory)
        let extensionsDir = self.agentDirectoryURL.appending(path: "extensions", directoryHint: .isDirectory)
        let runtimeDir = self.agentDirectoryURL.appending(path: "runtime", directoryHint: .isDirectory)
        try self.ensureDirectory(agentsDir, fileManager: fm)
        try self.ensureDirectory(sessionsDir, fileManager: fm)
        try self.ensureDirectory(extensionsDir, fileManager: fm)
        try self.ensureDirectory(runtimeDir, fileManager: fm)
        
        // Collect extra model overrides referenced by individual Bots
        var extraModelsByEndpoint: [UUID: Set<String>] = [:]
        for botID in AIBotID.allCases {
            let cfg = resolvedBotStore.config(for: botID)
            let overrideModel = cfg.modelOverride.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !overrideModel.isEmpty else { continue }
            if let epID = cfg.endpointID ?? activeEndpoint?.id {
                extraModelsByEndpoint[epID, default: []].insert(overrideModel)
            }
        }
        
        var providersDict: [String: Any] = [:]
        var authDict: [String: Any] = [:]
        var totalModels = 0
        
        for profile in resolvedEndpoints {
            let pid = Self.providerID(for: profile)
            let wireEndpoint = profile.configuration(apiKey: "").wireConfiguration.endpoint
            let apiType = Self.piAPIType(for: wireEndpoint)
            let baseURL = Self.normalizedPiBaseURL(profile.baseURL, endpoint: wireEndpoint)
            guard !baseURL.isEmpty else { continue }
            
            var seenModelIDs: Set<String> = []
            var modelEntries: [[String: Any]] = []
            let candidates = profile.availableModelIDs
                + Array(extraModelsByEndpoint[profile.id] ?? [])
                + (profile.provider == .custom ? [] : [profile.provider.defaultModel])
            
            for rawModel in candidates {
                let mid = rawModel.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !mid.isEmpty, seenModelIDs.insert(mid).inserted else { continue }
                var modelEntry: [String: Any] = [
                    "id": mid,
                    "name": mid,
                    "reasoning": Self.isReasoningModelID(mid),
                    "input": ["text", "image"],
                    "contextWindow": 128_000,
                    "maxTokens": 16_384,
                    "cost": [
                        "input": 0,
                        "output": 0,
                        "cacheRead": 0,
                        "cacheWrite": 0,
                    ],
                ]
                var perModelCfg = profile.configuration(apiKey: "")
                perModelCfg.model = mid
                let perModelWireEndpoint = perModelCfg.wireConfiguration.endpoint
                if perModelWireEndpoint != wireEndpoint {
                    modelEntry["api"] = Self.piAPIType(for: perModelWireEndpoint)
                }
                modelEntries.append(modelEntry)
                totalModels += 1
            }
            
            var providerObj: [String: Any] = [
                "name": profile.displayName,
                "baseUrl": baseURL,
                "api": apiType,
                "models": modelEntries,
            ]
            if wireEndpoint == .openAIChatCompletions || wireEndpoint == .openAIResponses {
                providerObj["authHeader"] = true
            }
            var sanitizedHeaders: [String: String] = [:]
            for (rawKey, rawValue) in profile.customHeaders {
                let k = rawKey.trimmingCharacters(in: .whitespacesAndNewlines)
                let v = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !k.isEmpty, !v.isEmpty else { continue }
                sanitizedHeaders[k] = v
            }
            if profile.provider == .openCodeGo, sanitizedHeaders["x-opencode-session"] == nil {
                sanitizedHeaders["x-opencode-session"] = "coteditor-go-session"
            }
            if !sanitizedHeaders.isEmpty {
                providerObj["headers"] = sanitizedHeaders
            }
            providersDict[pid] = providerObj
            
            let resolvedKey = (keyLookup?(profile) ?? AIEndpointStore.apiKey(for: profile))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let effectiveKey = resolvedKey.isEmpty && wireEndpoint == .ollama ? "ollama" : resolvedKey
            if !effectiveKey.isEmpty {
                authDict[pid] = [
                    "type": "api_key",
                    "key": effectiveKey,
                ]
            }
        }
        
        var didWriteAnyFile = false
        var didWriteRuntimeConfig = false
        let modelsPayload: [String: Any] = [
            "$schema": "https://pi.dev/schemas/models.schema.json",
            "providers": providersDict,
        ]
        let modelsData = try JSONSerialization.data(withJSONObject: modelsPayload, options: [.prettyPrinted, .sortedKeys])
        if try self.writeIfChanged(modelsData, to: self.agentDirectoryURL.appending(path: "models.json"), fileManager: fm) {
            didWriteAnyFile = true
            didWriteRuntimeConfig = true
        }
        
        // Write auth.json with strict owner-only 0o600 permissions
        let authURL = self.agentDirectoryURL.appending(path: "auth.json")
        let authData = try JSONSerialization.data(withJSONObject: authDict, options: [.prettyPrinted, .sortedKeys])
        if try self.writeIfChanged(authData, to: authURL, permissions: 0o600, fileManager: fm) {
            didWriteAnyFile = true
            didWriteRuntimeConfig = true
        }
        
        // Write native CotEditor Pi extension (`extensions/cot-tools.ts`) for live quotes, news, search, DB & UI control
        let cotToolsURL = extensionsDir.appending(path: PiCotToolsExtension.filename)
        if try self.writeIfChanged(Data(PiCotToolsExtension.source.utf8), to: cotToolsURL, fileManager: fm) {
            didWriteAnyFile = true
            didWriteRuntimeConfig = true
        }
        if didWriteRuntimeConfig || self.workspaceConfigStamp == "initial" {
            self.workspaceConfigStamp = UUID().uuidString
        }
        
        // Write Pi 1.6+ schema-compliant settings.json (quiet startup, no slow auto-retry loops during headless runs)
        let settingsPayload: [String: Any] = [
            "$schema": "https://pi.dev/schemas/settings.schema.json",
            "quietStartup": true,
            "lastChangelogVersion": self.piVersion ?? Self.minimumRecommendedVersion,
            "retry": [
                "enabled": false,
            ],
        ]
        if let settingsData = try? JSONSerialization.data(withJSONObject: settingsPayload, options: [.prettyPrinted, .sortedKeys]) {
            if (try? self.writeIfChanged(settingsData, to: self.agentDirectoryURL.appending(path: "settings.json"), fileManager: fm)) == true {
                didWriteAnyFile = true
            }
        }
        
        // Write live CotEditor perception & SQLite control contract for autonomous Pi runs
        let dbFilePath = self.database.databaseURL.path(percentEncoded: false)
        let cotContextDoc = """
        # CotEditor Live Perception & Takeover Contract
        
        - `COT_DB_PATH`: `\(dbFilePath)`
        - Core SQLite tables:
          - `documents (id, title, file_path, syntax, content, group_name, updated_at)`
          - `user_kyc_memories (id, dimension, fact_key, title, detail, confidence, is_pinned)`
          - `user_watchlist_stocks (instrument_id, namespace, symbol, name, eastmoney_secid, tencent_code, last_price, last_change_pct)`
          - `user_podcasts (id, platform, title, show_name, source_url, audio_url, playback_position_sec, is_saved)`
          - `user_followed_feeds (id, title, site_url, feed_url, category)`
          - `user_followed_creators (id, platform, handle, display_name, profile_url, focus_tags)`
          - `workspace_live_state (slot, payload_json, updated_at)`
          - `agent_command_queue (action_type, payload_json, status='pending')` — insert JSON rows (`convert_tab`, `open_board`, `open_document`, `upsert_memory`, `watch_stock`, `play_podcast`, `follow_feed`, `follow_creator`, `update_bot`) to drive the live editor UI.
        
        \(kycContext)
        
        \(workspaceContext.isEmpty ? "" : "## 实时工作区上下文\n\(workspaceContext)")
        """
        if (try? self.writeIfChanged(Data(cotContextDoc.utf8), to: self.agentDirectoryURL.appending(path: "COT_CONTEXT.md"), fileManager: fm)) == true {
            didWriteAnyFile = true
        }
        
        // Write per-bot agent workspace (SYSTEM.md + bot-manifest.json + session directory)
        for botID in AIBotID.allCases {
            let botCfg = resolvedBotStore.config(for: botID)
            let botDir = agentsDir.appending(path: botID.rawValue, directoryHint: .isDirectory)
            let botSessionDir = sessionsDir.appending(path: botID.rawValue, directoryHint: .isDirectory)
            try self.ensureDirectory(botDir, fileManager: fm)
            try self.ensureDirectory(botSessionDir, fileManager: fm)
            
            let customPersona = botCfg.customPersona.trimmingCharacters(in: .whitespacesAndNewlines)
            let effectivePersona = customPersona.isEmpty ? globalPersona : customPersona
            let stagePrompt = resolvedBotStore.systemPrompt(for: botID)
            let promptParts = [effectivePersona, kycContext, stagePrompt].filter { !$0.isEmpty }
            let fullPrompt = promptParts.joined(separator: "\n\n")
            if try self.writeIfChanged(Data(fullPrompt.utf8), to: botDir.appending(path: "SYSTEM.md"), fileManager: fm) {
                didWriteAnyFile = true
            }
            
            let targetEndpoint = botCfg.endpointID.flatMap { id in resolvedEndpoints.first(where: { $0.id == id }) } ?? activeEndpoint
            let effectiveModel = botCfg.modelOverride.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? (targetEndpoint?.displayModel ?? "")
                : botCfg.modelOverride.trimmingCharacters(in: .whitespacesAndNewlines)
            let character = AIGijinkaCharacter.resolve(
                modelName: effectiveModel,
                endpointName: targetEndpoint?.displayName,
                baseURL: targetEndpoint?.baseURL
            )
            let artwork = character?.artwork(for: botID, variantOverride: botCfg.artworkVariantIndex)
            let toolProfile = botCfg.effectiveToolProfile(for: botID)
            
            let manifest: [String: Any] = [
                "id": botID.rawValue,
                "handle": botID.handle,
                "displayName": botID.displayName,
                "isEnabled": botCfg.isEnabled,
                "provider": targetEndpoint.map(Self.providerID(for:)) ?? "",
                "gatewayName": targetEndpoint?.displayName ?? "",
                "model": effectiveModel,
                "personaBrand": character?.brand ?? "",
                "artworkID": artwork?.id ?? "",
                "toolProfile": toolProfile.rawValue,
            ]
            let manifestData = try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
            if try self.writeIfChanged(manifestData, to: botDir.appending(path: "bot-manifest.json"), fileManager: fm) {
                didWriteAnyFile = true
            }
        }
        
        if didWriteAnyFile || self.lastSyncedAt == nil || self.syncedProviderCount != providersDict.count || self.syncedBotCount != AIBotID.allCases.count {
            self.syncedProviderCount = providersDict.count
            self.syncedBotCount = AIBotID.allCases.count
            self.lastSyncedAt = Date()
        }
        
        return PiWorkspaceSyncSummary(
            agentDirectory: self.agentDirectoryURL,
            providerCount: providersDict.count,
            modelCount: totalModels,
            botCount: AIBotID.allCases.count
        )
    }
    
    
    nonisolated static func isReasoningModelID(_ modelID: String) -> Bool {
        let lower = modelID.lowercased()
        let markers = [
            "reasoner", "deepseek-r1", "deepseek-v4", "gpt-5", "gpt-6",
            "o1", "o3", "o4", "claude-3-7", "claude-4", "claude-opus-4", "claude-sonnet-4",
            "gemini-2.5", "gemini-3", "qwen4", "qwq", "thinking",
        ]
        return markers.contains { lower.contains($0) }
    }
    
    
    /// Stateful accumulator for Pi 1.6+ delta-only JSONL event streams (`--mode json` / `--mode rpc`).
    nonisolated struct JSONLStreamState: Sendable {
        var textBlocks: [Int: String] = [:]
        var thinkingBlocks: [Int: String] = [:]
        var finalAssistantText: String?
        var errorMessage: String?
        var activeToolName: String?
        var completedTools: [String] = []
        var isSettled: Bool = false
        
        var streamedText: String {
            self.textBlocks.keys.sorted().compactMap { self.textBlocks[$0] }.joined()
        }
        
        var streamedThinking: String {
            self.thinkingBlocks.keys.sorted().compactMap { self.thinkingBlocks[$0] }.joined()
        }
        
        var resolvedOutput: String {
            (self.finalAssistantText ?? self.streamedText).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        mutating func ingest(_ json: [String: Any]) -> (partialSnapshot: String?, toolHint: String?) {
            guard let eventType = json["type"] as? String else { return (nil, nil) }
            switch eventType {
                case "message_update":
                    if let assistantEvent = json["assistantMessageEvent"] as? [String: Any],
                       let subType = assistantEvent["type"] as? String
                    {
                        let idx = assistantEvent["contentIndex"] as? Int ?? 0
                        switch subType {
                            case "thinking_delta":
                                if let delta = assistantEvent["delta"] as? String, !delta.isEmpty {
                                    self.thinkingBlocks[idx, default: ""] += delta
                                }
                            case "thinking_end":
                                if let content = assistantEvent["content"] as? String {
                                    self.thinkingBlocks[idx] = content
                                }
                            case "text_delta":
                                if let delta = assistantEvent["delta"] as? String, !delta.isEmpty {
                                    self.textBlocks[idx, default: ""] += delta
                                    return (self.streamedText, nil)
                                }
                            case "text_end":
                                if let content = assistantEvent["content"] as? String {
                                    self.textBlocks[idx] = content
                                    return (self.streamedText, nil)
                                }
                            case "error":
                                if let errStr = assistantEvent["error"] as? String, !errStr.isEmpty {
                                    self.errorMessage = errStr
                                } else if let errObj = assistantEvent["error"] as? [String: Any],
                                          let errMsg = errObj["errorMessage"] as? String, !errMsg.isEmpty
                                {
                                    self.errorMessage = errMsg
                                }
                            default:
                                break
                        }
                    }
                    
                case "tool_execution_start":
                    if let toolName = json["toolName"] as? String, !toolName.isEmpty {
                        self.activeToolName = toolName
                        if self.streamedText.isEmpty {
                            return (nil, "▸ Pi Agent 正在执行工具 `\(toolName)`…\n")
                        }
                    }
                    
                case "tool_execution_end":
                    if let toolName = json["toolName"] as? String, !toolName.isEmpty {
                        self.completedTools.append(toolName)
                        if self.activeToolName == toolName {
                            self.activeToolName = nil
                        }
                    }
                    
                case "message_end":
                    if let message = json["message"] as? [String: Any],
                       (message["role"] as? String) == "assistant"
                    {
                        if let errMsg = message["errorMessage"] as? String, !errMsg.isEmpty {
                            self.errorMessage = errMsg
                        }
                        if let blocks = message["content"] as? [[String: Any]] {
                            let joined = blocks.compactMap { block -> String? in
                                guard (block["type"] as? String) == "text" else { return nil }
                                return block["text"] as? String
                            }.joined()
                            if !joined.isEmpty {
                                self.finalAssistantText = joined
                                return (joined, nil)
                            }
                        }
                    }
                    
                case "auto_retry_end":
                    if (json["success"] as? Bool) == false,
                       let finalErr = json["finalError"] as? String, !finalErr.isEmpty
                    {
                        self.errorMessage = finalErr
                    }
                    
                case "agent_settled":
                    self.isSettled = true
                    
                default:
                    break
            }
            return (nil, nil)
        }
    }
    
    
    // MARK: Headless Pi JSONL Streaming Execution
    
    /// Determines whether `AIService` should route a Bot call through the `pi` kernel subprocess.
    func shouldRouteThroughKernel(for botID: AIBotID, hasImages: Bool) -> Bool {
        // Inline keystroke ghost completion stays on ultra-low-latency direct SSE;
        // multimodal image payloads fall back cleanly unless purely text/workspace driven.
        guard self.isKernelEnabled, self.isAvailable, !hasImages, botID != .ghost else {
            return false
        }
        return true
    }
    
    
    /// Executes a Bot task on the `pi` kernel in `--mode json -p` mode, streaming deltas progressively.
    func runBot(
        _ botID: AIBotID,
        systemPrompt: String,
        userPrompt: String,
        endpointProfile: AIEndpointProfile,
        configuration: AIConfiguration,
        workingDirectory: URL? = nil,
        onPartial: (@MainActor @Sendable (String) -> Void)? = nil
    ) async throws -> String {
        
        if self.piBinaryPath == nil {
            self.piBinaryPath = Self.discoverPiBinary(customOverride: self.database.string(forKey: Self.customBinaryConfigKey))
        }
        guard let binaryPath = self.piBinaryPath, FileManager.default.isExecutableFile(atPath: binaryPath) else {
            throw AIError.http(status: 503, message: AppLanguage.text("未找到 pi 可执行文件", en: "pi executable not found"))
        }
        
        _ = try? self.syncWorkspace()
        
        let providerID = Self.providerID(for: endpointProfile)
        let modelID = configuration.model.trimmingCharacters(in: .whitespacesAndNewlines)
        let botConfig = AIBotStore.shared.config(for: botID)
        let toolProfile = botConfig.effectiveToolProfile(for: botID)
        let sessionDir = self.agentDirectoryURL
            .appending(path: "sessions", directoryHint: .isDirectory)
            .appending(path: botID.rawValue, directoryHint: .isDirectory)
        let agentDirPath = self.agentDirectoryURL.path(percentEncoded: false)
        let apiKey = configuration.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        
        var args: [String] = [
            "--mode", "json",
            "-p",
            "--offline",
            "--no-extensions",
            "--no-mcp",
            "--no-skills",
            "--no-prompt-templates",
            "--no-themes",
            "--provider", providerID,
            "--model", modelID,
            "--system-prompt", systemPrompt,
        ]
        if toolProfile == .pureChat {
            args.append("--no-context-files")
            args.append("--no-session")
        } else {
            args.append(contentsOf: ["--session-dir", sessionDir.path(percentEncoded: false)])
            args.append("--no-approve")
        }
        args.append(contentsOf: toolProfile.cliArguments)
        if !apiKey.isEmpty {
            args.append(contentsOf: ["--api-key", apiKey])
        }
        args.append("--")
        args.append(userPrompt)
        
        self.activeBotRuns.insert(botID)
        defer { self.activeBotRuns.remove(botID) }
        
        let dbPath = self.database.databaseURL.path(percentEncoded: false)
        
        return try await Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = URL(filePath: binaryPath)
            process.arguments = args
            if let workingDirectory, FileManager.default.fileExists(atPath: workingDirectory.path(percentEncoded: false)) {
                process.currentDirectoryURL = workingDirectory
            }
            
            process.environment = Self.augmentedRuntimeEnvironment(
                binaryPath: binaryPath,
                agentDirectoryPath: agentDirPath,
                databasePath: dbPath
            )
            
            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe
            process.standardInput = FileHandle.nullDevice
            
            try process.run()
            
            let handle = stdoutPipe.fileHandleForReading
            let stderrHandle = stderrPipe.fileHandleForReading
            let stderrTask = Task.detached(priority: .utility) { () -> Data in
                stderrHandle.readDataToEndOfFile()
            }
            var lineBuffer = Data()
            var streamState = JSONLStreamState()
            var lastEmitUptime: TimeInterval = 0
            var pendingPartial: String?
            
            while true {
                if Task.isCancelled {
                    if process.isRunning { process.terminate() }
                    stderrTask.cancel()
                    throw CancellationError()
                }
                let chunk = try handle.read(upToCount: 4096) ?? Data()
                if chunk.isEmpty { break }
                lineBuffer.append(chunk)
                
                // Strict LF framing per Pi 1.6+ JSONL protocol specification
                while let newlineIndex = lineBuffer.firstIndex(of: 0x0A) {
                    var recordBytes = lineBuffer.subdata(in: 0..<newlineIndex)
                    lineBuffer.removeSubrange(0...newlineIndex)
                    if recordBytes.last == 0x0D {
                        recordBytes.removeLast()
                    }
                    guard !recordBytes.isEmpty,
                          let json = try? JSONSerialization.jsonObject(with: recordBytes) as? [String: Any]
                    else { continue }
                    
                    let update = streamState.ingest(json)
                    if let onPartial, let snapshot = update.partialSnapshot ?? update.toolHint {
                        let now = ProcessInfo.processInfo.systemUptime
                        if now - lastEmitUptime >= 0.035 {
                            lastEmitUptime = now
                            pendingPartial = nil
                            await MainActor.run { onPartial(snapshot) }
                        } else {
                            pendingPartial = snapshot
                        }
                    }
                }
            }
            if let onPartial, let trailing = pendingPartial {
                await MainActor.run { onPartial(trailing) }
            }
            
            process.waitUntilExit()
            let stderrData = await stderrTask.value
            let stderrString = String(data: stderrData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            
            let resolvedOutput = streamState.resolvedOutput
            if !resolvedOutput.isEmpty {
                return resolvedOutput
            }
            if let errMsg = streamState.errorMessage, !errMsg.isEmpty {
                throw AIError.http(status: 502, message: errMsg)
            }
            if process.terminationStatus != 0 {
                let detail = stderrString.isEmpty ? "exit \(process.terminationStatus)" : stderrString
                throw AIError.http(status: 502, message: "Pi 内核执行失败：\(detail)")
            }
            throw AIError.emptyResponse
        }.value
    }
    
    
    // MARK: Warm Persistent RPC Runtime (Butler & NEWS AI)
    
    /// Whether the warm persistent Pi RPC kernel can execute turns right now.
    var canRunRPC: Bool {
        self.isKernelEnabled && self.isAvailable
    }
    
    
    /// Runs a streaming conversation turn on a warm persistent `pi --mode rpc` daemon
    /// loaded with CotEditor's native `extensions/cot-tools.ts`.
    func runRPCTurn(
        channel: PiAgentChannel,
        logicalSessionKey: String,
        systemPrompt: String,
        userPrompt: String,
        priorHistoryContext: String? = nil,
        endpointProfile: AIEndpointProfile,
        configuration: AIConfiguration,
        thinkingLevel: String? = nil,
        workingDirectory: URL? = nil,
        onEvent: @escaping @MainActor @Sendable (PiAgentStreamEvent) -> Void
    ) async throws -> PiAgentRunResult {
        if self.piBinaryPath == nil {
            self.piBinaryPath = Self.discoverPiBinary(customOverride: self.database.string(forKey: Self.customBinaryConfigKey))
        }
        guard let binaryPath = self.piBinaryPath, FileManager.default.isExecutableFile(atPath: binaryPath) else {
            throw AIError.http(status: 503, message: AppLanguage.text("未找到 pi 可执行文件", en: "pi executable not found"))
        }
        
        _ = try? self.syncWorkspace()
        
        let providerID = Self.providerID(for: endpointProfile)
        let modelID = configuration.model.trimmingCharacters(in: .whitespacesAndNewlines)
        let effectiveThinking = thinkingLevel ?? configuration.reasoningEffort
        let dbPath = self.database.databaseURL.path(percentEncoded: false)
        
        let trackedBot: AIBotID = channel == .butler ? .butler : .readingCompanion
        self.activeBotRuns.insert(trackedBot)
        defer { self.activeBotRuns.remove(trackedBot) }
        
        let request = PiRPCTurnRequest(
            channel: channel,
            binaryPath: binaryPath,
            agentDirectoryURL: self.agentDirectoryURL,
            databasePath: dbPath,
            workspaceConfigStamp: self.workspaceConfigStamp,
            workingDirectoryURL: workingDirectory,
            logicalSessionKey: logicalSessionKey,
            providerID: providerID,
            modelID: modelID,
            thinkingLevel: effectiveThinking,
            systemPrompt: systemPrompt,
            userPrompt: userPrompt,
            priorHistoryContext: priorHistoryContext
        )
        return try await PiRPCRuntime.shared.runTurn(request, onEvent: onEvent)
    }
    
    
    func abortRPCTurn(channel: PiAgentChannel) {
        Task {
            await PiRPCRuntime.shared.abort(channel: channel)
        }
    }
    
    
    func resetRPCSession(channel: PiAgentChannel) {
        Task {
            await PiRPCRuntime.shared.resetSession(channel: channel)
        }
    }
    
    
    func shutdownRPCDaemons() {
        Task {
            await PiRPCRuntime.shared.shutdownAll()
        }
    }
    
    
    // MARK: Interactive Terminal Launch
    
    /// Builds a clean shell command to launch `botID` interactively inside CotEditor's built-in Terminal
    /// using `PiKernel`'s synchronized `models.json`, `auth.json`, session directory, and `SYSTEM.md`.
    func interactiveTerminalCommand(for botID: AIBotID, workingDirectory: URL? = nil) -> String? {
        if self.piBinaryPath == nil {
            self.piBinaryPath = Self.discoverPiBinary(customOverride: self.database.string(forKey: Self.customBinaryConfigKey))
        }
        guard let binaryPath = self.piBinaryPath else { return nil }
        _ = try? self.syncWorkspace()
        
        let endpoints = AIEndpointStore.profiles
        let activeID = AIEndpointStore.activeID ?? endpoints.first?.id
        let botCfg = AIBotStore.shared.config(for: botID)
        let targetEndpoint = botCfg.endpointID.flatMap { id in endpoints.first(where: { $0.id == id }) }
            ?? endpoints.first(where: { $0.id == activeID })
            ?? endpoints.first
        
        let agentDir = self.agentDirectoryURL.path(percentEncoded: false)
        let dbPath = self.database.databaseURL.path(percentEncoded: false)
        let cotToolsFile = self.agentDirectoryURL
            .appending(path: "extensions/\(PiCotToolsExtension.filename)")
            .path(percentEncoded: false)
        let botPromptFile = self.agentDirectoryURL
            .appending(path: "agents/\(botID.rawValue)/SYSTEM.md")
            .path(percentEncoded: false)
        let sessionDir = self.agentDirectoryURL
            .appending(path: "sessions/\(botID.rawValue)")
            .path(percentEncoded: false)
        let toolProfile = botCfg.effectiveToolProfile(for: botID)
        
        var parts: [String] = []
        if let workingDirectory {
            parts.append("cd \(Self.shellQuote(workingDirectory.path(percentEncoded: false))) &&")
        }
        parts.append("PI_CODING_AGENT_DIR=\(Self.shellQuote(agentDir))")
        parts.append("COT_DB_PATH=\(Self.shellQuote(dbPath))")
        parts.append("PI_SKIP_VERSION_CHECK=1")
        parts.append(Self.shellQuote(binaryPath))
        parts.append("-e \(Self.shellQuote(cotToolsFile))")
        
        if let targetEndpoint {
            let pid = Self.providerID(for: targetEndpoint)
            let modelID = botCfg.modelOverride.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? (targetEndpoint.displayModel ?? "")
                : botCfg.modelOverride.trimmingCharacters(in: .whitespacesAndNewlines)
            if !modelID.isEmpty {
                parts.append("--provider \(Self.shellQuote(pid))")
                parts.append("--model \(Self.shellQuote(modelID))")
            }
        }
        parts.append("--session-dir \(Self.shellQuote(sessionDir))")
        parts.append("--append-system-prompt \(Self.shellQuote(botPromptFile))")
        parts.append("--name \(Self.shellQuote("\(botID.displayName) (\(botID.handle))"))")
        for arg in toolProfile.cliArguments {
            parts.append(Self.shellQuote(arg))
        }
        
        return parts.joined(separator: " ")
    }
    
    
    /// Opens the frontmost document window's built-in Terminal (creating a document window if none exists)
    /// and starts `botID` as an interactive `pi` coding/working agent session.
    @discardableResult
    func launchBotInFrontmostTerminal(_ botID: AIBotID) -> Bool {
        let docWindowController = NSApp.orderedWindows
            .compactMap { $0.windowController as? DocumentWindowController }
            .first
        let workingDir = (docWindowController?.documentViewController?.focusedDocument.fileURL
            ?? (NSDocumentController.shared.currentDocument as? NSDocument)?.fileURL)?
            .deletingLastPathComponent()
        
        guard let command = self.interactiveTerminalCommand(for: botID, workingDirectory: workingDir) else {
            return false
        }
        
        if let workspaceVC = docWindowController?.workspaceContentViewController {
            docWindowController?.window?.makeKeyAndOrderFront(nil)
            workspaceVC.launchCommandInTerminal(command)
            return true
        }
        
        // Open a new document window first if none was open
        NSDocumentController.shared.newDocument(nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            if let freshWC = NSApp.orderedWindows.compactMap({ $0.windowController as? DocumentWindowController }).first {
                freshWC.window?.makeKeyAndOrderFront(nil)
                freshWC.workspaceContentViewController?.launchCommandInTerminal(command)
            }
        }
        return true
    }
    
    
    private nonisolated static func shellQuote(_ value: String) -> String {
        if value.isEmpty { return "''" }
        let escaped = value.replacingOccurrences(of: "'", with: "'\\''")
        return "'\(escaped)'"
    }
}
