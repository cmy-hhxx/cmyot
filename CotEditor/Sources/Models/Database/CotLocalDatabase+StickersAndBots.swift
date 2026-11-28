//
//  CotLocalDatabase+StickersAndBots.swift
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

/// Persisted Meeting Room session metadata.
nonisolated struct MeetingRoomSession: Identifiable, Codable, Equatable, Sendable {
    var id: String
    var title: String
    var isPinned: Bool
    var participantIDs: [String]
    var createdAtMs: Double
    var updatedAtMs: Double
    var ownerID: String = "user"
    
    init(
        id: String,
        title: String,
        isPinned: Bool,
        participantIDs: [String],
        createdAtMs: Double,
        updatedAtMs: Double,
        ownerID: String = "user"
    ) {
        self.id = id
        self.title = title
        self.isPinned = isPinned
        self.participantIDs = participantIDs
        self.createdAtMs = createdAtMs
        self.updatedAtMs = updatedAtMs
        self.ownerID = ownerID
    }
    
    enum CodingKeys: String, CodingKey {
        case id, title, isPinned, participantIDs, createdAtMs, updatedAtMs, ownerID
    }
    
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(String.self, forKey: .id)
        self.title = try c.decode(String.self, forKey: .title)
        self.isPinned = try c.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
        self.participantIDs = try c.decodeIfPresent([String].self, forKey: .participantIDs) ?? []
        self.createdAtMs = try c.decodeIfPresent(Double.self, forKey: .createdAtMs) ?? 0
        self.updatedAtMs = try c.decodeIfPresent(Double.self, forKey: .updatedAtMs) ?? 0
        self.ownerID = try c.decodeIfPresent(String.self, forKey: .ownerID) ?? "user"
    }
}


extension CotLocalDatabase {
    
    func createStickersAndBotsTablesIfNeeded() {
        let sql = """
        CREATE TABLE IF NOT EXISTS user_stickers (
            id TEXT PRIMARY KEY,
            file_name TEXT NOT NULL,
            category TEXT NOT NULL,
            format TEXT NOT NULL,
            width INTEGER NOT NULL DEFAULT 0,
            height INTEGER NOT NULL DEFAULT 0,
            bytes INTEGER NOT NULL DEFAULT 0,
            sha256 TEXT NOT NULL UNIQUE,
            ocr_text TEXT NOT NULL DEFAULT '',
            meaning TEXT NOT NULL DEFAULT '',
            moods_json TEXT NOT NULL DEFAULT '[]',
            tags_json TEXT NOT NULL DEFAULT '[]',
            source_site TEXT NOT NULL DEFAULT '',
            source_url TEXT NOT NULL DEFAULT '',
            is_favorite INTEGER NOT NULL DEFAULT 0,
            use_count INTEGER NOT NULL DEFAULT 0,
            last_used_at REAL,
            created_at REAL NOT NULL
        );
        CREATE INDEX IF NOT EXISTS idx_user_stickers_cat ON user_stickers(category, is_favorite DESC, use_count DESC, created_at DESC);

        CREATE TABLE IF NOT EXISTS custom_bots (
            id TEXT PRIMARY KEY,
            payload_json TEXT NOT NULL,
            created_at REAL NOT NULL,
            updated_at REAL NOT NULL
        );
        CREATE INDEX IF NOT EXISTS idx_custom_bots_created ON custom_bots(created_at ASC);

        CREATE TABLE IF NOT EXISTS bot_emotion_states (
            bot_id TEXT PRIMARY KEY,
            payload_json TEXT NOT NULL,
            updated_at REAL NOT NULL
        );

        CREATE TABLE IF NOT EXISTS meeting_room_sessions (
            id TEXT PRIMARY KEY,
            title TEXT NOT NULL,
            is_pinned INTEGER NOT NULL DEFAULT 0,
            participant_ids_json TEXT NOT NULL DEFAULT '[]',
            created_at_ms REAL NOT NULL,
            updated_at_ms REAL NOT NULL,
            owner_id TEXT NOT NULL DEFAULT 'user'
        );
        CREATE INDEX IF NOT EXISTS idx_meeting_sessions_order ON meeting_room_sessions(is_pinned DESC, updated_at_ms DESC);

        CREATE TABLE IF NOT EXISTS meeting_room_messages (
            id TEXT PRIMARY KEY,
            session_id TEXT NOT NULL,
            payload_json TEXT NOT NULL,
            created_at_ms REAL NOT NULL
        );
        CREATE INDEX IF NOT EXISTS idx_meeting_messages_session ON meeting_room_messages(session_id, created_at_ms ASC);
        """
        self.executeSQL(sql)
        self.ensureMeetingRoomSessionColumnsExist()
    }
    
    
    private func ensureMeetingRoomSessionColumnsExist() {
        let existing = self.tableColumns("meeting_room_sessions")
        if !existing.contains("owner_id") {
            self.executeSQL("ALTER TABLE meeting_room_sessions ADD COLUMN owner_id TEXT NOT NULL DEFAULT 'user';")
        }
    }
    
    
    // MARK: - Stickers CRUD
    
    func fetchAllStickers() -> [StickerAsset] {
        let sql = """
        SELECT id, file_name, category, format, width, height, bytes, sha256,
               ocr_text, meaning, moods_json, tags_json, source_site, source_url,
               is_favorite, use_count, last_used_at, created_at
        FROM user_stickers
        ORDER BY is_favorite DESC, use_count DESC, created_at DESC;
        """
        var stmt: OpaquePointer?
        var items: [StickerAsset] = []
        let decoder = JSONDecoder()
        if sqlite3_prepare_v2(self.db, sql, -1, &stmt, nil) == SQLITE_OK {
            while sqlite3_step(stmt) == SQLITE_ROW {
                guard
                    let idCStr = sqlite3_column_text(stmt, 0),
                    let fileCStr = sqlite3_column_text(stmt, 1),
                    let catCStr = sqlite3_column_text(stmt, 2),
                    let fmtCStr = sqlite3_column_text(stmt, 3),
                    let shaCStr = sqlite3_column_text(stmt, 7)
                else { continue }
                let ocr = sqlite3_column_text(stmt, 8).map { String(cString: $0) } ?? ""
                let meaning = sqlite3_column_text(stmt, 9).map { String(cString: $0) } ?? ""
                let moodsRaw = sqlite3_column_text(stmt, 10).map { String(cString: $0) } ?? "[]"
                let tagsRaw = sqlite3_column_text(stmt, 11).map { String(cString: $0) } ?? "[]"
                let moods = (try? decoder.decode([String].self, from: Data(moodsRaw.utf8))) ?? []
                let tags = (try? decoder.decode([String].self, from: Data(tagsRaw.utf8))) ?? []
                let site = sqlite3_column_text(stmt, 12).map { String(cString: $0) } ?? ""
                let url = sqlite3_column_text(stmt, 13).map { String(cString: $0) } ?? ""
                let lastUsed = sqlite3_column_type(stmt, 16) == SQLITE_NULL ? nil : sqlite3_column_double(stmt, 16)
                items.append(StickerAsset(
                    id: String(cString: idCStr),
                    fileName: String(cString: fileCStr),
                    category: String(cString: catCStr),
                    format: String(cString: fmtCStr),
                    width: Int(sqlite3_column_int(stmt, 4)),
                    height: Int(sqlite3_column_int(stmt, 5)),
                    bytes: Int(sqlite3_column_int(stmt, 6)),
                    sha256: String(cString: shaCStr),
                    ocrText: ocr,
                    meaning: meaning,
                    moods: moods,
                    tags: tags,
                    sourceSite: site,
                    sourceURL: url,
                    isFavorite: sqlite3_column_int(stmt, 14) != 0,
                    useCount: Int(sqlite3_column_int(stmt, 15)),
                    lastUsedAt: lastUsed,
                    createdAt: sqlite3_column_double(stmt, 17)
                ))
            }
        }
        sqlite3_finalize(stmt)
        return items
    }
    
    
    func upsertSticker(_ asset: StickerAsset) {
        self.upsertStickers([asset])
    }
    
    
    func upsertStickers(_ assets: [StickerAsset]) {
        guard !assets.isEmpty else { return }
        let encoder = JSONEncoder()
        let sql = """
        INSERT INTO user_stickers (
            id, file_name, category, format, width, height, bytes, sha256,
            ocr_text, meaning, moods_json, tags_json, source_site, source_url,
            is_favorite, use_count, last_used_at, created_at
        )
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(sha256) DO UPDATE SET
            category = excluded.category,
            ocr_text = CASE WHEN excluded.ocr_text != '' THEN excluded.ocr_text ELSE user_stickers.ocr_text END,
            meaning = CASE WHEN excluded.meaning != '' THEN excluded.meaning ELSE user_stickers.meaning END,
            moods_json = CASE WHEN excluded.moods_json != '[]' THEN excluded.moods_json ELSE user_stickers.moods_json END,
            tags_json = CASE WHEN excluded.tags_json != '[]' THEN excluded.tags_json ELSE user_stickers.tags_json END;
        """
        self.withTransaction {
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(self.db, sql, -1, &stmt, nil) == SQLITE_OK {
                for asset in assets {
                    sqlite3_reset(stmt)
                    sqlite3_clear_bindings(stmt)
                    let moodsJSON = (try? encoder.encode(asset.moods)).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
                    let tagsJSON = (try? encoder.encode(asset.tags)).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
                    sqlite3_bind_text(stmt, 1, asset.id, -1, self.transientDestructor)
                    sqlite3_bind_text(stmt, 2, asset.fileName, -1, self.transientDestructor)
                    sqlite3_bind_text(stmt, 3, asset.category, -1, self.transientDestructor)
                    sqlite3_bind_text(stmt, 4, asset.format, -1, self.transientDestructor)
                    sqlite3_bind_int(stmt, 5, Int32(asset.width))
                    sqlite3_bind_int(stmt, 6, Int32(asset.height))
                    sqlite3_bind_int(stmt, 7, Int32(asset.bytes))
                    sqlite3_bind_text(stmt, 8, asset.sha256, -1, self.transientDestructor)
                    sqlite3_bind_text(stmt, 9, asset.ocrText, -1, self.transientDestructor)
                    sqlite3_bind_text(stmt, 10, asset.meaning, -1, self.transientDestructor)
                    sqlite3_bind_text(stmt, 11, moodsJSON, -1, self.transientDestructor)
                    sqlite3_bind_text(stmt, 12, tagsJSON, -1, self.transientDestructor)
                    sqlite3_bind_text(stmt, 13, asset.sourceSite, -1, self.transientDestructor)
                    sqlite3_bind_text(stmt, 14, asset.sourceURL, -1, self.transientDestructor)
                    sqlite3_bind_int(stmt, 15, asset.isFavorite ? 1 : 0)
                    sqlite3_bind_int(stmt, 16, Int32(asset.useCount))
                    if let lastUsed = asset.lastUsedAt {
                        sqlite3_bind_double(stmt, 17, lastUsed)
                    } else {
                        sqlite3_bind_null(stmt, 17)
                    }
                    sqlite3_bind_double(stmt, 18, asset.createdAt)
                    let rc = sqlite3_step(stmt)
                    if rc != SQLITE_DONE {
                        self.logSQLiteError(#function, code: rc)
                    }
                }
            }
            sqlite3_finalize(stmt)
        }
    }
    
    
    func updateStickerSemantics(
        id: String,
        category: String,
        ocrText: String,
        meaning: String,
        moods: [String],
        tags: [String]
    ) {
        let encoder = JSONEncoder()
        let moodsJSON = (try? encoder.encode(moods)).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
        let tagsJSON = (try? encoder.encode(tags)).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
        let sql = """
        UPDATE user_stickers
        SET category = ?, ocr_text = ?, meaning = ?, moods_json = ?, tags_json = ?
        WHERE id = ?;
        """
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(self.db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, category, -1, self.transientDestructor)
            sqlite3_bind_text(stmt, 2, ocrText, -1, self.transientDestructor)
            sqlite3_bind_text(stmt, 3, meaning, -1, self.transientDestructor)
            sqlite3_bind_text(stmt, 4, moodsJSON, -1, self.transientDestructor)
            sqlite3_bind_text(stmt, 5, tagsJSON, -1, self.transientDestructor)
            sqlite3_bind_text(stmt, 6, id, -1, self.transientDestructor)
            sqlite3_step(stmt)
        }
        sqlite3_finalize(stmt)
    }
    
    
    func setStickerFavorite(id: String, isFavorite: Bool) {
        let sql = "UPDATE user_stickers SET is_favorite = ? WHERE id = ?;"
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(self.db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_int(stmt, 1, isFavorite ? 1 : 0)
            sqlite3_bind_text(stmt, 2, id, -1, self.transientDestructor)
            sqlite3_step(stmt)
        }
        sqlite3_finalize(stmt)
    }
    
    
    func recordStickerUse(id: String, usedAt: Double = Date().timeIntervalSince1970) {
        let sql = "UPDATE user_stickers SET use_count = use_count + 1, last_used_at = ? WHERE id = ?;"
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(self.db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_double(stmt, 1, usedAt)
            sqlite3_bind_text(stmt, 2, id, -1, self.transientDestructor)
            sqlite3_step(stmt)
        }
        sqlite3_finalize(stmt)
    }
    
    
    func deleteSticker(id: String) {
        let sql = "DELETE FROM user_stickers WHERE id = ?;"
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(self.db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, id, -1, self.transientDestructor)
            sqlite3_step(stmt)
        }
        sqlite3_finalize(stmt)
    }
    
    
    // MARK: - Custom Bots & Emotion States CRUD
    
    func fetchCustomBotPayloads() -> [String] {
        let sql = "SELECT payload_json FROM custom_bots ORDER BY created_at ASC;"
        var stmt: OpaquePointer?
        var out: [String] = []
        if sqlite3_prepare_v2(self.db, sql, -1, &stmt, nil) == SQLITE_OK {
            while sqlite3_step(stmt) == SQLITE_ROW {
                if let cStr = sqlite3_column_text(stmt, 0) {
                    out.append(String(cString: cStr))
                }
            }
        }
        sqlite3_finalize(stmt)
        return out
    }
    
    
    func upsertCustomBotPayload(id: String, json: String, createdAt: Double, updatedAt: Double) {
        let sql = """
        INSERT INTO custom_bots (id, payload_json, created_at, updated_at)
        VALUES (?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET payload_json = excluded.payload_json, updated_at = excluded.updated_at;
        """
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(self.db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, id, -1, self.transientDestructor)
            sqlite3_bind_text(stmt, 2, json, -1, self.transientDestructor)
            sqlite3_bind_double(stmt, 3, createdAt)
            sqlite3_bind_double(stmt, 4, updatedAt)
            sqlite3_step(stmt)
        }
        sqlite3_finalize(stmt)
    }
    
    
    func deleteCustomBot(id: String) {
        let sql = "DELETE FROM custom_bots WHERE id = ?;"
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(self.db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, id, -1, self.transientDestructor)
            sqlite3_step(stmt)
        }
        sqlite3_finalize(stmt)
    }
    
    
    func fetchBotEmotionPayloads() -> [String: String] {
        let sql = "SELECT bot_id, payload_json FROM bot_emotion_states;"
        var stmt: OpaquePointer?
        var out: [String: String] = [:]
        if sqlite3_prepare_v2(self.db, sql, -1, &stmt, nil) == SQLITE_OK {
            while sqlite3_step(stmt) == SQLITE_ROW {
                guard let idCStr = sqlite3_column_text(stmt, 0),
                      let jsonCStr = sqlite3_column_text(stmt, 1)
                else { continue }
                out[String(cString: idCStr)] = String(cString: jsonCStr)
            }
        }
        sqlite3_finalize(stmt)
        return out
    }
    
    
    func upsertBotEmotionPayload(botID: String, json: String, updatedAt: Double) {
        let sql = """
        INSERT INTO bot_emotion_states (bot_id, payload_json, updated_at)
        VALUES (?, ?, ?)
        ON CONFLICT(bot_id) DO UPDATE SET payload_json = excluded.payload_json, updated_at = excluded.updated_at;
        """
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(self.db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, botID, -1, self.transientDestructor)
            sqlite3_bind_text(stmt, 2, json, -1, self.transientDestructor)
            sqlite3_bind_double(stmt, 3, updatedAt)
            sqlite3_step(stmt)
        }
        sqlite3_finalize(stmt)
    }
    
    
    // MARK: - Meeting Room Sessions & Messages CRUD
    
    func fetchMeetingRoomSessions() -> [MeetingRoomSession] {
        let sql = """
        SELECT id, title, is_pinned, participant_ids_json, created_at_ms, updated_at_ms, COALESCE(NULLIF(owner_id, ''), 'user')
        FROM meeting_room_sessions
        ORDER BY is_pinned DESC, updated_at_ms DESC;
        """
        var stmt: OpaquePointer?
        var items: [MeetingRoomSession] = []
        let decoder = JSONDecoder()
        if sqlite3_prepare_v2(self.db, sql, -1, &stmt, nil) == SQLITE_OK {
            while sqlite3_step(stmt) == SQLITE_ROW {
                guard let idCStr = sqlite3_column_text(stmt, 0),
                      let titleCStr = sqlite3_column_text(stmt, 1)
                else { continue }
                let participantsRaw = sqlite3_column_text(stmt, 3).map { String(cString: $0) } ?? "[]"
                let participantIDs = (try? decoder.decode([String].self, from: Data(participantsRaw.utf8))) ?? []
                let ownerID = sqlite3_column_text(stmt, 6).map { String(cString: $0) } ?? "user"
                items.append(MeetingRoomSession(
                    id: String(cString: idCStr),
                    title: String(cString: titleCStr),
                    isPinned: sqlite3_column_int(stmt, 2) != 0,
                    participantIDs: participantIDs,
                    createdAtMs: sqlite3_column_double(stmt, 4),
                    updatedAtMs: sqlite3_column_double(stmt, 5),
                    ownerID: ownerID.isEmpty ? "user" : ownerID
                ))
            }
        }
        sqlite3_finalize(stmt)
        return items
    }
    
    
    func upsertMeetingRoomSession(_ session: MeetingRoomSession) {
        let participantsJSON = (try? JSONEncoder().encode(session.participantIDs))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
        let resolvedOwner = session.ownerID.trimmingCharacters(in: .whitespacesAndNewlines)
        let ownerID = resolvedOwner.isEmpty ? "user" : resolvedOwner
        let sql = """
        INSERT INTO meeting_room_sessions (id, title, is_pinned, participant_ids_json, created_at_ms, updated_at_ms, owner_id)
        VALUES (?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET
            title = excluded.title,
            is_pinned = excluded.is_pinned,
            participant_ids_json = excluded.participant_ids_json,
            updated_at_ms = excluded.updated_at_ms,
            owner_id = excluded.owner_id;
        """
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(self.db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, session.id, -1, self.transientDestructor)
            sqlite3_bind_text(stmt, 2, session.title, -1, self.transientDestructor)
            sqlite3_bind_int(stmt, 3, session.isPinned ? 1 : 0)
            sqlite3_bind_text(stmt, 4, participantsJSON, -1, self.transientDestructor)
            sqlite3_bind_double(stmt, 5, session.createdAtMs)
            sqlite3_bind_double(stmt, 6, session.updatedAtMs)
            sqlite3_bind_text(stmt, 7, ownerID, -1, self.transientDestructor)
            sqlite3_step(stmt)
        }
        sqlite3_finalize(stmt)
    }
    
    
    func deleteMeetingRoomSession(id: String) {
        self.withTransaction {
            var stmt1: OpaquePointer?
            if sqlite3_prepare_v2(self.db, "DELETE FROM meeting_room_messages WHERE session_id = ?;", -1, &stmt1, nil) == SQLITE_OK {
                sqlite3_bind_text(stmt1, 1, id, -1, self.transientDestructor)
                sqlite3_step(stmt1)
            }
            sqlite3_finalize(stmt1)
            
            var stmt2: OpaquePointer?
            if sqlite3_prepare_v2(self.db, "DELETE FROM meeting_room_sessions WHERE id = ?;", -1, &stmt2, nil) == SQLITE_OK {
                sqlite3_bind_text(stmt2, 1, id, -1, self.transientDestructor)
                sqlite3_step(stmt2)
            }
            sqlite3_finalize(stmt2)
        }
    }
    
    
    func fetchMeetingRoomMessagePayloads(sessionID: String) -> [String] {
        let sql = "SELECT payload_json FROM meeting_room_messages WHERE session_id = ? ORDER BY created_at_ms ASC;"
        var stmt: OpaquePointer?
        var out: [String] = []
        if sqlite3_prepare_v2(self.db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, sessionID, -1, self.transientDestructor)
            while sqlite3_step(stmt) == SQLITE_ROW {
                if let cStr = sqlite3_column_text(stmt, 0) {
                    out.append(String(cString: cStr))
                }
            }
        }
        sqlite3_finalize(stmt)
        return out
    }
    
    
    func replaceMeetingRoomMessagePayloads(sessionID: String, entries: [(id: String, json: String, createdAtMs: Double)]) {
        self.withTransaction {
            var delStmt: OpaquePointer?
            if sqlite3_prepare_v2(self.db, "DELETE FROM meeting_room_messages WHERE session_id = ?;", -1, &delStmt, nil) == SQLITE_OK {
                sqlite3_bind_text(delStmt, 1, sessionID, -1, self.transientDestructor)
                sqlite3_step(delStmt)
            }
            sqlite3_finalize(delStmt)
            
            let insSQL = "INSERT OR REPLACE INTO meeting_room_messages (id, session_id, payload_json, created_at_ms) VALUES (?, ?, ?, ?);"
            var insStmt: OpaquePointer?
            if sqlite3_prepare_v2(self.db, insSQL, -1, &insStmt, nil) == SQLITE_OK {
                for entry in entries {
                    sqlite3_reset(insStmt)
                    sqlite3_clear_bindings(insStmt)
                    sqlite3_bind_text(insStmt, 1, entry.id, -1, self.transientDestructor)
                    sqlite3_bind_text(insStmt, 2, sessionID, -1, self.transientDestructor)
                    sqlite3_bind_text(insStmt, 3, entry.json, -1, self.transientDestructor)
                    sqlite3_bind_double(insStmt, 4, entry.createdAtMs)
                    sqlite3_step(insStmt)
                }
            }
            sqlite3_finalize(insStmt)
        }
    }
}
