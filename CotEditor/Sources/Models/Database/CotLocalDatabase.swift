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
    var groupName: String = ""
    var deletedAt: Date?
    var createdAt: Date? = nil
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
    var boardState: PaneBoardState? = nil
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


/// Portable snapshot of the active local user's profile (name, avatar image, accent color, etc.)
/// stored inside `cot_user_data.sqlite3` so database export/import restores the complete user identity.
nonisolated struct PortableUserProfileSnapshot: Codable, Sendable, Equatable {
    
    var displayName: String
    var avatarDataBase64: String?
    var avatarColorHex: String
    var accountKind: String
    var email: String?
    var remoteUserID: String?
    var createdAt: Date
    
    
    init(profile: UserProfile) {
        self.displayName = profile.displayName
        self.avatarDataBase64 = profile.avatarData?.base64EncodedString()
        self.avatarColorHex = profile.avatarColorHex
        self.accountKind = profile.accountKind
        self.email = profile.email
        self.remoteUserID = profile.remoteUserID
        self.createdAt = profile.createdAt
    }
    
    
    var decodedAvatarData: Data? {
        guard let avatarDataBase64, !avatarDataBase64.isEmpty else { return nil }
        return Data(base64Encoded: avatarDataBase64)
    }
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
        static let promptSemanticRestructure = "ai.prompt.semanticRestructure"
        static let promptWeeklyReport = "ai.prompt.weeklyReport"
        static let promptWeeklyReportPart = "ai.prompt.weeklyReportPart"
        static let promptChart = "ai.prompt.chart"
        static let promptOCR = "ai.prompt.ocr"
        static let promptOrganizeMerge = "ai.prompt.organizeAndMerge"
        static let weeklyReportFragments = "ai.weeklyReport.fragments"
        static let weeklyReportAuthor = "weeklyReport.authorName"
        static let typewriterEffectEnabled = "fun.typewriterEffect"
        static let typewriterEffectStyle = "fun.typewriterEffect.style"
        static let typewriterEffectV2Migrated = "fun.typewriterEffect.v2Enabled"
        static let vimCursorEffectEnabled = "fun.vimCursorEffect"
        static let plainTextInlineImagesEnabled = "editor.plainTextInlineImages"
        static let usesCustomCursorColor = "editor.usesCustomCursorColor"
        static let customCursorColorHex = "editor.customCursorColorHex"
        static let userHabitModelJSON = "editor.userHabitModelJSON"
        static let inlineCompletionEnabled = "editor.inlineCompletionEnabled"
        static let aiNextTokenEnabled = "ai.nextTokenEnabled"
        static let aiNextTokenModelOverride = "ai.nextTokenModelOverride"
        static let aiNextTokenDebounceMs = "ai.nextTokenDebounceMs"
        static let aiNextTokenStrategy = "ai.nextTokenStrategy"
        static let aiNextTokenDailyCap = "ai.nextTokenDailyCap"
        static let aiNextTokenDailyStatsJSON = "ai.nextTokenDailyStatsJSON"
        static let userPreferencesSnapshot = "sync.userPreferences"
        static let activePaneTabsSession = "session.activePaneTabs"
        static let windowLayoutTree = "session.windowLayoutTree"
        static let documentGroups = "documentCenter.groups"
        static let syncAIProfiles = "sync.aiProfiles"
        static let syncAIActiveProfileID = "sync.aiActiveProfileID"
        static let syncAIProfileAPIKeys = "sync.aiProfileAPIKeys"
        static let syncUserProfileSnapshot = "sync.userProfileSnapshot"
        static let aiBotsConfigJSON = "ai.botsConfigJSON"
        static let userPersonalityProfileJSON = "analytics.userPersonalityProfileJSON"
        static let aiPersonalityAutoEnabled = "analytics.personalityAutoEnabled"
        static let cotPassStyleIndex = "pass.styleIndex"
        static let cotPassLicenseKey = "pass.licenseKey"
        static let butlerMeetingRoomJSON = "butler.meetingRoomHistoryJSON"
        static let cotPassSerialCode = "pass.serialCode"
        static let analyticsHistoricalBackfillV2 = "analytics.historicalBackfillV2"
        static let studioPaletteID = "ui.studioPaletteID"
        static let studioCustomLightHex = "ui.studioCustomLightHex"
        static let studioCustomDarkHex = "ui.studioCustomDarkHex"
        static let studioCustomAccentHex = "ui.studioCustomAccentHex"
        static let appIconSpecJSON = "ui.appIconSpecJSON"
        static let editorWallpaperSpecJSON = "appearance.wallpaperSpecJSON"
        static let editorWallpaperCustomCatalogJSON = "appearance.wallpaperCustomCatalogJSON"
        static let aiHotNewsCacheJSON = "analytics.aiHotNewsCacheJSON"
        static let aiActionPredictionsJSON = "analytics.aiActionPredictionsJSON"
        static let aiDoneTodayCommentaryJSON = "analytics.aiDoneTodayCommentaryJSON"
        static let dashboardDanmakuEnabled = "analytics.dashboardDanmakuEnabled"
        static let newsBookmarkedItemsJSON = "analytics.newsBookmarkedItemsJSON"
        static let newsReadIDsJSON = "analytics.newsReadIDsJSON"
        static let newsBrowsingHistoryJSON = "analytics.newsBrowsingHistoryJSON"
        static let newsPersonalNotesJSON = "analytics.newsPersonalNotesJSON"
        static let newsAIBriefsJSON = "analytics.newsAIBriefsJSON"
        static let newsReaderFontScale = "analytics.newsReaderFontScale"
        static let butlerName = "butler.name"
        static let butlerNickname = "butler.nickname"
        static let butlerAvatarVariant = "butler.avatarVariant"
        static let butlerActiveSessionID = "butler.activeSessionID"
        static let butlerCustomAvatarBase64 = "butler.customAvatarBase64"
        static let watchlistSeededV1 = "market.watchlistSeededV1"
        static let watchlistSeededUserFocusV2 = "market.watchlistSeededUserFocusV2"
        static let podcastAgentRemindersJSON = "podcast.agentRemindersJSON"
        static let aiScheduledOrganizeEnabled = "ai.scheduledOrganize.enabled"
        static let aiScheduledOrganizeHour = "ai.scheduledOrganize.hour"
        static let aiScheduledOrganizeMinute = "ai.scheduledOrganize.minute"
        static let aiScheduledOrganizeFrequency = "ai.scheduledOrganize.frequency"
        static let aiScheduledOrganizeRenameUntitled = "ai.scheduledOrganize.renameUntitled"
        static let aiScheduledOrganizeStarMap = "ai.scheduledOrganize.starMap"
        static let aiScheduledOrganizeRefreshDashboard = "ai.scheduledOrganize.refreshDashboard"
        static let aiScheduledOrganizeCatchUpOnWake = "ai.scheduledOrganize.catchUpOnWake"
        static let aiScheduledOrganizeLastCycleKey = "ai.scheduledOrganize.lastCycleKey"
        static let aiScheduledOrganizeLastSummary = "ai.scheduledOrganize.lastSummary"
        static let dashboardHeroCoverImageBase64 = "dashboard.heroCoverImageBase64"
        static let dashboardHeroCoverFocalX = "dashboard.heroCoverFocalX"
        static let dashboardHeroCoverFocalY = "dashboard.heroCoverFocalY"
        static let dashboardHeroCoverFitMode = "dashboard.heroCoverFitMode"
        static let userAvatarLibraryJSON = "media.avatarLibraryJSON"
        static let userBackgroundLibraryJSON = "media.backgroundLibraryJSON"
        static let boardBackgroundAssignmentsJSON = "media.boardBackgroundAssignmentsJSON"
        static let proactiveMenuBarTipsEnabled = "proactive.menuBarTipsEnabled"
        static let proactiveDailyTipsStateJSON = "proactive.dailyTipsStateJSON"
    }
    
    static let weeklyReportsDidChangeNotification = Notification.Name("CotLocalDatabaseWeeklyReportsDidChange")
    static let structuredAssetsDidChangeNotification = Notification.Name("CotLocalDatabaseStructuredAssetsDidChange")
    static let defaultWeeklyReportsZipPath = "/Users/cmy/Downloads/周报.zip"
    
    
    // MARK: Public Properties
    
    static let shared = CotLocalDatabase()
    
    /// Recently saved/updated documents in the local database.
    private(set) var documents: [StoredDocumentRecord] = []
    
    /// Document snapshots moved to the Document Center trash.
    private(set) var trashedDocuments: [StoredDocumentRecord] = []
    
    /// Monotonically incremented whenever `documents` is reloaded (including in-place renames/updates).
    private(set) var documentsRevision: Int = 0
    
    /// User-defined Document Center groups (ordered, including empty groups).
    private(set) var documentGroups: [String] = []
    
    /// All historical and generated weekly reports stored in the database (newest first).
    private(set) var weeklyReports: [StoredWeeklyReport] = []
    
    /// All configuration key-value pairs stored in the database (constructed lazily on demand).
    var configEntries: [DatabaseConfigEntry] {
        _ = self.configRevision
        if let cached = self.cachedConfigEntries {
            return cached
        }
        let entries = self.configMap
            .map { key, value in
                DatabaseConfigEntry(
                    key: key,
                    value: value,
                    updatedAt: Date(timeIntervalSince1970: self.configTimestamps[key] ?? 0)
                )
            }
            .sorted { $0.key < $1.key }
        self.cachedConfigEntries = entries
        return entries
    }
    
    /// Current number of persisted key-value config entries without sorting or allocating records.
    var configCount: Int {
        _ = self.configRevision
        return self.configMap.count
    }
    
    /// Monotonically incremented whenever any config entry changes.
    private(set) var configRevision: Int = 0
    
    /// The file URL of the active SQLite database.
    private(set) var databaseURL: URL
    
    
    // MARK: SQLite Storage & Sync State
    
    var db: OpaquePointer?
    let transientDestructor = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    private var userDefaultsSyncObserver: (any NSObjectProtocol)?
    private var userDefaultsSyncTask: Task<Void, Never>?
    private var isApplyingSyncedDefaults = false
    @ObservationIgnored private var configMap: [String: String] = [:]
    @ObservationIgnored private var configTimestamps: [String: TimeInterval] = [:]
    @ObservationIgnored private var cachedConfigEntries: [DatabaseConfigEntry]?
    @ObservationIgnored private var hasLoadedConfigMap = false
    @ObservationIgnored private var transactionDepth = 0
    
    
    static var isRunningUnitTests: Bool {
        
        let env = ProcessInfo.processInfo.environment
        return NSClassFromString("XCTestCase") != nil
            || env["XCTestConfigurationFilePath"] != nil
            || env["XCTestBundlePath"] != nil
    }
    
    
    // MARK: Lifecycle
    
    init(customURL: URL? = nil) {
        
        if let customURL {
            try? FileManager.default.createDirectory(at: customURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            self.databaseURL = customURL
        } else if Self.isRunningUnitTests {
            // Isolate XCTest hosts completely from the user's real database and open-tab session.
            self.databaseURL = FileManager.default.temporaryDirectory
                .appending(path: "cot_xctest_shared_\(ProcessInfo.processInfo.processIdentifier).sqlite3")
        } else {
            let resolvedURL = UserProfileManager.shared.activeDatabaseURL
            try? FileManager.default.createDirectory(at: resolvedURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            self.databaseURL = resolvedURL
        }
        
        self.openDatabase()
        self.createTablesIfNeeded()
        self.withTransaction {
            self.seedDefaultConfigsIfNeeded()
            self.reloadConfigs()
            self.migrateLegacyPromptsIfNeeded()
            self.migrateTypewriterV2IfNeeded()
        }
        
        if customURL == nil {
            self.seedDefaultWeeklyReportsIfNeeded()
        }
        self.purgeEnhancedAndNormalizeWeeklyReports(reloadAfter: false)
        self.reloadAll()
        
        if customURL == nil {
            self.pruneHistoricalTablesOnLaunchIfNeeded()
            self.observeUserDefaultsForSync()
        }
    }
    
    
    isolated deinit {
        
        self.userDefaultsSyncTask?.cancel()
        if let observer = self.userDefaultsSyncObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        self.closeDatabase()
    }
    
    
    // MARK: Public Configuration API
    
    /// Reads a string configuration value from the database, falling back to `defaultValue`.
    func string(forKey key: String, default defaultValue: String = "") -> String {
        
        if self.hasLoadedConfigMap {
            return self.configMap[key] ?? defaultValue
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
        
        if self.hasLoadedConfigMap, self.configMap[key] == value {
            return
        }
        
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
            let rc = sqlite3_step(stmt)
            if rc != SQLITE_DONE {
                self.logSQLiteError(#function, code: rc)
            }
        }
        sqlite3_finalize(stmt)
        
        if self.hasLoadedConfigMap {
            self.configMap[key] = value
            self.configTimestamps[key] = now
            self.cachedConfigEntries = nil
            self.configRevision &+= 1
        } else {
            self.reloadConfigs()
        }
    }
    
    
    /// Writes a boolean configuration value to the database.
    func set(_ value: Bool, forKey key: String) {
        
        self.set(value ? "true" : "false", forKey: key)
    }
    
    
    /// Removes a configuration key from the database.
    func removeConfig(forKey key: String) {
        
        if self.hasLoadedConfigMap, self.configMap[key] == nil {
            return
        }
        
        let sql = "DELETE FROM configs WHERE key = ?;"
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(self.db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, key, -1, self.transientDestructor)
            let rc = sqlite3_step(stmt)
            if rc != SQLITE_DONE {
                self.logSQLiteError(#function, code: rc)
            }
        }
        sqlite3_finalize(stmt)
        
        if self.hasLoadedConfigMap {
            self.configMap.removeValue(forKey: key)
            self.configTimestamps.removeValue(forKey: key)
            self.cachedConfigEntries = nil
            self.configRevision &+= 1
        } else {
            self.reloadConfigs()
        }
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
        highlights: [TextHighlight] = [],
        groupName: String? = nil
    ) {
        let resolvedID = id ?? filePath ?? "untitled:\(title)"
        let highlightsJSON = (try? String(data: JSONEncoder().encode(highlights), encoding: .utf8)) ?? "[]"
        let now = Date().timeIntervalSince1970
        let normalizedGroup = groupName?.trimmingCharacters(in: .whitespacesAndNewlines)
        
        let sql = """
        INSERT INTO documents (id, title, file_path, syntax, content, highlights_json, group_name, updated_at, created_at)
        VALUES (?, ?, ?, ?, ?, ?, COALESCE(?, ''), ?, ?)
        ON CONFLICT(id) DO UPDATE SET
            title = excluded.title,
            file_path = excluded.file_path,
            syntax = excluded.syntax,
            content = excluded.content,
            highlights_json = excluded.highlights_json,
            group_name = COALESCE(?, documents.group_name),
            updated_at = excluded.updated_at,
            created_at = COALESCE(documents.created_at, excluded.created_at);
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
            if let normalizedGroup {
                sqlite3_bind_text(stmt, 7, normalizedGroup, -1, self.transientDestructor)
            } else {
                sqlite3_bind_null(stmt, 7)
            }
            sqlite3_bind_double(stmt, 8, now)
            sqlite3_bind_double(stmt, 9, now)
            if let normalizedGroup {
                sqlite3_bind_text(stmt, 10, normalizedGroup, -1, self.transientDestructor)
            } else {
                sqlite3_bind_null(stmt, 10)
            }
            let rc = sqlite3_step(stmt)
            if rc != SQLITE_DONE {
                self.logSQLiteError(#function, code: rc)
            }
        }
        sqlite3_finalize(stmt)
        
        if let normalizedGroup, !normalizedGroup.isEmpty {
            self.registerDocumentGroupIfNeeded(normalizedGroup)
        }
        
        let nowDate = Date(timeIntervalSince1970: now)
        if let trashIdx = self.trashedDocuments.firstIndex(where: { $0.id == resolvedID }) {
            let existing = self.trashedDocuments.remove(at: trashIdx)
            let resolvedGroup = normalizedGroup ?? existing.groupName
            let updated = StoredDocumentRecord(
                id: resolvedID,
                title: title,
                filePath: filePath,
                syntax: syntax,
                content: content,
                highlightsJSON: highlightsJSON,
                updatedAt: nowDate,
                groupName: resolvedGroup,
                deletedAt: existing.deletedAt,
                createdAt: existing.createdAt ?? nowDate
            )
            self.trashedDocuments.insert(updated, at: 0)
            self.documentsRevision &+= 1
        } else {
            let existing: StoredDocumentRecord? = if let idx = self.documents.firstIndex(where: { $0.id == resolvedID }) {
                self.documents.remove(at: idx)
            } else {
                nil
            }
            let resolvedGroup = normalizedGroup ?? existing?.groupName ?? ""
            let updated = StoredDocumentRecord(
                id: resolvedID,
                title: title,
                filePath: filePath,
                syntax: syntax,
                content: content,
                highlightsJSON: highlightsJSON,
                updatedAt: nowDate,
                groupName: resolvedGroup,
                deletedAt: nil,
                createdAt: existing?.createdAt ?? nowDate
            )
            self.documents.insert(updated, at: 0)
            if self.documents.count > 200 {
                self.documents.removeLast(self.documents.count - 200)
            }
            if !resolvedGroup.isEmpty && resolvedGroup != "未分组" && !self.documentGroups.contains(resolvedGroup) {
                self.documentGroups.append(resolvedGroup)
            }
            self.documentsRevision &+= 1
        }
    }
    
    
    /// Fetches one stored non-deleted document record by ID or canonical file path without loading all rows.
    func fetchDocumentRecord(id: String?, filePath: String?) -> StoredDocumentRecord? {
        
        let trimmedID = id?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let trimmedPath = filePath?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmedID.isEmpty || !trimmedPath.isEmpty else { return nil }
        
        let lookupIDs: (raw: String, clean: String, prefixed: String)? = trimmedID.isEmpty ? nil : {
            let clean = trimmedID.hasPrefix("doc:") ? String(trimmedID.dropFirst(4)) : trimmedID
            return (trimmedID, clean, "doc:\(clean)")
        }()
        
        let sql: String
        if lookupIDs != nil, !trimmedPath.isEmpty {
            sql = """
            SELECT id, title, file_path, syntax, content, highlights_json, updated_at, COALESCE(group_name, ''), COALESCE(deleted_at, 0), COALESCE(created_at, updated_at)
            FROM documents
            WHERE deleted_at IS NULL AND (id = ? OR id = ? OR id = ? OR file_path = ? OR id = ?)
            ORDER BY updated_at DESC
            LIMIT 1;
            """
        } else if lookupIDs != nil {
            sql = """
            SELECT id, title, file_path, syntax, content, highlights_json, updated_at, COALESCE(group_name, ''), COALESCE(deleted_at, 0), COALESCE(created_at, updated_at)
            FROM documents
            WHERE deleted_at IS NULL AND (id = ? OR id = ? OR id = ?)
            ORDER BY updated_at DESC
            LIMIT 1;
            """
        } else {
            sql = """
            SELECT id, title, file_path, syntax, content, highlights_json, updated_at, COALESCE(group_name, ''), COALESCE(deleted_at, 0), COALESCE(created_at, updated_at)
            FROM documents
            WHERE deleted_at IS NULL AND (file_path = ? OR id = ?)
            ORDER BY updated_at DESC
            LIMIT 1;
            """
        }
        
        var stmt: OpaquePointer?
        var record: StoredDocumentRecord?
        if sqlite3_prepare_v2(self.db, sql, -1, &stmt, nil) == SQLITE_OK {
            if let lookupIDs, !trimmedPath.isEmpty {
                sqlite3_bind_text(stmt, 1, lookupIDs.raw, -1, self.transientDestructor)
                sqlite3_bind_text(stmt, 2, lookupIDs.clean, -1, self.transientDestructor)
                sqlite3_bind_text(stmt, 3, lookupIDs.prefixed, -1, self.transientDestructor)
                sqlite3_bind_text(stmt, 4, trimmedPath, -1, self.transientDestructor)
                sqlite3_bind_text(stmt, 5, trimmedPath, -1, self.transientDestructor)
            } else if let lookupIDs {
                sqlite3_bind_text(stmt, 1, lookupIDs.raw, -1, self.transientDestructor)
                sqlite3_bind_text(stmt, 2, lookupIDs.clean, -1, self.transientDestructor)
                sqlite3_bind_text(stmt, 3, lookupIDs.prefixed, -1, self.transientDestructor)
            } else {
                sqlite3_bind_text(stmt, 1, trimmedPath, -1, self.transientDestructor)
                sqlite3_bind_text(stmt, 2, trimmedPath, -1, self.transientDestructor)
            }
            if sqlite3_step(stmt) == SQLITE_ROW {
                record = Self.decodeStoredDocumentRow(stmt)
            }
        }
        sqlite3_finalize(stmt)
        return record
    }
    
    
    // MARK: Document Group API
    
    /// Creates a persistent Document Center group if it doesn't already exist.
    @discardableResult
    func createDocumentGroup(named rawName: String) -> String? {
        
        let trimmed = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != "未分组" else { return nil }
        
        var groups = self.loadStoredGroupList()
        if !groups.contains(trimmed) {
            groups.append(trimmed)
            self.saveStoredGroupList(groups)
        }
        if !self.documentGroups.contains(trimmed) {
            self.documentGroups.append(trimmed)
            self.documentsRevision &+= 1
        }
        return trimmed
    }
    
    
    /// Renames a Document Center group and updates every document assigned to it.
    @discardableResult
    func renameDocumentGroup(from oldName: String, to rawNewName: String) -> Bool {
        
        let trimmed = rawNewName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != "未分组", trimmed != oldName else { return false }
        
        var groups = self.loadStoredGroupList()
        guard !groups.contains(trimmed) else { return false }
        
        if let index = groups.firstIndex(of: oldName) {
            groups[index] = trimmed
        } else {
            groups.append(trimmed)
        }
        self.saveStoredGroupList(groups)
        
        let sql = "UPDATE documents SET group_name = ? WHERE group_name = ?;"
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(self.db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, trimmed, -1, self.transientDestructor)
            sqlite3_bind_text(stmt, 2, oldName, -1, self.transientDestructor)
            let rc = sqlite3_step(stmt)
            if rc != SQLITE_DONE {
                self.logSQLiteError(#function, code: rc)
            }
        }
        sqlite3_finalize(stmt)
        
        self.reloadDocuments()
        return true
    }
    
    
    /// Dissolves a Document Center group while keeping all of its documents intact as ungrouped.
    func deleteDocumentGroup(named name: String) {
        
        var groups = self.loadStoredGroupList()
        groups.removeAll { $0 == name }
        self.saveStoredGroupList(groups)
        
        let sql = "UPDATE documents SET group_name = '' WHERE group_name = ?;"
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(self.db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, name, -1, self.transientDestructor)
            let rc = sqlite3_step(stmt)
            if rc != SQLITE_DONE {
                self.logSQLiteError(#function, code: rc)
            }
        }
        sqlite3_finalize(stmt)
        
        self.reloadDocuments()
    }
    
    
    /// Removes stored Document Center groups that no longer contain any active document.
    ///
    /// - Returns: The group names that were pruned so callers can record them for undo.
    @discardableResult
    func pruneEmptyDocumentGroups(reloadAfter: Bool = true) -> [String] {
        
        var activeGroups = Set<String>()
        let sql = "SELECT DISTINCT group_name FROM documents WHERE deleted_at IS NULL AND group_name IS NOT NULL AND group_name != '';"
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(self.db, sql, -1, &stmt, nil) == SQLITE_OK {
            while sqlite3_step(stmt) == SQLITE_ROW {
                if let ptr = sqlite3_column_text(stmt, 0) {
                    activeGroups.insert(String(cString: ptr))
                }
            }
        }
        sqlite3_finalize(stmt)
        
        let stored = self.loadStoredGroupList()
        let removed = stored.filter { !activeGroups.contains($0) }
        guard !removed.isEmpty else { return [] }
        
        let kept = stored.filter { activeGroups.contains($0) }
        self.saveStoredGroupList(kept)
        if reloadAfter {
            self.reloadDocuments()
        } else {
            self.documentGroups = kept
            self.documentsRevision &+= 1
        }
        return removed
    }
    
    
    /// Assigns a document (by ID or file path, creating the record first if needed) to `groupName`.
    func assignDocumentGroup(
        id: String,
        filePath: String?,
        groupName: String,
        fallbackTitle: String = "",
        fallbackSyntax: String = "Plain Text",
        fallbackContent: String = "",
        reloadAfter: Bool = true
    ) {
        let trimmedGroup = groupName.trimmingCharacters(in: .whitespacesAndNewlines)
        let targetGroup = (trimmedGroup == "未分组") ? "" : trimmedGroup
        if !targetGroup.isEmpty {
            self.registerDocumentGroupIfNeeded(targetGroup)
        }
        
        let cleanID = id.hasPrefix("doc:") ? String(id.dropFirst(4)) : id
        let prefixedID = "doc:\(cleanID)"
        
        var changed = 0
        if let filePath, !filePath.isEmpty {
            let sql = "UPDATE documents SET group_name = ? WHERE id = ? OR id = ? OR id = ? OR file_path = ? OR id = ?;"
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(self.db, sql, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_text(stmt, 1, targetGroup, -1, self.transientDestructor)
                sqlite3_bind_text(stmt, 2, id, -1, self.transientDestructor)
                sqlite3_bind_text(stmt, 3, cleanID, -1, self.transientDestructor)
                sqlite3_bind_text(stmt, 4, prefixedID, -1, self.transientDestructor)
                sqlite3_bind_text(stmt, 5, filePath, -1, self.transientDestructor)
                sqlite3_bind_text(stmt, 6, filePath, -1, self.transientDestructor)
                sqlite3_step(stmt)
                changed = Int(sqlite3_changes(self.db))
            }
            sqlite3_finalize(stmt)
        } else {
            let sql = "UPDATE documents SET group_name = ? WHERE id = ? OR id = ? OR id = ?;"
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(self.db, sql, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_text(stmt, 1, targetGroup, -1, self.transientDestructor)
                sqlite3_bind_text(stmt, 2, id, -1, self.transientDestructor)
                sqlite3_bind_text(stmt, 3, cleanID, -1, self.transientDestructor)
                sqlite3_bind_text(stmt, 4, prefixedID, -1, self.transientDestructor)
                sqlite3_step(stmt)
                changed = Int(sqlite3_changes(self.db))
            }
            sqlite3_finalize(stmt)
        }
        
        if changed == 0, !fallbackTitle.isEmpty {
            self.saveDocument(
                id: id,
                title: fallbackTitle,
                filePath: filePath,
                syntax: fallbackSyntax,
                content: fallbackContent,
                groupName: targetGroup
            )
            return
        }
        
        if reloadAfter {
            self.reloadDocuments()
        }
    }
    
    
    private func loadStoredGroupList() -> [String] {
        
        let raw = self.string(forKey: ConfigKey.documentGroups)
        guard
            !raw.isEmpty,
            let data = raw.data(using: .utf8),
            let decoded = try? JSONDecoder().decode([String].self, from: data)
        else { return [] }
        return decoded
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0 != "未分组" }
    }
    
    
    private func saveStoredGroupList(_ groups: [String]) {
        
        var seen = Set<String>()
        let unique = groups
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0 != "未分组" && seen.insert($0).inserted }
        guard let data = try? JSONEncoder().encode(unique),
              let json = String(data: data, encoding: .utf8)
        else { return }
        self.set(json, forKey: ConfigKey.documentGroups)
    }
    
    
    private func registerDocumentGroupIfNeeded(_ groupName: String) {
        
        var groups = self.loadStoredGroupList()
        guard !groups.contains(groupName) else { return }
        groups.append(groupName)
        self.saveStoredGroupList(groups)
    }
    
    
    /// Deletes a stored document record from the database (matching by record ID or file path).
    func deleteDocument(id: String, filePath: String? = nil) {
        
        let cleanID = id.hasPrefix("doc:") ? String(id.dropFirst(4)) : id
        let prefixedID = "doc:\(cleanID)"
        
        if let filePath, !filePath.isEmpty {
            let sql = "DELETE FROM documents WHERE id = ? OR id = ? OR id = ? OR file_path = ? OR id = ?;"
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(self.db, sql, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_text(stmt, 1, id, -1, self.transientDestructor)
                sqlite3_bind_text(stmt, 2, cleanID, -1, self.transientDestructor)
                sqlite3_bind_text(stmt, 3, prefixedID, -1, self.transientDestructor)
                sqlite3_bind_text(stmt, 4, filePath, -1, self.transientDestructor)
                sqlite3_bind_text(stmt, 5, filePath, -1, self.transientDestructor)
                sqlite3_step(stmt)
            }
            sqlite3_finalize(stmt)
        } else {
            let sql = "DELETE FROM documents WHERE id = ? OR id = ? OR id = ?;"
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(self.db, sql, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_text(stmt, 1, id, -1, self.transientDestructor)
                sqlite3_bind_text(stmt, 2, cleanID, -1, self.transientDestructor)
                sqlite3_bind_text(stmt, 3, prefixedID, -1, self.transientDestructor)
                sqlite3_step(stmt)
            }
            sqlite3_finalize(stmt)
        }
        
        self.reloadDocuments()
    }
    
    
    /// Moves a stored document snapshot into the Document Center trash.
    func trashDocument(id: String, filePath: String? = nil) {
        
        self.setDocumentDeletedAt(Date().timeIntervalSince1970, id: id, filePath: filePath)
    }
    
    
    /// Brings a trashed document snapshot back into the Document Center.
    func restoreDocument(id: String, filePath: String? = nil) {
        
        self.setDocumentDeletedAt(nil, id: id, filePath: filePath)
    }
    
    
    /// Deletes one trashed snapshot permanently.
    func permanentlyDeleteDocument(id: String, filePath: String? = nil) {
        
        self.deleteDocument(id: id, filePath: filePath)
    }
    
    
    /// Permanently deletes every snapshot currently in the trash.
    func emptyDocumentTrash() {
        
        self.executeSQL("DELETE FROM documents WHERE deleted_at IS NOT NULL;")
        self.reloadDocuments()
    }
    
    
    private func setDocumentDeletedAt(_ timestamp: TimeInterval?, id: String, filePath: String?) {
        
        let cleanID = id.hasPrefix("doc:") ? String(id.dropFirst(4)) : id
        let prefixedID = "doc:\(cleanID)"
        let sql = """
        UPDATE documents SET deleted_at = ?
        WHERE id = ? OR id = ? OR id = ? OR (? IS NOT NULL AND file_path = ?);
        """
        
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(self.db, sql, -1, &stmt, nil) == SQLITE_OK {
            if let timestamp {
                sqlite3_bind_double(stmt, 1, timestamp)
            } else {
                sqlite3_bind_null(stmt, 1)
            }
            sqlite3_bind_text(stmt, 2, id, -1, self.transientDestructor)
            sqlite3_bind_text(stmt, 3, cleanID, -1, self.transientDestructor)
            sqlite3_bind_text(stmt, 4, prefixedID, -1, self.transientDestructor)
            if let filePath {
                sqlite3_bind_text(stmt, 5, filePath, -1, self.transientDestructor)
                sqlite3_bind_text(stmt, 6, filePath, -1, self.transientDestructor)
            } else {
                sqlite3_bind_null(stmt, 5)
                sqlite3_bind_null(stmt, 6)
            }
            sqlite3_step(stmt)
        }
        sqlite3_finalize(stmt)
        
        self.reloadDocuments()
    }
    
    
    /// Updates an existing document record's identifier, title, or file path when renamed or saved.
    func renameDocument(
        oldID: String,
        oldFilePath: String? = nil,
        newID: String,
        newTitle: String,
        newFilePath: String?,
        reloadAfter: Bool = true
    ) {
        
        let cleanOldID = oldID.hasPrefix("doc:") ? String(oldID.dropFirst(4)) : oldID
        let candidateOldIDs = Set([oldID, cleanOldID, "doc:\(cleanOldID)"])
        
        let matchedOld = self.documents.first {
            candidateOldIDs.contains($0.id) || (oldFilePath != nil && $0.filePath == oldFilePath)
        }
        let matchedNew = self.documents.first {
            $0.id == newID || (newFilePath != nil && $0.filePath == newFilePath)
        }
        
        let preservedGroup: String = {
            if let grp = matchedOld?.groupName, !grp.isEmpty { return grp }
            if let grp = matchedNew?.groupName, !grp.isEmpty { return grp }
            return ""
        }()
        
        let now = Date().timeIntervalSince1970
        if let oldRecord = matchedOld {
            if let conflict = matchedNew, conflict.id != oldRecord.id {
                let deleteConflictSQL = "DELETE FROM documents WHERE id = ?;"
                var delStmt: OpaquePointer?
                if sqlite3_prepare_v2(self.db, deleteConflictSQL, -1, &delStmt, nil) == SQLITE_OK {
                    sqlite3_bind_text(delStmt, 1, conflict.id, -1, self.transientDestructor)
                    let rc = sqlite3_step(delStmt)
                    if rc != SQLITE_DONE {
                        self.logSQLiteError("renameDocument.deleteConflict", code: rc)
                    }
                }
                sqlite3_finalize(delStmt)
            }
            
            // Never clobber SQLite's latest `group_name` with a stale in-memory cache when renaming
            // in-place (especially inside batch transactions after `assignDocumentGroup`).
            if oldRecord.id == newID {
                let updateSQL = "UPDATE documents SET title = ?, file_path = ?, updated_at = ? WHERE id = ?;"
                var stmt: OpaquePointer?
                if sqlite3_prepare_v2(self.db, updateSQL, -1, &stmt, nil) == SQLITE_OK {
                    sqlite3_bind_text(stmt, 1, newTitle, -1, self.transientDestructor)
                    if let newFilePath {
                        sqlite3_bind_text(stmt, 2, newFilePath, -1, self.transientDestructor)
                    } else {
                        sqlite3_bind_null(stmt, 2)
                    }
                    sqlite3_bind_double(stmt, 3, now)
                    sqlite3_bind_text(stmt, 4, oldRecord.id, -1, self.transientDestructor)
                    let rc = sqlite3_step(stmt)
                    if rc != SQLITE_DONE {
                        self.logSQLiteError("renameDocument.updateInPlace", code: rc)
                    }
                }
                sqlite3_finalize(stmt)
            } else {
                let updateSQL = "UPDATE documents SET id = ?, title = ?, file_path = ?, group_name = COALESCE(NULLIF(group_name, ''), ?), updated_at = ? WHERE id = ?;"
                var stmt: OpaquePointer?
                if sqlite3_prepare_v2(self.db, updateSQL, -1, &stmt, nil) == SQLITE_OK {
                    sqlite3_bind_text(stmt, 1, newID, -1, self.transientDestructor)
                    sqlite3_bind_text(stmt, 2, newTitle, -1, self.transientDestructor)
                    if let newFilePath {
                        sqlite3_bind_text(stmt, 3, newFilePath, -1, self.transientDestructor)
                    } else {
                        sqlite3_bind_null(stmt, 3)
                    }
                    sqlite3_bind_text(stmt, 4, preservedGroup, -1, self.transientDestructor)
                    sqlite3_bind_double(stmt, 5, now)
                    sqlite3_bind_text(stmt, 6, oldRecord.id, -1, self.transientDestructor)
                    let rc = sqlite3_step(stmt)
                    if rc != SQLITE_DONE {
                        self.logSQLiteError("renameDocument.updateOld", code: rc)
                    }
                }
                sqlite3_finalize(stmt)
            }
        } else if let newRecord = matchedNew {
            let updateSQL = "UPDATE documents SET id = ?, title = ?, file_path = ?, updated_at = ? WHERE id = ?;"
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(self.db, updateSQL, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_text(stmt, 1, newID, -1, self.transientDestructor)
                sqlite3_bind_text(stmt, 2, newTitle, -1, self.transientDestructor)
                if let newFilePath {
                    sqlite3_bind_text(stmt, 3, newFilePath, -1, self.transientDestructor)
                } else {
                    sqlite3_bind_null(stmt, 3)
                }
                sqlite3_bind_double(stmt, 4, now)
                sqlite3_bind_text(stmt, 5, newRecord.id, -1, self.transientDestructor)
                let rc = sqlite3_step(stmt)
                if rc != SQLITE_DONE {
                    self.logSQLiteError("renameDocument.updateNew", code: rc)
                }
            }
            sqlite3_finalize(stmt)
        } else {
            // Direct SQLite fallback for rows inserted earlier inside the same uncommitted transaction.
            let prefixedOld = "doc:\(cleanOldID)"
            let updateSQL = "UPDATE documents SET title = ?, file_path = COALESCE(?, file_path), updated_at = ? WHERE id = ? OR id = ? OR id = ?;"
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(self.db, updateSQL, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_text(stmt, 1, newTitle, -1, self.transientDestructor)
                if let newFilePath {
                    sqlite3_bind_text(stmt, 2, newFilePath, -1, self.transientDestructor)
                } else {
                    sqlite3_bind_null(stmt, 2)
                }
                sqlite3_bind_double(stmt, 3, now)
                sqlite3_bind_text(stmt, 4, oldID, -1, self.transientDestructor)
                sqlite3_bind_text(stmt, 5, cleanOldID, -1, self.transientDestructor)
                sqlite3_bind_text(stmt, 6, prefixedOld, -1, self.transientDestructor)
                let rc = sqlite3_step(stmt)
                if rc != SQLITE_DONE {
                    self.logSQLiteError("renameDocument.updateDirect", code: rc)
                }
            }
            sqlite3_finalize(stmt)
        }
        
        if reloadAfter {
            self.reloadDocuments()
        }
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
            let rc = sqlite3_step(stmt)
            if rc != SQLITE_DONE {
                self.logSQLiteError(#function, code: rc)
            }
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
            let rc = sqlite3_step(stmt)
            if rc != SQLITE_DONE {
                self.logSQLiteError(#function, code: rc)
            }
        }
        sqlite3_finalize(stmt)
        
        self.reloadWeeklyReports()
    }
    
    
    /// Lightweight value payload for parsing weekly reports off `@MainActor`.
    nonisolated struct PreparedWeeklyReportPayload: Sendable {
        let id: String
        let periodLabel: String
        let yearMonth: String
        let title: String
        let content: String
        let sourcePath: String?
        let isEnhanced: Bool
        let modifiedAt: Date?
    }
    
    
    /// Parses weekly report files / folders / `.zip` archives on any queue before writing to SQLite.
    nonisolated static func prepareWeeklyReportPayloads(
        fromURLs urls: [URL],
        knownUpdatedAtBySourcePath: [String: Date] = [:]
    ) throws -> [PreparedWeeklyReportPayload] {
        
        var payloads: [PreparedWeeklyReportPayload] = []
        let fm = FileManager.default
        
        for url in urls {
            if url.pathExtension.lowercased() == "zip" {
                payloads.append(contentsOf: try Self.prepareWeeklyReportPayloads(fromZipURL: url))
                continue
            }
            
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
                if let enumerator = fm.enumerator(
                    at: url,
                    includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey]
                ) {
                    var files: [URL] = []
                    for case let fileURL as URL in enumerator {
                        let name = fileURL.lastPathComponent
                        let lower = name.lowercased()
                        if !name.hasPrefix("._"),
                           !lower.contains("_enhanced"),
                           !name.contains("增强版"),
                           ["md", "txt", "markdown"].contains(fileURL.pathExtension.lowercased())
                        {
                            files.append(fileURL)
                        }
                    }
                    payloads.append(contentsOf: Self.prepareWeeklyReportFiles(
                        files,
                        baseFolder: url,
                        knownUpdatedAtBySourcePath: knownUpdatedAtBySourcePath
                    ))
                }
            } else {
                payloads.append(contentsOf: Self.prepareWeeklyReportFiles(
                    [url],
                    baseFolder: url.deletingLastPathComponent(),
                    knownUpdatedAtBySourcePath: knownUpdatedAtBySourcePath
                ))
            }
        }
        return payloads
    }
    
    
    private nonisolated static func prepareWeeklyReportPayloads(fromZipURL zipURL: URL) throws -> [PreparedWeeklyReportPayload] {
        
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
                let lower = path.lowercased()
                return !path.isEmpty
                    && !path.contains("..")
                    && !path.hasPrefix("__MACOSX/")
                    && !URL(filePath: path).lastPathComponent.hasPrefix("._")
                    && !lower.contains("_enhanced")
                    && !path.contains("增强版")
                    && lower.hasSuffix(".md")
            }
        guard !entryPaths.isEmpty else { return [] }
        
        let fm = FileManager.default
        let tempDir = fm.temporaryDirectory.appending(path: "cot_zip_\(UUID().uuidString)", directoryHint: .isDirectory)
        try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tempDir) }
        
        let extractProcess = Process()
        extractProcess.executableURL = URL(filePath: "/usr/bin/unzip")
        extractProcess.arguments = ["-qq", "-o", zipURL.path, "-d", tempDir.path]
        extractProcess.standardOutput = Pipe()
        extractProcess.standardError = Pipe()
        try extractProcess.run()
        extractProcess.waitUntilExit()
        guard extractProcess.terminationStatus == 0 else {
            throw CocoaError(.fileReadCorruptFile)
        }
        
        var payloads: [PreparedWeeklyReportPayload] = []
        payloads.reserveCapacity(entryPaths.count)
        for entryPath in entryPaths {
            let extractedURL = tempDir.appending(path: entryPath)
            guard let content = try? String(contentsOf: extractedURL, encoding: .utf8),
                  !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else { continue }
            let parsed = Self.parseWeeklyReportMetadata(relativePath: entryPath, content: content)
            payloads.append(PreparedWeeklyReportPayload(
                id: parsed.id,
                periodLabel: parsed.periodLabel,
                yearMonth: parsed.yearMonth,
                title: parsed.title,
                content: content,
                sourcePath: entryPath,
                isEnhanced: parsed.isEnhanced,
                modifiedAt: nil
            ))
        }
        return payloads
    }
    
    
    private nonisolated static func prepareWeeklyReportFiles(
        _ urls: [URL],
        baseFolder: URL,
        knownUpdatedAtBySourcePath: [String: Date]
    ) -> [PreparedWeeklyReportPayload] {
        
        let basePath = baseFolder.path
        var payloads: [PreparedWeeklyReportPayload] = []
        payloads.reserveCapacity(urls.count)
        
        for fileURL in urls {
            let name = fileURL.lastPathComponent
            if name.lowercased().contains("_enhanced") || name.contains("增强版") {
                continue
            }
            let values = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey])
            let modDate = values?.contentModificationDate
            if let modDate,
               let knownUpdatedAt = knownUpdatedAtBySourcePath[fileURL.path],
               knownUpdatedAt.timeIntervalSince(modDate) > 2.0
            {
                continue
            }
            guard let content = try? String(contentsOf: fileURL, encoding: .utf8),
                  !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else { continue }
            
            let relPath = fileURL.path.hasPrefix(basePath + "/")
                ? String(fileURL.path.dropFirst(basePath.count + 1))
                : fileURL.lastPathComponent
            let parsed = Self.parseWeeklyReportMetadata(relativePath: relPath, content: content)
            payloads.append(PreparedWeeklyReportPayload(
                id: parsed.id,
                periodLabel: parsed.periodLabel,
                yearMonth: parsed.yearMonth,
                title: parsed.title,
                content: content,
                sourcePath: fileURL.path,
                isEnhanced: parsed.isEnhanced,
                modifiedAt: modDate
            ))
        }
        return payloads
    }
    
    
    /// Batch-persists pre-parsed weekly report payloads inside one SQLite transaction.
    @discardableResult
    func applyPreparedWeeklyReports(_ payloads: [PreparedWeeklyReportPayload]) -> Int {
        
        guard !payloads.isEmpty else { return 0 }
        self.withTransaction {
            for payload in payloads {
                self.saveWeeklyReport(
                    id: payload.id,
                    periodLabel: payload.periodLabel,
                    yearMonth: payload.yearMonth,
                    title: payload.title,
                    content: payload.content,
                    sourcePath: payload.sourcePath,
                    isEnhanced: payload.isEnhanced,
                    reloadAfter: false
                )
            }
        }
        self.purgeEnhancedAndNormalizeWeeklyReports(reloadAfter: false)
        self.reloadWeeklyReports()
        return payloads.count
    }
    
    
    /// Imports all Markdown weekly reports from a `.zip` archive into `weekly_reports`.
    ///
    /// - Returns: The number of weekly reports imported or updated.
    @discardableResult
    func importWeeklyReports(fromZipURL zipURL: URL) throws -> Int {
        
        let payloads = try Self.prepareWeeklyReportPayloads(fromZipURL: zipURL)
        return self.applyPreparedWeeklyReports(payloads)
    }
    
    
    /// Imports weekly report `.md` / `.txt` files or directories (or `.zip`) selected by the user.
    @discardableResult
    func importWeeklyReports(fromURLs urls: [URL]) throws -> Int {
        
        let knownDates = self.weeklyReportsKnownUpdatedAtBySourcePath()
        let payloads = try Self.prepareWeeklyReportPayloads(fromURLs: urls, knownUpdatedAtBySourcePath: knownDates)
        return self.applyPreparedWeeklyReports(payloads)
    }
    
    
    func weeklyReportsKnownUpdatedAtBySourcePath() -> [String: Date] {
        var map: [String: Date] = [:]
        map.reserveCapacity(self.weeklyReports.count)
        for report in self.weeklyReports {
            if let sourcePath = report.sourcePath, !sourcePath.isEmpty {
                map[sourcePath] = report.updatedAt
            }
        }
        return map
    }
    
    
    /// Returns recent non-enhanced weekly reports to serve as style references when generating new reports.
    func styleReferenceWeeklyReports(limit: Int = 2) -> [StoredWeeklyReport] {
        
        let standard = Array(self.weeklyReports.lazy.filter { !$0.isEnhanced }.prefix(limit))
        return standard.isEmpty ? Array(self.weeklyReports.prefix(limit)) : standard
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
        self.reloadWeeklyReports()
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
    
    
    /// Period metadata for any week offset relative to `referenceDate`.
    static func weekPeriodInfo(
        for referenceDate: Date = .now,
        weekOffset: Int = 0
    ) -> (periodLabel: String, yearMonth: String, displayRange: String) {
        
        let calendar = Calendar(identifier: .gregorian)
        let targetDate = calendar.date(byAdding: .weekOfYear, value: weekOffset, to: referenceDate) ?? referenceDate
        let weekday = calendar.component(.weekday, from: targetDate)  // 1 = Sun, 2 = Mon
        let daysFromMonday = (weekday == 1) ? 6 : (weekday - 2)
        let monday = calendar.date(byAdding: .day, value: -daysFromMonday, to: targetDate) ?? targetDate
        let friday = calendar.date(byAdding: .day, value: 4, to: monday) ?? monday
        
        let startFmt = DateFormatter()
        startFmt.dateFormat = "yyyyMMdd"
        let endFmt = DateFormatter()
        endFmt.dateFormat = "MMdd"
        let ymFmt = DateFormatter()
        ymFmt.dateFormat = "yyyyMM"
        let dispFmt = DateFormatter()
        dispFmt.dateFormat = "MM/dd"
        
        let periodLabel = "\(startFmt.string(from: monday))-\(endFmt.string(from: friday))"
        let yearMonth = ymFmt.string(from: monday)
        let displayRange = "\(dispFmt.string(from: monday)) - \(dispFmt.string(from: friday))"
        return (periodLabel, yearMonth, displayRange)
    }
    
    
    /// Builds a clean Markdown weekly report skeleton matching the user's historical specification.
    static func makeWeeklyReportTemplate(
        author: String,
        periodLabel: String,
        fragments: String = ""
    ) -> String {
        
        let cleanAuthor = author.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "陈明扬" : author.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanFragments = fragments.trimmingCharacters(in: .whitespacesAndNewlines)
        
        let fragmentLines: String = if cleanFragments.isEmpty {
            "1. \n2. "
        } else {
            cleanFragments
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
                .enumerated()
                .map { idx, line in
                    let stripped = line.replacingOccurrences(of: #"^\d+[\.\、]\s*"#, with: "", options: .regularExpression)
                    return "\(idx + 1). \(stripped)"
                }
                .joined(separator: "\n")
        }
        
        return """
        # \(cleanAuthor)-周报-\(periodLabel)

        本周主要干了以下几件事：

        1. 
        2. 

        ## 重点事项一

        进展：
        \(fragmentLines)

        卡点：
        1. （无卡点可删除本段）

        ## 下周计划

        1. 
        """
    }
    
    
    /// Creates a new weekly report for the target cycle (`weekOffset = 0` means the current week),
    /// or returns the existing one if that cycle already has a report so existing edits are preserved.
    @discardableResult
    func createWeeklyReport(
        referenceDate: Date = .now,
        weekOffset: Int = 0,
        includeSavedFragments: Bool = true
    ) -> (report: StoredWeeklyReport, alreadyExisted: Bool) {
        
        let info = Self.weekPeriodInfo(for: referenceDate, weekOffset: weekOffset)
        if let existing = self.weeklyReports.first(where: {
            $0.periodLabel == info.periodLabel || $0.id == "\(info.yearMonth)/\(info.periodLabel)"
        }) {
            return (existing, true)
        }
        
        let author = self.weeklyReportAuthor
        let fragments = includeSavedFragments ? self.string(forKey: ConfigKey.weeklyReportFragments) : ""
        let content = Self.makeWeeklyReportTemplate(
            author: author,
            periodLabel: info.periodLabel,
            fragments: fragments
        )
        let reportID = "\(info.yearMonth)/\(info.periodLabel)"
        let title = "\(author)-周报-\(info.periodLabel)"
        
        self.saveWeeklyReport(
            id: reportID,
            periodLabel: info.periodLabel,
            yearMonth: info.yearMonth,
            title: title,
            content: content,
            sourcePath: nil,
            isEnhanced: false,
            reloadAfter: true
        )
        
        let resolved = self.weeklyReports.first(where: { $0.id == reportID }) ?? StoredWeeklyReport(
            id: reportID,
            periodLabel: info.periodLabel,
            yearMonth: info.yearMonth,
            title: title,
            content: content,
            sourcePath: nil,
            isEnhanced: false,
            createdAt: Date(),
            updatedAt: Date()
        )
        return (resolved, false)
    }
    
    
    /// Renames a stored weekly report, updating period metadata cleanly if a `YYYYMMDD-MMDD` range is present.
    func renameWeeklyReport(id: String, newTitle rawTitle: String) {
        
        let trimmed = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let existing = self.weeklyReports.first(where: { $0.id == id }) else { return }
        
        var updatedPeriod = existing.periodLabel
        var updatedYearMonth = existing.yearMonth
        if let range = trimmed.range(of: #"20\d{6}-\d{4}"#, options: .regularExpression) {
            updatedPeriod = String(trimmed[range])
            updatedYearMonth = String(updatedPeriod.prefix(6))
        }
        
        self.saveWeeklyReport(
            id: existing.id,
            periodLabel: updatedPeriod,
            yearMonth: updatedYearMonth,
            title: trimmed,
            content: existing.content,
            sourcePath: existing.sourcePath,
            isEnhanced: false,
            createdAt: existing.createdAt,
            reloadAfter: true
        )
    }
    
    
    nonisolated static func parseWeeklyReportMetadata(relativePath: String, content: String) -> (id: String, periodLabel: String, yearMonth: String, title: String, isEnhanced: Bool) {
        
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
            .replacingOccurrences(of: "（增强版）", with: "")
            .replacingOccurrences(of: "(增强版)", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
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
        
        let periodLabel: String = if let range = basePeriod.range(of: #"20\d{6}-\d{4}"#, options: .regularExpression) {
            String(basePeriod[range])
        } else if let range = title.range(of: #"20\d{6}-\d{4}"#, options: .regularExpression) {
            String(title[range])
        } else {
            basePeriod
        }
        let stableID = cleanPath.hasSuffix(".md") ? String(cleanPath.dropLast(3)) : cleanPath
        return (stableID, periodLabel, yearMonth, title, false)
    }
    
    
    /// Removes all enhanced (`增强版` / `_enhanced`) weekly reports and normalizes remaining report titles/periods.
    func purgeEnhancedAndNormalizeWeeklyReports(reloadAfter: Bool = true) {
        
        self.withTransaction {
            self.executeSQL("""
            DELETE FROM weekly_reports
            WHERE is_enhanced != 0
               OR lower(id) LIKE '%_enhanced%'
               OR lower(COALESCE(source_path, '')) LIKE '%_enhanced%'
               OR period_label LIKE '%增强版%'
               OR title LIKE '%增强版%';
            """)
            
            self.reloadWeeklyReports(postNotification: false)
            let author = self.weeklyReportAuthor
            for report in self.weeklyReports {
                var normalizedPeriod = report.periodLabel
                    .replacingOccurrences(of: "（增强版）", with: "")
                    .replacingOccurrences(of: "(增强版)", with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if let match = normalizedPeriod.range(of: #"20\d{6}-\d{4}"#, options: .regularExpression) {
                    normalizedPeriod = String(normalizedPeriod[match])
                } else if let match = report.title.range(of: #"20\d{6}-\d{4}"#, options: .regularExpression) {
                    normalizedPeriod = String(report.title[match])
                }
                
                var normalizedTitle = report.title
                    .replacingOccurrences(of: "（增强版）", with: "")
                    .replacingOccurrences(of: "(增强版)", with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if normalizedPeriod.range(of: #"^20\d{6}-\d{4}$"#, options: .regularExpression) != nil {
                    normalizedTitle = "\(author)-周报-\(normalizedPeriod)"
                }
                
                if normalizedPeriod != report.periodLabel || normalizedTitle != report.title || report.isEnhanced {
                    self.saveWeeklyReport(
                        id: report.id,
                        periodLabel: normalizedPeriod,
                        yearMonth: report.yearMonth,
                        title: normalizedTitle,
                        content: report.content,
                        sourcePath: report.sourcePath,
                        isEnhanced: false,
                        createdAt: report.createdAt,
                        reloadAfter: false
                    )
                }
            }
        }
        if reloadAfter {
            self.reloadWeeklyReports()
        }
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
    
    
    // MARK: Multi-User & Sync Helpers
    
    /// Flushes WAL changes back into the primary SQLite file before switching users or backing up.
    func checkpointDatabase() {
        
        self.executeSQL("PRAGMA wal_checkpoint(TRUNCATE);")
    }
    
    
    /// Closes the current SQLite handle and mounts a different user's isolated SQLite database file.
    func switchDatabase(to newURL: URL, defaultAuthorName: String? = nil) {
        
        try? FileManager.default.createDirectory(at: newURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        self.closeDatabase()
        self.databaseURL = newURL
        self.openDatabase()
        self.createTablesIfNeeded()
        self.withTransaction {
            self.seedDefaultConfigsIfNeeded(defaultAuthorName: defaultAuthorName)
            self.reloadConfigs()
            self.migrateLegacyPromptsIfNeeded()
            self.migrateTypewriterV2IfNeeded()
        }
        self.purgeEnhancedAndNormalizeWeeklyReports(reloadAfter: false)
        self.reloadAll()
        
        if self === Self.shared {
            NotificationCenter.default.post(name: Self.structuredAssetsDidChangeNotification, object: self)
        }
    }
    
    
    /// Snapshots `AIEndpointStore` profiles, active ID, and API keys into the active user's database.
    func syncAIEndpointsToDatabase() {
        
        let profiles = AIEndpointStore.profiles
        if let profilesData = try? JSONEncoder().encode(profiles),
           let profilesJSON = String(data: profilesData, encoding: .utf8)
        {
            self.set(profilesJSON, forKey: ConfigKey.syncAIProfiles)
        }
        self.set(AIEndpointStore.activeID?.uuidString ?? "", forKey: ConfigKey.syncAIActiveProfileID)
        
        var keyMap: [String: String] = [:]
        for profile in profiles {
            let key = AIKeychain.apiKey(for: profile.id).trimmingCharacters(in: .whitespacesAndNewlines)
            if !key.isEmpty {
                keyMap[profile.id.uuidString] = key
            }
        }
        let legacyKey = AIKeychain.legacyAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !legacyKey.isEmpty {
            keyMap["__legacy__"] = legacyKey
        }
        if let keysData = try? JSONEncoder().encode(keyMap),
           let keysJSON = String(data: keysData, encoding: .utf8)
        {
            self.set(keysJSON, forKey: ConfigKey.syncAIProfileAPIKeys)
        }
    }
    
    
    /// Restores `AIEndpointStore` profiles, active ID, and API keys from the active user's database.
    func restoreAIEndpointsFromDatabase(resetIfMissing: Bool) {
        
        let syncedProfilesJSON = self.queryConfigValue(forKey: ConfigKey.syncAIProfiles) ?? ""
        if !syncedProfilesJSON.isEmpty,
           let data = syncedProfilesJSON.data(using: .utf8),
           let importedProfiles = try? JSONDecoder().decode([AIEndpointProfile].self, from: data)
        {
            let activeStr = self.queryConfigValue(forKey: ConfigKey.syncAIActiveProfileID) ?? ""
            let importedActiveID = activeStr.isEmpty ? nil : UUID(uuidString: activeStr)
            
            if resetIfMissing {
                AIEndpointStore.profiles = importedProfiles
                AIEndpointStore.activeID = importedActiveID ?? importedProfiles.first?.id
            } else if !importedProfiles.isEmpty {
                var existing = AIEndpointStore.profiles
                for profile in importedProfiles {
                    if let idx = existing.firstIndex(where: { $0.id == profile.id }) {
                        existing[idx] = profile
                    } else {
                        existing.append(profile)
                    }
                }
                AIEndpointStore.profiles = existing
                if let importedActiveID, existing.contains(where: { $0.id == importedActiveID }) {
                    AIEndpointStore.activeID = importedActiveID
                } else if AIEndpointStore.activeID == nil {
                    AIEndpointStore.activeID = existing.first?.id
                }
            }
        } else if resetIfMissing {
            AIEndpointStore.profiles = []
            AIEndpointStore.activeID = nil
        }
        
        let syncedKeysJSON = self.queryConfigValue(forKey: ConfigKey.syncAIProfileAPIKeys) ?? ""
        if !syncedKeysJSON.isEmpty,
           let keysData = syncedKeysJSON.data(using: .utf8),
           let keyMap = try? JSONDecoder().decode([String: String].self, from: keysData)
        {
            var uuidMap: [String: String] = [:]
            for (account, key) in keyMap {
                if account == "__legacy__" {
                    AIKeychain.setLegacyAPIKey(key)
                } else {
                    uuidMap[account] = key
                }
            }
            AIKeychain.mergeAPIKeys(uuidMap, overwriteExisting: true)
        }
    }
    
    
    /// Snapshots the active user's avatar, display name, accent color, and account metadata into `configs`.
    func syncUserProfileToDatabase(_ profile: UserProfile? = nil) {
        
        let resolvedProfile: UserProfile? = if let profile {
            profile
        } else if self === Self.shared {
            UserProfileManager.shared.activeProfile
        } else {
            nil
        }
        guard let resolvedProfile else { return }
        
        let snapshot = PortableUserProfileSnapshot(profile: resolvedProfile)
        if let data = try? JSONEncoder().encode(snapshot),
           let json = String(data: data, encoding: .utf8)
        {
            self.set(json, forKey: ConfigKey.syncUserProfileSnapshot)
        }
    }
    
    
    /// Restores the user's profile (avatar, display name, accent color) from `sync.userProfileSnapshot`.
    func restoreUserProfileFromDatabase(to manager: UserProfileManager? = nil) {
        
        let targetManager: UserProfileManager? = if let manager {
            manager
        } else if self === Self.shared {
            UserProfileManager.shared
        } else {
            nil
        }
        guard let targetManager else { return }
        
        let json = self.queryConfigValue(forKey: ConfigKey.syncUserProfileSnapshot) ?? ""
        guard !json.isEmpty,
              let data = json.data(using: .utf8),
              let snapshot = try? JSONDecoder().decode(PortableUserProfileSnapshot.self, from: data)
        else { return }
        
        targetManager.applyImportedProfileSnapshot(snapshot)
    }
    
    
    // MARK: Import & Export API
    
    /// Exports the entire SQLite database (with current AI profiles, API keys, user avatar/profile & settings synced into `configs`)
    /// to the destination URL using `VACUUM INTO` or atomic file copy.
    func exportDatabase(to destinationURL: URL) throws {
        
        // Snapshot current stats, AI endpoint profiles + keys, user profile/avatar & user preferences into configs
        if self === Self.shared {
            AnalyticsManager.shared.flushPendingStats()
            self.syncAIEndpointsToDatabase()
            self.syncUserProfileToDatabase()
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
    
    
    /// Imports another Cot SQLite database file, replacing/merging documents, AI endpoints+keys, user avatar/profile, and configurations.
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
        
        self.restoreAIEndpointsFromDatabase(resetIfMissing: false)
        self.restoreUserProfileFromDatabase()
        self.restoreUserPreferencesFromDatabase(overwriteExisting: true)
        self.applySyncedDefaultsToUserDefaults()
        
        if self === Self.shared {
            StudioPaletteManager.shared.reloadFromDatabase()
            WallpaperManager.shared.reloadFromDatabase()
            UserMediaLibraryStore.shared.reloadFromDatabase()
            ThemeManager.shared.validateOrRepairActiveThemePreference()
            AIBotStore.shared.reloadFromDatabase()
            UserHabitPredictor.shared.reloadFromDatabase()
            AINextTokenPredictor.shared.reloadForActiveUser()
            AnalyticsManager.shared.reloadFromDatabase()
            NotificationCenter.default.post(name: Self.structuredAssetsDidChangeNotification, object: self)
            NotificationCenter.default.post(name: UserProfileManager.activeProfileDidChangeNotification, object: UserProfileManager.shared)
        }
    }
    
    
    /// Syncs feature toggles stored in `CotLocalDatabase` back to `UserDefaults` so live bindings update.
    func applySyncedDefaultsToUserDefaults() {
        
        self.isApplyingSyncedDefaults = true
        defer { self.isApplyingSyncedDefaults = false }
        
        let defaults = UserDefaults.standard
        defaults.set(self.bool(forKey: ConfigKey.typewriterEffectEnabled, default: true), forKey: ConfigKey.typewriterEffectEnabled)
        let styleRaw = self.string(forKey: ConfigKey.typewriterEffectStyle, default: "powerMode")
        defaults.set(styleRaw.isEmpty ? "powerMode" : styleRaw, forKey: ConfigKey.typewriterEffectStyle)
        defaults.set(self.bool(forKey: ConfigKey.vimCursorEffectEnabled, default: true), forKey: ConfigKey.vimCursorEffectEnabled)
        defaults.set(self.bool(forKey: ConfigKey.plainTextInlineImagesEnabled, default: true), forKey: ConfigKey.plainTextInlineImagesEnabled)
        
        defaults.set(self.bool(forKey: ConfigKey.inlineCompletionEnabled, default: true), forKey: ConfigKey.inlineCompletionEnabled)
        defaults.set(self.bool(forKey: ConfigKey.aiNextTokenEnabled, default: true), forKey: ConfigKey.aiNextTokenEnabled)
        let strategyRaw = self.string(forKey: ConfigKey.aiNextTokenStrategy, default: "smart")
        defaults.set(strategyRaw.isEmpty ? "smart" : strategyRaw, forKey: ConfigKey.aiNextTokenStrategy)
        defaults.set(self.string(forKey: ConfigKey.aiNextTokenModelOverride, default: ""), forKey: ConfigKey.aiNextTokenModelOverride)
        let debounceMs = Int(self.string(forKey: ConfigKey.aiNextTokenDebounceMs, default: "420")) ?? 420
        defaults.set(debounceMs, forKey: ConfigKey.aiNextTokenDebounceMs)
        let dailyCap = Int(self.string(forKey: ConfigKey.aiNextTokenDailyCap, default: "300")) ?? 300
        defaults.set(dailyCap, forKey: ConfigKey.aiNextTokenDailyCap)
        defaults.set(self.string(forKey: ConfigKey.aiNextTokenDailyStatsJSON, default: ""), forKey: ConfigKey.aiNextTokenDailyStatsJSON)
        
        if let rawCursorEnabled = (self.hasLoadedConfigMap ? self.configMap[ConfigKey.usesCustomCursorColor] : self.queryConfigValue(forKey: ConfigKey.usesCustomCursorColor)) {
            let enabled = ["1", "true", "yes", "on"].contains(rawCursorEnabled.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
            defaults.set(enabled, forKey: DefaultKeys.usesCustomCursorColor.rawValue)
        }
        if let hex = (self.hasLoadedConfigMap ? self.configMap[ConfigKey.customCursorColorHex] : self.queryConfigValue(forKey: ConfigKey.customCursorColorHex)), !hex.isEmpty {
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
    
    /// Executes `body` inside a single immediate SQLite transaction (safe under nested calls).
    func withTransaction<T>(_ body: () throws -> T) rethrows -> T {
        
        guard self.db != nil else {
            return try body()
        }
        let isOutermost = (self.transactionDepth == 0)
        self.transactionDepth += 1
        if isOutermost {
            self.executeSQL("BEGIN IMMEDIATE TRANSACTION;")
        }
        do {
            let result = try body()
            self.transactionDepth -= 1
            if isOutermost {
                self.executeSQL("COMMIT;")
            }
            return result
        } catch {
            self.transactionDepth -= 1
            if isOutermost {
                self.executeSQL("ROLLBACK;")
            }
            throw error
        }
    }
    
    
    private func openDatabase() {
        
        if sqlite3_open(self.databaseURL.path, &self.db) != SQLITE_OK {
            self.db = nil
            return
        }
        self.executeSQL("""
        PRAGMA journal_mode = WAL;
        PRAGMA synchronous = NORMAL;
        PRAGMA busy_timeout = 5000;
        PRAGMA temp_store = MEMORY;
        PRAGMA cache_size = -8000;
        PRAGMA mmap_size = 67108864;
        """)
    }
    
    
    private func closeDatabase() {
        
        if let db = self.db {
            if self.transactionDepth == 0 {
                sqlite3_exec(db, "PRAGMA wal_checkpoint(TRUNCATE);", nil, nil, nil)
            }
            sqlite3_close(db)
            self.db = nil
        }
        self.transactionDepth = 0
        self.configMap.removeAll()
        self.configTimestamps.removeAll()
        self.cachedConfigEntries = nil
        self.hasLoadedConfigMap = false
        self.configRevision &+= 1
    }
    
    
    func executeSQL(_ sql: String) {
        
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
            group_name TEXT NOT NULL DEFAULT '',
            updated_at REAL NOT NULL,
            deleted_at REAL,
            created_at REAL
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
        CREATE TABLE IF NOT EXISTS daily_writing_stats (
            date_key TEXT PRIMARY KEY,
            typed_chars INTEGER NOT NULL DEFAULT 0,
            ai_completed_chars INTEGER NOT NULL DEFAULT 0,
            ai_completion_accepts INTEGER NOT NULL DEFAULT 0,
            files_created INTEGER NOT NULL DEFAULT 0,
            documents_saved INTEGER NOT NULL DEFAULT 0,
            ai_requests INTEGER NOT NULL DEFAULT 0,
            input_tokens INTEGER NOT NULL DEFAULT 0,
            output_tokens INTEGER NOT NULL DEFAULT 0,
            local_hits INTEGER NOT NULL DEFAULT 0,
            local_accepted_chars INTEGER NOT NULL DEFAULT 0,
            max_single_accept_chars INTEGER NOT NULL DEFAULT 0,
            hourly_chars_json TEXT NOT NULL DEFAULT '',
            updated_at REAL NOT NULL
        );
        CREATE TABLE IF NOT EXISTS ai_usage_events (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            date_key TEXT NOT NULL,
            timestamp REAL NOT NULL,
            feature TEXT NOT NULL,
            model TEXT NOT NULL,
            provider TEXT NOT NULL,
            input_tokens INTEGER NOT NULL DEFAULT 0,
            output_tokens INTEGER NOT NULL DEFAULT 0,
            latency_ms INTEGER NOT NULL DEFAULT 0,
            success INTEGER NOT NULL DEFAULT 1
        );
        CREATE INDEX IF NOT EXISTS idx_ai_usage_date_key ON ai_usage_events(date_key);
        CREATE INDEX IF NOT EXISTS idx_ai_usage_date_ts ON ai_usage_events(date_key, timestamp DESC);
        CREATE INDEX IF NOT EXISTS idx_ai_usage_ts ON ai_usage_events(timestamp DESC);
        CREATE INDEX IF NOT EXISTS idx_weekly_reports_sort ON weekly_reports(year_month DESC, period_label DESC, updated_at DESC);
        CREATE TABLE IF NOT EXISTS daily_ai_digests (
            date_key TEXT PRIMARY KEY,
            summary TEXT NOT NULL,
            topics_json TEXT NOT NULL DEFAULT '[]',
            tomorrow_focus TEXT NOT NULL DEFAULT '',
            source_char_count INTEGER NOT NULL DEFAULT 0,
            source_fingerprint TEXT NOT NULL DEFAULT '',
            model_used TEXT NOT NULL DEFAULT '',
            generated_at REAL NOT NULL
        );
        CREATE TABLE IF NOT EXISTS user_reminders (
            id TEXT PRIMARY KEY,
            title TEXT NOT NULL,
            notes TEXT NOT NULL DEFAULT '',
            due_date REAL NOT NULL,
            due_day_key TEXT NOT NULL,
            priority INTEGER NOT NULL DEFAULT 1,
            is_completed INTEGER NOT NULL DEFAULT 0,
            created_at REAL NOT NULL,
            completed_at REAL,
            is_pinned INTEGER NOT NULL DEFAULT 0,
            has_deadline INTEGER NOT NULL DEFAULT 1
        );
        CREATE INDEX IF NOT EXISTS idx_reminders_due_day ON user_reminders(due_day_key);
        """
        self.executeSQL(sql)
        self.ensureDocumentsExtendedColumnsExist()
        self.executeSQL("""
        CREATE INDEX IF NOT EXISTS idx_documents_active_updated ON documents(deleted_at, updated_at DESC);
        CREATE INDEX IF NOT EXISTS idx_documents_trash_deleted ON documents(deleted_at DESC) WHERE deleted_at IS NOT NULL;
        CREATE INDEX IF NOT EXISTS idx_documents_file_path ON documents(file_path) WHERE file_path IS NOT NULL;
        CREATE INDEX IF NOT EXISTS idx_documents_group_name ON documents(group_name) WHERE group_name != '';
        """)
        self.ensureDailyStatsExtendedColumnsExist()
        self.ensureRemindersExtendedColumnsExist()
        self.executeSQL("CREATE INDEX IF NOT EXISTS idx_reminders_sort ON user_reminders(is_completed ASC, is_pinned DESC, due_date DESC);")
        self.createStructuredAssetTablesIfNeeded()
    }
    
    
    private func ensureDailyStatsExtendedColumnsExist() {
        
        var existing: Set<String> = []
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(self.db, "PRAGMA table_info(daily_writing_stats);", -1, &stmt, nil) == SQLITE_OK {
            while sqlite3_step(stmt) == SQLITE_ROW {
                if let nameCStr = sqlite3_column_text(stmt, 1) {
                    existing.insert(String(cString: nameCStr))
                }
            }
        }
        sqlite3_finalize(stmt)
        if !existing.contains("local_accepted_chars") {
            self.executeSQL("ALTER TABLE daily_writing_stats ADD COLUMN local_accepted_chars INTEGER NOT NULL DEFAULT 0;")
        }
        if !existing.contains("max_single_accept_chars") {
            self.executeSQL("ALTER TABLE daily_writing_stats ADD COLUMN max_single_accept_chars INTEGER NOT NULL DEFAULT 0;")
        }
        if !existing.contains("hourly_chars_json") {
            self.executeSQL("ALTER TABLE daily_writing_stats ADD COLUMN hourly_chars_json TEXT NOT NULL DEFAULT '';")
        }
    }
    
    
    private func ensureRemindersExtendedColumnsExist() {
        
        var existing: Set<String> = []
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(self.db, "PRAGMA table_info(user_reminders);", -1, &stmt, nil) == SQLITE_OK {
            while sqlite3_step(stmt) == SQLITE_ROW {
                if let nameCStr = sqlite3_column_text(stmt, 1) {
                    existing.insert(String(cString: nameCStr))
                }
            }
        }
        sqlite3_finalize(stmt)
        if !existing.contains("is_pinned") {
            self.executeSQL("ALTER TABLE user_reminders ADD COLUMN is_pinned INTEGER NOT NULL DEFAULT 0;")
        }
        if !existing.contains("has_deadline") {
            self.executeSQL("ALTER TABLE user_reminders ADD COLUMN has_deadline INTEGER NOT NULL DEFAULT 1;")
        }
    }
    
    
    private func ensureDocumentsExtendedColumnsExist() {
        
        var existing: Set<String> = []
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(self.db, "PRAGMA table_info(documents);", -1, &stmt, nil) == SQLITE_OK {
            while sqlite3_step(stmt) == SQLITE_ROW {
                if let nameCStr = sqlite3_column_text(stmt, 1) {
                    existing.insert(String(cString: nameCStr))
                }
            }
        }
        sqlite3_finalize(stmt)
        if !existing.contains("group_name") {
            self.executeSQL("ALTER TABLE documents ADD COLUMN group_name TEXT NOT NULL DEFAULT '';")
        }
        if !existing.contains("deleted_at") {
            self.executeSQL("ALTER TABLE documents ADD COLUMN deleted_at REAL;")
        }
        if !existing.contains("created_at") {
            self.executeSQL("ALTER TABLE documents ADD COLUMN created_at REAL;")
            self.executeSQL("UPDATE documents SET created_at = updated_at WHERE created_at IS NULL;")
        }
    }
    
    
    private func seedDefaultConfigsIfNeeded(defaultAuthorName: String? = nil) {
        
        let resolvedAuthor = defaultAuthorName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? defaultAuthorName!.trimmingCharacters(in: .whitespacesAndNewlines)
            : "陈明扬"
        
        let defaults: [(String, String)] = [
            (ConfigKey.aiPersona, "你是一位专业、干练、审美在线的技术与写作助手，回答直接、结构清晰、不讲废话。"),
            (ConfigKey.promptTranslate, AIAction.translate.defaultSystemPrompt),
            (ConfigKey.promptSummarize, AIAction.summarize.defaultSystemPrompt),
            (ConfigKey.promptExplain, AIAction.explain.defaultSystemPrompt),
            (ConfigKey.promptSemanticRestructure, AIAction.semanticRestructure.defaultSystemPrompt),
            (ConfigKey.promptWeeklyReport, AIAction.weeklyReport.defaultSystemPrompt),
            (ConfigKey.promptWeeklyReportPart, AIAction.weeklyReportItem.defaultSystemPrompt),
            (ConfigKey.promptChart, AIAction.interactiveChart.defaultSystemPrompt),
            (ConfigKey.promptOCR, AIAction.ocrPolish.defaultSystemPrompt),
            (ConfigKey.promptOrganizeMerge, AIAction.organizeAndMerge.defaultSystemPrompt),
            (ConfigKey.weeklyReportAuthor, resolvedAuthor),
            (ConfigKey.typewriterEffectEnabled, "true"),
            (ConfigKey.typewriterEffectStyle, "powerMode"),
            (ConfigKey.vimCursorEffectEnabled, "true"),
            (ConfigKey.plainTextInlineImagesEnabled, "true"),
            (ConfigKey.usesCustomCursorColor, "false"),
            (ConfigKey.customCursorColorHex, "#0A84FF"),
        ]
        
        let now = Date().timeIntervalSince1970
        let sql = "INSERT OR IGNORE INTO configs (key, value, updated_at) VALUES (?, ?, ?);"
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(self.db, sql, -1, &stmt, nil) == SQLITE_OK {
            for (key, value) in defaults {
                sqlite3_reset(stmt)
                sqlite3_clear_bindings(stmt)
                sqlite3_bind_text(stmt, 1, key, -1, self.transientDestructor)
                sqlite3_bind_text(stmt, 2, value, -1, self.transientDestructor)
                sqlite3_bind_double(stmt, 3, now)
                sqlite3_step(stmt)
            }
        }
        sqlite3_finalize(stmt)
    }
    
    
    /// Upgrades unmodified built-in prompts (for example the old weekly report prompts, or the
    /// Markdown-heavy summarizer prompt) to the current plain-text defaults.
    ///
    /// A prompt the user edited is left alone: only an exact match with a shipped default is
    /// replaced, so custom prompts survive the upgrade.
    private func migrateLegacyPromptsIfNeeded() {
        
        for action in AIAction.allCases {
            let existing = self.hasLoadedConfigMap
                ? self.configMap[action.databaseConfigKey]
                : self.queryConfigValue(forKey: action.databaseConfigKey)
            guard let existing else { continue }
            let trimmedExisting = existing.trimmingCharacters(in: .whitespacesAndNewlines)
            if action.legacyDefaultSystemPrompts.contains(where: {
                $0.trimmingCharacters(in: .whitespacesAndNewlines) == trimmedExisting
            }) {
                self.set(action.defaultSystemPrompt, forKey: action.databaseConfigKey)
            }
        }
    }
    
    
    /// Enables the upgraded visual-only typing effects once for existing profiles.
    private func migrateTypewriterV2IfNeeded() {
        
        let migrated = self.hasLoadedConfigMap
            ? self.configMap[ConfigKey.typewriterEffectV2Migrated]
            : self.queryConfigValue(forKey: ConfigKey.typewriterEffectV2Migrated)
        guard migrated == nil else { return }
        self.set("true", forKey: ConfigKey.typewriterEffectEnabled)
        self.set("true", forKey: ConfigKey.typewriterEffectV2Migrated)
    }
    
    
    private func seedDefaultWeeklyReportsIfNeeded() {
        
        guard !Self.isRunningUnitTests else { return }
        guard self.databaseURL.lastPathComponent == "cot_user_data.sqlite3" else { return }
        var hasReports = false
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(self.db, "SELECT 1 FROM weekly_reports LIMIT 1;", -1, &stmt, nil) == SQLITE_OK {
            hasReports = (sqlite3_step(stmt) == SQLITE_ROW)
        }
        sqlite3_finalize(stmt)
        guard !hasReports else { return }
        let zipURL = URL(filePath: Self.defaultWeeklyReportsZipPath)
        guard FileManager.default.fileExists(atPath: zipURL.path) else { return }
        _ = try? self.importWeeklyReports(fromZipURL: zipURL)
    }
    
    
    private func pruneHistoricalTablesOnLaunchIfNeeded() {
        
        guard !Self.isRunningUnitTests else { return }
        let now = Date().timeIntervalSince1970
        let queueCutoff = now - 7 * 86400
        let usageCutoff = now - 420 * 86400
        
        self.withTransaction {
            var qStmt: OpaquePointer?
            if sqlite3_prepare_v2(self.db, "DELETE FROM agent_command_queue WHERE status != 'pending' AND COALESCE(executed_at, created_at) < ?;", -1, &qStmt, nil) == SQLITE_OK {
                sqlite3_bind_double(qStmt, 1, queueCutoff)
                sqlite3_step(qStmt)
            }
            sqlite3_finalize(qStmt)
            
            var uStmt: OpaquePointer?
            if sqlite3_prepare_v2(self.db, "DELETE FROM ai_usage_events WHERE timestamp < ?;", -1, &uStmt, nil) == SQLITE_OK {
                sqlite3_bind_double(uStmt, 1, usageCutoff)
                sqlite3_step(uStmt)
            }
            sqlite3_finalize(uStmt)
            
            self.executeSQL("""
            DELETE FROM user_memory_journal
            WHERE id NOT IN (SELECT id FROM user_memory_journal ORDER BY id DESC LIMIT 500);
            """)
        }
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
                    try? await Task.sleep(for: .milliseconds(2000))
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
        var map: [String: String] = [:]
        var timestamps: [String: TimeInterval] = [:]
        
        if sqlite3_prepare_v2(self.db, sql, -1, &stmt, nil) == SQLITE_OK {
            while sqlite3_step(stmt) == SQLITE_ROW {
                guard
                    let keyCStr = sqlite3_column_text(stmt, 0),
                    let valCStr = sqlite3_column_text(stmt, 1)
                else { continue }
                let key = String(cString: keyCStr)
                map[key] = String(cString: valCStr)
                timestamps[key] = sqlite3_column_double(stmt, 2)
            }
        }
        sqlite3_finalize(stmt)
        self.configMap = map
        self.configTimestamps = timestamps
        self.cachedConfigEntries = nil
        self.hasLoadedConfigMap = true
        self.configRevision &+= 1
    }
    
    
    private static func decodeStoredDocumentRow(_ stmt: OpaquePointer?) -> StoredDocumentRecord? {
        
        guard
            let stmt,
            let idCStr = sqlite3_column_text(stmt, 0),
            let titleCStr = sqlite3_column_text(stmt, 1),
            let syntaxCStr = sqlite3_column_text(stmt, 3),
            let contentCStr = sqlite3_column_text(stmt, 4),
            let highlightsCStr = sqlite3_column_text(stmt, 5)
        else { return nil }
        
        let filePath: String? = if let pathCStr = sqlite3_column_text(stmt, 2) {
            String(cString: pathCStr)
        } else {
            nil
        }
        let ts = sqlite3_column_double(stmt, 6)
        let groupName: String = if let grpCStr = sqlite3_column_text(stmt, 7) {
            String(cString: grpCStr).trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            ""
        }
        let deletedTS = sqlite3_column_double(stmt, 8)
        let createdTS = sqlite3_column_double(stmt, 9)
        
        return StoredDocumentRecord(
            id: String(cString: idCStr),
            title: String(cString: titleCStr),
            filePath: filePath,
            syntax: String(cString: syntaxCStr),
            content: String(cString: contentCStr),
            highlightsJSON: String(cString: highlightsCStr),
            updatedAt: Date(timeIntervalSince1970: ts),
            groupName: groupName,
            deletedAt: deletedTS > 0 ? Date(timeIntervalSince1970: deletedTS) : nil,
            createdAt: createdTS > 0 ? Date(timeIntervalSince1970: createdTS) : nil
        )
    }
    
    
    func reloadDocuments() {
        
        let activeSQL = """
        SELECT id, title, file_path, syntax, content, highlights_json, updated_at, COALESCE(group_name, ''), COALESCE(deleted_at, 0), COALESCE(created_at, updated_at)
        FROM documents
        WHERE deleted_at IS NULL
        ORDER BY updated_at DESC
        LIMIT 200;
        """
        var activeItems: [StoredDocumentRecord] = []
        var activeStmt: OpaquePointer?
        if sqlite3_prepare_v2(self.db, activeSQL, -1, &activeStmt, nil) == SQLITE_OK {
            while sqlite3_step(activeStmt) == SQLITE_ROW {
                if let rec = Self.decodeStoredDocumentRow(activeStmt) {
                    activeItems.append(rec)
                }
            }
        }
        sqlite3_finalize(activeStmt)
        
        let trashSQL = """
        SELECT id, title, file_path, syntax, content, highlights_json, updated_at, COALESCE(group_name, ''), COALESCE(deleted_at, 0), COALESCE(created_at, updated_at)
        FROM documents
        WHERE deleted_at IS NOT NULL
        ORDER BY deleted_at DESC
        LIMIT 200;
        """
        var trashItems: [StoredDocumentRecord] = []
        var trashStmt: OpaquePointer?
        if sqlite3_prepare_v2(self.db, trashSQL, -1, &trashStmt, nil) == SQLITE_OK {
            while sqlite3_step(trashStmt) == SQLITE_ROW {
                if let rec = Self.decodeStoredDocumentRow(trashStmt) {
                    trashItems.append(rec)
                }
            }
        }
        sqlite3_finalize(trashStmt)
        
        self.documents = activeItems
        self.trashedDocuments = trashItems
        self.documentsRevision &+= 1
        
        var mergedGroups = self.loadStoredGroupList()
        for item in activeItems where !item.groupName.isEmpty && item.groupName != "未分组" {
            if !mergedGroups.contains(item.groupName) {
                mergedGroups.append(item.groupName)
            }
        }
        self.documentGroups = mergedGroups
    }
    
    
    func logSQLiteError(_ operation: String, code: Int32) {
        
        let errmsg = self.db.flatMap { sqlite3_errmsg($0) }.map { String(cString: $0) } ?? "unknown"
        CotLogger.shared.error(
            category: .database,
            "SQLite error in \(operation)",
            context: ["code": "\(code)", "message": errmsg]
        )
    }
    
    
    func reloadWeeklyReports(postNotification: Bool = true) {
        
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
        if postNotification {
            NotificationCenter.default.post(name: Self.weeklyReportsDidChangeNotification, object: self)
        }
    }
    
    
    // MARK: Analytics, Digests & Reminders Storage API
    
    /// Atomically increments one or more daily counters in `daily_writing_stats`.
    func incrementDailyWritingStats(
        dateKey: String,
        typedChars: Int = 0,
        aiCompletedChars: Int = 0,
        aiCompletionAccepts: Int = 0,
        filesCreated: Int = 0,
        documentsSaved: Int = 0,
        aiRequests: Int = 0,
        inputTokens: Int = 0,
        outputTokens: Int = 0,
        localHits: Int = 0,
        localAcceptedChars: Int = 0,
        singleAcceptChars: Int = 0,
        hourBucket: Int? = nil,
        precomputedHourlyBuckets: [Int]? = nil
    ) {
        let now = Date().timeIntervalSince1970
        let updatedHourlyJSON: String? = {
            if let precomputedHourlyBuckets, precomputedHourlyBuckets.count == 24 {
                guard let data = try? JSONEncoder().encode(precomputedHourlyBuckets),
                      let json = String(data: data, encoding: .utf8)
                else { return nil }
                return json
            }
            guard typedChars > 0, let hour = hourBucket, (0..<24).contains(hour) else { return nil }
            var buckets = self.queryHourlyBuckets(forDateKey: dateKey)
            buckets[hour] += typedChars
            guard let data = try? JSONEncoder().encode(buckets),
                  let json = String(data: data, encoding: .utf8)
            else { return nil }
            return json
        }()
        
        let sql = """
        INSERT INTO daily_writing_stats (
            date_key, typed_chars, ai_completed_chars, ai_completion_accepts,
            files_created, documents_saved, ai_requests, input_tokens, output_tokens, local_hits,
            local_accepted_chars, max_single_accept_chars, hourly_chars_json, updated_at
        )
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, COALESCE(?, ''), ?)
        ON CONFLICT(date_key) DO UPDATE SET
            typed_chars = daily_writing_stats.typed_chars + excluded.typed_chars,
            ai_completed_chars = daily_writing_stats.ai_completed_chars + excluded.ai_completed_chars,
            ai_completion_accepts = daily_writing_stats.ai_completion_accepts + excluded.ai_completion_accepts,
            files_created = daily_writing_stats.files_created + excluded.files_created,
            documents_saved = daily_writing_stats.documents_saved + excluded.documents_saved,
            ai_requests = daily_writing_stats.ai_requests + excluded.ai_requests,
            input_tokens = daily_writing_stats.input_tokens + excluded.input_tokens,
            output_tokens = daily_writing_stats.output_tokens + excluded.output_tokens,
            local_hits = daily_writing_stats.local_hits + excluded.local_hits,
            local_accepted_chars = daily_writing_stats.local_accepted_chars + excluded.local_accepted_chars,
            max_single_accept_chars = MAX(daily_writing_stats.max_single_accept_chars, excluded.max_single_accept_chars),
            hourly_chars_json = COALESCE(?, daily_writing_stats.hourly_chars_json),
            updated_at = excluded.updated_at;
        """
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(self.db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, dateKey, -1, self.transientDestructor)
            sqlite3_bind_int64(stmt, 2, Int64(typedChars))
            sqlite3_bind_int64(stmt, 3, Int64(aiCompletedChars))
            sqlite3_bind_int64(stmt, 4, Int64(aiCompletionAccepts))
            sqlite3_bind_int64(stmt, 5, Int64(filesCreated))
            sqlite3_bind_int64(stmt, 6, Int64(documentsSaved))
            sqlite3_bind_int64(stmt, 7, Int64(aiRequests))
            sqlite3_bind_int64(stmt, 8, Int64(inputTokens))
            sqlite3_bind_int64(stmt, 9, Int64(outputTokens))
            sqlite3_bind_int64(stmt, 10, Int64(localHits))
            sqlite3_bind_int64(stmt, 11, Int64(localAcceptedChars))
            sqlite3_bind_int64(stmt, 12, Int64(singleAcceptChars))
            if let updatedHourlyJSON {
                sqlite3_bind_text(stmt, 13, updatedHourlyJSON, -1, self.transientDestructor)
            } else {
                sqlite3_bind_null(stmt, 13)
            }
            sqlite3_bind_double(stmt, 14, now)
            if let updatedHourlyJSON {
                sqlite3_bind_text(stmt, 15, updatedHourlyJSON, -1, self.transientDestructor)
            } else {
                sqlite3_bind_null(stmt, 15)
            }
            let rc = sqlite3_step(stmt)
            if rc != SQLITE_DONE {
                self.logSQLiteError(#function, code: rc)
            }
        }
        sqlite3_finalize(stmt)
    }
    
    
    private func queryHourlyBuckets(forDateKey dateKey: String) -> [Int] {
        
        var buckets = Array(repeating: 0, count: 24)
        let sql = "SELECT COALESCE(hourly_chars_json, '') FROM daily_writing_stats WHERE date_key = ? LIMIT 1;"
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(self.db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, dateKey, -1, self.transientDestructor)
            if sqlite3_step(stmt) == SQLITE_ROW, let cStr = sqlite3_column_text(stmt, 0) {
                let raw = String(cString: cStr)
                if !raw.isEmpty,
                   let data = raw.data(using: .utf8),
                   let decoded = try? JSONDecoder().decode([Int].self, from: data),
                   decoded.count == 24
                {
                    buckets = decoded
                }
            }
        }
        sqlite3_finalize(stmt)
        return buckets
    }
    
    
    /// Inserts a backfilled `DailyWritingStats` row only if that `date_key` has no existing telemetry or all counters are zero.
    func backfillDailyWritingStatsIfEmpty(_ stats: DailyWritingStats) {
        
        let hourlyJSON = (try? String(data: JSONEncoder().encode(stats.hourlyTypedChars), encoding: .utf8)) ?? ""
        let sql = """
        INSERT INTO daily_writing_stats (
            date_key, typed_chars, ai_completed_chars, ai_completion_accepts,
            files_created, documents_saved, ai_requests, input_tokens, output_tokens, local_hits,
            local_accepted_chars, max_single_accept_chars, hourly_chars_json, updated_at
        )
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(date_key) DO UPDATE SET
            typed_chars = CASE WHEN daily_writing_stats.typed_chars = 0 AND daily_writing_stats.ai_completed_chars = 0 AND daily_writing_stats.ai_requests = 0 THEN excluded.typed_chars ELSE daily_writing_stats.typed_chars END,
            ai_completed_chars = CASE WHEN daily_writing_stats.typed_chars = 0 AND daily_writing_stats.ai_completed_chars = 0 AND daily_writing_stats.ai_requests = 0 THEN excluded.ai_completed_chars ELSE daily_writing_stats.ai_completed_chars END,
            ai_completion_accepts = CASE WHEN daily_writing_stats.typed_chars = 0 AND daily_writing_stats.ai_completed_chars = 0 AND daily_writing_stats.ai_requests = 0 THEN excluded.ai_completion_accepts ELSE daily_writing_stats.ai_completion_accepts END,
            files_created = CASE WHEN daily_writing_stats.typed_chars = 0 AND daily_writing_stats.ai_completed_chars = 0 AND daily_writing_stats.ai_requests = 0 THEN excluded.files_created ELSE daily_writing_stats.files_created END,
            documents_saved = CASE WHEN daily_writing_stats.typed_chars = 0 AND daily_writing_stats.ai_completed_chars = 0 AND daily_writing_stats.ai_requests = 0 THEN excluded.documents_saved ELSE daily_writing_stats.documents_saved END,
            ai_requests = CASE WHEN daily_writing_stats.typed_chars = 0 AND daily_writing_stats.ai_completed_chars = 0 AND daily_writing_stats.ai_requests = 0 THEN excluded.ai_requests ELSE daily_writing_stats.ai_requests END,
            input_tokens = CASE WHEN daily_writing_stats.typed_chars = 0 AND daily_writing_stats.ai_completed_chars = 0 AND daily_writing_stats.ai_requests = 0 THEN excluded.input_tokens ELSE daily_writing_stats.input_tokens END,
            output_tokens = CASE WHEN daily_writing_stats.typed_chars = 0 AND daily_writing_stats.ai_completed_chars = 0 AND daily_writing_stats.ai_requests = 0 THEN excluded.output_tokens ELSE daily_writing_stats.output_tokens END,
            local_hits = CASE WHEN daily_writing_stats.typed_chars = 0 AND daily_writing_stats.ai_completed_chars = 0 AND daily_writing_stats.ai_requests = 0 THEN excluded.local_hits ELSE daily_writing_stats.local_hits END,
            local_accepted_chars = CASE WHEN daily_writing_stats.typed_chars = 0 AND daily_writing_stats.ai_completed_chars = 0 AND daily_writing_stats.ai_requests = 0 THEN excluded.local_accepted_chars ELSE daily_writing_stats.local_accepted_chars END,
            max_single_accept_chars = CASE WHEN daily_writing_stats.typed_chars = 0 AND daily_writing_stats.ai_completed_chars = 0 AND daily_writing_stats.ai_requests = 0 THEN excluded.max_single_accept_chars ELSE daily_writing_stats.max_single_accept_chars END,
            updated_at = excluded.updated_at;
        """
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(self.db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, stats.dateKey, -1, self.transientDestructor)
            sqlite3_bind_int64(stmt, 2, Int64(stats.typedChars))
            sqlite3_bind_int64(stmt, 3, Int64(stats.aiCompletedChars))
            sqlite3_bind_int64(stmt, 4, Int64(stats.aiCompletionAccepts))
            sqlite3_bind_int64(stmt, 5, Int64(stats.filesCreated))
            sqlite3_bind_int64(stmt, 6, Int64(stats.documentsSaved))
            sqlite3_bind_int64(stmt, 7, Int64(stats.aiRequests))
            sqlite3_bind_int64(stmt, 8, Int64(stats.inputTokens))
            sqlite3_bind_int64(stmt, 9, Int64(stats.outputTokens))
            sqlite3_bind_int64(stmt, 10, Int64(stats.localHits))
            sqlite3_bind_int64(stmt, 11, Int64(stats.localAcceptedChars))
            sqlite3_bind_int64(stmt, 12, Int64(stats.maxSingleAcceptChars))
            sqlite3_bind_text(stmt, 13, hourlyJSON, -1, self.transientDestructor)
            sqlite3_bind_double(stmt, 14, stats.updatedAt.timeIntervalSince1970)
            let rc = sqlite3_step(stmt)
            if rc != SQLITE_DONE {
                self.logSQLiteError(#function, code: rc)
            }
        }
        sqlite3_finalize(stmt)
    }
    
    
    /// Fetches daily stats rows from `sinceDateKey` inclusive, ordered newest first.
    func fetchDailyWritingStats(sinceDateKey: String) -> [DailyWritingStats] {
        
        let sql = """
        SELECT date_key, typed_chars, ai_completed_chars, ai_completion_accepts,
               files_created, documents_saved, ai_requests, input_tokens, output_tokens, local_hits,
               COALESCE(local_accepted_chars, 0), COALESCE(max_single_accept_chars, 0),
               COALESCE(hourly_chars_json, ''), updated_at
        FROM daily_writing_stats
        WHERE date_key >= ?
        ORDER BY date_key DESC;
        """
        var stmt: OpaquePointer?
        var items: [DailyWritingStats] = []
        if sqlite3_prepare_v2(self.db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, sinceDateKey, -1, self.transientDestructor)
            while sqlite3_step(stmt) == SQLITE_ROW {
                guard let keyCStr = sqlite3_column_text(stmt, 0) else { continue }
                var hourly = Array(repeating: 0, count: 24)
                if let hourlyCStr = sqlite3_column_text(stmt, 12) {
                    let raw = String(cString: hourlyCStr)
                    if !raw.isEmpty,
                       let data = raw.data(using: .utf8),
                       let decoded = try? JSONDecoder().decode([Int].self, from: data),
                       decoded.count == 24
                    {
                        hourly = decoded
                    }
                }
                items.append(DailyWritingStats(
                    dateKey: String(cString: keyCStr),
                    typedChars: Int(sqlite3_column_int64(stmt, 1)),
                    aiCompletedChars: Int(sqlite3_column_int64(stmt, 2)),
                    aiCompletionAccepts: Int(sqlite3_column_int64(stmt, 3)),
                    filesCreated: Int(sqlite3_column_int64(stmt, 4)),
                    documentsSaved: Int(sqlite3_column_int64(stmt, 5)),
                    aiRequests: Int(sqlite3_column_int64(stmt, 6)),
                    inputTokens: Int(sqlite3_column_int64(stmt, 7)),
                    outputTokens: Int(sqlite3_column_int64(stmt, 8)),
                    localHits: Int(sqlite3_column_int64(stmt, 9)),
                    localAcceptedChars: Int(sqlite3_column_int64(stmt, 10)),
                    maxSingleAcceptChars: Int(sqlite3_column_int64(stmt, 11)),
                    hourlyTypedChars: hourly,
                    updatedAt: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 13))
                ))
            }
        }
        sqlite3_finalize(stmt)
        return items
    }
    
    
    /// Inserts one AI invocation event into `ai_usage_events`.
    func insertAIUsageEvent(_ event: AIUsageEvent) {
        
        let sql = """
        INSERT INTO ai_usage_events (
            date_key, timestamp, feature, model, provider,
            input_tokens, output_tokens, latency_ms, success
        )
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);
        """
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(self.db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, event.dateKey, -1, self.transientDestructor)
            sqlite3_bind_double(stmt, 2, event.timestamp.timeIntervalSince1970)
            sqlite3_bind_text(stmt, 3, event.feature, -1, self.transientDestructor)
            sqlite3_bind_text(stmt, 4, event.model, -1, self.transientDestructor)
            sqlite3_bind_text(stmt, 5, event.provider, -1, self.transientDestructor)
            sqlite3_bind_int64(stmt, 6, Int64(event.inputTokens))
            sqlite3_bind_int64(stmt, 7, Int64(event.outputTokens))
            sqlite3_bind_int64(stmt, 8, Int64(event.latencyMs))
            sqlite3_bind_int(stmt, 9, event.success ? 1 : 0)
            let rc = sqlite3_step(stmt)
            if rc != SQLITE_DONE {
                self.logSQLiteError(#function, code: rc)
            }
        }
        sqlite3_finalize(stmt)
    }
    
    
    /// Fetches recorded AI usage events from `sinceDateKey` inclusive, newest first (optionally bounded).
    func fetchAIUsageEvents(sinceDateKey: String, limit: Int? = nil) -> [AIUsageEvent] {
        
        let limitClause = limit.map { " LIMIT \($0)" } ?? ""
        let sql = """
        SELECT id, date_key, timestamp, feature, model, provider, input_tokens, output_tokens, latency_ms, success
        FROM ai_usage_events
        WHERE date_key >= ?
        ORDER BY timestamp DESC\(limitClause);
        """
        var stmt: OpaquePointer?
        var items: [AIUsageEvent] = []
        if sqlite3_prepare_v2(self.db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, sinceDateKey, -1, self.transientDestructor)
            while sqlite3_step(stmt) == SQLITE_ROW {
                if let event = Self.decodeAIUsageEventRow(stmt) {
                    items.append(event)
                }
            }
        }
        sqlite3_finalize(stmt)
        return items
    }
    
    
    /// Fetches all AI usage events recorded on a single day `yyyy-MM-dd` (newest first).
    func fetchAIUsageEvents(forDateKey dateKey: String) -> [AIUsageEvent] {
        
        let sql = """
        SELECT id, date_key, timestamp, feature, model, provider, input_tokens, output_tokens, latency_ms, success
        FROM ai_usage_events
        WHERE date_key = ?
        ORDER BY timestamp DESC;
        """
        var stmt: OpaquePointer?
        var items: [AIUsageEvent] = []
        if sqlite3_prepare_v2(self.db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, dateKey, -1, self.transientDestructor)
            while sqlite3_step(stmt) == SQLITE_ROW {
                if let event = Self.decodeAIUsageEventRow(stmt) {
                    items.append(event)
                }
            }
        }
        sqlite3_finalize(stmt)
        return items
    }
    
    
    private static func decodeAIUsageEventRow(_ stmt: OpaquePointer?) -> AIUsageEvent? {
        
        guard
            let stmt,
            let keyCStr = sqlite3_column_text(stmt, 1),
            let featureCStr = sqlite3_column_text(stmt, 3),
            let modelCStr = sqlite3_column_text(stmt, 4),
            let providerCStr = sqlite3_column_text(stmt, 5)
        else { return nil }
        return AIUsageEvent(
            id: sqlite3_column_int64(stmt, 0),
            dateKey: String(cString: keyCStr),
            timestamp: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 2)),
            feature: String(cString: featureCStr),
            model: String(cString: modelCStr),
            provider: String(cString: providerCStr),
            inputTokens: Int(sqlite3_column_int64(stmt, 6)),
            outputTokens: Int(sqlite3_column_int64(stmt, 7)),
            latencyMs: Int(sqlite3_column_int64(stmt, 8)),
            success: sqlite3_column_int(stmt, 9) != 0
        )
    }
    
    
    /// Saves or updates one daily AI digest in `daily_ai_digests`.
    func saveDailyAIDigest(_ digest: DailyAIDigest) {
        
        let topicsJSON = (try? String(data: JSONEncoder().encode(digest.topics), encoding: .utf8)) ?? "[]"
        let sql = """
        INSERT INTO daily_ai_digests (
            date_key, summary, topics_json, tomorrow_focus,
            source_char_count, source_fingerprint, model_used, generated_at
        )
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(date_key) DO UPDATE SET
            summary = excluded.summary,
            topics_json = excluded.topics_json,
            tomorrow_focus = excluded.tomorrow_focus,
            source_char_count = excluded.source_char_count,
            source_fingerprint = excluded.source_fingerprint,
            model_used = excluded.model_used,
            generated_at = excluded.generated_at;
        """
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(self.db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, digest.dateKey, -1, self.transientDestructor)
            sqlite3_bind_text(stmt, 2, digest.summary, -1, self.transientDestructor)
            sqlite3_bind_text(stmt, 3, topicsJSON, -1, self.transientDestructor)
            sqlite3_bind_text(stmt, 4, digest.tomorrowFocus, -1, self.transientDestructor)
            sqlite3_bind_int64(stmt, 5, Int64(digest.sourceCharCount))
            sqlite3_bind_text(stmt, 6, digest.sourceFingerprint, -1, self.transientDestructor)
            sqlite3_bind_text(stmt, 7, digest.modelUsed, -1, self.transientDestructor)
            sqlite3_bind_double(stmt, 8, digest.generatedAt.timeIntervalSince1970)
            let rc = sqlite3_step(stmt)
            if rc != SQLITE_DONE {
                self.logSQLiteError(#function, code: rc)
            }
        }
        sqlite3_finalize(stmt)
    }
    
    
    /// Fetches a daily AI digest for a specific date key (`yyyy-MM-dd`).
    func fetchDailyAIDigest(forDateKey dateKey: String) -> DailyAIDigest? {
        
        let sql = """
        SELECT date_key, summary, topics_json, tomorrow_focus,
               source_char_count, source_fingerprint, model_used, generated_at
        FROM daily_ai_digests
        WHERE date_key = ?
        LIMIT 1;
        """
        var stmt: OpaquePointer?
        var result: DailyAIDigest?
        if sqlite3_prepare_v2(self.db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, dateKey, -1, self.transientDestructor)
            if sqlite3_step(stmt) == SQLITE_ROW {
                result = Self.decodeDailyDigestRow(stmt)
            }
        }
        sqlite3_finalize(stmt)
        return result
    }
    
    
    /// Fetches the most recent daily AI digests.
    func fetchRecentDailyAIDigests(limit: Int = 7) -> [DailyAIDigest] {
        
        let sql = """
        SELECT date_key, summary, topics_json, tomorrow_focus,
               source_char_count, source_fingerprint, model_used, generated_at
        FROM daily_ai_digests
        ORDER BY date_key DESC
        LIMIT ?;
        """
        var stmt: OpaquePointer?
        var items: [DailyAIDigest] = []
        if sqlite3_prepare_v2(self.db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_int64(stmt, 1, Int64(max(1, limit)))
            while sqlite3_step(stmt) == SQLITE_ROW {
                if let item = Self.decodeDailyDigestRow(stmt) {
                    items.append(item)
                }
            }
        }
        sqlite3_finalize(stmt)
        return items
    }
    
    
    private static func decodeDailyDigestRow(_ stmt: OpaquePointer?) -> DailyAIDigest? {
        
        guard
            let stmt,
            let keyCStr = sqlite3_column_text(stmt, 0),
            let summaryCStr = sqlite3_column_text(stmt, 1),
            let topicsCStr = sqlite3_column_text(stmt, 2),
            let focusCStr = sqlite3_column_text(stmt, 3),
            let fpCStr = sqlite3_column_text(stmt, 5),
            let modelCStr = sqlite3_column_text(stmt, 6)
        else { return nil }
        
        let topicsRaw = String(cString: topicsCStr)
        let topics = topicsRaw.data(using: .utf8).flatMap { try? JSONDecoder().decode([String].self, from: $0) } ?? []
        return DailyAIDigest(
            dateKey: String(cString: keyCStr),
            summary: String(cString: summaryCStr),
            topics: topics,
            tomorrowFocus: String(cString: focusCStr),
            sourceCharCount: Int(sqlite3_column_int64(stmt, 4)),
            sourceFingerprint: String(cString: fpCStr),
            modelUsed: String(cString: modelCStr),
            generatedAt: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 7))
        )
    }
    
    
    /// Inserts or updates a reminder item in `user_reminders`.
    func saveReminder(_ reminder: UserReminder) {
        
        let sql = """
        INSERT INTO user_reminders (
            id, title, notes, due_date, due_day_key, priority, is_completed, created_at, completed_at, is_pinned, has_deadline
        )
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET
            title = excluded.title,
            notes = excluded.notes,
            due_date = excluded.due_date,
            due_day_key = excluded.due_day_key,
            priority = excluded.priority,
            is_completed = excluded.is_completed,
            completed_at = excluded.completed_at,
            is_pinned = excluded.is_pinned,
            has_deadline = excluded.has_deadline;
        """
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(self.db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, reminder.id, -1, self.transientDestructor)
            sqlite3_bind_text(stmt, 2, reminder.title, -1, self.transientDestructor)
            sqlite3_bind_text(stmt, 3, reminder.notes, -1, self.transientDestructor)
            sqlite3_bind_double(stmt, 4, reminder.dueDate.timeIntervalSince1970)
            sqlite3_bind_text(stmt, 5, reminder.dueDayKey, -1, self.transientDestructor)
            sqlite3_bind_int(stmt, 6, Int32(reminder.priority.rawValue))
            sqlite3_bind_int(stmt, 7, reminder.isCompleted ? 1 : 0)
            sqlite3_bind_double(stmt, 8, reminder.createdAt.timeIntervalSince1970)
            if let completedAt = reminder.completedAt {
                sqlite3_bind_double(stmt, 9, completedAt.timeIntervalSince1970)
            } else {
                sqlite3_bind_null(stmt, 9)
            }
            sqlite3_bind_int(stmt, 10, reminder.isPinned ? 1 : 0)
            sqlite3_bind_int(stmt, 11, reminder.hasDeadline ? 1 : 0)
            let rc = sqlite3_step(stmt)
            if rc != SQLITE_DONE {
                self.logSQLiteError(#function, code: rc)
            }
        }
        sqlite3_finalize(stmt)
    }
    
    
    /// Toggles completion state for a reminder by ID.
    func toggleReminderCompleted(id: String, isCompleted: Bool) {
        
        let sql = "UPDATE user_reminders SET is_completed = ?, completed_at = ? WHERE id = ?;"
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(self.db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_int(stmt, 1, isCompleted ? 1 : 0)
            if isCompleted {
                sqlite3_bind_double(stmt, 2, Date().timeIntervalSince1970)
            } else {
                sqlite3_bind_null(stmt, 2)
            }
            sqlite3_bind_text(stmt, 3, id, -1, self.transientDestructor)
            sqlite3_step(stmt)
        }
        sqlite3_finalize(stmt)
    }
    
    
    /// Updates pin status for a reminder by ID.
    func setReminderPinned(id: String, isPinned: Bool) {
        
        let sql = "UPDATE user_reminders SET is_pinned = ? WHERE id = ?;"
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(self.db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_int(stmt, 1, isPinned ? 1 : 0)
            sqlite3_bind_text(stmt, 2, id, -1, self.transientDestructor)
            sqlite3_step(stmt)
        }
        sqlite3_finalize(stmt)
    }
    
    
    /// Updates deadline for a reminder by ID.
    func updateReminderDeadline(id: String, dueDate: Date, dueDayKey: String, hasDeadline: Bool) {
        
        let sql = "UPDATE user_reminders SET due_date = ?, due_day_key = ?, has_deadline = ? WHERE id = ?;"
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(self.db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_double(stmt, 1, dueDate.timeIntervalSince1970)
            sqlite3_bind_text(stmt, 2, dueDayKey, -1, self.transientDestructor)
            sqlite3_bind_int(stmt, 3, hasDeadline ? 1 : 0)
            sqlite3_bind_text(stmt, 4, id, -1, self.transientDestructor)
            sqlite3_step(stmt)
        }
        sqlite3_finalize(stmt)
    }
    
    
    /// Deletes a reminder by ID.
    func deleteReminder(id: String) {
        
        let sql = "DELETE FROM user_reminders WHERE id = ?;"
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(self.db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, id, -1, self.transientDestructor)
            sqlite3_step(stmt)
        }
        sqlite3_finalize(stmt)
    }
    
    
    /// Fetches all reminders ordered by completion, pinned status, due date, priority, and creation time.
    func fetchAllReminders() -> [UserReminder] {
        
        let sql = """
        SELECT id, title, notes, due_date, due_day_key, priority, is_completed, created_at, COALESCE(completed_at, 0),
               COALESCE(is_pinned, 0), COALESCE(has_deadline, 1)
        FROM user_reminders
        ORDER BY is_completed ASC, is_pinned DESC, COALESCE(has_deadline, 1) DESC, due_date DESC, priority DESC, created_at DESC;
        """
        var stmt: OpaquePointer?
        var items: [UserReminder] = []
        if sqlite3_prepare_v2(self.db, sql, -1, &stmt, nil) == SQLITE_OK {
            while sqlite3_step(stmt) == SQLITE_ROW {
                guard
                    let idCStr = sqlite3_column_text(stmt, 0),
                    let titleCStr = sqlite3_column_text(stmt, 1),
                    let notesCStr = sqlite3_column_text(stmt, 2),
                    let dayCStr = sqlite3_column_text(stmt, 4)
                else { continue }
                
                let priorityRaw = Int(sqlite3_column_int(stmt, 5))
                let completedTS = sqlite3_column_double(stmt, 8)
                items.append(UserReminder(
                    id: String(cString: idCStr),
                    title: String(cString: titleCStr),
                    notes: String(cString: notesCStr),
                    dueDate: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 3)),
                    dueDayKey: String(cString: dayCStr),
                    priority: ReminderPriority(rawValue: priorityRaw) ?? .normal,
                    isCompleted: sqlite3_column_int(stmt, 6) != 0,
                    createdAt: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 7)),
                    completedAt: completedTS > 0 ? Date(timeIntervalSince1970: completedTS) : nil,
                    isPinned: sqlite3_column_int(stmt, 9) != 0,
                    hasDeadline: sqlite3_column_int(stmt, 10) != 0
                ))
            }
        }
        sqlite3_finalize(stmt)
        return items
    }
}
