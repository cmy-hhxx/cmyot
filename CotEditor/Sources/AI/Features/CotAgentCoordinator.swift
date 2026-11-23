//
//  CotAgentCoordinator.swift
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

/// Structured action payload emitted by the Butler Bot or external `pi` CLI via `agent_command_queue`
/// to control CotEditor panes, boards, Bot fleet preferences, KYC memory, and user assets.
nonisolated struct CotAgentAction: Codable, Sendable, Equatable {
    
    var type: String
    var board: String? = nil
    var query: String? = nil
    var splitRight: Bool? = nil
    var title: String? = nil
    var content: String? = nil
    var name: String? = nil
    var nickname: String? = nil
    var prompt: String? = nil
    var botID: String? = nil
    var isEnabled: Bool? = nil
    var persona: String? = nil
    var modelOverride: String? = nil
    var dimension: String? = nil
    var key: String? = nil
    var detail: String? = nil
    var isPinned: Bool? = nil
    var keyOrID: String? = nil
    var thesis: String? = nil
    var symbolOrID: String? = nil
    var siteURL: String? = nil
    var feedURL: String? = nil
    var category: String? = nil
    var platform: String? = nil
    var handle: String? = nil
    var displayName: String? = nil
    var why: String? = nil
}


/// Compact visual receipt shown inline beneath Butler replies for each executed action.
nonisolated struct AppliedActionReceipt: Codable, Identifiable, Sendable, Equatable {
    
    var id: String = UUID().uuidString
    var symbolName: String
    var summary: String
}


/// Live snapshot of open CotEditor windows, panes, tabs, and boards serialized to SQLite
/// so `pi` and the Butler always perceive what the user is working on right now.
nonisolated struct LiveWorkspaceSnapshot: Codable, Sendable, Equatable {
    
    struct PaneTabSummary: Codable, Sendable, Equatable {
        var title: String
        var isSelected: Bool
        var boardKind: String?
        var boardQuery: String?
        var syntax: String
        var excerpt: String
    }
    
    struct PaneSummary: Codable, Sendable, Equatable {
        var paneIndex: Int
        var isFocused: Bool
        var tabs: [PaneTabSummary]
    }
    
    struct WindowSummary: Codable, Sendable, Equatable {
        var isMain: Bool
        var panes: [PaneSummary]
    }
    
    var capturedAt: Date
    var butlerName: String
    var butlerNickname: String
    var windows: [WindowSummary]
    var activeDocumentTitle: String?
    var activeDocumentExcerpt: String?
    var activePodcastTitle: String?
    var activeMarketInstrument: String?
}


/// Coordinates live editor perception (`workspace_live_state`), SQLite command queue polling
/// (`agent_command_queue`), and in-app action execution across panes, boards, bots, and KYC memory.
@MainActor @Observable
final class CotAgentCoordinator {
    
    static let shared = CotAgentCoordinator()
    
    private let database: CotLocalDatabase
    private let memoryStore: CotMemoryStore
    private var pollTask: Task<Void, Never>?
    private(set) var lastWorkspaceSnapshot: LiveWorkspaceSnapshot?
    
    
    init(
        database: CotLocalDatabase = .shared,
        memoryStore: CotMemoryStore = .shared
    ) {
        self.database = database
        self.memoryStore = memoryStore
        
        if !CotLocalDatabase.isRunningUnitTests, database === CotLocalDatabase.shared {
            self.startCommandQueueLoop()
        }
    }
    
    
    isolated deinit {
        self.pollTask?.cancel()
    }
    
    
    // MARK: - Live Workspace Perception
    
    /// Captures the live state of open windows, panes, tabs, and active media into SQLite `workspace_live_state`.
    @discardableResult
    func captureWorkspaceSnapshot() -> LiveWorkspaceSnapshot {
        let windows: [LiveWorkspaceSnapshot.WindowSummary] = NSApp?.orderedWindows.compactMap { window in
            guard let docVC = (window.windowController as? DocumentWindowController)?.documentViewController else {
                return nil
            }
            let focusedEditor = docVC.focusedEditorViewController
            let panes = docVC.editorViewControllers.enumerated().map { idx, editorVC in
                let tabs = editorVC.tabs.map { tab in
                    let rawText = tab.document.textStorage.string
                    return LiveWorkspaceSnapshot.PaneTabSummary(
                        title: tab.title,
                        isSelected: tab === editorVC.selectedTab,
                        boardKind: tab.boardState?.kind.rawValue,
                        boardQuery: tab.boardState?.query,
                        syntax: tab.document.syntaxName,
                        excerpt: tab.isBoard ? "" : String(rawText.prefix(240))
                    )
                }
                return LiveWorkspaceSnapshot.PaneSummary(
                    paneIndex: idx,
                    isFocused: editorVC === focusedEditor,
                    tabs: tabs
                )
            }
            return LiveWorkspaceSnapshot.WindowSummary(isMain: window.isMainWindow, panes: panes)
        } ?? []
        
        let frontDocVC = Self.activeDocumentViewController()
        let activeTab = frontDocVC?.focusedEditorViewController?.selectedTab
        let activeExcerpt = activeTab.flatMap { tab -> String? in
            guard !tab.isBoard else { return nil }
            let text = tab.document.textStorage.string.trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : String(text.prefix(1200))
        }
        
        let butlerName = self.database.string(forKey: CotLocalDatabase.ConfigKey.butlerName, default: "曜")
        let butlerNick = self.database.string(forKey: CotLocalDatabase.ConfigKey.butlerNickname, default: "总管")
        
        let snapshot = LiveWorkspaceSnapshot(
            capturedAt: Date(),
            butlerName: butlerName.isEmpty ? "曜" : butlerName,
            butlerNickname: butlerNick.isEmpty ? "总管" : butlerNick,
            windows: windows,
            activeDocumentTitle: activeTab?.title,
            activeDocumentExcerpt: activeExcerpt,
            activePodcastTitle: CotPodcastService.shared.currentEpisode?.title,
            activeMarketInstrument: CotMarketService.shared.selectedInstrumentName
        )
        self.lastWorkspaceSnapshot = snapshot
        
        if let data = try? JSONEncoder().encode(snapshot),
           let json = String(data: data, encoding: .utf8)
        {
            self.database.saveWorkspaceLiveState(slot: "active_workspace", payloadJSON: json)
        }
        return snapshot
    }
    
    
    func workspaceContextSummary() -> String {
        let snap = self.captureWorkspaceSnapshot()
        var lines: [String] = []
        if let title = snap.activeDocumentTitle {
            lines.append("当前焦点标签：\(title)")
        }
        if let excerpt = snap.activeDocumentExcerpt, !excerpt.isEmpty {
            lines.append("当前文档摘录：\n\(String(excerpt.prefix(800)))")
        }
        let openTitles = snap.windows.flatMap(\.panes).flatMap(\.tabs).map { tab in
            if let kind = tab.boardKind {
                return "[\(kind)] \(tab.title)"
            }
            return tab.title
        }
        if !openTitles.isEmpty {
            lines.append("打开的窗格标签：" + openTitles.prefix(10).joined(separator: " | "))
        }
        if let podcast = snap.activePodcastTitle {
            lines.append("正在播放播客：\(podcast)")
        }
        if let market = snap.activeMarketInstrument {
            lines.append("当前看盘标的：\(market)")
        }
        return lines.joined(separator: "\n")
    }
    
    
    // MARK: - Action Execution
    
    func execute(_ actions: [CotAgentAction]) async -> [AppliedActionReceipt] {
        var receipts: [AppliedActionReceipt] = []
        
        for action in actions {
            if let receipt = await self.executeSingle(action) {
                receipts.append(receipt)
            }
        }
        
        if !receipts.isEmpty && self.database === CotLocalDatabase.shared {
            _ = try? PiKernelManager.shared.syncWorkspace()
            _ = self.captureWorkspaceSnapshot()
        }
        return receipts
    }
    
    
    private func executeSingle(_ action: CotAgentAction) async -> AppliedActionReceipt? {
        switch action.type {
            case "convert_tab":
                let boardRaw = (action.board ?? "").lowercased()
                if boardRaw == "document" {
                    if let docVC = Self.activeDocumentViewController(),
                       let pane = docVC.focusedEditorViewController
                    {
                        docVC.revertBoardToDocument(pane.selectedTab, in: pane)
                        return AppliedActionReceipt(symbolName: "doc.text", summary: pane.selectedTab.title)
                    }
                    return nil
                }
                guard let kind = PaneBoardKind(rawValue: boardRaw) else { return nil }
                if let docVC = Self.activeDocumentViewController(),
                   let pane = docVC.focusedEditorViewController
                {
                    docVC.convertTab(pane.selectedTab, to: kind, in: pane, explicitQuery: action.query)
                    let label = action.query?.isEmpty == false ? action.query! : kind.title
                    return AppliedActionReceipt(symbolName: kind.symbolName, summary: label)
                }
                return nil
                
            case "open_board":
                guard let kind = (action.board?.lowercased()).flatMap(PaneBoardKind.init(rawValue:)) else {
                    return nil
                }
                if let docVC = Self.activeDocumentViewController(),
                   let pane = docVC.focusedEditorViewController
                {
                    docVC.openNewBoardTab(kind, in: pane, explicitQuery: action.query, splitRight: action.splitRight == true)
                    let label = action.query?.isEmpty == false ? action.query! : kind.title
                    return AppliedActionReceipt(symbolName: kind.symbolName, summary: label)
                }
                return nil
                
            case "open_document":
                if let docVC = Self.activeDocumentViewController() {
                    let title = action.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    let content = action.content ?? ""
                    docVC.openNewDocumentTab(
                        title: title.isEmpty ? "笔记" : title,
                        content: content,
                        splitRight: action.splitRight == true
                    )
                    return AppliedActionReceipt(symbolName: "doc.text", summary: title.isEmpty ? "新建文档" : title)
                }
                return nil
                
            case "rename_butler":
                let newName = action.name?.trimmingCharacters(in: .whitespacesAndNewlines)
                let newNick = action.nickname?.trimmingCharacters(in: .whitespacesAndNewlines)
                if let newName, !newName.isEmpty {
                    self.database.set(newName, forKey: CotLocalDatabase.ConfigKey.butlerName)
                }
                if let newNick, !newNick.isEmpty {
                    self.database.set(newNick, forKey: CotLocalDatabase.ConfigKey.butlerNickname)
                }
                if self.database === CotLocalDatabase.shared {
                    CotButlerManager.shared.reloadFromDatabase()
                }
                let shown = [newName, newNick].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
                return shown.isEmpty ? nil : AppliedActionReceipt(symbolName: "person.crop.circle.badge.checkmark", summary: shown)
                
            case "update_global_persona":
                let prompt = (action.prompt ?? action.persona ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                guard !prompt.isEmpty else { return nil }
                self.database.aiPersona = prompt
                return AppliedActionReceipt(symbolName: "sparkles", summary: AppLanguage.text("众 Bot 人设已同步", en: "All Bots Updated"))
                
            case "update_bot":
                guard let rawID = action.botID?.trimmingCharacters(in: .whitespacesAndNewlines),
                      let botID = AIBotID(rawValue: rawID)
                else { return nil }
                let botStore = AIBotStore.shared
                var cfg = botStore.config(for: botID)
                if let enabled = action.isEnabled { cfg.isEnabled = enabled }
                if let persona = action.persona { cfg.customPersona = persona.trimmingCharacters(in: .whitespacesAndNewlines) }
                if let model = action.modelOverride { cfg.modelOverride = model.trimmingCharacters(in: .whitespacesAndNewlines) }
                botStore.updateConfig(cfg, for: botID)
                return AppliedActionReceipt(symbolName: botID.symbolName, summary: botID.displayName)
                
            case "upsert_memory":
                let dim = (action.dimension).flatMap(KYCDimension.init(rawValue:)) ?? .cognition
                let title = (action.title ?? action.key ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                let key = (action.key ?? title).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !title.isEmpty, !key.isEmpty else { return nil }
                self.memoryStore.upsertMemory(
                    dimension: dim,
                    factKey: key,
                    title: title,
                    detail: action.detail ?? "",
                    confidence: 0.92,
                    source: "butler",
                    isPinned: action.isPinned,
                    actorBot: "Butler"
                )
                return AppliedActionReceipt(symbolName: dim.symbolName, summary: "\(dim.label) · \(title)")
                
            case "delete_memory":
                guard let keyOrID = action.keyOrID?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !keyOrID.isEmpty
                else { return nil }
                self.memoryStore.deleteMemory(idOrKey: keyOrID)
                return AppliedActionReceipt(symbolName: "trash", summary: keyOrID)
                
            case "watch_stock":
                let q = (action.query ?? action.symbolOrID ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                guard !q.isEmpty else { return nil }
                if let record = await CotMarketService.shared.resolveAndWatch(query: q, thesis: action.thesis ?? "", addedBy: "butler", database: self.database, memoryStore: self.memoryStore) {
                    return AppliedActionReceipt(symbolName: "chart.xyaxis.line", summary: "\(record.name) (\(record.symbol))")
                }
                return nil
                
            case "unwatch_stock":
                let target = (action.symbolOrID ?? action.query ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                guard !target.isEmpty else { return nil }
                self.memoryStore.removeStock(instrumentIDOrSymbol: target)
                return AppliedActionReceipt(symbolName: "chart.xyaxis.line", summary: target)
                
            case "follow_feed":
                let site = (action.siteURL ?? action.query ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                let title = (action.title ?? site).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !title.isEmpty else { return nil }
                self.memoryStore.addOrUpdateFeed(
                    title: title,
                    siteURL: site,
                    feedURL: action.feedURL ?? "",
                    category: action.category ?? "",
                    notes: action.detail ?? "",
                    addedBy: "butler"
                )
                return AppliedActionReceipt(symbolName: "doc.richtext", summary: title)
                
            case "follow_creator":
                let handle = (action.handle ?? action.query ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                guard !handle.isEmpty else { return nil }
                self.memoryStore.addOrUpdateCreator(
                    platform: action.platform ?? "x",
                    handle: handle,
                    displayName: action.displayName ?? "",
                    whyFollowing: action.why ?? action.detail ?? "",
                    addedBy: "butler"
                )
                let normalized = handle.hasPrefix("@") ? handle : "@\(handle)"
                return AppliedActionReceipt(symbolName: "at", summary: normalized)
                
            case "play_podcast":
                let q = (action.query ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                guard !q.isEmpty else { return nil }
                if let docVC = Self.activeDocumentViewController(),
                   let pane = docVC.focusedEditorViewController
                {
                    docVC.openNewBoardTab(.podcast, in: pane, explicitQuery: q, splitRight: action.splitRight == true)
                } else {
                    await CotPodcastService.shared.searchAndRecommend(for: [q], autoplayFirst: true)
                }
                return AppliedActionReceipt(symbolName: "waveform", summary: q)
                
            default:
                return nil
        }
    }
    
    
    // MARK: - SQLite Command Queue Loop (External Pi Takeover)
    
    private func startCommandQueueLoop() {
        self.pollTask?.cancel()
        self.pollTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(1200))
                guard !Task.isCancelled else { break }
                await self?.drainCommandQueueNow()
            }
        }
    }
    
    
    /// Executes all pending rows in SQLite `agent_command_queue` and marks them executed.
    func drainCommandQueueNow() async {
        let pending = self.database.fetchPendingAgentCommands(limit: 20)
        guard !pending.isEmpty else { return }
        
        for cmd in pending {
            var decoded: CotAgentAction?
            if let data = cmd.payloadJSON.data(using: .utf8),
               var action = try? JSONDecoder().decode(CotAgentAction.self, from: data)
            {
                if action.type.isEmpty {
                    action.type = cmd.actionType
                }
                decoded = action
            } else if let data = cmd.payloadJSON.data(using: .utf8),
                      let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            {
                var merged = dict
                merged["type"] = merged["type"] ?? cmd.actionType
                if let normalizedData = try? JSONSerialization.data(withJSONObject: merged) {
                    decoded = try? JSONDecoder().decode(CotAgentAction.self, from: normalizedData)
                }
            }
            
            if let action = decoded {
                let receipts = await self.execute([action])
                let note = receipts.map(\.summary).joined(separator: ", ")
                self.database.markAgentCommandExecuted(id: cmd.id, status: "executed", resultNote: note)
            } else {
                self.database.markAgentCommandExecuted(id: cmd.id, status: "ignored", resultNote: "invalid_payload")
            }
        }
    }
    
    
    private static func activeDocumentViewController() -> DocumentViewController? {
        if let mainWC = NSApp?.mainWindow?.windowController as? DocumentWindowController,
           let docVC = mainWC.documentViewController
        {
            return docVC
        }
        return NSApp?.orderedWindows.lazy
            .compactMap { ($0.windowController as? DocumentWindowController)?.documentViewController }
            .first
    }
}
