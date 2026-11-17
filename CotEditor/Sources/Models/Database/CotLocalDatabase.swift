//
//  CotLocalDatabase.swift
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
import Observation
import SQLite3

/// A stored document snapshot inside the local SQLite database.
nonisolated struct StoredDocumentRecord: Identifiable, Codable, Sendable, Equatable {
    
    var id: String
    var title: String
    var filePath: String?
    var syntax: String
    var content: String
    var highlightsJSON: String
    var updatedAt: Date
}


/// A single tab entry inside a window's persisted pane/tab session.
nonisolated struct PersistedPaneTabItem: Codable, Sendable, Equatable {
    
    var title: String
    var filePath: String?
    var syntax: String
    var content: String
    var isPinned: Bool
    var paneIndex: Int
}


/// A single key-value entry in the local database's configuration table.
nonisolated struct DatabaseConfigEntry: Identifiable, Codable, Sendable, Equatable {
    
    var key: String
    var value: String
    var updatedAt: Date
    
    var id: String  { self.key }
}


/// The local SQLite database (`cot_user_data.sqlite3`) that persists user documents,
/// AI personas, stage-by-stage prompts, weekly report fragments, and custom preferences.
///
/// The entire database lives in a single SQLite file (in WAL/DELETE mode with checkpoints on
/// export) so the user can export it on one machine and import it on another to sync their
/// documents, personas, prompts, and settings in one step.
@MainActor @Observable final class CotLocalDatabase {
    
    // MARK: Well-Known Configuration Keys
    
    nonisolated enum ConfigKey {
        
        static let aiPersona = "ai.persona"
        static let promptTranslate = "ai.prompt.translate"
        static let promptSummarize = "ai.prompt.summarize"
        static let promptExplain = "ai.prompt.explain"
        static let promptWeeklyReport = "ai.prompt.weeklyReport"
        static let promptWeeklyReportPart = "ai.prompt.weeklyReportPart"
        static let promptChart = "ai.prompt.chart"
        static let promptOCR = "ai.prompt.ocr"
        static let weeklyReportFragments = "ai.weeklyReport.fragments"
        static let typewriterEffectEnabled = "fun.typewriterEffect"
        static let vimCursorEffectEnabled = "fun.vimCursorEffect"
        static let plainTextInlineImagesEnabled = "editor.plainTextInlineImages"
        static let activePaneTabsSession = "session.activePaneTabs"
    }
    
    
    // MARK: Public Properties
    
    static let shared = CotLocalDatabase()
    
    /// Recently saved/updated documents in the local database.
    private(set) var documents: [StoredDocumentRecord] = []
    
    /// All configuration key-value pairs stored in the database.
    private(set) var configEntries: [DatabaseConfigEntry] = []
    
    /// The file URL of the active SQLite database.
    let databaseURL: URL
    
    
    // MARK: Private Properties
    
    private var db: OpaquePointer?
    private let transientDestructor = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    
    
    // MARK: Lifecycle
    
    init(customURL: URL? = nil) {
        
        if let customURL {
            self.databaseURL = customURL
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            let folder = appSupport.appending(path: "Cot", directoryHint: .isDirectory)
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            self.databaseURL = folder.appending(path: "cot_user_data.sqlite3")
        }
        
        self.openDatabase()
        self.createTablesIfNeeded()
        self.seedDefaultConfigsIfNeeded()
        self.reloadAll()
    }
    
    
    // MARK: Public Configuration API
    
    /// Reads a string configuration value from the database, falling back to `defaultValue`.
    func string(forKey key: String, default defaultValue: String = "") -> String {
        
        if let entry = self.configEntries.first(where: { $0.key == key }) {
            return entry.value
        }
        return self.queryConfigValue(forKey: key) ?? defaultValue
    }
    
    
    /// Reads a boolean configuration value from the database.
    func bool(forKey key: String, default defaultValue: Bool = false) -> Bool {
        
        let raw = self.string(forKey: key, default: defaultValue ? "true" : "false")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        switch raw {
            case "1", "true", "yes", "on":
                return true
            case "0", "false", "no", "off":
                return false
            default:
                return defaultValue
        }
    }
    
    
    /// Writes a string configuration value to the database and refreshes observers.
    func set(_ value: String, forKey key: String) {
        
        let now = Date().timeIntervalSince1970
        let sql = """
        INSERT INTO configs (key, value, updated_at)
        VALUES (?, ?, ?)
        ON CONFLICT(key) DO UPDATE SET value = excluded.value, updated_at = excluded.updated_at;
        """
        
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(self.db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, key, -1, self.transientDestructor)
            sqlite3_bind_text(stmt, 2, value, -1, self.transientDestructor)
            sqlite3_bind_double(stmt, 3, now)
            sqlite3_step(stmt)
        }
        sqlite3_finalize(stmt)
        
        self.reloadConfigs()
    }
    
    
    /// Writes a boolean configuration value to the database.
    func set(_ value: Bool, forKey key: String) {
        
        self.set(value ? "true" : "false", forKey: key)
    }
    
    
    /// Removes a configuration key from the database.
    func removeConfig(forKey key: String) {
        
        let sql = "DELETE FROM configs WHERE key = ?;"
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(self.db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, key, -1, self.transientDestructor)
            sqlite3_step(stmt)
        }
        sqlite3_finalize(stmt)
        
        self.reloadConfigs()
    }
    
    
    // MARK: AI Persona & Stage Prompts
    
    /// The user-configured AI persona prepended to AI system prompts.
    var aiPersona: String {
        
        get { self.string(forKey: ConfigKey.aiPersona) }
        set { self.set(newValue, forKey: ConfigKey.aiPersona) }
    }
    
    
    /// Returns the custom stage prompt for a given `ConfigKey`, or `nil` if empty/default.
    func customStagePrompt(forKey key: String) -> String? {
        
        let value = self.string(forKey: key).trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
    
    
    /// Appends a weekly report item ("一键变成周报的一部分") to the accumulated weekly fragments.
    func appendWeeklyReportFragment(_ fragment: String) {
        
        let trimmed = fragment.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        
        let current = self.string(forKey: ConfigKey.weeklyReportFragments)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let combined = current.isEmpty ? trimmed : (current + "\n\n" + trimmed)
        self.set(combined, forKey: ConfigKey.weeklyReportFragments)
    }
    
    
    /// Clears accumulated weekly report fragments.
    func clearWeeklyReportFragments() {
        
        self.set("", forKey: ConfigKey.weeklyReportFragments)
    }
    
    
    // MARK: Document Storage API
    
    /// Saves or updates a document snapshot in the local SQLite database.
    func saveDocument(
        id: String? = nil,
        title: String,
        filePath: String?,
        syntax: String,
        content: String,
        highlights: [TextHighlight] = []
    ) {
        let resolvedID = id ?? filePath ?? "untitled:\(title)"
        let highlightsJSON = (try? String(data: JSONEncoder().encode(highlights), encoding: .utf8)) ?? "[]"
        let now = Date().timeIntervalSince1970
        
        let sql = """
        INSERT INTO documents (id, title, file_path, syntax, content, highlights_json, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET
            title = excluded.title,
            file_path = excluded.file_path,
            syntax = excluded.syntax,
            content = excluded.content,
            highlights_json = excluded.highlights_json,
            updated_at = excluded.updated_at;
        """
        
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(self.db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, resolvedID, -1, self.transientDestructor)
            sqlite3_bind_text(stmt, 2, title, -1, self.transientDestructor)
            if let filePath {
                sqlite3_bind_text(stmt, 3, filePath, -1, self.transientDestructor)
            } else {
                sqlite3_bind_null(stmt, 3)
            }
            sqlite3_bind_text(stmt, 4, syntax, -1, self.transientDestructor)
            sqlite3_bind_text(stmt, 5, content, -1, self.transientDestructor)
            sqlite3_bind_text(stmt, 6, highlightsJSON, -1, self.transientDestructor)
            sqlite3_bind_double(stmt, 7, now)
            sqlite3_step(stmt)
        }
        sqlite3_finalize(stmt)
        
        self.reloadDocuments()
    }
    
    
    /// Deletes a stored document record from the database.
    func deleteDocument(id: String) {
        
        let sql = "DELETE FROM documents WHERE id = ?;"
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(self.db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, id, -1, self.transientDestructor)
            sqlite3_step(stmt)
        }
        sqlite3_finalize(stmt)
        
        self.reloadDocuments()
    }
    
    
    // MARK: Import & Export API
    
    /// Exports the entire SQLite database (with current AI profiles & settings synced into `configs`)
    /// to the destination URL using `VACUUM INTO` or atomic file copy.
    func exportDatabase(to destinationURL: URL) throws {
        
        // Snapshot current AI endpoint profiles into configs so they travel with the DB
        if let profilesData = try? JSONEncoder().encode(AIEndpointStore.profiles),
           let profilesJSON = String(data: profilesData, encoding: .utf8)
        {
            self.set(profilesJSON, forKey: "sync.aiProfiles")
        }
        
        self.executeSQL("PRAGMA wal_checkpoint(FULL);")
        
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
        }
        
        let escapedPath = destinationURL.path.replacingOccurrences(of: "'", with: "''")
        let vacuumSQL = "VACUUM INTO '\(escapedPath)';"
        if sqlite3_exec(self.db, vacuumSQL, nil, nil, nil) != SQLITE_OK {
            try FileManager.default.copyItem(at: self.databaseURL, to: destinationURL)
        }
    }
    
    
    /// Imports another Cot SQLite database file, replacing or merging documents and configurations.
    func importDatabase(from sourceURL: URL) throws {
        
        // Validate that the source is a readable SQLite database with our tables
        var checkDB: OpaquePointer?
        guard sqlite3_open_v2(sourceURL.path, &checkDB, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            sqlite3_close(checkDB)
            throw CocoaError(.fileReadCorruptFile)
        }
        sqlite3_close(checkDB)
        
        self.closeDatabase()
        
        let walURL = URL(filePath: self.databaseURL.path + "-wal")
        let shmURL = URL(filePath: self.databaseURL.path + "-shm")
        try? FileManager.default.removeItem(at: walURL)
        try? FileManager.default.removeItem(at: shmURL)
        if FileManager.default.fileExists(atPath: self.databaseURL.path) {
            try FileManager.default.removeItem(at: self.databaseURL)
        }
        try FileManager.default.copyItem(at: sourceURL, to: self.databaseURL)
        
        self.openDatabase()
        self.createTablesIfNeeded()
        self.seedDefaultConfigsIfNeeded()
        self.reloadAll()
        
        // Restore synced AI profiles if present
        let syncedProfilesJSON = self.string(forKey: "sync.aiProfiles")
        if !syncedProfilesJSON.isEmpty,
           let data = syncedProfilesJSON.data(using: .utf8),
           let importedProfiles = try? JSONDecoder().decode([AIEndpointProfile].self, from: data),
           !importedProfiles.isEmpty
        {
            var existing = AIEndpointStore.profiles
            for profile in importedProfiles where !existing.contains(where: { $0.id == profile.id }) {
                existing.append(profile)
            }
            AIEndpointStore.profiles = existing
            if AIEndpointStore.activeID == nil {
                AIEndpointStore.activeID = existing.first?.id
            }
        }
        
        self.applySyncedDefaultsToUserDefaults()
    }
    
    
    /// Syncs feature toggles stored in `CotLocalDatabase` back to `UserDefaults` so live bindings update.
    func applySyncedDefaultsToUserDefaults() {
        
        let defaults = UserDefaults.standard
        defaults.set(self.bool(forKey: ConfigKey.typewriterEffectEnabled, default: false), forKey: ConfigKey.typewriterEffectEnabled)
        defaults.set(self.bool(forKey: ConfigKey.vimCursorEffectEnabled, default: true), forKey: ConfigKey.vimCursorEffectEnabled)
        defaults.set(self.bool(forKey: ConfigKey.plainTextInlineImagesEnabled, default: true), forKey: ConfigKey.plainTextInlineImagesEnabled)
    }
    
    
    /// Reloads both documents and configuration entries from disk.
    func reloadAll() {
        
        self.reloadConfigs()
        self.reloadDocuments()
        self.applySyncedDefaultsToUserDefaults()
    }
    
    
    // MARK: Private SQLite Helpers
    
    private func openDatabase() {
        
        if sqlite3_open(self.databaseURL.path, &self.db) != SQLITE_OK {
            self.db = nil
        }
    }
    
    
    private func closeDatabase() {
        
        if let db = self.db {
            sqlite3_close(db)
            self.db = nil
        }
    }
    
    
    private func executeSQL(_ sql: String) {
        
        guard let db = self.db else { return }
        sqlite3_exec(db, sql, nil, nil, nil)
    }
    
    
    private func createTablesIfNeeded() {
        
        let sql = """
        CREATE TABLE IF NOT EXISTS documents (
            id TEXT PRIMARY KEY,
            title TEXT NOT NULL,
            file_path TEXT,
            syntax TEXT NOT NULL DEFAULT 'Plain Text',
            content TEXT NOT NULL,
            highlights_json TEXT NOT NULL DEFAULT '[]',
            updated_at REAL NOT NULL
        );
        CREATE TABLE IF NOT EXISTS configs (
            key TEXT PRIMARY KEY,
            value TEXT NOT NULL,
            updated_at REAL NOT NULL
        );
        """
        self.executeSQL(sql)
    }
    
    
    private func seedDefaultConfigsIfNeeded() {
        
        let defaults: [(String, String)] = [
            (ConfigKey.aiPersona, "你是一位专业、干练、审美在线的技术与写作助手，回答直接、结构清晰、不讲废话。"),
            (ConfigKey.promptTranslate, AIAction.translate.defaultSystemPrompt),
            (ConfigKey.promptSummarize, AIAction.summarize.defaultSystemPrompt),
            (ConfigKey.promptExplain, AIAction.explain.defaultSystemPrompt),
            (ConfigKey.promptWeeklyReport, AIAction.weeklyReport.defaultSystemPrompt),
            (ConfigKey.promptWeeklyReportPart, AIAction.weeklyReportItem.defaultSystemPrompt),
            (ConfigKey.promptChart, AIAction.interactiveChart.defaultSystemPrompt),
            (ConfigKey.promptOCR, AIAction.ocrPolish.defaultSystemPrompt),
            (ConfigKey.typewriterEffectEnabled, "false"),
            (ConfigKey.vimCursorEffectEnabled, "true"),
            (ConfigKey.plainTextInlineImagesEnabled, "true"),
        ]
        
        let now = Date().timeIntervalSince1970
        let sql = "INSERT OR IGNORE INTO configs (key, value, updated_at) VALUES (?, ?, ?);"
        
        for (key, value) in defaults {
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(self.db, sql, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_text(stmt, 1, key, -1, self.transientDestructor)
                sqlite3_bind_text(stmt, 2, value, -1, self.transientDestructor)
                sqlite3_bind_double(stmt, 3, now)
                sqlite3_step(stmt)
            }
            sqlite3_finalize(stmt)
        }
    }
    
    
    private func queryConfigValue(forKey key: String) -> String? {
        
        let sql = "SELECT value FROM configs WHERE key = ? LIMIT 1;"
        var stmt: OpaquePointer?
        var result: String?
        if sqlite3_prepare_v2(self.db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, key, -1, self.transientDestructor)
            if sqlite3_step(stmt) == SQLITE_ROW, let cStr = sqlite3_column_text(stmt, 0) {
                result = String(cString: cStr)
            }
        }
        sqlite3_finalize(stmt)
        return result
    }
    
    
    private func reloadConfigs() {
        
        let sql = "SELECT key, value, updated_at FROM configs ORDER BY key ASC;"
        var stmt: OpaquePointer?
        var items: [DatabaseConfigEntry] = []
        
        if sqlite3_prepare_v2(self.db, sql, -1, &stmt, nil) == SQLITE_OK {
            while sqlite3_step(stmt) == SQLITE_ROW {
                guard
                    let keyCStr = sqlite3_column_text(stmt, 0),
                    let valCStr = sqlite3_column_text(stmt, 1)
                else { continue }
                let ts = sqlite3_column_double(stmt, 2)
                items.append(DatabaseConfigEntry(
                    key: String(cString: keyCStr),
                    value: String(cString: valCStr),
                    updatedAt: Date(timeIntervalSince1970: ts)
                ))
            }
        }
        sqlite3_finalize(stmt)
        self.configEntries = items
    }
    
    
    private func reloadDocuments() {
        
        let sql = """
        SELECT id, title, file_path, syntax, content, highlights_json, updated_at
        FROM documents
        ORDER BY updated_at DESC
        LIMIT 200;
        """
        var stmt: OpaquePointer?
        var items: [StoredDocumentRecord] = []
        
        if sqlite3_prepare_v2(self.db, sql, -1, &stmt, nil) == SQLITE_OK {
            while sqlite3_step(stmt) == SQLITE_ROW {
                guard
                    let idCStr = sqlite3_column_text(stmt, 0),
                    let titleCStr = sqlite3_column_text(stmt, 1),
                    let syntaxCStr = sqlite3_column_text(stmt, 3),
                    let contentCStr = sqlite3_column_text(stmt, 4),
                    let highlightsCStr = sqlite3_column_text(stmt, 5)
                else { continue }
                
                let filePath: String? = if let pathCStr = sqlite3_column_text(stmt, 2) {
                    String(cString: pathCStr)
                } else {
                    nil
                }
                let ts = sqlite3_column_double(stmt, 6)
                
                items.append(StoredDocumentRecord(
                    id: String(cString: idCStr),
                    title: String(cString: titleCStr),
                    filePath: filePath,
                    syntax: String(cString: syntaxCStr),
                    content: String(cString: contentCStr),
                    highlightsJSON: String(cString: highlightsCStr),
                    updatedAt: Date(timeIntervalSince1970: ts)
                ))
            }
        }
        sqlite3_finalize(stmt)
        self.documents = items
    }
}
