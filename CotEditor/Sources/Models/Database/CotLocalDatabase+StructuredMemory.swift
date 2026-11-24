//
//  CotLocalDatabase+StructuredMemory.swift
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

// MARK: - Multi-Angle KYC & Portable Asset Value Types

/// Eight orthogonal KYC angles capturing who the user is, how they think, what they follow, and their boundaries.
nonisolated enum KYCDimension: String, CaseIterable, Codable, Identifiable, Sendable {
    
    case identity
    case cognition
    case writingStyle
    case goals
    case finance
    case informationDiet
    case workflow
    case taboos
    
    var id: String { self.rawValue }
    
    var label: String {
        switch self {
            case .identity: AppLanguage.text("身份", en: "Identity")
            case .cognition: AppLanguage.text("思维", en: "Cognition")
            case .writingStyle: AppLanguage.text("表达", en: "Voice")
            case .goals: AppLanguage.text("目标", en: "Goals")
            case .finance: AppLanguage.text("市场", en: "Markets")
            case .informationDiet: AppLanguage.text("信息源", en: "Feeds")
            case .workflow: AppLanguage.text("工作流", en: "Workflow")
            case .taboos: AppLanguage.text("边界", en: "Taboos")
        }
    }
    
    var symbolName: String {
        switch self {
            case .identity: "person.text.rectangle"
            case .cognition: "brain.head.profile"
            case .writingStyle: "pencil.and.outline"
            case .goals: "scope"
            case .finance: "chart.xyaxis.line"
            case .informationDiet: "dot.radiowaves.left.and.right"
            case .workflow: "slider.horizontal.3"
            case .taboos: "hand.raised"
        }
    }
}


/// A single structured KYC / long-term memory fact stored in `user_kyc_memories`.
nonisolated struct UserKYCMemoryRecord: Identifiable, Codable, Sendable, Equatable {
    
    var id: String
    var dimension: KYCDimension
    var factKey: String
    var title: String
    var detail: String
    var confidence: Double
    var source: String
    var evidenceRef: String?
    var isPinned: Bool
    var isArchived: Bool
    var reinforcementCount: Int
    var createdAt: Date
    var updatedAt: Date
}


/// Append-only audit log recording how Bots, Pi, or the user evolved KYC memory over time.
nonisolated struct UserMemoryJournalEntry: Identifiable, Codable, Sendable, Equatable {
    
    var id: Int64
    var timestamp: Date
    var actorBot: String
    var changeType: String
    var dimension: String
    var summary: String
}


/// A persisted watched market instrument inside `user_watchlist_stocks`.
nonisolated struct WatchlistStockRecord: Identifiable, Codable, Sendable, Equatable {
    
    var instrumentID: String
    var namespace: String
    var symbol: String
    var name: String
    var eastmoneySecID: String
    var tencentCode: String
    var sortOrder: Int
    var thesisNote: String
    var alertUpPrice: Double?
    var alertDownPrice: Double?
    var lastPrice: Double?
    var lastChangePct: Double?
    var addedBy: String
    var createdAt: Date
    var updatedAt: Date
    
    var id: String { self.instrumentID }
}


/// A persisted podcast episode or show entry inside `user_podcasts`.
nonisolated struct StoredPodcastRecord: Identifiable, Codable, Sendable, Equatable {
    
    var id: String
    var itemKind: String
    var platform: String
    var title: String
    var showName: String
    var sourceURL: String
    var audioURL: String
    var artworkURL: String
    var durationSec: Double
    var playbackPositionSec: Double
    var isSaved: Bool
    var topicTag: String
    var notes: String
    var lastPlayedAt: Date?
    var createdAt: Date
    var updatedAt: Date
}


/// A persisted blog / RSS / Substack / site source inside `user_followed_feeds`.
nonisolated struct FollowedFeedRecord: Identifiable, Codable, Sendable, Equatable {
    
    var id: String
    var title: String
    var siteURL: String
    var feedURL: String
    var category: String
    var author: String
    var notes: String
    var isPinned: Bool
    var addedBy: String
    var createdAt: Date
    var updatedAt: Date
}


/// A persisted X / social creator inside `user_followed_creators`.
nonisolated struct FollowedCreatorRecord: Identifiable, Codable, Sendable, Equatable {
    
    var id: String
    var platform: String
    var handle: String
    var displayName: String
    var profileURL: String
    var avatarURL: String
    var focusTags: String
    var whyFollowing: String
    var isPinned: Bool
    var addedBy: String
    var createdAt: Date
    var updatedAt: Date
}


/// Persisted conversation session for the top-bar Chief Butler Bot (`butler_sessions`).
nonisolated struct ButlerSessionRecord: Identifiable, Codable, Sendable, Equatable {
    
    var id: String
    var title: String
    var isPinned: Bool
    var createdAt: Date
    var updatedAt: Date
    var previewText: String = ""
    var messageCount: Int = 0
}


/// Persisted conversation turn for the top-bar Chief Butler Bot (`butler_messages`).
nonisolated struct ButlerChatMessage: Identifiable, Codable, Sendable, Equatable {
    
    var id: String
    var sessionID: String = "default"
    var role: String
    var content: String
    var actionsJSON: String
    var createdAt: Date
    
    init(
        id: String,
        sessionID: String = "default",
        role: String,
        content: String,
        actionsJSON: String,
        createdAt: Date
    ) {
        self.id = id
        self.sessionID = sessionID
        self.role = role
        self.content = content
        self.actionsJSON = actionsJSON
        self.createdAt = createdAt
    }
}


/// Command queued in SQLite (`agent_command_queue`) by external or headless Pi Agents for live UI takeover.
nonisolated struct QueuedAgentCommand: Identifiable, Codable, Sendable, Equatable {
    
    var id: Int64
    var actionType: String
    var payloadJSON: String
    var status: String
    var resultNote: String
    var createdAt: Date
    var executedAt: Date?
}


// MARK: - Structured SQLite Schema & Modular CRUD Extension

extension CotLocalDatabase {
    
    func createStructuredAssetTablesIfNeeded() {
        let sql = """
        CREATE TABLE IF NOT EXISTS schema_migrations (
            version INTEGER PRIMARY KEY,
            module TEXT NOT NULL,
            applied_at REAL NOT NULL
        );
        CREATE TABLE IF NOT EXISTS user_kyc_memories (
            id TEXT PRIMARY KEY,
            dimension TEXT NOT NULL,
            fact_key TEXT NOT NULL,
            title TEXT NOT NULL,
            detail TEXT NOT NULL DEFAULT '',
            confidence REAL NOT NULL DEFAULT 0.85,
            source TEXT NOT NULL DEFAULT 'user_explicit',
            evidence_ref TEXT,
            is_pinned INTEGER NOT NULL DEFAULT 0,
            is_archived INTEGER NOT NULL DEFAULT 0,
            reinforcement_count INTEGER NOT NULL DEFAULT 1,
            created_at REAL NOT NULL,
            updated_at REAL NOT NULL,
            UNIQUE(dimension, fact_key)
        );
        CREATE INDEX IF NOT EXISTS idx_kyc_dimension_pinned ON user_kyc_memories(dimension, is_pinned DESC, confidence DESC);

        CREATE TABLE IF NOT EXISTS user_memory_journal (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            timestamp REAL NOT NULL,
            actor_bot TEXT NOT NULL,
            change_type TEXT NOT NULL,
            dimension TEXT NOT NULL,
            summary TEXT NOT NULL
        );
        CREATE INDEX IF NOT EXISTS idx_memory_journal_ts ON user_memory_journal(timestamp DESC);

        CREATE TABLE IF NOT EXISTS user_watchlist_stocks (
            instrument_id TEXT PRIMARY KEY,
            namespace TEXT NOT NULL,
            symbol TEXT NOT NULL,
            name TEXT NOT NULL,
            eastmoney_secid TEXT NOT NULL DEFAULT '',
            tencent_code TEXT NOT NULL DEFAULT '',
            sort_order INTEGER NOT NULL DEFAULT 0,
            thesis_note TEXT NOT NULL DEFAULT '',
            alert_up_price REAL,
            alert_down_price REAL,
            last_price REAL,
            last_change_pct REAL,
            added_by TEXT NOT NULL DEFAULT 'user',
            created_at REAL NOT NULL,
            updated_at REAL NOT NULL
        );
        CREATE INDEX IF NOT EXISTS idx_watchlist_sort ON user_watchlist_stocks(sort_order ASC, updated_at DESC);

        CREATE TABLE IF NOT EXISTS user_podcasts (
            id TEXT PRIMARY KEY,
            item_kind TEXT NOT NULL DEFAULT 'episode',
            platform TEXT NOT NULL,
            title TEXT NOT NULL,
            show_name TEXT NOT NULL DEFAULT '',
            source_url TEXT NOT NULL,
            audio_url TEXT NOT NULL DEFAULT '',
            artwork_url TEXT NOT NULL DEFAULT '',
            duration_sec REAL NOT NULL DEFAULT 0,
            playback_position_sec REAL NOT NULL DEFAULT 0,
            is_saved INTEGER NOT NULL DEFAULT 0,
            topic_tag TEXT NOT NULL DEFAULT '',
            notes TEXT NOT NULL DEFAULT '',
            last_played_at REAL,
            created_at REAL NOT NULL,
            updated_at REAL NOT NULL
        );
        CREATE INDEX IF NOT EXISTS idx_podcasts_saved_played ON user_podcasts(is_saved DESC, last_played_at DESC, updated_at DESC);

        CREATE TABLE IF NOT EXISTS user_followed_feeds (
            id TEXT PRIMARY KEY,
            title TEXT NOT NULL,
            site_url TEXT NOT NULL,
            feed_url TEXT NOT NULL DEFAULT '',
            category TEXT NOT NULL DEFAULT '',
            author TEXT NOT NULL DEFAULT '',
            notes TEXT NOT NULL DEFAULT '',
            is_pinned INTEGER NOT NULL DEFAULT 0,
            added_by TEXT NOT NULL DEFAULT 'user',
            created_at REAL NOT NULL,
            updated_at REAL NOT NULL
        );
        CREATE INDEX IF NOT EXISTS idx_feeds_pinned ON user_followed_feeds(is_pinned DESC, updated_at DESC);

        CREATE TABLE IF NOT EXISTS user_followed_creators (
            id TEXT PRIMARY KEY,
            platform TEXT NOT NULL DEFAULT 'x',
            handle TEXT NOT NULL,
            display_name TEXT NOT NULL,
            profile_url TEXT NOT NULL DEFAULT '',
            avatar_url TEXT NOT NULL DEFAULT '',
            focus_tags TEXT NOT NULL DEFAULT '',
            why_following TEXT NOT NULL DEFAULT '',
            is_pinned INTEGER NOT NULL DEFAULT 0,
            added_by TEXT NOT NULL DEFAULT 'user',
            created_at REAL NOT NULL,
            updated_at REAL NOT NULL
        );
        CREATE INDEX IF NOT EXISTS idx_creators_pinned ON user_followed_creators(is_pinned DESC, updated_at DESC);

        CREATE TABLE IF NOT EXISTS butler_sessions (
            id TEXT PRIMARY KEY,
            title TEXT NOT NULL,
            is_pinned INTEGER NOT NULL DEFAULT 0,
            created_at REAL NOT NULL,
            updated_at REAL NOT NULL
        );
        CREATE INDEX IF NOT EXISTS idx_butler_sessions_updated ON butler_sessions(is_pinned DESC, updated_at DESC);

        CREATE TABLE IF NOT EXISTS butler_messages (
            id TEXT PRIMARY KEY,
            session_id TEXT NOT NULL DEFAULT 'default',
            role TEXT NOT NULL,
            content TEXT NOT NULL,
            actions_json TEXT NOT NULL DEFAULT '[]',
            created_at REAL NOT NULL
        );
        CREATE INDEX IF NOT EXISTS idx_butler_created ON butler_messages(created_at ASC);

        CREATE TABLE IF NOT EXISTS workspace_live_state (
            slot TEXT PRIMARY KEY,
            payload_json TEXT NOT NULL,
            updated_at REAL NOT NULL
        );

        CREATE TABLE IF NOT EXISTS agent_command_queue (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            action_type TEXT NOT NULL,
            payload_json TEXT NOT NULL,
            status TEXT NOT NULL DEFAULT 'pending',
            result_note TEXT NOT NULL DEFAULT '',
            created_at REAL NOT NULL,
            executed_at REAL
        );
        CREATE INDEX IF NOT EXISTS idx_agent_queue_status ON agent_command_queue(status, id ASC);
        """
        self.executeSQL(sql)
        
        self.ensureButlerMessageSessionColumnExists()
        self.executeSQL("""
        CREATE INDEX IF NOT EXISTS idx_kyc_active_sort ON user_kyc_memories(is_archived, is_pinned DESC, confidence DESC, updated_at DESC);
        CREATE INDEX IF NOT EXISTS idx_kyc_fact_key ON user_kyc_memories(fact_key);
        CREATE INDEX IF NOT EXISTS idx_watchlist_symbol_lower ON user_watchlist_stocks(lower(symbol));
        CREATE INDEX IF NOT EXISTS idx_butler_messages_session ON butler_messages(session_id, created_at ASC);
        """)
        self.migrateLegacyButlerMessagesToSessionIfNeeded()
        
        let now = Date().timeIntervalSince1970
        let migrationSQL = "INSERT OR IGNORE INTO schema_migrations (version, module, applied_at) VALUES (1, 'structured_kyc_assets_v1', ?);"
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(self.db, migrationSQL, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_double(stmt, 1, now)
            sqlite3_step(stmt)
        }
        sqlite3_finalize(stmt)
        
        self.seedStarterWatchlistIfNeeded()
    }
    
    
    func seedStarterWatchlistIfNeeded(allowDuringTests: Bool = false) {
        guard allowDuringTests || !Self.isRunningUnitTests else { return }
        guard !self.bool(forKey: ConfigKey.watchlistSeededV1, default: false) else { return }
        self.set(true, forKey: ConfigKey.watchlistSeededV1)
        
        guard self.fetchWatchlistStocks().isEmpty else { return }
        let now = Date()
        let defaults: [WatchlistStockRecord] = [
            WatchlistStockRecord(
                instrumentID: "hk:HSTECH",
                namespace: "hk",
                symbol: "HSTECH",
                name: "恒生科技指数",
                eastmoneySecID: "124.HSTECH",
                tencentCode: "hkHSTECH",
                sortOrder: 0,
                thesisNote: "",
                alertUpPrice: nil,
                alertDownPrice: nil,
                lastPrice: nil,
                lastChangePct: nil,
                addedBy: "seed",
                createdAt: now,
                updatedAt: now
            ),
            WatchlistStockRecord(
                instrumentID: "hk:00700",
                namespace: "hk",
                symbol: "00700",
                name: "腾讯控股",
                eastmoneySecID: "116.00700",
                tencentCode: "hk00700",
                sortOrder: 1,
                thesisNote: "",
                alertUpPrice: nil,
                alertDownPrice: nil,
                lastPrice: nil,
                lastChangePct: nil,
                addedBy: "seed",
                createdAt: now,
                updatedAt: now
            ),
            WatchlistStockRecord(
                instrumentID: "sh:600519",
                namespace: "sh",
                symbol: "600519",
                name: "贵州茅台",
                eastmoneySecID: "1.600519",
                tencentCode: "sh600519",
                sortOrder: 2,
                thesisNote: "",
                alertUpPrice: nil,
                alertDownPrice: nil,
                lastPrice: nil,
                lastChangePct: nil,
                addedBy: "seed",
                createdAt: now,
                updatedAt: now
            ),
            WatchlistStockRecord(
                instrumentID: "us:NVDA",
                namespace: "us",
                symbol: "NVDA",
                name: "英伟达",
                eastmoneySecID: "105.NVDA",
                tencentCode: "usNVDA.OQ",
                sortOrder: 3,
                thesisNote: "",
                alertUpPrice: nil,
                alertDownPrice: nil,
                lastPrice: nil,
                lastChangePct: nil,
                addedBy: "seed",
                createdAt: now,
                updatedAt: now
            ),
        ]
        self.withTransaction {
            for stock in defaults {
                self.upsertWatchlistStock(stock)
            }
        }
    }
    
    
    // MARK: - KYC Memories & Journal
    
    func fetchKYCMemories(dimension: KYCDimension? = nil, includeArchived: Bool = false) -> [UserKYCMemoryRecord] {
        var clauses: [String] = []
        if !includeArchived {
            clauses.append("is_archived = 0")
        }
        if dimension != nil {
            clauses.append("dimension = ?")
        }
        let whereClause = clauses.isEmpty ? "" : "WHERE " + clauses.joined(separator: " AND ")
        let sql = """
        SELECT id, dimension, fact_key, title, detail, confidence, source, evidence_ref,
               is_pinned, is_archived, reinforcement_count, created_at, updated_at
        FROM user_kyc_memories
        \(whereClause)
        ORDER BY is_pinned DESC, confidence DESC, updated_at DESC;
        """
        var stmt: OpaquePointer?
        var items: [UserKYCMemoryRecord] = []
        if sqlite3_prepare_v2(self.db, sql, -1, &stmt, nil) == SQLITE_OK {
            if let dimension {
                sqlite3_bind_text(stmt, 1, dimension.rawValue, -1, self.transientDestructor)
            }
            while sqlite3_step(stmt) == SQLITE_ROW {
                guard
                    let idCStr = sqlite3_column_text(stmt, 0),
                    let dimCStr = sqlite3_column_text(stmt, 1),
                    let keyCStr = sqlite3_column_text(stmt, 2),
                    let titleCStr = sqlite3_column_text(stmt, 3),
                    let detailCStr = sqlite3_column_text(stmt, 4),
                    let srcCStr = sqlite3_column_text(stmt, 6)
                else { continue }
                
                let dim = KYCDimension(rawValue: String(cString: dimCStr)) ?? .identity
                let evidence: String? = if let evCStr = sqlite3_column_text(stmt, 7) {
                    String(cString: evCStr)
                } else {
                    nil
                }
                items.append(UserKYCMemoryRecord(
                    id: String(cString: idCStr),
                    dimension: dim,
                    factKey: String(cString: keyCStr),
                    title: String(cString: titleCStr),
                    detail: String(cString: detailCStr),
                    confidence: sqlite3_column_double(stmt, 5),
                    source: String(cString: srcCStr),
                    evidenceRef: evidence,
                    isPinned: sqlite3_column_int(stmt, 8) != 0,
                    isArchived: sqlite3_column_int(stmt, 9) != 0,
                    reinforcementCount: Int(sqlite3_column_int64(stmt, 10)),
                    createdAt: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 11)),
                    updatedAt: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 12))
                ))
            }
        }
        sqlite3_finalize(stmt)
        return items
    }
    
    
    func upsertKYCMemory(
        id: String? = nil,
        dimension: KYCDimension,
        factKey: String,
        title: String,
        detail: String = "",
        confidence: Double = 0.9,
        source: String = "user_explicit",
        evidenceRef: String? = nil,
        isPinned: Bool? = nil,
        actorBot: String = "Butler"
    ) {
        let cleanKey = factKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanKey.isEmpty, !cleanTitle.isEmpty else { return }
        
        let resolvedID = id ?? "\(dimension.rawValue):\(cleanKey)"
        let cleanDetail = detail.trimmingCharacters(in: .whitespacesAndNewlines)
        let clampedConf = min(1.0, max(0.1, confidence))
        let now = Date().timeIntervalSince1970
        let pinInt: Int32? = isPinned.map { $0 ? 1 : 0 }
        
        let sql = """
        INSERT INTO user_kyc_memories (
            id, dimension, fact_key, title, detail, confidence, source, evidence_ref,
            is_pinned, is_archived, reinforcement_count, created_at, updated_at
        )
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, COALESCE(?, 0), 0, 1, ?, ?)
        ON CONFLICT(dimension, fact_key) DO UPDATE SET
            title = excluded.title,
            detail = CASE WHEN excluded.detail != '' THEN excluded.detail ELSE user_kyc_memories.detail END,
            confidence = MAX(user_kyc_memories.confidence, excluded.confidence),
            source = excluded.source,
            evidence_ref = COALESCE(excluded.evidence_ref, user_kyc_memories.evidence_ref),
            is_pinned = COALESCE(?, user_kyc_memories.is_pinned),
            is_archived = 0,
            reinforcement_count = user_kyc_memories.reinforcement_count + 1,
            updated_at = excluded.updated_at;
        """
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(self.db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, resolvedID, -1, self.transientDestructor)
            sqlite3_bind_text(stmt, 2, dimension.rawValue, -1, self.transientDestructor)
            sqlite3_bind_text(stmt, 3, cleanKey, -1, self.transientDestructor)
            sqlite3_bind_text(stmt, 4, cleanTitle, -1, self.transientDestructor)
            sqlite3_bind_text(stmt, 5, cleanDetail, -1, self.transientDestructor)
            sqlite3_bind_double(stmt, 6, clampedConf)
            sqlite3_bind_text(stmt, 7, source, -1, self.transientDestructor)
            if let evidenceRef {
                sqlite3_bind_text(stmt, 8, evidenceRef, -1, self.transientDestructor)
            } else {
                sqlite3_bind_null(stmt, 8)
            }
            if let pinInt {
                sqlite3_bind_int(stmt, 9, pinInt)
            } else {
                sqlite3_bind_null(stmt, 9)
            }
            sqlite3_bind_double(stmt, 10, now)
            sqlite3_bind_double(stmt, 11, now)
            if let pinInt {
                sqlite3_bind_int(stmt, 12, pinInt)
            } else {
                sqlite3_bind_null(stmt, 12)
            }
            let rc = sqlite3_step(stmt)
            if rc != SQLITE_DONE {
                self.logSQLiteError(#function, code: rc)
            }
        }
        sqlite3_finalize(stmt)
        
        self.appendMemoryJournal(actorBot: actorBot, changeType: "upsert", dimension: dimension.rawValue, summary: cleanTitle)
    }
    
    
    func toggleKYCMemoryPinned(id: String, isPinned: Bool) {
        let sql = "UPDATE user_kyc_memories SET is_pinned = ?, updated_at = ? WHERE id = ?;"
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(self.db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_int(stmt, 1, isPinned ? 1 : 0)
            sqlite3_bind_double(stmt, 2, Date().timeIntervalSince1970)
            sqlite3_bind_text(stmt, 3, id, -1, self.transientDestructor)
            sqlite3_step(stmt)
        }
        sqlite3_finalize(stmt)
    }
    
    
    func deleteKYCMemory(idOrKey: String) {
        let sql = "DELETE FROM user_kyc_memories WHERE id = ? OR fact_key = ?;"
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(self.db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, idOrKey, -1, self.transientDestructor)
            sqlite3_bind_text(stmt, 2, idOrKey, -1, self.transientDestructor)
            sqlite3_step(stmt)
        }
        sqlite3_finalize(stmt)
    }
    
    
    func appendMemoryJournal(actorBot: String, changeType: String, dimension: String, summary: String) {
        let sql = "INSERT INTO user_memory_journal (timestamp, actor_bot, change_type, dimension, summary) VALUES (?, ?, ?, ?, ?);"
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(self.db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_double(stmt, 1, Date().timeIntervalSince1970)
            sqlite3_bind_text(stmt, 2, actorBot, -1, self.transientDestructor)
            sqlite3_bind_text(stmt, 3, changeType, -1, self.transientDestructor)
            sqlite3_bind_text(stmt, 4, dimension, -1, self.transientDestructor)
            sqlite3_bind_text(stmt, 5, summary, -1, self.transientDestructor)
            sqlite3_step(stmt)
        }
        sqlite3_finalize(stmt)
    }
    
    
    func fetchMemoryJournal(limit: Int = 50) -> [UserMemoryJournalEntry] {
        let sql = "SELECT id, timestamp, actor_bot, change_type, dimension, summary FROM user_memory_journal ORDER BY id DESC LIMIT ?;"
        var stmt: OpaquePointer?
        var items: [UserMemoryJournalEntry] = []
        if sqlite3_prepare_v2(self.db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_int64(stmt, 1, Int64(max(1, limit)))
            while sqlite3_step(stmt) == SQLITE_ROW {
                guard
                    let actorCStr = sqlite3_column_text(stmt, 2),
                    let typeCStr = sqlite3_column_text(stmt, 3),
                    let dimCStr = sqlite3_column_text(stmt, 4),
                    let sumCStr = sqlite3_column_text(stmt, 5)
                else { continue }
                items.append(UserMemoryJournalEntry(
                    id: sqlite3_column_int64(stmt, 0),
                    timestamp: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 1)),
                    actorBot: String(cString: actorCStr),
                    changeType: String(cString: typeCStr),
                    dimension: String(cString: dimCStr),
                    summary: String(cString: sumCStr)
                ))
            }
        }
        sqlite3_finalize(stmt)
        return items
    }
    
    
    // MARK: - Watchlist Stocks
    
    func fetchWatchlistStocks() -> [WatchlistStockRecord] {
        let sql = """
        SELECT instrument_id, namespace, symbol, name, eastmoney_secid, tencent_code,
               sort_order, thesis_note, alert_up_price, alert_down_price,
               last_price, last_change_pct, added_by, created_at, updated_at
        FROM user_watchlist_stocks
        ORDER BY sort_order ASC, updated_at DESC;
        """
        var stmt: OpaquePointer?
        var items: [WatchlistStockRecord] = []
        if sqlite3_prepare_v2(self.db, sql, -1, &stmt, nil) == SQLITE_OK {
            while sqlite3_step(stmt) == SQLITE_ROW {
                guard
                    let idCStr = sqlite3_column_text(stmt, 0),
                    let nsCStr = sqlite3_column_text(stmt, 1),
                    let symCStr = sqlite3_column_text(stmt, 2),
                    let nameCStr = sqlite3_column_text(stmt, 3),
                    let emCStr = sqlite3_column_text(stmt, 4),
                    let tcCStr = sqlite3_column_text(stmt, 5),
                    let noteCStr = sqlite3_column_text(stmt, 7),
                    let addedCStr = sqlite3_column_text(stmt, 12)
                else { continue }
                
                let upPrice = sqlite3_column_type(stmt, 8) == SQLITE_NULL ? nil : sqlite3_column_double(stmt, 8)
                let downPrice = sqlite3_column_type(stmt, 9) == SQLITE_NULL ? nil : sqlite3_column_double(stmt, 9)
                let lastPrice = sqlite3_column_type(stmt, 10) == SQLITE_NULL ? nil : sqlite3_column_double(stmt, 10)
                let lastChange = sqlite3_column_type(stmt, 11) == SQLITE_NULL ? nil : sqlite3_column_double(stmt, 11)
                items.append(WatchlistStockRecord(
                    instrumentID: String(cString: idCStr),
                    namespace: String(cString: nsCStr),
                    symbol: String(cString: symCStr),
                    name: String(cString: nameCStr),
                    eastmoneySecID: String(cString: emCStr),
                    tencentCode: String(cString: tcCStr),
                    sortOrder: Int(sqlite3_column_int(stmt, 6)),
                    thesisNote: String(cString: noteCStr),
                    alertUpPrice: upPrice,
                    alertDownPrice: downPrice,
                    lastPrice: lastPrice,
                    lastChangePct: lastChange,
                    addedBy: String(cString: addedCStr),
                    createdAt: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 13)),
                    updatedAt: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 14))
                ))
            }
        }
        sqlite3_finalize(stmt)
        return items
    }
    
    
    func upsertWatchlistStock(_ stock: WatchlistStockRecord) {
        let now = Date().timeIntervalSince1970
        let sql = """
        INSERT INTO user_watchlist_stocks (
            instrument_id, namespace, symbol, name, eastmoney_secid, tencent_code,
            sort_order, thesis_note, alert_up_price, alert_down_price,
            last_price, last_change_pct, added_by, created_at, updated_at
        )
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(instrument_id) DO UPDATE SET
            namespace = excluded.namespace,
            symbol = excluded.symbol,
            name = excluded.name,
            eastmoney_secid = CASE WHEN excluded.eastmoney_secid != '' THEN excluded.eastmoney_secid ELSE user_watchlist_stocks.eastmoney_secid END,
            tencent_code = CASE WHEN excluded.tencent_code != '' THEN excluded.tencent_code ELSE user_watchlist_stocks.tencent_code END,
            thesis_note = CASE WHEN excluded.thesis_note != '' THEN excluded.thesis_note ELSE user_watchlist_stocks.thesis_note END,
            alert_up_price = COALESCE(excluded.alert_up_price, user_watchlist_stocks.alert_up_price),
            alert_down_price = COALESCE(excluded.alert_down_price, user_watchlist_stocks.alert_down_price),
            last_price = COALESCE(excluded.last_price, user_watchlist_stocks.last_price),
            last_change_pct = COALESCE(excluded.last_change_pct, user_watchlist_stocks.last_change_pct),
            updated_at = excluded.updated_at;
        """
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(self.db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, stock.instrumentID, -1, self.transientDestructor)
            sqlite3_bind_text(stmt, 2, stock.namespace, -1, self.transientDestructor)
            sqlite3_bind_text(stmt, 3, stock.symbol, -1, self.transientDestructor)
            sqlite3_bind_text(stmt, 4, stock.name, -1, self.transientDestructor)
            sqlite3_bind_text(stmt, 5, stock.eastmoneySecID, -1, self.transientDestructor)
            sqlite3_bind_text(stmt, 6, stock.tencentCode, -1, self.transientDestructor)
            sqlite3_bind_int(stmt, 7, Int32(stock.sortOrder))
            sqlite3_bind_text(stmt, 8, stock.thesisNote, -1, self.transientDestructor)
            Self.bindOptionalDouble(stmt, index: 9, value: stock.alertUpPrice)
            Self.bindOptionalDouble(stmt, index: 10, value: stock.alertDownPrice)
            Self.bindOptionalDouble(stmt, index: 11, value: stock.lastPrice)
            Self.bindOptionalDouble(stmt, index: 12, value: stock.lastChangePct)
            sqlite3_bind_text(stmt, 13, stock.addedBy, -1, self.transientDestructor)
            sqlite3_bind_double(stmt, 14, stock.createdAt.timeIntervalSince1970)
            sqlite3_bind_double(stmt, 15, now)
            let rc = sqlite3_step(stmt)
            if rc != SQLITE_DONE {
                self.logSQLiteError(#function, code: rc)
            }
        }
        sqlite3_finalize(stmt)
    }
    
    
    func updateWatchlistStockQuote(instrumentID: String, lastPrice: Double, changePercent: Double) {
        let sql = "UPDATE user_watchlist_stocks SET last_price = ?, last_change_pct = ?, updated_at = ? WHERE instrument_id = ?;"
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(self.db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_double(stmt, 1, lastPrice)
            sqlite3_bind_double(stmt, 2, changePercent)
            sqlite3_bind_double(stmt, 3, Date().timeIntervalSince1970)
            sqlite3_bind_text(stmt, 4, instrumentID, -1, self.transientDestructor)
            sqlite3_step(stmt)
        }
        sqlite3_finalize(stmt)
    }
    
    
    func deleteWatchlistStock(instrumentIDOrSymbol: String) {
        let sql = "DELETE FROM user_watchlist_stocks WHERE instrument_id = ? OR lower(symbol) = lower(?) OR name = ?;"
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(self.db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, instrumentIDOrSymbol, -1, self.transientDestructor)
            sqlite3_bind_text(stmt, 2, instrumentIDOrSymbol, -1, self.transientDestructor)
            sqlite3_bind_text(stmt, 3, instrumentIDOrSymbol, -1, self.transientDestructor)
            sqlite3_step(stmt)
        }
        sqlite3_finalize(stmt)
    }
    
    
    func reorderWatchlistStocks(orderedIDs: [String]) {
        self.withTransaction {
            let sql = "UPDATE user_watchlist_stocks SET sort_order = ? WHERE instrument_id = ?;"
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(self.db, sql, -1, &stmt, nil) == SQLITE_OK {
                for (idx, id) in orderedIDs.enumerated() {
                    sqlite3_reset(stmt)
                    sqlite3_clear_bindings(stmt)
                    sqlite3_bind_int(stmt, 1, Int32(idx))
                    sqlite3_bind_text(stmt, 2, id, -1, self.transientDestructor)
                    sqlite3_step(stmt)
                }
            }
            sqlite3_finalize(stmt)
        }
    }
    
    
    // MARK: - Podcasts
    
    func fetchStoredPodcasts() -> [StoredPodcastRecord] {
        let sql = """
        SELECT id, item_kind, platform, title, show_name, source_url, audio_url, artwork_url,
               duration_sec, playback_position_sec, is_saved, topic_tag, notes, last_played_at, created_at, updated_at
        FROM user_podcasts
        ORDER BY is_saved DESC, last_played_at DESC, updated_at DESC;
        """
        var stmt: OpaquePointer?
        var items: [StoredPodcastRecord] = []
        if sqlite3_prepare_v2(self.db, sql, -1, &stmt, nil) == SQLITE_OK {
            while sqlite3_step(stmt) == SQLITE_ROW {
                guard
                    let idCStr = sqlite3_column_text(stmt, 0),
                    let kindCStr = sqlite3_column_text(stmt, 1),
                    let platCStr = sqlite3_column_text(stmt, 2),
                    let titleCStr = sqlite3_column_text(stmt, 3),
                    let showCStr = sqlite3_column_text(stmt, 4),
                    let srcCStr = sqlite3_column_text(stmt, 5),
                    let audCStr = sqlite3_column_text(stmt, 6),
                    let artCStr = sqlite3_column_text(stmt, 7),
                    let tagCStr = sqlite3_column_text(stmt, 11),
                    let notesCStr = sqlite3_column_text(stmt, 12)
                else { continue }
                
                let lastPlayed: Date? = sqlite3_column_type(stmt, 13) == SQLITE_NULL
                    ? nil
                    : Date(timeIntervalSince1970: sqlite3_column_double(stmt, 13))
                items.append(StoredPodcastRecord(
                    id: String(cString: idCStr),
                    itemKind: String(cString: kindCStr),
                    platform: String(cString: platCStr),
                    title: String(cString: titleCStr),
                    showName: String(cString: showCStr),
                    sourceURL: String(cString: srcCStr),
                    audioURL: String(cString: audCStr),
                    artworkURL: String(cString: artCStr),
                    durationSec: sqlite3_column_double(stmt, 8),
                    playbackPositionSec: sqlite3_column_double(stmt, 9),
                    isSaved: sqlite3_column_int(stmt, 10) != 0,
                    topicTag: String(cString: tagCStr),
                    notes: String(cString: notesCStr),
                    lastPlayedAt: lastPlayed,
                    createdAt: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 14)),
                    updatedAt: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 15))
                ))
            }
        }
        sqlite3_finalize(stmt)
        return items
    }
    
    
    func upsertStoredPodcast(_ podcast: StoredPodcastRecord) {
        let now = Date().timeIntervalSince1970
        let sql = """
        INSERT INTO user_podcasts (
            id, item_kind, platform, title, show_name, source_url, audio_url, artwork_url,
            duration_sec, playback_position_sec, is_saved, topic_tag, notes, last_played_at, created_at, updated_at
        )
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET
            title = excluded.title,
            show_name = CASE WHEN excluded.show_name != '' THEN excluded.show_name ELSE user_podcasts.show_name END,
            source_url = excluded.source_url,
            audio_url = CASE WHEN excluded.audio_url != '' THEN excluded.audio_url ELSE user_podcasts.audio_url END,
            artwork_url = CASE WHEN excluded.artwork_url != '' THEN excluded.artwork_url ELSE user_podcasts.artwork_url END,
            duration_sec = MAX(user_podcasts.duration_sec, excluded.duration_sec),
            playback_position_sec = MAX(excluded.playback_position_sec, user_podcasts.playback_position_sec),
            is_saved = excluded.is_saved,
            topic_tag = CASE WHEN excluded.topic_tag != '' THEN excluded.topic_tag ELSE user_podcasts.topic_tag END,
            notes = CASE WHEN excluded.notes != '' THEN excluded.notes ELSE user_podcasts.notes END,
            last_played_at = COALESCE(excluded.last_played_at, user_podcasts.last_played_at),
            updated_at = excluded.updated_at;
        """
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(self.db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, podcast.id, -1, self.transientDestructor)
            sqlite3_bind_text(stmt, 2, podcast.itemKind, -1, self.transientDestructor)
            sqlite3_bind_text(stmt, 3, podcast.platform, -1, self.transientDestructor)
            sqlite3_bind_text(stmt, 4, podcast.title, -1, self.transientDestructor)
            sqlite3_bind_text(stmt, 5, podcast.showName, -1, self.transientDestructor)
            sqlite3_bind_text(stmt, 6, podcast.sourceURL, -1, self.transientDestructor)
            sqlite3_bind_text(stmt, 7, podcast.audioURL, -1, self.transientDestructor)
            sqlite3_bind_text(stmt, 8, podcast.artworkURL, -1, self.transientDestructor)
            sqlite3_bind_double(stmt, 9, podcast.durationSec)
            sqlite3_bind_double(stmt, 10, podcast.playbackPositionSec)
            sqlite3_bind_int(stmt, 11, podcast.isSaved ? 1 : 0)
            sqlite3_bind_text(stmt, 12, podcast.topicTag, -1, self.transientDestructor)
            sqlite3_bind_text(stmt, 13, podcast.notes, -1, self.transientDestructor)
            Self.bindOptionalDouble(stmt, index: 14, value: podcast.lastPlayedAt?.timeIntervalSince1970)
            sqlite3_bind_double(stmt, 15, podcast.createdAt.timeIntervalSince1970)
            sqlite3_bind_double(stmt, 16, now)
            let rc = sqlite3_step(stmt)
            if rc != SQLITE_DONE {
                self.logSQLiteError(#function, code: rc)
            }
        }
        sqlite3_finalize(stmt)
    }
    
    
    func updatePodcastPlaybackPosition(id: String, positionSec: Double, durationSec: Double) {
        let now = Date().timeIntervalSince1970
        let sql = """
        UPDATE user_podcasts
        SET playback_position_sec = ?,
            duration_sec = CASE WHEN ? > 0 THEN ? ELSE duration_sec END,
            last_played_at = ?,
            updated_at = ?
        WHERE id = ?;
        """
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(self.db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_double(stmt, 1, max(0, positionSec))
            sqlite3_bind_double(stmt, 2, durationSec)
            sqlite3_bind_double(stmt, 3, durationSec)
            sqlite3_bind_double(stmt, 4, now)
            sqlite3_bind_double(stmt, 5, now)
            sqlite3_bind_text(stmt, 6, id, -1, self.transientDestructor)
            sqlite3_step(stmt)
        }
        sqlite3_finalize(stmt)
    }
    
    
    func deleteStoredPodcast(id: String) {
        let sql = "DELETE FROM user_podcasts WHERE id = ?;"
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(self.db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, id, -1, self.transientDestructor)
            sqlite3_step(stmt)
        }
        sqlite3_finalize(stmt)
    }
    
    
    // MARK: - Followed Blogs & Feeds
    
    func fetchFollowedFeeds() -> [FollowedFeedRecord] {
        let sql = """
        SELECT id, title, site_url, feed_url, category, author, notes, is_pinned, added_by, created_at, updated_at
        FROM user_followed_feeds
        ORDER BY is_pinned DESC, updated_at DESC;
        """
        var stmt: OpaquePointer?
        var items: [FollowedFeedRecord] = []
        if sqlite3_prepare_v2(self.db, sql, -1, &stmt, nil) == SQLITE_OK {
            while sqlite3_step(stmt) == SQLITE_ROW {
                guard
                    let idCStr = sqlite3_column_text(stmt, 0),
                    let titleCStr = sqlite3_column_text(stmt, 1),
                    let siteCStr = sqlite3_column_text(stmt, 2),
                    let feedCStr = sqlite3_column_text(stmt, 3),
                    let catCStr = sqlite3_column_text(stmt, 4),
                    let authCStr = sqlite3_column_text(stmt, 5),
                    let notesCStr = sqlite3_column_text(stmt, 6),
                    let addedCStr = sqlite3_column_text(stmt, 8)
                else { continue }
                items.append(FollowedFeedRecord(
                    id: String(cString: idCStr),
                    title: String(cString: titleCStr),
                    siteURL: String(cString: siteCStr),
                    feedURL: String(cString: feedCStr),
                    category: String(cString: catCStr),
                    author: String(cString: authCStr),
                    notes: String(cString: notesCStr),
                    isPinned: sqlite3_column_int(stmt, 7) != 0,
                    addedBy: String(cString: addedCStr),
                    createdAt: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 9)),
                    updatedAt: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 10))
                ))
            }
        }
        sqlite3_finalize(stmt)
        return items
    }
    
    
    func upsertFollowedFeed(_ feed: FollowedFeedRecord) {
        let now = Date().timeIntervalSince1970
        let sql = """
        INSERT INTO user_followed_feeds (
            id, title, site_url, feed_url, category, author, notes, is_pinned, added_by, created_at, updated_at
        )
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET
            title = excluded.title,
            site_url = excluded.site_url,
            feed_url = CASE WHEN excluded.feed_url != '' THEN excluded.feed_url ELSE user_followed_feeds.feed_url END,
            category = CASE WHEN excluded.category != '' THEN excluded.category ELSE user_followed_feeds.category END,
            author = CASE WHEN excluded.author != '' THEN excluded.author ELSE user_followed_feeds.author END,
            notes = CASE WHEN excluded.notes != '' THEN excluded.notes ELSE user_followed_feeds.notes END,
            is_pinned = excluded.is_pinned,
            updated_at = excluded.updated_at;
        """
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(self.db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, feed.id, -1, self.transientDestructor)
            sqlite3_bind_text(stmt, 2, feed.title, -1, self.transientDestructor)
            sqlite3_bind_text(stmt, 3, feed.siteURL, -1, self.transientDestructor)
            sqlite3_bind_text(stmt, 4, feed.feedURL, -1, self.transientDestructor)
            sqlite3_bind_text(stmt, 5, feed.category, -1, self.transientDestructor)
            sqlite3_bind_text(stmt, 6, feed.author, -1, self.transientDestructor)
            sqlite3_bind_text(stmt, 7, feed.notes, -1, self.transientDestructor)
            sqlite3_bind_int(stmt, 8, feed.isPinned ? 1 : 0)
            sqlite3_bind_text(stmt, 9, feed.addedBy, -1, self.transientDestructor)
            sqlite3_bind_double(stmt, 10, feed.createdAt.timeIntervalSince1970)
            sqlite3_bind_double(stmt, 11, now)
            let rc = sqlite3_step(stmt)
            if rc != SQLITE_DONE {
                self.logSQLiteError(#function, code: rc)
            }
        }
        sqlite3_finalize(stmt)
    }
    
    
    func deleteFollowedFeed(id: String) {
        let sql = "DELETE FROM user_followed_feeds WHERE id = ?;"
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(self.db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, id, -1, self.transientDestructor)
            sqlite3_step(stmt)
        }
        sqlite3_finalize(stmt)
    }
    
    
    // MARK: - Followed X / Social Creators
    
    func fetchFollowedCreators() -> [FollowedCreatorRecord] {
        let sql = """
        SELECT id, platform, handle, display_name, profile_url, avatar_url,
               focus_tags, why_following, is_pinned, added_by, created_at, updated_at
        FROM user_followed_creators
        ORDER BY is_pinned DESC, updated_at DESC;
        """
        var stmt: OpaquePointer?
        var items: [FollowedCreatorRecord] = []
        if sqlite3_prepare_v2(self.db, sql, -1, &stmt, nil) == SQLITE_OK {
            while sqlite3_step(stmt) == SQLITE_ROW {
                guard
                    let idCStr = sqlite3_column_text(stmt, 0),
                    let platCStr = sqlite3_column_text(stmt, 1),
                    let handleCStr = sqlite3_column_text(stmt, 2),
                    let nameCStr = sqlite3_column_text(stmt, 3),
                    let profCStr = sqlite3_column_text(stmt, 4),
                    let avCStr = sqlite3_column_text(stmt, 5),
                    let tagsCStr = sqlite3_column_text(stmt, 6),
                    let whyCStr = sqlite3_column_text(stmt, 7),
                    let addedCStr = sqlite3_column_text(stmt, 9)
                else { continue }
                items.append(FollowedCreatorRecord(
                    id: String(cString: idCStr),
                    platform: String(cString: platCStr),
                    handle: String(cString: handleCStr),
                    displayName: String(cString: nameCStr),
                    profileURL: String(cString: profCStr),
                    avatarURL: String(cString: avCStr),
                    focusTags: String(cString: tagsCStr),
                    whyFollowing: String(cString: whyCStr),
                    isPinned: sqlite3_column_int(stmt, 8) != 0,
                    addedBy: String(cString: addedCStr),
                    createdAt: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 10)),
                    updatedAt: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 11))
                ))
            }
        }
        sqlite3_finalize(stmt)
        return items
    }
    
    
    func upsertFollowedCreator(_ creator: FollowedCreatorRecord) {
        let now = Date().timeIntervalSince1970
        let sql = """
        INSERT INTO user_followed_creators (
            id, platform, handle, display_name, profile_url, avatar_url,
            focus_tags, why_following, is_pinned, added_by, created_at, updated_at
        )
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET
            display_name = excluded.display_name,
            profile_url = CASE WHEN excluded.profile_url != '' THEN excluded.profile_url ELSE user_followed_creators.profile_url END,
            focus_tags = CASE WHEN excluded.focus_tags != '' THEN excluded.focus_tags ELSE user_followed_creators.focus_tags END,
            why_following = CASE WHEN excluded.why_following != '' THEN excluded.why_following ELSE user_followed_creators.why_following END,
            is_pinned = excluded.is_pinned,
            updated_at = excluded.updated_at;
        """
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(self.db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, creator.id, -1, self.transientDestructor)
            sqlite3_bind_text(stmt, 2, creator.platform, -1, self.transientDestructor)
            sqlite3_bind_text(stmt, 3, creator.handle, -1, self.transientDestructor)
            sqlite3_bind_text(stmt, 4, creator.displayName, -1, self.transientDestructor)
            sqlite3_bind_text(stmt, 5, creator.profileURL, -1, self.transientDestructor)
            sqlite3_bind_text(stmt, 6, creator.avatarURL, -1, self.transientDestructor)
            sqlite3_bind_text(stmt, 7, creator.focusTags, -1, self.transientDestructor)
            sqlite3_bind_text(stmt, 8, creator.whyFollowing, -1, self.transientDestructor)
            sqlite3_bind_int(stmt, 9, creator.isPinned ? 1 : 0)
            sqlite3_bind_text(stmt, 10, creator.addedBy, -1, self.transientDestructor)
            sqlite3_bind_double(stmt, 11, creator.createdAt.timeIntervalSince1970)
            sqlite3_bind_double(stmt, 12, now)
            let rc = sqlite3_step(stmt)
            if rc != SQLITE_DONE {
                self.logSQLiteError(#function, code: rc)
            }
        }
        sqlite3_finalize(stmt)
    }
    
    
    func deleteFollowedCreator(id: String) {
        let sql = "DELETE FROM user_followed_creators WHERE id = ?;"
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(self.db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, id, -1, self.transientDestructor)
            sqlite3_step(stmt)
        }
        sqlite3_finalize(stmt)
    }
    
    
    // MARK: - Butler Sessions, Messages & Live Workspace / Agent Queue
    
    private func ensureButlerMessageSessionColumnExists() {
        var stmt: OpaquePointer?
        var hasColumn = false
        if sqlite3_prepare_v2(self.db, "PRAGMA table_info(butler_messages);", -1, &stmt, nil) == SQLITE_OK {
            while sqlite3_step(stmt) == SQLITE_ROW {
                if let nameCStr = sqlite3_column_text(stmt, 1),
                   String(cString: nameCStr) == "session_id"
                {
                    hasColumn = true
                    break
                }
            }
        }
        sqlite3_finalize(stmt)
        if !hasColumn {
            self.executeSQL("ALTER TABLE butler_messages ADD COLUMN session_id TEXT NOT NULL DEFAULT 'default';")
        }
    }
    
    
    private func migrateLegacyButlerMessagesToSessionIfNeeded() {
        var stmt: OpaquePointer?
        var earliestTitle = AppLanguage.text("历史对话", en: "Previous Chat")
        var minTS = Date().timeIntervalSince1970
        var maxTS = minTS
        var hasDefaultMessages = false
        
        let checkSQL = """
        SELECT MIN(created_at), MAX(created_at),
               (SELECT content FROM butler_messages WHERE session_id = 'default' AND role = 'user' ORDER BY created_at ASC LIMIT 1)
        FROM butler_messages
        WHERE session_id = 'default';
        """
        if sqlite3_prepare_v2(self.db, checkSQL, -1, &stmt, nil) == SQLITE_OK {
            if sqlite3_step(stmt) == SQLITE_ROW, sqlite3_column_type(stmt, 0) != SQLITE_NULL {
                hasDefaultMessages = true
                minTS = sqlite3_column_double(stmt, 0)
                maxTS = sqlite3_column_double(stmt, 1)
                if let cStr = sqlite3_column_text(stmt, 2) {
                    let condensed = Self.condensedSessionTitle(from: String(cString: cStr))
                    if !condensed.isEmpty {
                        earliestTitle = condensed
                    }
                }
            }
        }
        sqlite3_finalize(stmt)
        guard hasDefaultMessages else { return }
        
        let insertSQL = """
        INSERT OR IGNORE INTO butler_sessions (id, title, is_pinned, created_at, updated_at)
        VALUES ('default', ?, 0, ?, ?);
        """
        var insStmt: OpaquePointer?
        if sqlite3_prepare_v2(self.db, insertSQL, -1, &insStmt, nil) == SQLITE_OK {
            sqlite3_bind_text(insStmt, 1, earliestTitle, -1, self.transientDestructor)
            sqlite3_bind_double(insStmt, 2, minTS)
            sqlite3_bind_double(insStmt, 3, maxTS)
            sqlite3_step(insStmt)
        }
        sqlite3_finalize(insStmt)
    }
    
    
    private static func condensedSessionTitle(from raw: String) -> String {
        let singleLine = raw
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard singleLine.count > 16 else { return singleLine }
        return String(singleLine.prefix(16))
    }
    
    
    func fetchButlerSessions() -> [ButlerSessionRecord] {
        let sql = """
        SELECT s.id,
               s.title,
               s.is_pinned,
               s.created_at,
               s.updated_at,
               COALESCE((SELECT SUBSTR(m.content, 1, 200) FROM butler_messages m WHERE m.session_id = s.id ORDER BY m.created_at DESC LIMIT 1), ''),
               (SELECT COUNT(*) FROM butler_messages m WHERE m.session_id = s.id)
        FROM butler_sessions s
        ORDER BY s.is_pinned DESC, s.updated_at DESC;
        """
        var stmt: OpaquePointer?
        var sessions: [ButlerSessionRecord] = []
        if sqlite3_prepare_v2(self.db, sql, -1, &stmt, nil) == SQLITE_OK {
            while sqlite3_step(stmt) == SQLITE_ROW {
                guard
                    let idCStr = sqlite3_column_text(stmt, 0),
                    let titleCStr = sqlite3_column_text(stmt, 1)
                else { continue }
                let preview = sqlite3_column_text(stmt, 5).map { String(cString: $0) } ?? ""
                sessions.append(ButlerSessionRecord(
                    id: String(cString: idCStr),
                    title: String(cString: titleCStr),
                    isPinned: sqlite3_column_int(stmt, 2) != 0,
                    createdAt: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 3)),
                    updatedAt: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 4)),
                    previewText: preview,
                    messageCount: Int(sqlite3_column_int64(stmt, 6))
                ))
            }
        }
        sqlite3_finalize(stmt)
        return sessions
    }
    
    
    @discardableResult
    func createButlerSession(
        id: String = UUID().uuidString,
        title: String = AppLanguage.text("新对话", en: "New Chat")
    ) -> ButlerSessionRecord {
        let now = Date()
        let nowTS = now.timeIntervalSince1970
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedTitle = cleanTitle.isEmpty ? AppLanguage.text("新对话", en: "New Chat") : cleanTitle
        let sql = """
        INSERT OR IGNORE INTO butler_sessions (id, title, is_pinned, created_at, updated_at)
        VALUES (?, ?, 0, ?, ?);
        """
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(self.db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, id, -1, self.transientDestructor)
            sqlite3_bind_text(stmt, 2, resolvedTitle, -1, self.transientDestructor)
            sqlite3_bind_double(stmt, 3, nowTS)
            sqlite3_bind_double(stmt, 4, nowTS)
            sqlite3_step(stmt)
        }
        sqlite3_finalize(stmt)
        return ButlerSessionRecord(
            id: id,
            title: resolvedTitle,
            isPinned: false,
            createdAt: now,
            updatedAt: now,
            previewText: "",
            messageCount: 0
        )
    }
    
    
    func renameButlerSession(id: String, title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let sql = "UPDATE butler_sessions SET title = ?, updated_at = ? WHERE id = ?;"
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(self.db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, trimmed, -1, self.transientDestructor)
            sqlite3_bind_double(stmt, 2, Date().timeIntervalSince1970)
            sqlite3_bind_text(stmt, 3, id, -1, self.transientDestructor)
            sqlite3_step(stmt)
        }
        sqlite3_finalize(stmt)
    }
    
    
    func toggleButlerSessionPinned(id: String, isPinned: Bool) {
        let sql = "UPDATE butler_sessions SET is_pinned = ? WHERE id = ?;"
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(self.db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_int(stmt, 1, isPinned ? 1 : 0)
            sqlite3_bind_text(stmt, 2, id, -1, self.transientDestructor)
            sqlite3_step(stmt)
        }
        sqlite3_finalize(stmt)
    }
    
    
    func deleteButlerSession(id: String) {
        self.withTransaction {
            let msgSQL = "DELETE FROM butler_messages WHERE session_id = ?;"
            var msgStmt: OpaquePointer?
            if sqlite3_prepare_v2(self.db, msgSQL, -1, &msgStmt, nil) == SQLITE_OK {
                sqlite3_bind_text(msgStmt, 1, id, -1, self.transientDestructor)
                sqlite3_step(msgStmt)
            }
            sqlite3_finalize(msgStmt)
            
            let sessSQL = "DELETE FROM butler_sessions WHERE id = ?;"
            var sessStmt: OpaquePointer?
            if sqlite3_prepare_v2(self.db, sessSQL, -1, &sessStmt, nil) == SQLITE_OK {
                sqlite3_bind_text(sessStmt, 1, id, -1, self.transientDestructor)
                sqlite3_step(sessStmt)
            }
            sqlite3_finalize(sessStmt)
        }
    }
    
    
    func fetchButlerMessages(sessionID: String? = nil, limit: Int = 120) -> [ButlerChatMessage] {
        let sql: String = if sessionID != nil {
            """
            SELECT id, session_id, role, content, actions_json, created_at
            FROM (
                SELECT id, session_id, role, content, actions_json, created_at
                FROM butler_messages
                WHERE session_id = ?
                ORDER BY created_at DESC
                LIMIT ?
            )
            ORDER BY created_at ASC;
            """
        } else {
            """
            SELECT id, session_id, role, content, actions_json, created_at
            FROM (
                SELECT id, session_id, role, content, actions_json, created_at
                FROM butler_messages
                ORDER BY created_at DESC
                LIMIT ?
            )
            ORDER BY created_at ASC;
            """
        }
        var stmt: OpaquePointer?
        var items: [ButlerChatMessage] = []
        if sqlite3_prepare_v2(self.db, sql, -1, &stmt, nil) == SQLITE_OK {
            if let sessionID {
                sqlite3_bind_text(stmt, 1, sessionID, -1, self.transientDestructor)
                sqlite3_bind_int64(stmt, 2, Int64(max(1, limit)))
            } else {
                sqlite3_bind_int64(stmt, 1, Int64(max(1, limit)))
            }
            while sqlite3_step(stmt) == SQLITE_ROW {
                guard
                    let idCStr = sqlite3_column_text(stmt, 0),
                    let sessCStr = sqlite3_column_text(stmt, 1),
                    let roleCStr = sqlite3_column_text(stmt, 2),
                    let contentCStr = sqlite3_column_text(stmt, 3),
                    let actionsCStr = sqlite3_column_text(stmt, 4)
                else { continue }
                items.append(ButlerChatMessage(
                    id: String(cString: idCStr),
                    sessionID: String(cString: sessCStr),
                    role: String(cString: roleCStr),
                    content: String(cString: contentCStr),
                    actionsJSON: String(cString: actionsCStr),
                    createdAt: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 5))
                ))
            }
        }
        sqlite3_finalize(stmt)
        return items
    }
    
    
    func appendButlerMessage(_ message: ButlerChatMessage) {
        let resolvedSessionID = message.sessionID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "default"
            : message.sessionID
        self.withTransaction {
            _ = self.createButlerSession(id: resolvedSessionID)
            
            let sql = "INSERT OR REPLACE INTO butler_messages (id, session_id, role, content, actions_json, created_at) VALUES (?, ?, ?, ?, ?, ?);"
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(self.db, sql, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_text(stmt, 1, message.id, -1, self.transientDestructor)
                sqlite3_bind_text(stmt, 2, resolvedSessionID, -1, self.transientDestructor)
                sqlite3_bind_text(stmt, 3, message.role, -1, self.transientDestructor)
                sqlite3_bind_text(stmt, 4, message.content, -1, self.transientDestructor)
                sqlite3_bind_text(stmt, 5, message.actionsJSON, -1, self.transientDestructor)
                sqlite3_bind_double(stmt, 6, message.createdAt.timeIntervalSince1970)
                let rc = sqlite3_step(stmt)
                if rc != SQLITE_DONE {
                    self.logSQLiteError(#function, code: rc)
                }
            }
            sqlite3_finalize(stmt)
            
            // Update session updated_at and auto-title untitled sessions on the first user turn
            let ts = message.createdAt.timeIntervalSince1970
            if message.role == "user" {
                let candidateTitle = Self.condensedSessionTitle(from: message.content)
                if !candidateTitle.isEmpty {
                    let titleSQL = """
                    UPDATE butler_sessions
                    SET title = CASE WHEN title IN ('新对话', 'New Chat', '历史对话', 'Previous Chat') THEN ? ELSE title END,
                        updated_at = MAX(updated_at, ?)
                    WHERE id = ?;
                    """
                    var tStmt: OpaquePointer?
                    if sqlite3_prepare_v2(self.db, titleSQL, -1, &tStmt, nil) == SQLITE_OK {
                        sqlite3_bind_text(tStmt, 1, candidateTitle, -1, self.transientDestructor)
                        sqlite3_bind_double(tStmt, 2, ts)
                        sqlite3_bind_text(tStmt, 3, resolvedSessionID, -1, self.transientDestructor)
                        sqlite3_step(tStmt)
                    }
                    sqlite3_finalize(tStmt)
                    return
                }
            }
            let touchSQL = "UPDATE butler_sessions SET updated_at = MAX(updated_at, ?) WHERE id = ?;"
            var touchStmt: OpaquePointer?
            if sqlite3_prepare_v2(self.db, touchSQL, -1, &touchStmt, nil) == SQLITE_OK {
                sqlite3_bind_double(touchStmt, 1, ts)
                sqlite3_bind_text(touchStmt, 2, resolvedSessionID, -1, self.transientDestructor)
                sqlite3_step(touchStmt)
            }
            sqlite3_finalize(touchStmt)
        }
    }
    
    
    func clearButlerMessages(sessionID: String? = nil) {
        if let sessionID {
            let sql = "DELETE FROM butler_messages WHERE session_id = ?;"
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(self.db, sql, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_text(stmt, 1, sessionID, -1, self.transientDestructor)
                sqlite3_step(stmt)
            }
            sqlite3_finalize(stmt)
        } else {
            self.executeSQL("DELETE FROM butler_messages;")
            self.executeSQL("DELETE FROM butler_sessions;")
        }
    }
    
    
    func saveWorkspaceLiveState(slot: String = "active_workspace", payloadJSON: String) {
        let sql = """
        INSERT INTO workspace_live_state (slot, payload_json, updated_at)
        VALUES (?, ?, ?)
        ON CONFLICT(slot) DO UPDATE SET payload_json = excluded.payload_json, updated_at = excluded.updated_at;
        """
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(self.db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, slot, -1, self.transientDestructor)
            sqlite3_bind_text(stmt, 2, payloadJSON, -1, self.transientDestructor)
            sqlite3_bind_double(stmt, 3, Date().timeIntervalSince1970)
            sqlite3_step(stmt)
        }
        sqlite3_finalize(stmt)
    }
    
    
    func queryWorkspaceLiveState(slot: String = "active_workspace") -> String? {
        let sql = "SELECT payload_json FROM workspace_live_state WHERE slot = ? LIMIT 1;"
        var stmt: OpaquePointer?
        var result: String?
        if sqlite3_prepare_v2(self.db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, slot, -1, self.transientDestructor)
            if sqlite3_step(stmt) == SQLITE_ROW, let cStr = sqlite3_column_text(stmt, 0) {
                result = String(cString: cStr)
            }
        }
        sqlite3_finalize(stmt)
        return result
    }
    
    
    @discardableResult
    func enqueueAgentCommand(actionType: String, payloadJSON: String) -> Int64 {
        let sql = "INSERT INTO agent_command_queue (action_type, payload_json, status, created_at) VALUES (?, ?, 'pending', ?);"
        var stmt: OpaquePointer?
        var insertedID: Int64 = 0
        if sqlite3_prepare_v2(self.db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, actionType, -1, self.transientDestructor)
            sqlite3_bind_text(stmt, 2, payloadJSON, -1, self.transientDestructor)
            sqlite3_bind_double(stmt, 3, Date().timeIntervalSince1970)
            if sqlite3_step(stmt) == SQLITE_DONE {
                insertedID = sqlite3_last_insert_rowid(self.db)
            }
        }
        sqlite3_finalize(stmt)
        return insertedID
    }
    
    
    func fetchPendingAgentCommands(limit: Int = 20) -> [QueuedAgentCommand] {
        let sql = """
        SELECT id, action_type, payload_json, status, result_note, created_at, executed_at
        FROM agent_command_queue
        WHERE status = 'pending'
        ORDER BY id ASC
        LIMIT ?;
        """
        var stmt: OpaquePointer?
        var items: [QueuedAgentCommand] = []
        if sqlite3_prepare_v2(self.db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_int64(stmt, 1, Int64(max(1, limit)))
            while sqlite3_step(stmt) == SQLITE_ROW {
                guard
                    let typeCStr = sqlite3_column_text(stmt, 1),
                    let payloadCStr = sqlite3_column_text(stmt, 2),
                    let statusCStr = sqlite3_column_text(stmt, 3),
                    let noteCStr = sqlite3_column_text(stmt, 4)
                else { continue }
                let execDate: Date? = sqlite3_column_type(stmt, 6) == SQLITE_NULL
                    ? nil
                    : Date(timeIntervalSince1970: sqlite3_column_double(stmt, 6))
                items.append(QueuedAgentCommand(
                    id: sqlite3_column_int64(stmt, 0),
                    actionType: String(cString: typeCStr),
                    payloadJSON: String(cString: payloadCStr),
                    status: String(cString: statusCStr),
                    resultNote: String(cString: noteCStr),
                    createdAt: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 5)),
                    executedAt: execDate
                ))
            }
        }
        sqlite3_finalize(stmt)
        return items
    }
    
    
    func markAgentCommandExecuted(id: Int64, status: String = "executed", resultNote: String = "") {
        let sql = "UPDATE agent_command_queue SET status = ?, result_note = ?, executed_at = ? WHERE id = ?;"
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(self.db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, status, -1, self.transientDestructor)
            sqlite3_bind_text(stmt, 2, resultNote, -1, self.transientDestructor)
            sqlite3_bind_double(stmt, 3, Date().timeIntervalSince1970)
            sqlite3_bind_int64(stmt, 4, id)
            sqlite3_step(stmt)
        }
        sqlite3_finalize(stmt)
    }
    
    
    // MARK: - Private SQLite Bind Helpers
    
    private static func bindOptionalDouble(_ stmt: OpaquePointer?, index: Int32, value: Double?) {
        if let value {
            sqlite3_bind_double(stmt, index, value)
        } else {
            sqlite3_bind_null(stmt, index)
        }
    }
}
