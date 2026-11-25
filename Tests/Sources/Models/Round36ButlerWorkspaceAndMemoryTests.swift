//
//  Round36ButlerWorkspaceAndMemoryTests.swift
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
import Testing
@testable import CotEditor

@Suite(.serialized)
@MainActor
struct Round36ButlerWorkspaceAndMemoryTests {
    
    private func makeTempDir() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appending(path: "coteditor-round36-\(UUID().uuidString)", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
    
    
    // MARK: 1. Logical Workspaces (Zero Forced Filesystem Path) & CRUD
    
    @Test func logicalWorkspacesWorkWithoutDiskFoldersAndPersistAcrossReload() throws {
        let tempDir = self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        let db = CotLocalDatabase(customURL: tempDir.appending(path: "logical-ws.sqlite3"))
        let mem = CotMemoryStore(database: db)
        let manager = CotButlerManager(database: db, memoryStore: mem)
        
        // Initially zero workspaces — never auto-pollutes with OS Desktop/Documents folders
        #expect(manager.availableWorkspaces().isEmpty)
        
        let wsResearch = try #require(manager.createWorkspace(name: "AI 行业研究", startSession: true))
        #expect(wsResearch.isFolderBacked == false)
        #expect(wsResearch.folderPath == nil)
        #expect(manager.activeWorkspaceID == wsResearch.id)
        #expect(manager.activeSession?.workspaceName == "AI 行业研究")
        #expect(manager.activeWorkspacePath == nil)
        
        // Verify prompt acknowledges logical workspace without inventing filesystem paths
        let prompt = manager.buildButlerSystemPrompt(workspacePath: nil, workspaceName: "AI 行业研究")
        #expect(prompt.contains("AI 行业研究"))
        #expect(prompt.contains("逻辑主题工作区"))
        
        // Add a user turn so creating a second workspace spawns a separate session
        db.appendButlerMessage(ButlerChatMessage(
            id: UUID().uuidString,
            sessionID: manager.activeSessionID,
            role: "user",
            content: "梳理一下端侧推理芯片趋势",
            actionsJSON: "[]",
            createdAt: Date()
        ))
        manager.reloadFromDatabase()
        
        let wsLife = try #require(manager.createWorkspace(name: "日常随想", startSession: true))
        #expect(manager.availableWorkspaces().map(\.name) == ["AI 行业研究", "日常随想"])
        #expect(manager.availableWorkspaces().allSatisfy { !$0.isFolderBacked })
        
        // Rename & reorder workspaces
        manager.renameWorkspace(wsResearch.id, to: "深度投研")
        manager.reorderWorkspaces([wsLife.id, wsResearch.id])
        
        let reloaded = CotButlerManager(database: db, memoryStore: mem)
        #expect(reloaded.availableWorkspaces().map(\.name) == ["日常随想", "深度投研"])
        
        // Optional folder link + unlink
        let folder = tempDir.appending(path: "LinkedDocs", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        reloaded.updateWorkspaceFolder(wsResearch.id, folderPath: folder.path(percentEncoded: false))
        let linkedWS = try #require(reloaded.availableWorkspaces().first(where: { $0.id == wsResearch.id }))
        #expect(linkedWS.isFolderBacked == true)
        #expect(linkedWS.folderPath == folder.standardizedFileURL.path(percentEncoded: false))
        
        reloaded.updateWorkspaceFolder(wsResearch.id, folderPath: nil)
        let unlinkedWS = try #require(reloaded.availableWorkspaces().first(where: { $0.id == wsResearch.id }))
        #expect(unlinkedWS.isFolderBacked == false)
        #expect(unlinkedWS.folderPath == nil)
        
        // Deleting a workspace preserves its sessions safely in General
        let sessionCountBeforeDelete = reloaded.sessions.count
        reloaded.deleteWorkspace(wsResearch.id)
        #expect(reloaded.sessions.count == sessionCountBeforeDelete)
        #expect(reloaded.availableWorkspaces().map(\.id) == [wsLife.id])
    }
    
    
    // MARK: 2. Session Drag-Reordering & Cross-Workspace Grouping
    
    @Test func sessionMoveReordersWithinGroupAndMovesAcrossGroups() throws {
        let tempDir = self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        let db = CotLocalDatabase(customURL: tempDir.appending(path: "reorder.sqlite3"))
        let mem = CotMemoryStore(database: db)
        let manager = CotButlerManager(database: db, memoryStore: mem)
        
        let s1 = manager.activeSessionID
        db.appendButlerMessage(ButlerChatMessage(id: UUID().uuidString, sessionID: s1, role: "user", content: "第一条会话", actionsJSON: "[]", createdAt: Date()))
        manager.reloadFromDatabase()
        manager.renameSession(s1, to: "会话 A")
        
        manager.startNewSession()
        let s2 = manager.activeSessionID
        db.appendButlerMessage(ButlerChatMessage(id: UUID().uuidString, sessionID: s2, role: "user", content: "第二条会话", actionsJSON: "[]", createdAt: Date()))
        manager.reloadFromDatabase()
        manager.renameSession(s2, to: "会话 B")
        
        manager.startNewSession()
        let s3 = manager.activeSessionID
        db.appendButlerMessage(ButlerChatMessage(id: UUID().uuidString, sessionID: s3, role: "user", content: "第三条会话", actionsJSON: "[]", createdAt: Date()))
        manager.reloadFromDatabase()
        manager.renameSession(s3, to: "会话 C")
        
        let ws = try #require(manager.createWorkspace(name: "工作项目", startSession: false))
        
        // Reorder within General: [s1, s3, s2]
        manager.moveSession(s1, toWorkspaceID: nil, orderedSessionIDs: [s1, s3, s2], isPinned: false)
        #expect(manager.sessions.map(\.id) == [s1, s3, s2])
        
        // Move s2 into workspace `ws`
        manager.moveSession(s2, toWorkspaceID: ws.id, orderedSessionIDs: [s2], isPinned: false)
        let generalAfterMove = manager.sessions.filter { $0.workspaceID == nil }.map(\.id)
        let wsAfterMove = manager.sessions.filter { $0.workspaceID == ws.id }.map(\.id)
        #expect(generalAfterMove == [s1, s3])
        #expect(wsAfterMove == [s2])
        
        // Move s2 back to General at index 0 as pinned, verify persistence in fresh manager
        manager.moveSession(s2, toWorkspaceID: nil, orderedSessionIDs: [s2, s1, s3], isPinned: true)
        
        let reloaded = CotButlerManager(database: db, memoryStore: mem)
        #expect(reloaded.sessions.map(\.id) == [s2, s1, s3])
        #expect(reloaded.sessions.first?.isPinned == true)
        #expect(reloaded.sessions.first?.workspaceID == nil)
    }
    
    
    // MARK: 3. Unified AI Conversation Logs & Memory Extraction Agent
    
    @Test func aiConversationLogsArchiveAllChannelsAndHydrateNewsHistory() throws {
        let tempDir = self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        let db = CotLocalDatabase(customURL: tempDir.appending(path: "logs.sqlite3"))
        let now = Date()
        
        db.appendAIConversationLog(AIConversationLogRecord(
            id: "butler:1",
            channel: "butler",
            sessionID: "sess-1",
            workspaceName: "逻辑工作区",
            botID: "butler",
            role: "user",
            content: "以后请直接给结论，不要客套话",
            createdAt: now,
            memoryExtracted: false
        ))
        db.appendAIConversationLog(AIConversationLogRecord(
            id: "news:1",
            channel: "news",
            sessionID: "news-item-42",
            workspaceName: "NVIDIA 财报简报",
            botID: "readingCompanion",
            role: "user",
            content: "我重点关注算力芯片和港股科技板块",
            createdAt: now.addingTimeInterval(1),
            memoryExtracted: false
        ))
        db.appendAIConversationLog(AIConversationLogRecord(
            id: "news:2",
            channel: "news",
            sessionID: "news-item-42",
            workspaceName: "NVIDIA 财报简报",
            botID: "readingCompanion",
            role: "assistant",
            content: "已为你梳理算力链路的核心指标。",
            createdAt: now.addingTimeInterval(2),
            memoryExtracted: false
        ))
        db.appendAIConversationLog(AIConversationLogRecord(
            id: "action:1",
            channel: "editor_action",
            sessionID: "act-9",
            workspaceName: "周报草稿.md",
            botID: "summarize",
            role: "user",
            content: "总结本周项目推进",
            createdAt: now.addingTimeInterval(3),
            memoryExtracted: false
        ))
        
        #expect(db.countUnextractedAIConversationUserTurns() == 3)
        #expect(db.fetchAIConversationLogs(onlyUnextracted: true, limit: 20).count == 4)
        
        // Verify AIHotNewsService hydrates archived NEWS chat turns on a fresh instance
        let newsService = AIHotNewsService(
            database: db,
            cacheRootDirectory: tempDir.appending(path: "NewsCache", directoryHint: .isDirectory)
        )
        let item = AIHotNewsItem(
            id: "news-item-42",
            title: "NVIDIA 财报简报",
            source: "Tech",
            urlString: "https://example.com/nvda"
        )
        let hydrated = newsService.chatMessages(for: item)
        #expect(hydrated.count == 2)
        #expect(hydrated.first?.role == .user)
        #expect(hydrated.last?.text.contains("算力链路") == true)
    }
    
    
    @Test func memoryExtractionAgentDistillsQualifiedFactsAndMarksLogsExtracted() async throws {
        let tempDir = self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        let db = CotLocalDatabase(customURL: tempDir.appending(path: "mem-agent.sqlite3"))
        let memStore = CotMemoryStore(database: db)
        let now = Date()
        
        db.appendAIConversationLog(AIConversationLogRecord(
            id: "u1",
            channel: "butler",
            sessionID: "s1",
            workspaceName: "投资研究",
            botID: "butler",
            role: "user",
            content: "记住：我平时主要用 Swift 做 macOS 原生开发，回复尽量直接给关键结论。",
            createdAt: now,
            memoryExtracted: false
        ))
        db.appendAIConversationLog(AIConversationLogRecord(
            id: "u2",
            channel: "news",
            sessionID: "n1",
            workspaceName: "市场观察",
            botID: "readingCompanion",
            role: "user",
            content: "我长期关注半导体与光通信板块，不喜欢看长篇空话。",
            createdAt: now.addingTimeInterval(1),
            memoryExtracted: false
        ))
        
        // Verify heuristic fallback extracts explicit declarations
        let heuristics = CotMemoryExtractionAgent.extractLocalHeuristicMemories(
            from: db.fetchAIConversationLogs(onlyUnextracted: true)
        )
        #expect(!heuristics.isEmpty)
        
        // Verify LLM-backed extraction pipeline parses fenced JSON, filters low confidence, and marks logs extracted
        let agent = CotMemoryExtractionAgent(
            database: db,
            memoryStore: memStore,
            llmRunner: { _, prompt in
                #expect(prompt.contains("Swift"))
                return """
                ```json
                {
                  "memories": [
                    {
                      "dimension": "workflow",
                      "fact_key": "primary_stack_macos_swift",
                      "title": "主力使用 Swift 开发 macOS",
                      "detail": "日常从事 macOS 原生客户端研发",
                      "confidence": 0.91
                    },
                    {
                      "dimension": "writingStyle",
                      "fact_key": "prefer_direct_conclusions",
                      "title": "偏好直接给关键结论",
                      "detail": "不喜欢铺垫和长篇客套话",
                      "confidence": 0.88
                    },
                    {
                      "dimension": "finance",
                      "fact_key": "uncertain_noise",
                      "title": "低置信噪音",
                      "detail": "不应入库",
                      "confidence": 0.42
                    }
                  ]
                }
                ```
                """
            }
        )
        
        let inserted = await agent.analyzePendingConversations(force: true)
        #expect(inserted == 2)
        #expect(memStore.memories.contains(where: { $0.factKey == "primary_stack_macos_swift" && $0.source == "memory_agent" }))
        #expect(memStore.memories.contains(where: { $0.factKey == "prefer_direct_conclusions" }))
        #expect(!memStore.memories.contains(where: { $0.factKey == "uncertain_noise" }))
        #expect(memStore.journal.contains(where: { $0.actorBot == "MemoryAgent" }))
        #expect(db.countUnextractedAIConversationUserTurns() == 0)
        
        // Second run has no pending logs -> returns 0
        let secondRun = await agent.analyzePendingConversations(force: true)
        #expect(secondRun == 0)
    }
    
    
    // MARK: 4. WebUI Bundle Contains Updated Workspace & Drag Handlers
    
    @Test func rebuiltWebUIBundleIncludesLogicalWorkspaceAndMoveSessionHandlers() {
        let html = BeautifulAgentUIBundle.htmlDocument()
        #expect(html.contains("createWorkspace"))
        #expect(html.contains("moveSession"))
        #expect(html.contains("reorderWorkspaces"))
        #expect(html.contains("themePageHex"))
    }
}
