//
//  MigrationArchiveService.swift
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

import AppleArchive
import CoreGraphics
import CryptoKit
import Defaults
import Foundation
import ImageIO
import SQLite3
import System
import UniformTypeIdentifiers

// MARK: - Archive Models & Errors

nonisolated struct MigrationArchiveManifestFile: Codable, Equatable, Sendable {
    
    let relativePath: String
    let sha256: String
    let bytes: Int64
}


nonisolated struct MigrationArchiveStats: Codable, Equatable, Sendable {
    
    let originalSQLiteBytes: Int64
    let slimmedSQLiteBytes: Int64
    let recompressedBlobCount: Int
    let reclaimedBlobBytes: Int64
    let sidecarCount: Int
}


nonisolated struct MigrationArchiveManifest: Codable, Equatable, Sendable {
    
    static let currentFormatVersion = 1
    
    let formatVersion: Int
    let appVersion: String
    let createdAt: Date
    let files: [MigrationArchiveManifestFile]
    let stats: MigrationArchiveStats
}


nonisolated struct MigrationArchiveExportResult: Equatable, Sendable {
    
    let archiveURL: URL
    let archiveBytes: Int64
    let stats: MigrationArchiveStats
}


nonisolated struct MigrationArchiveImportResult: Equatable, Sendable {
    
    let sourceURL: URL
    let wasLegacySQLite: Bool
    let rollbackSnapshotURL: URL
    let restoredSidecarCount: Int
}


nonisolated struct MigrationArchiveSidecarRoots: Sendable {
    
    let keyBindings: URL
    let themes: URL
    let syntaxes: URL
    let replacements: URL
    
    static func liveRoots() -> MigrationArchiveSidecarRoots {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let base = appSupport.appending(path: "CotEditor", directoryHint: .isDirectory)
        return MigrationArchiveSidecarRoots(
            keyBindings: base.appending(path: "KeyBindings", directoryHint: .isDirectory),
            themes: base.appending(path: "Themes", directoryHint: .isDirectory),
            syntaxes: base.appending(path: "Syntaxes", directoryHint: .isDirectory),
            replacements: base.appending(path: "Replacements", directoryHint: .isDirectory)
        )
    }
    
    var namedDirectories: [(name: String, url: URL)] {
        [
            ("KeyBindings", self.keyBindings),
            ("Themes", self.themes),
            ("Syntaxes", self.syntaxes),
            ("Replacements", self.replacements),
        ]
    }
}


nonisolated enum MigrationArchiveError: LocalizedError, Sendable {
    
    case unreadableSource
    case invalidManifest
    case unsupportedFormatVersion(Int)
    case missingDatabasePayload
    case checksumMismatch(String)
    case archiveFailed(String)
    case restoreFailed(String)
    
    var errorDescription: String? {
        switch self {
            case .unreadableSource:
                AppLanguage.text("无法读取迁移文件", en: "Unreadable migration file")
            case .invalidManifest:
                AppLanguage.text("迁移包清单损坏或缺失", en: "Invalid or missing migration manifest")
            case .unsupportedFormatVersion(let v):
                AppLanguage.text("不支持的迁移包版本 (\(v))", en: "Unsupported archive version (\(v))")
            case .missingDatabasePayload:
                AppLanguage.text("迁移包缺少核心数据库", en: "Archive is missing database payload")
            case .checksumMismatch(let path):
                AppLanguage.text("文件校验失败：\(path)", en: "Checksum mismatch: \(path)")
            case .archiveFailed(let reason):
                AppLanguage.text("打包失败：\(reason)", en: "Archive failed: \(reason)")
            case .restoreFailed(let reason):
                AppLanguage.text("恢复失败，已回滚原数据：\(reason)", en: "Restore failed and rolled back: \(reason)")
        }
    }
}


// MARK: - Pure Nonisolated Archive Engine

enum MigrationArchiveService {
    
    nonisolated static let archiveExtension = "cotbackup"
    nonisolated static let databaseEntryName = "cot_user_data.sqlite3"
    nonisolated static let manifestEntryName = "manifest.json"
    
    private nonisolated static let cacheConfigKeys: [String] = [
        CotLocalDatabase.ConfigKey.aiHotNewsCacheJSON,
        CotLocalDatabase.ConfigKey.aiActionPredictionsJSON,
        CotLocalDatabase.ConfigKey.aiDoneTodayCommentaryJSON,
        CotLocalDatabase.ConfigKey.proactiveDailyTipsStateJSON,
    ]
    
    private nonisolated static let cacheTables: [String] = [
        "agent_command_queue",
        "workspace_live_state",
    ]
    
    private nonisolated static let standardRecompressMinBytes = 32 * 1024
    private nonisolated static let gifRecompressMinBytes = 160 * 1024
    private nonisolated static let tightBudgetThresholdBytes: Int64 = 44 * 1024 * 1024
    
    nonisolated enum CompressionPass: Sendable {
        case standard
        case tightBudget
    }
    
    
    // MARK: Public Async Entrypoints
    
    @MainActor
    static func exportArchive(
        from database: CotLocalDatabase,
        to destinationURL: URL,
        sidecarRoots: MigrationArchiveSidecarRoots? = nil
    ) async throws -> MigrationArchiveExportResult {
        let resolvedRoots = sidecarRoots ?? MigrationArchiveSidecarRoots.liveRoots()
        let tempRoot = FileManager.default.temporaryDirectory
            .appending(path: "cot_export_\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        
        let stagingDir = tempRoot.appending(path: "staging", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: stagingDir, withIntermediateDirectories: true)
        let snapshotDBURL = stagingDir.appending(path: Self.databaseEntryName)
        
        if database === CotLocalDatabase.shared {
            AnalyticsManager.shared.flushPendingStats()
            database.syncAIEndpointsToDatabase()
            database.syncUserProfileToDatabase()
            database.syncAllLocalMediaBlobsToDatabase()
        }
        database.syncUserPreferencesToDatabase()
        try database.vacuumSnapshot(to: snapshotDBURL)
        
        let appVersion = Bundle.main.shortVersion
        let archiveTempURL = tempRoot.appending(path: "archive.\(Self.archiveExtension)")
        
        return try await Task.detached(priority: .userInitiated) {
            defer { try? FileManager.default.removeItem(at: tempRoot) }
            
            let originalBytes = Self.fileSize(at: snapshotDBURL)
            let recompressOutcome = try Self.slimAndOptimizeSQLiteCopy(at: snapshotDBURL)
            let slimmedBytes = Self.fileSize(at: snapshotDBURL)
            
            let sidecarCount = try Self.stageSidecarDirectories(from: resolvedRoots, into: stagingDir)
            let manifestFiles = try Self.collectManifestFiles(in: stagingDir)
            let stats = MigrationArchiveStats(
                originalSQLiteBytes: originalBytes,
                slimmedSQLiteBytes: slimmedBytes,
                recompressedBlobCount: recompressOutcome.count,
                reclaimedBlobBytes: recompressOutcome.reclaimedBytes,
                sidecarCount: sidecarCount
            )
            let manifest = MigrationArchiveManifest(
                formatVersion: MigrationArchiveManifest.currentFormatVersion,
                appVersion: appVersion,
                createdAt: Date(),
                files: manifestFiles,
                stats: stats
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let manifestData = try encoder.encode(manifest)
            try manifestData.write(to: stagingDir.appending(path: Self.manifestEntryName), options: .atomic)
            
            try Self.compressDirectory(stagingDir, to: archiveTempURL)
            
            let fm = FileManager.default
            try fm.createDirectory(at: destinationURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let destPath = destinationURL.path(percentEncoded: false)
            if fm.fileExists(atPath: destPath) {
                _ = try? fm.replaceItemAt(destinationURL, withItemAt: archiveTempURL)
            }
            if fm.fileExists(atPath: archiveTempURL.path(percentEncoded: false)) {
                if fm.fileExists(atPath: destPath) {
                    try fm.removeItem(at: destinationURL)
                }
                try fm.moveItem(at: archiveTempURL, to: destinationURL)
            }
            
            let archiveBytes = Self.fileSize(at: destinationURL)
            return MigrationArchiveExportResult(
                archiveURL: destinationURL,
                archiveBytes: archiveBytes,
                stats: stats
            )
        }.value
    }
    
    
    @MainActor
    static func importArchive(
        from sourceURL: URL,
        into database: CotLocalDatabase,
        sidecarRoots: MigrationArchiveSidecarRoots? = nil,
        backupDirectory: URL? = nil
    ) async throws -> MigrationArchiveImportResult {
        let resolvedRoots = sidecarRoots ?? MigrationArchiveSidecarRoots.liveRoots()
        let resolvedBackupDir = backupDirectory ?? Self.defaultRollbackDirectory(for: database)
        let isLegacySQLite = try await Task.detached(priority: .userInitiated) {
            try Self.hasSQLiteHeader(at: sourceURL)
        }.value
        
        let rollbackURL = Self.makeRollbackURL(in: resolvedBackupDir)
        try FileManager.default.createDirectory(at: rollbackURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try database.vacuumSnapshot(to: rollbackURL)
        
        if isLegacySQLite {
            do {
                try database.importDatabase(from: sourceURL, resetEndpointsIfMissing: database === CotLocalDatabase.shared)
                if database === CotLocalDatabase.shared {
                    await Self.invalidateSharedSettingManagers()
                }
                return MigrationArchiveImportResult(
                    sourceURL: sourceURL,
                    wasLegacySQLite: true,
                    rollbackSnapshotURL: rollbackURL,
                    restoredSidecarCount: 0
                )
            } catch {
                try? database.importDatabase(from: rollbackURL, resetEndpointsIfMissing: database === CotLocalDatabase.shared)
                throw MigrationArchiveError.restoreFailed(error.localizedDescription)
            }
        }
        
        let tempRoot = FileManager.default.temporaryDirectory
            .appending(path: "cot_import_\(UUID().uuidString)", directoryHint: .isDirectory)
        let extractDir = tempRoot.appending(path: "extracted", directoryHint: .isDirectory)
        let sidecarBackupDir = tempRoot.appending(path: "sidecar_backup", directoryHint: .isDirectory)
        
        do {
            let (extractedDBURL, _) = try await Task.detached(priority: .userInitiated) {
                try FileManager.default.createDirectory(at: extractDir, withIntermediateDirectories: true)
                try Self.extractArchive(sourceURL, to: extractDir)
                let manifest = try Self.validateExtractedArchive(in: extractDir)
                let dbURL = extractDir.appending(path: Self.databaseEntryName)
                guard FileManager.default.fileExists(atPath: dbURL.path(percentEncoded: false)) else {
                    throw MigrationArchiveError.missingDatabasePayload
                }
                return (dbURL, manifest)
            }.value
            
            defer { try? FileManager.default.removeItem(at: tempRoot) }
            
            try Self.backupSidecars(from: resolvedRoots, to: sidecarBackupDir)
            
            do {
                try database.importDatabase(from: extractedDBURL, resetEndpointsIfMissing: true)
                let sidecarSourceRoot = extractDir.appending(path: "sidecars", directoryHint: .isDirectory)
                let restoredCount = try Self.restoreSidecars(from: sidecarSourceRoot, to: resolvedRoots)
                
                if database === CotLocalDatabase.shared {
                    try Self.reloadLiveSidecarManagers(keyBindingsRoot: resolvedRoots.keyBindings)
                    await Self.invalidateSharedSettingManagers()
                    StudioPaletteManager.shared.reloadFromDatabase()
                    ThemeManager.shared.validateOrRepairActiveThemePreference()
                }
                
                return MigrationArchiveImportResult(
                    sourceURL: sourceURL,
                    wasLegacySQLite: false,
                    rollbackSnapshotURL: rollbackURL,
                    restoredSidecarCount: restoredCount
                )
            } catch {
                try? Self.restoreSidecars(from: sidecarBackupDir, to: resolvedRoots)
                try? database.importDatabase(from: rollbackURL, resetEndpointsIfMissing: database === CotLocalDatabase.shared)
                if database === CotLocalDatabase.shared {
                    try? Self.reloadLiveSidecarManagers(keyBindingsRoot: resolvedRoots.keyBindings)
                    await Self.invalidateSharedSettingManagers()
                }
                throw MigrationArchiveError.restoreFailed(error.localizedDescription)
            }
        } catch let error as MigrationArchiveError {
            try? FileManager.default.removeItem(at: tempRoot)
            throw error
        } catch {
            try? FileManager.default.removeItem(at: tempRoot)
            throw MigrationArchiveError.restoreFailed(error.localizedDescription)
        }
    }
    
    
    /// Resets all local SQLite data, managed media folders, sidecars, API gateways/keys, and portable preferences
    /// after capturing a safety rollback snapshot in `Backups/`.
    @MainActor
    static func resetAllLocalData(
        database: CotLocalDatabase = .shared,
        sidecarRoots: MigrationArchiveSidecarRoots? = nil,
        mediaDirectories: [URL]? = nil,
        backupDirectory: URL? = nil
    ) async throws -> URL {
        let resolvedRoots = sidecarRoots ?? MigrationArchiveSidecarRoots.liveRoots()
        let resolvedBackupDir = backupDirectory ?? Self.defaultRollbackDirectory(for: database)
        let rollbackURL = Self.makeRollbackURL(in: resolvedBackupDir)
        try FileManager.default.createDirectory(at: rollbackURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try database.vacuumSnapshot(to: rollbackURL)
        
        try database.resetToEmptyDatabase()
        
        let fm = FileManager.default
        for (_, dirURL) in resolvedRoots.namedDirectories {
            if fm.fileExists(atPath: dirURL.path(percentEncoded: false)) {
                try? fm.removeItem(at: dirURL)
            }
        }
        
        let managedMediaDirs = mediaDirectories ?? Self.liveManagedMediaDirectories()
        for dirURL in managedMediaDirs {
            if fm.fileExists(atPath: dirURL.path(percentEncoded: false)) {
                try? fm.removeItem(at: dirURL)
            }
        }
        
        if database === CotLocalDatabase.shared {
            AIEndpointStore.profiles = []
            AIEndpointStore.activeID = nil
            AIKeychain.clearAllAPIKeys()
            
            let defaults = UserDefaults.standard
            for key in DefaultSettings.portableKeys {
                defaults.removeObject(forKey: key.rawValue)
            }
            for extraKey in [
                DefaultKeys.vimMode.rawValue,
                DefaultKeys.usesCustomCursorColor.rawValue,
                DefaultKeys.customCursorColorHex.rawValue,
                DefaultKeys.aiActiveProfileID.rawValue,
                DefaultKeys.aiProfiles.rawValue,
                DefaultKeys.showStatusBar.rawValue,
                DefaultKeys.showNavigationBar.rawValue,
                DefaultKeys.splitViewVertical.rawValue,
            ] {
                defaults.removeObject(forKey: extraKey)
            }
            
            UserProfileManager.shared.resetActiveProfileToDefault()
            try? KeyBindingManager.shared.restoreDefaults()
            await Self.invalidateSharedSettingManagers()
            database.reloadAllSharedStoresAfterMigration()
            NotificationCenter.default.post(name: CotLocalDatabase.structuredAssetsDidChangeNotification, object: database)
            NotificationCenter.default.post(name: UserProfileManager.activeProfileDidChangeNotification, object: UserProfileManager.shared)
        }
        
        return rollbackURL
    }
    
    
    private nonisolated static func liveManagedMediaDirectories() -> [URL] {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let cotEditorBase = appSupport.appending(path: "CotEditor", directoryHint: .isDirectory)
        let cotBase = appSupport.appending(path: "Cot", directoryHint: .isDirectory)
        return [
            cotEditorBase.appending(path: "MediaLibrary", directoryHint: .isDirectory),
            cotEditorBase.appending(path: "Wallpapers", directoryHint: .isDirectory),
            cotBase.appending(path: "CustomAppIcon", directoryHint: .isDirectory),
            cotBase.appending(path: "InlineImages", directoryHint: .isDirectory),
        ]
    }
    
    
    // MARK: Nonisolated SQLite Optimization & Media Recompression
    
    nonisolated static func slimAndOptimizeSQLiteCopy(at sqliteURL: URL) throws -> (count: Int, reclaimedBytes: Int64) {
        var db: OpaquePointer?
        guard sqlite3_open_v2(sqliteURL.path(percentEncoded: false), &db, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK,
              let db
        else {
            sqlite3_close(db)
            throw MigrationArchiveError.archiveFailed("Unable to open staged SQLite copy")
        }
        defer { sqlite3_close(db) }
        
        // 1. Clear regenerable ephemeral tables and cache-only config keys
        for table in Self.cacheTables {
            _ = sqlite3_exec(db, "DELETE FROM \(table);", nil, nil, nil)
        }
        for key in Self.cacheConfigKeys {
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, "DELETE FROM configs WHERE key = ?;", -1, &stmt, nil) == SQLITE_OK {
                key.withCString { cStr in
                    sqlite3_bind_text(stmt, 1, cStr, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
                }
                sqlite3_step(stmt)
            }
            sqlite3_finalize(stmt)
        }
        
        // 2. Pass 1: recompress all media_blobs and oversized base64 images in configs
        var outcome = Self.recompressMediaBlobs(in: db, pass: .standard)
        let configOutcome = Self.recompressOversizedConfigImages(in: db)
        outcome.count += configOutcome.count
        outcome.reclaimedBytes += configOutcome.reclaimedBytes
        _ = sqlite3_exec(db, "VACUUM;", nil, nil, nil)
        
        // 3. Adaptive Pass 2 when still above 44 MB threshold to keep .cotbackup under 50 MB
        if Self.fileSize(at: sqliteURL) > Self.tightBudgetThresholdBytes {
            let pass2 = Self.recompressMediaBlobs(in: db, pass: .tightBudget)
            outcome.count += pass2.count
            outcome.reclaimedBytes += pass2.reclaimedBytes
            _ = sqlite3_exec(db, "VACUUM;", nil, nil, nil)
        }
        return outcome
    }
    
    
    private nonisolated static func recompressMediaBlobs(in db: OpaquePointer, pass: CompressionPass) -> (count: Int, reclaimedBytes: Int64) {
        struct BlobCandidate {
            let key: String
            let namespace: String
            let data: Data
        }
        
        let minBytes = (pass == .standard) ? Self.standardRecompressMinBytes : (48 * 1024)
        var candidates: [BlobCandidate] = []
        let selectSQL = "SELECT blob_key, namespace, data FROM media_blobs WHERE bytes > ?;"
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, selectSQL, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_int(stmt, 1, Int32(minBytes))
            while sqlite3_step(stmt) == SQLITE_ROW {
                guard let keyCStr = sqlite3_column_text(stmt, 0),
                      let nsCStr = sqlite3_column_text(stmt, 1),
                      let rawPtr = sqlite3_column_blob(stmt, 2)
                else { continue }
                let len = Int(sqlite3_column_bytes(stmt, 2))
                guard len > minBytes else { continue }
                candidates.append(BlobCandidate(
                    key: String(cString: keyCStr),
                    namespace: String(cString: nsCStr),
                    data: Data(bytes: rawPtr, count: len)
                ))
            }
        }
        sqlite3_finalize(stmt)
        
        var count = 0
        var reclaimedBytes: Int64 = 0
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        let updateSQL = "UPDATE media_blobs SET sha256 = ?, bytes = ?, data = ? WHERE blob_key = ?;"
        
        _ = sqlite3_exec(db, "BEGIN IMMEDIATE TRANSACTION;", nil, nil, nil)
        for item in candidates {
            guard let optimized = Self.optimizeBlobData(item.data, namespace: item.namespace, pass: pass),
                  optimized.count < item.data.count
            else { continue }
            
            let newSHA = Self.sha256Hex(optimized)
            var uStmt: OpaquePointer?
            if sqlite3_prepare_v2(db, updateSQL, -1, &uStmt, nil) == SQLITE_OK {
                sqlite3_bind_text(uStmt, 1, newSHA, -1, transient)
                sqlite3_bind_int(uStmt, 2, Int32(optimized.count))
                optimized.withUnsafeBytes { rawBuf in
                    _ = sqlite3_bind_blob(uStmt, 3, rawBuf.baseAddress, Int32(optimized.count), transient)
                }
                sqlite3_bind_text(uStmt, 4, item.key, -1, transient)
                if sqlite3_step(uStmt) == SQLITE_DONE {
                    count += 1
                    reclaimedBytes += Int64(item.data.count - optimized.count)
                }
            }
            sqlite3_finalize(uStmt)
        }
        _ = sqlite3_exec(db, "COMMIT;", nil, nil, nil)
        return (count, reclaimedBytes)
    }
    
    
    private nonisolated static func optimizeBlobData(_ data: Data, namespace: String, pass: CompressionPass) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let frameCount = CGImageSourceGetCount(source)
        if frameCount > 1 {
            let gifMin = (pass == .standard) ? Self.gifRecompressMinBytes : (96 * 1024)
            guard data.count > gifMin else { return nil }
            let edge: CGFloat = (pass == .standard) ? 280 : 220
            let maxFrames = (pass == .standard) ? 18 : 12
            return Self.recompressAnimatedGIF(source: source, frameCount: frameCount, maxPixelEdge: edge, maxFrames: maxFrames)
        }
        
        switch namespace {
            case MediaBlobNamespace.mediaBackground.rawValue, MediaBlobNamespace.wallpaper.rawValue:
                let edge: CGFloat = (pass == .standard) ? 1600 : 1280
                let q: CGFloat = (pass == .standard) ? 0.66 : 0.52
                return Self.recompressImageData(data, maxPixelEdge: edge, quality: q, forceOpaqueHEICOrJPEG: true)
            case MediaBlobNamespace.mediaAvatar.rawValue:
                let edge: CGFloat = (pass == .standard) ? 512 : 384
                let q: CGFloat = (pass == .standard) ? 0.72 : 0.62
                return Self.recompressImageData(data, maxPixelEdge: edge, quality: q, forceOpaqueHEICOrJPEG: false)
            case MediaBlobNamespace.sticker.rawValue:
                let edge: CGFloat = (pass == .standard) ? 480 : 360
                let q: CGFloat = (pass == .standard) ? 0.72 : 0.60
                return Self.recompressImageData(data, maxPixelEdge: edge, quality: q, forceOpaqueHEICOrJPEG: false, preferUniversalJPEG: true)
            case MediaBlobNamespace.inlineImage.rawValue:
                let edge: CGFloat = (pass == .standard) ? 1600 : 1280
                let q: CGFloat = (pass == .standard) ? 0.74 : 0.62
                return Self.recompressImageData(data, maxPixelEdge: edge, quality: q, forceOpaqueHEICOrJPEG: false, preferUniversalJPEG: true)
            default:
                return nil
        }
    }
    
    
    private nonisolated static func recompressOversizedConfigImages(in db: OpaquePointer) -> (count: Int, reclaimedBytes: Int64) {
        let minB64Bytes = 120 * 1024
        var rows: [(key: String, value: String)] = []
        let sql = """
        SELECT key, value FROM configs
        WHERE length(value) > ?
          AND (key = 'dashboard.heroCoverImageBase64'
               OR key = 'butler.customAvatarBase64'
               OR key = 'sync.userProfileSnapshot'
               OR key LIKE 'ai.bot.%.avatar');
        """
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_int(stmt, 1, Int32(minB64Bytes))
            while sqlite3_step(stmt) == SQLITE_ROW {
                guard let k = sqlite3_column_text(stmt, 0),
                      let v = sqlite3_column_text(stmt, 1) else { continue }
                rows.append((String(cString: k), String(cString: v)))
            }
        }
        sqlite3_finalize(stmt)
        guard !rows.isEmpty else { return (0, 0) }
        
        var count = 0
        var reclaimed: Int64 = 0
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        let updateSQL = "UPDATE configs SET value = ? WHERE key = ?;"
        
        _ = sqlite3_exec(db, "BEGIN IMMEDIATE TRANSACTION;", nil, nil, nil)
        for row in rows {
            let maxEdge: CGFloat = (row.key == "dashboard.heroCoverImageBase64") ? 1600 : 512
            let newValue: String? = if row.key == "sync.userProfileSnapshot" {
                Self.recompressUserProfileSnapshotJSON(row.value, maxPixelEdge: maxEdge)
            } else if let raw = Data(base64Encoded: row.value),
                      let shrunk = Self.recompressImageData(raw, maxPixelEdge: maxEdge, quality: 0.72, forceOpaqueHEICOrJPEG: false, preferUniversalJPEG: true),
                      shrunk.count < raw.count {
                shrunk.base64EncodedString()
            } else {
                nil
            }
            guard let newValue, newValue.utf8.count < row.value.utf8.count else { continue }
            var uStmt: OpaquePointer?
            if sqlite3_prepare_v2(db, updateSQL, -1, &uStmt, nil) == SQLITE_OK {
                sqlite3_bind_text(uStmt, 1, newValue, -1, transient)
                sqlite3_bind_text(uStmt, 2, row.key, -1, transient)
                if sqlite3_step(uStmt) == SQLITE_DONE {
                    count += 1
                    reclaimed += Int64(row.value.utf8.count - newValue.utf8.count)
                }
            }
            sqlite3_finalize(uStmt)
        }
        _ = sqlite3_exec(db, "COMMIT;", nil, nil, nil)
        return (count, reclaimed)
    }
    
    
    private nonisolated static func recompressUserProfileSnapshotJSON(_ json: String, maxPixelEdge: CGFloat) -> String? {
        guard let data = json.data(using: .utf8),
              var dict = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let b64 = dict["avatarDataBase64"] as? String,
              let raw = Data(base64Encoded: b64),
              let shrunk = Self.recompressImageData(raw, maxPixelEdge: maxPixelEdge, quality: 0.72, forceOpaqueHEICOrJPEG: false, preferUniversalJPEG: true),
              shrunk.count < raw.count
        else { return nil }
        dict["avatarDataBase64"] = shrunk.base64EncodedString()
        guard let outData = try? JSONSerialization.data(withJSONObject: dict) else { return nil }
        return String(data: outData, encoding: .utf8)
    }
    
    
    nonisolated static func recompressImageData(
        _ data: Data,
        maxPixelEdge: CGFloat,
        quality: CGFloat = 0.76,
        forceOpaqueHEICOrJPEG: Bool = false,
        preferUniversalJPEG: Bool = false
    ) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) == 1
        else { return nil }
        
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: Int(maxPixelEdge),
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
                ?? CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { return nil }
        
        let isTransparent = !forceOpaqueHEICOrJPEG && Self.hasMeaningfulTransparency(cgImage)
        let outData = NSMutableData()
        if isTransparent {
            guard let dest = CGImageDestinationCreateWithData(outData, UTType.png.identifier as CFString, 1, nil) else {
                return nil
            }
            CGImageDestinationAddImage(dest, cgImage, nil)
            guard CGImageDestinationFinalize(dest) else { return nil }
            return outData.length > 0 ? (outData as Data) : nil
        }
        
        let props: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: quality]
        if !preferUniversalJPEG {
            if let dest = CGImageDestinationCreateWithData(outData, UTType.heic.identifier as CFString, 1, nil) {
                CGImageDestinationAddImage(dest, cgImage, props as CFDictionary)
                if CGImageDestinationFinalize(dest), outData.length > 0 {
                    return outData as Data
                }
            }
            outData.length = 0
        }
        guard let jpegDest = CGImageDestinationCreateWithData(outData, UTType.jpeg.identifier as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(jpegDest, cgImage, props as CFDictionary)
        guard CGImageDestinationFinalize(jpegDest) else { return nil }
        return outData.length > 0 ? (outData as Data) : nil
    }
    
    
    private nonisolated static func recompressAnimatedGIF(
        source: CGImageSource,
        frameCount: Int,
        maxPixelEdge: CGFloat,
        maxFrames: Int
    ) -> Data? {
        let step = max(1, Int(ceil(Double(frameCount) / Double(max(1, maxFrames)))))
        var kept: [(index: Int, delay: Double)] = []
        var accumulatedDelay = 0.0
        
        for i in 0..<frameCount {
            let frameProps = CGImageSourceCopyPropertiesAtIndex(source, i, nil) as? [CFString: Any]
            let gifDict = frameProps?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
            let unclamped = gifDict?[kCGImagePropertyGIFUnclampedDelayTime] as? Double
            let clamped = gifDict?[kCGImagePropertyGIFDelayTime] as? Double
            let delay = max(0.02, unclamped ?? clamped ?? 0.08)
            accumulatedDelay += delay
            if i % step == 0 || i == frameCount - 1 {
                kept.append((i, accumulatedDelay))
                accumulatedDelay = 0.0
            }
        }
        guard !kept.isEmpty else { return nil }
        
        let outData = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(outData, UTType.gif.identifier as CFString, kept.count, nil) else {
            return nil
        }
        let containerProps: [CFString: Any] = [
            kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0],
        ]
        CGImageDestinationSetProperties(dest, containerProps as CFDictionary)
        
        let thumbOpts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: Int(maxPixelEdge),
        ]
        for entry in kept {
            guard let img = CGImageSourceCreateThumbnailAtIndex(source, entry.index, thumbOpts as CFDictionary)
                    ?? CGImageSourceCreateImageAtIndex(source, entry.index, nil)
            else { continue }
            let frameMeta: [CFString: Any] = [
                kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: entry.delay],
            ]
            CGImageDestinationAddImage(dest, img, frameMeta as CFDictionary)
        }
        guard CGImageDestinationFinalize(dest), outData.length > 0 else { return nil }
        return outData as Data
    }
    
    
    private nonisolated static func hasMeaningfulTransparency(_ cgImage: CGImage) -> Bool {
        let alpha = cgImage.alphaInfo
        let hasAlphaChannel = (alpha == .first || alpha == .last || alpha == .premultipliedFirst || alpha == .premultipliedLast)
        guard hasAlphaChannel else { return false }
        
        let sampleSide = 24
        var buf = [UInt8](repeating: 255, count: sampleSide * sampleSide * 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: &buf,
            width: sampleSide,
            height: sampleSide,
            bitsPerComponent: 8,
            bytesPerRow: sampleSide * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return true
        }
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: sampleSide, height: sampleSide))
        for i in stride(from: 3, to: buf.count, by: 4) where buf[i] < 245 {
            return true
        }
        return false
    }
    
    
    // MARK: AppleArchive Packing & Validation
    
    private nonisolated static func compressDirectory(_ directoryURL: URL, to destinationURL: URL) throws {
        guard let writeStream = ArchiveByteStream.fileStream(
            path: FilePath(destinationURL.path(percentEncoded: false)),
            mode: .writeOnly,
            options: [.create, .truncate],
            permissions: FilePermissions(rawValue: 0o644)
        ) else {
            throw MigrationArchiveError.archiveFailed("Failed to open destination stream")
        }
        defer { try? writeStream.close() }
        
        guard let compressStream = ArchiveByteStream.compressionStream(
            using: .lzfse,
            writingTo: writeStream
        ) else {
            throw MigrationArchiveError.archiveFailed("Failed to create LZFSE compression stream")
        }
        defer { try? compressStream.close() }
        
        guard let encodeStream = ArchiveStream.encodeStream(writingTo: compressStream) else {
            throw MigrationArchiveError.archiveFailed("Failed to create archive encode stream")
        }
        defer { try? encodeStream.close() }
        
        guard let keySet = ArchiveHeader.FieldKeySet("TYP,PAT,LNK,DEV,DAT,UID,GID,MOD,FLG,MTM,BTM,CTM") else {
            throw MigrationArchiveError.archiveFailed("Invalid archive key set")
        }
        try encodeStream.writeDirectoryContents(archiveFrom: FilePath(directoryURL.path(percentEncoded: false)), keySet: keySet)
        try encodeStream.close()
        try compressStream.close()
        try writeStream.close()
    }
    
    
    private nonisolated static func extractArchive(_ archiveURL: URL, to destinationDir: URL) throws {
        guard let readStream = ArchiveByteStream.fileStream(
            path: FilePath(archiveURL.path(percentEncoded: false)),
            mode: .readOnly,
            options: [],
            permissions: FilePermissions(rawValue: 0o644)
        ) else {
            throw MigrationArchiveError.unreadableSource
        }
        defer { try? readStream.close() }
        
        guard let decompressStream = ArchiveByteStream.decompressionStream(readingFrom: readStream) else {
            throw MigrationArchiveError.unreadableSource
        }
        defer { try? decompressStream.close() }
        
        guard let decodeStream = ArchiveStream.decodeStream(readingFrom: decompressStream) else {
            throw MigrationArchiveError.unreadableSource
        }
        defer { try? decodeStream.close() }
        
        guard let extractStream = ArchiveStream.extractStream(
            extractingTo: FilePath(destinationDir.path(percentEncoded: false)),
            flags: [.ignoreOperationNotPermitted]
        ) else {
            throw MigrationArchiveError.unreadableSource
        }
        defer { try? extractStream.close() }
        
        _ = try ArchiveStream.process(readingFrom: decodeStream, writingTo: extractStream)
    }
    
    
    private nonisolated static func validateExtractedArchive(in extractDir: URL) throws -> MigrationArchiveManifest {
        let manifestURL = extractDir.appending(path: Self.manifestEntryName)
        guard let manifestData = try? Data(contentsOf: manifestURL) else {
            throw MigrationArchiveError.invalidManifest
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let manifest = try? decoder.decode(MigrationArchiveManifest.self, from: manifestData) else {
            throw MigrationArchiveError.invalidManifest
        }
        guard manifest.formatVersion == MigrationArchiveManifest.currentFormatVersion else {
            throw MigrationArchiveError.unsupportedFormatVersion(manifest.formatVersion)
        }
        
        for entry in manifest.files {
            guard let fileURL = MediaBlobPathSanitizer.safeDestinationURL(
                rootDirectory: extractDir,
                relativePath: entry.relativePath
            ),
                  let fileData = try? Data(contentsOf: fileURL)
            else {
                throw MigrationArchiveError.checksumMismatch(entry.relativePath)
            }
            if Self.sha256Hex(fileData) != entry.sha256 {
                throw MigrationArchiveError.checksumMismatch(entry.relativePath)
            }
        }
        return manifest
    }
    
    
    // MARK: Sidecar Helpers
    
    private nonisolated static func stageSidecarDirectories(
        from roots: MigrationArchiveSidecarRoots,
        into stagingDir: URL
    ) throws -> Int {
        let fm = FileManager.default
        let sidecarRoot = stagingDir.appending(path: "sidecars", directoryHint: .isDirectory)
        var copiedFiles = 0
        
        for (name, srcDir) in roots.namedDirectories {
            guard fm.fileExists(atPath: srcDir.path(percentEncoded: false)),
                  let enumerator = fm.enumerator(
                    at: srcDir,
                    includingPropertiesForKeys: [.isRegularFileKey],
                    options: [.skipsHiddenFiles]
                  )
            else { continue }
            
            let stdSrc = srcDir.resolvingSymlinksInPath().standardizedFileURL.path(percentEncoded: false)
            let stdSrcPrefix = stdSrc.hasSuffix("/") ? stdSrc : stdSrc + "/"
            for case let fileURL as URL in enumerator {
                let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey])
                guard values?.isRegularFile == true else { continue }
                let resolvedFilePath = fileURL.resolvingSymlinksInPath().standardizedFileURL.path(percentEncoded: false)
                guard resolvedFilePath.hasPrefix(stdSrcPrefix) else { continue }
                let rel = String(resolvedFilePath.dropFirst(stdSrcPrefix.count))
                guard let destURL = MediaBlobPathSanitizer.safeDestinationURL(
                    rootDirectory: sidecarRoot.appending(path: name, directoryHint: .isDirectory),
                    relativePath: rel
                ) else { continue }
                try fm.createDirectory(at: destURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                try fm.copyItem(at: fileURL, to: destURL)
                copiedFiles += 1
            }
        }
        return copiedFiles
    }
    
    
    private nonisolated static func backupSidecars(
        from roots: MigrationArchiveSidecarRoots,
        to backupDir: URL
    ) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: backupDir, withIntermediateDirectories: true)
        for (name, srcDir) in roots.namedDirectories where fm.fileExists(atPath: srcDir.path(percentEncoded: false)) {
            let dest = backupDir.appending(path: name, directoryHint: .isDirectory)
            if fm.fileExists(atPath: dest.path(percentEncoded: false)) {
                try? fm.removeItem(at: dest)
            }
            try fm.copyItem(at: srcDir, to: dest)
        }
    }
    
    
    @discardableResult
    private nonisolated static func restoreSidecars(
        from sourceRoot: URL,
        to roots: MigrationArchiveSidecarRoots
    ) throws -> Int {
        let fm = FileManager.default
        var restoredFiles = 0
        
        for (name, targetDir) in roots.namedDirectories {
            let archivedDir = sourceRoot.appending(path: name, directoryHint: .isDirectory)
            if fm.fileExists(atPath: targetDir.path(percentEncoded: false)) {
                try fm.removeItem(at: targetDir)
            }
            guard fm.fileExists(atPath: archivedDir.path(percentEncoded: false)) else { continue }
            try fm.createDirectory(at: targetDir.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fm.copyItem(at: archivedDir, to: targetDir)
            if let enumerator = fm.enumerator(at: targetDir, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) {
                for case let item as URL in enumerator {
                    if (try? item.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true {
                        restoredFiles += 1
                    }
                }
            }
        }
        return restoredFiles
    }
    
    
    @MainActor
    private static func reloadLiveSidecarManagers(keyBindingsRoot: URL) throws {
        let shortcutsURL = keyBindingsRoot.appendingPathComponent("Shortcuts", conformingTo: .propertyList)
        if FileManager.default.fileExists(atPath: shortcutsURL.path(percentEncoded: false)) {
            let data = try Data(contentsOf: shortcutsURL)
            try KeyBindingManager.shared.importSetting(data: data)
        } else {
            try KeyBindingManager.shared.restoreDefaults()
        }
    }
    
    
    @MainActor
    private static func invalidateSharedSettingManagers() async {
        await ThemeManager.shared.invalidateUserSettings()
        await SyntaxManager.shared.invalidateUserSettings()
        await ReplacementManager.shared.invalidateUserSettings()
    }
    
    
    // MARK: Manifest & File Utilities
    
    private nonisolated static func collectManifestFiles(in rootDir: URL) throws -> [MigrationArchiveManifestFile] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: rootDir,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        
        let stdRoot = rootDir.resolvingSymlinksInPath().standardizedFileURL.path(percentEncoded: false)
        let stdRootPrefix = stdRoot.hasSuffix("/") ? stdRoot : stdRoot + "/"
        var entries: [MigrationArchiveManifestFile] = []
        for case let fileURL as URL in enumerator {
            guard (try? fileURL.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true else { continue }
            let resolvedPath = fileURL.resolvingSymlinksInPath().standardizedFileURL.path(percentEncoded: false)
            guard resolvedPath.hasPrefix(stdRootPrefix) else { continue }
            let rel = String(resolvedPath.dropFirst(stdRootPrefix.count))
            guard rel != Self.manifestEntryName else { continue }
            let data = try Data(contentsOf: fileURL)
            entries.append(MigrationArchiveManifestFile(
                relativePath: rel,
                sha256: Self.sha256Hex(data),
                bytes: Int64(data.count)
            ))
        }
        return entries.sorted { $0.relativePath < $1.relativePath }
    }
    
    
    private nonisolated static func hasSQLiteHeader(at url: URL) throws -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            throw MigrationArchiveError.unreadableSource
        }
        defer { try? handle.close() }
        let header = (try? handle.read(upToCount: 16)) ?? Data()
        return header == Data("SQLite format 3\0".utf8)
    }
    
    
    private nonisolated static func defaultRollbackDirectory(for database: CotLocalDatabase) -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return appSupport
            .appending(path: "CotEditor", directoryHint: .isDirectory)
            .appending(path: "Backups", directoryHint: .isDirectory)
    }
    
    
    private nonisolated static func makeRollbackURL(in directory: URL) -> URL {
        let stamp = Int(Date().timeIntervalSince1970)
        return directory.appending(path: "pre-import-\(stamp)-\(UUID().uuidString.prefix(6)).sqlite3")
    }
    
    
    private nonisolated static func fileSize(at url: URL) -> Int64 {
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path(percentEncoded: false))
        return (attrs?[.size] as? NSNumber)?.int64Value ?? 0
    }
    
    
    nonisolated static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
