//
//  IMConversationTests.swift
//
//  Tests
//

import Foundation
import SQLite3
import Testing
@testable import CotEditor

@Suite(.serialized)
@MainActor
struct IMConversationTests {
    
    @Test func legacyButlerSessionMigratesWithButlerBotID() throws {
        let dir = FileManager.default.temporaryDirectory
            .appending(path: "CotIMLegacyTest-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        
        let dbURL = dir.appending(path: "legacy.sqlite3")
        var rawDB: OpaquePointer?
        #expect(sqlite3_open(dbURL.path(percentEncoded: false), &rawDB) == SQLITE_OK)
        let seedSQL = """
        CREATE TABLE butler_workspaces (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            folder_path TEXT NOT NULL DEFAULT '',
            sort_order INTEGER NOT NULL DEFAULT 0,
            created_at REAL NOT NULL,
            updated_at REAL NOT NULL
        );
        CREATE TABLE butler_sessions (
            id TEXT PRIMARY KEY,
            title TEXT NOT NULL,
            is_pinned INTEGER NOT NULL DEFAULT 0,
            workspace_id TEXT NOT NULL DEFAULT '',
            workspace_path TEXT NOT NULL DEFAULT '',
            sort_order INTEGER NOT NULL DEFAULT 0,
            created_at REAL NOT NULL,
            updated_at REAL NOT NULL
        );
        INSERT INTO butler_sessions (id, title, is_pinned, workspace_id, workspace_path, sort_order, created_at, updated_at)
        VALUES ('legacy-1', '旧对话', 0, '', '', 0, 1000, 1000);
        """
        #expect(sqlite3_exec(rawDB, seedSQL, nil, nil, nil) == SQLITE_OK)
        sqlite3_close(rawDB)
        
        let db = CotLocalDatabase(customURL: dbURL)
        let sessions = db.fetchButlerSessions()
        #expect(sessions.count == 1)
        #expect(sessions.first?.id == "legacy-1")
        #expect(sessions.first?.botID == "butler")
        #expect(sessions.first?.unreadCount == 0)
    }
    
    
    @Test func ensureDirectSessionIsIdempotentAndOnDemand() throws {
        let dir = FileManager.default.temporaryDirectory
            .appending(path: "CotIMDirectTest-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        
        let db = CotLocalDatabase(customURL: dir.appending(path: "im.sqlite3"))
        #expect(db.fetchButlerSessions().isEmpty)
        
        let first = db.ensureDirectSession(forBotID: "translate", defaultTitle: "双语翻译官")
        let second = db.ensureDirectSession(forBotID: "translate", defaultTitle: "双语翻译官")
        #expect(first.id == second.id)
        #expect(first.botID == "translate")
        #expect(db.fetchButlerSessions().count == 1)
        
        let newer = db.createButlerSession(title: "新话题", botID: "translate")
        let latest = db.ensureDirectSession(forBotID: "translate", defaultTitle: "双语翻译官")
        #expect(latest.id == newer.id)
        #expect(db.fetchButlerSessions().count == 2)
    }
    
    
    @Test func unreadIncrementsOnInactiveProactiveAndClearsOnOpen() throws {
        let dir = FileManager.default.temporaryDirectory
            .appending(path: "CotIMUnreadTest-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        
        let db = CotLocalDatabase(customURL: dir.appending(path: "unread.sqlite3"))
        let manager = CotButlerManager(database: db)
        let butlerSessionID = manager.activeSessionID
        #expect(!butlerSessionID.isEmpty)
        
        let dmSession = manager.receiveProactiveMessage(
            fromBotID: AIBotID.weeklyReport.rawValue,
            text: "本周已完成 4 项周报片段，要现在整理吗？"
        )
        #expect(dmSession != nil)
        #expect(manager.activeSessionID == butlerSessionID)
        
        let updatedDM = manager.sessions.first(where: { $0.botID == AIBotID.weeklyReport.rawValue })
        #expect(updatedDM?.unreadCount == 1)
        #expect(updatedDM?.lastMessagePreview.contains("本周已完成") == true)
        
        let opened = manager.openDirectChat(botID: AIBotID.weeklyReport.rawValue)
        #expect(opened.unreadCount == 0)
        #expect(manager.activeSessionID == opened.id)
        #expect(manager.messages.last?.content == "本周已完成 4 项周报片段，要现在整理吗？")
    }
    
    
    @Test func startNewTopicKeepsBotAndInheritsBotWorkspace() throws {
        let dir = FileManager.default.temporaryDirectory
            .appending(path: "CotIMTopicTest-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        
        let wsDir = dir.appending(path: "TranslateDocs", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: wsDir, withIntermediateDirectories: true)
        
        let db = CotLocalDatabase(customURL: dir.appending(path: "topic.sqlite3"))
        let ws = db.createButlerWorkspace(
            name: "翻译工作区",
            folderPath: wsDir.path(percentEncoded: false),
            botID: AIBotID.translate.rawValue,
            defaultDocGroup: "翻译稿"
        )
        let manager = CotButlerManager(database: db)
        let first = manager.openDirectChat(botID: AIBotID.translate.rawValue)
        #expect(first.botID == AIBotID.translate.rawValue)
        #expect(first.workspaceID == ws.id)
        
        manager.startNewTopic()
        #expect(manager.activeSession?.id != first.id)
        #expect(manager.activeSession?.botID == AIBotID.translate.rawValue)
        #expect(manager.activeSession?.workspaceID == ws.id)
        #expect(manager.sessions.filter { $0.botID == AIBotID.translate.rawValue }.count == 2)
    }
    
    
    @Test func proactiveLevelBackwardCompatibleDecoding() throws {
        let legacyBuiltInJSON = Data(#"{"isEnabled":true,"modelOverride":"gpt-4o"}"#.utf8)
        let decodedBuiltIn = try JSONDecoder().decode(AIBotConfig.self, from: legacyBuiltInJSON)
        #expect(decodedBuiltIn.proactiveLevel == nil)
        #expect(decodedBuiltIn.effectiveProactiveLevel(for: .butler) == .restrained)
        #expect(decodedBuiltIn.effectiveProactiveLevel(for: .weeklyReport) == .restrained)
        #expect(decodedBuiltIn.effectiveProactiveLevel(for: .readingCompanion) == .restrained)
        #expect(decodedBuiltIn.effectiveProactiveLevel(for: .translate) == .off)
        
        let legacyCustomJSON = Data(#"{"id":"custom_abc","name":"小助手","nickname":"助手"}"#.utf8)
        let decodedCustom = try JSONDecoder().decode(CustomBotProfile.self, from: legacyCustomJSON)
        #expect(decodedCustom.proactiveLevel == .off)
        #expect(decodedCustom.isEnabled == true)
    }
    
    
    @Test func cotBackupPreservesPerBotSessionAndBotWorkspace() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appending(path: "CotIMMigrationTest-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        
        let srcRoot = dir.appending(path: "srcSupport", directoryHint: .isDirectory)
        let dstRoot = dir.appending(path: "dstSupport", directoryHint: .isDirectory)
        let makeRoots: (URL) -> MigrationArchiveSidecarRoots = { base in
            MigrationArchiveSidecarRoots(
                keyBindings: base.appending(path: "KeyBindings", directoryHint: .isDirectory),
                themes: base.appending(path: "Themes", directoryHint: .isDirectory),
                syntaxes: base.appending(path: "Syntaxes", directoryHint: .isDirectory),
                replacements: base.appending(path: "Replacements", directoryHint: .isDirectory)
            )
        }
        let srcRoots = makeRoots(srcRoot)
        let dstRoots = makeRoots(dstRoot)
        for (_, dirURL) in srcRoots.namedDirectories + dstRoots.namedDirectories {
            try FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true)
        }
        
        let sourceDB = CotLocalDatabase(customURL: dir.appending(path: "source.sqlite3"))
        let ws = sourceDB.createButlerWorkspace(
            name: "研报库",
            botID: AIBotID.readingCompanion.rawValue,
            defaultDocGroup: "研报摘要"
        )
        let dm = sourceDB.createButlerSession(
            title: "每日资讯",
            workspaceID: ws.id,
            botID: AIBotID.readingCompanion.rawValue
        )
        sourceDB.appendButlerMessage(ButlerChatMessage(
            id: UUID().uuidString,
            sessionID: dm.id,
            role: "assistant",
            content: "今日两条播客已更新摘要。",
            actionsJSON: "{}",
            createdAt: Date()
        ))
        sourceDB.incrementSessionUnread(id: dm.id, preview: "今日两条播客已更新摘要。")
        
        let archiveURL = dir.appending(path: "im.cotbackup")
        _ = try await MigrationArchiveService.exportArchive(from: sourceDB, to: archiveURL, sidecarRoots: srcRoots)
        
        let targetDB = CotLocalDatabase(customURL: dir.appending(path: "target.sqlite3"))
        let backupDir = dir.appending(path: "Backups", directoryHint: .isDirectory)
        _ = try await MigrationArchiveService.importArchive(
            from: archiveURL,
            into: targetDB,
            sidecarRoots: dstRoots,
            backupDirectory: backupDir
        )
        
        let restoredWS = targetDB.findButlerWorkspace(botID: AIBotID.readingCompanion.rawValue)
        #expect(restoredWS?.name == "研报库")
        #expect(restoredWS?.defaultDocGroup == "研报摘要")
        
        let restoredDM = targetDB.fetchLatestSession(forBotID: AIBotID.readingCompanion.rawValue)
        #expect(restoredDM?.title == "每日资讯")
        #expect(restoredDM?.unreadCount == 1)
        #expect(restoredDM?.lastMessagePreview == "今日两条播客已更新摘要。")
    }
    
    
    @Test func contactListBuilderMergesLatestSessionSumsUnreadAndOrdersButlerFirst() {
        let older = ButlerSessionRecord(
            id: "s-trans-1",
            title: "旧翻译",
            isPinned: false,
            createdAt: Date(timeIntervalSince1970: 100),
            updatedAt: Date(timeIntervalSince1970: 100),
            botID: "translate",
            unreadCount: 1,
            lastMessagePreview: "旧消息"
        )
        let newer = ButlerSessionRecord(
            id: "s-trans-2",
            title: "新翻译",
            isPinned: true,
            createdAt: Date(timeIntervalSince1970: 200),
            updatedAt: Date(timeIntervalSince1970: 300),
            botID: "translate",
            unreadCount: 2,
            lastMessagePreview: "最新译文已完成"
        )
        let customSession = ButlerSessionRecord(
            id: "s-custom-1",
            title: "自定义对话",
            isPinned: false,
            createdAt: Date(timeIntervalSince1970: 150),
            updatedAt: Date(timeIntervalSince1970: 150),
            botID: "custom_1",
            unreadCount: 4,
            lastMessagePreview: "自定义回复"
        )
        let seeds = [
            IMContactSeed(id: "custom_1", name: "自定义", nickname: "自", handle: "@c", tagline: "t", accentHex: "#111111", avatarURL: nil, isCustom: true, isButler: false),
            IMContactSeed(id: "translate", name: "翻译官", nickname: "翻", handle: "@t", tagline: "t", accentHex: "#222222", avatarURL: nil, isCustom: false, isButler: false),
            IMContactSeed(id: "butler", name: "总管", nickname: "曜", handle: "@b", tagline: "t", accentHex: "#333333", avatarURL: nil, isCustom: false, isButler: true),
        ]
        
        let contacts = IMContactListBuilder.build(sessions: [older, newer, customSession], bots: seeds)
        #expect(contacts.map(\.id) == ["butler", "translate", "custom_1"])
        #expect(contacts[0].sessionID == nil)
        #expect(contacts[0].unreadCount == 0)
        #expect(contacts[1].sessionID == "s-trans-2")
        #expect(contacts[1].unreadCount == 3)
        #expect(contacts[1].lastMessagePreview == "最新译文已完成")
        #expect(contacts[1].isPinned == true)
        #expect(contacts[2].unreadCount == 4)
    }
    
    
    @Test func receiveProactiveMessageCountsAsUnreadEvenForActiveSessionWhenHidden() throws {
        let dir = FileManager.default.temporaryDirectory
            .appending(path: "CotIMActiveUnreadTest-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        
        let db = CotLocalDatabase(customURL: dir.appending(path: "active-unread.sqlite3"))
        let manager = CotButlerManager(database: db)
        let activeID = manager.activeSessionID
        
        let delivered = manager.receiveProactiveMessage(
            fromBotID: AIBotID.butler.rawValue,
            text: "晚安复盘已整理完成。",
            countsAsUnread: true
        )
        #expect(delivered?.id == activeID)
        #expect(manager.totalUnreadCount == 1)
        #expect(manager.mostRecentUnreadSession?.id == activeID)
        
        manager.selectSession(activeID)
        #expect(manager.totalUnreadCount == 0)
    }
}
