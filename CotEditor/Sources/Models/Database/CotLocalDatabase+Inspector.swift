//
//  CotLocalDatabase+Inspector.swift
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
import SQLite3

// MARK: - Local Database Inspection Models

nonisolated enum DatabaseCategoryKind: String, CaseIterable, Identifiable, Sendable {
    
    case documents
    case aiRecords
    case memory
    case feedsAndBoards
    case systemConfig
    
    var id: String { self.rawValue }
    
    var displayName: String {
        switch self {
            case .documents: AppLanguage.text("文档周报", en: "Documents")
            case .aiRecords: AppLanguage.text("AI 记录", en: "AI Records")
            case .memory: AppLanguage.text("长期记忆", en: "Memory")
            case .feedsAndBoards: AppLanguage.text("订阅统计", en: "Feeds")
            case .systemConfig: AppLanguage.text("偏好配置", en: "Settings")
        }
    }
    
    static func classify(tableName: String) -> DatabaseCategoryKind {
        switch tableName {
            case "documents", "weekly_reports":
                .documents
            case "ai_usage_events", "butler_workspaces", "butler_sessions", "butler_messages",
                 "ai_conversation_logs", "daily_ai_digests", "agent_command_queue":
                .aiRecords
            case "user_kyc_memories", "user_memory_journal":
                .memory
            case "user_watchlist_stocks", "user_podcasts", "user_followed_feeds",
                 "user_followed_creators", "user_reminders", "daily_writing_stats":
                .feedsAndBoards
            default:
                .systemConfig
        }
    }
    
    static func localizedTableTitle(for tableName: String) -> String {
        switch tableName {
            case "documents": AppLanguage.text("本地文档", en: "Documents")
            case "configs": AppLanguage.text("配置键值", en: "Configurations")
            case "weekly_reports": AppLanguage.text("周报归档", en: "Weekly Reports")
            case "daily_writing_stats": AppLanguage.text("每日写作统计", en: "Daily Writing Stats")
            case "ai_usage_events": AppLanguage.text("AI Token 记录", en: "AI Token Events")
            case "daily_ai_digests": AppLanguage.text("每日 AI 摘要", en: "Daily AI Digests")
            case "user_reminders": AppLanguage.text("待办提醒", en: "Reminders")
            case "schema_migrations": AppLanguage.text("结构迁移记录", en: "Schema Migrations")
            case "user_kyc_memories": AppLanguage.text("长期偏好记忆", en: "Long-Term Memories")
            case "user_memory_journal": AppLanguage.text("记忆变更日志", en: "Memory Journal")
            case "user_watchlist_stocks": AppLanguage.text("自选股票", en: "Stock Watchlist")
            case "user_podcasts": AppLanguage.text("播客与收听进度", en: "Podcasts")
            case "user_followed_feeds": AppLanguage.text("订阅资讯源", en: "Followed Feeds")
            case "user_followed_creators": AppLanguage.text("关注创作者", en: "Followed Creators")
            case "butler_workspaces": AppLanguage.text("总管工作区", en: "Butler Workspaces")
            case "butler_sessions": AppLanguage.text("总管会话", en: "Butler Sessions")
            case "butler_messages": AppLanguage.text("总管对话消息", en: "Butler Messages")
            case "workspace_live_state": AppLanguage.text("工作区快照", en: "Workspace State")
            case "agent_command_queue": AppLanguage.text("Agent 指令队列", en: "Agent Queue")
            case "ai_conversation_logs": AppLanguage.text("AI 对话日志", en: "AI Conversation Logs")
            case "media_blobs": AppLanguage.text("素材二进制库", en: "Media Blobs")
            case "user_stickers": AppLanguage.text("表情包索引", en: "Stickers")
            case "custom_bots": AppLanguage.text("自定义 Bot", en: "Custom Bots")
            case "bot_emotion_states": AppLanguage.text("Bot 情绪状态", en: "Bot Emotions")
            case "meeting_room_sessions": AppLanguage.text("会议室会话", en: "Meeting Sessions")
            case "meeting_room_messages": AppLanguage.text("会议室消息", en: "Meeting Messages")
            default: tableName
        }
    }
}


nonisolated struct DatabaseStorageCategory: Identifiable, Equatable, Sendable {
    
    let kind: DatabaseCategoryKind
    let bytes: Int64
    let rowCount: Int
    let tableCount: Int
    
    var id: String { self.kind.id }
}


nonisolated struct DatabaseColumnInfo: Identifiable, Equatable, Sendable {
    
    let name: String
    let dataType: String
    let isPrimaryKey: Bool
    let isNotNull: Bool
    
    var id: String { self.name }
}


nonisolated struct DatabaseTableSummary: Identifiable, Equatable, Sendable {
    
    let name: String
    let displayName: String
    let category: DatabaseCategoryKind
    let rowCount: Int
    let estimatedBytes: Int64
    let columns: [DatabaseColumnInfo]
    let indexCount: Int
    
    var id: String { self.name }
}


nonisolated struct DatabaseTablePreview: Equatable, Sendable {
    
    let tableName: String
    let columns: [String]
    let rows: [[String]]
    let totalRowCount: Int
}


nonisolated struct DatabaseModelTokenUsage: Identifiable, Equatable, Sendable {
    
    let model: String
    let requests: Int
    let inputTokens: Int
    let outputTokens: Int
    let avgLatencyMs: Int
    
    var id: String { self.model }
    var totalTokens: Int { self.inputTokens + self.outputTokens }
}


nonisolated struct DatabaseFeatureTokenUsage: Identifiable, Equatable, Sendable {
    
    let feature: String
    let displayName: String
    let requests: Int
    let inputTokens: Int
    let outputTokens: Int
    
    var id: String { self.feature }
    var totalTokens: Int { self.inputTokens + self.outputTokens }
}


nonisolated struct DatabaseDailyTokenPoint: Identifiable, Equatable, Sendable {
    
    let dateKey: String
    let shortLabel: String
    let inputTokens: Int
    let outputTokens: Int
    let requests: Int
    
    var id: String { self.dateKey }
    var totalTokens: Int { self.inputTokens + self.outputTokens }
}


nonisolated struct DatabaseAITokenEventRow: Identifiable, Equatable, Sendable {
    
    let id: Int64
    let timestamp: Date
    let feature: String
    let featureLabel: String
    let model: String
    let provider: String
    let inputTokens: Int
    let outputTokens: Int
    let latencyMs: Int
    let success: Bool
    
    var totalTokens: Int { self.inputTokens + self.outputTokens }
}


nonisolated struct DatabaseAITokenSummary: Equatable, Sendable {
    
    let totalRequests: Int
    let successRequests: Int
    let totalInputTokens: Int
    let totalOutputTokens: Int
    let averageLatencyMs: Int
    let byModel: [DatabaseModelTokenUsage]
    let byFeature: [DatabaseFeatureTokenUsage]
    let dailyTrend: [DatabaseDailyTokenPoint]
    let recentEvents: [DatabaseAITokenEventRow]
    
    var totalTokens: Int { self.totalInputTokens + self.totalOutputTokens }
    var successRate: Double {
        guard self.totalRequests > 0 else { return 1.0 }
        return Double(self.successRequests) / Double(self.totalRequests)
    }
    
    static let empty = DatabaseAITokenSummary(
        totalRequests: 0,
        successRequests: 0,
        totalInputTokens: 0,
        totalOutputTokens: 0,
        averageLatencyMs: 0,
        byModel: [],
        byFeature: [],
        dailyTrend: [],
        recentEvents: []
    )
}


nonisolated struct DatabaseAssetCounts: Equatable, Sendable {
    
    let activeDocuments: Int
    let trashedDocuments: Int
    let totalDocumentChars: Int
    let weeklyReports: Int
    let butlerSessions: Int
    let butlerMessages: Int
    let conversationLogs: Int
    let kycMemories: Int
    let memoryJournals: Int
    let remindersOpen: Int
    let remindersTotal: Int
    let watchlistStocks: Int
    let podcasts: Int
    let followedFeeds: Int
    let followedCreators: Int
    let writingDays: Int
    let totalTypedChars: Int
    let totalAICompletedChars: Int
    let configEntries: Int
    
    var totalSubscriptions: Int {
        self.watchlistStocks + self.podcasts + self.followedFeeds + self.followedCreators
    }
    
    var totalMessages: Int {
        self.butlerMessages + self.conversationLogs
    }
}


nonisolated struct DatabaseInspectionSnapshot: Equatable, Sendable {
    
    let filePath: String
    let fileName: String
    let mainFileBytes: Int64
    let walBytes: Int64
    let shmBytes: Int64
    let totalBytes: Int64
    let pageCount: Int
    let pageSize: Int
    let freelistPages: Int
    let reclaimableBytes: Int64
    let journalMode: String
    let sqliteVersion: String
    let migrationCount: Int
    let lastModifiedAt: Date?
    let totalRowCount: Int
    let tables: [DatabaseTableSummary]
    let categories: [DatabaseStorageCategory]
    let tokenSummary: DatabaseAITokenSummary
    let assets: DatabaseAssetCounts
}


// MARK: - SQLite Introspection & Maintenance

extension CotLocalDatabase {
    
    private static let sensitiveConfigKeys: Set<String> = [
        ConfigKey.syncAIProfileAPIKeys,
        ConfigKey.cotPassLicenseKey,
    ]
    
    private static let timestampColumnHints: Set<String> = [
        "updated_at", "created_at", "deleted_at", "timestamp",
        "generated_at", "due_date", "completed_at", "applied_at",
        "last_played_at", "executed_at",
    ]
    
    private static let previewDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd HH:mm"
        return formatter
    }()
    
    
    /// Builds a complete live diagnostic snapshot of the local SQLite file, schema, categories,
    /// asset counts, and AI token history.
    func inspectDatabaseSnapshot() -> DatabaseInspectionSnapshot {
        let fm = FileManager.default
        let mainPath = self.databaseURL.path
        let walPath = mainPath + "-wal"
        let shmPath = mainPath + "-shm"
        
        let mainBytes = Self.fileSize(atPath: mainPath, fileManager: fm)
        let walBytes = Self.fileSize(atPath: walPath, fileManager: fm)
        let shmBytes = Self.fileSize(atPath: shmPath, fileManager: fm)
        let totalBytes = mainBytes + walBytes + shmBytes
        let lastModified = (try? fm.attributesOfItem(atPath: mainPath)[.modificationDate]) as? Date
        
        let pageCount = self.querySingleInt("PRAGMA page_count;")
        let pageSize = self.querySingleInt("PRAGMA page_size;")
        let freelistPages = self.querySingleInt("PRAGMA freelist_count;")
        let reclaimableBytes = Int64(freelistPages) * Int64(pageSize)
        let journalMode = self.querySingleString("PRAGMA journal_mode;").uppercased()
        let sqliteVersion = self.querySingleString("SELECT sqlite_version();")
        let migrationCount = self.querySingleInt("SELECT COUNT(*) FROM schema_migrations;")
        
        let tableNames = self.queryAllUserTableNames()
        let indexCountsByTable = self.queryIndexCountsByTable()
        
        var tables: [DatabaseTableSummary] = []
        tables.reserveCapacity(tableNames.count)
        
        for name in tableNames {
            let columns = self.queryColumns(forTable: name)
            let rowCount = self.querySingleInt("SELECT COUNT(*) FROM \"\(name)\";")
            let estimatedBytes = self.estimatePayloadBytes(forTable: name, columns: columns, rowCount: rowCount)
            tables.append(DatabaseTableSummary(
                name: name,
                displayName: DatabaseCategoryKind.localizedTableTitle(for: name),
                category: DatabaseCategoryKind.classify(tableName: name),
                rowCount: rowCount,
                estimatedBytes: estimatedBytes,
                columns: columns,
                indexCount: indexCountsByTable[name] ?? 0
            ))
        }
        
        tables.sort { lhs, rhs in
            if lhs.rowCount != rhs.rowCount {
                return lhs.rowCount > rhs.rowCount
            }
            if lhs.estimatedBytes != rhs.estimatedBytes {
                return lhs.estimatedBytes > rhs.estimatedBytes
            }
            return lhs.name < rhs.name
        }
        
        let totalRowCount = tables.reduce(0) { $0 + $1.rowCount }
        let categories = Self.aggregateCategories(from: tables)
        let tokenSummary = self.queryAITokenSummary()
        let assets = self.queryAssetCounts()
        
        return DatabaseInspectionSnapshot(
            filePath: mainPath,
            fileName: self.databaseURL.lastPathComponent,
            mainFileBytes: mainBytes,
            walBytes: walBytes,
            shmBytes: shmBytes,
            totalBytes: totalBytes,
            pageCount: pageCount,
            pageSize: pageSize,
            freelistPages: freelistPages,
            reclaimableBytes: reclaimableBytes,
            journalMode: journalMode.isEmpty ? "WAL" : journalMode,
            sqliteVersion: sqliteVersion.isEmpty ? "3" : sqliteVersion,
            migrationCount: migrationCount,
            lastModifiedAt: lastModified,
            totalRowCount: totalRowCount,
            tables: tables,
            categories: categories,
            tokenSummary: tokenSummary,
            assets: assets
        )
    }
    
    
    /// Fetches up to `limit` most recent rows from a verified user table, masking sensitive secrets
    /// and formatting timestamps cleanly for visual inspection.
    func inspectTablePreview(tableName: String, limit: Int = 30) -> DatabaseTablePreview {
        let validTables = Set(self.queryAllUserTableNames())
        guard validTables.contains(tableName), let db = self.db else {
            return DatabaseTablePreview(tableName: tableName, columns: [], rows: [], totalRowCount: 0)
        }
        
        let totalRowCount = self.querySingleInt("SELECT COUNT(*) FROM \"\(tableName)\";")
        let columnInfos = self.queryColumns(forTable: tableName)
        let columnNames = columnInfos.map(\.name)
        let orderColumn = Self.preferredOrderColumn(in: columnNames)
        let clampedLimit = max(1, min(100, limit))
        
        let sql: String
        if let orderColumn {
            sql = "SELECT * FROM \"\(tableName)\" ORDER BY \"\(orderColumn)\" DESC LIMIT \(clampedLimit);"
        } else {
            sql = "SELECT * FROM \"\(tableName)\" ORDER BY rowid DESC LIMIT \(clampedLimit);"
        }
        
        var rows: [[String]] = []
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            let colCount = Int(sqlite3_column_count(stmt))
            let resolvedNames: [String] = (0..<colCount).map { idx in
                if let cName = sqlite3_column_name(stmt, Int32(idx)) {
                    return String(cString: cName)
                }
                return "col_\(idx)"
            }
            let keyColumnIndex = (tableName == "configs") ? resolvedNames.firstIndex(of: "key") : nil
            let valueColumnIndex = (tableName == "configs") ? resolvedNames.firstIndex(of: "value") : nil
            
            while sqlite3_step(stmt) == SQLITE_ROW {
                let rowKey: String? = if let kIdx = keyColumnIndex, let text = sqlite3_column_text(stmt, Int32(kIdx)) {
                    String(cString: text)
                } else {
                    nil
                }
                let isSensitiveConfig = rowKey.map { Self.sensitiveConfigKeys.contains($0) } ?? false
                
                var cells: [String] = []
                cells.reserveCapacity(colCount)
                for idx in 0..<colCount {
                    if isSensitiveConfig && idx == valueColumnIndex {
                        cells.append("••••••••")
                        continue
                    }
                    let colName = idx < resolvedNames.count ? resolvedNames[idx] : ""
                    cells.append(Self.formatColumnValue(stmt: stmt, index: Int32(idx), columnName: colName))
                }
                rows.append(cells)
            }
            sqlite3_finalize(stmt)
            return DatabaseTablePreview(
                tableName: tableName,
                columns: resolvedNames,
                rows: rows,
                totalRowCount: totalRowCount
            )
        }
        sqlite3_finalize(stmt)
        return DatabaseTablePreview(tableName: tableName, columns: columnNames, rows: [], totalRowCount: totalRowCount)
    }
    
    
    /// Checkpoints the WAL journal and compacts unused SQLite pages, returning reclaimed bytes.
    @discardableResult
    func compactDatabase() -> Int64 {
        let fm = FileManager.default
        let mainPath = self.databaseURL.path
        let before = Self.fileSize(atPath: mainPath, fileManager: fm)
            + Self.fileSize(atPath: mainPath + "-wal", fileManager: fm)
            + Self.fileSize(atPath: mainPath + "-shm", fileManager: fm)
        
        self.executeSQL("PRAGMA wal_checkpoint(TRUNCATE);")
        self.executeSQL("VACUUM;")
        self.executeSQL("PRAGMA wal_checkpoint(TRUNCATE);")
        
        let after = Self.fileSize(atPath: mainPath, fileManager: fm)
            + Self.fileSize(atPath: mainPath + "-wal", fileManager: fm)
            + Self.fileSize(atPath: mainPath + "-shm", fileManager: fm)
        return max(0, before - after)
    }
    
    
    // MARK: Private Introspection Queries
    
    private static func fileSize(atPath path: String, fileManager: FileManager) -> Int64 {
        guard let attrs = try? fileManager.attributesOfItem(atPath: path),
              let number = attrs[.size] as? NSNumber
        else { return 0 }
        return number.int64Value
    }
    
    
    private func querySingleInt(_ sql: String) -> Int {
        guard let db = self.db else { return 0 }
        var stmt: OpaquePointer?
        var value = 0
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK,
           sqlite3_step(stmt) == SQLITE_ROW
        {
            value = Int(sqlite3_column_int64(stmt, 0))
        }
        sqlite3_finalize(stmt)
        return value
    }
    
    
    private func querySingleString(_ sql: String) -> String {
        guard let db = self.db else { return "" }
        var stmt: OpaquePointer?
        var value = ""
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK,
           sqlite3_step(stmt) == SQLITE_ROW,
           let cStr = sqlite3_column_text(stmt, 0)
        {
            value = String(cString: cStr)
        }
        sqlite3_finalize(stmt)
        return value
    }
    
    
    private func queryAllUserTableNames() -> [String] {
        guard let db = self.db else { return [] }
        let sql = "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%' ORDER BY name ASC;"
        var names: [String] = []
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            while sqlite3_step(stmt) == SQLITE_ROW {
                if let cStr = sqlite3_column_text(stmt, 0) {
                    names.append(String(cString: cStr))
                }
            }
        }
        sqlite3_finalize(stmt)
        return names
    }
    
    
    private func queryIndexCountsByTable() -> [String: Int] {
        guard let db = self.db else { return [:] }
        let sql = "SELECT tbl_name, COUNT(*) FROM sqlite_master WHERE type = 'index' AND name NOT LIKE 'sqlite_%' GROUP BY tbl_name;"
        var result: [String: Int] = [:]
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            while sqlite3_step(stmt) == SQLITE_ROW {
                if let cStr = sqlite3_column_text(stmt, 0) {
                    result[String(cString: cStr)] = Int(sqlite3_column_int64(stmt, 1))
                }
            }
        }
        sqlite3_finalize(stmt)
        return result
    }
    
    
    private func queryColumns(forTable tableName: String) -> [DatabaseColumnInfo] {
        guard let db = self.db else { return [] }
        var columns: [DatabaseColumnInfo] = []
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, "PRAGMA table_info(\"\(tableName)\");", -1, &stmt, nil) == SQLITE_OK {
            while sqlite3_step(stmt) == SQLITE_ROW {
                let name = sqlite3_column_text(stmt, 1).map { String(cString: $0) } ?? ""
                let type = sqlite3_column_text(stmt, 2).map { String(cString: $0) } ?? ""
                let notNull = sqlite3_column_int(stmt, 3) != 0
                let isPK = sqlite3_column_int(stmt, 5) != 0
                columns.append(DatabaseColumnInfo(
                    name: name,
                    dataType: type.isEmpty ? "ANY" : type.uppercased(),
                    isPrimaryKey: isPK,
                    isNotNull: notNull
                ))
            }
        }
        sqlite3_finalize(stmt)
        return columns
    }
    
    
    private func estimatePayloadBytes(forTable tableName: String, columns: [DatabaseColumnInfo], rowCount: Int) -> Int64 {
        guard rowCount > 0, !columns.isEmpty else { return 0 }
        let sumTerms = columns.map { col in
            "COALESCE(LENGTH(CAST(\"\(col.name)\" AS BLOB)), 0)"
        }.joined(separator: " + ")
        let sql = "SELECT COALESCE(SUM(\(sumTerms)), 0) FROM \"\(tableName)\";"
        let rawBytes = Int64(self.querySingleInt(sql))
        // Add modest B-tree header overhead (~24 bytes per row) so small tables never show 0 B
        return max(Int64(rowCount) * 24, rawBytes + Int64(rowCount) * 24)
    }
    
    
    private static func aggregateCategories(from tables: [DatabaseTableSummary]) -> [DatabaseStorageCategory] {
        DatabaseCategoryKind.allCases.map { kind in
            let matched = tables.filter { $0.category == kind }
            return DatabaseStorageCategory(
                kind: kind,
                bytes: matched.reduce(0) { $0 + $1.estimatedBytes },
                rowCount: matched.reduce(0) { $0 + $1.rowCount },
                tableCount: matched.count
            )
        }
    }
    
    
    private func queryAITokenSummary() -> DatabaseAITokenSummary {
        guard let db = self.db else { return .empty }
        
        var totalRequests = 0
        var successRequests = 0
        var totalInput = 0
        var totalOutput = 0
        var avgLatency = 0
        
        let aggSQL = """
        SELECT COUNT(*),
               COALESCE(SUM(CASE WHEN success != 0 THEN 1 ELSE 0 END), 0),
               COALESCE(SUM(input_tokens), 0),
               COALESCE(SUM(output_tokens), 0),
               COALESCE(AVG(latency_ms), 0)
        FROM ai_usage_events;
        """
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, aggSQL, -1, &stmt, nil) == SQLITE_OK, sqlite3_step(stmt) == SQLITE_ROW {
            totalRequests = Int(sqlite3_column_int64(stmt, 0))
            successRequests = Int(sqlite3_column_int64(stmt, 1))
            totalInput = Int(sqlite3_column_int64(stmt, 2))
            totalOutput = Int(sqlite3_column_int64(stmt, 3))
            avgLatency = Int(sqlite3_column_double(stmt, 4).rounded())
        }
        sqlite3_finalize(stmt)
        
        guard totalRequests > 0 else { return .empty }
        
        return DatabaseAITokenSummary(
            totalRequests: totalRequests,
            successRequests: successRequests,
            totalInputTokens: totalInput,
            totalOutputTokens: totalOutput,
            averageLatencyMs: avgLatency,
            byModel: self.queryTokenUsageByModel(db: db),
            byFeature: self.queryTokenUsageByFeature(db: db),
            dailyTrend: self.queryDailyTokenTrend(db: db),
            recentEvents: self.queryRecentTokenEvents(db: db)
        )
    }
    
    
    private func queryTokenUsageByModel(db: OpaquePointer) -> [DatabaseModelTokenUsage] {
        var result: [DatabaseModelTokenUsage] = []
        let sql = """
        SELECT model,
               COUNT(*),
               COALESCE(SUM(input_tokens), 0),
               COALESCE(SUM(output_tokens), 0),
               COALESCE(AVG(latency_ms), 0)
        FROM ai_usage_events
        GROUP BY model
        ORDER BY (COALESCE(SUM(input_tokens), 0) + COALESCE(SUM(output_tokens), 0)) DESC
        LIMIT 8;
        """
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            while sqlite3_step(stmt) == SQLITE_ROW {
                let model = sqlite3_column_text(stmt, 0).map { String(cString: $0) } ?? "unknown"
                result.append(DatabaseModelTokenUsage(
                    model: model.isEmpty ? "default" : model,
                    requests: Int(sqlite3_column_int64(stmt, 1)),
                    inputTokens: Int(sqlite3_column_int64(stmt, 2)),
                    outputTokens: Int(sqlite3_column_int64(stmt, 3)),
                    avgLatencyMs: Int(sqlite3_column_double(stmt, 4).rounded())
                ))
            }
        }
        sqlite3_finalize(stmt)
        return result
    }
    
    
    private func queryTokenUsageByFeature(db: OpaquePointer) -> [DatabaseFeatureTokenUsage] {
        var result: [DatabaseFeatureTokenUsage] = []
        let sql = """
        SELECT feature,
               COUNT(*),
               COALESCE(SUM(input_tokens), 0),
               COALESCE(SUM(output_tokens), 0)
        FROM ai_usage_events
        GROUP BY feature
        ORDER BY (COALESCE(SUM(input_tokens), 0) + COALESCE(SUM(output_tokens), 0)) DESC
        LIMIT 8;
        """
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            while sqlite3_step(stmt) == SQLITE_ROW {
                let feature = sqlite3_column_text(stmt, 0).map { String(cString: $0) } ?? "other"
                result.append(DatabaseFeatureTokenUsage(
                    feature: feature,
                    displayName: Self.localizedFeatureName(feature),
                    requests: Int(sqlite3_column_int64(stmt, 1)),
                    inputTokens: Int(sqlite3_column_int64(stmt, 2)),
                    outputTokens: Int(sqlite3_column_int64(stmt, 3))
                ))
            }
        }
        sqlite3_finalize(stmt)
        return result
    }
    
    
    private func queryDailyTokenTrend(db: OpaquePointer) -> [DatabaseDailyTokenPoint] {
        var dailyRaw: [DatabaseDailyTokenPoint] = []
        let sql = """
        SELECT date_key,
               COALESCE(SUM(input_tokens), 0),
               COALESCE(SUM(output_tokens), 0),
               COUNT(*)
        FROM ai_usage_events
        GROUP BY date_key
        ORDER BY date_key DESC
        LIMIT 14;
        """
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            while sqlite3_step(stmt) == SQLITE_ROW {
                let dateKey = sqlite3_column_text(stmt, 0).map { String(cString: $0) } ?? ""
                let shortLabel = dateKey.count >= 10 ? String(dateKey.suffix(5)) : dateKey
                dailyRaw.append(DatabaseDailyTokenPoint(
                    dateKey: dateKey,
                    shortLabel: shortLabel,
                    inputTokens: Int(sqlite3_column_int64(stmt, 1)),
                    outputTokens: Int(sqlite3_column_int64(stmt, 2)),
                    requests: Int(sqlite3_column_int64(stmt, 3))
                ))
            }
        }
        sqlite3_finalize(stmt)
        return Array(dailyRaw.reversed())
    }
    
    
    private func queryRecentTokenEvents(db: OpaquePointer) -> [DatabaseAITokenEventRow] {
        var recentEvents: [DatabaseAITokenEventRow] = []
        let sql = """
        SELECT id, timestamp, feature, model, provider, input_tokens, output_tokens, latency_ms, success
        FROM ai_usage_events
        ORDER BY timestamp DESC, id DESC
        LIMIT 25;
        """
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            while sqlite3_step(stmt) == SQLITE_ROW {
                let feature = sqlite3_column_text(stmt, 2).map { String(cString: $0) } ?? ""
                let model = sqlite3_column_text(stmt, 3).map { String(cString: $0) } ?? ""
                let provider = sqlite3_column_text(stmt, 4).map { String(cString: $0) } ?? ""
                recentEvents.append(DatabaseAITokenEventRow(
                    id: sqlite3_column_int64(stmt, 0),
                    timestamp: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 1)),
                    feature: feature,
                    featureLabel: Self.localizedFeatureName(feature),
                    model: model,
                    provider: provider,
                    inputTokens: Int(sqlite3_column_int64(stmt, 5)),
                    outputTokens: Int(sqlite3_column_int64(stmt, 6)),
                    latencyMs: Int(sqlite3_column_int64(stmt, 7)),
                    success: sqlite3_column_int(stmt, 8) != 0
                ))
            }
        }
        sqlite3_finalize(stmt)
        return recentEvents
    }
    
    
    private func queryAssetCounts() -> DatabaseAssetCounts {
        DatabaseAssetCounts(
            activeDocuments: self.querySingleInt("SELECT COUNT(*) FROM documents WHERE deleted_at IS NULL;"),
            trashedDocuments: self.querySingleInt("SELECT COUNT(*) FROM documents WHERE deleted_at IS NOT NULL;"),
            totalDocumentChars: self.querySingleInt("SELECT COALESCE(SUM(LENGTH(content)), 0) FROM documents WHERE deleted_at IS NULL;"),
            weeklyReports: self.querySingleInt("SELECT COUNT(*) FROM weekly_reports;"),
            butlerSessions: self.querySingleInt("SELECT COUNT(*) FROM butler_sessions;"),
            butlerMessages: self.querySingleInt("SELECT COUNT(*) FROM butler_messages;"),
            conversationLogs: self.querySingleInt("SELECT COUNT(*) FROM ai_conversation_logs;"),
            kycMemories: self.querySingleInt("SELECT COUNT(*) FROM user_kyc_memories WHERE is_archived = 0;"),
            memoryJournals: self.querySingleInt("SELECT COUNT(*) FROM user_memory_journal;"),
            remindersOpen: self.querySingleInt("SELECT COUNT(*) FROM user_reminders WHERE is_completed = 0;"),
            remindersTotal: self.querySingleInt("SELECT COUNT(*) FROM user_reminders;"),
            watchlistStocks: self.querySingleInt("SELECT COUNT(*) FROM user_watchlist_stocks;"),
            podcasts: self.querySingleInt("SELECT COUNT(*) FROM user_podcasts;"),
            followedFeeds: self.querySingleInt("SELECT COUNT(*) FROM user_followed_feeds;"),
            followedCreators: self.querySingleInt("SELECT COUNT(*) FROM user_followed_creators;"),
            writingDays: self.querySingleInt("SELECT COUNT(*) FROM daily_writing_stats WHERE typed_chars > 0 OR ai_completed_chars > 0;"),
            totalTypedChars: self.querySingleInt("SELECT COALESCE(SUM(typed_chars), 0) FROM daily_writing_stats;"),
            totalAICompletedChars: self.querySingleInt("SELECT COALESCE(SUM(ai_completed_chars), 0) FROM daily_writing_stats;"),
            configEntries: self.querySingleInt("SELECT COUNT(*) FROM configs;")
        )
    }
    
    
    private static func preferredOrderColumn(in columns: [String]) -> String? {
        for candidate in ["updated_at", "timestamp", "created_at", "generated_at", "date_key", "id"] {
            if columns.contains(candidate) {
                return candidate
            }
        }
        return nil
    }
    
    
    private static func formatColumnValue(stmt: OpaquePointer?, index: Int32, columnName: String) -> String {
        let type = sqlite3_column_type(stmt, index)
        switch type {
            case SQLITE_NULL:
                return "—"
            case SQLITE_INTEGER:
                return "\(sqlite3_column_int64(stmt, index))"
            case SQLITE_FLOAT:
                let val = sqlite3_column_double(stmt, index)
                if Self.timestampColumnHints.contains(columnName), val > 1_500_000_000, val < 4_000_000_000 {
                    return Self.previewDateFormatter.string(from: Date(timeIntervalSince1970: val))
                }
                return String(format: "%.2f", val)
            case SQLITE_BLOB:
                let bytes = sqlite3_column_bytes(stmt, index)
                return "[Blob · \(bytes) B]"
            default:
                guard let cStr = sqlite3_column_text(stmt, index) else { return "" }
                let raw = String(cString: cStr)
                    .replacingOccurrences(of: "\n", with: " ")
                    .replacingOccurrences(of: "\r", with: "")
                    .trimmingCharacters(in: .whitespaces)
                if raw.count > 72 {
                    return String(raw.prefix(70)) + "…"
                }
                return raw.isEmpty ? "—" : raw
        }
    }
    
    
    private static func localizedFeatureName(_ raw: String) -> String {
        let lower = raw.lowercased()
        if lower.contains("butler") || lower.contains("chat") { return AppLanguage.text("AI 对话", en: "AI Chat") }
        if lower.contains("complet") || lower.contains("next") { return AppLanguage.text("续写补全", en: "Completion") }
        if lower.contains("organ") || lower.contains("merge") { return AppLanguage.text("一键整理", en: "Organize") }
        if lower.contains("weekly") { return AppLanguage.text("周报生成", en: "Weekly Report") }
        if lower.contains("summar") || lower.contains("digest") { return AppLanguage.text("摘要提炼", en: "Summary") }
        if lower.contains("translat") { return AppLanguage.text("翻译", en: "Translate") }
        if lower.contains("restruct") || lower.contains("rewrite") { return AppLanguage.text("润色重构", en: "Restructure") }
        if lower.contains("ocr") || lower.contains("image") || lower.contains("vision") { return AppLanguage.text("图像识别", en: "Vision / OCR") }
        if lower.contains("news") { return AppLanguage.text("资讯伴读", en: "News AI") }
        if lower.contains("memory") || lower.contains("kyc") { return AppLanguage.text("记忆提炼", en: "Memory") }
        if lower.contains("chart") { return AppLanguage.text("图表生成", en: "Chart") }
        return raw.isEmpty ? AppLanguage.text("其他", en: "Other") : raw
    }
}


// MARK: - Human-Readable Vault Browser Models & Queries

nonisolated enum DatabaseVaultSectionKind: String, CaseIterable, Identifiable, Sendable {
    
    case documents
    case weeklyReports
    case memories
    case reminders
    case conversations
    case subscriptions
    
    var id: String { self.rawValue }
    
    var title: String {
        switch self {
            case .documents: AppLanguage.text("本地文档", en: "Documents")
            case .weeklyReports: AppLanguage.text("周报归档", en: "Weekly Reports")
            case .memories: AppLanguage.text("长期记忆", en: "Memories")
            case .reminders: AppLanguage.text("待办事项", en: "Tasks")
            case .conversations: AppLanguage.text("AI 对话", en: "AI Chats")
            case .subscriptions: AppLanguage.text("订阅与关注", en: "Subscriptions")
        }
    }
    
    var categoryKind: DatabaseCategoryKind {
        switch self {
            case .documents, .weeklyReports: .documents
            case .memories: .memory
            case .reminders, .subscriptions: .feedsAndBoards
            case .conversations: .aiRecords
        }
    }
}


nonisolated struct DatabaseVaultContentItem: Identifiable, Equatable, Sendable {
    
    let id: String
    let title: String
    let badge: String?
    let metric: String
    let detail: String?
}


extension CotLocalDatabase {
    
    /// Formats a file path with `~` home abbreviation so settings UI never overflows on long user paths.
    nonisolated static func abbreviatedDisplayPath(_ fullPath: String) -> String {
        (fullPath as NSString).abbreviatingWithTildeInPath
    }
    
    
    /// Returns clean, user-readable items for a vault category (never exposing raw SQLite table/key names).
    func inspectVaultItems(for kind: DatabaseVaultSectionKind, limit: Int = 30) -> [DatabaseVaultContentItem] {
        guard let db = self.db else { return [] }
        let clampedLimit = max(1, min(80, limit))
        
        switch kind {
            case .documents:
                return self.queryVaultDocuments(db: db, limit: clampedLimit)
            case .weeklyReports:
                return self.queryVaultWeeklyReports(db: db, limit: clampedLimit)
            case .memories:
                return self.queryVaultMemories(db: db, limit: clampedLimit)
            case .reminders:
                return self.queryVaultReminders(db: db, limit: clampedLimit)
            case .conversations:
                return self.queryVaultConversations(db: db, limit: clampedLimit)
            case .subscriptions:
                return self.queryVaultSubscriptions(db: db, limit: clampedLimit)
        }
    }
    
    
    private func queryVaultDocuments(db: OpaquePointer, limit: Int) -> [DatabaseVaultContentItem] {
        var items: [DatabaseVaultContentItem] = []
        let sql = """
        SELECT id, title, group_name, LENGTH(content), updated_at
        FROM documents
        WHERE deleted_at IS NULL
        ORDER BY updated_at DESC
        LIMIT \(limit);
        """
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            while sqlite3_step(stmt) == SQLITE_ROW {
                let id = sqlite3_column_text(stmt, 0).map { String(cString: $0) } ?? UUID().uuidString
                let rawTitle = sqlite3_column_text(stmt, 1).map { String(cString: $0) } ?? ""
                let group = sqlite3_column_text(stmt, 2).map { String(cString: $0) } ?? ""
                let chars = Int(sqlite3_column_int64(stmt, 3))
                let ts = sqlite3_column_double(stmt, 4)
                let title = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? AppLanguage.text("未命名文档", en: "Untitled")
                    : rawTitle
                items.append(DatabaseVaultContentItem(
                    id: id,
                    title: title,
                    badge: group.isEmpty ? nil : group,
                    metric: "\(chars.formatted()) \(AppLanguage.text("字", en: "ch"))",
                    detail: ts > 1_500_000_000 ? Self.previewDateFormatter.string(from: Date(timeIntervalSince1970: ts)) : nil
                ))
            }
        }
        sqlite3_finalize(stmt)
        return items
    }
    
    
    private func queryVaultWeeklyReports(db: OpaquePointer, limit: Int) -> [DatabaseVaultContentItem] {
        var items: [DatabaseVaultContentItem] = []
        let sql = """
        SELECT id, title, period_label, LENGTH(content), updated_at
        FROM weekly_reports
        ORDER BY updated_at DESC
        LIMIT \(limit);
        """
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            while sqlite3_step(stmt) == SQLITE_ROW {
                let id = sqlite3_column_text(stmt, 0).map { String(cString: $0) } ?? UUID().uuidString
                let title = sqlite3_column_text(stmt, 1).map { String(cString: $0) } ?? AppLanguage.text("周报", en: "Report")
                let period = sqlite3_column_text(stmt, 2).map { String(cString: $0) } ?? ""
                let chars = Int(sqlite3_column_int64(stmt, 3))
                let ts = sqlite3_column_double(stmt, 4)
                items.append(DatabaseVaultContentItem(
                    id: id,
                    title: title.isEmpty ? (period.isEmpty ? AppLanguage.text("周报", en: "Report") : period) : title,
                    badge: period.isEmpty ? nil : period,
                    metric: "\(chars.formatted()) \(AppLanguage.text("字", en: "ch"))",
                    detail: ts > 1_500_000_000 ? Self.previewDateFormatter.string(from: Date(timeIntervalSince1970: ts)) : nil
                ))
            }
        }
        sqlite3_finalize(stmt)
        return items
    }
    
    
    private func queryVaultMemories(db: OpaquePointer, limit: Int) -> [DatabaseVaultContentItem] {
        var items: [DatabaseVaultContentItem] = []
        let sql = """
        SELECT id, content, category, updated_at
        FROM user_kyc_memories
        WHERE is_archived = 0
        ORDER BY updated_at DESC
        LIMIT \(limit);
        """
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            while sqlite3_step(stmt) == SQLITE_ROW {
                let id = sqlite3_column_text(stmt, 0).map { String(cString: $0) } ?? UUID().uuidString
                let content = (sqlite3_column_text(stmt, 1).map { String(cString: $0) } ?? "")
                    .replacingOccurrences(of: "\n", with: " ")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let cat = sqlite3_column_text(stmt, 2).map { String(cString: $0) } ?? ""
                let ts = sqlite3_column_double(stmt, 3)
                guard !content.isEmpty else { continue }
                items.append(DatabaseVaultContentItem(
                    id: id,
                    title: content,
                    badge: cat.isEmpty ? nil : cat,
                    metric: ts > 1_500_000_000 ? Self.previewDateFormatter.string(from: Date(timeIntervalSince1970: ts)) : "",
                    detail: nil
                ))
            }
        }
        sqlite3_finalize(stmt)
        return items
    }
    
    
    private func queryVaultReminders(db: OpaquePointer, limit: Int) -> [DatabaseVaultContentItem] {
        var items: [DatabaseVaultContentItem] = []
        let sql = """
        SELECT id, title, is_completed, updated_at
        FROM user_reminders
        ORDER BY is_completed ASC, updated_at DESC
        LIMIT \(limit);
        """
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            while sqlite3_step(stmt) == SQLITE_ROW {
                let id = sqlite3_column_text(stmt, 0).map { String(cString: $0) } ?? UUID().uuidString
                let title = (sqlite3_column_text(stmt, 1).map { String(cString: $0) } ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let done = sqlite3_column_int(stmt, 2) != 0
                let ts = sqlite3_column_double(stmt, 3)
                guard !title.isEmpty else { continue }
                items.append(DatabaseVaultContentItem(
                    id: id,
                    title: title,
                    badge: done ? AppLanguage.text("已完成", en: "Done") : AppLanguage.text("待办", en: "Open"),
                    metric: ts > 1_500_000_000 ? Self.previewDateFormatter.string(from: Date(timeIntervalSince1970: ts)) : "",
                    detail: nil
                ))
            }
        }
        sqlite3_finalize(stmt)
        return items
    }
    
    
    private func queryVaultConversations(db: OpaquePointer, limit: Int) -> [DatabaseVaultContentItem] {
        var items: [DatabaseVaultContentItem] = []
        let sessionSQL = """
        SELECT s.id, s.title, COUNT(m.id), s.updated_at
        FROM butler_sessions s
        LEFT JOIN butler_messages m ON m.session_id = s.id
        GROUP BY s.id
        ORDER BY s.updated_at DESC
        LIMIT \(limit);
        """
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sessionSQL, -1, &stmt, nil) == SQLITE_OK {
            while sqlite3_step(stmt) == SQLITE_ROW {
                let id = sqlite3_column_text(stmt, 0).map { String(cString: $0) } ?? UUID().uuidString
                let title = (sqlite3_column_text(stmt, 1).map { String(cString: $0) } ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let msgCount = Int(sqlite3_column_int64(stmt, 2))
                let ts = sqlite3_column_double(stmt, 3)
                items.append(DatabaseVaultContentItem(
                    id: "sess:\(id)",
                    title: title.isEmpty ? AppLanguage.text("总管对话", en: "Butler Session") : title,
                    badge: AppLanguage.text("总管", en: "Butler"),
                    metric: "\(msgCount) \(AppLanguage.text("条", en: "msgs"))",
                    detail: ts > 1_500_000_000 ? Self.previewDateFormatter.string(from: Date(timeIntervalSince1970: ts)) : nil
                ))
            }
        }
        sqlite3_finalize(stmt)
        return items
    }
    
    
    private func queryVaultSubscriptions(db: OpaquePointer, limit: Int) -> [DatabaseVaultContentItem] {
        var items: [DatabaseVaultContentItem] = []
        let queries: [(sql: String, badge: String)] = [
            ("SELECT symbol, name FROM user_watchlist_stocks ORDER BY sort_order ASC LIMIT 20;", AppLanguage.text("自选股", en: "Stock")),
            ("SELECT id, title FROM user_podcasts ORDER BY updated_at DESC LIMIT 20;", AppLanguage.text("播客", en: "Podcast")),
            ("SELECT id, title FROM user_followed_feeds ORDER BY updated_at DESC LIMIT 20;", AppLanguage.text("资讯", en: "Feed")),
            ("SELECT id, name FROM user_followed_creators ORDER BY updated_at DESC LIMIT 20;", AppLanguage.text("创作者", en: "Creator")),
        ]
        for query in queries {
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, query.sql, -1, &stmt, nil) == SQLITE_OK {
                while sqlite3_step(stmt) == SQLITE_ROW && items.count < limit {
                    let first = sqlite3_column_text(stmt, 0).map { String(cString: $0) } ?? ""
                    let second = sqlite3_column_text(stmt, 1).map { String(cString: $0) } ?? ""
                    let display = second.isEmpty ? first : (query.badge == AppLanguage.text("自选股", en: "Stock") ? "\(second) (\(first))" : second)
                    guard !display.isEmpty else { continue }
                    items.append(DatabaseVaultContentItem(
                        id: "\(query.badge):\(first):\(items.count)",
                        title: display,
                        badge: query.badge,
                        metric: "",
                        detail: nil
                    ))
                }
            }
            sqlite3_finalize(stmt)
        }
        return items
    }
}
