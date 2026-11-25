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
import Darwin
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
    var text: String? = nil
    var replaceSelection: Bool? = nil
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
    var activeDocumentSelection: String? = nil
    var activePodcastTitle: String?
    var activeMarketInstrument: String?
}


/// Coordinates live editor perception (`workspace_live_state`), SQLite command queue polling
/// (`agent_command_queue`), and in-app action execution across panes, boards, bots, and KYC memory.
@MainActor @Observable
final class CotAgentCoordinator {
    
    private struct DBFileSignature: Equatable {
        var dbMtimeSec: Int
        var dbMtimeNsec: Int
        var dbSize: off_t
        var walMtimeSec: Int
        var walMtimeNsec: Int
        var walSize: off_t
    }
    
    static let shared = CotAgentCoordinator()
    
    private let database: CotLocalDatabase
    private let memoryStore: CotMemoryStore
    private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var activationObserver: NSObjectProtocol?
    @ObservationIgnored private var lastPolledDBSignature: DBFileSignature?
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
        if let observer = self.activationObserver {
            NotificationCenter.default.removeObserver(observer)
        }
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
                    let excerpt: String
                    if tab.isBoard {
                        excerpt = ""
                    } else {
                        let ns = tab.document.textStorage.mutableString as NSString
                        let range = ns.rangeOfComposedCharacterSequences(for: NSRange(location: 0, length: min(ns.length, 240)))
                        excerpt = ns.substring(with: range)
                    }
                    return LiveWorkspaceSnapshot.PaneTabSummary(
                        title: tab.title,
                        isSelected: tab === editorVC.selectedTab,
                        boardKind: tab.boardState?.kind.rawValue,
                        boardQuery: tab.boardState?.query,
                        syntax: tab.document.syntaxName,
                        excerpt: excerpt
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
        let activeSelection: String? = {
            guard activeTab?.isBoard != true,
                  let sel = frontDocVC?.focusedTextView?.selectedString.trimmingCharacters(in: .whitespacesAndNewlines),
                  !sel.isEmpty
            else { return nil }
            return String(sel.prefix(1500))
        }()
        let activeExcerpt = activeTab.flatMap { tab -> String? in
            guard !tab.isBoard else { return nil }
            let ns = tab.document.textStorage.mutableString as NSString
            guard ns.length > 0 else { return nil }
            let range = ns.rangeOfComposedCharacterSequences(for: NSRange(location: 0, length: min(ns.length, 3200)))
            let text = ns.substring(with: range).trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : String(text.prefix(2800))
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
            activeDocumentSelection: activeSelection,
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
            lines.append("正在编辑的文档：\(title)")
        }
        if let selection = snap.activeDocumentSelection, !selection.isEmpty {
            lines.append("当前选中文本：\n\(String(selection.prefix(800)))")
        }
        if let excerpt = snap.activeDocumentExcerpt, !excerpt.isEmpty {
            lines.append("当前文档摘录：\n\(String(excerpt.prefix(1200)))")
        }
        let openTitles = snap.windows.flatMap(\.panes).flatMap(\.tabs).map { tab in
            if let kind = tab.boardKind {
                return "[\(kind)] \(tab.title)"
            }
            return tab.title
        }
        if !openTitles.isEmpty {
            lines.append("已打开的标签页：" + openTitles.prefix(10).joined(separator: " | "))
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
                
            case "insert_to_editor":
                let payloadText = (action.text ?? action.content ?? "").trimmingCharacters(in: .newlines)
                guard !payloadText.isEmpty else { return nil }
                if self.insertTextIntoActiveEditor(payloadText, replacingSelection: action.replaceSelection == true) {
                    return AppliedActionReceipt(
                        symbolName: "text.insert",
                        summary: AppLanguage.text("已插入到当前编辑器", en: "Inserted into Editor")
                    )
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
                
            case "curate_podcast":
                let topic = (action.query ?? action.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                guard !topic.isEmpty else { return nil }
                let reason = action.detail ?? action.why
                let shouldOpenBoard = (action.board == "podcast")
                if shouldOpenBoard,
                   let docVC = Self.activeDocumentViewController(),
                   let pane = docVC.focusedEditorViewController
                {
                    docVC.openNewBoardTab(.podcast, in: pane, explicitQuery: topic, splitRight: action.splitRight == true)
                }
                Task { @MainActor in
                    _ = await CotPodcastService.shared.agentDiscoverDownloadAndRemind(
                        topic: topic,
                        reason: reason,
                        openBoard: false
                    )
                }
                return AppliedActionReceipt(
                    symbolName: "waveform.badge.plus",
                    summary: AppLanguage.text("正在搜索并下载「\(topic)」播客", en: "Finding & Downloading: \(topic)")
                )
                
            default:
                return nil
        }
    }
    
    
    // MARK: - SQLite Command Queue Loop (External Pi Takeover)
    
    private func startCommandQueueLoop() {
        self.pollTask?.cancel()
        if let existing = self.activationObserver {
            NotificationCenter.default.removeObserver(existing)
            self.activationObserver = nil
        }
        self.activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.drainCommandQueueIfDatabaseChanged()
            }
        }
        
        self.pollTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                let delayMs: Int = if let self {
                    self.adaptivePollIntervalMilliseconds()
                } else {
                    4500
                }
                try? await Task.sleep(for: .milliseconds(delayMs))
                guard !Task.isCancelled else { break }
                await self?.drainCommandQueueIfDatabaseChanged()
            }
        }
    }
    
    
    private func adaptivePollIntervalMilliseconds() -> Int {
        if !PiKernelManager.shared.activeBotRuns.isEmpty {
            return 1200
        }
        let hasVisibleTerminal = NSApp?.orderedWindows.contains {
            ($0.windowController as? DocumentWindowController)?.workspaceContentViewController?.isTerminalVisible == true
        } ?? false
        if hasVisibleTerminal {
            return 1200
        }
        if NSApp?.isActive == false {
            return 12_000
        }
        return 4500
    }
    
    
    private func currentDatabaseFileSignature() -> DBFileSignature? {
        let dbPath = self.database.databaseURL.path(percentEncoded: false)
        var dbStat = stat()
        guard stat(dbPath, &dbStat) == 0 else { return nil }
        var walStat = stat()
        let hasWal = stat(dbPath + "-wal", &walStat) == 0
        return DBFileSignature(
            dbMtimeSec: dbStat.st_mtimespec.tv_sec,
            dbMtimeNsec: dbStat.st_mtimespec.tv_nsec,
            dbSize: dbStat.st_size,
            walMtimeSec: hasWal ? walStat.st_mtimespec.tv_sec : 0,
            walMtimeNsec: hasWal ? walStat.st_mtimespec.tv_nsec : 0,
            walSize: hasWal ? walStat.st_size : 0
        )
    }
    
    
    private func drainCommandQueueIfDatabaseChanged() async {
        let signature = self.currentDatabaseFileSignature()
        if let signature, let last = self.lastPolledDBSignature, signature == last {
            return
        }
        await self.drainCommandQueueNow()
        self.lastPolledDBSignature = self.currentDatabaseFileSignature() ?? signature
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
    
    
    // MARK: - Direct Editor Helpers (Used by Butler, NEWS AI, and Editor Handoffs)
    
    /// Inserts `text` into the currently focused document editor (undoable).
    /// If the focused tab is a board, falls back to the first non-board text pane or opens a new document tab.
    @discardableResult
    func insertTextIntoActiveEditor(_ text: String, replacingSelection: Bool = false) -> Bool {
        guard !text.isEmpty, let docVC = Self.activeDocumentViewController() else { return false }
        let targetPane: EditorViewController? = {
            if let focused = docVC.focusedEditorViewController, !focused.selectedTab.isBoard {
                return focused
            }
            return docVC.editorViewControllers.first(where: { !$0.selectedTab.isBoard })
        }()
        if let pane = targetPane, let textView = pane.textView, textView.isEditable {
            let selRange = textView.selectedRange()
            let replacementRange: NSRange = if replacingSelection {
                selRange
            } else {
                NSRange(location: selRange.upperBound, length: 0)
            }
            let prefix = (!replacingSelection && replacementRange.location > 0) ? "\n" : ""
            textView.insertText(prefix + text, replacementRange: replacementRange)
            docVC.view.window?.makeFirstResponderDiscardingMarkedText(textView)
            return true
        }
        // No editable text pane open — open a fresh Markdown note in a split tab
        docVC.openNewDocumentTab(title: AppLanguage.text("AI 笔记", en: "AI Note"), content: text, splitRight: true)
        return true
    }
    
    
    /// Opens a fresh Markdown document tab with the given title and content.
    @discardableResult
    func openNewMarkdownDocument(title: String, content: String, splitRight: Bool = false) -> Bool {
        guard let docVC = Self.activeDocumentViewController() else { return false }
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        docVC.openNewDocumentTab(
            title: cleanTitle.isEmpty ? AppLanguage.text("笔记", en: "Note") : cleanTitle,
            content: content,
            splitRight: splitRight
        )
        return true
    }
    
    
    /// Opens a board tab (such as `.butler`, `.market`, `.news`, `.podcast`) inside the active window.
    @discardableResult
    func openBoard(_ kind: PaneBoardKind, query: String? = nil, splitRight: Bool = true) -> Bool {
        guard let docVC = Self.activeDocumentViewController(),
              let pane = docVC.focusedEditorViewController ?? docVC.editorViewControllers.first
        else { return false }
        docVC.openNewBoardTab(kind, in: pane, explicitQuery: query, splitRight: splitRight)
        return true
    }
    
    
    /// Returns the working directory of the active folder window or focused file document, if available.
    func activeWorkingDirectoryURL() -> URL? {
        if let mainWC = NSApp?.mainWindow?.windowController as? DocumentWindowController {
            if let dirURL = (mainWC.contentViewController as? WindowContentViewController)?.directoryDocument?.fileURL {
                return dirURL.standardizedFileURL
            }
            if let fileURL = mainWC.documentViewController?.focusedDocument.fileURL {
                return fileURL.deletingLastPathComponent().standardizedFileURL
            }
        }
        guard let docVC = Self.activeDocumentViewController() else { return nil }
        if let wc = docVC.view.window?.windowController as? DocumentWindowController,
           let dirURL = (wc.contentViewController as? WindowContentViewController)?.directoryDocument?.fileURL
        {
            return dirURL.standardizedFileURL
        }
        return docVC.focusedDocument.fileURL?.deletingLastPathComponent().standardizedFileURL
    }
    
    
    /// Discovers unique local workspace folders currently open in CotEditor windows (folder windows first, then open file parents).
    func openWorkspaceDirectories() -> [URL] {
        var seen: Set<String> = []
        var result: [URL] = []
        let appendUnique: (URL) -> Void = { url in
            let std = url.standardizedFileURL
            let path = std.path(percentEncoded: false)
            guard !path.isEmpty, path != "/", FileManager.default.fileExists(atPath: path) else { return }
            if seen.insert(path).inserted {
                result.append(std)
            }
        }
        
        if let windows = NSApp?.orderedWindows {
            for window in windows {
                guard let wc = window.windowController as? DocumentWindowController else { continue }
                if let dirURL = (wc.contentViewController as? WindowContentViewController)?.directoryDocument?.fileURL {
                    appendUnique(dirURL)
                }
            }
            for window in windows {
                guard let docVC = (window.windowController as? DocumentWindowController)?.documentViewController else { continue }
                for editorVC in docVC.editorViewControllers {
                    for tab in editorVC.tabs where !tab.isBoard {
                        if let fileURL = tab.document.fileURL {
                            appendUnique(fileURL.deletingLastPathComponent())
                        }
                    }
                }
            }
        }
        return result
    }
    
    
    /// Snapshot of currently open non-board text documents across all CotEditor windows for live `@document` attachment.
    struct OpenEditorDocumentInfo: Sendable {
        let id: String
        let title: String
        let filePath: String?
        let syntax: String
        let isActive: Bool
        let content: String
    }
    
    
    func openEditorDocuments(maxContentChars: Int = 36_000) -> [OpenEditorDocumentInfo] {
        let frontDocVC = Self.activeDocumentViewController()
        let activeTab = frontDocVC?.focusedEditorViewController?.selectedTab
        var seenIDs: Set<String> = []
        var items: [OpenEditorDocumentInfo] = []
        
        guard let windows = NSApp?.orderedWindows else { return [] }
        for window in windows {
            guard let docVC = (window.windowController as? DocumentWindowController)?.documentViewController else { continue }
            for editorVC in docVC.editorViewControllers {
                for tab in editorVC.tabs where !tab.isBoard {
                    let filePath = tab.document.fileURL?.standardizedFileURL.path(percentEncoded: false)
                    let docID = "open:\(tab.id.uuidString)"
                    guard seenIDs.insert(docID).inserted else { continue }
                    let ns = tab.document.textStorage.mutableString as NSString
                    let len = min(ns.length, maxContentChars)
                    let text: String = if len > 0 {
                        ns.substring(with: ns.rangeOfComposedCharacterSequences(for: NSRange(location: 0, length: len)))
                    } else {
                        ""
                    }
                    items.append(OpenEditorDocumentInfo(
                        id: docID,
                        title: tab.title,
                        filePath: filePath,
                        syntax: tab.document.syntaxName,
                        isActive: tab === activeTab,
                        content: text
                    ))
                }
            }
        }
        return items.sorted { lhs, rhs in
            if lhs.isActive != rhs.isActive { return lhs.isActive }
            return false
        }
    }
    
    
    /// Lists readable text/code/markdown files inside a workspace folder (shallow traversal) for `@` document mentions.
    struct WorkspaceFileCandidate: Sendable {
        let title: String
        let relativePath: String
        let fullPath: String
    }
    
    
    nonisolated static func listWorkspaceFiles(at directoryURL: URL, limit: Int = 36) -> [WorkspaceFileCandidate] {
        let fm = FileManager.default
        let rootPath = directoryURL.standardizedFileURL.path(percentEncoded: false)
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: rootPath, isDirectory: &isDir), isDir.boolValue else { return [] }
        
        let ignoredNames: Set<String> = [
            ".git", ".svn", ".hg", "node_modules", ".build", "DerivedData",
            "dist", "build", ".next", ".nuxt", "Pods", "Carthage", ".venv", "__pycache__",
            ".DS_Store", ".Trash",
        ]
        let allowedExts: Set<String> = [
            "md", "markdown", "txt", "rtf", "swift", "ts", "tsx", "js", "jsx",
            "py", "go", "rs", "java", "kt", "c", "cpp", "h", "hpp", "m", "mm",
            "json", "yaml", "yml", "toml", "xml", "html", "css", "scss", "sql",
            "sh", "zsh", "bash", "csv", "log", "env", "ini", "conf", "org", "rst",
        ]
        
        var collected: [(url: URL, rel: String, mtime: Date)] = []
        let keys: [URLResourceKey] = [.isDirectoryKey, .isHiddenKey, .contentModificationDateKey, .fileSizeKey]
        
        func scan(_ dir: URL, prefix: String, depth: Int) {
            guard depth <= 2, collected.count < limit * 3 else { return }
            guard let entries = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: keys, options: [.skipsPackageDescendants]) else {
                return
            }
            for entry in entries {
                let name = entry.lastPathComponent
                if ignoredNames.contains(name) || name.hasPrefix(".") { continue }
                let vals = try? entry.resourceValues(forKeys: Set(keys))
                if vals?.isDirectory == true {
                    if depth < 2 {
                        let nextPrefix = prefix.isEmpty ? name : "\(prefix)/\(name)"
                        scan(entry, prefix: nextPrefix, depth: depth + 1)
                    }
                    continue
                }
                if let size = vals?.fileSize, size > 1_500_000 { continue }
                let ext = entry.pathExtension.lowercased()
                guard allowedExts.contains(ext) || ext.isEmpty else { continue }
                let rel = prefix.isEmpty ? name : "\(prefix)/\(name)"
                collected.append((entry, rel, vals?.contentModificationDate ?? .distantPast))
            }
        }
        
        scan(directoryURL.standardizedFileURL, prefix: "", depth: 0)
        collected.sort { $0.mtime > $1.mtime }
        return collected.prefix(limit).map { item in
            WorkspaceFileCandidate(
                title: item.url.lastPathComponent,
                relativePath: item.rel,
                fullPath: item.url.standardizedFileURL.path(percentEncoded: false)
            )
        }
    }
    
    
    /// Produces a compact top-level directory listing for system prompt context.
    nonisolated static func workspaceDirectoryOverview(at directoryURL: URL, maxEntries: Int = 28) -> String {
        let fm = FileManager.default
        let rootPath = directoryURL.standardizedFileURL.path(percentEncoded: false)
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: rootPath, isDirectory: &isDir), isDir.boolValue else { return "" }
        let ignored: Set<String> = [".git", "node_modules", ".build", "DerivedData", ".DS_Store"]
        guard let entries = try? fm.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return "" }
        
        let names = entries
            .filter { !ignored.contains($0.lastPathComponent) }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            .prefix(maxEntries)
            .map { url -> String in
                let isSubdir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
                return isSubdir ? "\(url.lastPathComponent)/" : url.lastPathComponent
            }
        return names.joined(separator: ", ")
    }
    
    
    /// Returns the current editor selection snippet, if any.
    func activeSelectionSnippet() -> String? {
        guard let docVC = Self.activeDocumentViewController(),
              docVC.focusedEditorViewController?.selectedTab.isBoard != true,
              let sel = docVC.focusedTextView?.selectedString.trimmingCharacters(in: .whitespacesAndNewlines),
              !sel.isEmpty
        else { return nil }
        return String(sel.prefix(2000))
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
