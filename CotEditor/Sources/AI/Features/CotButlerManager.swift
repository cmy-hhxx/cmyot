//
//  CotButlerManager.swift
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

/// Chief Butler Bot manager: multi-session persisted conversations, custom avatar/name/nickname,
/// multi-bot preference governance, multi-angle KYC memory evolution, and workspace takeover.
@MainActor @Observable
final class CotButlerManager {
    
    static let shared = CotButlerManager()
    static let identityDidChangeNotification = Notification.Name("CotButlerManagerIdentityDidChange")
    
    var name: String {
        didSet {
            guard !self.isSyncingIdentity else { return }
            let trimmed = self.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let resolved = trimmed.isEmpty ? "曜" : trimmed
            self.database.set(resolved, forKey: CotLocalDatabase.ConfigKey.butlerName)
            NotificationCenter.default.post(name: Self.identityDidChangeNotification, object: self)
        }
    }
    
    var nickname: String {
        didSet {
            guard !self.isSyncingIdentity else { return }
            let trimmed = self.nickname.trimmingCharacters(in: .whitespacesAndNewlines)
            let resolved = trimmed.isEmpty ? "总管" : trimmed
            self.database.set(resolved, forKey: CotLocalDatabase.ConfigKey.butlerNickname)
            NotificationCenter.default.post(name: Self.identityDidChangeNotification, object: self)
        }
    }
    
    var avatarVariantIndex: Int? {
        didSet {
            guard !self.isSyncingIdentity else { return }
            let value = self.avatarVariantIndex.map(String.init) ?? ""
            self.database.set(value, forKey: CotLocalDatabase.ConfigKey.butlerAvatarVariant)
            if self.database === CotLocalDatabase.shared {
                var cfg = AIBotStore.shared.config(for: .butler)
                if cfg.artworkVariantIndex != self.avatarVariantIndex {
                    cfg.artworkVariantIndex = self.avatarVariantIndex
                    AIBotStore.shared.updateConfig(cfg, for: .butler)
                }
            }
            NotificationCenter.default.post(name: Self.identityDidChangeNotification, object: self)
        }
    }
    
    private(set) var customAvatarImage: NSImage?
    private(set) var sessions: [ButlerSessionRecord] = []
    private(set) var activeSessionID: String = ""
    private(set) var messages: [ButlerChatMessage] = []
    private(set) var isStreaming: Bool = false
    private(set) var streamingDraft: String = ""
    
    private let database: CotLocalDatabase
    private let memoryStore: CotMemoryStore
    private var dbObserver: (any NSObjectProtocol)?
    private var isSyncingIdentity = false
    
    
    init(
        database: CotLocalDatabase = .shared,
        memoryStore: CotMemoryStore = .shared
    ) {
        self.database = database
        self.memoryStore = memoryStore
        
        let storedName = database.string(forKey: CotLocalDatabase.ConfigKey.butlerName, default: "曜")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        self.name = storedName.isEmpty ? "曜" : storedName
        
        let storedNick = database.string(forKey: CotLocalDatabase.ConfigKey.butlerNickname, default: "总管")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        self.nickname = storedNick.isEmpty ? "总管" : storedNick
        
        let variantRaw = database.string(forKey: CotLocalDatabase.ConfigKey.butlerAvatarVariant)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        self.avatarVariantIndex = Int(variantRaw)
        self.customAvatarImage = Self.decodeAvatarImage(from: database.string(forKey: CotLocalDatabase.ConfigKey.butlerCustomAvatarBase64))
        
        self.bootstrapSessionsAndMessages()
        
        if database === CotLocalDatabase.shared {
            self.dbObserver = NotificationCenter.default.addObserver(
                forName: CotLocalDatabase.structuredAssetsDidChangeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.reloadFromDatabase()
                }
            }
        }
    }
    
    
    isolated deinit {
        if let dbObserver {
            NotificationCenter.default.removeObserver(dbObserver)
        }
    }
    
    
    func reloadFromDatabase() {
        self.isSyncingIdentity = true
        let storedName = self.database.string(forKey: CotLocalDatabase.ConfigKey.butlerName, default: "曜")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedName = storedName.isEmpty ? "曜" : storedName
        if self.name != resolvedName {
            self.name = resolvedName
        }
        
        let storedNick = self.database.string(forKey: CotLocalDatabase.ConfigKey.butlerNickname, default: "总管")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedNick = storedNick.isEmpty ? "总管" : storedNick
        if self.nickname != resolvedNick {
            self.nickname = resolvedNick
        }
        
        let variantRaw = self.database.string(forKey: CotLocalDatabase.ConfigKey.butlerAvatarVariant)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let botVariant = self.database === CotLocalDatabase.shared ? AIBotStore.shared.config(for: .butler).artworkVariantIndex : nil
        self.avatarVariantIndex = Int(variantRaw) ?? botVariant
        self.customAvatarImage = Self.decodeAvatarImage(from: self.database.string(forKey: CotLocalDatabase.ConfigKey.butlerCustomAvatarBase64))
        self.isSyncingIdentity = false
        
        self.bootstrapSessionsAndMessages()
        NotificationCenter.default.post(name: Self.identityDidChangeNotification, object: self)
    }
    
    
    // MARK: - Custom Identity & Artwork
    
    func setCustomAvatarData(_ data: Data?) {
        if let data,
           let rawImage = NSImage(data: data),
           let pngData = UserProfileManager.processedAvatarPNGData(from: rawImage)
        {
            self.database.set(pngData.base64EncodedString(), forKey: CotLocalDatabase.ConfigKey.butlerCustomAvatarBase64)
            self.customAvatarImage = NSImage(data: pngData)
        } else {
            self.database.set("", forKey: CotLocalDatabase.ConfigKey.butlerCustomAvatarBase64)
            self.customAvatarImage = nil
        }
        NotificationCenter.default.post(name: Self.identityDidChangeNotification, object: self)
    }
    
    
    func syncArtworkVariant(_ variantIndex: Int?) {
        self.avatarVariantIndex = variantIndex
    }
    
    
    func cycleAvatarVariant() {
        let count = max(1, self.resolvedCharacter().artworks.count)
        let current = self.avatarVariantIndex ?? 0
        self.avatarVariantIndex = (current + 1) % count
    }
    
    
    func resolvedCharacter() -> AIGijinkaCharacter {
        let botCfg = AIBotStore.shared.config(for: .butler)
        let endpoint = AIBotStore.shared.resolvedEndpointProfile(for: .butler)
        let overrideModel = botCfg.modelOverride.trimmingCharacters(in: .whitespacesAndNewlines)
        return AIGijinkaCharacter.resolve(
            modelName: overrideModel.isEmpty ? endpoint?.displayModel : overrideModel,
            endpointName: endpoint?.displayName,
            baseURL: endpoint?.baseURL
        ) ?? .deepseek
    }
    
    
    func resolvedArtwork() -> AIGijinkaArtwork {
        let variant = self.avatarVariantIndex ?? AIBotStore.shared.config(for: .butler).artworkVariantIndex
        return self.resolvedCharacter().artwork(for: .butler, variantOverride: variant)
    }
    
    
    private static func decodeAvatarImage(from base64: String) -> NSImage? {
        let trimmed = base64.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let data = Data(base64Encoded: trimmed) else { return nil }
        return NSImage(data: data)
    }
    
    
    // MARK: - Session Management
    
    private func bootstrapSessionsAndMessages() {
        var loaded = self.database.fetchButlerSessions()
        if loaded.isEmpty {
            let initial = self.database.createButlerSession(title: AppLanguage.text("新对话", en: "New Chat"))
            loaded = [initial]
        }
        self.sessions = loaded
        
        let savedActive = self.database.string(forKey: CotLocalDatabase.ConfigKey.butlerActiveSessionID)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !savedActive.isEmpty, loaded.contains(where: { $0.id == savedActive }) {
            self.activeSessionID = savedActive
        } else {
            self.activeSessionID = loaded.first?.id ?? ""
            self.database.set(self.activeSessionID, forKey: CotLocalDatabase.ConfigKey.butlerActiveSessionID)
        }
        self.messages = self.database.fetchButlerMessages(sessionID: self.activeSessionID)
    }
    
    
    func startNewSession() {
        // Reuse an empty active session rather than cluttering history with empty rows
        if let active = self.sessions.first(where: { $0.id == self.activeSessionID }),
           self.messages.isEmpty,
           active.messageCount == 0
        {
            return
        }
        let created = self.database.createButlerSession(title: AppLanguage.text("新对话", en: "New Chat"))
        self.activeSessionID = created.id
        self.database.set(created.id, forKey: CotLocalDatabase.ConfigKey.butlerActiveSessionID)
        self.sessions = self.database.fetchButlerSessions()
        self.messages = []
    }
    
    
    func selectSession(_ sessionID: String) {
        guard self.activeSessionID != sessionID,
              self.sessions.contains(where: { $0.id == sessionID })
        else { return }
        self.activeSessionID = sessionID
        self.database.set(sessionID, forKey: CotLocalDatabase.ConfigKey.butlerActiveSessionID)
        self.messages = self.database.fetchButlerMessages(sessionID: sessionID)
    }
    
    
    func renameSession(_ sessionID: String, to title: String) {
        self.database.renameButlerSession(id: sessionID, title: title)
        self.sessions = self.database.fetchButlerSessions()
    }
    
    
    func togglePinSession(_ sessionID: String) {
        guard let session = self.sessions.first(where: { $0.id == sessionID }) else { return }
        self.database.toggleButlerSessionPinned(id: sessionID, isPinned: !session.isPinned)
        self.sessions = self.database.fetchButlerSessions()
    }
    
    
    func deleteSession(_ sessionID: String) {
        self.database.deleteButlerSession(id: sessionID)
        var remaining = self.database.fetchButlerSessions()
        if remaining.isEmpty {
            let fresh = self.database.createButlerSession(title: AppLanguage.text("新对话", en: "New Chat"))
            remaining = [fresh]
        }
        self.sessions = remaining
        if self.activeSessionID == sessionID || !remaining.contains(where: { $0.id == self.activeSessionID }) {
            self.activeSessionID = remaining.first?.id ?? ""
            self.database.set(self.activeSessionID, forKey: CotLocalDatabase.ConfigKey.butlerActiveSessionID)
        }
        self.messages = self.database.fetchButlerMessages(sessionID: self.activeSessionID)
    }
    
    
    func clearCurrentSession() {
        guard !self.activeSessionID.isEmpty else { return }
        self.database.clearButlerMessages(sessionID: self.activeSessionID)
        self.messages = []
        self.sessions = self.database.fetchButlerSessions()
    }
    
    
    func clearConversation() {
        self.clearCurrentSession()
    }
    
    
    func applyGlobalPersonaToAllBots(_ persona: String, clearPerBotOverrides: Bool = true) {
        let clean = persona.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        self.database.aiPersona = clean
        if clearPerBotOverrides {
            for botID in AIBotID.allCases {
                var cfg = AIBotStore.shared.config(for: botID)
                if !cfg.customPersona.isEmpty {
                    cfg.customPersona = ""
                    AIBotStore.shared.updateConfig(cfg, for: botID)
                }
            }
        }
        if self.database === CotLocalDatabase.shared {
            _ = try? PiKernelManager.shared.syncWorkspace()
        }
    }
    
    
    // MARK: - Conversation & Takeover Execution
    
    func sendMessage(_ rawText: String) async {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !self.isStreaming else { return }
        
        if self.activeSessionID.isEmpty {
            self.bootstrapSessionsAndMessages()
        }
        let targetSessionID = self.activeSessionID
        
        let userMsg = ButlerChatMessage(
            id: UUID().uuidString,
            sessionID: targetSessionID,
            role: "user",
            content: text,
            actionsJSON: "[]",
            createdAt: Date()
        )
        self.database.appendButlerMessage(userMsg)
        self.messages.append(userMsg)
        self.sessions = self.database.fetchButlerSessions()
        
        let resolvedConfig = AIBotStore.shared.resolvedConfiguration(for: .butler)
        guard resolvedConfig.isUsable else {
            await self.handleOfflineCommand(text, sessionID: targetSessionID)
            return
        }
        
        self.isStreaming = true
        self.streamingDraft = ""
        defer {
            self.isStreaming = false
            self.streamingDraft = ""
        }
        
        let systemPrompt = self.buildButlerSystemPrompt(
            resolvedConfig: resolvedConfig,
            userMessage: text
        )
        var aiMessages: [AIMessage] = [.system(systemPrompt)]
        for turn in self.messages.suffix(12) {
            if turn.role == "assistant" {
                aiMessages.append(AIMessage(role: .assistant, text: turn.content))
            } else {
                aiMessages.append(.user(turn.content))
            }
        }
        
        var lastDraftFlushAt: Date = .distantPast
        do {
            let fullRaw = try await AIService.shared.chat(
                aiMessages,
                configuration: resolvedConfig,
                analyticsFeature: "butler"
            ) { [weak self] partial in
                let now = Date()
                guard now.timeIntervalSince(lastDraftFlushAt) >= 0.06 else { return }
                lastDraftFlushAt = now
                self?.streamingDraft = Self.stripActionEnvelope(partial)
            }
            
            let extracted = Self.extractActions(from: fullRaw)
            let receipts = await CotAgentCoordinator.shared.execute(extracted.actions)
            let receiptsJSON = (try? String(data: JSONEncoder().encode(receipts), encoding: .utf8)) ?? "[]"
            let replyText = extracted.cleanText.isEmpty
                ? (receipts.isEmpty ? "已处理。" : receipts.map(\.summary).joined(separator: " · "))
                : extracted.cleanText
            
            let assistantMsg = ButlerChatMessage(
                id: UUID().uuidString,
                sessionID: targetSessionID,
                role: "assistant",
                content: replyText,
                actionsJSON: receiptsJSON,
                createdAt: Date()
            )
            self.database.appendButlerMessage(assistantMsg)
            if self.activeSessionID == targetSessionID {
                self.messages.append(assistantMsg)
            }
            self.sessions = self.database.fetchButlerSessions()
        } catch {
            let errMsg = ButlerChatMessage(
                id: UUID().uuidString,
                sessionID: targetSessionID,
                role: "assistant",
                content: error.localizedDescription,
                actionsJSON: "[]",
                createdAt: Date()
            )
            self.database.appendButlerMessage(errMsg)
            if self.activeSessionID == targetSessionID {
                self.messages.append(errMsg)
            }
            self.sessions = self.database.fetchButlerSessions()
        }
    }
    
    
    private func handleOfflineCommand(_ text: String, sessionID: String) async {
        var actions: [CotAgentAction] = []
        let lower = text.lowercased()
        
        if let range = text.range(of: "以后叫你") ?? text.range(of: "改名叫") {
            let newName = text[range.upperBound...].trimmingCharacters(in: CharacterSet(charactersIn: " ：:，,。!！\"'"))
            if !newName.isEmpty {
                actions.append(CotAgentAction(type: "rename_butler", name: newName))
            }
        } else if lower.contains("看盘") || lower.contains("k线") || lower.contains("股票") {
            let query = text
                .replacingOccurrences(of: "看盘", with: "")
                .replacingOccurrences(of: "打开", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            actions.append(CotAgentAction(type: "convert_tab", board: "market", query: query))
        } else if lower.contains("播客") {
            let query = text
                .replacingOccurrences(of: "播客", with: "")
                .replacingOccurrences(of: "打开", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            actions.append(CotAgentAction(type: "convert_tab", board: "podcast", query: query))
        } else if lower.contains("news") || lower.contains("新闻") || lower.contains("资讯") {
            actions.append(CotAgentAction(type: "convert_tab", board: "news"))
        } else if text.contains("@") {
            let tokens = text.split(separator: " ").map(String.init)
            if let handle = tokens.first(where: { $0.hasPrefix("@") }) {
                actions.append(CotAgentAction(type: "follow_creator", platform: "x", handle: handle))
            }
        }
        
        let receipts = await CotAgentCoordinator.shared.execute(actions)
        let receiptsJSON = (try? String(data: JSONEncoder().encode(receipts), encoding: .utf8)) ?? "[]"
        let reply = receipts.isEmpty
            ? AppLanguage.text("请先在设置中为总管接入 API 订阅", en: "Configure API gateway for Butler in Settings")
            : receipts.map(\.summary).joined(separator: " · ")
        
        let assistantMsg = ButlerChatMessage(
            id: UUID().uuidString,
            sessionID: sessionID,
            role: "assistant",
            content: reply,
            actionsJSON: receiptsJSON,
            createdAt: Date()
        )
        self.database.appendButlerMessage(assistantMsg)
        if self.activeSessionID == sessionID {
            self.messages.append(assistantMsg)
        }
        self.sessions = self.database.fetchButlerSessions()
    }
    
    
    private static let localClockFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy年M月d日 EEEE HH:mm (ZZZZ)"
        return formatter
    }()
    
    
    func buildButlerSystemPrompt(
        resolvedConfig: AIConfiguration? = nil,
        userMessage: String = "",
        now: Date = Date()
    ) -> String {
        let workspaceSummary = CotAgentCoordinator.shared.workspaceContextSummary()
        let kyc = self.memoryStore.compiledKYCContext()
        let globalPersona = self.database.aiPersona.trimmingCharacters(in: .whitespacesAndNewlines)
        let butlerCfg = AIBotStore.shared.config(for: .butler)
        let customPersona = butlerCfg.customPersona.trimmingCharacters(in: .whitespacesAndNewlines)
        let stagePrompt = AIBotStore.shared.systemPrompt(for: .butler).trimmingCharacters(in: .whitespacesAndNewlines)
        let activeModel = resolvedConfig?.model.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let timeString = Self.localClockFormatter.string(from: now)
        
        let lowerMsg = userMessage.lowercased()
        let botManagementKeywords = [
            "bot", "助手", "续写", "翻译", "提炼", "解释", "周报", "图表",
            "识图", "整理", "人设", "风格", "全局", "性格", "调教", "切换模型", "换模型",
        ]
        let includeBotRoster = botManagementKeywords.contains { lowerMsg.contains($0) }
        
        var lines: [String] = [
            "你是用户在 CotEditor 里的私人助手「\(self.name)」（昵称「@\(self.nickname)」）。",
            "当前本地时间：\(timeString)",
        ]
        if !activeModel.isEmpty {
            lines.append("你当前使用的模型：\(activeModel)")
        }
        if !customPersona.isEmpty {
            lines.append("用户为你设定的风格：\(customPersona)")
        }
        if !stagePrompt.isEmpty {
            lines.append("补充要求：\(stagePrompt)")
        }
        
        lines.append("""
        
        ## 说话方式（非常重要）
        - 用自然、顺耳、好懂的日常中文聊天，像一个靠谱又好相处的个人助理；不要端着、不要装酷冷漠，也不要油腻客套。
        - 问什么答什么，直截了当：
          - 用户问现在几点、今天星期几，直接根据上面的「当前本地时间」回答。
          - 用户打招呼（如 hi / 你好 / 在吗），自然打个招呼并顺手问有什么可以帮忙的即可。
          - 用户问你是什么模型，直接说你当前使用的模型名称即可，不要主动扯出其他助手或一堆配置。
        - 严禁在给用户看的回复里说内部技术黑话：绝对不要出现「工作区」「编队」「KYC」「SQLite」「数据库」「兴趣资产」「时间戳」「状态栏」「Action」「JSON」「<cot_actions>」以及英文内部ID（如 `ghost`、`butler`、`ocrPolish`、`weeklyReportItem`）。如果确实需要提到其他功能，请用通俗中文名称（如「续写幽灵」「双语翻译官」「周报搭子」）。
        - 简单问题一两句答清楚，复杂问题再条理清晰地展开。

        ## 帮用户执行操作（仅在需要时使用）
        - 只有当用户明确表达了需要你执行操作（例如：打开看盘/播客/资讯、新建文档、给你改名字、记住某个偏好或禁忌、关注股票/博客/X 账号、调整某个助手的开关/风格/模型）时，才在回复末尾附带 `<cot_actions>[...]</cot_actions>` JSON 数组，系统会自动执行。
        - 普通闲聊、问答、查时间、问模型时，不要输出 `<cot_actions>`，也不要向用户提及这个标签。

        可用操作格式（仅放在 `<cot_actions>[...]</cot_actions>` 中）：
        - `{"type":"convert_tab","board":"market|podcast|news|document","query":"可选关键词"}`
        - `{"type":"open_board","board":"market|podcast|news","query":"可选关键词","splitRight":true}`
        - `{"type":"open_document","title":"标题","content":"Markdown内容","splitRight":false}`
        - `{"type":"rename_butler","name":"新名字","nickname":"新昵称"}`
        - `{"type":"update_global_persona","prompt":"同步给全部助手的新风格"}`
        - `{"type":"update_bot","botID":"butler|ghost|translate|summarize|explain|weeklyReport|weeklyReportItem|interactiveChart|ocrPolish|organizeAndMerge|readingCompanion|persona","isEnabled":true,"persona":"可选自定义风格","modelOverride":"可选模型"}`
        - `{"type":"upsert_memory","dimension":"identity|cognition|writingStyle|goals|finance|informationDiet|workflow|taboos","key":"英文唯一键","title":"简短要点","detail":"补充说明","isPinned":false}`
        - `{"type":"delete_memory","keyOrID":"id或key"}`
        - `{"type":"watch_stock","query":"如 恒生科技 / 00700 / NVDA","thesis":"关注理由"}`
        - `{"type":"unwatch_stock","symbolOrID":"代码或id"}`
        - `{"type":"follow_feed","title":"博客名称","siteURL":"https://...","feedURL":"可选RSS","category":"可选分类"}`
        - `{"type":"follow_creator","platform":"x","handle":"@username","displayName":"显示名","why":"关注原因"}`
        - `{"type":"play_podcast","query":"搜索关键词或播客链接"}`
        """)
        
        if !globalPersona.isEmpty {
            lines.append("## 用户的全局回复偏好\n\(globalPersona)")
        }
        if includeBotRoster {
            let botLines = AIBotID.allCases.map { botID -> String in
                let cfg = AIBotStore.shared.config(for: botID)
                let displayName = AIBotStore.shared.resolvedName(for: botID)
                let status = cfg.isEnabled ? "已开启" : "已关闭"
                let model = cfg.modelOverride.isEmpty ? "跟随默认模型" : cfg.modelOverride
                return "- \(displayName)（内部ID: \(botID.rawValue)）：\(status)，模型：\(model)"
            }.joined(separator: "\n")
            lines.append("## 全部助手配置（回复用户时一律使用中文名，不要说出内部ID）\n\(botLines)")
        }
        if !kyc.isEmpty {
            lines.append(kyc)
        }
        if !workspaceSummary.isEmpty {
            lines.append("## 用户当前正在看的文档与页面（仅供背景参考）\n\(workspaceSummary)")
        }
        
        return lines.joined(separator: "\n\n")
    }
    
    
    // MARK: - Action Tag Extraction
    
    static func stripActionEnvelope(_ raw: String) -> String {
        if let open = raw.range(of: "<cot_actions>") {
            return String(raw[..<open.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    
    static func extractActions(from raw: String) -> (cleanText: String, actions: [CotAgentAction]) {
        guard let start = raw.range(of: "<cot_actions>"),
              let end = raw.range(of: "</cot_actions>", range: start.upperBound..<raw.endIndex)
        else {
            return (Self.stripActionEnvelope(raw), [])
        }
        let jsonBody = String(raw[start.upperBound..<end.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let before = String(raw[..<start.lowerBound])
        let after = String(raw[end.upperBound...])
        let cleanText = (before + "\n" + after).trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard let data = jsonBody.data(using: .utf8),
              let actions = try? JSONDecoder().decode([CotAgentAction].self, from: data)
        else {
            return (cleanText, [])
        }
        return (cleanText, actions)
    }
    
    
    static func decodeReceipts(from json: String) -> [AppliedActionReceipt] {
        guard !json.isEmpty,
              let data = json.data(using: .utf8),
              let receipts = try? JSONDecoder().decode([AppliedActionReceipt].self, from: data)
        else { return [] }
        return receipts
    }
}
