//
//  UserProfileManager.swift
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
import SQLite3

/// A local user profile whose documents, preferences, stats, reminders, and AI history
/// live in an isolated SQLite database file, with optional fields reserved for future login.
nonisolated struct UserProfile: Identifiable, Codable, Sendable, Equatable {
    
    var id: String
    var displayName: String
    var avatarData: Data?
    var avatarColorHex: String
    var dbFilename: String
    var accountKind: String
    var email: String?
    var remoteUserID: String?
    var createdAt: Date
    var lastActiveAt: Date
}


/// Manages local user accounts (`cot_accounts.sqlite3`) and coordinates per-user
/// database isolation, avatar storage, and live workspace switching.
@MainActor @Observable final class UserProfileManager {
    
    static let shared = UserProfileManager()
    
    static let activeProfileDidChangeNotification = Notification.Name("CotUserProfileManagerActiveProfileDidChange")
    
    static let avatarPresetColors: [String] = [
        "#0A84FF", "#34C759", "#FF9F0A", "#FF375F", "#AF52DE", "#30B0C7", "#5E5CE6",
    ]
    
    // MARK: Public State
    
    private(set) var profiles: [UserProfile] = []
    private(set) var activeProfile: UserProfile
    
    let rootDirectory: URL
    let accountsDatabaseURL: URL
    
    // MARK: Private Properties
    
    private var db: OpaquePointer?
    private let transientDestructor = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    private var avatarCache: [String: (data: Data, image: NSImage)] = [:]
    
    
    private static var isRunningUnitTests: Bool {
        
        let env = ProcessInfo.processInfo.environment
        return NSClassFromString("XCTestCase") != nil
            || env["XCTestConfigurationFilePath"] != nil
            || env["XCTestBundlePath"] != nil
    }
    
    
    // MARK: Lifecycle
    
    init(rootDirectory: URL? = nil) {
        
        let resolvedRoot: URL
        if let rootDirectory {
            resolvedRoot = rootDirectory
        } else if Self.isRunningUnitTests {
            resolvedRoot = FileManager.default.temporaryDirectory
                .appending(path: "cot_xctest_profiles_\(ProcessInfo.processInfo.processIdentifier)", directoryHint: .isDirectory)
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            resolvedRoot = appSupport.appending(path: "Cot", directoryHint: .isDirectory)
        }
        
        self.rootDirectory = resolvedRoot
        self.accountsDatabaseURL = resolvedRoot.appending(path: "cot_accounts.sqlite3")
        
        let usersFolder = resolvedRoot.appending(path: "users", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: resolvedRoot, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: usersFolder, withIntermediateDirectories: true)
        
        let placeholder = UserProfile(
            id: "default",
            displayName: "默认用户",
            avatarData: nil,
            avatarColorHex: "#0A84FF",
            dbFilename: "cot_user_data.sqlite3",
            accountKind: "local",
            email: nil,
            remoteUserID: nil,
            createdAt: Date(),
            lastActiveAt: Date()
        )
        self.activeProfile = placeholder
        
        self.openDatabase()
        self.createTablesIfNeeded()
        self.seedDefaultProfileIfNeeded()
        self.reloadProfiles()
    }
    
    
    isolated deinit {
        
        if let db = self.db {
            sqlite3_close(db)
        }
    }
    
    
    // MARK: Public Computed & Path Helpers
    
    var activeDatabaseURL: URL {
        
        self.databaseURL(for: self.activeProfile)
    }
    
    
    func databaseURL(for profile: UserProfile) -> URL {
        
        self.rootDirectory.appending(path: profile.dbFilename)
    }
    
    
    func avatarImage(for profile: UserProfile) -> NSImage? {
        
        guard let data = profile.avatarData, !data.isEmpty else { return nil }
        if let cached = self.avatarCache[profile.id], cached.data == data {
            return cached.image
        }
        guard let image = NSImage(data: data) else { return nil }
        self.avatarCache[profile.id] = (data, image)
        return image
    }
    
    
    static func initials(for name: String) -> String {
        
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "U" }
        
        if let firstScalar = trimmed.unicodeScalars.first, !firstScalar.isASCII {
            return String(trimmed.prefix(1))
        }
        
        let parts = trimmed.split(whereSeparator: \.isWhitespace)
        if parts.count >= 2 {
            let first = parts[0].prefix(1).uppercased()
            let second = parts[1].prefix(1).uppercased()
            return "\(first)\(second)"
        }
        
        return String(trimmed.prefix(2)).uppercased()
    }
    
    
    /// Center-crops `image` to a square and encodes a crisp PNG representation capped at `maxSide` px.
    static func processedAvatarPNGData(from image: NSImage, maxSide: CGFloat = 256) -> Data? {
        
        let sourceSize = image.size
        guard sourceSize.width > 0, sourceSize.height > 0 else { return nil }
        
        let targetSide = max(32, min(maxSide, max(sourceSize.width, sourceSize.height)))
        let sideInt = Int(round(targetSide))
        
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: sideInt,
            pixelsHigh: sideInt,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return nil }
        
        rep.size = NSSize(width: sideInt, height: sideInt)
        
        NSGraphicsContext.saveGraphicsState()
        if let context = NSGraphicsContext(bitmapImageRep: rep) {
            NSGraphicsContext.current = context
            context.imageInterpolation = .high
            
            let cropSide = min(sourceSize.width, sourceSize.height)
            let sourceRect = NSRect(
                x: (sourceSize.width - cropSide) * 0.5,
                y: (sourceSize.height - cropSide) * 0.5,
                width: cropSide,
                height: cropSide
            )
            let destRect = NSRect(x: 0, y: 0, width: sideInt, height: sideInt)
            image.draw(in: destRect, from: sourceRect, operation: .copy, fraction: 1.0)
            context.flushGraphics()
        }
        NSGraphicsContext.restoreGraphicsState()
        
        return rep.representation(using: .png, properties: [:])
    }
    
    
    // MARK: Profile CRUD & Switching
    
    /// Updates display name, avatar image data, or accent color on an existing profile.
    func updateProfile(
        id: String,
        displayName: String? = nil,
        avatarData: Data?? = nil,
        avatarColorHex: String? = nil
    ) {
        guard var target = self.profiles.first(where: { $0.id == id }) else { return }
        
        var nameChanged = false
        if let displayName {
            let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty, trimmed != target.displayName {
                target.displayName = trimmed
                nameChanged = true
            }
        }
        if let avatarData {
            target.avatarData = avatarData
            self.avatarCache.removeValue(forKey: id)
        }
        if let avatarColorHex, !avatarColorHex.isEmpty {
            target.avatarColorHex = avatarColorHex
        }
        
        self.upsertUserRow(target)
        self.reloadProfiles()
        
        if self === Self.shared, target.id == self.activeProfile.id {
            if nameChanged {
                CotLocalDatabase.shared.weeklyReportAuthor = target.displayName
            }
            CotLocalDatabase.shared.syncUserProfileToDatabase(target)
        }
        
        NotificationCenter.default.post(name: Self.activeProfileDidChangeNotification, object: self)
    }
    
    
    /// Applies a portable profile snapshot restored from an imported SQLite database to the active profile.
    func applyImportedProfileSnapshot(_ snapshot: PortableUserProfileSnapshot) {
        
        var target = self.activeProfile
        let trimmedName = snapshot.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedName.isEmpty {
            target.displayName = trimmedName
        }
        if let avatar = snapshot.decodedAvatarData, !avatar.isEmpty {
            target.avatarData = avatar
        } else if snapshot.avatarDataBase64 == nil {
            target.avatarData = nil
        }
        if !snapshot.avatarColorHex.isEmpty {
            target.avatarColorHex = snapshot.avatarColorHex
        }
        target.accountKind = snapshot.accountKind
        target.email = snapshot.email
        target.remoteUserID = snapshot.remoteUserID
        
        self.avatarCache.removeValue(forKey: target.id)
        self.upsertUserRow(target)
        self.reloadProfiles()
        
        if self === Self.shared {
            CotLocalDatabase.shared.weeklyReportAuthor = target.displayName
        }
        NotificationCenter.default.post(name: Self.activeProfileDidChangeNotification, object: self)
    }
    
    
    /// Creates a new isolated local user profile (with its own SQLite database file).
    @discardableResult
    func createProfile(
        displayName: String,
        avatarData: Data? = nil,
        avatarColorHex: String = "#0A84FF",
        copyCurrentAIEndpoints: Bool = true,
        switchImmediately: Bool = true
    ) -> UserProfile {
        
        let trimmedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedName = trimmedName.isEmpty ? "用户 \(self.profiles.count + 1)" : trimmedName
        let id = UUID().uuidString.lowercased()
        let dbFilename = "users/cot_user_\(id).sqlite3"
        let now = Date()
        
        let profile = UserProfile(
            id: id,
            displayName: resolvedName,
            avatarData: avatarData,
            avatarColorHex: avatarColorHex,
            dbFilename: dbFilename,
            accountKind: "local",
            email: nil,
            remoteUserID: nil,
            createdAt: now,
            lastActiveAt: now
        )
        
        // Pre-seed the isolated user's database before switching so it starts cleanly.
        let targetURL = self.databaseURL(for: profile)
        let targetDB = CotLocalDatabase(customURL: targetURL)
        targetDB.weeklyReportAuthor = resolvedName
        targetDB.syncUserProfileToDatabase(profile)
        if copyCurrentAIEndpoints, self === Self.shared {
            let currentProfiles = AIEndpointStore.profiles
            if let profilesData = try? JSONEncoder().encode(currentProfiles),
               let json = String(data: profilesData, encoding: .utf8)
            {
                targetDB.set(json, forKey: CotLocalDatabase.ConfigKey.syncAIProfiles)
            }
            targetDB.set(AIEndpointStore.activeID?.uuidString ?? "", forKey: CotLocalDatabase.ConfigKey.syncAIActiveProfileID)
            var keyMap: [String: String] = [:]
            for ep in currentProfiles {
                let key = AIKeychain.apiKey(for: ep.id).trimmingCharacters(in: .whitespacesAndNewlines)
                if !key.isEmpty {
                    keyMap[ep.id.uuidString] = key
                }
            }
            if let keysData = try? JSONEncoder().encode(keyMap),
               let keysJSON = String(data: keysData, encoding: .utf8)
            {
                targetDB.set(keysJSON, forKey: CotLocalDatabase.ConfigKey.syncAIProfileAPIKeys)
            }
        } else {
            targetDB.set("[]", forKey: CotLocalDatabase.ConfigKey.syncAIProfiles)
            targetDB.set("", forKey: CotLocalDatabase.ConfigKey.syncAIActiveProfileID)
            targetDB.set("{}", forKey: CotLocalDatabase.ConfigKey.syncAIProfileAPIKeys)
        }
        targetDB.checkpointDatabase()
        
        self.upsertUserRow(profile)
        self.reloadProfiles()
        
        if switchImmediately {
            self.switchToProfile(id: profile.id)
        } else {
            NotificationCenter.default.post(name: Self.activeProfileDidChangeNotification, object: self)
        }
        
        return self.profiles.first(where: { $0.id == profile.id }) ?? profile
    }
    
    
    /// Switches the active local user, flushing the outgoing user's data and loading the incoming user's DB.
    func switchToProfile(id: String) {
        
        guard
            let target = self.profiles.first(where: { $0.id == id }),
            target.id != self.activeProfile.id
        else { return }
        
        let isSharedAppManager = (self === Self.shared)
        
        if isSharedAppManager {
            AnalyticsManager.shared.flushPendingStats()
            
            for case let document as Document in NSDocumentController.shared.documents {
                document.syncToLocalDatabase(force: true)
            }
            for window in NSApp.orderedWindows {
                if let docVC = (window.windowController as? DocumentWindowController)?.documentViewController {
                    docVC.savePaneTabsSessionToDatabase()
                }
            }
            CotLocalDatabase.shared.syncAIEndpointsToDatabase()
            CotLocalDatabase.shared.syncUserProfileToDatabase()
            CotLocalDatabase.shared.syncUserPreferencesToDatabase()
            CotLocalDatabase.shared.checkpointDatabase()
        }
        
        var updatedTarget = target
        updatedTarget.lastActiveAt = Date()
        self.upsertUserRow(updatedTarget)
        self.setAccountState(updatedTarget.id, forKey: "active_user_id")
        self.reloadProfiles()
        
        if isSharedAppManager {
            let dbURL = self.databaseURL(for: updatedTarget)
            CotLocalDatabase.shared.switchDatabase(to: dbURL, defaultAuthorName: updatedTarget.displayName)
            CotLocalDatabase.shared.restoreAIEndpointsFromDatabase(resetIfMissing: true)
            CotLocalDatabase.shared.restoreUserPreferencesFromDatabase(overwriteExisting: true)
            
            AIBotStore.shared.reloadFromDatabase()
            UserHabitPredictor.shared.reloadFromDatabase()
            AINextTokenPredictor.shared.reloadForActiveUser()
            AnalyticsManager.shared.reloadFromDatabase()
            
            self.reloadOpenWindowsForActiveUser()
        }
        
        NotificationCenter.default.post(name: Self.activeProfileDidChangeNotification, object: self)
    }
    
    
    /// Deletes a local user profile (refusing if it is the sole remaining user).
    @discardableResult
    func deleteProfile(id: String) -> Bool {
        
        guard self.profiles.count > 1,
              let target = self.profiles.first(where: { $0.id == id })
        else { return false }
        
        if target.id == self.activeProfile.id,
           let fallback = self.profiles.first(where: { $0.id != id })
        {
            self.switchToProfile(id: fallback.id)
        }
        
        let sql = "DELETE FROM users WHERE id = ?;"
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(self.db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, id, -1, self.transientDestructor)
            sqlite3_step(stmt)
        }
        sqlite3_finalize(stmt)
        
        self.avatarCache.removeValue(forKey: id)
        
        let dbURL = self.databaseURL(for: target)
        if dbURL != self.activeDatabaseURL {
            for suffix in ["", "-wal", "-shm"] {
                let candidate = URL(filePath: dbURL.path + suffix)
                try? FileManager.default.removeItem(at: candidate)
            }
        }
        
        self.reloadProfiles()
        NotificationCenter.default.post(name: Self.activeProfileDidChangeNotification, object: self)
        return true
    }
    
    
    // MARK: Private Helpers
    
    private func reloadOpenWindowsForActiveUser() {
        
        let windowControllers = NSApp.orderedWindows.compactMap { $0.windowController as? DocumentWindowController }
        guard let primaryWC = windowControllers.first else { return }
        
        // Close extra secondary windows cleanly without save prompts (already flushed to outgoing DB).
        for wc in windowControllers.dropFirst() {
            if let docVC = wc.documentViewController {
                for pane in docVC.editorViewControllers {
                    for tab in pane.tabs {
                        tab.document.updateChangeCount(.changeCleared)
                        tab.document.hasUncommittedChanges = false
                    }
                }
            }
            (wc.document as? NSDocument)?.updateChangeCount(.changeCleared)
            wc.close()
        }
        
        primaryWC.workspaceContentViewController?.hideInWindowCenter()
        primaryWC.documentViewController?.reloadWorkspaceForActiveUser()
    }
    
    
    private func openDatabase() {
        
        if sqlite3_open(self.accountsDatabaseURL.path, &self.db) != SQLITE_OK {
            self.db = nil
        }
    }
    
    
    private func createTablesIfNeeded() {
        
        let sql = """
        CREATE TABLE IF NOT EXISTS users (
            id TEXT PRIMARY KEY,
            display_name TEXT NOT NULL,
            avatar_data BLOB,
            avatar_color_hex TEXT NOT NULL DEFAULT '#0A84FF',
            db_filename TEXT NOT NULL,
            account_kind TEXT NOT NULL DEFAULT 'local',
            email TEXT,
            remote_user_id TEXT,
            created_at REAL NOT NULL,
            last_active_at REAL NOT NULL
        );
        CREATE TABLE IF NOT EXISTS account_state (
            key TEXT PRIMARY KEY,
            value TEXT NOT NULL
        );
        """
        sqlite3_exec(self.db, sql, nil, nil, nil)
    }
    
    
    private func seedDefaultProfileIfNeeded() {
        
        var count = 0
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(self.db, "SELECT COUNT(*) FROM users;", -1, &stmt, nil) == SQLITE_OK {
            if sqlite3_step(stmt) == SQLITE_ROW {
                count = Int(sqlite3_column_int(stmt, 0))
            }
        }
        sqlite3_finalize(stmt)
        guard count == 0 else { return }
        
        let existingAuthor = self.readLegacyAuthorNameFromDefaultDB()
        let systemName = NSFullUserName().trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedName: String = if let existingAuthor, !existingAuthor.isEmpty {
            existingAuthor
        } else if !systemName.isEmpty {
            systemName
        } else {
            "默认用户"
        }
        
        let now = Date()
        let defaultProfile = UserProfile(
            id: "default",
            displayName: resolvedName,
            avatarData: nil,
            avatarColorHex: "#0A84FF",
            dbFilename: "cot_user_data.sqlite3",
            accountKind: "local",
            email: nil,
            remoteUserID: nil,
            createdAt: now,
            lastActiveAt: now
        )
        self.upsertUserRow(defaultProfile)
        self.setAccountState(defaultProfile.id, forKey: "active_user_id")
    }
    
    
    private func readLegacyAuthorNameFromDefaultDB() -> String? {
        
        let defaultDBURL = self.rootDirectory.appending(path: "cot_user_data.sqlite3")
        guard FileManager.default.fileExists(atPath: defaultDBURL.path) else { return nil }
        
        var legacyDB: OpaquePointer?
        guard sqlite3_open_v2(defaultDBURL.path, &legacyDB, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            sqlite3_close(legacyDB)
            return nil
        }
        defer { sqlite3_close(legacyDB) }
        
        var stmt: OpaquePointer?
        var author: String?
        if sqlite3_prepare_v2(legacyDB, "SELECT value FROM configs WHERE key = 'weeklyReport.authorName' LIMIT 1;", -1, &stmt, nil) == SQLITE_OK {
            if sqlite3_step(stmt) == SQLITE_ROW, let cStr = sqlite3_column_text(stmt, 0) {
                author = String(cString: cStr).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        sqlite3_finalize(stmt)
        return author
    }
    
    
    private func upsertUserRow(_ profile: UserProfile) {
        
        let sql = """
        INSERT INTO users (id, display_name, avatar_data, avatar_color_hex, db_filename, account_kind, email, remote_user_id, created_at, last_active_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET
            display_name = excluded.display_name,
            avatar_data = excluded.avatar_data,
            avatar_color_hex = excluded.avatar_color_hex,
            db_filename = excluded.db_filename,
            account_kind = excluded.account_kind,
            email = excluded.email,
            remote_user_id = excluded.remote_user_id,
            last_active_at = excluded.last_active_at;
        """
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(self.db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, profile.id, -1, self.transientDestructor)
            sqlite3_bind_text(stmt, 2, profile.displayName, -1, self.transientDestructor)
            if let data = profile.avatarData, !data.isEmpty {
                _ = data.withUnsafeBytes { rawBuffer in
                    sqlite3_bind_blob(stmt, 3, rawBuffer.baseAddress, Int32(data.count), self.transientDestructor)
                }
            } else {
                sqlite3_bind_null(stmt, 3)
            }
            sqlite3_bind_text(stmt, 4, profile.avatarColorHex, -1, self.transientDestructor)
            sqlite3_bind_text(stmt, 5, profile.dbFilename, -1, self.transientDestructor)
            sqlite3_bind_text(stmt, 6, profile.accountKind, -1, self.transientDestructor)
            if let email = profile.email {
                sqlite3_bind_text(stmt, 7, email, -1, self.transientDestructor)
            } else {
                sqlite3_bind_null(stmt, 7)
            }
            if let remoteID = profile.remoteUserID {
                sqlite3_bind_text(stmt, 8, remoteID, -1, self.transientDestructor)
            } else {
                sqlite3_bind_null(stmt, 8)
            }
            sqlite3_bind_double(stmt, 9, profile.createdAt.timeIntervalSince1970)
            sqlite3_bind_double(stmt, 10, profile.lastActiveAt.timeIntervalSince1970)
            sqlite3_step(stmt)
        }
        sqlite3_finalize(stmt)
    }
    
    
    private func setAccountState(_ value: String, forKey key: String) {
        
        let sql = """
        INSERT INTO account_state (key, value)
        VALUES (?, ?)
        ON CONFLICT(key) DO UPDATE SET value = excluded.value;
        """
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(self.db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, key, -1, self.transientDestructor)
            sqlite3_bind_text(stmt, 2, value, -1, self.transientDestructor)
            sqlite3_step(stmt)
        }
        sqlite3_finalize(stmt)
    }
    
    
    private func accountState(forKey key: String) -> String? {
        
        let sql = "SELECT value FROM account_state WHERE key = ? LIMIT 1;"
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
    
    
    private func reloadProfiles() {
        
        let sql = """
        SELECT id, display_name, avatar_data, avatar_color_hex, db_filename, account_kind, email, remote_user_id, created_at, last_active_at
        FROM users
        ORDER BY created_at ASC;
        """
        var stmt: OpaquePointer?
        var loaded: [UserProfile] = []
        
        if sqlite3_prepare_v2(self.db, sql, -1, &stmt, nil) == SQLITE_OK {
            while sqlite3_step(stmt) == SQLITE_ROW {
                guard
                    let idCStr = sqlite3_column_text(stmt, 0),
                    let nameCStr = sqlite3_column_text(stmt, 1),
                    let colorCStr = sqlite3_column_text(stmt, 3),
                    let fileCStr = sqlite3_column_text(stmt, 4),
                    let kindCStr = sqlite3_column_text(stmt, 5)
                else { continue }
                
                var avatarData: Data?
                if let blob = sqlite3_column_blob(stmt, 2) {
                    let byteCount = Int(sqlite3_column_bytes(stmt, 2))
                    if byteCount > 0 {
                        avatarData = Data(bytes: blob, count: byteCount)
                    }
                }
                
                let email = sqlite3_column_text(stmt, 6).map { String(cString: $0) }
                let remoteID = sqlite3_column_text(stmt, 7).map { String(cString: $0) }
                let createdAt = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 8))
                let lastActiveAt = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 9))
                
                loaded.append(UserProfile(
                    id: String(cString: idCStr),
                    displayName: String(cString: nameCStr),
                    avatarData: avatarData,
                    avatarColorHex: String(cString: colorCStr),
                    dbFilename: String(cString: fileCStr),
                    accountKind: String(cString: kindCStr),
                    email: email,
                    remoteUserID: remoteID,
                    createdAt: createdAt,
                    lastActiveAt: lastActiveAt
                ))
            }
        }
        sqlite3_finalize(stmt)
        
        self.profiles = loaded
        let activeID = self.accountState(forKey: "active_user_id")
        if let activeID, let matched = loaded.first(where: { $0.id == activeID }) {
            self.activeProfile = matched
        } else if let first = loaded.first {
            self.activeProfile = first
            self.setAccountState(first.id, forKey: "active_user_id")
        }
    }
}
