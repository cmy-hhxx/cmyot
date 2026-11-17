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
import Defaults

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


/// A stored historical or generated weekly report inside the local SQLite database.
nonisolated struct StoredWeeklyReport: Identifiable, Codable, Sendable, Equatable {
    
    var id: String
    var periodLabel: String
    var yearMonth: String
    var title: String
    var content: String
    var sourcePath: String?
    var isEnhanced: Bool
    var createdAt: Date
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
    var highlightsJSON: String?
    var databaseID: String? = nil
}


/// A recursive node representing either a split container or a leaf editor pane.
nonisolated indirect enum PersistedLayoutNode: Codable, Sendable, Equatable {
    
    case split(isVertical: Bool, children: [PersistedLayoutNode], weights: [Double])
    case pane(tabs: [PersistedPaneTabItem], selectedTabIndex: Int, showsLineNumber: Bool)
}


/// The full persisted layout of a single document window.
nonisolated struct PersistedWindowLayout: Codable, Sendable, Equatable {
    
    var root: PersistedLayoutNode
    var focusedPaneIndex: Int
    var windowFrame: String?
}


/// The persisted workspace session across all open document windows.
nonisolated struct PersistedWorkspaceSession: Codable, Sendable, Equatable {
    
    var windows: [PersistedWindowLayout]
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
        static let promptOrganizeMerge = "ai.prompt.organizeAndMerge"
        static let weeklyReportFragments = "ai.weeklyReport.fragments"
        static let weeklyReportAuthor = "weeklyReport.authorName"
        static let typewriterEffectEnabled = "fun.typewriterEffect"
        static let vimCursorEffectEnabled = "fun.vimCursorEffect"
        static let plainTextInlineImagesEnabled = "editor.plainTextInlineImages"
        static let usesCustomCursorColor = "editor.usesCustomCursorColor"
        static let customCursorColorHex = "editor.customCursorColorHex"
        static let userPreferencesSnapshot = "sync.userPreferences"
        static let activePaneTabsSession = "session.activePaneTabs"
        static let windowLayoutTree = "session.windowLayoutTree"
    }
    
    static let weeklyReportsDidChangeNotification = Notification.Name("CotLocalDatabaseWeeklyReportsDidChange")
    static let defaultWeeklyReportsZipPath = "/Users/cmy/Downloads/周报.zip"
    
    
    // MARK: Public Properties
    
    static let shared = CotLocalDatabase()
    
    /// Recently saved/updated documents in the local database.
    private(set) var documents: [StoredDocumentRecord] = []
    
    /// All historical and generated weekly reports stored in the database (newest first).
    private(set) var weeklyReports: [StoredWeeklyReport] = []
    
    /// All configuration key-value pairs stored in the database.
    private(set) var configEntries: [DatabaseConfigEntry] = []
    
    /// The file URL of the active SQLite database.
    let databaseURL: URL
    
    
    // MARK: Private Properties
    
    private var db: OpaquePointer?
    private let transientDestructor = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    private var userDefaultsSyncObserver: NSObjectProtocol?
    private var userDefaultsSyncTask: Task<Void, Never>?
    private var isApplyingSyncedDefaults = false
    
    
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
        self.migrateLegacyPromptsIfNeeded()
        self.reloadAll()
        
        if customURL == nil {
            self.seedDefaultWeeklyReportsIfNeeded()
            self.observeUserDefaultsForSync()
        }
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
    
    
    /// Updates an existing document record's identifier, title, or file path when renamed or saved.
    func renameDocument(oldID: String, newID: String, newTitle: String, newFilePath: String?) {
        
        if oldID != newID {
            let deleteOldSQL = "DELETE FROM documents WHERE id = ?;"
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(self.db, deleteOldSQL, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_text(stmt, 1, oldID, -1, self.transientDestructor)
                sqlite3_step(stmt)
            }
            sqlite3_finalize(stmt)
        }
        
        let updateSQL = "UPDATE documents SET title = ?, file_path = ?, updated_at = ? WHERE id = ?;"
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(self.db, updateSQL, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, newTitle, -1, self.transientDestructor)
            if let newFilePath {
                sqlite3_bind_text(stmt, 2, newFilePath, -1, self.transientDestructor)
            } else {
                sqlite3_bind_null(stmt, 2)
            }
            sqlite3_bind_double(stmt, 3, Date().timeIntervalSince1970)
            sqlite3_bind_text(stmt, 4, newID, -1, self.transientDestructor)
            sqlite3_step(stmt)
        }
        sqlite3_finalize(stmt)
        
        self.reloadDocuments()
    }
    
    
    // MARK: Weekly Reports Storage API
    
    /// The author name used when generating new weekly reports.
    var weeklyReportAuthor: String {
        
        get {
            let raw = self.string(forKey: ConfigKey.weeklyReportAuthor, default: "陈明扬")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return raw.isEmpty ? "陈明扬" : raw
        }
        set {
            self.set(newValue, forKey: ConfigKey.weeklyReportAuthor)
        }
    }
    
    
    /// Saves or updates a weekly report inside the `weekly_reports` table.
    func saveWeeklyReport(
        id: String? = nil,
        periodLabel: String,
        yearMonth: String,
        title: String,
        content: String,
        sourcePath: String? = nil,
        isEnhanced: Bool = false,
        createdAt: Date? = nil,
        reloadAfter: Bool = true
    ) {
        let resolvedID = id ?? (sourcePath ?? "\(yearMonth)/\(periodLabel)")
        let now = Date().timeIntervalSince1970
        let createdTS = createdAt?.timeIntervalSince1970 ?? now
        
        let sql = """
        INSERT INTO weekly_reports (id, period_label, year_month, title, content, source_path, is_enhanced, created_at, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET
            period_label = excluded.period_label,
            year_month = excluded.year_month,
            title = excluded.title,
            content = excluded.content,
            source_path = COALESCE(excluded.source_path, weekly_reports.source_path),
            is_enhanced = excluded.is_enhanced,
            updated_at = excluded.updated_at;
        """
        
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(self.db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, resolvedID, -1, self.transientDestructor)
            sqlite3_bind_text(stmt, 2, periodLabel, -1, self.transientDestructor)
            sqlite3_bind_text(stmt, 3, yearMonth, -1, self.transientDestructor)
            sqlite3_bind_text(stmt, 4, title, -1, self.transientDestructor)
            sqlite3_bind_text(stmt, 5, content, -1, self.transientDestructor)
            if let sourcePath {
                sqlite3_bind_text(stmt, 6, sourcePath, -1, self.transientDestructor)
            } else {
                sqlite3_bind_null(stmt, 6)
            }
            sqlite3_bind_int(stmt, 7, isEnhanced ? 1 : 0)
            sqlite3_bind_double(stmt, 8, createdTS)
            sqlite3_bind_double(stmt, 9, now)
            sqlite3_step(stmt)
        }
        sqlite3_finalize(stmt)
        
        if reloadAfter {
            self.reloadWeeklyReports()
        }
    }
    
    
    /// Deletes a weekly report by ID.
    func deleteWeeklyReport(id: String) {
        
        let sql = "DELETE FROM weekly_reports WHERE id = ?;"
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(self.db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, id, -1, self.transientDestructor)
            sqlite3_step(stmt)
        }
        sqlite3_finalize(stmt)
        
        self.reloadWeeklyReports()
    }
    
    
    /// Imports all Markdown weekly reports from a `.zip` archive into `weekly_reports`.
    ///
    /// - Returns: The number of weekly reports imported or updated.
    @discardableResult
    func importWeeklyReports(fromZipURL zipURL: URL) throws -> Int {
        
        guard FileManager.default.fileExists(atPath: zipURL.path) else {
            throw CocoaError(.fileNoSuchFile)
        }
        
        let listProcess = Process()
        listProcess.executableURL = URL(filePath: "/usr/bin/unzip")
        listProcess.arguments = ["-Z1", zipURL.path]
        let listPipe = Pipe()
        listProcess.standardOutput = listPipe
        listProcess.standardError = Pipe()
        try listProcess.run()
        let listData = listPipe.fileHandleForReading.readDataToEndOfFile()
        listProcess.waitUntilExit()
        
        guard listProcess.terminationStatus == 0,
              let listOutput = String(data: listData, encoding: .utf8)
        else { throw CocoaError(.fileReadCorruptFile) }
        
        let entryPaths = listOutput
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { path in
                !path.isEmpty
                    && !path.hasPrefix("__MACOSX/")
                    && !URL(filePath: path).lastPathComponent.hasPrefix("._")
                    && path.lowercased().hasSuffix(".md")
            }
        
        var importedCount = 0
        self.executeSQL("BEGIN TRANSACTION;")
        defer {
            self.executeSQL("COMMIT;")
            self.reloadWeeklyReports()
        }
        
        for entryPath in entryPaths {
            let catProcess = Process()
            catProcess.executableURL = URL(filePath: "/usr/bin/unzip")
            catProcess.arguments = ["-p", zipURL.path, entryPath]
            let catPipe = Pipe()
            catProcess.standardOutput = catPipe
            catProcess.standardError = Pipe()
            try catProcess.run()
            let contentData = catPipe.fileHandleForReading.readDataToEndOfFile()
            catProcess.waitUntilExit()
            
            guard catProcess.terminationStatus == 0,
                  let content = String(data: contentData, encoding: .utf8),
                  !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else { continue }
            
            let parsed = Self.parseWeeklyReportMetadata(relativePath: entryPath, content: content)
            self.saveWeeklyReport(
                id: parsed.id,
                periodLabel: parsed.periodLabel,
                yearMonth: parsed.yearMonth,
                title: parsed.title,
                content: content,
                sourcePath: entryPath,
                isEnhanced: parsed.isEnhanced,
                reloadAfter: false
            )
            importedCount += 1
        }
        
        return importedCount
    }
    
    
    /// Imports weekly report `.md` / `.txt` files or directories (or `.zip`) selected by the user.
    @discardableResult
    func importWeeklyReports(fromURLs urls: [URL]) throws -> Int {
        
        var total = 0
        for url in urls {
            if url.pathExtension.lowercased() == "zip" {
                total += try self.importWeeklyReports(fromZipURL: url)
                continue
            }
            
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
                if let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: nil) {
                    var files: [URL] = []
                    for case let fileURL as URL in enumerator {
                        let name = fileURL.lastPathComponent
                        if !name.hasPrefix("._"), ["md", "txt", "markdown"].contains(fileURL.pathExtension.lowercased()) {
                            files.append(fileURL)
                        }
                    }
                    total += self.importWeeklyReportFiles(files, baseFolder: url)
                }
            } else {
                total += self.importWeeklyReportFiles([url], baseFolder: url.deletingLastPathComponent())
            }
        }
        return total
    }
    
    
    private func importWeeklyReportFiles(_ urls: [URL], baseFolder: URL) -> Int {
        
        var count = 0
        self.executeSQL("BEGIN TRANSACTION;")
        defer {
            self.executeSQL("COMMIT;")
            self.reloadWeeklyReports()
        }
        
        let basePath = baseFolder.path
        for fileURL in urls {
            guard let content = try? String(contentsOf: fileURL, encoding: .utf8),
                  !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else { continue }
            
            let relPath = fileURL.path.hasPrefix(basePath + "/")
                ? String(fileURL.path.dropFirst(basePath.count + 1))
                : fileURL.lastPathComponent
            let parsed = Self.parseWeeklyReportMetadata(relativePath: relPath, content: content)
            self.saveWeeklyReport(
                id: parsed.id,
                periodLabel: parsed.periodLabel,
                yearMonth: parsed.yearMonth,
                title: parsed.title,
                content: content,
                sourcePath: fileURL.path,
                isEnhanced: parsed.isEnhanced,
                reloadAfter: false
            )
            count += 1
        }
        return count
    }
    
    
    /// Returns recent non-enhanced weekly reports to serve as style references when generating new reports.
    func styleReferenceWeeklyReports(limit: Int = 2) -> [StoredWeeklyReport] {
        
        let standard = self.weeklyReports.filter { !$0.isEnhanced }
        let pool = standard.isEmpty ? self.weeklyReports : standard
        return Array(pool.prefix(limit))
    }
    
    
    /// Convenience helper for archiving a newly generated Markdown weekly report directly into `weekly_reports`.
    @discardableResult
    func saveGeneratedWeeklyReport(content: String) -> StoredWeeklyReport {
        
        let fallbackPeriod = AIService.currentWeekPeriodLabel()
        let lines = content.components(separatedBy: .newlines)
        let headingTitle = lines
            .first(where: { $0.trimmingCharacters(in: .whitespaces).hasPrefix("# ") })?
            .trimmingCharacters(in: .whitespaces)
            .dropFirst(2)
            .trimmingCharacters(in: .whitespaces)
        
        let title = (headingTitle?.isEmpty == false) ? headingTitle! : "\(self.weeklyReportAuthor)-周报-\(fallbackPeriod)"
        let yearMonth: String = if let range = title.range(of: #"(20\d{2})(0[1-9]|1[0-2])"#, options: .regularExpression) {
            String(title[range])
        } else {
            String(fallbackPeriod.prefix(6))
        }
        let periodLabel: String = if let range = title.range(of: #"20\d{6}-\d{4}"#, options: .regularExpression) {
            String(title[range])
        } else {
            fallbackPeriod
        }
        let reportID = "\(yearMonth)/\(periodLabel)"
        
        self.saveWeeklyReport(
            id: reportID,
            periodLabel: periodLabel,
            yearMonth: yearMonth,
            title: title,
            content: content,
            sourcePath: nil,
            isEnhanced: false,
            reloadAfter: true
        )
        return self.weeklyReports.first(where: { $0.id == reportID }) ?? StoredWeeklyReport(
            id: reportID,
            periodLabel: periodLabel,
            yearMonth: yearMonth,
            title: title,
            content: content,
            sourcePath: nil,
            isEnhanced: false,
            createdAt: Date(),
            updatedAt: Date()
        )
    }
    
    
    static func parseWeeklyReportMetadata(relativePath: String, content: String) -> (id: String, periodLabel: String, yearMonth: String, title: String, isEnhanced: Bool) {
        
        let cleanPath = relativePath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let url = URL(filePath: cleanPath)
        let stem = url.deletingPathExtension().lastPathComponent
        let isEnhanced = stem.lowercased().hasSuffix("_enhanced")
        let basePeriod = isEnhanced ? String(stem.dropLast("_enhanced".count)) : stem
        
        let components = cleanPath.split(separator: "/").map(String.init)
        var yearMonth = ""
        if components.count >= 2 {
            let parent = components[components.count - 2]
            if parent.count == 6, parent.allSatisfy(\.isNumber) {
                yearMonth = parent
            }
        }
        
        let lines = content.components(separatedBy: .newlines)
        let headingTitle = lines
            .first(where: { $0.trimmingCharacters(in: .whitespaces).hasPrefix("# ") })?
            .trimmingCharacters(in: .whitespaces)
            .dropFirst(2)
            .trimmingCharacters(in: .whitespaces)
        
        let title = (headingTitle?.isEmpty == false ? headingTitle! : stem)
        if yearMonth.isEmpty {
            // Try extracting YYYYMM from title like `陈明扬-周报-20261012-1016`
            if let range = title.range(of: #"(20\d{2})(0[1-9]|1[0-2])"#, options: .regularExpression) {
                yearMonth = String(title[range])
            } else {
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyyMM"
                yearMonth = formatter.string(from: Date())
            }
        }
        
        let periodLabel = isEnhanced ? "\(basePeriod) (增强版)" : basePeriod
        let stableID = cleanPath.hasSuffix(".md") ? String(cleanPath.dropLast(3)) : cleanPath
        return (stableID, periodLabel, yearMonth, title, isEnhanced)
    }
    
    
    // MARK: User Preferences Snapshot API
    
    /// Captures all user editor/app preferences into the local SQLite database so settings survive
    /// migrations, DB exports, and restores.
    func syncUserPreferencesToDatabase() {
        
        guard !self.isApplyingSyncedDefaults else { return }
        
        let defaults = UserDefaults.standard
        var snapshot: [String: Any] = [:]
        
        let extraKeys = [
            DefaultKeys.vimMode.rawValue,
            DefaultKeys.usesCustomCursorColor.rawValue,
            DefaultKeys.customCursorColorHex.rawValue,
            DefaultKeys.aiActiveProfileID.rawValue,
            DefaultKeys.showStatusBar.rawValue,
            DefaultKeys.showNavigationBar.rawValue,
            DefaultKeys.splitViewVertical.rawValue,
            "AppleLanguages",
        ]
        
        let allKeys = Set(DefaultSettings.portableKeys.map(\.rawValue) + extraKeys)
        for key in allKeys {
            if let value = defaults.object(forKey: key) {
                snapshot[key] = value
            }
        }
        
        if let plistData = try? PropertyListSerialization.data(fromPropertyList: snapshot, format: .binary, options: 0) {
            self.set(plistData.base64EncodedString(), forKey: ConfigKey.userPreferencesSnapshot)
        }
        self.set(defaults.bool(forKey: DefaultKeys.usesCustomCursorColor.rawValue), forKey: ConfigKey.usesCustomCursorColor)
        let hex = defaults.string(forKey: DefaultKeys.customCursorColorHex.rawValue) ?? "#0A84FF"
        self.set(hex, forKey: ConfigKey.customCursorColorHex)
    }
    
    
    /// Restores user preferences from `sync.userPreferences` in the database back into `UserDefaults`.
    func restoreUserPreferencesFromDatabase(overwriteExisting: Bool) {
        
        self.isApplyingSyncedDefaults = true
        defer { self.isApplyingSyncedDefaults = false }
        
        let defaults = UserDefaults.standard
        let encoded = self.string(forKey: ConfigKey.userPreferencesSnapshot)
        if !encoded.isEmpty,
           let plistData = Data(base64Encoded: encoded),
           let dict = try? PropertyListSerialization.propertyList(from: plistData, options: [], format: nil) as? [String: Any]
        {
            for (key, value) in dict {
                if overwriteExisting || defaults.object(forKey: key) == nil {
                    defaults.set(value, forKey: key)
                }
            }
        }
        
        if overwriteExisting || defaults.object(forKey: DefaultKeys.usesCustomCursorColor.rawValue) == nil {
            defaults.set(self.bool(forKey: ConfigKey.usesCustomCursorColor, default: false),
                         forKey: DefaultKeys.usesCustomCursorColor.rawValue)
        }
        if overwriteExisting || defaults.object(forKey: DefaultKeys.customCursorColorHex.rawValue) == nil {
            let hex = self.string(forKey: ConfigKey.customCursorColorHex, default: "#0A84FF")
            defaults.set(hex.isEmpty ? "#0A84FF" : hex, forKey: DefaultKeys.customCursorColorHex.rawValue)
        }
    }
    
    
    // MARK: Import & Export API
    
    /// Exports the entire SQLite database (with current AI profiles & settings synced into `configs`)
    /// to the destination URL using `VACUUM INTO` or atomic file copy.
    func exportDatabase(to destinationURL: URL) throws {
        
        // Snapshot current AI endpoint profiles & user preferences into configs so they travel with the DB
        if let profilesData = try? JSONEncoder().encode(AIEndpointStore.profiles),
           let profilesJSON = String(data: profilesData, encoding: .utf8)
        {
            self.set(profilesJSON, forKey: "sync.aiProfiles")
        }
        self.syncUserPreferencesToDatabase()
        
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
        self.migrateLegacyPromptsIfNeeded()
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
        
        self.restoreUserPreferencesFromDatabase(overwriteExisting: true)
        self.applySyncedDefaultsToUserDefaults()
    }
    
    
    /// Syncs feature toggles stored in `CotLocalDatabase` back to `UserDefaults` so live bindings update.
    func applySyncedDefaultsToUserDefaults() {
        
        self.isApplyingSyncedDefaults = true
        defer { self.isApplyingSyncedDefaults = false }
        
        let defaults = UserDefaults.standard
        defaults.set(self.bool(forKey: ConfigKey.typewriterEffectEnabled, default: false), forKey: ConfigKey.typewriterEffectEnabled)
        defaults.set(self.bool(forKey: ConfigKey.vimCursorEffectEnabled, default: true), forKey: ConfigKey.vimCursorEffectEnabled)
        defaults.set(self.bool(forKey: ConfigKey.plainTextInlineImagesEnabled, default: true), forKey: ConfigKey.plainTextInlineImagesEnabled)
        
        if let rawCursorEnabled = self.queryConfigValue(forKey: ConfigKey.usesCustomCursorColor) {
            let enabled = ["1", "true", "yes", "on"].contains(rawCursorEnabled.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
            defaults.set(enabled, forKey: DefaultKeys.usesCustomCursorColor.rawValue)
        }
        if let hex = self.queryConfigValue(forKey: ConfigKey.customCursorColorHex), !hex.isEmpty {
            defaults.set(hex, forKey: DefaultKeys.customCursorColorHex.rawValue)
        }
    }
    
    
    /// Reloads documents, weekly reports, and configuration entries from disk.
    func reloadAll() {
        
        self.reloadConfigs()
        self.reloadDocuments()
        self.reloadWeeklyReports()
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
        CREATE TABLE IF NOT EXISTS weekly_reports (
            id TEXT PRIMARY KEY,
            period_label TEXT NOT NULL,
            year_month TEXT NOT NULL,
            title TEXT NOT NULL,
            content TEXT NOT NULL,
            source_path TEXT,
            is_enhanced INTEGER NOT NULL DEFAULT 0,
            created_at REAL NOT NULL,
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
            (ConfigKey.promptOrganizeMerge, AIAction.organizeAndMerge.defaultSystemPrompt),
            (ConfigKey.weeklyReportAuthor, "陈明扬"),
            (ConfigKey.typewriterEffectEnabled, "false"),
            (ConfigKey.vimCursorEffectEnabled, "true"),
            (ConfigKey.plainTextInlineImagesEnabled, "true"),
            (ConfigKey.usesCustomCursorColor, "false"),
            (ConfigKey.customCursorColorHex, "#0A84FF"),
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
    
    
    /// Upgrades unmodified v1 built-in prompts (such as the old weekly report prompts) to v2.
    private func migrateLegacyPromptsIfNeeded() {
        
        for action in [AIAction.weeklyReport, .weeklyReportItem] {
            guard let existing = self.queryConfigValue(forKey: action.databaseConfigKey) else { continue }
            let trimmedExisting = existing.trimmingCharacters(in: .whitespacesAndNewlines)
            if action.legacyDefaultSystemPrompts.contains(where: {
                $0.trimmingCharacters(in: .whitespacesAndNewlines) == trimmedExisting
            }) {
                self.set(action.defaultSystemPrompt, forKey: action.databaseConfigKey)
            }
        }
    }
    
    
    private func seedDefaultWeeklyReportsIfNeeded() {
        
        guard self.weeklyReports.isEmpty else { return }
        let zipURL = URL(filePath: Self.defaultWeeklyReportsZipPath)
        guard FileManager.default.fileExists(atPath: zipURL.path) else { return }
        _ = try? self.importWeeklyReports(fromZipURL: zipURL)
    }
    
    
    private func observeUserDefaultsForSync() {
        
        // Initial snapshot if missing
        if self.queryConfigValue(forKey: ConfigKey.userPreferencesSnapshot) == nil {
            self.syncUserPreferencesToDatabase()
        }
        
        self.userDefaultsSyncObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: UserDefaults.standard,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, !self.isApplyingSyncedDefaults else { return }
                self.userDefaultsSyncTask?.cancel()
                self.userDefaultsSyncTask = Task { [weak self] in
                    try? await Task.sleep(for: .milliseconds(800))
                    guard !Task.isCancelled else { return }
                    self?.syncUserPreferencesToDatabase()
                }
            }
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
    
    
    func reloadWeeklyReports() {
        
        let sql = """
        SELECT id, period_label, year_month, title, content, source_path, is_enhanced, created_at, updated_at
        FROM weekly_reports
        ORDER BY year_month DESC, period_label DESC, updated_at DESC;
        """
        var stmt: OpaquePointer?
        var items: [StoredWeeklyReport] = []
        
        if sqlite3_prepare_v2(self.db, sql, -1, &stmt, nil) == SQLITE_OK {
            while sqlite3_step(stmt) == SQLITE_ROW {
                guard
                    let idCStr = sqlite3_column_text(stmt, 0),
                    let periodCStr = sqlite3_column_text(stmt, 1),
                    let ymCStr = sqlite3_column_text(stmt, 2),
                    let titleCStr = sqlite3_column_text(stmt, 3),
                    let contentCStr = sqlite3_column_text(stmt, 4)
                else { continue }
                
                let sourcePath: String? = if let srcCStr = sqlite3_column_text(stmt, 5) {
                    String(cString: srcCStr)
                } else {
                    nil
                }
                let isEnhanced = sqlite3_column_int(stmt, 6) != 0
                let createdTS = sqlite3_column_double(stmt, 7)
                let updatedTS = sqlite3_column_double(stmt, 8)
                
                items.append(StoredWeeklyReport(
                    id: String(cString: idCStr),
                    periodLabel: String(cString: periodCStr),
                    yearMonth: String(cString: ymCStr),
                    title: String(cString: titleCStr),
                    content: String(cString: contentCStr),
                    sourcePath: sourcePath,
                    isEnhanced: isEnhanced,
                    createdAt: Date(timeIntervalSince1970: createdTS),
                    updatedAt: Date(timeIntervalSince1970: updatedTS)
                ))
            }
        }
        sqlite3_finalize(stmt)
        self.weeklyReports = items
        NotificationCenter.default.post(name: Self.weeklyReportsDidChangeNotification, object: self)
    }
}
